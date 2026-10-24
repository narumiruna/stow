use chrono::{DateTime, Utc};
use rusqlite::{Transaction, params, params_from_iter, types::Value};
use stow_core::{Item, ItemStatus, ItemType};
use uuid::Uuid;

use crate::{Error, LocalRepository, Result};

/// Portable counterpart of the current Swift search options. An empty text query
/// lists matching items by creation date; Trash is excluded unless requested.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SearchQuery {
    pub text: String,
    pub item_type: Option<ItemType>,
    pub source_app: Option<String>,
    pub added_after: Option<DateTime<Utc>>,
    pub added_before: Option<DateTime<Utc>>,
    pub status: Option<ItemStatus>,
    pub include_trashed: bool,
    pub pinned_only: bool,
    pub limit: usize,
}

impl Default for SearchQuery {
    fn default() -> Self {
        Self {
            text: String::new(),
            item_type: None,
            source_app: None,
            added_after: None,
            added_before: None,
            status: None,
            include_trashed: false,
            pinned_only: false,
            limit: 200,
        }
    }
}

impl LocalRepository {
    /// Search all token prefixes, with bound metadata filters and a bounded result
    /// count. FTS operators supplied by the caller are ordinary tokens.
    pub fn search_items(&self, query: &SearchQuery) -> Result<Vec<Item>> {
        if query.text.len() > 4096 {
            return Err(Error::InvalidQuery);
        }
        let expression = match_expression(&query.text);
        let mut values = Vec::<Value>::new();
        let mut clauses = Vec::new();
        if let Some(expression) = &expression {
            clauses.push("item_search MATCH ?");
            values.push(Value::Text(expression.clone()));
        }
        if let Some(item_type) = query.item_type {
            clauses.push("m.type = ?");
            values.push(Value::Text(item_type.as_str().into()));
        }
        if let Some(source) = query
            .source_app
            .as_ref()
            .filter(|source| !source.is_empty())
        {
            clauses.push("m.source_app = ? COLLATE NOCASE");
            values.push(Value::Text(source.clone()));
        }
        if let Some(after) = query.added_after {
            clauses.push("(m.created_at_seconds,m.created_at_nanos) >= (?,?)");
            values.push(Value::Integer(after.timestamp()));
            values.push(Value::Integer(i64::from(after.timestamp_subsec_nanos())));
        }
        if let Some(before) = query.added_before {
            clauses.push("(m.created_at_seconds,m.created_at_nanos) <= (?,?)");
            values.push(Value::Integer(before.timestamp()));
            values.push(Value::Integer(i64::from(before.timestamp_subsec_nanos())));
        }
        if let Some(status) = query.status {
            clauses.push("m.status = ?");
            values.push(Value::Text(status.as_str().into()));
        } else if !query.include_trashed {
            clauses.push("m.status != ?");
            values.push(Value::Text(ItemStatus::Trashed.as_str().into()));
        }
        if query.pinned_only {
            clauses.push("m.is_pinned = 1");
        }
        let mut sql = String::from(
            "SELECT items.id,items.snapshot FROM item_search_metadata m
             JOIN items ON items.id=m.id",
        );
        if expression.is_some() {
            sql.push_str(" JOIN item_search ON item_search.id=m.id");
        }
        if !clauses.is_empty() {
            sql.push_str(" WHERE ");
            sql.push_str(&clauses.join(" AND "));
        }
        sql.push_str(if expression.is_some() {
            " ORDER BY bm25(item_search),m.created_at_seconds DESC,m.created_at_nanos DESC,m.id ASC LIMIT ?"
        } else {
            " ORDER BY m.created_at_seconds DESC,m.created_at_nanos DESC,m.id ASC LIMIT ?"
        });
        values.push(Value::Integer(query.limit.clamp(1, 10_000) as i64));
        let mut statement = self.connection.prepare(&sql)?;
        let rows = statement.query_map(params_from_iter(values), |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?))
        })?;
        rows.map(|row| {
            let (id, snapshot) = row?;
            let id = Uuid::parse_str(&id).map_err(|_| Error::InvalidData)?;
            crate::repository::decode_item(id, &snapshot)
        })
        .collect()
    }
}

