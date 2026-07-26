//! The satellite seam, end to end through the real binary (design/ios.md §2):
//! a temp satellite root + a temp box, drained by `liv drain`, inspected
//! directly through liv-core/liv-services. HOME is pointed into the scratch
//! dir so the attachments home (`~/liv/attachments`) never leaves the test.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output};

use liv_core::{props, FileRef, Id, Session, Store, Value};
use liv_services::{content, property_id, run, Constraint, Op, Query};
use serde_json::json;

const DEV: &str = "8f14e45f-ceea-467f-a8d1-2f9a4a13c1b4";

// ---- scaffolding ----

/// A fresh scratch dir per test: `home/` (the attachments home), `sat/` (the
/// satellite root), `box.log` (the desk box).
fn scratch(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("liv_satellite_{name}"));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(dir.join("home")).unwrap();
    fs::create_dir_all(dir.join("sat")).unwrap();
    dir
}

fn liv(dir: &Path, args: &[&str]) -> Output {
    let out = Command::new(env!("CARGO_BIN_EXE_liv"))
        .env("HOME", dir.join("home"))
        .args(["--log", dir.join("box.log").to_str().unwrap()])
        .args(args)
        .output()
        .unwrap();
    assert!(
        out.status.success(),
        "liv {args:?} failed:\n{}",
        String::from_utf8_lossy(&out.stderr)
    );
    out
}

fn drain(dir: &Path) -> String {
    let out = liv(dir, &["drain", dir.join("sat").to_str().unwrap()]);
    String::from_utf8_lossy(&out.stdout).into_owned()
}

fn write_batch(dir: &Path, ulid: &str, body: &serde_json::Value) {
    let outbox = dir.join("sat/outbox").join(DEV);
    fs::create_dir_all(&outbox).unwrap();
    fs::write(outbox.join(format!("batch-{ulid}.json")), body.to_string()).unwrap();
}

/// Land media bytes under their true sha name; return the hex sha.
fn write_media(dir: &Path, bytes: &[u8], ext: &str) -> String {
    let media = dir.join("sat/media").join(DEV);
    fs::create_dir_all(&media).unwrap();
    let staging = media.join("staging.bin");
    fs::write(&staging, bytes).unwrap();
    let sha = hex(&liv_services::files::hash_file(staging.to_str().unwrap()).unwrap());
    fs::rename(&staging, media.join(format!("{sha}.{ext}"))).unwrap();
    sha
}

fn hex(hash: &[u8; 32]) -> String {
    hash.iter().map(|b| format!("{b:02x}")).collect()
}

fn ack_path(dir: &Path, ulid: &str) -> PathBuf {
    dir.join("sat/ack").join(DEV).join(format!("batch-{ulid}.json"))
}

fn by_ext(store: &Store, ext: &str) -> Option<Id> {
    run(
        store,
        &Query {
            constraints: vec![Constraint {
                property: props::EXTERNAL_ID,
                op: Op::Equals(Value::text(ext)),
            }],
            include_working: true,
            ..Query::default()
        },
    )
    .first()
    .copied()
}

fn ext_count(store: &Store) -> usize {
    run(
        store,
        &Query {
            constraints: vec![Constraint { property: props::EXTERNAL_ID, op: Op::Exists }],
            include_working: true,
            ..Query::default()
        },
    )
    .len()
}

fn name_of(store: &Store, id: Id) -> String {
    match store.get(id).and_then(|e| e.get(props::NAME)) {
        Some(Value::Text(name)) => name.clone(),
        other => panic!("no name on #{id}: {other:?}"),
    }
}

// ---- the tests ----

