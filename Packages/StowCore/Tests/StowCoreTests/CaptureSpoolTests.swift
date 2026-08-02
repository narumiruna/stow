import Foundation
import XCTest
@testable import StowCore

@MainActor
final class CaptureSpoolTests: XCTestCase {
    func testStagedCaptureSurvivesReopenAndIngestsExactlyOnce() throws {
        let root = temporaryDirectory()
        let attachmentURL = root.appendingPathComponent("source.png")
        try Data([1, 2, 3, 4]).write(to: attachmentURL)
        let draft = CaptureDraft(type: .image, title: "Photo", stagedAttachmentName: "source.png", attachmentByteCount: 4, contentType: "image/png", fileName: "source.png")
        let spool = try CaptureSpool(rootURL: root.appendingPathComponent("Spool"))

        try spool.stage(draft, attachmentURL: attachmentURL, at: Date(timeIntervalSince1970: 100))
        let reopened = try CaptureSpool(rootURL: root.appendingPathComponent("Spool"))
        XCTAssertEqual(try reopened.pendingCount(), 1)

        let container = try StowContainerFactory.inMemory()
        let repository = StowRepository(modelContext: container.mainContext)
        let result = reopened.ingestAll(into: repository)

        XCTAssertEqual(result.ingested, 1)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(try repository.allItems().count, 1)
        XCTAssertEqual(try repository.attachments(itemID: repository.allItems()[0].id).first?.data, Data([1, 2, 3, 4]))
        XCTAssertEqual(try reopened.pendingCount(), 0)
        XCTAssertEqual(reopened.ingestAll(into: repository).ingested, 0)
    }

    func testInterruptedTemporaryDirectoryIsIgnoredAndRemovedByMaintenance() throws {
        let root = temporaryDirectory().appendingPathComponent("Spool")
        let spool = try CaptureSpool(rootURL: root)
        let interrupted = root.appendingPathComponent(".staging-interrupted", isDirectory: true)
        try FileManager.default.createDirectory(at: interrupted, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: interrupted.appendingPathComponent("manifest.json"))

        XCTAssertEqual(try spool.pendingCount(), 0)
        XCTAssertEqual(try spool.removeInterruptedStaging(), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: interrupted.path))
    }

    func testMalformedManifestMovesToQuarantineWithoutBlockingValidCapture() throws {
        let root = temporaryDirectory().appendingPathComponent("Spool")
        let spool = try CaptureSpool(rootURL: root)
        let bad = root.appendingPathComponent("Pending/bad", isDirectory: true)
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: bad.appendingPathComponent("manifest.json"))
        try spool.stage(CaptureDraft(type: .text, title: "Good", textContent: "body"), at: Date(timeIntervalSince1970: 100))

        let container = try StowContainerFactory.inMemory()
        let result = spool.ingestAll(into: StowRepository(modelContext: container.mainContext))

        XCTAssertEqual(result.ingested, 1)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(try spool.pendingCount(), 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Quarantine").path).count, 1)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
