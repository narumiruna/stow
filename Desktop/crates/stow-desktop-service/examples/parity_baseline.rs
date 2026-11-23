//! Isolated Linux repository measurements, not desktop startup or Swift parity proof.
use std::time::{Duration, Instant};

use chrono::{TimeZone, Utc};
use stow_core::{Item, ItemType};
use stow_storage::{LocalRepository, SearchQuery};
use uuid::Uuid;

fn percentile(samples: &mut [Duration], percent: usize) -> Duration {
    samples.sort_unstable();
    samples[(samples.len() * percent).div_ceil(100).saturating_sub(1)]
}

fn resident_kib() -> Option<u64> {
    let status = std::fs::read_to_string("/proc/self/status").ok()?;
    status.lines().find_map(|line| {
        line.strip_prefix("VmRSS:")?
            .split_whitespace()
            .next()?
            .parse()
            .ok()
    })
}

fn query_times(
    repository: &LocalRepository,
    text: &str,
    expected: usize,
) -> stow_storage::Result<(u128, u128)> {
    let query = SearchQuery {
        text: text.into(),
        limit: 200,
        ..Default::default()
    };
    let mut samples = Vec::with_capacity(20);
    for _ in 0..20 {
        let started = Instant::now();
        let rows = repository.search_items(&query)?;
        assert_eq!(rows.len(), expected);
        samples.push(started.elapsed());
    }
    Ok((
        percentile(&mut samples, 50).as_micros(),
        percentile(&mut samples, 95).as_micros(),
    ))
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    if !cfg!(target_os = "linux") {
        return Err("This baseline requires the supported Linux repository; it does not bypass platform guards.".into());
    }
    println!(
        "items,seed_ms,reopen_reindex_ms,list_p50_us,list_p95_us,search_p50_us,search_p95_us,resident_kib"
    );
    for size in [10_000_u128, 100_000] {
        let temp = tempfile::Builder::new()
            .prefix("stow-parity-baseline-")
            .tempdir()?;
        let root = temp.path().join("library");
        let mut repository = LocalRepository::open(&root)?;
        let now = Utc.with_ymd_and_hms(2026, 1, 1, 0, 0, 0).single().unwrap();
        let started = Instant::now();
        for index in 1..=size {
            let mut item = Item::new(ItemType::Text, format!("Fixture {index}"), now);
            item.id = Uuid::from_u128(index);
            item.capture_id = item.id;
            item.text_content = Some(if index % 1000 == 0 {
                "needle fixture ".repeat(16)
            } else {
                "ordinary fixture ".repeat(16)
            });
            item.source_app = Some("Parity fixture".into());
            item.is_pinned = index % 11 == 0;
            repository.upsert(&item)?;
        }
        let seed_ms = started.elapsed().as_millis();
        drop(repository);
        let started = Instant::now();
        let repository = LocalRepository::open(&root)?;
        let reopen_ms = started.elapsed().as_millis();
        let (list_p50, list_p95) = query_times(&repository, "", 200)?;
        let (search_p50, search_p95) = query_times(&repository, "needle", (size / 1000) as usize)?;
        let rss = resident_kib().map_or_else(|| "unavailable".into(), |value| value.to_string());
        println!(
            "{size},{seed_ms},{reopen_ms},{list_p50},{list_p95},{search_p50},{search_p95},{rss}"
        );
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn percentiles_use_nearest_rank_and_sort_samples() {
        let mut samples: Vec<_> = (1..=20).rev().map(Duration::from_micros).collect();
        assert_eq!(percentile(&mut samples, 50), Duration::from_micros(10));
        assert_eq!(percentile(&mut samples, 95), Duration::from_micros(19));
    }
}
