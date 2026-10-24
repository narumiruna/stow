#![cfg(all(unix, not(target_os = "macos")))]

use chrono::{DateTime, Utc};
use rusqlite::{Connection, params};
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

fn assert_rowid_mapping(db: &Connection, expected: &[(i64, Uuid)]) {
    for table in ["items", "item_search"] {
        let mut statement = db
            .prepare(&format!("SELECT rowid,id FROM {table} ORDER BY rowid"))
            .unwrap();
        let actual = statement
            .query_map([], |row| {
                Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?))
            })
            .unwrap()
            .map(|row| {
                let (rowid, id) = row.unwrap();
                (rowid, Uuid::parse_str(&id).unwrap())
            })
            .collect::<Vec<_>>();
        assert_eq!(actual, expected, "{table}");
    }
    let metadata_count: i64 = db
        .query_row("SELECT count(*) FROM item_search_metadata", [], |row| {
            row.get(0)
        })
        .unwrap();
    assert_eq!(metadata_count, expected.len() as i64);
}

#[test]
fn noncontiguous_rowids_and_uuid_ties_survive_legacy_reopen_and_rebuild() {
    let (directory, mut repository) = fixture();
    let root = directory.path().join("library");
    let db = Connection::open(root.join("library.sqlite3")).unwrap();
    let high = item(30, "shared token", 100);
    let low = item(10, "shared token", 100);
    // Canonical insertion order is the reverse of UUID order, with a rowid gap.
    for (rowid, item) in [(7, &high), (42, &low)] {
        db.execute(
            "INSERT INTO items(rowid,id,snapshot) VALUES (?1,?2,?3)",
            params![
                rowid,
                item.id.to_string(),
                serde_json::to_string(item).unwrap()
            ],
        )
        .unwrap();
    }
    repository.rebuild_index().unwrap();
    let mapping = [(7, high.id), (42, low.id)];
    assert_rowid_mapping(&db, &mapping);
    let expected = vec![low.id, high.id];
    for search in [SearchQuery::default(), query("shared")] {
        assert_eq!(ids(repository.search_items(&search).unwrap()), expected);
    }
    repository.rebuild_index().unwrap();
    assert_rowid_mapping(&db, &mapping);
    for search in [SearchQuery::default(), query("shared")] {
        assert_eq!(ids(repository.search_items(&search).unwrap()), expected);
    }
    drop(repository);
    // Simulate the old index: automatic FTS rowids follow UUID-sorted rebuild
    // order, not canonical rowids. Open must discard this derived state.
    db.execute_batch("DELETE FROM item_search").unwrap();
    for item in [&low, &high] {
        db.execute(
            "INSERT INTO item_search(id,content) VALUES (?1,'legacytoken')",
            [item.id.to_string()],
        )
        .unwrap();
    }
    let legacy_rowids = db
        .query_row(
            "SELECT count(*) FROM item_search WHERE rowid IN (1,2)",
            [],
            |row| row.get::<_, i64>(0),
        )
        .unwrap();
    assert_eq!(legacy_rowids, 2);
    let repository = LocalRepository::open(&root).unwrap();
    assert_eq!(repository.get(high.id).unwrap(), Some(high.clone()));
    assert_eq!(repository.get(low.id).unwrap(), Some(low.clone()));
    assert_eq!(
        db.pragma_query_value(None, "user_version", |row| row.get::<_, i64>(0))
            .unwrap(),
        3
    );
    assert_rowid_mapping(&db, &mapping);
    assert!(
        repository
            .search_items(&query("legacytoken"))
            .unwrap()
            .is_empty()
    );
    for search in [SearchQuery::default(), query("shared")] {
        assert_eq!(ids(repository.search_items(&search).unwrap()), expected);
    }
}

