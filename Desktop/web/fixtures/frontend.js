// Deterministic test data only. Never imported by the embedded frontend.
export const hostile = '<script>alert("saved")</script><img src="https://remote.invalid/pixel"><a href="javascript:alert(1)">Open</a>';
export const longContent = `${hostile}\n${'Long captured content. '.repeat(4096)}`;
export const typedItems = ['link', 'text', 'code', 'image', 'file'].map((type) => ({
  id: type, item_type: type, title: `${type}: ${hostile}`, text_content: longContent,
  url_string: type === 'link' ? 'javascript:alert(1)' : null,
  link_description: type === 'link' ? hostile : null,
  language: type === 'code' ? 'javascript' : null,
  file_name: ['image', 'file'].includes(type) ? hostile : null,
}));
export const deniedStorage = {
  storage_available: false, platform: 'windows', message: 'Storage durability protocol unavailable',
  capabilities: { local_storage: false, icloud: false, clipboard_capture: false, direct_paste: false, global_shortcut: false },
};
