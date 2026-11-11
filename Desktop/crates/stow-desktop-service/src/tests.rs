use std::{
    sync::atomic::{AtomicBool, AtomicUsize, Ordering},
    time::Duration,
};

use chrono::Utc;
use stow_core::{ItemStatus, ItemType};

use super::{
    memory_tests::{DropNotice, MemoryRepository},
    *,
};

fn service() -> DesktopService {
    DesktopService::start(|| Ok(Box::new(MemoryRepository::default())))
}

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

fn edit(item: &stow_core::Item) -> UpdateRequest {
    UpdateRequest {
        id: item.id,
        expected_updated_at: item.updated_at.to_rfc3339(),
        edit: EditRequest {
            title: "Changed".into(),
            note: None,
            text_content: Some("Saved".into()),
            language: None,
        },
    }
}

#[test]
fn worker_cannot_join_itself_even_while_an_external_shutdown_waits() {
    let service = service();
    let worker_handle = service.clone();
    let request_handle = service.clone();
    let (entered, started) = mpsc::channel();
    let (resume, resumed) = mpsc::channel();
    let request = thread::spawn(move || {
        request_handle.request(move |_| {
            entered.send(()).unwrap();
            resumed.recv().unwrap();
            worker_handle.shutdown()
        })
    });
    started.recv_timeout(Duration::from_secs(5)).unwrap();
    let shutdown_handle = service.clone();
    let shutdown = thread::spawn(move || shutdown_handle.shutdown());
    while service.worker.control.lock().unwrap().sender.is_some() {
        thread::yield_now();
    }
    resume.send(()).unwrap();
    assert_eq!(
        request.join().unwrap().unwrap_err().code,
        "invalid_argument"
    );
    shutdown.join().unwrap().unwrap();
}

#[test]
fn invalid_arguments_are_rejected_before_backend_dispatch() {
    // An unavailable backend would return unavailable if validation dispatched.
    let service = DesktopService::start(|| Err(error("unavailable", "Unavailable.")));
    let mut request = draft();
    request.text_content = Some("x".repeat(TEXT_LIMIT + 1));
    assert_eq!(
        service.create(request).unwrap_err().code,
        "invalid_argument"
    );
    for kind in [ItemType::Image, ItemType::File] {
        let mut request = draft();
        request.item_type = kind;
        assert_eq!(service.create(request).unwrap_err().code, "unsupported");
    }
    let mut request = draft();
    request.text_content = Some(" \n\t ".into());
    assert_eq!(
        service.create(request).unwrap_err().code,
        "invalid_argument"
    );
    for url in [
        "https://example.com/日本語",
        "http:///example.com",
        "https://example.com/%QZ",
        "file:///tmp/test",
    ] {
        let mut request = draft();
        request.item_type = ItemType::Link;
        request.url_string = Some(url.into());
        assert_eq!(
            service.create(request).unwrap_err().code,
            "invalid_argument"
        );
    }
    for field in 0..5 {
        let mut request = draft();
        match field {
            0 => request.title = "x".repeat(FIELD_LIMIT + 1),
            1 => request.url_string = Some("x".repeat(FIELD_LIMIT + 1)),
            2 => request.note = Some("x".repeat(TEXT_LIMIT + 1)),
            3 => request.source_app = Some("x".repeat(FIELD_LIMIT + 1)),
            _ => request.language = Some("x".repeat(FIELD_LIMIT + 1)),
        }
        assert_eq!(
            service.create(request).unwrap_err().code,
            "invalid_argument"
        );
    }
    let mut search = SearchRequest {
        text: "x".repeat(4097),
        ..Default::default()
    };
    assert_eq!(
        service.search(search.clone()).unwrap_err().code,
        "invalid_argument"
    );
    search.text.clear();
    search.source_app = Some("x".repeat(FIELD_LIMIT + 1));
    assert_eq!(service.search(search).unwrap_err().code, "invalid_argument");
    let mut request = edit(&stow_core::Item::new(ItemType::Text, "Example", Utc::now()));
    request.edit.title = "x".repeat(FIELD_LIMIT + 1);
    assert_eq!(
        service.update(request).unwrap_err().code,
        "invalid_argument"
    );
    assert_eq!(
        service
            .apply(ApplyRequest {
                id: Uuid::new_v4(),
                expected_updated_at: "invalid".into(),
                command: LifecycleAction::Trash
            })
            .unwrap_err()
            .code,
        "invalid_argument"
    );
    service.shutdown().unwrap();
}

