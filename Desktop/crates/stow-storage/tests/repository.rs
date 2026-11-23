#![cfg(all(unix, not(target_os = "macos")))]

use std::fs;
use std::io::{self, Read, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt, symlink};

use chrono::Utc;
use rusqlite::Connection;
use sha2::{Digest, Sha256};
use stow_core::{Item, ItemType};
use stow_storage::{DeleteOutcome, Error, LocalRepository, MAX_ATTACHMENT_BYTES};
use tempfile::TempDir;
use uuid::Uuid;

fn fixture() -> (TempDir, std::path::PathBuf) {
    let temp = TempDir::new().unwrap();
    let root = temp.path().join("library");
    (temp, root)
}

fn item(title: &str) -> Item {
    Item::new(ItemType::Text, title, Utc::now())
}

fn private_file(path: &std::path::Path, bytes: &[u8]) {
    let mut file = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .open(path)
        .unwrap();
    file.write_all(bytes).unwrap();
    file.sync_all().unwrap();
}

#[test]
fn snapshots_index_and_blobs_survive_restart_and_delete() {
    let (_temp, root) = fixture();
    let mut repository = LocalRepository::open(&root).unwrap();
    let mut first = item("hello world");
    first.note = Some("note needle".into());
    repository.upsert(&first).unwrap();
    let attachment = repository.attach(first.id, b"binary\0payload").unwrap();
    assert_eq!(repository.search("needle").unwrap(), vec![first.clone()]);
    first.title = "replacement title".into();
    first.note = None;
    repository.upsert(&first).unwrap();
    assert!(repository.search("needle").unwrap().is_empty());
    assert!(repository.search("hello").unwrap().is_empty());
    repository.rebuild_index().unwrap();
    drop(repository);
    let mut repository = LocalRepository::open(&root).unwrap();
    assert_eq!(repository.get(first.id).unwrap(), Some(first.clone()));
    assert_eq!(repository.list().unwrap(), vec![first.clone()]);
    assert_eq!(
        repository.search("replacement").unwrap(),
        vec![first.clone()]
    );
    assert_eq!(
        repository.read_attachment(attachment.id).unwrap(),
        b"binary\0payload"
    );
    assert_eq!(
        repository.delete(first.id).unwrap(),
        DeleteOutcome {
            deleted: true,
            cleanup_pending: false
        }
    );
    assert_eq!(
        repository.delete(first.id).unwrap(),
        DeleteOutcome {
            deleted: false,
            cleanup_pending: false
        }
    );
    assert!(repository.list().unwrap().is_empty());
    assert!(repository.search("replacement").unwrap().is_empty());
    assert!(matches!(
        repository.read_attachment(attachment.id),
        Err(Error::AttachmentNotFound)
    ));
    assert_eq!(fs::read_dir(root.join("blobs")).unwrap().count(), 0);
    drop(repository);
    assert!(
        LocalRepository::open(root)
            .unwrap()
            .list()
            .unwrap()
            .is_empty()
    );
}

#[test]
fn attachments_are_rediscovered_from_only_item_id_after_reopen() {
    let (_temp, root) = fixture();
    let item_id = {
        let mut repository = LocalRepository::open(&root).unwrap();
        let first = item("attachments");
        let other = item("other");
        repository.upsert(&first).unwrap();
        repository.upsert(&other).unwrap();
        repository.attach(first.id, b"first").unwrap();
        repository.attach(first.id, b"second").unwrap();
        repository.attach(other.id, b"unrelated").unwrap();
        assert!(repository.attachments(Uuid::new_v4()).unwrap().is_empty());
        first.id
    };
    let repository = LocalRepository::open(&root).unwrap();
    let attachments = repository.attachments(item_id).unwrap();
    assert_eq!(attachments.len(), 2);
    assert!(attachments[0].id < attachments[1].id);
    assert_eq!(repository.attachments(item_id).unwrap(), attachments);
    let mut contents = Vec::new();
    for info in attachments {
        assert_eq!(info.item_id, item_id);
        assert_eq!(
            repository.attachment_info(info.id).unwrap(),
            Some(info.clone())
        );
        let bytes = repository.read_attachment(info.id).unwrap();
        assert_eq!(info.byte_count, bytes.len() as u64);
        contents.push(bytes);
    }
    contents.sort();
    assert_eq!(contents, vec![b"first".to_vec(), b"second".to_vec()]);
}

