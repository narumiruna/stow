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
    private(set) var launchReadyMilliseconds: Double?
    var searchResultIDs: Set<UUID>?
    var isSearching = false
    var usesPrivateICloud: Bool { StowEnvironment.currentContainerUsesCloud }
    var privacyStorageText: String {
        usesPrivateICloud ? "Private • Stored in your iCloud" : "Private • Stored locally"
    }

    @ObservationIgnored private let launchStartedAt = ContinuousClock.now
    private var repository: StowRepository?
    private var actionService: ItemActionService?
    private var spool: CaptureSpool?
    private var metrics: OnDeviceMetricsClient?
    private var searchIndex: SQLiteSearchIndex?
    private var indexedFingerprint = ""
    private var searchGeneration = 0
    private let syncMonitor = CloudSyncMonitor()

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
        repository = StowRepository(modelContext: context)
        actionService = repository.map(ItemActionService.init(repository:))
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-seed-panel"), let repository {
            seedPanelFixtures(repository)
        }
        #endif
        do {
            let sharedURL = StowEnvironment.sharedContainerURL()
            spool = try CaptureSpool(rootURL: sharedURL.appendingPathComponent("CaptureSpool", isDirectory: true))
            metrics = try OnDeviceMetricsClient(url: sharedURL.appendingPathComponent("Metrics/v0.1.json"), enabled: UserDefaults.standard.object(forKey: "analyticsEnabled") as? Bool ?? true)
            searchIndex = try SQLiteSearchIndex(url: sharedURL.appendingPathComponent("Search/v1.sqlite"))
        } catch {
            presentedError = error.localizedDescription
        }
        runMaintenance()
    }

    func create(_ draft: CaptureDraft) {
        let started = ContinuousClock.now
        do {
            let item = try repository?.create(from: draft)
            try? metrics?.record(.captureSucceeded)
            try? metrics?.recordDuration(.captureDuration, seconds: started.duration(to: .now).secondsValue)
            isAdding = false
            if let item, item.type == .link, let repository {
                Task { await LinkMetadataEnricher().enrich(item: item, repository: repository) }
            }
        } catch {
            try? metrics?.record(.captureFailed)
            presentedError = error.localizedDescription
        }
    }

    func createAttachment(_ draft: CaptureDraft, fileURL: URL) {
        do {
            guard let repository else { throw StowRepositoryError.itemNotFound }
            let captureSpool = try spool ?? CaptureSpool(rootURL: StowEnvironment.sharedContainerURL().appendingPathComponent("CaptureSpool", isDirectory: true))
            try captureSpool.stage(draft, attachmentURL: fileURL)
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
            let result = captureSpool.ingestAll(into: repository)
            if let failure = result.failures.first { throw NSError(domain: "StowCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: failure]) }
            try? metrics?.record(.captureSucceeded)
            isAdding = false
        } catch {
            try? metrics?.record(.captureFailed)
            presentedError = error.localizedDescription
        }
    }

    func save(_ item: StowItem, title: String, note: String?, text: String?, language: String?) {
        do {
            try repository?.update(item.id, title: title, note: note, textContent: text, language: language)
        } catch {
            presentedError = error.localizedDescription
        }
    }

    func togglePin(_ item: StowItem) {
        do { try repository?.setPinned(item.id, pinned: !item.isPinned) }
        catch { presentedError = error.localizedDescription }
    }

    func archiveOrRestore(_ item: StowItem) {
        do {
            if item.status == .archived { try repository?.restoreFromArchive(item.id) }
            else { try repository?.archive(item.id); try? metrics?.record(.itemArchived) }
        } catch { presentedError = error.localizedDescription }
    }

    func trashOrRestore(_ item: StowItem) {
        do {
            if item.status == .trashed { try repository?.restoreFromTrash(item.id) }
            else { try repository?.trash(item.id) }
        } catch { presentedError = error.localizedDescription }
    }

    func performUse(_ item: StowItem, action: ItemRetrievalAction, metric: MetricCounter, operation: () throws -> Void) {
        do {
            guard let actionService else { throw StowRepositoryError.itemNotFound }
            try actionService.perform(itemID: item.id, action: action, operation: operation)
            try? metrics?.record(metric)
        } catch { presentedError = error.localizedDescription }
    }

    func markUsed(_ item: StowItem, metric: MetricCounter = .itemOpened) {
        performUse(item, action: .preview, metric: metric) {}
    }

    func setMetricsEnabled(_ enabled: Bool) {
        metrics?.setEnabled(enabled)
    }

    func updateSearch(items: [StowItem]) async {
        guard let searchIndex else { return }
        searchGeneration += 1
        let generation = searchGeneration
        searchResultIDs = nil
        let requestedText = searchText
        let requestedType = typeFilter
        let requestedSource = sourceFilter
        let requestedDate = dateFilter
        let requestedSection = selection
        var versionHasher = Hasher()
        for item in items { versionHasher.combine(item.id); versionHasher.combine(item.updatedAt) }
        let fingerprint = "\(items.count):\(versionHasher.finalize())"
        isSearching = true
        defer { if generation == searchGeneration { isSearching = false } }
        do {
            if !requestedText.isEmpty { try await Task.sleep(for: .milliseconds(120)) }
            guard generation == searchGeneration, !Task.isCancelled else { return }
            if fingerprint != indexedFingerprint {
                try await searchIndex.rebuild(items.map(SearchDocument.init(item:)))
                indexedFingerprint = fingerprint
            }
            let calendar = Calendar.current
            let now = Date()
            let after: Date?
            switch requestedDate {
            case .anytime: after = nil
            case .today: after = calendar.startOfDay(for: now)
            case .week: after = calendar.date(byAdding: .day, value: -7, to: now)
            case .month: after = calendar.date(byAdding: .month, value: -1, to: now)
            }
            let status: ItemStatus?
            switch requestedSection {
            case .inbox: status = .inbox
            case .archive: status = .archived
            case .trash: status = .trashed
            case .recent, .pinned, .settings: status = nil
            }
            let started = ContinuousClock.now
            let query = SearchQuery(text: requestedText, type: requestedType, sourceApp: requestedSource, addedAfter: after, status: status, limit: 10_000)
            let ids = try await searchIndex.search(query)
            guard generation == searchGeneration, !Task.isCancelled else { return }
            searchResultIDs = Set(ids)
            try? metrics?.recordDuration(.searchDuration, seconds: started.duration(to: .now).secondsValue)
            if !requestedText.isEmpty, !ids.isEmpty { try? metrics?.record(.searchSucceeded) }
        } catch {
            guard generation == searchGeneration, !Task.isCancelled else { return }
            searchResultIDs = nil
            presentedError = "The local search index will be rebuilt. \(error.localizedDescription)"
        }
    }

    #if DEBUG
    private func seedPanelFixtures(_ repository: StowRepository) {
        guard (try? repository.allItems().isEmpty) == true else { return }
        do {
            let base = Date(timeIntervalSince1970: 1_000)
            _ = try repository.create(from: CaptureDraft(type: .link, title: "Panel Link", urlString: "https://example.com"), at: base)
            _ = try repository.create(from: CaptureDraft(type: .text, title: "Panel Text", textContent: "panel text payload"), at: base.addingTimeInterval(1))
            _ = try repository.create(from: CaptureDraft(type: .code, title: "Panel Code", textContent: "let panel = true", language: "swift"), at: base.addingTimeInterval(2))
            let image = try repository.create(from: CaptureDraft(type: .image, title: "Panel Image", stagedAttachmentName: "panel.png", attachmentByteCount: 68, contentType: "image/png", fileName: "panel.png"), at: base.addingTimeInterval(3))
            let imageData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
            try repository.addAttachment(StowAttachment(itemID: image.id, data: imageData, contentType: "image/png", fileName: "panel.png"))
            let file = try repository.create(from: CaptureDraft(type: .file, title: "Panel File", stagedAttachmentName: "panel.txt", attachmentByteCount: 10, contentType: "text/plain", fileName: "panel.txt"), at: base.addingTimeInterval(4))
            try repository.addAttachment(StowAttachment(itemID: file.id, data: Data("panel file".utf8), contentType: "text/plain", fileName: "panel.txt"))
        } catch { presentedError = error.localizedDescription }
    }
    #endif

    func runMaintenance() {
        guard let repository else { return }
        let ingestion = spool?.ingestAll(into: repository)
        do {
            _ = try repository.purgeExpiredTrash()
            _ = try spool?.removeInterruptedStaging()
            let temporaryRoot = FileManager.default.temporaryDirectory
            _ = try AttachmentStore(repository: repository, temporaryDirectory: temporaryRoot.appendingPathComponent("StowOpen", isDirectory: true)).removeTemporaryFiles()
            _ = try AttachmentStore(repository: repository, temporaryDirectory: temporaryRoot.appendingPathComponent("StowTransfers", isDirectory: true)).removeTemporaryFiles()
            _ = try AttachmentStore(repository: repository, temporaryDirectory: temporaryRoot.appendingPathComponent("StowImports", isDirectory: true)).removeTemporaryFiles()
        } catch { presentedError = error.localizedDescription }
        if let ingestion, !ingestion.failures.isEmpty {
            presentedError = "Some shared items could not be imported. They were retained for diagnostics."
        }
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
}

private extension Duration {
    var secondsValue: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1_000_000_000_000_000_000
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
