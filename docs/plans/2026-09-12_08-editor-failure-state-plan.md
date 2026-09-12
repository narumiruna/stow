# Editor Failure State Plan

## Goal

Keep unsaved edits visible and protected when validation, persistence, or editor-mode transitions fail.

## Context

`StowItemDetailView` exits editing regardless of `AppModel.save` success. Quick-panel keyboard commands can switch editor modes through `showPopover`, which clears dirty state without consulting the close policy.

## Architecture

Define one pure editor transition policy for save, cancel, mode switch, and panel exit. Views render its result instead of mutating dirty state independently.

## Non-Goals

- Do not visually redesign editors.
- Do not split all of `RetrievalPanel.swift` in this PR.
- Do not change repository validation rules.

## Plan

- [ ] Add a pure editor transition model that represents clean, dirty, saving, save-failed, and discard-confirmation states.
- [ ] Update `StowItemDetailView` so editing ends only after a successful save and the complete draft remains available after failure.
- [ ] Route quick-panel Edit, Rename, preview, selection-change, keyboard, and close transitions through the same policy; prevent `showPopover` from clearing dirty state directly.
- [ ] Preserve the existing layered Escape and explicit-close behavior while requiring confirmation for every dirty mode switch.
- [ ] Add unit tests for failed save, Edit-to-Rename, Rename-to-Preview, selection change, Escape, destination close, confirmed discard, and successful save.

## Completion Checklist

- [ ] `StowAppTests` passes with transition-policy coverage and no UI automation.
- [ ] macOS and iOS non-interactive builds pass.
- [ ] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ci.sh` passes without invoking UI tests.
- [ ] After all non-interactive checks, `Scripts/ui_tests.sh all` passes once as the final interactive batch for this PR.
- [ ] `git diff --check` passes.