#[test]
fn delete_reports_committed_outcome_when_unrelated_blob_is_corrupt() {
    for reopen in [false, true] {
        let (_temp, root) = fixture();
        let mut repository = LocalRepository::open(&root).unwrap();
        let deleted = item("deleted");
        let retained = item("retained");
        repository.upsert(&deleted).unwrap();
        repository.upsert(&retained).unwrap();
        let orphan = repository.attach(deleted.id, b"orphan").unwrap();
        let kept = repository.attach(retained.id, b"original").unwrap();
        let orphan_path = root.join("blobs").join(orphan.id.to_string());
        let kept_path = root.join("blobs").join(kept.id.to_string());
        fs::write(&kept_path, b"modified").unwrap();
        assert_eq!(
            repository.delete(deleted.id).unwrap(),
            DeleteOutcome {
                deleted: true,
                cleanup_pending: true,
            }
        );
        assert!(repository.get(deleted.id).unwrap().is_none());
        assert!(repository.search("deleted").unwrap().is_empty());
        assert!(repository.attachments(deleted.id).unwrap().is_empty());
        assert!(orphan_path.exists());
        assert_eq!(
            repository.delete(deleted.id).unwrap(),
            DeleteOutcome {
                deleted: false,
                cleanup_pending: true,
            }
        );
        if reopen {
            drop(repository);
            assert!(matches!(
                LocalRepository::open(&root),
                Err(Error::CorruptAttachment)
            ));
            assert!(orphan_path.exists());
            fs::write(&kept_path, b"original").unwrap();
            repository = LocalRepository::open(&root).unwrap();
        } else {
            fs::write(&kept_path, b"original").unwrap();
            assert_eq!(
                repository.delete(deleted.id).unwrap(),
                DeleteOutcome {
                    deleted: false,
                    cleanup_pending: false,
                }
            );
        }
        assert!(!orphan_path.exists());
        assert!(repository.get(deleted.id).unwrap().is_none());
        assert_eq!(repository.get(retained.id).unwrap(), Some(retained));
        assert_eq!(repository.read_attachment(kept.id).unwrap(), b"original");
    }
}

#[test]
fn delete_failure_before_commit_rolls_back() {
    let (_temp, root) = fixture();
    let mut repository = LocalRepository::open(&root).unwrap();
    let first = item("preserved");
    repository.upsert(&first).unwrap();
    let attachment = repository.attach(first.id, b"preserved").unwrap();
    let db = Connection::open(root.join("library.sqlite3")).unwrap();
    db.execute_batch(
        "CREATE TRIGGER reject_delete BEFORE DELETE ON items
        BEGIN SELECT RAISE(ABORT, 'injected failure'); END;",
    )
    .unwrap();
    assert!(matches!(repository.delete(first.id), Err(Error::Sqlite(_))));
    assert_eq!(repository.get(first.id).unwrap(), Some(first.clone()));
    assert_eq!(repository.search("preserved").unwrap(), vec![first]);
    assert_eq!(
        repository.read_attachment(attachment.id).unwrap(),
        b"preserved"
    );
}

#[test]
fn dangling_references_fail_before_open_or_delete_cleanup() {
    for reopen in [false, true] {
        let (_temp, root) = fixture();
        let mut repository = LocalRepository::open(&root).unwrap();
        let first = item("missing parent");
        repository.upsert(&first).unwrap();
        let attachment = repository.attach(first.id, b"committed").unwrap();
        let stage = root
            .join("staging")
            .join(format!("{}.part", Uuid::new_v4()));
        let orphan = root.join("blobs").join(Uuid::new_v4().to_string());
        private_file(&stage, b"stage");
        private_file(&orphan, b"orphan");
        let db = Connection::open(root.join("library.sqlite3")).unwrap();
        db.execute_batch("PRAGMA foreign_keys=OFF").unwrap();
        db.execute("DELETE FROM items WHERE id=?1", [first.id.to_string()])
            .unwrap();
        drop(db);
        if reopen {
            drop(repository);
            assert!(matches!(
                LocalRepository::open(&root),
                Err(Error::InvalidData)
            ));
        } else {
            assert!(matches!(
                repository.delete(first.id),
                Err(Error::InvalidData)
            ));
            drop(repository);
        }
        assert_eq!(fs::read(&stage).unwrap(), b"stage");
        assert_eq!(fs::read(&orphan).unwrap(), b"orphan");
        assert_eq!(
            fs::read(root.join("blobs").join(attachment.id.to_string())).unwrap(),
            b"committed"
        );
        let db = Connection::open(root.join("library.sqlite3")).unwrap();
        assert_eq!(
            db.query_row("SELECT count(*) FROM attachments", [], |r| r
                .get::<_, i64>(0))
                .unwrap(),
            1
        );
        // Repair the parent externally, then verify normal recovery and reads.
        db.execute(
            "INSERT INTO items(id,snapshot) VALUES (?1,?2)",
            rusqlite::params![first.id.to_string(), serde_json::to_string(&first).unwrap()],
        )
        .unwrap();
        drop(db);
        let repository = LocalRepository::open(&root).unwrap();
        assert_eq!(
            repository.read_attachment(attachment.id).unwrap(),
            b"committed"
        );
        assert!(!stage.exists());
        assert!(!orphan.exists());
    }
}

