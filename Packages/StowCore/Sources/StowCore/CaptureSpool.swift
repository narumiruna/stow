import Foundation

public enum CaptureSpoolIngestionOutcome: Equatable, Sendable {
    case ingested(captureID: UUID)
    case quarantined(captureID: UUID?, source: String, message: String)
    case deferred(captureID: UUID?, source: String, message: String)
}

public struct CaptureIngestionResult: Equatable, Sendable {
    public var ingested: Int
    public var failures: [String]
    public var outcomes: [CaptureSpoolIngestionOutcome]

    public init(
        ingested: Int = 0,
        failures: [String] = [],
        outcomes: [CaptureSpoolIngestionOutcome] = []
    ) {
        self.ingested = ingested
        self.failures = failures
        self.outcomes = outcomes
    }

    public static func == (lhs: CaptureIngestionResult, rhs: CaptureIngestionResult) -> Bool {
        lhs.ingested == rhs.ingested && lhs.failures == rhs.failures
    }

    fileprivate mutating func append(_ outcome: CaptureSpoolIngestionOutcome) {
        outcomes.append(outcome)
        switch outcome {
        case .ingested:
            ingested += 1
        case .quarantined(_, let source, let message), .deferred(_, let source, let message):
            failures.append("\(source): \(message)")
        }
    }

    fileprivate mutating func appendFailure(_ message: String) {
        failures.append(message)
    }
}

public enum CaptureIngestionIntent: String, Codable, Equatable, Sendable {
    case createNew
    case coalesceClipboard
}

private struct StagedRepresentationDescriptor: Codable {
    let typeIdentifier: String
    let fileName: String
    let byteCount: Int
    let ordinal: Int
}

private struct StagedCaptureEnvelope: Codable {
    let draft: CaptureDraft
    let capturedAt: Date
    let attachmentFileName: String?
    let ingestionIntent: CaptureIngestionIntent?
    let representations: [StagedRepresentationDescriptor]?
}

private struct LoadedCapture {
    let draft: CaptureDraft
    let capturedAt: Date
    let attachmentData: Data?
    let representations: [StowRepresentationDraft]
    let ingestionIntent: CaptureIngestionIntent
}

private struct InvalidCapturePayload: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
public final class CaptureSpool {
    public static let defaultStagingExpiration: TimeInterval = 24 * 60 * 60

    public let rootURL: URL
    private let pendingURL: URL
    private let quarantineURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let now: () -> Date
    private let stagingExpiration: TimeInterval
    private let quarantineMove: ((URL, URL) throws -> Void)?

    public init(
        rootURL: URL,
        fileManager: FileManager = .default,
        stagingExpiration: TimeInterval = CaptureSpool.defaultStagingExpiration,
        now: @escaping () -> Date = Date.init,
        quarantineMove: ((URL, URL) throws -> Void)? = nil
    ) throws {
        self.rootURL = rootURL.standardizedFileURL
        pendingURL = self.rootURL.appendingPathComponent("Pending", isDirectory: true)
        quarantineURL = self.rootURL.appendingPathComponent("Quarantine", isDirectory: true)
        self.fileManager = fileManager
        self.stagingExpiration = stagingExpiration
        self.now = now
        self.quarantineMove = quarantineMove
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        try fileManager.createDirectory(at: pendingURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: quarantineURL, withIntermediateDirectories: true)
    }

    public func stage(
        _ draft: CaptureDraft,
        attachmentURL: URL? = nil,
        representations: [StowRepresentationDraft] = [],
        intent: CaptureIngestionIntent = .createNew,
        at date: Date = Date()
    ) throws {
        let normalized = try draft.normalized()
        try StowRepresentationValidator.validate(representations)
        if normalized.type == .image || normalized.type == .file {
            guard attachmentURL != nil else { throw CaptureValidationError.missingAttachment }
        }

        let stagingURL = rootURL.appendingPathComponent(
            ".staging-\(normalized.id.uuidString)-\(UUID().uuidString)",
            isDirectory: true
        )
        let destinationURL = pendingURL.appendingPathComponent(normalized.id.uuidString, isDirectory: true)
        if fileManager.fileExists(atPath: destinationURL.path) { return }
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
            var representationDescriptors: [StagedRepresentationDescriptor] = []
            for representation in representations {
                let fileName = "representation-\(representation.ordinal).data"
                try representation.data.write(
                    to: stagingURL.appendingPathComponent(fileName),
                    options: [.atomic]
                )
                representationDescriptors.append(StagedRepresentationDescriptor(
                    typeIdentifier: representation.typeIdentifier,
                    fileName: fileName,
                    byteCount: representation.data.count,
                    ordinal: representation.ordinal
                ))
            }
            let envelope = StagedCaptureEnvelope(
                draft: normalized,
                capturedAt: date,
                attachmentFileName: attachmentFileName,
                ingestionIntent: intent == .createNew ? nil : intent,
                representations: representationDescriptors.isEmpty ? nil : representationDescriptors
            )
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
            result.appendFailure(error.localizedDescription)
            return result
        }

