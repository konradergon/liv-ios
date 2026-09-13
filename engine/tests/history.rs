//! What a note used to say, and what points at what.
//!
//! Two questions off one value. `core/` answers both by scanning: history
//! walks every transaction in the box, and backlinks walk every entity's
//! content cell. Both are *rebuild on read instead of maintain on write*,
//! which `scale.rs` names as the defect this tree has produced four times.
//!
//! So the fold keeps two small tables. Neither holds a value — history
//! holds the DOT of each save and reads the spans back out of the log,
//! because the log is the history and a second copy of it could disagree.

use liv_engine::*;

fn dev(n: u8) -> DeviceId {
    DeviceId([n; 8])
}

const T0: u64 = 1_787_391_635_000;

fn engine() -> Engine {
    Engine::open_in_memory(dev(1)).unwrap()
}

fn note(e: &mut Engine, name: &str) -> EntityId {
    e.create(kind::NOTE, Some(name), T0).unwrap()
}

// ---- history ----------------------------------------------------------

#[test]
fn every_save_is_a_version_newest_first() {
    let mut e = engine();
    let id = note(&mut e, "Roof");
    let one = e.set_content(id, vec![Span::text("one")], 0, T0 + 1).unwrap();
    let two = e.set_content(id, vec![Span::text("two")], one, T0 + 2).unwrap();
    e.set_content(id, vec![Span::text("three")], two, T0 + 3).unwrap();

    let h = e.content_history(id).unwrap();
    assert_eq!(h.len(), 3);
    // NEWEST FIRST — the shell's history card lists the most recent at
    // the top, and reversing a list in Swift is logic in the shell.
    assert_eq!(h[0].spans, vec![Span::text("three")]);
    assert_eq!(h[1].spans, vec![Span::text("two")]);
    assert_eq!(h[2].spans, vec![Span::text("one")]);
    assert_eq!(h[0].at_ms, (T0 + 3) as i64);
}

#[test]
fn a_note_that_was_never_edited_has_no_history() {
    let mut e = engine();
    let id = note(&mut e, "Roof");
    assert!(e.content_history(id).unwrap().is_empty());
    assert!(e.content_history(EntityId([0x99; 16])).unwrap().is_empty());
}

#[test]
fn clearing_a_body_is_not_a_version() {
    // There is nothing to restore from "the user emptied it" — and
    // listing it would put a blank row in the card above the text the
    // user actually wants back.
    let mut e = engine();
    let id = note(&mut e, "Roof");
    let one = e.set_content(id, vec![Span::text("one")], 0, T0 + 1).unwrap();
    e.set_content(id, vec![], one, T0 + 2).unwrap();

    let h = e.content_history(id).unwrap();
    assert_eq!(h.len(), 1, "the save, not the clearing");
    assert_eq!(h[0].spans, vec![Span::text("one")]);
}

/// **An undo is not a version.**
///
/// `core/` skips reversal transactions for the same reason: undoing an
/// edit appends the inverse, which for content is the OLD value written
/// again — a phantom entry identical to one already in the list. The
/// forward edits are the honest history.
#[test]
fn an_undo_does_not_add_a_version() {
    let mut e = engine();
    let id = note(&mut e, "Roof");
    let one = e.set_content(id, vec![Span::text("one")], 0, T0 + 1).unwrap();
    e.set_content(id, vec![Span::text("two")], one, T0 + 2).unwrap();
    assert_eq!(e.content_history(id).unwrap().len(), 2);

    e.undo(T0 + 3).unwrap();
    let h = e.content_history(id).unwrap();
    assert_eq!(h.len(), 2, "still two — the undo put back a value already listed");
    assert_eq!(e.content(id).unwrap().0, vec![Span::text("one")]);

    e.redo(T0 + 4).unwrap();
    assert_eq!(e.content_history(id).unwrap().len(), 2, "and a redo is not one either");
}

#[test]
fn a_version_can_be_put_back_as_an_ordinary_save() {
    // The whole point of the list. Restoring is not a special verb: it is
    // `set_content` of an old version's spans over a freshly read base,
    // appended as a new version. The log is never rewritten.
    let mut e = engine();
    let id = note(&mut e, "Roof");
    let one = e.set_content(id, vec![Span::text("one")], 0, T0 + 1).unwrap();
    e.set_content(id, vec![Span::text("two")], one, T0 + 2).unwrap();

    let old = e.content_history(id).unwrap().pop().unwrap();
    let base = e.content(id).unwrap().1;
    e.set_content(id, old.spans.clone(), base, T0 + 3).unwrap();

    assert_eq!(e.content(id).unwrap().0, vec![Span::text("one")]);
    assert_eq!(e.content_history(id).unwrap().len(), 3, "a restore IS a version");
}

