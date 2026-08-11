import Foundation

public enum StowAutomationProtocol {
    public static let schemaVersion = 1

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .custom { codingPath in
            let source = codingPath.last?.stringValue ?? ""
            let parts = source.split(separator: "_")
            guard let first = parts.first else { return AutomationCodingKey(source) }
            var result = String(first)
            for part in parts.dropFirst() {
                result += part.prefix(1).uppercased() + part.dropFirst()
            }
            if result.hasSuffix("Id") {
                result = String(result.dropLast(2)) + "ID"
            }
            return AutomationCodingKey(result)
        }
        return decoder
    }
}

private struct AutomationCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        return nil
    }
}

public enum StowAutomationCommand: String, Codable, CaseIterable, Sendable {
    case status
    case search
    case get
    case add
    case export
}

public enum StowAutomationStatusFilter: String, Codable, CaseIterable, Sendable {
    case inbox
    case archived
    case trashed
    case all

    public var itemStatus: ItemStatus? {
        switch self {
        case .inbox: .inbox
        case .archived: .archived
        case .trashed: .trashed
        case .all: nil
        }
    }
}

public struct StowAutomationSearchPayload: Codable, Equatable, Sendable {
    public var query: String
    public var status: StowAutomationStatusFilter?
    public var type: ItemType?
    public var limit: Int

    public init(query: String, status: StowAutomationStatusFilter? = nil, type: ItemType? = nil, limit: Int = 20) {
        self.query = query
        self.status = status
        self.type = type
        self.limit = max(1, min(limit, 10_000))
    }
}

public struct StowAutomationGetPayload: Codable, Equatable, Sendable {
    public var itemID: UUID

    public init(itemID: UUID) {
        self.itemID = itemID
    }
}

public struct StowAutomationAddPayload: Codable, Equatable, Sendable {
    public var draft: CaptureDraft

    public init(draft: CaptureDraft) {
        self.draft = draft
    }
}

public struct StowAutomationExportPayload: Codable, Equatable, Sendable {
    public var itemID: UUID
    public var attachmentID: UUID?

    public init(itemID: UUID, attachmentID: UUID? = nil) {
        self.itemID = itemID
        self.attachmentID = attachmentID
    }
}

public struct StowAutomationRequest: Codable, Equatable, Identifiable, Sendable {
    public var schemaVersion: Int
    public var requestID: UUID
    public var createdAt: Date
    public var command: StowAutomationCommand
    public var search: StowAutomationSearchPayload?
    public var get: StowAutomationGetPayload?
    public var add: StowAutomationAddPayload?
    public var export: StowAutomationExportPayload?

    public var id: UUID { requestID }

    public init(
        requestID: UUID = UUID(),
        createdAt: Date = Date(),
        command: StowAutomationCommand,
        search: StowAutomationSearchPayload? = nil,
        get: StowAutomationGetPayload? = nil,
        add: StowAutomationAddPayload? = nil,
        export: StowAutomationExportPayload? = nil,
        schemaVersion: Int = StowAutomationProtocol.schemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.createdAt = createdAt
        self.command = command
        self.search = search
        self.get = get
        self.add = add
        self.export = export
    }
}

public struct StowAutomationAttachment: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var contentType: String
    public var fileName: String
    public var byteCount: Int
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var createdAt: Date

    public init(
        id: UUID,
        contentType: String,
        fileName: String,
        byteCount: Int,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.contentType = contentType
        self.fileName = fileName
        self.byteCount = byteCount
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.createdAt = createdAt
    }
}

public struct StowAutomationItemSummary: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var type: ItemType
    public var title: String
    public var snippet: String?
    public var sourceApp: String?
    public var sourceDomain: String?
    public var status: ItemStatus
    public var isPinned: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var attachmentCount: Int

    public init(
        id: UUID,
        type: ItemType,
        title: String,
        snippet: String? = nil,
        sourceApp: String? = nil,
        sourceDomain: String? = nil,
        status: ItemStatus,
        isPinned: Bool,
        createdAt: Date,
        updatedAt: Date,
        attachmentCount: Int
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.snippet = snippet
        self.sourceApp = sourceApp
        self.sourceDomain = sourceDomain
        self.status = status
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.attachmentCount = attachmentCount
    }
}

