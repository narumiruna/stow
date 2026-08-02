import Foundation
import UniformTypeIdentifiers

public struct CaptureProviderDescriptor: Equatable, Sendable {
    public var typeIdentifiers: [String]
    public var suggestedName: String?

    public init(typeIdentifiers: [String], suggestedName: String? = nil) {
        self.typeIdentifiers = typeIdentifiers
        self.suggestedName = suggestedName
    }
}

public enum CaptureRepresentationKind: String, Equatable, Sendable {
    case url
    case text
    case image
    case file
}

public struct CaptureRepresentationSelection: Equatable, Sendable {
    public var providerIndex: Int
    public var kind: CaptureRepresentationKind

    public init(providerIndex: Int, kind: CaptureRepresentationKind) {
        self.providerIndex = providerIndex
        self.kind = kind
    }
}

public enum CaptureRepresentationSelector {
    public static func select(_ providers: [CaptureProviderDescriptor]) -> CaptureRepresentationSelection? {
        if let index = providers.firstIndex(where: supportsWebURL) {
            return CaptureRepresentationSelection(providerIndex: index, kind: .url)
        }
        if let index = providers.firstIndex(where: { supports($0, type: .image) }) {
            return CaptureRepresentationSelection(providerIndex: index, kind: .image)
        }
        if let index = providers.firstIndex(where: isNamedFile) {
            return CaptureRepresentationSelection(providerIndex: index, kind: .file)
        }
        if let index = providers.firstIndex(where: { supports($0, type: .plainText) || supports($0, type: .utf8PlainText) }) {
            return CaptureRepresentationSelection(providerIndex: index, kind: .text)
        }
        if let index = providers.firstIndex(where: { supports($0, type: .data) || supports($0, type: .fileURL) }) {
            return CaptureRepresentationSelection(providerIndex: index, kind: .file)
        }
        return nil
    }

    private static func supportsWebURL(_ provider: CaptureProviderDescriptor) -> Bool {
        provider.typeIdentifiers.contains { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .url) && !type.conforms(to: .fileURL)
        }
    }

    private static func isNamedFile(_ provider: CaptureProviderDescriptor) -> Bool {
        guard let name = provider.suggestedName, !URL(fileURLWithPath: name).pathExtension.isEmpty else { return false }
        return supports(provider, type: .data) || supports(provider, type: .fileURL) || supports(provider, type: .item)
    }

    private static func supports(_ provider: CaptureProviderDescriptor, type expected: UTType) -> Bool {
        provider.typeIdentifiers.contains { UTType($0)?.conforms(to: expected) == true }
    }
}
