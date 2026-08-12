import Foundation
import XCTest
@testable import StowCore

@MainActor
final class StowRepresentationTests: XCTestCase {
    func testRepresentationsRoundTripInOrdinalOrderAndRejectDuplicateTypes() throws {
        let container = try StowContainerFactory.inMemory()
        let repository = StowRepository(modelContext: container.mainContext)
        let outcome = try repository.ingestClipboard(
            CaptureDraft(type: .text, title: "Rich", textContent: "rich text"),
            representations: [
                StowRepresentationDraft(typeIdentifier: StowRepresentationType.html, data: Data("<b>rich</b>".utf8), ordinal: 2),
                StowRepresentationDraft(typeIdentifier: StowRepresentationType.rtf, data: Data("{\\rtf1 rich}".utf8), ordinal: 1),
            ]
        )

        let representations = try repository.representations(itemID: outcome.item.id)
        XCTAssertEqual(representations.map(\.typeIdentifier), [StowRepresentationType.rtf, StowRepresentationType.html])
        XCTAssertEqual(representations.map(\.ordinal), [1, 2])
        XCTAssertThrowsError(try repository.ingestClipboard(
            CaptureDraft(type: .text, title: "Duplicate", textContent: "other"),
            representations: [
                StowRepresentationDraft(typeIdentifier: StowRepresentationType.rtf, data: Data([1]), ordinal: 0),
                StowRepresentationDraft(typeIdentifier: StowRepresentationType.rtf, data: Data([2]), ordinal: 1),
            ]
        )) { error in
            XCTAssertEqual(error as? StowRepresentationError, .duplicateType(StowRepresentationType.rtf))
        }
    }

    func testUnknownMalformedAndOversizedRepresentationsAreRejectedAtomically() throws {
        let container = try StowContainerFactory.inMemory()
        let repository = StowRepository(modelContext: container.mainContext)
        let initialCount = try repository.allItems().count
        let cases: [StowRepresentationDraft] = [
            StowRepresentationDraft(typeIdentifier: "com.example.private", data: Data([1]), ordinal: 0),
            StowRepresentationDraft(typeIdentifier: StowRepresentationType.rtf, data: Data(), ordinal: 0),
            StowRepresentationDraft(
                typeIdentifier: StowRepresentationType.url,
                data: Data(repeating: 0x61, count: StowRepresentationLimits.urlBytes + 1),
                ordinal: 0
            ),
        ]

        for representation in cases {
            XCTAssertThrowsError(try repository.ingestClipboard(
                CaptureDraft(type: .text, title: "Rejected", textContent: "body"),
                representations: [representation]
            ))
        }
        XCTAssertEqual(try repository.allItems().count, initialCount)
        XCTAssertTrue(try repository.allRepresentations().isEmpty)
    }

    func testCaptureIDRetryRepairsMissingRepresentationsWithoutDuplicatingItem() throws {
        let container = try StowContainerFactory.inMemory()
        let repository = StowRepository(modelContext: container.mainContext)
        let draft = CaptureDraft(type: .text, title: "Rich", textContent: "body")
        let original = try repository.create(from: draft)

        let retried = try repository.create(
            from: draft,
            representations: [
                StowRepresentationDraft(typeIdentifier: StowRepresentationType.rtf, data: Data("{\\rtf1 body}".utf8), ordinal: 0),
            ]
        )

        XCTAssertEqual(retried.id, original.id)
        XCTAssertEqual(try repository.allItems().count, 1)
        XCTAssertEqual(try repository.representations(itemID: original.id).count, 1)
    }

    func testTextEditDropsStaleRichRepresentations() throws {
        let container = try StowContainerFactory.inMemory()
        let repository = StowRepository(modelContext: container.mainContext)
        let item = try repository.create(
            from: CaptureDraft(type: .text, title: "Rich", textContent: "body"),
            representations: [
                StowRepresentationDraft(typeIdentifier: StowRepresentationType.rtf, data: Data("{\\rtf1 body}".utf8), ordinal: 0),
            ]
        )

        try repository.update(item.id, title: "Rich", note: nil, textContent: "  edited\n", language: nil)

        XCTAssertEqual(item.textContent, "  edited\n")
        XCTAssertTrue(try repository.representations(itemID: item.id).isEmpty)
        XCTAssertNotNil(item.contentFingerprint)
    }

    func testPurgeDeletesOwnedRepresentations() throws {
        let container = try StowContainerFactory.inMemory()
        let repository = StowRepository(modelContext: container.mainContext)
        let start = Date(timeIntervalSince1970: 100)
        let item = try repository.ingestClipboard(
            CaptureDraft(type: .text, title: "Rich", textContent: "body"),
            representations: [
                StowRepresentationDraft(typeIdentifier: StowRepresentationType.html, data: Data("<p>body</p>".utf8), ordinal: 0),
            ],
            at: start
        ).item
        try repository.trash(item.id, at: start)

        XCTAssertEqual(try repository.purgeExpiredTrash(at: start.addingTimeInterval(30 * 86_400)), 1)
        XCTAssertTrue(try repository.representations(itemID: item.id).isEmpty)
    }

    func testAllowlistLimitsAcceptExactBoundaryAndRejectBoundaryPlusOne() throws {
        let boundary = Data(repeating: 0x61, count: StowRepresentationLimits.urlBytes)
        XCTAssertNoThrow(try StowRepresentationValidator.validate([
            StowRepresentationDraft(typeIdentifier: StowRepresentationType.url, data: boundary, ordinal: 0),
        ]))
        XCTAssertThrowsError(try StowRepresentationValidator.validate([
            StowRepresentationDraft(typeIdentifier: StowRepresentationType.url, data: boundary + Data([0x61]), ordinal: 0),
        ])) { error in
            XCTAssertEqual(error as? StowRepresentationError, .representationTooLarge(StowRepresentationType.url))
        }
    }
}
