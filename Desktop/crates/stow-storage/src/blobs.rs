use std::collections::HashMap;
use std::fs;
use std::io::{Read, Write};
use std::path::Path;

use rusqlite::{OptionalExtension, params};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::{Error, LocalRepository, Result, paths};

pub const MAX_ATTACHMENT_BYTES: u64 = 100 * 1024 * 1024;

/// A storage identifier, not a caller-selected path or original filename.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct AttachmentInfo {
    pub id: Uuid,
    pub item_id: Uuid,
    pub byte_count: u64,
    pub sha256: String,
}

impl LocalRepository {
    pub fn attach(&mut self, item_id: Uuid, bytes: &[u8]) -> Result<AttachmentInfo> {
        if bytes.len() as u64 > MAX_ATTACHMENT_BYTES {
            return Err(Error::AttachmentTooLarge);
        }
        self.attach_reader(
            item_id,
            bytes,
            bytes.len() as u64,
            Sha256::digest(bytes).into(),
        )
    }

    /// Read at most 100 MiB + one byte. Verify the expected size and SHA256 both
    /// while staging and from the staged file before publication. The caller
    /// must not retry with a different checksum after a verification failure.
    pub fn attach_reader(
        &mut self,
        item_id: Uuid,
        mut source: impl Read,
        expected_size: u64,
        expected_sha256: [u8; 32],
    ) -> Result<AttachmentInfo> {
        if expected_size > MAX_ATTACHMENT_BYTES {
            return Err(Error::AttachmentTooLarge);
        }
        if self.get(item_id)?.is_none() {
            return Err(Error::ItemNotFound);
        }
        let info = self.publish_reader(item_id, &mut source, expected_size, expected_sha256)?;
        let transaction = self.connection.transaction()?;
        insert_blob(&transaction, "attachments", &info, None)?;
        transaction.commit()?;
        Ok(info)
    }

    pub(crate) fn publish_reader(
        &self,
        item_id: Uuid,
        mut source: impl Read,
        expected_size: u64,
        expected_sha256: [u8; 32],
    ) -> Result<AttachmentInfo> {
        if expected_size > MAX_ATTACHMENT_BYTES {
            return Err(Error::AttachmentTooLarge);
        }
        let id = Uuid::new_v4();
        let stage = self.root.join("staging").join(format!("{id}.part"));
        let published = self.root.join("blobs").join(id.to_string());
        let mut file = paths::new_file(&stage)?;
        let mut count = 0u64;
        let mut hash = Sha256::new();
        let mut buffer = [0u8; 64 * 1024];
        loop {
            // Also bound a dishonest reader whose declared length is small.
            let remaining = (MAX_ATTACHMENT_BYTES + 1 - count).min(buffer.len() as u64) as usize;
            let size = source.read(&mut buffer[..remaining])?;
            if size == 0 {
                break;
            }
            count += size as u64;
            if count > MAX_ATTACHMENT_BYTES {
                return Err(Error::AttachmentTooLarge);
            }
            hash.update(&buffer[..size]);
            file.write_all(&buffer[..size])?;
        }
        if count != expected_size || <[u8; 32]>::from(hash.finalize()) != expected_sha256 {
            return Err(Error::CorruptAttachment);
        }
        file.sync_all()?;
        drop(file);
        let info = AttachmentInfo {
            id,
            item_id,
            byte_count: count,
            sha256: expected_sha256
                .iter()
                .map(|byte| format!("{byte:02x}"))
                .collect(),
        };
        verify_file(&stage, &info, false)?;
        paths::publish(&stage, &published)?;
        Ok(info)
    }

