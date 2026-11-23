//! Compatibility reexports of the portable service contract.
pub use stow_core::{
    ApplyRequest, AttachmentMetadata, Capabilities, CreateRequest, EditRequest, ItemDetail,
    ItemSummary, LifecycleAction, SearchRequest, ServiceError, ServiceStatus, UpdateRequest,
};
pub type Result<T> = stow_core::ServiceResult<T>;
