//! SQLite implementation of the portable desktop repository contract.
use std::path::PathBuf;

use chrono::{DateTime, Utc};
use stow_core::{
    ApplyRequest, AttachmentMetadata, CreateRequest, Item, ItemDetail, ItemSummary, Repository,
    SERVICE_TEXT_LIMIT, SearchRequest, ServiceError, ServiceResult as Result, UpdateRequest,
    next_revision, optional_string, revision_timestamp, service_error as error,
};
use uuid::Uuid;

use crate::{CaptureKind, LocalRepository};

/// Open only a host-selected preview root. Disabled platforms reject the request
/// before parent creation or any other filesystem mutation.
pub fn open_desktop(root: PathBuf) -> Result<Box<dyn Repository>> {
    #[cfg(target_os = "linux")]
    prepare_parents(&root).map_err(storage_error)?;
    LocalRepository::open(root)
        .map(|repository| Box::new(repository) as Box<dyn Repository>)
        .map_err(storage_error)
}

impl Repository for LocalRepository {
    fn search(&mut self, request: SearchRequest) -> Result<Vec<ItemSummary>> {
        Ok(self
            .search_items(&request.into())
            .map_err(storage_error)?
            .into_iter()
            .map(ItemSummary::from)
            .collect())
    }

    fn get(&mut self, id: Uuid) -> Result<ItemDetail> {
        detail(self, id)
    }

    fn create(&mut self, request: CreateRequest) -> Result<ItemDetail> {
        let draft = request.normalized_draft()?;
        let outcome =
            LocalRepository::create(self, &draft, None, &[], Utc::now()).map_err(storage_error)?;
        let mut response = detail(self, outcome.item.id)?;
        response.capture_replayed = outcome.kind == CaptureKind::Replayed;
        Ok(response)
    }

    fn update(&mut self, request: UpdateRequest) -> Result<ItemDetail> {
        // The permanent exclusive writer lock and this mutable owner keep the
        // compare and write in one operation. No other writer can interleave.
        let item = checked_item(
            self,
            request.id,
            revision_timestamp(&request.expected_updated_at)?,
        )?;
        LocalRepository::update(
            self,
            request.id,
            &request.edit.into(),
            next_revision(item.updated_at)?,
        )
        .map_err(storage_error)?;
        detail(self, request.id)
    }

    fn apply(&mut self, request: ApplyRequest) -> Result<ItemDetail> {
        let item = checked_item(
            self,
            request.id,
            revision_timestamp(&request.expected_updated_at)?,
        )?;
        LocalRepository::apply(
            self,
            &[request.id],
            request.command.into(),
            next_revision(item.updated_at)?,
        )
        .map_err(storage_error)?;
        detail(self, request.id)
    }

    fn rebuild(&mut self) -> Result<()> {
        self.rebuild_index().map_err(storage_error)
    }
}

#[cfg(target_os = "linux")]
fn prepare_parents(root: &std::path::Path) -> crate::Result<()> {
    use std::{fs, os::unix::fs::DirBuilderExt, path::Component};
    if !root.is_absolute()
        || root
            .components()
            .any(|part| matches!(part, Component::ParentDir | Component::CurDir))
    {
        return Err(crate::Error::UnsafePath);
    }
    let parent = root.parent().ok_or(crate::Error::UnsafePath)?;
    let mut current = PathBuf::new();
    for component in parent.components() {
        current.push(component);
        match fs::symlink_metadata(&current) {
            Ok(metadata) if metadata.is_dir() && !metadata.file_type().is_symlink() => (),
            Ok(_) => return Err(crate::Error::UnsafePath),
            Err(failure) if failure.kind() == std::io::ErrorKind::NotFound => {
                fs::DirBuilder::new().mode(0o700).create(&current)?;
                fs::File::open(&current)?.sync_all()?;
                fs::File::open(current.parent().ok_or(crate::Error::UnsafePath)?)?.sync_all()?;
            }
            Err(failure) => return Err(failure.into()),
        }
    }
    Ok(())
}

fn storage_error(value: crate::Error) -> ServiceError {
    let code = match value {
        crate::Error::UnsupportedPlatform | crate::Error::Locked => "unavailable",
        crate::Error::ItemNotFound => "not_found",
        crate::Error::InvalidCapture | crate::Error::InvalidQuery => "invalid_argument",
        _ => "storage",
    };
    error(code, &value.to_string())
}

fn checked_item(repo: &LocalRepository, id: Uuid, expected: DateTime<Utc>) -> Result<Item> {
    let item = repo
        .get(id)
        .map_err(storage_error)?
        .ok_or_else(|| error("not_found", "Item not found."))?;
    if item.updated_at != expected {
        return Err(error(
            "conflict",
            "The item changed. Reload it before saving.",
        ));
    }
    Ok(item)
}

fn detail(repo: &LocalRepository, id: Uuid) -> Result<ItemDetail> {
    let mut item = repo
        .get(id)
        .map_err(storage_error)?
        .ok_or_else(|| error("not_found", "Item not found."))?;
    optional_string(&item.text_content, SERVICE_TEXT_LIMIT)?;
    item.favicon_data = None;
    item.link_preview_image_data = None;
    let attachments = repo
        .attachment_descriptors(id)
        .map_err(storage_error)?
        .into_iter()
        .map(|a| AttachmentMetadata {
            id: a.id,
            file_name: a.file_name,
            content_type: a.content_type,
            byte_count: a.byte_count,
        })
        .collect();
    Ok(ItemDetail {
        capture_replayed: false,
        item,
        attachments,
        representations_count: repo.representation_count(id).map_err(storage_error)?,
    })
}
