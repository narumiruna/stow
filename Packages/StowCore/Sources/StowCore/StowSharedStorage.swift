import Foundation
#if os(macOS)
import Security
#endif

public enum StowSharedStorage {
    public static let appGroupIdentifier = "group.dev.narumi.stow"
    public static let cloudKitContainerIdentifier = "iCloud.dev.narumi.stow"

    public static func macOSContainerURL(fileManager: FileManager = .default) -> URL {
        #if os(macOS)
        if hasAppGroupEntitlement(),
           let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return groupURL
        }
        #if DEBUG
        let fallback = fileManager.temporaryDirectory.appendingPathComponent("StowDevelopmentAppGroup", isDirectory: true)
        #else
        let fallback = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stow", isDirectory: true)
        #endif
        try? fileManager.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
        #else
        preconditionFailure("The CLI shared-container locator is available only on macOS.")
        #endif
    }

    public static func automationRootURL(fileManager: FileManager = .default) -> URL {
        macOSContainerURL(fileManager: fileManager).appendingPathComponent("Automation", isDirectory: true)
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
