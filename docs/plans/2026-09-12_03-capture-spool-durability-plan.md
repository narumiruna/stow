# Capture Spool Durability Plan

## Goal

Preserve valid captures across transient persistence, cleanup, and quarantine failures while keeping malformed payloads from blocking ingestion.

## Context

`CaptureSpool.ingestAll` quarantines every error, including repository save failures. Quarantine failure deletes the source, and interrupted-staging cleanup removes all `.staging-*` directories without an age guard. Immediate attachment saves also process unrelated pending captures and can report failure after the requested capture succeeded.

## Architecture

Separate payload loading/validation from repository persistence. Quarantine only proven-invalid payloads; defer recoverable persistence failures in Pending. Address one requested capture independently from maintenance-wide draining.

## Non-Goals

- Do not change clipboard duplicate semantics.
- Do not change representation repair behavior.
- Do not redesign the share-extension UI.

## Plan

- [ ] Introduce typed per-capture ingestion outcomes for ingested, invalid/quarantined, and deferred/retryable results; preserve capture IDs and actionable messages in tests and callers.
- [ ] Refactor `CaptureSpool` so successfully read but malformed manifests, unsafe paths, invalid sizes, and invalid representations are quarantined, while repository save and filesystem I/O failures leave the source in Pending.
- [ ] Make quarantine failure preserve the original source and report the failed move; remove the delete-on-quarantine-failure fallback.
- [ ] Give every staging attempt a unique temporary directory instead of deleting a deterministic `.staging-<capture-id>` path; verify concurrent attempts for one capture ID cannot delete each other's work.
- [ ] Add age-based interrupted-staging cleanup with an injected clock and a conservative default; prove fresh staging survives while expired staging is removed.
- [ ] Add a focused `ingest(captureID:into:)` path and use it from `AppModel.createAttachment`; verify an unrelated malformed pending capture cannot make a successful current save return false.
- [ ] Add regression tests using a non-writable SwiftData configuration and injected filesystem failures; verify recovery ingests the retained capture exactly once.

## Completion Checklist

- [ ] Capture spool, offline recovery, and new failure-injection tests pass under `swift test --package-path Packages/StowCore`.
- [ ] `StowAppTests` verifies current-capture result reporting independently of unrelated pending work.
- [ ] Existing valid malformed-payload quarantine behavior remains covered.
- [ ] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ci.sh` passes without invoking UI tests.
- [ ] `git diff --check` passes.
