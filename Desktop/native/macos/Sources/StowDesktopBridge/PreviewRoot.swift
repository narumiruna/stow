import Darwin
import Foundation

/// Own the directory and the exclusive writer lock for the complete owner lifetime.
final class PreviewRoot {
    static let name = "dev.narumi.stow.desktop-preview"
    static let storeName = "Preview.store"
    let url: URL
    private let directory: Int32
    private let lock: Int32

    init(path: String) throws {
        guard path.hasPrefix("/"), !path.utf8.contains(0),
              path.split(separator: "/").last == Substring(Self.name),
              !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }),
              !path.hasSuffix("/") else { throw BridgeFailure.storage }
        var parent = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard parent >= 0 else { throw BridgeFailure.storage }
        defer { Darwin.close(parent) }
        for component in path.split(separator: "/").dropLast() {
            let child = openat(parent, String(component), O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            guard child >= 0 else { throw BridgeFailure.storage }
            var ancestor = stat()
            guard fstat(child, &ancestor) == 0,
                  ancestor.st_uid == 0 || ancestor.st_uid == getuid(),
                  ancestor.st_mode & 0o022 == 0 || (ancestor.st_uid == 0 && ancestor.st_mode & S_ISVTX != 0) else {
                Darwin.close(child)
                throw BridgeFailure.storage
            }
            Darwin.close(parent)
            parent = child
        }
        if mkdirat(parent, Self.name, 0o700) != 0 && errno != EEXIST { throw BridgeFailure.storage }
        let directory = openat(parent, Self.name, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard directory >= 0 else { throw BridgeFailure.storage }
        var info = stat()
        guard fstat(directory, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else {
            Darwin.close(directory)
            throw BridgeFailure.storage
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        do {
            let allowed: Set<String> = [
                "writer.lock", Self.storeName, Self.storeName + "-shm", Self.storeName + "-wal", ".Preview_SUPPORT",
                "Search.sqlite", "Search.sqlite-shm", "Search.sqlite-wal",
                "PinnedSearch.sqlite", "PinnedSearch.sqlite-shm", "PinnedSearch.sqlite-wal",
            ]
            for entry in try FileManager.default.contentsOfDirectory(atPath: path) {
                guard allowed.contains(entry) else { throw BridgeFailure.storage }
            }
            try Self.validateTree(url)
        } catch { Darwin.close(directory); throw error }
        let lock = openat(directory, "writer.lock", O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard lock >= 0 else { Darwin.close(directory); throw BridgeFailure.storage }
        guard fstat(lock, &info) == 0, info.st_uid == getuid(), info.st_nlink == 1,
              info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o077 == 0,
              flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(lock)
            Darwin.close(directory)
            throw BridgeFailure.storage
        }
        self.directory = directory
        self.lock = lock
        self.url = url
    }

    func requireExistingStore() throws {
        var held = stat()
        var current = stat()
        guard fstat(directory, &held) == 0, lstat(url.path, &current) == 0,
              current.st_mode & S_IFMT == S_IFDIR, current.st_uid == getuid(), current.st_mode & 0o077 == 0,
              held.st_dev == current.st_dev, held.st_ino == current.st_ino else { throw BridgeFailure.storage }
        var info = stat()
        guard fstatat(directory, Self.storeName, &info, AT_SYMLINK_NOFOLLOW) == 0,
              info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(), info.st_nlink == 1,
              info.st_mode & 0o022 == 0, info.st_size > 0 else { throw BridgeFailure.storage }
        try Self.validateTree(url)
    }

    /// Reject symlinks, shared files, special nodes and foreign ownership before SwiftData opens.
    private static func validateTree(_ root: URL) throws {
        for child in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            var info = stat()
            guard lstat(child.path, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o022 == 0 else {
                throw BridgeFailure.storage
            }
            switch info.st_mode & S_IFMT {
            case S_IFDIR: try validateTree(child)
            case S_IFREG: guard info.st_nlink == 1 else { throw BridgeFailure.storage }
            default: throw BridgeFailure.storage
            }
        }
    }

    deinit {
        flock(lock, LOCK_UN)
        Darwin.close(lock)
        Darwin.close(directory)
    }
}
