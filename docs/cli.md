# macOS CLI

The `stow` CLI lets a coding agent use the local Stow library without opening the SwiftData or CloudKit store itself.

[Back to Stow](../README.md)

## Install and remove

Use the [development prerequisites](development.md#prerequisites), then run commands from the repository root.

Build the macOS app and install a symlink for the current user:

```sh
just install-cli
```

The installer's default destination is `~/.local/bin/stow`. It never requests administrator access or edits a shell profile. Add `~/.local/bin` to `PATH` yourself if needed.

Remove the symlink without changing saved Stow data:

```sh
just uninstall-cli
```

## Discover commands

Check the host and discover commands:

```sh
stow status --json
stow help
stow version --json
```

## Add content and retry mutations

Add code through standard input:

```sh
printf 'let answer = 42\n' | \
  stow add --type code --title 'Answer' --language swift --stdin --json
```

Reuse an explicit request ID when a timed-out mutation must be retried:

```sh
request_id="$(uuidgen)"
printf 'idempotent body\n' | \
  stow add --type text --stdin --request-id "$request_id" --json

export_request_id="$(uuidgen)"
stow export ITEM_UUID --request-id "$export_request_id" --json
```

Retry either command with its original request ID and content to recover a response that completed after the caller timed out. This avoids repeating host-side mutation work. Use a new request ID for a different operation.

## Search and retrieve

Search returns compact metadata and bounded snippets. `get` returns the complete text fields and attachment metadata:

```sh
stow search --status inbox --limit 20 --json
stow search 'SwiftData migration' --type code --limit 10 --json
stow get ITEM_UUID --json
```

Replace `ITEM_UUID` and `ATTACHMENT_UUID` in examples with IDs from your library. `get` never inserts Base64 attachment bytes into JSON.

## Export attachments

Export an image or file to a private App Group path that a local coding agent can read:

```sh
stow export ITEM_UUID --json
stow export ITEM_UUID --attachment ATTACHMENT_UUID --json
```

Request a separate destination copy when needed:

```sh
stow export ITEM_UUID --output /tmp/stow-image.png --json
```

An existing destination is preserved unless `--force` is explicit. A directory is never replaced. Sandbox policy can reject an arbitrary destination while leaving the returned App Group export path available.

## Output and errors

JSON mode writes exactly one response document to standard output and writes diagnostics to standard error. It uses ISO 8601 dates and lowercase enums, and never prompts or invokes a pager.

Errors include a stable code, message, retryable flag, and request ID. An export-copy error also includes `fallback_path` for the readable App Group copy.

| Exit code | Meaning |
|---|---|
| 64 | Usage error |
| 65 | Validation failure |
| 66 | Missing content |
| 69 | Host unavailable |
| 70 | Protocol or internal failure |
| 74 | I/O failure |
| 75 | Timeout |

## Access boundary

The CLI supports coding agents on the same Mac and user account only. It does not expose HTTP, remote, SSH, MCP, or iCloud automation access. Run it only when you intend to give the calling process access to the requested library content.

See the [privacy notice](release/privacy.md) for storage and data handling.