#[test]
fn golden_path_drain() {
    let dir = scratch("golden");
    let sha = write_media(&dir, b"honest jpeg bytes", "jpg");
    let ulid = "01JGOLDEN000000000000000AA";
    write_batch(
        &dir,
        ulid,
        &json!({
            "v": 1, "batch": ulid, "device": DEV, "device_name": "Konrad's iPhone",
            "created": "2026-07-25 09:30",
            "items": [
                { "uuid": "u-idea", "kind": "idea",
                  "text": "A bright thought\nwith a second line",
                  "captured": "2026-07-25 09:01" },
                { "uuid": "u-task", "kind": "task", "name": "Call the plumber",
                  "status": "doing", "due_civil": 202607271330i64, "date_only": false,
                  "captured": "2026-07-25 09:02" },
                { "uuid": "u-event", "kind": "event", "name": "Sommerfest",
                  "due_civil": 202608010000i64, "date_only": true,
                  "captured": "2026-07-25 09:03" },
                { "uuid": "u-photo", "kind": "photo", "name": "the receipt",
                  "media_sha": sha, "media_ext": "jpg",
                  "captured": "2026-07-25 09:04" },
                { "uuid": "u-link", "kind": "link", "url": "https://example.com/a",
                  "name": "An article", "captured": "2026-07-25 09:05" },
            ]
        }),
    );

    let stdout = drain(&dir);
    assert!(stdout.contains("5 brought in, 0 already here"), "{stdout}");
    assert!(stdout.contains(&format!("phone·{}#{ulid}", &DEV[..8])), "{stdout}");

    let session = Session::open(dir.join("box.log")).unwrap();
    let store = session.store();

    // Idea/task/event landed as notes under the external-id law.
    let idea = by_ext(store, &format!("ios://{DEV}/u-idea")).expect("idea landed");
    assert_eq!(name_of(store, idea), "A bright thought");
    let task = by_ext(store, &format!("ios://{DEV}/u-task")).expect("task landed");
    let event = by_ext(store, &format!("ios://{DEV}/u-event")).expect("event landed");

    // The task's due and status are REAL typed cells, not text.
    let due_prop = property_id(store, "due").unwrap();
    match store.get(task).unwrap().get(due_prop) {
        Some(Value::DateTime(dt)) => {
            assert_eq!(dt.civil, 202607271330);
            assert!(!dt.date_only);
        }
        other => panic!("task has no typed due: {other:?}"),
    }
    let status_prop = property_id(store, "status").unwrap();
    let doing = content::find_option(store, status_prop, "doing").unwrap();
    assert_eq!(store.get(task).unwrap().get(status_prop), Some(&Value::Select(doing)));

    // The event's date-only due survives as date-only.
    match store.get(event).unwrap().get(due_prop) {
        Some(Value::DateTime(dt)) => {
            assert_eq!(dt.civil, 202608010000);
            assert!(dt.date_only);
        }
        other => panic!("event has no typed due: {other:?}"),
    }

    // Both carry the liv_kind marker (phase-1: TYPE stays note).
    let kind_prop = property_id(store, "liv_kind").expect("liv_kind minted");
    assert_eq!(store.get(task).unwrap().get(kind_prop), Some(&Value::text("task")));

    // The photo's bytes landed in the attachments home under their sha, and
    // exactly ONE file entity carries that hash (hash-dedupe key).
    let dest = dir.join("home/liv/attachments").join(format!("{sha}.jpg"));
    assert!(dest.is_file(), "attachment not landed");
    assert_eq!(fs::read(&dest).unwrap(), b"honest jpeg bytes");
    let file_prop = property_id(store, "file").unwrap();
    let hash = liv_services::files::hash_file(dest.to_str().unwrap()).unwrap();
    let files = run(
        store,
        &Query {
            constraints: vec![Constraint {
                property: file_prop,
                op: Op::Equals(Value::File(FileRef { path: String::new(), hash })),
            }],
            include_working: true,
            ..Query::default()
        },
    );
    assert_eq!(files.len(), 1, "one file entity per content hash");

    // The link dedupes by url (its external id IS the url).
    assert!(by_ext(store, "https://example.com/a").is_some(), "link landed");

    // The ack: written, complete, honest.
    let ack: serde_json::Value =
        serde_json::from_slice(&fs::read(ack_path(&dir, ulid)).unwrap()).unwrap();
    assert_eq!(ack["v"], 1);
    assert_eq!(ack["batch"], ulid);
    assert_eq!(ack["device"], DEV);
    assert_eq!(ack["imported"], 5);
    assert_eq!(ack["deduped"], 0);
    assert!(ack["drained_at"].is_string() && ack["host"].is_string());
}