#[test]
fn one_writer_and_lock_released_on_drop() {
    let (_temp, root) = fixture();
    let repository = LocalRepository::open(&root).unwrap();
    assert!(matches!(LocalRepository::open(&root), Err(Error::Locked)));
    assert!(
        std::process::Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "writer_process_probe"])
            .env("STOW_TEST_LOCK_ROOT", &root)
            .status()
            .unwrap()
            .success()
    );
    drop(repository);
    LocalRepository::open(root).unwrap();
}

#[test]
fn writer_process_probe() {
    if let Some(root) = std::env::var_os("STOW_TEST_LOCK_ROOT") {
        assert!(matches!(LocalRepository::open(root), Err(Error::Locked)));
    }
}

#[test]
fn failed_migration_rolls_back_schema_and_version() {
    let (_temp, root) = fixture();
    drop(LocalRepository::open(&root).unwrap());
    let db = Connection::open(root.join("library.sqlite3")).unwrap();
    // Reconstruct v1 with an unexpected index, so migration 2 fails.
    db.execute_batch(
        "DROP INDEX items_fingerprint; DROP TABLE capture_receipts; DROP TABLE representations;
        ALTER TABLE attachments DROP COLUMN metadata; PRAGMA user_version=1",
    )
    .unwrap();
    drop(db);
    assert!(LocalRepository::open(&root).is_err());
    let db = Connection::open(root.join("library.sqlite3")).unwrap();
    assert_eq!(
        db.pragma_query_value(None, "user_version", |r| r.get::<_, i64>(0))
            .unwrap(),
        1
    );
    db.execute_batch("DROP TABLE item_search").unwrap();
    drop(db);
    LocalRepository::open(root).unwrap();
}

#[test]
fn newer_schema_is_rejected_without_rewriting_version() {
    let (_temp, root) = fixture();
    drop(LocalRepository::open(&root).unwrap());
    let db = Connection::open(root.join("library.sqlite3")).unwrap();
    db.pragma_update(None, "user_version", 99).unwrap();
    drop(db);
    assert!(matches!(
        LocalRepository::open(&root),
        Err(Error::NewerSchema(99))
    ));
    let db = Connection::open(root.join("library.sqlite3")).unwrap();
    assert_eq!(
        db.pragma_query_value(None, "user_version", |r| r.get::<_, i64>(0))
            .unwrap(),
        99
    );
}

#[test]
fn migration_from_version_one_and_repair_missing_index() {
    let (_temp, root) = fixture();
    let mut repository = LocalRepository::open(&root).unwrap();
    let first = item("migration fixture");
    repository.upsert(&first).unwrap();
    drop(repository);
    let db = Connection::open(root.join("library.sqlite3")).unwrap();
    db.execute_batch(
        "DROP INDEX items_fingerprint; DROP TABLE item_search; DROP TABLE capture_receipts;
        DROP TABLE representations; ALTER TABLE attachments DROP COLUMN metadata;
        PRAGMA user_version=1",
    )
    .unwrap();
    drop(db);
    let repository = LocalRepository::open(&root).unwrap();
    assert_eq!(repository.search("migration").unwrap(), vec![first.clone()]);
    drop(repository);
    let db = Connection::open(root.join("library.sqlite3")).unwrap();
    db.execute_batch("DROP TABLE item_search").unwrap();
    drop(db);
    assert_eq!(
        LocalRepository::open(root)
            .unwrap()
            .search("fixture")
            .unwrap(),
        vec![first]
    );
}

