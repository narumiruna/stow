import Foundation
import SQLite3

public struct SearchQuery: Equatable, Sendable {
    public var text: String
    public var type: ItemType?
    public var sourceApp: String?
    public var addedAfter: Date?
    public var addedBefore: Date?
    public var status: ItemStatus?
    public var limit: Int

    public init(
        text: String = "",
        type: ItemType? = nil,
        sourceApp: String? = nil,
        addedAfter: Date? = nil,
        addedBefore: Date? = nil,
        status: ItemStatus? = nil,
        limit: Int = 200
    ) {
        self.text = text
        self.type = type
        self.sourceApp = sourceApp
        self.addedAfter = addedAfter
        self.addedBefore = addedBefore
        self.status = status
        self.limit = max(1, min(limit, 10_000))
    }
}

public struct SearchIndexError: Error, LocalizedError, Sendable {
    public let operation: String
    public let message: String

    public var errorDescription: String? { "Search index \(operation) failed: \(message)" }
}

public actor SQLiteSearchIndex {
    nonisolated(unsafe) private var database: OpaquePointer?

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var opened: OpaquePointer?
        guard sqlite3_open_v2(url.path, &opened, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let opened else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database"
            sqlite3_close(opened)
            throw SearchIndexError(operation: "open", message: message)
        }
        database = opened
        do {
            try Self.execute(opened, sql: "PRAGMA journal_mode=WAL;")
            try Self.execute(opened, sql: "CREATE TABLE IF NOT EXISTS item_meta (id TEXT PRIMARY KEY NOT NULL, type TEXT NOT NULL, source_app TEXT, created_at REAL NOT NULL, status TEXT NOT NULL, is_pinned INTEGER NOT NULL, last_used_at REAL);")
            try Self.execute(opened, sql: "CREATE VIRTUAL TABLE IF NOT EXISTS item_fts USING fts5(id UNINDEXED, content, tokenize='unicode61 remove_diacritics 2');")
        } catch {
            sqlite3_close(opened)
            database = nil
            throw error
        }
    }

    deinit {
        sqlite3_close(database)
    }

    public func rebuild(_ documents: [SearchDocument]) throws {
        try transaction {
            try execute("DELETE FROM item_fts;")
            try execute("DELETE FROM item_meta;")
            for document in documents { try insert(document) }
        }
    }

    public func upsert(_ document: SearchDocument) throws {
        try transaction {
            try delete(id: document.id)
            try insert(document)
        }
    }

    public func remove(id: UUID) throws {
        try transaction { try delete(id: id) }
    }

    public func search(_ query: SearchQuery) throws -> [UUID] {
        let match = Self.matchExpression(query.text)
        var clauses: [String] = []
        var values: [SQLiteValue] = []

        if let match {
            clauses.append("item_fts MATCH ?")
            values.append(.text(match))
        }
        if let type = query.type {
            clauses.append("m.type = ?")
            values.append(.text(type.rawValue))
        }
        if let sourceApp = query.sourceApp, !sourceApp.isEmpty {
            clauses.append("m.source_app = ? COLLATE NOCASE")
            values.append(.text(sourceApp))
        }
        if let addedAfter = query.addedAfter {
            clauses.append("m.created_at >= ?")
            values.append(.double(addedAfter.timeIntervalSince1970))
        }
        if let addedBefore = query.addedBefore {
            clauses.append("m.created_at <= ?")
            values.append(.double(addedBefore.timeIntervalSince1970))
        }
        if let status = query.status {
            clauses.append("m.status = ?")
            values.append(.text(status.rawValue))
        } else {
            clauses.append("m.status != ?")
            values.append(.text(ItemStatus.trashed.rawValue))
        }

        var sql = "SELECT m.id FROM item_meta m"
        if match != nil { sql += " JOIN item_fts ON item_fts.id = m.id" }
        if !clauses.isEmpty { sql += " WHERE " + clauses.joined(separator: " AND ") }
        sql += match == nil ? " ORDER BY m.created_at DESC, m.id ASC" : " ORDER BY bm25(item_fts), m.created_at DESC, m.id ASC"
        sql += " LIMIT ?;"
        values.append(.integer(Int64(query.limit)))

        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)
        var result: [UUID] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let raw = sqlite3_column_text(statement, 0), let id = UUID(uuidString: String(cString: raw)) else { continue }
            result.append(id)
        }
        try ensureFinished(statement, operation: "query")
        return result
    }

    public func documentCount() throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM item_meta;")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { try ensureFinished(statement, operation: "count"); return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func insert(_ document: SearchDocument) throws {
        let metadata = try prepare("INSERT INTO item_meta (id, type, source_app, created_at, status, is_pinned, last_used_at) VALUES (?, ?, ?, ?, ?, ?, ?);")
        defer { sqlite3_finalize(metadata) }
        try bind([
            .text(document.id.uuidString), .text(document.type.rawValue), document.sourceApp.map(SQLiteValue.text) ?? .null,
            .double(document.createdAt.timeIntervalSince1970), .text(document.status.rawValue), .integer(document.isPinned ? 1 : 0),
            document.lastUsedAt.map { .double($0.timeIntervalSince1970) } ?? .null,
        ], to: metadata)
        guard sqlite3_step(metadata) == SQLITE_DONE else { throw currentError("insert metadata") }

        let fulltext = try prepare("INSERT INTO item_fts (id, content) VALUES (?, ?);")
        defer { sqlite3_finalize(fulltext) }
        try bind([.text(document.id.uuidString), .text(document.content)], to: fulltext)
        guard sqlite3_step(fulltext) == SQLITE_DONE else { throw currentError("insert full text") }
    }

    private func delete(id: UUID) throws {
        for sql in ["DELETE FROM item_fts WHERE id = ?;", "DELETE FROM item_meta WHERE id = ?;"] {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }
            try bind([.text(id.uuidString)], to: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw currentError("delete") }
        }
    }

    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            try body()
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let database else { throw SearchIndexError(operation: "prepare", message: "Database is closed") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw currentError("prepare") }
        return statement
    }

    private func execute(_ sql: String) throws {
        guard let database else { throw SearchIndexError(operation: "execute", message: "Database is closed") }
        try Self.execute(database, sql: sql)
    }

    private static func execute(_ database: OpaquePointer, sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw SearchIndexError(operation: "execute", message: message)
        }
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .text(let value): result = sqlite3_bind_text(statement, index, value, -1, transient)
            case .double(let value): result = sqlite3_bind_double(statement, index, value)
            case .integer(let value): result = sqlite3_bind_int64(statement, index, value)
            case .null: result = sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else { throw currentError("bind") }
        }
    }

    private func ensureFinished(_ statement: OpaquePointer, operation: String) throws {
        let code = sqlite3_errcode(database)
        if code != SQLITE_OK && code != SQLITE_DONE && code != SQLITE_ROW { throw currentError(operation) }
    }

    private func currentError(_ operation: String) -> SearchIndexError {
        SearchIndexError(operation: operation, message: database.map { String(cString: sqlite3_errmsg($0)) } ?? "Database is closed")
    }

    private static func matchExpression(_ text: String) -> String? {
        let tokens = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " AND ")
    }
}

private enum SQLiteValue {
    case text(String)
    case double(Double)
    case integer(Int64)
    case null
}