#[test]
fn repeated_updates_delete_missing_delete_and_rowid_reuse_leave_no_stale_tokens() {
    let (directory, mut repository) = fixture();
    let db = Connection::open(directory.path().join("library/library.sqlite3")).unwrap();
    let mut updated = item(30, "originaltoken", 100);
    repository.upsert(&updated).unwrap();
    for title in ["secondtoken", "thirdtoken", "finaltoken"] {
        let previous = updated.title.clone();
        updated.title = title.into();
        repository.upsert(&updated).unwrap();
        assert!(
            repository
                .search_items(&query(&previous))
                .unwrap()
                .is_empty()
        );
        assert_eq!(
            repository.search_items(&query(title)).unwrap(),
            vec![updated.clone()]
        );
        assert_rowid_mapping(&db, &[(1, updated.id)]);
    }
    assert!(!repository.delete(Uuid::from_u128(999)).unwrap().deleted);
    assert_rowid_mapping(&db, &[(1, updated.id)]);
    assert!(repository.delete(updated.id).unwrap().deleted);
    assert!(!repository.delete(updated.id).unwrap().deleted);
    assert_rowid_mapping(&db, &[]);
    let replacement = item(10, "replacementtoken", 100);
    repository.upsert(&replacement).unwrap();
    assert_rowid_mapping(&db, &[(1, replacement.id)]);
    for old in ["originaltoken", "secondtoken", "thirdtoken", "finaltoken"] {
        assert!(repository.search_items(&query(old)).unwrap().is_empty());
    }
    assert_eq!(
        repository.search_items(&query("replacementtoken")).unwrap(),
        vec![replacement]
    );
}

#[test]
fn metadata_failure_rolls_back_canonical_row_and_replaced_fts_tokens() {
    let (directory, mut repository) = fixture();
    let db = Connection::open(directory.path().join("library/library.sqlite3")).unwrap();
    let original = item(30, "originaltoken", 100);
    repository.upsert(&original).unwrap();
    db.execute_batch(
        "CREATE TRIGGER reject_metadata BEFORE INSERT ON item_search_metadata
         BEGIN SELECT RAISE(ABORT, 'injected failure'); END;",
    )
    .unwrap();
    let mut changed = original.clone();
    changed.title = "replacementtoken".into();
    assert!(matches!(repository.upsert(&changed), Err(Error::Sqlite(_))));
    assert_eq!(repository.get(original.id).unwrap(), Some(original.clone()));
    assert_rowid_mapping(&db, &[(1, original.id)]);
    assert_eq!(
        repository.search_items(&query("originaltoken")).unwrap(),
        vec![original]
    );
    assert!(
        repository
            .search_items(&query("replacementtoken"))
            .unwrap()
            .is_empty()
    );
}

#[test]
fn purge_removes_fts_before_canonical_row_and_preserves_live_entries() {
    let (directory, mut repository) = fixture();
    let db = Connection::open(directory.path().join("library/library.sqlite3")).unwrap();
    let mut expired = item(30, "expiredtoken", 100);
    expired.trash(DateTime::from_timestamp(200, 0).unwrap());
    let live = item(10, "livetoken", 100);
    repository.upsert(&expired).unwrap();
    repository.upsert(&live).unwrap();
    let purge_at = DateTime::from_timestamp(40 * 86_400, 0).unwrap();
    assert_eq!(repository.purge_expired_trash(purge_at, 30).unwrap(), 1);
    assert_rowid_mapping(&db, &[(2, live.id)]);
    let mut search = query("expiredtoken");
    search.include_trashed = true;
    assert!(repository.search_items(&search).unwrap().is_empty());
    assert_eq!(
        repository.search_items(&query("livetoken")).unwrap(),
        vec![live]
    );
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
fn inclusive_utc_day_does_not_round_into_the_next_midnight() {
    let (_directory, mut repository) = fixture();
    let end = DateTime::parse_from_rfc3339("2026-01-01T23:59:59.999999999Z")
        .unwrap()
        .with_timezone(&Utc);
    let next = DateTime::parse_from_rfc3339("2026-01-02T00:00:00Z")
        .unwrap()
        .with_timezone(&Utc);
    let mut last = item(1, "Last instant", 0);
    last.created_at = end;
    let mut midnight = item(2, "Next day", 0);
    midnight.created_at = next;
    repository.upsert(&last).unwrap();
    repository.upsert(&midnight).unwrap();
    let query = SearchQuery {
        added_before: Some(end),
        ..Default::default()
    };
    assert_eq!(repository.search_items(&query).unwrap(), vec![last.clone()]);
    assert_eq!(
        repository.search_items(&SearchQuery::default()).unwrap(),
        vec![midnight, last]
    );
}

#[test]
fn pinned_filter_runs_before_the_result_limit() {
    let (_directory, mut repository) = fixture();
    let mut pinned = item(1, "Older pinned item", 100);
    pinned.is_pinned = true;
    let unpinned = item(2, "New unpinned item", 200);
    repository.upsert(&pinned).unwrap();
    repository.upsert(&unpinned).unwrap();
    let query = SearchQuery {
        pinned_only: true,
        limit: 1,
        ..Default::default()
    };
    assert_eq!(repository.search_items(&query).unwrap(), vec![pinned]);
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
