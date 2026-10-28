#[cfg(any(target_os = "macos", not(unix)))]
#[test]
fn desktop_open_rejects_disabled_platforms_before_parent_creation() {
    let temp = tempfile::tempdir().unwrap();
    let error = stow_storage::open_desktop(temp.path().join("new/nested/library"))
        .err()
        .unwrap();
    assert_eq!(error.code, "unavailable");
    assert!(!error.retryable);
    assert_eq!(std::fs::read_dir(temp.path()).unwrap().count(), 0);
}

#[cfg(any(target_os = "macos", not(unix)))]
#[test]
fn desktop_open_does_not_change_existing_disabled_platform_store() {
    let temp = tempfile::tempdir().unwrap();
    let root = temp.path().join("existing-library");
    std::fs::create_dir(&root).unwrap();
    let sentinel = root.join("library.sqlite3");
    let original = b"existing canonical store must not change";
    std::fs::write(&sentinel, original).unwrap();
    let permissions = std::fs::metadata(&sentinel).unwrap().permissions();
    assert_eq!(
        stow_storage::open_desktop(root.clone()).err().unwrap().code,
        "unavailable"
    );
    assert_eq!(std::fs::read(&sentinel).unwrap(), original);
    assert_eq!(
        std::fs::metadata(&sentinel).unwrap().permissions(),
        permissions
    );
    assert_eq!(std::fs::read_dir(root).unwrap().count(), 1);
}

#[cfg(target_os = "linux")]
mod linux {
    use chrono::{TimeZone, Utc};
    use std::{
        fs,
        os::unix::fs::{PermissionsExt, symlink},
    };
    use stow_core::{
        ApplyRequest, CaptureDraft, CreateRequest, EditRequest, ItemType, LifecycleAction,
        Repository, RepresentationDraft, UpdateRequest, representation_type,
    };
    use stow_storage::{AttachmentDraft, LocalRepository, open_desktop};
    use uuid::Uuid;

    fn request() -> CreateRequest {
        CreateRequest {
            capture_id: Uuid::new_v4(),
            item_type: ItemType::Text,
            title: "Example".into(),
            text_content: Some("Retained text".into()),
            url_string: None,
            note: None,
            source_app: None,
            language: None,
            is_pinned: false,
            directly_archive: false,
        }
    }

    #[test]
    fn startup_creates_private_parents_and_rejects_symlinks() {
        let temp = tempfile::tempdir().unwrap();
        let parent = temp.path().join("new/nested");
        let repository = open_desktop(parent.join("library")).unwrap();
        assert_eq!(
            fs::metadata(&parent).unwrap().permissions().mode() & 0o777,
            0o700
        );
        drop(repository);
        symlink(&parent, temp.path().join("alias")).unwrap();
        assert!(open_desktop(temp.path().join("alias/rejected")).is_err());
        assert!(!parent.join("rejected").exists());
        assert!(open_desktop(std::path::PathBuf::from("relative/library")).is_err());
        assert!(open_desktop(temp.path().join("missing/../rejected")).is_err());
        assert!(!temp.path().join("missing").exists());
    }

    #[test]
    fn details_exclude_bytes_and_metadata_edits_preserve_canonical_payloads() {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().join("library");
        let mut repository = LocalRepository::open(&root).unwrap();
        let mut draft = CaptureDraft::new(ItemType::Image, "Image");
        draft.staged_attachment_name = Some("staged.png".into());
        draft.attachment_byte_count = Some(3);
        let attachment = AttachmentDraft {
            data: vec![1, 2, 3],
            thumbnail_data: Some(vec![4, 5]),
            content_type: "image/png".into(),
            file_name: "original.png".into(),
            pixel_width: Some(4),
            pixel_height: Some(8),
        };
        let representations = vec![RepresentationDraft {
            type_identifier: representation_type::HTML.into(),
            data: b"<b>image</b>".to_vec(),
            ordinal: 2,
        }];
        let mut item = repository
            .create(
                &draft,
                Some(&attachment),
                &representations,
                Utc.timestamp_opt(1000, 0).unwrap(),
            )
            .unwrap()
            .item;
        item.favicon_data = Some(vec![6, 7]);
        item.link_preview_image_data = Some(vec![8, 9]);
        repository.upsert(&item).unwrap();
        let attachment_id = repository.attachments(item.id).unwrap()[0].id;
        // Detail access must not read blobs, including representation bytes.
        fs::rename(root.join("blobs"), root.join("hidden-blobs")).unwrap();
        let detail = Repository::get(&mut repository, item.id).unwrap();
        fs::rename(root.join("hidden-blobs"), root.join("blobs")).unwrap();
        assert!(detail.item.favicon_data.is_none());
        assert!(detail.item.link_preview_image_data.is_none());
        assert_eq!(detail.representations_count, 1);
        assert_eq!(detail.attachments.len(), 1);
        assert_eq!(detail.attachments[0].byte_count, 3);
        assert_eq!(
            detail.attachments[0].file_name.as_deref(),
            Some("original.png")
        );
        let updated = Repository::update(
            &mut repository,
            UpdateRequest {
                id: item.id,
                expected_updated_at: item.updated_at.to_rfc3339(),
                edit: EditRequest {
                    title: "Renamed".into(),
                    note: Some("Metadata".into()),
                    text_content: None,
                    language: None,
                },
            },
        )
        .unwrap();
        assert_eq!(updated.item.title, "Renamed");
        let stored = repository.get(item.id).unwrap().unwrap();
        assert_eq!(stored.favicon_data, item.favicon_data);
        assert_eq!(stored.link_preview_image_data, item.link_preview_image_data);
        assert_eq!(stored.content_fingerprint, item.content_fingerprint);
        assert_eq!(
            repository
                .load_attachment(attachment_id)
                .unwrap()
                .unwrap()
                .data,
            attachment.data
        );
        assert_eq!(
            repository.representations(item.id).unwrap()[0].data,
            representations[0].data
        );
    }

    #[test]
    fn adapter_checks_exact_revision_and_preserves_data_on_failed_save() {
        let temp = tempfile::tempdir().unwrap();
        let root = temp.path().join("library");
        let mut repository = LocalRepository::open(&root).unwrap();
        let created = Repository::create(&mut repository, request()).unwrap();
        let item = created.item;
        let drift = item.updated_at + chrono::TimeDelta::nanoseconds(1);
        assert_eq!(
            Repository::apply(
                &mut repository,
                ApplyRequest {
                    id: item.id,
                    expected_updated_at: drift.to_rfc3339(),
                    command: LifecycleAction::Trash,
                }
            )
            .unwrap_err()
            .code,
            "conflict"
        );
        assert_eq!(repository.get(item.id).unwrap().unwrap(), item);
        fs::rename(&root, temp.path().join("moved")).unwrap();
        let failure = Repository::update(
            &mut repository,
            UpdateRequest {
                id: item.id,
                expected_updated_at: item.updated_at.to_rfc3339(),
                edit: EditRequest {
                    title: "Failed".into(),
                    note: None,
                    text_content: Some("Not committed".into()),
                    language: None,
                },
            },
        )
        .unwrap_err();
        assert_eq!(failure.code, "storage");
        assert!(failure.retryable);
        assert_eq!(repository.get(item.id).unwrap().unwrap(), item);
        fs::rename(temp.path().join("moved"), root).unwrap();
    }
}
