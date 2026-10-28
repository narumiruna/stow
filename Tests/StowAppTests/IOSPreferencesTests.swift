import Foundation
import Observation
import StowCore
import XCTest
@testable import StowApp

@MainActor
final class IOSPreferencesTests: XCTestCase {
    func testDefaultsDoNotWritePreferences() throws {
        try withDefaults { defaults, suiteName in
            let before = defaults.persistentDomain(forName: suiteName) ?? [:]
            let preferences = IOSPreferences(defaults: defaults)

            XCTAssertFalse(preferences.appLockEnabled)
            XCTAssertEqual(preferences.lockDelay, .immediately)
            XCTAssertFalse(preferences.automaticLinkPreviewsEnabled)
            XCTAssertEqual(preferences.launchPage, .inbox)
            XCTAssertEqual(preferences.appearance, .system)
            XCTAssertEqual(preferences.initialSection, .inbox)
            XCTAssertEqual((defaults.persistentDomain(forName: suiteName) ?? [:]) as NSDictionary, before as NSDictionary)
        }
    }

    func testUpgradeWithoutPreviewPreferenceKeepsPreviewsOff() throws {
        try withDefaults { defaults, suiteName in
            defaults.set(true, forKey: "analyticsEnabled")
            StowShareSettings(defaults: defaults).savesSharedItemsImmediately = true
            let before = defaults.persistentDomain(forName: suiteName) ?? [:]

            XCTAssertFalse(IOSPreferences(defaults: defaults).automaticLinkPreviewsEnabled)
            XCTAssertNil(defaults.object(forKey: IOSPreferences.Key.automaticLinkPreviewsEnabled))
            XCTAssertEqual(defaults.persistentDomain(forName: suiteName) as NSDictionary?, before as NSDictionary)
        }
    }

    func testNewInstanceRestoresAllPreferencesFromOnlyItsSuite() throws {
        try withDefaults { defaults, suiteName in
            let preferences = IOSPreferences(defaults: defaults)
            preferences.commitAppLock(enabled: true)
            preferences.commitLockDelay(.fiveMinutes)
            preferences.automaticLinkPreviewsEnabled = true
            preferences.launchPage = .lastLibrarySection
            preferences.appearance = .dark
            preferences.recordLibrarySection(.archive)

            let reopenedDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            let restored = IOSPreferences(defaults: reopenedDefaults)
            XCTAssertTrue(restored.appLockEnabled)
            XCTAssertEqual(restored.lockDelay, .fiveMinutes)
            XCTAssertTrue(restored.automaticLinkPreviewsEnabled)
            XCTAssertEqual(restored.launchPage, .lastLibrarySection)
            XCTAssertEqual(restored.appearance, .dark)
            XCTAssertEqual(restored.initialSection, .archive)

            try withDefaults { otherDefaults, _ in
                let isolated = IOSPreferences(defaults: otherDefaults)
                XCTAssertFalse(isolated.appLockEnabled)
                XCTAssertEqual(isolated.lockDelay, .immediately)
                XCTAssertFalse(isolated.automaticLinkPreviewsEnabled)
                XCTAssertEqual(isolated.launchPage, .inbox)
                XCTAssertEqual(isolated.appearance, .system)
                XCTAssertEqual(isolated.initialSection, .inbox)
            }
        }
    }

    func testEveryChoiceRoundTripsAndUsesStableStoredValues() throws {
        try withDefaults { defaults, _ in
            let preferences = IOSPreferences(defaults: defaults)
            for enabled in [true, false] {
                preferences.commitAppLock(enabled: enabled)
                preferences.automaticLinkPreviewsEnabled = enabled
                XCTAssertEqual(defaults.object(forKey: IOSPreferences.Key.appLockEnabled) as? Bool, enabled)
                XCTAssertEqual(defaults.object(forKey: IOSPreferences.Key.automaticLinkPreviewsEnabled) as? Bool, enabled)
                let restored = IOSPreferences(defaults: defaults)
                XCTAssertEqual(restored.appLockEnabled, enabled)
                XCTAssertEqual(restored.automaticLinkPreviewsEnabled, enabled)
            }
            for delay in IOSLockDelay.allCases {
                preferences.commitLockDelay(delay)
                XCTAssertEqual(defaults.object(forKey: IOSPreferences.Key.lockDelay) as? Int, delay.rawValue)
                XCTAssertEqual(IOSPreferences(defaults: defaults).lockDelay, delay)
            }
            for page in IOSLaunchPage.allCases {
                preferences.launchPage = page
                XCTAssertEqual(defaults.string(forKey: IOSPreferences.Key.launchPage), page.rawValue)
                XCTAssertEqual(IOSPreferences(defaults: defaults).launchPage, page)
            }
            for appearance in IOSAppearance.allCases {
                preferences.appearance = appearance
                XCTAssertEqual(defaults.string(forKey: IOSPreferences.Key.appearance), appearance.rawValue)
                XCTAssertEqual(IOSPreferences(defaults: defaults).appearance, appearance)
            }
        }
    }