#[test]
fn timestamps_are_normalized_to_exact_fixed_nine_digits() {
    assert_eq!(
        canonical_revision("2026-01-01T01:00:00.125+01:00").unwrap(),
        "2026-01-01T00:00:00.125000000Z"
    );
    assert_ne!(
        canonical_revision("2026-01-01T00:00:00.123456789Z").unwrap(),
        canonical_revision("2026-01-01T00:00:00.123456788Z").unwrap()
    );
    assert!(canonical_revision(&"x".repeat(65)).is_err());
    assert!(canonical_revision("not a date").is_err());
    let revisions = Arc::new(Mutex::new(Vec::new()));
    let observed = revisions.clone();
    let service = DesktopService::start(move || {
        Ok(Box::new(MemoryRepository {
            revisions: observed,
            ..Default::default()
        }))
    });
    for expected in [
        "2026-01-01T01:00:00.125+01:00",
        "2026-01-01T00:00:00.125000001Z",
    ] {
        let _ = service.apply(ApplyRequest {
            id: Uuid::new_v4(),
            expected_updated_at: expected.into(),
            command: LifecycleAction::Trash,
        });
    }
    assert_eq!(
        *revisions.lock().unwrap(),
        vec![
            "2026-01-01T00:00:00.125000000Z",
            "2026-01-01T00:00:00.125000001Z"
        ]
    );
    service.shutdown().unwrap();
}

#[test]
fn backend_factory_runs_on_worker_and_failure_has_no_fallback() {
    let caller = thread::current().id();
    let service = DesktopService::start(move || {
        assert_ne!(thread::current().id(), caller);
        Err(error("unavailable", "Storage cannot open."))
    });
    let status = service.status().unwrap();
    assert!(!status.storage_available);
    assert_eq!(status.message, "Storage cannot open.");
    assert!(!status.capabilities.local_storage);
    assert!(!status.capabilities.icloud);
    assert!(!status.capabilities.clipboard_capture);
    assert!(!status.capabilities.direct_paste);
    assert!(!status.capabilities.global_shortcut);
    assert_eq!(service.get(Uuid::new_v4()).unwrap_err().code, "unavailable");
    service.shutdown().unwrap();
}

fn exercise_contract(service: &DesktopService) -> Uuid {
    let request = draft();
    let created = service.create(request.clone()).unwrap();
    let id = created.item.id;
    assert!(!created.capture_replayed);
    let mut retried = request;
    retried.text_content = Some("Edited after response loss".into());
    let replayed = service.create(retried).unwrap();
    assert_eq!(replayed.item.id, id);
    assert!(replayed.capture_replayed);
    assert_eq!(replayed.item.text_content.as_deref(), Some("Retained text"));
    let updated = service.update(edit(&created.item)).unwrap();
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
    let drift = updated.item.updated_at + chrono::TimeDelta::nanoseconds(1);
    assert_eq!(
        service
            .apply(ApplyRequest {
                id,
                expected_updated_at: drift.to_rfc3339(),
                command: LifecycleAction::Trash
            })
            .unwrap_err()
            .code,
        "conflict"
    );
    // Equivalent offset spellings compare equal, without NSDate rounding.
    let equivalent = updated
        .item
        .updated_at
        .with_timezone(&chrono::FixedOffset::east_opt(3600).unwrap())
        .to_rfc3339();
    let mut current = service
        .apply(ApplyRequest {
            id,
            expected_updated_at: equivalent,
            command: LifecycleAction::Pin,
        })
        .unwrap();
    assert!(current.item.is_pinned);
    for action in [LifecycleAction::Archive, LifecycleAction::Trash] {
        current = service
            .apply(ApplyRequest {
                id,
                expected_updated_at: current.item.updated_at.to_rfc3339(),
                command: action,
            })
            .unwrap();
    }
    assert!(service.search(SearchRequest::default()).unwrap().is_empty());
    current = service
        .apply(ApplyRequest {
            id,
            expected_updated_at: current.item.updated_at.to_rfc3339(),
            command: LifecycleAction::RestoreTrash,
        })
        .unwrap();
    assert_eq!(current.item.status, ItemStatus::Archived);
    assert!(current.item.status_before_trash.is_none());
    for action in [LifecycleAction::RestoreArchive, LifecycleAction::Unpin] {
        current = service
            .apply(ApplyRequest {
                id,
                expected_updated_at: current.item.updated_at.to_rfc3339(),
                command: action,
            })
            .unwrap();
    }
    assert_eq!(current.item.status, ItemStatus::Inbox);
    assert!(!current.item.is_pinned);
    service.rebuild().unwrap();
    let json = serde_json::to_value(service.search(SearchRequest::default()).unwrap()).unwrap();
    assert_eq!(json.as_array().unwrap().len(), 1);
    assert!(json[0].get("text_content").is_none());
    id
}

