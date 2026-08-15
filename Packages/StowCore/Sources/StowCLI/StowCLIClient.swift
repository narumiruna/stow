import AppKit
import Foundation
import StowCore

private final class StowLaunchCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var isFinished = false
    private var storedError: Error?

    func finish(error: Error?) {
        lock.lock()
        storedError = error
        isFinished = true
        lock.unlock()
    }

    func snapshot() -> (finished: Bool, error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        return (isFinished, storedError)
    }
}

@MainActor
struct StowCLIHostLauncher {
    var environment: [String: String] = ProcessInfo.processInfo.environment
    var executableURL: URL = URL(fileURLWithPath: CommandLine.arguments.first ?? "stow")
    var workspace: NSWorkspace = .shared

    func launchIfNeeded() throws {
        if !NSRunningApplication.runningApplications(withBundleIdentifier: "dev.narumi.stow").isEmpty { return }
        guard let appURL = applicationURL else {
            throw StowAutomationError(
                code: .hostUnavailable,
                message: "Stow is not installed; set STOW_APP_PATH for a development build.",
                retryable: true
            )
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.hides = true
        configuration.arguments = ["--stow-automation"]
        let stowEnvironment = environment.filter { $0.key.hasPrefix("STOW_") }
        if !stowEnvironment.isEmpty { configuration.environment = stowEnvironment }
        if let sharedContainerPath = environment[StowSharedStorage.developmentContainerPathEnvironmentKey],
           !sharedContainerPath.isEmpty {
            configuration.arguments.append("--stow-shared-container-path=\(sharedContainerPath)")
        }
        let completion = StowLaunchCompletion()
        workspace.openApplication(at: appURL, configuration: configuration) { _, error in
            completion.finish(error: error)
        }
        while !completion.snapshot().finished {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        if let completionError = completion.snapshot().error {
            throw StowAutomationError(
                code: .hostUnavailable,
                message: "Stow could not be launched: \(completionError.localizedDescription)",
                retryable: true
            )
        }
    }

    private var applicationURL: URL? {
        if let configuredPath = environment["STOW_APP_PATH"], !configuredPath.isEmpty {
            let url = URL(fileURLWithPath: configuredPath).standardizedFileURL
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        if let embeddedAppURL { return embeddedAppURL }
        return workspace.urlForApplication(withBundleIdentifier: "dev.narumi.stow")
    }

    private var embeddedAppURL: URL? {
        let resolved = executableURL.resolvingSymlinksInPath()
        guard resolved.deletingLastPathComponent().lastPathComponent == "Helpers" else { return nil }
        let contents = resolved.deletingLastPathComponent().deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        return app.pathExtension == "app" ? app : nil
    }
}

@MainActor
struct StowCLIClient {
    var spool: StowAutomationSpool
    var launchHost: () throws -> Void
    var now: () -> Date
    var sleep: (TimeInterval) -> Void

    init(
        spool: StowAutomationSpool,
        launchHost: @escaping () throws -> Void = { try StowCLIHostLauncher().launchIfNeeded() },
        now: @escaping () -> Date = Date.init,
        sleep: @escaping (TimeInterval) -> Void = Thread.sleep(forTimeInterval:)
    ) {
        self.spool = spool
        self.launchHost = launchHost
        self.now = now
        self.sleep = sleep
    }

    func send(_ request: StowAutomationRequest, timeout: TimeInterval) -> StowAutomationResponse {
        do {
            if let response = try spool.response(for: request.requestID) { return response }
            try spool.submit(request)
            try launchHost()
            let deadline = now().addingTimeInterval(timeout)
            while now() < deadline {
                if let response = try spool.response(for: request.requestID) { return response }
                sleep(0.05)
            }
            return StowAutomationResponse(
                requestID: request.requestID,
                error: StowAutomationError(
                    code: .timeout,
                    message: timeoutMessage(for: request.command),
                    retryable: true
                )
            )
        } catch let error as StowAutomationError {
            return StowAutomationResponse(requestID: request.requestID, error: error)
        } catch {
            return StowAutomationResponse(
                requestID: request.requestID,
                error: StowAutomationError(code: .ioFailure, message: error.localizedDescription, retryable: true)
            )
        }
    }

    private func timeoutMessage(for command: StowAutomationCommand) -> String {
        switch command {
        case .add, .export:
            "Stow did not respond before the timeout; retry with the same request ID."
        case .status, .search, .get:
            "Stow did not respond before the timeout; retry the command."
        }
    }

    func copyExportIfRequested(
        in response: StowAutomationResponse,
        options: StowCLIExportOptions?
    ) -> StowAutomationResponse {
        guard response.ok, let options, let outputPath = options.outputPath,
              var result = response.data, var exported = result.export else { return response }
        let source = URL(fileURLWithPath: exported.path)
        let destination = URL(fileURLWithPath: outputPath).standardizedFileURL
        do {
            var isDirectory = ObjCBool(false)
            let destinationExists = FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory)
            if destinationExists {
                guard !isDirectory.boolValue else {
                    throw StowAutomationError(code: .ioFailure, message: "The output path is a directory and will not be replaced.")
                }
                guard options.force else {
                    throw StowAutomationError(
                        code: .ioFailure,
                        message: "The output file already exists; pass --force to replace it."
                    )
                }
            }
            let staging = destination.deletingLastPathComponent()
                .appendingPathComponent(".\(destination.lastPathComponent).stow-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: staging) }
            try FileManager.default.copyItem(at: source, to: staging)
            if destinationExists {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: staging)
            } else {
                try FileManager.default.moveItem(at: staging, to: destination)
            }
            exported.path = destination.path
            result.export = exported
            var updated = response
            updated.data = result
            return updated
        } catch let error as StowAutomationError {
            return StowAutomationResponse(
                requestID: response.requestID,
                error: StowAutomationError(
                    code: error.code,
                    message: error.message,
                    retryable: error.retryable,
                    fallbackPath: exported.path
                )
            )
        } catch {
            return StowAutomationResponse(
                requestID: response.requestID,
                error: StowAutomationError(
                    code: .ioFailure,
                    message: error.localizedDescription,
                    fallbackPath: exported.path
                )
            )
        }
    }
}
