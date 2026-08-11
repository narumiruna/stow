# Stow Agent-First CLI Plan

## Goal

Add a local macOS `stow` command-line interface that lets coding agents discover, search, retrieve, add, and export Stow content without opening the SwiftData or CloudKit store from a second process.

The CLI must provide stable machine-readable output, non-interactive behavior, idempotent writes, and explicit attachment export so an agent can inspect saved images and files through a local path.

## Context

- `StowRepository` is the authoritative item API, and `SQLiteSearchIndex` supplies the current local search semantics.
- `StowAttachment` stores attachment bytes, content type, safe file name, byte count, and optional image dimensions.
- `AttachmentStore.materialize` already writes attachment bytes atomically into a controlled temporary directory.
- ADR 0002 requires the host app to remain solely responsible for SwiftData and CloudKit access, so the CLI must not open `Stow.store` directly.
- The macOS app normally remains available through its menu bar and already supports launching without presenting the Library window.
- This plan treats the coding agent as an explicitly authorized local process and does not add a network service.

## Architecture

The CLI will be a thin local client, while the running Stow macOS app will execute every library operation.

```text
coding agent
    |
    v
stow CLI
    | atomic versioned request
    v
App Group/Automation/Pending
    |
    v
Stow macOS automation controller
    | StowRepository + SQLiteSearchIndex + AttachmentStore
    v
App Group/Automation/Responses and Exports
    |
    v
stow CLI JSON or text result
```

The shared protocol will use `Codable` request and response envelopes with `schema_version`, `request_id`, timestamps, command payloads, and either `data` or a structured `error` containing `code`, `message`, and `retryable`.

The spool will publish requests and responses with atomic renames, process one request exactly once, reject unsupported schema versions, quarantine malformed input without executing it, and retain completed responses long enough for timeout recovery.

A mutating request will accept `--request-id UUID`, and `add` will reuse that UUID as the `CaptureDraft.id` so a retry cannot create a duplicate even if the first response is lost.

The CLI will check whether `dev.narumi.stow` is running and launch it without activation only when necessary, while an in-app directory watcher will process requests submitted to an already-running app.

The first command surface will be:

```text
stow status [--json]
stow search [QUERY] [--status inbox|archived|trashed|all] [--type TYPE] [--limit N] [--json]
stow get ITEM_ID [--json]
stow add --type text|code|link [--title TITLE] [--language LANGUAGE] [--note NOTE] [--url URL] [--text TEXT|--stdin] [--request-id UUID] [--json]
stow export ITEM_ID [--attachment ATTACHMENT_ID] [--output PATH] [--force] [--json]
stow help
stow version [--json]
```

`search` will accept an optional query so filter-only calls provide listing behavior, while `get` will return full textual fields plus attachment metadata without embedding attachment bytes.

`export` will materialize one attachment under `App Group/Automation/Exports/<request-id>/`, return that local path by default, and optionally let the CLI copy it to `--output` without silently replacing an existing file unless `--force` is present.

If a sandboxed embedded helper cannot write an arbitrary `--output` path, the guaranteed behavior will remain the App Group export path, which a same-user coding agent can read or copy itself.

JSON mode will emit one JSON document on standard output, diagnostics will go to standard error, dates will use ISO 8601, enums will use lowercase stable values, and binary data will never be printed into JSON or encoded as Base64.

Usage errors, missing items, unavailable app installations, protocol failures, and retryable timeouts will use documented nonzero exit codes, and a timeout response will include the request ID needed to retry or recover the completed response.

`list`, `search`, and `get` will not change Recently Used state, while a successful `export` will count as explicit use consistently with the existing Library behavior.

## Tech Stack

- Swift 6.3, Foundation, AppKit, SwiftData, and the existing `StowCore` package will be used without a new third-party command parser.
- Shared protocol, spool, DTO, and testable client logic will live in `Packages/StowCore`.
- The macOS request watcher and command executor will live under `Sources/StowApp/macOS` and call host-owned model and repository operations.
- An executable product named `stow` will be available through SwiftPM for development and embedded as a signed macOS helper through the generated Xcode project.
- `Codable` fixtures, temporary directories, an in-memory `ModelContainer`, and injected launcher and clock dependencies will keep most verification non-interactive.

