//! Headless, disposable-data Rust-to-Swift verification. Never starts Tauri.
#[cfg(target_os = "macos")]
fn main() {
    use std::{
        ffi::c_void,
        path::PathBuf,
        sync::mpsc,
        time::{Duration, Instant},
    };
    unsafe extern "C" {
        static kCFRunLoopDefaultMode: *const c_void;
        fn CFRunLoopRunInMode(mode: *const c_void, seconds: f64, return_after_source: u8) -> i32;
    }
    let arguments: Vec<_> = std::env::args_os().skip(1).collect();
    if arguments.len() != 2 {
        eprintln!("Usage: stow-bridge-probe <exercise|reopen> <disposable-preview-root>");
        std::process::exit(2);
    }
    let mode = arguments[0].to_string_lossy().into_owned();
    let root = PathBuf::from(&arguments[1]);
    let (sender, receiver) = mpsc::channel();
    let worker = std::thread::spawn(move || {
        let result = std::panic::catch_unwind(|| probe::run(&mode, root));
        let result = result.unwrap_or_else(|_| Err("The bridge probe panicked.".into()));
        let _ = sender.send(result);
    });
    let started = Instant::now();
    let result = loop {
        match receiver.try_recv() {
            Ok(result) => break result,
            Err(mpsc::TryRecvError::Disconnected) => break Err("The probe disconnected.".into()),
            Err(mpsc::TryRecvError::Empty) => {}
        }
        // This deadline belongs only to a disposable-data verification process,
        // not to accepted application mutations or their retry behavior.
        if started.elapsed() > Duration::from_secs(90) {
            eprintln!("The headless bridge probe exceeded its safety deadline.");
            std::process::exit(1);
        }
        // SAFETY: this is the process main thread; CoreFoundation owns the mode.
        unsafe {
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, 1);
        }
    };
    worker.join().expect("probe worker stopped");
    if let Err(error) = result {
        eprintln!("{error}");
        std::process::exit(1);
    }
    println!("Headless Rust-to-Swift process check passed.");
}

#[cfg(not(target_os = "macos"))]
fn main() {
    eprintln!("The Swift bridge probe requires macOS; it does not enable another backend.");
    std::process::exit(2);
}

#[cfg(target_os = "macos")]
mod probe {
    use std::path::PathBuf;
    use stow_core::{ItemStatus, ItemType};
    use stow_desktop_service::{
        ApplyRequest, CreateRequest, DesktopService, EditRequest, LifecycleAction, SearchRequest,
        UpdateRequest,
    };
    use uuid::Uuid;

    fn draft() -> CreateRequest {
        CreateRequest {
            capture_id: Uuid::parse_str("20000000-0000-4000-8000-000000000099").unwrap(),
            item_type: ItemType::Text,
            title: "Rust probe".into(),
            text_content: Some("  Retained Café é\n日本語  ".into()),
            url_string: None,
            note: None,
            source_app: Some("Rust bridge probe".into()),
            language: None,
            is_pinned: false,
            directly_archive: false,
        }
    }

