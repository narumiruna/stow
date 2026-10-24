use super::*;

fn draft() -> CreateRequest {
    CreateRequest {
        capture_id: Uuid::new_v4(),
        item_type: ItemType::Text,
        title: "Example".into(),
        text_content: Some("Retained text".into()),
        url_string: None,
        note: None,
        source_app: None,
        language: None,
        is_pinned: false,
        directly_archive: false,
    }
}

#[test]
fn oversized_arguments_are_rejected_before_dispatch() {
    let root = tempfile::tempdir().unwrap();
    let service = DesktopService::start(root.path().join("library"));
    let mut request = draft();
    request.text_content = Some("x".repeat(TEXT_LIMIT + 1));
    assert_eq!(
        service.create(request).unwrap_err().code,
        "invalid_argument"
    );
    let mut request = draft();
    request.item_type = ItemType::Image;
    assert_eq!(service.create(request).unwrap_err().code, "unsupported");
}

#[test]
fn concurrency_timestamps_preserve_nanoseconds() {
    let first = timestamp("2026-01-01T00:00:00.123456789Z").unwrap();
    let different = timestamp("2026-01-01T00:00:00.123456788Z").unwrap();
    let offset = timestamp("2026-01-01T01:00:00.123456789+01:00").unwrap();
    assert_ne!(first, different);
    assert_eq!(first, offset);
    assert!(timestamp("not a date").is_err());
}

#[test]
fn unavailable_status_is_explicit() {
    let root = tempfile::tempdir().unwrap();
    let service = DesktopService::start(root.path().join("missing").join(".."));
    let status = service.status().unwrap();
    assert!(!status.storage_available);
    assert!(!status.capabilities.local_storage);
    assert!(!status.capabilities.icloud);
    assert!(!status.capabilities.clipboard_capture);
    assert!(!status.capabilities.direct_paste);
    assert!(!status.capabilities.global_shortcut);
    assert!(service.get(Uuid::new_v4()).is_err());
}

#[cfg(any(target_os = "windows", target_os = "macos"))]
#[test]
fn unsupported_platform_does_not_create_a_library() {
    let root = tempfile::tempdir().unwrap();
    let library = root.path().join("library");
    let service = DesktopService::start(library.clone());
    assert!(!service.status().unwrap().storage_available);
    assert!(!library.exists());
}

#[cfg(target_os = "linux")]
#[test]
fn startup_creates_private_parents_and_rejects_symlinks() {
    use std::os::unix::fs::{PermissionsExt, symlink};
    let root = tempfile::tempdir().unwrap();
    let parent = root.path().join("new").join("nested");
    let service = DesktopService::start(parent.join("library"));
    assert!(service.status().unwrap().storage_available);
    assert_eq!(
        std::fs::metadata(&parent).unwrap().permissions().mode() & 0o777,
        0o700
    );
    drop(service);
    symlink(&parent, root.path().join("alias")).unwrap();
    let service = DesktopService::start(root.path().join("alias").join("rejected"));
    assert!(!service.status().unwrap().storage_available);
    assert!(!parent.join("rejected").exists());
}

#[cfg(target_os = "linux")]
#[test]
fn persistence_replay_conflicts_and_lifecycle() {
    let root = tempfile::tempdir().unwrap();
    let library = root.path().join("library");
    let request = draft();
    let id;
    {
        let service = DesktopService::start(library.clone());
        assert!(service.status().unwrap().storage_available);
        let created = service.create(request.clone()).unwrap();
        id = created.item.id;
        assert!(!created.capture_replayed);
        let mut retried = request;
        retried.text_content = Some("Edited after response loss".into());
        let replayed = service.create(retried).unwrap();
        assert_eq!(replayed.item.id, id);
        assert!(replayed.capture_replayed);
        assert_eq!(replayed.item.text_content.as_deref(), Some("Retained text"));
        let updated = service
            .update(UpdateRequest {
                id,
                expected_updated_at: created.item.updated_at.to_rfc3339(),
                edit: EditRequest {
                    title: "Changed".into(),
                    note: None,
                    text_content: Some("Saved".into()),
                    language: None,
                },
            })
            .unwrap();
        assert_eq!(
            service
                .apply(ApplyRequest {
                    id,
                    expected_updated_at: created.item.updated_at.to_rfc3339(),
                    command: LifecycleAction::Trash
                })
                .unwrap_err()
                .code,
            "conflict"
        );
        // Same instant in another UTC-offset representation must compare equal.
        let equivalent = updated
            .item
            .updated_at
            .with_timezone(&chrono::FixedOffset::east_opt(3600).unwrap())
            .to_rfc3339();
        let archived = service
            .apply(ApplyRequest {
                id,
                expected_updated_at: equivalent,
                command: LifecycleAction::Archive,
            })
            .unwrap();
        let trashed = service
            .apply(ApplyRequest {
                id,
                expected_updated_at: archived.item.updated_at.to_rfc3339(),
                command: LifecycleAction::Trash,
            })
            .unwrap();
        assert!(service.search(SearchRequest::default()).unwrap().is_empty());
        let restored = service
            .apply(ApplyRequest {
                id,
                expected_updated_at: trashed.item.updated_at.to_rfc3339(),
                command: LifecycleAction::RestoreTrash,
            })
            .unwrap();
        assert_eq!(restored.item.status, stow_core::ItemStatus::Archived);
        service.rebuild().unwrap();
        let json = serde_json::to_value(service.search(SearchRequest::default()).unwrap()).unwrap();
        assert!(json[0].get("text_content").is_none());
    }
    let service = DesktopService::start(library);
    assert_eq!(
        service.get(id).unwrap().item.text_content.as_deref(),
        Some("Saved")
    );
}

