import CryptoKit
import Foundation

public enum ClipboardFingerprintError: Error, Equatable {
    case missingAttachmentData
}

public struct ClipboardFingerprintRepresentation: Equatable, Sendable {
    public let typeIdentifier: String
    public let data: Data

    public init(typeIdentifier: String, data: Data) {
        self.typeIdentifier = typeIdentifier
        self.data = data
    }
}

public enum ClipboardContentFingerprint {
    public static let formatVersion = 1

    public static func make(
        draft: CaptureDraft,
        attachmentData: Data? = nil,
        auxiliaryRepresentations: [ClipboardFingerprintRepresentation] = []
    ) throws -> String {
        var stream = CanonicalByteStream()
        stream.append("stow.clipboard.fingerprint")
        stream.append(formatVersion)
        stream.append(draft.type.rawValue)

        switch draft.type {
        case .text:
            stream.append(normalizedText(try textPayload(draft)))
            append(auxiliaryRepresentations, to: &stream)
        case .code:
            stream.append(normalizedText(try textPayload(draft)))
            stream.append(draft.language?.lowercased() ?? "")
            append(auxiliaryRepresentations, to: &stream)
        case .link:
            stream.append(try draft.normalized().urlString ?? "")
        case .image:
            guard let attachmentData else { throw ClipboardFingerprintError.missingAttachmentData }
            stream.append(draft.contentType?.lowercased() ?? "application/octet-stream")
            stream.append(attachmentData)
        case .file:
            guard let attachmentData else { throw ClipboardFingerprintError.missingAttachmentData }
            stream.append(normalizedFilename(draft.fileName ?? draft.title))
            stream.append(attachmentData)
        }

        let digest = SHA256.hash(data: stream.data)
        return "v\(formatVersion):" + digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func make(
        item: StowItem,
        attachment: StowAttachment? = nil,
        auxiliaryRepresentations: [ClipboardFingerprintRepresentation] = []
    ) throws -> String {
        try make(
            draft: CaptureDraft(
                type: item.type,
                title: item.title,
                textContent: item.textContent,
                urlString: item.urlString,
                stagedAttachmentName: item.type == .image || item.type == .file ? item.fileName ?? "attachment" : nil,
                attachmentByteCount: attachment?.byteCount,
                contentType: attachment?.contentType,
                fileName: item.fileName,
                sourceApp: item.sourceApp,
                sourceDomain: item.sourceDomain,
                note: item.note,
                language: item.language,
                isPinned: item.isPinned,
                directlyArchive: item.status == .archived
            ),
            attachmentData: attachment?.data,
            auxiliaryRepresentations: auxiliaryRepresentations
        )
    }

    private static func append(
        _ representations: [ClipboardFingerprintRepresentation],
        to stream: inout CanonicalByteStream
    ) {
        stream.append(representations.count)
        for representation in representations {
            stream.append(representation.typeIdentifier)
            stream.append(representation.data)
        }
    }

    private static func textPayload(_ draft: CaptureDraft) throws -> String {
        guard let text = draft.textContent,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CaptureValidationError.missingText
        }
        return text
    }

    private static func normalizedText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .precomposedStringWithCanonicalMapping
    }

    private static func normalizedFilename(_ value: String) -> String {
        URL(fileURLWithPath: value).lastPathComponent.precomposedStringWithCanonicalMapping
    }
}

private struct CanonicalByteStream {
    private(set) var data = Data()

    mutating func append(_ value: Int) {
        var integer = UInt64(value).bigEndian
        withUnsafeBytes(of: &integer) { data.append(contentsOf: $0) }
    }

    mutating func append(_ value: String) {
        append(Data(value.utf8))
    }

    mutating func append(_ value: Data) {
        append(value.count)
        data.append(value)
    }
}

public enum ClipboardActivityOrdering {
    public static func activityDate(for item: StowItem) -> Date {
        max(item.lastCapturedAt ?? .distantPast, item.lastUsedAt ?? .distantPast, item.createdAt)
    }

    public static func sorted(_ items: [StowItem]) -> [StowItem] {
        items.sorted { lhs, rhs in
            let leftDate = activityDate(for: lhs)
            let rightDate = activityDate(for: rhs)
            if leftDate == rightDate { return lhs.id.uuidString < rhs.id.uuidString }
            return leftDate > rightDate
        }
    }
}