    pub fn run(mode: &str, root: PathBuf) -> Result<(), String> {
        if !matches!(mode, "exercise" | "reopen") {
            return Err("Unknown bridge probe operation.".into());
        }
        let invalid = root.parent().unwrap().join("production-sentinel");
        let invalid_copy = invalid.clone();
        let unavailable = DesktopService::start(move || stow_desktop::open_backend(invalid_copy));
        assert!(
            !unavailable
                .status()
                .map_err(|e| e.to_string())?
                .storage_available
        );
        assert!(!invalid.exists());
        unavailable.shutdown().map_err(|e| e.to_string())?;

        let service = DesktopService::start(move || stow_desktop::open_backend(root));
        let status = service.status().map_err(|e| e.to_string())?;
        assert!(status.storage_available);
        assert!(status.capabilities.local_storage);
        assert!(!status.capabilities.icloud);
        assert!(!status.capabilities.clipboard_capture);
        assert!(!status.capabilities.global_shortcut);
        assert!(!status.capabilities.direct_paste);

        if mode == "exercise" {
            let mut link = draft();
            link.capture_id = Uuid::parse_str("20000000-0000-4000-8000-000000000098").unwrap();
            link.item_type = ItemType::Link;
            link.title = String::new();
            link.text_content = None;
            link.url_string = Some("https://EXAMPLE.COM:443/Path".into());
            link.source_app = Some("Rust link probe".into());
            let expected = link.normalized_draft().map_err(|e| e.to_string())?;
            let saved = service.create(link).map_err(|e| e.to_string())?;
            assert_eq!(saved.item.title, expected.title);
            assert_eq!(saved.item.source_domain, expected.source_domain);
            assert_eq!(saved.item.url_string, expected.url_string);

            let seeded = service
                .search(SearchRequest {
                    source_app: Some("Bridge fixture".into()),
                    include_trashed: true,
                    limit: Some(500),
                    ..Default::default()
                })
                .map_err(|e| e.to_string())?;
            assert_eq!(seeded.len(), 5);
            for summary in seeded {
                let detail = service.get(summary.id).map_err(|e| e.to_string())?;
                assert!(detail.item.favicon_data.is_none());
                assert!(detail.item.link_preview_image_data.is_none());
                assert_eq!(detail.attachments.len(), 1);
                assert_eq!(detail.representations_count, 1);
                let updated = service
                    .update(UpdateRequest {
                        id: summary.id,
                        expected_updated_at: detail.item.updated_at.to_rfc3339(),
                        edit: EditRequest {
                            title: format!("Edited fixture {}", detail.item.item_type.as_str()),
                            note: Some("Edited fixture note".into()),
                            text_content: detail.item.text_content.clone(),
                            language: detail.item.language.clone(),
                        },
                    })
                    .map_err(|e| e.to_string())?;
                assert_eq!(updated.attachments.len(), 1);
                assert_eq!(updated.representations_count, 1);
            }
        }

        let created = service.create(draft()).map_err(|e| e.to_string())?;
        assert_eq!(created.capture_replayed, mode == "reopen");
        assert_eq!(created.item.text_content, draft().text_content);
        let id = created.item.id;
        if mode == "exercise" {
            let mut retry = draft();
            retry.title = "Must not overwrite an accepted capture".into();
            let replay = service.create(retry).map_err(|e| e.to_string())?;
            assert!(replay.capture_replayed);
            assert_eq!(replay.item, created.item);
            let edit = EditRequest {
                title: "Rust probe edited".into(),
                note: Some("Metadata only".into()),
                text_content: created.item.text_content.clone(),
                language: None,
            };
            let stale = service
                .update(UpdateRequest {
                    id,
                    expected_updated_at: (created.item.updated_at
                        + chrono::TimeDelta::nanoseconds(1))
                    .to_rfc3339(),
                    edit: edit.clone(),
                })
                .unwrap_err();
            assert_eq!(stale.code, "conflict");
            assert_eq!(
                service.get(id).map_err(|e| e.to_string())?.item,
                created.item
            );
            let mut invalid = edit.clone();
            invalid.text_content = Some(" \n ".into());
            assert_eq!(
                service
                    .update(UpdateRequest {
                        id,
                        expected_updated_at: created.item.updated_at.to_rfc3339(),
                        edit: invalid,
                    })
                    .unwrap_err()
                    .code,
                "invalid_argument"
            );
            assert_eq!(
                service.get(id).map_err(|e| e.to_string())?.item,
                created.item
            );
            let mut detail = service
                .update(UpdateRequest {
                    id,
                    expected_updated_at: created.item.updated_at.to_rfc3339(),
                    edit,
                })
                .map_err(|e| e.to_string())?;
            for command in [
                LifecycleAction::Pin,
                LifecycleAction::Archive,
                LifecycleAction::Trash,
            ] {
                detail = service
                    .apply(ApplyRequest {
                        id,
                        expected_updated_at: detail.item.updated_at.to_rfc3339(),
                        command,
                    })
                    .map_err(|e| e.to_string())?;
            }
            assert_eq!(detail.item.status, ItemStatus::Trashed);
            assert!(
                service
                    .search(SearchRequest {
                        source_app: Some("Rust bridge probe".into()),
                        ..Default::default()
                    })
                    .map_err(|e| e.to_string())?
                    .is_empty()
            );
            detail = service
                .apply(ApplyRequest {
                    id,
                    expected_updated_at: detail.item.updated_at.to_rfc3339(),
                    command: LifecycleAction::RestoreTrash,
                })
                .map_err(|e| e.to_string())?;
            assert_eq!(detail.item.status, ItemStatus::Archived);
            detail = service
                .apply(ApplyRequest {
                    id,
                    expected_updated_at: detail.item.updated_at.to_rfc3339(),
                    command: LifecycleAction::RestoreArchive,
                })
                .map_err(|e| e.to_string())?;
            assert_eq!(detail.item.status, ItemStatus::Inbox);
            assert!(detail.item.is_pinned);
            service.rebuild().map_err(|e| e.to_string())?;
        } else {
            assert_eq!(created.item.title, "Rust probe edited");
            assert_eq!(created.item.note.as_deref(), Some("Metadata only"));
            assert_eq!(created.item.status, ItemStatus::Inbox);
            assert!(created.item.is_pinned);
            assert_eq!(
                service
                    .search(SearchRequest {
                        text: "Café".into(),
                        source_app: Some("Rust bridge probe".into()),
                        ..Default::default()
                    })
                    .map_err(|e| e.to_string())?
                    .len(),
                1
            );
        }
        service.shutdown().map_err(|e| e.to_string())?;
        assert!(service.get(id).is_err());
        Ok(())
    }
}
