#![cfg(all(unix, not(target_os = "macos")))]
use chrono::{TimeDelta, TimeZone, Utc};
use rusqlite::Connection;
use std::fs;
use stow_core::{CaptureDraft, ItemStatus, ItemType, RepresentationDraft, representation_type};
use stow_storage::{AttachmentDraft, CaptureKind, ItemCommand, ItemEdit, LocalRepository};
use tempfile::TempDir;
use uuid::Uuid;

fn at() -> chrono::DateTime<Utc> {
    Utc.timestamp_opt(1000, 0).unwrap()
}
fn text(body: &str) -> CaptureDraft {
    let mut d = CaptureDraft::new(ItemType::Text, "Original");
    d.text_content = Some(body.into());
    d.source_app = Some("Notes".into());
    d
}
fn reps() -> Vec<RepresentationDraft> {
    vec![
        RepresentationDraft {
            type_identifier: representation_type::HTML.into(),
            data: b"<b>body</b>".to_vec(),
            ordinal: 8,
        },
        RepresentationDraft {
            type_identifier: representation_type::RTF.into(),
            data: b"{\\rtf1 body}".to_vec(),
            ordinal: 2,
        },
    ]
}
fn image() -> (CaptureDraft, AttachmentDraft) {
    let mut d = CaptureDraft::new(ItemType::Image, "Image");
    d.staged_attachment_name = Some("staged.png".into());
    d.attachment_byte_count = Some(3);
    let a = AttachmentDraft {
        data: vec![1, 2, 3],
        thumbnail_data: Some(vec![4, 5]),
        content_type: "image/png".into(),
        file_name: "original.png".into(),
        pixel_width: Some(4),
        pixel_height: Some(8),
    };
    (d, a)
}

#[test]
fn metadata_bytes_and_original_order_survive_restart_without_duplicate_recapture_bytes() {
    let temp = TempDir::new().unwrap();
    let root = temp.path().join("library");
    let mut repo = LocalRepository::open(&root).unwrap();
    let (draft, a) = image();
    let first = repo
        .ingest_clipboard(&draft, Some(&a), &reps(), at())
        .unwrap();
    let attachment_id = repo.attachments(first.item.id).unwrap()[0].id;
    let mut recopy = draft.clone();
    recopy.id = Uuid::new_v4();
    recopy.title = "Incoming".into();
    assert_eq!(
        repo.ingest_clipboard(&recopy, Some(&a), &reps(), at())
            .unwrap()
            .kind,
        CaptureKind::Coalesced
    );
    assert_eq!(fs::read_dir(root.join("blobs")).unwrap().count(), 3);
    drop(repo);
    let repo = LocalRepository::open(&root).unwrap();
    let saved = repo.load_attachment(attachment_id).unwrap().unwrap();
    assert_eq!(saved.data, a.data);
    assert_eq!(saved.thumbnail_data, a.thumbnail_data);
    assert_eq!(saved.content_type, a.content_type);
    assert_eq!(saved.file_name, a.file_name);
    assert_eq!((saved.pixel_width, saved.pixel_height), (Some(4), Some(8)));
    assert_eq!(saved.byte_count, 3);
    assert_eq!(saved.created_at, at());
    let rs = repo.representations(first.item.id).unwrap();
    assert_eq!(rs.iter().map(|r| r.ordinal).collect::<Vec<_>>(), vec![2, 8]);
    assert_eq!(rs[0].data, reps()[1].data);
    assert_eq!(rs[1].data, reps()[0].data);
    assert!(rs.iter().all(|r| r.item_id == first.item.id
        && r.created_at == at()
        && r.byte_count == r.data.len() as i64));
}

