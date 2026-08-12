import XCTest
@testable import StowCore

final class PerformanceReliabilityTests: XCTestCase {
    func testTenThousandItemSearchMeetsApprovedThresholds() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let index = try SQLiteSearchIndex(url: root.appendingPathComponent("search.sqlite"))
        let documents = (0..<10_000).map { index in
            SearchDocument(
                id: UUID(),
                content: [
                    "Reference item \(index)",
                    index.isMultiple(of: 4) ? "https://example.com/\(index) example.com" : nil,
                    "private searchable payload token\(index % 100)",
                    "fixture note \(index % 17)",
                    index.isMultiple(of: 5) ? "document-\(index).pdf" : nil,
                ].compactMap { $0 }.joined(separator: "\n"),
                type: ItemType.allCases[index % ItemType.allCases.count],
                sourceApp: index.isMultiple(of: 3) ? "Fixture" : nil,
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                status: .inbox,
                isPinned: false,
                lastUsedAt: nil
            )
        }

        let clock = ContinuousClock()
        let rebuildStart = clock.now
        try await index.rebuild(documents)
        let rebuildSeconds = rebuildStart.duration(to: clock.now).seconds
        XCTAssertLessThan(rebuildSeconds, 5, "10,000-item rebuild exceeded the approved 5-second threshold")

        var queryDurations: [Double] = []
        for _ in 0..<20 {
            let start = clock.now
            _ = try await index.search(SearchQuery(text: "private token42", type: .text, limit: 10_000))
            queryDurations.append(start.duration(to: clock.now).seconds)
        }
        queryDurations.sort()
        let median = queryDurations[queryDurations.count / 2]
        let p95 = queryDurations[Int(Double(queryDurations.count - 1) * 0.95)]
        XCTAssertLessThan(median, 0.050, "Median search exceeded 50 ms")
        XCTAssertLessThan(p95, 0.150, "p95 search exceeded 150 ms")
    }

    func testTenThousandItemListPreparationRemainsResponsive() {
        let items = (0..<10_000).map { index in
            StowItem(type: ItemType.allCases[index % ItemType.allCases.count], title: "Item \(index)", textContent: "Payload \(index)", createdAt: Date(timeIntervalSince1970: TimeInterval(index)))
        }
        let clock = ContinuousClock()
        let started = clock.now
        let visible = items.filter { $0.status == .inbox }.sorted { $0.createdAt > $1.createdAt }
        XCTAssertEqual(visible.count, 10_000)
        XCTAssertLessThan(started.duration(to: clock.now).seconds, 1)
    }

    @MainActor
    func testTenThousandItemQueryDoesNotEagerlyFetchRepresentations() throws {
        let container = try StowContainerFactory.inMemory()
        let repository = StowRepository(modelContext: container.mainContext)
        for index in 0..<10_000 {
            container.mainContext.insert(StowItem(
                type: .text,
                title: "Item \(index)",
                textContent: "Payload \(index)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(index))
            ))
        }
        try container.mainContext.save()

        XCTAssertEqual(try repository.allItems().count, 10_000)
        XCTAssertEqual(repository.representationFetchCount, 0)
        let firstID = try XCTUnwrap(repository.allItems().first?.id)
        _ = try repository.representations(itemID: firstID)
        XCTAssertEqual(repository.representationFetchCount, 1)
    }

    @MainActor
    func testCaptureCommitAndRapidDuplicateIngestionMeetReliabilityTargets() throws {
        let container = try StowContainerFactory.inMemory()
        let repository = StowRepository(modelContext: container.mainContext)
        let captureID = UUID()
        let draft = CaptureDraft(id: captureID, type: .text, title: "Rapid", textContent: "payload")
        let clock = ContinuousClock()
        let start = clock.now
        for _ in 0..<500 { _ = try repository.create(from: draft) }
        XCTAssertLessThan(start.duration(to: clock.now).seconds, 1, "Capture commit path exceeded one second")
        XCTAssertEqual(try repository.allItems().count, 1)
    }

    func testAttachmentLimitAcceptsBoundaryAndRejectsOneByteOverWithoutAllocatingPayload() throws {
        let limit = 100 * 1_024 * 1_024
        let boundary = CaptureDraft(type: .file, title: "Boundary", stagedAttachmentName: "boundary.bin", attachmentByteCount: limit)
        XCTAssertNoThrow(try boundary.normalized())
        let oversized = CaptureDraft(type: .file, title: "Oversized", stagedAttachmentName: "oversized.bin", attachmentByteCount: limit + 1)
        XCTAssertThrowsError(try oversized.normalized()) { error in
            XCTAssertEqual(error as? CaptureValidationError, .attachmentTooLarge)
        }
    }

    @MainActor
    func testLargePermittedAttachmentStagesWithoutPartialFailure() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("boundary.bin")
        FileManager.default.createFile(atPath: source.path, contents: nil)
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: UInt64(100 * 1_024 * 1_024))
        try handle.close()
        let spool = try CaptureSpool(rootURL: root.appendingPathComponent("spool", isDirectory: true))
        let draft = CaptureDraft(type: .file, title: "Boundary", stagedAttachmentName: "boundary.bin", attachmentByteCount: 100 * 1_024 * 1_024, contentType: "application/octet-stream", fileName: "boundary.bin")
        XCTAssertNoThrow(try spool.stage(draft, attachmentURL: source))
        XCTAssertEqual(try spool.pendingCount(), 1)
    }

    @MainActor
    func testThumbnailPathHasBoundedMemoryMetric() {
        let pixel = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
        measure(metrics: [XCTMemoryMetric()]) {
            for _ in 0..<1_000 { _ = AttachmentStore.imageInfo(pixel) }
        }
    }
}

private extension Duration {
    var seconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
