import Foundation
import XCTest
import StowCore
@testable import StowApp

@MainActor
final class PlatformActionsPasteTests: XCTestCase {
    func testOriginalAndPlainTextWritesUsePreparedPayloadAndClearOnlyAtWriteBoundary() throws {
        let item = StowItem(type: .text, title: "Rich", textContent: "plain")
        let representation = StowRepresentation(
            itemID: item.id,
            typeIdentifier: StowRepresentationType.rtf,
            data: Data("{\\rtf1 plain}".utf8),
            ordinal: 0
        )
        let writer = PasteboardWriterDouble()

        try PlatformActions.copy(
            item,
            attachment: nil,
            representations: [representation],
            format: .original,
            writer: writer
        )

        XCTAssertEqual(writer.writeCount, 1)
        XCTAssertEqual(writer.payload?.entries.map(\.typeIdentifier), [
            StowRepresentationType.plainText,
            StowRepresentationType.rtf,
            StowRepresentationType.stowOwned,
        ])

        try PlatformActions.copy(
            item,
            attachment: nil,
            representations: [representation],
            format: .plainText,
            writer: writer
        )
        XCTAssertEqual(writer.payload?.entries.map(\.typeIdentifier), [
            StowRepresentationType.plainText,
            StowRepresentationType.stowOwned,
        ])
    }

    func testFailedWriterReportsUnavailableAfterPayloadAssembly() {
        let item = StowItem(type: .text, title: "Text", textContent: "body")
        let writer = PasteboardWriterDouble(acceptsWrite: false)

        XCTAssertThrowsError(try PlatformActions.copy(
            item,
            attachment: nil,
            representations: [],
            format: .original,
            writer: writer
        )) { error in
            XCTAssertEqual(error as? PlatformActionError, .unavailable)
        }
        XCTAssertEqual(writer.writeCount, 1)
    }
}

@MainActor
private final class PasteboardWriterDouble: PlatformPasteboardWriting {
    let acceptsWrite: Bool
    private(set) var payload: PastePayload?
    private(set) var writeCount = 0

    init(acceptsWrite: Bool = true) {
        self.acceptsWrite = acceptsWrite
    }

    func write(_ payload: PastePayload) -> Bool {
        writeCount += 1
        self.payload = payload
        return acceptsWrite
    }
}
