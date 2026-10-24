#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};
use stow_desktop_service::{
    ApplyRequest, CreateRequest, DesktopService, EditRequest, ItemDetail, ItemSummary,
    LifecycleAction, SearchRequest, ServiceError, ServiceStatus, UpdateRequest,
};
use tauri::{Emitter, Manager, State, WebviewUrl, WebviewWindow, WebviewWindowBuilder};
use uuid::Uuid;

type Result<T> = std::result::Result<T, ServiceError>;

#[derive(Default)]
struct ClosePolicy {
    frontend_ready: AtomicBool,
    exit_authorized: AtomicBool,
}

impl ClosePolicy {
    fn must_confirm(&self) -> bool {
        self.frontend_ready.load(Ordering::Acquire) && !self.exit_authorized.load(Ordering::Acquire)
    }
}

fn trusted_url(url: &tauri::Url) -> bool {
    url.username().is_empty()
        && url.password().is_none()
        && url.port().is_none()
        && ((url.scheme() == "tauri" && url.host_str() == Some("localhost"))
            || (url.scheme() == "http" && url.host_str() == Some("tauri.localhost")))
}

fn authorize(window: &WebviewWindow) -> Result<()> {
    if window.label() == "main" && window.url().is_ok_and(|url| trusted_url(&url)) {
        Ok(())
    } else {
        Err(ServiceError {
            code: "forbidden".into(),
            message: "This window cannot access the library.".into(),
            retryable: false,
        })
    }
}

async fn work<T: Send + 'static>(
    operation: impl FnOnce() -> Result<T> + Send + 'static,
) -> Result<T> {
    tauri::async_runtime::spawn_blocking(operation)
        .await
        .map_err(|_| ServiceError {
            code: "disconnected".into(),
            message: "The storage worker stopped. Restart Stow Desktop Preview.".into(),
            retryable: false,
        })?
}

#[tauri::command]
async fn desktop_status(
    window: WebviewWindow,
    state: State<'_, DesktopService>,
    policy: State<'_, Arc<ClosePolicy>>,
) -> Result<ServiceStatus> {
    authorize(&window)?;
    // The frontend registers its close listener before requesting status.
    policy.frontend_ready.store(true, Ordering::Release);
    let service = state.inner().clone();
    work(move || service.status()).await
}

#[tauri::command]
async fn search_items(
    window: WebviewWindow,
    state: State<'_, DesktopService>,
    query: SearchRequest,
) -> Result<Vec<ItemSummary>> {
    authorize(&window)?;
    let service = state.inner().clone();
    work(move || service.search(query)).await
}

#[tauri::command]
async fn get_item(
    window: WebviewWindow,
    state: State<'_, DesktopService>,
    id: Uuid,
) -> Result<ItemDetail> {
    authorize(&window)?;
    let service = state.inner().clone();
    work(move || service.get(id)).await
}

#[tauri::command]
async fn create_item(
    window: WebviewWindow,
    state: State<'_, DesktopService>,
    draft: CreateRequest,
) -> Result<ItemDetail> {
    authorize(&window)?;
    let service = state.inner().clone();
    work(move || service.create(draft)).await
}

#[tauri::command(rename_all = "snake_case")]
async fn update_item(
    window: WebviewWindow,
    state: State<'_, DesktopService>,
    id: Uuid,
    edit: EditRequest,
    expected_updated_at: String,
) -> Result<ItemDetail> {
    authorize(&window)?;
    let service = state.inner().clone();
    work(move || {
        service.update(UpdateRequest {
            id,
            edit,
            expected_updated_at,
        })
    })
    .await
}

#[tauri::command(rename_all = "snake_case")]
async fn apply_item_command(
    window: WebviewWindow,
    state: State<'_, DesktopService>,
    id: Uuid,
    command: LifecycleAction,
    expected_updated_at: String,
) -> Result<ItemDetail> {
    authorize(&window)?;
    let service = state.inner().clone();
    work(move || {
        service.apply(ApplyRequest {
            id,
            command,
            expected_updated_at,
        })
    })
    .await
}

#[tauri::command]
async fn rebuild_search(window: WebviewWindow, state: State<'_, DesktopService>) -> Result<()> {
    authorize(&window)?;
    let service = state.inner().clone();
    work(move || service.rebuild()).await
}

#[tauri::command]
fn close_preview(window: WebviewWindow, policy: State<'_, Arc<ClosePolicy>>) -> Result<()> {
    authorize(&window)?;
    policy.exit_authorized.store(true, Ordering::Release);
    window.app_handle().exit(0);
    Ok(())
}

fn main() {
    let app = tauri::Builder::default()
        .setup(|app| {
            // Preview identity avoids a production data cutover. Disabled
            // macOS/Windows backends do not open a substitute canonical store.
            let root = app.path().app_local_data_dir()?;
            app.manage(DesktopService::start(root));
            let policy = Arc::new(ClosePolicy::default());
            app.manage(policy.clone());
            let navigation_policy = policy.clone();
            let window =
                WebviewWindowBuilder::new(app, "main", WebviewUrl::App("index.html".into()))
                    .title("Stow Desktop Preview")
                    .inner_size(1100.0, 760.0)
                    .min_inner_size(760.0, 540.0)
                    // After the SPA handshake, block reload/top-level navigation so
                    // it cannot bypass draft protection or remove the close listener.
                    .on_navigation(move |url| {
                        trusted_url(url)
                            && !navigation_policy.frontend_ready.load(Ordering::Acquire)
                    })
                    .on_new_window(|_, _| tauri::webview::NewWindowResponse::Deny)
                    .build()?;
            let closing_window = window.clone();
            window.on_window_event(move |event| {
                if let tauri::WindowEvent::CloseRequested { api, .. } = event
                    && policy.must_confirm()
                {
                    api.prevent_close();
                    let _ = closing_window.emit("close_requested", ());
                }
            });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            desktop_status,
            search_items,
            get_item,
            create_item,
            update_item,
            apply_item_command,
            rebuild_search,
            close_preview,
        ])
        .build(tauri::generate_context!())
        .expect("Stow Desktop Preview could not start");
    app.run(|app, event| {
        if let tauri::RunEvent::ExitRequested { api, .. } = event
            && app.state::<Arc<ClosePolicy>>().must_confirm()
            && let Some(window) = app.get_webview_window("main")
        {
            api.prevent_exit();
            let _ = window.emit("close_requested", ());
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn close_confirmation_starts_after_listener_handshake_and_ends_after_approval() {
        let policy = ClosePolicy::default();
        assert!(!policy.must_confirm());
        policy.frontend_ready.store(true, Ordering::Release);
        assert!(policy.must_confirm());
        policy.exit_authorized.store(true, Ordering::Release);
        assert!(!policy.must_confirm());
    }

    #[test]
    fn only_bundled_application_origins_are_trusted() {
        for value in [
            "tauri://localhost/index.html",
            "http://tauri.localhost/index.html",
        ] {
            assert!(trusted_url(&value.parse().unwrap()));
        }
        for value in [
            "https://example.com",
            "http://localhost:1420",
            "file:///tmp/a.html",
            "tauri://other/index.html",
            "http://tauri.localhost.evil/index.html",
            "http://tauri.localhost:8080",
            "http://user@tauri.localhost/",
        ] {
            assert!(!trusted_url(&value.parse().unwrap()), "{value}");
        }
    }
}
