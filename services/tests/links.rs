//! Links, both directions — one mechanism (feature-map §6).
//!
//! A `[[ ]]` typed in a body and a link picked in properties are the same
//! edge: a `Ref` span inside the content cell, or a `related` cell. Both
//! land in the core's backlink index, so "what points at me" is a lookup,
//! never a scan of every body. `links()` is the one reader both ends of
//! the UI use.

use liv_core::*;
use liv_services::links::links;
use liv_services::{content, seed_if_fresh};

fn fresh(name: &str) -> (std::path::PathBuf, Session) {
    let dir = std::env::temp_dir().join(format!("liv_t_{name}"));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("box.log");
    let mut session = Session::open(&path).unwrap();
    seed_if_fresh(&mut session).unwrap();
    (path, session)
}

fn cleanup(path: &std::path::Path) {
    if let Some(dir) = path.parent() {
        let _ = std::fs::remove_dir_all(dir);
    }
}

fn note(session: &mut Session, name: &str) -> Id {
    let id = content::create_note(session, DateTime::at(2026, 8, 17, 9, 0)).unwrap();
    content::set_property(session, id, "name", name).unwrap();
    id
}

/// Put `[[target]]` in `source`'s body — the editor's write, minus the editor.
fn body_link(session: &mut Session, source: Id, before: &str, target: Id) {
    let spans = vec![Span::text(before), Span::Ref(target)];
    content::set_content(session, source, spans, 0).unwrap();
}

fn trash(session: &mut Session, id: Id) {
    session
        .commit(vec![Command::Trash { entity: id }], "trash", Author::User)
        .unwrap();
}

fn out_ids(session: &Session, id: Id) -> Vec<Id> {
    links(session.store(), id).out.iter().map(|l| l.id).collect()
}

fn in_ids(session: &Session, id: Id) -> Vec<Id> {
    links(session.store(), id).inbound.iter().map(|l| l.id).collect()
}

#[test]
fn a_picked_link_and_a_typed_link_are_the_same_edge() {
    let (path, mut session) = fresh("links_same_edge");
    let hub = note(&mut session, "Hub");
    let picked = note(&mut session, "Picked");
    let typed = note(&mut session, "Typed");

    // Properties: pick a link. Body: type one.
    content::add_cell(&mut session, hub, "related", &format!("#{picked}")).unwrap();
    body_link(&mut session, hub, "see ", typed);

    let both = links(session.store(), hub);
    assert_eq!(
        both.out.iter().map(|l| l.id).collect::<Vec<_>>(),
        vec![picked, typed],
        "both ends of the UI produce one outgoing list"
    );
    // Told apart by WHERE they live, not by what they are.
    assert!(!both.out[0].from_body, "a picked link is a cell");
    assert_eq!(both.out[0].property, "related");
    assert!(both.out[1].from_body, "a typed link lives in the body");
    assert_eq!(both.out[1].name, "Typed", "a link carries the target's name");

    // And each target sees the hub coming back, whichever door was used.
    assert_eq!(in_ids(&session, picked), vec![hub]);
    assert_eq!(in_ids(&session, typed), vec![hub]);
    assert!(in_ids(&session, hub).is_empty(), "nothing points at the hub yet");

    cleanup(&path);
}

#[test]
fn unlinking_removes_the_edge_both_ways() {
    let (path, mut session) = fresh("links_unlink");
    let a = note(&mut session, "A");
    let b = note(&mut session, "B");
    content::add_cell(&mut session, a, "related", &format!("#{b}")).unwrap();
    assert_eq!(out_ids(&session, a), vec![b]);

    content::remove_cell(&mut session, a, "related", &format!("#{b}")).unwrap();
    assert!(out_ids(&session, a).is_empty(), "the link is gone");
    assert!(in_ids(&session, b).is_empty(), "and so is the backlink");
    assert!(session.store().get(b).is_some(), "unlinking never deletes");

    cleanup(&path);
}

#[test]
fn a_body_link_disappears_with_its_brackets() {
    let (path, mut session) = fresh("links_body_edit");
    let a = note(&mut session, "A");
    let b = note(&mut session, "B");
    body_link(&mut session, a, "see ", b);
    assert_eq!(in_ids(&session, b), vec![a]);

    // The body is rewritten without the token — an ordinary edit.
    let print = content::content_fingerprint(
        session.store().get(a).and_then(|e| e.get(props::CONTENT)));
    content::set_content(&mut session, a, vec![Span::text("see nothing")], print).unwrap();
    assert!(out_ids(&session, a).is_empty());
    assert!(in_ids(&session, b).is_empty(), "no orphan backlink survives");

    cleanup(&path);
}