## Non-Goals

- Do not expose a remote HTTP, SSH, MCP, or cloud API.
- Do not support iOS invocation in this phase.
- Do not let the CLI open or migrate the SwiftData store.
- Do not add update, pin, archive, trash, restore, or permanent-delete commands in the MVP.
- Do not inline Base64 images or arbitrary binary bytes in JSON.
- Do not add prompts, a pager, ANSI-dependent output, a REPL, or a TUI.
- Do not change existing GUI behavior, stored item schema, CloudKit records, or capture limits.

## Assumptions

- The coding agent runs on the same Mac and under the same logged-in user account as Stow.
- Stow is installed or a development app path is supplied before a command that needs the host.
- Explicitly invoking `get` or `export` authorizes the caller to receive the selected private content.
- The existing 100 MB attachment limit remains the maximum exported attachment size.

## Resolved Unknowns

- The entitled embedded helper resolves the App Group and copies exports to caller-selected paths with explicit overwrite protection.
- The generated Xcode project builds a `StowCLI` tool target, embeds it under `Contents/Helpers/stow`, and signs it with the narrow CLI entitlement file.
- Live helper verification confirmed that `NSWorkspace` launch leaves Stow hidden and that concurrent launch requests keep one host process.

## Risks

- A request can finish after the CLI times out, so response caching and request-ID idempotency are required to make retries safe.
- Directory watchers can miss a race between initial draining and subscription, so startup must drain before and immediately after watcher installation.
- Request, response, and exported files contain private content, so they must stay inside the App Group, avoid content logging, use restrictive file behavior, and receive bounded completed-file cleanup.
- A stale search index could return incomplete results, so the host must apply the same fingerprint and rebuild behavior used by the current app before answering search requests.
- CLI-created items might not refresh a visible SwiftUI query if a separate context is used, so automation must reuse host-owned operations or prove same-container propagation with a test.
- A symlinked helper can break if the app moves, so installation must detect the current app path and report a repair command clearly.

## Rollback / Recovery

- Removing the helper target, watcher, and `Automation` directory integration will leave the existing item schema and GUI data unchanged.
- Pending requests will remain atomic until the host accepts them, malformed requests will never reach repository operations, and failed commands will preserve the previous valid store state.
- Completed responses and exports will remain available for a documented recovery interval and then be removed by host maintenance.
- Unsupported future protocol versions will fail explicitly rather than being guessed or partially executed.
- A timed-out mutating command can be retried with the same request ID without duplicating its item.

## Plan

