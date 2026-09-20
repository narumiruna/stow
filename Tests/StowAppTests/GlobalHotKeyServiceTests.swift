import XCTest
@testable import StowApp

@MainActor
final class GlobalHotKeyServiceTests: XCTestCase {
    func testExplicitConfigurationRegistersBothShortcutsWithoutReadingOrWritingDefaults() throws {
        let defaults = try makeDefaults()
        defaults.set("sentinel-add", forKey: MacShortcutConfiguration.quickAddDefaultsKey)
        defaults.set("sentinel-panel", forKey: MacShortcutConfiguration.quickPanelDefaultsKey)
        let backend = FakeHotKeyRegistrationBackend()
        let service = GlobalHotKeyService(backend: backend, defaults: defaults)
        let candidate = MacShortcutConfiguration(quickAdd: "controlOptionS", quickPanel: "optionCommandV")

        try service.apply(candidate)

        XCTAssertEqual(service.registeredConfiguration, candidate)
        XCTAssertEqual(backend.active.map(\.actionID), [
            GlobalHotKeyService.Action.quickAdd.rawValue,
            GlobalHotKeyService.Action.quickPanel.rawValue,
        ])
        XCTAssertEqual(defaults.string(forKey: MacShortcutConfiguration.quickAddDefaultsKey), "sentinel-add")
        XCTAssertEqual(defaults.string(forKey: MacShortcutConfiguration.quickPanelDefaultsKey), "sentinel-panel")
    }

    func testFirstCandidateConflictRestoresPreviousValidPair() throws {
        let backend = FakeHotKeyRegistrationBackend()
        let service = GlobalHotKeyService(backend: backend)
        let previous = MacShortcutConfiguration()
        try service.apply(previous)
        backend.failRegistrationAttempts = [3]

        XCTAssertThrowsError(
            try service.apply(.init(quickAdd: "controlOptionS", quickPanel: "optionCommandV"))
        ) { error in
            XCTAssertEqual(error as? GlobalHotKeyService.RegistrationError, .unavailable("⌃⌥S"))
        }

        XCTAssertEqual(service.registeredConfiguration, previous)
        XCTAssertEqual(backend.active.map(\.label), ["⌥⇧S", "⌘⇧V"])
    }

    func testSecondCandidateConflictRemovesPartialCandidateAndRestoresPreviousValidPair() throws {
        let backend = FakeHotKeyRegistrationBackend()
        let service = GlobalHotKeyService(backend: backend)
        let previous = MacShortcutConfiguration(quickAdd: "controlOptionS", quickPanel: "controlShiftV")
        try service.apply(previous)
        backend.failRegistrationAttempts = [4]

        XCTAssertThrowsError(
            try service.apply(.init(quickAdd: "commandOptionS", quickPanel: "optionCommandV"))
        ) { error in
            XCTAssertEqual(error as? GlobalHotKeyService.RegistrationError, .unavailable("⌥⌘V"))
        }

        XCTAssertEqual(service.registeredConfiguration, previous)
        XCTAssertEqual(backend.active.map(\.label), ["⌃⌥S", "⌃⇧V"])
        XCTAssertTrue(backend.unregisteredLabels.contains("⌘⌥S"))
    }

    func testRestorationFailureIsReportedAndDoesNotClaimARegisteredConfiguration() throws {
        let backend = FakeHotKeyRegistrationBackend()
        let service = GlobalHotKeyService(backend: backend)
        let previous = MacShortcutConfiguration()
        try service.apply(previous)
        backend.failRegistrationAttempts = [4, 5]

        XCTAssertThrowsError(
            try service.apply(.init(quickAdd: "commandOptionS", quickPanel: "controlShiftV"))
        ) { error in
            guard case let GlobalHotKeyService.RegistrationError.restorationFailed(candidate, restoration) = error else {
                return XCTFail("Expected restoration failure, got \(error)")
            }
            XCTAssertEqual(candidate, "The global shortcut ⌃⇧V is already used by another app. Choose another shortcut in Settings.")
            XCTAssertEqual(restoration, "The global shortcut ⌥⇧S is already used by another app. Choose another shortcut in Settings.")
            XCTAssertTrue(error.localizedDescription.contains("could not restore"))
        }

        XCTAssertNil(service.registeredConfiguration)
        XCTAssertTrue(backend.active.isEmpty)
    }

