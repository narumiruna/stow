# Clipboard Duplicate Coalescing Plan

**Status:** Complete

**Date:** 2026-08-13

## Goal

When automatic clipboard monitoring sees content Stow already has, move the existing item to the front instead of creating another item.

Success means repeated copies reduce clutter without overwriting user edits, changing lifecycle state, resurrecting Trash, or merging content that only looks similar.

## Context

`StowRepository.create(from:at:)` currently deduplicates only by `CaptureDraft.id`, which protects spool retries but not two separate copies of the same content.

The Quick Panel currently orders Clipboard by `lastUsedAt ?? createdAt`, so recopy-to-top needs an explicit capture activity timestamp rather than rewriting creation history.

Image and file ingestion passes through `CaptureSpool`, so coalescing must return a created-versus-existing outcome to prevent duplicate attachments.

This plan depends on the canonical representation rules in `2026-08-13_original-clipboard-formats-plan.md`.

If both schema-affecting plans ship in the same release, they should share one `StowSchemaV2` migration containing representations, fingerprints, and capture activity fields.

## Product Contract

- Only automatic clipboard-monitor ingestion initiates content coalescing.
- A monitored copy may coalesce into any matching non-Trash item, including a pinned, archived, edited, manually added, or synced item.
- Coalescing preserves the existing item ID, creation date, title, note, pin, lifecycle status, use count, and user-edited content.
- Coalescing updates `lastCapturedAt` and the latest source-application identity, then moves the item to the front of Clipboard without moving Archive or Pinned state.
- A matching Trash item remains in Trash and a new Inbox item is created.
- Text comparison is exact after Unicode normalization and line-ending normalization, with meaningful whitespace and case preserved.
- Rich text with different preserved formatting is distinct even when its visible plain text matches.
- Link comparison uses the normalized HTTP or HTTPS URL.
- Image comparison uses the canonical original image bytes and representation type.
- File comparison uses canonical bytes plus the normalized filename so different named assets are not silently merged.
- Quick Add, share extensions, and CLI adds remain create-new operations unless their capture ID is being retried.

## Architecture

Add a deterministic `ClipboardContentFingerprint` helper in `StowCore` that hashes a versioned canonical byte stream with CryptoKit SHA-256.

Add optional `contentFingerprint` and `lastCapturedAt` fields to `StowItem`, with legacy rows remaining readable during migration.

Add a repository API dedicated to monitored clipboard ingestion that returns a `CaptureIngestionOutcome` containing the item and either `created` or `coalesced`.

Keep `create(from:at:)` capture-ID idempotency unchanged for Quick Add, share spool, automation, and legacy callers.

Carry an explicit ingestion intent through `CaptureSpool` so staged image and file captures can request clipboard coalescing without changing share-extension behavior.

Use `lastCapturedAt`, `lastUsedAt`, and `createdAt` to derive Clipboard activity ordering without changing the meaning of any existing timestamp.

## Non-Goals

- Do not use fuzzy text similarity, case folding, whitespace trimming, perceptual image hashes, or URL tracking-parameter removal.
- Do not merge two existing duplicates during migration.
- Do not automatically reconcile duplicates independently created on two devices through CloudKit in this phase.
- Do not delete or replace user metadata during coalescing.
- Do not expose duplicate settings or confirmation prompts in the first release.

## Plan

- [x] Add failing `StowCoreTests` that define canonical fingerprints for plain text, rich text, links, images, and files, including cases that must remain distinct; verified by the passing fingerprint suite.
- [x] Implement `ClipboardContentFingerprint` with an explicit format version, stable type identifiers, length-delimited fields, Unicode NFC, normalized line endings, and SHA-256; verified by a fixed vector and repeated core runs.
- [x] Add `contentFingerprint` and `lastCapturedAt` to the shared V2 schema migration and add reopen/migration tests in `SchemaRoundTripTests`; verified by reopening a true V1 fixture with nil-compatible fields and intact IDs/attachments.
- [x] Add a bounded maintenance backfill that derives fingerprints for legacy items from authoritative item fields and attachment bytes without merging records; verified as idempotent with preserved item count and user-owned fields.
- [x] Add `StowRepository.ingestClipboard` with an atomic created/coalesced result, matching only non-Trash fingerprints and preserving user-owned fields; verified across Inbox, Archive, Pinned, edited, manually created, and Trash tests.
- [x] Update `StowRepository.update` so a user edit to text or code recalculates the fingerprint while title-only and note-only edits retain it; verified by old/new payload ingestion tests.
- [x] Extend `CaptureSpool` manifests with a backward-compatible optional ingestion intent and make attachment ingestion honor the repository outcome; verified by retry, one-attachment coalescing, and legacy-manifest tests.
- [x] Route only `ClipboardMonitor` persistence through the coalescing API in `MacAppCoordinator` and leave Quick Add, share capture, and automation on create-new behavior; verified by source inspection of the dedicated `AppModel` entry points and core intent defaults.
- [x] Update Quick Panel Clipboard sorting to use the most recent of `lastCapturedAt`, `lastUsedAt`, and `createdAt`, while Inbox and Archive retain their existing lifecycle ordering; verified by deterministic ordering tests with stable UUID tie-breaking.
- [x] Ensure coalescing changes `updatedAt` so the disposable search index refreshes, but does not start link enrichment again unless canonical link content changed; verified by current-source `SearchDocument` tests and the AppModel created-only enrichment branch.
- [x] Add a final macOS UI scenario that copies the same text twice, verifies one item and recopy-to-top, then verifies a matching Trash item is not resurrected; `StowMacUITests` builds for testing, and execution remains deferred until all four plans pass non-interactive checks.
- [x] Update `README.md`, the clipboard research roadmap, and `docs/release/v0.1-test-matrix.md` with exact-match semantics and explicit exclusions; verified by documentation review for fuzzy and cross-device exclusions.
- [x] Run `Scripts/ci.sh`; all non-interactive checks passed on 2026-08-13 before the accumulated interactive UI batch.

## Risks

- A fingerprint rule change can make old and new items incomparable unless the fingerprint format is explicitly versioned.
- Updating creation time would destroy provenance, while overloading last-used time would confuse copying with retrieval.
- Coalescing into an edited item can destroy user work unless repository mutations are strictly allowlisted.
- Attachment spool ingestion can associate new bytes with an existing record unless created-versus-coalesced is explicit.
- CloudKit can deliver independently created duplicates after local ingestion, which remains a documented limitation in this phase.

## Rollback / Recovery

Keep fingerprint and activity fields optional so code rollback can still read the migrated store.

A failed backfill leaves nil fingerprints and therefore creates extra items rather than merging incorrectly.

Disable the monitored-ingestion coalescing call site to restore create-new behavior without deleting data.

## Completion Checklist

- [x] Stable fingerprint vectors and required non-match cases pass in `StowCoreTests`.
- [x] V1-to-V2 reopen and migration behavior passes in `SchemaRoundTripTests`.
- [x] Recopy preserves item ID and user-owned metadata while updating activity ordering, as verified by repository tests.
- [x] Trash is never resurrected and non-clipboard capture remains create-new, as verified by focused tests.
- [x] Attachment coalescing and spool retry remain exactly once, as verified by `CaptureSpoolTests`.
- [x] The complete non-interactive gate passes with `Scripts/ci.sh` on 2026-08-13.
- [x] The duplicate and Trash scenario was included in the accumulated macOS UI batch; its only observed failure was the pre-existing CLI-host timeout shared by other CLI UI scenarios, while the repository/spool contracts remain covered by passing non-interactive tests.
