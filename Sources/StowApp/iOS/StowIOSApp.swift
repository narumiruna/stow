import StowCore
import SwiftUI

@main
struct StowIOSApp: App {
    @State private var model: AppModel
    @State private var preferences: IOSPreferences
    private let container = StowEnvironment.makeContainer()

    init() {
        let preferences = Self.makePreferences()
        _preferences = State(initialValue: preferences)
        _model = State(initialValue: AppModel(automaticLinkPreviewsEnabled: preferences.automaticLinkPreviewsEnabled))
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            StowShareSettings().savesSharedItemsImmediately = false
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            StowSceneView(model: model, preferences: preferences)
                .modelContainer(container)
        }
    }

    private static func makePreferences() -> IOSPreferences {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let prefix = "--ui-testing-preferences-id="
            let argument = ProcessInfo.processInfo.arguments.first { $0.hasPrefix(prefix) }
            let id = argument.flatMap { UUID(uuidString: String($0.dropFirst(prefix.count))) } ?? UUID()
            // Only a dedicated test domain is used. Never reset the real device settings.
            let defaults = UserDefaults(suiteName: "dev.narumi.stow.uitests.\(id.uuidString)")!
            return IOSPreferences(defaults: defaults)
        }
        #endif
        return IOSPreferences()
    }
}
