# Automation Transport Recovery Plan

## Goal

Recover automation requests during the current app session when response persistence fails after request execution.

## Context

After a claim moves to Processing, `StowAutomationController.drain()` stops on `spool.complete` failure. It then checks only Pending, leaving the request stuck until app restart; retries with the same request ID cannot advance it.

## Architecture

Keep an executed `(claim, response)` as pending completion and retry writing that same response with bounded backoff before claiming more work. Never re-execute the operation during an in-process transport retry.

## Non-Goals

- Do not replace the file-spool protocol.
- Do not add remote automation transport.
- Do not add a new persistence schema for cross-crash mutation receipts in this PR.

## Plan

- [ ] Extract the drain loop behind a minimal spool protocol or injected operations so claim, execute, and completion failures can be controlled in tests.
- [ ] Store a failed completion in memory and retry the identical response with bounded exponential backoff until success, cancellation, or app termination.
- [ ] Ensure pending-completion retry runs before claiming another request and that directory events cannot start a competing drain.
- [ ] Report transport degradation through structured model status while keeping stderr diagnostics free of request content.
- [ ] Add tests proving a transient completion failure does not re-execute the service, eventually creates one response, removes Processing, and allows later requests to drain.
- [ ] Add tests for cancellation and restart recovery, documenting the existing cross-crash idempotency boundary.

## Completion Checklist

- [ ] `StowAutomationSpoolTests`, `StowAutomationHostServiceTests`, and new controller retry tests pass.
- [ ] CLI timeout/retry tests continue to pass.
- [ ] macOS non-interactive build passes.
- [ ] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ci.sh` passes without invoking UI tests.
- [ ] `git diff --check` passes.
