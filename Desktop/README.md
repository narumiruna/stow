# Rust Desktop Preview

Tauri 2 is approved for the desktop rewrite. The preview connects a local web UI to one shared Rust command service with native-selected storage. It is not a replacement release for the current Swift app.

## Current Behavior

- Three-column Library with adaptive panes, compact filters, safe typed text presentation, and grouped Settings.
- Library search by text, type, source app, inclusive UTC dates, lifecycle state, and pin state.
- Text, code, and link Quick Add; stable capture IDs make retries idempotent.
- Editing, pinning, archive, Trash, and restore with optimistic revision checks.
- Save/Discard/Cancel protection for navigation and native close/quit requests.
- Draft retention after failed saves, conflicts, and edits made during a save.
- Attachment metadata and representation counts without reading original blobs.
- Explicit unavailable capabilities instead of simulated clipboard, hotkey, or sync controls.

Linux uses a separate preview application-data directory under the platform data root, identified by `dev.narumi.stow.desktop-preview`. Missing Linux parent directories are created privately. The frontend cannot choose a library path. Do not point this preview at production data.

macOS uses the same Rust service through a versioned C ABI bridge to an isolated local SwiftData preview store. Its private root is `~/Library/Application Support/dev.narumi.stow.desktop-preview`; the bridge never opens the production App Group/CloudKit library. Native startup selects this path, not the frontend.

Windows storage remains disabled until its durability/private-ACL gate passes. The preview never opens a replacement SQLite canonical library on macOS. The existing Swift application, SwiftData/iCloud store, iOS app, Share Extensions, and CLI are unchanged.

The [Swift parity execution record](PARITY.md) tracks the partial M0/M1 continuation, deterministic fixtures, repository benchmarks, and blocked acceptance gates. Collection counts, Recently Used, multi-selection, and batch/Undo are not delivered. Unsupported controls remain explicit; the app does not ship demo data.

File/image import and previews, native clipboard adapters, direct paste, shortcuts, quick panel, Rust CLI transport, production Apple storage integration, and installers are not delivered yet. See the [plan](../docs/plans/2026-10-24_rust-cross-platform-desktop-plan.md) and [verification record](VERIFICATION.md).

## Shared Backend

- `stow-core` defines portable models, request/result types, and the repository contract.
- `stow-desktop-service` owns one bounded worker and accepts a backend factory. It has no SQLite or UI dependency.
- `stow-storage` implements the contract for the Linux SQLite preview; its Windows/macOS platform guards remain intact.
- The macOS host adapter calls `Desktop/native/macos/`, which retains one main-actor SwiftData owner. List/detail responses contain metadata, not original blob bytes.
- Revision checks remain `expected_updated_at` RFC3339 values. Swift compares exact native-precision instants before mutation; there is no millisecond round trip through the CLI format.
- Explicit-create retries reuse their capture item while it exists. Clipboard coalescing and replay after purge are not supported by this bridge.
- The host drains the service off the main thread before exit. The main loop stays active for Swift callbacks; closing a bridge handle releases storage before reporting completion.

See the [bridge ABI and storage rules](native/macos/README.md). A successful preview save is local-only, not signed Apple or iCloud evidence.

## Build and Non-interactive Checks

Run from `Desktop/`. Rust is pinned in `rust-toolchain.toml`; web tests use Bun 1.4.4. Native macOS builds require Xcode and compile the Swift static library automatically. Set `DEVELOPER_DIR` to the required Xcode installation without changing the machine-wide developer directory.

```sh
bun install --frozen-lockfile --cwd web
bun test --cwd web
bun audit --cwd web
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo test --workspace --locked
cargo build --workspace --release --locked
cargo audit
cargo deny --locked check licenses
```

From the repository root, run the complete headless macOS bridge check:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/verify_desktop_bridge.sh
```

This runs Swift bridge tests, then separate native seed, Rust-to-Swift mutation/reopen, real save-failure recovery, and native byte-preservation processes against a new disposable on-disk store. It does not launch the desktop app. The file-size fault is limited to its fixture subprocess, which restores its process limits. Expected CoreData I/O diagnostics during this fault are not a passing-save claim.

The frontend has no production package dependencies or build step. Tauri embeds only `web/public/`, not tests or `node_modules`.

Linux host builds require a C compiler, `pkg-config`, WebKitGTK 4.1, GTK 3, DBus, and the development packages listed in `.github/workflows/rust.yml`. Windows uses WebView2; macOS uses WKWebView. Native runtime compatibility remains a separate gate.

For a host without Linux WebView development packages, portable checks can exclude only the host binary:

```sh
cargo test --workspace --exclude stow-desktop --locked
cargo clippy --workspace --exclude stow-desktop --all-targets --locked -- -D warnings
```

This exclusion is not proof that the Tauri host builds. CI must build and test the complete workspace on all three native platforms. None of these test commands launches the application or desktop UI.

## Security and Verification

- IPC grants only declared application commands and close-event subscription to the embedded main window.
- Rust verifies the window label and embedded origin. Remote navigation, new windows, and post-handshake reload are blocked.
- Saved content is rendered as text. The CSP permits no remote scripts, shell access, or `unsafe-eval`.
- Rust commands run on a bounded single-writer queue. The host never waits for worker completion on the UI thread; macOS SwiftData access remains on its owning main actor.
- Status reports actual backend availability. A successful local save is not cloud-delivery evidence.
- Native close/quit protection depends on a live frontend; forced termination or renderer failure is not draft persistence.

The `iced` probe is removed. [ADR 0006](../docs/decisions/0006-rust-desktop-feasibility-gates.md) records the approved Tauri decision; no second UI implementation is maintained.

Native screen-reader, IME, focus, signed iCloud, distribution, and final interactive checks remain open. Finish implementation and relevant non-interactive checks before the final UI batch through `Scripts/ui_tests.sh`. Never invoke that script or UI test schemes from CI.