public struct StowAutomationItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var captureID: UUID
    public var type: ItemType
    public var title: String
    public var textContent: String?
    public var urlString: String?
    public var fileName: String?
    public var sourceApp: String?
    public var sourceDomain: String?
    public var note: String?
    public var language: String?
    public var linkDescription: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var lastUsedAt: Date?
    public var useCount: Int
    public var status: ItemStatus
    public var isPinned: Bool
    public var attachments: [StowAutomationAttachment]

    public init(
        id: UUID,
        captureID: UUID,
        type: ItemType,
        title: String,
        textContent: String? = nil,
        urlString: String? = nil,
        fileName: String? = nil,
        sourceApp: String? = nil,
        sourceDomain: String? = nil,
        note: String? = nil,
        language: String? = nil,
        linkDescription: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        lastUsedAt: Date? = nil,
        useCount: Int,
        status: ItemStatus,
        isPinned: Bool,
        attachments: [StowAutomationAttachment]
    ) {
        self.id = id
        self.captureID = captureID
        self.type = type
        self.title = title
        self.textContent = textContent
        self.urlString = urlString
        self.fileName = fileName
        self.sourceApp = sourceApp
        self.sourceDomain = sourceDomain
        self.note = note
        self.language = language
        self.linkDescription = linkDescription
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
        self.status = status
        self.isPinned = isPinned
        self.attachments = attachments
    }
}

public struct StowAutomationHostStatus: Codable, Equatable, Sendable {
    public var hostVersion: String
    public var storage: String

    public init(hostVersion: String, storage: String) {
        self.hostVersion = hostVersion
        self.storage = storage
    }
}

public struct StowAutomationExport: Codable, Equatable, Sendable {
    public var itemID: UUID
    public var attachment: StowAutomationAttachment
    public var path: String

    public init(itemID: UUID, attachment: StowAutomationAttachment, path: String) {
        self.itemID = itemID
        self.attachment = attachment
        self.path = path
    }
}

public struct StowAutomationResult: Codable, Equatable, Sendable {
    public var status: StowAutomationHostStatus?
    public var items: [StowAutomationItemSummary]?
    public var item: StowAutomationItem?
    public var export: StowAutomationExport?

    public init(
        status: StowAutomationHostStatus? = nil,
        items: [StowAutomationItemSummary]? = nil,
        item: StowAutomationItem? = nil,
        export: StowAutomationExport? = nil
    ) {
        self.status = status
        self.items = items
        self.item = item
        self.export = export
    }
}

public enum StowAutomationErrorCode: String, Codable, Sendable {
    case invalidRequest = "invalid_request"
    case unsupportedVersion = "unsupported_version"
    case itemNotFound = "item_not_found"
    case attachmentNotFound = "attachment_not_found"
    case attachmentSelectionRequired = "attachment_selection_required"
    case validationFailed = "validation_failed"
    case hostUnavailable = "host_unavailable"
    case timeout
    case ioFailure = "io_failure"
    case internalFailure = "internal_failure"
}

public struct StowAutomationError: Codable, Equatable, Error, Sendable {
    public var code: StowAutomationErrorCode
    public var message: String
    public var retryable: Bool
    public var fallbackPath: String?

    public init(
        code: StowAutomationErrorCode,
        message: String,
        retryable: Bool = false,
        fallbackPath: String? = nil
    ) {
        self.code = code
        self.message = message
        self.retryable = retryable
        self.fallbackPath = fallbackPath
    }
}

public struct StowAutomationResponse: Codable, Equatable, Identifiable, Sendable {
    public var schemaVersion: Int
    public var requestID: UUID
    public var finishedAt: Date
    public var ok: Bool
    public var data: StowAutomationResult?
    public var error: StowAutomationError?

    public var id: UUID { requestID }

    public init(
        requestID: UUID,
        finishedAt: Date = Date(),
        data: StowAutomationResult,
        schemaVersion: Int = StowAutomationProtocol.schemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.finishedAt = finishedAt
        ok = true
        self.data = data
        error = nil
    }

    public init(
        requestID: UUID,
        finishedAt: Date = Date(),
        error: StowAutomationError,
        schemaVersion: Int = StowAutomationProtocol.schemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.finishedAt = finishedAt
        ok = false
        data = nil
        self.error = error
    }
}
