import XCTest
import StowCore
@testable import StowApp

final class StowAppSmokeTests: XCTestCase {
    func testCoreDependencyIsLinkedIntoNativeUnitTestTarget() throws {
        let draft = try CaptureDraft(type: .text, title: "", textContent: "Smoke test").normalized()
        XCTAssertEqual(draft.title, "Smoke test")
    }

    @MainActor
    func testAttachmentResultIgnoresUnrelatedMalformedPendingCapture() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let spoolRoot = root.appendingPathComponent("CaptureSpool", isDirectory: true)
        let spool = try CaptureSpool(rootURL: spoolRoot)
        let container = try StowContainerFactory.inMemory()
        let model = AppModel(captureSpool: spool, sharedContainerURL: root)
        model.connect(container.mainContext)

        let malformed = spoolRoot.appendingPathComponent("Pending/malformed", isDirectory: true)
        try FileManager.default.createDirectory(at: malformed, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: malformed.appendingPathComponent("manifest.json"))
        let sourceDirectory = root.appendingPathComponent("Source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let attachmentURL = sourceDirectory.appendingPathComponent("current.txt")
        try Data("current".utf8).write(to: attachmentURL)
        let captureID = UUID()

        XCTAssertTrue(model.createAttachment(
            CaptureDraft(
                id: captureID,
                type: .file,
                title: "Current",
                stagedAttachmentName: "current.txt",
                attachmentByteCount: 7,
                contentType: "text/plain",
                fileName: "current.txt"
            ),
            fileURL: attachmentURL
        ))
        XCTAssertNil(model.presentedError)
        XCTAssertEqual(try model.repository?.allItems().map(\.captureID), [captureID])
        XCTAssertTrue(FileManager.default.fileExists(atPath: malformed.path))
    }
}
