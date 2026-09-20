import StowCore
import SwiftUI

@main
struct StowIOSApp: App {
    @State private var model = AppModel()
    private let container = StowEnvironment.makeContainer()

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            StowShareSettings().savesSharedItemsImmediately = false
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            StowRootView()
                .environment(model)
                .modelContainer(container)
        }
    }
}
