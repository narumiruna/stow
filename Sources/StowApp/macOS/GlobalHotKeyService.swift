import AppKit
import Carbon.HIToolbox

private let stowHotKeySignature: OSType = 0x53544F57 // STOW

protocol GlobalHotKeyRegistration: AnyObject {}

@MainActor
protocol GlobalHotKeyRegistrationBackend: AnyObject {
    func installEventHandler(_ handler: @escaping @MainActor (UInt32) -> Void) throws
    func register(
        keyCode: UInt32,
        modifiers: UInt32,
        actionID: UInt32,
        label: String
    ) throws -> any GlobalHotKeyRegistration
    func unregister(_ registration: any GlobalHotKeyRegistration)
}

@MainActor
final class GlobalHotKeyService {
    enum Action: UInt32, Sendable {
        case quickAdd = 1
        case quickPanel = 2
    }

    struct Configuration: Equatable, Sendable {
        let quickAddKey: String
        let quickPanelKey: String

        init(
            quickAddKey: String = GlobalHotKeyService.defaultQuickAddKey,
            quickPanelKey: String = GlobalHotKeyService.defaultQuickPanelKey
        ) {
            self.quickAddKey = quickAddKey
            self.quickPanelKey = quickPanelKey
        }
    }

    enum RegistrationError: LocalizedError, Equatable {
        case unavailable(String)
        case restorationFailed(candidate: String, restoration: String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let shortcut):
                "The global shortcut \(shortcut) is already used by another app. Choose another shortcut in Settings."
            case .restorationFailed(let candidate, let restoration):
                "Stow could not restore the previous global shortcuts after the proposed shortcuts failed. Candidate error: \(candidate) Restoration error: \(restoration)"
            }
        }
    }

    nonisolated static let quickAddDefaultsKey = "quickAddShortcut"
    nonisolated static let quickPanelDefaultsKey = "quickPanelShortcut"
    nonisolated static let defaultQuickAddKey = "optionShiftS"
    nonisolated static let defaultQuickPanelKey = "commandShiftV"

    var handler: ((Action) -> Void)?
    private(set) var registeredConfiguration: Configuration?

    private let backend: any GlobalHotKeyRegistrationBackend
    private let defaults: UserDefaults
    private var registrations: [any GlobalHotKeyRegistration] = []
    private var eventHandlerIsInstalled = false

    init(
        backend: any GlobalHotKeyRegistrationBackend = CarbonHotKeyRegistrationBackend(),
        defaults: UserDefaults = .standard
    ) {
        self.backend = backend
        self.defaults = defaults
    }

    /// Loads the persisted configuration for launch. Settings should call `apply(_:)`
    /// before persisting a proposed configuration.
    func registerDefaults() throws {
        try apply(
            Configuration(
                quickAddKey: defaults.string(forKey: Self.quickAddDefaultsKey) ?? Self.defaultQuickAddKey,
                quickPanelKey: defaults.string(forKey: Self.quickPanelDefaultsKey) ?? Self.defaultQuickPanelKey
            )
        )
    }

    /// Replaces both global shortcuts as one transaction without reading or writing UserDefaults.
    /// If either candidate registration fails, the previous valid pair is restored first.
    func apply(_ configuration: Configuration) throws {
        try installEventHandlerIfNeeded()
        guard configuration != registeredConfiguration else { return }

        let previousConfiguration = registeredConfiguration
        unregisterCurrentPair()

        do {
            registrations = try makeRegistrations(for: configuration)
            registeredConfiguration = configuration
            return
        } catch {
            let candidateError = registrationError(from: error)
            guard let previousConfiguration else { throw candidateError }

            do {
                registrations = try makeRegistrations(for: previousConfiguration)
                registeredConfiguration = previousConfiguration
            } catch {
                let restorationError = registrationError(from: error)
                unregisterCurrentPair()
                throw RegistrationError.restorationFailed(
                    candidate: candidateError.localizedDescription,
                    restoration: restorationError.localizedDescription
                )
            }
            throw candidateError
        }
    }

    private func installEventHandlerIfNeeded() throws {
        guard !eventHandlerIsInstalled else { return }
        do {
            try backend.installEventHandler { [weak self] actionID in
                guard let action = Action(rawValue: actionID) else { return }
                self?.handler?(action)
            }
            eventHandlerIsInstalled = true
        } catch {
            throw RegistrationError.unavailable("keyboard event handler")
        }
    }

    private func makeRegistrations(for configuration: Configuration) throws -> [any GlobalHotKeyRegistration] {
        let definitions = [
            Self.definition(for: configuration.quickAddKey, action: .quickAdd),
            Self.definition(for: configuration.quickPanelKey, action: .quickPanel),
        ]
        var proposed: [any GlobalHotKeyRegistration] = []
        do {
            for definition in definitions {
                do {
                    proposed.append(
                        try backend.register(
                            keyCode: definition.keyCode,
                            modifiers: definition.modifiers,
                            actionID: definition.action.rawValue,
                            label: definition.label
                        )
                    )
                } catch {
                    throw RegistrationError.unavailable(definition.label)
                }
            }
            return proposed
        } catch {
            for registration in proposed { backend.unregister(registration) }
            throw error
        }
    }

    private func unregisterCurrentPair() {
        for registration in registrations { backend.unregister(registration) }
        registrations.removeAll()
        registeredConfiguration = nil
    }

    private func registrationError(from error: Error) -> RegistrationError {
        if let registrationError = error as? RegistrationError { return registrationError }
        return .unavailable("keyboard event handler")
    }

    private static func definition(for key: String, action: Action) -> ShortcutDefinition {
        switch (action, key) {
        case (.quickAdd, "controlOptionS"):
            ShortcutDefinition(action: action, keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey), label: "⌃⌥S")
        case (.quickAdd, "commandOptionS"):
            ShortcutDefinition(action: action, keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(cmdKey | optionKey), label: "⌘⌥S")
        case (.quickPanel, "optionCommandV"):
            ShortcutDefinition(action: action, keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(optionKey | cmdKey), label: "⌥⌘V")
        case (.quickPanel, "controlShiftV"):
            ShortcutDefinition(action: action, keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | shiftKey), label: "⌃⇧V")
        case (.quickAdd, _):
            ShortcutDefinition(action: action, keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(optionKey | shiftKey), label: "⌥⇧S")
        case (.quickPanel, _):
            ShortcutDefinition(action: action, keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey), label: "⌘⇧V")
        }
    }

    private struct ShortcutDefinition {
        let action: Action
        let keyCode: UInt32
        let modifiers: UInt32
        let label: String
    }
}

