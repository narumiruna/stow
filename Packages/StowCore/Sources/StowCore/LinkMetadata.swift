import Foundation

public struct LinkMetadata: Equatable, Sendable {
    public var title: String?
    public var description: String?
    public var domain: String?
    public var faviconData: Data?
    public var previewImageData: Data?

    public init(title: String? = nil, description: String? = nil, domain: String? = nil, faviconData: Data? = nil, previewImageData: Data? = nil) {
        self.title = title
        self.description = description
        self.domain = domain
        self.faviconData = faviconData
        self.previewImageData = previewImageData
    }
}
