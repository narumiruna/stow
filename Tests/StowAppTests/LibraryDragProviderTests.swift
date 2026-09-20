import XCTest
import StowCore
@testable import StowApp

@MainActor
final class LibraryDragProviderTests: XCTestCase {
    func testProviderPreservesPayloadAndAccountsForEveryLoad() async throws {
        let text = StowItem(type: .text, title: "Text", textContent: "drag text")
        let link = StowItem(type: .link, title: "Link")
        link.urlString = "https://example.com/path"
        let attachment = StowAttachment(itemID: text.id, data: Data([0, 1, 255]), contentType: "public.png", fileName: "image.png")
        for payload in [DragPayload(item: text), DragPayload(item: link), DragPayload(item: text, attachment: attachment)] {
            let accounted = expectation(description: "One callback per load")
            accounted.expectedFulfillmentCount = 2
            accounted.assertForOverFulfill = true
            var callbackCount = 0
            let provider = LibraryDragProvider.make(payload: payload) {
                callbackCount += 1
                accounted.fulfill()
            }
            XCTAssertEqual(provider.registeredTypeIdentifiers, [payload.typeIdentifier])
            XCTAssertEqual(provider.suggestedName, payload.suggestedName)
            await Task.yield()
            XCTAssertEqual(callbackCount, 0, "Construction must not account for a drag")
            for _ in 0..<2 {
                let data: Data = try await withCheckedThrowingContinuation { continuation in
                    provider.loadDataRepresentation(forTypeIdentifier: payload.typeIdentifier) { data, error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume(returning: data ?? Data()) }
                    }
                }
                XCTAssertEqual(data, payload.data)
            }
            await fulfillment(of: [accounted], timeout: 2)
            XCTAssertEqual(callbackCount, 2)
        }
    }
}
