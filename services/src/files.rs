//! Files — the librarian (P7). A file entity references bytes by path + a
//! 32-byte content hash; the entity owns the meaning, the file owns the
//! bytes. Reading is a strictly read-only ladder; we never move, copy, or
//! rename the user's file. Extraction/thumbnails (7b/7d) are a cache keyed
//! by hash, off the log, rebuildable and disposable — never a cell.

use std::io::Read;

use sha2::{Digest, Sha256};

use lotus_core::{
    props, Author, Cell, Command, DateTime, FileRef, Id, PersistError, Session, Value,
};

use crate::property_id;

/// SHA-256 of a file's bytes → `[u8; 32]`, exactly `FileRef.hash`. The one
/// place a file hash is computed. Distinct from `content_fingerprint` (an
/// FNV over a serde value): this is over raw bytes, strong enough that a
/// one-byte edit reliably misses the extraction cache. Streams the file so
/// a large PDF isn't slurped whole.
pub fn hash_file(path: &str) -> std::io::Result<[u8; 32]> {
    let mut file = std::fs::File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 64 * 1024];
    loop {
        let read = file.read(&mut buf)?;
        if read == 0 {
            break;
        }
        hasher.update(&buf[..read]);
    }
    Ok(hasher.finalize().into())
}

/// Birth of a file entity by reference: `Create` + `name` (the filename) +
/// a `file` cell (path + freshly computed hash) + `format` (the lowercased
/// extension) + `created`, in one transaction. NEVER copies or moves the
/// file — only reads it to hash. An unreadable path is an error, not a
/// phantom entity. Returns the new id.
pub fn add_file(
    session: &mut Session,
    path: &str,
    created: DateTime,
) -> Result<Id, PersistError> {
    let hash = hash_file(path).map_err(PersistError::Io)?;
    let p = std::path::Path::new(path);
    let filename = p
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or(path)
        .to_string();
    let format = p
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_lowercase();

    // The file/format properties are seeded (seed_files) at every open, so
    // this only fails on a genuinely broken box.
    let file_prop = property_id(session.store(), "file")
        .ok_or_else(|| PersistError::Corrupt("no file property — box unseeded".into()))?;

    let id = session.allocate_id();
    let mut commands = vec![
        Command::Create { entity: id },
        Command::AddCell {
            entity: id,
            cell: Cell { property: props::NAME, value: Value::text(filename) },
        },
        Command::AddCell {
            entity: id,
            cell: Cell {
                property: file_prop,
                value: Value::File(FileRef { path: path.to_string(), hash }),
            },
        },
        Command::AddCell {
            entity: id,
            cell: Cell { property: props::CREATED, value: Value::DateTime(created) },
        },
    ];
    if !format.is_empty() {
        if let Some(format_prop) = property_id(session.store(), "format") {
            commands.push(Command::AddCell {
                entity: id,
                cell: Cell { property: format_prop, value: Value::text(format) },
            });
        }
    }

    session.commit(commands, "add file".to_string(), Author::User)?;
    Ok(id)
}
