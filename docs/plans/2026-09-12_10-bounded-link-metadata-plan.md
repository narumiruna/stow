# Bounded Link Metadata Fetching Plan

## Goal

Enforce metadata and image response limits while bytes are arriving so arbitrary saved links cannot cause unbounded memory growth.

## Context

`LinkMetadataEnricher` uses `URLSession.data` and checks 2 MiB or 5 MiB only after the complete response has been buffered. Multiple large or slow responses can exhaust app resources.

## Architecture

Introduce a small injectable bounded HTTP loader that validates response status and streams at most `limit + 1` bytes before cancelling. Keep metadata enrichment best-effort.

## Non-Goals

- Do not add a general networking layer or cache database.
- Do not execute scripts or render remote HTML.
- Do not change HTML parsing rules.

## Plan

- [ ] Add a bounded asynchronous response loader with explicit byte limit, timeout, accepted status range, and cancellation behavior.
- [ ] Replace page, favicon, and preview-image `data` calls with the loader using their existing 2 MiB and 5 MiB limits.
- [ ] Validate useful content types before parsing HTML or storing image data while retaining safe fallback behavior for missing headers.
- [ ] Inject the loader into `LinkMetadataEnricher` without changing its best-effort caller contract.
- [ ] Add deterministic tests for exact-boundary data, one-byte-over cancellation, misleading Content-Length, chunked oversized responses, timeout, non-success status, and task cancellation.

## Completion Checklist

- [ ] New bounded-loader and enrichment tests pass in `StowAppTests` without external network access.
- [ ] Existing `HTMLMetadataParserTests` pass.
- [ ] macOS and iOS non-interactive builds pass.
- [ ] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ci.sh` passes without invoking UI tests.
- [ ] `git diff --check` passes.
