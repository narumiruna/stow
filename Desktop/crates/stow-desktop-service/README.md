# Desktop service

`DesktopService::start(factory)` starts one storage worker. The host supplies a `Send + 'static` factory that returns `stow_core::ServiceResult<Box<dyn stow_core::Repository>>`. The worker creates and owns the repository; the repository does not need `Send`. Requests cannot select another library. A failed open remains visible through `status`; the service does not open a fallback library. The service has no production storage dependency.

For the Linux preview, the host supplies `move || stow_storage::open_desktop(root)`. That adapter creates missing parent directories with mode 0700 and rejects symlink ancestors. It rejects macOS and Windows before filesystem mutation. The macOS host supplies its native SwiftData adapter.

The cloneable handle has synchronous `status`, `search`, `get`, `create`, `update`, `apply`, and `rebuild` methods. Run these methods in a blocking task. The service has no UI or async runtime dependency.

- The request queue holds at most 32 pending operations. A full queue returns `busy` without accepting the operation.
- An accepted request waits for completion. There is no mutation timeout or automatic retry. A worker panic or disconnect returns `disconnected`.
- Call `shutdown()` from a background thread while the native event loop continues to run. It stops admissions across all clones, disconnects the queue, drains accepted operations, and joins the worker. Concurrent shutdown callers wait for the same result, including worker panic errors. Shutdown does not enqueue a message into a full queue.
- Dropping the last handle disconnects and detaches the worker; it never joins synchronously. This fallback prevents a deadlock when the native backend needs the main actor. The host must complete explicit shutdown before native exit.
- Create requires a client-generated `capture_id`. Keep this ID when retrying a failed response. The repository replays the existing item instead of creating another item while that item exists. This contract does not promise replay after purge or clipboard receipt parity.
- Update and lifecycle requests require the exact `expected_updated_at` instant. The service converts the revision to UTC RFC3339 with exactly nine fractional digits before dispatch. Timestamp comparison preserves nanoseconds and accepts equivalent RFC3339 offsets. A stale request returns `conflict` before mutation.
- Create validates supported types and content before dispatch. It supports text, code, and links only; empty text and URLs outside the existing Rust ASCII spelling rules are rejected. Text and note fields are limited to 1 MiB. URL, title, source, and language fields are limited to 16 KiB. Search text is limited to 4096 bytes; result limits are clamped to 1–500.
- Summaries contain no content or preview bytes. Details remove embedded icon and preview bytes, reject text over 1 MiB, and return attachment metadata and representation counts without blob reads.
- Capability flags report implemented functions only. Clipboard, direct paste, global shortcut, and iCloud support are false. Local storage is true only after a successful backend open. The SQLite platform guard remains authoritative: Windows and macOS do not create a Rust canonical library.

DTOs and the repository contract are defined in `stow-core`. Existing service DTO names remain available through public reexports. DTOs use snake_case JSON fields. Errors contain `code`, a content-free `message`, and `retryable`. Busy and storage errors permit retry; a conflict requires a reload, and a disconnected worker requires a restart. No service method logs payloads.
