#![cfg(all(unix, not(target_os = "macos")))]

use chrono::{DateTime, Utc};
use stow_core::{Item, ItemStatus, ItemType};
use stow_storage::{Error, LocalRepository, SearchQuery};
use tempfile::TempDir;
use uuid::Uuid;

fn item(id: u128, title: &str, seconds: i64) -> Item {
    let mut item = Item::new(
        ItemType::Text,
        title,
        DateTime::from_timestamp(seconds, 0).unwrap(),
    );
    item.id = Uuid::from_u128(id);
    item.capture_id = item.id;
    item
}

fn fixture() -> (TempDir, LocalRepository) {
    let directory = TempDir::new().unwrap();
    let repository = LocalRepository::open(directory.path().join("library")).unwrap();
    (directory, repository)
}

fn query(text: &str) -> SearchQuery {
    SearchQuery {
        text: text.into(),
        ..Default::default()
    }
}

fn ids(items: Vec<Item>) -> Vec<Uuid> {
    items.into_iter().map(|item| item.id).collect()
}

#[test]
fn all_prefix_tokens_and_metadata_filters_match_swift_fixtures() {
    let (_directory, mut repository) = fixture();
    let mut wanted = item(1, "Swift structured concurrency guide", 200);
    wanted.item_type = ItemType::File;
    wanted.source_app = Some("Safari".into());
    let mut wrong_type = item(2, "Swift concurrency notes", 300);
    wrong_type.source_app = Some("Notes".into());
    repository.upsert(&wanted).unwrap();
    repository.upsert(&wrong_type).unwrap();
    let mut search = query("swift concur");
    search.item_type = Some(ItemType::File);
    search.source_app = Some("sAfArI".into());
    assert_eq!(repository.search_items(&search).unwrap(), vec![wanted]);
    search.source_app = Some("Notes".into());
    assert!(repository.search_items(&search).unwrap().is_empty());
    assert!(
        repository
            .search_items(&query("Safari"))
            .unwrap()
            .is_empty()
    );
}

#[test]
fn width_diacritics_nul_and_utf8_content_survive_binding() {
    let (_directory, mut repository) = fixture();
    let items = [
        item(1, "Swift concurrency guide", 100),
        item(2, "Ｐａｎｅｌ　Ｔｅｘｔ", 100),
        item(3, "beforeToken\0afterToken", 100),
        item(4, "咖啡 手帳", 100),
        item(5, "Café ガイド", 100),
        item(6, "", 100),
    ];
    for item in &items {
        repository.upsert(item).unwrap();
    }
    for (text, id) in [
        ("Ｓｗｉｆｔ　ｃｏｎｃｕｒｒｅｎｃｙ", 1),
        ("Panel Text", 2),
        ("beforeToken", 3),
        ("afterToken", 3),
        ("咖啡", 4),
        ("Cafe", 5),
        ("ｶﾞｲﾄﾞ", 5),
    ] {
        assert_eq!(
            ids(repository.search_items(&query(text)).unwrap()),
            vec![Uuid::from_u128(id)],
            "{text}"
        );
    }
    assert_eq!(
        repository
            .search_items(&SearchQuery::default())
            .unwrap()
            .len(),
        6
    );
}

#[test]
fn legacy_literal_queries_use_the_same_width_mapping_as_indexed_content() {
    let (_directory, mut repository) = fixture();
    for (index, title) in ["Ｐａｎｅｌ", "ガイド", "ㄱㄴㄷ"].iter().enumerate() {
        let item = item(index as u128 + 1, title, 100);
        repository.upsert(&item).unwrap();
        assert_eq!(repository.search(title).unwrap(), vec![item]);
    }
}

