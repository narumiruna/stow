import AppKit
import XCTest
import StowCore
@testable import StowApp

@MainActor
final class ClipboardCapturePolicyTests: XCTestCase {
    func testEveryProtectedMarkerIsIgnoredByPresenceAlone() {
        let cases: [(String, ClipboardCaptureIgnoreReason)] = [
            (ClipboardPasteboardTypeIdentifier.concealed, .concealed),
            (ClipboardPasteboardTypeIdentifier.transient, .transient),
            (ClipboardPasteboardTypeIdentifier.stowOwned, .stowOwned),
        ]

        for (marker, reason) in cases {
            XCTAssertEqual(
                ClipboardCapturePolicy.decision(for: [marker]),
                .ignore(reason)
            )
            XCTAssertEqual(
                ClipboardCapturePolicy.decision(for: [NSPasteboard.PasteboardType.string.rawValue, marker]),
                .ignore(reason)
            )
        }
    }

    func testUnknownVendorAndOrdinarySupportedTypesRemainCapturable() {
        for types in [
            ["com.example.vendor-metadata"],
            [NSPasteboard.PasteboardType.string.rawValue],
            [NSPasteboard.PasteboardType.URL.rawValue],
            [NSPasteboard.PasteboardType.png.rawValue],
            [NSPasteboard.PasteboardType.fileURL.rawValue],
        ] {
            XCTAssertEqual(ClipboardCapturePolicy.decision(for: types), .capture)
        }
    }

    func testProtectedChangeAdvancesOnceWithoutPayloadReadsCallbacksOrErrors() {
        let reader = PasteboardReaderDouble(
            advertisedTypeIdentifiers: [
                NSPasteboard.PasteboardType.string.rawValue,
                ClipboardPasteboardTypeIdentifier.concealed,
            ],
            string: "must not be read"
        )
        let monitor = ClipboardMonitor(reader: reader)
        let model = AppModel()
        var captures = 0
        monitor.captureHandler = { _ in captures += 1 }
        monitor.errorHandler = { model.presentedError = $0.localizedDescription }
        monitor.start()
        defer { monitor.stop() }

        reader.changeCount += 1
        monitor.checkForChanges()
        monitor.checkForChanges()

        XCTAssertEqual(reader.typeReadCount, 1, "One change count must be evaluated once")
        XCTAssertEqual(reader.payloadReadCount, 0, "Protected content must never be read")
        XCTAssertEqual(captures, 0)
        XCTAssertNil(model.presentedError)
    }

    func testOrdinaryTextAndLinkChangesStillCapture() throws {
        let text = try capture(
            reader: PasteboardReaderDouble(
                advertisedTypeIdentifiers: [NSPasteboard.PasteboardType.string.rawValue],
                string: "ordinary text"
            )
        )
        guard case .draft(let textDraft, _) = text else { return XCTFail("Expected a text draft") }
        XCTAssertEqual(textDraft.type, .text)
        XCTAssertEqual(textDraft.textContent, "ordinary text")

        let link = try capture(
            reader: PasteboardReaderDouble(
                advertisedTypeIdentifiers: [NSPasteboard.PasteboardType.string.rawValue],
                string: "https://example.com/path"
            )
        )
        guard case .draft(let linkDraft, _) = link else { return XCTFail("Expected a link draft") }
        XCTAssertEqual(linkDraft.type, .link)
        XCTAssertEqual(linkDraft.urlString, "https://example.com/path")
    }

    func testSafeRepresentationsAreSelectedOnlyAfterPolicyPreflight() throws {
        let richReader = PasteboardReaderDouble(
            advertisedTypeIdentifiers: [
                NSPasteboard.PasteboardType.rtf.rawValue,
                NSPasteboard.PasteboardType.html.rawValue,
                NSPasteboard.PasteboardType.string.rawValue,
            ],
            string: "Rich text",
            candidates: [
                PasteboardRepresentationCandidate(typeIdentifier: StowRepresentationType.rtf, data: Data("{\\rtf1 Rich text}".utf8)),
                PasteboardRepresentationCandidate(typeIdentifier: StowRepresentationType.html, data: Data("<b>Rich text</b>".utf8)),
                PasteboardRepresentationCandidate(typeIdentifier: StowRepresentationType.plainText, data: Data("Rich text".utf8)),
                PasteboardRepresentationCandidate(typeIdentifier: "com.example.private", data: Data([1])),
            ]
        )

        let content = try capture(reader: richReader)

        guard case .draft(let draft, let representations) = content else {
            return XCTFail("Expected rich text draft")
        }
        XCTAssertEqual(draft.textContent, "Rich text")
        XCTAssertEqual(representations.map(\.typeIdentifier), [
            StowRepresentationType.rtf,
            StowRepresentationType.html,
        ])
        XCTAssertEqual(richReader.snapshotReadCount, 1)
        XCTAssertEqual(richReader.typeReadCount, 1)
    }