#[test]
fn portable_replay_conflicts_and_lifecycle() {
    let service = service();
    assert!(service.status().unwrap().capabilities.local_storage);
    exercise_contract(&service);
    service.shutdown().unwrap();
}

#[test]
fn search_limits_are_clamped_before_dispatch() {
    let service = service();
    for _ in 0..502 {
        service.create(draft()).unwrap();
    }
    for (limit, count) in [(None, 200), (Some(0), 1), (Some(usize::MAX), 500)] {
        assert_eq!(
            service
                .search(SearchRequest {
                    limit,
                    ..Default::default()
                })
                .unwrap()
                .len(),
            count
        );
    }
    service.shutdown().unwrap();
}

#[test]
fn failed_save_retains_committed_data_and_allows_retry() {
    let fail_save = Arc::new(AtomicBool::new(false));
    let injected = fail_save.clone();
    let service = DesktopService::start(move || {
        Ok(Box::new(MemoryRepository {
            fail_save: injected,
            ..Default::default()
        }))
    });
    let request = draft();
    fail_save.store(true, Ordering::SeqCst);
    assert_eq!(service.create(request.clone()).unwrap_err().code, "storage");
    assert!(service.search(SearchRequest::default()).unwrap().is_empty());
    let created = service.create(request).unwrap();
    assert!(!created.capture_replayed);
    let mut invalid = edit(&created.item);
    invalid.edit.text_content = Some(String::new());
    assert_eq!(
        service.update(invalid).unwrap_err().code,
        "invalid_argument"
    );
    assert_eq!(service.get(created.item.id).unwrap().item, created.item);
    fail_save.store(true, Ordering::SeqCst);
    assert_eq!(
        service.update(edit(&created.item)).unwrap_err().code,
        "storage"
    );
    assert_eq!(service.get(created.item.id).unwrap().item, created.item);
    let saved = service.update(edit(&created.item)).unwrap();
    assert_eq!(saved.item.title, "Changed");
    fail_save.store(true, Ordering::SeqCst);
    assert_eq!(
        service
            .apply(ApplyRequest {
                id: saved.item.id,
                expected_updated_at: saved.item.updated_at.to_rfc3339(),
                command: LifecycleAction::Trash
            })
            .unwrap_err()
            .code,
        "storage"
    );
    assert_eq!(service.get(saved.item.id).unwrap().item, saved.item);
    service.shutdown().unwrap();
}

#[test]
fn competing_edits_have_one_winner() {
    let service = service();
    let created = service.create(draft()).unwrap();
    let request = edit(&created.item);
    let clone = service.clone();
    let other = request.clone();
    let thread = thread::spawn(move || clone.update(other));
    let first = service.update(request);
    let second = thread.join().unwrap();
    assert_ne!(first.is_ok(), second.is_ok());
    assert_eq!(
        first.err().or_else(|| second.err()).unwrap().code,
        "conflict"
    );
    service.shutdown().unwrap();
}

fn block_worker(service: &DesktopService) -> mpsc::Sender<()> {
    let (entered_tx, entered_rx) = mpsc::channel();
    let (release_tx, release_rx) = mpsc::channel();
    service
        .enqueue(Box::new(move |_| {
            entered_tx.send(()).unwrap();
            release_rx.recv().unwrap();
        }))
        .unwrap();
    entered_rx.recv_timeout(Duration::from_secs(5)).unwrap();
    release_tx
}

