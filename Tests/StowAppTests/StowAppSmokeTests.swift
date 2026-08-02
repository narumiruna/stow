import XCTest
import StowCore

final class StowAppSmokeTests: XCTestCase {
    func testCoreDependencyIsLinkedIntoNativeUnitTestTarget() throws {
        let draft = try CaptureDraft(type: .text, title: "", textContent: "Smoke test").normalized()
        XCTAssertEqual(draft.title, "Smoke test")
    }
}
