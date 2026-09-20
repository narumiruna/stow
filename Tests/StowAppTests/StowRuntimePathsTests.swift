import SwiftData
import XCTest
import StowCore
@testable import StowApp

@MainActor
final class StowRuntimePathsTests: XCTestCase {
    func testHostUsesInMemoryContainerAndOwnedRoots() throws {
        XCTAssertTrue(StowEnvironment.isUnitTestHost)
        let container = StowEnvironment.makeContainer()
        XCTAssertFalse(StowEnvironment.currentContainerUsesCloud)
        XCTAssertTrue(container.configurations.allSatisfy { $0.isStoredInMemoryOnly })
        let paths = StowRuntimePaths.current
        XCTAssertTrue(paths.sharedContainer.path.contains("StowTestHost-"))
        XCTAssertEqual(paths.sharedContainer.deletingLastPathComponent(), paths.temporaryDirectory.deletingLastPathComponent())
        XCTAssertNotEqual(paths.temporaryDirectory, FileManager.default.temporaryDirectory)
    }

    func testConnectAndMaintenanceTouchOnlyInjectedRoots() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StowIsolation-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let sentinelRoot = root.appendingPathComponent("SeparateRuntime")
        let ownedRoot = root.appendingPathComponent("TestRuntime")
        let sentinel = try CaptureSpool(rootURL: sentinelRoot.appendingPathComponent("CaptureSpool"))
        try sentinel.stage(CaptureDraft(type: .text, title: "Sentinel", textContent: "untouched sentinel"))
        let owned = try CaptureSpool(rootURL: ownedRoot.appendingPathComponent("CaptureSpool"))
        try owned.stage(CaptureDraft(type: .text, title: "Owned", textContent: "owned capture"))
        var sentinels: [URL] = []
        var expiredOwnedFiles: [URL] = []
        for runtimeRoot in [sentinelRoot, ownedRoot] {
            for name in ["StowOpen", "StowTransfers", "StowImports"] {
                let directory = runtimeRoot.appendingPathComponent("Temporary/\(name)")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let file = directory.appendingPathComponent("expired")
                try Data("private bytes".utf8).write(to: file)
                try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: file.path)
                if runtimeRoot == sentinelRoot { sentinels.append(file) } else { expiredOwnedFiles.append(file) }
            }
        }
        let container = try StowContainerFactory.inMemory()
        let model = AppModel(runtimePaths: StowRuntimePaths(
            sharedContainer: ownedRoot, temporaryDirectory: ownedRoot.appendingPathComponent("Temporary")
        ))
        model.connect(container.mainContext)
        model.runMaintenance()
        XCTAssertNil(model.presentedError)
        XCTAssertEqual(try model.repository?.allItems().map(\.textContent), ["owned capture"])
        XCTAssertEqual(try owned.pendingCount(), 0)
        XCTAssertEqual(try sentinel.pendingCount(), 1)
        for file in sentinels { XCTAssertEqual(try Data(contentsOf: file), Data("private bytes".utf8)) }
        for file in expiredOwnedFiles { XCTAssertFalse(FileManager.default.fileExists(atPath: file.path)) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: ownedRoot.appendingPathComponent("Search/v1.sqlite").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sentinelRoot.appendingPathComponent("Search").path))
    }
}
