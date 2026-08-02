import XCTest
@testable import StowCore

final class DragPayloadTests: XCTestCase {
    func testTextCodeAndLinkKeepOriginalRepresentations() {
        let text = DragPayload(item: StowItem(type: .text, title: "Text", textContent: "original text"))
        XCTAssertEqual(text.data, Data("original text".utf8))
        XCTAssertEqual(text.typeIdentifier, "public.utf8-plain-text")
        XCTAssertNil(text.suggestedName)

        let code = DragPayload(item: StowItem(type: .code, title: "Code", textContent: "let value = 1"))
        XCTAssertEqual(code.data, Data("let value = 1".utf8))
        XCTAssertEqual(code.typeIdentifier, "public.utf8-plain-text")
        XCTAssertNil(code.suggestedName)

        let link = DragPayload(item: StowItem(type: .link, title: "Link", urlString: "https://example.com/path"))
        XCTAssertEqual(link.data, Data("https://example.com/path".utf8))
        XCTAssertEqual(link.typeIdentifier, "public.url")
        XCTAssertNil(link.suggestedName)
    }

    func testImageAndFileKeepAttachmentBytesTypeAndName() {
        for type in [ItemType.image, .file] {
            let item = StowItem(type: type, title: "Attachment")
            let attachment = StowAttachment(itemID: item.id, data: Data([0, 1, 2, 3]), contentType: type == .image ? "image/png" : "application/pdf", fileName: type == .image ? "image.png" : "document.pdf")
            let payload = DragPayload(item: item, attachment: attachment)
            XCTAssertEqual(payload.data, attachment.data)
            XCTAssertEqual(payload.typeIdentifier, attachment.contentType)
            XCTAssertEqual(payload.suggestedName, attachment.fileName)
        }
    }
}
