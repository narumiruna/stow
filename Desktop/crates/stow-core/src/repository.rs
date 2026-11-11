use crate::{CaptureDraft, Item, ItemStatus, ItemType};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Clone, Debug, Serialize, Deserialize, thiserror::Error)]
#[error("{message}")]
pub struct ServiceError {
    pub code: String,
    pub message: String,
    pub retryable: bool,
}
pub type ServiceResult<T> = std::result::Result<T, ServiceError>;

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ServiceStatus {
    pub storage_available: bool,
    pub message: String,
    pub platform: String,
    pub capabilities: Capabilities,
}
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub struct Capabilities {
    pub local_storage: bool,
    pub clipboard_capture: bool,
    pub direct_paste: bool,
    pub global_shortcut: bool,
    pub icloud: bool,
}
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SearchRequest {
    #[serde(default)]
    pub text: String,
    pub status: Option<ItemStatus>,
    pub item_type: Option<ItemType>,
    pub source_app: Option<String>,
    pub added_after: Option<DateTime<Utc>>,
    pub added_before: Option<DateTime<Utc>>,
    #[serde(default)]
    pub include_trashed: bool,
    #[serde(default)]
    pub pinned_only: bool,
    pub limit: Option<usize>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CreateRequest {
    pub capture_id: Uuid,
    pub item_type: ItemType,
    pub title: String,
    pub text_content: Option<String>,
    pub url_string: Option<String>,
    pub note: Option<String>,
    pub source_app: Option<String>,
    pub language: Option<String>,
    #[serde(default)]
    pub is_pinned: bool,
    #[serde(default)]
    pub directly_archive: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct EditRequest {
    pub title: String,
    pub note: Option<String>,
    pub text_content: Option<String>,
    pub language: Option<String>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct UpdateRequest {
    pub id: Uuid,
    pub expected_updated_at: String,
    pub edit: EditRequest,
}
#[derive(Clone, Copy, Debug, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LifecycleAction {
    Archive,
    RestoreArchive,
    Trash,
    RestoreTrash,
    Pin,
    Unpin,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ApplyRequest {
    pub id: Uuid,
    pub expected_updated_at: String,
    pub command: LifecycleAction,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ItemSummary {
    pub id: Uuid,
    pub item_type: ItemType,
    pub title: String,
    pub source_app: Option<String>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub status: ItemStatus,
    pub is_pinned: bool,
}
impl From<Item> for ItemSummary {
    fn from(item: Item) -> Self {
        Self {
            id: item.id,
            item_type: item.item_type,
            title: item.title,
            source_app: item.source_app,
            created_at: item.created_at,
            updated_at: item.updated_at,
            status: item.status,
            is_pinned: item.is_pinned,
        }
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AttachmentMetadata {
    pub id: Uuid,
    pub file_name: Option<String>,
    pub content_type: Option<String>,
    pub byte_count: u64,
}
/// Embedded icon and preview bytes are always None.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ItemDetail {
    pub capture_replayed: bool,
    pub item: Item,
    pub attachments: Vec<AttachmentMetadata>,
    pub representations_count: usize,
}

/// Editable fields. Text bytes are preserved, not trimmed.
#[derive(Clone, Debug)]
pub struct ItemEdit {
    pub title: String,
    pub note: Option<String>,
    pub text_content: Option<String>,
    pub language: Option<String>,
}

#[derive(Clone, Copy, Debug)]
pub enum ItemCommand {
    Archive,
    RestoreFromArchive,
    Trash,
    RestoreFromTrash,
    SetPinned(bool),
    RecordSuccessfulUse,
}

/// Portable counterpart of the current Swift search options. An empty text query
/// lists matching items by creation date; Trash is excluded unless requested.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SearchQuery {
    pub text: String,
    pub item_type: Option<ItemType>,
    pub source_app: Option<String>,
    pub added_after: Option<DateTime<Utc>>,
    pub added_before: Option<DateTime<Utc>>,
    pub status: Option<ItemStatus>,
    pub include_trashed: bool,
    pub pinned_only: bool,
    pub limit: usize,
}

impl Default for SearchQuery {
    fn default() -> Self {
        Self {
            text: String::new(),
            item_type: None,
            source_app: None,
            added_after: None,
            added_before: None,
            status: None,
            include_trashed: false,
            pinned_only: false,
            limit: 200,
        }
    }
}

pub const SERVICE_TEXT_LIMIT: usize = 1024 * 1024;
pub const SERVICE_FIELD_LIMIT: usize = 16 * 1024;

/// A backend owner executes each operation without interleaving another writer.
/// Implementations compare revisions at native precision before any mutation.
/// The factory creates this value on the service worker; it need not be Send.
pub trait Repository {
    /// Return summaries without content, attachment bytes, or preview bytes.
    fn search(&mut self, request: SearchRequest) -> ServiceResult<Vec<ItemSummary>>;
    /// Return scalar details and attachment metadata, without embedded previews.
    fn get(&mut self, id: Uuid) -> ServiceResult<ItemDetail>;
    /// Replay an explicit capture ID while its item exists. Do not coalesce.
    fn create(&mut self, request: CreateRequest) -> ServiceResult<ItemDetail>;
    /// Compare the exact revision and save atomically at the backend owner.
    fn update(&mut self, request: UpdateRequest) -> ServiceResult<ItemDetail>;
    /// Compare the exact revision before applying the lifecycle command.
    fn apply(&mut self, request: ApplyRequest) -> ServiceResult<ItemDetail>;
    /// Rebuild only derived search data; preserve canonical items and bytes.
    fn rebuild(&mut self) -> ServiceResult<()>;
}

/// Construct an error without including request content.
pub fn service_error(code: &str, message: &str) -> ServiceError {
    ServiceError {
        code: code.into(),
        message: message.into(),
        retryable: matches!(code, "busy" | "storage"),
    }
}

pub fn bounded_string(value: &str, maximum: usize) -> ServiceResult<()> {
    if value.len() > maximum {
        Err(service_error(
            "invalid_argument",
            "A string exceeds its byte limit.",
        ))
    } else {
        Ok(())
    }
}

pub fn optional_string(value: &Option<String>, maximum: usize) -> ServiceResult<()> {
    if let Some(value) = value {
        bounded_string(value, maximum)?;
    }
    Ok(())
}

/// Parse an exact revision, without floating-point or millisecond rounding.
pub fn revision_timestamp(value: &str) -> ServiceResult<DateTime<Utc>> {
    bounded_string(value, 64)?;
    DateTime::parse_from_rfc3339(value)
        .map(|date| date.with_timezone(&Utc))
        .map_err(|_| {
            service_error(
                "invalid_argument",
                "expected_updated_at must be an RFC3339 timestamp.",
            )
        })
}

pub fn next_revision(previous: DateTime<Utc>) -> ServiceResult<DateTime<Utc>> {
    let now = Utc::now();
    if now > previous {
        Ok(now)
    } else {
        previous
            .checked_add_signed(chrono::TimeDelta::nanoseconds(1))
            .ok_or_else(|| service_error("storage", "The item timestamp cannot advance."))
    }
}

impl CreateRequest {
    pub fn validate_type(&self) -> ServiceResult<()> {
        if !matches!(
            self.item_type,
            ItemType::Text | ItemType::Code | ItemType::Link
        ) {
            return Err(service_error(
                "unsupported",
                "Only text, code, and link capture is supported.",
            ));
        }
        Ok(())
    }

    /// Validate the portable create slice before any backend can mutate storage.
    /// Preserve the existing Rust ASCII URL restriction.
    pub fn normalized_draft(&self) -> ServiceResult<CaptureDraft> {
        self.validate_type()?;
        let mut draft = CaptureDraft::new(self.item_type, &self.title);
        draft.id = self.capture_id;
        draft.text_content = self.text_content.clone();
        draft.url_string = self.url_string.clone();
        draft.note = self.note.clone();
        draft.source_app = self.source_app.clone();
        draft.language = self.language.clone();
        draft.is_pinned = self.is_pinned;
        draft.directly_archive = self.directly_archive;
        draft
            .normalized()
            .map_err(|_| service_error("invalid_argument", "invalid capture payload"))
    }
}

impl From<SearchRequest> for SearchQuery {
    fn from(request: SearchRequest) -> Self {
        Self {
            text: request.text,
            item_type: request.item_type,
            source_app: request.source_app,
            added_after: request.added_after,
            added_before: request.added_before,
            status: request.status,
            include_trashed: request.include_trashed,
            pinned_only: request.pinned_only,
            limit: request.limit.unwrap_or(200).clamp(1, 500),
        }
    }
}

impl From<EditRequest> for ItemEdit {
    fn from(edit: EditRequest) -> Self {
        Self {
            title: edit.title,
            note: edit.note,
            text_content: edit.text_content,
            language: edit.language,
        }
    }
}

impl From<LifecycleAction> for ItemCommand {
    fn from(action: LifecycleAction) -> Self {
        match action {
            LifecycleAction::Archive => Self::Archive,
            LifecycleAction::RestoreArchive => Self::RestoreFromArchive,
            LifecycleAction::Trash => Self::Trash,
            LifecycleAction::RestoreTrash => Self::RestoreFromTrash,
            LifecycleAction::Pin => Self::SetPinned(true),
            LifecycleAction::Unpin => Self::SetPinned(false),
        }
    }
}
