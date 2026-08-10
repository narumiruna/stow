import SwiftData
import SwiftUI

@main
struct StowMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppCoordinator.self) private var appDelegate
    @State private var model: AppModel
    private let container: ModelContainer

    init() {
        let container = StowEnvironment.makeContainer()
        let model = AppModel()
        model.connect(ModelContext(container))
        self.container = container
        _model = State(initialValue: model)
        MacAppCoordinator.install(model: model, container: container)
    }

    var body: some Scene {
        WindowGroup("Stow", id: "library") {
            StowRootView()
                .environment(model)
                .modelContainer(container)
                .frame(minWidth: 840, minHeight: 560)
                .task { appDelegate.configure(model: model, container: container) }
        }
        .commands { StowCommands(model: model) }

        MenuBarExtra("Stow", systemImage: "shippingbox.fill") {
            StowMenuBarView {
                appDelegate.configure(model: model, container: container)
            }
            .environment(model)
            .modelContainer(container)
        }

        Settings {
            StowSettingsView()
                .environment(model)
                .modelContainer(container)
        }
    }
}

private struct StowMenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var modelContext
    @AppStorage("clipboardMonitoringEnabled") private var clipboardMonitoringEnabled = true
    let onReady: () -> Void

    var body: some View {
        Button("Show Stow") { NotificationCenter.default.post(name: .stowShowQuickPanel, object: nil) }
            .keyboardShortcut("v", modifiers: [.command, .shift])
        Button("Quick Add…") { NotificationCenter.default.post(name: .stowShowQuickAdd, object: nil) }
        Button("Open Library") { openLibrary() }
        Divider()
        Toggle("Monitor Clipboard", isOn: $clipboardMonitoringEnabled)
        Text(model.privacyStorageText)
            .foregroundStyle(.secondary)
        Divider()
        Button("Settings…") { NotificationCenter.default.post(name: .stowOpenSettings, object: nil) }
        Button("Quit Stow") { NSApp.terminate(nil) }
        .task {
            model.connect(modelContext)
            onReady()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") && !ProcessInfo.processInfo.arguments.contains("--ui-testing-utility-mode") { openLibrary() }
            #endif
        }
        .onChange(of: clipboardMonitoringEnabled) { _, _ in
            NotificationCenter.default.post(name: .stowClipboardMonitoringChanged, object: nil)
        }
    }

    private func openLibrary() {
        NotificationCenter.default.post(name: .stowOpenLibrary, object: nil)
    }
}

private struct StowCommands: Commands {
    let model: AppModel
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Quick Add…") { NotificationCenter.default.post(name: .stowShowQuickAdd, object: nil) }
                .keyboardShortcut("s", modifiers: [.option, .shift])
            Button("Quick Panel…") { NotificationCenter.default.post(name: .stowShowQuickPanel, object: nil) }
                .keyboardShortcut("v", modifiers: [.command, .shift])
        }
    }
}

