# Search Index Text Binding Plan

## Goal

Index the complete Swift string, including content after embedded NUL characters, without changing normal search semantics.

## Context

`SQLiteSearchIndex.bind` passes `-1` to `sqlite3_bind_text`, so SQLite treats input as NUL-terminated and silently truncates valid text at the first embedded NUL.

## Non-Goals

- Do not change tokenization, ranking, filtering, or query limits.
- Do not rebuild the AppModel search orchestration.
- Do not migrate the SQLite schema.

## Plan

- [ ] Replace NUL-terminated text binding with an explicit UTF-8 byte length and a checked conversion to SQLite's length type.
- [ ] Preserve `SQLITE_TRANSIENT` ownership so bound bytes remain valid after the Swift buffer scope ends.
- [ ] Add a search test whose indexed content contains searchable tokens before and after an embedded NUL; verify both tokens find the document.
- [ ] Add boundary coverage for empty strings, non-ASCII text, and ordinary text to prove existing behavior is unchanged.

## Completion Checklist

- [ ] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/StowCore --filter SearchServiceTests` passes.
- [ ] The complete `StowCore` test suite passes.
- [ ] `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ci.sh` passes without invoking UI tests.
- [ ] `git diff --check` passes and the production change remains limited to SQLite text binding.
