//! Local capture commands. This store has its own fingerprint namespace; it does
//! not import or backfill fingerprints from the macOS canonical library.
use chrono::{DateTime, Utc};
use rusqlite::{OptionalExtension, params};
use sha2::{Digest, Sha256};
use stow_core::{
    Attachment, CaptureDraft, FingerprintRepresentation, Item, ItemCommand, ItemEdit, ItemType,
    Representation, RepresentationDraft, RepresentationScope, clipboard_fingerprint,
    validate_representations,
};
use uuid::Uuid;

use crate::blobs::insert_blob;
use crate::{Error, LocalRepository, Result};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AttachmentDraft {
    pub data: Vec<u8>,
    pub thumbnail_data: Option<Vec<u8>>,
    pub content_type: String,
    pub file_name: String,
    pub pixel_width: Option<i64>,
    pub pixel_height: Option<i64>,
}

/// Attachment information for a list/detail view, without blob or thumbnail bytes.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AttachmentDescriptor {
    pub id: Uuid,
    pub file_name: Option<String>,
    pub content_type: Option<String>,
    pub byte_count: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum CaptureKind {
    Created,
    Coalesced,
    Replayed,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CaptureOutcome {
    pub item: Item,
    pub kind: CaptureKind,
}

fn fingerprint(
    draft: &CaptureDraft,
    attachment: Option<&AttachmentDraft>,
    reps: &[RepresentationDraft],
) -> Result<String> {
    let auxiliary = reps
        .iter()
        .map(|r| FingerprintRepresentation {
            type_identifier: r.type_identifier.clone(),
            data: r.data.clone(),
        })
        .collect::<Vec<_>>();
    let value = clipboard_fingerprint(draft, attachment.map(|a| a.data.as_slice()), &auxiliary)
        .map_err(|_| Error::InvalidCapture)?;
    Ok(format!("local-1:{value}"))
}

fn validate(
    draft: &CaptureDraft,
    attachment: Option<&AttachmentDraft>,
    reps: &[RepresentationDraft],
) -> Result<CaptureDraft> {
    let mut draft = draft.normalized().map_err(|_| Error::InvalidCapture)?;
    validate_representations(reps, RepresentationScope::Captured)
        .map_err(|_| Error::InvalidCapture)?;
    if draft
        .text_content
        .as_ref()
        .is_some_and(|s| s.len() > stow_core::PLAIN_TEXT_BYTES)
        || draft
            .url_string
            .as_ref()
            .is_some_and(|s| s.len() > stow_core::URL_BYTES)
    {
        return Err(Error::InvalidCapture);
    }
    if matches!(draft.item_type, ItemType::Image | ItemType::File) != attachment.is_some() {
        return Err(Error::InvalidCapture);
    }
    if let Some(a) = attachment {
        if (draft.item_type == ItemType::Image && a.data.is_empty())
            || a.data.len() as u64 > crate::MAX_ATTACHMENT_BYTES
            || a.thumbnail_data
                .as_ref()
                .is_some_and(|b| b.len() > stow_core::IMAGE_BYTES)
            || a.content_type.trim().is_empty()
            || a.file_name.trim().is_empty()
            || a.pixel_width.is_some_and(|n| n <= 0)
            || a.pixel_height.is_some_and(|n| n <= 0)
            || draft
                .attachment_byte_count
                .is_some_and(|n| n != a.data.len() as i64)
            || (draft.item_type == ItemType::Image && !a.content_type.starts_with("image/"))
        {
            return Err(Error::InvalidCapture);
        }
        // Actual attachment metadata defines the canonical image/file input.
        draft.content_type = Some(a.content_type.clone());
        draft.file_name = Some(a.file_name.clone());
    }
    Ok(draft)
}

impl LocalRepository {
    pub fn create(
        &mut self,
        draft: &CaptureDraft,
        attachment: Option<&AttachmentDraft>,
        reps: &[RepresentationDraft],
        at: DateTime<Utc>,
    ) -> Result<CaptureOutcome> {
        self.capture(draft, attachment, reps, at, false)
    }

    pub fn ingest_clipboard(
        &mut self,
        draft: &CaptureDraft,
        attachment: Option<&AttachmentDraft>,
        reps: &[RepresentationDraft],
        at: DateTime<Utc>,
    ) -> Result<CaptureOutcome> {
        self.capture(draft, attachment, reps, at, true)
    }

    fn capture(
        &mut self,
        draft: &CaptureDraft,
        attachment: Option<&AttachmentDraft>,
        reps: &[RepresentationDraft],
        at: DateTime<Utc>,
        clipboard: bool,
    ) -> Result<CaptureOutcome> {
        // No file is published until every payload has passed validation.
        let draft = validate(draft, attachment, reps)?;
        let existing_receipt: Option<String> = self
            .connection
            .query_row(
                "SELECT item_id FROM capture_receipts WHERE capture_id=?1",
                [draft.id.to_string()],
                |r| r.get(0),
            )
            .optional()?;
        if let Some(id) = existing_receipt {
            let item = self
                .get(Uuid::parse_str(&id).map_err(|_| Error::InvalidData)?)?
                .ok_or(Error::InvalidData)?;
            return Ok(CaptureOutcome {
                item,
                kind: CaptureKind::Replayed,
            });
        }
        let fingerprint = fingerprint(&draft, attachment, reps)?;
        let matching = if clipboard {
            self.connection
                .query_row(
                    "SELECT id,snapshot FROM items
                     WHERE json_extract(snapshot,'$.content_fingerprint')=?1
                     AND json_extract(snapshot,'$.status')!='trashed' ORDER BY id LIMIT 1",
                    [&fingerprint],
                    |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)),
                )
                .optional()?
                .map(|(id, snapshot)| {
                    let id = Uuid::parse_str(&id).map_err(|_| Error::InvalidData)?;
                    crate::repository::decode_item(id, &snapshot)
                })
                .transpose()?
        } else {
            None
        };
        if let Some(mut item) = matching {
            item.last_captured_at = Some(at);
            item.source_app = draft.source_app.clone();
            item.updated_at = at;
            let transaction = self.connection.transaction()?;
            save_item(&transaction, &item)?;
            receipt(&transaction, draft.id, item.id)?;
            transaction.commit()?;
            return Ok(CaptureOutcome {
                item,
                kind: CaptureKind::Coalesced,
            });
        }
        let mut item = Item::from_draft(&draft, at);
        item.content_fingerprint = Some(fingerprint);
        if clipboard {
            item.last_captured_at = Some(at);
        }
        // Publication can leave only unreferenced files on failure. Recovery
        // removes these files after checking all committed references.
        let attachment = attachment
            .map(|a| {
                let info = self.publish_reader(
                    item.id,
                    a.data.as_slice(),
                    a.data.len() as u64,
                    Sha256::digest(&a.data).into(),
                )?;
                let metadata = Attachment {
                    id: info.id,
                    item_id: item.id,
                    data: Vec::new(),
                    thumbnail_data: a.thumbnail_data.clone(),
                    content_type: a.content_type.clone(),
                    file_name: a.file_name.clone(),
                    byte_count: info.byte_count as i64,
                    pixel_width: a.pixel_width,
                    pixel_height: a.pixel_height,
                    created_at: at,
                };
                Ok::<_, Error>((info, serde_json::to_string(&metadata)?))
            })
            .transpose()?;
        let representations = reps
            .iter()
            .map(|r| {
                let info = self.publish_reader(
                    item.id,
                    r.data.as_slice(),
                    r.data.len() as u64,
                    Sha256::digest(&r.data).into(),
                )?;
                let metadata = Representation {
                    id: info.id,
                    item_id: item.id,
                    type_identifier: r.type_identifier.clone(),
                    data: Vec::new(),
                    byte_count: info.byte_count as i64,
                    ordinal: r.ordinal,
                    created_at: at,
                };
                Ok::<_, Error>((info, serde_json::to_string(&metadata)?))
            })
            .collect::<Result<Vec<_>>>()?;
        let transaction = self.connection.transaction()?;
        save_item(&transaction, &item)?;
        if let Some((info, metadata)) = attachment {
            insert_blob(&transaction, "attachments", &info, Some(&metadata))?;
        }
        for (info, metadata) in representations {
            insert_blob(&transaction, "representations", &info, Some(&metadata))?;
        }
        receipt(&transaction, draft.id, item.id)?;
        transaction.commit()?;
        Ok(CaptureOutcome {
            item,
            kind: CaptureKind::Created,
        })
    }

    pub fn attachment_descriptors(&self, item_id: Uuid) -> Result<Vec<AttachmentDescriptor>> {
        let mut statement = self.connection.prepare(
            "SELECT id,byte_count,json_extract(metadata,'$.file_name'),
             json_extract(metadata,'$.content_type') FROM attachments WHERE item_id=?1 ORDER BY id",
        )?;
        let rows = statement.query_map([item_id.to_string()], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, i64>(1)?,
                row.get::<_, Option<String>>(2)?,
                row.get::<_, Option<String>>(3)?,
            ))
        })?;
        rows.map(|row| {
            let (id, count, file_name, content_type) = row?;
            let byte_count = u64::try_from(count).map_err(|_| Error::InvalidData)?;
            if byte_count > crate::MAX_ATTACHMENT_BYTES {
                return Err(Error::InvalidData);
            }
            Ok(AttachmentDescriptor {
                id: Uuid::parse_str(&id).map_err(|_| Error::InvalidData)?,
                file_name,
                content_type,
                byte_count,
            })
        })
        .collect()
    }

    pub fn representation_count(&self, item_id: Uuid) -> Result<usize> {
        let count: i64 = self.connection.query_row(
            "SELECT count(*) FROM representations WHERE item_id=?1",
            [item_id.to_string()],
            |row| row.get(0),
        )?;
        usize::try_from(count).map_err(|_| Error::InvalidData)
    }

    /// Legacy v2 byte-only attachments have no full metadata and return None.
    pub fn load_attachment(&self, id: Uuid) -> Result<Option<Attachment>> {
        let metadata: Option<Option<String>> = self
            .connection
            .query_row(
                "SELECT metadata FROM attachments WHERE id=?1",
                [id.to_string()],
                |r| r.get(0),
            )
            .optional()?;
        let Some(Some(metadata)) = metadata else {
            return Ok(None);
        };
        let mut a: Attachment = serde_json::from_str(&metadata)?;
        let info = self.attachment_info(id)?.ok_or(Error::InvalidData)?;
        if a.id != id
            || a.item_id != info.item_id
            || a.byte_count != info.byte_count as i64
            || !a.data.is_empty()
        {
            return Err(Error::InvalidData);
        }
        a.data = self.read_attachment(id)?;
        Ok(Some(a))
    }

    pub fn representations(&self, item_id: Uuid) -> Result<Vec<Representation>> {
        let mut statement = self
            .connection
            .prepare("SELECT id,metadata FROM representations WHERE item_id=?1")?;
        let rows = statement.query_map([item_id.to_string()], |r| {
            Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))
        })?;
        let mut reps = Vec::new();
        let mut types = std::collections::HashSet::new();
        let mut ordinals = std::collections::HashSet::new();
        let mut total = 0usize;
        for row in rows {
            let (id, metadata) = row?;
            let id = Uuid::parse_str(&id).map_err(|_| Error::InvalidData)?;
            let info = self.blob_info(id)?.ok_or(Error::InvalidData)?;
            let mut rep: Representation = serde_json::from_str(&metadata)?;
            let maximum = stow_core::maximum_representation_bytes(&rep.type_identifier)
                .ok_or(Error::InvalidData)?;
            if rep.id != id
                || rep.item_id != item_id
                || info.item_id != item_id
                || rep.byte_count != info.byte_count as i64
                || rep.byte_count <= 0
                || info.byte_count > maximum as u64
                || rep.ordinal < 0
                || !types.insert(rep.type_identifier.clone())
                || !ordinals.insert(rep.ordinal)
                || !rep.data.is_empty()
            {
                return Err(Error::InvalidData);
            }
            total = total
                .checked_add(info.byte_count as usize)
                .ok_or(Error::InvalidData)?;
            if total > stow_core::TOTAL_REPRESENTATION_BYTES {
                return Err(Error::InvalidData);
            }
            rep.data = self.read_blob(id)?;
            reps.push(rep);
        }
        reps.sort_by_key(|r| (r.ordinal, r.id));
        Ok(reps)
    }

    pub fn apply(&mut self, ids: &[Uuid], command: ItemCommand, at: DateTime<Utc>) -> Result<()> {
        let mut items = Vec::new();
        for id in ids
            .iter()
            .copied()
            .collect::<std::collections::BTreeSet<_>>()
        {
            let mut item = self.get(id)?.ok_or(Error::ItemNotFound)?;
            match command {
                ItemCommand::Archive => item.archive(at),
                ItemCommand::RestoreFromArchive => item.restore_from_archive(at),
                ItemCommand::Trash => item.trash(at),
                ItemCommand::RestoreFromTrash => item.restore_from_trash(at),
                ItemCommand::SetPinned(value) => item.set_pinned(value, at),
                ItemCommand::RecordSuccessfulUse => item
                    .record_successful_use(at)
                    .map_err(|_| Error::InvalidData)?,
            }
            items.push(item);
        }
        let transaction = self.connection.transaction()?;
        for item in items {
            save_item(&transaction, &item)?;
        }
        transaction.commit()?;
        Ok(())
    }

    pub fn update(&mut self, id: Uuid, edit: &ItemEdit, at: DateTime<Utc>) -> Result<()> {
        let mut item = self.get(id)?.ok_or(Error::ItemNotFound)?;
        let language = clean(edit.language.as_deref()).map(|s| s.to_lowercase());
        let updates_text = matches!(item.item_type, ItemType::Text | ItemType::Code);
        let changed =
            updates_text && (item.text_content != edit.text_content || item.language != language);
        if updates_text
            && edit
                .text_content
                .as_ref()
                .is_none_or(|s| s.trim().is_empty() || s.len() > stow_core::PLAIN_TEXT_BYTES)
        {
            return Err(Error::InvalidCapture);
        }
        if !edit.title.trim().is_empty() {
            item.title = edit.title.trim().to_owned();
        }
        item.note = clean(edit.note.as_deref());
        if updates_text {
            item.text_content = edit.text_content.clone();
            item.language = language;
        }
        if changed {
            let mut draft = CaptureDraft::new(item.item_type, &item.title);
            draft.text_content = item.text_content.clone();
            draft.language = item.language.clone();
            item.content_fingerprint = Some(fingerprint(&draft, None, &[])?);
        }
        item.updated_at = at;
        let transaction = self.connection.transaction()?;
        if changed {
            transaction.execute(
                "DELETE FROM representations WHERE item_id=?1",
                [id.to_string()],
            )?;
        }
        save_item(&transaction, &item)?;
        transaction.commit()?;
        Ok(())
    }

    pub fn purge_expired_trash(&mut self, at: DateTime<Utc>, retention_days: i64) -> Result<usize> {
        if retention_days < 0 {
            return Err(Error::InvalidData);
        }
        crate::repository::validate_foreign_keys(&self.connection)?;
        let ids = self
            .list()?
            .into_iter()
            .filter(|i| i.should_purge(at, retention_days))
            .map(|i| i.id)
            .collect::<Vec<_>>();
        let transaction = self.connection.transaction()?;
        for id in &ids {
            crate::search::remove_item(&transaction, *id)?;
            transaction.execute("DELETE FROM items WHERE id=?1", [id.to_string()])?;
        }
        transaction.commit()?;
        // Canonical deletion has committed. Cleanup failure must not report a
        // failed mutation; startup retries removal of unreferenced files.
        let _ = self.recover_attachments();
        Ok(ids.len())
    }
}

fn clean(value: Option<&str>) -> Option<String> {
    value
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_owned)
}
fn receipt(transaction: &rusqlite::Transaction<'_>, capture_id: Uuid, item_id: Uuid) -> Result<()> {
    transaction.execute(
        "INSERT INTO capture_receipts(capture_id,item_id) VALUES (?1,?2)",
        params![capture_id.to_string(), item_id.to_string()],
    )?;
    Ok(())
}
fn save_item(transaction: &rusqlite::Transaction<'_>, item: &Item) -> Result<()> {
    transaction.execute("INSERT INTO items(id,snapshot) VALUES (?1,?2) ON CONFLICT(id) DO UPDATE SET snapshot=excluded.snapshot", params![item.id.to_string(), serde_json::to_string(item)?])?;
    crate::search::index_item(transaction, item)
}
