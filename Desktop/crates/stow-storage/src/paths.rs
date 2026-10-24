use std::fs::{self, File, OpenOptions};
use std::path::{Component, Path};

use crate::{Error, Result};

/// Validate every existing component without resolving symlinks.
pub(crate) fn check_components(path: &Path) -> Result<()> {
    if !path.is_absolute() {
        return Err(Error::UnsafePath);
    }
    let mut current = std::path::PathBuf::new();
    for component in path.components() {
        match component {
            Component::ParentDir | Component::CurDir => return Err(Error::UnsafePath),
            _ => current.push(component),
        }
        let metadata = fs::symlink_metadata(&current)?;
        if metadata.file_type().is_symlink() || !metadata.is_dir() {
            return Err(Error::UnsafePath);
        }
    }
    Ok(())
}

pub(crate) fn private_dir(path: &Path) -> Result<()> {
    let parent = path.parent().ok_or(Error::UnsafePath)?;
    check_components(parent)?;
    if !path.exists() {
        let builder = fs::DirBuilder::new();
        #[cfg(unix)]
        let builder = {
            use std::os::unix::fs::DirBuilderExt;
            let mut builder = builder;
            builder.mode(0o700);
            builder
        };
        builder.create(path)?;
        sync_dir(parent)?;
    }
    check_components(path)?;
    check_private(&fs::symlink_metadata(path)?, true)
}

pub(crate) fn check_private(metadata: &fs::Metadata, directory: bool) -> Result<()> {
    if metadata.file_type().is_symlink()
        || (directory && !metadata.is_dir())
        || (!directory && !metadata.is_file())
    {
        return Err(Error::UnsafePath);
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        // SAFETY: geteuid has no preconditions and does not modify memory.
        if metadata.uid() != unsafe { libc::geteuid() }
            || metadata.mode() & 0o077 != 0
            || (!directory && metadata.nlink() != 1)
        {
            return Err(Error::UnsafePath);
        }
    }
    #[cfg(not(unix))]
    return Err(Error::UnsupportedPlatform);
    #[allow(unreachable_code)]
    Ok(())
}

/// Open regular files without following their final component. Parent directories
/// are private and checked separately. Never accepts caller-selected blob names.
pub(crate) fn open_file(path: &Path, create: bool, write: bool) -> Result<File> {
    if let Ok(metadata) = fs::symlink_metadata(path) {
        check_private(&metadata, false)?;
    }
    let mut options = OpenOptions::new();
    options.read(true).write(write).create(create);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options
            .mode(0o600)
            .custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK);
    }
    let file = options.open(path)?;
    check_private(&file.metadata()?, false)?;
    Ok(file)
}

pub(crate) fn new_file(path: &Path) -> Result<File> {
    let mut options = OpenOptions::new();
    options.read(true).write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600).custom_flags(libc::O_NOFOLLOW);
    }
    let file = options.open(path)?;
    check_private(&file.metadata()?, false)?;
    Ok(file)
}

pub(crate) fn sync_dir(path: &Path) -> Result<()> {
    check_components(path)?;
    File::open(path)?.sync_all()?;
    Ok(())
}
