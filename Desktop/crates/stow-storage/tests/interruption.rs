#![cfg(target_os = "linux")]

use std::fs;
use std::io::{self, Read};
use std::process::{Command, exit};

use chrono::Utc;
use stow_core::{Item, ItemType};
use stow_storage::LocalRepository;
use tempfile::TempDir;

struct ExitAfterPartialRead(bool);

impl Read for ExitAfterPartialRead {
    fn read(&mut self, buffer: &mut [u8]) -> io::Result<usize> {
        if self.0 {
            // No destructors, rollback handlers, or normal repository shutdown.
            exit(23);
        }
        self.0 = true;
        buffer[..7].copy_from_slice(b"partial");
        Ok(7)
    }
}

#[test]
fn abrupt_process_exit_during_staging_preserves_committed_data() {
    if let Some(root) = std::env::var_os("STOW_TEST_INTERRUPTED_LIBRARY") {
        let mut repository = LocalRepository::open(root).unwrap();
        let item = repository.list().unwrap().remove(0);
        let _ = repository.attach_reader(item.id, ExitAfterPartialRead(false), 128, [0; 32]);
        panic!("child did not exit during staging");
    }

    let directory = TempDir::new().unwrap();
    let root = directory.path().join("library");
    let mut repository = LocalRepository::open(&root).unwrap();
    let item = Item::new(ItemType::Text, "committed", Utc::now());
    repository.upsert(&item).unwrap();
    let attachment = repository.attach(item.id, b"keep these bytes").unwrap();
    drop(repository);

    let status = Command::new(std::env::current_exe().unwrap())
        .args([
            "--exact",
            "abrupt_process_exit_during_staging_preserves_committed_data",
        ])
        .env("STOW_TEST_INTERRUPTED_LIBRARY", &root)
        .status()
        .unwrap();
    assert_eq!(status.code(), Some(23));
    assert_eq!(fs::read_dir(root.join("staging")).unwrap().count(), 1);

    let repository = LocalRepository::open(&root).unwrap();
    assert_eq!(repository.list().unwrap(), vec![item.clone()]);
    assert_eq!(
        repository.attachments(item.id).unwrap(),
        vec![attachment.clone()]
    );
    assert_eq!(
        repository.read_attachment(attachment.id).unwrap(),
        b"keep these bytes"
    );
    assert_eq!(fs::read_dir(root.join("staging")).unwrap().count(), 0);
    assert_eq!(fs::read_dir(root.join("blobs")).unwrap().count(), 1);
}
