import Foundation
import XCTest
@testable import StowCore

#if os(macOS)
final class StowSharedStorageTests: XCTestCase {
    func testUnentitledDebugProcessUsesDevelopmentFallback() {
        let expected = FileManager.default.temporaryDirectory
            .appendingPathComponent("StowDevelopmentAppGroup", isDirectory: true)
            .standardizedFileURL

        XCTAssertEqual(StowSharedStorage.macOSContainerURL().standardizedFileURL, expected)
        XCTAssertEqual(
            StowSharedStorage.automationRootURL().standardizedFileURL,
            expected.appendingPathComponent("Automation", isDirectory: true).standardizedFileURL
        )
    }
}
#endif