    /// List an item's attachment metadata in stable attachment UUID order.
    /// An unknown item or an item without attachments returns an empty list.
    pub fn attachments(&self, item_id: Uuid) -> Result<Vec<AttachmentInfo>> {
        let mut statement = self
            .connection
            .prepare("SELECT id,byte_count,sha256 FROM attachments WHERE item_id=?1 ORDER BY id")?;
        let rows = statement.query_map([item_id.to_string()], |r| {
            Ok((
                r.get::<_, String>(0)?,
                r.get::<_, i64>(1)?,
                r.get::<_, String>(2)?,
            ))
        })?;
        rows.map(|row| {
            let (id, byte_count, sha256) = row?;
            Ok(AttachmentInfo {
                id: Uuid::parse_str(&id).map_err(|_| Error::InvalidData)?,
                item_id,
                byte_count: u64::try_from(byte_count).map_err(|_| Error::InvalidData)?,
                sha256,
            })
        })
        .collect()
    }

    pub(crate) fn blob_info(&self, id: Uuid) -> Result<Option<AttachmentInfo>> {
        let row = self
            .connection
            .query_row(
                "SELECT item_id,byte_count,sha256 FROM attachments WHERE id=?1
             UNION ALL SELECT item_id,byte_count,sha256 FROM representations WHERE id=?1",
                [id.to_string()],
                |r| {
                    Ok((
                        r.get::<_, String>(0)?,
                        r.get::<_, i64>(1)?,
                        r.get::<_, String>(2)?,
                    ))
                },
            )
            .optional()?;
        row.map(|(item_id, count, sha256)| {
            Ok(AttachmentInfo {
                id,
                item_id: Uuid::parse_str(&item_id).map_err(|_| Error::InvalidData)?,
                byte_count: u64::try_from(count).map_err(|_| Error::InvalidData)?,
                sha256,
            })
        })
        .transpose()
    }

    pub(crate) fn read_blob(&self, id: Uuid) -> Result<Vec<u8>> {
        let info = self.blob_info(id)?.ok_or(Error::AttachmentNotFound)?;
        verify_file(&self.root.join("blobs").join(id.to_string()), &info, true)
    }

    pub fn read_attachment(&self, id: Uuid) -> Result<Vec<u8>> {
        let info = self.attachment_info(id)?.ok_or(Error::AttachmentNotFound)?;
        verify_file(&self.root.join("blobs").join(id.to_string()), &info, true)
    }

    pub fn attachment_info(&self, id: Uuid) -> Result<Option<AttachmentInfo>> {
        let row = self
            .connection
            .query_row(
                "SELECT item_id,byte_count,sha256 FROM attachments WHERE id=?1",
                [id.to_string()],
                |r| {
                    Ok((
                        r.get::<_, String>(0)?,
                        r.get::<_, i64>(1)?,
                        r.get::<_, String>(2)?,
                    ))
                },
            )
            .optional()?;
        row.map(|(item_id, byte_count, sha256)| {
            Ok(AttachmentInfo {
                id,
                item_id: Uuid::parse_str(&item_id).map_err(|_| Error::InvalidData)?,
                byte_count: u64::try_from(byte_count).map_err(|_| Error::InvalidData)?,
                sha256,
            })
        })
        .transpose()
    }

    /// Called only while holding the writer lock. Validate all entries and
    /// committed blobs before removing interrupted stages or unreferenced blobs.
    pub(crate) fn recover_attachments(&mut self) -> Result<()> {
        crate::repository::validate_foreign_keys(&self.connection)?;
        let ids: Vec<String> = self
            .connection
            .prepare("SELECT id FROM attachments UNION ALL SELECT id FROM representations")?
            .query_map([], |r| r.get(0))?
            .collect::<std::result::Result<_, _>>()?;
        let mut references = HashMap::new();
        for id in ids {
            let uuid = parse_name(&id)?;
            let info = self.blob_info(uuid)?.ok_or(Error::InvalidData)?;
            if references.insert(id, info).is_some() {
                return Err(Error::InvalidData);
            }
        }
        let stages = scan(&self.root.join("staging"), true)?;
        let blobs = scan(&self.root.join("blobs"), false)?;
        for (id, info) in &references {
            verify_file(&self.root.join("blobs").join(id), info, false)?;
        }
        for path in stages {
            fs::remove_file(path)?;
        }
        for path in blobs {
            let name = path
                .file_name()
                .and_then(|n| n.to_str())
                .ok_or(Error::UnsafePath)?;
            if !references.contains_key(name) {
                fs::remove_file(path)?;
            }
        }
        paths::sync_dir(&self.root.join("staging"))?;
        paths::sync_dir(&self.root.join("blobs"))?;
        Ok(())
    }
}

