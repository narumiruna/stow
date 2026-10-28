import Foundation
import StowCore

/// JSON values preserve explicit null fields and integer byte arrays.
public enum BridgeJSON: Codable, Sendable, Equatable {
    case object([String: BridgeJSON]), array([BridgeJSON]), string(String)
    case integer(Int64), bool(Bool), null

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int64.self) { self = .integer(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: BridgeJSON].self) { self = .object(v) }
        else { self = .array(try c.decode([BridgeJSON].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .integer(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    public subscript(_ key: String) -> BridgeJSON? {
        guard case .object(let o) = self else { return nil }
        return o[key]
    }
    public var string: String? { if case .string(let s) = self { s } else { nil } }
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(self))
    }
    func fields(_ allowed: Set<String>) throws {
        guard case .object(let o) = self, Set(o.keys).isSubset(of: allowed) else {
            throw BridgeFailure.invalid
        }
    }
    static func optional(_ s: String?) -> Self { s.map(Self.string) ?? .null }
    static func date(_ d: Date?) -> Self { optional(d.map(BridgeDate.string)) }
}

public struct BridgeCreateRequest: Decodable, Sendable {
    public let capture_id: UUID
    public let item_type: ItemType
    public let title: String
    public let text_content: String?
    public let url_string: String?
    public let note: String?
    public let source_app: String?
    public let language: String?
    public let is_pinned: Bool?
    public let directly_archive: Bool?
}
public struct BridgeEditRequest: Decodable, Sendable {
    public let title: String
    public let note: String?
    public let text_content: String?
    public let language: String?
}
public struct BridgeUpdateRequest: Decodable, Sendable {
    public let id: UUID
    public let expected_updated_at: String
    public let edit: BridgeEditRequest
}
public enum BridgeAction: String, Decodable, Sendable {
    case archive, restore_archive, trash, restore_trash, pin, unpin
}
public struct BridgeApplyRequest: Decodable, Sendable {
    public let id: UUID
    public let expected_updated_at: String
    public let command: BridgeAction
}
public struct BridgeSearchRequest: Decodable, Sendable {
    public let text: String?
    public let status: ItemStatus?
    public let item_type: ItemType?
    public let source_app: String?
    public let added_after: String?
    public let added_before: String?
    public let include_trashed: Bool?
    public let pinned_only: Bool?
    public let limit: Int?
}

/// UTC comparison at wire precision, without rounding an incoming boundary through Date.
struct BridgeTimestamp: Comparable, Sendable {
    let seconds: Int64
    let nanos: Int64

    init(_ date: Date) {
        let reference = date.timeIntervalSinceReferenceDate
        let whole = floor(reference)
        let fraction = Int64(((reference - whole) * 1_000_000_000).rounded())
        seconds = Int64(whole) + 978_307_200 + (fraction == 1_000_000_000 ? 1 : 0)
        nanos = fraction == 1_000_000_000 ? 0 : fraction
    }

    init(_ value: String) throws {
        guard value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-5][0-9](\.[0-9]{1,9})?(Z|[+-][0-9]{2}:[0-9]{2})$"#,
                          options: .regularExpression) != nil else { throw BridgeFailure.invalid }
        let prefix = String(value.prefix(19))
        let suffix = value.dropFirst(19)
        let fraction = suffix.hasPrefix(".") ? String(suffix.dropFirst().prefix(while: { $0.isNumber })) : ""
        let zone = String(suffix.dropFirst(fraction.isEmpty ? 0 : fraction.count + 1))
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: prefix + zone) else { throw BridgeFailure.invalid }
        seconds = Int64(date.timeIntervalSince1970.rounded())
        nanos = Int64(fraction + String(repeating: "0", count: 9 - fraction.count))!
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.seconds == rhs.seconds ? lhs.nanos < rhs.nanos : lhs.seconds < rhs.seconds
    }
}

