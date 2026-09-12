# Share Capture Recovery Plan

## Goal

Allow retry after transient share-save failures and reliably remove extension-owned staging files on failure, cancellation, or teardown.

## Context

`ShareCaptureView` disables Save whenever `errorMessage` is set, including retryable save errors. `ShareCaptureModel` copies provider files before enforcing the size limit and cleans staging only after successful save. Controller-created loading tasks are not retained or cancelled.

## Architecture

Model loading and saving as separate states. Give `ShareCaptureModel` explicit ownership of one staging directory and lifecycle methods for retry and cancellation. Add a native non-UI `StowShareTests` target after project generation is reproducible.

## Non-Goals

- Do not redesign the share-extension form.
- Do not change supported representation precedence.
- Do not change the capture spool protocol.

## Plan

- [ ] Replace the single `errorMessage` gate with distinct load and save failure state; verify a valid loaded draft remains saveable after a transient save error.
- [ ] Inject the share storage root and spool factory so save failure and retry can be tested without the live App Group.
- [ ] Check source file metadata and the 100 MiB limit before copying; clean partially created directories on every load failure.
- [ ] Add explicit `cancel()`/cleanup ownership to the model and invoke it from both share controllers when the request is cancelled or the controller is torn down.
- [ ] Retain and cancel provider-loading tasks in the controllers; ignore late completion after cancellation.
- [ ] Add `StowShareTests` through the project generator and cover retry, oversized input, partial copy failure, cancellation, successful ownership transfer, and late provider completion.

## Completion Checklist

- [ ] `ruby Scripts/generate_project.rb --check` passes.
- [ ] The new non-interactive `StowShareTests` scheme passes on macOS and iOS Simulator where applicable.
- [ ] Existing core capture-spool tests pass.
- [ ] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ci.sh` passes without invoking UI tests.
- [ ] After all non-interactive checks, `Scripts/ui_tests.sh all` passes once as the final interactive batch for this PR.
- [ ] `git diff --check` passes.
