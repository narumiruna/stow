import Foundation

public struct StowShareSettings {
    public static let saveImmediatelyKey = "saveSharedItemsImmediately"

    private let defaults: UserDefaults?
    private let simulatorFileURL: URL?

    public init(defaults: UserDefaults? = nil) {
        if let defaults {
            self.defaults = defaults
            simulatorFileURL = nil
            return
        }
        #if targetEnvironment(simulator)
        self.defaults = nil
        let simulatorID = ProcessInfo.processInfo.environment["SIMULATOR_UDID"] ?? "unknown"
        simulatorFileURL = URL(fileURLWithPath: "/tmp/StowSimulatorAppGroup/\(simulatorID)", isDirectory: true)
            .appendingPathComponent("ShareSettings/saveImmediately", isDirectory: false)
        #else
        self.defaults = UserDefaults(suiteName: StowSharedStorage.appGroupIdentifier) ?? .standard
        simulatorFileURL = nil
        #endif
    }

    public var savesSharedItemsImmediately: Bool {
        get {
            if let defaults { return defaults.bool(forKey: Self.saveImmediatelyKey) }
            guard let simulatorFileURL, let data = try? Data(contentsOf: simulatorFileURL) else { return false }
            return data == Data([1])
        }
        nonmutating set {
            if let defaults {
                defaults.set(newValue, forKey: Self.saveImmediatelyKey)
                return
            }
            guard let simulatorFileURL else { return }
            try? FileManager.default.createDirectory(at: simulatorFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data([newValue ? 1 : 0]).write(to: simulatorFileURL, options: .atomic)
        }
    }
}
