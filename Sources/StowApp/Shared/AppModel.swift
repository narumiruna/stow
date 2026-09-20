import Foundation
import Observation
import SwiftData
import StowCore

@MainActor
@Observable
final class AppModel {
    var selection: StowSection = .inbox
    var searchText = ""
    var typeFilter: ItemType?
    var sourceFilter: String?
    var dateFilter: DateAddedFilter = .anytime
    var presentedError: String?
    var isAdding = false
    var syncStatus = CloudSyncMonitor.Status.idle
    var globalShortcutStatus = "Not checked"
    var clipboardMonitoringStatus = "Not checked"
    private(set) var searchIndexRebuildState: SearchIndexRebuildState = .idle
    private(set) var launchReadyMilliseconds: Double?
    var searchResultIDs: Set<UUID>?
    var isSearching = false
    var usesPrivateICloud: Bool { StowEnvironment.currentContainerUsesCloud }
    var isReadyForCapture: Bool { repository != nil }
    var privacyStorageText: String {
        usesPrivateICloud ? "Private • Stored in your iCloud" : "Private • Stored locally"
    }

    @ObservationIgnored private let launchStartedAt = ContinuousClock.now
    private(set) var repository: StowRepository?
    private var actionService: ItemActionService?
    private var spool: CaptureSpool?
    private var metrics: OnDeviceMetricsClient?
    private var searchCoordinator: SearchCoordinator?
    private var searchGeneration = 0
    private var retrievalSearchGeneration = 0
    private let syncMonitor = CloudSyncMonitor()
    @ObservationIgnored private let searchDocumentsOverride: (() throws -> [SearchDocument])?
    @ObservationIgnored private let captureSpoolOverride: CaptureSpool?
    @ObservationIgnored private let loadRepresentationsOverride: ((UUID) throws -> [StowRepresentation])?
    @ObservationIgnored private let runtimePathsOverride: StowRuntimePaths?
    private var runtimePaths: StowRuntimePaths { runtimePathsOverride ?? .current }

    init(
        searchDocuments: (() throws -> [SearchDocument])? = nil,
        searchCoordinator: SearchCoordinator? = nil,
        captureSpool: CaptureSpool? = nil,
        runtimePaths: StowRuntimePaths? = nil,
        loadRepresentations: ((UUID) throws -> [StowRepresentation])? = nil
    ) {
        searchDocumentsOverride = searchDocuments
        self.searchCoordinator = searchCoordinator
        captureSpoolOverride = captureSpool
        runtimePathsOverride = runtimePaths
        loadRepresentationsOverride = loadRepresentations
    }

    func markLaunchReady() {
        guard launchReadyMilliseconds == nil else { return }
        let components = launchStartedAt.duration(to: .now).components
        launchReadyMilliseconds = Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
    }

