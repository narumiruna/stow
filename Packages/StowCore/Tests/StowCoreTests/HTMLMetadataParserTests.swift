import Foundation
import XCTest
@testable import StowCore

final class HTMLMetadataParserTests: XCTestCase {
    func testOpenGraphMetadataTakesPrecedenceAndResolvesRelativeImage() {
        let html = """
        <html><head>
        <title>Fallback title</title>
        <meta property="og:title" content="Open Graph Title">
        <meta name="description" content="Fallback description">
        <meta property="og:description" content="Open Graph description">
        <meta property="og:image" content="/images/preview.jpg">
        <link rel="icon" href="icons/favicon.png">
        </head></html>
        """

        let result = HTMLMetadataParser.parse(html, baseURL: URL(string: "https://example.com/articles/one")!)

        XCTAssertEqual(result.title, "Open Graph Title")
        XCTAssertEqual(result.description, "Open Graph description")
        XCTAssertEqual(result.previewImageURL, URL(string: "https://example.com/images/preview.jpg"))
        XCTAssertEqual(result.faviconURL, URL(string: "https://example.com/articles/icons/favicon.png"))
    }

    func testEntitiesAreDecodedAndMalformedHTMLDoesNotThrow() {
        let html = "<title>Swift &amp; Safety</title><meta name='description' content='It&#39;s fast'>"

        let result = HTMLMetadataParser.parse(html, baseURL: URL(string: "https://swift.org")!)

        XCTAssertEqual(result.title, "Swift & Safety")
        XCTAssertEqual(result.description, "It's fast")
    }
}
