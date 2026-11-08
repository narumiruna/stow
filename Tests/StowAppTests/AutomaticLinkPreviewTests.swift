import Foundation
import SwiftData
import StowCore
import XCTest
@testable import StowApp

@MainActor
final class AutomaticLinkPreviewTests: XCTestCase {
    func testDisabledPolicyMakesNoRequestsForDirectClipboardOrStagedMaintenance() async throws {
        let loader = PreviewLoader()
        let fixture = try PreviewFixture(enabled: false, loader: loader)
        defer { fixture.removeFiles() }
        let staged = linkDraft("staged")
        try fixture.spool.stage(staged)
        let repository = StowRepository(modelContext: fixture.container.mainContext)
        let existing = try repository.create(from: linkDraft("existing"))
        try repository.updateLinkMetadata(existing.id, metadata: LinkMetadata(
            title: "Existing title", description: "Existing description", domain: "preview.test",
            faviconData: Data([8]), previewImageData: Data([9])
        ))

        fixture.connect()
        let direct = linkDraft("direct")
        let clipboard = linkDraft("clipboard")
        XCTAssertTrue(fixture.model.create(direct))
        XCTAssertTrue(fixture.model.ingestClipboard(clipboard))
        fixture.model.runMaintenance()
        fixture.model.runMaintenance()
        await settle()

        let calls = await loader.calls
        XCTAssertTrue(calls.isEmpty)
        let items = try repository.allItems()
        XCTAssertEqual(Set(items.compactMap(\.urlString)), Set([
            staged.urlString!, direct.urlString!, clipboard.urlString!, existing.urlString!
        ]))
        XCTAssertEqual(existing.linkDescription, "Existing description")
        XCTAssertEqual(existing.faviconData, Data([8]))
        XCTAssertEqual(existing.linkPreviewImageData, Data([9]))
    }

    func testIOSSettingsActionCancelsBeforeObservationAndCannotCoalesceOffOn() async throws {
        for reenable in [false, true] {
            let loader = PreviewLoader(holding: .pages)
            let fixture = try PreviewFixture(enabled: true, loader: loader)
            defer { fixture.removeFiles() }
            let suite = "PreviewSettingsTests-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let preferences = IOSPreferences(defaults: defaults)
            fixture.connect()
            fixture.model.setAutomaticLinkPreviewsEnabled(true, preferences: preferences)
            let item = try fixture.model.createForAutomation(linkDraft("settings-action"))
            let originalUpdatedAt = item.updatedAt
            await waitUntil { await loader.calls.count == 1 }
            fixture.model.setAutomaticLinkPreviewsEnabled(false, preferences: preferences)
            XCTAssertFalse(fixture.model.automaticLinkPreviewsEnabled)
            XCTAssertFalse(preferences.automaticLinkPreviewsEnabled)
            if reenable { fixture.model.setAutomaticLinkPreviewsEnabled(true, preferences: preferences) }
            await loader.releaseAll()
            await settle()
            let calls = await loader.calls
            XCTAssertEqual(calls.count, 1)
            assertUnenriched(item, updatedAt: originalUpdatedAt)
            XCTAssertEqual(preferences.automaticLinkPreviewsEnabled, reenable)
            XCTAssertEqual(IOSPreferences(defaults: defaults).automaticLinkPreviewsEnabled, reenable)
        }
    }

