# Attachment Materialization Safety Plan

## Goal

Prevent one attachment from overwriting another attachment with the same filename across copy, open, Quick Look, drag, and share workflows.

## Context

`PlatformActions.materialize(_:)` writes every attachment directly to `StowOpen/<filename>`. Two distinct attachments named `report.pdf` therefore share one URL and the later write replaces the earlier bytes.

## Architecture

Create one focused temporary attachment materializer that owns safe names, attachment-specific directories, atomic writes, and cleanup. Reuse it from app actions instead of maintaining parallel implementations.

## Non-Goals

- Do not change persisted attachment data or schema.
- Do not alter clipboard representation selection.
- Do not redesign action buttons or sharing UI.

## Plan

- [ ] Add a reusable materializer under `StowCore` that writes to `<root>/<attachment-id>/<safe-filename>` and rejects empty or unsafe names.
- [ ] Route `PlatformActions`, `StowShareButton`, Quick Look, and file-open paths through the shared materializer; remove duplicate path construction where possible.
- [ ] Align temporary cleanup with the attachment-specific directory layout and verify active files are retained until the existing age threshold expires.
- [ ] Add tests proving distinct same-named attachments receive distinct URLs, preserve both byte sequences, and repeated materialization of one attachment is stable.
- [ ] Add failure tests for empty names and atomic-write errors without deleting an earlier valid materialization.

## Completion Checklist

- [ ] `swift test --package-path Packages/StowCore` passes with materializer tests.
- [ ] `xcodebuild -project Stow.xcodeproj -scheme StowAppTests CODE_SIGNING_ALLOWED=NO test` passes with action-level collision coverage.
- [ ] macOS and iOS non-interactive builds pass.
- [ ] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ci.sh` passes without invoking UI tests.
- [ ] `git diff --check` passes.
