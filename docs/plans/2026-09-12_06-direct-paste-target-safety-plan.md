# Direct Paste Target Safety Plan

## Goal

Guarantee that Stow emits Command-V only when the intended application is still active and eligible for direct paste.

## Context

`DirectPasteService` ignores activation success, waits 140 ms, and posts a global keyboard event without rechecking the frontmost process. Focus changes can paste clipboard content into the wrong application.

## Architecture

Separate target validation, activation, delay, and event posting behind injectable boundaries. Keep the existing pure preflight policy and add a post-activation validation policy.

## Non-Goals

- Do not request Accessibility permission automatically.
- Do not change global shortcuts.
- Do not redesign the quick panel.

## Plan

- [ ] Change direct paste to return an explicit success/fallback result and capture the target process identifier before activation.
- [ ] Inject application activation, frontmost-application lookup, delay, Accessibility state, and Command-V posting so the sequence is deterministic in unit tests.
- [ ] Revalidate that the target is alive, trusted, and frontmost immediately before posting; on mismatch, emit no keyboard events and retain the copied clipboard payload.
- [ ] Update `RetrievalPanelController` to handle the post-close fallback result without claiming a successful direct paste.
- [ ] Add tests for activation failure, target termination, focus switching during the delay, revoked Accessibility access, and the valid target path.

## Completion Checklist

- [ ] `StowAppTests` proves no keyboard event is posted for every invalid post-activation state.
- [ ] macOS non-interactive build passes.
- [ ] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ci.sh` passes without invoking UI tests.
- [ ] After all non-interactive checks, `Scripts/ui_tests.sh macos` passes once as the final interactive batch for this PR.
- [ ] `git diff --check` passes.
