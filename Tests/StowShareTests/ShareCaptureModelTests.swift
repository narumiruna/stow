import Foundation
import StowCore
import UniformTypeIdentifiers
import XCTest

@MainActor
final class ShareCaptureModelTests: XCTestCase {
    func testSaveFailureKeepsLoadedDraftRetryable() async throws {
        struct TransientError: LocalizedError {
            var errorDescription: String? { "Temporary spool failure" }
        }
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var attempts = 0
        let model = ShareCaptureModel(
            storageRoot: { root },
            spoolFactory: { url in
                attempts += 1
                if attempts == 1 { throw TransientError() }
                return try CaptureSpool(rootURL: url)
            },
            stagingRootURL: root.appendingPathComponent("Imports", isDirectory: true)
        )
        await model.load(from: [textItem("retryable body")])

        XCTAssertThrowsError(try model.save())
        XCTAssertEqual(model.saveErrorMessage, "Temporary spool failure")
        XCTAssertTrue(model.canSave)

        try model.save()

        XCTAssertNil(model.saveErrorMessage)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(
            try CaptureSpool(rootURL: root.appendingPathComponent("CaptureSpool", isDirectory: true)).pendingCount(),
            1
        )
    }

    func testOversizedSourceIsRejectedBeforeCopying() async throws {
        struct CopyShouldNotRun: LocalizedError {
            var errorDescription: String? { "Copy should not run" }
        }
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("oversized.bin")
        FileManager.default.createFile(atPath: source.path, contents: Data([0]))
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: UInt64(100 * 1_024 * 1_024 + 1))
        try handle.close()
        let imports = root.appendingPathComponent("Imports", isDirectory: true)
        let model = ShareCaptureModel(
            storageRoot: { root },
            stagingRootURL: imports,
            copyFile: { _, _ in throw CopyShouldNotRun() }
        )

        await model.load(from: [fileItem(source)])

        XCTAssertFalse(model.canSave)
        XCTAssertEqual(model.loadErrorMessage, CaptureValidationError.attachmentTooLarge.localizedDescription)
        XCTAssertFalse(model.errorMessage?.contains("Copy should not run") == true)
        XCTAssertTrue(directoryContents(at: imports).isEmpty)
    }

    func testPartialCopyFailureRemovesOwnedStagingDirectory() async throws {
        struct InjectedCopyError: LocalizedError {
            var errorDescription: String? { "Injected partial copy failure" }
        }
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("partial.bin")
        try Data("complete".utf8).write(to: source)
        let imports = root.appendingPathComponent("Imports", isDirectory: true)
        let model = ShareCaptureModel(
            storageRoot: { root },
            stagingRootURL: imports,
            copyFile: { _, destination in
                try Data("partial".utf8).write(to: destination)
                throw InjectedCopyError()
            }
        )

        await model.load(from: [fileItem(source)])

        XCTAssertEqual(model.loadErrorMessage, "Injected partial copy failure")
        XCTAssertFalse(model.canSave)
        XCTAssertTrue(directoryContents(at: imports).isEmpty)
    }

    func testCancelRemovesLoadedStagingDirectory() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("cancel.bin")
        try Data("cancel".utf8).write(to: source)
        let imports = root.appendingPathComponent("Imports", isDirectory: true)
        let model = ShareCaptureModel(storageRoot: { root }, stagingRootURL: imports)
        await model.load(from: [fileItem(source)])
        XCTAssertTrue(model.canSave)
        XCTAssertEqual(directoryContents(at: imports).count, 1)

        model.cancel()

        XCTAssertFalse(model.canSave)
        XCTAssertTrue(directoryContents(at: imports).isEmpty)
    }

    func testSuccessfulSaveTransfersAttachmentOwnershipToSpool() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("owned.bin")
        let bytes = Data("owned bytes".utf8)
        try bytes.write(to: source)
        let imports = root.appendingPathComponent("Imports", isDirectory: true)
        let model = ShareCaptureModel(storageRoot: { root }, stagingRootURL: imports)
        await model.load(from: [fileItem(source)])

        try model.save()

        XCTAssertTrue(directoryContents(at: imports).isEmpty)
        let spool = try CaptureSpool(rootURL: root.appendingPathComponent("CaptureSpool", isDirectory: true))
        XCTAssertEqual(try spool.pendingCount(), 1)
        let container = try StowContainerFactory.inMemory()
        let repository = StowRepository(modelContext: container.mainContext)
        XCTAssertEqual(spool.ingestAll(into: repository).ingested, 1)
        let item = try XCTUnwrap(repository.allItems().first)
        XCTAssertEqual(try repository.attachments(itemID: item.id).first?.data, bytes)
    }

    func testLateProviderCompletionIsIgnoredAfterCancellation() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("late.bin")
        try Data("late".utf8).write(to: source)
        let delayed = DelayedFileProvider(sourceURL: source)
        let item = NSExtensionItem()
        item.attachments = [delayed.provider]
        let imports = root.appendingPathComponent("Imports", isDirectory: true)
        let model = ShareCaptureModel(storageRoot: { root }, stagingRootURL: imports)

        let loading = Task { await model.load(from: [item]) }
        await delayed.waitUntilRequested()
        model.cancel()
        delayed.complete()
        await loading.value

        XCTAssertFalse(model.canSave)
        XCTAssertNil(model.loadErrorMessage)
        XCTAssertTrue(directoryContents(at: imports).isEmpty)
    }

    private func textItem(_ text: String) -> NSExtensionItem {
        let provider = NSItemProvider(
            item: text as NSString,
            typeIdentifier: UTType.plainText.identifier
        )
        let item = NSExtensionItem()
        item.attachments = [provider]
        return item
    }

    private func fileItem(_ sourceURL: URL) -> NSExtensionItem {
        let provider = NSItemProvider()
        provider.suggestedName = sourceURL.lastPathComponent
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.data.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            completion(sourceURL, false, nil)
            return nil
        }
        let item = NSExtensionItem()
        item.attachments = [provider]
        return item
    }

    private func directoryContents(at url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        )) ?? []
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class DelayedFileProvider: @unchecked Sendable {
    let provider = NSItemProvider()
    private let sourceURL: URL
    private let lock = NSLock()
    private var completion: ((URL?, Bool, Error?) -> Void)?

    init(sourceURL: URL) {
        self.sourceURL = sourceURL
        provider.suggestedName = sourceURL.lastPathComponent
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.data.identifier,
            fileOptions: [],
            visibility: .all
        ) { [weak self] completion in
            self?.lock.withLock { self?.completion = completion }
            return nil
        }
    }

    func waitUntilRequested() async {
        while lock.withLock({ completion == nil }) {
            await Task.yield()
        }
    }

    func complete() {
        let completion = lock.withLock { self.completion }
        completion?(sourceURL, false, nil)
    }
}
