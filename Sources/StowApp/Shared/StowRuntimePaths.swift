import Foundation

/// Storage owned by one app runtime. Tests supply both roots, not just an in-memory database.
struct StowRuntimePaths {
    let sharedContainer: URL
    let temporaryDirectory: URL

    static var current: Self {
        Self(sharedContainer: StowEnvironment.sharedContainerURL(),
             temporaryDirectory: StowEnvironment.temporaryDirectory)
    }
}
