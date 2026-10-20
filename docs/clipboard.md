# macOS Clipboard Details

This reference explains automatic capture and supported original formats. For normal capture and quick panel use, see the [user guide](user-guide.md).

[Back to Stow](../README.md)

## Capture and duplicate matching

While Stow is running, it can automatically save newly copied text, links, images, and regular files to Inbox. Configure monitoring under **Stow → Settings → Capture**. Monitoring starts with the next clipboard change; it ignores content copied before monitoring started.

When automatic monitoring sees the same canonical content again, Stow keeps one item. It preserves edits and lifecycle state, updates the source app and capture activity, and moves the item to the front of Clipboard.

- Text matching normalizes Unicode and line endings but preserves case and meaningful whitespace. Preserved representation identifiers and bytes also participate, so identical visible text with different RTF/HTML formatting can remain separate.
- Links use their normalized HTTP/HTTPS URL.
- Images use original bytes and type.
- Files use bytes and the normalized filename, not the content type.

Matching Trash content is never restored; it creates a new Inbox item. Quick Add, share extensions, and CLI adds still create new items. Independently synced cross-device duplicates are not reconciled.

## Excluded clipboard changes

Before reading payloads, Stow ignores a clipboard change marked with any of these types:

- `org.nspasteboard.ConcealedType`
- `org.nspasteboard.TransientType`
- Stow's own `dev.narumi.stow.owned-content` marker

The concealed and transient identifiers protect content from cooperating password managers and clipboard tools. They are compatibility conventions, not a universal password API. Stow does not guess whether arbitrary secret-looking text is sensitive.

On macOS 15.4 or later, set Stow to **Always Allow** under **System Settings → Privacy & Security → Paste from Other Apps** for reliable background capture. See [Support](release/support.md#common-checks) for capture troubleshooting and the [privacy notice](release/privacy.md) for data handling.

## Preserved original formats

Stow preserves supported original formats from the first pasteboard item, not every format or item advertised by the source app. File handling uses the first file URL; directories are skipped. Regular files have a 100 MiB attachment limit.

| Representation | Limit |
|---|---|
| UTF-8 plain text | 1 MiB |
| RTF | 5 MiB |
| HTML | 5 MiB |
| HTTP/HTTPS URL | 16 KiB |
| PNG or TIFF image | 100 MiB each |
| Total preserved representations per capture | 110 MiB |

App-private formats, RTFD, file promises, and unknown types are not preserved as raw formats. Empty, malformed, and over-limit representations are omitted. PNG is preferred over TIFF when both are available; both image originals are not retained together.

An image that AppKit can read can still be captured through conversion to PNG or TIFF. Thus an unsupported raw format does not always mean that the content itself is rejected.

## Paste behavior

Return, double-click, numbered Use shortcuts, and context-menu **Use** restore supported original formats when available.

Press **Shift-Return** or choose **Paste as Plain Text** for text, code, and links to write only their canonical string. Older items without preserved representations continue to use their type-based paste fallback.

The [user guide](user-guide.md#direct-paste-and-copy-only) explains optional direct paste and the copy-only fallback.
