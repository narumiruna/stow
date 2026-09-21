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
        let model = AppModel(captureSpool: spool, runtimePaths: StowRuntimePaths(
            sharedContainer: root, temporaryDirectory: root.appendingPathComponent("Temporary")
        ))
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

final class BoundedHTTPResponseLoaderTests: XCTestCase {
    private let limit = 8

    override func setUp() {
        super.setUp()
        BoundedHTTPURLProtocol.reset()
    }

    override func tearDown() {
        BoundedHTTPURLProtocol.reset()
        super.tearDown()
    }

    func testExactBoundarySucceedsAndOneByteOverCancels() async throws {
        BoundedHTTPURLProtocol.setScenario(.response(
            status: 200,
            headers: ["Content-Type": "text/html"],
            chunks: [Data(repeating: 65, count: limit)]
        ), for: "/exact")
        BoundedHTTPURLProtocol.setScenario(.response(
            status: 200,
            headers: ["Content-Type": "text/html"],
            chunks: [Data(repeating: 65, count: limit + 1)]
        ), for: "/over")
        let loader = makeLoader()

        let exact = try await loader.load(
            URLRequest(url: url("/exact")),
            byteLimit: limit,
            timeoutInterval: 1,
            contentKind: .html
        )
        XCTAssertEqual(exact.data.count, limit)

        await XCTAssertThrowsErrorAsync(try await loader.load(
            URLRequest(url: url("/over")),
            byteLimit: limit,
            timeoutInterval: 1,
            contentKind: .html
        )) { error in
            XCTAssertEqual(error as? BoundedHTTPResponseError, .responseTooLarge(limit: self.limit))
        }
    }

    func testMisleadingContentLengthStillEnforcesStreamedLimit() async {
        BoundedHTTPURLProtocol.setScenario(.response(
            status: 200,
            headers: ["Content-Type": "text/html", "Content-Length": "1"],
            chunks: [Data(repeating: 65, count: limit + 1)]
        ), for: "/misleading-length")

        await XCTAssertThrowsErrorAsync(try await makeLoader().load(
            URLRequest(url: url("/misleading-length")),
            byteLimit: limit,
            timeoutInterval: 1,
            contentKind: .html
        )) { error in
            XCTAssertEqual(error as? BoundedHTTPResponseError, .responseTooLarge(limit: self.limit))
        }
    }

    func testChunkedOversizedResponseIsRejected() async {
        BoundedHTTPURLProtocol.setScenario(.response(
            status: 200,
            headers: ["Content-Type": "text/html"],
            chunks: [Data(repeating: 65, count: 4), Data(repeating: 66, count: 5)]
        ), for: "/chunked")

        await XCTAssertThrowsErrorAsync(try await makeLoader().load(
            URLRequest(url: url("/chunked")),
            byteLimit: limit,
            timeoutInterval: 1,
            contentKind: .html
        )) { error in
            XCTAssertEqual(error as? BoundedHTTPResponseError, .responseTooLarge(limit: self.limit))
        }
    }

    func testTimeoutAndNonSuccessStatusAreRejected() async {
        BoundedHTTPURLProtocol.setScenario(.timeout, for: "/timeout")
        BoundedHTTPURLProtocol.setScenario(.response(
            status: 503,
            headers: ["Content-Type": "text/html"],
            chunks: []
        ), for: "/status")
        let loader = makeLoader()

        await XCTAssertThrowsErrorAsync(try await loader.load(
            URLRequest(url: url("/timeout")),
            byteLimit: limit,
            timeoutInterval: 0.05,
            contentKind: .html
        )) { error in
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
        XCTAssertEqual(BoundedHTTPURLProtocol.timeoutInterval(for: "/timeout"), 0.05, accuracy: 0.001)

        await XCTAssertThrowsErrorAsync(try await loader.load(
            URLRequest(url: url("/status")),
            byteLimit: limit,
            timeoutInterval: 1,
            contentKind: .html
        )) { error in
            XCTAssertEqual(error as? BoundedHTTPResponseError, .unacceptableStatus(503))
        }
    }

    func testTaskCancellationCancelsLoading() async throws {
        BoundedHTTPURLProtocol.setScenario(.pending, for: "/pending")
        let loader = makeLoader()
        let request = URLRequest(url: url("/pending"))
        let byteLimit = limit
        let task = Task {
            try await loader.load(
                request,
                byteLimit: byteLimit,
                timeoutInterval: 10,
                contentKind: .html
            )
        }

        try await Task.sleep(for: .milliseconds(30))
        task.cancel()
        await XCTAssertThrowsErrorAsync(try await task.value) { error in
            XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled)
        }
    }

