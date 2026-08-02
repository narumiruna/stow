# ADR 0003: SQLite FTS5 for Local Search

- Status: Accepted
- Date: 2026-08-02

## Decision

Use a disposable SQLite FTS5 index owned by `SQLiteSearchIndex`. SwiftData/CloudKit records remain authoritative. The host app rebuilds the index when item versions change and searches it off the main actor with type, source-app, date, and status metadata filters.

Core Spotlight was rejected as the in-app query engine. It remains suitable for optional system-wide discovery later, but its asynchronous system indexing, query language, app-domain behavior, and less deterministic repair timing make it a weaker authority for Stow's immediate filtered result list.

## Benchmark

Command:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run --package-path Spikes/LocalSearch -c release LocalSearchBenchmark
```

Reference machine, 10,000 mixed documents, 100 representative queries:

| Engine | Rebuild | Median query | p95 query |
| --- | ---: | ---: | ---: |
| SQLite FTS5 | 44.193 ms | 6.509 ms | 17.813 ms |
| Core Spotlight | 101.080 ms | 51.824 ms | 54.968 ms |

Both met the ADR 0001 targets. FTS5 was faster and provides deterministic transaction, filtering, ranking, removal, and full rebuild behavior. `SearchServiceTests` verify token matching, filters, Trash exclusion, sorting, upsert, removal, and repair semantics.

## Recovery

The index contains no unique source data. Delete its SQLite files and rebuild from `SearchDocument` values whenever consistency checks or schema versions differ.