#[test]
fn clipboard_coalesce_preserves_edits_state_and_receipts_prevent_replay_changes() {
    let temp = TempDir::new().unwrap();
    let root = temp.path().join("library");
    let mut repo = LocalRepository::open(&root).unwrap();
    let first = repo.create(&text("body"), None, &[], at()).unwrap().item;
    repo.update(
        first.id,
        &ItemEdit {
            title: "User title".into(),
            note: Some("note".into()),
            text_content: Some("body".into()),
            language: None,
        },
        at(),
    )
    .unwrap();
    repo.apply(&[first.id], ItemCommand::Archive, at()).unwrap();
    repo.apply(&[first.id], ItemCommand::SetPinned(true), at())
        .unwrap();
    repo.apply(&[first.id], ItemCommand::RecordSuccessfulUse, at())
        .unwrap();
    let mut copy = text("body");
    copy.source_app = Some("Terminal".into());
    let captured = repo
        .ingest_clipboard(&copy, None, &[], at() + TimeDelta::seconds(1))
        .unwrap();
    assert_eq!(captured.kind, CaptureKind::Coalesced);
    assert_eq!(captured.item.id, first.id);
    assert_eq!(captured.item.title, "User title");
    assert_eq!(captured.item.note.as_deref(), Some("note"));
    assert!(captured.item.is_pinned);
    assert_eq!(captured.item.status, ItemStatus::Archived);
    assert_eq!(captured.item.use_count, 1);
    assert_eq!(captured.item.source_app.as_deref(), Some("Terminal"));
    repo.apply(&[first.id], ItemCommand::Trash, at()).unwrap();
    drop(repo);
    let mut repo = LocalRepository::open(&root).unwrap();
    let replay = repo
        .ingest_clipboard(&copy, None, &[], at() + TimeDelta::seconds(100))
        .unwrap();
    assert_eq!(replay.kind, CaptureKind::Replayed);
    assert_eq!(replay.item.status, ItemStatus::Trashed);
    assert_eq!(replay.item.last_captured_at, captured.item.last_captured_at);
    let fresh = repo
        .ingest_clipboard(&text("body"), None, &[], at())
        .unwrap();
    assert_eq!(fresh.kind, CaptureKind::Created);
    assert_eq!(fresh.item.status, ItemStatus::Inbox);
    assert_ne!(fresh.item.id, first.id);
    // Manual captures never coalesce by content.
    assert_eq!(
        repo.create(&text("body"), None, &[], at()).unwrap().kind,
        CaptureKind::Created
    );
}

#[test]
fn capture_id_replay_does_not_reintroduce_stale_representations_after_edit() {
    let temp = TempDir::new().unwrap();
    let root = temp.path().join("library");
    let mut repo = LocalRepository::open(&root).unwrap();
    let draft = text("body");
    let first = repo.create(&draft, None, &reps(), at()).unwrap().item;
    let old_fingerprint = first.content_fingerprint;
    repo.update(
        first.id,
        &ItemEdit {
            title: "Renamed".into(),
            note: None,
            text_content: Some("body".into()),
            language: None,
        },
        at(),
    )
    .unwrap();
    assert_eq!(repo.representations(first.id).unwrap().len(), 2);
    assert_eq!(
        repo.get(first.id).unwrap().unwrap().content_fingerprint,
        old_fingerprint
    );
    repo.update(
        first.id,
        &ItemEdit {
            title: "Renamed".into(),
            note: None,
            text_content: Some("  edited\n".into()),
            language: None,
        },
        at(),
    )
    .unwrap();
    assert!(repo.representations(first.id).unwrap().is_empty());
    assert_ne!(
        repo.get(first.id).unwrap().unwrap().content_fingerprint,
        old_fingerprint
    );
    assert_eq!(
        repo.create(&draft, None, &reps(), at()).unwrap().kind,
        CaptureKind::Replayed
    );
    assert!(repo.representations(first.id).unwrap().is_empty());
    assert_eq!(
        repo.ingest_clipboard(&text("  edited\n"), None, &[], at())
            .unwrap()
            .item
            .id,
        first.id
    );
    drop(repo);
    let repo = LocalRepository::open(&root).unwrap();
    assert_eq!(
        repo.get(first.id).unwrap().unwrap().text_content.as_deref(),
        Some("  edited\n")
    );
    assert_eq!(fs::read_dir(root.join("blobs")).unwrap().count(), 0);
}