#[test]
fn snapshot_change_rolls_back_when_index_update_fails() {
    let (_temp, root) = fixture();
    let mut repository = LocalRepository::open(&root).unwrap();
    let mut first = item("original");
    repository.upsert(&first).unwrap();
    // Test-only corruption through a second raw connection; never a public API.
    let db = Connection::open(root.join("library.sqlite3")).unwrap();
    db.execute_batch("DROP TABLE item_search").unwrap();
    first.title = "must rollback".into();
    assert!(repository.upsert(&first).is_err());
    assert_eq!(repository.get(first.id).unwrap().unwrap().title, "original");
    repository.rebuild_index().unwrap();
    assert_eq!(repository.search("original").unwrap().len(), 1);
}

#[test]
fn query_is_literal_and_invalid_queries_are_errors() {
    let (_temp, root) = fixture();
    let mut repository = LocalRepository::open(root).unwrap();
    repository.upsert(&item("alpha beta")).unwrap();
    repository.upsert(&item("gamma")).unwrap();
    assert_eq!(repository.search("alpha beta").unwrap().len(), 1);
    for query in [
        "alpha OR gamma",
        "alpha*",
        "\" OR *",
        "NEAR(alpha gamma)",
        "' ; DROP TABLE items; --",
        "()",
    ] {
        // No query can execute a boolean operator, wildcard, or SQL statement.
        assert!(repository.search(query).is_ok());
    }
    assert!(repository.search("alpha OR gamma").unwrap().is_empty());
    assert_eq!(repository.list().unwrap().len(), 2);
    for query in ["", "  ", "alpha\0beta", "alpha\nbeta", &"x".repeat(4097)] {
        assert!(matches!(repository.search(query), Err(Error::InvalidQuery)));
    }
}

#[test]
fn interrupted_staging_and_orphan_publication_are_recovered() {
    let (_temp, root) = fixture();
    let mut repository = LocalRepository::open(&root).unwrap();
    let first = item("preserved");
    repository.upsert(&first).unwrap();
    let attachment = repository.attach(first.id, b"committed").unwrap();
    drop(repository);
    // After partial write, after file sync, after publication, and between link
    // and unlink. None has a committed reference and all must be removed.
    for bytes in [b"partial".as_slice(), b"fully staged"] {
        private_file(
            &root
                .join("staging")
                .join(format!("{}.part", Uuid::new_v4())),
            bytes,
        );
    }
    private_file(
        &root.join("blobs").join(Uuid::new_v4().to_string()),
        b"published orphan",
    );
    let id = Uuid::new_v4();
    let stage = root.join("staging").join(format!("{id}.part"));
    private_file(&stage, b"linked orphan");
    fs::hard_link(stage, root.join("blobs").join(id.to_string())).unwrap();
    let repository = LocalRepository::open(&root).unwrap();
    assert_eq!(
        repository.read_attachment(attachment.id).unwrap(),
        b"committed"
    );
    assert_eq!(fs::read_dir(root.join("staging")).unwrap().count(), 0);
    assert_eq!(fs::read_dir(root.join("blobs")).unwrap().count(), 1);
}

struct InterruptedReader;
impl Read for InterruptedReader {
    fn read(&mut self, _: &mut [u8]) -> io::Result<usize> {
        Err(io::Error::other("injected interruption"))
    }
}

#[test]
fn failed_staging_never_commits_and_restart_removes_it() {
    let (_temp, root) = fixture();
    let mut repository = LocalRepository::open(&root).unwrap();
    let first = item("item");
    repository.upsert(&first).unwrap();
    assert!(
        repository
            .attach_reader(first.id, InterruptedReader, 1, [0; 32])
            .is_err()
    );
    assert!(matches!(
        repository.attach_reader(first.id, b"a".as_slice(), 1, [0; 32]),
        Err(Error::CorruptAttachment)
    ));
    assert!(matches!(
        repository.attach_reader(first.id, b"a".as_slice(), 2, Sha256::digest(b"a").into()),
        Err(Error::CorruptAttachment)
    ));
    assert!(matches!(
        repository.attach_reader(first.id, io::empty(), MAX_ATTACHMENT_BYTES + 1, [0; 32]),
        Err(Error::AttachmentTooLarge)
    ));
    assert!(matches!(
        repository.attach(Uuid::new_v4(), b"x"),
        Err(Error::ItemNotFound)
    ));
    assert_eq!(fs::read_dir(root.join("blobs")).unwrap().count(), 0);
    drop(repository);
    LocalRepository::open(&root).unwrap();
    assert_eq!(fs::read_dir(root.join("staging")).unwrap().count(), 0);
}

