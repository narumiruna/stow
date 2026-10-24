# Rust Desktop Work

This workspace contains rewrite foundations and an isolated UI feasibility sample. It is not a replacement for the current Stow app. Do not use it with a production library.

The [implementation plan](../docs/plans/2026-10-24_rust-cross-platform-desktop-plan.md) defines the complete delivery gates. macOS must continue to use the existing SwiftData store and iCloud container. Windows and Linux storage must be local only. Windows storage is currently disabled because its security and durability gate has not passed.

## Build and Check

Use the Rust toolchain in `rust-toolchain.toml`. Run from `Desktop/`:

```sh
cargo fmt --all -- --check
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo test --workspace --locked
cargo build --workspace --release --locked
```

Dependency checks use `cargo-audit` 0.22.2 and `cargo-deny` 0.20.2:

```sh
cargo audit
cargo deny --locked check licenses
```

The current lockfile has an unmaintained `ttf-parser` dependency through the UI probe. See `VERIFICATION.md`; a successful audit is not a warning-free audit.

These commands do not open a desktop window or access the clipboard. On Linux, install a C compiler, `pkg-config`, and the native display libraries required by the UI probe. See the probe's README for its exact feature selection.

Keep build outputs outside a Windows-mounted WSL checkout when possible:

```sh
CARGO_TARGET_DIR=/tmp/stow-rust-target cargo test --workspace --locked
```

Use isolated temporary libraries in tests. Do not pass the existing App Group directory or a SwiftData store to the Rust local repository. Local storage is not an iCloud replacement.

## Boundaries

- `crates/stow-core`: Portable data types, capture validation, lifecycle rules, and fingerprints.
- `crates/stow-storage`: Local capture/replay/coalescing commands, lifecycle edits, full attachment/representation storage, transactional migrations, and filtered search. It is not connected to the current app.
- `spikes/iced-probe`: Disposable UI feasibility sample. Production adoption is stopped because `iced` 0.14 lacks the required native accessibility integration. See [ADR 0006](../docs/decisions/0006-rust-desktop-feasibility-gates.md).
- `fixtures/search.json`: Shared cases consumed by Rust and native Swift tests.
- `licenses/Unicode-3.0.txt`: Required notice for the Unicode width mapping data.

No Rust desktop host, macOS bridge, native clipboard adapter, replacement CLI, installer, or cutover is delivered by these foundations. The existing Swift app, Share Extensions, and CLI are unchanged.

## Verification Limits

Native builds and headless tests do not establish:

- Signed macOS CloudKit or App Group access.
- iOS interoperability or two-device sync.
- Screen-reader support, IME operation, native focus restoration, or direct paste safety.
- Installer behavior, notarization, or rollback.

Do not remove these gates or mark the rewrite complete without their evidence. Interactive checks must remain in `Scripts/ui_tests.sh` and run only after the complete implementation and all relevant non-interactive checks.
