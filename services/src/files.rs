//! Files — the librarian (P7). A file entity references bytes by path + a
//! 32-byte content hash; the entity owns the meaning, the file owns the
//! bytes. Reading is a strictly read-only ladder; we never move, copy, or
//! rename the user's file. Extraction/thumbnails (7b/7d) are a cache keyed
//! by hash, off the log, rebuildable and disposable — never a cell.

use std::io::Read;
use std::path::{Path, PathBuf};

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

/// The outcome of re-hashing a file entity's referenced path.
#[derive(Debug, PartialEq, Eq)]
pub enum Resync {
    /// The bytes are unchanged — the stored hash still holds.
    Unchanged,
    /// The bytes changed; the File cell was replaced with the new hash.
    Changed([u8; 32]),
    /// The path no longer resolves (moved/deleted), or the entity carries
    /// no file cell — a broken reference, distinct from a change.
    Broken,
}

/// Re-hash a file entity's referenced path. A changed hash IS the
/// integration: replace the File cell in one transaction (replace-the-cell,
/// one undo step) so the new hash — and thus a fresh extraction — takes
/// over. Unchanged is a no-op; a vanished path is Broken (never a phantom
/// re-extract). Called lazily when a file is opened, never on a timer.
pub fn resync_file(session: &mut Session, id: Id) -> Result<Resync, PersistError> {
    let Some(file_prop) = property_id(session.store(), "file") else {
        return Ok(Resync::Broken);
    };
    let id = session.store().resolve(id);
    let current = match session.store().get(id).and_then(|e| e.get(file_prop)) {
        Some(Value::File(f)) => f.clone(),
        _ => return Ok(Resync::Broken),
    };
    let fresh = match hash_file(&current.path) {
        Ok(hash) => hash,
        Err(_) => return Ok(Resync::Broken),
    };
    if fresh == current.hash {
        return Ok(Resync::Unchanged);
    }
    let replaced = FileRef { path: current.path.clone(), hash: fresh };
    session.commit(
        vec![
            Command::RemoveCell {
                entity: id,
                cell: Cell { property: file_prop, value: Value::File(current) },
            },
            Command::AddCell {
                entity: id,
                cell: Cell { property: file_prop, value: Value::File(replaced) },
            },
        ],
        "resync file".to_string(),
        Author::User,
    )?;
    Ok(Resync::Changed(fresh))
}

/// The extraction cache root for a box: `<box_dir>/cache`. A sibling of the
/// log, holding one subdirectory per content hash — rebuildable, disposable,
/// never part of the log.
pub fn cache_dir(box_path: &str) -> PathBuf {
    Path::new(box_path)
        .parent()
        .unwrap_or_else(|| Path::new("."))
        .join("cache")
}

/// The extracted plain text of a file, cached by content hash under
/// `cache/<hex>/text`. On a hit, the cached text; on a miss, read the bytes,
/// extract per format, and write the cache. A read failure (file gone) is
/// empty and is NOT cached — the file is a broken reference, searchable by
/// name only, never a crash. The ONLY place bytes are read for extraction,
/// and it writes ONLY under `cache/`.
pub fn extracted_text(cache_dir: &Path, file: &FileRef, format: &str) -> String {
    let entry = cache_dir.join(hex(&file.hash));
    let text_path = entry.join("text");
    if let Ok(cached) = std::fs::read_to_string(&text_path) {
        return cached;
    }
    let Ok(bytes) = std::fs::read(&file.path) else {
        return String::new();
    };
    let text = extract(&bytes, format);
    // Best-effort cache write; a failed write just means the next open
    // re-extracts. Never fatal.
    let _ = std::fs::create_dir_all(&entry);
    let _ = std::fs::write(&text_path, &text);
    text
}

/// Format → extracted text. 7b ships plain text only; PDF/Word are stubs
/// (empty) filled in 7d — a file of an unextractable format is searchable
/// by its name until then.
fn extract(bytes: &[u8], format: &str) -> String {
    match format {
        "txt" | "text" | "md" | "markdown" | "csv" | "log" | "json" => {
            String::from_utf8_lossy(bytes).into_owned()
        }
        // "pdf" | "docx" → deferred (7d); empty until then.
        _ => String::new(),
    }
}

/// Lowercase hex of a 32-byte hash — the cache subdirectory name.
fn hex(hash: &[u8; 32]) -> String {
    let mut out = String::with_capacity(64);
    for byte in hash {
        out.push_str(&format!("{byte:02x}"));
    }
    out
}
