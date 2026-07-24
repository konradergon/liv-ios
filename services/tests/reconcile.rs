//! P20j.3 — the reconcile decision table + ingest (design §4), kill-shot
//! gated. Rule order is law: (1) content-addressed CLEAN first — file ==
//! render(store) means our own write, never re-ingested (the echo
//! suppressor, 100×-pinned); (2) a clean external edit ingests as ONE
//! announced, undoable, log-recorded transaction; (3) conflicts NEVER
//! merge or auto-apply; (4) deletions and mass changes NEVER auto-apply —
//! a disk deletion never deletes the entity.

use liv_core::*;
use liv_services::content;
use liv_services::projection::{self, Manifest, ReconcileFinding, VaultIo};
use std::collections::BTreeMap;

fn boxed(name: &str) -> (Session, std::path::PathBuf) {
    let path = std::env::temp_dir().join(format!("liv_rec_{name}.log"));
    let _ = std::fs::remove_file(&path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
    let mut session = Session::open(&path).unwrap();
    liv_services::seed_if_fresh(&mut session).unwrap();
    (session, path)
}

fn cleanup(path: &std::path::Path) {
    let _ = std::fs::remove_file(path);
    let _ = std::fs::remove_file(format!("{}.declined", path.display()));
    let _ = std::fs::remove_file(format!("{}.pending", path.display()));
}

#[derive(Default)]
struct MemIo {
    files: BTreeMap<String, Vec<u8>>,
}

impl VaultIo for MemIo {
    fn write_atomic(&mut self, rel: &str, bytes: &[u8]) -> std::io::Result<()> {
        self.files.insert(rel.to_string(), bytes.to_vec());
        Ok(())
    }
    fn rename(&mut self, from: &str, to: &str) -> std::io::Result<()> {
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
    fn list(&self, prefix: &str) -> Vec<String> {
        self.files.keys().filter(|k| k.starts_with(prefix)).cloned().collect()
    }
}

fn note(session: &mut Session, name: &str) -> Id {
    let stamp = DateTime::at(2026, 7, 15, 9, 0);
    let id = content::create_note(session, stamp).unwrap();
    content::set_type(session, id, "note").unwrap();
    content::set_property(session, id, "name", name).unwrap();
    id
}

fn project(io: &mut MemIo, store: &Store) -> Manifest {
    let manifest = projection::load_manifest(io);
    let (ops, next) = projection::plan_projection(store, &manifest);
    projection::apply_projection(io, &ops, &next).unwrap();
    next
}

fn log_len(path: &std::path::Path) -> u64 {
    std::fs::metadata(path).map(|m| m.len()).unwrap_or(0)
}

#[test]
fn kill_shot_b_own_writes_never_reingest_100x() {
    let (mut session, path) = boxed("echo");
    note(&mut session, "Alpha");
    note(&mut session, "Beta");
    let mut io = MemIo::default();
    project(&mut io, session.store());

    let before = log_len(&path);
    for _ in 0..100 {
        let manifest = projection::load_manifest(&io);
        let findings = projection::scan(&io, session.store(), &manifest);
        assert!(
            findings.is_empty(),
            "our own writes must scan clean, got {findings:?}"
        );
        let outcome =
            projection::ingest(&mut session, &io, &manifest, &findings).unwrap();
        assert_eq!(outcome.edited + outcome.created, 0);
    }
    assert_eq!(log_len(&path), before, "0 commits across 100 syncs");
    cleanup(&path);
}

#[test]
fn a_clean_external_edit_ingests_as_one_undoable_txn() {
    let (mut session, path) = boxed("edit");
    let id = note(&mut session, "Field notes");
    let mut io = MemIo::default();
    project(&mut io, session.store());

    // The user edits the file outside Liv: body appended, valid markdown.
    let rel = "library/notes/field-notes.md";
    let mut bytes = io.read(rel).unwrap();
    bytes.extend_from_slice(b"a line written in another editor");
    io.write_atomic(rel, &bytes).unwrap();

    let manifest = projection::load_manifest(&io);
    let findings = projection::scan(&io, session.store(), &manifest);
    assert!(
        matches!(findings.as_slice(), [ReconcileFinding::Edited { id: found, .. }] if *found == id),
        "one clean edit, got {findings:?}"
    );
    let outcome = projection::ingest(&mut session, &io, &manifest, &findings).unwrap();
    assert_eq!(outcome.edited, 1);

    // The edit landed in the box…
    let store = session.store();
    let content_prop = liv_services::property_id(store, "content").unwrap();
    let body = match store.get(id).unwrap().get(content_prop) {
        Some(Value::RichText(rich)) => {
            liv_services::markdown::render_markdown(rich, &|_| String::new())
        }
        other => panic!("expected rich content, got {other:?}"),
    };
    assert!(body.contains("another editor"), "{body}");

    // …and ONE undo removes exactly it.
    session.undo(Author::User).unwrap();
    let store = session.store();
    let body = match store.get(id).unwrap().get(content_prop) {
        Some(Value::RichText(rich)) => {
            liv_services::markdown::render_markdown(rich, &|_| String::new())
        }
        _ => String::new(),
    };
    assert!(!body.contains("another editor"));
    cleanup(&path);
}

#[test]
fn a_conflict_never_auto_applies() {
    let (mut session, path) = boxed("conflict");
    let id = note(&mut session, "Contested");
    let mut io = MemIo::default();
    project(&mut io, session.store());

    // BOTH sides move: the box gets new content…
    let spans = liv_services::markdown::parse_markdown("the app side wrote this").spans;
    let store = session.store();
    let content_prop_now = store.get(id).unwrap().get(props::CONTENT);
    let base = content::content_fingerprint(content_prop_now);
    content::set_content(&mut session, id, spans, base).unwrap();
    // …and the disk file is edited independently (against the OLD render).
    let rel = "library/notes/contested.md";
    let mut bytes = io.read(rel).unwrap();
    bytes.extend_from_slice(b"the disk side wrote this");
    io.write_atomic(rel, &bytes).unwrap();

    let manifest = projection::load_manifest(&io);
    let findings = projection::scan(&io, session.store(), &manifest);
    assert!(
        matches!(findings.as_slice(), [ReconcileFinding::Conflict { id: found, .. }] if *found == id),
        "a conflict, got {findings:?}"
    );
    let before = log_len(&path);
    let outcome = projection::ingest(&mut session, &io, &manifest, &findings).unwrap();
    assert_eq!((outcome.edited, outcome.created), (0, 0), "conflicts are surfaced, never merged");
    assert_eq!(log_len(&path), before, "no write happened");
    cleanup(&path);
}

#[test]
fn a_disk_deletion_never_deletes_the_entity() {
    let (mut session, path) = boxed("delete");
    let id = note(&mut session, "Survivor");
    let mut io = MemIo::default();
    project(&mut io, session.store());
    io.files.remove("library/notes/survivor.md");

    let manifest = projection::load_manifest(&io);
    let findings = projection::scan(&io, session.store(), &manifest);
    assert!(
        matches!(findings.as_slice(), [ReconcileFinding::Missing { id: found, .. }] if *found == id),
        "a missing-file card, got {findings:?}"
    );
    let before = log_len(&path);
    projection::ingest(&mut session, &io, &manifest, &findings).unwrap();
    assert_eq!(log_len(&path), before);
    assert!(!session.store().get(id).unwrap().trashed, "the entity lives");
    cleanup(&path);
}

#[test]
fn a_mass_change_burst_downgrades_to_one_card() {
    let (mut session, path) = boxed("mass");
    let mut ids = Vec::new();
    for i in 0..30 {
        ids.push(note(&mut session, &format!("Bulk {i}")));
    }
    let mut io = MemIo::default();
    project(&mut io, session.store());

    // A sync client rewrites everything at once.
    let paths: Vec<String> = io.list("library/").into_iter().collect();
    for rel in &paths {
        let mut bytes = io.read(rel).unwrap();
        bytes.extend_from_slice(b"sync client noise");
        io.write_atomic(rel, &bytes).unwrap();
    }

    let manifest = projection::load_manifest(&io);
    let findings = projection::scan(&io, session.store(), &manifest);
    assert!(
        matches!(findings.as_slice(), [ReconcileFinding::MassChange { count }] if *count >= 30),
        "one mass-change card, got {} findings",
        findings.len()
    );
    let before = log_len(&path);
    projection::ingest(&mut session, &io, &manifest, &findings).unwrap();
    assert_eq!(log_len(&path), before, "nothing auto-applies");
    cleanup(&path);
}

#[test]
fn a_new_markdown_file_ingests_and_settles_canonical() {
    let (mut session, path) = boxed("newfile");
    let mut io = MemIo::default();
    project(&mut io, session.store());

    io.write_atomic(
        "library/notes/A Fresh Thought.md",
        b"# A fresh thought\n\nwritten by hand, outside\n",
    )
    .unwrap();

    let manifest = projection::load_manifest(&io);
    let findings = projection::scan(&io, session.store(), &manifest);
    assert!(
        matches!(findings.as_slice(), [ReconcileFinding::NewFile { .. }]),
        "a new file, got {findings:?}"
    );
    let outcome = projection::ingest(&mut session, &io, &manifest, &findings).unwrap();
    assert_eq!(outcome.created, 1);

    let store = session.store();
    let born = store.entities().find(|e| {
        matches!(e.get(props::NAME), Some(Value::Text(n)) if n == "A fresh thought")
    });
    assert!(born.is_some(), "the entity was born from the file");

    // The adopted path folds into the manifest, so the projector RENAMES
    // the hand-made file to its canonical slug — never a duplicate.
    let mut io2 = io;
    let mut seeded = projection::load_manifest(&io2);
    projection::adopt_into(&mut seeded, &outcome.adopted);
    let (ops, next) = projection::plan_projection(session.store(), &seeded);
    projection::apply_projection(&mut io2, &ops, &next).unwrap();
    assert!(io2.exists("library/notes/a-fresh-thought.md"));
    assert!(
        !io2.exists("library/notes/A Fresh Thought.md"),
        "the hand path was claimed, not left as a stray"
    );

    // THE regression pin: a second scan+ingest cycle finds NOTHING — the
    // duplicate factory is structurally closed.
    let manifest2 = projection::load_manifest(&io2);
    let findings2 = projection::scan(&io2, session.store(), &manifest2);
    assert!(findings2.is_empty(), "second cycle must be silent, got {findings2:?}");
    cleanup(&path);
}

// ---- P20j.7: expanding a mass burst + the resolution verdicts ----

#[test]
fn scan_all_expands_a_mass_burst_into_individual_findings() {
    let (mut session, path) = boxed("expand");
    let mut ids = Vec::new();
    for i in 0..30 {
        ids.push(note(&mut session, &format!("Bulk {i}")));
    }
    let mut io = MemIo::default();
    project(&mut io, session.store());
    for rel in io.files.keys().filter(|k| k.starts_with("library/")).cloned().collect::<Vec<_>>() {
        let mut bytes = io.read(&rel).unwrap();
        bytes.extend_from_slice(b"noise");
        io.write_atomic(&rel, &bytes).unwrap();
    }
    let manifest = projection::load_manifest(&io);
    // scan() collapses to one card; scan_all() shows every one.
    assert!(matches!(
        projection::scan(&io, session.store(), &manifest).as_slice(),
        [ReconcileFinding::MassChange { .. }]
    ));
    let all = projection::scan_all(&io, session.store(), &manifest);
    assert_eq!(all.len(), 30);
    assert!(all.iter().all(|f| matches!(f, ReconcileFinding::Edited { .. })));
    cleanup(&path);
}

#[test]
fn resolve_take_disk_ingests_the_conflicting_file() {
    let (mut session, path) = boxed("takedisk");
    let id = note(&mut session, "Contested");
    let mut io = MemIo::default();
    project(&mut io, session.store());
    // Both sides move (a conflict).
    let spans = liv_services::markdown::parse_markdown("app version").spans;
    let base = content::content_fingerprint(session.store().get(id).unwrap().get(props::CONTENT));
    content::set_content(&mut session, id, spans, base).unwrap();
    let rel = "library/notes/contested.md";
    io.write_atomic(rel, b"# Contested\n\ndisk version wins\n").unwrap();

    let manifest = projection::load_manifest(&io);
    projection::resolve_take_disk(&mut session, &io, id, rel).unwrap();
    let store = session.store();
    let content_prop = liv_services::property_id(store, "content").unwrap();
    let body = match store.get(id).unwrap().get(content_prop) {
        Some(Value::RichText(r)) => liv_services::markdown::render_markdown(r, &|_| String::new()),
        _ => String::new(),
    };
    assert!(body.contains("disk version wins"), "{body}");
    let _ = manifest;
    cleanup(&path);
}

#[test]
fn resolve_keep_app_rewrites_the_file_from_the_store() {
    let (mut session, path) = boxed("keepapp");
    let id = note(&mut session, "Canonical");
    let mut io = MemIo::default();
    project(&mut io, session.store());
    let rel = "library/notes/canonical.md";
    // The disk is vandalized.
    io.write_atomic(rel, b"garbage the sync client left").unwrap();

    let manifest = projection::load_manifest(&io);
    projection::resolve_keep_app(&mut io, session.store(), id).unwrap();
    let bytes = io.read(rel).unwrap();
    let expected = liv_services::vault::render_vault_entity(session.store(), id).unwrap();
    assert_eq!(bytes, expected.as_bytes(), "the store's version is back on disk");
    // And a scan is now clean (the manifest row was refreshed).
    let refreshed = projection::load_manifest(&io);
    let findings = projection::scan(&io, session.store(), &refreshed);
    assert!(findings.is_empty(), "keep-app settled the divergence, got {findings:?}");
    let _ = manifest;
    cleanup(&path);
}

#[test]
fn resolve_trash_removes_the_entity_and_parks_the_file() {
    let (mut session, path) = boxed("resolvetrash");
    let id = note(&mut session, "Doomed");
    let mut io = MemIo::default();
    project(&mut io, session.store());

    projection::resolve_trash(&mut session, id).unwrap();
    assert!(session.store().get(id).unwrap().trashed);
    // Re-projecting parks the file (never a hard delete).
    project(&mut io, session.store());
    assert!(!io.exists("library/notes/doomed.md"));
    assert!(io.exists(".trash/library/notes/doomed.md"));
    cleanup(&path);
}