    func testMalformedExistingLockFlagsFailClosedWithoutRewritingThem() throws {
        let invalidValues: [Any] = [
            "false", "true", "0", "", 0, 1, 2, -1, 0.5,
            Data([0]), [false], ["enabled": false],
        ]
        try withDefaults { defaults, suiteName in
            for value in invalidValues {
                defaults.set(value, forKey: IOSPreferences.Key.appLockEnabled)
                let before = defaults.persistentDomain(forName: suiteName) ?? [:]

                XCTAssertTrue(IOSPreferences(defaults: defaults).appLockEnabled, "Stored value: \(value)")
                XCTAssertEqual(defaults.persistentDomain(forName: suiteName) as NSDictionary?, before as NSDictionary)
            }
            defaults.set(false, forKey: IOSPreferences.Key.appLockEnabled)
            XCTAssertFalse(IOSPreferences(defaults: defaults).appLockEnabled)
            defaults.set(true, forKey: IOSPreferences.Key.appLockEnabled)
            XCTAssertTrue(IOSPreferences(defaults: defaults).appLockEnabled)
        }
    }

    func testInvalidDelayNeverExtendsTheGracePeriod() throws {
        let invalidValues: [Any] = [
            -1, 1, 59, 301, Int.max, 60.5, 300.5, "60", "fiveMinutes", true, false,
            Data([60]), [60], ["seconds": 60],
        ]
        try withDefaults { defaults, _ in
            for value in invalidValues {
                defaults.set(value, forKey: IOSPreferences.Key.lockDelay)
                XCTAssertEqual(IOSPreferences(defaults: defaults).lockDelay, .immediately, "Stored value: \(value)")
            }
        }
    }

    func testInvalidBrowsingAppearanceAndPreviewValuesUseSafeDefaultsWithoutWrites() throws {
        let invalidValues: [Any] = [
            "unknown", "Inbox", "System", "", "false", 0, 1, false,
            Data([1]), ["inbox"], ["value": "dark"],
        ]
        try withDefaults { defaults, suiteName in
            for value in invalidValues {
                defaults.set(value, forKey: IOSPreferences.Key.launchPage)
                defaults.set(value, forKey: IOSPreferences.Key.appearance)
                defaults.set(value, forKey: IOSPreferences.Key.automaticLinkPreviewsEnabled)
                let before = defaults.persistentDomain(forName: suiteName) ?? [:]
                let preferences = IOSPreferences(defaults: defaults)

                XCTAssertEqual(preferences.launchPage, .inbox, "Stored value: \(value)")
                XCTAssertEqual(preferences.initialSection, .inbox)
                XCTAssertEqual(preferences.appearance, .system, "Stored value: \(value)")
                XCTAssertFalse(preferences.automaticLinkPreviewsEnabled, "Stored value: \(value)")
                XCTAssertEqual(defaults.persistentDomain(forName: suiteName) as NSDictionary?, before as NSDictionary)
            }
        }
    }

    func testLaunchPageSelectionMapsToExistingSections() throws {
        try withDefaults { defaults, _ in
            let preferences = IOSPreferences(defaults: defaults)
            preferences.recordLibrarySection(.archive)
            let cases: [(IOSLaunchPage, StowSection)] = [
                (.inbox, .inbox), (.pinned, .pinned), (.recent, .recent), (.lastLibrarySection, .archive),
            ]
            for (page, section) in cases {
                preferences.launchPage = page
                XCTAssertEqual(preferences.initialSection, section)
                XCTAssertEqual(IOSPreferences(defaults: defaults).initialSection, section)
            }
        }
    }

