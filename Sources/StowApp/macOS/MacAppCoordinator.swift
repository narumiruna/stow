import AppKit
import SwiftData
import SwiftUI

@MainActor
final class MacAppCoordinator: NSObject, NSApplicationDelegate {
    static let shared = MacAppCoordinator()
    private let hotKeys = GlobalHotKeyService()
    private let retrievalPanel = RetrievalPanelController()
    private let quickCapturePanel = QuickCapturePanelController()
    private weak var model: AppModel?
    private var container: ModelContainer?
    private var pendingAction: GlobalHotKeyService.Action?
    private var pendingRegistrationError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(self, selector: #selector(reloadHotKeys), name: .stowHotKeysChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showQuickPanel), name: .stowShowQuickPanel, object: nil)
        hotKeys.handler = { [weak self] action in self?.handle(action) }
        registerHotKeys()
    }

    @objc private func reloadHotKeys() { registerHotKeys() }
    @objc private func showQuickPanel() { handle(.quickPanel) }

    private func registerHotKeys() {
        do {
            try hotKeys.registerDefaults()
            pendingRegistrationError = nil
            model?.globalShortcutStatus = "Registered"
        } catch {
            pendingRegistrationError = error.localizedDescription
            model?.globalShortcutStatus = error.localizedDescription
            model?.presentedError = error.localizedDescription
        }
    }

    func configure(model: AppModel, container: ModelContainer) {
        self.model = model
        self.container = container
        registerHotKeys()
        if let pendingRegistrationError { model.presentedError = pendingRegistrationError }
        if let pendingAction {
            self.pendingAction = nil
            handle(pendingAction)
        }
    }

    private func handle(_ action: GlobalHotKeyService.Action) {
        guard model != nil, container != nil else {
            pendingAction = action
            return
        }
        switch action {
        case .quickAdd:
            if let model, let container { quickCapturePanel.present(model: model, container: container) }
        case .quickPanel:
            if let model, let container { retrievalPanel.present(model: model, container: container) }
        }
    }
}

extension Notification.Name {
    static let stowHotKeysChanged = Notification.Name("StowHotKeysChanged")
    static let stowShowQuickPanel = Notification.Name("StowShowQuickPanel")
}

@MainActor
private final class QuickCapturePanelController {
    private var panel: NSPanel?

    func present(model: AppModel, container: ModelContainer) {
        model.isAdding = true
        if panel == nil {
            let root = QuickAddView()
                .environment(model)
                .modelContainer(container)
                .onChange(of: model.isAdding) { [weak self] _, presented in
                    if !presented { self?.panel?.orderOut(nil) }
                }
            let host = NSHostingController(rootView: root)
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 620), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            panel.title = "Quick Add to Stow"
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.isReleasedWhenClosed = false
            panel.contentViewController = host
            panel.center()
            self.panel = panel
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }
}
