import { afterEach, describe, expect, test } from 'bun:test';
import { Window } from 'happy-dom';
import { typedItems, longContent, deniedStorage } from './fixtures/frontend.js';
import { createApp } from './public/app.js';
import { createOnlyDifferences, errorMessage, searchQuery, relativeDate } from './public/model.js';

const markup = await Bun.file(new URL('./public/index.html', import.meta.url)).text();
const windows = [];
afterEach(() => { for (const window of windows.splice(0)) window.happyDOM.abort(); });
const tick = async () => { for (let i = 0; i < 12; i++) await Promise.resolve(); };
const deferred = () => { let resolve, reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; }); return { promise, resolve, reject }; };
const item = (id = 'a', extra = {}) => ({ id, title: `Item ${id}`, item_type: 'text', text_content: `Body ${id}`, note: '', language: '', source_app: 'Editor', created_at: '2026-01-01T00:00:00Z', updated_at: '2026-01-01T00:00:00Z', status: 'inbox', is_pinned: false, ...extra });
const detail = (value = item()) => ({ item: value, attachments: [], representations_count: 0, capture_replayed: false });
async function setup(overrides = {}) {
  const window = new Window({ url: 'http://localhost', settings: { disableJavaScriptEvaluation: true, disableCSSFileLoading: true, disableJavaScriptFileLoading: true } });
  windows.push(window);
  window.document.write(markup);
  const calls = [];
  const handlers = {
    desktop_status: () => ({ storage_available: true, message: 'Local library', platform: 'linux', capabilities: { local_storage: true, icloud: false, clipboard_capture: false, direct_paste: false, global_shortcut: false } }),
    search_items: () => [item(), item('b')], get_item: ({ id }) => detail(item(id)),
    update_item: ({ id, edit }) => detail(item(id, { ...edit, updated_at: '2026-01-02T00:00:00Z' })),
    create_item: ({ draft }) => detail(item('created', draft)),
    apply_item_command: ({ id }) => detail(item(id, { status: 'archived' })),
    rebuild_search: () => null,
    close_preview: () => null,
    ...overrides,
  };
  const app = createApp((name, args) => { calls.push([name, args]); return Promise.resolve().then(() => handlers[name](args)); }, window.document);
  await app.ready;
  const $ = (id) => window.document.getElementById(id);
  const click = async (id) => { $(id).click(); await tick(); };
  // Existing regression cases edit immediately; new read-mode cases use selectReadOnly.
  const input = async (id, value) => { if (id.startsWith('edit-') && $('editor').hidden) { $('edit-button').click(); await tick(); } $(id).value = value; $(id).dispatchEvent(new window.Event('input', { bubbles: true })); await tick(); };
  const selectReadOnly = async (id = 'a') => { [...$('items').querySelectorAll('button')].find((button) => button.dataset.itemId === id).click(); await tick(); };
  const select = async (id = 'a') => { await selectReadOnly(id); if (!$('edit-button').hidden) await click('edit-button'); };
  const search = async () => { $('search-form').dispatchEvent(new window.Event('submit', { cancelable: true, bubbles: true })); await tick(); };
  const save = async () => { $('editor').dispatchEvent(new window.Event('submit', { cancelable: true, bubbles: true })); await tick(); };
  return { window, $, click, input, select, selectReadOnly, search, save, calls, handlers, requestClose: app.requestClose };
}

async function committedLinkWithLostResponse() {
  const saved = new Map();
  let responseLost = false;
  const app = await setup({ create_item: ({ draft }) => {
    if (saved.has(draft.capture_id)) return { ...saved.get(draft.capture_id), capture_replayed: true };
    const result = detail(item(`created-${saved.size + 1}`, {
      capture_id: draft.capture_id, item_type: draft.item_type, title: draft.title,
      text_content: draft.text_content, note: draft.note, language: draft.language,
      url_string: draft.url_string.trim(), is_pinned: draft.is_pinned,
      status: draft.directly_archive ? 'archived' : 'inbox',
    }));
    saved.set(draft.capture_id, result);
    if (!responseLost) { responseLost = true; throw new Error('Committed response lost'); }
    return result;
  } });
  await app.click('add-button'); await app.input('edit-type', 'link');
  await app.input('edit-title', 'Original title'); await app.input('edit-url', 'https://original.example/');
  await app.save();
  return { ...app, saved };
}

describe('query and error model', () => {
  test('uses explicit nullable filters and UTC date boundaries', () => {
    expect(searchQuery({ text: 'abc', type: 'code', source: ' Editor ', from: '2026-01-01', to: '2026-02-01', status: 'trashed' })).toEqual({ text: 'abc', item_type: 'code', source_app: 'Editor', added_after: '2026-01-01T00:00:00Z', added_before: '2026-02-01T23:59:59.999999999Z', status: 'trashed', pinned_only: false, include_trashed: false, limit: 200 });
    expect(() => searchQuery({ from: '2026-02-02', to: '2026-01-01' })).toThrow('From must be on or before To');
  });
  test('accepts one UTC day and includes its final nanosecond', () => {
    const query = searchQuery({ text: '', source: '', from: '2026-02-01', to: '2026-02-01', pinned: true });
    expect(query.added_after).toBe('2026-02-01T00:00:00Z');
    expect(query.added_before).toBe('2026-02-01T23:59:59.999999999Z');
    expect(query.pinned_only).toBe(true);
  });
  test('create-only comparison uses canonical archive state and normalized URL values', () => {
    const original = item('created', { item_type: 'link', url_string: 'https://example.com/', is_pinned: true, status: 'archived' });
    const matching = { item_type: 'link', url_string: ' https://example.com/ ', is_pinned: true, directly_archive: true };
    expect(createOnlyDifferences(matching, original)).toEqual([]);
    expect(createOnlyDifferences({ ...matching, is_pinned: false, directly_archive: false }, original)).toEqual(['pin', 'archive']);
    expect(createOnlyDifferences({ item_type: 'text', url_string: '', is_pinned: false, directly_archive: false }, item('text', { url_string: null }))).toEqual([]);
  });
  test('relative dates retain a safe fallback and deterministic rendering', () => {
    const now = Date.parse('2026-01-02T00:00:00Z');
    expect(relativeDate('2026-01-01T00:00:00Z', now)).toBe('yesterday');
    expect(relativeDate('2026-01-03T00:00:00Z', now)).toBe('tomorrow');
    expect(relativeDate('invalid', now)).toBe('Date unavailable');
  });
  test('formats structured errors without losing conflict codes', () => {
    expect(errorMessage('{"code":"conflict","message":"Reload required","retryable":false}')).toBe('conflict: Reload required');
  });
});

