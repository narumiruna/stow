import Darwin
import Foundation
import StowCore
import SwiftData
import Testing
@testable import StowDesktopBridge

private final class Reply: @unchecked Sendable {
    let continuation: AsyncStream<BridgeJSON>.Continuation
    let didComplete: (@Sendable () -> Void)?
    init(_ continuation: AsyncStream<BridgeJSON>.Continuation, didComplete: (@Sendable () -> Void)? = nil) {
        self.continuation = continuation
        self.didComplete = didComplete
    }
}

private let complete: BridgeCompletion = { context, bytes, length in
    let reply = Unmanaged<Reply>.fromOpaque(context!).takeRetainedValue()
    let data = Data(bytes: bytes!, count: length)
    stowBridgeFree(bytes, length)
    reply.didComplete?()
    reply.continuation.yield(try! JSONDecoder().decode(BridgeJSON.self, from: data))
    reply.continuation.finish()
}

private final class CallbackEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [Int] = []
    func append(_ event: Int) { lock.lock(); events.append(event); lock.unlock() }
    var values: [Int] { lock.lock(); defer { lock.unlock() }; return events }
}

private func start(_ handle: UInt64, data: Data, didComplete: (@Sendable () -> Void)? = nil) -> AsyncStream<BridgeJSON> {
    AsyncStream { continuation in
        let context = Unmanaged.passRetained(Reply(continuation, didComplete: didComplete)).toOpaque()
        data.withUnsafeBytes { raw in
            stowBridgeSubmit(handle, raw.bindMemory(to: UInt8.self).baseAddress, raw.count, context, complete)
        }
    }
}
func request(_ command: String, _ payload: BridgeJSON = .object([:])) -> Data {
    try! JSONEncoder().encode(BridgeJSON.object(["version": .integer(1), "command": .string(command), "payload": payload]))
}
private func call(_ handle: UInt64, _ command: String, _ payload: BridgeJSON = .object([:])) async -> BridgeJSON {
    await first(start(handle, data: request(command, payload)))
}
private func first(_ stream: AsyncStream<BridgeJSON>) async -> BridgeJSON {
    var iterator = stream.makeAsyncIterator()
    return await iterator.next()!
}
private func code(_ value: BridgeJSON) -> String? { value["error"]?["code"]?.string }
private func createPayload(_ capture: UUID = UUID(), type: String = "text", text: String = " body\n") -> BridgeJSON {
    .object(["capture_id": .string(capture.uuidString), "item_type": .string(type), "title": .string(" Title "),
             "text_content": .string(text), "note": .null, "source_app": .string(" Test "), "language": .null])
}
func tempRoot() throws -> URL {
    // /var and /tmp can be symlinks on macOS. Canonicalize the trusted test parent.
    let resolved = try #require(realpath(FileManager.default.temporaryDirectory.path, nil))
    defer { free(resolved) }
    let parent = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
        .appendingPathComponent("stow-bridge-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false,
                                            attributes: [.posixPermissions: 0o700])
    return parent.appendingPathComponent(PreviewRoot.name, isDirectory: true)
}
private func open(_ root: URL) async throws -> UInt64 {
    let response = await call(0, "open", .object(["root": .string(root.path)]))
    guard case .integer(let h) = response["ok"]?["handle"] else {
        Issue.record("open failed: \(response)")
        throw BridgeFailure.storage
    }
    return UInt64(h)
}
func cleanup(_ root: URL) { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

@Suite(.serialized) @MainActor
struct BridgeTests {
    @Test func malformedABIAndBufferOwnership() async throws {
        #expect(stowBridgeABIVersion() == 1)
        stowBridgeFree(nil, 0)
        for data in [Data("secret-invalid-json".utf8), Data("[]".utf8), Data("{}".utf8),
                     Data("{\"version\":1,\"command\":\"close\",\"payload\":{\"secret\":1}}".utf8),
                     Data("{\"version\":1,\"command\":\"unknown\",\"payload\":{}}".utf8)] {
            let response = await first(start(0, data: data))
            #expect(code(response) == "invalid_argument")
            #expect(!String(decoding: try JSONEncoder().encode(response), as: UTF8.self).contains("secret"))
        }
        let version = Data("{\"version\":2,\"command\":\"close\",\"payload\":{}}".utf8)
        #expect(code(await first(start(0, data: version))) == "unsupported_version")
        #expect(code(await call(7, "close")) == "invalid_handle")
        for length in [-1, 0, 16 * 1_024 * 1_024 + 1] {
            let stream = AsyncStream<BridgeJSON> { continuation in
                let context = Unmanaged.passRetained(Reply(continuation)).toOpaque()
                stowBridgeSubmit(0, nil, length, context, complete)
            }
            #expect(code(await first(stream)) == "invalid_argument")
        }
        // The request allocation can change immediately after submit returns.
        var data = request("close")
        let stream = AsyncStream<BridgeJSON> { continuation in
            let context = Unmanaged.passRetained(Reply(continuation)).toOpaque()
            data.withUnsafeBytes { b in stowBridgeSubmit(99, b.bindMemory(to: UInt8.self).baseAddress, b.count, context, complete) }
        }
        data.resetBytes(in: data.indices)
        #expect(code(await first(stream)) == "invalid_handle")
    }

    @Test func createReplayReopenAndRejectedRequests() async throws {
        let root = try tempRoot(); defer { cleanup(root) }
        let handle = try await open(root)
        let capture = UUID()
        let created = await call(handle, "create", createPayload(capture))
        let item = try #require(created["ok"]?["item"])
        let id = try #require(item["id"]?.string)
        #expect(item["title"] == .string("Title"))
        #expect(item["text_content"] == .string(" body\n"))
        #expect(item["favicon_data"] == .null)
        #expect(created["ok"]?["capture_replayed"] == .bool(false))
        #expect((await call(handle, "create", createPayload(capture)))["ok"]?["capture_replayed"] == .bool(true))
        #expect(code(await call(handle, "create", createPayload(text: " \n"))) == "invalid_argument")
        #expect(code(await call(handle, "create", createPayload(type: "image"))) == "unsupported")
        #expect(code(await call(handle, "search", .object(["limit": .integer(0)]))) == "invalid_argument")
        #expect(code(await call(handle, "update", .object(["id": .string(id), "expected_updated_at": .string("2001-01-01T00:00:00.000000000Z"),
                                                          "edit": .object(["title": .string("changed")]) ]))) == "conflict")
        let results = await call(handle, "search", .object(["text": .string("body")]))
        guard case .array(let rows) = results["ok"] else { Issue.record("search failed"); return }
        #expect(rows.count == 1)
        #expect((await call(handle, "close"))["ok"] == .null)
        #expect(code(await call(handle, "get", .object(["id": .string(id)]))) == "invalid_handle")
        let reopened = try await open(root)
        #expect((await call(reopened, "get", .object(["id": .string(id)])))["ok"]?["item"] == item)
        #expect((await call(reopened, "rebuild"))["ok"] == .null)
        _ = await call(reopened, "close")
    }

    @Test func exactNativeDateRevisionsAndLifecycle() async throws {
        let root = try tempRoot(); defer { cleanup(root) }
        let owner = try StoreOwner(path: root.path)
        let date = Date(timeIntervalSinceReferenceDate: 800_000_000.1234567)
        let item = try owner.repository.create(from: CaptureDraft(type: .text, title: "native", textContent: "body"), at: date)
        let revision = BridgeDate.string(date)
        #expect(revision.hasSuffix(".123456717Z"))
        let nanosecondDifferent = String(revision.dropLast(10)) + "123456718Z"
        func apply(_ action: String, revision: String) throws -> BridgeRequest {
            try BridgeRequest(request("apply", .object(["id": .string(item.id.uuidString),
                                                        "expected_updated_at": .string(revision), "command": .string(action)])))
        }
        do { _ = try await owner.execute(apply("pin", revision: nanosecondDifferent)); Issue.record("accepted 1ns conflict") }
        catch { #expect((error as? BridgeFailure)?.code == "conflict") }
        #expect(!item.isPinned)
        #expect(item.updatedAt == date)
        #expect(BridgeDate.next(after: date, now: date).timeIntervalSinceReferenceDate == date.timeIntervalSinceReferenceDate.nextUp)
        for action in ["pin", "unpin", "archive", "trash", "restore_trash", "restore_archive"] {
            let previous = item.updatedAt
            _ = try await owner.execute(apply(action, revision: BridgeDate.string(previous)))
            #expect(item.updatedAt > previous)
        }
        #expect(item.status == .inbox)
        #expect(item.trashedAt == nil)
        #expect(item.statusBeforeTrash == nil)
    }

    @Test func indexFailureDoesNotFailCommittedMutationAndPinBeforeLimit() async throws {
        let root = try tempRoot(); defer { cleanup(root) }
        let owner = try StoreOwner(path: root.path)
        owner.makeIndex = { _ in throw BridgeFailure.index }
        let created = try await owner.execute(BridgeRequest(request("create", createPayload())))
        #expect(created["item"] != nil)
        for command in ["search", "rebuild"] {
            do { _ = try await owner.execute(BridgeRequest(request(command))); Issue.record("index failure hidden") }
            catch { #expect((error as? BridgeFailure)?.code == "index") }
        }
        #expect(try owner.repository.allItems().count == 1)
        owner.makeIndex = { try SQLiteSearchIndex(url: $0) }
        _ = try owner.repository.create(from: CaptureDraft(type: .text, title: "pinned", textContent: "body", isPinned: true),
                                        at: Date(timeIntervalSince1970: 10))
        for _ in 0..<3 { _ = try owner.repository.create(from: CaptureDraft(type: .text, title: "newer", textContent: "body")) }
        let results = try await owner.execute(BridgeRequest(request("search", .object(["pinned_only": .bool(true), "limit": .integer(1)]))))
        guard case .array(let rows) = results else { Issue.record("search shape"); return }
        #expect(rows.count == 1)
        #expect(rows.first?["title"] == .string("pinned"))
    }

    @Test func closeDrainsAcceptedWorkAndRejectsLateAdmission() async throws {
        let root = try tempRoot(); defer { cleanup(root) }
        let handle = try await open(root)
        _ = await call(handle, "create", createPayload())
        let events = CallbackEvents()
        let searches = (0..<20).map { index in
            start(handle, data: request("search"), didComplete: { events.append(index) })
        }
        let reopen = AsyncStream<BridgeJSON>.makeStream()
        let reopenData = request("open", .object(["root": .string(root.path)]))
        let close = start(handle, data: request("close"), didComplete: {
            events.append(20)
            // Close completion guarantees teardown; even a direct lock open must succeed.
            if (try? PreviewRoot(path: root.path)) != nil { events.append(21) }
            let context = Unmanaged.passRetained(Reply(reopen.continuation)).toOpaque()
            reopenData.withUnsafeBytes { buffer in
                stowBridgeSubmit(0, buffer.bindMemory(to: UInt8.self).baseAddress, buffer.count, context, complete)
            }
        })
        let late = start(handle, data: request("search"))
        #expect(code(await first(late)) == "invalid_handle")
        for search in searches { #expect((await first(search))["ok"] != nil) }
        #expect((await first(close))["ok"] == .null)
        #expect(events.values == Array(0...21))
        #expect(code(await call(handle, "close")) == "invalid_handle")
        let reopened = await first(reopen.stream)
        guard case .integer(let number) = reopened["ok"]?["handle"] else { Issue.record("immediate reopen failed"); return }
        _ = await call(UInt64(number), "close")
    }

    @Test func privatePathLockAndSentinelSafety() async throws {
        let root = try tempRoot(); defer { cleanup(root) }
        let parent = root.deletingLastPathComponent()
        let sentinel = parent.appendingPathComponent("production-sentinel")
        try Data("do not touch".utf8).write(to: sentinel)
        #expect(code(await call(0, "open", .object(["root": .string(parent.path)]))) == "storage")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])
        #expect(code(await call(0, "open", .object(["root": .string(root.path)]))) == "storage")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let unrelated = root.appendingPathComponent("production-sentinel")
        try Data("unrelated".utf8).write(to: unrelated)
        #expect(code(await call(0, "open", .object(["root": .string(root.path)]))) == "storage")
        #expect(try Data(contentsOf: unrelated) == Data("unrelated".utf8))
        try FileManager.default.removeItem(at: unrelated)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("writer.lock"), withDestinationURL: sentinel)
        #expect(code(await call(0, "open", .object(["root": .string(root.path)]))) == "storage")
        try FileManager.default.removeItem(at: root.appendingPathComponent("writer.lock"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(PreviewRoot.storeName), withDestinationURL: sentinel)
        #expect(code(await call(0, "open", .object(["root": .string(root.path)]))) == "storage")
        try FileManager.default.removeItem(at: root.appendingPathComponent(PreviewRoot.storeName))
        #expect(link(sentinel.path, root.appendingPathComponent("writer.lock").path) == 0)
        #expect(code(await call(0, "open", .object(["root": .string(root.path)]))) == "storage")
        try FileManager.default.removeItem(at: root.appendingPathComponent("writer.lock"))
        let handle = try await open(root)
        #expect(code(await call(0, "open", .object(["root": .string(root.path)]))) == "storage")
        _ = await call(handle, "close")
        let alias = parent.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: parent)
        #expect(code(await call(0, "open", .object(["root": .string(alias.appendingPathComponent(PreviewRoot.name).path)]))) == "storage")
        let second = parent.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: second.appendingPathComponent(PreviewRoot.name), withDestinationURL: root)
        #expect(code(await call(0, "open", .object(["root": .string(second.appendingPathComponent(PreviewRoot.name).path)]))) == "storage")
        #expect(try Data(contentsOf: sentinel) == Data("do not touch".utf8))
    }
}
