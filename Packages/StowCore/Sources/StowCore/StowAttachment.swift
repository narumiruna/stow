import Foundation
import SwiftData

@Model
public final class StowAttachment {
    public var id: UUID = UUID()
    public var itemID: UUID = UUID()
    @Attribute(.externalStorage) public var data: Data = Data()
    @Attribute(.externalStorage) public var thumbnailData: Data?
    public var contentType: String = "application/octet-stream"
    public var fileName: String = "Attachment"
    public var byteCount: Int = 0
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var createdAt: Date = Date()

    public init(
        id: UUID = UUID(),
        itemID: UUID,
        data: Data,
        thumbnailData: Data? = nil,
        contentType: String,
        fileName: String,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.itemID = itemID
        self.data = data
        self.thumbnailData = thumbnailData
        self.contentType = contentType
        self.fileName = URL(fileURLWithPath: fileName).lastPathComponent
        self.byteCount = data.count
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.createdAt = createdAt
    }
}
