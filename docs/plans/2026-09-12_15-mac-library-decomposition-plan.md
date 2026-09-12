# macOS Library Decomposition Plan

## Goal

Split the 1,116-line macOS Library view into cohesive presentation components without altering Library behavior.

## Context

`MacLibraryView.swift` contains sidebar counts, collection filtering, batch selection, detail actions, edit-sheet state, feedback, drag providers, and window configuration. This makes small behavior changes expensive to review and test.

## Architecture

Retain `MacLibraryView` as the screen-level composition root. Extract pure presentation logic and independent visual components while keeping lifecycle mutations in existing application services.

## Non-Goals

- Do not redesign Library visuals or navigation.
- Do not change search, lifecycle, drag, share, or save behavior.
- Do not refactor the quick panel in the same PR.

## Plan

- [ ] Add focused tests for Library filtering, section sorting, multi-selection actions, failure-preserved drafts, feedback, and attachment lookup before moving code.
- [ ] Move filter summary, empty-state, section sorting, and selection derivation into `MacLibraryPresentation` helpers.
- [ ] Move sidebar, filter bar, collection row, batch detail, item detail, edit sheet, feedback view, drag adapter, and window configurator into responsibility-named files.
- [ ] Reduce `MacLibraryView` to queries, top-level state, composition, and delegation; remove duplicated presentation branches revealed by extraction.
- [ ] Preserve all accessibility identifiers, minimum-size behavior, toolbar placement, and existing test seams.
- [ ] Regenerate and check the project only through the reproducible generator workflow.

## Completion Checklist

- [ ] The refactor contains no intended behavior or user-facing copy changes.
- [ ] `StowAppTests` and macOS build pass.
- [ ] `ruby Scripts/generate_project.rb --check` passes.
- [ ] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ci.sh` passes without invoking UI tests.
- [ ] After all non-interactive checks, `Scripts/ui_tests.sh macos` passes once as the final interactive batch for this PR.
- [ ] `git diff --check` passes.
