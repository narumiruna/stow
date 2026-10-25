import { editable, newDraft, sameDraft, searchQuery, errorMessage, createOnlyDifferences, collections, collectionFor, filterTokens, relativeDate } from './model.js';

// All privileged operations pass through this injected command boundary.
export function createApp(invoke, document) {
  const $ = (id) => document.getElementById(id);
  const state = {
    available: false, items: [], selected: null, detail: null, draft: null, base: null,
    creating: false, editing: false, saving: false, commandBusy: false, searchGeneration: 0,
    detailGeneration: 0, filters: null, pending: null, searchReady: false, createReplay: null,
  };
  const status = (text) => { $('status').textContent = text; };
  const clearError = () => { $('error').hidden = true; $('error').textContent = ''; };
  const fail = (error) => { $('error').textContent = errorMessage(error); $('error').hidden = false; };
  const dirty = () => state.draft !== null && !sameDraft(state.draft, state.base);
  const createConflicts = () => state.creating && state.createReplay
    ? createOnlyDifferences(state.draft, state.createReplay) : [];
  const createConflictMessage = (fields) => `The item was already saved. Your changes to ${fields.join(', ')} are not saved. Choose Save as new item or Discard changes.`;
  const selectionCurrent = () => state.searchReady && !state.creating && state.detail !== null
    && state.detail.item.id === state.selected && state.items.some((item) => item.id === state.selected);
  const on = (id, event, action) => $(id).addEventListener(event, (e) => {
    try { Promise.resolve(action(e)).catch(fail); } catch (error) { fail(error); }
  });
  function element(tag, text) {
    const node = document.createElement(tag);
    node.textContent = text;
    return node;
  }
  function readFilters() {
    return { text: $('search-text').value, type: $('filter-type').value,
      source: $('filter-source').value, from: $('filter-from').value,
      to: $('filter-to').value, status: $('filter-status').value, pinned: $('filter-pin').checked };
  }
  function restoreFilters() {
    for (const [key, id] of Object.entries({ text: 'search-text', type: 'filter-type', source: 'filter-source', from: 'filter-from', to: 'filter-to', status: 'filter-status' })) {
      $(id).value = state.filters[key];
    }
    $('filter-pin').checked = state.filters.pinned;
  }
  let renderedFilterKey = '';
  function syncFilters() {
    const tokens = filterTokens(state.filters);
    const key = JSON.stringify(tokens);
    if (key !== renderedFilterKey) {
      renderedFilterKey = key;
      $('filter-tokens').replaceChildren(...tokens.map((token) => {
        const button = element('button', `${token.label} ×`);
        button.type = 'button'; button.dataset.filter = token.key;
        button.title = token.label;
        button.setAttribute('aria-label', `Remove ${token.label} filter`);
        button.addEventListener('click', () => { clearFilters(token.clear).catch(fail); });
        return button;
      }));
    }
    $('filter-tokens').hidden = tokens.length === 0;
    $('clear-filters').hidden = tokens.length === 0;
    $('filter-menu').querySelector('summary').textContent = tokens.length ? `Filter (${tokens.length})` : 'Filter';
    for (const button of [...$('filter-tokens').querySelectorAll('button'), $('clear-filters')]) {
      button.disabled = !state.available || state.saving || state.commandBusy;
    }
  }
  async function clearFilters(changes) {
    const accepted = await guarded(async () => {
      state.filters = { ...state.filters, ...changes };
      restoreFilters(); clearError(); await search();
      $('search-text').focus();
    });
    if (!accepted) restoreFilters();
  }
  function syncNavigation() {
    const active = collectionFor(state.filters);
    for (const name of Object.keys(collections)) {
      $(`nav-${name}`).setAttribute('aria-current', active === name ? 'page' : 'false');
      $(`nav-${name}`).disabled = !state.available;
    }
    $('nav-recent').disabled = true;
    $('nav-recent').setAttribute('aria-disabled', 'true');
    $('nav-recent').title = 'Recently Used is not available. Usage ordering is not supported by this backend.';
    const filtered = state.filters.text || state.filters.type || state.filters.source.trim() || state.filters.from || state.filters.to;
    const title = active ? collections[active].title : 'Library';
    $('library-heading').textContent = title;
    $('results-heading').textContent = `${title}${filtered ? ' — Search results' : ''}`;
  }
  function syncButtons() {
    syncNavigation(); syncFilters();
    $('edit-button').hidden = !state.detail || state.creating || state.editing;
    $('edit-button').disabled = !state.available || state.saving || state.commandBusy || !state.detail;
    $('cancel-edit-button').disabled = state.saving || state.commandBusy;
    $('save-button').textContent = state.creating ? 'Save' : 'Save Changes';
    const conflicts = createConflicts();
    $('create-conflict').hidden = conflicts.length === 0;
    $('create-conflict').textContent = conflicts.length ? createConflictMessage(conflicts) : '';
    $('create-new-button').hidden = conflicts.length === 0;
    $('create-new-button').disabled = !state.available || state.saving || state.commandBusy;
    $('save-button').disabled = !state.available || state.saving || !dirty() || conflicts.length > 0;
    $('discard-button').disabled = state.saving || !dirty();
    $('edit-state').textContent = state.saving ? 'Saving… You can continue editing text fields.' : dirty() ? 'Unsaved changes' : 'No unsaved changes';
    for (const id of ['edit-type', 'edit-pin', 'edit-archive']) $(id).disabled = state.saving || state.commandBusy;
    $('edit-url').disabled = state.saving || state.commandBusy || !state.creating || state.draft?.item_type !== 'link';
    for (const id of ['edit-title', 'edit-text', 'edit-note', 'edit-language']) $(id).disabled = state.commandBusy;
    for (const id of ['pin-button', 'archive-button', 'trash-button']) $(id).disabled = !state.available || state.saving || state.commandBusy || !selectionCurrent();
    $('add-button').disabled = !state.available || state.saving || state.commandBusy;
  }
  function renderEditor() {
    $('editor').hidden = !state.draft || (!state.creating && !state.editing);
    if (!state.draft) { syncButtons(); return; }
    const d = state.draft;
    $('editor-heading').textContent = state.creating ? 'Quick Add' : 'Edit item';
    $('create-type-label').hidden = !state.creating;
    $('create-options').hidden = !state.creating;
    $('edit-url-label').hidden = !state.creating || d.item_type !== 'link';
    const type = state.creating ? d.item_type : state.detail.item.item_type;
    $('edit-language-label').hidden = type !== 'code';
    $('edit-text-label').hidden = !['text', 'code'].includes(type);
    for (const [key, id] of Object.entries({ title: 'edit-title', note: 'edit-note', text_content: 'edit-text', language: 'edit-language' })) $(id).value = d[key];
    if (state.creating) {
      $('edit-type').value = d.item_type;
      $('edit-url').value = d.url_string;
      $('edit-pin').checked = d.is_pinned;
      $('edit-archive').checked = d.directly_archive;
    }
    syncButtons();
  }
  function renderDetail() {
    $('item-content').hidden = !state.detail || state.creating;
    if (state.detail && !state.creating) {
      const { item, attachments, representations_count } = state.detail;
      $('item-content').dataset.type = item.item_type;
      $('detail-heading').textContent = item.title || 'Untitled item';
      $('detail-state').textContent = '';
      $('item-meta').textContent = `${item.item_type} · ${item.status}${item.is_pinned ? ' · Pinned' : ''} · Source: ${item.source_app || 'Not recorded'} · Created: ${item.created_at} · Updated: ${item.updated_at}`;
      // Captured HTML, URLs, and names are text only. No links or HTML rendering.
      const types = { link: 'Link', text: 'Text', code: 'Code', image: 'Image', file: 'File' };
      const type = Object.hasOwn(types, item.item_type) ? item.item_type : 'text';
      const preview = $('item-preview');
      preview.className = `typed-preview preview-${type}`;
      const part = (tag, text, className) => {
        const node = element(tag, text); node.className = className; return node;
      };
      preview.replaceChildren(part('p', types[type], `preview-kind type-${type}`));
      if (type === 'link' && item.url_string) preview.append(part('p', item.url_string, 'preview-url'));
      if (item.text_content) preview.append(part(type === 'code' ? 'pre' : 'p', item.text_content, 'preview-body'));
      if (item.link_description) preview.append(part('p', item.link_description, 'preview-description'));
      if (item.file_name) preview.append(part('p', item.file_name, 'preview-file-name'));
      if (type === 'code' && item.language) preview.append(part('p', item.language, 'preview-language'));
      if (['image', 'file'].includes(type)) preview.append(part('p', `${types[type]} preview unavailable. Attachment metadata only.`, 'preview-unavailable'));
      else if (!item.url_string && !item.text_content && !item.link_description) preview.append(part('p', 'No text preview.', 'preview-unavailable'));
      if (item.note) preview.append(part('p', item.note, 'preview-note'));
      $('attachments').replaceChildren(...attachments.map((a) => element('li', `${a.file_name ?? 'File name unavailable'} · ${a.content_type ?? 'Content type unavailable'} · ${a.byte_count} bytes (content unavailable)`)));
      if (!attachments.length) $('attachments').append(element('li', 'No attachments.'));
      $('representation-info').textContent = `Preserved representations: ${representations_count}`;
      $('pin-button').textContent = item.is_pinned ? 'Unpin' : 'Pin';
      $('archive-button').hidden = item.status === 'trashed';
      $('archive-button').textContent = item.status === 'archived' ? 'Restore to Inbox' : 'Archive';
      $('trash-button').textContent = item.status === 'trashed' ? 'Restore from Trash' : 'Move to Trash';
    } else {
      $('detail-heading').textContent = state.creating ? 'Quick Add' : 'Details';
      $('detail-state').textContent = state.creating ? 'Create a text, code, or link item. File and image creation are not available.' : 'Select an item.';
    }
    renderEditor();
  }
  function renderItems() {
    const focusedId = $('items').contains(document.activeElement) ? document.activeElement.dataset.itemId : null;
    const visible = state.items;
    $('items').replaceChildren(...visible.map((item) => {
      const row = document.createElement('li');
      row.className = 'item-row';
      const button = document.createElement('button');
      const types = { link: 'Link', text: 'Text', code: 'Code', image: 'Image', file: 'File' };
      const type = Object.hasOwn(types, item.item_type) ? item.item_type : 'text';
      const icon = element('span', types[type]);
      icon.className = `type-icon type-${type}`;
      const title = element('span', `${item.is_pinned ? 'Pinned · ' : ''}${item.title || 'Untitled item'}`);
      title.className = 'item-title';
      button.append(icon, title);
      button.type = 'button';
      button.dataset.type = type;
      button.dataset.itemId = item.id;
      button.setAttribute('aria-current', String(item.id === state.selected));
      const meta = element('small', `${item.source_app || 'No source'} · ${item.status} · ${relativeDate(item.created_at)}`);
      meta.title = item.created_at;
      meta.className = 'item-meta';
      button.append(meta);
      button.addEventListener('click', () => { guarded(() => select(item.id)).catch(fail); });
      button.addEventListener('keydown', (event) => {
        if (event.isComposing || event.keyCode === 229 || !['ArrowUp', 'ArrowDown'].includes(event.key)) return;
        event.preventDefault();
        const index = visible.findIndex((candidate) => candidate.id === item.id);
        const next = visible[Math.max(0, Math.min(visible.length - 1, index + (event.key === 'ArrowDown' ? 1 : -1)))];
        if (next.id === item.id) return;
        guarded(async () => {
          await select(next.id);
          [...$('items').querySelectorAll('button')].find((b) => b.dataset.itemId === next.id)?.focus();
        }).catch(fail);
      });
      row.append(button);
      return row;
    }));
    if (focusedId) [...$('items').querySelectorAll('button')].find((button) => button.dataset.itemId === focusedId)?.focus();
    // Local selection/editor changes must not turn search errors or loading into empty results.
    if (!state.searchReady) return;
    const filtered = state.filters.text || state.filters.type || state.filters.source.trim() || state.filters.from || state.filters.to;
    const collection = collectionFor(state.filters);
    $('results-state').textContent = visible.length ? `${visible.length} item${visible.length === 1 ? '' : 's'} shown${state.items.length === 200 ? ' (result limit reached; narrow your search)' : ''}.`
      : filtered ? 'No matching items. Change the search or filters.'
      : collection === 'inbox' ? 'Inbox is empty. Use Quick Add to save an item.'
      : `No items in ${collection ? collections[collection].title : 'this collection'}.`;
  }
  async function search() {
    if (!state.available) return;
    const generation = ++state.searchGeneration;
    state.searchReady = false;
    syncButtons();
    $('results-state').textContent = 'Searching…';
    $('items').setAttribute('aria-busy', 'true');
    $('retry-search').hidden = true;
    try {
      const items = await invoke('search_items', { query: searchQuery(state.filters) });
      if (generation !== state.searchGeneration) return;
      state.items = items;
      state.searchReady = true;
      renderItems();
      status('Search complete.');
      // Keep the selected draft even when it is outside the new result set.
    } catch (error) {
      if (generation !== state.searchGeneration) return;
      state.items = [];
      $('items').replaceChildren();
      $('results-state').textContent = 'Search unavailable. Retry or rebuild the index in Settings.';
      $('retry-search').hidden = false;
      fail(error);
    } finally {
      if (generation === state.searchGeneration) {
        $('items').setAttribute('aria-busy', 'false');
        syncButtons();
      }
    }
  }
  async function select(id) {
    if (state.saving || state.commandBusy) return;
    const generation = ++state.detailGeneration;
    state.selected = id; state.creating = false; state.editing = false;
    state.detail = null; state.draft = null; state.base = null; state.createReplay = null;
    renderItems(); renderDetail();
    $('detail-state').textContent = 'Loading item…';
    clearError();
    try {
      const detail = await invoke('get_item', { id });
      if (generation !== state.detailGeneration || state.selected !== id) return;
      state.detail = detail;
      state.draft = editable(detail.item);
      state.base = { ...state.draft };
      renderDetail();
    } catch (error) {
      if (generation !== state.detailGeneration) return;
      $('detail-state').textContent = 'Item unavailable. Select the item again to retry.';
      fail(error);
    }
  }
  async function save() {
    if (!dirty()) return true;
    if (state.saving || !state.available) return false;
    const conflicts = createConflicts();
    if (conflicts.length) { fail(new Error(createConflictMessage(conflicts))); return false; }
    const snapshot = { ...state.draft };
    const creating = state.creating;
    const id = state.selected;
    state.saving = true; syncButtons(); clearError();
    try {
      const detail = await invoke(creating ? 'create_item' : 'update_item', creating
        ? { draft: snapshot }
        : { id, edit: snapshot, expected_updated_at: state.detail.item.updated_at });
      // Keep the complete create draft if the existing item cannot accept it.
      // A new capture ID requires an explicit Save as new item action.
      const replayConflicts = creating && detail.capture_replayed
        ? createOnlyDifferences(state.draft, detail.item) : [];
      if (replayConflicts.length) {
        state.detail = detail; state.createReplay = detail.item;
        renderDetail(); fail(new Error(createConflictMessage(replayConflicts)));
        status('The original item is saved. Your draft is kept.');
        await search();
        return false;
      }
      // Navigation is locked during save, but text may change while invoke runs.
      const unchanged = sameDraft(state.draft, snapshot);
      const remaining = editable(state.draft);
      state.detail = detail; state.selected = detail.item.id; state.creating = false; state.createReplay = null;
      state.base = editable(detail.item);
      const replayDiffers = creating && detail.capture_replayed && !sameDraft(remaining, state.base);
      state.draft = unchanged && !replayDiffers ? { ...state.base } : remaining;
      state.editing = dirty();
      renderDetail();
      status(dirty() ? 'Saved locally. Newer edits are not saved.' : 'Saved locally.');
      await search();
      return !dirty();
    } catch (error) {
      fail(error); status('Save failed. Your draft is retained.');
      return false;
    } finally {
      state.saving = false; syncButtons();
      if (!dirty() && !state.creating && !state.editing && !state.pending) $('edit-button').focus();
    }
  }
  function discard() {
    if (state.creating && state.createReplay) {
      state.selected = state.detail.item.id; state.creating = false; state.createReplay = null;
      state.base = editable(state.detail.item); state.draft = { ...state.base };
      renderItems(); renderDetail();
    } else {
      state.draft = state.base ? { ...state.base } : null;
      renderEditor();
    }
    clearError(); status('Changes discarded.');
  }
  async function guarded(action) {
    if (state.saving || state.commandBusy || state.pending) return false;
    if (dirty()) {
      const dialog = $('unsaved-dialog');
      const focus = document.activeElement;
      const decision = new Promise((resolve) => { state.pending = resolve; });
      $('dialog-error').textContent = '';
      dialog.showModal(); $('dialog-cancel').focus();
      const proceed = await decision;
      state.pending = null; dialog.close();
      if (focus?.isConnected) focus.focus();
      if (!proceed) return false;
    }
    await action();
    return true;
  }
  async function resolveDialog(choice) {
    if (!state.pending) return;
    if (state.saving) return;
    if (choice === 'cancel') { state.pending(false); return; }
    if (choice === 'discard') { discard(); state.pending(true); return; }
    for (const id of ['dialog-save', 'dialog-discard', 'dialog-cancel']) $(id).disabled = true;
    const saved = await save();
    for (const id of ['dialog-save', 'dialog-discard', 'dialog-cancel']) $(id).disabled = false;
    if (saved) state.pending(true);
    else {
      $('dialog-error').textContent = $('error').hidden ? 'Newer edits are not saved. Save again or cancel.' : $('error').textContent;
      $('dialog-cancel').focus();
    }
  }
  function showLibrary() { $('settings').hidden = true; $('library').hidden = false; }
  function quickAdd() {
    ++state.detailGeneration;
    state.selected = null; state.detail = null; state.creating = true; state.editing = true; state.createReplay = null;
    state.draft = newDraft(document.defaultView.crypto.randomUUID());
    state.base = { ...state.draft };
    showLibrary(); renderItems(); renderDetail(); clearError(); $('edit-title').focus();
  }
  async function command(name) {
    if (!selectionCurrent() || !state.available || state.saving || state.commandBusy) return;
    const id = state.selected;
    const revision = state.detail.item.updated_at;
    state.commandBusy = true; syncButtons(); clearError();
    try {
      const detail = await invoke('apply_item_command', { id, command: name, expected_updated_at: revision });
      state.detail = detail; state.base = editable(detail.item); state.draft = { ...state.base };
      renderDetail(); status('Item updated locally.'); await search();
    } catch (error) { fail(error); }
    finally { state.commandBusy = false; syncButtons(); }
  }
  on('search-form', 'submit', async (event) => {
    event.preventDefault();
    const next = readFilters();
    try { searchQuery(next); } catch (error) { fail(error); return; }
    const accepted = await guarded(async () => { state.filters = next; clearError(); await search(); });
    if (!accepted) restoreFilters();
  });
  for (const [name, collection] of Object.entries(collections)) {
    on(`nav-${name}`, 'click', async () => {
      if (!state.available) return;
      const accepted = await guarded(async () => {
        state.filters = { ...state.filters, status: collection.status, pinned: collection.pinned };
        restoreFilters(); syncNavigation(); showLibrary(); clearError(); await search();
      });
      if (!accepted) restoreFilters();
    });
  }
  on('edit-button', 'click', () => {
    if (!state.detail || state.creating || state.saving || state.commandBusy || state.pending || !state.available) return;
    state.editing = true; renderEditor(); $('edit-title').focus();
  });
  on('cancel-edit-button', 'click', () => guarded(() => {
    state.editing = false;
    if (state.creating) {
      ++state.detailGeneration;
      state.creating = false; state.selected = null; state.detail = null;
      state.draft = null; state.base = null; state.createReplay = null;
    }
    renderItems(); renderDetail();
    (state.detail ? $('edit-button') : $('add-button')).focus();
  }));
  on('clear-filters', 'click', () => clearFilters({ type: '', source: '', from: '', to: '' }));
  on('retry-search', 'click', () => guarded(search));
  on('add-button', 'click', () => guarded(quickAdd));
  on('library-button', 'click', () => guarded(() => { showLibrary(); $('search-text').focus(); }));
  // Keep pane navigation local; do not trigger the host's navigation policy.
  for (const link of document.querySelectorAll('a[href^="#"]')) {
    link.addEventListener('click', (event) => {
      const target = $(link.getAttribute('href').slice(1));
      if (!target) return;
      event.preventDefault();
      target.focus();
      target.scrollIntoView({ block: 'nearest' });
    });
  }
  let settingsPage = 'capture';
  function showSettingsPage(name, focus = true) {
    settingsPage = name;
    for (const page of ['capture', 'paste', 'storage', 'privacy']) {
      $(`settings-page-${page}`).hidden = page !== name;
      $(`settings-${page}`).setAttribute('aria-current', page === name ? 'page' : 'false');
    }
    if (focus) {
      const target = $(`settings-page-${name}`);
      target.setAttribute('tabindex', '-1'); target.focus();
    }
  }
  for (const page of ['capture', 'paste', 'storage', 'privacy']) on(`settings-${page}`, 'click', () => showSettingsPage(page));
  showSettingsPage(settingsPage, false);
  on('settings-button', 'click', () => guarded(() => { $('library').hidden = true; $('settings').hidden = false; showSettingsPage(settingsPage); }));
  on('editor', 'submit', (event) => { event.preventDefault(); return save(); });
  on('discard-button', 'click', () => guarded(() => {}));
  on('create-new-button', 'click', () => {
    if (!createConflicts().length || state.saving || state.commandBusy || state.pending || !state.available) return;
    if (!$('editor').reportValidity()) return;
    state.draft.capture_id = document.defaultView.crypto.randomUUID();
    state.base = { ...state.base, capture_id: state.draft.capture_id };
    state.createReplay = null;
    renderEditor();
    return save();
  });
  for (const [id, field] of Object.entries({ 'edit-title': 'title', 'edit-text': 'text_content', 'edit-note': 'note', 'edit-language': 'language', 'edit-url': 'url_string', 'edit-type': 'item_type', 'edit-pin': 'is_pinned', 'edit-archive': 'directly_archive' })) {
    on(id, 'input', () => {
      if (!state.draft || (!state.creating && !state.editing)) return;
      state.draft[field] = $(id).type === 'checkbox' ? $(id).checked : $(id).value;
      if (id === 'edit-type') renderEditor(); else syncButtons();
    });
  }
  on('pin-button', 'click', () => selectionCurrent() && guarded(() => command(state.detail?.item.is_pinned ? 'unpin' : 'pin')));
  on('archive-button', 'click', () => selectionCurrent() && guarded(() => command(state.detail?.item.status === 'archived' ? 'restore_archive' : 'archive')));
  on('trash-button', 'click', () => selectionCurrent() && guarded(() => command(state.detail?.item.status === 'trashed' ? 'restore_trash' : 'trash')));
  for (const choice of ['save', 'discard', 'cancel']) on(`dialog-${choice}`, 'click', () => resolveDialog(choice));
  on('unsaved-dialog', 'cancel', (event) => { event.preventDefault(); return resolveDialog('cancel'); });
  document.addEventListener('keydown', (event) => {
    if (event.isComposing || event.keyCode === 229 || event.key !== 'Escape' || $('unsaved-dialog').open) return;
    // Escape never deletes a draft or triggers a mutation.
    if ($('editor').contains(document.activeElement)) { event.preventDefault(); $('search-text').focus(); }
  });
  on('rebuild-button', 'click', async () => {
    if (!state.available) return;
    $('rebuild-button').disabled = true; clearError(); status('Rebuilding search index…');
    try { await invoke('rebuild_search', {}); status('Search index rebuilt.'); await search(); }
    catch (error) { fail(error); }
    finally { $('rebuild-button').disabled = !state.available; }
  });
  state.filters = readFilters();
  syncButtons();
  const ready = (async () => {
    try {
      const result = await invoke('desktop_status');
      state.available = result.storage_available;
      $('platform-status').textContent = `${result.platform}: ${result.message}`;
      const labels = { local_storage: 'Local storage', icloud: 'iCloud', clipboard_capture: 'Clipboard capture', direct_paste: 'Direct paste', global_shortcut: 'Global shortcut' };
      $('capabilities').replaceChildren(...Object.entries(labels).filter(([key]) => key !== 'icloud' || result.platform === 'macos').flatMap(([key, label]) => [element('dt', label), element('dd', result.capabilities[key] ? 'Available in backend' : 'Unavailable')]));
      $('storage-description').textContent = result.platform === 'macos'
        ? 'Apple storage integration must be verified separately. Local save does not prove iCloud delivery.'
        : 'This library is stored only on this device. Synchronization is not included.';
      $('rebuild-button').disabled = !state.available;
      syncButtons();
      if (state.available) await search();
      else { $('results-state').textContent = 'Storage unavailable. Library actions are disabled.'; status('Storage unavailable.'); }
    } catch (error) {
      $('results-state').textContent = 'Storage status unavailable. Library actions are disabled.';
      status('Desktop backend unavailable.');
      $('platform-status').textContent = 'Desktop backend unavailable. Open this frontend in the Stow desktop host.';
      $('rebuild-button').disabled = true; fail(error);
    }
  })();
  return { ready, requestClose: async () => {
    try { return await guarded(() => invoke('close_preview', {})); }
    catch (error) { fail(error); status('Close failed. Your draft is retained.'); return false; }
  } };
}
