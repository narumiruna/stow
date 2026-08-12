# Original Clipboard Formats Plan

**Status:** Implementation complete; final accumulated UI verification pending

**Date:** 2026-08-13

## Goal

Preserve safe original clipboard representations so Return restores formatting by default while a secondary plain-text action remains available.

Success means copied rich text can be pasted back as rich text, image bytes are not needlessly transcoded, legacy items still paste, and unsupported private formats are never persisted merely because a source app advertised them.

## Context

`ClipboardMonitor` currently reads `.string`, converts `NSImage` to PNG or TIFF, and stores only the first file URL.

`CaptureDraft.normalized()` trims text, so leading and trailing whitespace cannot currently be restored exactly.

`PlatformActions.copy` writes plain strings for text, reconstructs images through `NSImage`, and has no original-versus-plain format choice.

`StowAttachment` remains the correct authority for image and file bytes, while safe auxiliary text representations need a separate model.

The sensitive-exclusion plan must land first so concealed data is rejected before any additional representation is read.

The duplicate-coalescing plan should use the representation contract defined here when it computes canonical fingerprints.

## Product Contract

- Return and the existing Use action paste the best preserved original representation set.
- `Shift-Return` and a context-menu action named “Paste as Plain Text” paste only the canonical plain string for text, code, and links.
- Older items without preserved representations continue to paste through the current type-based fallback.
- Text keeps meaningful leading whitespace, trailing whitespace, line endings, and case when at least one non-whitespace character exists.
- The item title and search text may use a trimmed display derivation without mutating stored payload bytes.
- Rich text capture preserves a safe allowlist of plain text, RTF, and HTML representations from the selected pasteboard item.
- Links preserve their canonical HTTP or HTTPS URL plus safe string/URL representations.
- Images prefer existing PNG or TIFF bytes directly and avoid an `NSImage` decode/re-encode unless no safe image representation exists.
- Files continue to copy bytes into Stow-managed storage and preserve one regular file in this phase.
- Unknown custom formats, file promises, RTFD packages, and app-private pasteboard types are ignored.
- Preserved representations obey per-representation and total capture-size limits before persistence or sync.

## Architecture

Add a `StowRepresentation` SwiftData model with item ID, pasteboard type identifier, external-storage data, byte count, ordinal, and creation date.

Use `StowRepresentation` only for safe auxiliary representations that are not already authoritative in `StowItem` or `StowAttachment`.

Add `StowSchemaV2` and a lightweight V1-to-V2 migration containing `StowRepresentation` plus the optional fingerprint/activity fields required by the duplicate plan if both ship together.

Introduce a value-type pasteboard snapshot or reader adapter in the macOS target that enumerates type identifiers and reads allowlisted data only after `ClipboardCapturePolicy` approves the change.

Extend `CaptureSpool` to stage representation files atomically beside the existing manifest and attachment so crash recovery cannot create a partially formatted item.

Add a `PasteFormat` value with `original` and `plainText` cases and keep `PlatformActions` as the only writer to the system pasteboard.

Fetch representations on demand through `AppModel` or the repository when an item is used instead of loading every representation into every timeline card.

## Non-Goals

- Do not preserve every advertised pasteboard type.
- Do not execute or interpret app-private, dynamic, promised-file, or embedded script formats.
- Do not add multiple-file clipboard capture in this phase.
- Do not add a format picker to the persistent toolbar.
- Do not change drag-out formatting in the first implementation.
- Do not convert between RTF and HTML when only one original rich representation exists.
- Do not add Windows or Linux representation compatibility.

## Plan

