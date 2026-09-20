import Foundation
import XCTest
@testable import StowCore

final class StowShareSettingsTests: XCTestCase {
    func testDirectSaveDefaultsOffAndPersistsAcrossInstances() throws {
        let suiteName = "StowShareSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = StowShareSettings(defaults: defaults)
        XCTAssertFalse(settings.savesSharedItemsImmediately)

        settings.savesSharedItemsImmediately = true

        XCTAssertTrue(StowShareSettings(defaults: defaults).savesSharedItemsImmediately)
    }
}
