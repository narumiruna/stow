# AppModel Capture and Maintenance Extraction Plan

## Goal

Reduce `AppModel` to observable application state by moving capture ingestion, metrics recording, metadata enrichment scheduling, and maintenance orchestration behind focused services.

## Context

`AppModel.swift` mixes UI state with repository setup, capture creation, spool ingestion, metrics, link enrichment, trash purge, fingerprint backfill, and temporary-file cleanup. This coupling makes error ownership and dependency injection difficult to review.

## Architecture

Introduce a `CaptureService` for create/ingest operations and a `MaintenanceService` for finite startup maintenance. Both receive explicit repository and runtime dependencies. `AppModel` maps typed results into observable UI state.

## Non-Goals

- Do not alter capture, deduplication, retention, or metric semantics.
- Do not redesign views.
- Do not change search behavior; apply the search-extraction plan separately.

## Plan

- [ ] Extract capture creation, attachment staging/ingestion, metrics, and link-enrichment scheduling into `CaptureService` with typed success and failure results.
- [ ] Extract spool draining, trash purge, interrupted-staging cleanup, fingerprint backfill, temporary cleanup, and bounded link maintenance into `MaintenanceService`.
- [ ] Replace repeated `do/catch`, metric, and `presentedError` branches in `AppModel` with small result-mapping methods.
- [ ] Inject both services through the runtime environment established by the test-isolation PR and add isolated service tests for success and partial failure.
- [ ] Verify `AppModel` retains only observable state, repository-facing user actions, and delegation glue; avoid introducing a generic service locator.

## Completion Checklist

- [ ] `swift test --package-path Packages/StowCore` passes.
- [ ] `StowAppTests` passes with capture and maintenance service coverage.
- [ ] macOS and iOS non-interactive builds pass.
- [ ] `AppModel.swift` contains no direct spool, metrics-file, search-file, or temporary-directory construction.
- [ ] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ci.sh` passes without invoking UI tests.
- [ ] `git diff --check` passes.
