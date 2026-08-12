import Foundation
import SwiftData
import XCTest
@testable import StowCore

@MainActor
final class ClipboardIngestionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)
    private var containers: [ModelContainer] = []

    func testRecopyCoalescesIntoInboxWhilePreservingUserMetadata() throws {
        let repository = try makeRepository()
        let created = try repository.ingestClipboard(
            CaptureDraft(type: .text, title: "Original", textContent: "payload", sourceApp: "Notes"),
            at: start
        )
        guard case .created(let item) = created else { return XCTFail("Expected creation") }
        try repository.update(
            item.id,
            title: "My title",
            note: "My note",
            textContent: "payload",
            language: nil,
            at: start.addingTimeInterval(1)
        )
        try repository.setPinned(item.id, pinned: true, at: start.addingTimeInterval(2))
        try repository.recordSuccessfulUse(item.id, at: start.addingTimeInterval(3))

        let recopy = try repository.ingestClipboard(
            CaptureDraft(type: .text, title: "Incoming", textContent: "payload", sourceApp: "TextEdit"),
            at: start.addingTimeInterval(10)
        )

        guard case .coalesced(let coalesced) = recopy else { return XCTFail("Expected coalescing") }
        XCTAssertEqual(coalesced.id, item.id)
        XCTAssertEqual(coalesced.createdAt, start)
        XCTAssertEqual(coalesced.title, "My title")
        XCTAssertEqual(coalesced.note, "My note")
        XCTAssertTrue(coalesced.isPinned)
        XCTAssertEqual(coalesced.status, .inbox)
        XCTAssertEqual(coalesced.useCount, 1)
        XCTAssertEqual(coalesced.textContent, "payload")
        XCTAssertEqual(coalesced.sourceApp, "TextEdit")
        XCTAssertEqual(coalesced.lastCapturedAt, start.addingTimeInterval(10))
        XCTAssertEqual(coalesced.updatedAt, start.addingTimeInterval(10))
        XCTAssertEqual(try repository.allItems().count, 1)
    }

    func testArchivedPinnedEditedAndManuallyCreatedItemsCanCoalesce() throws {
        let repository = try makeRepository()
        let archived = try repository.create(
            from: CaptureDraft(type: .text, title: "Saved", textContent: "archived payload", isPinned: true),
            at: start
        )
        try repository.archive(archived.id, at: start.addingTimeInterval(1))
        _ = try repository.backfillContentFingerprints()

        let outcome = try repository.ingestClipboard(
            CaptureDraft(type: .text, title: "Clipboard", textContent: "archived payload", sourceApp: "Terminal"),
            at: start.addingTimeInterval(5)
        )

        guard case .coalesced(let item) = outcome else { return XCTFail("Expected coalescing") }
        XCTAssertEqual(item.id, archived.id)
        XCTAssertEqual(item.status, .archived)
        XCTAssertTrue(item.isPinned)
        XCTAssertEqual(item.sourceApp, "Terminal")
    }

    func testNonClipboardCreatesWithDifferentCaptureIDsRemainDistinct() throws {
        let repository = try makeRepository()
        _ = try repository.create(
            from: CaptureDraft(type: .text, title: "First", textContent: "same"),
            at: start
        )
        _ = try repository.create(
            from: CaptureDraft(type: .text, title: "Second", textContent: "same"),
            at: start.addingTimeInterval(1)
        )

        XCTAssertEqual(try repository.allItems().count, 2)
    }

    func testTrashIsNeverResurrectedAndCreatesNewInboxItem() throws {
        let repository = try makeRepository()
        let trashed = try repository.ingestClipboard(
            CaptureDraft(type: .text, title: "Old", textContent: "same"),
            at: start
        ).item
        try repository.trash(trashed.id, at: start.addingTimeInterval(1))

        let outcome = try repository.ingestClipboard(
            CaptureDraft(type: .text, title: "New", textContent: "same"),
            at: start.addingTimeInterval(2)
        )

        guard case .created(let fresh) = outcome else { return XCTFail("Expected a fresh item") }
        XCTAssertNotEqual(fresh.id, trashed.id)
        XCTAssertEqual(fresh.status, .inbox)
        XCTAssertEqual(trashed.status, .trashed)
        XCTAssertEqual(try repository.allItems().count, 2)
    }

    func testContentEditRecalculatesFingerprintButMetadataEditRetainsIt() throws {
        let repository = try makeRepository()
        let item = try repository.ingestClipboard(
            CaptureDraft(type: .text, title: "Original", textContent: "old payload"),
            at: start
        ).item
        let originalFingerprint = try XCTUnwrap(item.contentFingerprint)

        try repository.update(
            item.id,
            title: "Renamed",
            note: "Metadata only",
            textContent: "old payload",
            language: nil,
            at: start.addingTimeInterval(1)
        )
        XCTAssertEqual(item.contentFingerprint, originalFingerprint)

        try repository.update(
            item.id,
            title: "Renamed",
            note: "Metadata only",
            textContent: "edited payload",
            language: nil,
            at: start.addingTimeInterval(2)
        )
        XCTAssertNotEqual(item.contentFingerprint, originalFingerprint)

        guard case .created = try repository.ingestClipboard(
            CaptureDraft(type: .text, title: "Old", textContent: "old payload"),
            at: start.addingTimeInterval(3)
        ) else { return XCTFail("Old content should create") }
        guard case .coalesced(let edited) = try repository.ingestClipboard(
            CaptureDraft(type: .text, title: "Edited", textContent: "edited payload"),
            at: start.addingTimeInterval(4)
        ) else { return XCTFail("Edited content should coalesce") }
        XCTAssertEqual(edited.id, item.id)
    }

    func testBackfillIsIdempotentAndPreservesEveryUserOwnedField() throws {
        let repository = try makeRepository()
        let item = try repository.create(
            from: CaptureDraft(type: .text, title: "Title", textContent: "body", sourceApp: "Notes", note: "note", isPinned: true),
            at: start
        )
        try repository.archive(item.id, at: start.addingTimeInterval(1))
        let snapshot = ItemSnapshot(item)

        XCTAssertEqual(try repository.backfillContentFingerprints(), 1)
        XCTAssertEqual(try repository.backfillContentFingerprints(), 0)
        XCTAssertEqual(try repository.allItems().count, 1)
        XCTAssertEqual(ItemSnapshot(item), snapshot)
        XCTAssertNotNil(item.contentFingerprint)
    }

    func testAttachmentOutcomeIsAtomicAndCoalescedBytesAreNotAttached() throws {
        let repository = try makeRepository()
        let bytes = Data([1, 2, 3])
        let draft = CaptureDraft(
            type: .image,
            title: "Image",
            stagedAttachmentName: "image.png",
            attachmentByteCount: bytes.count,
            contentType: "image/png",
            fileName: "image.png",
            sourceApp: "Photos"
        )
        let first = try repository.ingestClipboard(draft, attachmentData: bytes, at: start)
        let second = try repository.ingestClipboard(
            CaptureDraft(
                type: .image,
                title: "Copy",
                stagedAttachmentName: "other.png",
                attachmentByteCount: bytes.count,
                contentType: "image/png",
                fileName: "other.png",
                sourceApp: "Preview"
            ),
            attachmentData: bytes,
            at: start.addingTimeInterval(1)
        )

        guard case .created(let item) = first, case .coalesced(let same) = second else {
            return XCTFail("Expected created then coalesced")
        }
        XCTAssertEqual(item.id, same.id)
        XCTAssertEqual(try repository.attachments(itemID: item.id).count, 1)
        XCTAssertEqual(try repository.attachments(itemID: item.id)[0].data, bytes)
    }

    func testCoalescingRefreshesSearchDocumentSourceWithoutMutatingCanonicalContent() throws {
        let repository = try makeRepository()
        let created = try repository.ingestClipboard(
            CaptureDraft(type: .text, title: "Title", textContent: "searchable payload", sourceApp: "Notes"),
            at: start
        ).item

        let outcome = try repository.ingestClipboard(
            CaptureDraft(type: .text, title: "Incoming", textContent: "searchable payload", sourceApp: "TextEdit"),
            at: start.addingTimeInterval(5)
        )

        guard case .coalesced(let item) = outcome else { return XCTFail("Expected coalescing") }
        let document = SearchDocument(item: item)
        XCTAssertEqual(document.id, created.id)
        XCTAssertEqual(document.sourceApp, "TextEdit")
        XCTAssertTrue(document.content.contains("searchable payload"))
        XCTAssertEqual(try repository.allItems().count, 1)
    }

    func testClipboardActivityOrderingUsesCaptureUseAndCreationDates() throws {
        let repository = try makeRepository()
        let created = try repository.create(from: CaptureDraft(type: .text, title: "Created", textContent: "a"), at: start)
        let captured = try repository.ingestClipboard(CaptureDraft(type: .text, title: "Captured", textContent: "b"), at: start.addingTimeInterval(1)).item
        let used = try repository.create(from: CaptureDraft(type: .text, title: "Used", textContent: "c"), at: start.addingTimeInterval(2))
        try repository.recordSuccessfulUse(used.id, at: start.addingTimeInterval(4))
        _ = try repository.ingestClipboard(CaptureDraft(type: .text, title: "Captured", textContent: "b"), at: start.addingTimeInterval(5))

        XCTAssertEqual(
            ClipboardActivityOrdering.sorted([created, captured, used]).map(\.id),
            [captured.id, used.id, created.id]
        )

        created.updatedAt = start.addingTimeInterval(100)
        XCTAssertEqual(
            ClipboardActivityOrdering.sorted([created, captured, used]).map(\.id),
            [captured.id, used.id, created.id],
            "A sync-only updatedAt change must not alter Clipboard activity order"
        )

        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let equalFirst = StowItem(id: firstID, type: .text, title: "Equal A", textContent: "a", createdAt: start)
        let equalSecond = StowItem(id: secondID, type: .text, title: "Equal B", textContent: "b", createdAt: start)
        XCTAssertEqual(
            ClipboardActivityOrdering.sorted([equalSecond, equalFirst]).map(\.id),
            [firstID, secondID]
        )
    }

    private func makeRepository() throws -> StowRepository {
        let container = try StowContainerFactory.inMemory()
        containers.append(container)
        return StowRepository(modelContext: container.mainContext)
    }
}

private struct ItemSnapshot: Equatable {
    let id: UUID
    let createdAt: Date
    let title: String
    let note: String?
    let isPinned: Bool
    let status: ItemStatus
    let textContent: String?

    init(_ item: StowItem) {
        id = item.id
        createdAt = item.createdAt
        title = item.title
        note = item.note
        isPinned = item.isPinned
        status = item.status
        textContent = item.textContent
    }
}
