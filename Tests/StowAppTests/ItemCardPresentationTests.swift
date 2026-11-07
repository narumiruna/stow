import XCTest
import StowCore
@testable import StowApp

final class ItemCardPresentationTests: XCTestCase {
    func testEnrichedLinkDecodesEntitiesAndPrefersDescriptionToNote() {
        let item = StowItem(
            type: .link,
            title: "  Tom &amp;\n Jerry &#39;Guide&#39;  ",
            urlString: "https://url.example.com/article",
            sourceApp: "Safari",
            sourceDomain: "  metadata.example.com\n ",
            note: "A user note"
        )
        item.linkDescription = " \t A&nbsp; practical\n &quot;guide&quot; &#38; examples  "

        let presentation = ItemCardPresentation(item: item)

        XCTAssertEqual(presentation.title, "Tom & Jerry 'Guide'")
        XCTAssertEqual(presentation.excerpt, "A practical \"guide\" & examples")
        XCTAssertEqual(presentation.source, "metadata.example.com")
        XCTAssertEqual(item.title, "  Tom &amp;\n Jerry &#39;Guide&#39;  ")
    }

    func testLinkDescriptionMatchingDecodedTitleFallsBackToNote() {
        let item = StowItem(type: .link, title: "  Fish &amp; Chips  ")
        item.linkDescription = " Fish&nbsp; &amp;\n Chips "
        XCTAssertNil(ItemCardPresentation(item: item).excerpt)

        item.note = "  Try\n this recipe  "
        XCTAssertEqual(ItemCardPresentation(item: item).excerpt, "Try this recipe")
    }

    func testDomainOnlyLinkHasNoExcerpt() {
        for title in ["", "  example.com\n "] {
            let item = StowItem(
                type: .link,
                title: title,
                textContent: "This field is not a link description",
                urlString: "https://example.com/article",
                sourceDomain: "  example.com  "
            )

            let presentation = ItemCardPresentation(item: item)

            XCTAssertEqual(presentation.title, "example.com")
            XCTAssertNil(presentation.excerpt)
            XCTAssertEqual(presentation.source, "example.com")
        }
    }

    func testLinkFallsBackToURLHostWhenTitleAndDomainAreBlank() {
        let item = StowItem(
            type: .link,
            title: " \n\t ",
            urlString: " \n https://www.example.com/articles/42?ref=card \t ",
            sourceApp: "Safari",
            sourceDomain: " \n "
        )

        let presentation = ItemCardPresentation(item: item)

        XCTAssertEqual(presentation.title, "www.example.com")
        XCTAssertNil(presentation.excerpt)
        XCTAssertEqual(presentation.source, "www.example.com")
    }

    func testBlankDataUsesNonblankSingularTypeFallbacks() {
        let types: [(ItemType, String)] = [
            (.link, "Link"), (.text, "Note"), (.code, "Code"),
            (.image, "Image"), (.file, "File"),
        ]
        for (type, expected) in types {
            for blank in [nil, "", " \n\t\u{00A0} "] as [String?] {
                let item = StowItem(
                    type: type,
                    title: blank ?? "",
                    textContent: blank,
                    urlString: blank,
                    fileName: blank,
                    sourceApp: blank,
                    sourceDomain: blank,
                    note: blank
                )
                item.linkDescription = blank

                let presentation = ItemCardPresentation(item: item)

                XCTAssertEqual(presentation.title, expected, type.rawValue)
                XCTAssertNil(presentation.excerpt, type.rawValue)
                XCTAssertEqual(presentation.source, expected, type.rawValue)
            }
        }
    }

    func testTextAndCodeUseActualContentBeforeNotesWithoutDecodingEntities() {
        for type in [ItemType.text, .code] {
            let item = StowItem(
                type: type,
                title: "  A &amp;\n B  ",
                textContent: " \t let  value = \"A &amp; B\"\n print(value)  ",
                note: "A user note"
            )

            let presentation = ItemCardPresentation(item: item)

            XCTAssertEqual(presentation.title, "A &amp; B", type.rawValue)
            let expected = type == .code
                ? " \t let  value = \"A &amp; B\"\n print(value)  "
                : "let value = \"A &amp; B\" print(value)"
            XCTAssertEqual(presentation.excerpt, expected, type.rawValue)
        }
    }

    func testLongExcerptHasAVisibleCharacterLimitWithoutChangingSavedContent() {
        let text = String(repeating: "🧑🏽‍💻", count: 180)
        let item = StowItem(type: .text, title: "A long note", textContent: text)

        XCTAssertEqual(ItemCardPresentation(item: item).excerpt, String(text.prefix(160)) + "…")
        XCTAssertEqual(item.textContent, text)
    }

