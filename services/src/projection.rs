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
    /// Every path under the prefix — the scan's eyes (read-only).
    fn list(&self, prefix: &str) -> Vec<String>;
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


// ---- P20j.3: the reconcile decision table + ingest (design §4) ----

/// A sync-client-shaped burst: more than this many changed files in one
/// scan downgrades everything to ONE card — never auto-applied.
pub const MASS_CHANGE_THRESHOLD: usize = 25;

#[derive(Debug, Clone, PartialEq)]
pub enum ReconcileFinding {
    /// Rule 2 — a clean external edit (box unmoved since the sync point):
    /// the ingest candidate.
    Edited { id: Id, path: String },
    /// A markdown file the manifest has never seen — born outside.
    NewFile { path: String },
    /// Rule 3 — both sides moved. Surfaced, never merged.
    Conflict { id: Id, path: String },
    /// Rule 4 — the file left the disk. Surfaced; the entity NEVER dies.
    Missing { id: Id, path: String },
    /// A byte-identical copy of an expected file at a stray path (a lost
    /// manifest after a rename) — the projector parks it.
    OrphanCopy { path: String },
    /// Rule 4 — the sync-client fingerprint. One card, nothing applies.
    MassChange { count: usize },
}

/// The scan: read-only. Rule 1 is FIRST and content-addressed — a file
/// whose bytes equal render(store) is ours, whatever the timestamps say;
/// the projector's own writes are structurally incapable of re-ingesting.
pub fn scan(io: &dyn VaultIo, store: &Store, manifest: &Manifest) -> Vec<ReconcileFinding> {
    let findings = scan_inner(io, store, manifest);
    let changeful = findings
        .iter()
        .filter(|f| {
            matches!(
                f,
                ReconcileFinding::Edited { .. }
                    | ReconcileFinding::NewFile { .. }
                    | ReconcileFinding::Missing { .. }
            )
        })
        .count();
    if changeful > MASS_CHANGE_THRESHOLD {
        return vec![ReconcileFinding::MassChange { count: changeful }];
    }
    findings
}

/// The scan body without the burst collapse — `scan` wraps it, `scan_all`
/// exposes it.
fn scan_inner(io: &dyn VaultIo, store: &Store, manifest: &Manifest) -> Vec<ReconcileFinding> {
    let expected = expected_files(store);
    let expected_by_id: HashMap<Id, &crate::vault::VaultFile> =
        expected.iter().map(|f| (f.id, f)).collect();
    let expected_digests: HashMap<String, &str> = expected
        .iter()
        .filter_map(|f| f.content.as_deref().map(|c| (digest(c.as_bytes()), f.rel_path.as_str())))
        .collect();

    let mut findings: Vec<ReconcileFinding> = Vec::new();
    let mut known_paths: HashMap<&str, ()> = HashMap::new();

    for row in &manifest.rows {
        known_paths.insert(row.path.as_str(), ());
        if row.trash_from.is_some() {
            continue; // parked — the projector owns it
        }
        let on_disk = io.read(&row.path).ok();
        let expected_now = expected_by_id
            .get(&row.id)
            .and_then(|f| f.content.as_deref());
        match on_disk {
            None => {
                // Rule 4: the file left the disk. If the entity no longer
                // projects either, the projector will reconcile silently;
                // a LIVE entity's missing file is a card.
                if expected_now.is_some() {
                    findings.push(ReconcileFinding::Missing {
                        id: row.id,
                        path: row.path.clone(),
                    });
                }
            }
            Some(bytes) => {
                let file_digest = digest(&bytes);
                if file_digest == row.digest {
                    continue; // untouched since the sync point
                }
                // Rule 1: content-addressed clean — the file already IS
                // what the store renders (our own write racing a stale
                // manifest). The projector refreshes the row; no finding.
                if let Some(now) = expected_now {
                    if digest(now.as_bytes()) == file_digest {
                        continue;
                    }
                }
                // Box moved since the sync point?
                let box_moved = expected_now
                    .map(|now| digest(now.as_bytes()) != row.digest)
                    .unwrap_or(true);
                if box_moved {
                    findings.push(ReconcileFinding::Conflict {
                        id: row.id,
                        path: row.path.clone(),
                    });
                } else {
                    findings.push(ReconcileFinding::Edited {
                        id: row.id,
                        path: row.path.clone(),
                    });
                }
            }
        }
    }

    // Unknown markdown under library/: content-addressed orphan detection
    // first (a stray copy of our own bytes), else a hand-born file.
    for path in io.list("library/") {
        if known_paths.contains_key(path.as_str()) || !path.ends_with(".md") {
            continue;
        }
        match io.read(&path) {
            Ok(bytes) => {
                let d = digest(&bytes);
                if expected_digests.contains_key(d.as_str()) {
                    findings.push(ReconcileFinding::OrphanCopy { path });
                } else {
                    findings.push(ReconcileFinding::NewFile { path });
                }
            }
            Err(_) => {}
        }
    }

    findings
}