pub(crate) fn insert_blob(
    transaction: &rusqlite::Transaction<'_>,
    table: &str,
    info: &AttachmentInfo,
    metadata: Option<&str>,
) -> Result<()> {
    let sql = match table {
        "attachments" => {
            "INSERT INTO attachments(id,item_id,byte_count,sha256,metadata) VALUES (?1,?2,?3,?4,?5)"
        }
        "representations" => {
            "INSERT INTO representations(id,item_id,byte_count,sha256,metadata) VALUES (?1,?2,?3,?4,?5)"
        }
        _ => return Err(Error::InvalidData),
    };
    transaction.execute(
        sql,
        params![
            info.id.to_string(),
            info.item_id.to_string(),
            info.byte_count as i64,
            info.sha256,
            metadata
        ],
    )?;
    Ok(())
}

fn parse_name(name: &str) -> Result<Uuid> {
    let uuid = Uuid::parse_str(name).map_err(|_| Error::UnsafePath)?;
    if uuid.to_string() != name {
        return Err(Error::UnsafePath);
    }
    Ok(uuid)
}

fn scan(directory: &Path, staged: bool) -> Result<Vec<std::path::PathBuf>> {
    paths::check_components(directory)?;
    let mut paths = Vec::new();
    for entry in fs::read_dir(directory)? {
        let entry = entry?;
        let path = entry.path();
        let name = entry.file_name();
        let name = name.to_str().ok_or(Error::UnsafePath)?;
        parse_name(if staged {
            name.strip_suffix(".part").ok_or(Error::UnsafePath)?
        } else {
            name
        })?;
        let metadata = fs::symlink_metadata(&path)?;
        // A crash between link and unlink can leave two links to the same inode.
        // Only permit it for recovery, with no reads/writes through that inode.
        check_recovery_file(&metadata)?;
        #[cfg(windows)]
        paths::check_file(&path)?;
        paths.push(path);
    }
    Ok(paths)
}

fn check_recovery_file(metadata: &fs::Metadata) -> Result<()> {
    #[cfg(windows)]
    if metadata.is_file() && !metadata.is_symlink() {
        return Ok(());
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        // SAFETY: geteuid has no preconditions.
        if metadata.is_file()
            && metadata.uid() == unsafe { libc::geteuid() }
            && metadata.mode() & 0o077 == 0
            && metadata.nlink() <= 2
        {
            return Ok(());
        }
    }
    Err(Error::UnsafePath)
}

fn verify_file(path: &Path, info: &AttachmentInfo, collect: bool) -> Result<Vec<u8>> {
    if info.byte_count > MAX_ATTACHMENT_BYTES || info.sha256.len() != 64 {
        return Err(Error::CorruptAttachment);
    }
    let file = paths::open_file(path, false, false)?;
    if file.metadata()?.len() != info.byte_count {
        return Err(Error::CorruptAttachment);
    }
    let mut reader = file.take(MAX_ATTACHMENT_BYTES + 1);
    let mut hash = Sha256::new();
    let mut data = Vec::new();
    let mut count = 0u64;
    let mut buffer = [0; 64 * 1024];
    loop {
        let size = reader.read(&mut buffer)?;
        if size == 0 {
            break;
        }
        count += size as u64;
        if count > MAX_ATTACHMENT_BYTES {
            return Err(Error::AttachmentTooLarge);
        }
        hash.update(&buffer[..size]);
        if collect {
            data.extend_from_slice(&buffer[..size]);
        }
    }
    let digest: String = hash.finalize().iter().map(|b| format!("{b:02x}")).collect();
    if count != info.byte_count || digest != info.sha256 {
        return Err(Error::CorruptAttachment);
    }
    Ok(data)
}
