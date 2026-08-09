import Foundation
import XCTest
@testable import StowCore

final class SearchServiceTests: XCTestCase {
    private func document(
        id: UUID = UUID(),
        content: String,
        type: ItemType = .text,
        sourceApp: String? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 100),
        status: ItemStatus = .inbox,
        isPinned: Bool = false,
        lastUsedAt: Date? = nil
    ) -> SearchDocument {
        SearchDocument(id: id, content: content, type: type, sourceApp: sourceApp, createdAt: createdAt, status: status, isPinned: isPinned, lastUsedAt: lastUsedAt)
    }

    func testSearchMatchesAllTokensAndFiltersMetadata() async throws {
        let index = try SQLiteSearchIndex(url: temporaryURL())
        let wanted = document(content: "Swift structured concurrency guide", type: .file, sourceApp: "Safari", createdAt: Date(timeIntervalSince1970: 200))
        let wrongType = document(content: "Swift concurrency notes", type: .text, sourceApp: "Notes", createdAt: Date(timeIntervalSince1970: 300))
        try await index.rebuild([wanted, wrongType])

        let results = try await index.search(SearchQuery(text: "swift concurrency", type: .file, sourceApp: "Safari"))

        XCTAssertEqual(results, [wanted.id])
    }

    func testFullwidthInputAndContentMatchHalfwidthSearchTerms() async throws {
        let index = try SQLiteSearchIndex(url: temporaryURL())
        let halfwidthContent = document(content: "Swift concurrency guide")
        let fullwidthContent = document(content: "Ｐａｎｅｌ　Ｔｅｘｔ")
        try await index.rebuild([halfwidthContent, fullwidthContent])

        let fullwidthQuery = try await index.search(SearchQuery(text: "Ｓｗｉｆｔ　ｃｏｎｃｕｒｒｅｎｃｙ"))
        let halfwidthQuery = try await index.search(SearchQuery(text: "Panel Text"))

        XCTAssertEqual(fullwidthQuery, [halfwidthContent.id])
        XCTAssertEqual(halfwidthQuery, [fullwidthContent.id])
    }

    func testTrashIsExcludedByDefaultAndCanBeRequested() async throws {
        let index = try SQLiteSearchIndex(url: temporaryURL())
        let live = document(content: "receipt", status: .archived)
        let trashed = document(content: "receipt", status: .trashed)
        try await index.rebuild([live, trashed])

        let liveResults = try await index.search(SearchQuery(text: "receipt"))
        let trashResults = try await index.search(SearchQuery(text: "receipt", status: .trashed))
        XCTAssertEqual(liveResults, [live.id])
        XCTAssertEqual(trashResults, [trashed.id])
    }

    func testDateFilterIsInclusiveAndEmptyQuerySortsNewestFirst() async throws {
        let index = try SQLiteSearchIndex(url: temporaryURL())
        let old = document(content: "old", createdAt: Date(timeIntervalSince1970: 100))
        let new = document(content: "new", createdAt: Date(timeIntervalSince1970: 200))
        try await index.rebuild([old, new])

        let results = try await index.search(SearchQuery(addedAfter: Date(timeIntervalSince1970: 100), addedBefore: Date(timeIntervalSince1970: 200)))

        XCTAssertEqual(results, [new.id, old.id])
    }

    func testUpsertAndRemoveKeepIndexConsistent() async throws {
        let index = try SQLiteSearchIndex(url: temporaryURL())
        let id = UUID()
        try await index.upsert(document(id: id, content: "before"))
        try await index.upsert(document(id: id, content: "after"))

        let oldResults = try await index.search(SearchQuery(text: "before"))
        let newResults = try await index.search(SearchQuery(text: "after"))
        XCTAssertTrue(oldResults.isEmpty)
        XCTAssertEqual(newResults, [id])

        try await index.remove(id: id)
        let removedResults = try await index.search(SearchQuery(text: "after"))
        XCTAssertTrue(removedResults.isEmpty)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
    }
}