pub struct IngestOutcome {
    pub edited: usize,
    pub created: usize,
    /// Findings the ingest deliberately left for the shell's cards.
    pub surfaced: usize,
    /// Newly-born entities and the hand-made paths they were born FROM —
    /// the caller seeds manifest rows with these before the next plan, so
    /// the projector RENAMES the hand path to canonical instead of
    /// re-ingesting it as another new file (the duplicate factory).
    pub adopted: Vec<AdoptedFile>,
}

#[derive(Debug, Clone)]
pub struct AdoptedFile {
    pub id: Id,
    pub path: String,
    pub digest: String,
}

/// Fold adopted births into a manifest so the next plan owns their paths.
pub fn adopt_into(manifest: &mut Manifest, adopted: &[AdoptedFile]) {
    for a in adopted {
        manifest.rows.push(ManifestRow {
            path: a.path.clone(),
            id: a.id,
            digest: a.digest.clone(),
            trash_from: None,
        });
    }
}

fn pool_type(path: &str) -> Option<&'static str> {
    let pool = path.strip_prefix("library/")?.split('/').next()?;
    match pool {
        "notes" | "daily" => Some("note"),
        "contacts" => Some("person"),
        "events" => Some("event"),
        "tasks" => Some("task"),
        "links" => Some("link"),
        _ => None,
    }
}

/// Tier-A ingest: ONE batched transaction for every clean edit and new
/// file — announced by the caller, undone by one ⌘⌥Z, labeled
/// "vault-edit". Conflict/Missing/Mass findings are counted and LEFT for
/// the shell — never merged, never auto-applied. v0 ingests NAME + BODY
/// (the shell's own editor writes exactly those); frontmatter-cell edits
/// are a recorded deepening.
pub fn ingest(
    session: &mut Session,
    io: &dyn VaultIo,
    _manifest: &Manifest,
    findings: &[ReconcileFinding],
) -> Result<IngestOutcome, crate::content::WriteError> {
    let mut commands: Vec<Command> = Vec::new();
    let mut edited = 0;
    let mut created = 0;
    let mut surfaced = 0;
    let mut adopted: Vec<AdoptedFile> = Vec::new();

    for finding in findings {
        match finding {
            ReconcileFinding::Edited { id, path } => {
                let Ok(bytes) = io.read(path) else { continue };
                let Ok(raw) = String::from_utf8(bytes) else { continue };
                let parsed = crate::vault::parse_vault_note(&raw);
                let store = session.store();
                let Some(entity) = store.get(*id) else { continue };
                // Name follows the H1 (H1 wins — the recorded rule).
                if let Some(new_name) = &parsed.name {
                    if let Some(Value::Text(old)) = entity.get(props::NAME) {
                        if old != new_name {
                            commands.push(Command::RemoveCell {
                                entity: *id,
                                cell: Cell {
                                    property: props::NAME,
                                    value: Value::text(old.clone()),
                                },
                            });
                            commands.push(Command::AddCell {
                                entity: *id,
                                cell: Cell {
                                    property: props::NAME,
                                    value: Value::text(new_name.clone()),
                                },
                            });
                        }
                    }
                }
                let new_content = Value::RichText(parsed.body);
                if entity.get(props::CONTENT) != Some(&new_content) {
                    for old in entity.all(props::CONTENT) {
                        commands.push(Command::RemoveCell {
                            entity: *id,
                            cell: Cell { property: props::CONTENT, value: old.clone() },
                        });
                    }
                    commands.push(Command::AddCell {
                        entity: *id,
                        cell: Cell { property: props::CONTENT, value: new_content },
                    });
                }
                edited += 1;
            }
            ReconcileFinding::NewFile { path } => {
                let Ok(bytes) = io.read(path) else { continue };
                let Ok(raw) = String::from_utf8(bytes) else { continue };
                let parsed = crate::vault::parse_vault_note(&raw);
                let id = session.allocate_id();
                commands.push(Command::Create { entity: id });
                if let Some(kind) = pool_type(path) {
                    if let Some(ty) = crate::content::find_type(session.store(), kind) {
                        commands.push(Command::AddCell {
                            entity: id,
                            cell: Cell { property: props::TYPE, value: Value::Reference(ty) },
                        });
                    }
                }
                let name = parsed.name.unwrap_or_else(|| {
                    path.rsplit('/')
                        .next()
                        .unwrap_or("untitled")
                        .trim_end_matches(".md")
                        .to_string()
                });
                commands.push(Command::AddCell {
                    entity: id,
                    cell: Cell { property: props::NAME, value: Value::text(name) },
                });
                if !parsed.body.spans.is_empty() {
                    commands.push(Command::AddCell {
                        entity: id,
                        cell: Cell {
                            property: props::CONTENT,
                            value: Value::RichText(parsed.body),
                        },
                    });
                }
                adopted.push(AdoptedFile {
                    id,
                    path: path.clone(),
                    digest: digest(raw.as_bytes()),
                });
                created += 1;
            }
            ReconcileFinding::Conflict { .. }
            | ReconcileFinding::Missing { .. }
            | ReconcileFinding::OrphanCopy { .. }
            | ReconcileFinding::MassChange { .. } => surfaced += 1,
        }
    }

    if !commands.is_empty() {
        session
            .commit(commands, "vault-edit", Author::User)
            .map_err(|e| crate::content::WriteError::Persist(e.to_string()))?;
    }
    Ok(IngestOutcome { edited, created, surfaced, adopted })
}


