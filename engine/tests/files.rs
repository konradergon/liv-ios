//! Files, by reference, and the thing `core/` gets wrong about them.
//!
//! **A path is where, not what.** `core/`'s `FileRef` carries both — a
//! device-local path AND the content hash — in one value, in the log.
//! `core.md` §14 records that as a model bug and `op-format.md` §6 repeats
//! it: a path does not survive a device boundary, so a file synced from a
//! laptop arrives on a phone carrying a path that resolves to nothing and
//! looks perfectly valid.
//!
//! Here they are separated. The HASH is the cell, and it travels; the PATH
//! is a device-local row that does not. A file that arrives by sync has a
//! hash and no path here, and saying so is the honest answer.
//!
//! Nothing is ever copied or moved. The librarian reads to hash and
//! otherwise leaves the file exactly where the user put it.

use liv_engine::*;

fn dev(n: u8) -> DeviceId {
    DeviceId([n; 8])
}

const T0: u64 = 1_787_391_635_000;

fn engine() -> Engine {
    Engine::open_in_memory(dev(1)).unwrap()
}

/// A scratch directory of this test's own.
fn dir(name: &str) -> std::path::PathBuf {
    let d = std::env::temp_dir().join(format!("liv_engine_files_{name}"));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    d
}

fn write(dir: &std::path::Path, name: &str, body: &str) -> String {
    let p = dir.join(name);
    std::fs::write(&p, body).unwrap();
    p.to_string_lossy().into_owned()
}

// ---- adding -----------------------------------------------------------

