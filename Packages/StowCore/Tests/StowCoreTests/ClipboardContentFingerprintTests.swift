import Foundation
import XCTest
@testable import StowCore

final class ClipboardContentFingerprintTests: XCTestCase {
    func testPlainTextNormalizesNFCAndLineEndingsButPreservesWhitespaceAndCase() throws {
        let composed = try ClipboardContentFingerprint.make(
            draft: CaptureDraft(type: .text, title: "", textContent: "Café\r\nline")
        )
        let decomposed = try ClipboardContentFingerprint.make(
            draft: CaptureDraft(type: .text, title: "", textContent: "Cafe\u{301}\rline")
        )

        XCTAssertEqual(composed, decomposed)
        XCTAssertNotEqual(
            composed,
            try ClipboardContentFingerprint.make(
                draft: CaptureDraft(type: .text, title: "", textContent: "café\nline")
            )
        )
        XCTAssertNotEqual(
            composed,
            try ClipboardContentFingerprint.make(
                draft: CaptureDraft(type: .text, title: "", textContent: " Café\nline")
            )
        )
    }

    func testRichTextFormattingIsDistinctWhenVisibleTextMatches() throws {
        let draft = CaptureDraft(type: .text, title: "", textContent: "same text")
        let plain = try ClipboardContentFingerprint.make(draft: draft)
        let bold = try ClipboardContentFingerprint.make(
            draft: draft,
            auxiliaryRepresentations: [
                ClipboardFingerprintRepresentation(typeIdentifier: "public.rtf", data: Data("bold".utf8)),
            ]
        )
        let italic = try ClipboardContentFingerprint.make(
            draft: draft,
            auxiliaryRepresentations: [
                ClipboardFingerprintRepresentation(typeIdentifier: "public.rtf", data: Data("italic".utf8)),
            ]
        )

        XCTAssertNotEqual(plain, bold)
        XCTAssertNotEqual(bold, italic)
    }

    func testStableVectorsCoverPlainTextCodeAndLinks() throws {
        XCTAssertEqual(
            try ClipboardContentFingerprint.make(
                draft: CaptureDraft(type: .text, title: "", textContent: "Hello\r\nworld")
            ),
            "v1:7ae10e25b69a6bb6514cabad2f01d8c8ad3c7ab43693746abbe8f6062a506888"
        )
        XCTAssertNotEqual(
            try ClipboardContentFingerprint.make(
                draft: CaptureDraft(type: .text, title: "", textContent: "let x = 1")
            ),
            try ClipboardContentFingerprint.make(
                draft: CaptureDraft(type: .code, title: "", textContent: "let x = 1", language: "swift")
            )
        )
        XCTAssertEqual(
            try ClipboardContentFingerprint.make(
                draft: CaptureDraft(type: .link, title: "", urlString: "https://example.com/path")
            ),
            try ClipboardContentFingerprint.make(
                draft: CaptureDraft(type: .link, title: "Alias", urlString: "https://example.com/path")
            )
        )
    }

    func testImageUsesOriginalBytesAndRepresentationType() throws {
        let bytes = Data([0, 1, 2, 3])
        let png = try ClipboardContentFingerprint.make(
            draft: CaptureDraft(type: .image, title: "Image", stagedAttachmentName: "image.png", attachmentByteCount: bytes.count, contentType: "image/png", fileName: "image.png"),
            attachmentData: bytes
        )
        let tiff = try ClipboardContentFingerprint.make(
            draft: CaptureDraft(type: .image, title: "Image", stagedAttachmentName: "image.tiff", attachmentByteCount: bytes.count, contentType: "image/tiff", fileName: "image.tiff"),
            attachmentData: bytes
        )

        XCTAssertNotEqual(png, tiff)
        XCTAssertEqual(
            png,
            try ClipboardContentFingerprint.make(
                draft: CaptureDraft(type: .image, title: "Renamed", stagedAttachmentName: "other.png", attachmentByteCount: bytes.count, contentType: "image/png", fileName: "other.png"),
                attachmentData: bytes
            )
        )
    }

    func testFileUsesCanonicalBytesAndNormalizedFilename() throws {
        let bytes = Data("asset".utf8)
        let first = try ClipboardContentFingerprint.make(
            draft: CaptureDraft(type: .file, title: "File", stagedAttachmentName: "asset.bin", attachmentByteCount: bytes.count, contentType: "application/octet-stream", fileName: "Cafe\u{301}.bin"),
            attachmentData: bytes
        )
        let normalized = try ClipboardContentFingerprint.make(
            draft: CaptureDraft(type: .file, title: "Other", stagedAttachmentName: "asset.bin", attachmentByteCount: bytes.count, contentType: "application/octet-stream", fileName: "Café.bin"),
            attachmentData: bytes
        )
        let renamed = try ClipboardContentFingerprint.make(
            draft: CaptureDraft(type: .file, title: "Other", stagedAttachmentName: "asset.bin", attachmentByteCount: bytes.count, contentType: "application/octet-stream", fileName: "different.bin"),
            attachmentData: bytes
        )

        XCTAssertEqual(first, normalized)
        XCTAssertNotEqual(first, renamed)
    }
}
