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
