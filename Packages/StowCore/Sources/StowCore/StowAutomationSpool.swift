import Foundation

public enum StowAutomationSpoolError: Error, Equatable, LocalizedError, Sendable {
    case requestIDMismatch
    case invalidFileName
    case unsafeExportDirectory
    case unsupportedVersion
    case responseUnavailable

    public var errorDescription: String? {
        switch self {
        case .requestIDMismatch: "The automation response does not match its request."
        case .invalidFileName: "The attachment file name is invalid."
        case .unsafeExportDirectory: "The automation export directory is unsafe."
        case .unsupportedVersion: "The automation response uses an unsupported protocol version."
        case .responseUnavailable: "The automation response is unavailable."
        }
    }
}

public struct StowAutomationClaim: Sendable {
    public let request: StowAutomationRequest
    fileprivate let processingURL: URL
}

public final class StowAutomationSpool {
    public let rootURL: URL
    public let pendingDirectoryURL: URL
    public let processingDirectoryURL: URL
    public let responsesDirectoryURL: URL
    public let exportsDirectoryURL: URL
    public let quarantineDirectoryURL: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(rootURL: URL, fileManager: FileManager = .default) throws {
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager
        pendingDirectoryURL = self.rootURL.appendingPathComponent("Pending", isDirectory: true)
        processingDirectoryURL = self.rootURL.appendingPathComponent("Processing", isDirectory: true)
        responsesDirectoryURL = self.rootURL.appendingPathComponent("Responses", isDirectory: true)
        exportsDirectoryURL = self.rootURL.appendingPathComponent("Exports", isDirectory: true)
        quarantineDirectoryURL = self.rootURL.appendingPathComponent("Quarantine", isDirectory: true)
        encoder = StowAutomationProtocol.encoder()
        decoder = StowAutomationProtocol.decoder()
        for directory in [
            self.rootURL,
            pendingDirectoryURL,
            processingDirectoryURL,
            responsesDirectoryURL,
            exportsDirectoryURL,
            quarantineDirectoryURL,
        ] {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
    }

    public func submit(_ request: StowAutomationRequest) throws {
        if responseExists(request.requestID) || requestExists(request.requestID) { return }
        let data = try encoder.encode(request)
        let destination = requestURL(request.requestID, in: pendingDirectoryURL)
        let staging = rootURL.appendingPathComponent(".staging-\(request.requestID.uuidString)-\(UUID().uuidString).json")
        do {
            try data.write(to: staging, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.path)
            do {
                try fileManager.moveItem(at: staging, to: destination)
            } catch where fileManager.fileExists(atPath: destination.path) || requestExists(request.requestID) || responseExists(request.requestID) {
                try? fileManager.removeItem(at: staging)
            }
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    public func response(for requestID: UUID) throws -> StowAutomationResponse? {
        let url = responseURL(requestID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let response = try decoder.decode(StowAutomationResponse.self, from: Data(contentsOf: url))
        guard response.requestID == requestID else { throw StowAutomationSpoolError.requestIDMismatch }
        guard response.schemaVersion == StowAutomationProtocol.schemaVersion else { throw StowAutomationSpoolError.unsupportedVersion }
        return response
    }

    public func hasPendingRequests() -> Bool {
        ((try? pendingFiles())?.isEmpty == false)
    }

    public func recoverInterruptedProcessing() throws {
        for source in try jsonFiles(in: processingDirectoryURL) {
            let requestID = source.deletingPathExtension().lastPathComponent
            guard let id = UUID(uuidString: requestID) else {
                quarantine(source)
                continue
            }
            if responseExists(id) {
                try? fileManager.removeItem(at: source)
                continue
            }
            let destination = requestURL(id, in: pendingDirectoryURL)
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: source)
            } else {
                try fileManager.moveItem(at: source, to: destination)
            }
        }
    }

    public func claimNext() throws -> StowAutomationClaim? {
        while let source = try pendingFiles().first {
            let fileStem = source.deletingPathExtension().lastPathComponent
            guard let requestID = UUID(uuidString: fileStem) else {
                quarantine(source)
                continue
            }
            if responseExists(requestID) {
                try? fileManager.removeItem(at: source)
                continue
            }
            let processing = requestURL(requestID, in: processingDirectoryURL)
            do {
                try fileManager.moveItem(at: source, to: processing)
            } catch {
                if fileManager.fileExists(atPath: processing.path) {
                    try? fileManager.removeItem(at: source)
                    continue
                }
                throw error
            }
            do {
                let request = try decoder.decode(StowAutomationRequest.self, from: Data(contentsOf: processing))
                guard request.requestID == requestID else {
                    let response = StowAutomationResponse(
                        requestID: requestID,
                        error: StowAutomationError(code: .invalidRequest, message: "The request ID does not match its file name.")
                    )
                    try writeResponseIfAbsent(response)
                    quarantine(processing)
                    continue
                }
                return StowAutomationClaim(request: request, processingURL: processing)
            } catch {
                let response = StowAutomationResponse(
                    requestID: requestID,
                    error: StowAutomationError(code: .invalidRequest, message: "The automation request is malformed.")
                )
                try writeResponseIfAbsent(response)
                quarantine(processing)
            }
        }
        return nil
    }

    public func complete(_ claim: StowAutomationClaim, with response: StowAutomationResponse) throws {
        guard claim.request.requestID == response.requestID else { throw StowAutomationSpoolError.requestIDMismatch }
        try writeResponseIfAbsent(response)
        try? fileManager.removeItem(at: claim.processingURL)
    }

    public func writeExport(_ data: Data, fileName: String, requestID: UUID) throws -> URL {
        let safeName = URL(fileURLWithPath: fileName).lastPathComponent
        guard !safeName.isEmpty, safeName == fileName else { throw StowAutomationSpoolError.invalidFileName }
        let directory = exportsDirectoryURL.appendingPathComponent(requestID.uuidString, isDirectory: true)
        var isDirectory = ObjCBool(false)
        if fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            let isSymbolicLink = (try? fileManager.destinationOfSymbolicLink(atPath: directory.path)) != nil
            guard isDirectory.boolValue, !isSymbolicLink else { throw StowAutomationSpoolError.unsafeExportDirectory }
        } else {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        }
        let destination = directory.appendingPathComponent(safeName)
        if !fileManager.fileExists(atPath: destination.path) {
            try data.write(to: destination, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        }
        return destination
    }

    @discardableResult
    public func removeInterruptedStaging(olderThan age: TimeInterval = 300, now: Date = Date()) throws -> Int {
        let children = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )
        let interrupted = try children.filter {
            let isStaging = $0.lastPathComponent.hasPrefix(".staging-") || $0.lastPathComponent.hasPrefix(".response-")
            guard isStaging else { return false }
            return try isOlder($0, than: age, now: now)
        }
        for child in interrupted { try fileManager.removeItem(at: child) }
        return interrupted.count
    }

    @discardableResult
    public func removeCompletedArtifacts(olderThan age: TimeInterval = 86_400, now: Date = Date()) throws -> Int {
        var removed = 0
        for child in try jsonFiles(in: responsesDirectoryURL) {
            if try isOlder(child, than: age, now: now) {
                try fileManager.removeItem(at: child)
                removed += 1
            }
        }
        for directory in [exportsDirectoryURL, quarantineDirectoryURL] {
            let children = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            for child in children where try isOlder(child, than: age, now: now) {
                try fileManager.removeItem(at: child)
                removed += 1
            }
        }
        return removed
    }

    private func requestExists(_ requestID: UUID) -> Bool {
        fileManager.fileExists(atPath: requestURL(requestID, in: pendingDirectoryURL).path)
            || fileManager.fileExists(atPath: requestURL(requestID, in: processingDirectoryURL).path)
    }

    private func responseExists(_ requestID: UUID) -> Bool {
        fileManager.fileExists(atPath: responseURL(requestID).path)
    }

    private func responseURL(_ requestID: UUID) -> URL {
        responsesDirectoryURL.appendingPathComponent("\(requestID.uuidString).json")
    }

    private func requestURL(_ requestID: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("\(requestID.uuidString).json")
    }

    private func writeResponseIfAbsent(_ response: StowAutomationResponse) throws {
        let destination = responseURL(response.requestID)
        guard !fileManager.fileExists(atPath: destination.path) else { return }
        let data = try encoder.encode(response)
        let staging = rootURL.appendingPathComponent(".response-\(response.requestID.uuidString)-\(UUID().uuidString).json")
        do {
            try data.write(to: staging, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staging.path)
            do {
                try fileManager.moveItem(at: staging, to: destination)
            } catch where fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: staging)
            }
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    private func pendingFiles() throws -> [URL] {
        try jsonFiles(in: pendingDirectoryURL)
    }

    private func jsonFiles(in directory: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func quarantine(_ source: URL) {
        let destination = quarantineDirectoryURL.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent)-\(UUID().uuidString).json")
        do {
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            try? fileManager.removeItem(at: source)
        }
    }

    private func isOlder(_ url: URL, than age: TimeInterval, now: Date) throws -> Bool {
        let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
        return now.timeIntervalSince(modified) >= age
    }
}
