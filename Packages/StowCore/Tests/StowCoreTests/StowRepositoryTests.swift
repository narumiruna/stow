import Foundation
import SwiftData
import XCTest
@testable import StowCore

@MainActor
final class StowRepositoryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testCreateIsIdempotentByCaptureID() throws {
        let (container, repository) = try makeRepository()
        let captureID = UUID()
        let draft = CaptureDraft(id: captureID, type: .text, title: "Note", textContent: "Body")

        let first = try repository.create(from: draft, at: start)
        let second = try repository.create(from: draft, at: start.addingTimeInterval(1))

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(try repository.allItems().count, 1)
        withExtendedLifetime(container) {}
    }

    func testInboxIsNewestFirstAndExcludesArchivedAndTrashed() throws {
        let (container, repository) = try makeRepository()
        let old = try repository.create(from: CaptureDraft(type: .text, title: "Old", textContent: "1"), at: start)
        let newest = try repository.create(from: CaptureDraft(type: .text, title: "New", textContent: "2"), at: start.addingTimeInterval(20))
        let archived = try repository.create(from: CaptureDraft(type: .text, title: "Archived", textContent: "3"), at: start.addingTimeInterval(10))
        try repository.archive(archived.id, at: start.addingTimeInterval(30))

        XCTAssertEqual(try repository.items(in: .inbox).map(\.id), [newest.id, old.id])
        withExtendedLifetime(container) {}
    }

    func testRecentUsesLastUsedDateAndPinnedExcludesTrash() throws {
        let (container, repository) = try makeRepository()
        let first = try repository.create(from: CaptureDraft(type: .text, title: "First", textContent: "1", isPinned: true), at: start)
        let second = try repository.create(from: CaptureDraft(type: .text, title: "Second", textContent: "2", isPinned: true), at: start)
        try repository.recordSuccessfulUse(first.id, at: start.addingTimeInterval(5))
        try repository.recordSuccessfulUse(second.id, at: start.addingTimeInterval(10))
        try repository.trash(first.id, at: start.addingTimeInterval(20))

        XCTAssertEqual(try repository.recent().map(\.id), [second.id])
        XCTAssertEqual(try repository.pinned().map(\.id), [second.id])
        withExtendedLifetime(container) {}
    }

    func testBatchLifecycleMutationsApplyTogether() throws {
        let (container, repository) = try makeRepository()
        let first = try repository.create(from: CaptureDraft(type: .text, title: "First", textContent: "1"), at: start)
        let second = try repository.create(from: CaptureDraft(type: .text, title: "Second", textContent: "2"), at: start)

        try repository.setPinned([first.id, second.id], pinned: true, at: start.addingTimeInterval(1))
        try repository.archive([first.id, second.id], at: start.addingTimeInterval(2))
        XCTAssertTrue(first.isPinned)
        XCTAssertTrue(second.isPinned)
        XCTAssertEqual(first.status, .archived)
        XCTAssertEqual(second.status, .archived)

        try repository.trash([first.id, second.id], at: start.addingTimeInterval(3))
        XCTAssertEqual(first.status, .trashed)
        XCTAssertEqual(second.status, .trashed)
        try repository.restoreFromTrash([first.id, second.id], at: start.addingTimeInterval(4))
        XCTAssertEqual(first.status, .archived)
        XCTAssertEqual(second.status, .archived)
        withExtendedLifetime(container) {}
    }

    func testBatchMutationValidatesEveryIDBeforeChangingAnyItem() throws {
        let (container, repository) = try makeRepository()
        let first = try repository.create(from: CaptureDraft(type: .text, title: "First", textContent: "1"), at: start)

        XCTAssertThrowsError(try repository.trash([first.id, UUID()])) { error in
            XCTAssertEqual(error as? StowRepositoryError, .itemNotFound)
        }
        XCTAssertEqual(first.status, .inbox)
        XCTAssertNil(first.trashedAt)
        withExtendedLifetime(container) {}
    }

    func testFailedUpdateValidationDoesNotLeakPartialFieldChanges() throws {
        let (container, repository) = try makeRepository()
        let item = try repository.create(from: CaptureDraft(type: .text, title: "Original", textContent: "Body", note: "Saved"), at: start)
        let originalUpdatedAt = item.updatedAt

        XCTAssertThrowsError(try repository.update(
            item.id,
            title: "Leaked title",
            note: "Leaked note",
            textContent: "   ",
            language: nil,
            at: start.addingTimeInterval(20)
        )) { error in
            XCTAssertEqual(error as? CaptureValidationError, .missingText)
        }
        XCTAssertEqual(item.title, "Original")
        XCTAssertEqual(item.note, "Saved")
        XCTAssertEqual(item.textContent, "Body")
        XCTAssertEqual(item.updatedAt, originalUpdatedAt)
        withExtendedLifetime(container) {}
    }

    func testLinkMetadataEnrichmentUpdatesExistingItemWithoutDuplicatingIt() throws {
        let (container, repository) = try makeRepository()
        let item = try repository.create(from: CaptureDraft(type: .link, title: "", urlString: "https://swift.org"), at: start)

        try repository.updateLinkMetadata(item.id, metadata: LinkMetadata(title: "The Swift Programming Language", description: "A powerful language", domain: "swift.org", faviconData: Data([1]), previewImageData: Data([2])), at: start.addingTimeInterval(5))

        let updated = try XCTUnwrap(repository.item(id: item.id))
        XCTAssertEqual(updated.title, "The Swift Programming Language")
        XCTAssertEqual(updated.linkDescription, "A powerful language")
        XCTAssertEqual(updated.faviconData, Data([1]))
        XCTAssertEqual(updated.linkPreviewImageData, Data([2]))
        XCTAssertEqual(try repository.allItems().count, 1)
        withExtendedLifetime(container) {}
    }

    func testPurgeDeletesOnlyExpiredTrashAndAttachments() throws {
        let (container, repository) = try makeRepository()
        let expired = try repository.create(from: CaptureDraft(type: .file, title: "Old", stagedAttachmentName: "old.pdf", attachmentByteCount: 3, fileName: "old.pdf"), at: start)
        let fresh = try repository.create(from: CaptureDraft(type: .text, title: "Fresh", textContent: "fresh"), at: start)
        try repository.addAttachment(StowAttachment(itemID: expired.id, data: Data([1, 2, 3]), contentType: "application/pdf", fileName: "old.pdf"))
        try repository.trash(expired.id, at: start)
        try repository.trash(fresh.id, at: start.addingTimeInterval(29 * 86_400))

        let purged = try repository.purgeExpiredTrash(at: start.addingTimeInterval(30 * 86_400))

        XCTAssertEqual(purged, 1)
        XCTAssertNil(try repository.item(id: expired.id))
        XCTAssertNotNil(try repository.item(id: fresh.id))
        XCTAssertTrue(try repository.attachments(itemID: expired.id).isEmpty)
        XCTAssertEqual(try repository.purgeExpiredTrash(at: start.addingTimeInterval(30 * 86_400)), 0)
        withExtendedLifetime(container) {}
    }

    private func makeRepository() throws -> (ModelContainer, StowRepository) {
        let container = try StowContainerFactory.inMemory()
        return (container, StowRepository(modelContext: container.mainContext))
    }
}
