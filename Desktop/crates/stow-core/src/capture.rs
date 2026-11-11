use crate::ItemType;
use serde::{Deserialize, Serialize};
use unicode_segmentation::UnicodeSegmentation;
use uuid::Uuid;

pub const MAXIMUM_ATTACHMENT_BYTES: i64 = 100 * 1024 * 1024;

#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error)]
pub enum CaptureValidationError {
    #[error("The shared text is empty.")]
    MissingText,
    #[error("The shared link is not a valid HTTP or HTTPS URL.")]
    InvalidUrl,
    #[error("The shared image or file is unavailable.")]
    MissingAttachment,
    #[error("The capture does not provide a supported URL, text, image, or file representation.")]
    UnsupportedRepresentation,
    #[error("The attachment exceeds the 100 MiB limit.")]
    AttachmentTooLarge,
    #[error("The attachment byte count is negative.")]
    InvalidAttachmentByteCount,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct CaptureDraft {
    pub id: Uuid,
    pub item_type: ItemType,
    pub title: String,
    pub text_content: Option<String>,
    pub url_string: Option<String>,
    pub staged_attachment_name: Option<String>,
    pub attachment_byte_count: Option<i64>,
    pub content_type: Option<String>,
    pub file_name: Option<String>,
    pub source_app: Option<String>,
    pub source_domain: Option<String>,
    pub note: Option<String>,
    pub language: Option<String>,
    pub is_pinned: bool,
    pub directly_archive: bool,
}

impl CaptureDraft {
    pub fn new(item_type: ItemType, title: impl Into<String>) -> Self {
        Self {
            id: Uuid::new_v4(),
            item_type,
            title: title.into(),
            text_content: None,
            url_string: None,
            staged_attachment_name: None,
            attachment_byte_count: None,
            content_type: None,
            file_name: None,
            source_app: None,
            source_domain: None,
            note: None,
            language: None,
            is_pinned: false,
            directly_archive: false,
        }
    }
    pub fn normalized(&self) -> Result<Self, CaptureValidationError> {
        self.normalized_with_attachment_limit(MAXIMUM_ATTACHMENT_BYTES)
    }
    pub fn normalized_with_attachment_limit(
        &self,
        maximum: i64,
    ) -> Result<Self, CaptureValidationError> {
        let mut result = self.clone();
        result.title = self.title.trim().to_owned();
        result.note = nonempty(self.note.as_deref());
        result.language = nonempty(self.language.as_deref()).map(|s| s.to_lowercase());
        result.file_name = nonempty(self.file_name.as_deref());
        result.source_app = nonempty(self.source_app.as_deref());
        match self.item_type {
            ItemType::Link => {
                let value = self.url_string.as_deref().unwrap_or("").trim();
                // Reject spellings that require parser repair or percent encoding.
                // Native Foundation comparison is still required before v1 reuse.
                if !supported_url_spelling(value) {
                    return Err(CaptureValidationError::InvalidUrl);
                }
                let url = url::Url::parse(value).map_err(|_| CaptureValidationError::InvalidUrl)?;
                if !matches!(url.scheme(), "http" | "https")
                    || url.host_str().is_none_or(str::is_empty)
                    || !value.contains("://")
                    || value.chars().any(char::is_control)
                {
                    return Err(CaptureValidationError::InvalidUrl);
                }
                let host = url.host_str().ok_or(CaptureValidationError::InvalidUrl)?;
                // Do not use Url::to_string(): it adds '/' and removes default ports,
                // changing the input used by the Swift fingerprint format.
                result.url_string = Some(value.to_owned());
                result.source_domain = Some(host.to_lowercase());
                if result.title.is_empty() {
                    result.title = host.to_owned();
                }
            }
            ItemType::Text | ItemType::Code => {
                let text = self.text_content.as_deref().unwrap_or("");
                let display = text.trim();
                if display.is_empty() {
                    return Err(CaptureValidationError::MissingText);
                }
                if result.title.is_empty() {
                    let first = display
                        .split([
                            '\n', '\r', '\u{000b}', '\u{000c}', '\u{0085}', '\u{2028}', '\u{2029}',
                        ])
                        .find(|s| !s.is_empty())
                        .unwrap_or("Text");
                    result.title = first.graphemes(true).take(80).collect();
                }
            }
            ItemType::Image | ItemType::File => {
                result.staged_attachment_name = Some(
                    nonempty(self.staged_attachment_name.as_deref())
                        .ok_or(CaptureValidationError::MissingAttachment)?,
                );
                if self.attachment_byte_count.is_some_and(|n| n < 0) {
                    return Err(CaptureValidationError::InvalidAttachmentByteCount);
                }
                if self.attachment_byte_count.is_some_and(|n| n > maximum) {
                    return Err(CaptureValidationError::AttachmentTooLarge);
                }
                if result.title.is_empty() {
                    result.title = result.file_name.clone().unwrap_or_else(|| {
                        if self.item_type == ItemType::Image {
                            "Image"
                        } else {
                            "File"
                        }
                        .to_owned()
                    });
                }
            }
        }
        Ok(result)
    }
}

fn supported_url_spelling(value: &str) -> bool {
    let Some((_, remainder)) = value.split_once("://") else {
        return false;
    };
    if remainder.is_empty() || remainder.starts_with(['/', '\\']) {
        return false;
    }
    let bytes = value.as_bytes();
    let mut index = 0;
    while index < bytes.len() {
        let byte = bytes[index];
        if byte == b'%' {
            if index + 2 >= bytes.len()
                || !bytes[index + 1].is_ascii_hexdigit()
                || !bytes[index + 2].is_ascii_hexdigit()
            {
                return false;
            }
            index += 3;
        } else if byte.is_ascii_alphanumeric() || b"-._~:/?#[]@!$&'()*+,;=".contains(&byte) {
            index += 1;
        } else {
            return false;
        }
    }
    true
}

fn nonempty(value: Option<&str>) -> Option<String> {
    value
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_owned)
}