#[cfg(target_os = "linux")]
#[test]
fn details_remove_embedded_bytes() {
    let root = tempfile::tempdir().unwrap();
    let service = DesktopService::start(root.path().join("library"));
    let created = service.create(draft()).unwrap();
    let id = created.item.id;
    service
        .request(move |state| {
            let repo = repository(state)?;
            let mut item = repo.get(id).map_err(storage_error)?.unwrap();
            item.favicon_data = Some(vec![1, 2]);
            item.link_preview_image_data = Some(vec![3, 4]);
            repo.upsert(&item).map_err(storage_error)
        })
        .unwrap();
    let detail = service.get(id).unwrap();
    assert!(detail.item.favicon_data.is_none());
    assert!(detail.item.link_preview_image_data.is_none());
    assert!(detail.attachments.is_empty());
    assert_eq!(detail.representations_count, 0);
}

#[cfg(target_os = "linux")]
#[test]
fn failed_save_retains_committed_data() {
    let root = tempfile::tempdir().unwrap();
    let service = DesktopService::start(root.path().join("library"));
    let created = service.create(draft()).unwrap();
    let id = created.item.id;
    let original = created.item.clone();
    let failure = service.update(UpdateRequest {
        id,
        expected_updated_at: original.updated_at.to_rfc3339(),
        edit: EditRequest {
            title: "Not saved".into(),
            note: None,
            text_content: Some(String::new()),
            language: None,
        },
    });
    assert_eq!(failure.unwrap_err().code, "invalid_argument");
    assert_eq!(service.get(id).unwrap().item, original);
    // Force a repository write failure without changing the committed snapshot.
    service
        .request(move |state| {
            let repo = repository(state)?;
            std::fs::rename(root.path().join("library"), root.path().join("moved")).unwrap();
            let result = repo.update(
                id,
                &ItemEdit {
                    title: "Failed".into(),
                    note: None,
                    text_content: Some("Not committed".into()),
                    language: None,
                },
                Utc::now(),
            );
            assert!(result.is_err());
            assert_eq!(repo.get(id).unwrap().unwrap(), original);
            Ok(())
        })
        .unwrap();
}

#[cfg(target_os = "linux")]
#[test]
fn competing_edits_have_one_winner() {
    let root = tempfile::tempdir().unwrap();
    let service = DesktopService::start(root.path().join("library"));
    let created = service.create(draft()).unwrap();
    let request = UpdateRequest {
        id: created.item.id,
        expected_updated_at: created.item.updated_at.to_rfc3339(),
        edit: EditRequest {
            title: "Winner".into(),
            note: None,
            text_content: Some("New".into()),
            language: None,
        },
    };
    let clone = service.clone();
    let other = request.clone();
    let thread = std::thread::spawn(move || clone.update(other));
    let first = service.update(request);
    let second = thread.join().unwrap();
    assert_ne!(first.is_ok(), second.is_ok());
    assert_eq!(
        first.err().or_else(|| second.err()).unwrap().code,
        "conflict"
    );
}

#[test]
fn bounded_queue_and_last_handle_shutdown() {
    let root = tempfile::tempdir().unwrap();
    let service = DesktopService::start(root.path().join("library"));
    let (entered_tx, entered_rx) = mpsc::channel();
    let (release_tx, release_rx) = mpsc::channel();
    service
        .worker
        .sender
        .as_ref()
        .unwrap()
        .try_send(Box::new(move |_| {
            entered_tx.send(()).unwrap();
            release_rx.recv().unwrap();
        }))
        .unwrap_or_else(|_| panic!("could not enqueue test barrier"));
    entered_rx.recv().unwrap();
    for _ in 0..QUEUE_CAPACITY {
        service
            .worker
            .sender
            .as_ref()
            .unwrap()
            .try_send(Box::new(|_| {}))
            .unwrap_or_else(|_| panic!("queue filled early"));
    }
    assert_eq!(service.status().unwrap_err().code, "busy");
    let clone = service.clone();
    drop(service);
    release_tx.send(()).unwrap();
    drop(clone); // Disconnects before join; drains the bounded queue.
}

#[test]
fn worker_panic_disconnects_without_hanging() {
    let root = tempfile::tempdir().unwrap();
    let service = DesktopService::start(root.path().join("library"));
    let result: Result<()> = service.request(|_| panic!("injected worker panic"));
    assert_eq!(result.unwrap_err().code, "disconnected");
    assert_eq!(service.status().unwrap_err().code, "disconnected");
}
