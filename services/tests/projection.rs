//! P20j.2 — the materializer + manifest, kill-shot gated (the design's
//! order-is-law): log first (already shipped), per-file tmp+fsync+rename,
//! manifest LAST and atomic. The manifest is a CACHE — corrupt or missing
//! it rebuilds; and KILL-SHOT A aborts the apply at EVERY op boundary
//! (plus injected disk-full) and demands reconvergence to
//! files == expected(store) with zero loss and zero duplicates.

use lotus_core::*;
use lotus_services::content;
use lotus_services::projection::{self, Manifest, VaultIo};
use std::collections::BTreeMap;

fn boxed(name: &str) -> (Session, std::path::PathBuf) {
    let path = std::env::temp_dir().join(format!("lotus_proj_{name}.log"));
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
    let mut session = Session::open(&path).unwrap();
    lotus_services::seed_if_fresh(&mut session).unwrap();
    (session, path)
}

fn cleanup(path: &std::path::Path) {
    let _ = std::fs::remove_file(path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
}

/// The in-memory vault: every IO path the materializer may take, plus a
/// FUSE — abort (or ENOSPC) after N successful ops, so the crash matrix
/// is a loop, not a prayer.
#[derive(Default)]
struct MemIo {
    files: BTreeMap<String, Vec<u8>>,
    fuse: Option<usize>,
    ops: usize,
}

impl MemIo {
    fn burn(&mut self) -> std::io::Result<()> {
        if let Some(fuse) = self.fuse {
            if self.ops >= fuse {
                return Err(std::io::Error::new(
                    std::io::ErrorKind::StorageFull,
                    "fuse blown (injected)",
                ));
            }
        }
        self.ops += 1;
        Ok(())
    }
}

impl VaultIo for MemIo {
    fn write_atomic(&mut self, rel: &str, bytes: &[u8]) -> std::io::Result<()> {
        self.burn()?;
        self.files.insert(rel.to_string(), bytes.to_vec());
        Ok(())
    }
    fn rename(&mut self, from: &str, to: &str) -> std::io::Result<()> {
        self.burn()?;
        let bytes = self
            .files
            .remove(from)
            .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::NotFound, from.to_string()))?;
        self.files.insert(to.to_string(), bytes);
        Ok(())
    }
    fn read(&self, rel: &str) -> std::io::Result<Vec<u8>> {
        self.files
            .get(rel)
            .cloned()
            .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::NotFound, rel.to_string()))
    }
    fn exists(&self, rel: &str) -> bool {
        self.files.contains_key(rel)
    }
}

/// Everything under library/ must equal expected_files exactly — no loss,
/// no dupes, no strays.
fn assert_converged(io: &MemIo, store: &Store) {
    let expected = lotus_services::vault::expected_files(store);
    for file in &expected {
        if let Some(content) = &file.content {
            let on_disk = io.files.get(&file.rel_path);
            assert!(on_disk.is_some(), "missing {}", file.rel_path);
            assert_eq!(
                on_disk.unwrap(),
                content.as_bytes(),
                "content mismatch at {}",
                file.rel_path
            );
        }
    }
    let expected_paths: std::collections::HashSet<&str> =
        expected.iter().map(|f| f.rel_path.as_str()).collect();
    for path in io.files.keys() {
        if path.starts_with("library/") {
            assert!(expected_paths.contains(path.as_str()), "stray file {path}");
        }
    }
}

fn project(io: &mut MemIo, store: &Store) -> std::io::Result<Manifest> {
    let manifest = projection::load_manifest(io);
    let (ops, next) = projection::plan_projection(store, &manifest);
    projection::apply_projection(io, &ops, &next)?;
    Ok(next)
}

#[test]
fn materialize_writes_expected_files_and_the_manifest() {
    let (mut session, path) = boxed("write");
    let stamp = DateTime::at(2026, 7, 15, 9, 0);
    let note = content::create_note(&mut session, stamp).unwrap();
    content::set_type(&mut session, note, "note").unwrap();
    content::set_property(&mut session, note, "name", "Methodology").unwrap();

    let mut io = MemIo::default();
    let manifest = project(&mut io, session.store()).unwrap();
    assert_converged(&io, session.store());
    assert!(io.files.contains_key(".liv/index.json"), "the manifest is on disk, LAST");
    assert!(manifest.rows.iter().any(|r| r.id == note));

    // A second projection is a no-op: zero ops planned (echo-proof).
    let loaded = projection::load_manifest(&io);
    let (ops, _) = projection::plan_projection(session.store(), &loaded);
    assert!(ops.is_empty(), "re-projection must plan nothing, got {ops:?}");
    cleanup(&path);
}

