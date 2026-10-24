# iced feasibility probe

This is an isolated Phase 0 sample, **not a production app**. It does not complete Phase 0 or approve `iced` for Stow.

## Scope

- Show three fixed, in-memory Library items, a selectable list, and details.
- Filter title, original content, and type with a case-insensitive search input. Outer search whitespace is ignored.
- Edit a single-line content draft with the keyboard.
- Simulate a failed save without storage. Keep the draft and original item unchanged after failure.
- Reject edits and saves for selections that are missing or excluded by search. Keep the old draft until another item is selected. Selecting the same item keeps its draft.
- Show local-only, in-memory status. No sync settings or cloud integration are present.

There are no application file, network, clipboard, or production-store operations. The root widget supplies a null clipboard to all child widgets, including editable inputs; copy, cut, paste, and primary-selection operations cannot read or write the system clipboard through these widgets. Cut can still remove selected draft text. The wrapper is specific to this sample's widgets and does not support overlays.

`iced` still includes platform clipboard backend dependencies. Its windowing and text-rendering dependencies can initialize operating-system services and load installed fonts. This is not an operating-system sandbox or a claim that dependencies perform no filesystem activity. No links are opened, attachments loaded, or data persisted. All draft changes disappear when the process exits.

## Dependency choice

`cargo info iced@0.14.0` confirmed version 0.14.0, MIT license, and minimum Rust 1.88. The manifest pins this dependency directly, with default features disabled:

- `advanced`: wrap editable widgets with a null clipboard.
- `thread-pool`: required futures executor; no application background jobs are defined.
- `tiny-skia`: software rendering, without the default `wgpu` renderer.
- `x11`, `wayland`: Linux window backends. These features do not prove desktop compatibility.

The workspace lockfile records transitive versions. Resolved framework packages include `iced_widget` 0.14.2, `iced_winit` 0.14.1, and `iced_tiny_skia` 0.14.1. No production Stow crates are dependencies of this sample. Workspace dependency checks pass with one unmaintained `ttf-parser` warning; see `../../VERIFICATION.md`. Distribution notices and bundled native licenses still require review.

## Non-interactive verification

From the repository root, with Bash timeouts set to 300 seconds:

```bash
source "$HOME/.cargo/env"
export CARGO_TARGET_DIR=/tmp/stow-rust-target
cargo fmt --manifest-path Desktop/Cargo.toml -p iced-probe -- --check
cargo check --manifest-path Desktop/Cargo.toml -p iced-probe
cargo test --manifest-path Desktop/Cargo.toml -p iced-probe
cargo clippy --manifest-path Desktop/Cargo.toml -p iced-probe --all-targets -- -D warnings
cargo build --manifest-path Desktop/Cargo.toml -p iced-probe
```

These commands passed on Ubuntu 26.04.1 LTS under WSL2, Linux 6.18.33.2-microsoft-standard-WSL2, x86_64, with Rust/Cargo 1.99.1. Five headless tests cover filtering, stale or removed selection, failed-save draft retention, and item selection. Tests do not create windows or initialize the desktop application. The final development build passed. No UI was launched and no interactive UI tests were run.

## Unproven gates

This sample **cannot prove platform gates**. Native Linux, Windows, and macOS CI release builds and headless tests passed at `fe56e73`; see `../../VERIFICATION.md`. No minimum-Rust build, packaged installation, accessibility, IME, keyboard navigation, high contrast, reduced motion, scaling, multiple-monitor behavior, panel focus restoration, native clipboard support, signed Swift bridge, App Group, Share Extension, CLI, or iCloud compatibility has been verified. WSL compilation is not a native three-platform build result. No performance baseline has been measured.

Keep the existing desktop app. Further platform and signed integration checks remain required by `docs/plans/2026-10-24_rust-cross-platform-desktop-plan.md`.
