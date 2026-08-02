import SwiftUI

@main
struct StowMacApp: App {
    @NSApplicationDelegateAdaptor(MacAppCoordinator.self) private var appDelegate
    @State private var model = AppModel()
    private let container = StowEnvironment.makeContainer()

    var body: some Scene {
        WindowGroup {
            StowRootView()
                .environment(model)
                .modelContainer(container)
                .frame(minWidth: 840, minHeight: 560)
                .task { appDelegate.configure(model: model, container: container) }
        }
        .commands { StowCommands(model: model) }

        Settings {
            StowSettingsView()
                .environment(model)
                .modelContainer(container)
        }
    }
}

private struct StowCommands: Commands {
    let model: AppModel
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Quick Add…") { model.isAdding = true }
                .keyboardShortcut("s", modifiers: [.option, .shift])
            Button("Quick Panel…") { NotificationCenter.default.post(name: .stowShowQuickPanel, object: nil) }
                .keyboardShortcut("v", modifiers: [.command, .shift])
        }
    }
}