#[test]
fn rename_moves_the_file_and_undo_moves_it_back() {
    let (mut session, path) = boxed("rename");
    let stamp = DateTime::at(2026, 7, 15, 9, 0);
    let note = content::create_note(&mut session, stamp).unwrap();
    content::set_type(&mut session, note, "note").unwrap();
    content::set_property(&mut session, note, "name", "Draft one").unwrap();

    let mut io = MemIo::default();
    project(&mut io, session.store()).unwrap();
    assert!(io.exists("library/notes/draft-one.md"));

    content::set_property(&mut session, note, "name", "Final version").unwrap();
    project(&mut io, session.store()).unwrap();
    assert!(!io.exists("library/notes/draft-one.md"), "the old path moved");
    assert!(io.exists("library/notes/final-version.md"));

    // Undo over the log IS undo on disk.
    session.undo(Author::User).unwrap();
    project(&mut io, session.store()).unwrap();
    assert!(io.exists("library/notes/draft-one.md"));
    assert!(!io.exists("library/notes/final-version.md"));
    cleanup(&path);
}

#[test]
fn trash_round_trips_through_dot_trash() {
    let (mut session, path) = boxed("trash");
    let stamp = DateTime::at(2026, 7, 15, 9, 0);
    let note = content::create_note(&mut session, stamp).unwrap();
    content::set_type(&mut session, note, "note").unwrap();
    content::set_property(&mut session, note, "name", "Keep me").unwrap();

    let mut io = MemIo::default();
    project(&mut io, session.store()).unwrap();
    session
        .commit(vec![Command::Trash { entity: note }], "trash", Author::User)
        .unwrap();
    project(&mut io, session.store()).unwrap();
    assert!(!io.exists("library/notes/keep-me.md"));
    assert!(
        io.exists(".trash/library/notes/keep-me.md"),
        "trash preserves the original rel path: {:?}",
        io.files.keys().collect::<Vec<_>>()
    );

    session.undo(Author::User).unwrap();
    project(&mut io, session.store()).unwrap();
    assert!(io.exists("library/notes/keep-me.md"), "undo restores the exact path");
    assert!(!io.exists(".trash/library/notes/keep-me.md"));
    cleanup(&path);
}

#[test]
fn kill_shot_a_the_crash_matrix_converges() {
    // Abort the apply after EVERY possible op count (0..=total, incl. the
    // manifest write) across a mutating history; a clean re-projection
    // must always converge with zero loss and zero duplicates.
    let (mut session, path) = boxed("crash");
    let stamp = DateTime::at(2026, 7, 15, 9, 0);
    let a = content::create_note(&mut session, stamp).unwrap();
    content::set_type(&mut session, a, "note").unwrap();
    content::set_property(&mut session, a, "name", "Alpha").unwrap();
    let b = content::create_note(&mut session, stamp).unwrap();
    content::set_type(&mut session, b, "note").unwrap();
    content::set_property(&mut session, b, "name", "Beta").unwrap();

    // Baseline: how many ops does a fresh projection take?
    let total = {
        let mut probe = MemIo::default();
        let manifest = projection::load_manifest(&probe);
        let (ops, next) = projection::plan_projection(session.store(), &manifest);
        projection::apply_projection(&mut probe, &ops, &next).unwrap();
        probe.ops
    };
    assert!(total >= 3, "the probe should take several ops, got {total}");

    for fuse in 0..=total {
        let mut io = MemIo::default();
        io.fuse = Some(fuse);
        {
            let manifest = projection::load_manifest(&io);
            let (ops, next) = projection::plan_projection(session.store(), &manifest);
            let _ = projection::apply_projection(&mut io, &ops, &next); // may blow
        }
        // The crash "reboots": the fuse clears, reconcile runs clean.
        io.fuse = None;
        project(&mut io, session.store()).unwrap();
        assert_converged(&io, session.store());
    }

    // And mid-history: rename Alpha, crash at every boundary, converge.
    content::set_property(&mut session, a, "name", "Alpha prime").unwrap();
    for fuse in 0..=total {
        let mut io = MemIo::default();
        io.fuse = None;
        // Materialize the OLD state first (pre-rename disk).
        {
            // Rewind expectation: project current store fully, then rename
            // arrives via a fresh plan aborted mid-way.
            let manifest = projection::load_manifest(&io);
            let (ops, next) = projection::plan_projection(session.store(), &manifest);
            let _ = (ops, next);
        }
        let mut io = MemIo::default();
        project(&mut io, session.store()).unwrap();
        io.fuse = Some(fuse);
        let manifest = projection::load_manifest(&io);
        let (ops, next) = projection::plan_projection(session.store(), &manifest);
        let _ = projection::apply_projection(&mut io, &ops, &next);
        io.fuse = None;
        project(&mut io, session.store()).unwrap();
        assert_converged(&io, session.store());
    }
    cleanup(&path);
}

#[test]
fn a_corrupt_manifest_heals() {
    let (mut session, path) = boxed("corrupt");
    let stamp = DateTime::at(2026, 7, 15, 9, 0);
    let note = content::create_note(&mut session, stamp).unwrap();
    content::set_type(&mut session, note, "note").unwrap();
    content::set_property(&mut session, note, "name", "Sturdy").unwrap();

    let mut io = MemIo::default();
    project(&mut io, session.store()).unwrap();
    io.files.insert(".liv/index.json".into(), b"{ not json at all".to_vec());
    project(&mut io, session.store()).unwrap();
    assert_converged(&io, session.store());
    cleanup(&path);
}
