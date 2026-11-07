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
        _model = State(initialValue: AppModel(
            runtimePaths: Self.galleryTestRuntimePaths(),
            automaticLinkPreviewsEnabled: preferences.automaticLinkPreviewsEnabled
        ))
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

    private static func galleryTestRuntimePaths() -> StowRuntimePaths? {
        #if DEBUG && targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing"), arguments.contains("--ui-testing-seed-gallery") {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("StowGalleryUITests-\(UUID().uuidString)", isDirectory: true)
            return StowRuntimePaths(
                sharedContainer: root.appendingPathComponent("Shared", isDirectory: true),
                temporaryDirectory: root.appendingPathComponent("Temporary", isDirectory: true)
            )
        }
        #endif
        return nil
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
