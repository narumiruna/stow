import Foundation
import SwiftData

public enum StowRepresentationType {
    public static let plainText = "public.utf8-plain-text"
    public static let rtf = "public.rtf"
    public static let html = "public.html"
    public static let url = "public.url"
    public static let png = "public.png"
    public static let tiff = "public.tiff"
    public static let fileURL = "public.file-url"
    public static let stowOwned = "dev.narumi.stow.owned-content"

    public static let auxiliaryAllowlist: Set<String> = [rtf, html, url]
    public static let capturedAllowlist: Set<String> = [plainText, rtf, html, url, png, tiff]
}

public enum StowRepresentationLimits {
    public static let plainTextBytes = 1 * 1_024 * 1_024
    public static let richTextBytes = 5 * 1_024 * 1_024
    public static let urlBytes = 16 * 1_024
    public static let imageBytes = 100 * 1_024 * 1_024
    public static let totalBytes = 110 * 1_024 * 1_024

    public static func maximumBytes(for typeIdentifier: String) -> Int? {
        switch typeIdentifier {
        case StowRepresentationType.plainText: plainTextBytes
        case StowRepresentationType.rtf, StowRepresentationType.html: richTextBytes
        case StowRepresentationType.url: urlBytes
        case StowRepresentationType.png, StowRepresentationType.tiff: imageBytes
        default: nil
        }
    }
}

public enum StowRepresentationError: Error, Equatable, LocalizedError {
    case unsupportedType(String)
    case duplicateType(String)
    case emptyData(String)
    case invalidOrdinal(Int)
    case representationTooLarge(String)
    case totalTooLarge

    public var errorDescription: String? {
        switch self {
        case .unsupportedType: "The clipboard format is not supported."
        case .duplicateType: "The clipboard format appears more than once."
        case .emptyData: "The clipboard format is empty."
        case .invalidOrdinal: "The clipboard format order is invalid."
        case .representationTooLarge: "The clipboard format exceeds its storage limit."
        case .totalTooLarge: "The preserved clipboard formats exceed the total storage limit."
        }
    }
}

public struct StowRepresentationDraft: Equatable, Sendable {
    public let typeIdentifier: String
    public let data: Data
    public let ordinal: Int

    public init(typeIdentifier: String, data: Data, ordinal: Int) {
        self.typeIdentifier = typeIdentifier
        self.data = data
        self.ordinal = ordinal
    }
}

public enum StowRepresentationValidator {
    public static func validate(
        _ representations: [StowRepresentationDraft],
        requireAuxiliary: Bool = true
    ) throws {
        var seen = Set<String>()
        var ordinals = Set<Int>()
        var total = 0
        for representation in representations {
            let allowed = requireAuxiliary
                ? StowRepresentationType.auxiliaryAllowlist
                : StowRepresentationType.capturedAllowlist
            guard allowed.contains(representation.typeIdentifier) else {
                throw StowRepresentationError.unsupportedType(representation.typeIdentifier)
            }
            guard seen.insert(representation.typeIdentifier).inserted else {
                throw StowRepresentationError.duplicateType(representation.typeIdentifier)
            }
            guard !representation.data.isEmpty else {
                throw StowRepresentationError.emptyData(representation.typeIdentifier)
            }
            guard representation.ordinal >= 0,
                  ordinals.insert(representation.ordinal).inserted else {
                throw StowRepresentationError.invalidOrdinal(representation.ordinal)
            }
            guard let maximum = StowRepresentationLimits.maximumBytes(for: representation.typeIdentifier),
                  representation.data.count <= maximum else {
                throw StowRepresentationError.representationTooLarge(representation.typeIdentifier)
            }
            total += representation.data.count
            guard total <= StowRepresentationLimits.totalBytes else {
                throw StowRepresentationError.totalTooLarge
            }
        }
    }
}

extension StowSchemaV2 {
    @Model
    public final class StowRepresentation {
        public var id: UUID = UUID()
        public var itemID: UUID = UUID()
        public var typeIdentifier: String = StowRepresentationType.plainText
        @Attribute(.externalStorage) public var data: Data = Data()
        public var byteCount: Int = 0
        public var ordinal: Int = 0
        public var createdAt: Date = Date()

        public init(
            id: UUID = UUID(),
            itemID: UUID,
            typeIdentifier: String,
            data: Data,
            ordinal: Int,
            createdAt: Date = Date()
        ) {
            self.id = id
            self.itemID = itemID
            self.typeIdentifier = typeIdentifier
            self.data = data
            byteCount = data.count
            self.ordinal = ordinal
            self.createdAt = createdAt
        }
    }
}

public typealias StowRepresentation = StowSchemaV2.StowRepresentation
