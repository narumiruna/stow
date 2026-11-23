//! Native-selected backends. The web IPC cannot choose a library or backend.
use std::path::PathBuf;
use stow_core::{Repository, ServiceResult};

#[cfg(target_os = "macos")]
pub mod macos_bridge;

pub fn open_backend(root: PathBuf) -> ServiceResult<Box<dyn Repository>> {
    #[cfg(target_os = "macos")]
    {
        Ok(Box::new(macos_bridge::MacRepository::open(&root)?))
    }
    #[cfg(not(target_os = "macos"))]
    {
        stow_storage::open_desktop(root)
    }
}

#[cfg(all(test, target_os = "macos"))]
mod tests {
    use super::*;

    #[test]
    fn non_preview_and_relative_roots_fail_without_touching_sentinels() {
        let temporary = tempfile::tempdir().unwrap();
        let parent = temporary.path().canonicalize().unwrap();
        let sentinel = parent.join("existing-library");
        std::fs::create_dir(&sentinel).unwrap();
        std::fs::write(sentinel.join("sentinel"), b"retained").unwrap();
        assert!(open_backend(sentinel.clone()).is_err());
        assert_eq!(
            std::fs::read(sentinel.join("sentinel")).unwrap(),
            b"retained"
        );
        assert_eq!(std::fs::read_dir(&sentinel).unwrap().count(), 1);
        let missing = parent.join("not-the-preview");
        assert!(open_backend(missing.clone()).is_err());
        assert!(!missing.exists());
        assert!(open_backend(PathBuf::from("dev.narumi.stow.desktop-preview")).is_err());
    }
}
