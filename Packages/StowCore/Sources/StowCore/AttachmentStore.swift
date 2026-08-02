import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct AttachmentImageInfo: Equatable, Sendable {
    public var thumbnail: Data?
    public var width: Int?
    public var height: Int?

    public init(thumbnail: Data?, width: Int?, height: Int?) {
        self.thumbnail = thumbnail
        self.width = width
        self.height = height
    }
}

public enum AttachmentStoreError: Error, Equatable, LocalizedError, Sendable {
    case attachmentTooLarge
    case unreadableFile

    public var errorDescription: String? {
        switch self {
        case .attachmentTooLarge: "The attachment exceeds the allowed size."
        case .unreadableFile: "The attachment could not be read."
        }
    }
}

@MainActor
public final class AttachmentStore {
    private let repository: StowRepository
    private let temporaryDirectory: URL
    private let maxBytes: Int
    private let fileManager: FileManager

    public init(repository: StowRepository, temporaryDirectory: URL, maxBytes: Int = 100 * 1_024 * 1_024, fileManager: FileManager = .default) {
        self.repository = repository
        self.temporaryDirectory = temporaryDirectory
        self.maxBytes = maxBytes
        self.fileManager = fileManager
    }

    @discardableResult
    public func importFile(itemID: UUID, sourceURL: URL, contentType: String, fileName: String) throws -> StowAttachment {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
        guard let handle = try? FileHandle(forReadingFrom: sourceURL) else { throw AttachmentStoreError.unreadableFile }
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: 1_024 * 1_024), !chunk.isEmpty {
            guard data.count <= maxBytes - chunk.count else { throw AttachmentStoreError.attachmentTooLarge }
            data.append(chunk)
        }
        let imageInfo = Self.imageInfo(data)
        let attachment = StowAttachment(
            itemID: itemID,
            data: data,
            thumbnailData: imageInfo.thumbnail,
            contentType: contentType,
            fileName: URL(fileURLWithPath: fileName).lastPathComponent,
            pixelWidth: imageInfo.width,
            pixelHeight: imageInfo.height
        )
        try repository.addAttachment(attachment)
        return attachment
    }

    public func materialize(_ attachment: StowAttachment) throws -> URL {
        let directory = temporaryDirectory.appendingPathComponent(attachment.id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeName = URL(fileURLWithPath: attachment.fileName).lastPathComponent
        guard !safeName.isEmpty else { throw AttachmentStoreError.unreadableFile }
        let destination = directory.appendingPathComponent(safeName)
        try attachment.data.write(to: destination, options: .atomic)
        return destination
    }

    @discardableResult
    public func removeTemporaryFiles(olderThan age: TimeInterval = 86_400, now: Date = Date()) throws -> Int {
        guard fileManager.fileExists(atPath: temporaryDirectory.path) else { return 0 }
        let children = try fileManager.contentsOfDirectory(at: temporaryDirectory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
        var removed = 0
        for child in children {
            let modified = try child.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            if now.timeIntervalSince(modified) >= age {
                try fileManager.removeItem(at: child)
                removed += 1
            }
        }
        return removed
    }

    public static func imageInfo(_ data: Data) -> AttachmentImageInfo {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return AttachmentImageInfo(thumbnail: nil, width: nil, height: nil) }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int
        let height = properties?[kCGImagePropertyPixelHeight] as? Int
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return AttachmentImageInfo(thumbnail: nil, width: width, height: height) }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return AttachmentImageInfo(thumbnail: nil, width: width, height: height) }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.78] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return AttachmentImageInfo(thumbnail: nil, width: width, height: height) }
        return AttachmentImageInfo(thumbnail: output as Data, width: width, height: height)
    }
}
