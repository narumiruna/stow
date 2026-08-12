import AppKit
import ApplicationServices
import Carbon.HIToolbox

@MainActor
final class DirectPasteService: RetrievalDirectPasteCapability {
    var canPasteDirectly: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-force-direct-paste") { return true }
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-disable-direct-paste") { return false }
        #endif
        return AXIsProcessTrusted()
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
