use serde_json::Value;
use stow_core::{
    CaptureDraft, Item, ItemStatus, LifecycleAction, ServiceError, revision_timestamp,
};

fn fixture() -> Value {
    let value: Value =
        serde_json::from_str(include_str!("../../../fixtures/backend.json")).unwrap();
    assert_eq!(value["version"], 1);
    value
}

#[test]
fn complete_item_snapshots_roundtrip_all_fields_and_nulls() {
    let fixture = fixture();
    assert_eq!(fixture["items"].as_array().unwrap().len(), 5);
    for raw in fixture["items"].as_array().unwrap() {
        let item: Item = serde_json::from_value(raw.clone()).unwrap();
        let encoded = serde_json::to_value(&item).unwrap();
        assert_eq!(
            encoded.as_object().unwrap().len(),
            raw.as_object().unwrap().len()
        );
        // RFC3339 permits shorter equivalent fractional seconds. Compare every
        // timestamp at nanosecond precision and every other scalar literally.
        for (key, expected) in raw.as_object().unwrap() {
            let actual = &encoded[key];
            if key.ends_with("_at") && !expected.is_null() {
                assert_eq!(
                    revision_timestamp(actual.as_str().unwrap()).unwrap(),
                    revision_timestamp(expected.as_str().unwrap()).unwrap(),
                    "{key}"
                );
            } else {
                assert_eq!(actual, expected, "{key}");
            }
        }
        assert_eq!(serde_json::from_value::<Item>(encoded).unwrap(), item);
    }
}

#[test]
fn normalization_respects_declared_rust_support_and_expected_fields() {
    for case in fixture()["normalization"].as_array().unwrap() {
        let draft: CaptureDraft = serde_json::from_value(case["draft"].clone()).unwrap();
        let result = draft.normalized();
        assert_eq!(
            result.is_ok(),
            case["rust_ok"].as_bool().unwrap(),
            "{}",
            case["name"]
        );
        if let Ok(normalized) = result {
            let actual = serde_json::to_value(normalized).unwrap();
            for (key, expected) in case["expected"].as_object().unwrap() {
                assert_eq!(&actual[key], expected, "{}: {key}", case["name"]);
            }
        }
    }
}

#[test]
fn revisions_compare_exact_nanoseconds() {
    for pair in fixture()["revision_pairs"].as_array().unwrap() {
        let first = revision_timestamp(pair["first"].as_str().unwrap()).unwrap();
        let second = revision_timestamp(pair["second"].as_str().unwrap()).unwrap();
        assert_eq!(first == second, pair["equal"].as_bool().unwrap());
    }
}

#[test]
fn content_free_error_fields_roundtrip() {
    for raw in fixture()["errors"].as_array().unwrap() {
        let error: ServiceError = serde_json::from_value(raw.clone()).unwrap();
        assert_eq!(serde_json::to_value(&error).unwrap(), *raw);
        assert_eq!(error.to_string(), error.message);
    }
}

#[test]
fn lifecycle_actions_preserve_restore_state() {
    let now = revision_timestamp("2026-01-01T00:00:00.125000000Z").unwrap();
    for case in fixture()["lifecycle"].as_array().unwrap() {
        let mut item = Item::new(stow_core::ItemType::Text, "Fixture", now);
        item.status = serde_json::from_value(case["initial"].clone()).unwrap();
        for raw in case["actions"].as_array().unwrap() {
            let action: LifecycleAction = serde_json::from_value(raw.clone()).unwrap();
            match action {
                LifecycleAction::Archive => item.archive(now),
                LifecycleAction::RestoreArchive => item.restore_from_archive(now),
                LifecycleAction::Trash => item.trash(now),
                LifecycleAction::RestoreTrash => item.restore_from_trash(now),
                LifecycleAction::Pin => item.set_pinned(true, now),
                LifecycleAction::Unpin => item.set_pinned(false, now),
            }
        }
        assert_eq!(
            item.status,
            serde_json::from_value::<ItemStatus>(case["expected"].clone()).unwrap()
        );
        assert!(item.trashed_at.is_none());
        assert!(item.status_before_trash.is_none());
    }
}
