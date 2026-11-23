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
    assert_eq!(std::fs::read_dir(temp.path()).unwrap().count(), 0);
}

#[cfg(any(target_os = "macos", not(unix)))]
#[test]
fn canonical_open_is_blocked_without_changing_existing_files() {
    let temp = tempfile::TempDir::new().unwrap();
    let root = temp.path().join("existing-library");
    std::fs::create_dir(&root).unwrap();
    let sentinel = root.join("library.sqlite3");
    let original = b"existing canonical store must not change";
    std::fs::write(&sentinel, original).unwrap();
    let permissions = std::fs::metadata(&sentinel).unwrap().permissions();

    assert!(matches!(
        stow_storage::LocalRepository::open(&root),
        Err(stow_storage::Error::UnsupportedPlatform)
    ));
    assert_eq!(std::fs::read(&sentinel).unwrap(), original);
    assert_eq!(
        std::fs::metadata(&sentinel).unwrap().permissions(),
        permissions
    );
    assert_eq!(std::fs::read_dir(&root).unwrap().count(), 1);
    assert_eq!(std::fs::read_dir(temp.path()).unwrap().count(), 1);
}
