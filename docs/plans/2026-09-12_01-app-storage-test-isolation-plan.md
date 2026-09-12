# App Storage Test Isolation Plan

## Goal

Ensure native unit tests and previews cannot read, ingest, mutate, or delete files from a developer's live Stow container.

## Context

`AppModel.connect(_:)` creates capture, metrics, search, and temporary-file services from global paths. `StowAutomationHostServiceTests` connects an in-memory model but therefore still drains the live capture spool.

## Architecture

Introduce a small `StowRuntimePaths` value containing the shared-container and temporary roots. Production uses `.live`; tests construct it from one test-owned directory. Keep service behavior unchanged.

## Non-Goals

- Do not split `AppModel` responsibilities in this PR.
- Do not change capture-spool retry semantics.
- Do not change App Group identifiers or production store locations.

## Plan

- [ ] Add `StowRuntimePaths` beside `StowEnvironment` with explicit shared-container and temporary roots; verify production defaults preserve every current path.
- [ ] Inject `StowRuntimePaths` through `AppModel.init` and replace direct global-path lookups in `connect(_:)`, attachment maintenance, and related setup; verify a test model creates artifacts only below its injected root.
- [ ] Update every `StowAppTests` helper that connects `AppModel` to allocate and clean an isolated directory before connection; verify no test calls `connect(_:)` with live defaults.
- [ ] Add a regression test that places a pending capture in a separate sentinel root, connects an isolated model, and proves the sentinel remains pending and unchanged.
- [ ] Run the hosted `StowAppTests` scheme now that its storage is isolated; verify all tests execute without touching the live App Group or `/tmp/StowDevelopmentAppGroup`.

## Completion Checklist

- [ ] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/StowCore` passes.
- [ ] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Stow.xcodeproj -scheme StowAppTests CODE_SIGNING_ALLOWED=NO test` passes.
- [ ] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ci.sh` passes without invoking UI tests.
- [ ] `git diff --check` passes and the diff contains only runtime-path injection and test-isolation changes.
