# Retrieval Panel Decomposition Plan

## Goal

Split the 1,895-line retrieval panel implementation into cohesive files without changing user-visible behavior.

## Context

`RetrievalPanel.swift` combines filtering, selection, keyboard commands, editor transitions, visual components, source-app icon lookup, and AppKit drag infrastructure. Independent state mutation paths have already caused dirty-editor protection gaps.

## Architecture

Keep one feature boundary but separate state/commands from rendering and AppKit adapters. Prefer feature-specific internal types over new public abstractions.

## Non-Goals

- Do not visually redesign the panel.
- Do not change shortcuts, search semantics, paste behavior, or close policy.
- Do not combine this move-only refactor with reliability fixes from earlier PRs.

## Plan

- [ ] Freeze panel behavior with focused tests for selection, filtering, command availability, close layering, editor transitions, and drag completion before moving code.
- [ ] Move retrieval filter/sort/selection derivation into `RetrievalPanelPresentation.swift` as pure functions used by the view.
- [ ] Move toolbar, search controls, timeline card, and popover/editor views into responsibility-named Swift files while preserving accessibility identifiers.
- [ ] Move source-app icons and AppKit drag-source infrastructure into separate adapters with narrow inputs and callbacks.
- [ ] Keep `RetrievalPanelView` as composition and event routing; remove duplicate local helpers exposed by the extraction.
- [ ] Regenerate and check the Xcode project only if required by the project structure, using the non-mutating generator check afterward.

## Completion Checklist

- [ ] The refactor contains no intended behavior or copy changes.
- [ ] `StowAppTests` and macOS build pass.
- [ ] `ruby Scripts/generate_project.rb --check` passes.
- [ ] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ci.sh` passes without invoking UI tests.
- [ ] After all non-interactive checks, `Scripts/ui_tests.sh macos` passes once as the final interactive batch for this PR.
- [ ] `git diff --check` passes.
