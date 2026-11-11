use crate::{Attachment, CaptureDraft, CaptureValidationError, Item, ItemType};
use sha2::{Digest, Sha256};
use unicode_normalization::UnicodeNormalization;

pub const FINGERPRINT_FORMAT_VERSION: u64 = 1;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FingerprintRepresentation {
    pub type_identifier: String,
    pub data: Vec<u8>,
}

#[derive(Clone, Debug, PartialEq, Eq, thiserror::Error)]
pub enum FingerprintError {
    #[error(transparent)]
    Validation(#[from] CaptureValidationError),
    #[error("Original attachment data is unavailable.")]
    MissingAttachmentData,
}

/// Swift v1 canonical stream: UInt64 big-endian lengths, UTF-8, SHA-256.
/// Auxiliary inputs are used in the supplied order, not sorted or validated here.
/// Fixed Swift test vectors are ported to Rust tests. Cross-language execution and
/// the full Foundation URL normalization surface remain release verification gates.
pub fn clipboard_fingerprint(
    draft: &CaptureDraft,
    attachment_data: Option<&[u8]>,
    auxiliary: &[FingerprintRepresentation],
) -> Result<String, FingerprintError> {
    let mut stream = CanonicalStream(Sha256::new());
    stream.bytes(b"stow.clipboard.fingerprint");
    stream.integer(FINGERPRINT_FORMAT_VERSION);
    stream.bytes(draft.item_type.as_str().as_bytes());
    match draft.item_type {
        ItemType::Text | ItemType::Code => {
            let text = draft
                .text_content
                .as_deref()
                .filter(|s| !s.trim().is_empty())
                .ok_or(CaptureValidationError::MissingText)?;
            let normalized: String = text
                .replace("\r\n", "\n")
                .replace('\r', "\n")
                .nfc()
                .collect();
            stream.bytes(normalized.as_bytes());
            if draft.item_type == ItemType::Code {
                stream.bytes(
                    draft
                        .language
                        .as_deref()
                        .unwrap_or("")
                        .to_lowercase()
                        .as_bytes(),
                );
            }
            stream.integer(auxiliary.len() as u64);
            for rep in auxiliary {
                stream.bytes(rep.type_identifier.as_bytes());
                stream.bytes(&rep.data);
            }
        }
        ItemType::Link => {
            stream.bytes(
                draft
                    .normalized()?
                    .url_string
                    .as_deref()
                    .unwrap_or("")
                    .as_bytes(),
            );
        }
        ItemType::Image => {
            let data = attachment_data.ok_or(FingerprintError::MissingAttachmentData)?;
            stream.bytes(
                draft
                    .content_type
                    .as_deref()
                    .unwrap_or("application/octet-stream")
                    .to_lowercase()
                    .as_bytes(),
            );
            stream.bytes(data);
        }
        ItemType::File => {
            let data = attachment_data.ok_or(FingerprintError::MissingAttachmentData)?;
            // Foundation fileURLWithPath uses POSIX separators, even on this portable path.
            let name = draft.file_name.as_deref().unwrap_or(&draft.title);
            let name = name.trim_end_matches('/').rsplit('/').next().unwrap_or("");
            stream.bytes(name.nfc().collect::<String>().as_bytes());
            stream.bytes(data);
        }
    }
    Ok(format!(
        "v{FINGERPRINT_FORMAT_VERSION}:{:x}",
        stream.0.finalize()
    ))
}

pub fn item_fingerprint(
    item: &Item,
    attachment: Option<&Attachment>,
    auxiliary: &[FingerprintRepresentation],
) -> Result<String, FingerprintError> {
    let mut draft = CaptureDraft::new(item.item_type, &item.title);
    draft.text_content = item.text_content.clone();
    draft.url_string = item.url_string.clone();
    draft.file_name = item.file_name.clone();
    draft.language = item.language.clone();
    draft.content_type = attachment.map(|a| a.content_type.clone());
    clipboard_fingerprint(&draft, attachment.map(|a| a.data.as_slice()), auxiliary)
}

struct CanonicalStream(Sha256);
impl CanonicalStream {
    fn integer(&mut self, value: u64) {
        self.0.update(value.to_be_bytes());
    }
    fn bytes(&mut self, bytes: &[u8]) {
        self.integer(bytes.len() as u64);
        self.0.update(bytes);
    }
}
