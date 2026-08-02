import Foundation

public struct CaptureIngestionResult: Equatable, Sendable {
    public var ingested: Int = 0
    public var failures: [String] = []

    public init(ingested: Int = 0, failures: [String] = []) {
        self.ingested = ingested
        self.failures = failures
    }
}

private struct StagedCaptureEnvelope: Codable {
    let draft: CaptureDraft
    let capturedAt: Date
    let attachmentFileName: String?
}

@MainActor
public final class CaptureSpool {
    public let rootURL: URL
    private let pendingURL: URL
    private let quarantineURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(rootURL: URL, fileManager: FileManager = .default) throws {
        self.rootURL = rootURL.standardizedFileURL
        pendingURL = self.rootURL.appendingPathComponent("Pending", isDirectory: true)
        quarantineURL = self.rootURL.appendingPathComponent("Quarantine", isDirectory: true)
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        try fileManager.createDirectory(at: pendingURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: quarantineURL, withIntermediateDirectories: true)
    }

    public func stage(_ draft: CaptureDraft, attachmentURL: URL? = nil, at date: Date = Date()) throws {
        let normalized = try draft.normalized()
        if normalized.type == .image || normalized.type == .file {
            guard attachmentURL != nil else { throw CaptureValidationError.missingAttachment }
        }

        let stagingURL = rootURL.appendingPathComponent(".staging-\(normalized.id.uuidString)", isDirectory: true)
        let destinationURL = pendingURL.appendingPathComponent(normalized.id.uuidString, isDirectory: true)
        if fileManager.fileExists(atPath: destinationURL.path) { return }
        try? fileManager.removeItem(at: stagingURL)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)

        do {
            var attachmentFileName: String?
            if let attachmentURL {
                let byteCount = try attachmentURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard byteCount <= 100 * 1_024 * 1_024 else { throw CaptureValidationError.attachmentTooLarge }
                let safeExtension = attachmentURL.pathExtension.isEmpty ? "data" : attachmentURL.pathExtension.lowercased()
                let name = "attachment.\(safeExtension)"
                try fileManager.copyItem(at: attachmentURL, to: stagingURL.appendingPathComponent(name))
                attachmentFileName = name
            }
            let envelope = StagedCaptureEnvelope(draft: normalized, capturedAt: date, attachmentFileName: attachmentFileName)
            let manifest = try encoder.encode(envelope)
            try manifest.write(to: stagingURL.appendingPathComponent("manifest.json"), options: [.atomic])
            try fileManager.moveItem(at: stagingURL, to: destinationURL)
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }
    }

    public func pendingCount() throws -> Int {
        try pendingDirectories().count
    }

    public func ingestAll(into repository: StowRepository) -> CaptureIngestionResult {
        var result = CaptureIngestionResult()
        let directories: [URL]
        do {
            directories = try pendingDirectories()
        } catch {
            result.failures.append(error.localizedDescription)
            return result
        }

        for directory in directories {
            do {
                let manifest = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
                let envelope = try decoder.decode(StagedCaptureEnvelope.self, from: manifest)
                var attachment: (data: Data, name: String)?
                if let attachmentFileName = envelope.attachmentFileName {
                    let safeName = URL(fileURLWithPath: attachmentFileName).lastPathComponent
                    guard safeName == attachmentFileName else { throw CocoaError(.fileReadInvalidFileName) }
                    let attachmentURL = directory.appendingPathComponent(safeName)
                    let byteCount = try attachmentURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard byteCount <= 100 * 1_024 * 1_024 else { throw CaptureValidationError.attachmentTooLarge }
                    attachment = (try Data(contentsOf: attachmentURL, options: .mappedIfSafe), safeName)
                }
                let item = try repository.create(from: envelope.draft, at: envelope.capturedAt)
                if let attachment, try repository.attachments(itemID: item.id).isEmpty {
                    let imageInfo = AttachmentStore.imageInfo(attachment.data)
                    try repository.addAttachment(StowAttachment(
                        itemID: item.id,
                        data: attachment.data,
                        thumbnailData: imageInfo.thumbnail,
                        contentType: envelope.draft.contentType ?? "application/octet-stream",
                        fileName: envelope.draft.fileName ?? attachment.name,
                        pixelWidth: imageInfo.width,
                        pixelHeight: imageInfo.height,
                        createdAt: envelope.capturedAt
                    ))
                }
                try fileManager.removeItem(at: directory)
                result.ingested += 1
            } catch {
                result.failures.append("\(directory.lastPathComponent): \(error.localizedDescription)")
                quarantine(directory)
            }
        }
        return result
    }

    @discardableResult
    public func removeInterruptedStaging() throws -> Int {
        let children = try fileManager.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil)
        let interrupted = children.filter { $0.lastPathComponent.hasPrefix(".staging-") }
        for url in interrupted { try fileManager.removeItem(at: url) }
        return interrupted.count
    }

    private func pendingDirectories() throws -> [URL] {
        try fileManager.contentsOfDirectory(at: pendingURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func quarantine(_ directory: URL) {
        let destination = quarantineURL.appendingPathComponent("\(directory.lastPathComponent)-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.moveItem(at: directory, to: destination)
        } catch {
            try? fileManager.removeItem(at: directory)
        }
    }
}
