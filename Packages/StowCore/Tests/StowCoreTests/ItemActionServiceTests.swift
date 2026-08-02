import Foundation
import XCTest
@testable import StowCore

@MainActor
final class ItemActionServiceTests: XCTestCase {
    func testSuccessfulActionRecordsUsageExactlyOnce() throws {
        let container = try StowContainerFactory.inMemory()
        let repository = StowRepository(modelContext: container.mainContext)
        let item = try repository.create(from: CaptureDraft(type: .text, title: "Text", textContent: "body"))
        let service = ItemActionService(repository: repository)

        try service.perform(itemID: item.id, action: .copy, at: Date(timeIntervalSince1970: 100)) {}

        XCTAssertEqual(item.useCount, 1)
        XCTAssertEqual(item.lastUsedAt, Date(timeIntervalSince1970: 100))
    }

    func testFailedAndCancelledActionsDoNotRecordUsage() throws {
        enum Expected: Error { case failure }
        let container = try StowContainerFactory.inMemory()
        let repository = StowRepository(modelContext: container.mainContext)
        let item = try repository.create(from: CaptureDraft(type: .link, title: "Link", urlString: "https://example.com"))
        let service = ItemActionService(repository: repository)

        XCTAssertThrowsError(try service.perform(itemID: item.id, action: .open) { throw Expected.failure })
        XCTAssertEqual(item.useCount, 0)
        XCTAssertNil(item.lastUsedAt)
    }
}