    func testCodeExcerptHasAtMostFourLogicalLinesWithoutChangingSavedContent() {
        let code = "let first = 1\n    let second = 2\n\n    let fourth = 4\nlet fifth = 5"
        let item = StowItem(type: .code, title: "A code snippet", textContent: code)

        XCTAssertEqual(ItemCardPresentation(item: item).excerpt, "let first = 1\n    let second = 2\n\n    let fourth = 4…")
        XCTAssertEqual(item.textContent, code)
    }

    func testCodeExcerptPreservesCommentLineBreaksAndIndentation() {
        let code = "// A comment\nif enabled {\n    let value = 1\n}\n"
        let item = StowItem(type: .code, title: "Code example", textContent: code)

        XCTAssertEqual(ItemCardPresentation(item: item).excerpt, "// A comment\nif enabled {\n    let value = 1\n}")
        XCTAssertEqual(item.textContent, code)
    }

    func testTextAndCodeUseNotesWhenContentIsBlankOrRepeatsTitle() {
        for type in [ItemType.text, .code] {
            for content in [nil, " \n\t ", " Saved\n title "] as [String?] {
                let item = StowItem(
                    type: type,
                    title: "Saved title",
                    textContent: content,
                    note: "  A user\n note  "
                )

                XCTAssertEqual(ItemCardPresentation(item: item).excerpt, "A user note", type.rawValue)
            }
        }
    }

    func testWhitespaceAndCaseDifferencesDoNotProduceDuplicateExcerpts() {
        for type in ItemType.allCases {
            let item = StowItem(
                type: type,
                title: "  Saved\n Title  ",
                textContent: " saved \t title ",
                fileName: " saved \t title ",
                note: " saved \t title "
            )
            item.linkDescription = " saved \t title "

            let presentation = ItemCardPresentation(item: item)

            XCTAssertEqual(presentation.title, "Saved Title", type.rawValue)
            XCTAssertNil(presentation.excerpt, type.rawValue)
        }
    }

    func testLinkRejectsTitleURLAndDomainsAndUsesDistinctNoteFallback() {
        let item = StowItem(
            type: .link,
            title: "Article title",
            urlString: "https://url.example.com/article",
            sourceDomain: "metadata.example.com"
        )
        let descriptions: [String?] = [
            nil, " \n ", " Article\n title ",
            " HTTPS://URL.EXAMPLE.COM/article ",
            " metadata.example.com ", " url.example.com ",
        ]
        for description in descriptions {
            item.linkDescription = description
            item.note = description
            XCTAssertNil(ItemCardPresentation(item: item).excerpt, description ?? "nil")

            item.note = "  Read\n before Friday  "
            XCTAssertEqual(ItemCardPresentation(item: item).excerpt, "Read before Friday", description ?? "nil")
        }
    }

    func testAttachmentsPreferDistinctNotesThenFilenames() {
        for type in [ItemType.image, .file] {
            let item = StowItem(
                type: type,
                title: "Attachment",
                textContent: "This field is not an attachment summary",
                fileName: "  diagram\n draft.svg  ",
                note: "  A user\t comment  "
            )
            XCTAssertEqual(ItemCardPresentation(item: item).excerpt, "A user comment", type.rawValue)

            item.note = " Attachment\n "
            XCTAssertEqual(ItemCardPresentation(item: item).excerpt, "diagram draft.svg", type.rawValue)

            item.note = " \n\t "
            XCTAssertEqual(ItemCardPresentation(item: item).excerpt, "diagram draft.svg", type.rawValue)

            item.fileName = "  Attachment  "
            XCTAssertNil(ItemCardPresentation(item: item).excerpt, type.rawValue)
        }
    }

    func testUntitledAttachmentsUseFilenameWithoutRepeatingIt() {
        for type in [ItemType.image, .file] {
            let item = StowItem(type: type, title: " \n ", fileName: "  diagram.svg\t ")

            let presentation = ItemCardPresentation(item: item)

            XCTAssertEqual(presentation.title, "diagram.svg", type.rawValue)
            XCTAssertNil(presentation.excerpt, type.rawValue)
        }
    }

    func testLinkUsesSourceAppWhenDomainAndURLHostAreUnavailable() {
        let item = StowItem(
            type: .link,
            title: "Saved link",
            urlString: "not a valid URL",
            sourceApp: "  User\n App  ",
            sourceDomain: " \t "
        )

        XCTAssertEqual(ItemCardPresentation(item: item).source, "User App")
    }

    func testOtherTypesUseSourceAppInsteadOfLinkMetadata() {
        for type in [ItemType.text, .code, .image, .file] {
            let item = StowItem(
                type: type,
                title: "Saved item",
                urlString: "https://ignored.example.com/article",
                sourceApp: "  User\n App  ",
                sourceDomain: "ignored.example.com"
            )

            XCTAssertEqual(ItemCardPresentation(item: item).source, "User App", type.rawValue)
        }
    }
}
