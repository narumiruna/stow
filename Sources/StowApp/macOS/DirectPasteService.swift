import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Decides whether Stow asks macOS for Accessibility access at launch.
/// Stow asks automatically at most once; later requests come from Settings.
enum DirectPasteLaunchPromptPolicy {
    static let promptShownDefaultsKey = "directPasteLaunchPromptShown"

    static func shouldPrompt(alreadyPrompted: Bool, accessGranted: Bool, isAutomatedLaunch: Bool) -> Bool {
        !alreadyPrompted && !accessGranted && !isAutomatedLaunch
    }
}

@MainActor
final class DirectPasteService: RetrievalDirectPasteCapability {
    var canPasteDirectly: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-force-direct-paste") { return true }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-disable-direct-paste") { return false }
        #endif
        return AXIsProcessTrusted()
    }

    /// Shows the system Accessibility prompt once, on the first launch without access.
    static func requestAccessOnFirstLaunchIfNeeded(defaults: UserDefaults = .standard) {
        #if DEBUG
        let isAutomatedLaunch = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #else
        let isAutomatedLaunch = false
        #endif
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

    func paste(into application: NSRunningApplication?) {
        guard canPasteDirectly, let application, !application.isTerminated else { return }
        application.activate()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            postCommandV()
        }
    }

    private func postCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
