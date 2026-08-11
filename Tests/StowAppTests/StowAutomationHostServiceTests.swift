import SwiftData
import StowCore
import XCTest
@testable import StowApp

@MainActor
final class StowAutomationHostServiceTests: XCTestCase {
    func testAddIsIdempotentAndGetDoesNotRecordUsage() async throws {
        let setup = try makeService()
        let requestID = UUID()
        let draft = CaptureDraft(
            id: requestID,
            type: .code,
            title: "Agent example",
            textContent: "let answer = 42",
            sourceApp: "Stow CLI",
            language: "swift"
        )
        let add = StowAutomationRequest(
            requestID: requestID,
            command: .add,
            add: StowAutomationAddPayload(draft: draft)
        )

        let first = await setup.service.execute(add)
        let second = await setup.service.execute(add)
        let itemID = try XCTUnwrap(first.data?.item?.id)
        let get = await setup.service.execute(StowAutomationRequest(command: .get, get: .init(itemID: itemID)))

        XCTAssertTrue(first.ok)
        XCTAssertEqual(second.data?.item?.id, itemID)
        XCTAssertEqual(try setup.model.repository?.allItems().count, 1)
        XCTAssertEqual(get.data?.item?.textContent, "let answer = 42")
        XCTAssertEqual(get.data?.item?.useCount, 0)
    }

    func testFilterOnlyAndQueriedSearchReturnBoundedSummariesWithExistingSearchSemantics() async throws {
        let setup = try makeService()
        let repository = try XCTUnwrap(setup.model.repository)
        _ = try repository.create(from: CaptureDraft(type: .text, title: "Other", textContent: "unrelated"), at: Date(timeIntervalSince1970: 100))
        let wanted = try repository.create(
            from: CaptureDraft(type: .code, title: "Migration", textContent: String(repeating: "SwiftData migration ", count: 30), language: "swift"),
            at: Date(timeIntervalSince1970: 200)
        )

        let filtered = await setup.service.execute(StowAutomationRequest(
            command: .search,
            search: .init(query: "", status: .inbox, type: .code, limit: 1)
        ))
        let search = await setup.service.execute(StowAutomationRequest(
            command: .search,
            search: .init(query: "SwiftData migration", status: nil, type: .code, limit: 10)
        ))

        XCTAssertEqual(filtered.data?.items?.map(\.id), [wanted.id])
        XCTAssertEqual(search.data?.items?.map(\.id), [wanted.id])
        XCTAssertTrue((search.data?.items?.first?.snippet?.count ?? 0) <= 240)
    }

    func testGetReturnsImageMetadataAndExportPreservesBytesAndRecordsUse() async throws {
        let setup = try makeService()
        let repository = try XCTUnwrap(setup.model.repository)
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        let item = try repository.create(from: CaptureDraft(
            type: .image,
            title: "Diagram",
            stagedAttachmentName: "diagram.png",
            attachmentByteCount: bytes.count,
            contentType: "image/png",
            fileName: "diagram.png"
        ))
        let attachment = StowAttachment(
            itemID: item.id,
            data: bytes,
            contentType: "image/png",
            fileName: "diagram.png",
            pixelWidth: 1600,
            pixelHeight: 900
        )
        try repository.addAttachment(attachment)

        let get = await setup.service.execute(StowAutomationRequest(command: .get, get: .init(itemID: item.id)))
        let export = await setup.service.execute(StowAutomationRequest(command: .export, export: .init(itemID: item.id)))
        let exportPath = try XCTUnwrap(export.data?.export?.path)

        XCTAssertEqual(get.data?.item?.attachments.first?.contentType, "image/png")
        XCTAssertEqual(get.data?.item?.attachments.first?.pixelWidth, 1600)
        XCTAssertEqual(get.data?.item?.attachments.first?.pixelHeight, 900)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: exportPath)), bytes)
        XCTAssertEqual(try repository.item(id: item.id)?.useCount, 1)
    }

    func testMultipleAttachmentsRequireExplicitSelection() async throws {
        let setup = try makeService()
        let repository = try XCTUnwrap(setup.model.repository)
        let item = try repository.create(from: CaptureDraft(type: .file, title: "Files", stagedAttachmentName: "a.txt", attachmentByteCount: 1, contentType: "text/plain", fileName: "a.txt"))
        try repository.addAttachment(StowAttachment(itemID: item.id, data: Data("a".utf8), contentType: "text/plain", fileName: "a.txt"))
        try repository.addAttachment(StowAttachment(itemID: item.id, data: Data("b".utf8), contentType: "text/plain", fileName: "b.txt"))

        let response = await setup.service.execute(StowAutomationRequest(command: .export, export: .init(itemID: item.id)))

        XCTAssertEqual(response.error?.code, .attachmentSelectionRequired)
        XCTAssertEqual(try repository.item(id: item.id)?.useCount, 0)
    }

    func testUnsupportedProtocolVersionFailsWithoutExecutingCommand() async throws {
        let setup = try makeService()
        let response = await setup.service.execute(StowAutomationRequest(command: .status, schemaVersion: 99))

        XCTAssertEqual(response.error?.code, .unsupportedVersion)
        XCTAssertTrue(try setup.model.repository?.allItems().isEmpty == true)
    }

    private func makeService() throws -> (service: StowAutomationHostService, model: AppModel) {
        let container = try StowContainerFactory.inMemory()
        let model = AppModel()
        model.connect(ModelContext(container))
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("StowAutomationHostServiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let spool = try StowAutomationSpool(rootURL: root)
        return (StowAutomationHostService(model: model, spool: spool, hostVersion: "test"), model)
    }
}
