# macOS Visual Polish

## Goal

Give the macOS Library, Quick Panel, and Settings a calmer, consistent native appearance without changing capture, storage, shortcuts, or item actions.

## Plan

- [x] Inspect macOS views, presentation policies, existing accessibility identifiers, and non-interactive build/test commands.
- [x] Add macOS-only surface and icon components; use semantic colors and increased-contrast borders.
- [x] Refine Library navigation, collection hierarchy, previews, and empty states; test section counts independently of filters.
- [x] Unify Quick Panel cards and Settings groups while retaining existing interaction paths and identifiers.
- [x] Register the new source in the project without changing existing signing settings; rerun the non-interactive quality gate. The final project diff contains only four source-registration lines. `Scripts/ci.sh` passed on 2026-09-12: 117 package tests, 55 app tests, macOS and iOS builds, version tests, and entitlement checks. `git diff --check` also passed.

## Completion Checklist

- [x] Changes remain macOS-only and preserve native list selection and existing actions. macOS Debug build passed; existing identifiers are retained, with added light/dark preview scenarios for the final UI batch.
- [x] All relevant non-interactive checks pass with the final project configuration. Evidence: `/tmp/stow-visual-ci-final.log`.
- [ ] Complete the final macOS UI batch and inspect its light/dark preview screenshots. Blocked: `Scripts/ui_tests.sh macos` exited 77 because macOS Developer Mode is disabled. No UI scenarios ran; enabling Developer Mode requires an external administrator action.