/// Split before the epoch conversion. Adding the epoch as Double loses native bits.
public enum BridgeDate {
    public static func string(_ date: Date) -> String {
        let timestamp = BridgeTimestamp(date)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.string(from: Date(timeIntervalSince1970: Double(timestamp.seconds)))
            + String(format: ".%09lldZ", timestamp.nanos)
    }

    static func parse(_ value: String?) throws -> Date? {
        guard let value else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: value) { return d }
        f.formatOptions = [.withInternetDateTime]
        guard let d = f.date(from: value) else { throw BridgeFailure.invalid }
        return d
    }

    static func validateRevision(_ value: String) throws {
        guard value.utf8.count == 30,
              value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{9}Z$"#,
                          options: .regularExpression) != nil,
              (try? BridgeTimestamp(value)) != nil else { throw BridgeFailure.invalid }
    }

    static func next(after old: Date, now: Date = Date()) -> Date {
        Date(timeIntervalSinceReferenceDate: max(now.timeIntervalSinceReferenceDate,
                                               old.timeIntervalSinceReferenceDate.nextUp))
    }
}

struct BridgeFailure: Error, Sendable {
    let code: String
    let message: String
    let retryable: Bool
    static let invalid = Self(code: "invalid_argument", message: "Invalid bridge request.", retryable: false)
    static let version = Self(code: "unsupported_version", message: "Unsupported bridge version.", retryable: false)
    static let handle = Self(code: "invalid_handle", message: "Bridge handle is unavailable.", retryable: false)
    static let storage = Self(code: "storage", message: "Preview storage is unavailable.", retryable: true)
    static let index = Self(code: "index", message: "Search index is unavailable.", retryable: true)
    static let conflict = Self(code: "conflict", message: "Item revision has changed.", retryable: false)
    static let missing = Self(code: "not_found", message: "Item is unavailable.", retryable: false)
    static let unsupported = Self(code: "unsupported", message: "Operation is not supported.", retryable: false)
    var json: BridgeJSON {
        .object(["error": .object(["code": .string(code), "message": .string(message), "retryable": .bool(retryable)])])
    }
}

struct BridgeRequest: Sendable {
    let command: String
    let payload: BridgeJSON
    init(_ data: Data) throws {
        let value: BridgeJSON
        do { value = try JSONDecoder().decode(BridgeJSON.self, from: data) }
        catch { throw BridgeFailure.invalid }
        try value.fields(["version", "command", "payload"])
        guard case .integer(let version) = value["version"] else { throw BridgeFailure.invalid }
        guard version == 1 else { throw BridgeFailure.version }
        guard let command = value["command"]?.string, let payload = value["payload"] else {
            throw BridgeFailure.invalid
        }
        let fields: Set<String>
        switch command {
        case "open": fields = ["root"]
        case "get": fields = ["id"]
        case "search": fields = ["text", "status", "item_type", "source_app", "added_after", "added_before", "include_trashed", "pinned_only", "limit"]
        case "create": fields = ["capture_id", "item_type", "title", "text_content", "url_string", "note", "source_app", "language", "is_pinned", "directly_archive"]
        case "update":
            fields = ["id", "expected_updated_at", "edit"]
            guard let edit = payload["edit"] else { throw BridgeFailure.invalid }
            try edit.fields(["title", "note", "text_content", "language"])
        case "apply": fields = ["id", "expected_updated_at", "command"]
        case "rebuild", "close": fields = []
        default: throw BridgeFailure.invalid
        }
        try payload.fields(fields)
        // serde defaults apply to missing fields, not explicit null values.
        for key in ["is_pinned", "directly_archive", "include_trashed", "pinned_only"] {
            if let value = payload[key] {
                guard case .bool = value else { throw BridgeFailure.invalid }
            }
        }
        if command == "search", let value = payload["text"], value.string == nil {
            throw BridgeFailure.invalid
        }
        self.command = command
        self.payload = payload
    }
}
