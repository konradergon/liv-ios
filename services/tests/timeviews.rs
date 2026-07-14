//! Seeds II (P18d): time entries (logged whole, at stop), saved views (the
//! P13 remainder), and widgets (the board as small entities). All WORKING
//! backstage; totals/projections computed on read, stored nowhere.

use lotus_core::*;
use lotus_services::{content, property_id, timeviews};

fn boxed(name: &str) -> (Session, std::path::PathBuf) {
    let path = std::env::temp_dir().join(format!("lotus_timeviews_{name}.log"));
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

fn capture(session: &mut Session, text: &str) -> Id {
    lotus_services::capture(session, text, DateTime::at(2026, 7, 14, 9, 0)).unwrap()
}

#[test]
fn time_entries_log_whole_intervals_and_totals_tolerate_overlap() {
    let (mut session, path) = boxed("time");
    let project = capture(&mut session, "thesis work");

    // One closed interval, one commit: 09:00 → 10:30 = 90 minutes.
    let entry = content::log_time(
        &mut session, project,
        DateTime::at(2026, 7, 14, 9, 0),
        DateTime::at(2026, 7, 14, 10, 30),
    )
    .unwrap();
    let store = session.store();
    let row = store.get(entry).unwrap();
    assert!(row.has(props::WORKING, &Value::Bool(true)), "records are backstage");
    let target_prop = property_id(store, "target").unwrap();
    assert!(row.has(target_prop, &Value::Reference(project)));

    // A CLI may legally append an OVERLAPPING entry — totals must tolerate it
    // (single-active is a SHELL invariant, not a core law): 10:00 → 11:00.
    content::log_time(
        &mut session, project,
        DateTime::at(2026, 7, 14, 10, 0),
        DateTime::at(2026, 7, 14, 11, 0),
    )
    .unwrap();

    let summary = timeviews::time_totals(session.store(), 20260714);
    assert_eq!(summary.totals.len(), 1);
    assert_eq!(summary.totals[0].target, project);
    assert_eq!(summary.totals[0].minutes, 150, "90 + 60, overlap double-counts honestly");
    assert_eq!(summary.entries.len(), 2);

    // A cross-midnight interval never goes negative: 23:30 → 00:30 = 60.
    let other = capture(&mut session, "night shift");
    content::log_time(
        &mut session, other,
        DateTime::at(2026, 7, 13, 23, 30),
        DateTime::at(2026, 7, 14, 0, 30),
    )
    .unwrap();
    let summary = timeviews::time_totals(session.store(), 20260714);
    let night = summary.totals.iter().find(|t| t.target == other).unwrap();
    assert_eq!(night.minutes, 60);

    // A trashed target's entries go dark — skipped, never a panic.
    session.commit(vec![Command::Trash { entity: project }], "trash", Author::User).unwrap();
    let summary = timeviews::time_totals(session.store(), 20260714);
    assert!(summary.totals.iter().all(|t| t.target != project));

    cleanup(&path);
}

#[test]
fn saved_views_round_trip_name_and_query() {
    let (mut session, path) = boxed("views");
    let view = content::create_view(
        &mut session, "Open tasks", "is:task status!=done", DateTime::at(2026, 7, 14, 9, 0),
    )
    .unwrap();

    let store = session.store();
    let row = store.get(view).unwrap();
    assert!(row.has(props::WORKING, &Value::Bool(true)), "views are backstage");
    assert!(matches!(row.get(props::NAME), Some(Value::Text(n)) if n == "Open tasks"));
    let query_prop = property_id(store, "query").expect("query property");
    assert!(row.has(query_prop, &Value::text("is:task status!=done")));

    let views = timeviews::saved_views(store);
    assert_eq!(views.len(), 1);
    assert_eq!(views[0].name, "Open tasks");
    assert_eq!(views[0].query, "is:task status!=done");

    cleanup(&path);
}

#[test]
fn widgets_are_small_entities_born_in_one_commit() {
    let (mut session, path) = boxed("widgets");

    // The first widget on a fresh box lazily births its types in the SAME
    // transaction — one undo removes everything.
    let widget =
        content::add_widget(&mut session, "habits", None, Some(3.0), DateTime::at(2026, 7, 14, 9, 0))
            .unwrap();
    let store = session.store();
    let row = store.get(widget).unwrap();
    assert!(row.has(props::WORKING, &Value::Bool(true)));
    let kind_prop = property_id(store, "widget-kind").expect("widget-kind property");
    assert!(row.has(kind_prop, &Value::text("habits")));
    let span_prop = property_id(store, "span").expect("span property");
    assert!(row.has(span_prop, &Value::Number(3.0)));

    // Orders stack; the projection returns them in order.
    let second =
        content::add_widget(&mut session, "agenda", None, None, DateTime::at(2026, 7, 14, 9, 1))
            .unwrap();
    let widgets = timeviews::board_widgets(session.store());
    assert_eq!(widgets.len(), 2);
    assert_eq!(widgets[0].id, widget);
    assert_eq!(widgets[1].id, second);
    assert!(widgets[0].order < widgets[1].order);
    assert_eq!(widgets[0].kind, "habits");

    // ONE undo unwinds the whole first-widget commit (types included).
    session.undo(Author::User).unwrap(); // removes `second`
    session.undo(Author::User).unwrap(); // removes `widget` + its type births
    let gone = session.store().get(widget).map(|e| e.trashed) != Some(false);
    assert!(gone);

    cleanup(&path);
}
