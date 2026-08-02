import Foundation
import XCTest
@testable import StowCore

final class CaptureDraftTests: XCTestCase {
    func testURLDraftNormalizesWhitespaceAndDerivesTitleAndDomain() throws {
        let draft = CaptureDraft(type: .link, title: "  ", urlString: "  https://www.swift.org/documentation  ")

        let normalized = try draft.normalized()

        XCTAssertEqual(normalized.urlString, "https://www.swift.org/documentation")
        XCTAssertEqual(normalized.sourceDomain, "www.swift.org")
        XCTAssertEqual(normalized.title, "www.swift.org")
    }

    func testMultilineTextPreservesLineBreaksWhileTrimmingEdges() throws {
        let draft = CaptureDraft(type: .text, title: "", textContent: "  first\nsecond  \n")

        let normalized = try draft.normalized()

        XCTAssertEqual(normalized.textContent, "first\nsecond")
        XCTAssertEqual(normalized.title, "first")
    }

    func testEmptyTextIsRejected() {
        let draft = CaptureDraft(type: .text, title: "Empty", textContent: " \n ")

        XCTAssertThrowsError(try draft.normalized()) { error in
            XCTAssertEqual(error as? CaptureValidationError, .missingText)
        }
    }

    func testMalformedLinkIsRejected() {
        let draft = CaptureDraft(type: .link, title: "Bad", urlString: "not a url")

        XCTAssertThrowsError(try draft.normalized()) { error in
            XCTAssertEqual(error as? CaptureValidationError, .invalidURL)
        }
    }

    func testSourceAndNotesSurviveNormalization() throws {
        let draft = CaptureDraft(type: .text, title: "Shared", textContent: "body", sourceApp: "Notes", note: "  process later  ")

        let normalized = try draft.normalized()

        XCTAssertEqual(normalized.sourceApp, "Notes")
        XCTAssertEqual(normalized.note, "process later")
    }

    func testDirectArchiveAndPinAreAppliedToNewItem() throws {
        let draft = CaptureDraft(type: .code, title: "Example", textContent: "let x = 1", language: "swift", isPinned: true, directlyArchive: true)

        let item = StowItem(draft: try draft.normalized(), createdAt: Date(timeIntervalSince1970: 10))

        XCTAssertEqual(item.type, .code)
        XCTAssertEqual(item.status, .archived)
        XCTAssertTrue(item.isPinned)
        XCTAssertEqual(item.language, "swift")
    }
}
