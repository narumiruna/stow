# Project Generation Reproducibility Plan

## Goal

Make Xcode project generation deterministic, non-destructive when checking drift, and enforceable in CI.

## Context

`Scripts/generate_project.rb` deletes `Stow.xcodeproj` immediately and ignores command-line arguments. Regenerating the current clean project produces a large tracked diff, so the generator and committed project are not one reliable source of truth.

## Non-Goals

- Do not add or remove product targets in this PR.
- Do not upgrade Xcode, Swift, Ruby, or `xcodeproj`.
- Do not reformat unrelated project settings.

## Plan

- [ ] Refactor `Scripts/generate_project.rb` so project construction accepts an output path rather than deleting the committed project unconditionally; verify normal generation still creates all current targets and shared schemes.
- [ ] Reconcile generator declarations with intentional settings in the committed `Stow.xcodeproj`; verify one normal generation followed by another produces no diff.
- [ ] Add a real `--check` mode that generates into a temporary directory, compares `project.pbxproj` and shared schemes, reports differing paths, and leaves the working tree untouched.
- [ ] Add script-level tests for unknown arguments, `--check` success, and drift detection using temporary project copies.
- [ ] Add the non-mutating generator check to `Scripts/ci.sh` before Xcode builds.
- [ ] Document normal generation and drift checking in `README.md`.

## Completion Checklist

- [ ] `ruby Scripts/generate_project.rb --check` passes twice from a clean tree without changing `git status`.
- [ ] Generator script tests pass.
- [ ] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ci.sh` passes without invoking UI tests.
- [ ] `git diff --check` passes and generated project changes are explainable and stable.
