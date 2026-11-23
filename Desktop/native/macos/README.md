# macOS preview bridge

`StowDesktopBridge` is a static Swift library for the isolated desktop preview store. It uses the existing `Packages/StowCore` package. It does not connect an application model, CloudKit, clipboard capture, or production storage.

## Build and test

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Desktop/native/macos
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --package-path Desktop/native/macos -c release
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build --package-path Desktop/native/macos -c release --show-bin-path
```

The output directory contains `libStowDesktopBridge.a`. The archive includes the required `StowCore` objects. The C header is `include/stow_bridge.h`. Link the archive with the Swift runtime, Foundation, SwiftData, CoreData, CoreGraphics, ImageIO, UniformTypeIdentifiers, CryptoKit, Security, and SQLite (`sqlite3`). Use the selected Xcode toolchain to resolve the Swift runtime libraries. `StowBridgeFixture` is a separate verification executable. Its code is not in the static library.

## ABI v1

- `stow_bridge_submit` copies the request before it returns.
  - Input is UTF-8 JSON, with a maximum size of 16 MiB.
  - The caller must supply valid pointers and keep the callback context valid until its callback returns.
- Each submission completes once, asynchronously on the main actor.
  - The host must service the main run loop. It must not block the main actor while it waits for Rust work that uses the bridge.
  - The callback receives one allocated JSON buffer, without a NUL suffix. The caller must release it exactly once with `stow_bridge_free`, including error responses. A null free is harmless.
  - Responses have a maximum size of 64 MiB. Oversized output returns a content-free error.
- Requests use `{"version":1,"command":"...","payload":{...}}`.
  - `open` requires handle zero and payload `{"root":"/absolute/path/dev.narumi.stow.desktop-preview"}`. It returns `{"ok":{"handle":1}}`, with a new numeric registry handle.
  - `get` uses `{"id":"UUID"}`. `search`, `create`, `update`, and `apply` use the shared desktop service DTO fields. `rebuild` and `close` use `{}`.
  - Other commands require a valid nonzero handle. Handles are never object pointers.
  - Unknown fields, unsupported versions, malformed shapes, and unsupported create types are rejected.
- Successful responses use `{"ok":payload}`. `rebuild` and `close` return null payloads.
  - Errors use `{"error":{"code":"...","message":"...","retryable":false}}`.
  - Error messages do not include requests, paths, stored content, or native error descriptions.
  - `status` and capability reporting belong to the Rust service, not the C ABI.
- Operations on each handle execute in admission order.
  - `close` stops admission synchronously, then drains accepted work and callbacks.
  - After earlier callbacks return, the bridge releases its indexes, repository, context, container, and writer lock, then calls the close callback. Close completion guarantees teardown. The empty owner object remains alive until that callback returns.
  - Late requests return `invalid_handle`. The caller must still consume their callbacks.

## Storage rules

- The host chooses the root. Its final component must be `dev.narumi.stow.desktop-preview`.
  - All path components must be directories, without symlinks. Ancestors must belong to root or the current user and must not permit shared writes, except root-owned sticky directories.
  - The root must belong to the current user, with no group or other permissions. A new root uses mode `0700`.
  - Existing roots may contain only the bridge store, its SwiftData support directory, the derived indexes, their sidecars, and `writer.lock`. Symlinks, hard-linked files, special files, foreign ownership, and shared writable entries are rejected.
  - `writer.lock` is opened without following symlinks and held with an exclusive, nonblocking `flock`. The bridge never unlinks it.
- Canonical data uses `StowContainerFactory.local(url:)` and the stable `Preview.store` filename. The bridge does not read or write raw backing-store bytes or change the schema.
- Explicit create supports text, code, and the shared ASCII HTTP/HTTPS URL subset. The Rust adapter applies portable draft defaults before native validation, so native host-case handling does not change generated titles. Validation runs before mutation. This does not establish complete Foundation/Rust URL equivalence. Explicit capture IDs replay while their items exist. Clipboard coalescing and persistent replay receipts are not exposed.
- A storage failure discards the failed repository, context, container, and derived-index owners, while it retains the writer lock. The next non-close command requires the same existing, safe regular store and reopens it. Recovery does not retry the failed mutation or create an empty replacement. Native rollback alone can retain partially changed registered objects after a failed save; the bridge does not reuse those objects.
- Metadata edits use the existing repository behavior. They preserve unrelated scalar fields, attachment bytes, representation bytes, and native fingerprints. Canonical text or language changes retain the existing native representation invalidation and fingerprint behavior.
- Dates use fixed-nine-digit UTC RFC3339 strings. The bridge splits `timeIntervalSinceReferenceDate` into integer and fractional parts before it adds the integer Unix epoch offset.
  - Rust must normalize `expected_updated_at` to fixed-nine-digit UTC form before submission.
  - Revision checks compare the emitted string exactly. They do not convert the supplied revision back to a rounded `Date`.
  - Compare, mutation, and save execute synchronously on the main actor. A same-tick revision advances with `nextUp`.
- Get responses contain complete scalar item snapshots, attachment metadata, representation counts, and the replay flag. Icon, preview, attachment, and representation bytes are not embedded. UUID strings are lowercase, enums use lowercase or snake_case names, and optional fields include explicit JSON nulls.
- Search indexes are disposable. A canonical save marks them dirty. Search and explicit rebuild report observable index errors. A derived-index failure does not turn a committed mutation into a failed mutation response.
  - A separate pinned index applies the pin filter before the search limit.
  - Exact integer seconds/nanoseconds filter native creation dates before indexing and before the limit. The bridge does not round search bounds through `Date` or SQLite epoch `Double` values. A changed date window rebuilds both derived indexes.

## Native verification fixture

Use a canonical, private temporary parent. On macOS, use POSIX `realpath`: Foundation can retain the `/var` alias even after `resolvingSymlinksInPath()`.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run --package-path Desktop/native/macos StowBridgeFixture seed /private/tmp/PRIVATE_PARENT/dev.narumi.stow.desktop-preview
# Run the separate Rust process-restart verification harness.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run --package-path Desktop/native/macos StowBridgeFixture failed-save /private/tmp/PRIVATE_PARENT/dev.narumi.stow.desktop-preview
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run --package-path Desktop/native/macos StowBridgeFixture inspect /private/tmp/PRIVATE_PARENT/dev.narumi.stow.desktop-preview
```

`seed` creates all five native item types with deterministic IDs, `source_app="Bridge fixture"`, native scalar metadata, icon bytes, attachment bytes, and HTML representations. The Rust verification harness must edit each title to `Edited fixture ITEM_TYPE` and each note to `Edited fixture note`. It must preserve text and language. `inspect` reopens the disk store and verifies the edits, strictly advanced revisions, and all unrelated fields and bytes. Both commands return `{"ok":true,"items":5}` on success, or exit nonzero with a content-free error. `failed-save` temporarily sets `RLIMIT_FSIZE=0` and ignores `SIGXFSZ` in its own verification process. It forces a real native save failure while changing text, language, fingerprint, and representation state. It restores the process limits and signal handler, then verifies complete snapshot equality on the same handle and after close/reopen. Native CoreData can log expected I/O diagnostics during this check. These operations exist only in the verification executable, not the production C ABI.

Headless tests consume `Desktop/fixtures/backend.json` and cover malformed ABI requests, ownership, replay, disk reopen, exact native revisions, all lifecycle actions, rejected mutations, index failure, pinned filtering, private path and lock safety, close with outstanding work, and five-type native metadata preservation. They do not launch an application or operate the desktop UI.