describe('M1 Library presentation', () => {
  test('filter tokens remove applied criteria with draft protection and preserve search and collection', async () => {
    const app = await setup();
    app.$('filter-type').value = 'code'; app.$('filter-source').value = '<script>Editor</script>';
    app.$('filter-from').value = '2026-01-01';
    await app.input('search-text', 'needle'); await app.search();
    expect(app.$('filter-tokens').querySelectorAll('button')).toHaveLength(3);
    expect(app.$('filter-menu').querySelector('summary').textContent).toBe('Filter (3)');
    expect(app.$('filter-tokens').querySelector('script')).toBeNull();
    app.$('filter-tokens').querySelector('[data-filter="source"]').click(); await tick();
    expect(app.calls.filter(([name]) => name === 'search_items').at(-1)[1].query.source_app).toBeNull();
    await app.select(); await app.input('edit-note', 'Retain draft');
    app.$('filter-tokens').querySelector('[data-filter="type"]').click(); await tick();
    await app.click('dialog-cancel');
    expect(app.$('filter-type').value).toBe('code');
    expect(app.$('filter-tokens').querySelectorAll('button')).toHaveLength(2);
    await app.click('clear-filters'); await app.click('dialog-discard');
    expect(app.$('filter-tokens').hidden).toBe(true);
    expect(app.calls.filter(([name]) => name === 'search_items').at(-1)[1].query).toMatchObject({ text: 'needle', status: 'inbox', pinned_only: false, item_type: null, added_after: null, added_before: null });
    expect(app.window.document.activeElement.id).toBe('search-text');
  });
  test('selection starts in read mode; Edit and Quick Add have explicit focus destinations', async () => {
    const app = await setup();
    expect(app.$('editor').hidden).toBe(true);
    await app.selectReadOnly();
    expect(app.$('editor').hidden).toBe(true);
    expect(app.$('item-content').hidden).toBe(false);
    expect(app.$('edit-button').hidden).toBe(false);
    await app.click('edit-button');
    expect(app.$('editor').hidden).toBe(false);
    expect(app.window.document.activeElement.id).toBe('edit-title');
    await app.click('cancel-edit-button');
    expect(app.$('editor').hidden).toBe(true);
    expect(app.$('detail-heading').textContent).toBe('Item a');
    expect(app.window.document.activeElement.id).toBe('edit-button');
    await app.click('add-button');
    expect(app.$('editor').hidden).toBe(false);
    expect(app.$('item-content').hidden).toBe(true);
    expect(app.window.document.activeElement.id).toBe('edit-title');
    await app.click('cancel-edit-button');
    expect(app.$('editor').hidden).toBe(true);
    expect(app.window.document.activeElement.id).toBe('add-button');
  });
  test('successful Save Changes returns to read mode after controls unlock', async () => {
    const app = await setup(); await app.select(); await app.input('edit-title', 'Saved');
    await app.save();
    expect(app.$('editor').hidden).toBe(true);
    expect(app.$('detail-heading').textContent).toBe('Saved');
    expect(app.$('edit-button').disabled).toBe(false);
    expect(app.window.document.activeElement.id).toBe('edit-button');
  });
  test('Cancel Edit shares Save/Discard/Cancel and retains the canonical detail', async () => {
    const app = await setup(); await app.select(); await app.input('edit-title', 'Draft');
    await app.click('cancel-edit-button'); await app.click('dialog-cancel');
    expect(app.$('editor').hidden).toBe(false);
    expect(app.$('edit-title').value).toBe('Draft');
    expect(app.$('detail-heading').textContent).toBe('Item a');
    await app.click('cancel-edit-button'); await app.click('dialog-discard');
    expect(app.$('editor').hidden).toBe(true);
    expect(app.$('detail-heading').textContent).toBe('Item a');
    await app.click('edit-button'); await app.input('edit-title', 'Saved');
    await app.click('cancel-edit-button'); await app.click('dialog-save');
    expect(app.$('editor').hidden).toBe(true);
    expect(app.$('detail-heading').textContent).toBe('Saved');
  });
  test('failed Cancel Edit save keeps the editor and dialog open', async () => {
    const app = await setup({ update_item: () => { throw new Error('Disk denied'); } });
    await app.select(); await app.input('edit-note', 'Keep');
    await app.click('cancel-edit-button'); await app.click('dialog-save');
    expect(app.$('editor').hidden).toBe(false);
    expect(app.$('unsaved-dialog').open).toBe(true);
    expect(app.$('dialog-error').textContent).toContain('Disk denied');
    expect(app.$('edit-note').value).toBe('Keep');
  });
  test('collections issue server-side membership filters without fake counts or recent approximation', async () => {
    const app = await setup();
    for (const [name, status, pinned] of [['inbox', 'inbox', false], ['pinned', null, true], ['archive', 'archived', false], ['trash', 'trashed', false]]) {
      await app.click(`nav-${name}`);
      expect(app.calls.filter(([command]) => command === 'search_items').at(-1)[1].query).toMatchObject({ status, pinned_only: pinned, include_trashed: false });
      expect(app.$(`nav-${name}`).getAttribute('aria-current')).toBe('page');
      expect(app.$('results-heading').textContent.toLowerCase()).toContain(name);
    }
    const count = app.calls.length;
    expect(app.$('nav-recent').disabled).toBe(true);
    await app.click('nav-recent');
    expect(app.calls).toHaveLength(count);
    expect(app.calls.some(([name]) => name === 'get_item')).toBe(false);
  });
  test('navigation retains filters and restores canceled filter changes and selected collection', async () => {
    const app = await setup(); await app.click('nav-inbox'); await app.select();
    await app.input('edit-title', 'Draft');
    await app.click('nav-pinned'); await app.click('dialog-cancel');
    expect(app.$('nav-inbox').getAttribute('aria-current')).toBe('page');
    expect(app.$('filter-status').value).toBe('inbox');
    expect(app.$('filter-pin').checked).toBe(false);
    await app.click('nav-pinned'); await app.click('dialog-discard');
    expect(app.$('nav-pinned').getAttribute('aria-current')).toBe('page');
    app.$('filter-status').value = 'archived'; app.$('filter-pin').checked = false;
    await app.input('search-text', 'needle'); await app.search();
    expect(app.$('nav-archive').getAttribute('aria-current')).toBe('page');
    expect(app.$('results-heading').textContent).toBe('Archive — Search results');
    await app.click('nav-trash');
    expect(app.calls.filter(([name]) => name === 'search_items').at(-1)[1].query.text).toBe('needle');
  });
  for (const fixture of typedItems) {
    test(`${fixture.item_type} uses safe typed read presentation without per-row detail requests`, async () => {
      const app = await setup({ search_items: () => typedItems.map((value) => item(value.id, value)), get_item: ({ id }) => detail(item(id, fixture)) });
      expect(app.calls.map(([name]) => name)).toEqual(['desktop_status', 'search_items']);
      await app.selectReadOnly(fixture.id);
      expect(app.$('editor').hidden).toBe(true);
      expect(app.$('item-preview').classList.contains(`preview-${fixture.item_type}`)).toBe(true);
      expect(app.$('item-preview').textContent).toContain(longContent);
      expect(app.$('item-preview').querySelector('img,script,a,iframe')).toBeNull();
      expect(app.$('item-preview').querySelector('.preview-kind').textContent.toLowerCase()).toBe(fixture.item_type);
      expect(app.$('items').querySelectorAll('.type-icon')).toHaveLength(5);
      expect(app.calls.filter(([name]) => name === 'get_item')).toHaveLength(1);
      if (['image', 'file'].includes(fixture.item_type)) expect(app.$('item-preview').textContent).toContain('Attachment metadata only');
    });
  }
  test('empty collection, no matches, failed search, and unavailable storage are distinct', async () => {
    const app = await setup({ search_items: () => [] });
    expect(app.$('results-state').textContent).toContain('Inbox is empty');
    await app.click('nav-trash'); expect(app.$('results-state').textContent).toContain('No items in Trash');
    await app.input('search-text', 'missing'); await app.search();
    expect(app.$('results-state').textContent).toContain('No matching items');
    app.handlers.search_items = () => { throw new Error('Index unavailable'); };
    await app.search(); expect(app.$('results-state').textContent).toContain('Search unavailable');
    expect(app.$('retry-search').hidden).toBe(false);
    await app.click('add-button');
    expect(app.$('results-state').textContent).toContain('Search unavailable');
    const denied = await setup({ desktop_status: () => deniedStorage });
    expect(denied.$('results-state').textContent).toContain('Storage unavailable');
    expect(denied.$('retry-search').hidden).toBe(true);
    expect(denied.$('nav-inbox').disabled).toBe(true);
    expect(denied.calls.map(([name]) => name)).toEqual(['desktop_status']);
  });
  test('Settings pages have one active target and focus; capabilities stay read-only', async () => {
    const app = await setup(); await app.click('settings-button');
    for (const name of ['paste', 'storage', 'privacy', 'capture']) {
      await app.click(`settings-${name}`);
      expect(app.$(`settings-${name}`).getAttribute('aria-current')).toBe('page');
      expect(app.window.document.activeElement.id).toBe(`settings-page-${name}`);
      for (const page of ['capture', 'paste', 'storage', 'privacy']) expect(app.$(`settings-page-${page}`).hidden).toBe(page !== name);
    }
    expect(app.$('capabilities').querySelector('input,button,select')).toBeNull();
    expect(app.$('settings').textContent).not.toContain('iCloud');
  });
});