#[test]
fn empty_regular_files_are_supported() {
    let temp = TempDir::new().unwrap();
    let root = temp.path().join("library");
    let mut repo = LocalRepository::open(&root).unwrap();
    let (mut draft, mut attachment) = image();
    draft.item_type = ItemType::File;
    draft.attachment_byte_count = Some(0);
    attachment.data.clear();
    attachment.content_type = "application/octet-stream".into();
    let item = repo
        .create(&draft, Some(&attachment), &[], at())
        .unwrap()
        .item;
    let id = repo.attachments(item.id).unwrap()[0].id;
    drop(repo);
    let repo = LocalRepository::open(&root).unwrap();
    assert!(repo.load_attachment(id).unwrap().unwrap().data.is_empty());
}

#[test]
fn validation_rejects_all_payloads_before_any_publication() {
    let temp = TempDir::new().unwrap();
    let root = temp.path().join("library");
    let mut repo = LocalRepository::open(&root).unwrap();
    let (d, a) = image();
    let mut invalid = reps();
    invalid[1].type_identifier = "unknown".into();
    assert!(repo.create(&d, Some(&a), &invalid, at()).is_err());
    let mut bad = a.clone();
    bad.data.push(4);
    assert!(repo.create(&d, Some(&bad), &[], at()).is_err());
    let mut bad = a.clone();
    bad.content_type = "text/plain".into();
    assert!(repo.create(&d, Some(&bad), &[], at()).is_err());
    assert!(repo.create(&d, None, &[], at()).is_err());
    assert!(
        repo.create(
            &text(&"x".repeat(stow_core::PLAIN_TEXT_BYTES + 1)),
            None,
            &[],
            at()
        )
        .is_err()
    );
    assert_eq!(fs::read_dir(root.join("staging")).unwrap().count(), 0);
    assert_eq!(fs::read_dir(root.join("blobs")).unwrap().count(), 0);
    assert!(repo.list().unwrap().is_empty());
}

#[test]
fn failed_database_commit_rolls_back_entire_capture_and_restart_cleans_orphans() {
    let temp = TempDir::new().unwrap();
    let root = temp.path().join("library");
    let mut repo = LocalRepository::open(&root).unwrap();
    let db = Connection::open(root.join("library.sqlite3")).unwrap();
    db.execute_batch("CREATE TRIGGER fail_capture BEFORE INSERT ON representations BEGIN SELECT RAISE(ABORT,'injected'); END;").unwrap();
    let (draft, a) = image();
    assert!(repo.create(&draft, Some(&a), &reps(), at()).is_err());
    assert!(repo.list().unwrap().is_empty());
    for table in [
        "items",
        "attachments",
        "representations",
        "capture_receipts",
    ] {
        let count: i64 = db
            .query_row(&format!("SELECT count(*) FROM {table}"), [], |r| r.get(0))
            .unwrap();
        assert_eq!(count, 0);
    }
    assert_eq!(fs::read_dir(root.join("blobs")).unwrap().count(), 3);
    db.execute_batch("DROP TRIGGER fail_capture").unwrap();
    drop(db);
    drop(repo);
    let mut repo = LocalRepository::open(&root).unwrap();
    assert_eq!(fs::read_dir(root.join("blobs")).unwrap().count(), 0);
    assert_eq!(
        repo.create(&draft, Some(&a), &reps(), at()).unwrap().kind,
        CaptureKind::Created
    );
}

#[test]
fn publication_failure_never_commits_item_and_batch_mutation_is_atomic() {
    let temp = TempDir::new().unwrap();
    let root = temp.path().join("library");
    let mut repo = LocalRepository::open(&root).unwrap();
    fs::remove_dir(root.join("blobs")).unwrap();
    let (draft, a) = image();
    assert!(repo.create(&draft, Some(&a), &[], at()).is_err());
    assert!(repo.list().unwrap().is_empty());
    let item = repo.create(&text("body"), None, &[], at()).unwrap().item;
    assert!(
        repo.apply(&[item.id, Uuid::new_v4()], ItemCommand::Trash, at())
            .is_err()
    );
    assert_eq!(
        repo.get(item.id).unwrap().unwrap().status,
        ItemStatus::Inbox
    );
}

