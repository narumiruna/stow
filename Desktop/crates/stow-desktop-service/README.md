# Desktop service

`DesktopService::start(root)` starts one storage worker. The application selects the absolute root at startup. Requests cannot select another library. On Linux, the worker creates missing parent directories with mode 0700 and rejects symlink ancestors. A failed open remains visible through `status`; the service does not open a fallback library.

The cloneable handle has synchronous `status`, `search`, `get`, `create`, `update`, `apply`, and `rebuild` methods. Run these methods in a blocking task. The service has no UI or async runtime dependency.

- The request queue holds at most 32 pending operations. A full queue returns `busy` without accepting the operation.
- An accepted request waits for completion. There is no mutation timeout or automatic retry. A worker panic or disconnect returns `disconnected`.
- The last handle disconnects the queue and joins the worker after accepted operations finish. Shutdown does not enqueue a message into a full queue.
- Create requires a client-generated `capture_id`. Keep this ID when retrying a failed response. The repository replays the capture receipt instead of creating another item.
- Update and lifecycle requests require the exact `expected_updated_at` instant. Timestamp comparison preserves nanoseconds and accepts equivalent RFC3339 offsets. A stale request returns `conflict` before mutation.
- Create supports text, code, and links only. Text and note fields are limited to 1 MiB. URL, title, source, and language fields are limited to 16 KiB. Search text is limited to 4096 bytes; result limits are clamped to 1–500.
- Summaries contain no content or preview bytes. Details remove embedded icon and preview bytes, reject text over 1 MiB, and return attachment metadata and representation counts without blob reads.
- Capability flags report implemented functions only. Clipboard, direct paste, global shortcut, and iCloud support are false. Local storage is true only after a successful open. The storage platform guard remains authoritative: Windows and macOS do not create a local canonical library.

DTOs use snake_case JSON fields. Errors contain `code`, a content-free `message`, and `retryable`. Busy and storage errors permit retry; a conflict requires a reload, and a disconnected worker requires a restart. No service method logs payloads.
