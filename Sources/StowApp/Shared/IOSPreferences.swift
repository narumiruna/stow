import Foundation
import Observation

enum IOSLockDelay: Int, CaseIterable, Identifiable {
    case immediately = 0
    case oneMinute = 60
    case fiveMinutes = 300

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }

    var title: String {
        switch self {
        case .immediately: "Immediately"
        case .oneMinute: "1 minute"
        case .fiveMinutes: "5 minutes"
        }
    }
}

enum IOSLaunchPage: String, CaseIterable, Identifiable {
    case inbox
    case pinned
    case recent
    case lastLibrarySection

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .pinned: "Pinned"
        case .recent: "Recently Used"
        case .lastLibrarySection: "Last Library Section"
        }
    }
}

enum IOSAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// Device-local preferences. The caller owns authentication for App Lock changes.
@MainActor
@Observable
final class IOSPreferences {
    enum Key {
        static let appLockEnabled = "ios.appLockEnabled"
        static let lockDelay = "ios.lockDelay"
        static let automaticLinkPreviewsEnabled = "ios.automaticLinkPreviewsEnabled"
        static let launchPage = "ios.launchPage"
        static let appearance = "ios.appearance"
        static let lastLibrarySection = "ios.lastLibrarySection"
    }

    @ObservationIgnored private let defaults: UserDefaults

    private(set) var appLockEnabled: Bool
    private(set) var lockDelay: IOSLockDelay
    private(set) var protectionRevision = 0

    var automaticLinkPreviewsEnabled: Bool {
        didSet { defaults.set(automaticLinkPreviewsEnabled, forKey: Key.automaticLinkPreviewsEnabled) }
    }

    var launchPage: IOSLaunchPage {
        didSet { defaults.set(launchPage.rawValue, forKey: Key.launchPage) }
    }

    var appearance: IOSAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    private var lastLibrarySection: StowSection

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // A missing preference is a new installation. Any malformed existing flag keeps the gate closed.
        if let storedLock = defaults.object(forKey: Key.appLockEnabled) {
            appLockEnabled = Self.storedBoolean(storedLock) ?? true
        } else {
            appLockEnabled = false
        }
        lockDelay = (defaults.object(forKey: Key.lockDelay) as? Int)
            .flatMap(IOSLockDelay.init(rawValue:)) ?? .immediately
        automaticLinkPreviewsEnabled = Self.storedBoolean(
            defaults.object(forKey: Key.automaticLinkPreviewsEnabled)
        ) ?? false
        launchPage = (defaults.object(forKey: Key.launchPage) as? String)
            .flatMap(IOSLaunchPage.init(rawValue:)) ?? .inbox
        appearance = (defaults.object(forKey: Key.appearance) as? String)
            .flatMap(IOSAppearance.init(rawValue:)) ?? .system
        switch defaults.object(forKey: Key.lastLibrarySection) as? String {
        case "recent": lastLibrarySection = .recent
        case "pinned": lastLibrarySection = .pinned
        case "archive": lastLibrarySection = .archive
        default: lastLibrarySection = .inbox
        }
    }

    func commitAppLock(enabled: Bool) {
        let changed = enabled != appLockEnabled
        defaults.set(enabled, forKey: Key.appLockEnabled)
        appLockEnabled = enabled
        if changed { protectionRevision += 1 }
    }

    func commitLockDelay(_ delay: IOSLockDelay) {
        let changed = delay != lockDelay
        defaults.set(delay.rawValue, forKey: Key.lockDelay)
        lockDelay = delay
        if changed { protectionRevision += 1 }
    }

    var initialSection: StowSection {
        switch launchPage {
        case .inbox: .inbox
        case .pinned: .pinned
        case .recent: .recent
        case .lastLibrarySection: lastLibrarySection
        }
    }

    func recordLibrarySection(_ section: StowSection) {
        let identifier: String
        switch section {
        case .inbox: identifier = "inbox"
        case .recent: identifier = "recent"
        case .pinned: identifier = "pinned"
        case .archive: identifier = "archive"
        case .settings, .trash: return
        }
        defaults.set(identifier, forKey: Key.lastLibrarySection)
        lastLibrarySection = section
    }

    private static func storedBoolean(_ value: Any?) -> Bool? {
        // UserDefaults.bool(forKey:) also accepts strings and numbers. Do not accept those for security flags.
        guard let number = value as? NSNumber,
              String(cString: number.objCType) == String(cString: NSNumber(value: true).objCType) else {
            return nil
        }
        return number.boolValue
    }
}
