import Foundation
import SwiftData
import XCTest
@testable import StowCore

@MainActor
final class AttachmentStoreTests: XCTestCase {
    func testImportRoundTripsBytesAndMetadata() throws {
        let container = try StowContainerFactory.inMemory()
        let repository = StowRepository(modelContext: container.mainContext)
        let item = try repository.create(from: CaptureDraft(type: .image, title: "Photo", stagedAttachmentName: "photo.png", attachmentByteCount: 4, contentType: "image/png", fileName: "photo.png"))
        let data = Data([0x89, 0x50, 0x4e, 0x47])

        let attachment = StowAttachment(itemID: item.id, data: data, contentType: "image/png", fileName: "photo.png", pixelWidth: 20, pixelHeight: 10)
        try repository.addAttachment(attachment)

        let fetched = try XCTUnwrap(repository.attachments(itemID: item.id).first)
        XCTAssertEqual(fetched.data, data)
        XCTAssertEqual(fetched.byteCount, 4)
        XCTAssertEqual(fetched.pixelWidth, 20)
        XCTAssertEqual(fetched.pixelHeight, 10)
    }

    func testAttachmentStoreStreamsFileAndMaterializesOriginalBytes() throws {
        let container = try StowContainerFactory.inMemory()
        let repository = StowRepository(modelContext: container.mainContext)
        let item = try repository.create(from: CaptureDraft(type: .file, title: "Guide", stagedAttachmentName: "guide.pdf", attachmentByteCount: 8, fileName: "guide.pdf"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("guide.pdf")
        let bytes = Data("%PDF-test".utf8)
        try bytes.write(to: source)
        let store = AttachmentStore(repository: repository, temporaryDirectory: root.appendingPathComponent("materialized"), maxBytes: 100)

        let attachment = try store.importFile(itemID: item.id, sourceURL: source, contentType: "application/pdf", fileName: "guide.pdf")
        let materialized = try store.materialize(attachment)

        XCTAssertEqual(attachment.data, bytes)
        XCTAssertEqual(try Data(contentsOf: materialized), bytes)
        XCTAssertEqual(materialized.lastPathComponent, "guide.pdf")
    }

    func testAttachmentStoreRejectsLimitWithoutPersistingPartialAttachment() throws {
        let container = try StowContainerFactory.inMemory()
        let repository = StowRepository(modelContext: container.mainContext)
        let item = try repository.create(from: CaptureDraft(type: .file, title: "File", stagedAttachmentName: "file.bin", attachmentByteCount: 4, fileName: "file.bin"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("file.bin")
        try Data([1, 2, 3, 4]).write(to: source)
        let store = AttachmentStore(repository: repository, temporaryDirectory: root.appendingPathComponent("materialized"), maxBytes: 3)

        XCTAssertThrowsError(try store.importFile(itemID: item.id, sourceURL: source, contentType: "application/octet-stream", fileName: "file.bin"))
        XCTAssertTrue(try repository.attachments(itemID: item.id).isEmpty)
    }

    func testSupportedAndGenericFilesRoundTripByteForByte() throws {
        let container = try StowContainerFactory.inMemory()
        let repository = StowRepository(modelContext: container.mainContext)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = AttachmentStore(repository: repository, temporaryDirectory: root.appendingPathComponent("materialized"))
        let fixtures: [(String, String, Data)] = [
            ("photo.jpg", "image/jpeg", Data([0xff, 0xd8, 0xff])),
            ("photo.png", "image/png", Data([0x89, 0x50, 0x4e, 0x47])),
            ("photo.heic", "image/heic", Data("heic".utf8)),
            ("document.pdf", "application/pdf", Data("%PDF".utf8)),
            ("notes.txt", "text/plain", Data("notes".utf8)),
            ("main.swift", "text/x-swift", Data("let x = 1".utf8)),
            ("archive.bin", "application/octet-stream", Data([0, 1, 2, 3])),
        ]

        for (index, fixture) in fixtures.enumerated() {
            let item = try repository.create(from: CaptureDraft(type: fixture.1.hasPrefix("image/") ? .image : .file, title: fixture.0, stagedAttachmentName: fixture.0, attachmentByteCount: fixture.2.count, contentType: fixture.1, fileName: fixture.0))
            let source = root.appendingPathComponent("\(index)-\(fixture.0)")
            try fixture.2.write(to: source)
            let attachment = try store.importFile(itemID: item.id, sourceURL: source, contentType: fixture.1, fileName: fixture.0)
            XCTAssertEqual(attachment.data, fixture.2, fixture.0)
        }
    }

    func testValidImageProducesThumbnailAndDimensions() throws {
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="))

        let info = AttachmentStore.imageInfo(png)

        XCTAssertEqual(info.width, 1)
        XCTAssertEqual(info.height, 1)
        XCTAssertNotNil(info.thumbnail)
    }

    func testTemporaryCleanupUsesControllableClockAndRetainsFreshData() throws {
        let container = try StowContainerFactory.inMemory()
        let repository = StowRepository(modelContext: container.mainContext)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let old = root.appendingPathComponent("old", isDirectory: true)
        let fresh = root.appendingPathComponent("fresh", isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 100_000)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-100)], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-10)], ofItemAtPath: fresh.path)
        let store = AttachmentStore(repository: repository, temporaryDirectory: root)

        XCTAssertEqual(try store.removeTemporaryFiles(olderThan: 50, now: now), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
        XCTAssertEqual(try store.removeTemporaryFiles(olderThan: 50, now: now), 0)
    }

    func testOversizeDraftFailsBeforeCreatingItem() throws {
        let container = try StowContainerFactory.inMemory()
        let repository = StowRepository(modelContext: container.mainContext)
        let draft = CaptureDraft(type: .file, title: "Huge", stagedAttachmentName: "huge.pdf", attachmentByteCount: 101 * 1_024 * 1_024)

        XCTAssertThrowsError(try repository.create(from: draft))
        XCTAssertTrue(try repository.allItems().isEmpty)
    }
}