/// **Replay REPAIRS these tables, it does not merely re-agree with them.**
///
/// The first version of this test wrote a history, replayed, and asserted
/// it was unchanged — and passed with the new tables left out of the drop
/// list entirely. It could not fail: the rows are keyed by the writing
/// dot and the fold uses `INSERT OR REPLACE`, so re-folding over rows that
/// were never dropped writes exactly the same rows.
///
/// That is the wrong question. `replay` exists because a bug in the fold
/// must be FIXABLE (`core.md` §1) — the log is untouched, the tables are a
/// consequence, so a corrected fold can simply be re-run. A table that is
/// not dropped keeps whatever the old fold put there. So: corrupt them by
/// hand, the way a bad fold would have, and assert the corruption is gone.
#[test]
fn a_replay_repairs_a_wrong_history_and_wrong_links() {
    let mut e = engine();
    let id = note(&mut e, "Roof");
    let to = note(&mut e, "Ferry times");
    let one = e.set_content(id, vec![Span::text("one")], 0, T0 + 1).unwrap();
    e.set_content(id, vec![Span::Ref(to)], one, T0 + 2).unwrap();

    let history = e.content_history(id).unwrap();
    let links = e.links_to(to).unwrap();
    assert_eq!(history.len(), 2);
    assert_eq!(links, vec![id]);

    // A version that never happened, and a link to nothing.
    e.conn()
        .execute(
            "INSERT INTO edits(entity, prop, device, seq, at_ms) VALUES (?1, ?2, ?3, 9999, 1)",
            rusqlite::params![&id.0[..], &prop::BODY.0[..], &dev(3).0[..]],
        )
        .unwrap();
    e.conn()
        .execute(
            "INSERT INTO links(src, prop, device, seq, ord, dst)
             VALUES (?1, ?2, ?3, 9999, 0, ?1)",
            rusqlite::params![&id.0[..], &prop::BODY.0[..], &dev(3).0[..]],
        )
        .unwrap();
    assert_eq!(e.links_to(id).unwrap(), vec![id], "the corruption took");

    e.replay().unwrap();

    assert_eq!(e.content_history(id).unwrap(), history, "the phantom version is gone");
    assert!(e.links_to(id).unwrap().is_empty(), "and the phantom link");
    assert_eq!(e.links_to(to).unwrap(), links, "while the real one stands");
}

// ---- links ------------------------------------------------------------

#[test]
fn a_body_reference_is_a_link_in_both_directions() {
    let mut e = engine();
    let from = note(&mut e, "Trip");
    let to = note(&mut e, "Ferry times");
    e.set_content(from, vec![Span::text("see "), Span::Ref(to)], 0, T0 + 1).unwrap();

    assert_eq!(e.links_from(from).unwrap(), vec![to]);
    assert_eq!(e.links_to(to).unwrap(), vec![from], "and what points HERE");
    assert!(e.links_to(from).unwrap().is_empty());
}

#[test]
fn editing_a_body_moves_its_links_with_it() {
    let mut e = engine();
    let from = note(&mut e, "Trip");
    let a = note(&mut e, "Ferry times");
    let b = note(&mut e, "Packing");

    let fp = e.set_content(from, vec![Span::Ref(a)], 0, T0 + 1).unwrap();
    assert_eq!(e.links_to(a).unwrap(), vec![from]);

    e.set_content(from, vec![Span::Ref(b)], fp, T0 + 2).unwrap();
    assert!(e.links_to(a).unwrap().is_empty(), "the old link went with the old body");
    assert_eq!(e.links_to(b).unwrap(), vec![from]);
}

#[test]
fn clearing_a_body_takes_its_links() {
    let mut e = engine();
    let from = note(&mut e, "Trip");
    let to = note(&mut e, "Ferry times");
    let fp = e.set_content(from, vec![Span::Ref(to)], 0, T0 + 1).unwrap();

    e.set_content(from, vec![], fp, T0 + 2).unwrap();
    assert!(e.links_to(to).unwrap().is_empty());
    assert!(e.links_from(from).unwrap().is_empty());
}

#[test]
fn one_note_naming_another_twice_is_one_link() {
    // The Links panel lists things, not mentions. Two `[[Ferry]]` tokens
    // in one paragraph are one relationship.
    let mut e = engine();
    let from = note(&mut e, "Trip");
    let to = note(&mut e, "Ferry times");
    e.set_content(
        from,
        vec![Span::Ref(to), Span::text(" and again "), Span::Ref(to)],
        0,
        T0 + 1,
    )
    .unwrap();

    assert_eq!(e.links_from(from).unwrap(), vec![to]);
    assert_eq!(e.links_to(to).unwrap(), vec![from]);
}

#[test]
fn links_are_in_reading_order() {
    // The order they appear in the body, which is the order the panel
    // shows them — a set would sort by id, which is creation order and
    // means nothing to a reader.
    let mut e = engine();
    let from = note(&mut e, "Trip");
    let a = note(&mut e, "A");
    let b = note(&mut e, "B");
    let c = note(&mut e, "C");
    e.set_content(from, vec![Span::Ref(c), Span::Ref(a), Span::Ref(b)], 0, T0 + 1)
        .unwrap();

    assert_eq!(e.links_from(from).unwrap(), vec![c, a, b]);
}

#[test]
fn an_undone_save_takes_its_links_back() {
    let mut e = engine();
    let from = note(&mut e, "Trip");
    let to = note(&mut e, "Ferry times");
    e.set_content(from, vec![Span::Ref(to)], 0, T0 + 1).unwrap();
    assert_eq!(e.links_to(to).unwrap(), vec![from]);

    e.undo(T0 + 2).unwrap();
    assert!(e.links_to(to).unwrap().is_empty(), "the body went, so the link did");
}