#[test]
fn purge_cascades_all_owned_metadata_receipts_and_blobs() {
    let temp = TempDir::new().unwrap();
    let root = temp.path().join("library");
    let mut repo = LocalRepository::open(&root).unwrap();
    let (draft, a) = image();
    let item = repo.create(&draft, Some(&a), &reps(), at()).unwrap().item;
    repo.apply(&[item.id], ItemCommand::Trash, at()).unwrap();
    assert_eq!(
        repo.purge_expired_trash(at() + TimeDelta::days(30), 30)
            .unwrap(),
        1
    );
    assert!(repo.attachments(item.id).unwrap().is_empty());
    assert!(repo.representations(item.id).unwrap().is_empty());
    assert_eq!(fs::read_dir(root.join("blobs")).unwrap().count(), 0);
    let db = Connection::open(root.join("library.sqlite3")).unwrap();
    let count: i64 = db
        .query_row("SELECT count(*) FROM capture_receipts", [], |r| r.get(0))
        .unwrap();
    assert_eq!(count, 0);
    assert!(repo.search("Image").unwrap().is_empty());
}

#[test]
fn failed_coalesce_and_edit_leave_snapshot_and_representations_unchanged() {
    let temp = TempDir::new().unwrap();
    let root = temp.path().join("library");
    let mut repo = LocalRepository::open(&root).unwrap();
    let first = repo
        .create(&text("body"), None, &reps(), at())
        .unwrap()
        .item;
    let original_reps = repo.representations(first.id).unwrap();
    let db = Connection::open(root.join("library.sqlite3")).unwrap();
    db.execute_batch("CREATE TRIGGER fail_receipt BEFORE INSERT ON capture_receipts BEGIN SELECT RAISE(ABORT,'injected'); END;").unwrap();
    let mut incoming = text("body");
    incoming.source_app = Some("Terminal".into());
    assert!(
        repo.ingest_clipboard(&incoming, None, &reps(), at() + TimeDelta::seconds(10))
            .is_err()
    );
    assert_eq!(repo.get(first.id).unwrap(), Some(first.clone()));
    assert_eq!(repo.representations(first.id).unwrap(), original_reps);
    db.execute_batch("DROP TRIGGER fail_receipt; CREATE TRIGGER fail_edit BEFORE UPDATE ON items BEGIN SELECT RAISE(ABORT,'injected'); END;").unwrap();
    let edit = ItemEdit {
        title: "Changed".into(),
        note: None,
        text_content: Some("edited".into()),
        language: None,
    };
    assert!(repo.update(first.id, &edit, at()).is_err());
    assert_eq!(repo.get(first.id).unwrap(), Some(first));
    assert_eq!(
        repo.representations(original_reps[0].item_id).unwrap(),
        original_reps
    );
}

#[test]
fn committed_representation_corruption_fails_closed_on_restart() {
    let temp = TempDir::new().unwrap();
    let root = temp.path().join("library");
    let mut repo = LocalRepository::open(&root).unwrap();
    let first = repo
        .create(&text("body"), None, &reps(), at())
        .unwrap()
        .item;
    let representation = repo.representations(first.id).unwrap().remove(0);
    fs::write(
        root.join("blobs").join(representation.id.to_string()),
        b"corrupt",
    )
    .unwrap();
    assert!(repo.representations(first.id).is_err());
    drop(repo);
    assert!(LocalRepository::open(&root).is_err());
    // Failure does not remove any committed file.
    assert_eq!(fs::read_dir(root.join("blobs")).unwrap().count(), 2);
}

