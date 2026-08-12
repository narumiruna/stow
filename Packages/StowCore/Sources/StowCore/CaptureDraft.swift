import Foundation

public enum CaptureValidationError: Error, Equatable, LocalizedError, Sendable {
    case missingText
    case invalidURL
    case missingAttachment
    case unsupportedRepresentation
    case attachmentTooLarge

    public var errorDescription: String? {
        switch self {
        case .missingText: "The shared text is empty."
        case .invalidURL: "The shared link is not a valid HTTP or HTTPS URL."
        case .missingAttachment: "The shared image or file is unavailable."
        case .unsupportedRepresentation: "Stow can save shared URLs, text, images, and files. This item does not provide a supported representation."
        case .attachmentTooLarge: "The attachment exceeds the 100 MB limit."
        }
    }
}

public struct CaptureDraft: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var type: ItemType
    public var title: String
    public var textContent: String?
    public var urlString: String?
    public var stagedAttachmentName: String?
    public var attachmentByteCount: Int?
    public var contentType: String?
    public var fileName: String?
    public var sourceApp: String?
    public var sourceDomain: String?
    public var note: String?
    public var language: String?
    public var isPinned: Bool
    public var directlyArchive: Bool

    public init(
        id: UUID = UUID(),
        type: ItemType,
        title: String,
        textContent: String? = nil,
        urlString: String? = nil,
        stagedAttachmentName: String? = nil,
        attachmentByteCount: Int? = nil,
        contentType: String? = nil,
        fileName: String? = nil,
        sourceApp: String? = nil,
        sourceDomain: String? = nil,
        note: String? = nil,
        language: String? = nil,
        isPinned: Bool = false,
        directlyArchive: Bool = false
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.textContent = textContent
        self.urlString = urlString
        self.stagedAttachmentName = stagedAttachmentName
        self.attachmentByteCount = attachmentByteCount
        self.contentType = contentType
        self.fileName = fileName
        self.sourceApp = sourceApp
        self.sourceDomain = sourceDomain
        self.note = note
        self.language = language
        self.isPinned = isPinned
        self.directlyArchive = directlyArchive
    }

    public func normalized(maxAttachmentBytes: Int = 100 * 1_024 * 1_024) throws -> CaptureDraft {
        var result = self
        result.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        result.note = Self.nilIfEmpty(note)
        result.language = Self.nilIfEmpty(language)?.lowercased()
        result.fileName = Self.nilIfEmpty(fileName)
        result.sourceApp = Self.nilIfEmpty(sourceApp)

        switch type {
        case .link:
            let value = urlString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let components = URLComponents(string: value),
                  let scheme = components.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let host = components.host, !host.isEmpty else {
                throw CaptureValidationError.invalidURL
            }
            result.urlString = components.url?.absoluteString ?? value
            result.sourceDomain = host.lowercased()
            if result.title.isEmpty { result.title = host }

        case .text, .code:
            let originalValue = textContent ?? ""
            let displayValue = originalValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !displayValue.isEmpty else { throw CaptureValidationError.missingText }
            result.textContent = originalValue
            if result.title.isEmpty {
                result.title = displayValue.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Text"
                if result.title.count > 80 { result.title = String(result.title.prefix(80)) }
            }

        case .image, .file:
            guard let stagedAttachmentName = Self.nilIfEmpty(stagedAttachmentName) else {
                throw CaptureValidationError.missingAttachment
            }
            if let count = attachmentByteCount, count > maxAttachmentBytes {
                throw CaptureValidationError.attachmentTooLarge
            }
            result.stagedAttachmentName = stagedAttachmentName
            if result.title.isEmpty { result.title = result.fileName ?? (type == .image ? "Image" : "File") }
        }

        return result
    }

    private static func nilIfEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