#[test]
fn drain_twice_imports_nothing_and_reacks() {
    let dir = scratch("idempotent");
    let sha = write_media(&dir, b"the same photo", "png");
    let ulid = "01JTWICE0000000000000000AA";
    write_batch(
        &dir,
        ulid,
        &json!({
            "v": 1, "batch": ulid, "device": DEV, "created": "2026-07-25 10:00",
            "items": [
                { "uuid": "u-1", "kind": "idea", "text": "once only", "captured": "2026-07-25 09:59" },
                { "uuid": "u-2", "kind": "photo", "media_sha": sha, "media_ext": "png", "captured": "2026-07-25 09:59" },
                { "uuid": "u-3", "kind": "link", "url": "https://example.com/b", "captured": "2026-07-25 09:59" },
            ]
        }),
    );

    let first = drain(&dir);
    assert!(first.contains("3 brought in, 0 already here"), "{first}");
    let count_after_first = {
        let s = Session::open(dir.join("box.log")).unwrap();
        ext_count(s.store())
    };

    // With the ack present, the batch is skipped outright.
    let skipped = drain(&dir);
    assert!(skipped.contains("nothing waiting in the outbox"), "{skipped}");

    // Lose the ack (they are an optimization, not correctness): the redrain
    // self-heals to imported 0 and rewrites the ack harmlessly.
    fs::remove_file(ack_path(&dir, ulid)).unwrap();
    let second = drain(&dir);
    assert!(second.contains("0 brought in, 3 already here"), "{second}");
    let ack: serde_json::Value =
        serde_json::from_slice(&fs::read(ack_path(&dir, ulid)).unwrap()).unwrap();
    assert_eq!(ack["imported"], 0);
    assert_eq!(ack["deduped"], 3);

    let s = Session::open(dir.join("box.log")).unwrap();
    assert_eq!(ext_count(s.store()), count_after_first, "the redrain duplicated something");
}

#[test]
fn torn_batch_is_quarantined_box_untouched() {
    let dir = scratch("torn");
    let ulid = "01JTORN00000000000000000AA";
    let outbox = dir.join("sat/outbox").join(DEV);
    fs::create_dir_all(&outbox).unwrap();
    fs::write(
        outbox.join(format!("batch-{ulid}.json")),
        br#"{ "v": 1, "batch": "01JTORN", "items": [ { "kind": "#,
    )
    .unwrap();

    let stdout = drain(&dir);
    assert!(stdout.contains("quarantined"), "{stdout}");

    // Moved aside, never acked, and the box gained nothing.
    assert!(!outbox.join(format!("batch-{ulid}.json")).exists());
    assert!(dir.join("sat/quarantine").join(format!("batch-{ulid}.json")).is_file());
    assert!(!ack_path(&dir, ulid).exists());
    let s = Session::open(dir.join("box.log")).unwrap();
    assert_eq!(ext_count(s.store()), 0);
}

#[test]
fn media_hash_mismatch_is_quarantined() {
    let dir = scratch("mismatch");
    // The batch claims the sha of the honest bytes, but the file on the wire
    // holds different bytes under that name.
    let claimed = write_media(&dir, b"the honest bytes", "jpg");
    let media_file = dir.join("sat/media").join(DEV).join(format!("{claimed}.jpg"));
    fs::write(&media_file, b"corrupted bytes").unwrap();

    let ulid = "01JBADHASH00000000000000AA";
    write_batch(
        &dir,
        ulid,
        &json!({
            "v": 1, "batch": ulid, "device": DEV, "created": "2026-07-25 11:00",
            "items": [
                { "uuid": "u-good", "kind": "idea", "text": "rides along", "captured": "2026-07-25 10:59" },
                { "uuid": "u-bad", "kind": "photo", "media_sha": claimed, "media_ext": "jpg", "captured": "2026-07-25 10:59" },
            ]
        }),
    );

    let stdout = drain(&dir);
    assert!(stdout.contains("quarantined") && stdout.contains("hash mismatch"), "{stdout}");

    // The WHOLE batch is refused — even the innocent idea never imports.
    let s = Session::open(dir.join("box.log")).unwrap();
    assert_eq!(ext_count(s.store()), 0, "a quarantined batch partially imported");
    assert!(!ack_path(&dir, ulid).exists());
    assert!(dir.join("sat/quarantine").join(format!("batch-{ulid}.json")).is_file());
    // Nothing landed in the attachments home under the claimed sha.
    assert!(!dir.join("home/liv/attachments").join(format!("{claimed}.jpg")).exists());
}

