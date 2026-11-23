use std::fs::{self, File};
use std::path::{Path, PathBuf};

use fs2::FileExt;
use rusqlite::{Connection, OptionalExtension, params};
use stow_core::Item;
use uuid::Uuid;

use crate::{Error, Result, paths};

const SCHEMA_VERSION: i64 = 3;
// Only additive migrations exist. A destructive migration must add a durable
// backup before it is included here.
const MIGRATIONS: [&str; 3] = [
    "CREATE TABLE items (id TEXT PRIMARY KEY NOT NULL, snapshot TEXT NOT NULL);
     CREATE TABLE attachments (
       id TEXT PRIMARY KEY NOT NULL,
       item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
       byte_count INTEGER NOT NULL CHECK(byte_count BETWEEN 0 AND 104857600),
       sha256 TEXT NOT NULL CHECK(length(sha256) = 64)
     );",
    "CREATE VIRTUAL TABLE item_search USING fts5(id UNINDEXED, content, tokenize='unicode61');",
    "ALTER TABLE attachments ADD COLUMN metadata TEXT;
     CREATE INDEX items_fingerprint ON items(json_extract(snapshot,'$.content_fingerprint'));
     CREATE TABLE representations (
       id TEXT PRIMARY KEY NOT NULL,
       item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
       byte_count INTEGER NOT NULL CHECK(byte_count BETWEEN 1 AND 104857600),
       sha256 TEXT NOT NULL CHECK(length(sha256)=64),
       metadata TEXT NOT NULL
     );
     CREATE INDEX representations_item ON representations(item_id);
     CREATE TABLE capture_receipts (
       capture_id TEXT PRIMARY KEY NOT NULL,
       item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE
     );
     INSERT OR IGNORE INTO capture_receipts(capture_id,item_id)
       SELECT json_extract(snapshot,'$.capture_id'),id FROM items;",
];

/// Result after the delete transaction commits.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct DeleteOutcome {
    pub deleted: bool,
    pub cleanup_pending: bool,
}

/// One exclusive library writer. Run operations on a storage worker, not a UI thread.
/// All fields are private so callers cannot bypass transactions or blob checks.
pub struct LocalRepository {
    pub(crate) connection: Connection,
    pub(crate) root: PathBuf,
    // Drop the connection before releasing this permanent lock file.
    _lock: File,
}

impl LocalRepository {
    /// Open an absolute private library directory. Does not select a default path.
    /// macOS is rejected to protect the existing SwiftData canonical store.
    /// Windows is blocked until private ACL and durable publication support exists.
    pub fn open(root: impl AsRef<Path>) -> Result<Self> {
        if cfg!(target_os = "macos") || !cfg!(unix) {
            return Err(Error::UnsupportedPlatform);
        }
        let root = root.as_ref();
        paths::private_dir(root)?;
        let lock = paths::open_file(&root.join("writer.lock"), true, true)?;
        lock.try_lock_exclusive().map_err(|error| {
            if error.kind() == std::io::ErrorKind::WouldBlock {
                Error::Locked
            } else {
                Error::Io(error)
            }
        })?;
        for name in [
            "library.sqlite3",
            "library.sqlite3-journal",
            "library.sqlite3-wal",
            "library.sqlite3-shm",
        ] {
            match fs::symlink_metadata(root.join(name)) {
                Ok(_) => paths::check_file(&root.join(name))?,
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => (),
                Err(error) => return Err(error.into()),
            }
        }
        // Pre-create with mode 0600; SQLite journal files inherit database mode.
        paths::open_file(&root.join("library.sqlite3"), true, true)?.sync_all()?;
        paths::sync_dir(root)?;
        let mut connection = Connection::open_with_flags(
            root.join("library.sqlite3"),
            rusqlite::OpenFlags::SQLITE_OPEN_READ_WRITE
                | rusqlite::OpenFlags::SQLITE_OPEN_NO_MUTEX
                | rusqlite::OpenFlags::SQLITE_OPEN_NOFOLLOW,
        )?;
        let version: i64 = connection.pragma_query_value(None, "user_version", |r| r.get(0))?;
        if version > SCHEMA_VERSION {
            return Err(Error::NewerSchema(version));
        }
        if version < 0 {
            return Err(Error::InvalidData);
        }
        connection.execute_batch(
            "PRAGMA foreign_keys=ON; PRAGMA journal_mode=DELETE; PRAGMA synchronous=EXTRA;",
        )?;
        for next in version + 1..=SCHEMA_VERSION {
            let transaction = connection.transaction()?;
            transaction.execute_batch(MIGRATIONS[(next - 1) as usize])?;
            transaction.pragma_update(None, "user_version", next)?;
            transaction.commit()?;
        }
        validate_foreign_keys(&connection)?;
        paths::private_dir(&root.join("staging"))?;
        paths::private_dir(&root.join("blobs"))?;
        let mut repository = Self {
            connection,
            root: root.to_owned(),
            _lock: lock,
        };
        repository.recover_attachments()?;
        // The index has no unique data. Rebuild on every open, including an
        // interrupted old rebuild or an index deleted outside this API.
        repository.rebuild_index()?;
        Ok(repository)
    }

