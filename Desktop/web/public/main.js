import { createApp } from './app.js';

const bridge = window.__TAURI__;
if (!bridge?.core?.invoke || !bridge?.event?.listen) {
  createApp(() => Promise.reject(new Error('Tauri command bridge is unavailable.')), document);
} else {
  let app;
  try {
    // Register before desktop_status marks the native close policy ready.
    await bridge.event.listen('close_requested', () => {
      app?.requestClose().catch(() => {});
    });
    app = createApp((command, args) => bridge.core.invoke(command, args), document);
  } catch {
    createApp(() => Promise.reject(new Error('Desktop close protection could not start.')), document);
  }
}
