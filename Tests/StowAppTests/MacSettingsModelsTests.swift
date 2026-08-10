import XCTest
@testable import StowApp

@MainActor
final class MacSettingsModelsTests: XCTestCase {
    func testSettingsPagesUseCanonicalGoalBasedOrder() {
        XCTAssertEqual(
            MacSettingsPage.allCases.map(\.rawValue),
            ["Capture", "Paste & Shortcuts", "Sync & Storage", "Privacy"]
        )
    }

    func testShortcutConfigurationUsesExistingDefaultsKeysAndPreservesOtherValues() throws {
        let suiteName = "MacSettingsModelsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("keep me", forKey: "unrelatedSetting")

        XCTAssertEqual(
            MacShortcutConfiguration.current(defaults: defaults),
            MacShortcutConfiguration(quickAdd: "optionShiftS", quickPanel: "commandShiftV")
        )

        let replacement = MacShortcutConfiguration(quickAdd: "controlOptionS", quickPanel: "optionCommandV")
        replacement.persist(to: defaults)

        XCTAssertEqual(defaults.string(forKey: "quickAddShortcut"), "controlOptionS")
        XCTAssertEqual(defaults.string(forKey: "quickPanelShortcut"), "optionCommandV")
        XCTAssertEqual(defaults.string(forKey: "unrelatedSetting"), "keep me")
    }

    func testShortcutTransactionPersistsOnlyAfterBothRegistrationsSucceed() throws {
        let suiteName = "MacShortcutTransactionTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let previous = MacShortcutConfiguration(quickAdd: "optionShiftS", quickPanel: "commandShiftV")
        previous.persist(to: defaults)
        let backend = TransactionFakeHotKeyBackend()
        let service = GlobalHotKeyService(backend: backend, defaults: defaults)
        try service.registerDefaults()

        backend.failAttempts = [4]
        let candidate = MacShortcutConfiguration(quickAdd: "controlOptionS", quickPanel: "optionCommandV")
        let failed = MacShortcutTransaction.apply(candidate, using: service, defaults: defaults)

        guard case .failure = failed else { return XCTFail("Expected a shortcut conflict") }
        XCTAssertEqual(MacShortcutConfiguration.current(defaults: defaults), previous)
        XCTAssertEqual(
            service.registeredConfiguration,
            GlobalHotKeyService.Configuration(quickAddKey: previous.quickAdd, quickPanelKey: previous.quickPanel)
        )

        backend.failAttempts = []
        XCTAssertEqual(MacShortcutTransaction.apply(candidate, using: service, defaults: defaults), .success)
        XCTAssertEqual(MacShortcutConfiguration.current(defaults: defaults), candidate)
    }
}

@MainActor
private final class TransactionFakeHotKeyBackend: GlobalHotKeyRegistrationBackend {
    final class Registration: GlobalHotKeyRegistration {
        let actionID: UInt32
        init(actionID: UInt32) { self.actionID = actionID }
    }

    var failAttempts: Set<Int> = []
    private var attempt = 0
    private var active: [Registration] = []

    func installEventHandler(_ handler: @escaping @MainActor (UInt32) -> Void) throws {}

    func register(keyCode: UInt32, modifiers: UInt32, actionID: UInt32, label: String) throws -> any GlobalHotKeyRegistration {
        attempt += 1
        if failAttempts.contains(attempt) { throw TestError.conflict }
        let registration = Registration(actionID: actionID)
        active.append(registration)
        return registration
    }

    func unregister(_ registration: any GlobalHotKeyRegistration) {
        guard let registration = registration as? Registration else { return }
        active.removeAll { $0 === registration }
    }

    private enum TestError: Error { case conflict }
}