    func testContentTypeValidationAllowsMissingHeaderFallback() async throws {
        BoundedHTTPURLProtocol.setScenario(.response(
            status: 200,
            headers: ["Content-Type": "text/plain"],
            chunks: [Data("hello".utf8)]
        ), for: "/wrong-type")
        BoundedHTTPURLProtocol.setScenario(
            .responseWithoutContentType(Data("hello".utf8)),
            for: "/missing-type"
        )
        let loader = makeLoader()

        await XCTAssertThrowsErrorAsync(try await loader.load(
            URLRequest(url: url("/wrong-type")),
            byteLimit: limit,
            timeoutInterval: 1,
            contentKind: .html
        )) { error in
            XCTAssertEqual(error as? BoundedHTTPResponseError, .unsupportedContentType("text/plain"))
        }
        let result = try await loader.load(
            URLRequest(url: url("/missing-type")),
            byteLimit: limit,
            timeoutInterval: 1,
            contentKind: .html
        )
        XCTAssertEqual(String(decoding: result.data, as: UTF8.self), "hello")
    }

    @MainActor
    func testEnricherUsesInjectedLoaderForPageAndImages() async throws {
        let pageURL = try XCTUnwrap(URL(string: "https://example.com/article"))
        let html = """
        <html><head>
        <title>Bounded title</title>
        <meta name="description" content="Bounded description">
        <link rel="icon" href="/icon.png">
        <meta property="og:image" content="/preview.png">
        </head></html>
        """
        let iconData = Data([1, 2, 3])
        let previewData = Data([4, 5, 6])
        let enricher = LinkMetadataEnricher { request, _, _, _ in
            let url = try XCTUnwrap(request.url)
            let data: Data
            let mimeType: String
            switch url.path {
            case "/article":
                data = Data(html.utf8)
                mimeType = "text/html"
            case "/icon.png":
                data = iconData
                mimeType = "image/png"
            case "/preview.png":
                data = previewData
                mimeType = "image/png"
            default:
                throw URLError(.badURL)
            }
            let response = try XCTUnwrap(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": mimeType]
            ))
            return BoundedHTTPResponse(data: data, response: response)
        }
        let container = try StowContainerFactory.inMemory()
        let repository = StowRepository(modelContext: container.mainContext)
        let item = try repository.create(from: CaptureDraft(
            type: .link,
            title: "example.com",
            urlString: pageURL.absoluteString
        ))

        await enricher.enrich(item: item, repository: repository)

        let updated = try XCTUnwrap(repository.item(id: item.id))
        XCTAssertEqual(updated.title, "Bounded title")
        XCTAssertEqual(updated.linkDescription, "Bounded description")
        XCTAssertEqual(updated.faviconData, iconData)
        XCTAssertEqual(updated.linkPreviewImageData, previewData)
    }

    private func makeLoader() -> BoundedHTTPResponseLoader {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BoundedHTTPURLProtocol.self]
        return BoundedHTTPResponseLoader(session: URLSession(configuration: configuration))
    }

    private func url(_ path: String) -> URL {
        URL(string: "https://bounded.test\(path)")!
    }
}

private final class BoundedHTTPURLProtocol: URLProtocol, @unchecked Sendable {
    enum Scenario: Sendable {
        case response(status: Int, headers: [String: String], chunks: [Data])
        case responseWithoutContentType(Data)
        case timeout
        case pending
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var scenarios: [String: Scenario] = [:]
    nonisolated(unsafe) private static var timeoutIntervals: [String: TimeInterval] = [:]

    private let stateLock = NSLock()
    private var stopped = false

    static func reset() {
        lock.withLock {
            scenarios = [:]
            timeoutIntervals = [:]
        }
    }

    static func setScenario(_ scenario: Scenario, for path: String) {
        lock.withLock { scenarios[path] = scenario }
    }

    static func timeoutInterval(for path: String) -> TimeInterval {
        lock.withLock { timeoutIntervals[path] ?? 0 }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let scenario = Self.lock.withLock { () -> Scenario? in
            Self.timeoutIntervals[path] = request.timeoutInterval
            return Self.scenarios[path]
        }
        guard let scenario else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }

        switch scenario {
        case .response(let status, let headers, let chunks):
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: status,
                    httpVersion: nil,
                    headerFields: headers
                  ) else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for chunk in chunks where !isStopped {
                client?.urlProtocol(self, didLoad: chunk)
            }
            if !isStopped { client?.urlProtocolDidFinishLoading(self) }
        case .responseWithoutContentType(let data):
            guard let url = request.url else { return }
            let response = URLResponse(
                url: url,
                mimeType: nil,
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .timeout:
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
        case .pending:
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "text/html"]
                  ) else { return }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data([65]))
        }
    }

    override func stopLoading() {
        stateLock.withLock { stopped = true }
    }

    private var isStopped: Bool {
        stateLock.withLock { stopped }
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