#[test]
fn invalid_representation_metadata_is_rejected_without_changing_bytes() {
    let temp = TempDir::new().unwrap();
    let root = temp.path().join("library");
    let mut repo = LocalRepository::open(&root).unwrap();
    let item = repo
        .create(&text("body"), None, &reps(), at())
        .unwrap()
        .item;
    let db = Connection::open(root.join("library.sqlite3")).unwrap();
    let (id, metadata): (String, String) = db
        .query_row(
            "SELECT id,metadata FROM representations WHERE json_extract(metadata,'$.ordinal')=8",
            [],
            |row| Ok((row.get(0)?, row.get(1)?)),
        )
        .unwrap();
    for assignment in [
        "'$.type_identifier','private.format'",
        "'$.type_identifier','public.rtf'",
        "'$.ordinal',-1",
        "'$.ordinal',2",
        "'$.data',json('[1]')",
        "'$.item_id','00000000-0000-0000-0000-000000000000'",
    ] {
        db.execute(
            "UPDATE representations SET metadata=?1 WHERE id=?2",
            rusqlite::params![metadata, id],
        )
        .unwrap();
        db.execute(
            &format!(
                "UPDATE representations SET metadata=json_set(metadata,{assignment}) WHERE id=?1"
            ),
            [&id],
        )
        .unwrap();
        assert!(
            matches!(
                repo.representations(item.id),
                Err(stow_storage::Error::InvalidData)
            ),
            "{assignment}"
        );
        assert_eq!(fs::read_dir(root.join("blobs")).unwrap().count(), 2);
    }
    db.execute(
        "UPDATE representations SET metadata=?1 WHERE id=?2",
        rusqlite::params![metadata, id],
    )
    .unwrap();
    assert_eq!(repo.representations(item.id).unwrap().len(), 2);
}

#[test]
fn attachment_and_representation_id_collision_fails_before_recovery_cleanup() {
    let temp = TempDir::new().unwrap();
    let root = temp.path().join("library");
    let mut repo = LocalRepository::open(&root).unwrap();
    let (draft, attachment) = image();
    let item = repo
        .create(&draft, Some(&attachment), &reps(), at())
        .unwrap()
        .item;
    let attachment_id = repo.attachments(item.id).unwrap()[0].id;
    let db = Connection::open(root.join("library.sqlite3")).unwrap();
    let representation_id = repo.representations(item.id).unwrap()[0].id;
    db.execute(
        "UPDATE representations SET id=?1 WHERE id=?2",
        rusqlite::params![attachment_id.to_string(), representation_id.to_string()],
    )
    .unwrap();
    drop(db);
    drop(repo);
    assert!(matches!(
        LocalRepository::open(&root),
        Err(stow_storage::Error::InvalidData)
    ));
    assert_eq!(fs::read_dir(root.join("blobs")).unwrap().count(), 3);
}

#[test]
fn additive_v2_migration_preserves_snapshots_and_attachment_bytes() {
    let temp = TempDir::new().unwrap();
    let root = temp.path().join("library");
    let mut repo = LocalRepository::open(&root).unwrap();
    let item = repo.create(&text("legacy"), None, &[], at()).unwrap().item;
    let attachment = repo.attach(item.id, b"legacy bytes").unwrap();
    drop(repo);
    let db = Connection::open(root.join("library.sqlite3")).unwrap();
    db.execute_batch("DROP INDEX items_fingerprint; DROP TABLE capture_receipts; DROP TABLE representations; ALTER TABLE attachments DROP COLUMN metadata; PRAGMA user_version=2;").unwrap();
    drop(db);
    let mut repo = LocalRepository::open(&root).unwrap();
    assert_eq!(repo.get(item.id).unwrap(), Some(item.clone()));
    assert_eq!(
        repo.read_attachment(attachment.id).unwrap(),
        b"legacy bytes"
    );
    assert_eq!(repo.attachments(item.id).unwrap(), vec![attachment.clone()]);
    assert_eq!(repo.load_attachment(attachment.id).unwrap(), None);
    let mut replay = text("legacy");
    replay.id = item.capture_id;
    assert_eq!(
        repo.create(&replay, None, &[], at()).unwrap().kind,
        CaptureKind::Replayed
    );
}
