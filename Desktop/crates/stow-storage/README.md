# Local storage foundation

This crate stores local item snapshots and attachment bytes. It has no sync engine, UI, CLI, or access to the Apple store. It does not complete Phase 1 of the desktop plan.

## Platform limits

- `LocalRepository::open` rejects macOS. SwiftData remains the macOS canonical store.
- This implementation supports Unix filesystems with file locks, hard links, and durable directory synchronization. Linux tests use an isolated temporary directory.
- Windows open fails with `UnsupportedPlatform`. Private ACLs, reparse-point rejection, and durable directory publication must be implemented and tested before Windows storage can be enabled.
- Network filesystems and filesystems without these guarantees are not supported.
- Native Windows and macOS CI compiles this crate and verifies that opening storage fails before creating files. It does not enable or verify local persistence on these platforms.

## API and consistency

- The caller supplies an absolute application-data library path. Its parent must exist. The crate never selects a temporary or production default path.
- Item snapshots use the `stow-core` serde format. `upsert`, `get`, `list`, `delete`, `search`, and `rebuild_index` form a limited repository API. No domain transition or duplicate policy is implemented here.
- Item snapshots and derived FTS5 documents change in one SQLite transaction. SQLite uses the rollback journal with `synchronous=EXTRA`.
- Numbered additive migrations commit the schema and `user_version` together. Newer schemas are rejected. There are no destructive migrations; any future destructive migration must first implement a durable backup.
- The index is rebuilt in one transaction on open. Search uses a bound, escaped literal FTS phrase. It is not the complete Swift search contract. It has no wildcard, boolean, or query-language interface. Empty queries, control characters, and inputs above 4096 bytes are errors.
- `list` returns UUID order. Search returns FTS rank, then UUID order. Search and index work must run off the UI thread.
- An exclusive file lock covers the entire repository lifetime, including recovery. Do not remove or replace `writer.lock`.

## Attachment publication

1. Generate a UUID storage name; never use an original filename as a path.
2. Create a private staging file on the library filesystem.
3. Stream at most 100 MiB plus one detection byte. Check declared size and SHA256. Sync the file, then verify its bytes again from disk.
4. Publish with an atomic, non-replacing hard link into `blobs`, then remove the staging link. Sync both directories.
5. Commit the attachment reference in SQLite only after publication is durable.

`attach` accepts a byte slice. `attach_reader` accepts a stream, expected byte count, and expected SHA256. `attachments(item_id)` returns `Vec<AttachmentInfo>` in stable attachment UUID order, or an empty list for an unknown item or an item without attachments. After reopen, callers can use only the item ID to discover attachment IDs and pass them to `read_attachment`. Reads are bounded and verify size and SHA256 before returning bytes. Attachment IDs are distinct from item IDs. Original names, content types, thumbnails, and clipboard representations are not modeled by this limited API.

## Recovery

- Open runs `PRAGMA foreign_key_check` before recovery. Delete and attachment cleanup also check existing references. Dangling references return `Error::InvalidData` before cleanup removes any stages or blobs; enabling foreign keys alone does not validate existing data.
- Before a database reference commits, interruptions can leave a partial stage, a full stage, an unreferenced blob, or two links between staging and blobs. Open removes these after checking all committed references.
- After a reference commits, the blob is retained. Missing or corrupt committed blobs cause open to fail; they are not silently removed or replaced.
- `delete(id)` returns `Result<DeleteOutcome>`. It commits removal of item and attachment references before blob cleanup. `deleted` reports whether an item was removed. `cleanup_pending` reports whether cleanup failed after commit. A cleanup failure returns `Ok` with `cleanup_pending: true`, not an error. Errors before commit remain `Err` and do not commit the deletion.
    - Cleanup failure can leave an orphan. Another delete, including a retry for the now-absent item, or the next open retries cleanup. A corrupt unrelated committed blob blocks cleanup and open until repaired; cleanup does not remove that blob. A retry after a committed deletion reports `deleted: false`.
    - Outcome flags contain no content or internal cleanup error source. The crate does not log cleanup failures.
- A failed attachment write can leave a stage until the next open. No database reference is created for that stage.
- Unknown names, symlinks, unsafe file types, or unsafe permissions cause recovery to stop. Recovery does not follow them or delete arbitrary files.
- Tests simulate the persistent state at each publication boundary. They do not prove power-loss behavior for a particular filesystem or device.

## Security boundary

The library root and managed subdirectories must belong to the effective Unix user and have no group or other permission bits. Existing unsafe permissions are rejected, not silently repaired. Files are created with mode `0600`. Opens use `O_NOFOLLOW`; regular file checks reject extra hard links. Path components are checked for symlinks. Recovery permits two-link orphan publication states only for removal.

The parent path must be under caller control. Checks and the private root protect against other users under normal filesystem permission enforcement. They do not protect against a malicious process with the same user identity that can replace private directories between checks and operations. Root-descriptor-relative operations would be needed to strengthen that boundary. The crate does not log item content, search queries, or blob bytes. Error display text excludes this content; callers must not log internal error sources as content-free diagnostics.