#[test]
fn dishonest_stream_is_bounded() {
    let (_temp, root) = fixture();
    let mut repository = LocalRepository::open(root).unwrap();
    let first = item("item");
    repository.upsert(&first).unwrap();
    assert!(matches!(
        repository.attach_reader(first.id, io::repeat(0), 0, [0; 32]),
        Err(Error::AttachmentTooLarge)
    ));
}

#[test]
fn corruption_and_missing_committed_bytes_fail_closed() {
    for missing in [false, true] {
        let (_temp, root) = fixture();
        let mut repository = LocalRepository::open(&root).unwrap();
        let first = item("item");
        repository.upsert(&first).unwrap();
        let attachment = repository.attach(first.id, b"original").unwrap();
        let path = root.join("blobs").join(attachment.id.to_string());
        if missing {
            fs::remove_file(path).unwrap();
        } else {
            fs::write(path, b"modified").unwrap();
        }
        assert!(repository.read_attachment(attachment.id).is_err());
        drop(repository);
        assert!(LocalRepository::open(root).is_err());
    }
}

#[test]
fn unsafe_permissions_and_symlinks_are_rejected_without_following() {
    let (temp, root) = fixture();
    fs::create_dir(&root).unwrap();
    fs::set_permissions(&root, fs::Permissions::from_mode(0o755)).unwrap();
    assert!(matches!(
        LocalRepository::open(&root),
        Err(Error::UnsafePath)
    ));
    fs::set_permissions(&root, fs::Permissions::from_mode(0o700)).unwrap();
    drop(LocalRepository::open(&root).unwrap());
    let outside = temp.path().join("outside");
    private_file(&outside, b"do not change");
    for name in [
        "writer.lock",
        "library.sqlite3",
        "library.sqlite3-journal",
        "library.sqlite3-wal",
        "library.sqlite3-shm",
    ] {
        let path = root.join(name);
        let saved = root.join(format!("{name}.saved"));
        if path.exists() {
            fs::rename(&path, &saved).unwrap();
        }
        symlink(&outside, &path).unwrap();
        assert!(matches!(
            LocalRepository::open(&root),
            Err(Error::UnsafePath)
        ));
        fs::remove_file(&path).unwrap();
        if saved.exists() {
            fs::rename(saved, path).unwrap();
        }
    }
    for directory in ["staging", "blobs"] {
        let path = root.join(directory).join(if directory == "staging" {
            format!("{}.part", Uuid::new_v4())
        } else {
            Uuid::new_v4().to_string()
        });
        symlink(&outside, &path).unwrap();
        assert!(matches!(
            LocalRepository::open(&root),
            Err(Error::UnsafePath)
        ));
        fs::remove_file(path).unwrap();
    }
    let alias = temp.path().join("alias");
    symlink(&root, &alias).unwrap();
    assert!(matches!(
        LocalRepository::open(&alias),
        Err(Error::UnsafePath)
    ));
    assert!(matches!(
        LocalRepository::open(alias.join("nested")),
        Err(Error::UnsafePath)
    ));
    assert_eq!(fs::read(outside).unwrap(), b"do not change");
}

#[test]
fn committed_attachment_symlink_is_not_read() {
    let (temp, root) = fixture();
    let mut repository = LocalRepository::open(&root).unwrap();
    let first = item("item");
    repository.upsert(&first).unwrap();
    let attachment = repository.attach(first.id, b"content").unwrap();
    let outside = temp.path().join("outside");
    private_file(&outside, b"content");
    let blob = root.join("blobs").join(attachment.id.to_string());
    fs::remove_file(&blob).unwrap();
    symlink(outside, blob).unwrap();
    assert!(matches!(
        repository.read_attachment(attachment.id),
        Err(Error::UnsafePath)
    ));
}
