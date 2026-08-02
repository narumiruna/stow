import Foundation
import XCTest
@testable import StowCore

@MainActor
final class ItemLifecycleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testNewItemStartsInInboxAndCanBeArchivedAndRestored() {
        let item = StowItem(type: .text, title: "A note", textContent: "hello", createdAt: now)

        XCTAssertEqual(item.status, .inbox)
        XCTAssertFalse(item.isPinned)
        XCTAssertEqual(item.useCount, 0)

        item.archive(at: now.addingTimeInterval(10))
        XCTAssertEqual(item.status, .archived)
        XCTAssertEqual(item.updatedAt, now.addingTimeInterval(10))

        item.restoreFromArchive(at: now.addingTimeInterval(20))
        XCTAssertEqual(item.status, .inbox)
    }

    func testTrashRestoreReturnsItemToItsPreviousLiveState() {
        let item = StowItem(type: .link, title: "Swift", urlString: "https://swift.org", createdAt: now)
        item.archive(at: now.addingTimeInterval(1))
        item.trash(at: now.addingTimeInterval(2))

        XCTAssertEqual(item.status, .trashed)
        XCTAssertEqual(item.trashedAt, now.addingTimeInterval(2))

        item.restoreFromTrash(at: now.addingTimeInterval(3))
        XCTAssertEqual(item.status, .archived)
        XCTAssertNil(item.trashedAt)
    }

    func testTrashExpiresOnlyAtThirtyDays() {
        let item = StowItem(type: .text, title: "Temporary", textContent: "x", createdAt: now)
        item.trash(at: now)

        XCTAssertFalse(item.shouldPurge(at: now.addingTimeInterval(30 * 86_400 - 1)))
        XCTAssertTrue(item.shouldPurge(at: now.addingTimeInterval(30 * 86_400)))
    }

    func testSuccessfulRetrievalUpdatesUsageExactlyOncePerCall() {
        let item = StowItem(type: .code, title: "Snippet", textContent: "print(1)", createdAt: now)

        item.recordSuccessfulUse(at: now.addingTimeInterval(5))

        XCTAssertEqual(item.useCount, 1)
        XCTAssertEqual(item.lastUsedAt, now.addingTimeInterval(5))
        XCTAssertEqual(item.updatedAt, now.addingTimeInterval(5))
    }
}
