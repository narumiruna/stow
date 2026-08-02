@preconcurrency import CoreSpotlight
import Foundation
import StowCore
import UniformTypeIdentifiers

@main
@MainActor
struct LocalSearchBenchmark {
    static func main() async throws {
        let count = 10_000
        let documents = (0..<count).map { index in
            SearchDocument(
                id: UUID(),
                content: "Item \(index) Swift concurrency \(index.isMultiple(of: 3) ? "guide" : "reference") source.example note filename-\(index).txt",
                type: ItemType.allCases[index % ItemType.allCases.count],
                sourceApp: index.isMultiple(of: 2) ? "Safari" : "Notes",
                createdAt: Date(timeIntervalSince1970: Double(index)),
                status: index.isMultiple(of: 20) ? .archived : .inbox,
                isPinned: index.isMultiple(of: 17),
                lastUsedAt: index.isMultiple(of: 4) ? Date(timeIntervalSince1970: Double(index + 10)) : nil
            )
        }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("stow-search-\(UUID().uuidString).sqlite")
        let sqlite = try SQLiteSearchIndex(url: temp)
        let sqliteRebuild = try await measure { try await sqlite.rebuild(documents) }
        var sqliteQueries: [Double] = []
        for query in benchmarkQueries {
            sqliteQueries.append(try await measure { _ = try await sqlite.search(query) })
        }

        print("SQLite FTS5")
        print("  rebuild_10000_ms=\(format(sqliteRebuild))")
        print("  query_median_ms=\(format(percentile(sqliteQueries, 0.50)))")
        print("  query_p95_ms=\(format(percentile(sqliteQueries, 0.95)))")

        guard CSSearchableIndex.isIndexingAvailable() else {
            print("Core Spotlight")
            print("  unavailable=true")
            return
        }
        do {
            let spotlight = CSSearchableIndex(name: "StowLocalSearchBenchmark")
            try await deleteAll(spotlight)
            let items = documents.map { document -> CSSearchableItem in
                let attributes = CSSearchableItemAttributeSet(contentType: .text)
                attributes.title = document.content.components(separatedBy: " ").prefix(2).joined(separator: " ")
                attributes.textContent = document.content
                attributes.contentDescription = document.sourceApp
                return CSSearchableItem(uniqueIdentifier: document.id.uuidString, domainIdentifier: "stow-benchmark", attributeSet: attributes)
            }
            let spotlightRebuild = try await measure {
                for start in stride(from: 0, to: items.count, by: 500) {
                    try await index(spotlight, items: Array(items[start..<min(start + 500, items.count)]))
                }
            }
            // Core Spotlight commits asynchronously; wait for indexing before measured queries.
            try await Task.sleep(for: .seconds(2))
            var spotlightQueries: [Double] = []
            for _ in 0..<100 {
                spotlightQueries.append(try await measure { _ = try await spotlightSearch(#"textContent == "*swift*"cd && textContent == "*concurrency*"cd"#) })
            }
            print("Core Spotlight")
            print("  rebuild_10000_ms=\(format(spotlightRebuild))")
            print("  query_median_ms=\(format(percentile(spotlightQueries, 0.50)))")
            print("  query_p95_ms=\(format(percentile(spotlightQueries, 0.95)))")
            try await deleteAll(spotlight)
        } catch {
            print("Core Spotlight")
            print("  benchmark_error=\(error.localizedDescription)")
        }
    }

    private static let benchmarkQueries: [SearchQuery] = (0..<100).map { index in
        SearchQuery(text: index.isMultiple(of: 2) ? "swift concurrency" : "guide", type: index.isMultiple(of: 5) ? .file : nil, sourceApp: index.isMultiple(of: 7) ? "Safari" : nil)
    }

    private static func measure(_ operation: () async throws -> Void) async throws -> Double {
        let clock = ContinuousClock()
        let start = clock.now
        try await operation()
        let elapsed = start.duration(to: clock.now).components
        return Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1_000_000_000_000_000
    }

    private static func percentile(_ values: [Double], _ percentile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * percentile))]
    }

    private static func format(_ value: Double) -> String { String(format: "%.3f", value) }

    private static func index(_ index: CSSearchableIndex, items: [CSSearchableItem]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            index.indexSearchableItems(items) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    private static func deleteAll(_ index: CSSearchableIndex) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            index.deleteAllSearchableItems { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
    }

    private static func spotlightSearch(_ queryString: String) async throws -> [String] {
        final class State: @unchecked Sendable { var identifiers: [String] = [] }
        let state = State()
        return try await withCheckedThrowingContinuation { continuation in
            let context = CSSearchQueryContext()
            context.fetchAttributes = ["uniqueIdentifier"]
            let query = CSSearchQuery(queryString: queryString, queryContext: context)
            query.foundItemsHandler = { items in state.identifiers.append(contentsOf: items.map(\.uniqueIdentifier)) }
            query.completionHandler = { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: state.identifiers) }
            }
            query.start()
        }
    }
}
