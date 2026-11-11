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

The frontend uses only `desktop_status`, `search_items`, `get_item`, `create_item`, `update_item`, `apply_item_command`, `rebuild_search`, and `close_preview`. Each Quick Add draft has one `capture_id` UUID. Failed creation retries retain this ID. Edits and lifecycle commands send the authoritative `updated_at` value for optimistic concurrency.

Search submits explicit filters, including the `pinned_only` boolean. Both date boundaries are inclusive UTC dates. To maps to `23:59:59.999999999Z` on the selected day. The backend applies the pinned filter before the 200-result limit. A selected detail and its draft can remain visible outside the current results, but lifecycle actions are disabled. Lifecycle commands also validate result membership before invocation. Pending or failed searches disable lifecycle actions.

## Presentation and evidence

The shared shell has Library navigation, a collection pane, and a detail/editor pane. Narrow work areas stack panes without removing the draft. Search filters use a compact disclosure and removable applied-filter tokens. Clearing filters preserves the search and selected collection. Sidebar queries use backend membership filters; counts and Recently Used are not inferred from the limited result page.

Selection opens read mode. Edit explicitly opens the editor; Cancel uses the existing Save/Discard/Cancel guard. Settings has separate Capture, Paste & Shortcuts, Storage, and Privacy pages. Content previews use text nodes; image/file content and native actions remain unavailable rather than simulated.

Fixtures in `fixtures/` cover all five types and hostile/long content. They are not embedded in the application. DOM tests do not verify CSS layout or native accessibility. See [the parity execution record](../PARITY.md) for the uncompleted gates.

## Draft safety

- Search, selection, settings, Quick Add, discard, and lifecycle transitions require Save, Discard, or Cancel when the draft has changes.
- The in-app dialog does not use browser confirmation prompts. Escape cancels the dialog. Outside the dialog, Escape moves editor focus to Search without deleting changes.
- Save failures retain the draft. A replay with different type, URL, pin, or archive options keeps the complete Quick Add draft and reports the unsaved fields.
  - Save as new item explicitly creates another item. It assigns a new capture ID once. Failed retries retain that ID.
  - Discard changes shows the original saved item. The replay does not change that item.
- A replay with matching creation options uses the returned item as the saved base. Different editable fields remain unsaved and use `update_item` on the next save.
- URL validation applies only to Quick Add link drafts. The URL input is disabled for other drafts and existing-item editing.
- Navigation and lifecycle commands are locked during a save. Text fields remain editable. A completed save does not replace edits made after the request started.
- Search and detail requests use separate generation counters. Stale responses and errors do not replace newer results or details.

## Content restrictions

Saved content is assigned with `textContent` and form values. The frontend does not render captured HTML, create links from saved URLs, load remote previews, fetch resources, execute captured scripts, or open attachments. Image and file items show metadata only. Import, clipboard operations, direct paste, global shortcuts, native quick panel, and attachment content commands are not implemented. Settings show actual backend capabilities and describe these limits. The iCloud capability label is shown only on macOS. Missing attachment names and content types use explicit unavailable placeholders.

The Tauri host owns CSP and command authorization. Do not enable filesystem, shell, network, or clipboard plugins for this frontend.