    func testOrdinaryImageAndFileChangesStillCaptureWithoutGeneralPasteboard() throws {
        let imageReader = PasteboardReaderDouble(
            advertisedTypeIdentifiers: [NSPasteboard.PasteboardType.png.rawValue],
            image: testImage()
        )
        let image = try capture(reader: imageReader)
        guard case .attachment(let imageDraft, let imageURL, _) = image else {
            return XCTFail("Expected an image attachment")
        }
        defer { try? FileManager.default.removeItem(at: imageURL.deletingLastPathComponent()) }
        XCTAssertEqual(imageDraft.type, .image)
        XCTAssertGreaterThan(imageDraft.attachmentByteCount ?? 0, 0)

        let sourceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipboardCapturePolicyTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sourceDirectory) }
        let sourceURL = sourceDirectory.appendingPathComponent("fixture.txt")
        try Data("file fixture".utf8).write(to: sourceURL)
        let fileReader = PasteboardReaderDouble(
            advertisedTypeIdentifiers: [NSPasteboard.PasteboardType.fileURL.rawValue],
            urls: [sourceURL]
        )
        let file = try capture(reader: fileReader)
        guard case .attachment(let fileDraft, let stagedURL, _) = file else {
            return XCTFail("Expected a file attachment")
        }
        defer { try? FileManager.default.removeItem(at: stagedURL.deletingLastPathComponent()) }
        XCTAssertEqual(fileDraft.type, .file)
        XCTAssertEqual(fileDraft.fileName, "fixture.txt")
    }

    private func capture(reader: PasteboardReaderDouble) throws -> ClipboardMonitor.CapturedContent {
        let monitor = ClipboardMonitor(reader: reader)
        var captured: ClipboardMonitor.CapturedContent?
        var capturedError: Error?
        monitor.captureHandler = { captured = $0 }
        monitor.errorHandler = { capturedError = $0 }
        monitor.start()
        defer { monitor.stop() }
        reader.changeCount += 1
        monitor.checkForChanges()
        if let capturedError { throw capturedError }
        return try XCTUnwrap(captured)
    }

    private func testImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()
        return image
    }
}

@MainActor
private final class PasteboardReaderDouble: ClipboardPasteboardReading {
    var changeCount = 0
    var captureAccessAllowed = true
    var statusText = "Monitoring"
    private let types: [String]
    private let urls: [URL]
    private let image: NSImage?
    private let string: String?
    private let candidates: [PasteboardRepresentationCandidate]?
    private(set) var typeReadCount = 0
    private(set) var payloadReadCount = 0
    private(set) var snapshotReadCount = 0

    init(
        advertisedTypeIdentifiers: [String],
        urls: [URL] = [],
        image: NSImage? = nil,
        string: String? = nil,
        candidates: [PasteboardRepresentationCandidate]? = nil
    ) {
        types = advertisedTypeIdentifiers
        self.urls = urls
        self.image = image
        self.string = string
        self.candidates = candidates
    }

    var advertisedTypeIdentifiers: [String] {
        typeReadCount += 1
        return types
    }

    func readURLs() -> [URL] {
        payloadReadCount += 1
        return urls
    }

    func readImage() -> NSImage? {
        payloadReadCount += 1
        return image
    }

    func readString() -> String? {
        payloadReadCount += 1
        return string
    }

    func readSnapshot() -> ClipboardPasteboardSnapshot {
        payloadReadCount += 1
        snapshotReadCount += 1
        return ClipboardPasteboardSnapshot(
            candidates: candidates ?? string.map {
                [PasteboardRepresentationCandidate(
                    typeIdentifier: StowRepresentationType.plainText,
                    data: Data($0.utf8)
                )]
            } ?? [],
            urls: urls
        )
    }
}