@MainActor
private final class CarbonHotKeyRegistrationBackend: GlobalHotKeyRegistrationBackend {
    private final class Registration: GlobalHotKeyRegistration {
        private var reference: EventHotKeyRef?

        init(reference: EventHotKeyRef) {
            self.reference = reference
        }

        func cancel() {
            guard let reference else { return }
            UnregisterEventHotKey(reference)
            self.reference = nil
        }

        deinit {
            if let reference { UnregisterEventHotKey(reference) }
        }
    }

    private var handler: (@MainActor (UInt32) -> Void)?
    nonisolated(unsafe) private var eventHandler: EventHandlerRef?

    func installEventHandler(_ handler: @escaping @MainActor (UInt32) -> Void) throws {
        self.handler = handler
        guard eventHandler == nil else { return }

        var specification = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var identifier = EventHotKeyID()
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard result == noErr, identifier.signature == stowHotKeySignature else { return result }
                let backend = Unmanaged<CarbonHotKeyRegistrationBackend>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { backend.send(actionID: identifier.id) }
                return noErr
            },
            1,
            &specification,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard status == noErr else { throw CarbonRegistrationError(status: status) }
    }

    func register(
        keyCode: UInt32,
        modifiers: UInt32,
        actionID: UInt32,
        label: String
    ) throws -> any GlobalHotKeyRegistration {
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: stowHotKeySignature, id: actionID)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else { throw CarbonRegistrationError(status: status) }
        return Registration(reference: reference)
    }

    func unregister(_ registration: any GlobalHotKeyRegistration) {
        (registration as? Registration)?.cancel()
    }

    private func send(actionID: UInt32) {
        handler?(actionID)
    }

    deinit {
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    private struct CarbonRegistrationError: Error {
        let status: OSStatus
    }
}