    func testDisableBeforeScheduledWorkStartsMakesNoRequests() async throws {
        let loader = PreviewLoader()
        let fixture = try PreviewFixture(enabled: true, loader: loader)
        defer { fixture.removeFiles() }
        fixture.connect()
        XCTAssertTrue(fixture.model.create(linkDraft("queued")))
        fixture.model.setAutomaticLinkPreviewsEnabled(false)
        await settle()

        let calls = await loader.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testDisableDuringPageLoadPreventsAssetsAndAllMetadataWrites() async throws {
        let loader = PreviewLoader(holding: .pages)
        let fixture = try PreviewFixture(enabled: true, loader: loader)
        defer { fixture.removeFiles() }
        fixture.connect()
        let item = try fixture.model.createForAutomation(linkDraft("page"))
        let originalUpdatedAt = item.updatedAt
        await waitUntil { await loader.calls.count == 1 }

        fixture.model.setAutomaticLinkPreviewsEnabled(false)
        await loader.releaseAll()
        await settle()

        let calls = await loader.calls
        XCTAssertEqual(calls.count, 1)
        assertUnenriched(item, updatedAt: originalUpdatedAt)
        XCTAssertEqual(item.urlString, "https://preview.test/page")
    }

    func testDisableDuringAssetLoadsRejectsResultsEvenWhenLoaderIgnoresCancellation() async throws {
        let loader = PreviewLoader(holding: .assets)
        let fixture = try PreviewFixture(enabled: true, loader: loader)
        defer { fixture.removeFiles() }
        fixture.connect()
        let item = try fixture.model.createForAutomation(linkDraft("assets"))
        let originalUpdatedAt = item.updatedAt
        await waitUntil { await loader.calls.count == 3 }

        fixture.model.setAutomaticLinkPreviewsEnabled(false)
        await loader.releaseAll()
        await settle()

        let calls = await loader.calls
        XCTAssertEqual(calls.count, 3)
        assertUnenriched(item, updatedAt: originalUpdatedAt)
    }

    func testOffOnRejectsStaleGenerationAndRetainsOwnershipUntilCompletion() async throws {
        let loader = PreviewLoader(holding: .pages)
        let fixture = try PreviewFixture(enabled: true, loader: loader)
        defer { fixture.removeFiles() }
        fixture.connect()
        let item = try fixture.model.createForAutomation(linkDraft("generation"))
        let originalUpdatedAt = item.updatedAt
        await waitUntil { await loader.calls.count == 1 }

        fixture.model.setAutomaticLinkPreviewsEnabled(false)
        fixture.model.setAutomaticLinkPreviewsEnabled(true)
        fixture.model.runMaintenance()
        await settle()
        let callsWhileStaleRequestIsPending = await loader.calls
        XCTAssertEqual(callsWhileStaleRequestIsPending.count, 1, "Do not overlap a cancelled request that has not finished")

        await loader.releaseAll()
        await settle()
        assertUnenriched(item, updatedAt: originalUpdatedAt)
        let callsAfterStaleCompletion = await loader.calls
        XCTAssertEqual(callsAfterStaleCompletion.count, 1, "The stale page must not start assets")

        fixture.model.runMaintenance()
        await waitUntil { item.linkDescription == "Fetched description" }
        let callsAfterRetry = await loader.calls
        XCTAssertEqual(callsAfterRetry.count, 4)
    }

    func testEnabledMaintenanceSchedulesAtMostTenCandidatesAndDeduplicatesInFlightWork() async throws {
        let loader = PreviewLoader(holding: .pages)
        let fixture = try PreviewFixture(enabled: true, loader: loader)
        defer { fixture.removeFiles() }
        for index in 0..<12 { try fixture.spool.stage(linkDraft("maintenance-\(index)")) }
        fixture.connect()
        await waitUntil { await loader.calls.count == 10 }

        fixture.model.runMaintenance()
        fixture.model.runMaintenance()
        await settle()
        let pendingCalls = await loader.calls
        XCTAssertEqual(pendingCalls.count, 10)
        XCTAssertEqual(Set(pendingCalls.map(\.url)).count, 10)
        XCTAssertTrue(pendingCalls.allSatisfy { $0.kind == .html })
        XCTAssertEqual(try fixture.model.repository?.allItems().count, 12)

        await loader.releaseAll()
        await waitUntil {
            (try? fixture.model.repository?.allItems().filter { $0.linkDescription != nil }.count) == 10
        }
        let completedCalls = await loader.calls
        XCTAssertEqual(completedCalls.count, 30)
    }

    func testDirectClipboardAndMaintenanceShareDeduplicationAndBoundedLoading() async throws {
        let loader = PreviewLoader(holding: .pages)
        let fixture = try PreviewFixture(enabled: true, loader: loader)
        defer { fixture.removeFiles() }
        fixture.connect()
        let direct = try fixture.model.createForAutomation(linkDraft("direct"))
        let clipboardDraft = CaptureDraft(
            type: .link, title: "Saved clipboard title", urlString: "https://preview.test/clipboard"
        )
        XCTAssertTrue(fixture.model.ingestClipboard(clipboardDraft))
        // Repeated clipboard ingestion must not start another request for the existing item.
        XCTAssertTrue(fixture.model.ingestClipboard(clipboardDraft))
        fixture.model.runMaintenance()
        fixture.model.runMaintenance()
        await waitUntil { await loader.calls.count == 2 }
        await settle()
        let pendingCalls = await loader.calls
        XCTAssertEqual(pendingCalls.count, 2)
        XCTAssertEqual(Set(pendingCalls.map(\.url)).count, 2)

        await loader.releaseAll()
        await waitUntil {
            (try? fixture.model.repository?.allItems().filter { $0.linkDescription != nil }.count) == 2
        }
        let calls = await loader.calls
        XCTAssertEqual(calls.count, 6)
        for call in calls {
            XCTAssertEqual(call.timeout, 12)
            XCTAssertEqual(call.limit, call.kind == .html ? 2 * 1_024 * 1_024 : 5 * 1_024 * 1_024)
            if call.kind == .html { XCTAssertEqual(call.userAgent, "Stow/0.1") }
        }
        XCTAssertEqual(direct.title, "Fetched title")
        XCTAssertEqual(direct.linkDescription, "Fetched description")
        XCTAssertEqual(direct.faviconData, PreviewLoader.faviconData)
        XCTAssertEqual(direct.linkPreviewImageData, PreviewLoader.previewImageData)
        let clipboard = try XCTUnwrap(fixture.model.repository?.allItems().first { $0.captureID == clipboardDraft.id })
        XCTAssertEqual(clipboard.title, "Saved clipboard title")
    }

    func testPermissionGuardRejectsStalePageAndAssetResultsWithoutTaskCancellation() async throws {
        // Exercise the generation guard separately from Task.isCancelled.
        for holding in [PreviewLoader.Holding.pages, .assets] {
            let loader = PreviewLoader(holding: holding)
            let container = try StowContainerFactory.inMemory()
            let repository = StowRepository(modelContext: container.mainContext)
            let item = try repository.create(from: linkDraft("permission"))
            let originalUpdatedAt = item.updatedAt
            let permission = PreviewPermission()
            let enricher = LinkMetadataEnricher { request, limit, timeout, kind in
                try await loader.load(request, limit: limit, timeout: timeout, kind: kind)
            }
            let task = Task {
                await enricher.enrich(item: item, repository: repository) { permission.generation == 0 }
            }
            await waitUntil { await loader.calls.count == (holding == .pages ? 1 : 3) }
            permission.generation += 1
            await loader.releaseAll()
            await task.value

            let calls = await loader.calls
            XCTAssertEqual(calls.count, holding == .pages ? 1 : 3)
            assertUnenriched(item, updatedAt: originalUpdatedAt)
        }
    }

    func testReleasedModelCancelsWorkAndDoesNotWriteLateMetadata() async throws {
        let loader = PreviewLoader(holding: .pages)
        let container = try StowContainerFactory.inMemory()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PreviewDeinit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        var model: AppModel? = AppModel(
            searchCoordinator: SearchCoordinator(rebuild: { _ in }, search: { _ in [] }),
            runtimePaths: StowRuntimePaths(sharedContainer: root, temporaryDirectory: root.appendingPathComponent("Temporary")),
            automaticLinkPreviewsEnabled: true,
            linkMetadataEnricher: LinkMetadataEnricher { request, limit, timeout, kind in
                try await loader.load(request, limit: limit, timeout: timeout, kind: kind)
            }
        )
        weak var releasedModel = model
        model?.connect(container.mainContext)
        let item = try XCTUnwrap(model).createForAutomation(linkDraft("deinit"))
        let originalUpdatedAt = item.updatedAt
        await waitUntil { await loader.calls.count == 1 }
        model = nil
        XCTAssertNil(releasedModel)
        await loader.releaseAll()
        await settle()
        let calls = await loader.calls
        XCTAssertEqual(calls.count, 1)
        assertUnenriched(item, updatedAt: originalUpdatedAt)
    }

    func testMacOSDefaultRemainsEnabledAndFetches() async throws {
        #if os(macOS)
        let loader = PreviewLoader()
        let fixture = try PreviewFixture(loader: loader)
        defer { fixture.removeFiles() }
        XCTAssertTrue(AppModel.defaultAutomaticLinkPreviewsEnabled)
        XCTAssertTrue(fixture.model.automaticLinkPreviewsEnabled)
        fixture.connect()
        let item = try fixture.model.createForAutomation(linkDraft("default"))
        await waitUntil { item.linkDescription == "Fetched description" }
        let calls = await loader.calls
        XCTAssertEqual(calls.count, 3)
        #endif
    }

    func testManualRefreshFetchesWhenAutomaticPreviewsAreDisabledAndBypassesEveryCache() async throws {
        let loader = PreviewLoader()
        let fixture = try PreviewFixture(enabled: false, loader: loader)
        defer { fixture.removeFiles() }
        fixture.connect()
        let item = try fixture.model.createForAutomation(linkDraft("manual"))

        await fixture.model.refreshLinkPreview(for: item)

        let calls = await loader.calls
        XCTAssertEqual(calls.count, 3)
        XCTAssertEqual(calls.filter { $0.kind == .html }.count, 1)
        XCTAssertTrue(calls.allSatisfy { $0.cachePolicy == .reloadIgnoringLocalCacheData })
        XCTAssertEqual(calls.first?.userAgent, "Stow/0.1")
        XCTAssertFalse(fixture.model.automaticLinkPreviewsEnabled)
        XCTAssertEqual(item.title, "Fetched title")
        XCTAssertEqual(item.linkDescription, "Fetched description")
        XCTAssertEqual(item.faviconData, PreviewLoader.faviconData)
        XCTAssertEqual(item.linkPreviewImageData, PreviewLoader.previewImageData)
    }

    func testManualRefreshReplacesExistingMetadataButPreservesCustomTitle() async throws {
        let loader = PreviewLoader()
        let fixture = try PreviewFixture(enabled: false, loader: loader)
        defer { fixture.removeFiles() }
        fixture.connect()
        let item = try fixture.model.createForAutomation(CaptureDraft(
            type: .link, title: "Custom title", urlString: "https://preview.test/enriched"
        ))
        let repository = try XCTUnwrap(fixture.model.repository)
        try repository.updateLinkMetadata(item.id, metadata: LinkMetadata(
            title: "Saved page title", description: "Saved description", domain: "preview.test",
            faviconData: Data([8]), previewImageData: Data([9])
        ))

        await fixture.model.refreshLinkPreview(for: item)

        let calls = await loader.calls
        XCTAssertEqual(calls.count, 3)
        XCTAssertEqual(item.title, "Custom title")
        XCTAssertEqual(item.linkDescription, "Fetched description")
        XCTAssertEqual(item.faviconData, PreviewLoader.faviconData)
        XCTAssertEqual(item.linkPreviewImageData, PreviewLoader.previewImageData)
    }

    func testManualRefreshDeduplicatesCallersAndAwaitsAllAssetsAcrossAutomaticSettingChanges() async throws {
        let loader = PreviewLoader(holding: .assets)
        let fixture = try PreviewFixture(enabled: false, loader: loader)
        defer { fixture.removeFiles() }
        fixture.connect()
        let item = try fixture.model.createForAutomation(linkDraft("manual-assets"))
        let originalUpdatedAt = item.updatedAt
        var completed = 0
        let first = Task {
            await fixture.model.refreshLinkPreview(for: item)
            completed += 1
        }
        await waitUntil { await loader.calls.count >= 3 }
        var secondStarted = false
        let second = Task {
            secondStarted = true
            await fixture.model.refreshLinkPreview(for: item)
            completed += 1
        }
        await waitUntil { secondStarted }

        fixture.model.setAutomaticLinkPreviewsEnabled(true)
        fixture.model.runMaintenance()
        fixture.model.runMaintenance()
        await settle()
        let callsDuringMaintenance = await loader.calls
        XCTAssertEqual(callsDuringMaintenance.count, 3, "Maintenance must not overlap manual work")
        fixture.model.setAutomaticLinkPreviewsEnabled(false)
        await settle()
        XCTAssertEqual(completed, 0)
        await loader.release(path: "/icon.png")
        await settle()
        XCTAssertEqual(completed, 0, "Both callers must await the remaining preview image")
        assertUnenriched(item, updatedAt: originalUpdatedAt)

        await loader.releaseAll()
        await first.value
        await second.value

        let calls = await loader.calls
        XCTAssertEqual(calls.count, 3)
        XCTAssertEqual(completed, 2)
        XCTAssertEqual(item.linkDescription, "Fetched description")
        XCTAssertEqual(item.faviconData, PreviewLoader.faviconData)
        XCTAssertEqual(item.linkPreviewImageData, PreviewLoader.previewImageData)
    }

    func testManualRefreshWaitsForAutomaticPageAndAssetsThenForcesAnotherRequest() async throws {
        let loader = PreviewLoader(holding: .pages)
        let fixture = try PreviewFixture(enabled: true, loader: loader)
        defer { fixture.removeFiles() }
        fixture.connect()
        let item = try fixture.model.createForAutomation(linkDraft("serialized"))
        await waitUntil { await loader.calls.count >= 1 }
        var started = false
        var completed = false
        let manual = Task {
            started = true
            await fixture.model.refreshLinkPreview(for: item)
            completed = true
        }
        await waitUntil { started }
        fixture.model.runMaintenance()
        await settle()
        let callsWhilePageIsPending = await loader.calls
        XCTAssertEqual(callsWhilePageIsPending.count, 1)
        XCTAssertFalse(completed)

        await loader.setHolding(.assets)
        await loader.release(path: "/serialized")
        await waitUntil { await loader.calls.count >= 3 }
        await settle()
        let callsWhileAssetsArePending = await loader.calls
        XCTAssertEqual(callsWhileAssetsArePending.count, 3, "Manual work must also await automatic assets")
        XCTAssertFalse(completed)

        await loader.releaseAll()
        await manual.value

        let calls = await loader.calls
        XCTAssertEqual(calls.count, 6, "Automatic enrichment must not satisfy an explicit refresh")
        XCTAssertEqual(calls.first?.cachePolicy, .returnCacheDataElseLoad)
        XCTAssertEqual(calls.dropFirst().prefix(2).map(\.cachePolicy), [.useProtocolCachePolicy, .useProtocolCachePolicy])
        XCTAssertEqual(calls.dropFirst(3).first?.kind, .html)
        XCTAssertTrue(calls.dropFirst(3).allSatisfy { $0.cachePolicy == .reloadIgnoringLocalCacheData })
        XCTAssertTrue(completed)
        XCTAssertEqual(item.linkDescription, "Fetched description")
    }

    func testManualRefreshPreservesFailedPageOrAssetMetadataAndCanRetry() async throws {
        for pageFails in [true, false] {
            let loader = PreviewLoader(failingPaths: pageFails ? ["/failure"] : ["/icon.png", "/preview.png"])
            let fixture = try PreviewFixture(enabled: false, loader: loader)
            defer { fixture.removeFiles() }
            fixture.connect()
            let item = try fixture.model.createForAutomation(linkDraft("failure"))
            let repository = try XCTUnwrap(fixture.model.repository)
            try repository.updateLinkMetadata(item.id, metadata: LinkMetadata(
                title: "Saved title", description: "Saved description", domain: "preview.test",
                faviconData: Data([8]), previewImageData: Data([9])
            ))
            let originalUpdatedAt = item.updatedAt

            await fixture.model.refreshLinkPreview(for: item)

            let failedCalls = await loader.calls
            XCTAssertEqual(failedCalls.count, pageFails ? 1 : 3)
            XCTAssertEqual(item.title, "Saved title")
            XCTAssertEqual(item.linkDescription, pageFails ? "Saved description" : "Fetched description")
            XCTAssertEqual(item.sourceDomain, "preview.test")
            XCTAssertEqual(item.faviconData, Data([8]))
            XCTAssertEqual(item.linkPreviewImageData, Data([9]))
            if pageFails { XCTAssertEqual(item.updatedAt, originalUpdatedAt) }

            await loader.setFailingPaths([])
            await fixture.model.refreshLinkPreview(for: item)

            let retriedCalls = await loader.calls
            XCTAssertEqual(retriedCalls.count, pageFails ? 4 : 6)
            XCTAssertEqual(item.title, "Saved title")
            XCTAssertEqual(item.linkDescription, "Fetched description")
            XCTAssertEqual(item.faviconData, PreviewLoader.faviconData)
            XCTAssertEqual(item.linkPreviewImageData, PreviewLoader.previewImageData)
        }
    }

    func testManualRefreshPreservesSavedImagesWhenImageResponsesAreEmptyOrCorrupt() async throws {
        for imageData in [Data(), Data("not an image".utf8)] {
            let loader = PreviewLoader(imageData: imageData)
            let fixture = try PreviewFixture(enabled: false, loader: loader)
            defer { fixture.removeFiles() }
            fixture.connect()
            let item = try fixture.model.createForAutomation(linkDraft("invalid-images"))
            let repository = try XCTUnwrap(fixture.model.repository)
            try repository.updateLinkMetadata(item.id, metadata: LinkMetadata(
                title: "Saved title", description: "Saved description", domain: "preview.test",
                faviconData: PreviewLoader.faviconData, previewImageData: PreviewLoader.previewImageData
            ))

            await fixture.model.refreshLinkPreview(for: item)

            let calls = await loader.calls
            XCTAssertEqual(calls.count, 3)
            XCTAssertTrue(calls.allSatisfy { $0.cachePolicy == .reloadIgnoringLocalCacheData })
            XCTAssertEqual(item.title, "Saved title")
            XCTAssertEqual(item.linkDescription, "Fetched description")
            XCTAssertEqual(item.faviconData, PreviewLoader.faviconData)
            XCTAssertEqual(item.linkPreviewImageData, PreviewLoader.previewImageData)
        }
    }

    func testManualRefreshPreservesMissingMetadataAndBypassesFallbackFaviconCache() async throws {
        let loader = PreviewLoader(html: "<html><head></head></html>", failingPaths: ["/favicon.ico"])
        let fixture = try PreviewFixture(enabled: false, loader: loader)
        defer { fixture.removeFiles() }
        fixture.connect()
        let item = try fixture.model.createForAutomation(linkDraft("missing"))
        let repository = try XCTUnwrap(fixture.model.repository)
        try repository.updateLinkMetadata(item.id, metadata: LinkMetadata(
            title: "Saved title", description: "Saved description", domain: "preview.test",
            faviconData: Data([8]), previewImageData: Data([9])
        ))

        await fixture.model.refreshLinkPreview(for: item)

        let calls = await loader.calls
        XCTAssertEqual(calls.map(\.url.path), ["/missing", "/favicon.ico"])
        XCTAssertTrue(calls.allSatisfy { $0.cachePolicy == .reloadIgnoringLocalCacheData })
        XCTAssertEqual(item.title, "Saved title")
        XCTAssertEqual(item.linkDescription, "Saved description")
        XCTAssertEqual(item.sourceDomain, "preview.test")
        XCTAssertEqual(item.faviconData, Data([8]))
        XCTAssertEqual(item.linkPreviewImageData, Data([9]))
    }

    func testManualRefreshOfNonLinkMakesNoRequestsOrChanges() async throws {
        let loader = PreviewLoader()
        let fixture = try PreviewFixture(enabled: true, loader: loader)
        defer { fixture.removeFiles() }
        fixture.connect()
        let item = try fixture.model.createForAutomation(CaptureDraft(
            type: .text, title: "Saved note", textContent: "Saved body", urlString: "https://preview.test/note"
        ))
        let originalUpdatedAt = item.updatedAt

        await fixture.model.refreshLinkPreview(for: item)

        let calls = await loader.calls
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(item.title, "Saved note")
        XCTAssertEqual(item.textContent, "Saved body")
        XCTAssertEqual(item.updatedAt, originalUpdatedAt)
        XCTAssertNil(item.linkDescription)
        XCTAssertNil(item.faviconData)
        XCTAssertNil(item.linkPreviewImageData)
    }

    private func linkDraft(_ path: String) -> CaptureDraft {
        CaptureDraft(type: .link, title: "preview.test", urlString: "https://preview.test/\(path)")
    }

    private func assertUnenriched(_ item: StowItem, updatedAt: Date, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(item.linkDescription, file: file, line: line)
        XCTAssertNil(item.faviconData, file: file, line: line)
        XCTAssertNil(item.linkPreviewImageData, file: file, line: line)
        XCTAssertEqual(item.title, "preview.test", file: file, line: line)
        XCTAssertEqual(item.updatedAt, updatedAt, file: file, line: line)
    }

    private func waitUntil(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ predicate: () async throws -> Bool
    ) async rethrows {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while try await !predicate() {
            guard ContinuousClock.now < deadline else {
                XCTFail("Preview work did not reach the expected state", file: file, line: line)
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    private func settle() async {
        // Give queued actor tasks time to attempt any forbidden request or write.
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(20))
    }
}

@MainActor
private final class PreviewPermission {
    var generation = 0
}

@MainActor
private final class PreviewFixture {
    let root: URL
    let container: ModelContainer
    let spool: CaptureSpool
    let model: AppModel

    init(enabled: Bool? = nil, loader: PreviewLoader) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PreviewTests-\(UUID().uuidString)", isDirectory: true)
        container = try StowContainerFactory.inMemory()
        spool = try CaptureSpool(rootURL: root.appendingPathComponent("Spool", isDirectory: true))
        let paths = StowRuntimePaths(sharedContainer: root, temporaryDirectory: root.appendingPathComponent("Temporary"))
        let enricher = LinkMetadataEnricher { request, limit, timeout, kind in
            try await loader.load(request, limit: limit, timeout: timeout, kind: kind)
        }
        let search = SearchCoordinator(rebuild: { _ in }, search: { _ in [] })
        if let enabled {
            model = AppModel(
                searchCoordinator: search, captureSpool: spool, runtimePaths: paths,
                automaticLinkPreviewsEnabled: enabled, linkMetadataEnricher: enricher
            )
        } else {
            model = AppModel(
                searchCoordinator: search, captureSpool: spool, runtimePaths: paths,
                linkMetadataEnricher: enricher
            )
        }
    }

    func connect() { model.connect(container.mainContext) }

    func removeFiles() {
        model.setAutomaticLinkPreviewsEnabled(false)
        try? FileManager.default.removeItem(at: root)
    }
}

private actor PreviewLoader {
    // Complete one-pixel PNGs: black favicon and white preview image.
    static let faviconData = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAX+XDSwAAAABJRU5ErkJggg=="
    )!
    static let previewImageData = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII="
    )!

