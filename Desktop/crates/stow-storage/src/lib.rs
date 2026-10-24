//! Local SQLite foundation. This is not the macOS canonical repository.
//! See the crate README for security boundaries and unsupported platforms.

mod blobs;
mod capture;
mod paths;
mod repository;
mod search;
mod width;

pub use blobs::{AttachmentInfo, MAX_ATTACHMENT_BYTES};
pub use capture::{
    AttachmentDescriptor, AttachmentDraft, CaptureKind, CaptureOutcome, ItemCommand, ItemEdit,
};
pub use repository::{DeleteOutcome, LocalRepository};
pub use search::SearchQuery;

pub type Result<T> = std::result::Result<T, Error>;

/// Errors do not include item snapshots, queries, or attachment contents.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("local canonical storage is not available on this platform")]
    UnsupportedPlatform,
    #[error("the library is already open by another writer")]
    Locked,
    #[error("unsafe library path or permissions")]
    UnsafePath,
    #[error("schema version {0} is newer than this application supports")]
    NewerSchema(i64),
    #[error("invalid search query (empty, too long, or contains a control character)")]
    InvalidQuery,
    #[error("item not found")]
    ItemNotFound,
    #[error("attachment not found")]
    AttachmentNotFound,
    #[error("attachment exceeds the 100 MiB limit")]
    AttachmentTooLarge,
    #[error("attachment size or SHA256 verification failed")]
    CorruptAttachment,
    #[error("invalid stored data")]
    InvalidData,
    #[error("invalid capture payload")]
    InvalidCapture,
    #[error("filesystem operation failed")]
    Io(#[from] std::io::Error),
    // Do not expose SQLite error text: constraint messages can contain user input.
    #[error("database operation failed")]
    Sqlite(#[from] rusqlite::Error),
    #[error("snapshot serialization failed")]
    Json(#[from] serde_json::Error),
}