    func testDefaultKeysFallbacksAlternativesAndLabelsRemainCompatible() throws {
        let defaults = try makeDefaults()
        let backend = FakeHotKeyRegistrationBackend()
        let service = GlobalHotKeyService(backend: backend, defaults: defaults)

        try service.registerDefaults()
        XCTAssertEqual(backend.active.map(\.label), ["⌥⇧S", "⌘⇧V"])
        XCTAssertEqual(service.registeredConfiguration, MacShortcutConfiguration())
        XCTAssertNil(defaults.object(forKey: MacShortcutConfiguration.quickAddDefaultsKey))
        XCTAssertNil(defaults.object(forKey: MacShortcutConfiguration.quickPanelDefaultsKey))

        let configurations: [(String, String, String, String)] = [
            ("unknown-add", "unknown-panel", "⌥⇧S", "⌘⇧V"),
            ("controlOptionS", "optionCommandV", "⌃⌥S", "⌥⌘V"),
            ("commandOptionS", "controlShiftV", "⌘⌥S", "⌃⇧V"),
        ]
        for (addKey, panelKey, addLabel, panelLabel) in configurations {
            defaults.set(addKey, forKey: MacShortcutConfiguration.quickAddDefaultsKey)
            defaults.set(panelKey, forKey: MacShortcutConfiguration.quickPanelDefaultsKey)
            try service.registerDefaults()
            XCTAssertEqual(backend.active.map(\.label), [addLabel, panelLabel])
            XCTAssertEqual(service.registeredConfiguration, MacShortcutConfiguration(quickAdd: addKey, quickPanel: panelKey))
            XCTAssertEqual(defaults.string(forKey: MacShortcutConfiguration.quickAddDefaultsKey), addKey)
            XCTAssertEqual(defaults.string(forKey: MacShortcutConfiguration.quickPanelDefaultsKey), panelKey)
        }
    }

    func testBackendEventsPreserveQuickAddAndQuickPanelHandlerBehavior() throws {
        let backend = FakeHotKeyRegistrationBackend()
        let service = GlobalHotKeyService(backend: backend)
        var received: [GlobalHotKeyService.Action] = []
        service.handler = { received.append($0) }
        try service.apply(.init())

        backend.send(actionID: GlobalHotKeyService.Action.quickPanel.rawValue)
        backend.send(actionID: 999)
        backend.send(actionID: GlobalHotKeyService.Action.quickAdd.rawValue)

        XCTAssertEqual(received, [.quickPanel, .quickAdd])
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "GlobalHotKeyServiceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }
}

@MainActor
private final class FakeHotKeyRegistrationBackend: GlobalHotKeyRegistrationBackend {
    final class Registration: GlobalHotKeyRegistration {
        let actionID: UInt32
        let label: String

        init(actionID: UInt32, label: String) {
            self.actionID = actionID
            self.label = label
        }
    }

    private(set) var active: [Registration] = []
    private(set) var unregisteredLabels: [String] = []
    var failRegistrationAttempts: Set<Int> = []
    private var registrationAttempt = 0
    private var eventHandler: ((UInt32) -> Void)?

    func installEventHandler(_ handler: @escaping @MainActor (UInt32) -> Void) throws {
        eventHandler = handler
    }

    func register(keyCode: UInt32, modifiers: UInt32, actionID: UInt32, label: String) throws -> any GlobalHotKeyRegistration {
        registrationAttempt += 1
        if failRegistrationAttempts.contains(registrationAttempt) {
            throw FakeError.conflict
        }
        let registration = Registration(actionID: actionID, label: label)
        active.append(registration)
        return registration
    }

    func unregister(_ registration: any GlobalHotKeyRegistration) {
        guard let registration = registration as? Registration else { return }
        unregisteredLabels.append(registration.label)
        active.removeAll { $0 === registration }
    }

    func send(actionID: UInt32) {
        eventHandler?(actionID)
    }

    enum FakeError: Error { case conflict }
}
