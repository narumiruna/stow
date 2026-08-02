import Foundation
import XCTest
@testable import StowCore

final class MetricsClientTests: XCTestCase {
    func testCountersPersistAcrossReopenWithoutContentFields() throws {
        let url = temporaryURL()
        let client = try OnDeviceMetricsClient(url: url, enabled: true)
        try client.record(.captureSucceeded)
        try client.record(.itemCopied)
        try client.record(.itemCopied)
        try client.recordDuration(.captureDuration, seconds: 0.4)

        let reopened = try OnDeviceMetricsClient(url: url, enabled: true)
        let snapshot = reopened.snapshot()

        XCTAssertEqual(snapshot.counts[.captureSucceeded], 1)
        XCTAssertEqual(snapshot.counts[.itemCopied], 2)
        XCTAssertEqual(snapshot.durationTotals[.captureDuration] ?? 0, 0.4, accuracy: 0.0001)
        let payload = String(data: try Data(contentsOf: url), encoding: .utf8) ?? ""
        XCTAssertFalse(payload.localizedCaseInsensitiveContains("content"))
        XCTAssertFalse(payload.localizedCaseInsensitiveContains("url"))
        XCTAssertFalse(payload.localizedCaseInsensitiveContains("filename"))
    }

    func testDisabledClientDoesNotRecordOptionalMetrics() throws {
        let client = try OnDeviceMetricsClient(url: temporaryURL(), enabled: false)

        try client.record(.searchSucceeded)

        XCTAssertTrue(client.snapshot().counts.isEmpty)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    }
}
