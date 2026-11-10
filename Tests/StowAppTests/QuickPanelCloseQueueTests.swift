import XCTest
@testable import StowApp

@MainActor
final class QuickPanelCloseQueueTests: XCTestCase {
    func testApprovalRunsCloseWorkWithoutCancellation() throws {
        let queue = QuickPanelCloseQueue()
        var events: [String] = []
        let command = try XCTUnwrap(queue.enqueue(
            .completedUse, isVisible: true, returnFocus: false,
            afterClose: { events.append("paste"); events.append("account") },
            onCancel: { events.append("cancel") }
        ))
        XCTAssertTrue(events.isEmpty)
        let pending = try XCTUnwrap(queue.take(commandID: command.id))
        XCTAssertFalse(pending.returnFocus)
        XCTAssertNil(queue.pending)
        queue.cancel()
        pending.afterClose?()
        XCTAssertEqual(events, ["paste", "account"])
        XCTAssertNil(queue.take(commandID: command.id))
    }

    func testKeepEditingAccountsOnceWithoutPasting() throws {
        let queue = QuickPanelCloseQueue()
        var accounts = 0
        var pastes = 0
        let command = try XCTUnwrap(queue.enqueue(
            .completedUse, isVisible: true, returnFocus: false,
            afterClose: { pastes += 1 }, onCancel: { accounts += 1 }
        ))
        queue.cancel(commandID: UUID())
        XCTAssertEqual(accounts, 0)
        XCTAssertNotNil(queue.pending)
        queue.cancel(commandID: command.id)
        queue.cancel(commandID: command.id)
        queue.cancel()
        XCTAssertEqual(accounts, 1)
        XCTAssertEqual(pastes, 0)
        XCTAssertNil(queue.pending)
        XCTAssertNil(queue.take(commandID: command.id))
    }

    func testDismissalAccountsOnceWithoutPasting() {
        let queue = QuickPanelCloseQueue()
        var accounts = 0
        var pastes = 0
        _ = queue.enqueue(
            .completedUse, isVisible: true, returnFocus: false,
            afterClose: { pastes += 1 }, onCancel: { accounts += 1 }
        )
        queue.cancel()
        queue.cancel()
        XCTAssertEqual(accounts, 1)
        XCTAssertEqual(pastes, 0)
        XCTAssertNil(queue.pending)
    }

    func testHiddenPanelRejectsCloseAndAccountsWithoutPasting() {
        let queue = QuickPanelCloseQueue()
        var accounts = 0
        var pastes = 0
        XCTAssertNil(queue.enqueue(
            .completedUse, isVisible: false, returnFocus: false,
            afterClose: { pastes += 1 }, onCancel: { accounts += 1 }
        ))
        queue.cancel()
        XCTAssertEqual(accounts, 1)
        XCTAssertEqual(pastes, 0)
        XCTAssertNil(queue.pending)
    }

    func testPendingCloseRejectsNewCloseWithoutChangingFirstClose() throws {
        let queue = QuickPanelCloseQueue()
        var firstCancellations = 0
        var accounts = 0
        var pastes = 0
        let first = try XCTUnwrap(queue.enqueue(
            .explicit, isVisible: true, returnFocus: true,
            onCancel: { firstCancellations += 1 }
        ))
        XCTAssertNil(queue.enqueue(
            .completedUse, isVisible: true, returnFocus: false,
            afterClose: { pastes += 1 }, onCancel: { accounts += 1 }
        ))
        XCTAssertEqual(queue.pending?.command.id, first.id)
        XCTAssertEqual(accounts, 1)
        XCTAssertEqual(pastes, 0)
        XCTAssertEqual(firstCancellations, 0)
        queue.cancel()
        XCTAssertEqual(firstCancellations, 1)
        XCTAssertEqual(accounts, 1)
    }
}