- [x] Create a bounded transport and packaging spike that proves App Group lookup, signed helper embedding, hidden host launch, watcher wake-up, and export-path behavior on macOS; record the selected signing and `--output` behavior in a new CLI automation ADR.
- [x] Add versioned automation request, response, item, attachment, error, and command payload DTOs under `Packages/StowCore/Sources/StowCore`; verify ISO 8601 round trips, unknown-version rejection, stable enum values, and error encoding with focused `StowCoreTests`.
- [x] Add an atomic `AutomationSpool` under `Packages/StowCore/Sources/StowCore` with pending, processing, response, export, and quarantine ownership; verify interrupted writes, duplicate request IDs, malformed input, retry recovery, safe file names, race-resistant draining, and completed-artifact cleanup in temporary-directory tests.
- [x] Add host-facing automation operations to `AppModel` or a focused host service so `status`, filter-only `search`, queried `search`, `get`, `add`, and `export` reuse the existing repository, search-index rebuild semantics, link enrichment, validation, attachment materialization, and successful-use rules; verify each command with an in-memory container in `StowAppTests`.
- [x] Add `Sources/StowApp/macOS/StowAutomationController.swift` to drain and watch the automation spool on app launch, serialize execution on the host, cache responses by request ID, and avoid showing errors in GUI alerts for CLI-only failures; verify startup races, an already-running host, timeout recovery, and no duplicate mutation with non-interactive tests.
- [x] Add the `stow` executable and testable parser/client code under `Packages/StowCore/Sources/StowCLI`, expose it from `Packages/StowCore/Package.swift`, and implement deterministic text and JSON rendering, stdin input, request IDs, timeouts, exit codes, app discovery, non-activating launch, and safe export copying; verify every option and failure path with CLI unit tests and a fake spool responder.
- [x] Update `Scripts/generate_project.rb` and add the narrow CLI entitlement configuration so Xcode builds, signs, and embeds the `stow` helper in the macOS app while leaving iOS and share-extension targets unchanged; regenerate `Stow.xcodeproj` and verify the committed project matches a second generator run.
- [x] Extend `Scripts/verify_entitlements.sh` to inspect the embedded helper and prove it has only the required sandbox and App Group capabilities; verify ad-hoc CI signing and local signed development behavior without committing a team identifier.
- [x] Add `Scripts/install_cli.sh` and `just install-cli` to create or repair a user-authorized `~/.local/bin/stow` symlink without administrator access or blanket shell-profile edits; verify install, repeated install, moved-app diagnostics, and uninstall instructions in a temporary HOME where possible.
- [x] Document the command contract, JSON envelope version, examples for agent stdin usage, image retrieval through `get` plus `export`, privacy boundary, timeout retry flow, PATH setup, and unsupported remote-agent case in `README.md` and the automation ADR; verify every documented command against the built helper.
- [x] Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path Packages/StowCore` and keep the task open until protocol, spool, and CLI tests pass.
- [x] Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Stow.xcodeproj -scheme StowAppTests CODE_SIGNING_ALLOWED=NO test` and keep the task open until host automation tests pass.
- [x] Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ci.sh` and `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/verify_entitlements.sh` and keep the task open until all non-interactive package tests, app tests, builds, static project checks, and entitlement checks pass.
- [ ] After all implementation and non-interactive checks pass, add the accumulated CLI launch and no-focus-steal scenario to the existing macOS UI-test orchestration and run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/ui_tests.sh` once as the final interactive verification batch.
- [x] Perform one final agent-style smoke flow with the embedded helper by adding stdin code, searching it, getting its full content, retrieving image attachment metadata, exporting the image to a readable path, and retrying one mutation with the same request ID; record command output that proves stable IDs, valid JSON, readable bytes, and no duplicate item.

## Verification Evidence

- Package verification passed 78 tests with zero failures on 2026-08-12.
- `StowAppTests` passed 29 tests with zero failures, and `Scripts/ci.sh` completed both platform builds plus entitlement and privacy checks.
- Two consecutive generator runs produced the same committed `Stow.xcodeproj` bytes.
- Temporary-HOME installation repaired a stale managed symlink to an absolute helper path and remained idempotent on the next install.
- Live helper smoke verification returned stable IDs for a retried add, found and fetched the code item, exported a 347,662-byte PNG, refused overwrite with exit 74 and a readable `fallback_path`, preserved the destination, and succeeded with `--force`.
- Concurrent hidden CLI and manual app launches returned a successful status, one Stow process, and `Hidden=true` from Launch Services.
- The final XCTest UI batch is pending because `DevToolsSecurity -status` reports Developer Mode disabled, and XCTest timed out before running a scenario while its automation writer awaited authentication.

## Completion Checklist

- [x] The CLI performs all MVP commands through the host app and never opens `Stow.store`.
- [x] JSON output, exit codes, protocol versioning, timeout recovery, and idempotent add behavior are documented and covered by tests.
- [x] `get` returns image metadata and `export` gives the coding agent a readable local image or file path without Base64 JSON.
- [x] App-not-running and app-already-running flows complete without unwanted activation or visible-window changes.
- [x] The helper is reproducibly built, embedded, signed, verified, and installable without administrator access.
- [x] Existing GUI, CloudKit, share capture, search, privacy, iOS builds, and non-interactive CI behavior remain intact.
- [ ] All non-interactive checks and the single final interactive UI batch pass with recorded evidence.
- [ ] The implemented command surface and image workflow receive explicit user acceptance before this plan is archived.
