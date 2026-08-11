import Foundation
import XCTest
@testable import StowCLI
import StowCore

final class StowCLIArgumentsTests: XCTestCase {
    func testSearchParsesAgentFiltersAndJSONMode() throws {
        var parser = StowCLIArguments(arguments: [
            "search", "SwiftData", "migration", "--status", "all", "--type", "code", "--limit", "7", "--json",
        ])

        guard case .remote(let request, let json, let timeout, let export) = try parser.parse() else {
            return XCTFail("Expected remote invocation")
        }
        XCTAssertEqual(request.command, .search)
        XCTAssertEqual(request.search, StowAutomationSearchPayload(query: "SwiftData migration", status: .all, type: .code, limit: 7))
        XCTAssertTrue(json)
        XCTAssertEqual(timeout, 10)
        XCTAssertNil(export)
    }

    func testSearchAllowsFilterOnlyListing() throws {
        var parser = StowCLIArguments(arguments: ["search", "--type", "image", "--status", "all", "--json"])

        guard case .remote(let request, let json, _, _) = try parser.parse() else {
            return XCTFail("Expected remote invocation")
        }
        XCTAssertEqual(request.search, StowAutomationSearchPayload(query: "", status: .all, type: .image, limit: 20))
        XCTAssertTrue(json)
    }

    func testAddReadsUTF8StdinAndPreservesRequestID() throws {
        let id = UUID()
        var parser = StowCLIArguments(
            arguments: ["add", "--type", "code", "--language", "swift", "--stdin", "--request-id", id.uuidString],
            readStandardInput: { "let answer = 42\n" }
        )

        guard case .remote(let request, _, _, _) = try parser.parse() else {
            return XCTFail("Expected remote invocation")
        }
        XCTAssertEqual(request.requestID, id)
        XCTAssertEqual(request.add?.draft.id, id)
        XCTAssertEqual(request.add?.draft.textContent, "let answer = 42\n")
        XCTAssertEqual(request.add?.draft.sourceApp, "Stow CLI")
    }

    func testAddRejectsConflictingTextSourcesAndUnsupportedAttachments() {
        var conflicting = StowCLIArguments(
            arguments: ["add", "--type", "text", "--text", "body", "--stdin"],
            readStandardInput: { "stdin" }
        )
        XCTAssertThrowsError(try conflicting.parse())

        var image = StowCLIArguments(arguments: ["add", "--type", "image", "--text", "body"])
        XCTAssertThrowsError(try image.parse())
    }

    func testExportParsesAttachmentAndSafeOverwriteIntent() throws {
        let itemID = UUID()
        let attachmentID = UUID()
        var parser = StowCLIArguments(arguments: [
            "export", itemID.uuidString, "--attachment", attachmentID.uuidString,
            "--output", "/tmp/image.png", "--force", "--json",
        ])

        guard case .remote(let request, let json, _, let export) = try parser.parse() else {
            return XCTFail("Expected remote invocation")
        }
        XCTAssertEqual(request.export, StowAutomationExportPayload(itemID: itemID, attachmentID: attachmentID))
        XCTAssertEqual(export, StowCLIExportOptions(outputPath: "/tmp/image.png", force: true))
        XCTAssertTrue(json)
    }
}

@MainActor
final class StowCLIClientTests: XCTestCase {
    func testCachedResponseReturnsWithoutLaunchingHost() throws {
        let spool = try StowAutomationSpool(rootURL: temporaryRoot())
        let request = StowAutomationRequest(command: .status)
        try spool.submit(request)
        let claim = try XCTUnwrap(spool.claimNext())
        let expected = StowAutomationResponse(requestID: request.requestID, data: StowAutomationResult())
        try spool.complete(claim, with: expected)
        var launched = false
        let client = StowCLIClient(spool: spool, launchHost: { launched = true })

        let actual = client.send(request, timeout: 1)
        XCTAssertEqual(actual.requestID, expected.requestID)
        XCTAssertEqual(actual.data, expected.data)
        XCTAssertFalse(launched)
    }

    func testTimeoutIsStructuredAndRetainsRequestIDForRetry() throws {
        let spool = try StowAutomationSpool(rootURL: temporaryRoot())
        let request = StowAutomationRequest(command: .status)
        var current = Date(timeIntervalSince1970: 100)
        let client = StowCLIClient(
            spool: spool,
            launchHost: {},
            now: { current },
            sleep: { current = current.addingTimeInterval($0) }
        )

        let response = client.send(request, timeout: 0.1)

        XCTAssertEqual(response.requestID, request.requestID)
        XCTAssertEqual(response.error?.code, .timeout)
        XCTAssertTrue(response.error?.retryable == true)
    }

    func testExportCopyRefusesReplacementWithoutForce() throws {
        let root = temporaryRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.png")
        let destination = root.appendingPathComponent("destination.png")
        let directoryDestination = root.appendingPathComponent("directory", isDirectory: true)
        try Data("new".utf8).write(to: source)
        try Data("old".utf8).write(to: destination)
        try FileManager.default.createDirectory(at: directoryDestination, withIntermediateDirectories: true)
        let attachment = StowAutomationAttachment(
            id: UUID(),
            contentType: "image/png",
            fileName: "image.png",
            byteCount: 3,
            createdAt: Date()
        )
        let requestID = UUID()
        let response = StowAutomationResponse(
            requestID: requestID,
            data: StowAutomationResult(export: .init(itemID: UUID(), attachment: attachment, path: source.path))
        )
        let client = StowCLIClient(spool: try StowAutomationSpool(rootURL: root.appendingPathComponent("spool")))

        let refused = client.copyExportIfRequested(
            in: response,
            options: .init(outputPath: destination.path, force: false)
        )
        let replaced = client.copyExportIfRequested(
            in: response,
            options: .init(outputPath: destination.path, force: true)
        )
        let directoryRefused = client.copyExportIfRequested(
            in: response,
            options: .init(outputPath: directoryDestination.path, force: true)
        )

        XCTAssertEqual(refused.error?.code, .ioFailure)
        XCTAssertEqual(refused.error?.fallbackPath, source.path)
        XCTAssertEqual(replaced.data?.export?.path, destination.path)
        XCTAssertEqual(try Data(contentsOf: destination), Data("new".utf8))
        XCTAssertEqual(directoryRefused.error?.code, .ioFailure)
        XCTAssertEqual(directoryRefused.error?.fallbackPath, source.path)
        XCTAssertTrue(try directoryDestination.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("StowCLITests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

final class StowCLIOutputTests: XCTestCase {
    func testJSONErrorUsesStdoutAndStableExitCode() throws {
        let response = StowAutomationResponse(
            requestID: UUID(),
            error: StowAutomationError(code: .itemNotFound, message: "Missing")
        )

        let output = StowCLIOutputRenderer().render(response, json: true)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.standardOutput.utf8)) as? [String: Any])

        XCTAssertEqual(output.exitCode, 66)
        XCTAssertTrue(output.standardError.isEmpty)
        XCTAssertEqual(object["ok"] as? Bool, false)
        XCTAssertEqual((object["error"] as? [String: Any])?["code"] as? String, "item_not_found")
    }
}
