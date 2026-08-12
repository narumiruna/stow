# ADR 0005: Host-Owned CLI Automation

- Status: Accepted
- Date: 2026-08-12

## Decision

Stow provides an agent-first macOS CLI named `stow`, but the CLI never opens the SwiftData or CloudKit store.

The CLI and host exchange versioned, atomic JSON files under the private App Group `Automation` directory, and the running macOS app executes requests through its existing repository and search index.

The initial command surface is `status`, `search`, `get`, `add`, and `export`, with filter-only `search` calls providing listing behavior, deterministic text output, and optional one-document JSON output.

`get` returns full textual content and attachment metadata, while `export` materializes attachment bytes into the App Group and returns a readable local path instead of embedding Base64 data in JSON.

A caller may request an additional copy with `--output`, but a copy failure returns the authoritative App Group export as structured `fallback_path` data.

The CLI checks for a running Stow host and uses `NSWorkspace` with activation disabled to launch the embedded app only when necessary.

Each request has a stable UUID, completed responses are cached, and `add` reuses its request UUID as the capture UUID so timeout retries are idempotent.

## Rationale

ADR 0002 makes the host app solely responsible for SwiftData and CloudKit access because a second process can race the persistent store and bypass host recovery behavior.

A file-backed App Group protocol preserves that ownership, survives either process exiting, works without a network listener, and follows the existing atomic `CaptureSpool` recovery model.

JSON, stdin support, stable exit codes, bounded search snippets, and explicit export paths let coding agents use Stow without terminal prompts, TUI state, or excess context consumption.

## Packaging Evidence

`StowCLI` builds as both a SwiftPM executable product and an Xcode command-line target backed by the same sources.

The generated macOS app embeds the product at `Stow-macOS.app/Contents/Helpers/stow`, and `Scripts/verify_entitlements.sh` proves the embedded helper carries only App Sandbox and `group.dev.narumi.stow` entitlements after signing.

Unsigned Debug builds use the same `StowDevelopmentAppGroup` fallback as the host, while signed builds resolve the real App Group container.

A live helper smoke check confirmed that host launch remains hidden and preserves a single app process, while the matching XCTest UI scenario remains pending until macOS Developer Mode is enabled on the verification machine.

## Protocol and Recovery

Protocol version 1 uses snake-case keys, ISO 8601 dates, lowercase enum values, and a response envelope containing `ok`, `data`, or a structured `error`.

Requests move atomically through `Pending` and `Processing`, malformed requests move to `Quarantine`, and completed responses and exports are removed after 24 hours by periodic maintenance throughout the host lifetime.

A host restart returns interrupted processing files to pending, and an existing response always wins over a duplicate request.

A timeout returns exit code 75 and the request UUID so the caller can repeat a mutating command with `--request-id` without duplication.

## Security and Privacy

The transport remains local to the same macOS user and adds no HTTP, remote, MCP, or cloud endpoint.

Request bodies, responses, and exports remain inside the App Group with owner-only directory and file permissions, and Stow never logs captured content.

Invoking `get` or `export` is treated as explicit authorization for that local caller to receive the selected private content.

## Consequences

Stow must be installed and may be launched in the background for host-backed commands.

The CLI has modest request latency compared with direct SQLite access, but store integrity, CloudKit ownership, search repair, validation, and idempotency remain centralized.

Moving the app can break a user-created CLI symlink, so `Scripts/install_cli.sh` supports repeatable repair without administrator privileges or shell-profile edits.
