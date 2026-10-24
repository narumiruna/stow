# Rewrite Verification Record

## Status

The rewrite is incomplete. The workspace is an isolated foundation, not an installable Stow replacement. All completion criteria in the implementation plan remain subject to their original gates.

The development host is Linux x86_64 under WSL2. It cannot build or sign the macOS host, open SwiftData, or run two-device CloudKit checks. No desktop UI tests have been run during implementation.

## Existing Behavior Inventory

Paths below are relative to the repository root. A mapped test is a source reference, not proof that the complete Swift behavior has been ported.

| Behavior | Existing test source | Rust foundation or remaining work |
|---|---|---|
| URL normalization and title derivation | `Packages/StowCore/Tests/StowCoreTests/CaptureDraftTests.swift` | Core capture fixtures; Foundation URL equivalence still needs native comparison |
| Unicode and line-ending fingerprints | `Packages/StowCore/Tests/StowCoreTests/ClipboardContentFingerprintTests.swift` | Core tests use the existing stable plain-text hash and normalization cases |
| Original format allowlist and byte limits | `Packages/StowCore/Tests/StowCoreTests/StowRepresentationTests.swift` | Core validation only; native selection and persistence remain |
| Pin, archive, Trash, restore, purge | `Packages/StowCore/Tests/StowCoreTests/ItemLifecycleTests.swift` | Portable lifecycle tests |
| Clipboard coalescing and field preservation | `Packages/StowCore/Tests/StowCoreTests/ClipboardIngestionTests.swift` | Command-level ingestion remains unimplemented |
| Original-format and plain-text paste | `Packages/StowCore/Tests/StowCoreTests/OriginalClipboardFormatTests.swift` | Native clipboard adapters remain unimplemented |
| Atomic share capture and replay | `Packages/StowCore/Tests/StowCoreTests/CaptureSpoolTests.swift` | Existing Swift path retained; Rust bridge remains unimplemented |
| Attachment round trip and size bounds | `Packages/StowCore/Tests/StowCoreTests/AttachmentStoreTests.swift` | Isolated local storage tests; thumbnails and native import remain |
| Search tokens, filters, NUL, Unicode | `Packages/StowCore/Tests/StowCoreTests/SearchServiceTests.swift` | Local repository search is a foundation, not search parity |
| Search rollback and superseded results | `Tests/StowAppTests/SearchIndexRecoveryTests.swift` | Local index rebuild tests and probe state tests do not establish application parity |
| Safe paste target and permission fallback | `Tests/StowAppTests/RetrievalPastePolicyTests.swift` | Native target adapters remain unimplemented |
| Stale selection | `Tests/StowAppTests/QuickPanelInteractionPolicyTests.swift` | Probe state tests only; no actual quick panel |
| CLI request identity, recovery, export | `Packages/StowCore/Tests/StowCoreTests/StowAutomationTests.swift` | Existing CLI retained; Rust transport remains unimplemented |

## Gate Evidence Required Outside This Host

- Native GUI, signing, and distribution verification beyond the passing Rust headless CI matrix.
- Framework accessibility, keyboard, IME, display scaling, reduced motion, and panel focus checks on all supported desktops.
- Signed Rust-to-Swift bridge, existing-store access, App Group capture, and unchanged iOS interoperability.
- Signed two-device iCloud create, edit, archive, restore, delete, attachment, offline, and unavailable-account checks.
- Continued existing Swift CI coverage under the configured Xcode/Swift versions; the initial foundation commit passes this gate.
- Native installers, upgrade, uninstall, backup, and rollback checks.
- Current search latency and memory baseline for fixed 10,000-item and 100,000-item datasets. No numeric performance limit has been approved or claimed.

These checks must not be replaced with passing mock tests. No production-data cutover is authorized by a successful foundation build.

## Local Results

The final local run uses Rust/Cargo 1.99.1. The following checks passed:

- `cargo fmt --all -- --check`.
- `cargo clippy --workspace --all-targets --locked -- -D warnings`.
- `cargo test --workspace --locked`: 10 domain tests, 18 local repository tests, and 5 probe state tests. The repository run also invokes a child-process writer-lock check.
- `cargo build --workspace --release --locked`.
- `cargo deny --locked check licenses`.

Independent reviews covered correctness, security, lifecycle, compatibility, regressions, and scope. Corrected findings include package license/publication inheritance, attachment rediscovery after restart, explicit committed-delete cleanup outcomes, and dangling-reference validation before cleanup. Regression tests cover all three storage findings. URL validation now rejects known incompatible raw spellings; complete Foundation URL parity remains unverified.

At implementation commit `fe56e73`, [Rust CI run 40074019133](https://github.com/narumiruna/stow/actions/runs/40074019133) passed native formatting, Clippy, headless tests, and release builds on Ubuntu 24.04, Windows 2025, and macOS 15 runners. The advisory/license job also passed. Linux ran 33 tests; Windows and macOS each ran 10 domain tests, 5 probe tests, and 1 storage-platform guard test. The Linux storage tests are intentionally not run on the two unsupported storage platforms.

[Existing Swift CI run 40074019198](https://github.com/narumiruna/stow/actions/runs/40074019198) passed the repository's complete non-interactive gate, including package/app/share tests, macOS/iOS builds, version/project checks, and entitlement/privacy-manifest checks. These results do not establish signed CloudKit access or UI behavior.

`cargo audit` 0.22.2 exited successfully and reported no known vulnerabilities in the resolved lockfile. It reported one maintenance warning: `ttf-parser` 0.25.1, `RUSTSEC-2026-0192`, through the `iced` font stack. No advisory is ignored. Resolve or explicitly evaluate this dependency before adopting the framework for production.

`cargo license` 0.7.0 examined the resolved dependency SPDX metadata. `cargo deny` 0.20.2 passed the explicit license policy in `deny.toml`. All first-party packages inherit the repository license and prohibit publication. This is not a complete distribution-notice or bundled-native-code license audit.

The existing Swift CI script could not run locally. Its tracked, LF copy fails at `xcodebuild: command not found`. The working tree's pre-existing CRLF copy also fails Bash parsing; it was not rewritten. The existing macOS CI workflow is retained and must supply the native checks.

Interactive verification is not eligible while the full implementation is incomplete. No UI test or desktop launch was performed.
