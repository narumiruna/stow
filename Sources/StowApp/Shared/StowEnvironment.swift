import Foundation
import Security
import SwiftData
import StowCore

public enum StowEnvironment {
    public static let appGroupIdentifier = StowSharedStorage.appGroupIdentifier
    public static let cloudKitContainerIdentifier = StowSharedStorage.cloudKitContainerIdentifier
    @MainActor static private(set) var currentContainerUsesCloud = false

    @MainActor
    static func makeContainer() -> ModelContainer {
        currentContainerUsesCloud = false
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            return try! StowContainerFactory.inMemory()
        }
        #endif
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
        #if os(macOS)
        #if DEBUG
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--stow-shared-container-path=") }),
           let path = argument.split(separator: "=", maxSplits: 1).last,
           !path.isEmpty {
            let override = URL(fileURLWithPath: String(path), isDirectory: true).standardizedFileURL
            try? FileManager.default.createDirectory(at: override, withIntermediateDirectories: true)
            return override
        }
        #endif
        return StowSharedStorage.macOSContainerURL()
        #elseif targetEnvironment(simulator)
        let simulatorID = ProcessInfo.processInfo.environment["SIMULATOR_UDID"] ?? "unknown"
        let simulatorURL = URL(fileURLWithPath: "/tmp/StowSimulatorAppGroup/\(simulatorID)", isDirectory: true)
        try? FileManager.default.createDirectory(at: simulatorURL, withIntermediateDirectories: true)
        return simulatorURL
        #else
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return groupURL
        }
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stow", isDirectory: true)
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
