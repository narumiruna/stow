//! Test-only backend. It does not model SQLite publication or native persistence.
use std::{
    collections::BTreeMap,
    rc::Rc,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
};

use chrono::Utc;
use stow_core::{Item, ItemStatus, ItemType, next_revision};

use super::*;

#[derive(Default)]
pub(super) struct MemoryRepository {
    pub items: BTreeMap<Uuid, Item>,
    pub fail_save: Arc<AtomicBool>,
    pub revisions: Arc<Mutex<Vec<String>>>,
    // Prove that a backend created on the worker does not need Send.
    pub _worker_owned: Rc<()>,
    pub _dropped: Option<DropNotice>,
}

pub(super) struct DropNotice(pub mpsc::Sender<()>);
impl Drop for DropNotice {
    fn drop(&mut self) {
        let _ = self.0.send(());
    }
}

impl MemoryRepository {
    fn checked(&self, id: Uuid, expected: &str) -> Result<Item> {
        let item = self
            .items
            .get(&id)
            .cloned()
            .ok_or_else(|| error("not_found", "Item not found."))?;
        if item.updated_at != revision_timestamp(expected)? {
            return Err(error(
                "conflict",
                "The item changed. Reload it before saving.",
            ));
        }
        Ok(item)
    }

    fn save(&mut self, item: Item) -> Result<ItemDetail> {
        if self.fail_save.swap(false, Ordering::SeqCst) {
            return Err(error("storage", "The storage operation failed."));
        }
        let id = item.id;
        self.items.insert(id, item);
        self.get(id)
    }
}

impl Repository for MemoryRepository {
    fn search(&mut self, request: SearchRequest) -> Result<Vec<ItemSummary>> {
        let mut items: Vec<_> = self
            .items
            .values()
            .filter(|item| {
                request.status.map_or(
                    request.include_trashed || item.status != ItemStatus::Trashed,
                    |status| item.status == status,
                ) && request.item_type.is_none_or(|kind| item.item_type == kind)
                    && request.source_app.as_ref().is_none_or(|source| {
                        item.source_app
                            .as_ref()
                            .is_some_and(|value| value.eq_ignore_ascii_case(source))
                    })
                    && request
                        .added_after
                        .is_none_or(|date| item.created_at >= date)
                    && request
                        .added_before
                        .is_none_or(|date| item.created_at <= date)
                    && (!request.pinned_only || item.is_pinned)
                    && format!(
                        "{} {}",
                        item.title,
                        item.text_content.as_deref().unwrap_or("")
                    )
                    .to_lowercase()
                    .contains(&request.text.to_lowercase())
            })
            .cloned()
            .collect();
        items.sort_by(|a, b| b.created_at.cmp(&a.created_at).then(a.id.cmp(&b.id)));
        Ok(items
            .into_iter()
            .take(request.limit.unwrap_or(200))
            .map(ItemSummary::from)
            .collect())
    }

    fn get(&mut self, id: Uuid) -> Result<ItemDetail> {
        let mut item = self
            .items
            .get(&id)
            .cloned()
            .ok_or_else(|| error("not_found", "Item not found."))?;
        item.favicon_data = None;
        item.link_preview_image_data = None;
        Ok(ItemDetail {
            capture_replayed: false,
            item,
            attachments: Vec::new(),
            representations_count: 0,
        })
    }

    fn create(&mut self, request: CreateRequest) -> Result<ItemDetail> {
        let draft = request.normalized_draft()?;
        if let Some(id) = self
            .items
            .values()
            .find(|item| item.capture_id == request.capture_id)
            .map(|item| item.id)
        {
            let mut detail = self.get(id)?;
            detail.capture_replayed = true;
            return Ok(detail);
        }
        self.save(Item::from_draft(&draft, Utc::now()))
    }

    fn update(&mut self, request: UpdateRequest) -> Result<ItemDetail> {
        self.revisions
            .lock()
            .unwrap()
            .push(request.expected_updated_at.clone());
        let mut item = self.checked(request.id, &request.expected_updated_at)?;
        let edit = request.edit;
        if matches!(item.item_type, ItemType::Text | ItemType::Code) {
            if edit
                .text_content
                .as_ref()
                .is_none_or(|text| text.trim().is_empty())
            {
                return Err(error("invalid_argument", "invalid capture payload"));
            }
            item.text_content = edit.text_content;
            item.language = clean(edit.language).map(|value| value.to_lowercase());
        }
        if !edit.title.trim().is_empty() {
            item.title = edit.title.trim().into();
        }
        item.note = clean(edit.note);
        item.updated_at = next_revision(item.updated_at)?;
        self.save(item)
    }

    fn apply(&mut self, request: ApplyRequest) -> Result<ItemDetail> {
        self.revisions
            .lock()
            .unwrap()
            .push(request.expected_updated_at.clone());
        let mut item = self.checked(request.id, &request.expected_updated_at)?;
        let now = next_revision(item.updated_at)?;
        match request.command {
            LifecycleAction::Archive => item.archive(now),
            LifecycleAction::RestoreArchive => item.restore_from_archive(now),
            LifecycleAction::Trash => item.trash(now),
            LifecycleAction::RestoreTrash => item.restore_from_trash(now),
            LifecycleAction::Pin => item.set_pinned(true, now),
            LifecycleAction::Unpin => item.set_pinned(false, now),
        }
        self.save(item)
    }

    fn rebuild(&mut self) -> Result<()> {
        Ok(())
    }
}

fn clean(value: Option<String>) -> Option<String> {
    value
        .map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty())
}
