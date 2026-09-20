import Foundation
import StowCore
import XCTest
@testable import StowApp

@MainActor
final class SearchIndexRecoveryTests: XCTestCase {
    func testAppModelReportsSuccessfulRebuildLocally() async {
        let documents = [document(content: "one"), document(content: "two")]
        let index = RecordingSearchIndex()
        let coordinator = SearchCoordinator(
            rebuild: { await index.rebuild($0) },
            search: { await index.search($0) }
        )
        let model = AppModel(
            searchDocuments: { documents },
            searchCoordinator: coordinator
        )

        await model.rebuildSearchIndex()

        let receivedDocuments = await index.documents
        XCTAssertEqual(receivedDocuments, documents)
        XCTAssertEqual(model.searchIndexRebuildState, .succeeded(documentCount: 2))
        model.dismissSearchIndexRebuildFeedback()
        XCTAssertEqual(model.searchIndexRebuildState, .idle)
    }

    func testAppModelReportsFailureWithoutUsingGlobalErrorPresentation() async {
        struct TestError: LocalizedError {
            var errorDescription: String? { "The replacement could not be written." }
        }
        let coordinator = SearchCoordinator(
            rebuild: { _ in throw TestError() },
            search: { _ in [] }
        )
        let model = AppModel(
            searchDocuments: { [self] in [document(content: "replacement")] },
            searchCoordinator: coordinator
        )

        await model.rebuildSearchIndex()

        XCTAssertEqual(model.searchIndexRebuildState, .failed("The replacement could not be written."))
        XCTAssertNil(model.presentedError)
    }

    func testCoordinatorSerializesEnsureAndSearchAcrossDifferentDocumentSets() async throws {
        let index = SuspendedSearchIndex()
        let coordinator = SearchCoordinator(
            rebuild: { try await index.rebuild($0) },
            search: { await index.search($0) }
        )
        let firstDocument = document(content: "first")
        let secondDocument = document(content: "second")

        let first = Task {
            try await coordinator.search(
                snapshot: SearchSnapshot(documents: [firstDocument]),
                query: SearchQuery(text: "first")
            )
        }
        await index.waitForFirstRebuild()

        let second = Task {
            try await coordinator.search(
                snapshot: SearchSnapshot(documents: [secondDocument]),
                query: SearchQuery(text: "second")
            )
        }
        await Task.yield()

        let eventsWhileFirstRebuildIsSuspended = await index.events
        XCTAssertEqual(eventsWhileFirstRebuildIsSuspended, [.rebuild([firstDocument.id])])

        await index.resumeFirstRebuild()
        let firstResults = try await first.value.ids
        let secondResults = try await second.value.ids
        let completedEvents = await index.events

        XCTAssertEqual(firstResults, [firstDocument.id])
        XCTAssertEqual(secondResults, [secondDocument.id])
        XCTAssertEqual(
            completedEvents,
            [
                .rebuild([firstDocument.id]),
                .search,
                .rebuild([secondDocument.id]),
                .search,
            ]
        )
    }

    func testCoordinatorExplicitRebuildEstablishesFreshFingerprint() async throws {
        let index = RecordingSearchIndex()
        let coordinator = SearchCoordinator(
            rebuild: { await index.rebuild($0) },
            search: { await index.search($0) }
        )
        let documents = [document(content: "searchable")]

        let snapshot = SearchSnapshot(documents: documents)
        try await coordinator.rebuild(snapshot)
        let results = try await coordinator.search(
            snapshot: snapshot,
            query: SearchQuery(text: "searchable")
        )

        let rebuildCount = await index.rebuildCount
        XCTAssertEqual(rebuildCount, 1)
        XCTAssertEqual(results.ids, documents.map(\.id))
    }

