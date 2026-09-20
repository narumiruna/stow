import Foundation
#if os(macOS)
import Security
#endif

public enum StowSharedStorage {
    public static let appGroupIdentifier = "group.dev.narumi.stow"
    public static let cloudKitContainerIdentifier = "iCloud.dev.narumi.stow"
    public static let developmentContainerPathEnvironmentKey = "STOW_SHARED_CONTAINER_PATH"

    public static func sharedContainerURL(
        developmentOverridePath: String? = nil,
        appGroupContainerURL: URL?,
        fallbackURL: URL
    ) -> URL {
        if let developmentOverridePath, !developmentOverridePath.isEmpty {
            return URL(fileURLWithPath: developmentOverridePath, isDirectory: true).standardizedFileURL
        }
        return appGroupContainerURL ?? fallbackURL
    }

    public static func simulatorContainerURL(simulatorUDID: String?) -> URL {
        URL(
            fileURLWithPath: "/tmp/StowSimulatorAppGroup/\(simulatorUDID ?? "unknown")",
            isDirectory: true
        )
    }

    public static func developmentFallbackContainerURL(
        fileManager: FileManager = .default
    ) -> URL {
        fileManager.temporaryDirectory
            .appendingPathComponent("StowDevelopmentAppGroup", isDirectory: true)
    }

    public static func macOSContainerURL(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        developmentOverridePath: String? = nil
    ) -> URL {
        #if os(macOS)
        let hasEntitlement = hasAppGroupEntitlement()
        let appGroupURL = hasEntitlement
            ? fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
            : nil
        return macOSContainerURL(
            fileManager: fileManager,
            environment: environment,
            developmentOverridePath: developmentOverridePath,
            hasAppGroupEntitlement: hasEntitlement,
            appGroupContainerURL: appGroupURL
        )
        #else
        preconditionFailure("The CLI shared-container locator is available only on macOS.")
        #endif
    }

    #if os(macOS)
    static func macOSContainerURL(
        fileManager: FileManager,
        environment: [String: String],
        developmentOverridePath: String?,
        hasAppGroupEntitlement: Bool,
        appGroupContainerURL: URL?
    ) -> URL {
        #if DEBUG
        let overridePath = developmentOverridePath
            ?? environment[developmentContainerPathEnvironmentKey]
        #else
        let overridePath: String? = nil
        #endif
        #if DEBUG
        let fallback = developmentFallbackContainerURL(fileManager: fileManager)
        #else
        let fallback = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stow", isDirectory: true)
        #endif
        let container = sharedContainerURL(
            developmentOverridePath: overridePath,
            appGroupContainerURL: hasAppGroupEntitlement ? appGroupContainerURL : nil,
            fallbackURL: fallback
        )
        try? fileManager.createDirectory(at: container, withIntermediateDirectories: true)
        return container
    }
    #endif

    public static func automationRootURL(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        macOSContainerURL(fileManager: fileManager, environment: environment)
            .appendingPathComponent("Automation", isDirectory: true)
    }

    private static func hasAppGroupEntitlement() -> Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let groups = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.security.application-groups" as CFString,
                nil
              ) as? [String] else {
            return false
        }
        return groups.contains(appGroupIdentifier)
        #else
        return false
        #endif
    }
}
