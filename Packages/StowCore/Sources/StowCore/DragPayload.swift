import Foundation

public struct DragPayload: Equatable, Sendable {
    public let data: Data
    public let typeIdentifier: String
    public let suggestedName: String?

    public init(item: StowItem, attachment: StowAttachment? = nil) {
        if let attachment {
            data = attachment.data
            typeIdentifier = attachment.contentType
            suggestedName = attachment.fileName
        } else if item.type == .link, let url = item.urlString {
            data = Data(url.utf8)
            typeIdentifier = "public.url"
            suggestedName = nil
        } else {
            data = Data((item.textContent ?? item.title).utf8)
            typeIdentifier = "public.utf8-plain-text"
            suggestedName = nil
        }
    }
}
