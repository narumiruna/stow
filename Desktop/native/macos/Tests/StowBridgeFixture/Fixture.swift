import Darwin
import Foundation
import StowBridgeFixtureSupport
import StowCore
import StowDesktopBridge
import SwiftData

private final class FixtureReply: @unchecked Sendable {
    let continuation: CheckedContinuation<BridgeJSON, Never>
    init(_ continuation: CheckedContinuation<BridgeJSON, Never>) { self.continuation = continuation }
}

private let fixtureCompletion: BridgeCompletion = { context, bytes, length in
    let reply = Unmanaged<FixtureReply>.fromOpaque(context!).takeRetainedValue()
    let data = Data(bytes: bytes!, count: length)
    stowBridgeFree(bytes, length)
    let value = (try? JSONDecoder().decode(BridgeJSON.self, from: data)) ?? .null
    reply.continuation.resume(returning: value)
}

@main
struct StowBridgeFixture {
    @MainActor static func main() async {
        do {
            let args = CommandLine.arguments
            guard args.count == 3, ["seed", "inspect", "failed-save"].contains(args[1]) else { throw FixtureError.invalid }
            if args[1] == "failed-save" { try await failedSave(args[2]) }
            else {
                try withFixtureStore(args[2]) { container in
                    if args[1] == "seed" { try NativeFixture.seed(container) }
                    else { try NativeFixture.verify(container) }
                }
            }
            print("{\"ok\":true,\"items\":5}")
        } catch {
            // No paths, stored content, or native error descriptions in output.
            fputs("{\"error\":\"Native fixture verification failed.\"}\n", stderr)
            exit(1)
        }
    }

    @MainActor private static func invoke(_ handle: UInt64, _ command: String, _ payload: BridgeJSON) async -> BridgeJSON {
        let data = try! JSONEncoder().encode(BridgeJSON.object([
            "version": .integer(1), "command": .string(command), "payload": payload,
        ]))
        return await withCheckedContinuation { continuation in
            let context = Unmanaged.passRetained(FixtureReply(continuation)).toOpaque()
            data.withUnsafeBytes { buffer in
                stowBridgeSubmit(handle, buffer.bindMemory(to: UInt8.self).baseAddress, buffer.count, context, fixtureCompletion)
            }
        }
    }

    /// Run only in this disposable verification process, never in the test-suite process.
    @MainActor private static func failedSave(_ path: String) async throws {
        let opened = await invoke(0, "open", .object(["root": .string(path)]))
        guard case .integer(let number) = opened["ok"]?["handle"], number > 0 else { throw FixtureError.invalid }
        let handle = UInt64(number)
        let id = NativeFixture.id(1).uuidString.lowercased()
        let before = await invoke(handle, "get", .object(["id": .string(id)]))
        guard let revision = before["ok"]?["item"]?["updated_at"]?.string else { throw FixtureError.invalid }
        var saved = rlimit()
        guard getrlimit(RLIMIT_FSIZE, &saved) == 0 else { throw FixtureError.invalid }
        let handler = signal(SIGXFSZ, SIG_IGN)
        var blocked = saved
        blocked.rlim_cur = 0
        guard setrlimit(RLIMIT_FSIZE, &blocked) == 0 else {
            signal(SIGXFSZ, handler)
            throw FixtureError.invalid
        }
        let response = await invoke(handle, "update", .object([
            "id": .string(id), "expected_updated_at": .string(revision),
            "edit": .object(["title": .string("Must not persist"), "note": .string("Must not persist"),
                             "text_content": .string("Must not persist canonical content"),
                             "language": .string("rust")]),
        ]))
        let restored = setrlimit(RLIMIT_FSIZE, &saved)
        signal(SIGXFSZ, handler)
        guard restored == 0 else { throw FixtureError.invalid }
        let after = await invoke(handle, "get", .object(["id": .string(id)]))
        let closed = await invoke(handle, "close", .object([:]))
        guard response["error"]?["code"]?.string == "storage", before == after, closed["ok"] == .null else {
            throw FixtureError.invalid
        }
        // Reopen to prove that rollback also preserved the durable snapshot.
        let reopened = await invoke(0, "open", .object(["root": .string(path)]))
        guard case .integer(let reopenedNumber) = reopened["ok"]?["handle"] else { throw FixtureError.invalid }
        let durable = await invoke(UInt64(reopenedNumber), "get", .object(["id": .string(id)]))
        _ = await invoke(UInt64(reopenedNumber), "close", .object([:]))
        guard durable == before else { throw FixtureError.invalid }
    }

    /// Test executable only; production opens exclusively through the C ABI.
    @MainActor private static func withFixtureStore(_ path: String, body: (ModelContainer) throws -> Void) throws {
        let root = URL(fileURLWithPath: path, isDirectory: true)
        guard path.hasPrefix("/"), root.lastPathComponent == "dev.narumi.stow.desktop-preview",
              let canonical = realpath(root.deletingLastPathComponent().path, nil) else { throw FixtureError.invalid }
        defer { free(canonical) }
        guard root.deletingLastPathComponent().path == String(cString: canonical) else { throw FixtureError.invalid }
        if mkdir(path, 0o700) != 0 && errno != EEXIST { throw FixtureError.invalid }
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw FixtureError.invalid }
        // Verify all existing descendants before asking SwiftData to open the store.
        if let descendants = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let url as URL in descendants {
                guard lstat(url.path, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o022 == 0,
                      info.st_mode & S_IFMT == S_IFDIR || (info.st_mode & S_IFMT == S_IFREG && info.st_nlink == 1) else {
                    throw FixtureError.invalid
                }
            }
        }
        let lock = Darwin.open(root.appendingPathComponent("writer.lock").path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw FixtureError.invalid }
        defer { Darwin.close(lock) }
        guard fstat(lock, &info) == 0, info.st_nlink == 1, info.st_uid == getuid(), info.st_mode & 0o077 == 0,
              info.st_mode & S_IFMT == S_IFREG, flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw FixtureError.invalid }
        defer { flock(lock, LOCK_UN) }
        try body(StowContainerFactory.local(url: root.appendingPathComponent("Preview.store")))
    }
}