pub(crate) fn reset_index(transaction: &Transaction<'_>) -> Result<()> {
    transaction.execute_batch(
        "DROP TABLE IF EXISTS item_search;
         DROP TABLE IF EXISTS item_search_metadata;
         CREATE VIRTUAL TABLE item_search USING fts5(
             id UNINDEXED, content, tokenize='unicode61 remove_diacritics 2');
         CREATE TABLE item_search_metadata (
             id TEXT PRIMARY KEY NOT NULL,
             type TEXT NOT NULL,
             source_app TEXT,
             created_at_seconds INTEGER NOT NULL,
             created_at_nanos INTEGER NOT NULL,
             status TEXT NOT NULL,
             is_pinned INTEGER NOT NULL,
             last_used_at REAL
         );",
    )?;
    Ok(())
}

pub(crate) fn index_item(transaction: &Transaction<'_>, item: &Item) -> Result<()> {
    // Match SearchDocument(item:): source app is a filter, not searchable content.
    let content = [
        Some(item.title.as_str()),
        item.url_string.as_deref(),
        item.source_domain.as_deref(),
        item.text_content.as_deref(),
        item.note.as_deref(),
        item.file_name.as_deref(),
    ]
    .into_iter()
    .flatten()
    .collect::<Vec<_>>()
    .join("\n");
    let id = item.id.to_string();
    remove_item(transaction, item.id)?;
    transaction.execute(
        "INSERT INTO item_search(id,content) VALUES (?1,?2)",
        params![id, width_fold(&content)],
    )?;
    transaction.execute(
        "INSERT INTO item_search_metadata
         (id,type,source_app,created_at_seconds,created_at_nanos,status,is_pinned,last_used_at)
         VALUES (?1,?2,?3,?4,?5,?6,?7,?8)",
        params![
            id,
            item.item_type.as_str(),
            item.source_app,
            item.created_at.timestamp(),
            i64::from(item.created_at.timestamp_subsec_nanos()),
            item.status.as_str(),
            item.is_pinned,
            item.last_used_at.map(epoch_seconds),
        ],
    )?;
    Ok(())
}

pub(crate) fn remove_item(transaction: &Transaction<'_>, id: Uuid) -> Result<()> {
    let id = id.to_string();
    transaction.execute("DELETE FROM item_search WHERE id=?1", [&id])?;
    transaction.execute("DELETE FROM item_search_metadata WHERE id=?1", [&id])?;
    Ok(())
}

fn epoch_seconds(date: DateTime<Utc>) -> f64 {
    date.timestamp() as f64 + f64::from(date.timestamp_subsec_nanos()) / 1_000_000_000.0
}

fn match_expression(text: &str) -> Option<String> {
    let folded = width_fold(text).to_lowercase();
    let tokens = folded
        .split(|character: char| {
            !character.is_alphanumeric()
                && !unicode_normalization::char::is_combining_mark(character)
        })
        .filter(|token| !token.is_empty())
        .map(|token| format!("\"{token}\"*"))
        .collect::<Vec<_>>();
    (!tokens.is_empty()).then(|| tokens.join(" AND "))
}

/// Width folding, not general compatibility normalization. Preserve circled
/// digits and ligatures. Native ICU equivalence remains a shared-fixture gate.
pub(crate) fn width_fold(text: &str) -> String {
    crate::width::fold(text)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn width_folding_does_not_apply_unrelated_compatibility_changes() {
        assert_eq!(width_fold("Ｐａｎｅｌ　Ｔｅｘｔ"), "Panel Text");
        assert_eq!(width_fold("ガイド"), "ｶﾞｲﾄﾞ");
        assert_eq!(width_fold("ｶﾞｲﾄﾞ"), "ｶﾞｲﾄﾞ");
        assert_eq!(width_fold("① ﬃ Café"), "① ﬃ Café");
    }

    #[test]
    fn fts_expression_has_only_alphanumeric_literal_prefixes() {
        assert_eq!(
            match_expression("Ｓｗｉｆｔ　concur"),
            Some("\"swift\"* AND \"concur\"*".into())
        );
        assert_eq!(match_expression("\" OR *"), Some("\"or\"*".into()));
        assert_eq!(match_expression(" () * ' "), None);
    }
}
