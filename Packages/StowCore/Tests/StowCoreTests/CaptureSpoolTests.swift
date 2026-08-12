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

    func testClipboardAttachmentIntentCoalescesWithoutAddingASecondAttachment() throws {
        let root = temporaryDirectory()
        let firstURL = root.appendingPathComponent("first.png")
        let secondURL = root.appendingPathComponent("second.png")
        let bytes = Data([1, 2, 3, 4])
        try bytes.write(to: firstURL)
        try bytes.write(to: secondURL)
        let first = CaptureDraft(type: .image, title: "First", stagedAttachmentName: "first.png", attachmentByteCount: bytes.count, contentType: "image/png", fileName: "first.png")
        let second = CaptureDraft(type: .image, title: "Second", stagedAttachmentName: "second.png", attachmentByteCount: bytes.count, contentType: "image/png", fileName: "second.png")
        let spool = try CaptureSpool(rootURL: root.appendingPathComponent("Spool"))
        try spool.stage(first, attachmentURL: firstURL, intent: .coalesceClipboard, at: Date(timeIntervalSince1970: 100))

        let container = try StowContainerFactory.inMemory()
        let repository = StowRepository(modelContext: container.mainContext)
        XCTAssertEqual(spool.ingestAll(into: repository).ingested, 1)
        try spool.stage(second, attachmentURL: secondURL, intent: .coalesceClipboard, at: Date(timeIntervalSince1970: 101))
        XCTAssertEqual(spool.ingestAll(into: repository).ingested, 1)

        XCTAssertEqual(try repository.allItems().count, 1)
        XCTAssertEqual(try repository.allAttachments().count, 1)
        XCTAssertEqual(try repository.allItems().first?.lastCapturedAt, Date(timeIntervalSince1970: 101))
        XCTAssertEqual(spool.ingestAll(into: repository).ingested, 0)
    }

    func testRepresentationFilesSurviveReopenAndIngestWithAttachment() throws {
        let root = temporaryDirectory()
        let attachmentURL = root.appendingPathComponent("image.png")
        try Data([1, 2, 3]).write(to: attachmentURL)
        let spoolRoot = root.appendingPathComponent("Spool")
        let draft = CaptureDraft(type: .image, title: "Image", stagedAttachmentName: "image.png", attachmentByteCount: 3, contentType: "image/png", fileName: "image.png")
        let representation = StowRepresentationDraft(typeIdentifier: StowRepresentationType.html, data: Data("<p>caption</p>".utf8), ordinal: 0)
        try CaptureSpool(rootURL: spoolRoot).stage(
            draft,
            attachmentURL: attachmentURL,
            representations: [representation],
            at: Date(timeIntervalSince1970: 100)
        )

        let container = try StowContainerFactory.inMemory()
        let repository = StowRepository(modelContext: container.mainContext)
        let reopenedSpool = try CaptureSpool(rootURL: spoolRoot)
        let result = reopenedSpool.ingestAll(into: repository)

        XCTAssertEqual(result.ingested, 1)
        let item = try XCTUnwrap(repository.allItems().first)
        XCTAssertEqual(try repository.attachments(itemID: item.id).count, 1)
        XCTAssertEqual(try repository.representations(itemID: item.id).first?.data, representation.data)
        XCTAssertEqual(reopenedSpool.ingestAll(into: repository).ingested, 0)
        XCTAssertEqual(try repository.attachments(itemID: item.id).count, 1)
        XCTAssertEqual(try repository.representations(itemID: item.id).count, 1)
    }

    func testMalformedRepresentationManifestIsQuarantinedWithoutPartialPersistence() throws {
        let root = temporaryDirectory()
        let spoolRoot = root.appendingPathComponent("Spool")
        let spool = try CaptureSpool(rootURL: spoolRoot)
        try spool.stage(
            CaptureDraft(type: .text, title: "Rich", textContent: "body"),
            representations: [
                StowRepresentationDraft(typeIdentifier: StowRepresentationType.html, data: Data("<p>body</p>".utf8), ordinal: 0),
            ]
        )
        let pending = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: spoolRoot.appendingPathComponent("Pending"),
                includingPropertiesForKeys: nil
            ).first
        )
        let representationURL = pending.appendingPathComponent("representation-0.data")
        try Data("tampered".utf8).write(to: representationURL)

        let container = try StowContainerFactory.inMemory()
        let repository = StowRepository(modelContext: container.mainContext)
        let result = spool.ingestAll(into: repository)

        XCTAssertEqual(result.ingested, 0)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(try repository.allItems().isEmpty)
        XCTAssertTrue(try repository.allRepresentations().isEmpty)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: spoolRoot.appendingPathComponent("Quarantine"),
                includingPropertiesForKeys: nil
            ).count,
            1
        )
    }

    func testLegacyManifestWithoutIngestionIntentStillCreatesNew() throws {
        struct LegacyEnvelope: Codable {
            let draft: CaptureDraft
            let capturedAt: Date
            let attachmentFileName: String?
        }
        let root = temporaryDirectory().appendingPathComponent("Spool")
        let pending = root.appendingPathComponent("Pending/legacy", isDirectory: true)
        _ = try CaptureSpool(rootURL: root)
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(LegacyEnvelope(
            draft: CaptureDraft(type: .text, title: "Legacy", textContent: "body"),
            capturedAt: Date(timeIntervalSince1970: 100),
            attachmentFileName: nil
        )).write(to: pending.appendingPathComponent("manifest.json"))

        let container = try StowContainerFactory.inMemory()
        let repository = StowRepository(modelContext: container.mainContext)
        XCTAssertEqual(try CaptureSpool(rootURL: root).ingestAll(into: repository).ingested, 1)
        XCTAssertEqual(try repository.allItems().count, 1)
        XCTAssertNil(try repository.allItems().first?.lastCapturedAt)
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
