import Foundation
import SwiftData
import XCTest
@testable import StowCore

@MainActor
final class SchemaRoundTripTests: XCTestCase {
    func testSchemaV1ReopensEverySupportedTypeAndAttachmentThroughV2Migration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let storeURL = root.appendingPathComponent("Stow.sqlite")
        let identifiers: [UUID]

        do {
            let container = try StowContainerFactory.localV1(url: storeURL)
            let context = container.mainContext
            let drafts = [
                CaptureDraft(type: .link, title: "Link", urlString: "https://example.com"),
                CaptureDraft(type: .text, title: "Text", textContent: "body"),
                CaptureDraft(type: .code, title: "Code", textContent: "let x = 1", language: "swift"),
                CaptureDraft(type: .image, title: "Image", stagedAttachmentName: "image.heic", attachmentByteCount: 3, contentType: "image/heic", fileName: "image.heic"),
                CaptureDraft(type: .file, title: "PDF", stagedAttachmentName: "file.pdf", attachmentByteCount: 3, contentType: "application/pdf", fileName: "file.pdf"),
            ]
            let items = try drafts.map { draft -> StowSchemaV1.StowItem in
                let normalized = try draft.normalized()
                let item = StowSchemaV1.StowItem(
                    captureID: normalized.id,
                    type: normalized.type,
                    title: normalized.title,
                    textContent: normalized.textContent,
                    urlString: normalized.urlString,
                    fileName: normalized.fileName,
                    sourceApp: normalized.sourceApp,
                    sourceDomain: normalized.sourceDomain,
                    note: normalized.note,
                    language: normalized.language
                )
                context.insert(item)
                return item
            }
            context.insert(StowSchemaV1.StowAttachment(itemID: items[3].id, data: Data([1, 2, 3]), contentType: "image/heic", fileName: "image.heic"))
            context.insert(StowSchemaV1.StowAttachment(itemID: items[4].id, data: Data([4, 5, 6]), contentType: "application/pdf", fileName: "file.pdf"))
            try context.save()
            identifiers = items.map(\.id)
        }

        let reopened = try StowContainerFactory.local(url: storeURL)
        let repository = StowRepository(modelContext: reopened.mainContext)
        let items = try repository.allItems()

        XCTAssertEqual(Set(items.map(\.type)), Set(ItemType.allCases))
        XCTAssertEqual(Set(items.map(\.id)), Set(identifiers))
        XCTAssertNil(items.first?.contentFingerprint)
        XCTAssertNil(items.first?.lastCapturedAt)
        XCTAssertEqual(try repository.attachments(itemID: identifiers[3]).first?.data, Data([1, 2, 3]))
        XCTAssertEqual(try repository.attachments(itemID: identifiers[4]).first?.data, Data([4, 5, 6]))
    }

    func testV2RepresentationDataReopensWithoutChangingItemID() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let storeURL = root.appendingPathComponent("Stow.sqlite")
        let itemID: UUID

        do {
            let container = try StowContainerFactory.local(url: storeURL)
            let repository = StowRepository(modelContext: container.mainContext)
            let item = try repository.create(
                from: CaptureDraft(type: .text, title: "Rich", textContent: "body"),
                representations: [
                    StowRepresentationDraft(typeIdentifier: StowRepresentationType.rtf, data: Data("{\\rtf1 body}".utf8), ordinal: 0),
                ]
            )
            itemID = item.id
        }

        let reopened = try StowContainerFactory.local(url: storeURL)
        let repository = StowRepository(modelContext: reopened.mainContext)
        XCTAssertEqual(try repository.item(id: itemID)?.id, itemID)
        XCTAssertEqual(try repository.representations(itemID: itemID).first?.data, Data("{\\rtf1 body}".utf8))
    }
}
