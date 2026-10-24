#[cfg(any(target_os = "macos", not(unix)))]
#[test]
fn canonical_open_is_blocked_without_creating_files() {
    let temp = tempfile::TempDir::new().unwrap();
    let root = temp.path().join("must-not-exist");
    assert!(matches!(
        stow_storage::LocalRepository::open(&root),
        Err(stow_storage::Error::UnsupportedPlatform)
    ));
    assert!(!root.exists());
}