#[test]
fn bounded_queue_shutdown_drains_and_rejects_late_calls_across_clones() {
    let service = service();
    let release = block_worker(&service);
    let drained = Arc::new(AtomicUsize::new(0));
    for _ in 0..QUEUE_CAPACITY {
        let drained = drained.clone();
        service
            .enqueue(Box::new(move |_| {
                drained.fetch_add(1, Ordering::SeqCst);
            }))
            .unwrap();
    }
    assert_eq!(service.status().unwrap_err().code, "busy");
    let (done_tx, done_rx) = mpsc::channel();
    let mut threads = Vec::new();
    for _ in 0..2 {
        let clone = service.clone();
        let done = done_tx.clone();
        threads.push(thread::spawn(move || {
            done.send(clone.shutdown()).unwrap();
        }));
    }
    // Observe the atomic admission cutoff without depending on thread timing.
    while service.worker.control.lock().unwrap().sender.is_some() {
        thread::yield_now();
    }
    assert_eq!(service.clone().status().unwrap_err().code, "disconnected");
    assert!(matches!(done_rx.try_recv(), Err(mpsc::TryRecvError::Empty)));
    release.send(()).unwrap();
    for _ in 0..2 {
        done_rx
            .recv_timeout(Duration::from_secs(5))
            .unwrap()
            .unwrap();
    }
    for thread in threads {
        thread.join().unwrap();
    }
    assert_eq!(drained.load(Ordering::SeqCst), QUEUE_CAPACITY);
    service.shutdown().unwrap();
    assert_eq!(
        service.get(Uuid::new_v4()).unwrap_err().code,
        "disconnected"
    );
}

#[test]
fn last_handle_drop_does_not_join_or_block_native_main_actor() {
    let (dropped_tx, dropped_rx) = mpsc::channel();
    let service = DesktopService::start(move || {
        Ok(Box::new(MemoryRepository {
            _dropped: Some(DropNotice(dropped_tx)),
            ..Default::default()
        }))
    });
    let release = block_worker(&service);
    let (done_tx, done_rx) = mpsc::channel();
    let drop_thread = thread::spawn(move || {
        drop(service);
        done_tx.send(()).unwrap();
    });
    let nonblocking = done_rx.recv_timeout(Duration::from_secs(5));
    // Release even if the assertion fails so a synchronous-join regression does
    // not leave a blocked worker behind in the test process.
    release.send(()).unwrap();
    nonblocking.expect("Drop synchronously joined the blocked worker");
    drop_thread.join().unwrap();
    dropped_rx.recv_timeout(Duration::from_secs(5)).unwrap();
}

#[test]
fn worker_panic_disconnects_and_all_shutdown_callers_report_it() {
    let service = service();
    let result: Result<()> = service.request(|_| panic!("injected worker panic"));
    assert_eq!(result.unwrap_err().code, "disconnected");
    assert_eq!(service.status().unwrap_err().code, "disconnected");
    let clone = service.clone();
    let other = thread::spawn(move || clone.shutdown());
    let first = service.shutdown().unwrap_err();
    let second = other.join().unwrap().unwrap_err();
    assert_eq!(first.code, "disconnected");
    assert_eq!(first.message, second.message);
    assert!(first.message.contains("panicked"));
}

#[test]
fn panic_discards_queued_responses_without_hanging() {
    let service = service();
    let release = block_worker(&service);
    service
        .enqueue(Box::new(|_| panic!("injected queued panic")))
        .unwrap();
    let (sender, receiver) = mpsc::channel::<()>();
    service
        .enqueue(Box::new(move |_| {
            sender.send(()).unwrap();
        }))
        .unwrap();
    release.send(()).unwrap();
    assert!(matches!(
        receiver.recv_timeout(Duration::from_secs(5)),
        Err(mpsc::RecvTimeoutError::Disconnected)
    ));
    assert_eq!(service.shutdown().unwrap_err().code, "disconnected");
}

#[test]
fn shutdown_completes_backend_destruction_before_returning() {
    let (dropped_tx, dropped_rx) = mpsc::channel();
    let service = DesktopService::start(move || {
        Ok(Box::new(MemoryRepository {
            _dropped: Some(DropNotice(dropped_tx)),
            ..Default::default()
        }))
    });
    service.shutdown().unwrap();
    dropped_rx.try_recv().unwrap();
    assert_eq!(service.clone().status().unwrap_err().code, "disconnected");
}

#[test]
fn factory_panic_disconnects_without_hanging() {
    let service = DesktopService::start(|| panic!("injected factory panic"));
    assert_eq!(service.status().unwrap_err().code, "disconnected");
    assert_eq!(service.shutdown().unwrap_err().code, "disconnected");
}

#[cfg(target_os = "linux")]
#[test]
fn sqlite_persistence_replay_conflicts_and_lifecycle() {
    let root = tempfile::tempdir().unwrap();
    let library = root.path().join("library");
    let first = library.clone();
    let service = DesktopService::start(move || stow_storage::open_desktop(first));
    let id = exercise_contract(&service);
    service.shutdown().unwrap();
    let service = DesktopService::start(move || stow_storage::open_desktop(library));
    assert_eq!(
        service.get(id).unwrap().item.text_content.as_deref(),
        Some("Saved")
    );
    service.shutdown().unwrap();
}