    func testOnlySafeLibrarySectionsAreRecordedWithStableIdentifiers() throws {
        try withDefaults { defaults, suiteName in
            let preferences = IOSPreferences(defaults: defaults)
            preferences.launchPage = .lastLibrarySection
            let safeSections: [(StowSection, String)] = [
                (.inbox, "inbox"), (.recent, "recent"), (.pinned, "pinned"), (.archive, "archive"),
            ]
            for (section, identifier) in safeSections {
                preferences.recordLibrarySection(section)
                XCTAssertEqual(defaults.string(forKey: IOSPreferences.Key.lastLibrarySection), identifier)
                XCTAssertEqual(preferences.initialSection, section)
                XCTAssertEqual(IOSPreferences(defaults: defaults).initialSection, section)

                let before = defaults.persistentDomain(forName: suiteName) ?? [:]
                for excluded in [StowSection.settings, .trash] {
                    preferences.recordLibrarySection(excluded)
                    XCTAssertEqual(preferences.initialSection, section)
                    XCTAssertEqual(IOSPreferences(defaults: defaults).initialSection, section)
                    XCTAssertEqual(defaults.persistentDomain(forName: suiteName) as NSDictionary?, before as NSDictionary)
                }
            }
        }
    }

    func testExcludedSectionsDoNotCreateAStoredLastSection() throws {
        try withDefaults { defaults, _ in
            let preferences = IOSPreferences(defaults: defaults)
            preferences.launchPage = .lastLibrarySection
            preferences.recordLibrarySection(.settings)
            preferences.recordLibrarySection(.trash)

            XCTAssertNil(defaults.object(forKey: IOSPreferences.Key.lastLibrarySection))
            XCTAssertEqual(preferences.initialSection, .inbox)
            XCTAssertEqual(IOSPreferences(defaults: defaults).initialSection, .inbox)
        }
    }

    func testInvalidStoredLastSectionFallsBackToInboxWithoutWrites() throws {
        let invalidValues: [Any] = [
            "settings", "trash", "Settings", "Trash", "Archive", "unknown", "", 1, true,
            Data([1]), ["archive"], ["section": "pinned"],
        ]
        try withDefaults { defaults, suiteName in
            defaults.set(IOSLaunchPage.lastLibrarySection.rawValue, forKey: IOSPreferences.Key.launchPage)
            for value in invalidValues {
                defaults.set(value, forKey: IOSPreferences.Key.lastLibrarySection)
                let before = defaults.persistentDomain(forName: suiteName) ?? [:]

                XCTAssertEqual(IOSPreferences(defaults: defaults).initialSection, .inbox, "Stored value: \(value)")
                XCTAssertEqual(defaults.persistentDomain(forName: suiteName) as NSDictionary?, before as NSDictionary)
            }
        }
    }

    func testCommitsWriteOnlyTheirOwnKeysAndPreserveMetricsAndSharing() throws {
        try withDefaults { defaults, suiteName in
            defaults.set(false, forKey: "analyticsEnabled")
            defaults.set("keep", forKey: "unrelatedSetting")
            let shareSettings = StowShareSettings(defaults: defaults)
            shareSettings.savesSharedItemsImmediately = true
            let preferences = IOSPreferences(defaults: defaults)
            var expected = defaults.persistentDomain(forName: suiteName) ?? [:]
            let changes: [(String, Any, () -> Void)] = [
                (IOSPreferences.Key.appLockEnabled, true, { preferences.commitAppLock(enabled: true) }),
                (IOSPreferences.Key.lockDelay, 60, { preferences.commitLockDelay(.oneMinute) }),
                (IOSPreferences.Key.automaticLinkPreviewsEnabled, true, { preferences.automaticLinkPreviewsEnabled = true }),
                (IOSPreferences.Key.launchPage, "pinned", { preferences.launchPage = .pinned }),
                (IOSPreferences.Key.appearance, "light", { preferences.appearance = .light }),
                (IOSPreferences.Key.lastLibrarySection, "recent", { preferences.recordLibrarySection(.recent) }),
            ]
            for (key, value, change) in changes {
                XCTAssertTrue(key.hasPrefix("ios."))
                change()
                expected[key] = value
                XCTAssertEqual(defaults.persistentDomain(forName: suiteName) as NSDictionary?, expected as NSDictionary)
            }
            XCTAssertFalse(defaults.bool(forKey: "analyticsEnabled"))
            XCTAssertTrue(shareSettings.savesSharedItemsImmediately)
            XCTAssertEqual(defaults.string(forKey: "unrelatedSetting"), "keep")
        }
    }

