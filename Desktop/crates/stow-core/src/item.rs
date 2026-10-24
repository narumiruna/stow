use chrono::{DateTime, TimeDelta, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::CaptureDraft;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ItemType {
    Link,
    Text,
    Code,
    Image,
    File,
}

impl ItemType {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Link => "link",
            Self::Text => "text",
            Self::Code => "code",
            Self::Image => "image",
            Self::File => "file",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ItemStatus {
    Inbox,
    Archived,
    Trashed,
}

impl ItemStatus {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Inbox => "inbox",
            Self::Archived => "archived",
            Self::Trashed => "trashed",
        }
    }
}

/// Lossless snapshot of all Swift StowSchemaV2.StowItem fields.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Item {
    pub id: Uuid,
    pub capture_id: Uuid,
    pub item_type: ItemType,
    pub title: String,
    pub text_content: Option<String>,
    pub url_string: Option<String>,
    pub file_name: Option<String>,
    pub source_app: Option<String>,
    pub source_domain: Option<String>,
    pub note: Option<String>,
    pub language: Option<String>,
    pub link_description: Option<String>,
    pub favicon_data: Option<Vec<u8>>,
    pub link_preview_image_data: Option<Vec<u8>>,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    pub last_used_at: Option<DateTime<Utc>>,
    pub last_captured_at: Option<DateTime<Utc>>,
    pub use_count: i64,
    pub content_fingerprint: Option<String>,
    pub status: ItemStatus,
    pub is_pinned: bool,
    pub trashed_at: Option<DateTime<Utc>>,
    pub status_before_trash: Option<ItemStatus>,
}

impl Item {
    pub fn new(item_type: ItemType, title: impl Into<String>, now: DateTime<Utc>) -> Self {
        let id = Uuid::new_v4();
        Self {
            id,
            capture_id: id,
            item_type,
            title: title.into(),
            text_content: None,
            url_string: None,
            file_name: None,
            source_app: None,
            source_domain: None,
            note: None,
            language: None,
            link_description: None,
            favicon_data: None,
            link_preview_image_data: None,
            created_at: now,
            updated_at: now,
            last_used_at: None,
            last_captured_at: None,
            use_count: 0,
            content_fingerprint: None,
            status: ItemStatus::Inbox,
            is_pinned: false,
            trashed_at: None,
            status_before_trash: None,
        }
    }

    /// The caller must normalize and validate the draft before persistence.
    pub fn from_draft(draft: &CaptureDraft, now: DateTime<Utc>) -> Self {
        let mut item = Self::new(draft.item_type, &draft.title, now);
        item.capture_id = draft.id;
        item.text_content = draft.text_content.clone();
        item.url_string = draft.url_string.clone();
        item.file_name = draft.file_name.clone();
        item.source_app = draft.source_app.clone();
        item.source_domain = draft.source_domain.clone();
        item.note = draft.note.clone();
        item.language = draft.language.clone();
        item.is_pinned = draft.is_pinned;
        if draft.directly_archive {
            item.status = ItemStatus::Archived;
        }
        item
    }

    pub fn archive(&mut self, at: DateTime<Utc>) {
        if self.status != ItemStatus::Trashed {
            self.status = ItemStatus::Archived;
            self.updated_at = at;
        }
    }
    pub fn restore_from_archive(&mut self, at: DateTime<Utc>) {
        if self.status == ItemStatus::Archived {
            self.status = ItemStatus::Inbox;
            self.updated_at = at;
        }
    }
    pub fn trash(&mut self, at: DateTime<Utc>) {
        if self.status != ItemStatus::Trashed {
            self.status_before_trash = Some(self.status);
            self.status = ItemStatus::Trashed;
            self.trashed_at = Some(at);
            self.updated_at = at;
        }
    }
    pub fn restore_from_trash(&mut self, at: DateTime<Utc>) {
        if self.status == ItemStatus::Trashed {
            self.status = if self.status_before_trash == Some(ItemStatus::Archived) {
                ItemStatus::Archived
            } else {
                ItemStatus::Inbox
            };
            self.status_before_trash = None;
            self.trashed_at = None;
            self.updated_at = at;
        }
    }
    pub fn set_pinned(&mut self, pinned: bool, at: DateTime<Utc>) {
        if self.is_pinned != pinned {
            self.is_pinned = pinned;
            self.updated_at = at;
        }
    }
    /// Returns an error without mutation if the stored signed 64-bit count is exhausted.
    pub fn record_successful_use(&mut self, at: DateTime<Utc>) -> Result<(), UseCountOverflow> {
        let count = self.use_count.checked_add(1).ok_or(UseCountOverflow)?;
        self.use_count = count;
        self.last_used_at = Some(at);
        self.updated_at = at;
        Ok(())
    }
    pub fn should_purge(&self, at: DateTime<Utc>, retention_days: i64) -> bool {
        if self.status != ItemStatus::Trashed {
            return false;
        }
        self.trashed_at
            .zip(TimeDelta::try_days(retention_days))
            .and_then(|(date, days)| date.checked_add_signed(days))
            .is_some_and(|deadline| at >= deadline)
    }
    pub fn activity_date(&self) -> DateTime<Utc> {
        self.last_captured_at
            .into_iter()
            .chain(self.last_used_at)
            .chain([self.created_at])
            .max()
            .unwrap()
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, thiserror::Error)]
#[error("The item use count exceeds the signed 64-bit limit.")]
pub struct UseCountOverflow;

/// Descending activity date, then ascending UUID, as in ClipboardActivityOrdering.
pub fn sort_by_activity(items: &mut [Item]) {
    items.sort_by(|a, b| {
        b.activity_date()
            .cmp(&a.activity_date())
            .then(a.id.cmp(&b.id))
    });
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Attachment {
    pub id: Uuid,
    pub item_id: Uuid,
    pub data: Vec<u8>,
    pub thumbnail_data: Option<Vec<u8>>,
    pub content_type: String,
    pub file_name: String,
    pub byte_count: i64,
    pub pixel_width: Option<i64>,
    pub pixel_height: Option<i64>,
    pub created_at: DateTime<Utc>,
}
