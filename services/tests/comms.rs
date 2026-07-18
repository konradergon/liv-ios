//! Comms (P20g, BP-15): message ingestion. One batch = ONE transaction =
//! one undo; external-id is the dedupe key — re-import is a no-op, and a
//! REFRESH updates only the feed-owned cells (from/sent/body/source),
//! never yours (subjects, a cleared unread). Senders resolve to person
//! entities when a name matches; unresolved senders stay feed-owned text.

use lotus_core::*;
use lotus_services::comms::{self, MessageDrop};
use lotus_services::content;

fn boxed(name: &str) -> (Session, std::path::PathBuf) {
    let path = std::env::temp_dir().join(format!("lotus_comms_{name}.log"));
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

fn drop_a() -> MessageDrop {
    MessageDrop {
        external_id: "slack:C61A9/p1720939".into(),
        from: "Steven Åkesson".into(),
        source: "Slack · #liv-dev".into(),
        sent: Some("2026-07-14 08:41".into()),
        body: "swishar 60 ikväll, resten efter helgen".into(),
    }
}

fn messages(store: &Store) -> Vec<&Entity> {
    let message_type = lotus_services::content::find_type(store, "message").unwrap();
    store
        .entities()
        .filter(|e| !e.trashed && e.has(props::TYPE, &Value::Reference(message_type)))
        .collect()
}

#[test]
fn one_batch_is_one_transaction_and_one_undo() {
    let (mut session, path) = boxed("batch");
    let outcome = comms::import_messages(
        &mut session,
        &[drop_a(), MessageDrop {
            external_id: "mail:114".into(),
            from: "SSK Fakturor".into(),
            source: "Mail · SSK".into(),
            sent: Some("2026-07-13".into()),
            body: "Faktura #114 — påminnelse, förfaller 18 jul".into(),
        }],
    )
    .unwrap();
    assert_eq!(outcome.created, 2);
    assert_eq!(messages(session.store()).len(), 2);

    // The type + property births ride the SAME transaction: one undo
    // unwinds the entire batch, plumbing included.
    session.undo(Author::User).unwrap();
    let store = session.store();
    assert!(lotus_services::content::find_type(store, "message").is_none());
    cleanup(&path);
}

#[test]
fn reimport_is_a_no_op_and_refresh_updates_only_feed_owned() {
    let (mut session, path) = boxed("upsert");
    comms::import_messages(&mut session, &[drop_a()]).unwrap();
    let id = messages(session.store())[0].id;

    // Byte-identical re-import: nothing changes, nothing is written.
    let outcome = comms::import_messages(&mut session, &[drop_a()]).unwrap();
    assert_eq!((outcome.created, outcome.updated, outcome.skipped), (0, 0, 1));

    // The user files it (yours) and reads it (unread cleared). Subjects
    // is schema-on-read — birthed at first use, like the shell's door.
    content::birth_property(&mut session, "subjects", "text").unwrap();
    content::set_property(&mut session, id, "subjects", "money").unwrap();
    content::set_property(&mut session, id, "unread", "false").unwrap();

    // The feed edits the body (a refresh): feed-owned updates, yours stay.
    let mut edited = drop_a();
    edited.body = "swishar 60 ikväll — resten på måndag".into();
    let outcome = comms::import_messages(&mut session, &[edited]).unwrap();
    assert_eq!((outcome.created, outcome.updated, outcome.skipped), (0, 1, 0));

    let store = session.store();
    let row = store.get(id).unwrap();
    let content_prop = lotus_services::property_id(store, "content").unwrap();
    assert!(matches!(
        row.get(content_prop),
        Some(Value::Text(t)) if t.contains("måndag")
    ));
    let subjects = lotus_services::property_id(store, "subjects").unwrap();
    assert!(row.get(subjects).is_some(), "yours: subjects survived the refresh");
    let unread = lotus_services::property_id(store, "unread").unwrap();
    assert!(
        matches!(row.get(unread), Some(Value::Bool(false))),
        "yours: a cleared unread is never re-set by a refresh"
    );
    cleanup(&path);
}

#[test]
fn senders_resolve_to_person_entities_when_a_name_matches() {
    let (mut session, path) = boxed("resolve");
    // A person named exactly like the sender.
    let person = content::create_note(&mut session, DateTime::at(2026, 7, 14, 9, 0)).unwrap();
    content::set_type(&mut session, person, "person").unwrap();
    content::set_property(&mut session, person, "name", "Steven Åkesson").unwrap();

    comms::import_messages(&mut session, &[drop_a()]).unwrap();
    let store = session.store();
    let row = messages(store)[0];
    let from = lotus_services::property_id(store, "from").unwrap();
    assert!(
        matches!(row.get(from), Some(Value::Reference(target)) if *target == person),
        "the sender resolved to the person entity"
    );

    // An unresolved sender keeps only the feed-owned label.
    comms::import_messages(&mut session, &[MessageDrop {
        external_id: "slack:X/1".into(),
        from: "Unknown Sender".into(),
        source: "Slack · #random".into(),
        sent: None,
        body: "hello".into(),
    }])
    .unwrap();
    let store = session.store();
    let unknown = messages(store).into_iter().find(|e| {
        matches!(e.get(props::EXTERNAL_ID), Some(Value::Text(x)) if x == "slack:X/1")
    });
    let unknown = unknown.unwrap();
    assert!(unknown.get(from).is_none(), "no guessed reference");
    let label = lotus_services::property_id(store, "from-label").unwrap();
    assert!(matches!(unknown.get(label), Some(Value::Text(t)) if t == "Unknown Sender"));
    cleanup(&path);
}
