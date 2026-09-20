import Foundation
import XCTest
@testable import StowCore

final class StowSharedStorageTests: XCTestCase {
    func testSimulatorContainerUsesUDIDAndStableUnknownFallback() {
        XCTAssertEqual(
            StowSharedStorage.simulatorContainerURL(simulatorUDID: "ABC-123").path,
            "/tmp/StowSimulatorAppGroup/ABC-123"
        )
        XCTAssertEqual(
            StowSharedStorage.simulatorContainerURL(simulatorUDID: nil).path,
            "/tmp/StowSimulatorAppGroup/unknown"
        )
    }

    func testSharedContainerSelectionUsesOverrideThenAppGroupThenFallback() {
        let appGroup = URL(fileURLWithPath: "/tmp/app-group", isDirectory: true)
        let fallback = URL(fileURLWithPath: "/tmp/fallback", isDirectory: true)

        XCTAssertEqual(
            StowSharedStorage.sharedContainerURL(
                developmentOverridePath: "/tmp/../tmp/override",
                appGroupContainerURL: appGroup,
                fallbackURL: fallback
            ).standardizedFileURL,
            URL(fileURLWithPath: "/tmp/override", isDirectory: true).standardizedFileURL
        )
        XCTAssertEqual(
            StowSharedStorage.sharedContainerURL(
                appGroupContainerURL: appGroup,
                fallbackURL: fallback
            ),
            appGroup
        )
        XCTAssertEqual(
            StowSharedStorage.sharedContainerURL(
                appGroupContainerURL: nil,
                fallbackURL: fallback
            ),
            fallback
        )
    }

    #if os(macOS)
    func testUnentitledDebugProcessUsesDevelopmentFallback() {
        let expected = StowSharedStorage.developmentFallbackContainerURL().standardizedFileURL

        XCTAssertEqual(StowSharedStorage.macOSContainerURL(environment: [:]).standardizedFileURL, expected)
        XCTAssertEqual(
            StowSharedStorage.automationRootURL(environment: [:]).standardizedFileURL,
            expected.appendingPathComponent("Automation", isDirectory: true).standardizedFileURL
        )
    }

    func testMacOSEntitlementControlsAppGroupSelection() {
        let appGroup = URL(
            fileURLWithPath: "/tmp/StowAppGroup-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: appGroup) }
        let fallback = StowSharedStorage.developmentFallbackContainerURL().standardizedFileURL

        XCTAssertEqual(
            StowSharedStorage.macOSContainerURL(
                fileManager: .default,
                environment: [:],
                developmentOverridePath: nil,
                hasAppGroupEntitlement: true,
                appGroupContainerURL: appGroup
            ),
            appGroup
        )
        XCTAssertEqual(
            StowSharedStorage.macOSContainerURL(
                fileManager: .default,
                environment: [:],
                developmentOverridePath: nil,
                hasAppGroupEntitlement: false,
                appGroupContainerURL: appGroup
            ).standardizedFileURL,
            fallback
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

    func testExplicitCallerOverrideTakesPriorityOverEnvironment() throws {
        let argumentRoot = URL(fileURLWithPath: "/tmp/StowArgumentRoot-\(UUID().uuidString)", isDirectory: true)
        let environmentRoot = URL(fileURLWithPath: "/tmp/StowEnvironmentRoot-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: argumentRoot)
            try? FileManager.default.removeItem(at: environmentRoot)
        }

        XCTAssertEqual(
            StowSharedStorage.macOSContainerURL(
                environment: [StowSharedStorage.developmentContainerPathEnvironmentKey: environmentRoot.path],
                developmentOverridePath: argumentRoot.path
            ).standardizedFileURL,
            argumentRoot.standardizedFileURL
        )
    }
    #endif
}
