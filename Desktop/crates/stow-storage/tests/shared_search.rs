#![cfg(target_os = "linux")]

use chrono::{DateTime, Utc};
use serde::Deserialize;
use stow_core::{Item, ItemStatus, ItemType};
use stow_storage::{LocalRepository, SearchQuery};
use tempfile::TempDir;
use uuid::Uuid;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Fixture {
    datasets: Vec<Dataset>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Dataset {
    name: String,
    items: Vec<FixtureItem>,
    queries: Vec<FixtureQuery>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct FixtureItem {
    id: Uuid,
    title: String,
    text_content: Option<String>,
    #[serde(rename = "type")]
    item_type: ItemType,
    source_app: Option<String>,
    created_at: i64,
    status: ItemStatus,
    pinned: Option<bool>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct FixtureQuery {
    name: String,
    text: String,
    filters: Filters,
    expected_ids: Vec<Uuid>,
    #[serde(default)]
    sort_ids: bool,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Filters {
    #[serde(rename = "type")]
    item_type: Option<ItemType>,
    source_app: Option<String>,
    added_after: Option<i64>,
    added_before: Option<i64>,
    status: Option<ItemStatus>,
    #[serde(default)]
    include_trashed: bool,
}

fn date(seconds: i64) -> DateTime<Utc> {
    DateTime::from_timestamp(seconds, 0).expect("fixture timestamp")
}

#[test]
fn shared_search_fixtures_match_local_repository() {
    let fixture: Fixture =
        serde_json::from_str(include_str!("../../../fixtures/search.json")).unwrap();
    assert!(!fixture.datasets.is_empty());

    for dataset in fixture.datasets {
        let directory = TempDir::new().unwrap();
        let mut repository = LocalRepository::open(directory.path().join("library")).unwrap();
        for row in &dataset.items {
            let mut item = Item::new(row.item_type, &row.title, date(row.created_at));
            item.id = row.id;
            item.capture_id = row.id;
            item.text_content = row.text_content.clone();
            item.source_app = row.source_app.clone();
            item.status = row.status;
            item.is_pinned = row.pinned.unwrap_or(false);
            repository.upsert(&item).unwrap();
        }
        assert_eq!(repository.list().unwrap().len(), dataset.items.len());
        assert!(!dataset.queries.is_empty(), "{}", dataset.name);

        for query in dataset.queries {
            let filters = query.filters;
            let search = SearchQuery {
                text: query.text,
                item_type: filters.item_type,
                source_app: filters.source_app,
                added_after: filters.added_after.map(date),
                added_before: filters.added_before.map(date),
                status: filters.status,
                include_trashed: filters.include_trashed,
                ..Default::default()
            };
            let mut actual: Vec<_> = repository
                .search_items(&search)
                .unwrap()
                .into_iter()
                .map(|item| item.id)
                .collect();
            let mut expected = query.expected_ids;
            if query.sort_ids {
                actual.sort();
                expected.sort();
            }
            assert_eq!(actual, expected, "{}: {}", dataset.name, query.name);
        }
    }
}