#[test]
fn one_target_named_twice_is_one_row() {
    let (path, mut session) = fresh("links_dedupe");
    let a = note(&mut session, "A");
    let b = note(&mut session, "B");
    // Picked in properties AND typed twice in the body.
    content::add_cell(&mut session, a, "related", &format!("#{b}")).unwrap();
    content::set_content(
        &mut session,
        a,
        vec![Span::text("see "), Span::Ref(b), Span::text(" and "), Span::Ref(b)],
        0,
    )
    .unwrap();

    assert_eq!(out_ids(&session, a), vec![b], "one edge, one row");
    let out = links(session.store(), a).out;
    assert!(!out[0].from_body, "the removable one wins the row");
    assert_eq!(in_ids(&session, b), vec![a], "and one row on the way back");

    cleanup(&path);
}

#[test]
fn plumbing_never_shows_up_as_a_backlink() {
    let (path, mut session) = fresh("links_plumbing");
    let a = note(&mut session, "A");
    let b = note(&mut session, "B");
    // A layout layer holds its tabs as `related` cells — backstage
    // furniture that must never read as "linked from".
    content::create_layer(
        &mut session,
        "Morning",
        None,
        &[a, b],
        DateTime::at(2026, 8, 17, 9, 0),
    )
    .unwrap();
    assert!(in_ids(&session, a).is_empty(), "a layer is not a link");

    // A list, though, is a thing a person made and named.
    let list = content::create_list(
        &mut session, "Reading queue", DateTime::at(2026, 8, 17, 9, 0)).unwrap();
    content::add_cell(&mut session, list, "related", &format!("#{a}")).unwrap();
    assert_eq!(in_ids(&session, a), vec![list]);

    cleanup(&path);
}

#[test]
fn filing_is_not_a_link() {
    let (path, mut session) = fresh("links_filing");
    let a = note(&mut session, "A");
    let project = note(&mut session, "Kitchen rebuild");
    content::birth_property(&mut session, "project", "reference").unwrap();
    content::set_property(&mut session, a, "project", &format!("#{project}")).unwrap();

    // Filing has its own rows, and a project's members are what a filter
    // is for. The links section stays about links.
    assert!(out_ids(&session, a).is_empty());
    assert!(in_ids(&session, project).is_empty());

    cleanup(&path);
}

#[test]
fn a_trashed_end_drops_out_of_both_lists() {
    let (path, mut session) = fresh("links_trash");
    let a = note(&mut session, "A");
    let b = note(&mut session, "B");
    content::add_cell(&mut session, a, "related", &format!("#{b}")).unwrap();
    trash(&mut session, b);

    assert!(out_ids(&session, a).is_empty(), "a trashed target is not a link");
    let c = note(&mut session, "C");
    content::add_cell(&mut session, c, "related", &format!("#{a}")).unwrap();
    trash(&mut session, c);
    assert!(in_ids(&session, a).is_empty(), "nor is a trashed source");

    cleanup(&path);
}

#[test]
fn a_link_carries_what_a_row_needs() {
    let (path, mut session) = fresh("links_row");
    let a = note(&mut session, "A");
    let task = content::create_task(&mut session, DateTime::at(2026, 8, 17, 9, 0)).unwrap();
    content::set_property(&mut session, task, "name", "Ring the plumber").unwrap();
    content::add_cell(&mut session, a, "related", &format!("#{task}")).unwrap();

    let row = &links(session.store(), a).out[0];
    assert_eq!(row.id, task);
    assert_eq!(row.name, "Ring the plumber");
    assert!(row.kinds.iter().any(|k| k == "task"), "the row knows its glyph: {:?}", row.kinds);

    // An unnamed target still renders as something.
    let bare = content::create_note(&mut session, DateTime::at(2026, 8, 17, 9, 0)).unwrap();
    content::add_cell(&mut session, a, "related", &format!("#{bare}")).unwrap();
    let rows = links(session.store(), a).out;
    assert_eq!(rows[1].id, bare);
    assert!(!rows[1].name.is_empty(), "never an empty row");

    cleanup(&path);
}

#[test]
fn a_redirected_target_answers_as_the_survivor() {
    let (path, mut session) = fresh("links_redirect");
    let a = note(&mut session, "A");
    let dupe = note(&mut session, "Dupe");
    let survivor = note(&mut session, "Survivor");
    content::add_cell(&mut session, a, "related", &format!("#{dupe}")).unwrap();
    session
        .commit(
            vec![Command::Redirect { entity: dupe, to: survivor, before: NONE }],
            "merge",
            Author::User,
        )
        .unwrap();

    assert_eq!(out_ids(&session, a), vec![survivor], "the link follows the merge");
    assert_eq!(in_ids(&session, survivor), vec![a]);

    cleanup(&path);
}

#[test]
fn nothing_points_at_itself() {
    let (path, mut session) = fresh("links_self");
    let a = note(&mut session, "A");
    // The write side already refuses it (content::add_cell)…
    assert!(content::add_cell(&mut session, a, "related", &format!("#{a}")).is_err());
    // …and a body that names itself is words, not a row.
    body_link(&mut session, a, "me: ", a);

    let both = links(session.store(), a);
    assert!(both.out.is_empty(), "a self-link is not an outgoing row");
    assert!(both.inbound.is_empty(), "a self-link is not a backlink row");

    cleanup(&path);
}
