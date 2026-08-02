import SwiftUI

@main
struct StowIOSApp: App {
    @State private var model = AppModel()
    private let container = StowEnvironment.makeContainer()

    var body: some Scene {
        WindowGroup {
            StowRootView()
                .environment(model)
                .modelContainer(container)
        }
    }
}