    func testAppModelLibrarySearchKeepsNewestGenerationAndCapturedQuery() async {
        let firstItem = StowItem(type: .text, title: "first")
        let secondItem = StowItem(type: .text, title: "second", sourceApp: "Notes")
        let operations = ControlledSearchOperations(
            resultIDs: ["first": [firstItem.id], "second": [secondItem.id]]
        )
        let coordinator = SearchCoordinator(
            rebuild: { await operations.rebuild($0) },
            search: { try await operations.search($0) }
        )
        let model = AppModel(searchCoordinator: coordinator)
        model.searchText = "first"

        let first = Task { await model.updateSearch(items: [firstItem]) }
        await operations.waitForFirstSearch()

        model.searchText = "second"
        model.typeFilter = .text
        model.sourceFilter = "Notes"
        model.dateFilter = .week
        let second = Task { await model.updateSearch(items: [secondItem]) }
        first.cancel()
        await operations.resumeFirstSearch()
        await first.value
        await second.value

        let queries = await operations.queries
        XCTAssertEqual(queries.map(\.text), ["first", "second"])
        XCTAssertEqual(queries.last?.type, .text)
        XCTAssertEqual(queries.last?.sourceApp, "Notes")
        XCTAssertNotNil(queries.last?.addedAfter)
        XCTAssertEqual(model.searchResultIDs, Set([secondItem.id]))
        XCTAssertFalse(model.isSearching)
        XCTAssertNil(model.presentedError)
    }

    func testAppModelRetrievalSearchDiscardsSupersededResult() async {
        let firstItem = StowItem(type: .text, title: "first")
        let secondItem = StowItem(type: .text, title: "second")
        let operations = ControlledSearchOperations(
            resultIDs: ["first": [firstItem.id], "second": [secondItem.id]]
        )
        let coordinator = SearchCoordinator(
            rebuild: { await operations.rebuild($0) },
            search: { try await operations.search($0) }
        )
        let model = AppModel(searchCoordinator: coordinator)

        let first = Task {
            await model.searchForRetrieval(
                items: [firstItem],
                text: "first",
                type: nil,
                source: nil,
                date: .anytime,
                status: nil
            )
        }
        await operations.waitForFirstSearch()
        let second = Task {
            await model.searchForRetrieval(
                items: [secondItem],
                text: "second",
                type: nil,
                source: nil,
                date: .anytime,
                status: nil
            )
        }
        first.cancel()
        await operations.resumeFirstSearch()

        let firstOutcome = await first.value
        let secondOutcome = await second.value
        XCTAssertEqual(firstOutcome, .success([]))
        XCTAssertEqual(secondOutcome, .success([secondItem.id]))
    }

    func testAppModelLibrarySearchPreservesRecoveryErrorPresentation() async {
        struct TestError: LocalizedError {
            var errorDescription: String? { "The test index failed." }
        }
        let coordinator = SearchCoordinator(
            rebuild: { _ in },
            search: { _ in throw TestError() }
        )
        let model = AppModel(searchCoordinator: coordinator)

        await model.updateSearch(items: [])

        XCTAssertNil(model.searchResultIDs)
        XCTAssertFalse(model.isSearching)
        XCTAssertEqual(
            model.presentedError,
            "The local search index will be rebuilt. The test index failed."
        )
    }