    enum Holding { case none, pages, assets }

    struct Call: Sendable {
        let url: URL
        let limit: Int
        let timeout: TimeInterval
        let kind: BoundedHTTPContentKind
        let userAgent: String?
        let cachePolicy: URLRequest.CachePolicy
    }

    private(set) var calls: [Call] = []
    private var holding: Holding
    private let html: String?
    private let imageData: Data?
    private var failingPaths: Set<String>
    private var pending: [(Call, CheckedContinuation<BoundedHTTPResponse, any Error>)] = []

    init(holding: Holding = .none, html: String? = nil, imageData: Data? = nil, failingPaths: Set<String> = []) {
        self.holding = holding
        self.html = html
        self.imageData = imageData
        self.failingPaths = failingPaths
    }

    func setHolding(_ holding: Holding) { self.holding = holding }

    func setFailingPaths(_ paths: Set<String>) { failingPaths = paths }

    func load(_ request: URLRequest, limit: Int, timeout: TimeInterval, kind: BoundedHTTPContentKind) async throws -> BoundedHTTPResponse {
        let call = Call(
            url: request.url!, limit: limit, timeout: timeout, kind: kind,
            userAgent: request.value(forHTTPHeaderField: "User-Agent"), cachePolicy: request.cachePolicy
        )
        calls.append(call)
        if (holding == .pages && kind == .html) || (holding == .assets && kind == .image) {
            // Deliberately ignore task cancellation until the test releases the response.
            return try await withCheckedThrowingContinuation { pending.append((call, $0)) }
        }
        return try response(for: call)
    }

    func releaseAll() {
        holding = .none
        let responses = pending
        pending.removeAll()
        for (call, continuation) in responses {
            continuation.resume(with: Result { try response(for: call) })
        }
    }

    func release(path: String) {
        guard let index = pending.firstIndex(where: { $0.0.url.path == path }) else { return }
        let (call, continuation) = pending.remove(at: index)
        continuation.resume(with: Result { try response(for: call) })
    }

    private func response(for call: Call) throws -> BoundedHTTPResponse {
        if failingPaths.contains(call.url.path) { throw URLError(.badServerResponse) }
        let data: Data
        if call.kind == .html {
            let html = self.html ?? """
            <html><head><title>Fetched title</title>
            <meta name="description" content="Fetched description">
            <link rel="icon" href="/icon.png">
            <meta property="og:image" content="/preview.png">
            </head></html>
            """
            data = Data(html.utf8)
        } else {
            data = imageData ?? (call.url.path == "/icon.png" ? Self.faviconData : Self.previewImageData)
        }
        return BoundedHTTPResponse(data: data, response: URLResponse(
            url: call.url, mimeType: call.kind == .html ? "text/html" : "image/png",
            expectedContentLength: data.count, textEncodingName: nil
        ))
    }
}
