# Capture Replay Consistency Plan

## Goal

Make capture replay preserve newer metadata and intentional user edits while allowing safe repair of genuinely incomplete captures.

## Context

A replayed capture ID restores missing rich representations even when editing intentionally removed them. Clipboard coalescing also overwrites `lastCapturedAt` and `sourceApp` with older events, and fingerprint backfill can stop forever behind attachment-less rows.

## Non-Goals

- Do not change the canonical clipboard fingerprint algorithm.
- Do not reconcile independently synced duplicate items.
- Do not change spool error classification; that belongs to the preceding spool-durability PR.

## Plan

- [ ] Add a repository helper that compares canonical item content with an incoming normalized draft; verify representation repair occurs only when canonical content still matches.
- [ ] Extend representation retry tests to cover an edited text/code item and prove replay cannot restore stale HTML or RTF.
- [ ] Make clipboard coalescing update capture time and source only when the incoming event is at least as new as the stored capture activity; verify reverse-order ingestion keeps the newest metadata.
- [ ] Change fingerprint backfill so `limit` bounds successful updates rather than candidates scanned, allowing the scan to pass attachment-less rows.
- [ ] Add a regression fixture with at least 200 unprocessable rows before a valid item; verify the valid item is fingerprinted and subsequent runs are idempotent.

## Completion Checklist

- [ ] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/StowCore` passes.
- [ ] Tests cover stale representation replay, reverse chronological coalescing, and backfill starvation.
- [ ] Existing capture-ID repair and clipboard coalescing tests continue to pass.
- [ ] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ci.sh` passes without invoking UI tests.
- [ ] `git diff --check` passes.
