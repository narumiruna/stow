import Foundation

public struct PasteboardRepresentationCandidate: Equatable, Sendable {
    public let typeIdentifier: String
    public let data: Data

    public init(typeIdentifier: String, data: Data) {
        self.typeIdentifier = typeIdentifier
        self.data = data
    }
}

public struct PasteboardCanonicalAttachment: Equatable, Sendable {
    public let typeIdentifier: String
    public let data: Data
}

public struct PasteboardRepresentationSelectionResult: Equatable, Sendable {
    public let canonicalText: String?
    public let canonicalURL: String?
    public let canonicalAttachment: PasteboardCanonicalAttachment?
    public let representations: [StowRepresentationDraft]
}

public enum PasteboardRepresentationSelector {
    public static func select(
        _ candidates: [PasteboardRepresentationCandidate]
    ) throws -> PasteboardRepresentationSelectionResult {
        let safe = candidates.filter { candidate in
            guard StowRepresentationType.capturedAllowlist.contains(candidate.typeIdentifier),
                  let maximum = StowRepresentationLimits.maximumBytes(for: candidate.typeIdentifier),
                  !candidate.data.isEmpty,
                  candidate.data.count <= maximum else { return false }
            return isStructurallyValid(candidate)
        }
        var total = 0
        let withinTotal = safe.filter { candidate in
            guard total + candidate.data.count <= StowRepresentationLimits.totalBytes else { return false }
            total += candidate.data.count
            return true
        }

        let canonicalText = withinTotal
            .first { $0.typeIdentifier == StowRepresentationType.plainText }
            .flatMap { String(data: $0.data, encoding: .utf8) }
        let canonicalURL = withinTotal
            .first { $0.typeIdentifier == StowRepresentationType.url }
            .flatMap { String(data: $0.data, encoding: .utf8) }
        let image = withinTotal.first { $0.typeIdentifier == StowRepresentationType.png }
            ?? withinTotal.first { $0.typeIdentifier == StowRepresentationType.tiff }
        let representations: [StowRepresentationDraft] = withinTotal.enumerated().compactMap { index, candidate in
            guard StowRepresentationType.auxiliaryAllowlist.contains(candidate.typeIdentifier) else { return nil }
            return StowRepresentationDraft(
                typeIdentifier: candidate.typeIdentifier,
                data: candidate.data,
                ordinal: index
            )
        }
        return PasteboardRepresentationSelectionResult(
            canonicalText: canonicalText,
            canonicalURL: canonicalURL,
            canonicalAttachment: image.map { .init(typeIdentifier: $0.typeIdentifier, data: $0.data) },
            representations: representations
        )
    }

    private static func isStructurallyValid(_ candidate: PasteboardRepresentationCandidate) -> Bool {
        switch candidate.typeIdentifier {
        case StowRepresentationType.plainText,
             StowRepresentationType.html,
             StowRepresentationType.url:
            return String(data: candidate.data, encoding: .utf8) != nil
        case StowRepresentationType.rtf:
            return String(data: candidate.data, encoding: .utf8)?.hasPrefix("{\\rtf") == true
        case StowRepresentationType.png:
            return candidate.data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        case StowRepresentationType.tiff:
            return candidate.data.starts(with: [0x49, 0x49, 0x2A, 0x00])
                || candidate.data.starts(with: [0x4D, 0x4D, 0x00, 0x2A])
        default:
            return false
        }
    }
}

public enum PasteFormat: Equatable, Sendable {
    case original
    case plainText
}

public struct PastePayloadEntry: Equatable, Sendable {
    public let typeIdentifier: String
    public let data: Data

    public init(typeIdentifier: String, data: Data) {
        self.typeIdentifier = typeIdentifier
        self.data = data
    }
}

public struct PastePayload: Equatable, Sendable {
    public let entries: [PastePayloadEntry]

    public init(entries: [PastePayloadEntry]) {
        self.entries = entries
    }
}

public enum PastePayloadBuilder {
    public static func build(
        item: StowItem,
        attachment: StowAttachment? = nil,
        representations: [StowRepresentation],
        format: PasteFormat
    ) throws -> PastePayload {
        let string = (item.type == .link ? item.urlString : item.textContent) ?? item.title
        var entries: [PastePayloadEntry] = []
        switch item.type {
        case .text, .code, .link:
            entries.append(PastePayloadEntry(
                typeIdentifier: StowRepresentationType.plainText,
                data: Data(string.utf8)
            ))
        case .image:
            guard let attachment else { return PastePayload(entries: []) }
            let typeIdentifier = switch attachment.contentType.lowercased() {
            case "image/png": StowRepresentationType.png
            case "image/tiff": StowRepresentationType.tiff
            default: attachment.contentType
            }
            entries.append(PastePayloadEntry(
                typeIdentifier: typeIdentifier,
                data: attachment.data
            ))
        case .file:
            return PastePayload(entries: [])
        }

        if format == .original {
            let valid = representations
                .sorted { lhs, rhs in lhs.ordinal == rhs.ordinal ? lhs.id.uuidString < rhs.id.uuidString : lhs.ordinal < rhs.ordinal }
                .compactMap { representation -> PastePayloadEntry? in
                    let draft = StowRepresentationDraft(
                        typeIdentifier: representation.typeIdentifier,
                        data: representation.data,
                        ordinal: representation.ordinal
                    )
                    guard (try? StowRepresentationValidator.validate([draft])) != nil else { return nil }
                    return PastePayloadEntry(typeIdentifier: representation.typeIdentifier, data: representation.data)
                }
            entries.append(contentsOf: valid)
        }
        if !entries.isEmpty {
            entries.append(PastePayloadEntry(
                typeIdentifier: StowRepresentationType.stowOwned,
                data: Data("1".utf8)
            ))
        }
        return PastePayload(entries: entries)
    }
}