#[test]
fn trash_default_explicit_status_and_include_trashed_match_swift() {
    let (_directory, mut repository) = fixture();
    let mut live = item(1, "receipt", 100);
    live.status = ItemStatus::Archived;
    let mut trashed = item(2, "receipt", 100);
    trashed.trash(Utc::now());
    repository.upsert(&live).unwrap();
    repository.upsert(&trashed).unwrap();
    assert_eq!(
        repository.search_items(&query("receipt")).unwrap(),
        vec![live]
    );
    let mut search = query("receipt");
    search.status = Some(ItemStatus::Trashed);
    assert_eq!(repository.search_items(&search).unwrap(), vec![trashed]);
    search.status = None;
    search.include_trashed = true;
    assert_eq!(repository.search_items(&search).unwrap().len(), 2);
}

#[test]
fn empty_text_inclusive_dates_and_ties_have_stable_order() {
    let (_directory, mut repository) = fixture();
    let old = item(1, "old", 100);
    let newer_b = item(3, "newer b", 200);
    let newer_a = item(2, "newer a", 200);
    for item in [&old, &newer_b, &newer_a] {
        repository.upsert(item).unwrap();
    }
    let mut search = SearchQuery {
        added_after: Some(old.created_at),
        added_before: Some(newer_a.created_at),
        ..Default::default()
    };
    assert_eq!(
        ids(repository.search_items(&search).unwrap()),
        vec![newer_a.id, newer_b.id, old.id]
    );
    search.added_after = Some(newer_a.created_at);
    assert_eq!(
        ids(repository.search_items(&search).unwrap()),
        vec![newer_a.id, newer_b.id]
    );
    search.added_before = Some(old.created_at);
    assert!(repository.search_items(&search).unwrap().is_empty());
    search = SearchQuery::default();
    search.limit = 0;
    assert_eq!(
        ids(repository.search_items(&search).unwrap()),
        vec![newer_a.id]
    );
    search.limit = usize::MAX;
    assert_eq!(repository.search_items(&search).unwrap().len(), 3);
}

#[test]
fn query_language_is_not_executed_and_input_is_bounded() {
    let (_directory, mut repository) = fixture();
    let first = item(1, "alpha beta", 100);
    let literal = item(2, "alpha OR gamma", 100);
    let other = item(3, "gamma", 100);
    for item in [&first, &literal, &other] {
        repository.upsert(item).unwrap();
    }
    assert_eq!(
        repository.search_items(&query("alpha OR gamma")).unwrap(),
        vec![literal]
    );
    assert_eq!(
        repository.search_items(&query("*** () '\"")).unwrap().len(),
        3
    );
    assert!(
        repository
            .search_items(&query("'; DROP TABLE items;--"))
            .unwrap()
            .is_empty()
    );
    assert_eq!(repository.list().unwrap().len(), 3);
    assert!(matches!(
        repository.search_items(&query(&"a".repeat(4097))),
        Err(Error::InvalidQuery)
    ));
}

#[test]
fn changed_metadata_and_text_are_indexed_atomically_and_rebuildable() {
    let (directory, mut repository) = fixture();
    let mut item = item(1, "before", 100);
    item.source_app = Some("Safari".into());
    repository.upsert(&item).unwrap();
    item.title = "after".into();
    item.item_type = ItemType::Code;
    item.source_app = Some("Editor".into());
    item.status = ItemStatus::Archived;
    repository.upsert(&item).unwrap();
    assert!(
        repository
            .search_items(&query("before"))
            .unwrap()
            .is_empty()
    );
    let search = SearchQuery {
        text: "after".into(),
        item_type: Some(ItemType::Code),
        source_app: Some("Editor".into()),
        status: Some(ItemStatus::Archived),
        ..Default::default()
    };
    assert_eq!(
        repository.search_items(&search).unwrap(),
        vec![item.clone()]
    );
    drop(repository);
    let mut repository = LocalRepository::open(directory.path().join("library")).unwrap();
    assert_eq!(
        repository.search_items(&search).unwrap(),
        vec![item.clone()]
    );
    repository.rebuild_index().unwrap();
    assert_eq!(
        repository.search_items(&search).unwrap(),
        vec![item.clone()]
    );
    assert!(repository.delete(item.id).unwrap().deleted);
    assert!(repository.search_items(&search).unwrap().is_empty());
}
