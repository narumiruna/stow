# Swift Desktop Parity Execution Record

## Status

The [parity plan](../docs/plans/2026-10-24_swift-desktop-parity-plan.md) is **not complete**. This branch implements part of M0/M1 and fixes an index-scaling defect found during M0 measurements. It is not a Windows storage release or a replacement for the Swift app.

Base: `4818b1d` on `main`, which includes PR #38. The original working tree and its untracked plan remain unchanged. Work uses a separate worktree on `narumi/feat/swift-desktop-parity`.

| Milestone | State | Evidence or remaining requirement |
| --- | --- | --- |
| M0: contract and measurements | Partial | Source matrix, five-type hostile/long-content fixtures, and isolated Linux repository benchmark. Native startup/render/memory baselines, Swift comparison, and agreed regression budgets remain open. |
| M1: shared visual foundation | Partial | Three-column shell, adaptive panes, compact filters/tokens, type tiles, typed text-only detail, explicit Edit/Cancel, grouped Settings, and DOM coverage. Native layout/accessibility approval, complete row previews/counts, and remaining parity behavior are not established. |
| M2: Windows persistence | Blocked | No accepted complete durability/private-ACL protocol or native recovery/security test suite. Keep the platform guard. See the investigation below. |
| M3: usable Windows slice | Blocked by M2 | No real Windows library, native Copy, Recently Used, continuation, batch actions, or Trash Undo. Existing Linux manual-capture/lifecycle commands remain usable. |
| M4: rich content/native input | Not delivered; depends on M2/M3 | Image/file import, real thumbnails, export/open/share/drag, monitoring, tray, and shortcuts still require native implementations and tests. |
| M5: copy-only Quick Panel | Not delivered; depends on native Copy/tray/shortcuts | No second WebView or broader IPC permissions were added. |
| M6: direct paste/platform completion | Not delivered; Apple gate blocked | No synthetic input is emitted. A signed macOS bridge, provisioned test environment, and unchanged-iOS two-device checks are unavailable here. |
| M7: final native verification/distribution | Blocked | Complete implementation must precede the grouped local UI batch. Native accessibility, IME, focus, multi-display, signing, upgrade, rollback, and distribution gates remain open. |

Do not check off the full plan based on this record, a DOM test, or a compiled executable. Keep the pull request Draft.

## Source-to-Implementation Matrix

Swift paths below are under `Sources/StowApp/` unless stated otherwise. Existing source is the behavior reference; August screenshots are historical, not current-source runtime proof.

| Swift reference | Required behavior | Current Rust/web path and evidence | Remaining gap |
| --- | --- | --- | --- |
| `macOS/MacLibraryView.swift`, `MacVisualStyle.swift` | Three-column hierarchy, semantic surfaces, adaptive size | `web/public/index.html`, `styles.css`; source-reviewed layout and focusable pane navigation | Native comparison at each declared viewport/DPI/theme |
| `macOS/MacLibraryPresentation.swift` | Inbox/Pinned/Archive/Trash membership | `model.js` collections → existing `search_items`; tests check server-side filters and canceled transitions | Full counts, Recently Used, continuation |
| `Shared/AppModel.swift` (`StowSection`) | Recently Used sorted by explicit use | Navigation explicitly disabled; no sort of the first 200 rows | Native use commands and server ordering |
| `macOS/MacLibraryView.swift` (`MacLibraryFilterBar`) | Compact filters and removable tokens | Existing UTC query fields, individual removal and Clear, draft guards | Calendar presets and known-source choices; no silent UTC-contract change |
| `Shared/ItemPresentation.swift` | Type identity, source/date, bounded preview | Five type tiles, relative dates with full timestamp help, text-node detail classes | Bounded summary snippets, thumbnails, code highlighting |
| `macOS/MacLibraryView.swift` detail/editor | Read first, explicit Edit, Cancel/Save, preserve failures | `app.js`, `app.test.js`: read/edit focus, guarded Cancel, save/replay/conflict/in-flight regressions | Native edit presentation approval |
| `macOS/MacLibraryView.swift` collection actions | Multi-selection, batch applicability, Trash Undo | Existing single-item revision-checked lifecycle remains | Batch API, stale-Undo rules, selection contract |
| `Shared/QuickAddView.swift` | Text/code/link, clipboard, file/image drop | Existing text/code/link Quick Add and stable capture IDs retained | Native clipboard read, file/image import/drop |
| `Shared/PlatformActions.swift`, `MacItemActions.swift` | Copy/open/preview/share/drag and correct use recording | UI says unavailable; no extra command/plugin permission | Native operations and attachment-ID materialization |
| `macOS/ClipboardCapturePolicy.swift`, `MacAppCoordinator.swift` | Opt-in monitoring, next-change start, bounded original formats | Capability remains false | Windows adapter, privacy/self-write/race tests |
| `macOS/GlobalHotKeyService.swift`, `MacSettingsModels.swift` | Shortcut pair registration and rollback | Settings reports unavailable; no fake enabled switch | Native registration/rollback and tray lifecycle |
| `macOS/RetrievalPanel.swift`, controller and policies | Separate timeline, keyboard layers, copy-only focus return | No panel is claimed or shipped | Full M5 implementation and per-window authorization |
| `macOS/DirectPasteService.swift` and safety plan | Verified-target paste, safe fallback | No direct-paste capability or synthetic events | Safe implementation rather than copying the known Swift focus defect |
| `macOS/MacSettingsView.swift` | Capture/Paste/Storage/Privacy hierarchy and real recovery | Four accessible page targets, authoritative capability display, existing index rebuild | Actual native settings controls and richer recovery results |
| SwiftData repository, CloudKit, App Group | Canonical Apple compatibility | Existing identifiers/store/iOS/Share/CLI untouched; macOS alternate SQLite still rejected | Signed Swift bridge and Apple runtime evidence |

