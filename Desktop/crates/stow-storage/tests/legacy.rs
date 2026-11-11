#![cfg(target_os = "linux")]

use std::fs::{DirBuilder, OpenOptions};
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};

use chrono::DateTime;
use rusqlite::{Connection, params};
use stow_core::{CaptureDraft, Item, ItemStatus, ItemType};
use stow_storage::{CaptureKind, LocalRepository};
use tempfile::TempDir;

#[test]
fn real_v2_schema_preserves_legacy_fingerprint_without_matching_local_captures() {
    let directory = TempDir::new().unwrap();
    let root = directory.path().join("library");
    DirBuilder::new().mode(0o700).create(&root).unwrap();
    let database = root.join("library.sqlite3");
    OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(&database)
        .unwrap();
    let connection = Connection::open(&database).unwrap();
    // Construct the old schema directly. No current migration is run or undone.
    connection
        .execute_batch(
            "CREATE TABLE items (id TEXT PRIMARY KEY NOT NULL, snapshot TEXT NOT NULL);
         CREATE TABLE attachments (
           id TEXT PRIMARY KEY NOT NULL,
           item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
           byte_count INTEGER NOT NULL CHECK(byte_count BETWEEN 0 AND 104857600),
           sha256 TEXT NOT NULL CHECK(length(sha256) = 64));
         CREATE VIRTUAL TABLE item_search USING fts5(id UNINDEXED, content, tokenize='unicode61');
         PRAGMA user_version=2;",
        )
        .unwrap();
    let at = DateTime::from_timestamp(1000, 0).unwrap();
    let mut legacy = Item::new(ItemType::Text, "User title", at);
    legacy.text_content = Some("Hello\r\nworld".into());
    legacy.content_fingerprint =
        Some("v1:7ae10e25b69a6bb6514cabad2f01d8c8ad3c7ab43693746abbe8f6062a506888".into());
    legacy.status = ItemStatus::Archived;
    legacy.is_pinned = true;
    legacy.note = Some("Preserve this note".into());
    connection
        .execute(
            "INSERT INTO items(id,snapshot) VALUES (?1,?2)",
            params![
                legacy.id.to_string(),
                serde_json::to_string(&legacy).unwrap()
            ],
        )
        .unwrap();
    drop(connection);

    let mut repository = LocalRepository::open(&root).unwrap();
    assert_eq!(repository.get(legacy.id).unwrap(), Some(legacy.clone()));
    let mut draft = CaptureDraft::new(ItemType::Text, "New clipboard item");
    draft.text_content = legacy.text_content.clone();
    let captured = repository.ingest_clipboard(&draft, None, &[], at).unwrap();
    assert_eq!(captured.kind, CaptureKind::Created);
    assert_ne!(captured.item.id, legacy.id);
    assert!(
        captured
            .item
            .content_fingerprint
            .as_ref()
            .unwrap()
            .starts_with("local-1:v1:")
    );
    assert_eq!(repository.get(legacy.id).unwrap(), Some(legacy.clone()));
    draft.id = legacy.capture_id;
    let replay = repository.create(&draft, None, &[], at).unwrap();
    assert_eq!(replay.kind, CaptureKind::Replayed);
    assert_eq!(replay.item, legacy);
    assert_eq!(repository.list().unwrap().len(), 2);
}
