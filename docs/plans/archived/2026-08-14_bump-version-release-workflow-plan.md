## Goal

Make the manual semantic-version bump and tag-triggered GitHub release workflows reliable, race-safe, and verifiable for Stow.

## Context

The first `Bump Version` run failed before bumping because the third-party composite action enabled pip caching without a `requirements.txt` or `pyproject.toml`.
The repository already stores the release version in `.bumpversion.toml`, `Scripts/generate_project.rb`, and `Stow.xcodeproj/project.pbxproj`.
A repository `PAT_TOKEN` exists so a workflow-created tag can trigger the separate release workflow.

## Plan

- [x] Replace the failing third-party bump action in `.github/workflows/bump-version.yml` with a pinned uv and `bump-my-version` invocation that validates the dispatch branch, checks out full tag history, bumps all configured version files, creates one release commit and tag, and pushes both atomically; isolated patch/minor/major repositories produced `0.1.1`, `0.2.0`, and `1.0.0`, each with one commit and matching annotated tag.
- [x] Add `Scripts/verify_version.sh` as the shared local/CI release-version invariant and call it from `Scripts/ci.sh`; matching version/tag fixtures passed while malformed tags, mismatched tags, mismatched generator/Xcode values, and malformed configured versions failed.
- [x] Harden `.github/workflows/release.yml` so only strict `vMAJOR.MINOR.PATCH` tags whose tagged files agree can create a release, while using the built-in GitHub token for release creation; local negative fixtures passed and `actionlint` reported no errors.
- [x] Document the release command, PAT requirement, expected commit/tag/release sequence, and retry behavior in `README.md`; the documented **Bump Version** input and **Release** sequence match the workflow files.
- [x] Run non-interactive repository checks, inspect the final diff, and record reusable workflow failure guidance in `MEMORY.md`; `Scripts/ci.sh`, `actionlint`, YAML parsing, shell syntax, `Scripts/verify_version.sh --tag v0.1.0`, and `git diff --check` passed.

## Risks

- A PAT lacking repository contents write access will prevent the atomic push.
- A concurrent change to `main` between checkout and push can reject the release; rerunning against the new head is safer than overwriting it.
- The release workflow creates source-only GitHub releases and does not archive or submit signed Apple application binaries.

## Rollback / Recovery

A failed pre-push bump leaves the remote unchanged.
A rejected atomic push should be rerun from the latest `main`.
If a bad version tag reaches the remote, delete the tag and any corresponding GitHub release before rerunning with the corrected version commit.

## Completion Checklist

- [x] Patch, minor, and major dry runs update `.bumpversion.toml`, `Scripts/generate_project.rb`, and every Xcode `MARKETING_VERSION` consistently in isolated repositories; verified outputs were `0.1.1`, `0.2.0`, and `1.0.0`.
- [x] Both workflow files pass YAML parsing and `actionlint` with no UI-test references.
- [x] Release documentation and `MEMORY.md` match the implemented workflow and observed failure mode.
- [x] The final patch passes `git diff --check` and leaves version `0.1.0` unchanged with no local tag; verified by `Scripts/verify_version.sh --tag v0.1.0` and `git tag --list`.
