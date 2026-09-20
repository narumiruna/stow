import SwiftData
import XCTest
import StowCore
@testable import StowApp

@MainActor
final class MacItemActionsTests: XCTestCase {
    func testFormatsWriteBeforeAccountingAndClearErrorsOnSuccess() throws {
        let (model, root) = try makeModel()
        let item = try XCTUnwrap(model.repository).create(
            from: CaptureDraft(type: .text, title: "Rich", textContent: "plain"),
            representations: [StowRepresentationDraft(typeIdentifier: StowRepresentationType.rtf, data: Data("{\\rtf1 plain}".utf8), ordinal: 0)]
        )
        for (index, format) in [PasteFormat.original, .plainText].enumerated() {
            model.presentedError = "old error"
            let writer = CopyWriter { payload in
                XCTAssertEqual(item.useCount, index)
                XCTAssertEqual(try self.copyCount(root), index)
                XCTAssertEqual(payload.entries.first?.data, Data("plain".utf8))
                XCTAssertEqual(payload.entries.map(\.typeIdentifier), format == .original
                    ? [StowRepresentationType.plainText, StowRepresentationType.rtf, StowRepresentationType.stowOwned]
                    : [StowRepresentationType.plainText, StowRepresentationType.stowOwned])
                return true
            }
            XCTAssertTrue(model.copy(item, attachment: nil, format: format, writer: writer))
            XCTAssertEqual(writer.calls, 1)
            XCTAssertEqual(item.useCount, index + 1)
            XCTAssertEqual(try copyCount(root), index + 1)
            XCTAssertNil(model.presentedError)
        }
    }

    func testMissingAttachmentAndFailedWriteDoNotRecordUse() throws {
        let (model, root) = try makeModel()
        let repository = try XCTUnwrap(model.repository)
        let file = try repository.create(from: CaptureDraft(type: .file, title: "File", stagedAttachmentName: "a.txt", attachmentByteCount: 1, contentType: "text/plain", fileName: "a.txt"))
        let writer = CopyWriter { _ in false }
        XCTAssertFalse(model.copy(file, attachment: nil, writer: writer))
        XCTAssertEqual(writer.calls, 0)
        XCTAssertEqual(file.useCount, 0)
        XCTAssertEqual(model.presentedError, PlatformActionError.unavailable.localizedDescription)
        let text = try repository.create(from: CaptureDraft(type: .text, title: "Text", textContent: "body"))
        XCTAssertFalse(model.copy(text, attachment: nil, writer: writer))
        XCTAssertEqual(writer.calls, 1)
        XCTAssertEqual(text.useCount, 0)
        XCTAssertNil(text.lastUsedAt)
        XCTAssertEqual(try copyCount(root), 0)
        XCTAssertEqual(model.presentedError, PlatformActionError.unavailable.localizedDescription)
    }

    func testRepresentationFailureStillCopiesFallbackThenClearsError() throws {
        let (model, root) = try makeModel(loadRepresentations: { _ in throw PlatformActionError.unavailable })
        let item = try XCTUnwrap(model.repository).create(from: CaptureDraft(type: .text, title: "Text", textContent: "fallback"))
        let writer = CopyWriter { payload in
            XCTAssertEqual(model.presentedError, PlatformActionError.unavailable.localizedDescription)
            XCTAssertEqual(item.useCount, 0)
            XCTAssertEqual(payload.entries.map(\.typeIdentifier), [StowRepresentationType.plainText, StowRepresentationType.stowOwned])
            XCTAssertEqual(payload.entries.first?.data, Data("fallback".utf8))
            return true
        }
        XCTAssertTrue(model.copy(item, attachment: nil, writer: writer))
        XCTAssertNil(model.presentedError)
        XCTAssertEqual(item.useCount, 1)
        XCTAssertEqual(try copyCount(root), 1)
    }

    private func makeModel(loadRepresentations: ((UUID) throws -> [StowRepresentation])? = nil) throws -> (AppModel, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("StowCopyTests-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let container = try StowContainerFactory.inMemory()
        let model = AppModel(runtimePaths: StowRuntimePaths(sharedContainer: root, temporaryDirectory: root.appendingPathComponent("Temporary")), loadRepresentations: loadRepresentations)
        model.connect(ModelContext(container))
        model.setMetricsEnabled(true)
        return (model, root)
    }

    private func copyCount(_ root: URL) throws -> Int {
        try OnDeviceMetricsClient(url: root.appendingPathComponent("Metrics/v0.1.json"), enabled: true).snapshot().counts[.itemCopied] ?? 0
    }
}

@MainActor
private final class CopyWriter: PlatformPasteboardWriting {
    var calls = 0
    let operation: (PastePayload) throws -> Bool
    init(_ operation: @escaping (PastePayload) throws -> Bool) { self.operation = operation }
    func write(_ payload: PastePayload) -> Bool {
        calls += 1
        do { return try operation(payload) }
        catch { XCTFail("Unexpected writer assertion error: \(error)"); return false }
    }
}
