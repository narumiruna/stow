import Foundation
import StowCore
import XCTest
@testable import StowApp

@MainActor
final class SearchIndexRecoveryTests: XCTestCase {
    func testAppModelReportsSuccessfulRebuildLocally() async {
        let documents = [document(content: "one"), document(content: "two")]
        var receivedDocuments: [SearchDocument] = []
        let model = AppModel(
            searchDocuments: { documents },
            rebuildSearchIndex: { receivedDocuments = $0 }
        )

        await model.rebuildSearchIndex()

        XCTAssertEqual(receivedDocuments, documents)
        XCTAssertEqual(model.searchIndexRebuildState, .succeeded(documentCount: 2))
        model.dismissSearchIndexRebuildFeedback()
        XCTAssertEqual(model.searchIndexRebuildState, .idle)
    }

    func testAppModelReportsFailureWithoutUsingGlobalErrorPresentation() async {
        struct TestError: LocalizedError {
            var errorDescription: String? { "The replacement could not be written." }
        }
        let model = AppModel(
            searchDocuments: { [self] in [document(content: "replacement")] },
            rebuildSearchIndex: { _ in throw TestError() }
        )

        await model.rebuildSearchIndex()

        XCTAssertEqual(model.searchIndexRebuildState, .failed("The replacement could not be written."))
        XCTAssertNil(model.presentedError)
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
