use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use uuid::Uuid;

/// Original Apple identifiers. Platform adapters must map native formats explicitly.
pub mod representation_type {
    pub const PLAIN_TEXT: &str = "public.utf8-plain-text";
    pub const RTF: &str = "public.rtf";
    pub const HTML: &str = "public.html";
    pub const URL: &str = "public.url";
    pub const PNG: &str = "public.png";
    pub const TIFF: &str = "public.tiff";
    pub const FILE_URL: &str = "public.file-url";
    pub const STOW_OWNED: &str = "dev.narumi.stow.owned-content";
}
pub const PLAIN_TEXT_BYTES: usize = 1024 * 1024;
pub const RICH_TEXT_BYTES: usize = 5 * 1024 * 1024;
pub const URL_BYTES: usize = 16 * 1024;
pub const IMAGE_BYTES: usize = 100 * 1024 * 1024;
pub const TOTAL_REPRESENTATION_BYTES: usize = 110 * 1024 * 1024;

pub fn maximum_representation_bytes(identifier: &str) -> Option<usize> {
    use representation_type::*;
    match identifier {
        PLAIN_TEXT => Some(PLAIN_TEXT_BYTES),
        RTF | HTML => Some(RICH_TEXT_BYTES),
        URL => Some(URL_BYTES),
        PNG | TIFF => Some(IMAGE_BYTES),
        _ => None,
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct RepresentationDraft {
    pub type_identifier: String,
    pub data: Vec<u8>,
    pub ordinal: i64,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Representation {
    pub id: Uuid,
    pub item_id: Uuid,
    pub type_identifier: String,
    pub data: Vec<u8>,
    pub byte_count: i64,
    pub ordinal: i64,
    pub created_at: DateTime<Utc>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RepresentationScope {
    Auxiliary,
    Captured,
}

#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error)]
pub enum RepresentationError {
    #[error("Unsupported clipboard type: {0}")]
    UnsupportedType(String),
    #[error("Duplicate clipboard type: {0}")]
    DuplicateType(String),
    #[error("Empty clipboard data: {0}")]
    EmptyData(String),
    #[error("Invalid clipboard order: {0}")]
    InvalidOrdinal(i64),
    #[error("Clipboard format exceeds its byte limit: {0}")]
    RepresentationTooLarge(String),
    #[error("Preserved clipboard formats exceed the total byte limit.")]
    TotalTooLarge,
}

/// Validates without changing caller order. Ordinals need not be contiguous.
pub fn validate_representations(
    representations: &[RepresentationDraft],
    scope: RepresentationScope,
) -> Result<(), RepresentationError> {
    use representation_type::*;
    let mut seen = HashSet::new();
    let mut ordinals = HashSet::new();
    let mut total = 0usize;
    for rep in representations {
        let identifier = rep.type_identifier.as_str();
        let maximum = maximum_representation_bytes(identifier)
            .filter(|_| {
                scope == RepresentationScope::Captured || matches!(identifier, RTF | HTML | URL)
            })
            .ok_or_else(|| RepresentationError::UnsupportedType(identifier.to_owned()))?;
        if !seen.insert(identifier) {
            return Err(RepresentationError::DuplicateType(identifier.to_owned()));
        }
        if rep.data.is_empty() {
            return Err(RepresentationError::EmptyData(identifier.to_owned()));
        }
        if rep.ordinal < 0 || !ordinals.insert(rep.ordinal) {
            return Err(RepresentationError::InvalidOrdinal(rep.ordinal));
        }
        if rep.data.len() > maximum {
            return Err(RepresentationError::RepresentationTooLarge(
                identifier.to_owned(),
            ));
        }
        total = total
            .checked_add(rep.data.len())
            .ok_or(RepresentationError::TotalTooLarge)?;
        if total > TOTAL_REPRESENTATION_BYTES {
            return Err(RepresentationError::TotalTooLarge);
        }
    }
    Ok(())
}
