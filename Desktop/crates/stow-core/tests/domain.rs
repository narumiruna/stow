use chrono::{DateTime, TimeDelta, Utc};
use stow_core::representation_type::*;
use stow_core::*;

fn now() -> DateTime<Utc> {
    DateTime::from_timestamp(1000, 0).unwrap()
}
fn text(value: &str) -> CaptureDraft {
    let mut draft = CaptureDraft::new(ItemType::Text, "");
    draft.text_content = Some(value.to_owned());
    draft
}
fn fingerprint(draft: &CaptureDraft) -> String {
    clipboard_fingerprint(draft, None, &[]).unwrap()
}

#[test]
fn swift_stable_vector_and_normalization_fixtures() {
    // Copied from ClipboardContentFingerprintTests.swift, not a Swift execution.
    assert_eq!(
        fingerprint(&text("Hello\r\nworld")),
        "v1:7ae10e25b69a6bb6514cabad2f01d8c8ad3c7ab43693746abbe8f6062a506888"
    );
    assert_eq!(
        fingerprint(&text("Café\r\nline")),
        fingerprint(&text("Cafe\u{301}\rline"))
    );
    assert_ne!(
        fingerprint(&text("Café\nline")),
        fingerprint(&text("café\nline"))
    );
    assert_ne!(
        fingerprint(&text("Café\nline")),
        fingerprint(&text(" Café\nline"))
    );
    let mut code = text("let x = 1");
    code.item_type = ItemType::Code;
    code.language = Some("SWIFT".into());
    assert_ne!(fingerprint(&code), fingerprint(&text("let x = 1")));
    let upper = fingerprint(&code);
    code.language = Some("swift".into());
    assert_eq!(upper, fingerprint(&code));
}

#[test]
fn fingerprint_representation_order_and_bytes_are_significant() {
    let draft = text("same text");
    let rep = |kind: &str, data: &str| FingerprintRepresentation {
        type_identifier: kind.into(),
        data: data.as_bytes().to_vec(),
    };
    let bold = rep(RTF, "bold");
    let html = rep(HTML, "<b>bold</b>");
    assert_ne!(
        fingerprint(&draft),
        clipboard_fingerprint(&draft, None, std::slice::from_ref(&bold)).unwrap()
    );
    assert_ne!(
        clipboard_fingerprint(&draft, None, &[bold.clone(), html.clone()]).unwrap(),
        clipboard_fingerprint(&draft, None, &[html, bold]).unwrap()
    );
}

#[test]
fn swift_image_file_and_link_fixtures() {
    let mut image = CaptureDraft::new(ItemType::Image, "Image");
    image.content_type = Some("image/png".into());
    let bytes = [0, 1, 2, 3];
    let png = clipboard_fingerprint(&image, Some(&bytes), &[]).unwrap();
    image.title = "Renamed".into();
    image.file_name = Some("other.png".into());
    assert_eq!(
        png,
        clipboard_fingerprint(&image, Some(&bytes), &[]).unwrap()
    );
    image.content_type = Some("image/tiff".into());
    assert_ne!(
        png,
        clipboard_fingerprint(&image, Some(&bytes), &[]).unwrap()
    );
    assert_eq!(
        clipboard_fingerprint(&image, None, &[]),
        Err(FingerprintError::MissingAttachmentData)
    );
    let mut file = CaptureDraft::new(ItemType::File, "File");
    file.file_name = Some("/tmp/Cafe\u{301}.bin".into());
    let first = clipboard_fingerprint(&file, Some(b"asset"), &[]).unwrap();
    file.file_name = Some("Café.bin".into());
    assert_eq!(
        first,
        clipboard_fingerprint(&file, Some(b"asset"), &[]).unwrap()
    );
    file.file_name = Some("different.bin".into());
    assert_ne!(
        first,
        clipboard_fingerprint(&file, Some(b"asset"), &[]).unwrap()
    );
    let mut link = CaptureDraft::new(ItemType::Link, "");
    link.url_string = Some("https://example.com/path".into());
    let first = fingerprint(&link);
    link.title = "Alias".into();
    assert_eq!(first, fingerprint(&link));
}

#[test]
fn draft_preserves_text_and_generates_grapheme_title() {
    let mut draft = text("  first\nsecond  \n");
    draft.note = Some(" process later ".into());
    draft.language = Some(" SWIFT ".into());
    let value = draft.normalized().unwrap();
    assert_eq!(value.title, "first");
    assert_eq!(value.text_content, draft.text_content);
    assert_eq!(value.note.as_deref(), Some("process later"));
    assert_eq!(value.language.as_deref(), Some("swift"));
    let emoji = "👩‍💻";
    let draft = text(&emoji.repeat(81));
    assert_eq!(draft.normalized().unwrap().title, emoji.repeat(80));
    for value in ["", " \n ", "\u{2003}\r\t"] {
        assert_eq!(
            text(value).normalized(),
            Err(CaptureValidationError::MissingText)
        );
    }
}

