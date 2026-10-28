# Local storage foundation

This crate stores local item snapshots and attachment bytes. It has no sync engine, UI, CLI, or access to the Apple store. It does not complete Phase 1 of the desktop plan.

## Platform limits

- `LocalRepository::open` rejects macOS. SwiftData remains the macOS canonical store.
- This implementation supports Unix filesystems with file locks, hard links, and durable directory synchronization. Linux tests use an isolated temporary directory.
- Windows open fails with `UnsupportedPlatform` before it creates or changes files. See the Windows blocker below. Private ACLs, reparse-point rejection, and durable directory publication are not implemented.
- Network filesystems and filesystems without these guarantees are not supported.
- Native Windows and macOS CI compiles this crate and verifies that opening storage creates no files and does not change an existing store. It does not enable or verify local persistence on these platforms.

### Windows durability blocker

Windows storage remains blocked. Do not remove the platform guard or treat a successful build as persistence support.

- The repository requires durable directory creation, attachment publication, and cleanup before it commits database references. SQLite also uses rollback-journal deletion with `synchronous=EXTRA`.
- [`MoveFileExW` with `MOVEFILE_WRITE_THROUGH`](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-movefileexw) is a candidate for non-replacing attachment publication after the staging file is flushed. It does not supply a general directory synchronization operation for directory creation and cleanup.
- [`FlushFileBuffers`](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-flushfilebuffers) requires a writable handle. [`CreateFileW`](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew) permits directory handles with `FILE_FLAG_BACKUP_SEMANTICS`, but this does not establish a supported, unprivileged directory-flush contract. Volume flushing requires administrator privileges. Storage must not request elevation to replace this missing guarantee.
- No verified Windows filesystem/API combination currently satisfies this crate's directory durability requirement. Ignoring a directory flush error, replacing synchronization with a no-op, or using an ordinary rename would weaken the requirement and is not permitted.

To unblock Windows, establish and test a supported durability protocol for directory creation, non-replacing publication, cleanup, and SQLite journal handling on the declared local filesystem. Then implement secure creation with a current-user owner and private ACL, reject broad ACLs and all reparse-point path components, and validate each opened file. Reject unsupported filesystems. Native tests must cover restart, process locking, unsafe ACLs, reparse points, corruption, and every persistent crash state. Current platform tests check only rejection without mutation; these storage tests are not claimed as passing.

## API and consistency

- The caller supplies an absolute application-data library path. `LocalRepository::open` requires its parent to exist. `open_desktop(root)` creates missing Linux preview parents with mode 0700 and rejects symlink ancestors. Both entry points preserve disabled-platform rejection before filesystem mutation. The crate never selects a temporary or production default path.
- `LocalRepository` implements `stow_core::Repository`. `open_desktop(root)` returns a boxed portable repository for the service factory. The adapter checks exact revisions under the exclusive writer owner before writes, preserves the existing SQLite clock behavior, removes embedded preview bytes from details, and returns attachment metadata without blob reads. It does not change schema, publication, recovery, or fingerprint namespaces.
- Item snapshots use the `stow-core` serde format. `upsert`, `get`, `list`, `delete`, and `rebuild_index` retain the original foundation API. Application capture and lifecycle commands are described below.
- Item snapshots and derived FTS5 documents change in one SQLite transaction. SQLite uses the rollback journal with `synchronous=EXTRA`.
- Numbered additive migrations commit the schema and `user_version` together. Newer schemas are rejected. There are no destructive migrations; any future destructive migration must first implement a durable backup.
- The index is rebuilt in one transaction on open. `search_items(&SearchQuery)` matches all literal token prefixes and supports type, case-insensitive source app, inclusive creation-date, and lifecycle filters. It excludes Trash by default. Empty or punctuation-only queries list matching items. Results use FTS rank when text has tokens, then descending creation date and ascending UUID. The result limit is clamped to 1–10,000; query text is limited to 4096 bytes.
- Search uses Unicode 17.0 width mappings for ASCII and Japanese forms, not arbitrary Unicode compatibility characters. Korean jamo forms remain distinct, as verified by native Foundation search. The derived table includes its Unicode license notice. Shared Swift/Rust fixtures cover the declared cases; they do not prove all ICU behavior. Source app is a metadata filter, not full-text content.
- The original `search(&str)` remains a literal phrase API with no metadata filters. It rejects empty input, control characters, and input above 4096 bytes. Do not use it as the application search contract.
- `list` returns UUID order. Search and index work must run off the UI thread.
- An exclusive file lock covers the entire repository lifetime, including recovery. Do not remove or replace `writer.lock`.

## Attachment publication

1. Generate a UUID storage name; never use an original filename as a path.
2. Create a private staging file on the library filesystem.
3. Stream at most 100 MiB plus one detection byte. Check declared size and SHA256. Sync the file, then verify its bytes again from disk.
4. Publish with an atomic, non-replacing hard link into `blobs`, then remove the staging link. Sync both directories.
5. Commit the attachment reference in SQLite only after publication is durable.

`attach` accepts a byte slice. `attach_reader` accepts a stream, expected byte count, and expected SHA256. `attachments(item_id)` returns `Vec<AttachmentInfo>` in stable attachment UUID order, or an empty list for an unknown item or an item without attachments. After reopen, callers can use only the item ID to discover attachment IDs and pass them to `read_attachment`. Reads are bounded and verify size and SHA256 before returning bytes. Attachment IDs are distinct from item IDs. `load_attachment(id)` returns the full metadata and verified bytes for captures written by the new command API. Legacy byte-only attachments retain `AttachmentInfo` and readable bytes but return no full metadata; no metadata is invented during migration.

## Capture and Lifecycle Commands

- Schema migration 3 adds capture receipts, attachment metadata, representations, and a fingerprint lookup index. It preserves existing snapshots and legacy attachment bytes. All changes are additive and transactional.
- `create` always creates a new item for a new capture ID, even when content matches. `ingest_clipboard` can coalesce matching live items. Matching Trash content creates a new Inbox item. Capture IDs are persisted for replay, including captures coalesced into another item.
- Coalescing updates capture activity and source app. It preserves edits, note, pin/archive state, use count, and canonical bytes. It does not publish duplicate attachments or representations. The fingerprint lookup decodes only the matching item, not the entire library.
- New captures use the isolated `local-1:v1:` fingerprint namespace. They do not match, import, or backfill existing macOS fingerprints. Foundation URL parity is not established.
- All capture payloads are validated before file publication. Item, attachment references, representations, receipt, and search index commit in one database transaction after blob publication. A failed transaction leaves only unreferenced files for recovery.
- `representations(item_id)` returns original metadata and verified bytes in ordinal order. UUID storage names are independent of original filenames and format identifiers.
- `apply` performs batch lifecycle commands atomically, with an explicit timestamp. Duplicate item IDs are applied once. A missing item or exhausted use count aborts the batch.
- `update` preserves original text whitespace. Changing canonical text or language deletes stale original representations and recalculates the local fingerprint. Metadata-only edits preserve them. Invalid text or an indexing failure leaves all previous data unchanged.
- `purge_expired_trash` uses an explicit clock and retention period. It removes owned attachment and representation references, capture receipts, and search metadata in one transaction. Orphan cleanup follows commit and is retried on open.
- Empty regular files are supported. Empty image payloads are rejected. Canonical text is limited to 1 MiB, URLs to 16 KiB, attachments to 100 MiB, and preserved representations to the existing per-type and 110 MiB aggregate limits.

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
