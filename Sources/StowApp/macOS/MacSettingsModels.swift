import Foundation

enum MacSettingsPage: String, CaseIterable, Identifiable {
    case capture = "Capture"
    case pasteAndShortcuts = "Paste & Shortcuts"
    case syncAndStorage = "Sync & Storage"
    case privacy = "Privacy"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .capture: "doc.on.clipboard"
        case .pasteAndShortcuts: "keyboard"
        case .syncAndStorage: "externaldrive"
        case .privacy: "hand.raised"
        }
    }
}

struct MacShortcutConfiguration: Equatable, Sendable {
    static let defaultQuickAdd = "optionShiftS"
    static let defaultQuickPanel = "commandShiftV"

    var quickAdd: String
    var quickPanel: String

    static func current(defaults: UserDefaults = .standard) -> Self {
        Self(
            quickAdd: defaults.string(forKey: GlobalHotKeyService.quickAddDefaultsKey) ?? defaultQuickAdd,
            quickPanel: defaults.string(forKey: GlobalHotKeyService.quickPanelDefaultsKey) ?? defaultQuickPanel
        )
    }

    func persist(to defaults: UserDefaults = .standard) {
        defaults.set(quickAdd, forKey: GlobalHotKeyService.quickAddDefaultsKey)
        defaults.set(quickPanel, forKey: GlobalHotKeyService.quickPanelDefaultsKey)
    }
}

enum MacShortcutApplyResult: Equatable, Sendable {
    case success
    case failure(String)
}

typealias MacShortcutApplyHandler = @MainActor (MacShortcutConfiguration) async -> MacShortcutApplyResult

@MainActor
enum MacShortcutTransaction {
    static func apply(
        _ candidate: MacShortcutConfiguration,
        using service: GlobalHotKeyService,
        defaults: UserDefaults = .standard
    ) -> MacShortcutApplyResult {
        do {
            try service.apply(GlobalHotKeyService.Configuration(
                quickAddKey: candidate.quickAdd,
                quickPanelKey: candidate.quickPanel
            ))
            candidate.persist(to: defaults)
            return .success
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}
