# Rewrite Verification Record

## Status

The rewrite is incomplete. The workspace contains portable rules, local capture and metadata persistence, filtered search, and an isolated UI feasibility sample. It is not an installable Stow replacement. The existing Swift application, Share Extensions, CLI, and iCloud store are unchanged.

Production UI adoption is stopped: `iced` 0.14 lacks the native accessibility integration required by Phase 0. [ADR 0006](../docs/decisions/0006-rust-desktop-feasibility-gates.md) records upstream evidence and the required framework decision. Tauri 2 remains an unapproved fallback, not a verified solution.

Windows storage remains disabled. Its private ACL and durable publication protocol are not implemented. The [storage README](crates/stow-storage/README.md#windows-durability-blocker) records the Win32 API blocker. macOS local SQLite opening remains disabled to protect the canonical SwiftData store.

No desktop UI test or desktop launch has occurred during implementation. The WSL2 development host cannot perform signed Apple integration or two-device CloudKit checks.

## Behavior Inventory

Paths below are relative to the repository root. A source mapping is not proof of complete behavioral compatibility.

| Behavior | Existing Swift test source | Rust evidence and remaining limits |
|---|---|---|
| URL normalization and titles | `Packages/StowCore/Tests/StowCoreTests/CaptureDraftTests.swift` | Core fixtures; complete Foundation URL equivalence remains unverified |
| Unicode and line-ending fingerprints | `Packages/StowCore/Tests/StowCoreTests/ClipboardContentFingerprintTests.swift` | Stable text vector and normalization tests; no existing macOS fingerprints imported |
| Representation limits and ordering | `Packages/StowCore/Tests/StowCoreTests/StowRepresentationTests.swift` | Validation, byte/metadata round trips, stale-format removal, and corruption tests |
| Lifecycle and purge | `Packages/StowCore/Tests/StowCoreTests/ItemLifecycleTests.swift` | Explicit-clock domain and repository command tests |
| Clipboard coalescing | `Packages/StowCore/Tests/StowCoreTests/ClipboardIngestionTests.swift` | Local receipts, state/edit preservation, Trash exclusion, replay, and rollback tests |
| Native capture and paste | `Packages/StowCore/Tests/StowCoreTests/OriginalClipboardFormatTests.swift` | Native adapters remain unimplemented |
| Share capture and replay | `Packages/StowCore/Tests/StowCoreTests/CaptureSpoolTests.swift` | Swift path retained; Rust bridge remains unimplemented |
| Attachments | `Packages/StowCore/Tests/StowCoreTests/AttachmentStoreTests.swift` | Full metadata/byte round trips, legacy byte retention, empty files, bounds, and recovery; thumbnail generation/native import remain |
| Search and filters | `Packages/StowCore/Tests/StowCoreTests/SearchServiceTests.swift` | Prefix/metadata/Trash/date/order tests plus shared native fixtures described below |
| Index recovery | `Tests/StowAppTests/SearchIndexRecoveryTests.swift` | Transaction rollback and rebuild tests; no application-level generation handling yet |
| Safe direct paste | `Tests/StowAppTests/RetrievalPastePolicyTests.swift` | Target adapters remain unimplemented |
| Stale selection | `Tests/StowAppTests/QuickPanelInteractionPolicyTests.swift` | Probe state tests only; no production quick panel |
| CLI transport and export | `Packages/StowCore/Tests/StowCoreTests/StowAutomationTests.swift` | Existing CLI retained; Rust transport remains unimplemented |

## Local Continuation Checks

Rust/Cargo 1.99.1 on Linux x86_64 under WSL2:

- `cargo fmt --all -- --check`: passed.
- `cargo clippy --workspace --all-targets --locked -- -D warnings`: passed.
- `cargo test --workspace --locked`: 60 tests passed, including 25 shared search cases in one fixture test. Repository tests also invoke child-process checks.
- `cargo build --workspace --release --locked`: passed.
- `cargo deny --locked check licenses`: passed.
- `cargo audit` 0.22.2: successful, no known vulnerabilities; one unmaintained `ttf-parser` 0.25.1 warning, `RUSTSEC-2026-0192`. No advisory is ignored.

An independent review found a regression in the retained literal `search()` API: indexed content was width-folded but query text was not. Both now use the same transformation, with regression tests. Width conversion uses the Unicode 17.0 `<wide>` and `<narrow>` mappings, not unrestricted NFKC. The derived table and Unicode license are included. Tests check sorted/unique mappings, idempotence, Japanese voiced kana, Korean forms, and preservation of unrelated compatibility characters. A second review found that decomposed combining marks were split out of query tokens; token generation now retains Unicode marks, with shared composed/decomposed fixtures.

The continuation also adds representation metadata validation before blob reads, detection of attachment/representation ID collisions before recovery cleanup, an indexed fingerprint lookup, and a directly constructed v2 schema test. Migration preserves legacy fingerprint strings; new local fingerprints use a separate namespace and do not coalesce with them.

## Shared Search Fixtures

`Desktop/fixtures/search.json` is consumed by:

- `Packages/StowCore/Tests/StowCoreTests/PortableSearchFixtureTests.swift`, using the existing `SQLiteSearchIndex` actor and native Foundation transform.
- `Desktop/crates/stow-storage/tests/shared_search.rs`, using the Rust local repository on Linux.

The 25 cases cover token prefixes, metadata filters, source case handling, ASCII/Japanese/Korean width conversion, embedded NUL, Chinese text, lifecycle filters, inclusive dates, and stable creation ordering. Rust execution passes. The first native Swift run, [40076571267](https://github.com/narumiruna/stow/actions/runs/40076571267), found two incorrect Korean width-equivalence assumptions. Existing Foundation search keeps those jamo forms distinct. The Rust transform and fixture expectations were corrected to preserve that behavior; a fresh native run is required. Passing a finite fixture set will not establish complete ICU or URL normalization equivalence.

## Interruption and Corruption Evidence

- A child process exits without destructors after writing a partial attachment stage. Reopen removes that stage and preserves the existing item and committed attachment.
- Tests construct persistent states before/after publication and between hard-link creation and staging unlink.
- SQLite trigger failures test transaction rollback of capture, coalescing, edits, lifecycle batches, and indexes. They do not simulate an operating-system kill during COMMIT.
- Tests reject missing/corrupt committed bytes, malformed representation metadata, unknown formats, duplicate format order/type, unsafe permissions, symlinks, dangling references, and duplicate blob IDs without removing committed data.
- These tests do not prove device-specific power-loss behavior.

## Native CI Evidence

The previous foundation at `fe56e73` passed [Rust CI 40074019133](https://github.com/narumiruna/stow/actions/runs/40074019133) on Ubuntu 24.04, Windows 2025, and macOS 15, plus [Swift CI 40074019198](https://github.com/narumiruna/stow/actions/runs/40074019198). The documentation-only successor also passed both workflows.

Continuation native results are pending. Native Windows/macOS Rust tests verify portable rules and rejection of unsupported local storage without filesystem mutation. They do not run the Linux persistence suite or establish Windows persistence support.

The existing Swift CI gate includes package/app/share tests, macOS/iOS builds, version/project checks, and entitlement/privacy-manifest checks. It cannot run locally because Xcode is unavailable. Its working-tree script also has pre-existing CRLF line endings; these unrelated changes are preserved.

## Remaining Gates

- Approve a framework decision that can meet native accessibility requirements; then verify keyboard, screen reader, IME, scaling, contrast, reduced motion, multiple monitors, and panel focus.
- Establish a supported Windows persistence protocol and implement private ACL/reparse-point checks.
- Implement production UI, platform adapters, local CLI transport, and Swift storage bridge.
- Verify signed App Group, Share Extension, unchanged iOS interoperability, and two-device iCloud behavior.
- Record search latency and memory baselines on fixed 10,000-item and 100,000-item datasets.
- Complete native installers, upgrade, uninstall, backup, and rollback verification.
- Complete all relevant non-interactive checks before the one final local UI batch through `Scripts/ui_tests.sh`.

No completion criterion is waived. No production-data cutover is permitted by passing repository tests or CI builds.