    func testPreferenceChangesAreObservable() throws {
        try withDefaults { defaults, _ in
            let preferences = IOSPreferences(defaults: defaults)
            let changes: [(String, () -> Void, () -> Void)] = [
                ("app lock", { _ = preferences.appLockEnabled }, { preferences.commitAppLock(enabled: true) }),
                ("delay", { _ = preferences.lockDelay }, { preferences.commitLockDelay(.oneMinute) }),
                ("previews", { _ = preferences.automaticLinkPreviewsEnabled }, { preferences.automaticLinkPreviewsEnabled = true }),
                ("launch page", { _ = preferences.launchPage }, { preferences.launchPage = .lastLibrarySection }),
                ("appearance", { _ = preferences.appearance }, { preferences.appearance = .dark }),
                ("last section", { _ = preferences.initialSection }, { preferences.recordLibrarySection(.archive) }),
            ]
            for (name, read, change) in changes {
                let changed = expectation(description: "Observe \(name)")
                withObservationTracking { read() } onChange: { changed.fulfill() }
                change()
                wait(for: [changed], timeout: 0.1)
            }
        }
    }

    func testProtectionRevisionTracksChangesEvenIfObservationCoalescesThem() throws {
        try withDefaults { defaults, _ in
            let preferences = IOSPreferences(defaults: defaults)
            XCTAssertEqual(preferences.protectionRevision, 0)
            preferences.commitAppLock(enabled: true)
            preferences.commitAppLock(enabled: false)
            preferences.commitAppLock(enabled: true)
            XCTAssertEqual(preferences.protectionRevision, 3)
            preferences.commitLockDelay(.oneMinute)
            XCTAssertEqual(preferences.protectionRevision, 4)
            preferences.commitLockDelay(.oneMinute)
            preferences.commitAppLock(enabled: true)
            preferences.appearance = .dark
            XCTAssertEqual(preferences.protectionRevision, 4)
            XCTAssertEqual(IOSPreferences(defaults: defaults).protectionRevision, 0, "Sessions are never persisted")
        }
    }

    func testEnumIdentifiersTitlesAndDelaySecondsStayStable() {
        XCTAssertEqual(IOSLockDelay.allCases.map(\.rawValue), [0, 60, 300])
        XCTAssertEqual(IOSLockDelay.allCases.map(\.id), [0, 60, 300])
        XCTAssertEqual(IOSLockDelay.allCases.map(\.seconds), [0, 60, 300])
        XCTAssertEqual(IOSLockDelay.allCases.map(\.title), ["Immediately", "1 minute", "5 minutes"])
        XCTAssertEqual(IOSLaunchPage.allCases.map(\.rawValue), ["inbox", "pinned", "recent", "lastLibrarySection"])
        XCTAssertEqual(IOSLaunchPage.allCases.map(\.id), IOSLaunchPage.allCases.map(\.rawValue))
        XCTAssertEqual(IOSLaunchPage.allCases.map(\.title), ["Inbox", "Pinned", "Recently Used", "Last Library Section"])
        XCTAssertEqual(IOSAppearance.allCases.map(\.rawValue), ["system", "light", "dark"])
        XCTAssertEqual(IOSAppearance.allCases.map(\.id), IOSAppearance.allCases.map(\.rawValue))
        XCTAssertEqual(IOSAppearance.allCases.map(\.title), ["System", "Light", "Dark"])
    }

    private func withDefaults(_ body: (UserDefaults, String) throws -> Void) throws {
        let suiteName = "IOSPreferencesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults, suiteName)
    }
}