    func testSearchQueryFactoryUsesFixedClockAndSectionStatus() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_795_000_000)

        let today = SearchQueryFactory.library(
            text: "query",
            type: .code,
            source: "Xcode",
            date: .today,
            section: .inbox,
            now: now,
            calendar: calendar
        )
        let week = SearchQueryFactory.retrieval(
            text: "",
            type: nil,
            source: nil,
            date: .week,
            status: .archived,
            now: now,
            calendar: calendar
        )
        let month = SearchQueryFactory.retrieval(
            text: "",
            type: nil,
            source: nil,
            date: .month,
            status: nil,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(today.text, "query")
        XCTAssertEqual(today.type, .code)
        XCTAssertEqual(today.sourceApp, "Xcode")
        XCTAssertEqual(today.addedAfter, calendar.startOfDay(for: now))
        XCTAssertEqual(today.status, .inbox)
        XCTAssertEqual(today.limit, 10_000)
        XCTAssertEqual(week.addedAfter, calendar.date(byAdding: .day, value: -7, to: now))
        XCTAssertEqual(week.status, .archived)
        XCTAssertEqual(month.addedAfter, calendar.date(byAdding: .month, value: -1, to: now))
        XCTAssertNil(month.status)
        XCTAssertNil(SearchQueryFactory.addedAfter(for: .anytime, now: now, calendar: calendar))
        XCTAssertEqual(SearchQueryFactory.status(for: .archive), .archived)
        XCTAssertEqual(SearchQueryFactory.status(for: .trash), .trashed)
        XCTAssertNil(SearchQueryFactory.status(for: .recent))
    }

    func testSQLiteFailedRebuildRollsBackToPreviousUsableIndex() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SearchIndexRecoveryTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("search.sqlite")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let index = try SQLiteSearchIndex(url: url)
        let previous = document(content: "previous searchable content")
        try await index.rebuild([previous])

        let duplicateID = UUID()
        let invalidReplacement = [
            document(id: duplicateID, content: "first replacement"),
            document(id: duplicateID, content: "duplicate replacement"),
        ]
        do {
            try await index.rebuild(invalidReplacement)
            XCTFail("Expected the duplicate replacement to fail")
        } catch {
            // Expected: the transaction must roll back both DELETE statements and partial inserts.
        }

        let previousResults = try await index.search(SearchQuery(text: "previous searchable"))
        let replacementResults = try await index.search(SearchQuery(text: "replacement"))
        let documentCount = try await index.documentCount()
        XCTAssertEqual(previousResults, [previous.id])
        XCTAssertTrue(replacementResults.isEmpty)
        XCTAssertEqual(documentCount, 1)
    }

    private func document(id: UUID = UUID(), content: String) -> SearchDocument {
        SearchDocument(
            id: id,
            content: content,
            type: .text,
            sourceApp: "Tests",
            createdAt: Date(timeIntervalSince1970: 100),
            status: .inbox,
            isPinned: false,
            lastUsedAt: nil
        )
    }
}

private actor RecordingSearchIndex {
    private(set) var documents: [SearchDocument] = []
    private(set) var rebuildCount = 0

    func rebuild(_ documents: [SearchDocument]) {
        self.documents = documents
        rebuildCount += 1
    }

    func search(_ query: SearchQuery) -> [UUID] {
        documents.map(\.id)
    }
}

private actor ControlledSearchOperations {
    private let resultIDs: [String: [UUID]]
    private(set) var queries: [SearchQuery] = []
    private var firstSearchStarted = false
    private var firstSearchWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstSearchContinuation: CheckedContinuation<Void, Never>?

    init(resultIDs: [String: [UUID]]) {
        self.resultIDs = resultIDs
    }

    func rebuild(_ documents: [SearchDocument]) {}

    func search(_ query: SearchQuery) async throws -> [UUID] {
        queries.append(query)
        if !firstSearchStarted {
            firstSearchStarted = true
            firstSearchWaiters.forEach { $0.resume() }
            firstSearchWaiters.removeAll()
            await withCheckedContinuation { continuation in
                firstSearchContinuation = continuation
            }
        }
        return resultIDs[query.text] ?? []
    }

    func waitForFirstSearch() async {
        guard !firstSearchStarted else { return }
        await withCheckedContinuation { continuation in
            firstSearchWaiters.append(continuation)
        }
    }

    func resumeFirstSearch() {
        firstSearchContinuation?.resume()
        firstSearchContinuation = nil
    }
}

private actor SuspendedSearchIndex {
    enum Event: Equatable {
        case rebuild([UUID])
        case search
    }

    private(set) var events: [Event] = []
    private var documents: [SearchDocument] = []
    private var firstRebuildStarted = false
    private var firstRebuildWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstRebuildContinuation: CheckedContinuation<Void, Never>?

    func rebuild(_ documents: [SearchDocument]) async throws {
        events.append(.rebuild(documents.map(\.id)))
        self.documents = documents
        guard !firstRebuildStarted else { return }
        firstRebuildStarted = true
        firstRebuildWaiters.forEach { $0.resume() }
        firstRebuildWaiters.removeAll()
        await withCheckedContinuation { continuation in
            firstRebuildContinuation = continuation
        }
    }

    func search(_ query: SearchQuery) -> [UUID] {
        events.append(.search)
        return documents.map(\.id)
    }

    func waitForFirstRebuild() async {
        guard !firstRebuildStarted else { return }
        await withCheckedContinuation { continuation in
            firstRebuildWaiters.append(continuation)
        }
    }

    func resumeFirstRebuild() {
        firstRebuildContinuation?.resume()
        firstRebuildContinuation = nil
    }
}