#[test]
fn url_validation_preserves_fingerprint_spelling() {
    let mut draft = CaptureDraft::new(ItemType::Link, "  ");
    draft.url_string = Some("  https://www.swift.org/documentation  ".into());
    let normalized = draft.normalized().unwrap();
    assert_eq!(normalized.title, "www.swift.org");
    assert_eq!(normalized.source_domain.as_deref(), Some("www.swift.org"));
    assert_eq!(
        normalized.url_string.as_deref(),
        Some("https://www.swift.org/documentation")
    );
    draft.url_string = Some("https://example.com:443".into());
    assert_eq!(draft.normalized().unwrap().url_string, draft.url_string);
    for value in [
        "not a url",
        "ftp://example.com",
        "file:///tmp/a",
        "https://",
        "https:example.com",
        "https://a\nb",
        "https:///example.com",
        "https://example.com/a b",
        "https://example.com/日本語",
        "https://example.com/<tag>",
        "https://example.com/%xx",
        "https://example.com/%",
        r"https://example.com\path",
    ] {
        draft.url_string = Some(value.into());
        assert_eq!(draft.normalized(), Err(CaptureValidationError::InvalidUrl));
    }
}

#[test]
fn attachment_validation_boundaries() {
    let mut draft = CaptureDraft::new(ItemType::File, "");
    assert_eq!(
        draft.normalized(),
        Err(CaptureValidationError::MissingAttachment)
    );
    draft.staged_attachment_name = Some(" staged ".into());
    draft.file_name = Some(" file.bin ".into());
    draft.attachment_byte_count = Some(MAXIMUM_ATTACHMENT_BYTES);
    let normalized = draft.normalized().unwrap();
    assert_eq!(normalized.title, "file.bin");
    assert_eq!(normalized.staged_attachment_name.as_deref(), Some("staged"));
    draft.attachment_byte_count = Some(MAXIMUM_ATTACHMENT_BYTES + 1);
    assert_eq!(
        draft.normalized(),
        Err(CaptureValidationError::AttachmentTooLarge)
    );
    draft.attachment_byte_count = Some(-1);
    assert_eq!(
        draft.normalized(),
        Err(CaptureValidationError::InvalidAttachmentByteCount)
    );
}

#[test]
fn lifecycle_matches_swift_including_noops_and_archive_timestamp_refresh() {
    let start = now();
    let later = start + TimeDelta::seconds(10);
    let mut item = Item::new(ItemType::Text, "note", start);
    let original = item.clone();
    item.restore_from_archive(later);
    item.restore_from_trash(later);
    item.set_pinned(false, later);
    assert_eq!(item, original);
    item.archive(start);
    item.archive(later);
    assert_eq!(item.updated_at, later);
    item.trash(later);
    let trashed = item.clone();
    item.trash(start);
    item.archive(start);
    item.restore_from_archive(start);
    assert_eq!(item, trashed);
    assert!(!item.should_purge(later + TimeDelta::days(30) - TimeDelta::seconds(1), 30));
    assert!(item.should_purge(later + TimeDelta::days(30), 30));
    item.restore_from_trash(start);
    assert_eq!(item.status, ItemStatus::Archived);
    assert_eq!(item.trashed_at, None);
    assert_eq!(item.status_before_trash, None);
    item.restore_from_archive(later);
    assert_eq!(item.status, ItemStatus::Inbox);
    item.record_successful_use(later).unwrap();
    assert_eq!(item.use_count, 1);
    assert_eq!(item.last_used_at, Some(later));
    item.use_count = i64::MAX;
    let original = item.clone();
    assert_eq!(item.record_successful_use(start), Err(UseCountOverflow));
    assert_eq!(item, original);
}

#[test]
fn draft_flags_ordering_and_missing_restore_state() {
    let mut draft = text("code");
    draft.directly_archive = true;
    draft.is_pinned = true;
    let item = Item::from_draft(&draft.normalized().unwrap(), now());
    assert_eq!(item.capture_id, draft.id);
    assert_eq!(item.status, ItemStatus::Archived);
    assert!(item.is_pinned);
    let mut a = Item::new(ItemType::Text, "a", now());
    let mut b = a.clone();
    a.id = uuid::Uuid::from_u128(1);
    b.id = uuid::Uuid::from_u128(2);
    let mut items = vec![b.clone(), a.clone()];
    sort_by_activity(&mut items);
    assert_eq!(items[0].id, a.id);
    b.last_captured_at = Some(now() + TimeDelta::seconds(1));
    items = vec![a.clone(), b];
    sort_by_activity(&mut items);
    assert_eq!(items[0].id, uuid::Uuid::from_u128(2));
    a.status = ItemStatus::Trashed;
    a.status_before_trash = Some(ItemStatus::Trashed);
    a.restore_from_trash(now());
    assert_eq!(a.status, ItemStatus::Inbox);
}

