import Foundation
import XCTest
@testable import StowCore

final class StowAutomationProtocolTests: XCTestCase {
    func testRequestRoundTripUsesStableSnakeCaseKeysAndISO8601Dates() throws {
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let draft = CaptureDraft(id: id, type: .code, title: "Example", textContent: "let value = 42", sourceApp: "Stow CLI", language: "swift")
        let request = StowAutomationRequest(
            requestID: id,
            createdAt: date,
            command: .add,
            add: StowAutomationAddPayload(draft: draft)
        )

        let data = try StowAutomationProtocol.encoder().encode(request)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let decoded = try StowAutomationProtocol.decoder().decode(StowAutomationRequest.self, from: data)

        XCTAssertTrue(json.contains("\"schema_version\":1"))
        XCTAssertTrue(json.contains("\"request_id\""))
        XCTAssertTrue(json.contains("2023-11-14T22:13:20Z"))
        XCTAssertEqual(decoded, request)
    }

    func testResponseErrorEncodingIsStableAndRetryable() throws {
        let id = UUID()
        let response = StowAutomationResponse(
            requestID: id,
            error: StowAutomationError(code: .timeout, message: "Timed out.", retryable: true)
        )

        let data = try StowAutomationProtocol.encoder().encode(response)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let decoded = try StowAutomationProtocol.decoder().decode(StowAutomationResponse.self, from: data)

        XCTAssertTrue(json.contains("\"retryable\":true"))
        XCTAssertTrue(json.contains("\"code\":\"timeout\""))
        XCTAssertEqual(decoded.requestID, response.requestID)
        XCTAssertEqual(decoded.error, response.error)
        XCTAssertFalse(decoded.ok)
    }

    func testIOErrorEncodesStructuredFallbackPath() throws {
        let response = StowAutomationResponse(
            requestID: UUID(),
            error: StowAutomationError(
                code: .ioFailure,
                message: "Copy failed.",
                fallbackPath: "/private/export/image.png"
            )
        )

        let data = try StowAutomationProtocol.encoder().encode(response)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let error = try XCTUnwrap(object["error"] as? [String: Any])

        XCTAssertEqual(error["fallback_path"] as? String, "/private/export/image.png")
    }

    func testUnsupportedSchemaVersionRemainsVisibleForExplicitRejection() throws {
        let request = StowAutomationRequest(command: .status, schemaVersion: 99)
        let data = try StowAutomationProtocol.encoder().encode(request)
        let decoded = try StowAutomationProtocol.decoder().decode(StowAutomationRequest.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, 99)
        XCTAssertNotEqual(decoded.schemaVersion, StowAutomationProtocol.schemaVersion)
    }
}

final class StowAutomationSpoolTests: XCTestCase {
    func testRequestSurvivesReopenAndCompletesExactlyOnce() throws {
        let root = temporaryRoot()
        let id = UUID()
        let request = StowAutomationRequest(requestID: id, command: .status)
        try StowAutomationSpool(rootURL: root).submit(request)

        let host = try StowAutomationSpool(rootURL: root)
        let claim = try XCTUnwrap(host.claimNext())
        XCTAssertEqual(claim.request.requestID, request.requestID)
        XCTAssertEqual(claim.request.command, request.command)
        let response = StowAutomationResponse(requestID: id, data: StowAutomationResult(status: .init(hostVersion: "0.1.0", storage: "local")))
        try host.complete(claim, with: response)

        let client = try StowAutomationSpool(rootURL: root)
        XCTAssertEqual(try client.response(for: id)?.data, response.data)
        XCTAssertEqual(try client.response(for: id)?.requestID, response.requestID)
        XCTAssertNil(try host.claimNext())
    }

    func testResponseRejectsMismatchedRequestIDAndUnsupportedVersion() throws {
        let spool = try StowAutomationSpool(rootURL: temporaryRoot())
        let requestedID = UUID()
        let responseURL = spool.responsesDirectoryURL.appendingPathComponent("\(requestedID.uuidString).json")
        let mismatch = StowAutomationResponse(requestID: UUID(), data: StowAutomationResult())
        try StowAutomationProtocol.encoder().encode(mismatch).write(to: responseURL)
        XCTAssertThrowsError(try spool.response(for: requestedID)) { error in
            XCTAssertEqual(error as? StowAutomationSpoolError, .requestIDMismatch)
        }

        let unsupported = StowAutomationResponse(requestID: requestedID, data: StowAutomationResult(), schemaVersion: 99)
        try StowAutomationProtocol.encoder().encode(unsupported).write(to: responseURL, options: .atomic)
        XCTAssertThrowsError(try spool.response(for: requestedID)) { error in
            XCTAssertEqual(error as? StowAutomationSpoolError, .unsupportedVersion)
        }
    }

    func testDuplicateRequestIDDoesNotReplacePendingOrCompletedWork() throws {
        let root = temporaryRoot()
        let id = UUID()
        let original = StowAutomationRequest(requestID: id, command: .status)
        let duplicate = StowAutomationRequest(
            requestID: id,
            command: .get,
            get: StowAutomationGetPayload(itemID: UUID())
        )
        let spool = try StowAutomationSpool(rootURL: root)

        try spool.submit(original)
        try spool.submit(duplicate)
        let claim = try XCTUnwrap(spool.claimNext())
        XCTAssertEqual(claim.request.command, .status)
        let response = StowAutomationResponse(requestID: id, data: StowAutomationResult())
        try spool.complete(claim, with: response)
        try spool.submit(duplicate)

        XCTAssertNil(try spool.claimNext())
        XCTAssertEqual(try spool.response(for: id)?.data, response.data)
        XCTAssertEqual(try spool.response(for: id)?.requestID, response.requestID)
    }

