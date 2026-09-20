import Foundation
import Security
import SwiftData
import StowCore

public enum StowEnvironment {
    public static let appGroupIdentifier = StowSharedStorage.appGroupIdentifier
    public static let cloudKitContainerIdentifier = StowSharedStorage.cloudKitContainerIdentifier
    @MainActor static private(set) var currentContainerUsesCloud = false

    static var isUnitTestHost: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
        #else
        false
        #endif
    }

    private static let testRoot: URL = {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("StowTestHost-\(UUID().uuidString)", isDirectory: true)
        atexit { try? FileManager.default.removeItem(at: StowEnvironment.testRoot) }
        return root
    }()

    static var temporaryDirectory: URL {
        isUnitTestHost ? testRoot.appendingPathComponent("Temporary", isDirectory: true)
            : FileManager.default.temporaryDirectory
    }

    @MainActor
    static func makeContainer() -> ModelContainer {
        currentContainerUsesCloud = false
        #if DEBUG
        if isUnitTestHost || ProcessInfo.processInfo.arguments.contains("--ui-testing") {
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
        if isUnitTestHost { return testRoot.appendingPathComponent("Shared", isDirectory: true) }
        #if os(macOS)
        #if DEBUG
        let overridePath = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("--stow-shared-container-path=") })?
            .split(separator: "=", maxSplits: 1)
            .last
            .flatMap { $0.isEmpty ? nil : String($0) }
        #else
        let overridePath: String? = nil
        #endif
        return StowSharedStorage.macOSContainerURL(developmentOverridePath: overridePath)
        #elseif targetEnvironment(simulator)
        let simulatorURL = StowSharedStorage.simulatorContainerURL(
            simulatorUDID: ProcessInfo.processInfo.environment["SIMULATOR_UDID"]
        )
        try? FileManager.default.createDirectory(at: simulatorURL, withIntermediateDirectories: true)
        return simulatorURL
        #else
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stow", isDirectory: true)
        let container = StowSharedStorage.sharedContainerURL(
            appGroupContainerURL: FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier
            ),
            fallbackURL: fallback
        )
        try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        return container
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