describe('headless application controller', () => {
  test('IME key events do not move editor focus or change list selection', async () => {
    const app = await setup(); await app.select();
    app.$('edit-note').focus();
    app.$('edit-note').dispatchEvent(new app.window.KeyboardEvent('keydown', { key: 'Escape', isComposing: true, bubbles: true }));
    expect(app.window.document.activeElement.id).toBe('edit-note');
    const before = app.calls.filter(([name]) => name === 'get_item').length;
    app.$('items').querySelector('button').dispatchEvent(new app.window.KeyboardEvent('keydown', { key: 'ArrowDown', isComposing: true, bubbles: true }));
    await tick();
    expect(app.calls.filter(([name]) => name === 'get_item')).toHaveLength(before);
    expect(app.$('detail-heading').textContent).toBe('Item a');
  });
  test('pane links move focus without navigating the embedded origin', async () => {
    const app = await setup();
    for (const link of app.window.document.querySelectorAll('a[href^="#"]')) {
      const target = link.getAttribute('href').slice(1);
      link.click(); await tick();
      expect(app.window.document.activeElement.id).toBe(target);
      expect(app.window.location.hash).toBe('');
    }
    expect(app.$('library-heading').textContent).toBe('Inbox');
    await app.click('nav-pinned');
    expect(app.$('library-heading').textContent).toBe('Pinned');
  });
  test('native close uses the draft guard and waits for an active save', async () => {
    const app = await setup(); await app.select(); await app.input('edit-title', 'Retain me');
    const canceled = app.requestClose(); await tick();
    expect(app.$('unsaved-dialog').open).toBe(true);
    await app.click('dialog-cancel'); await canceled;
    expect(app.calls.filter(([name]) => name === 'close_preview')).toHaveLength(0);
    const pending = deferred(); app.handlers.update_item = () => pending.promise;
    await app.save();
    await app.requestClose();
    expect(app.calls.filter(([name]) => name === 'close_preview')).toHaveLength(0);
    pending.resolve(detail(item('a', { title: 'Retain me' }))); await tick();
    await app.input('edit-note', 'Discard by explicit choice');
    const discarded = app.requestClose(); await tick();
    await app.click('dialog-discard'); await discarded;
    expect(app.calls.filter(([name]) => name === 'close_preview')).toHaveLength(1);
  });
  test('native close command failure is visible instead of trapping the window silently', async () => {
    const app = await setup({ close_preview: () => { throw new Error('Native close failed'); } });
    expect(await app.requestClose()).toBe(false);
    expect(app.$('error').textContent).toContain('Native close failed');
    expect(app.$('status').textContent).toContain('Close failed');
  });
  test('loads summary list and renders hostile captured content only as text', async () => {
    const hostile = '<script>globalThis.pwned=true</script><img src="https://remote.invalid/pixel">';
    const app = await setup({ get_item: () => detail(item('a', { title: hostile, text_content: hostile, url_string: 'javascript:alert(1)' })) });
    await app.select();
    expect(app.$('item-preview').textContent).toContain(hostile);
    expect(app.$('item-preview').querySelector('script,img,a')).toBeNull();
    expect(app.$('detail-heading').textContent).toBe(hostile);
    expect(app.window.pwned).toBeUndefined();
    expect(app.$('storage-description').textContent).toContain('only on this device');
  });
  test('link details expose only fields supported by the update command', async () => {
    const app = await setup({ get_item: () => detail(item('a', { item_type: 'link', url_string: 'https://example.com', text_content: 'Captured description' })) });
    await app.select();
    expect(app.$('edit-text-label').hidden).toBe(true);
    expect(app.$('edit-url-label').hidden).toBe(true);
    expect(app.$('item-preview').textContent).toContain('Captured description');
    await app.input('edit-note', 'New note'); await app.save();
    expect(app.calls.find(([name]) => name === 'update_item')[1].edit.note).toBe('New note');
  });
  test('keeps drafts on failed save with optimistic concurrency revision', async () => {
    const app = await setup({ update_item: () => { throw { code: 'conflict', message: 'Changed elsewhere', retryable: false }; } });
    await app.select(); await app.input('edit-title', 'Draft'); await app.save();
    expect(app.$('edit-title').value).toBe('Draft');
    expect(app.$('error').textContent).toContain('conflict');
    expect(app.calls.find(([name]) => name === 'update_item')[1]).toEqual({ id: 'a', edit: { title: 'Draft', note: '', text_content: 'Body a', language: '' }, expected_updated_at: '2026-01-01T00:00:00Z' });
    expect(app.$('save-button').disabled).toBe(false);
  });
  test('selection changes require explicit cancel, discard, or save', async () => {
    const app = await setup(); await app.select(); await app.input('edit-title', 'Draft');
    await app.select('b'); expect(app.$('unsaved-dialog').open).toBe(true);
    await app.click('dialog-cancel'); expect(app.$('edit-title').value).toBe('Draft');
    await app.select('b'); await app.click('dialog-discard');
    expect(app.$('edit-title').value).toBe('Item b');
    await app.input('edit-title', 'Saved b'); await app.select('a'); await app.click('dialog-save');
    expect(app.$('edit-title').value).toBe('Item a');
    expect(app.calls.filter(([name]) => name === 'update_item')).toHaveLength(1);
  });
  test('failed dialog save does not navigate or lose a draft', async () => {
    const app = await setup({ update_item: () => { throw new Error('Disk full'); } });
    await app.select(); await app.input('edit-note', 'Keep me'); await app.select('b'); await app.click('dialog-save');
    expect(app.$('unsaved-dialog').open).toBe(true);
    expect(app.$('dialog-error').textContent).toContain('Disk full');
    expect(app.$('edit-note').value).toBe('Keep me');
    expect(app.calls.filter(([name]) => name === 'get_item')).toHaveLength(1);
    await app.click('dialog-cancel'); expect(app.$('unsaved-dialog').open).toBe(false);
  });
  test('search filters require a decision and canceled filters are restored', async () => {
    const app = await setup(); await app.select(); await app.input('edit-title', 'Draft');
    await app.input('search-text', 'next'); app.$('filter-type').value = 'code'; await app.search();
    expect(app.$('unsaved-dialog').open).toBe(true);
    await app.click('dialog-cancel'); expect(app.$('search-text').value).toBe(''); expect(app.$('filter-type').value).toBe('');
    expect(app.calls.filter(([name]) => name === 'search_items')).toHaveLength(1);
    await app.input('search-text', 'next'); await app.search(); await app.click('dialog-discard');
    expect(app.calls.filter(([name]) => name === 'search_items').at(-1)[1].query.text).toBe('next');
  });
  test('older search responses and errors cannot replace newer results', async () => {
    const old = deferred(), next = deferred();
    const app = await setup();
    app.handlers.search_items = ({ query }) => query.text === 'old' ? old.promise : next.promise;
    await app.input('search-text', 'old'); await app.search();
    await app.input('search-text', 'new'); await app.search();
    next.resolve([item('new')]); await tick(); old.reject(new Error('Stale failure')); await tick();
    expect(app.$('items').textContent).toContain('Item new');
    expect(app.$('error').hidden).toBe(true);
    expect(app.$('items').getAttribute('aria-busy')).toBe('false');
  });
  test('late details cannot overwrite another selection or Quick Add', async () => {
    const first = deferred();
    const app = await setup({ get_item: ({ id }) => id === 'a' ? first.promise : detail(item(id)) });
    await app.select(); await app.select('b'); first.resolve(detail()); await tick();
    expect(app.$('edit-title').value).toBe('Item b');
    const later = deferred(); app.handlers.get_item = () => later.promise;
    await app.select(); await app.click('add-button'); later.resolve(detail()); await tick();
    expect(app.$('editor-heading').textContent).toBe('Quick Add'); expect(app.$('edit-title').value).toBe('');
  });
  test('save keeps edits made while request is in flight and advances revision', async () => {
    const pending = deferred(); const app = await setup({ update_item: () => pending.promise });
    await app.select(); await app.input('edit-title', 'Snapshot'); await app.save();
    await app.input('edit-title', 'Newer'); await app.select('b');
    expect(app.$('unsaved-dialog').open).toBe(false);
    pending.resolve(detail(item('a', { title: 'Snapshot', updated_at: 'revision-2' }))); await tick();
    expect(app.$('edit-title').value).toBe('Newer'); expect(app.$('save-button').disabled).toBe(false);
    app.handlers.update_item = ({ edit }) => detail(item('a', edit)); await app.save();
    expect(app.calls.filter(([name]) => name === 'update_item').at(-1)[1].expected_updated_at).toBe('revision-2');
  });
  test('Quick Add retains capture ID after failure and newer edits after save', async () => {
    const app = await setup({ create_item: () => { throw new Error('Response lost'); } });
    await app.click('add-button'); app.$('edit-type').value = 'code'; app.$('edit-type').dispatchEvent(new app.window.Event('input'));
    await app.input('edit-text', 'print(1)'); await app.save(); await app.save();
    const creates = app.calls.filter(([name]) => name === 'create_item');
    expect(creates).toHaveLength(2); expect(creates[0][1].draft.capture_id).toBe(creates[1][1].draft.capture_id);
    expect(creates[0][1].draft.capture_id).toMatch(/^[0-9a-f-]{36}$/);
    const pending = deferred(); app.handlers.create_item = () => pending.promise;
    await app.save(); await app.input('edit-note', 'New note');
    pending.resolve(detail(item('created', { item_type: 'code', text_content: 'print(1)' }))); await tick();
    expect(app.$('edit-note').value).toBe('New note'); expect(app.$('editor-heading').textContent).toBe('Edit item');
    expect(app.$('save-button').disabled).toBe(false);
  });
  test('replayed create keeps a changed retry draft and uses the canonical revision', async () => {
    let canonical;
    const app = await setup({ create_item: ({ draft }) => {
      if (!canonical) {
        canonical = detail(item('created', { ...draft, updated_at: 'canonical-revision' }));
        throw new Error('Committed response lost');
      }
      return { ...canonical, capture_replayed: true };
    } });
    await app.click('add-button'); await app.input('edit-title', 'A'); await app.save();
    await app.input('edit-title', 'B'); await app.save();
    const creates = app.calls.filter(([name]) => name === 'create_item');
    expect(creates[0][1].draft.capture_id).toBe(creates[1][1].draft.capture_id);
    expect(app.$('detail-heading').textContent).toBe('A');
    expect(app.$('edit-title').value).toBe('B');
    expect(app.$('editor-heading').textContent).toBe('Edit item');
    expect(app.$('save-button').disabled).toBe(false);
    await app.save();
    expect(app.calls.find(([name]) => name === 'update_item')[1]).toMatchObject({ id: 'created', edit: { title: 'B' }, expected_updated_at: 'canonical-revision' });
    expect(app.$('save-button').disabled).toBe(true);
  });
  for (const [field, control, value] of [
    ['URL', 'edit-url', 'https://replacement.example/'],
    ['type', 'edit-type', 'code'],
    ['pin', 'edit-pin', true],
    ['archive', 'edit-archive', true],
  ]) {
    test(`replayed create retains changed ${field} until Save as new item is chosen`, async () => {
      const app = await committedLinkWithLostResponse();
      if (typeof value === 'boolean') {
        app.$(control).checked = value;
        app.$(control).dispatchEvent(new app.window.Event('input'));
      } else { await app.input(control, value); }
      if (field === 'type') await app.input('edit-text', 'Retained code');
      await app.save();
      expect(app.$('editor-heading').textContent).toBe('Quick Add');
      expect(typeof value === 'boolean' ? app.$(control).checked : app.$(control).value).toBe(value);
      expect(app.$('create-conflict').textContent).toContain('already saved');
      expect(app.$('create-new-button').hidden).toBe(false);
      const creates = app.calls.filter(([name]) => name === 'create_item');
      expect(creates).toHaveLength(2);
      expect(creates[0][1].draft.capture_id).toBe(creates[1][1].draft.capture_id);
      expect(app.calls.some(([name]) => name === 'update_item' || name === 'apply_item_command')).toBe(false);
      expect(app.saved.size).toBe(1);
      await app.click('create-new-button');
      const final = app.calls.filter(([name]) => name === 'create_item').at(-1)[1].draft;
      expect(final.capture_id).not.toBe(creates[0][1].draft.capture_id);
      expect(app.saved.size).toBe(2);
      expect(final[({ URL: 'url_string', type: 'item_type', pin: 'is_pinned', archive: 'directly_archive' })[field]]).toBe(value);
      expect(app.$('editor-heading').textContent).toBe('Edit item');
    });
  }
  test('an unresolved replay cannot send repeated creates or close through dialog Save', async () => {
    const app = await committedLinkWithLostResponse();
    await app.input('edit-url', 'https://replacement.example/'); await app.save();
    await app.save();
    expect(app.calls.filter(([name]) => name === 'create_item')).toHaveLength(2);
    const closing = app.requestClose(); await tick(); await app.click('dialog-save');
    expect(app.$('unsaved-dialog').open).toBe(true);
    expect(app.$('dialog-error').textContent).toContain('Save as new item');
    expect(app.calls.some(([name]) => name === 'close_preview')).toBe(false);
    await app.click('dialog-cancel'); await closing;
    expect(app.$('edit-url').value).toBe('https://replacement.example/');
  });
  test('a failed explicit new-item save keeps its new ID for safe retry', async () => {
    const app = await committedLinkWithLostResponse();
    await app.input('edit-url', 'https://replacement.example/'); await app.save();
    const originalId = app.calls.filter(([name]) => name === 'create_item')[0][1].draft.capture_id;
    const create = app.handlers.create_item;
    app.handlers.create_item = (args) => {
      const response = create(args);
      if (!response.capture_replayed) throw new Error('Second committed response lost');
      return response;
    };
    await app.click('create-new-button');
    expect(app.$('error').textContent).toContain('Second committed response lost');
    expect(app.$('edit-url').value).toBe('https://replacement.example/');
    const newId = app.calls.filter(([name]) => name === 'create_item').at(-1)[1].draft.capture_id;
    expect(newId).not.toBe(originalId);
    await app.save();
    expect(app.calls.filter(([name]) => name === 'create_item').at(-1)[1].draft.capture_id).toBe(newId);
    expect(app.saved.size).toBe(2);
    expect(app.$('editor-heading').textContent).toBe('Edit item');
    expect(app.$('save-button').disabled).toBe(true);
  });
  test('discard after a failed explicit new-item save does not restore the old capture ID', async () => {
    const app = await committedLinkWithLostResponse();
    await app.input('edit-url', 'https://replacement.example/'); await app.save();
    const create = app.handlers.create_item;
    app.handlers.create_item = (args) => {
      const response = create(args);
      if (!response.capture_replayed) throw new Error('Second response lost');
      return response;
    };
    await app.click('create-new-button');
    const newId = app.calls.filter(([name]) => name === 'create_item').at(-1)[1].draft.capture_id;
    await app.click('discard-button'); await app.click('dialog-discard');
    await app.input('edit-type', 'link'); await app.input('edit-title', 'Original title');
    await app.input('edit-url', 'https://replacement.example/'); await app.save();
    expect(app.calls.filter(([name]) => name === 'create_item').at(-1)[1].draft.capture_id).toBe(newId);
    expect(app.saved.size).toBe(2);
    expect(app.$('editor-heading').textContent).toBe('Edit item');
  });
  test('create-only replay conflict retains text edited while the response is pending', async () => {
    const app = await committedLinkWithLostResponse();
    const create = app.handlers.create_item;
    const pending = deferred();
    app.handlers.create_item = () => pending.promise;
    await app.input('edit-url', 'https://replacement.example/'); await app.save();
    await app.input('edit-note', 'Newer note');
    pending.resolve({ ...[...app.saved.values()][0], capture_replayed: true }); await tick();
    expect(app.$('edit-note').value).toBe('Newer note');
    expect(app.$('edit-url').value).toBe('https://replacement.example/');
    app.handlers.create_item = create; await app.click('create-new-button');
    expect(app.calls.filter(([name]) => name === 'create_item').at(-1)[1].draft.note).toBe('Newer note');
  });
  test('matching pinned and archived replay stays clean without create-only draft properties on the item', async () => {
    const app = await setup({ create_item: ({ draft }) => ({ ...detail(item('created', {
      title: draft.title, item_type: draft.item_type, text_content: draft.text_content,
      url_string: draft.url_string.trim(), is_pinned: true, status: 'archived',
    })), capture_replayed: true }) });
    await app.click('add-button'); await app.input('edit-type', 'link');
    await app.input('edit-title', 'Saved'); await app.input('edit-url', 'https://example.com/');
    for (const id of ['edit-pin', 'edit-archive']) {
      app.$(id).checked = true; app.$(id).dispatchEvent(new app.window.Event('input'));
    }
    await app.save();
    expect(app.$('editor-heading').textContent).toBe('Edit item');
    expect(app.$('create-new-button').hidden).toBe(true);
    expect(app.$('save-button').disabled).toBe(true);
  });
  test('discarding incompatible replay options shows the original saved item', async () => {
    const app = await committedLinkWithLostResponse();
    await app.input('edit-url', 'https://replacement.example/'); await app.save();
    await app.click('discard-button'); await app.click('dialog-discard');
    expect(app.$('editor-heading').textContent).toBe('Edit item');
    expect(app.$('item-preview').textContent).toContain('https://original.example/');
    expect(app.$('save-button').disabled).toBe(true);
    expect(app.saved.size).toBe(1);
    expect(app.calls.some(([name]) => name === 'update_item' || name === 'apply_item_command')).toBe(false);
  });
  test('matching replayed create is clean', async () => {
    const app = await setup({ create_item: ({ draft }) => ({ ...detail(item('created', draft)), capture_replayed: true }) });
    await app.click('add-button'); await app.input('edit-title', 'A'); await app.save();
    expect(app.$('save-button').disabled).toBe(true);
  });
  for (const type of ['text', 'code']) {
    test(`hidden invalid URL does not block a valid ${type} form submission`, async () => {
      const app = await setup(); await app.click('add-button');
      await app.input('edit-type', 'link'); await app.input('edit-url', 'not a URL');
      expect(app.$('edit-url').willValidate).toBe(true);
      expect(app.$('edit-url').validity.typeMismatch).toBe(true);
      await app.input('edit-type', type); await app.input('edit-text', 'Valid content');
      expect(app.$('edit-url-label').hidden).toBe(true);
      expect(app.$('edit-url').disabled).toBe(true);
      expect(app.$('edit-url').willValidate).toBe(false);
      expect(app.$('editor').checkValidity()).toBe(true);
      // Use normal button activation, not a synthetic submit event.
      await app.click('save-button');
      expect(app.calls.filter(([name]) => name === 'create_item')).toHaveLength(1);
    });
  }
  test('supports lifecycle command names and expected revision', async () => {
    const app = await setup({ get_item: () => detail(item('a', { status: 'trashed' })), apply_item_command: ({ command }) => detail(item('a', { status: command === 'restore_trash' ? 'archived' : 'inbox' })) });
    await app.select(); expect(app.$('archive-button').hidden).toBe(true);
    await app.click('trash-button'); await app.click('archive-button'); await app.click('pin-button');
    expect(app.calls.filter(([name]) => name === 'apply_item_command').map(([, args]) => args.command)).toEqual(['restore_trash', 'restore_archive', 'pin']);
    expect(app.calls.find(([name]) => name === 'apply_item_command')[1].expected_updated_at).toBe('2026-01-01T00:00:00Z');
  });
  test('arrow navigation and Escape preserve edits', async () => {
    const app = await setup(); await app.select();
    app.$('items').querySelector('button').dispatchEvent(new app.window.KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true })); await tick();
    expect(app.$('edit-title').value).toBe('Item b');
    await app.input('edit-note', 'Keep'); app.$('edit-note').focus();
    app.$('edit-note').dispatchEvent(new app.window.KeyboardEvent('keydown', { key: 'Escape', bubbles: true })); await tick();
    expect(app.window.document.activeElement.id).toBe('search-text'); expect(app.$('edit-note').value).toBe('Keep');
  });
  test('unavailable storage blocks library mutations but shows actual capabilities', async () => {
    const app = await setup({ desktop_status: () => ({ storage_available: false, platform: 'windows', message: 'Durability gate blocked', capabilities: {} }) });
    expect(app.$('add-button').disabled).toBe(true); expect(app.$('rebuild-button').disabled).toBe(true);
    expect(app.$('platform-status').textContent).toContain('Durability gate blocked');
    expect(app.calls.map(([name]) => name)).toEqual(['desktop_status']);
  });
  test('date, source, location, and pinned filters use the agreed query shape', async () => {
    const app = await setup({ search_items: ({ query }) => query.pinned_only ? [item('b', { is_pinned: true })] : [item(), item('b', { is_pinned: true })] });
    app.$('filter-type').value = 'code'; app.$('filter-source').value = ' Editor ';
    app.$('filter-from').value = '2026-01-01'; app.$('filter-to').value = '2026-02-01';
    app.$('filter-status').value = 'archived'; app.$('filter-pin').checked = true;
    await app.search();
    expect(app.$('items').querySelectorAll('button')).toHaveLength(1);
    expect(app.$('items').textContent).toContain('Item b');
    expect(app.calls.filter(([name]) => name === 'search_items').at(-1)[1].query).toEqual({ text: '', item_type: 'code', source_app: 'Editor', added_after: '2026-01-01T00:00:00Z', added_before: '2026-02-01T23:59:59.999999999Z', status: 'archived', pinned_only: true, include_trashed: false, limit: 200 });
  });
  test('pinned query finds records beyond the unfiltered result limit', async () => {
    const records = Array.from({ length: 205 }, (_, index) => item(String(index), { is_pinned: index >= 200 }));
    const app = await setup({ search_items: ({ query }) => records.filter((row) => !query.pinned_only || row.is_pinned).slice(0, query.limit) });
    expect(app.$('items').querySelectorAll('button')).toHaveLength(200);
    app.$('filter-pin').checked = true; await app.search();
    expect(app.$('items').querySelectorAll('button')).toHaveLength(5);
    expect(app.$('items').textContent).toContain('Item 204');
    expect(app.$('library').textContent).not.toContain('Pinned only filters these results');
    app.$('filter-pin').checked = false; await app.search();
    expect(app.calls.filter(([name]) => name === 'search_items').at(-1)[1].query.pinned_only).toBe(false);
  });
  test('hidden selections cannot run lifecycle actions after a pinned search', async () => {
    const app = await setup({ search_items: ({ query }) => query.pinned_only ? [item('b', { is_pinned: true })] : [item(), item('b')] });
    await app.select(); app.$('filter-pin').checked = true; await app.search();
    await app.input('edit-note', 'Keep hidden draft');
    for (const id of ['pin-button', 'archive-button', 'trash-button']) {
      expect(app.$(id).disabled).toBe(true);
      // Dispatch directly to verify the command path, not only disabled buttons.
      app.$(id).dispatchEvent(new app.window.Event('click'));
    }
    await tick();
    expect(app.$('unsaved-dialog').open).toBe(false);
    expect(app.calls.some(([name]) => name === 'apply_item_command')).toBe(false);
    expect(app.$('edit-note').value).toBe('Keep hidden draft');
    expect(app.$('save-button').disabled).toBe(false);
  });
  test('search pending and errors disable lifecycle actions without deleting drafts', async () => {
    const app = await setup(); await app.select(); await app.input('edit-note', 'Keep');
    const pending = deferred(); app.handlers.search_items = () => pending.promise;
    // Index recovery refreshes results without replacing the editor draft.
    await app.click('rebuild-button');
    expect(app.$('pin-button').disabled).toBe(true);
    pending.reject(new Error('Search failed')); await tick();
    for (const id of ['pin-button', 'archive-button', 'trash-button']) {
      expect(app.$(id).disabled).toBe(true);
      app.$(id).dispatchEvent(new app.window.Event('click'));
    }
    await tick();
    expect(app.calls.some(([name]) => name === 'apply_item_command')).toBe(false);
    expect(app.$('edit-note').value).toBe('Keep');
    app.handlers.search_items = () => [item()];
    await app.click('rebuild-button'); expect(app.$('pin-button').disabled).toBe(false);
  });
  test('lifecycle command revalidates selection after dialog save refreshes results', async () => {
    const app = await setup(); await app.select(); await app.input('edit-note', 'Save first');
    await app.click('trash-button');
    app.handlers.search_items = () => [item('b')];
    await app.click('dialog-save');
    expect(app.calls.some(([name]) => name === 'update_item')).toBe(true);
    expect(app.calls.some(([name]) => name === 'apply_item_command')).toBe(false);
    expect(app.$('trash-button').disabled).toBe(true);
  });
  test('settings show iCloud only on macOS', async () => {
    for (const platform of ['windows', 'linux', 'macos']) {
      const app = await setup({ desktop_status: () => ({ storage_available: true, platform, message: 'Local', capabilities: { icloud: false } }) });
      expect(app.$('settings').textContent.includes('iCloud')).toBe(platform === 'macos');
      expect(app.$('capabilities').textContent.includes('iCloud')).toBe(platform === 'macos');
    }
  });
  test('settings and lifecycle operations cannot silently discard edits', async () => {
    const app = await setup(); await app.select(); await app.input('edit-note', 'Keep');
    await app.click('settings-button'); await app.click('dialog-cancel');
    expect(app.$('settings').hidden).toBe(true);
    await app.click('trash-button'); await app.click('dialog-cancel');
    expect(app.calls.some(([name]) => name === 'apply_item_command')).toBe(false);
    expect(app.$('edit-note').value).toBe('Keep');
  });
  test('save from dialog does not proceed when new edits arrive mid-save', async () => {
    const pending = deferred(); const app = await setup({ update_item: () => pending.promise });
    await app.select(); await app.input('edit-title', 'Snapshot');
    await app.select('b'); await app.click('dialog-save');
    await app.input('edit-title', 'Newer');
    pending.resolve(detail(item('a', { title: 'Snapshot' }))); await tick();
    expect(app.$('unsaved-dialog').open).toBe(true);
    expect(app.$('dialog-error').textContent).toContain('Newer edits');
    expect(app.calls.filter(([name]) => name === 'get_item')).toHaveLength(1);
    await app.click('dialog-cancel'); expect(app.$('edit-title').value).toBe('Newer');
  });
  test('image and file details show attachment metadata without loading content', async () => {
    const app = await setup({ get_item: () => ({ item: item('a', { item_type: 'image' }), attachments: [{ id: 'attachment', file_name: '<img src="https://invalid/image">', content_type: 'image/png', byte_count: 12 }], representations_count: 3 }) });
    await app.select();
    expect(app.$('attachments').textContent).toContain('12 bytes');
    expect(app.$('attachments').querySelector('img')).toBeNull();
    expect(app.$('representation-info').textContent).toContain('3');
    expect(app.$('edit-text-label').hidden).toBe(true);
    expect(app.calls.map(([name]) => name)).toEqual(['desktop_status', 'search_items', 'get_item']);
  });
  test('nullable attachment metadata uses explicit placeholders', async () => {
    const app = await setup({ get_item: () => ({ ...detail(), attachments: [{ file_name: null, content_type: null, byte_count: 0 }] }) });
    await app.select();
    expect(app.$('attachments').textContent).toBe('File name unavailable · Content type unavailable · 0 bytes (content unavailable)');
    expect(app.$('attachments').textContent).not.toMatch(/null|undefined/);
  });
  test('backend startup errors leave mutation controls disabled', async () => {
    const app = await setup({ desktop_status: () => { throw new Error('Host unavailable'); } });
    expect(app.$('error').textContent).toContain('Host unavailable');
    expect(app.$('add-button').disabled).toBe(true);
    expect(app.$('rebuild-button').disabled).toBe(true);
  });
  test('rebuild recovery is explicit and metadata is read only', async () => {
    const app = await setup({ search_items: () => { throw { code: 'index_unavailable', message: 'Rebuild required', retryable: true }; }, get_item: () => detail() });
    expect(app.$('retry-search').hidden).toBe(false);
    app.handlers.search_items = () => [item('recovered')];
    await app.click('settings-button'); await app.click('rebuild-button');
    expect(app.calls.some(([name]) => name === 'rebuild_search')).toBe(true);
    expect(app.$('items').textContent).toContain('Item recovered');
    expect(app.$('settings').textContent).toContain('not implemented');
  });
});
