import Foundation
import StowCore

struct SearchItemRevision: Hashable, Sendable {
    let itemCount: Int
    private let fingerprint: Int

    @MainActor
    init(items: [StowItem]) {
        var hasher = Hasher()
        for item in items {
            hasher.combine(item.id)
            hasher.combine(item.updatedAt)
        }
        itemCount = items.count
        fingerprint = hasher.finalize()
    }

    init(documents: [SearchDocument]) {
        var hasher = Hasher()
        for document in documents {
            hasher.combine(document.id)
            hasher.combine(document.content)
            hasher.combine(document.type.rawValue)
            hasher.combine(document.sourceApp)
            hasher.combine(document.createdAt)
            hasher.combine(document.status.rawValue)
            hasher.combine(document.isPinned)
            hasher.combine(document.lastUsedAt)
        }
        itemCount = documents.count
        fingerprint = hasher.finalize()
    }

    var token: String { "\(itemCount):\(fingerprint)" }
}

struct SearchSnapshot: Sendable {
    let documents: [SearchDocument]
    let revision: SearchItemRevision

    @MainActor
    init(items: [StowItem]) {
        documents = items.map(SearchDocument.init(item:))
        revision = SearchItemRevision(items: items)
    }

    init(documents: [SearchDocument]) {
        self.documents = documents
        revision = SearchItemRevision(documents: documents)
    }
}

actor SearchCoordinator {
    typealias RebuildOperation = @Sendable ([SearchDocument]) async throws -> Void
    typealias SearchOperation = @Sendable (SearchQuery) async throws -> [UUID]

    private let rebuildOperation: RebuildOperation
    private let searchOperation: SearchOperation
    private var indexedRevision: SearchItemRevision?
    private var operationInProgress = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []

    init(index: SQLiteSearchIndex) {
        rebuildOperation = { documents in
            try await index.rebuild(documents)
        }
        searchOperation = { query in
            try await index.search(query)
        }
    }

    init(
        rebuild: @escaping RebuildOperation,
        search: @escaping SearchOperation
    ) {
        rebuildOperation = rebuild
        searchOperation = search
    }

    func rebuild(_ snapshot: SearchSnapshot) async throws {
        await acquireExclusiveAccess()
        defer { releaseExclusiveAccess() }

        try await rebuildOperation(snapshot.documents)
        indexedRevision = snapshot.revision
    }

    func search(
        snapshot: SearchSnapshot,
        query: SearchQuery
    ) async throws -> (ids: [UUID], duration: Duration) {
        await acquireExclusiveAccess()
        defer { releaseExclusiveAccess() }

        if snapshot.revision != indexedRevision {
            try await rebuildOperation(snapshot.documents)
            indexedRevision = snapshot.revision
        }
        let started = ContinuousClock.now
        let ids = try await searchOperation(query)
        return (ids, started.duration(to: .now))
    }

    private func acquireExclusiveAccess() async {
        guard operationInProgress else {
            operationInProgress = true
            return
        }
        await withCheckedContinuation { continuation in
            operationWaiters.append(continuation)
        }
    }

    private func releaseExclusiveAccess() {
        guard !operationWaiters.isEmpty else {
            operationInProgress = false
            return
        }
        operationWaiters.removeFirst().resume()
    }
}

enum SearchQueryFactory {
    static func library(
        text: String,
        type: ItemType?,
        source: String?,
        date: DateAddedFilter,
        section: StowSection,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SearchQuery {
        filtered(
            text: text,
            type: type,
            source: source,
            date: date,
            status: status(for: section),
            now: now,
            calendar: calendar
        )
    }

    static func retrieval(
        text: String,
        type: ItemType?,
        source: String?,
        date: DateAddedFilter,
        status: ItemStatus?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SearchQuery {
        filtered(
            text: text,
            type: type,
            source: source,
            date: date,
            status: status,
            now: now,
            calendar: calendar
        )
    }

    static func automation(_ payload: StowAutomationSearchPayload) -> SearchQuery {
        SearchQuery(
            text: payload.query,
            type: payload.type,
            status: payload.status?.itemStatus,
            includeTrashed: payload.status == .all,
            limit: payload.limit
        )
    }

    static func addedAfter(
        for filter: DateAddedFilter,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        switch filter {
        case .anytime: nil
        case .today: calendar.startOfDay(for: now)
        case .week: calendar.date(byAdding: .day, value: -7, to: now)
        case .month: calendar.date(byAdding: .month, value: -1, to: now)
        }
    }

    static func status(for section: StowSection) -> ItemStatus? {
        switch section {
        case .inbox: .inbox
        case .archive: .archived
        case .trash: .trashed
        case .recent, .pinned, .settings: nil
        }
    }

    private static func filtered(
        text: String,
        type: ItemType?,
        source: String?,
        date: DateAddedFilter,
        status: ItemStatus?,
        now: Date,
        calendar: Calendar
    ) -> SearchQuery {
        SearchQuery(
            text: text,
            type: type,
            sourceApp: source,
            addedAfter: addedAfter(for: date, now: now, calendar: calendar),
            status: status,
            limit: 10_000
        )
    }
}
