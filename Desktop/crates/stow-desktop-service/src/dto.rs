use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use stow_core::{Item, ItemStatus, ItemType};
use uuid::Uuid;

#[derive(Clone, Debug, Serialize, Deserialize, thiserror::Error)]
#[error("{message}")]
pub struct ServiceError {
    pub code: String,
    pub message: String,
    pub retryable: bool,
}
pub type Result<T> = std::result::Result<T, ServiceError>;

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