// ---- P20j.7: expand a mass burst + the resolution verdicts ----

/// The scan WITHOUT the mass-change collapse — the shell's "review these
/// individually" door on a burst card. Same rules, every finding shown.
pub fn scan_all(io: &dyn VaultIo, store: &Store, manifest: &Manifest) -> Vec<ReconcileFinding> {
    match scan(io, store, manifest).as_slice() {
        [ReconcileFinding::MassChange { .. }] => {
            // Re-run with the threshold lifted: temporarily raise the bar
            // by scanning against an EMPTY-of-mass path — simplest is to
            // reproduce scan's body sans the final collapse. We call the
            // internal helper.
            scan_inner(io, store, manifest)
        }
        _ => scan(io, store, manifest),
    }
}

/// Take the DISK version of a conflicting (or any) file: ingest it as an
/// Edited finding — ONE undoable "vault-edit" txn, exactly the clean-edit
/// path, chosen deliberately by the user.
pub fn resolve_take_disk(
    session: &mut Session,
    io: &dyn VaultIo,
    id: Id,
    rel_path: &str,
) -> Result<(), crate::content::WriteError> {
    let finding = ReconcileFinding::Edited { id, path: rel_path.to_string() };
    ingest(session, io, &Manifest::default(), &[finding]).map(|_| ())
}

/// Keep the APP version: rewrite the file from the store and refresh the
/// manifest row, so the divergence settles with no box write.
pub fn resolve_keep_app(io: &mut dyn VaultIo, store: &Store, id: Id) -> io::Result<()> {
    let expected = expected_files(store);
    let Some(file) = expected.iter().find(|f| f.id == id) else {
        return Ok(()); // no longer projects — nothing to keep
    };
    let Some(content) = &file.content else { return Ok(()) };
    io.write_atomic(&file.rel_path, content.as_bytes())?;
    // Refresh only this row in the manifest (a scan is then clean).
    let mut manifest = load_manifest(io);
    let want = digest(content.as_bytes());
    if let Some(row) = manifest.rows.iter_mut().find(|r| r.id == id) {
        row.path = file.rel_path.clone();
        row.digest = want;
        row.trash_from = None;
    } else {
        manifest.rows.push(ManifestRow {
            path: file.rel_path.clone(),
            id,
            digest: want,
            trash_from: None,
        });
    }
    let bytes = serde_json::to_vec(&manifest).map_err(io::Error::other)?;
    io.write_atomic(MANIFEST_PATH, &bytes)
}

/// Trash the entity (a Missing-file verdict, or any): the ordinary box
/// trash — the next projection parks the file in `.trash/`, never a hard
/// delete (deletion never cascades).
pub fn resolve_trash(session: &mut Session, id: Id) -> Result<(), crate::content::WriteError> {
    session
        .commit(vec![Command::Trash { entity: id }], "vault-resolve trash", Author::User)
        .map(|_| ())
        .map_err(|e| crate::content::WriteError::Persist(e.to_string()))
}

// ---- P20j.4: the real vault IO + the projector lock ----

/// The production `VaultIo`: rooted at the vault folder; every write is
/// tmp (+ fsync) + rename inside `.liv/tmp/`, parents created on demand.
pub struct RealVaultIo {
    root: std::path::PathBuf,
}

