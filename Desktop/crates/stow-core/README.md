# stow-core

Portable domain foundation for the desktop rewrite. This crate does not access a desktop, database, clipboard, network, or Apple API.

## Public API

- `Item`, `ItemType`, and `ItemStatus` preserve all `StowSchemaV2.StowItem` fields.
  - `Item::new` sets the capture ID to the item ID.
  - `Item::from_draft` preserves the draft capture ID and applies pin/archive flags. Normalize the draft first.
  - Lifecycle methods take an explicit UTC timestamp. Archive on an already archived item updates its timestamp, as in Swift. Archive on Trash does nothing.
  - `record_successful_use` returns an error without mutation on signed 64-bit overflow.
  - `should_purge` takes an explicit retention period in days; use `30` for the current policy. An unrepresentable deadline does not purge.
- `Attachment` and `Representation` preserve all original fields, including stored byte counts, dimensions, thumbnails, UUIDs, and ordinals. DTO deserialization does not repair or normalize existing records.
- `CaptureDraft::normalized` trims metadata, validates content, and generates text titles using at most 80 extended grapheme clusters. It preserves the original text payload.
  - The attachment limit is 100 MiB. Negative declared byte counts are rejected as a safety extension to the Swift rule.
  - This method does not read or validate a staged file. Storage must validate the real bytes and staging path.
  - As in Swift, text and rich-format byte limits belong to representation validation, not draft title normalization.
- `validate_representations` applies the Swift auxiliary or captured allowlist, per-format byte limits, the 110 MiB total limit, and distinct nonnegative ordinals. It does not sort. Native format mapping belongs to platform code.
- `clipboard_fingerprint` and `item_fingerprint` use the Swift v1 length-prefixed SHA-256 stream. Text uses NFC and LF line endings. Auxiliary representation order remains significant.
- `sort_by_activity` uses descending capture/use/creation activity and ascending UUID for ties.
- `Repository` defines the shared desktop search, get, create, update, lifecycle, and rebuild operations. Each method uses a mutable backend owner. Revision comparison and mutation must be one owner operation. The service factory creates the backend on its worker, so the trait does not require `Send`.
- Service DTOs, `ServiceError`, and `ServiceResult` define the portable result contract. `SearchQuery`, `ItemEdit`, and `ItemCommand` are also portable; `stow-storage` retains public reexports.
- `CreateRequest::normalized_draft` validates the explicit text/code/link slice, including nonempty text and the existing ASCII URL restriction. Service request byte limits remain enforced before dispatch.

DTO serialization uses lowercase enum strings, snake_case fields, RFC 3339 UTC timestamps, JSON byte arrays, and explicit null values. This is not the Swift Codable format or an approved bridge wire protocol.

## Verification limits

`tests/backend_fixture.rs` consumes version 1 of `Desktop/fixtures/backend.json`. It checks complete scalar/null snapshots, declared Rust normalization results, exact nanosecond revisions, error fields, and lifecycle actions. Explicit-create replay is checked by the service backend tests, not claimed from this fixture.

`tests/domain.rs` ports fixtures from Swift `CaptureDraftTests`, `ItemLifecycleTests`, `StowRepresentationTests`, and `ClipboardContentFingerprintTests`, including the fixed text hash. Tests execute in Rust only. They do not establish cross-language runtime compatibility.

URL validation uses the Rust `url` parser and a restricted ASCII spelling check. Raw spaces, non-ASCII characters, backslashes, invalid percent escapes, and repaired empty authorities are rejected instead of producing known incompatible fingerprints. Percent-encoded URLs can be supplied. This is a temporary input restriction, not complete Swift URL parity. The trimmed original URL spelling is retained so that default ports and an absent trailing slash are not silently changed in fingerprint inputs. Foundation percent encoding, Unicode host handling, host case in generated titles, and other parser edge cases still need shared fixtures executed in Swift and Rust. Do not reuse existing library fingerprints based on these tests alone.

The DTOs and rules are partial Phase 1 work. They do not satisfy the native UI, signed macOS bridge, CloudKit, or three-OS release gates. There is no synchronization implementation or repository implementation in this crate.
