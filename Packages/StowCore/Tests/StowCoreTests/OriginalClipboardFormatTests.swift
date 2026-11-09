import Foundation
import XCTest
@testable import StowCore

final class OriginalClipboardFormatTests: XCTestCase {
    func testMeaningfulOuterWhitespaceSurvivesNormalization() throws {
        let draft = CaptureDraft(type: .text, title: "", textContent: "  first\r\nsecond  \n")

        let normalized = try draft.normalized()

        XCTAssertEqual(normalized.textContent, "  first\r\nsecond  \n")
        XCTAssertEqual(normalized.title, "first")
        XCTAssertThrowsError(try CaptureDraft(type: .text, title: "", textContent: " \r\n ").normalized())
    }

    func testPasteboardSelectorPreservesSafeRichTypesInSourceOrder() throws {
        let candidates = [
            PasteboardRepresentationCandidate(typeIdentifier: "com.example.private", data: Data([1])),
            PasteboardRepresentationCandidate(typeIdentifier: StowRepresentationType.html, data: Data("<b>Hi</b>".utf8)),
            PasteboardRepresentationCandidate(typeIdentifier: StowRepresentationType.rtf, data: Data("{\\rtf1 Hi}".utf8)),
            PasteboardRepresentationCandidate(typeIdentifier: StowRepresentationType.plainText, data: Data("Hi".utf8)),
        ]

        let selection = try PasteboardRepresentationSelector.select(candidates)

        XCTAssertEqual(selection.canonicalText, "Hi")
        XCTAssertEqual(selection.representations.map(\.typeIdentifier), [
            StowRepresentationType.html,
            StowRepresentationType.rtf,
        ])
    }

    func testImageSelectorPrefersOriginalPNGAndFallsBackFromMalformedPreferredData() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1])
        let tiff = Data([0x49, 0x49, 0x2A, 0x00, 1])

        let selected = try PasteboardRepresentationSelector.select([
            PasteboardRepresentationCandidate(typeIdentifier: StowRepresentationType.png, data: png),
            PasteboardRepresentationCandidate(typeIdentifier: StowRepresentationType.tiff, data: tiff),
        ])
        XCTAssertEqual(selected.canonicalAttachment?.typeIdentifier, StowRepresentationType.png)
        XCTAssertEqual(selected.canonicalAttachment?.data, png)

        let fallback = try PasteboardRepresentationSelector.select([
            PasteboardRepresentationCandidate(typeIdentifier: StowRepresentationType.png, data: Data([0])),
            PasteboardRepresentationCandidate(typeIdentifier: StowRepresentationType.tiff, data: tiff),
        ])
        XCTAssertEqual(fallback.canonicalAttachment?.typeIdentifier, StowRepresentationType.tiff)
        XCTAssertEqual(fallback.canonicalAttachment?.data, tiff)
    }

    func testSelectorEnforcesPerTypeAndTotalLimitsAndIgnoresUnknownTypes() throws {
        let oversizedHTML = Data(repeating: 0x61, count: StowRepresentationLimits.richTextBytes + 1)
        let result = try PasteboardRepresentationSelector.select([
            PasteboardRepresentationCandidate(typeIdentifier: "com.example.private", data: Data([1])),
            PasteboardRepresentationCandidate(typeIdentifier: StowRepresentationType.html, data: oversizedHTML),
            PasteboardRepresentationCandidate(typeIdentifier: StowRepresentationType.plainText, data: Data("fallback".utf8)),
        ])

        XCTAssertEqual(result.canonicalText, "fallback")
        XCTAssertTrue(result.representations.isEmpty)
    }

    func testPastePayloadUsesOriginalRepresentationsPlainTextAndLegacyFallback() throws {
        let item = StowItem(type: .text, title: "Title", textContent: "plain")
        let rich = StowRepresentation(
            itemID: item.id,
            typeIdentifier: StowRepresentationType.rtf,
            data: Data("{\\rtf1 plain}".utf8),
            ordinal: 0
        )

        let original = try PastePayloadBuilder.build(item: item, representations: [rich], format: .original)
        XCTAssertEqual(original.entries.map(\.typeIdentifier), [
            StowRepresentationType.plainText,
            StowRepresentationType.rtf,
            StowRepresentationType.stowOwned,
        ])

        let plain = try PastePayloadBuilder.build(item: item, representations: [rich], format: .plainText)
        XCTAssertEqual(plain.entries.map(\.typeIdentifier), [
            StowRepresentationType.plainText,
            StowRepresentationType.stowOwned,
        ])

        let legacy = try PastePayloadBuilder.build(item: item, representations: [], format: .original)
        XCTAssertEqual(legacy.entries.first?.data, Data("plain".utf8))
    }

    func testCombinedPastePayloadJoinsTextLikeItemsInOrderAsPlainText() throws {
        let text = StowItem(type: .text, title: "Text", textContent: "first")
        let link = StowItem(type: .link, title: "Link", urlString: "https://example.com")
        let code = StowItem(type: .code, title: "Code", textContent: "let x = 1")
        let payload = try PastePayloadBuilder.buildCombined(items: [text, link, code])
        XCTAssertEqual(payload.entries.map(\.typeIdentifier), [
            StowRepresentationType.plainText,
            StowRepresentationType.stowOwned,
        ])
        XCTAssertEqual(payload.entries.first?.data, Data("first\nhttps://example.com\nlet x = 1".utf8))
    }

    func testCombinedPastePayloadRejectsImagesFilesAndEmptySelections() {
        let text = StowItem(type: .text, title: "Text", textContent: "first")
        for other in [StowItem(type: .image, title: "Image"), StowItem(type: .file, title: "File")] {
            XCTAssertThrowsError(try PastePayloadBuilder.buildCombined(items: [text, other])) { error in
                XCTAssertEqual(error as? PastePayloadError, .unsupportedMultiItemSelection)
            }
        }
        XCTAssertThrowsError(try PastePayloadBuilder.buildCombined(items: []))
    }

    func testPastePayloadSkipsMalformedAuxiliaryDataAndDoesNotNeedToClearWriterEarly() throws {
        let item = StowItem(type: .text, title: "Title", textContent: "plain")
        let malformed = StowRepresentation(
            itemID: item.id,
            typeIdentifier: StowRepresentationType.html,
            data: Data(),
            ordinal: 0
        )

        let payload = try PastePayloadBuilder.build(item: item, representations: [malformed], format: .original)

        XCTAssertEqual(payload.entries.map(\.typeIdentifier), [
            StowRepresentationType.plainText,
            StowRepresentationType.stowOwned,
        ])
    }
}
