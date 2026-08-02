import SwiftData
import XCTest
@testable import StowCore

@MainActor
final class OfflineRecoveryTests: XCTestCase {
    func testOfflineCaptureWithAttachmentSurvivesHostAbsenceAndReconnectsExactlyOnce() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let spoolRoot = root.appendingPathComponent("Spool", isDirectory: true)
        let attachmentURL = root.appendingPathComponent("offline.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("offline attachment".utf8).write(to: attachmentURL)
        let captureID = UUID()
        let draft = CaptureDraft(id: captureID, type: .file, title: "Offline file", stagedAttachmentName: "offline.txt", attachmentByteCount: 18, contentType: "text/plain", fileName: "offline.txt")

        try CaptureSpool(rootURL: spoolRoot).stage(draft, attachmentURL: attachmentURL)
        XCTAssertEqual(try CaptureSpool(rootURL: spoolRoot).pendingCount(), 1)

        let storeURL = root.appendingPathComponent("Stow.store")
        var container: ModelContainer? = try StowContainerFactory.local(url: storeURL)
        var repository: StowRepository? = container.map { StowRepository(modelContext: $0.mainContext) }
        let reconnectedSpool = try CaptureSpool(rootURL: spoolRoot)
        let first = reconnectedSpool.ingestAll(into: try XCTUnwrap(repository))
        XCTAssertEqual(first, CaptureIngestionResult(ingested: 1, failures: []))
        let persistedItemID = try XCTUnwrap(repository?.allItems().first(where: { $0.captureID == captureID })?.id)
        XCTAssertEqual(try repository?.allItems().count, 1)
        XCTAssertEqual(try repository?.attachments(itemID: persistedItemID).first?.data, Data("offline attachment".utf8))

        repository = nil
        container = nil
        container = try StowContainerFactory.local(url: storeURL)
        repository = container.map { StowRepository(modelContext: $0.mainContext) }
        XCTAssertEqual(reconnectedSpool.ingestAll(into: try XCTUnwrap(repository)).ingested, 0)
        XCTAssertEqual(try repository?.allItems().map(\.captureID), [captureID])
    }

    func testDeterministicEditPinArchiveSequencePreservesOrthogonalFieldsWithoutDuplicates() throws {
        let container = try StowContainerFactory.inMemory()
        let repository = StowRepository(modelContext: container.mainContext)
        let id = UUID()
        let created = try repository.create(from: CaptureDraft(id: id, type: .text, title: "Original", textContent: "body"))

        try repository.update(created.id, title: "Edited", note: "offline note", textContent: "updated body", language: nil)
        try repository.setPinned(created.id, pinned: true)
        try repository.archive(created.id)
        _ = try repository.create(from: CaptureDraft(id: id, type: .text, title: "Duplicate", textContent: "duplicate"))

        let item = try XCTUnwrap(try repository.item(id: created.id))
        XCTAssertEqual(item.title, "Edited")
        XCTAssertEqual(item.note, "offline note")
        XCTAssertEqual(item.textContent, "updated body")
        XCTAssertTrue(item.isPinned)
        XCTAssertEqual(item.status, .archived)
        XCTAssertEqual(try repository.allItems().count, 1)
    }
}