    pub fn upsert(&mut self, item: &Item) -> Result<()> {
        let snapshot = serde_json::to_string(item)?;
        let transaction = self.connection.transaction()?;
        let owner: Option<String> = transaction
            .query_row(
                "SELECT item_id FROM capture_receipts WHERE capture_id=?1",
                [item.capture_id.to_string()],
                |r| r.get(0),
            )
            .optional()?;
        if owner.is_some_and(|id| id != item.id.to_string()) {
            return Err(Error::InvalidData);
        }
        transaction.execute(
            "INSERT INTO items(id,snapshot) VALUES (?1,?2)
             ON CONFLICT(id) DO UPDATE SET snapshot=excluded.snapshot",
            params![item.id.to_string(), snapshot],
        )?;
        transaction.execute(
            "INSERT OR IGNORE INTO capture_receipts(capture_id,item_id) VALUES (?1,?2)",
            params![item.capture_id.to_string(), item.id.to_string()],
        )?;
        crate::search::index_item(&transaction, item)?;
        transaction.commit()?;
        Ok(())
    }

    pub fn get(&self, id: Uuid) -> Result<Option<Item>> {
        let snapshot: Option<String> = self
            .connection
            .query_row(
                "SELECT snapshot FROM items WHERE id=?1",
                [id.to_string()],
                |r| r.get(0),
            )
            .optional()?;
        snapshot
            .map(|snapshot| decode_item(id, &snapshot))
            .transpose()
    }

    /// Stable UUID order. Higher-level application ordering is not defined here.
    pub fn list(&self) -> Result<Vec<Item>> {
        let mut statement = self
            .connection
            .prepare("SELECT id,snapshot FROM items ORDER BY id")?;
        let rows =
            statement.query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?;
        rows.map(|row| {
            let (id, snapshot) = row?;
            decode_item(
                Uuid::parse_str(&id).map_err(|_| Error::InvalidData)?,
                &snapshot,
            )
        })
        .collect()
    }

    /// Commit references first. A failed cleanup leaves an orphan, never a
    /// committed reference to a deliberately removed blob. Open or another delete
    /// retries cleanup. Errors are returned only before the transaction commits.
    pub fn delete(&mut self, id: Uuid) -> Result<DeleteOutcome> {
        validate_foreign_keys(&self.connection)?;
        let transaction = self.connection.transaction()?;
        crate::search::remove_item(&transaction, id)?;
        let changed = transaction.execute("DELETE FROM items WHERE id=?1", [id.to_string()])?;
        transaction.commit()?;
        let cleanup_pending = self.recover_attachments().is_err();
        Ok(DeleteOutcome {
            deleted: changed != 0,
            cleanup_pending,
        })
    }

    pub fn rebuild_index(&mut self) -> Result<()> {
        let items = self.list()?;
        let transaction = self.connection.transaction()?;
        crate::search::reset_index(&transaction)?;
        for item in items {
            crate::search::index_item(&transaction, &item)?;
        }
        transaction.commit()?;
        Ok(())
    }

    /// Literal token phrase search, not FTS syntax or the complete Swift search
    /// contract. Quotes are escaped; boolean operators and prefixes stay literal.
    pub fn search(&self, query: &str) -> Result<Vec<Item>> {
        if query.trim().is_empty() || query.len() > 4096 || query.chars().any(char::is_control) {
            return Err(Error::InvalidQuery);
        }
        let query = crate::search::width_fold(query.trim());
        let literal = format!("\"{}\"", query.replace('"', "\"\""));
        let mut statement = self.connection.prepare(
            "SELECT items.id,items.snapshot FROM item_search
             JOIN items ON items.id=item_search.id
             WHERE item_search MATCH ?1 ORDER BY rank,items.id",
        )?;
        let rows = statement.query_map([literal], |r| {
            Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))
        })?;
        rows.map(|row| {
            let (id, snapshot) = row?;
            decode_item(
                Uuid::parse_str(&id).map_err(|_| Error::InvalidData)?,
                &snapshot,
            )
        })
        .collect()
    }
}

pub(crate) fn validate_foreign_keys(connection: &Connection) -> Result<()> {
    let mut statement = connection.prepare("PRAGMA foreign_key_check")?;
    if statement.query([])?.next()?.is_some() {
        return Err(Error::InvalidData);
    }
    Ok(())
}

pub(crate) fn decode_item(id: Uuid, snapshot: &str) -> Result<Item> {
    let item: Item = serde_json::from_str(snapshot)?;
    if item.id != id {
        return Err(Error::InvalidData);
    }
    Ok(item)
}
