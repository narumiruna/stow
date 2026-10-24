//! UI-independent, single-writer desktop service. Call synchronous methods from
//! a blocking task, never from the UI event loop.
mod dto;
pub use dto::*;

use chrono::{DateTime, Utc};
use std::{
    path::PathBuf,
    sync::{Arc, mpsc},
    thread::{self, JoinHandle},
};
use stow_core::{CaptureDraft, Item, ItemType};
use stow_storage::{ItemCommand, ItemEdit, LocalRepository, SearchQuery};
use uuid::Uuid;

const QUEUE_CAPACITY: usize = 32;
const TEXT_LIMIT: usize = 1024 * 1024;
const FIELD_LIMIT: usize = 16 * 1024;
type Job = Box<dyn FnOnce(&mut State) + Send>;
struct State {
    repository: std::result::Result<LocalRepository, ServiceError>,
}
struct Worker {
    sender: Option<mpsc::SyncSender<Job>>,
    join: Option<JoinHandle<()>>,
}
impl Drop for Worker {
    fn drop(&mut self) {
        // Disconnect before joining. No shutdown message can block on a full queue.
        self.sender.take();
        if let Some(join) = self.join.take() {
            let _ = join.join();
        }
    }
}
#[derive(Clone)]
pub struct DesktopService {
    worker: Arc<Worker>,
}
impl DesktopService {
    /// The application selects the root once. Requests cannot change it.
    /// Open failures remain available through `status` without a fallback store.
    pub fn start(root: PathBuf) -> Self {
        let (sender, receiver) = mpsc::sync_channel::<Job>(QUEUE_CAPACITY);
        let join = thread::Builder::new()
            .name("stow-storage".into())
            .spawn(move || {
                let mut state = State {
                    repository: open_repository(root),
                };
                while let Ok(job) = receiver.recv() {
                    job(&mut state);
                }
            })
            .ok();
        Self {
            worker: Arc::new(Worker {
                sender: join.as_ref().map(|_| sender),
                join,
            }),
        }
    }
    fn request<T: Send + 'static>(
        &self,
        operation: impl FnOnce(&mut State) -> Result<T> + Send + 'static,
    ) -> Result<T> {
        let (sender, receiver) = mpsc::channel();
        let job: Job = Box::new(move |state| {
            let _ = sender.send(operation(state));
        });
        self.worker
            .sender
            .as_ref()
            .ok_or_else(disconnected)?
            .try_send(job)
            .map_err(|failure| match failure {
                mpsc::TrySendError::Full(_) => error("busy", "The storage request queue is full."),
                mpsc::TrySendError::Disconnected(_) => disconnected(),
            })?;
        // No ambiguous mutation timeout: a request completes or the worker drops
        // its response sender on panic/disconnect. Response delivery never blocks.
        receiver.recv().map_err(|_| disconnected())?
    }
    pub fn status(&self) -> Result<ServiceStatus> {
        self.request(|state| {
            let available = state.repository.is_ok();
            Ok(ServiceStatus {
                storage_available: available,
                message: match &state.repository {
                    Ok(_) => "Library is stored only on this device.".into(),
                    Err(error) => error.message.clone(),
                },
                platform: std::env::consts::OS.into(),
                capabilities: Capabilities {
                    local_storage: available,
                    ..Default::default()
                },
            })
        })
    }
    pub fn search(&self, request: SearchRequest) -> Result<Vec<ItemSummary>> {
        bounded(&request.text, 4096)?;
        optional(&request.source_app, FIELD_LIMIT)?;
        self.request(move |state| {
            let query = SearchQuery {
                text: request.text,
                item_type: request.item_type,
                source_app: request.source_app,
                added_after: request.added_after,
                added_before: request.added_before,
                status: request.status,
                include_trashed: request.include_trashed,
                pinned_only: request.pinned_only,
                limit: request.limit.unwrap_or(200).clamp(1, 500),
            };
            Ok(repository(state)?
                .search_items(&query)
                .map_err(storage_error)?
                .into_iter()
                .map(ItemSummary::from)
                .collect())
        })
    }
    pub fn get(&self, id: Uuid) -> Result<ItemDetail> {
        self.request(move |state| detail(repository(state)?, id))
    }
    pub fn create(&self, request: CreateRequest) -> Result<ItemDetail> {
        if !matches!(
            request.item_type,
            ItemType::Text | ItemType::Code | ItemType::Link
        ) {
            return Err(error(
                "unsupported",
                "Only text, code, and link capture is supported.",
            ));
        }
        bounded(&request.title, FIELD_LIMIT)?;
        optional(&request.text_content, TEXT_LIMIT)?;
        optional(&request.url_string, 16 * 1024)?;
        optional(&request.note, TEXT_LIMIT)?;
        optional(&request.source_app, FIELD_LIMIT)?;
        optional(&request.language, FIELD_LIMIT)?;
        self.request(move |state| {
            let repo = repository(state)?;
            let mut draft = CaptureDraft::new(request.item_type, request.title);
            draft.id = request.capture_id;
            draft.text_content = request.text_content;
            draft.url_string = request.url_string;
            draft.note = request.note;
            draft.source_app = request.source_app;
            draft.language = request.language;
            draft.is_pinned = request.is_pinned;
            draft.directly_archive = request.directly_archive;
            let outcome = repo
                .create(&draft, None, &[], Utc::now())
                .map_err(storage_error)?;
            let mut response = detail(repo, outcome.item.id)?;
            response.capture_replayed = outcome.kind == stow_storage::CaptureKind::Replayed;
            Ok(response)
        })
    }
    pub fn update(&self, request: UpdateRequest) -> Result<ItemDetail> {
        bounded(&request.edit.title, FIELD_LIMIT)?;
        optional(&request.edit.text_content, TEXT_LIMIT)?;
        optional(&request.edit.note, TEXT_LIMIT)?;
        optional(&request.edit.language, FIELD_LIMIT)?;
        let expected = timestamp(&request.expected_updated_at)?;
        self.request(move |state| {
            let repo = repository(state)?;
            let item = checked_item(repo, request.id, expected)?;
            let edit = ItemEdit {
                title: request.edit.title,
                note: request.edit.note,
                text_content: request.edit.text_content,
                language: request.edit.language,
            };
            repo.update(request.id, &edit, next_time(&item)?)
                .map_err(storage_error)?;
            detail(repo, request.id)
        })
    }
    pub fn apply(&self, request: ApplyRequest) -> Result<ItemDetail> {
        let expected = timestamp(&request.expected_updated_at)?;
        self.request(move |state| {
            let repo = repository(state)?;
            let item = checked_item(repo, request.id, expected)?;
            let command = match request.command {
                LifecycleAction::Archive => ItemCommand::Archive,
                LifecycleAction::RestoreArchive => ItemCommand::RestoreFromArchive,
                LifecycleAction::Trash => ItemCommand::Trash,
                LifecycleAction::RestoreTrash => ItemCommand::RestoreFromTrash,
                LifecycleAction::Pin => ItemCommand::SetPinned(true),
                LifecycleAction::Unpin => ItemCommand::SetPinned(false),
            };
            repo.apply(&[request.id], command, next_time(&item)?)
                .map_err(storage_error)?;
            detail(repo, request.id)
        })
    }
    pub fn rebuild(&self) -> Result<()> {
        self.request(|state| repository(state)?.rebuild_index().map_err(storage_error))
    }
}
fn open_repository(root: PathBuf) -> Result<LocalRepository> {
    // Never create paths on platforms whose canonical store is disabled.
    #[cfg(target_os = "linux")]
    prepare_parents(&root).map_err(storage_error)?;
    LocalRepository::open(root).map_err(storage_error)
}

