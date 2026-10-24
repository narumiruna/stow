import Foundation
import XCTest
@testable import StowCore

final class PortableSearchFixtureTests: XCTestCase {
    @MainActor
    func testSharedSearchFixtures() async throws {
        // Fixtures are repository files, not Swift package resources.
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let fixture = try JSONDecoder().decode(
            SearchFixture.self,
            from: Data(contentsOf: root.appendingPathComponent("Desktop/fixtures/search.json"))
        )
        XCTAssertFalse(fixture.datasets.isEmpty)

        for dataset in fixture.datasets {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let index = try SQLiteSearchIndex(url: directory.appendingPathComponent("search.sqlite"))
            let documents = dataset.items.map { row in
                SearchDocument(item: StowItem(
                    id: row.id,
                    type: row.type,
                    title: row.title,
                    textContent: row.text_content,
                    sourceApp: row.source_app,
                    createdAt: Date(timeIntervalSince1970: row.created_at),
                    status: row.status,
                    isPinned: row.pinned ?? false
                ))
            }
            try await index.rebuild(documents)
            let count = try await index.documentCount()
            XCTAssertEqual(count, dataset.items.count, dataset.name)
            XCTAssertFalse(dataset.queries.isEmpty, dataset.name)

            for query in dataset.queries {
                let filters = query.filters
                var actual = try await index.search(SearchQuery(
                    text: query.text,
                    type: filters.type,
                    sourceApp: filters.source_app,
                    addedAfter: filters.added_after.map { Date(timeIntervalSince1970: $0) },
                    addedBefore: filters.added_before.map { Date(timeIntervalSince1970: $0) },
                    status: filters.status,
                    includeTrashed: filters.include_trashed ?? false
                ))
                var expected = query.expected_ids
                if query.sort_ids == true {
                    actual.sort { $0.uuidString < $1.uuidString }
                    expected.sort { $0.uuidString < $1.uuidString }
                }
                XCTAssertEqual(actual, expected, "\(dataset.name): \(query.name)")
            }
        }
    }
}

private struct SearchFixture: Decodable {
    let datasets: [SearchDataset]
}

private struct SearchDataset: Decodable {
    let name: String
    let items: [SearchFixtureItem]
    let queries: [SearchFixtureQuery]
}

private struct SearchFixtureItem: Decodable {
    let id: UUID
    let title: String
    let text_content: String?
    let type: ItemType
    let source_app: String?
    let created_at: TimeInterval
    let status: ItemStatus
    let pinned: Bool?
}

private struct SearchFixtureQuery: Decodable {
    let name: String
    let text: String
    let filters: SearchFixtureFilters
    let expected_ids: [UUID]
    let sort_ids: Bool?
}

private struct SearchFixtureFilters: Decodable {
    let type: ItemType?
    let source_app: String?
    let added_after: TimeInterval?
    let added_before: TimeInterval?
    let status: ItemStatus?
    let include_trashed: Bool?
}