impl RealVaultIo {
    pub fn new(root: &std::path::Path) -> Self {
        Self { root: root.to_path_buf() }
    }

    fn abs(&self, rel: &str) -> std::path::PathBuf {
        self.root.join(rel)
    }
}

impl VaultIo for RealVaultIo {
    fn write_atomic(&mut self, rel: &str, bytes: &[u8]) -> io::Result<()> {
        use std::io::Write;
        let target = self.abs(rel);
        if let Some(parent) = target.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let tmp_dir = self.root.join(".liv/tmp");
        std::fs::create_dir_all(&tmp_dir)?;
        let tmp = tmp_dir.join(format!(
            "w-{}-{}",
            std::process::id(),
            digest(rel.as_bytes()).chars().take(12).collect::<String>()
        ));
        {
            let mut file = std::fs::File::create(&tmp)?;
            file.write_all(bytes)?;
            file.sync_all()?;
        }
        std::fs::rename(&tmp, &target)
    }

    fn rename(&mut self, from: &str, to: &str) -> io::Result<()> {
        let target = self.abs(to);
        if let Some(parent) = target.parent() {
            std::fs::create_dir_all(parent)?;
        }
        std::fs::rename(self.abs(from), target)
    }

    fn read(&self, rel: &str) -> io::Result<Vec<u8>> {
        std::fs::read(self.abs(rel))
    }

    fn exists(&self, rel: &str) -> bool {
        self.abs(rel).exists()
    }

    fn list(&self, prefix: &str) -> Vec<String> {
        fn walk(dir: &std::path::Path, root: &std::path::Path, out: &mut Vec<String>) {
            let Ok(entries) = std::fs::read_dir(dir) else { return };
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_dir() {
                    walk(&path, root, out);
                } else if let Ok(rel) = path.strip_prefix(root) {
                    out.push(rel.to_string_lossy().replace('\\', "/"));
                }
            }
        }
        let mut out = Vec::new();
        walk(&self.root.join(prefix), &self.root, &mut out);
        // walk from the prefix dir but paths must stay root-relative:
        // handle a FILE prefix too.
        if out.is_empty() && self.abs(prefix).is_file() {
            out.push(prefix.to_string());
        }
        out
    }
}

/// One full projection under the PROJECTOR lock (design §3): a blocking
/// flock on `.liv/projector.lock`, held across load→plan→apply only —
/// IO-only, never the box lock, released on drop. Serializes the app and
/// the CLI reconciling after their box commits (kill-shot C).
pub fn project_locked(root: &std::path::Path, store: &Store) -> io::Result<Manifest> {
    std::fs::create_dir_all(root.join(".liv"))?;
    let lock_path = root.join(".liv/projector.lock");
    let lock = std::fs::OpenOptions::new()
        .create(true)
        .write(true)
        .open(&lock_path)?;
    lock.lock()?; // blocking; released when `lock` drops
    let mut io = RealVaultIo::new(root);
    let manifest = load_manifest(&io);
    let (ops, next) = plan_projection(store, &manifest);
    apply_projection(&mut io, &ops, &next)?;
    Ok(next)
}


// ---- P20j.5: vault discovery + the split lock-phase helpers ----

/// The vault root, discovered by the `.liv` ancestor of the box path
/// (design §6): `<root>/.liv/box/<log>` → root. Anything else = legacy
/// mode — projection off, every existing harness untouched.
pub fn vault_root_of(box_path: &std::path::Path) -> Option<std::path::PathBuf> {
    let box_dir = box_path.parent()?;
    if box_dir.file_name()? != "box" {
        return None;
    }
    let liv = box_dir.parent()?;
    if liv.file_name()? != ".liv" {
        return None;
    }
    liv.parent().map(|p| p.to_path_buf())
}

/// Apply a PRE-COMPUTED plan under the projector lock (the post-checkin
/// half: the plan was computed while the box lock was held — pure CPU +
/// one manifest read — and the file IO happens here, box lock released).
/// A stale plan is harmless: every op is disk-verified and the next
/// commit re-plans (kill-shots A/C).
pub fn apply_locked(
    root: &std::path::Path,
    ops: &[FsOp],
    next: &Manifest,
) -> io::Result<()> {
    std::fs::create_dir_all(root.join(".liv"))?;
    let lock = std::fs::OpenOptions::new()
        .create(true)
        .write(true)
        .open(root.join(".liv/projector.lock"))?;
    lock.lock()?;
    let mut io = RealVaultIo::new(root);
    apply_projection(&mut io, ops, next)
}
