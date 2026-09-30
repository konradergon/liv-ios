//! The CLI seeds a box the app can open, and reads back what the app
//! would draw — through the binary, the way a person and `drive.sh` use it.
//!
//! This is the verification tool's own check (stage 5, 2026-09-29): if it
//! cannot make a task with a due, a status and an area and read those back
//! as the app's rows carry them, nothing it is later used to verify can be
//! believed.

use std::process::Command;

fn liv(db: &std::path::Path, args: &[&str]) -> String {
    let out = Command::new(env!("CARGO_BIN_EXE_liv"))
        .arg("--box")
        .arg(db)
        .args(args)
        .output()
        .expect("the binary runs");
    assert!(
        out.status.success(),
        "liv {} failed: {}",
        args.join(" "),
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8(out.stdout).unwrap().trim().to_owned()
}

fn json(db: &std::path::Path, args: &[&str]) -> serde_json::Value {
    serde_json::from_str(&liv(db, args)).expect("a read answers JSON")
}

fn box_at(name: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("liv_cli_{name}"));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir.join("liv.db")
}

fn row<'a>(snap: &'a serde_json::Value, list: &str, id: &str) -> Option<&'a serde_json::Value> {
    snap[list].as_array().unwrap().iter().find(|r| r["id"] == id)
}

/// A row of the app's index — every live thing, as `liv_view_library`
/// sends it — by id.
fn listed<'a>(snap: &'a serde_json::Value, id: &str) -> Option<&'a serde_json::Value> {
    snap["library"]["all"].as_array().unwrap().iter().find(|r| r["id"] == id)
}

#[test]
fn a_seeded_box_reads_back_as_the_app_draws_it() {
    let db = box_at("seed");

    // An area the way the app makes one, then a task filed under it.
    liv(&db, &["option", "area", "Work"]);
    let task = liv(
        &db,
        &["new", "task", "Send", "the", "invoice", "--due", "2026-09-30 14:30", "--status", "Doing", "--area", "Work"],
    );
    assert_eq!(task.len(), 32, "new prints the id: {task}");

    // A note with words in it, and one thing thrown away and taken back.
    let note = liv(&db, &["new", "note", "Lisbon"]);
    liv(&db, &["content-set", &note, "Three nights, flying out Thursday."]);
    let scrap = liv(&db, &["capture", "call", "the", "roofer"]);
    let scrap: serde_json::Value = serde_json::from_str(&scrap).unwrap();
    let scrap = scrap["id"].as_str().unwrap().to_owned();
    liv(&db, &["trash", &scrap]);
    liv(&db, &["undo"]);

    let snap = json(&db, &["snapshot"]);
    let t = listed(&snap, &task).expect("the task is listed");
    assert_eq!(t["title"], "Send the invoice");
    assert_eq!(t["kind_word"], "task");
    assert_eq!(t["status_word"], "Doing");
    assert_eq!(t["area_word"], "Work");
    // 2026-09-30 is day 20,726; the due is the minute typed, not midnight.
    let day: i64 = 20_726;
    assert_eq!(t["due_ms"].as_i64(), Some(day * 86_400_000 + 14 * 3_600_000 + 30 * 60_000));

    let n = listed(&snap, &note).expect("the note is listed");
    assert_eq!(n["has_body"], true, "the body the CLI wrote is the body the app reads");
    // An unmarked span crosses in its short form, `{"Text": "…"}`.
    assert_eq!(json(&db, &["content", &note])["spans"][0]["Text"], "Three nights, flying out Thursday.");

    assert!(listed(&snap, &scrap).is_some(), "undo put the scrap back");
    assert!(row(&snap, "trash", &scrap).is_none(), "and it is no longer in the trash");

    // One user action, one transaction, counted from the log rather than
    // assumed: the option; the task and its three properties (Work and
    // Doing already exist, so no mint); the note; its body; the capture;
    // the trash; the undo. Ten.
    let groups = liv(&db, &["history"]).lines().count();
    assert_eq!(groups, 10, "one group per write:\n{}", liv(&db, &["history"]));

    let _ = std::fs::remove_dir_all(db.parent().unwrap());
}

#[test]
fn a_part_of_an_id_finds_the_one_thing_it_names() {
    let db = box_at("fragment");
    let a = liv(&db, &["new", "task", "one"]);
    let b = liv(&db, &["new", "task", "two"]);
    // Things made in one second share their first twelve characters, so a
    // prefix is useless; the middle is what differs.
    let part = &b[8..14];
    assert!(!a.contains(part), "the fixture needs a part only b has");
    liv(&db, &["trash", part]);
    let snap = json(&db, &["snapshot"]);
    assert!(row(&snap, "trash", &b).is_some());
    assert!(listed(&snap, &a).is_some());

    let out = Command::new(env!("CARGO_BIN_EXE_liv"))
        .arg("--box")
        .arg(&db)
        .args(["trash", "01a0"])
        .output()
        .unwrap();
    assert!(!out.status.success(), "four characters is not an id");
    let _ = std::fs::remove_dir_all(db.parent().unwrap());
}

#[test]
fn several_come_back_in_one_line_and_one_undo() {
    let db = box_at("restore_many");
    let ids: Vec<String> = ["a", "b", "c"].iter().map(|n| liv(&db, &["new", "note", n])).collect();
    for id in &ids {
        liv(&db, &["trash", id]);
    }
    let mut args = vec!["restore"];
    args.extend(ids.iter().map(String::as_str));
    assert_eq!(json(&db, &args)["restored"], 3);
    assert!(json(&db, &["trash"]).as_array().unwrap().is_empty());
    liv(&db, &["undo"]);
    assert_eq!(json(&db, &["trash"]).as_array().unwrap().len(), 3, "one undo, all three");
    let _ = std::fs::remove_dir_all(db.parent().unwrap());
}

/// `inbox ID` answers what the app's properties card asks
/// (`liv_sweep_one`): the whole-box `inbox`'s rows for that one thing.
#[test]
fn the_inbox_of_one_thing_is_the_inbox_narrowed() {
    let db = box_at("inbox_one");
    liv(&db, &["new", "person", "Anna"]);
    let scrap = liv(&db, &["capture", "call", "anna", "tomorrow"]);
    let scrap: serde_json::Value = serde_json::from_str(&scrap).unwrap();
    let scrap = scrap["id"].as_str().unwrap().to_owned();

    let all = json(&db, &["inbox"]);
    let theirs: Vec<&serde_json::Value> =
        all.as_array().unwrap().iter().filter(|r| r["entity"] == scrap.as_str()).collect();
    assert!(theirs.len() >= 2, "a date and a mention: {all}");
    let one = json(&db, &["inbox", &scrap]);
    assert_eq!(one.as_array().unwrap().iter().collect::<Vec<_>>(), theirs);
    let _ = std::fs::remove_dir_all(db.parent().unwrap());
}