All fixture content remains under `web/fixtures/`, outside embedded `web/public/`. Production does not contain demo items or claim successful unavailable actions. DOM tests cover all five types, long/hostile content, empty/no-result/search-failure/storage-unavailable distinctions, focus, and no per-row detail fetches.

## Windows Persistence Investigation

The [existing blocker](crates/stow-storage/README.md#windows-durability-blocker) and [ADR 0006](../docs/decisions/0006-rust-desktop-feasibility-gates.md) still apply.

Local evidence on Windows `10.0.26300.0`, Rust `1.99.1`, ordinary user context:

- Both native `stow-storage` platform rejection tests pass: a missing library stays absent, and an existing sentinel remains unchanged.
- An isolated, newly created temporary directory was opened with `CreateFileW`, `OPEN_EXISTING`, `FILE_FLAG_BACKUP_SEMANTICS`, and shared read/write/delete.
  - A `GENERIC_WRITE` directory handle returned success from `FlushFileBuffers` (error 0).
  - A `GENERIC_READ` handle returned failure (error 5).
  - Handles were closed and the owned temporary directory was removed. No elevation or production-library access occurred.

The writable-handle result is a useful candidate, not evidence of a complete protocol. It does not establish durable parent creation, non-replacing publication, stage unlink, cleanup, SQLite journal deletion, all declared filesystems, private DACLs, reparse-point rejection, or recovery at every persistent state. Process termination does not prove power-loss behavior.

Do not describe all Windows directory flushing as impossible based on a read-only handle. Also do not enable storage based on one successful API call. A documented supported protocol and native security/recovery tests are still required. No alternative storage design was adopted, and no acceptance criterion was weakened.

## Repository Performance Investigation

The reproducible helper is `crates/stow-desktop-service/examples/parity_baseline.rs`:

```sh
cd Desktop
cargo run --release --locked -p stow-desktop-service --example parity_baseline
cargo test --locked -p stow-desktop-service --example parity_baseline
```

It runs only on Linux, creates an isolated temporary library, and seeds 10,000 and 100,000 deterministic text snapshots. Each has repeated 240/272-byte text; every 1,000th item matches `needle`. It measures seed time, reopen including index rebuild, 20 limited-list/search requests, and a final process RSS sample. It cleans its temporary library on normal completion.

These are repository measurements, not service/IPC/WebView startup, render latency, peak memory, Windows persistence, or Swift comparisons. Timing values are not unit-test thresholds.

Reference host: AMD Ryzen 9 7950X3D, 32 logical CPUs, WSL2 kernel `6.18.33.2-microsoft-standard-WSL2`, Rust 1.99.1 release. The temporary filesystem is `tmpfs`; these timings exclude physical-disk durability costs.

Before the index fix, the 10,000-item run measured seed 8,347 ms, reopen/reindex 5,672 ms, list p50/p95 2,262/2,317 microseconds, search p50/p95 71/111 microseconds, and final RSS 11,340 KiB. The combined 10k/100k run was stopped after 7m03s without a completed 100k result. An earlier build-and-run command also reached its 300-second tool timeout. These are incomplete runs, not passing 100k measurements.

The cause is deletion through the FTS5 `id UNINDEXED` column before every insertion. That scans the growing index during seed and rebuild. The internal fix associates FTS rowids with existing canonical `items.rowid`, enabling indexed deletion. The schema version and public UUID/search ordering remain unchanged. Opening a library already rebuilds the disposable index, so legacy derived rowids are replaced before use.

After-fix serial measurements, with no concurrent build:

| Items | Seed ms | Reopen/reindex ms | List p50/p95 µs | Search p50/p95 µs | Final RSS KiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| 10,000 | 1,643 | 140 | 2,278 / 2,426 | 86 / 122 | 11,320 |
| 100,000 | 16,937 | 1,447 | 25,291 / 26,376 | 1,045 / 1,240 | 42,648 |

The 10k rebuild changed from 5,672 ms to 140 ms in these samples. These are observations, not a guaranteed ratio or an accepted UI budget. Full native/Swift baseline comparisons and regression budgets remain open; this helper does not satisfy the complete M0 gate.

Local verification passes: 62 web tests; 72 portable Rust tests plus the benchmark-helper unit test; portable formatting, Clippy, and release builds; complete Windows native workspace tests and host release build; frozen web install/audit; and whitespace checks. The two native Windows platform tests still verify refusal, not persistence support. Full three-OS/Swift CI results belong to the pull request, and native interactive acceptance remains blocked.

## Verification Rules and Remaining External Work

- Keep all existing web save/replay/close/race regressions and add focused presentation/FTS tests.
- Run frozen web dependency install, Bun tests/audit, Rust formatting, Clippy, workspace tests, release builds, and dependency/license checks. CI must retain the three-native-OS build matrix and Swift gate.
- Review the entire change for text injection, permission changes, worker ownership, stale revisions, cancellation, focus, collection membership, compatibility, and scope.
- Do not launch native UI tests during this incomplete implementation. Accumulate scenarios for the final batch exclusively in `Scripts/ui_tests.sh`; do not add UI calls to CI.
- Apple runtime acceptance needs an authorized macOS machine with Xcode, signing/provisioning, a test iCloud account/container, and test devices. Native screen-reader, IME, and multi-display checks need the declared local desktop environments.
- Signing, notices, advisory review, installation/upgrade/rollback/uninstall, and release distribution remain unmet. Do not publish packages, create version tags, or dispatch release workflows for this work.
