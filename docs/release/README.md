# Releases

This directory contains release status, review evidence, metadata, and the maintainer workflow. GitHub releases contain source code only, not installable app binaries.

[Back to Stow](../../README.md)

## Release documents

- [Remaining release checklist](v0.1-external-unblock.md): signing, CloudKit, and distribution work. An internal iOS TestFlight install is recorded; no public installation link is documented.
- [Device and release test matrix](v0.1-test-matrix.md): recorded results and outstanding verification.
- [Scope audit](v0.1-scope-audit.md): v0.1 acceptance evidence.
- [App Store metadata](v0.1-app-store-metadata.md): draft listing text, screenshot requirements, and review notes.
- [Privacy notice](privacy.md) and [Support](support.md): policy and troubleshooting copy.
- [Accessibility audit](v0.1-accessibility-audit.md): accessibility review evidence.
- [Library and Settings visual review](v0.1-library-settings-visual-review.md) and [quick panel visual review](v0.1-quick-panel-visual-review.md): appearance evidence.
- [Screenshot assets](assets): existing release images.

These records do not establish that all current release gates have passed. Review their remaining actions before distribution.

## Version bump and source release

After the release gates pass on `main`, run **Bump Version** from the GitHub Actions page on `main` and choose `patch`, `minor`, or `major`.

The [bump workflow](../../.github/workflows/bump-version.yml) uses `Scripts/bump_version.sh` to update `VERSION` and every Xcode `MARKETING_VERSION`. It atomically pushes one `chore(release)` commit and an annotated `vMAJOR.MINOR.PATCH` tag.

The project generator reads `VERSION` directly. Version bumps do not rewrite its source.

The tag triggers the [Release workflow](../../.github/workflows/release.yml), which runs `Scripts/verify_version.sh` and creates a source-only GitHub release with generated notes.

Check version consistency locally without starting a release:

```sh
Scripts/verify_version.sh
```

Run this command from the repository root. See [Development](../development.md) for build and test commands.

## Token and push recovery

Configure the repository Actions secret `PAT_TOKEN` with repository contents write access. The bump workflow needs this token because events pushed with the built-in `GITHUB_TOKEN` do not start the separate release workflow.

If the atomic push is rejected because `main` changed, rerun **Bump Version** from the latest `main`. Do not force-push the release commit or tag.

## Signing and CloudKit

Keep signing team selection and CloudKit credentials in local Xcode settings; never commit them. A source release does not validate signed archives, private iCloud synchronization, or App Store distribution. Follow the remaining release checklist and test matrix before app distribution.
