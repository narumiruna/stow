import Foundation
import XCTest
@testable import StowCore

@MainActor
final class SchemaRoundTripTests: XCTestCase {
    func testSchemaV1ReopensEverySupportedTypeAndAttachment() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let storeURL = root.appendingPathComponent("Stow.sqlite")
        let identifiers: [UUID]

        do {
            let container = try StowContainerFactory.local(url: storeURL)
            let repository = StowRepository(modelContext: container.mainContext)
            let drafts = [
                CaptureDraft(type: .link, title: "Link", urlString: "https://example.com"),
                CaptureDraft(type: .text, title: "Text", textContent: "body"),
                CaptureDraft(type: .code, title: "Code", textContent: "let x = 1", language: "swift"),
                CaptureDraft(type: .image, title: "Image", stagedAttachmentName: "image.heic", attachmentByteCount: 3, contentType: "image/heic", fileName: "image.heic"),
                CaptureDraft(type: .file, title: "PDF", stagedAttachmentName: "file.pdf", attachmentByteCount: 3, contentType: "application/pdf", fileName: "file.pdf"),
            ]
            let items = try drafts.map { try repository.create(from: $0) }
            try repository.addAttachment(StowAttachment(itemID: items[3].id, data: Data([1, 2, 3]), contentType: "image/heic", fileName: "image.heic"))
            try repository.addAttachment(StowAttachment(itemID: items[4].id, data: Data([4, 5, 6]), contentType: "application/pdf", fileName: "file.pdf"))
            identifiers = items.map(\.id)
        }

        let reopened = try StowContainerFactory.local(url: storeURL)
        let repository = StowRepository(modelContext: reopened.mainContext)
        let items = try repository.allItems()

        XCTAssertEqual(Set(items.map(\.type)), Set(ItemType.allCases))
        XCTAssertEqual(Set(items.map(\.id)), Set(identifiers))
        XCTAssertEqual(try repository.attachments(itemID: identifiers[3]).first?.data, Data([1, 2, 3]))
        XCTAssertEqual(try repository.attachments(itemID: identifiers[4]).first?.data, Data([4, 5, 6]))
    }
}
