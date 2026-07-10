//! P11 review fix — the version fence. The `end` key is a log-format
//! addition an older binary would silently DROP on read; its next edit of
//! that cell would then append an end-less RemoveCell that no span-aware
//! build can replay (the review's live-repro brick). So the FIRST span to
//! touch disk bumps the header in place, 1 → 2 (same byte length), and an
//! older binary refuses the box cleanly instead of corrupting it. A box
//! that never writes a span keeps its v1 header — old binaries keep
//! working there.

use lotus_core::*;

fn boxed(name: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("lotus_ver_{name}"));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir.join("box.log")
}

fn cleanup(path: &std::path::Path) {
    if let Some(dir) = path.parent() {
        let _ = std::fs::remove_dir_all(dir);
    }
}

fn header_line(path: &std::path::Path) -> String {
    std::fs::read_to_string(path).unwrap().lines().next().unwrap().to_string()
}

fn add_date(session: &mut Session, value: DateTime) -> Id {
    let e = session.allocate_id();
    session
        .commit(
            vec![
                Command::Create { entity: e },
                Command::AddCell {
                    entity: e,
                    cell: Cell { property: 4401, value: Value::DateTime(value) },
                },
            ],
            "add date",
            Author::User,
        )
        .unwrap();
    e
}

#[test]
fn a_span_free_box_keeps_the_v1_header() {
    let path = boxed("plain");
    let mut session = Session::open(&path).unwrap();
    add_date(&mut session, DateTime::date(2026, 7, 11));
    drop(session);
    assert_eq!(header_line(&path), r#"{"lotus_log":1}"#, "plain dates never bump");
    cleanup(&path);
}

#[test]
fn the_first_span_write_bumps_the_header_to_2() {
    let path = boxed("bump");
    let mut session = Session::open(&path).unwrap();
    assert_eq!(header_line(&path), r#"{"lotus_log":1}"#, "born at 1");

    let span = DateTime::span(DateTime::date(2026, 7, 11), DateTime::date(2026, 7, 13).civil);
    let e = add_date(&mut session, span);
    assert_eq!(header_line(&path), r#"{"lotus_log":2}"#, "the span fences the box");
    drop(session);

    // The bumped box reopens fine in THIS binary, span intact.
    let session = Session::open(&path).unwrap();
    match session.store().get(e).unwrap().cells.first().map(|c| &c.value) {
        Some(Value::DateTime(d)) => assert_eq!(d.end, Some(DateTime::date(2026, 7, 13).civil)),
        other => panic!("expected the span, got {other:?}"),
    }
    cleanup(&path);
}

#[test]
fn an_undo_of_a_span_add_still_replays() {
    // Our own undo appends the inverse RemoveCell WITH its end — the log
    // stays replayable (the brick only ever came from an end-dropping
    // older binary, which the fence now locks out).
    let path = boxed("undo");
    let mut session = Session::open(&path).unwrap();
    let span = DateTime::span(DateTime::date(2026, 7, 11), DateTime::date(2026, 7, 13).civil);
    let e = add_date(&mut session, span);
    session.undo(Author::User).unwrap();
    drop(session);

    let session = Session::open(&path).unwrap();
    assert!(
        session.store().get(e).unwrap().cells.is_empty(),
        "the span add was undone and the log replays"
    );
    cleanup(&path);
}
