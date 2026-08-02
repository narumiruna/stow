import AppKit
import Carbon.HIToolbox

private let stowHotKeySignature: OSType = 0x53544F57 // STOW

@MainActor
final class GlobalHotKeyService {
    enum Action: UInt32 { case quickAdd = 1; case quickPanel = 2 }
    enum RegistrationError: LocalizedError {
        case unavailable(String)
        var errorDescription: String? { switch self { case .unavailable(let shortcut): "The global shortcut \(shortcut) is already used by another app. Choose another shortcut in Settings." } }
    }

    var handler: ((Action) -> Void)?
    nonisolated(unsafe) private var references: [EventHotKeyRef?] = []
    nonisolated(unsafe) private var eventHandler: EventHandlerRef?

    func registerDefaults() throws {
        unregisterAll()
        if eventHandler == nil {
            var specification = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr, identifier.signature == stowHotKeySignature else { return result }
            let service = Unmanaged<GlobalHotKeyService>.fromOpaque(userData).takeUnretainedValue()
            if let action = Action(rawValue: identifier.id) {
                DispatchQueue.main.async { service.handler?(action) }
            }
            return noErr
            }, 1, &specification, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
            guard status == noErr else { throw RegistrationError.unavailable("keyboard event handler") }
        }
        let quickAdd = Self.definition(for: UserDefaults.standard.string(forKey: "quickAddShortcut") ?? "optionShiftS", action: .quickAdd)
        let quickPanel = Self.definition(for: UserDefaults.standard.string(forKey: "quickPanelShortcut") ?? "commandShiftV", action: .quickPanel)
        do {
            try register(action: .quickAdd, keyCode: quickAdd.keyCode, modifiers: quickAdd.modifiers, label: quickAdd.label)
            try register(action: .quickPanel, keyCode: quickPanel.keyCode, modifiers: quickPanel.modifiers, label: quickPanel.label)
        } catch {
            unregisterAll()
            throw error
        }
    }

    private func register(action: Action, keyCode: UInt32, modifiers: UInt32, label: String) throws {
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: stowHotKeySignature, id: action.rawValue)
        let status = RegisterEventHotKey(keyCode, modifiers, identifier, GetApplicationEventTarget(), 0, &reference)
        guard status == noErr else { throw RegistrationError.unavailable(label) }
        references.append(reference)
    }

    private func unregisterAll() {
        for reference in references { if let reference { UnregisterEventHotKey(reference) } }
        references.removeAll()
    }

    private static func definition(for key: String, action: Action) -> (keyCode: UInt32, modifiers: UInt32, label: String) {
        switch (action, key) {
        case (.quickAdd, "controlOptionS"): (UInt32(kVK_ANSI_S), UInt32(controlKey | optionKey), "⌃⌥S")
        case (.quickAdd, "commandOptionS"): (UInt32(kVK_ANSI_S), UInt32(cmdKey | optionKey), "⌘⌥S")
        case (.quickPanel, "optionCommandV"): (UInt32(kVK_ANSI_V), UInt32(optionKey | cmdKey), "⌥⌘V")
        case (.quickPanel, "controlShiftV"): (UInt32(kVK_ANSI_V), UInt32(controlKey | shiftKey), "⌃⇧V")
        case (.quickAdd, _): (UInt32(kVK_ANSI_S), UInt32(optionKey | shiftKey), "⌥⇧S")
        case (.quickPanel, _): (UInt32(kVK_ANSI_V), UInt32(cmdKey | shiftKey), "⌘⇧V")
        }
    }

    deinit {
        for reference in references { if let reference { UnregisterEventHotKey(reference) } }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

}