#[cfg(target_os = "linux")]
fn prepare_parents(root: &std::path::Path) -> stow_storage::Result<()> {
    use std::{fs, os::unix::fs::DirBuilderExt, path::Component};
    if !root.is_absolute()
        || root
            .components()
            .any(|part| matches!(part, Component::ParentDir | Component::CurDir))
    {
        return Err(stow_storage::Error::UnsafePath);
    }
    let parent = root.parent().ok_or(stow_storage::Error::UnsafePath)?;
    let mut current = PathBuf::new();
    for component in parent.components() {
        current.push(component);
        match fs::symlink_metadata(&current) {
            Ok(metadata) if metadata.is_dir() && !metadata.file_type().is_symlink() => (),
            Ok(_) => return Err(stow_storage::Error::UnsafePath),
            Err(failure) if failure.kind() == std::io::ErrorKind::NotFound => {
                fs::DirBuilder::new().mode(0o700).create(&current)?;
                fs::File::open(&current)?.sync_all()?;
                fs::File::open(current.parent().ok_or(stow_storage::Error::UnsafePath)?)?
                    .sync_all()?;
            }
            Err(failure) => return Err(failure.into()),
        }
    }
    Ok(())
}

fn error(code: &str, message: &str) -> ServiceError {
    ServiceError {
        code: code.into(),
        message: message.into(),
        retryable: matches!(code, "busy" | "storage"),
    }
}
fn disconnected() -> ServiceError {
    error("disconnected", "The storage worker is unavailable.")
}
fn storage_error(value: stow_storage::Error) -> ServiceError {
    let code = match value {
        stow_storage::Error::UnsupportedPlatform | stow_storage::Error::Locked => "unavailable",
        stow_storage::Error::ItemNotFound => "not_found",
        stow_storage::Error::InvalidCapture | stow_storage::Error::InvalidQuery => {
            "invalid_argument"
        }
        _ => "storage",
    };
    error(code, &value.to_string())
}
fn repository(state: &mut State) -> Result<&mut LocalRepository> {
    state.repository.as_mut().map_err(|error| error.clone())
}
fn bounded(value: &str, maximum: usize) -> Result<()> {
    if value.len() > maximum {
        Err(error(
            "invalid_argument",
            "A string exceeds its byte limit.",
        ))
    } else {
        Ok(())
    }
}
fn optional(value: &Option<String>, maximum: usize) -> Result<()> {
    if let Some(value) = value {
        bounded(value, maximum)?;
    }
    Ok(())
}
fn timestamp(value: &str) -> Result<DateTime<Utc>> {
    bounded(value, 64)?;
    DateTime::parse_from_rfc3339(value)
        .map(|date| date.with_timezone(&Utc))
        .map_err(|_| {
            error(
                "invalid_argument",
                "expected_updated_at must be an RFC3339 timestamp.",
            )
        })
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
fn next_time(item: &Item) -> Result<DateTime<Utc>> {
    let now = Utc::now();
    if now > item.updated_at {
        Ok(now)
    } else {
        item.updated_at
            .checked_add_signed(chrono::TimeDelta::nanoseconds(1))
            .ok_or_else(|| error("storage", "The item timestamp cannot advance."))
    }
}
fn detail(repo: &LocalRepository, id: Uuid) -> Result<ItemDetail> {
    let mut item = repo
        .get(id)
        .map_err(storage_error)?
        .ok_or_else(|| error("not_found", "Item not found."))?;
    optional(&item.text_content, TEXT_LIMIT)?;
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

#[cfg(test)]
mod tests;