        for directory in directories {
            result.append(ingest(directory: directory, into: repository))
        }
        return result
    }

    public func ingest(captureID: UUID, into repository: StowRepository) -> CaptureIngestionResult {
        let directory = pendingURL.appendingPathComponent(captureID.uuidString, isDirectory: true)
        var result = CaptureIngestionResult()
        guard fileManager.fileExists(atPath: directory.path) else {
            result.append(.deferred(
                captureID: captureID,
                source: captureID.uuidString,
                message: "The pending capture could not be found."
            ))
            return result
        }
        result.append(ingest(directory: directory, into: repository))
        return result
    }

    @discardableResult
    public func removeInterruptedStaging() throws -> Int {
        let children = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )
        let expirationDate = now().addingTimeInterval(-stagingExpiration)
        let interrupted = try children.filter { url in
            guard url.lastPathComponent.hasPrefix(".staging-") else { return false }
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
            guard let modificationDate = values.contentModificationDate else { return false }
            return modificationDate <= expirationDate
        }
        for url in interrupted { try fileManager.removeItem(at: url) }
        return interrupted.count
    }

    private func ingest(directory: URL, into repository: StowRepository) -> CaptureSpoolIngestionOutcome {
        let source = directory.lastPathComponent
        let sourceCaptureID = UUID(uuidString: source)
        let loaded: LoadedCapture
        do {
            loaded = try loadCapture(from: directory)
        } catch let error as InvalidCapturePayload {
            do {
                try quarantine(directory)
                return .quarantined(
                    captureID: sourceCaptureID,
                    source: source,
                    message: error.localizedDescription
                )
            } catch {
                return .deferred(
                    captureID: sourceCaptureID,
                    source: source,
                    message: "Invalid capture was preserved because quarantine failed: \(error.localizedDescription)"
                )
            }
        } catch {
            return .deferred(
                captureID: sourceCaptureID,
                source: source,
                message: error.localizedDescription
            )
        }

        do {
            switch loaded.ingestionIntent {
            case .createNew:
                _ = try repository.create(
                    from: loaded.draft,
                    attachmentData: loaded.attachmentData,
                    representations: loaded.representations,
                    at: loaded.capturedAt
                )
            case .coalesceClipboard:
                _ = try repository.ingestClipboard(
                    loaded.draft,
                    attachmentData: loaded.attachmentData,
                    representations: loaded.representations,
                    at: loaded.capturedAt
                )
            }
            try fileManager.removeItem(at: directory)
            return .ingested(captureID: loaded.draft.id)
        } catch {
            return .deferred(
                captureID: loaded.draft.id,
                source: source,
                message: error.localizedDescription
            )
        }
    }

    private func loadCapture(from directory: URL) throws -> LoadedCapture {
        let manifest = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        let envelope: StagedCaptureEnvelope
        do {
            envelope = try decoder.decode(StagedCaptureEnvelope.self, from: manifest)
        } catch {
            throw InvalidCapturePayload(message: error.localizedDescription)
        }

        let normalized: CaptureDraft
        do {
            normalized = try envelope.draft.normalized()
        } catch {
            throw InvalidCapturePayload(message: error.localizedDescription)
        }

        var attachmentData: Data?
        if let attachmentFileName = envelope.attachmentFileName {
            let safeName = try validatedFileName(attachmentFileName)
            let attachmentURL = directory.appendingPathComponent(safeName)
            let byteCount = try attachmentURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard byteCount <= 100 * 1_024 * 1_024 else {
                throw InvalidCapturePayload(message: CaptureValidationError.attachmentTooLarge.localizedDescription)
            }
            attachmentData = try Data(contentsOf: attachmentURL, options: .mappedIfSafe)
        } else if normalized.type == .image || normalized.type == .file {
            throw InvalidCapturePayload(message: CaptureValidationError.missingAttachment.localizedDescription)
        }

        var representations: [StowRepresentationDraft] = []
        for descriptor in envelope.representations ?? [] {
            let safeName = try validatedFileName(descriptor.fileName)
            let data = try Data(
                contentsOf: directory.appendingPathComponent(safeName),
                options: .mappedIfSafe
            )
            guard data.count == descriptor.byteCount else {
                throw InvalidCapturePayload(message: CocoaError(.fileReadCorruptFile).localizedDescription)
            }
            representations.append(StowRepresentationDraft(
                typeIdentifier: descriptor.typeIdentifier,
                data: data,
                ordinal: descriptor.ordinal
            ))
        }
        do {
            try StowRepresentationValidator.validate(representations)
        } catch {
            throw InvalidCapturePayload(message: error.localizedDescription)
        }

        return LoadedCapture(
            draft: normalized,
            capturedAt: envelope.capturedAt,
            attachmentData: attachmentData,
            representations: representations,
            ingestionIntent: envelope.ingestionIntent ?? .createNew
        )
    }

    private func validatedFileName(_ fileName: String) throws -> String {
        let lastPathComponent = URL(fileURLWithPath: fileName).lastPathComponent
        guard fileName == lastPathComponent, fileName != ".", fileName != ".." else {
            throw InvalidCapturePayload(message: CocoaError(.fileReadInvalidFileName).localizedDescription)
        }
        return fileName
    }

    private func pendingDirectories() throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: pendingURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func quarantine(_ directory: URL) throws {
        let destination = quarantineURL.appendingPathComponent(
            "\(directory.lastPathComponent)-\(UUID().uuidString)",
            isDirectory: true
        )
        if let quarantineMove {
            try quarantineMove(directory, destination)
        } else {
            try fileManager.moveItem(at: directory, to: destination)
        }
    }
}