#[test]
fn missing_media_defers_the_whole_batch() {
    let dir = scratch("missing_media");
    let ulid = "01JWAITING00000000000000AA";
    let absent_sha = "a".repeat(64);
    write_batch(
        &dir,
        ulid,
        &json!({
            "v": 1, "batch": ulid, "device": DEV, "created": "2026-07-25 12:00",
            "items": [
                { "uuid": "u-note", "kind": "idea", "text": "waits with the photo", "captured": "2026-07-25 11:59" },
                { "uuid": "u-photo", "kind": "photo", "media_sha": absent_sha, "media_ext": "heic", "captured": "2026-07-25 11:59" },
            ]
        }),
    );

    let stdout = drain(&dir);
    assert!(stdout.contains("deferred") && stdout.contains("media still arriving"), "{stdout}");

    // No ack, no quarantine, the batch stays put — the next drain retries.
    assert!(!ack_path(&dir, ulid).exists());
    assert!(!dir.join("sat/quarantine").exists());
    assert!(dir.join("sat/outbox").join(DEV).join(format!("batch-{ulid}.json")).is_file());
    let s = Session::open(dir.join("box.log")).unwrap();
    assert_eq!(ext_count(s.store()), 0, "a deferred batch partially imported");
}

#[test]
fn unknown_version_defers_with_the_update_message() {
    let dir = scratch("unknown_v");
    let ulid = "01JFUTURE000000000000000AA";
    write_batch(
        &dir,
        ulid,
        &json!({
            "v": 2, "batch": ulid, "device": DEV, "created": "2026-07-25 13:00",
            "items": [ { "uuid": "u-x", "kind": "hologram", "captured": "2026-07-25 12:59" } ]
        }),
    );

    let stdout = drain(&dir);
    assert!(stdout.contains("deferred"), "{stdout}");
    assert!(stdout.contains("update Liv on this Mac"), "{stdout}");
    assert!(!ack_path(&dir, ulid).exists());
    assert!(dir.join("sat/outbox").join(DEV).join(format!("batch-{ulid}.json")).is_file());
    let s = Session::open(dir.join("box.log")).unwrap();
    assert_eq!(ext_count(s.store()), 0);
}

#[test]
fn satellite_export_writes_the_gzipped_snapshot() {
    let dir = scratch("export");
    // Put something real in the box, then export.
    liv(&dir, &["add", "hello from the desk"]);
    liv(&dir, &["satellite-export", dir.join("sat").to_str().unwrap()]);

    let gz = dir.join("sat/snapshot/desk.json.gz");
    assert!(gz.is_file(), "no snapshot landed");
    let mut decoder = flate2::read::GzDecoder::new(fs::File::open(&gz).unwrap());
    let mut json = String::new();
    std::io::Read::read_to_string(&mut decoder, &mut json).unwrap();
    let snapshot: serde_json::Value = serde_json::from_str(&json).unwrap();

    // The same shape the FFI serves every shell — entities present, and the
    // captured scrap among them.
    let entities = snapshot["entities"].as_array().expect("entities array");
    assert!(!entities.is_empty());
    assert!(json.contains("hello from the desk"), "the capture is missing from the snapshot");
    // No leftover tmp file — the replace is atomic.
    assert!(!dir.join("sat/snapshot/desk.json.gz.tmp").exists());
}
