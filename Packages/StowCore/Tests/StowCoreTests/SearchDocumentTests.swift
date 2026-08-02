import Foundation
import XCTest
@testable import StowCore

final class SearchDocumentTests: XCTestCase {
    func testDocumentContainsEverySearchableField() {
        let item = StowItem(
            type: .file,
            title: "Swift Guide",
            textContent: "Concurrency chapter",
            urlString: "https://swift.org/guide",
            fileName: "guide.pdf",
            sourceApp: "Safari",
            sourceDomain: "swift.org",
            note: "Read this weekend",
            createdAt: Date(timeIntervalSince1970: 100)
        )

        let document = SearchDocument(item: item)

        XCTAssertTrue(document.content.contains("Swift Guide"))
        XCTAssertTrue(document.content.contains("Concurrency chapter"))
        XCTAssertTrue(document.content.contains("https://swift.org/guide"))
        XCTAssertTrue(document.content.contains("swift.org"))
        XCTAssertTrue(document.content.contains("Read this weekend"))
        XCTAssertTrue(document.content.contains("guide.pdf"))
        XCTAssertEqual(document.sourceApp, "Safari")
        XCTAssertEqual(document.type, .file)
    }
}
