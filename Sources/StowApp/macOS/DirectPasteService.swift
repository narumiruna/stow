import AppKit
import ApplicationServices
import Carbon.HIToolbox
import OSLog

/// Decides whether Stow asks macOS for Accessibility access at launch.
/// Stow asks automatically at most once; later requests come from Settings.
enum DirectPasteLaunchPromptPolicy {
    static let promptShownDefaultsKey = "directPasteLaunchPromptShown"

    static func shouldPrompt(alreadyPrompted: Bool, accessGranted: Bool, isAutomatedLaunch: Bool) -> Bool {
        !alreadyPrompted && !accessGranted && !isAutomatedLaunch
    }
}

/// Why Direct Paste can or cannot run in the current process.
enum DirectPasteAvailability: Equatable {
    case available
    /// App Sandbox blocks posting keyboard events to other apps.
    case sandboxed
    case accessibilityNotTrusted
    case eventPostingNotAllowed

    var isAvailable: Bool { self == .available }

    static func evaluate(isSandboxed: Bool, accessibilityTrusted: Bool, canPostEvents: Bool) -> DirectPasteAvailability {
        if isSandboxed { return .sandboxed }
        if !accessibilityTrusted { return .accessibilityNotTrusted }
        if !canPostEvents { return .eventPostingNotAllowed }
        return .available
    }

    /// Live check against the running process.
    static func current() -> DirectPasteAvailability {
        evaluate(
            isSandboxed: ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil,
            accessibilityTrusted: AXIsProcessTrusted(),
            canPostEvents: CGPreflightPostEventAccess()
        )
    }
}

enum DirectPasteFailure: Equatable {
    case unavailable(DirectPasteAvailability)
    case targetTerminated
    case activationFailed
    case focusTimeout
    case focusLost
    case eventPostingFailed
}

extension DirectPasteFailure {
    /// Whether the copy fallback may bring the target back to the front after this failure.
    /// Never after focus moved elsewhere, the wait timed out, or the target quit, and only while Stow itself
    /// is still frontmost, so the fallback never takes focus from an app the user switched to.
    func allowsReactivatingTarget(stowIsFrontmost: Bool) -> Bool {
        switch self {
        case .focusLost, .focusTimeout, .targetTerminated:
            false
        case .unavailable, .activationFailed, .eventPostingFailed:
            stowIsFrontmost
        }
    }
}

enum DirectPasteResult: Equatable {
    case pasted
    case failed(DirectPasteFailure)
}

/// The app Stow pastes into.
@MainActor
protocol DirectPasteTarget: AnyObject {
    var processIdentifier: pid_t { get }
    var isTerminated: Bool { get }
    func activateForPaste() -> Bool
}

extension NSRunningApplication: DirectPasteTarget {
    func activateForPaste() -> Bool { activate() }
}

/// System calls the paste sequence depends on; replaced by doubles in tests.
@MainActor
protocol DirectPasteEnvironment {
    func availability() -> DirectPasteAvailability
    func frontmostProcessIdentifier() -> pid_t?
    func postCommandV(to pid: pid_t) -> Bool
    func wait(milliseconds: Int) async
}

/// Activates the target, waits for it to become frontmost, re-checks state, then posts Command-V to it.
@MainActor
struct DirectPastePerformer {
    static let pollIntervalMilliseconds = 25
    static let maximumFocusChecks = 40

    let environment: any DirectPasteEnvironment

    func paste(into target: any DirectPasteTarget) async -> DirectPasteResult {
        let availability = environment.availability()
        guard availability.isAvailable else { return .failed(.unavailable(availability)) }
        guard !target.isTerminated else { return .failed(.targetTerminated) }

        let pid = target.processIdentifier
        let wasFrontmost = environment.frontmostProcessIdentifier() == pid
        if !target.activateForPaste(), !wasFrontmost {
            return .failed(.activationFailed)
        }

        if !wasFrontmost {
            var focused = false
            for _ in 0..<Self.maximumFocusChecks {
                await environment.wait(milliseconds: Self.pollIntervalMilliseconds)
                if let failure = recheck(target) { return .failed(failure) }
                if environment.frontmostProcessIdentifier() == pid {
                    focused = true
                    break
                }
            }
            guard focused else { return .failed(.focusTimeout) }
            // Give the newly activated app one interval to make its window key.
            await environment.wait(milliseconds: Self.pollIntervalMilliseconds)
        }

        if let failure = recheck(target) { return .failed(failure) }
        guard environment.frontmostProcessIdentifier() == pid else { return .failed(.focusLost) }
        return environment.postCommandV(to: pid) ? .pasted : .failed(.eventPostingFailed)
    }

    private func recheck(_ target: any DirectPasteTarget) -> DirectPasteFailure? {
        if target.isTerminated { return .targetTerminated }
        let availability = environment.availability()
        return availability.isAvailable ? nil : .unavailable(availability)
    }
}

@MainActor
struct SystemDirectPasteEnvironment: DirectPasteEnvironment {
    func availability() -> DirectPasteAvailability { DirectPasteAvailability.current() }

    func frontmostProcessIdentifier() -> pid_t? {
        NSWorkspace.shared.frontmostApplication?.processIdentifier
    }

    func postCommandV(to pid: pid_t) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return false }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(pid)
        keyUp.postToPid(pid)
        return true
    }

    func wait(milliseconds: Int) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }
}

@MainActor
final class DirectPasteService: RetrievalDirectPasteCapability {
    private static let logger = Logger(subsystem: "dev.narumi.stow", category: "DirectPaste")
    private let environment: any DirectPasteEnvironment

    init(environment: (any DirectPasteEnvironment)? = nil) {
        self.environment = environment ?? SystemDirectPasteEnvironment()
    }

    var canPasteDirectly: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-force-direct-paste") { return true }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-disable-direct-paste") { return false }
        #endif
        return environment.availability().isAvailable
    }

    /// Shows the system Accessibility prompt once, on the first launch without access.
    static func requestAccessOnFirstLaunchIfNeeded(defaults: UserDefaults = .standard) {
        #if DEBUG
        let isAutomatedLaunch = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #else
        let isAutomatedLaunch = false
        #endif
        // A sandboxed build can never paste directly, so asking for access would only confuse.
        guard DirectPasteAvailability.current() != .sandboxed else { return }
        let key = DirectPasteLaunchPromptPolicy.promptShownDefaultsKey
        guard DirectPasteLaunchPromptPolicy.shouldPrompt(
            alreadyPrompted: defaults.bool(forKey: key),
            accessGranted: AXIsProcessTrusted(),
            isAutomatedLaunch: isAutomatedLaunch
        ) else { return }
        defaults.set(true, forKey: key)
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func paste(into target: (any DirectPasteTarget)?) async -> DirectPasteResult {
        guard let target else { return .failed(.targetTerminated) }
        let result = await DirectPastePerformer(environment: environment).paste(into: target)
        if case .failed(let failure) = result {
            Self.logger.notice("Direct paste fell back to copy: \(String(describing: failure), privacy: .public)")
        }
        return result
    }
}
