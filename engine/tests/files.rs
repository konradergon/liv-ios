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
