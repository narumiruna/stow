import AppKit
import ApplicationServices
import Carbon.HIToolbox

@MainActor
final class DirectPasteService {
    var canPasteDirectly: Bool {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-disable-direct-paste") { return false }
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
