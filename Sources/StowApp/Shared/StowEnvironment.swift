import Foundation
import Security
import SwiftData
import StowCore

public enum StowEnvironment {
    public static let appGroupIdentifier = "group.app.stow.Stow"
    public static let cloudKitContainerIdentifier = "iCloud.app.stow.Stow"
    @MainActor static private(set) var currentContainerUsesCloud = false

    @MainActor
    static func makeContainer() -> ModelContainer {
        currentContainerUsesCloud = false
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            return try! StowContainerFactory.inMemory()
        }
        if hasCloudKitEntitlement() {
            do {
                let container = try StowContainerFactory.sharedHost(
                    appGroupIdentifier: appGroupIdentifier,
                    cloudKitContainerIdentifier: cloudKitContainerIdentifier
                )
                currentContainerUsesCloud = true
                return container
            } catch {
                // Keep the same App Group store local so a later entitled launch can synchronize it.
            }
        }
        let groupRoot = sharedContainerURL()
        let base = groupRoot.appendingPathComponent("Library/Application Support", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        do {
            return try StowContainerFactory.local(url: base.appendingPathComponent("Stow.store"))
        } catch {
            fatalError("Unable to initialize Stow persistence: \(error.localizedDescription)")
        }
    }

    static func sharedContainerURL() -> URL {
        #if targetEnvironment(simulator)
        let simulatorID = ProcessInfo.processInfo.environment["SIMULATOR_UDID"] ?? "unknown"
        let simulatorURL = URL(fileURLWithPath: "/tmp/StowSimulatorAppGroup/\(simulatorID)", isDirectory: true)
        try? FileManager.default.createDirectory(at: simulatorURL, withIntermediateDirectories: true)
        return simulatorURL
        #else
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return groupURL
        }
        #if DEBUG && os(macOS)
        let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("StowDevelopmentAppGroup", isDirectory: true)
        #else
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stow", isDirectory: true)
        #endif
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
        #endif
    }

    static func hasCloudKitEntitlement() -> Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil) as? [String] else {
            return false
        }
        return value.contains(cloudKitContainerIdentifier)
        #elseif targetEnvironment(simulator)
        return false
        #else
        // A device build reaches users only after provisioning validates this committed entitlement.
        return true
        #endif
    }
}