    func connect(_ context: ModelContext) {
        guard repository == nil else { return }
        syncMonitor.onChange = { [weak self] status in self?.syncStatus = status }
        if !StowEnvironment.currentContainerUsesCloud {
            syncStatus = .paused("This build has no iCloud entitlement; your library remains local.")
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-settings-sync-paused") {
            syncStatus = .paused("A deliberately long synchronization status verifies that recovery guidance wraps completely without hiding the action people need next.")
        }
        #endif
        repository = StowRepository(modelContext: context)
        actionService = repository.map(ItemActionService.init(repository:))
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-seed-panel"), let repository {
            seedPanelFixtures(repository, context: context)
        }
        #endif
        do {
            let sharedURL = runtimePaths.sharedContainer
            spool = try captureSpoolOverride ?? CaptureSpool(rootURL: sharedURL.appendingPathComponent("CaptureSpool", isDirectory: true))
            metrics = try OnDeviceMetricsClient(url: sharedURL.appendingPathComponent("Metrics/v0.1.json"), enabled: UserDefaults.standard.object(forKey: "analyticsEnabled") as? Bool ?? true)
            if searchCoordinator == nil {
                let searchIndex = try SQLiteSearchIndex(url: sharedURL.appendingPathComponent("Search/v1.sqlite"))
                searchCoordinator = SearchCoordinator(index: searchIndex)
            }
        } catch {
            presentedError = error.localizedDescription
        }
        runMaintenance()
    }

    @discardableResult
    func ingestClipboard(
        _ draft: CaptureDraft,
        representations: [StowRepresentationDraft] = []
    ) -> Bool {
        do {
            guard let repository else { throw StowRepositoryError.itemNotFound }
            let outcome = try repository.ingestClipboard(
                draft,
                representations: representations
            )
            presentedError = nil
            try? metrics?.record(.captureSucceeded)
            if case .created(let item) = outcome, item.type == .link {
                Task { await LinkMetadataEnricher().enrich(item: item, repository: repository) }
            }
            return true
        } catch {
            try? metrics?.record(.captureFailed)
            presentedError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func create(_ draft: CaptureDraft) -> Bool {
        do {
            _ = try createForAutomation(draft)
            presentedError = nil
            isAdding = false
            return true
        } catch {
            presentedError = error.localizedDescription
            return false
        }
    }

    func createForAutomation(_ draft: CaptureDraft) throws -> StowItem {
        let started = ContinuousClock.now
        do {
            guard let repository else { throw StowRepositoryError.itemNotFound }
            let item = try repository.create(from: draft)
            try? metrics?.record(.captureSucceeded)
            try? metrics?.recordDuration(.captureDuration, seconds: started.duration(to: .now).secondsValue)
            if item.type == .link {
                Task { await LinkMetadataEnricher().enrich(item: item, repository: repository) }
            }
            return item
        } catch {
            try? metrics?.record(.captureFailed)
            throw error
        }
    }

    @discardableResult
    func createAttachment(
        _ draft: CaptureDraft,
        fileURL: URL,
        representations: [StowRepresentationDraft] = [],
        intent: CaptureIngestionIntent = .createNew
    ) -> Bool {
        do {
            guard let repository else { throw StowRepositoryError.itemNotFound }
            let captureSpool = try spool ?? CaptureSpool(rootURL: runtimePaths.sharedContainer.appendingPathComponent("CaptureSpool", isDirectory: true))
            try captureSpool.stage(
                draft,
                attachmentURL: fileURL,
                representations: representations,
                intent: intent
            )
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
            let result = captureSpool.ingest(captureID: draft.id, into: repository)
            if let failure = result.failures.first { throw NSError(domain: "StowCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: failure]) }
            presentedError = nil
            try? metrics?.record(.captureSucceeded)
            isAdding = false
            return true
        } catch {
            try? metrics?.record(.captureFailed)
            presentedError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func save(_ item: StowItem, title: String, note: String?, text: String?, language: String?) -> Bool {
        if let message = saveForPanel(item, title: title, note: note, text: text, language: language) {
            presentedError = message
            return false
        }
        presentedError = nil
        return true
    }

    func saveForPanel(_ item: StowItem, title: String, note: String?, text: String?, language: String?) -> String? {
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-fail-save") {
                throw NSError(domain: "StowUITesting", code: 1, userInfo: [NSLocalizedDescriptionKey: "The test save could not be completed. Try again."])
            }
            #endif
            guard let repository else { throw StowRepositoryError.itemNotFound }
            try repository.update(item.id, title: title, note: note, textContent: text, language: language)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    @discardableResult
    func togglePin(_ item: StowItem) -> Bool { togglePin([item]) }

    @discardableResult
    func togglePin(_ items: [StowItem]) -> Bool {
        guard let first = items.first else { return false }
        return setPinned(items, pinned: !first.isPinned)
    }

    @discardableResult
    func setPinned(_ items: [StowItem], pinned: Bool) -> Bool {
        guard !items.isEmpty else { return false }
        do {
            guard let repository else { throw StowRepositoryError.itemNotFound }
            try repository.setPinned(items.map(\.id), pinned: pinned)
            presentedError = nil
            return true
        } catch {
            presentedError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func archiveOrRestore(_ item: StowItem) -> Bool { archiveOrRestore([item]) }

    @discardableResult
    func archiveOrRestore(_ items: [StowItem]) -> Bool {
        guard let first = items.first else { return false }
        do {
            guard let repository else { throw StowRepositoryError.itemNotFound }
            if first.status == .archived {
                try repository.restoreFromArchive(items.map(\.id))
            } else {
                try repository.archive(items.map(\.id))
                for _ in items { try? metrics?.record(.itemArchived) }
            }
            presentedError = nil
            return true
        } catch {
            presentedError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func trashOrRestore(_ item: StowItem) -> Bool {
        item.status == .trashed ? restoreFromTrash(ids: [item.id]) : moveToTrash([item])
    }

    @discardableResult
    func moveToTrash(_ items: [StowItem]) -> Bool {
        do {
            guard let repository else { throw StowRepositoryError.itemNotFound }
            try repository.trash(items.map(\.id))
            presentedError = nil
            return true
        } catch {
            presentedError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func restoreFromTrash(ids: [UUID]) -> Bool {
        do {
            guard let repository else { throw StowRepositoryError.itemNotFound }
            try repository.restoreFromTrash(ids)
            presentedError = nil
            return true
        } catch {
            presentedError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func performUse(_ item: StowItem, action: ItemRetrievalAction, metric: MetricCounter, operation: () throws -> Void) -> Bool {
        do {
            guard let actionService else { throw StowRepositoryError.itemNotFound }
            try actionService.perform(itemID: item.id, action: action, operation: operation)
            presentedError = nil
            try? metrics?.record(metric)
            return true
        } catch {
            presentedError = error.localizedDescription
            return false
        }
    }

    func representations(for item: StowItem) -> [StowRepresentation] {
        do {
            guard let repository else { throw StowRepositoryError.itemNotFound }
            if let loadRepresentationsOverride { return try loadRepresentationsOverride(item.id) }
            return try repository.representations(itemID: item.id)
        } catch {
            presentedError = error.localizedDescription
            return []
        }
    }

    func markUsed(_ item: StowItem, metric: MetricCounter = .itemOpened) {
        performUse(item, action: .preview, metric: metric) {}
    }

    func setMetricsEnabled(_ enabled: Bool) {
        metrics?.setEnabled(enabled)
    }

    func rebuildSearchIndex() async {
        guard !searchIndexRebuildState.isInProgress else { return }
        searchIndexRebuildState = .inProgress
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-fail-search-index-rebuild") {
                throw NSError(domain: "StowUITesting", code: 3, userInfo: [NSLocalizedDescriptionKey: "The test replacement index could not be written. Try again."])
            }
            #endif
            let snapshot: SearchSnapshot
            if let searchDocumentsOverride {
                snapshot = SearchSnapshot(documents: try searchDocumentsOverride())
            } else {
                guard let repository else { throw SearchIndexRecoveryError.libraryUnavailable }
                snapshot = SearchSnapshot(items: try repository.allItems())
            }
            guard let searchCoordinator else { throw SearchIndexRecoveryError.indexUnavailable }
            try await searchCoordinator.rebuild(snapshot)
            searchIndexRebuildState = .succeeded(documentCount: snapshot.documents.count)
        } catch {
            searchIndexRebuildState = .failed(error.localizedDescription)
        }
    }

    func dismissSearchIndexRebuildFeedback() {
        guard !searchIndexRebuildState.isInProgress else { return }
        searchIndexRebuildState = .idle
    }

    func updateSearch(items: [StowItem]) async {
        guard let searchCoordinator else { return }
        searchGeneration += 1
        let generation = searchGeneration
        searchResultIDs = nil
        let requestedText = searchText
        let requestedType = typeFilter
        let requestedSource = sourceFilter
        let requestedDate = dateFilter
        let requestedSection = selection
        isSearching = true
        defer { if generation == searchGeneration { isSearching = false } }
        do {
            if !requestedText.isEmpty { try await Task.sleep(for: .milliseconds(120)) }
            guard generation == searchGeneration, !Task.isCancelled else { return }
            let snapshot = SearchSnapshot(items: items)
            let query = SearchQueryFactory.library(
                text: requestedText,
                type: requestedType,
                source: requestedSource,
                date: requestedDate,
                section: requestedSection
            )
            let result = try await searchCoordinator.search(snapshot: snapshot, query: query)
            guard generation == searchGeneration, !Task.isCancelled else { return }
            searchResultIDs = Set(result.ids)
            try? metrics?.recordDuration(.searchDuration, seconds: result.duration.secondsValue)
            if !requestedText.isEmpty, !result.ids.isEmpty { try? metrics?.record(.searchSucceeded) }
        } catch {
            guard generation == searchGeneration, !Task.isCancelled else { return }
            searchResultIDs = nil
            presentedError = "The local search index will be rebuilt. \(error.localizedDescription)"
        }
    }

    func searchForAutomation(items: [StowItem], payload: StowAutomationSearchPayload) async throws -> [UUID] {
        guard let searchCoordinator else { throw SearchIndexRecoveryError.indexUnavailable }
        let result = try await searchCoordinator.search(
            snapshot: SearchSnapshot(items: items),
            query: SearchQueryFactory.automation(payload)
        )
        return result.ids
    }

    func searchForRetrieval(
        items: [StowItem],
        text: String,
        type: ItemType?,
        source: String?,
        date: DateAddedFilter,
        status: ItemStatus?
    ) async -> RetrievalSearchOutcome {
        guard let searchCoordinator else { return .failure("The local search index is unavailable.") }
        retrievalSearchGeneration += 1
        let generation = retrievalSearchGeneration
        do {
            if !text.isEmpty { try await Task.sleep(for: .milliseconds(80)) }
            guard generation == retrievalSearchGeneration, !Task.isCancelled else { return .success([]) }
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-fail-retrieval-search") {
                throw NSError(domain: "StowUITesting", code: 2, userInfo: [NSLocalizedDescriptionKey: "The test search index is unavailable."])
            }
            #endif
            let snapshot = SearchSnapshot(items: items)
            let query = SearchQueryFactory.retrieval(
                text: text,
                type: type,
                source: source,
                date: date,
                status: status
            )
            let result = try await searchCoordinator.search(snapshot: snapshot, query: query)
            guard generation == retrievalSearchGeneration, !Task.isCancelled else { return .success([]) }
            return .success(result.ids)
        } catch {
            guard generation == retrievalSearchGeneration, !Task.isCancelled else { return .success([]) }
            return .failure("The local search index will be rebuilt. \(error.localizedDescription)")
        }
    }

    #if DEBUG
    private func seedPanelFixtures(_ repository: StowRepository, context: ModelContext) {
        do {
            for attachment in try context.fetch(FetchDescriptor<StowAttachment>()) {
                context.delete(attachment)
            }
            for item in try context.fetch(FetchDescriptor<StowItem>()) {
                context.delete(item)
            }
            try context.save()

            let base = Date().addingTimeInterval(-5 * 60)
            _ = try repository.create(from: CaptureDraft(type: .link, title: "Panel Link", urlString: "https://example.com", sourceApp: "Safari"), at: base)
            _ = try repository.create(from: CaptureDraft(type: .text, title: "Panel Text", textContent: "panel text payload", sourceApp: "Notes"), at: base.addingTimeInterval(1))
            _ = try repository.create(from: CaptureDraft(type: .code, title: "Panel Code", textContent: "let panel = true", sourceApp: "Xcode", language: "swift"), at: base.addingTimeInterval(2))
            let image = try repository.create(from: CaptureDraft(type: .image, title: "Panel Image", stagedAttachmentName: "panel.png", attachmentByteCount: 68, contentType: "image/png", fileName: "panel.png", sourceApp: "Photos"), at: base.addingTimeInterval(3))
            let imageData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAIAAABLbSncAAAAmklEQVR4nA3JkRoEIAwA4Hum43E8jod90WAwHIZhT3QwGARBEPQc16//50sX6CTaSCvTJIpKLvT7fMuFclLZWFYuk0rU4lJe8AU+iTfyyjyJo7ILv9ALepJu1JV1kkZVF31hF+wk22gr2ySLai72ol1oJ7WNbeU2qUVtLu1Fv9BP6hv7yn1Sj9pd+otxYZw0No6Vx6QRdbiM3x+pQGtB6VrbMAAAAABJRU5ErkJggg==")!
            try repository.addAttachment(StowAttachment(itemID: image.id, data: imageData, contentType: "image/png", fileName: "panel.png"))
            let file = try repository.create(from: CaptureDraft(type: .file, title: "Panel File", stagedAttachmentName: "panel.txt", attachmentByteCount: 10, contentType: "text/plain", fileName: "panel.txt", sourceApp: "Finder"), at: base.addingTimeInterval(4))
            try repository.addAttachment(StowAttachment(itemID: file.id, data: Data("panel file".utf8), contentType: "text/plain", fileName: "panel.txt"))
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-library-long-content") {
                _ = try repository.create(from: CaptureDraft(
                    type: .text,
                    title: "A deliberately long Library title that must remain understandable at the minimum supported window width",
                    textContent: "Long content verifies wrapping, adaptive filters, complete accessibility values, and a stable detail layout.",
                    sourceApp: "An Extremely Long Source Application Name Used to Verify Adaptive Layout"
                ), at: base.addingTimeInterval(5))
            }
        } catch { presentedError = error.localizedDescription }
    }
    #endif

    func runMaintenance() {
        guard let repository else { return }
        let ingestion = spool?.ingestAll(into: repository)
        do {
            _ = try repository.purgeExpiredTrash()
            _ = try spool?.removeInterruptedStaging()
            let temporaryRoot = runtimePaths.temporaryDirectory
            _ = try AttachmentStore(repository: repository, temporaryDirectory: temporaryRoot.appendingPathComponent("StowOpen", isDirectory: true)).removeTemporaryFiles()
            _ = try AttachmentStore(repository: repository, temporaryDirectory: temporaryRoot.appendingPathComponent("StowTransfers", isDirectory: true)).removeTemporaryFiles()
            _ = try AttachmentStore(repository: repository, temporaryDirectory: temporaryRoot.appendingPathComponent("StowImports", isDirectory: true)).removeTemporaryFiles()
        } catch { presentedError = error.localizedDescription }
        if let ingestion, !ingestion.failures.isEmpty {
            presentedError = "Some shared items could not be imported. They were retained for diagnostics."
        }
        do {
            while try repository.backfillContentFingerprints() > 0 {}
        } catch { presentedError = error.localizedDescription }
        if let links = try? repository.allItems().filter({ $0.type == .link && $0.linkDescription == nil }) {
            for item in links.prefix(10) { Task { await LinkMetadataEnricher().enrich(item: item, repository: repository) } }
        }
    }
}

enum StowSection: String, CaseIterable, Identifiable {
    case inbox = "Inbox"
    case recent = "Recent"
    case pinned = "Pinned"
    case archive = "Archive"
    case trash = "Trash"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .inbox: "tray"
        case .recent: "clock"
        case .pinned: "pin"
        case .archive: "archivebox"
        case .trash: "trash"
        case .settings: "gear"
        }
    }

    func includes(_ item: StowItem) -> Bool {
        switch self {
        case .inbox: item.status == .inbox
        case .recent: item.status != .trashed && item.lastUsedAt != nil
        case .pinned: item.status != .trashed && item.isPinned
        case .archive: item.status == .archived
        case .trash: item.status == .trashed
        case .settings: false
        }
    }

    func sortedItems(_ items: [StowItem]) -> [StowItem] {
        items.sorted { lhs, rhs in
            if self == .recent {
                return (lhs.lastUsedAt ?? .distantPast) > (rhs.lastUsedAt ?? .distantPast)
            }
            return lhs.createdAt > rhs.createdAt
        }
    }
}

private extension Duration {
    var secondsValue: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1_000_000_000_000_000_000
    }
}

enum RetrievalSearchOutcome: Equatable {
    case success([UUID])
    case failure(String)
}

enum SearchIndexRebuildState: Equatable {
    case idle
    case inProgress
    case succeeded(documentCount: Int)
    case failed(String)

    var isInProgress: Bool {
        if case .inProgress = self { true } else { false }
    }
}

private enum SearchIndexRecoveryError: LocalizedError {
    case libraryUnavailable
    case indexUnavailable

    var errorDescription: String? {
        switch self {
        case .libraryUnavailable: "The library is not ready yet. Wait a moment, then try again."
        case .indexUnavailable: "The search index is unavailable. Reopen Stow, then try again."
        }
    }
}

enum DateAddedFilter: String, CaseIterable, Identifiable {
    case anytime = "Any time"
    case today = "Today"
    case week = "Past week"
    case month = "Past month"

    var id: String { rawValue }

    func includes(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch self {
        case .anytime: true
        case .today: calendar.isDate(date, inSameDayAs: now)
        case .week: date >= calendar.date(byAdding: .day, value: -7, to: now)!
        case .month: date >= calendar.date(byAdding: .month, value: -1, to: now)!
        }
    }
}
