import Foundation

public typealias BridgeCompletion = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, Int) -> Void

@_cdecl("stow_bridge_abi_version")
public func stowBridgeABIVersion() -> UInt32 { 1 }

/// Copies input before returning. Completion runs asynchronously on the main actor.
@_cdecl("stow_bridge_submit")
public func stowBridgeSubmit(
    _ handle: UInt64, _ bytes: UnsafePointer<UInt8>?, _ length: Int,
    _ context: UnsafeMutableRawPointer?, _ completion: @escaping BridgeCompletion
) {
    let callback = Callback(context: context, completion: completion)
    guard length >= 0, length <= 16 * 1_024 * 1_024, let bytes, length > 0 else {
        callback.reject(.invalid)
        return
    }
    let data = Data(bytes: bytes, count: length)
    do { Registry.shared.submit(handle: handle, request: try BridgeRequest(data), callback: callback) }
    catch { callback.reject((error as? BridgeFailure) ?? .invalid) }
}

/// The caller must release each response once. Null is harmless; length is informational.
@_cdecl("stow_bridge_free")
public func stowBridgeFree(_ bytes: UnsafeMutablePointer<UInt8>?, _ length: Int) {
    bytes?.deallocate()
}

private struct Callback: @unchecked Sendable {
    let context: UnsafeMutableRawPointer?
    let completion: BridgeCompletion

    @MainActor func finish(_ response: BridgeJSON) {
        let encoder = JSONEncoder()
        var data = (try? encoder.encode(response)) ?? Data()
        if data.count > 64 * 1_024 * 1_024 || data.isEmpty {
            let failure = BridgeFailure(code: "response_too_large", message: "Bridge response exceeds its limit.", retryable: false)
            data = try! encoder.encode(failure.json)
        }
        let bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        data.copyBytes(to: bytes, count: data.count)
        completion(context, bytes, data.count)
    }
    func reject(_ failure: BridgeFailure) {
        Task { @MainActor in finish(failure.json) }
    }
}

private struct Job: Sendable {
    let request: BridgeRequest
    let callback: Callback
}

private final class Entry: @unchecked Sendable {
    // jobs/closing are guarded by Registry.lock. owner is main-actor isolated.
    var jobs: [Job] = []
    var running = false
    var closing = false
    @MainActor var owner: StoreOwner?
    @MainActor init(owner: StoreOwner) { self.owner = owner }
}

private final class Registry: @unchecked Sendable {
    static let shared = Registry()
    private let lock = NSLock()
    private var entries: [UInt64: Entry] = [:]
    private var nextHandle: UInt64 = 1

    func submit(handle: UInt64, request: BridgeRequest, callback: Callback) {
        if request.command == "open" {
            guard handle == 0 else { callback.reject(.handle); return }
            Task { @MainActor in
                do {
                    guard let path = request.payload["root"]?.string else { throw BridgeFailure.invalid }
                    let owner = try StoreOwner(path: path)
                    let handle = register(Entry(owner: owner))
                    callback.finish(.object(["ok": .object(["handle": .integer(Int64(handle))])]))
                } catch { callback.finish(((error as? BridgeFailure) ?? .storage).json) }
            }
            return
        }
        lock.lock()
        guard handle != 0, let entry = entries[handle], !entry.closing else {
            lock.unlock()
            callback.reject(.handle)
            return
        }
        if request.command == "close" { entry.closing = true }
        entry.jobs.append(Job(request: request, callback: callback))
        let start = !entry.running
        entry.running = true
        lock.unlock()
        if start { Task { @MainActor in await drain(handle, entry: entry) } }
    }

    private func register(_ entry: Entry) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        let handle = nextHandle
        nextHandle += 1
        entries[handle] = entry
        return handle
    }

    private func next(_ entry: Entry) -> Job? {
        lock.lock()
        defer { lock.unlock() }
        guard !entry.jobs.isEmpty else { entry.running = false; return nil }
        return entry.jobs.removeFirst()
    }

    private func remove(_ handle: UInt64) {
        lock.lock()
        entries.removeValue(forKey: handle)
        lock.unlock()
    }

    @MainActor private func drain(_ handle: UInt64, entry: Entry) async {
        while let job = next(entry) {
            if job.request.command == "close" {
                // Previous admitted callbacks have returned. Close completion signals teardown.
                entry.owner?.close()
                remove(handle)
                job.callback.finish(.object(["ok": .null]))
                // Retain the empty owner object until its final callback has returned.
                entry.owner = nil
                return
            }
            do {
                guard let owner = entry.owner else { throw BridgeFailure.handle }
                let value = try await owner.execute(job.request)
                job.callback.finish(.object(["ok": value]))
            } catch { job.callback.finish(((error as? BridgeFailure) ?? .storage).json) }
        }
    }
}
