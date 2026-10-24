# Rewrite Verification Record

## Status

The rewrite is incomplete. The workspace now includes a Tauri 2 desktop preview, a semantic web Library UI, a dedicated Rust storage worker, and the local repository. It is not an installable replacement release. The existing Swift application, Share Extensions, CLI, and iCloud store are unchanged.

The user explicitly approved Tauri 2 with a Rust backend and web UI. [ADR 0006](../docs/decisions/0006-rust-desktop-feasibility-gates.md) records the decision. The stopped `iced` sample is removed. Framework approval does not establish native accessibility, IME, focus, or signed Apple compatibility.

Windows storage remains disabled. Its private ACL and durable publication protocol are not implemented. The [storage README](crates/stow-storage/README.md#windows-durability-blocker) records the Win32 API blocker. macOS local SQLite opening remains disabled to protect the canonical SwiftData store.

No desktop UI test or desktop launch has occurred during implementation. The WSL2 development host cannot perform signed Apple integration or two-device CloudKit checks.

## Tauri Continuation

- Rust service tests cover one bounded worker, queue saturation, panic/disconnect, shutdown, restart, optimistic revisions, capture replay, failed saves, argument bounds, and private Linux parent creation.
- Forty-five headless Bun/DOM tests cover frontend state and rendering. Coverage includes hostile content, dialogs, async races, replay conflicts, explicit new captures, native form validation, filters, close protection, and unavailable backends.
- Tauri grants only declared commands and close-event subscription to the embedded main window. Rust checks its label and origin. Navigation after the frontend handshake, remote pages, and new windows are denied. The CSP forbids remote scripts and `unsafe-eval`.
- List/detail metadata APIs do not read original attachment or representation blobs. Search applies the pin filter before its result limit. Integer second/nanosecond metadata keeps inclusive UTC day bounds from rounding into the next midnight.
- Native window close and application quit route through the same Save/Discard/Cancel guard after listener registration. Forced termination and renderer failure do not persist drafts.
- The preview uses a distinct application-data identity. Disabled macOS and Windows backends report unavailability without creating substitute canonical stores.

Local formatting, Clippy excluding only `stow-desktop`, and 68 portable Rust tests pass. Full host checking stops at missing DBus/GTK/WebKit development libraries on this WSL host; administrative installation is unavailable. The native CI workflow installs these dependencies and must compile, test, and build the complete workspace. No desktop UI was launched.

Bun 1.4.4 dependency audit reports no vulnerabilities in its nine development packages; the frontend has no production package dependencies. Rust license policy passes after adding Tauri's MPL-2.0 and Apache-2.0 WITH LLVM-exception requirements. Preserve their notice/source obligations during distribution.

The Tauri dependency audit reports `proc-macro-error` 1.0.4 as unmaintained (`RUSTSEC-2024-0370`) and the Linux GTK dependency `glib` 0.18.5 as unsound in `VariantStrIter` (`RUSTSEC-2024-0429`). These are not ignored or described as warning-free. The application does not directly use that iterator API; framework reachability and an upstream update remain production security review items. Removing `iced` also removes its previous `ttf-parser` warning.

At the initial Tauri implementation commit `74e34db`, [Rust desktop CI 40079486494](https://github.com/narumiruna/stow/actions/runs/40079486494) passed the complete host's formatting, Clippy, headless tests, and release builds on Ubuntu 24.04, Windows 2025, and macOS 15. The dependency audit/license job also passed. [Swift CI 40079486353](https://github.com/narumiruna/stow/actions/runs/40079486353) passed the existing complete non-interactive gate. These native builds validate compilation and generated command permissions, not desktop behavior. Subsequent frontend fixes hide unsupported link-body editing, retain changed create-only replay fields, and disable inapplicable URL validation. Final head checks must also pass.

Earlier repository-stage evidence follows.

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
| Index recovery | `Tests/StowAppTests/SearchIndexRecoveryTests.swift` | Transaction rollback/rebuild tests plus web search-generation guards |
| Safe direct paste | `Tests/StowAppTests/RetrievalPastePolicyTests.swift` | Target adapters remain unimplemented |
| Stale selection | `Tests/StowAppTests/QuickPanelInteractionPolicyTests.swift` | Web state tests reject hidden selections; no native quick panel yet |
| CLI transport and export | `Packages/StowCore/Tests/StowCoreTests/StowAutomationTests.swift` | Existing CLI retained; Rust transport remains unimplemented |

## Earlier Repository-stage Local Checks

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

The 25 cases cover token prefixes, metadata filters, source case handling, ASCII/Japanese/Korean width conversion, embedded NUL, Chinese text, lifecycle filters, inclusive dates, and stable creation ordering. Rust execution passes. The first native Swift run, [40076571267](https://github.com/narumiruna/stow/actions/runs/40076571267), found two incorrect Korean width-equivalence assumptions. Existing Foundation search keeps those jamo forms distinct. The Rust transform and fixture expectations were corrected to preserve that behavior; [Swift CI 40076721888](https://github.com/narumiruna/stow/actions/runs/40076721888) then passed all 134 package tests, including the shared fixture test, plus 87 app tests, 6 share tests, both builds, and repository static checks. Passing a finite fixture set will not establish complete ICU or URL normalization equivalence.

## Interruption and Corruption Evidence

- A child process exits without destructors after writing a partial attachment stage. Reopen removes that stage and preserves the existing item and committed attachment.
- Tests construct persistent states before/after publication and between hard-link creation and staging unlink.
- SQLite trigger failures test transaction rollback of capture, coalescing, edits, lifecycle batches, and indexes. They do not simulate an operating-system kill during COMMIT.
- Tests reject missing/corrupt committed bytes, malformed representation metadata, unknown formats, duplicate format order/type, unsafe permissions, symlinks, dangling references, and duplicate blob IDs without removing committed data.
- These tests do not prove device-specific power-loss behavior.

## Native CI Evidence

The previous foundation at `fe56e73` passed [Rust CI 40074019133](https://github.com/narumiruna/stow/actions/runs/40074019133) on Ubuntu 24.04, Windows 2025, and macOS 15, plus [Swift CI 40074019198](https://github.com/narumiruna/stow/actions/runs/40074019198). The documentation-only successor also passed both workflows.

The first Rust continuation runs found a macOS test-fixture path issue: the temporary root used the system `/var` symlink alias, which the repository correctly rejected. Only the test-owned temporary root is now canonicalized; production symlink rejection is unchanged.

At implementation commit `5bd243f`, [Rust CI 40076950305](https://github.com/narumiruna/stow/actions/runs/40076950305) passed all three native OS jobs and the dependency audit/license job. [Swift CI 40076950351](https://github.com/narumiruna/stow/actions/runs/40076950351) passed the complete existing non-interactive gate and all shared search fixtures. These results apply to the repository stage before the Tauri host was added. Native Windows/macOS Rust tests verify portable rules and rejection of unsupported local storage without filesystem mutation. They do not run the Linux persistence suite or establish Windows persistence support.

The existing Swift CI gate includes package/app/share tests, macOS/iOS builds, version/project checks, and entitlement/privacy-manifest checks. It cannot run locally because Xcode is unavailable. Its working-tree script also has pre-existing CRLF line endings; these unrelated changes are preserved.

## Remaining Gates

- Complete native keyboard, screen-reader, IME, scaling, contrast, reduced-motion, multiple-monitor, and panel-focus verification for the approved Tauri framework.
- Establish a supported Windows persistence protocol and implement private ACL/reparse-point checks.
- Implement production UI, platform adapters, local CLI transport, and Swift storage bridge.
- Verify signed App Group, Share Extension, unchanged iOS interoperability, and two-device iCloud behavior.
- Record search latency and memory baselines on fixed 10,000-item and 100,000-item datasets.
- Complete native installers, upgrade, uninstall, backup, and rollback verification.
- Complete all relevant non-interactive checks before the one final local UI batch through `Scripts/ui_tests.sh`.

No completion criterion is waived. No production-data cutover is permitted by passing repository tests or CI builds.