- [x] Define and document the initial allowlist and limits for plain text, RTF, HTML, URL, PNG, and TIFF, including one maximum per representation and one total capture limit; verified by passing exact-boundary, boundary-plus-one, malformed-data, unknown-type, and protected-marker tests.
- [x] Add `StowCoreTests` for `StowRepresentation`, repository round trips, ordered retrieval, duplicate type rejection, delete/purge cleanup, and V1 store migration; verified by `Scripts/ci.sh` on 2026-08-13.
- [x] Add `StowRepresentation` and `StowSchemaV2` in `Packages/StowCore`, coordinate the same migration with the duplicate plan, and update `StowContainerFactory`; verified by passing `SchemaRoundTripTests` for V1 reopen and V2 representation persistence with stable IDs.
- [x] Add repository APIs that insert all auxiliary representations with an item in one logical ingestion outcome, fetch them in deterministic order, and delete them whenever the owning item is purged; verified by repository rollback, ordering, and purge tests.
- [x] Change text normalization so validation checks a trimmed view for emptiness and title generation but stores the original non-empty payload, then update edit behavior to preserve intentional outer whitespace; verified by passing normalization and representation-edit tests without weakening empty-input rejection.
- [x] Add a pure pasteboard representation selector that chooses safe original image bytes and auxiliary rich-text data without reading unknown types; verified by passing source-ordering, malformed preferred-data, size-limit, unknown-type, and plain-text fallback tests.
- [x] Refactor `ClipboardMonitor` to read through the approved selector after sensitive-marker preflight, stage the canonical attachment without image transcoding when PNG or TIFF bytes exist, and pass auxiliary representations into persistence; verified by injected-reader preflight tests and passing monitor regression tests.
- [x] Extend `CaptureSpool` with backward-compatible optional representation descriptors and generated safe filenames, then validate type, path, declared size, actual size, ordinal uniqueness, and total size during ingestion; verified by passing reopen, interruption, legacy-manifest, duplicate, tamper, and quarantine tests.
- [x] Add `PasteFormat.original` and `PasteFormat.plainText` to `PlatformActions.copy`, writing the Stow-owned marker and all valid original types to one `NSPasteboardItem`; verified by injected-writer legacy fallback, malformed-data, payload-shape, and failed-write tests.
- [x] Route Return, double-click, numbered use, and context-menu Use through `.original`, then add `Shift-Return` and “Paste as Plain Text” through `.plainText` without adding permanent toolbar chrome; verified by source inspection and the shared controller action path.
- [x] Fetch representations only when the selected item is used, and measure the 10,000-item path to ensure rich-representation storage does not load all external blobs during ordinary queries; verified by passing performance tests and a bounded representation-fetch assertion.
- [x] Add a final macOS UI scenario that captures deterministic RTF/HTML, verifies default paste retains formatting, verifies `Shift-Return` produces plain text, and verifies a PNG round-trip keeps its original bytes; scenario is in `StowMacUITests` and execution remains deferred to the one final accumulated batch.
- [x] Update `README.md`, `docs/release/privacy.md`, and `docs/release/v0.1-test-matrix.md` with the allowlist, original/default behavior, plain-text action, storage limits, and unsupported formats; wording states “preserves supported original formats.”
- [x] Run `Scripts/ci.sh`; all non-interactive tests, builds, and entitlement/privacy checks passed on 2026-08-13.

## Risks

- Persisting every advertised type would increase storage, sync, parsing, and privacy exposure without improving common paste workflows.
- Clearing the system clipboard before a representation payload is fully assembled can destroy the user's current clipboard on a failed write.
- Text normalization changes can affect titles, search fingerprints, duplicate behavior, and existing validation assumptions.
- Rich representations can contain external references or malformed content, so Stow should preserve bytes but avoid rendering or transforming them during capture.
- Loading external representation blobs in timeline queries can create severe memory and scrolling regressions.
- A released V2 migration cannot later be rewritten safely, so the duplicate and format fields must be coordinated before shipping.

## Rollback / Recovery

Keep legacy item fields and attachment behavior authoritative so a representation read or write failure can fall back to the current paste path.

Make the new model additive and its relationships ID-based so old records remain readable if representation capture is disabled.

Quarantine incomplete staged captures and never delete their source directories until item, attachment, and representation persistence succeeds.

## Completion Checklist

- [x] The safe representation allowlist and byte limits are enforced by passing boundary and unknown-type tests.
- [x] V1 data reopens and V2 representation data round-trips in passing `SchemaRoundTripTests`.
- [x] Meaningful text whitespace survives capture and paste while whitespace-only input remains rejected, as verified by core tests.
- [x] Default paste writes supported original formats and plain-text paste writes only a string, as verified by injected pasteboard-writer tests.
- [x] Legacy items and malformed auxiliary data use a safe fallback, as verified by action tests.
- [x] Quick Panel queries do not eagerly load all representation blobs, as verified by the bounded fetch/performance assertion.
- [x] The complete non-interactive gate passes with `Scripts/ci.sh` on 2026-08-13.
- [ ] After all four plans are implemented, rich-text, plain-text, image, secret, duplicate, and immediate-search scenarios pass together in one final `Scripts/ui_tests.sh` batch.
