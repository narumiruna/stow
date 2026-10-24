// API values are explicit: no implicit dates or local-time conversions.
export function searchQuery(values) {
  const after = values.from ? `${values.from}T00:00:00Z` : null;
  const before = values.to ? `${values.to}T23:59:59.999999999Z` : null;
  if (after && before && after > before) throw new Error('From must be on or before To.');
  return {
    text: values.text, item_type: values.type || null,
    source_app: values.source.trim() || null, added_after: after, added_before: before,
    status: values.status || null, pinned_only: Boolean(values.pinned), include_trashed: false, limit: 200,
  };
}

// Collection membership stays in the search service, before its result limit.
export const collections = {
  inbox: { title: 'Inbox', status: 'inbox', pinned: false },
  pinned: { title: 'Pinned', status: '', pinned: true },
  archive: { title: 'Archive', status: 'archived', pinned: false },
  trash: { title: 'Trash', status: 'trashed', pinned: false },
};

export function collectionFor(filters) {
  return Object.keys(collections).find((name) => collections[name].status === filters.status
    && collections[name].pinned === Boolean(filters.pinned)) ?? null;
}

export function filterTokens(filters) {
  const tokens = [];
  if (filters.type) tokens.push({ key: 'type', label: `Type: ${filters.type}`, clear: { type: '' } });
  if (filters.source.trim()) tokens.push({ key: 'source', label: `App: ${filters.source.trim()}`, clear: { source: '' } });
  if (filters.from || filters.to) tokens.push({ key: 'date', label: `Added: ${filters.from || 'Any'} — ${filters.to || 'Any'} (UTC)`, clear: { from: '', to: '' } });
  return tokens;
}

export function relativeDate(value, now = Date.now()) {
  const seconds = (Date.parse(value) - now) / 1000;
  if (!Number.isFinite(seconds)) return 'Date unavailable';
  const format = new Intl.RelativeTimeFormat('en', { numeric: 'auto' });
  for (const [unit, size] of [['year', 31536000], ['month', 2592000], ['day', 86400], ['hour', 3600], ['minute', 60], ['second', 1]]) {
    if (Math.abs(seconds) >= size || unit === 'second') return format.format(Math.round(seconds / size), unit);
  }
}

export function editable(item) {
  return { title: item.title ?? '', note: item.note ?? '',
    text_content: item.text_content ?? '', language: item.language ?? '' };
}

export function newDraft(captureId) {
  return { capture_id: captureId, item_type: 'text', title: '', text_content: '',
    url_string: '', note: '', language: '', is_pinned: false, directly_archive: false };
}

// The update API cannot change these creation options.
export function createOnlyDifferences(draft, item) {
  const fields = [];
  if (draft.item_type !== item.item_type) fields.push('type');
  if (draft.item_type === 'link' && (draft.url_string ?? '').trim() !== (item.url_string ?? '')) fields.push('URL');
  if (Boolean(draft.is_pinned) !== Boolean(item.is_pinned)) fields.push('pin');
  if (Boolean(draft.directly_archive) !== (item.status === 'archived')) fields.push('archive');
  return fields;
}

export function sameDraft(a, b) {
  return JSON.stringify(a) === JSON.stringify(b);
}

export function errorMessage(error) {
  if (typeof error === 'string') {
    try { return errorMessage(JSON.parse(error)); } catch { return error; }
  }
  const message = error?.message || 'The operation failed.';
  return `${error?.code ? `${error.code}: ` : ''}${message}${error?.retryable ? ' You can retry.' : ''}`;
}
