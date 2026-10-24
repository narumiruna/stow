# Desktop web frontend

This is the static Tauri 2 frontend. It uses HTML, CSS, and JavaScript ES modules. No framework or asset build is required. Configure Tauri `frontendDist` to use `Desktop/web/public`, not this directory. Test dependencies must not be bundled with the application.

## Checks

Run from `Desktop/web`:

```sh
bun install --frozen-lockfile
bun test
```

`happy-dom` is an exact-version development dependency. Tests run in memory. They do not start a browser, WebView, desktop host, or UI automation. Native accessibility, IME, keyboard, and focus verification remain separate release gates.

## Command boundary

`public/app.js` exports `createApp(invoke, document)`. Its `ready` promise completes the initial status and search requests. Tests inject a command function and a document. `public/main.js` connects it to `window.__TAURI__.core.invoke`.

The frontend uses only `desktop_status`, `search_items`, `get_item`, `create_item`, `update_item`, `apply_item_command`, and `rebuild_search`. Each Quick Add draft has one `capture_id` UUID. Failed creation retries retain this ID. Edits and lifecycle commands send the authoritative `updated_at` value for optimistic concurrency.

Search submits explicit filters, including the `pinned_only` boolean. Both date boundaries are inclusive UTC dates. To maps to `23:59:59.999999999Z` on the selected day. The backend applies the pinned filter before the 200-result limit. A selected detail and its draft can remain visible outside the current results, but lifecycle actions are disabled. Lifecycle commands also validate result membership before invocation. Pending or failed searches disable lifecycle actions.

## Draft safety

- Search, selection, settings, Quick Add, discard, and lifecycle transitions require Save, Discard, or Cancel when the draft has changes.
- The in-app dialog does not use browser confirmation prompts. Escape cancels the dialog. Outside the dialog, Escape moves editor focus to Search without deleting changes.
- Save failures retain the draft. If creation returns `capture_replayed: true`, the returned item becomes the saved base. Different editable draft fields remain unsaved and use `update_item` on the next save. A conflict does not overwrite the saved record. To load its current version, select the item again and explicitly discard the draft.
- Navigation and lifecycle commands are locked during a save. Text fields remain editable. A completed save does not replace edits made after the request started.
- Search and detail requests use separate generation counters. Stale responses and errors do not replace newer results or details.

## Content restrictions

Saved content is assigned with `textContent` and form values. The frontend does not render captured HTML, create links from saved URLs, load remote previews, fetch resources, execute captured scripts, or open attachments. Image and file items show metadata only. Import, clipboard operations, direct paste, global shortcuts, native quick panel, and attachment content commands are not implemented. Settings show actual backend capabilities and describe these limits. The iCloud capability label is shown only on macOS. Missing attachment names and content types use explicit unavailable placeholders.

The Tauri host owns CSP and command authorization. Do not enable filesystem, shell, network, or clipboard plugins for this frontend.
