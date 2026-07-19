//! P20j.2 — the materializer + manifest (design/p20j-files-projection.md
//! §3). Order is law: the LOG is appended and fsynced first (that path
//! shipped long ago and never waits on files); every file lands through
//! an atomic write; the MANIFEST is written last — and it is a CACHE:
//! corrupt or missing, it rebuilds from store + disk, never a data loss.
//! The planner is pure (`plan_projection`), the applier drives a
//! `VaultIo` trait, so the crash matrix (kill-shot A) is a test loop
//! that aborts between any two ops and demands reconvergence.
//!
//! v0 projects the MARKDOWN class only; binary byte-copies arrive with
//! the import-writes-files slice (20j.8, recorded). The digest is
//! SHA-256 — the P15 librarian's own hash (the design doc said blake3;
//! corrected here, recorded in the slice log).

use crate::vault::{expected_files, VaultClass};
use lotus_core::*;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use std::io;

pub const MANIFEST_PATH: &str = ".liv/index.json";

/// Every IO the materializer may perform. The real vault implements this
/// over tmp+fsync+rename; tests implement it over a map with a fuse.
pub trait VaultIo {
    fn write_atomic(&mut self, rel: &str, bytes: &[u8]) -> io::Result<()>;
    fn rename(&mut self, from: &str, to: &str) -> io::Result<()>;
    fn read(&self, rel: &str) -> io::Result<Vec<u8>>;
    fn exists(&self, rel: &str) -> bool;
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ManifestRow {
    pub path: String,
    pub id: Id,
    pub digest: String,
    #[serde(default)]
    pub trash_from: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Manifest {
    pub generation: u64,
    pub rows: Vec<ManifestRow>,
}

/// Load the manifest — a CACHE: absent or corrupt yields empty, and the
/// planner treats disk truth by content, so healing is automatic.
pub fn load_manifest(io: &dyn VaultIo) -> Manifest {
    match io.read(MANIFEST_PATH) {
        Ok(bytes) => serde_json::from_slice(&bytes).unwrap_or_default(),
        Err(_) => Manifest::default(),
    }
}

pub fn digest(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    format!("{:x}", hasher.finalize())
}

/// One planned filesystem step, in apply order.
#[derive(Debug, Clone, PartialEq)]
pub enum FsOp {
    Write { rel: String, bytes: Vec<u8> },
    Rename { from: String, to: String },
    /// Into `.trash/<original-rel-path>` — undo restores exactly.
    Trash { from: String, to: String },
    Untrash { from: String, to: String },
}

fn trash_path(rel: &str) -> String {
    format!(".trash/{rel}")
}

/// The pure planner: diff expected(store) against the manifest, emit the
/// ops AND the manifest that will be true after they apply. Deterministic;
/// no IO. Applying from ANY intermediate disk state converges because the
/// applier verifies each op against the disk before acting (a rename
/// whose source is already gone but whose target exists is complete).
pub fn plan_projection(store: &Store, manifest: &Manifest) -> (Vec<FsOp>, Manifest) {
    let expected = expected_files(store);
    let by_id: HashMap<Id, &ManifestRow> =
        manifest.rows.iter().map(|r| (r.id, r)).collect();

    let mut ops: Vec<FsOp> = Vec::new();
    let mut next_rows: Vec<ManifestRow> = Vec::new();
    let mut live: HashMap<Id, ()> = HashMap::new();

    for file in &expected {
        if file.class != VaultClass::Markdown {
            continue; // binaries: 20j.8 (recorded)
        }
        let Some(content) = &file.content else { continue };
        live.insert(file.id, ());
        let want_digest = digest(content.as_bytes());
        match by_id.get(&file.id) {
            None => {
                ops.push(FsOp::Write { rel: file.rel_path.clone(), bytes: content.clone().into_bytes() });
            }
            Some(row) => {
                // Back from the trash? Restore the exact original path
                // first, then let rename/write reconcile the rest.
                if let Some(parked) = &row.trash_from {
                    ops.push(FsOp::Untrash {
                        from: parked.clone(),
                        to: row.path.clone(),
                    });
                }
                if row.path != file.rel_path {
                    ops.push(FsOp::Rename {
                        from: row.path.clone(),
                        to: file.rel_path.clone(),
                    });
                }
                if row.digest != want_digest {
                    ops.push(FsOp::Write {
                        rel: file.rel_path.clone(),
                        bytes: content.clone().into_bytes(),
                    });
                }
            }
        }
        next_rows.push(ManifestRow {
            path: file.rel_path.clone(),
            id: file.id,
            digest: want_digest,
            trash_from: None,
        });
    }

    // Manifest rows whose entity no longer projects (trashed, merged away,
    // de-pooled): the FILE is never deleted — it parks in .trash/ under its
    // original path, and the row remembers where.
    for row in &manifest.rows {
        if live.contains_key(&row.id) {
            continue;
        }
        if row.trash_from.is_some() {
            // Already parked — carry the row forward untouched.
            next_rows.push(row.clone());
            continue;
        }
        let parked = trash_path(&row.path);
        ops.push(FsOp::Trash { from: row.path.clone(), to: parked.clone() });
        next_rows.push(ManifestRow {
            path: row.path.clone(),
            id: row.id,
            digest: row.digest.clone(),
            trash_from: Some(parked),
        });
    }

    let next = Manifest { generation: manifest.generation + 1, rows: next_rows };
    (ops, next)
}

/// Apply the plan — every op verified against the CURRENT disk first, so
/// re-applying after a crash never fails on already-done work; the
/// manifest lands LAST. On any error the manifest is NOT written: the next
/// plan starts from the old manifest and the applier's idempotence heals.
pub fn apply_projection(
    io: &mut dyn VaultIo,
    ops: &[FsOp],
    next: &Manifest,
) -> io::Result<()> {
    for op in ops {
        match op {
            FsOp::Write { rel, bytes } => {
                // Skip only if the exact content is already there (a
                // completed step from a previous, crashed apply).
                if let Ok(existing) = io.read(rel) {
                    if existing == *bytes {
                        continue;
                    }
                }
                io.write_atomic(rel, bytes)?;
            }
            FsOp::Rename { from, to } | FsOp::Trash { from, to }
            | FsOp::Untrash { from, to } => {
                if !io.exists(from) && io.exists(to) {
                    continue; // already moved by a previous apply
                }
                if io.exists(from) {
                    io.rename(from, to)?;
                }
            }
        }
    }
    let bytes = serde_json::to_vec(next).map_err(io::Error::other)?;
    io.write_atomic(MANIFEST_PATH, &bytes)
}
