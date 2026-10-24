# Rust Desktop Preview

Tauri 2 is approved for the desktop rewrite. The preview connects a local web UI to the Rust repository through one storage worker. It is not a replacement release for the current Swift app.

## Current Behavior

- Library search by text, type, source app, inclusive UTC dates, lifecycle state, and pin state.
- Text, code, and link Quick Add; stable capture IDs make retries idempotent.
- Editing, pinning, archive, Trash, and restore with optimistic revision checks.
- Save/Discard/Cancel protection for navigation and native close/quit requests.
- Draft retention after failed saves, conflicts, and edits made during a save.
- Attachment metadata and representation counts without reading original blobs.
- Explicit unavailable capabilities instead of simulated clipboard, hotkey, or sync controls.

Linux uses a separate preview application-data directory under the platform data root, identified by `dev.narumi.stow.desktop-preview`. Missing Linux parent directories are created privately. The frontend cannot choose a library path. Do not point this preview at production data.

Windows storage remains disabled until its durability/private-ACL gate passes. macOS storage remains unavailable until the Swift bridge is integrated; the preview never opens a replacement SQLite canonical library on macOS. The existing SwiftData/iCloud store, iOS app, Share Extensions, and CLI are unchanged.

File/image import and previews, native clipboard adapters, direct paste, shortcuts, quick panel, Rust CLI transport, Swift bridge, and installers are not delivered yet. See the [plan](../docs/plans/2026-10-24_rust-cross-platform-desktop-plan.md) and [verification record](VERIFICATION.md).

## Build and Non-interactive Checks

Run from `Desktop/`. Rust is pinned in `rust-toolchain.toml`; web tests use Bun 1.4.4.

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
- Storage runs on a bounded single-writer queue. The UI event loop does not wait synchronously for database operations.
- Status reports actual backend availability. A successful local save is not cloud-delivery evidence.
- Native close/quit protection depends on a live frontend; forced termination or renderer failure is not draft persistence.

The `iced` probe is removed. [ADR 0006](../docs/decisions/0006-rust-desktop-feasibility-gates.md) records the approved Tauri decision; no second UI implementation is maintained.

Native screen-reader, IME, focus, signed iCloud, distribution, and final interactive checks remain open. Finish implementation and relevant non-interactive checks before the final UI batch through `Scripts/ui_tests.sh`. Never invoke that script or UI test schemes from CI.