#[test]
fn a_file_is_added_by_reference_and_never_moved() {
    let d = dir("add");
    let path = write(&d, "invoice.PDF", "some bytes");

    let mut e = engine();
    let id = e.add_file(&path, T0).unwrap();

    assert_eq!(e.kind_of(id).unwrap(), Some(kind::FILE));
    assert_eq!(e.name(id).unwrap().as_deref(), Some("invoice.PDF"), "the filename, as typed");
    // LOWERCASED, because a format is a kind of thing and `.PDF` and
    // `.pdf` are the same kind of thing.
    assert_eq!(e.one(id, prop::FORMAT).unwrap(), Some(Value::Text("pdf".into())));
    assert!(matches!(e.one(id, prop::FILE).unwrap(), Some(Value::Blob(_))));

    // Still there, still itself.
    assert_eq!(std::fs::read_to_string(&path).unwrap(), "some bytes");
    assert_eq!(e.path_of(id).unwrap().as_deref(), Some(path.as_str()));

    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn the_same_bytes_hash_the_same_wherever_they_are() {
    let d = dir("same");
    let a = write(&d, "one.txt", "identical");
    let b = write(&d, "two.txt", "identical");
    let c = write(&d, "three.txt", "different");

    let mut e = engine();
    let one = e.add_file(&a, T0).unwrap();
    let two = e.add_file(&b, T0 + 1).unwrap();
    let three = e.add_file(&c, T0 + 2).unwrap();

    assert_eq!(e.one(one, prop::FILE).unwrap(), e.one(two, prop::FILE).unwrap());
    assert_ne!(e.one(one, prop::FILE).unwrap(), e.one(three, prop::FILE).unwrap());

    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn an_unreadable_path_is_an_error_not_a_phantom_entity() {
    let mut e = engine();
    let before = e.entity_count().unwrap();
    assert!(e.add_file("/no/such/file/anywhere", T0).is_err());
    assert_eq!(e.entity_count().unwrap(), before, "and nothing was created");
}

#[test]
fn a_file_with_no_extension_carries_no_format() {
    let d = dir("noext");
    let path = write(&d, "Makefile", "all:");
    let mut e = engine();
    let id = e.add_file(&path, T0).unwrap();

    // Not "" — an empty format is a claim about the file, and we have
    // none to make.
    assert_eq!(e.one(id, prop::FORMAT).unwrap(), None);
    assert_eq!(e.name(id).unwrap().as_deref(), Some("Makefile"));

    let _ = std::fs::remove_dir_all(&d);
}

// ---- resync: a changed hash IS the integration ------------------------

#[test]
fn resync_notices_the_bytes_changed() {
    let d = dir("resync");
    let path = write(&d, "notes.md", "first draft");
    let mut e = engine();
    let id = e.add_file(&path, T0).unwrap();
    let first = e.one(id, prop::FILE).unwrap();

    assert_eq!(e.resync_file(id, T0 + 1).unwrap(), Resync::Unchanged);

    // Word saves the file. That is the whole integration.
    std::fs::write(&path, "second draft").unwrap();
    let Resync::Changed(fresh) = e.resync_file(id, T0 + 2).unwrap() else {
        panic!("a changed file is Changed");
    };
    assert_eq!(e.one(id, prop::FILE).unwrap(), Some(Value::Blob(fresh)));
    assert_ne!(e.one(id, prop::FILE).unwrap(), first);
    // And the path still points at it — the file did not move.
    assert_eq!(e.path_of(id).unwrap().as_deref(), Some(path.as_str()));

    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn a_vanished_file_is_broken_not_changed() {
    let d = dir("gone");
    let path = write(&d, "gone.txt", "here for now");
    let mut e = engine();
    let id = e.add_file(&path, T0).unwrap();
    let before = e.one(id, prop::FILE).unwrap();

    std::fs::remove_file(&path).unwrap();

    assert_eq!(e.resync_file(id, T0 + 1).unwrap(), Resync::Broken);
    // **The cell is UNTOUCHED.** A file the user unplugged a drive for is
    // not a file whose contents changed, and forgetting its hash would
    // lose the only thing that could recognise it again.
    assert_eq!(e.one(id, prop::FILE).unwrap(), before);

    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn resyncing_something_that_is_not_a_file_is_broken() {
    let mut e = engine();
    let note = e.create(kind::NOTE, Some("not a file"), T0).unwrap();
    assert_eq!(e.resync_file(note, T0 + 1).unwrap(), Resync::Broken);
}

#[test]
fn an_unchanged_resync_writes_nothing() {
    let d = dir("noop");
    let path = write(&d, "steady.txt", "same");
    let mut e = engine();
    let id = e.add_file(&path, T0).unwrap();
    let groups = e.group_count().unwrap();

    assert_eq!(e.resync_file(id, T0 + 1).unwrap(), Resync::Unchanged);
    assert_eq!(e.group_count().unwrap(), groups, "opening a file is not an edit");

    let _ = std::fs::remove_dir_all(&d);
}

// ---- the path does not travel -----------------------------------------

/// **The point of the whole file.**
///
/// A file entity arriving from another device brings its hash and nothing
/// else. `core/` would have brought the laptop's path too, and the phone
/// would have shown a file reference that looks fine and opens nothing.
#[test]
fn a_file_from_another_device_has_a_hash_and_no_path_here() {
    let d = dir("sync");
    let path = write(&d, "shared.txt", "bytes");

    // The laptop adds it.
    let mut laptop = Engine::open_in_memory(dev(1)).unwrap();
    let id = laptop.add_file(&path, T0).unwrap();
    assert!(laptop.path_of(id).unwrap().is_some());

    // The phone receives the ops.
    let mut phone = Engine::open_in_memory(dev(2)).unwrap();
    for g in laptop.groups().unwrap() {
        phone.receive(g).unwrap();
    }

    assert_eq!(
        phone.one(id, prop::FILE).unwrap(),
        laptop.one(id, prop::FILE).unwrap(),
        "the hash travelled"
    );
    assert_eq!(phone.name(id).unwrap().as_deref(), Some("shared.txt"));
    assert_eq!(phone.path_of(id).unwrap(), None, "and the path did NOT");

    let _ = std::fs::remove_dir_all(&d);
}

/// And it is not in the digest either — two devices holding the same file
/// in different folders have not drifted.
#[test]
fn where_a_file_sits_is_not_part_of_what_two_devices_compare() {
    let d = dir("digest");
    let one = write(&d, "a.txt", "same bytes");
    std::fs::create_dir_all(d.join("elsewhere")).unwrap();
    let two = write(&d.join("elsewhere"), "a.txt", "same bytes");

    let mut left = Engine::open_in_memory(dev(1)).unwrap();
    let id = left.add_file(&one, T0).unwrap();

    let mut right = Engine::open_in_memory(dev(2)).unwrap();
    for g in left.groups().unwrap() {
        right.receive(g).unwrap();
    }
    right.remember_path(id, &two).unwrap();

    assert_eq!(left.digest().unwrap(), right.digest().unwrap());
    assert_eq!(left.path_of(id).unwrap().as_deref(), Some(one.as_str()));
    assert_eq!(right.path_of(id).unwrap().as_deref(), Some(two.as_str()));

    let _ = std::fs::remove_dir_all(&d);
}

/// A replay must not take the paths with it: they are not derived from
/// the log, so nothing could put them back.
#[test]
fn a_replay_keeps_the_paths() {
    let d = dir("replay");
    let path = write(&d, "kept.txt", "bytes");
    let mut e = engine();
    let id = e.add_file(&path, T0).unwrap();

    e.replay().unwrap();

    assert_eq!(e.path_of(id).unwrap().as_deref(), Some(path.as_str()));

    let _ = std::fs::remove_dir_all(&d);
}

// ---- where the box is -------------------------------------------------
//
// The phone keeps a box and the files it was handed in the app's own
// folder, and that folder's path changes when the app is reinstalled or
// updated. An absolute path stored on Monday is a wrong path by Friday.
// So a file inside the box's folder is remembered RELATIVE to it, and
// read back by joining it to wherever the box is now.

/// A box on disk, in `dir` — the folder its files are remembered against.
fn box_in(dir: &std::path::Path) -> Engine {
    std::fs::create_dir_all(dir).unwrap();
    Engine::open(&dir.join("liv.db"), dev(1)).unwrap()
}

/// A file at `rel` under `dir`, with its folders.
fn put(dir: &std::path::Path, rel: &str, body: &[u8]) -> std::path::PathBuf {
    let p = dir.join(rel);
    std::fs::create_dir_all(p.parent().unwrap()).unwrap();
    std::fs::write(&p, body).unwrap();
    p
}

fn s(p: &std::path::Path) -> String {
    p.to_str().unwrap().to_owned()
}

/// What the `places` row says, as written — not resolved.
fn stored(e: &Engine, id: EntityId) -> String {
    let Some(Value::Blob(hash)) = e.one(id, prop::FILE).unwrap() else { panic!("not a file") };
    liv_engine::view::path_of(e.conn(), &hash).unwrap().expect("a place")
}

#[test]
fn a_file_beside_the_box_is_remembered_relative_to_its_folder() {
    let d = dir("beside");
    let file = put(&d, "files/u1/invoice.pdf", b"bytes");
    let mut e = box_in(&d);
    let id = e.add_file(&s(&file), T0).unwrap();

    assert_eq!(stored(&e, id), "files/u1/invoice.pdf");
    assert_eq!(e.path_of(id).unwrap(), Some(s(&file)), "and read back whole");

    let _ = std::fs::remove_dir_all(&d);
}

/// **The bug this fixes.** Reinstalling the app moves its folder; every
/// absolute path in `places` then pointed at a folder that was gone.
#[test]
fn a_moved_box_still_finds_its_files() {
    let d = dir("moved");
    let before = d.join("old");
    let file = put(&before, "files/u1/invoice.pdf", b"bytes");
    let id = {
        let mut e = box_in(&before);
        e.add_file(&s(&file), T0).unwrap()
    };

    let after = d.join("new");
    std::fs::rename(&before, &after).unwrap();
    let mut e = box_in(&after);

    assert_eq!(e.path_of(id).unwrap(), Some(s(&after.join("files/u1/invoice.pdf"))));
    assert_eq!(e.resync_file(id, T0 + 1).unwrap(), Resync::Unchanged);

    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn a_file_outside_the_box_folder_is_remembered_where_it_is() {
    let d = dir("outside");
    let file = put(&d, "elsewhere/report.pdf", b"bytes");
    let mut e = box_in(&d.join("box"));
    let id = e.add_file(&s(&file), T0).unwrap();

    assert_eq!(stored(&e, id), s(&file));
    assert_eq!(e.path_of(id).unwrap(), Some(s(&file)));

    let _ = std::fs::remove_dir_all(&d);
}

/// Every row written before places went relative is absolute, and keeps
/// working exactly as it did.
#[test]
fn an_absolute_place_written_before_reads_as_written() {
    let d = dir("old_row");
    let file = put(&d, "files/u1/old.pdf", b"bytes");
    let mut e = box_in(&d);
    let id = e.add_file(&s(&file), T0).unwrap();
    let Some(Value::Blob(hash)) = e.one(id, prop::FILE).unwrap() else { panic!() };
    liv_engine::view::remember_path(e.conn(), &hash, &s(&file)).unwrap();

    assert_eq!(stored(&e, id), s(&file));
    assert_eq!(e.path_of(id).unwrap(), Some(s(&file)));
    assert_eq!(e.resync_file(id, T0 + 1).unwrap(), Resync::Unchanged);

    let _ = std::fs::remove_dir_all(&d);
}

/// `liv file ./x.pdf` hands over a path relative to where the CLI ran,
/// which is not where the box is. It is made whole against the current
/// directory first — the same place `hash_file` read it from.
///
/// **The one test here that moves the current directory**; every other
/// one uses whole paths, so none of them notices.
#[test]
fn a_relative_input_path_is_resolved_against_the_current_directory() {
    // Canonical, because the current directory comes back with its
    // symlinks resolved (`/var` is `/private/var` on a Mac), and the box
    // must be opened by the same spelling for the prefix to match.
    let d = dir("relative_input").canonicalize().unwrap();
    let inside = put(&d, "box/files/u1/x.pdf", b"inside");
    let outside = put(&d, "x.txt", b"outside");
    let mut e = box_in(&d.join("box"));

    let was = std::env::current_dir().unwrap();
    std::env::set_current_dir(&d).unwrap();
    let a = e.add_file("box/files/u1/x.pdf", T0).unwrap();
    let b = e.add_file("./x.txt", T0 + 1).unwrap();
    std::env::set_current_dir(was).unwrap();

    assert_eq!(stored(&e, a), "files/u1/x.pdf");
    assert_eq!(e.path_of(a).unwrap(), Some(s(&inside)));
    assert_eq!(stored(&e, b), s(&outside), "outside the box: whole, without the ./");
    assert_eq!(e.resync_file(a, T0 + 2).unwrap(), Resync::Unchanged);
    assert_eq!(e.resync_file(b, T0 + 3).unwrap(), Resync::Unchanged);

    let _ = std::fs::remove_dir_all(&d);
}

/// `box/../outside.txt` starts with the box's folder and is not in it.
/// Stored relative, it would read back as a path that climbs out of
/// wherever the box moves to next.
#[test]
fn a_path_that_climbs_out_of_the_box_folder_is_remembered_whole() {
    let d = dir("climb");
    put(&d, "outside.txt", b"bytes");
    let mut e = box_in(&d.join("box"));
    let climbing = s(&d.join("box/../outside.txt"));
    let id = e.add_file(&climbing, T0).unwrap();

    assert_eq!(stored(&e, id), climbing);
    assert_eq!(e.resync_file(id, T0 + 1).unwrap(), Resync::Unchanged);

    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn a_changed_resync_keeps_the_place_relative() {
    let d = dir("changed_relative");
    let file = put(&d, "files/u1/notes.md", b"first draft");
    let mut e = box_in(&d);
    let id = e.add_file(&s(&file), T0).unwrap();

    std::fs::write(&file, "second draft").unwrap();
    assert!(matches!(e.resync_file(id, T0 + 1).unwrap(), Resync::Changed(_)));
    assert_eq!(stored(&e, id), "files/u1/notes.md", "the new bytes' row is relative too");
    assert_eq!(e.path_of(id).unwrap(), Some(s(&file)));

    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn file_alerts_resolve_places_in_a_moved_box() {
    let d = dir("alerts_moved");
    let before = d.join("old");
    let file = put(&before, "files/u1/invoice.pdf", b"bytes");
    {
        let mut e = box_in(&before);
        e.add_file(&s(&file), T0).unwrap();
    }
    let after = d.join("new");
    std::fs::rename(&before, &after).unwrap();
    let e = box_in(&after);

    assert!(e.file_alerts().unwrap().is_empty(), "it is there, under the new folder");

    let moved = after.join("files/u1/invoice.pdf");
    std::fs::remove_file(&moved).unwrap();
    let alerts = e.file_alerts().unwrap();
    assert_eq!(alerts.len(), 1);
    assert_eq!(alerts[0].why, "gone");
    assert_eq!(alerts[0].path, Some(s(&moved)), "whole, and where it looked");

    let _ = std::fs::remove_dir_all(&d);
}

// ---- a file that holds text -------------------------------------------
//
// The owner, 2026-10-01: files are opened if they contain text, which is
// edited as a note. `text_of` is the one judge of "contains text".

/// `text_of` on these bytes, from a file of their own.
fn text(name: &str, bytes: &[u8]) -> Option<String> {
    let d = dir(&format!("text_{name}"));
    let p = put(&d, "f", bytes);
    let t = text_of(&s(&p)).unwrap();
    let _ = std::fs::remove_dir_all(&d);
    t
}

#[test]
fn utf8_is_text() {
    let words = "# Linux Installation\n\nPartition first. Ünïcode is fine — so are dashes.";
    assert_eq!(text("utf8", words.as_bytes()).as_deref(), Some(words));
}

#[test]
fn a_byte_order_mark_is_dropped() {
    assert_eq!(text("bom", b"\xEF\xBB\xBFhello").as_deref(), Some("hello"));
}

#[test]
fn every_line_ending_becomes_a_newline() {
    assert_eq!(text("endings", b"windows\r\nold mac\runix\n").as_deref(), Some("windows\nold mac\nunix\n"));
}

#[test]
fn a_nul_byte_is_not_text() {
    // A PNG's first sixteen bytes. Its NUL says "binary" even where the
    // rest might have passed for text.
    let png = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR";
    assert_eq!(text("png", png), None);
    // And valid UTF-8 with a NUL in it is still not something to edit.
    assert_eq!(text("nul", b"abc\x00def"), None);
}

#[test]
fn bytes_that_are_not_utf8_are_not_text() {
    // "café" in Latin-1. Guessing an encoding would put the guess in
    // someone's note; refusing leaves the file to the app that made it.
    assert_eq!(text("latin1", b"caf\xe9"), None);
}

#[test]
fn text_is_capped_without_reading_past_it() {
    assert_eq!(text("at_cap", &vec![b'a'; TEXT_CAP as usize]).map(|t| t.len()), Some(TEXT_CAP as usize));
    assert_eq!(text("over_cap", &vec![b'a'; TEXT_CAP as usize + 1]), None);
}

#[test]
fn an_empty_file_is_empty_text() {
    assert_eq!(text("empty", b"").as_deref(), Some(""));
}

#[test]
fn an_unreadable_path_is_an_error_not_an_answer() {
    assert!(text_of("/no/such/file/anywhere").is_err());
    let d = dir("text_folder");
    assert!(text_of(&s(&d)).is_err(), "a folder is not a file");
    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn a_notes_name_is_the_files_name_without_its_extension() {
    assert_eq!(note_name("Linux Installation.md"), "Linux Installation");
    assert_eq!(note_name("README"), "README");
    assert_eq!(note_name(".bashrc"), ".bashrc", "a dot file is all name");
    assert_eq!(note_name("a.b.txt"), "a.b", "only the last extension");
}

/// A file named `name`, holding `bytes`, read by the rule.
fn text_named(name: &str, bytes: &[u8]) -> Option<String> {
    let d = dir(&format!("named_{}", name.replace(['.', ' '], "_")));
    let p = put(&d, name, bytes);
    let t = text_of(&s(&p)).unwrap();
    let _ = std::fs::remove_dir_all(&d);
    t
}

/// **Words wrapped in another app's markup are not a note** (review,
/// 2026-10-02): an RTF letter, a spreadsheet's CSV, a drawing's SVG and a
/// web page are all UTF-8, and each arrived as a note of raw markup with
/// the file itself gone. They stay files, and open in the app they belong
/// to.
#[test]
fn a_rich_format_is_a_file_not_a_note() {
    assert_eq!(text_named("letter.rtf", br"{\rtf1\ansi Dear Sam}"), None);
    assert_eq!(text_named("budget.csv", b"item,cost\nmilk,2\n"), None);
    assert_eq!(text_named("dot.svg", b"<svg></svg>"), None);
    assert_eq!(text_named("page.html", b"<p>hi</p>"), None);
    assert_eq!(text_named("Page.HTM", b"<p>hi</p>"), None, "whatever the case");
    assert_eq!(text_named("plain.pdf", b"%PDF-1.4\n1 0 obj\n"), None, "an all-ASCII PDF");
    assert_eq!(text_named("plan.txt", b"plan").as_deref(), Some("plan"));
    assert_eq!(text_named("notes.md", b"# notes").as_deref(), Some("# notes"));
}

/// An empty file is a note only when its name says it holds plain words:
/// an empty .docx is a document nobody has written yet, not a note.
#[test]
fn an_empty_file_is_text_only_when_its_name_says_so() {
    assert_eq!(text_named("empty.txt", b"").as_deref(), Some(""));
    assert_eq!(text_named("empty.md", b"").as_deref(), Some(""));
    assert_eq!(text_named("empty", b"").as_deref(), Some(""));
    assert_eq!(text_named("empty.docx", b""), None);
}

/// **A dot inside the words is not an extension** (review, 2026-10-02):
/// "Version 2.0 notes" was cut to "Version 2", "Dr. Who quotes" to "Dr".
#[test]
fn a_dot_inside_the_words_stays_in_the_name() {
    assert_eq!(note_name("Version 2.0 notes"), "Version 2.0 notes");
    assert_eq!(note_name("Dr. Who quotes"), "Dr. Who quotes");
    assert_eq!(note_name("Letter.final.md"), "Letter.final");
    assert_eq!(note_name("Release 2.0"), "Release 2.0");
    assert_eq!(note_name("song.mp3"), "song");
}

// ---- a file becomes a note --------------------------------------------

/// Every cell one thing holds, as (property, value), without the dots —
/// what "the same thing" means after an undo has rewritten them.
fn cells(e: &Engine, id: EntityId) -> Vec<(EntityId, Value)> {
    let mut out: Vec<_> = e.cells_of(id).unwrap().into_iter().map(|(p, _, v)| (p, v)).collect();
    out.sort_by_key(|(p, _)| p.0);
    out
}

#[test]
fn a_file_becomes_a_note_in_one_action() {
    let d = dir("into_note");
    let file = put(&d, "files/u1/Linux Installation.md", b"Partition first");
    let mut e = box_in(&d);
    let id = e.add_file(&s(&file), T0).unwrap();
    let groups = e.group_count().unwrap();
    let spans = vec![Span::text("Partition first")];

    e.file_into_note(id, spans.clone(), T0 + 1).unwrap();

    assert_eq!(e.group_count().unwrap(), groups + 1, "one action");
    assert_eq!(e.groups().unwrap().last().unwrap().action, action::SET, "a change to a thing");
    assert_eq!(e.kind_of(id).unwrap(), Some(kind::NOTE));
    assert_eq!(e.content(id).unwrap().0, spans);
    assert!(e.cell(id, prop::FILE).unwrap().is_empty(), "no longer a file");
    assert!(e.cell(id, prop::FORMAT).unwrap().is_empty());
    assert_eq!(e.name(id).unwrap().as_deref(), Some("Linux Installation"));
    assert_eq!(std::fs::read(&file).unwrap(), b"Partition first", "the file is never written");

    let _ = std::fs::remove_dir_all(&d);
}

/// A name someone typed is theirs: only the file's own extension comes
/// off it (review, 2026-10-02: "Letter to Dr. Who" became "Letter to Dr").
#[test]
fn only_the_files_own_extension_leaves_the_name() {
    let d = dir("into_note_named");
    let file = put(&d, "files/u1/letter.txt", b"Dear Sam");
    let mut e = box_in(&d);
    let id = e.add_file(&s(&file), T0).unwrap();
    e.set(id, prop::NAME, Value::Text("Letter to Dr. Who".into()), T0 + 1).unwrap();
    e.file_into_note(id, vec![Span::text("Dear Sam")], T0 + 2).unwrap();
    assert_eq!(e.name(id).unwrap().as_deref(), Some("Letter to Dr. Who"));
    let _ = std::fs::remove_dir_all(&d);
}

/// A task that carries a text file keeps being a task: its words move in,
/// its kind is its own (review, 2026-10-02).
#[test]
fn a_task_with_a_file_stays_a_task() {
    let d = dir("into_note_task");
    let file = put(&d, "files/u1/todo.txt", b"milk");
    let mut e = box_in(&d);
    let id = e.add_file(&s(&file), T0).unwrap();
    e.set(id, prop::KIND, Value::Ref(kind::TASK), T0 + 1).unwrap();
    e.file_into_note(id, vec![Span::text("milk")], T0 + 2).unwrap();
    assert_eq!(e.kind_of(id).unwrap(), Some(kind::TASK));
    assert_eq!(e.content(id).unwrap().0, vec![Span::text("milk")]);
    assert!(e.cell(id, prop::FILE).unwrap().is_empty());
    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn one_undo_puts_the_file_back_exactly() {
    let d = dir("into_note_undo");
    let file = put(&d, "files/u1/todo.txt", b"milk");
    let mut e = box_in(&d);
    let id = e.add_file(&s(&file), T0).unwrap();
    let before = cells(&e, id);

    e.file_into_note(id, vec![Span::text("milk")], T0 + 1).unwrap();
    assert_ne!(cells(&e, id), before);
    e.undo(T0 + 2).unwrap();

    assert_eq!(cells(&e, id), before);
    assert_eq!(e.path_of(id).unwrap(), Some(s(&file)), "and it still knows where it is");

    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn a_file_with_no_extension_keeps_its_name() {
    let d = dir("into_note_readme");
    let file = put(&d, "files/u1/README", b"read me");
    let mut e = box_in(&d);
    let id = e.add_file(&s(&file), T0).unwrap();

    e.file_into_note(id, vec![Span::text("read me")], T0 + 1).unwrap();
    assert_eq!(e.name(id).unwrap().as_deref(), Some("README"));

    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn only_a_file_in_use_becomes_a_note() {
    let d = dir("into_note_refused");
    let file = put(&d, "files/u1/a.txt", b"words");
    let mut e = box_in(&d);
    let note = e.create(kind::NOTE, Some("Already a note"), T0).unwrap();
    let trashed = e.add_file(&s(&file), T0 + 1).unwrap();
    e.trash(trashed, T0 + 2).unwrap();
    let groups = e.group_count().unwrap();

    for id in [note, trashed, EntityId([0x77; 16])] {
        let refused = e.file_into_note(id, vec![Span::text("words")], T0 + 3);
        assert!(matches!(refused, Err(ContentError::Invalid)), "{refused:?}");
    }
    assert_eq!(e.group_count().unwrap(), groups, "nothing written");
    assert_eq!(e.kind_of(trashed).unwrap(), Some(kind::FILE));

    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn a_file_is_not_turned_into_a_note_with_a_link_to_nothing() {
    let d = dir("into_note_ghost");
    let file = put(&d, "files/u1/a.txt", b"words");
    let mut e = box_in(&d);
    let id = e.add_file(&s(&file), T0).unwrap();
    let before = cells(&e, id);

    let refused = e.file_into_note(id, vec![Span::Ref(EntityId([0x99; 16]))], T0 + 1);
    assert!(matches!(refused, Err(ContentError::Invalid)), "{refused:?}");
    assert_eq!(cells(&e, id), before, "still the file it was");

    let _ = std::fs::remove_dir_all(&d);
}
