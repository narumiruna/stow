# Shared-store capture spike

The production spike is implemented as `CaptureSpool` in `Packages/StowCore` with executable tests in `CaptureSpoolTests`.

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/StowCore --filter CaptureSpoolTests
```

The selected architecture and recovery semantics are recorded in `docs/decisions/0002-capture-persistence.md`.