    func testDuplicatePendingFileCannotBlockAnInFlightRequest() throws {
        let spool = try StowAutomationSpool(rootURL: temporaryRoot())
        let request = StowAutomationRequest(command: .status)
        try spool.submit(request)
        _ = try XCTUnwrap(spool.claimNext())
        let duplicate = spool.pendingDirectoryURL.appendingPathComponent("\(request.requestID.uuidString).json")
        try StowAutomationProtocol.encoder().encode(request).write(to: duplicate)

        XCTAssertNil(try spool.claimNext())
        XCTAssertFalse(FileManager.default.fileExists(atPath: duplicate.path))
    }

    func testMalformedRequestIsQuarantinedAndReturnsStructuredFailure() throws {
        let root = temporaryRoot()
        let spool = try StowAutomationSpool(rootURL: root)
        let id = UUID()
        let malformed = spool.pendingDirectoryURL.appendingPathComponent("\(id.uuidString).json")
        try Data("not-json".utf8).write(to: malformed)

        XCTAssertNil(try spool.claimNext())
        let response = try XCTUnwrap(spool.response(for: id))
        XCTAssertEqual(response.error?.code, .invalidRequest)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: spool.quarantineDirectoryURL.path).count, 1)
    }

    func testInterruptedClaimReturnsToPendingDuringHostRecovery() throws {
        let root = temporaryRoot()
        let id = UUID()
        let firstHost = try StowAutomationSpool(rootURL: root)
        try firstHost.submit(StowAutomationRequest(requestID: id, command: .status))
        _ = try XCTUnwrap(firstHost.claimNext())

        let restartedHost = try StowAutomationSpool(rootURL: root)
        try restartedHost.recoverInterruptedProcessing()
        let recovered = try XCTUnwrap(restartedHost.claimNext())

        XCTAssertEqual(recovered.request.requestID, id)
    }

    func testExportUsesSafeFileNameAndPreservesBytes() throws {
        let spool = try StowAutomationSpool(rootURL: temporaryRoot())
        let bytes = Data([0, 1, 2, 3])
        let url = try spool.writeExport(bytes, fileName: "image.png", requestID: UUID())

        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(url.lastPathComponent, "image.png")
        XCTAssertThrowsError(try spool.writeExport(bytes, fileName: "../image.png", requestID: UUID()))
    }

    func testExportRejectsSymlinkedRequestDirectory() throws {
        let spool = try StowAutomationSpool(rootURL: temporaryRoot())
        let outside = temporaryRoot()
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let requestID = UUID()
        try FileManager.default.createSymbolicLink(
            at: spool.exportsDirectoryURL.appendingPathComponent(requestID.uuidString),
            withDestinationURL: outside
        )

        XCTAssertThrowsError(try spool.writeExport(Data("private".utf8), fileName: "item.txt", requestID: requestID)) { error in
            XCTAssertEqual(error as? StowAutomationSpoolError, .unsafeExportDirectory)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("item.txt").path))
    }

    func testInterruptedStagingCleanupRemovesPrivateTemporaryFiles() throws {
        let spool = try StowAutomationSpool(rootURL: temporaryRoot())
        let requestStaging = spool.rootURL.appendingPathComponent(".staging-private.json")
        let responseStaging = spool.rootURL.appendingPathComponent(".response-private.json")
        try Data("request content".utf8).write(to: requestStaging)
        try Data("response content".utf8).write(to: responseStaging)
        let oldDate = Date(timeIntervalSince1970: 100)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: requestStaging.path)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: responseStaging.path)

        XCTAssertEqual(try spool.removeInterruptedStaging(olderThan: 50, now: Date(timeIntervalSince1970: 200)), 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: requestStaging.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: responseStaging.path))
    }

    func testCleanupRemovesOnlyExpiredCompletedArtifacts() throws {
        let spool = try StowAutomationSpool(rootURL: temporaryRoot())
        let oldID = UUID()
        let freshID = UUID()
        try completeStatus(id: oldID, using: spool)
        try completeStatus(id: freshID, using: spool)
        let oldResponse = spool.responsesDirectoryURL.appendingPathComponent("\(oldID.uuidString).json")
        let oldDate = Date(timeIntervalSince1970: 100)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: oldResponse.path)

        let removed = try spool.removeCompletedArtifacts(olderThan: 50, now: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(removed, 1)
        XCTAssertNil(try spool.response(for: oldID))
        XCTAssertNotNil(try spool.response(for: freshID))
    }

    private func completeStatus(id: UUID, using spool: StowAutomationSpool) throws {
        try spool.submit(StowAutomationRequest(requestID: id, command: .status))
        let claim = try XCTUnwrap(spool.claimNext())
        try spool.complete(claim, with: StowAutomationResponse(requestID: id, data: StowAutomationResult()))
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("StowAutomationTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