fn rep(kind: &str, length: usize, ordinal: i64) -> RepresentationDraft {
    RepresentationDraft {
        type_identifier: kind.into(),
        data: vec![1; length],
        ordinal,
    }
}
#[test]
fn representation_validation_rules() {
    use RepresentationScope::*;
    assert!(validate_representations(&[], Auxiliary).is_ok());
    assert!(validate_representations(&[rep(RTF, 1, 2), rep(HTML, 1, 1)], Auxiliary).is_ok());
    for (reps, error) in [
        (
            vec![rep("private", 1, 0)],
            RepresentationError::UnsupportedType("private".into()),
        ),
        (
            vec![rep(RTF, 0, 0)],
            RepresentationError::EmptyData(RTF.into()),
        ),
        (
            vec![rep(RTF, 1, -1)],
            RepresentationError::InvalidOrdinal(-1),
        ),
        (
            vec![rep(RTF, 1, 0), rep(HTML, 1, 0)],
            RepresentationError::InvalidOrdinal(0),
        ),
        (
            vec![rep(RTF, 1, 0), rep(RTF, 1, 1)],
            RepresentationError::DuplicateType(RTF.into()),
        ),
    ] {
        assert_eq!(validate_representations(&reps, Auxiliary), Err(error));
    }
    assert_eq!(
        validate_representations(&[rep(PLAIN_TEXT, 1, 0)], Auxiliary),
        Err(RepresentationError::UnsupportedType(PLAIN_TEXT.into()))
    );
    for (kind, maximum) in [
        (PLAIN_TEXT, PLAIN_TEXT_BYTES),
        (RTF, RICH_TEXT_BYTES),
        (HTML, RICH_TEXT_BYTES),
        (URL, URL_BYTES),
        (PNG, IMAGE_BYTES),
        (TIFF, IMAGE_BYTES),
    ] {
        assert!(validate_representations(&[rep(kind, maximum, 0)], Captured).is_ok());
        assert_eq!(
            validate_representations(&[rep(kind, maximum + 1, 0)], Captured),
            Err(RepresentationError::RepresentationTooLarge(kind.into()))
        );
    }
    let mut reps = vec![
        rep(PNG, IMAGE_BYTES, 0),
        rep(RTF, RICH_TEXT_BYTES, 1),
        rep(HTML, RICH_TEXT_BYTES, 2),
    ];
    assert!(validate_representations(&reps, Captured).is_ok());
    reps.push(rep(URL, 1, 3));
    assert_eq!(
        validate_representations(&reps, Captured),
        Err(RepresentationError::TotalTooLarge)
    );
}

#[test]
fn all_snapshot_fields_round_trip_without_normalizing() {
    let mut item = Item::new(ItemType::Code, "  original  ", now());
    item.text_content = Some("\r\nraw".into());
    item.url_string = Some("https://example.com".into());
    item.file_name = Some("a.bin".into());
    item.source_app = Some("App".into());
    item.source_domain = Some("example.com".into());
    item.note = Some("note".into());
    item.language = Some("Rust".into());
    item.link_description = Some("description".into());
    item.favicon_data = Some(vec![0, 255]);
    item.link_preview_image_data = Some(vec![1, 2]);
    item.last_captured_at = Some(now());
    item.last_used_at = Some(now());
    item.use_count = 8;
    item.content_fingerprint = Some("v1:test".into());
    item.status = ItemStatus::Trashed;
    item.is_pinned = true;
    item.trashed_at = Some(now());
    item.status_before_trash = Some(ItemStatus::Archived);
    let json = serde_json::to_string(&item).unwrap();
    assert_eq!(serde_json::from_str::<Item>(&json).unwrap(), item);
    assert!(json.contains("\"status\":\"trashed\""));
    assert!(json.contains("1970-01-01T00:16:40Z"));
    let attachment = Attachment {
        id: uuid::Uuid::new_v4(),
        item_id: item.id,
        data: vec![0, 255],
        thumbnail_data: Some(vec![2]),
        content_type: "image/png".into(),
        file_name: "raw.bin".into(),
        byte_count: 2,
        pixel_width: Some(1),
        pixel_height: Some(2),
        created_at: now(),
    };
    assert_eq!(
        serde_json::from_str::<Attachment>(&serde_json::to_string(&attachment).unwrap()).unwrap(),
        attachment
    );
    let representation = Representation {
        id: uuid::Uuid::new_v4(),
        item_id: item.id,
        type_identifier: RTF.into(),
        data: vec![1],
        byte_count: 1,
        ordinal: 7,
        created_at: now(),
    };
    assert_eq!(
        serde_json::from_str::<Representation>(&serde_json::to_string(&representation).unwrap())
            .unwrap(),
        representation
    );
    assert!(serde_json::from_str::<ItemStatus>("\"unknown\"").is_err());
}
