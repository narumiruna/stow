import Foundation
import XCTest
@testable import StowCore

#if os(macOS)
final class StowSharedStorageTests: XCTestCase {
    func testUnentitledDebugProcessUsesDevelopmentFallback() {
        let expected = FileManager.default.temporaryDirectory
            .appendingPathComponent("StowDevelopmentAppGroup", isDirectory: true)
            .standardizedFileURL

        XCTAssertEqual(StowSharedStorage.macOSContainerURL(environment: [:]).standardizedFileURL, expected)
        XCTAssertEqual(
            StowSharedStorage.automationRootURL(environment: [:]).standardizedFileURL,
            expected.appendingPathComponent("Automation", isDirectory: true).standardizedFileURL
        )
    }

    func testExplicitDevelopmentContainerKeepsHostAndCLIOnOneRoot() throws {
        let root = URL(fileURLWithPath: "/tmp/StowSharedStorageTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = [StowSharedStorage.developmentContainerPathEnvironmentKey: root.path]

        XCTAssertEqual(
            StowSharedStorage.macOSContainerURL(environment: environment).standardizedFileURL,
            root.standardizedFileURL
        )
        XCTAssertEqual(
            StowSharedStorage.automationRootURL(environment: environment).standardizedFileURL,
            root.appendingPathComponent("Automation", isDirectory: true).standardizedFileURL
        )
        var isDirectory = ObjCBool(false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }
}
#endif
