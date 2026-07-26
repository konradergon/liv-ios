//! The satellite seam (design/ios.md §2): `drain` pulls the phone's outbox
//! batches into the box, `satellite-export` writes the desk snapshot back.
//!
//! The transport is dumb files. The phone owns `outbox/` and `media/`
//! (write-once), the desk owns `ack/` and `snapshot/`. A batch is drained as
//! ONE import transaction through `liv_services::import::commit_batch` — the
//! external-id law (`ios://<device>/<uuid>`) makes every re-delivery a no-op,
//! so acks are an optimization, never a correctness mechanism.

use std::ffi::{CStr, CString};
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use chrono::{Datelike, Local, Timelike};
use liv_core::{DateTime, Session};
use liv_services::import::{commit_batch, ImportDefaults, ImportItem};

// ---- the wire shapes (§2.2, the v1 concrete encoding) ----
// Every field beyond the required core is optional: an almost-right batch
// must fail loudly as a whole, never half-parse.

#[derive(serde::Deserialize)]
struct Batch {
    batch: String,
    device: String,
    #[serde(default)]
    created: Option<String>,
    items: Vec<Item>,
}

#[derive(serde::Deserialize)]
struct Item {
    uuid: String,
    kind: String,
    #[serde(default)]
    text: Option<String>,
    #[serde(default)]
    name: Option<String>,
    #[serde(default)]
    due_civil: Option<i64>,
    #[serde(default)]
    date_only: Option<bool>,
    #[serde(default)]
    status: Option<String>,
    #[serde(default)]
    url: Option<String>,
    #[serde(default)]
    media_sha: Option<String>,
    #[serde(default)]
    media_ext: Option<String>,
}

/// One batch file found in the outbox, identified before parsing: the
/// device from its directory, the ULID from its filename — the phone wrote
/// both, so even a torn file has an address for its report line.
struct Slot {
    device: String,
    ulid: String,
    path: PathBuf,
}

/// The whole-batch verdict, decided BEFORE the box is touched. A batch is
/// drained whole or not at all — there is no partial import.
enum Verdict {
    /// Media verified and staged; the lowered items are ready for one commit.
    Ready { items: Vec<ImportItem>, batch: Batch },
    /// Not ready yet (media still syncing, newer protocol). File untouched,
    /// no ack — the next drain retries.
    Defer(String),
    /// Provably bad (torn JSON, hash mismatch). Moved to `quarantine/` for
    /// inspection; never imported, never acked.
    Quarantine(String),
}

// ---- drain ----

/// `liv drain SATELLITE-ROOT` — batches in ULID order, one transaction per
/// batch, ack on success (even a pure re-delivery acks, silently). Exit 0
/// unless the satellite root itself is unreadable.
pub fn drain(session: &mut Session, rest: &[&str]) -> Result<(), String> {
    let root_arg = rest.first().ok_or("usage: liv drain SATELLITE-ROOT")?;
    let root = PathBuf::from(root_arg);
    fs::read_dir(&root).map_err(|e| format!("cannot read the satellite root {root_arg}: {e}"))?;

    let (mut brought, mut already) = (0usize, 0usize);
    let (mut drained, mut deferred, mut quarantined) = (0usize, 0usize, 0usize);

    for slot in scan(&root) {
        let ack_path = root
            .join("ack")
            .join(&slot.device)
            .join(format!("batch-{}.json", slot.ulid));
        if ack_path.is_file() {
            continue; // already delivered — the phone will clean up
        }
        let label = format!("phone·{}#{}", eight(&slot.device), slot.ulid);
        let bytes = match fs::read(&slot.path) {
            Ok(bytes) => bytes,
            Err(e) => {
                println!("{label}: deferred: unreadable right now ({e})");
                deferred += 1;
                continue;
            }
        };
        match judge(&root, &bytes) {
            Verdict::Ready { items, batch } => {
                let created = batch
                    .created
                    .as_deref()
                    .and_then(parse_stamp)
                    .unwrap_or_else(now_civil);
                let ids = commit_batch(session, &items, created, &ImportDefaults::default())
                    .map_err(|e| format!("import failed for {label}: {e}"))?;
                let (imported, deduped) = (ids.len(), items.len() - ids.len());
                write_ack(&ack_path, &batch, imported, deduped)?;
                println!("{label}: {imported} brought in, {deduped} already here");
                brought += imported;
                already += deduped;
                drained += 1;
            }
            Verdict::Defer(reason) => {
                println!("{label}: deferred: {reason}");
                deferred += 1;
            }
            Verdict::Quarantine(reason) => {
                quarantine(&root, &slot)?;
                println!("{label}: quarantined: {reason}");
                quarantined += 1;
            }
        }
    }

    if drained + deferred + quarantined == 0 {
        println!("nothing waiting in the outbox");
        return Ok(());
    }
    println!(
        "total: {brought} brought in, {already} already here · {deferred} deferred · {quarantined} quarantined"
    );
    Ok(())
}

/// Every `outbox/<device>/batch-<ULID>.json`, globally ULID-sorted (a ULID
/// is time-ordered, so this is arrival order across devices). The denylist
/// is absolute: nothing whose name touches `.liv` or `.trash` is ever read.
fn scan(root: &Path) -> Vec<Slot> {
    let mut slots = Vec::new();
    let Ok(devices) = fs::read_dir(root.join("outbox")) else {
        return slots; // no outbox yet — nothing has ever shipped
    };
    for dev in devices.flatten() {
        let device = dev.file_name().to_string_lossy().into_owned();
        if denylisted(&device) || !dev.path().is_dir() {
            continue;
        }
        let Ok(files) = fs::read_dir(dev.path()) else {
            continue;
        };
        for file in files.flatten() {
            let name = file.file_name().to_string_lossy().into_owned();
            if denylisted(&name) {
                continue;
            }
            let Some(ulid) = name
                .strip_prefix("batch-")
                .and_then(|n| n.strip_suffix(".json"))
            else {
                continue;
            };
            slots.push(Slot {
                device: device.clone(),
                ulid: ulid.to_string(),
                path: file.path(),
            });
        }
    }
    slots.sort_by(|a, b| a.ulid.cmp(&b.ulid).then_with(|| a.device.cmp(&b.device)));
    slots
}

fn denylisted(name: &str) -> bool {
    name.contains(".liv") || name.contains(".trash")
}

/// Decide the whole batch's fate, then lower it. Order matters: parse, then
/// the readiness gate over EVERY media file, then verify + stage — so a
/// deferrable batch is discovered before any bytes are copied, and a
/// quarantinable one before any import.
fn judge(root: &Path, bytes: &[u8]) -> Verdict {
    // Torn JSON is provably bad (the phone writes tmp+rename, so a visible
    // file is complete); an unknown version is merely from the future.
    let Ok(raw) = serde_json::from_slice::<serde_json::Value>(bytes) else {
        return Verdict::Quarantine("torn batch file".into());
    };
    match raw.get("v").and_then(|v| v.as_i64()) {
        Some(1) => {}
        Some(_) => {
            return Verdict::Defer("a newer phone wrote this — update Liv on this Mac".into())
        }
        None => return Verdict::Quarantine("malformed batch (no version)".into()),
    }
    let batch: Batch = match serde_json::from_value(raw) {
        Ok(batch) => batch,
        Err(e) => return Verdict::Quarantine(format!("malformed batch ({e})")),
    };
    if !plain_name(&batch.device) || !plain_name(&batch.batch) {
        return Verdict::Quarantine("malformed batch (unsafe ids)".into());
    }

    // The readiness gate: every photo's media file must be present and its
    // declared address safe, or the WHOLE batch waits.
    for item in &batch.items {
        match item.kind.as_str() {
            "idea" | "task" | "event" | "photo" | "link" => {}
            _ => return Verdict::Defer("unknown item kind — update Liv on this Mac".into()),
        }
        if item.kind == "photo" {
            let (Some(sha), Some(ext)) = (&item.media_sha, &item.media_ext) else {
                return Verdict::Quarantine("malformed batch (photo without media fields)".into());
            };
            if !is_sha_hex(sha) || !matches!(ext.as_str(), "heic" | "jpg" | "png" | "webp") {
                return Verdict::Quarantine("malformed batch (unsafe media fields)".into());
            }
            if !media_path(root, &batch.device, sha, ext).is_file() {
                return Verdict::Defer("media still arriving".into());
            }
        }
    }

    // Verify + stage + lower. Any failure here still abandons the whole
    // batch — attachments already staged are sha-named and content-verified,
    // so leftovers are harmless and the retry re-uses them.
    let mut items = Vec::new();
    for item in &batch.items {
        let source_id = format!("ios://{}/{}", batch.device, item.uuid);
        match item.kind.as_str() {
            "idea" => {
                let Some(text) = &item.text else {
                    return Verdict::Quarantine("malformed batch (idea without text)".into());
                };
                let title: String =
                    text.lines().next().unwrap_or("").trim().chars().take(60).collect();
                items.push(ImportItem::Note {
                    frontmatter: vec![
                        ("title".into(), title),
                        ("liv_kind".into(), "idea".into()),
                    ],
                    body: text.clone(),
                    source_id,
                });
            }
            "task" | "event" => {
                let Some(name) = &item.name else {
                    return Verdict::Quarantine(format!(
                        "malformed batch ({} without name)",
                        item.kind
                    ));
                };
                let mut frontmatter = vec![
                    ("title".into(), name.clone()),
                    ("liv_kind".into(), item.kind.clone()),
                ];
                if item.kind == "task" {
                    if let Some(status) = &item.status {
                        frontmatter.push(("status".into(), status.clone()));
                    }
                }
                if let Some(due) = item.due_civil {
                    frontmatter
                        .push(("due".into(), due_string(due, item.date_only.unwrap_or(false))));
                }
                items.push(ImportItem::Note { frontmatter, body: String::new(), source_id });
            }
            "photo" => {
                let sha = item.media_sha.as_ref().unwrap().to_lowercase();
                let ext = item.media_ext.as_ref().unwrap();
                match stage_media(&media_path(root, &batch.device, &sha, ext), &sha, ext) {
                    Ok(dest) => items.push(ImportItem::File { path: dest }),
                    Err(Stage::Mismatch) => {
                        return Verdict::Quarantine(format!(
                            "hash mismatch on media {}…",
                            eight(&sha)
                        ))
                    }
                    Err(Stage::Gone) => return Verdict::Defer("media still arriving".into()),
                    Err(Stage::Io(e)) => {
                        return Verdict::Defer(format!("media unreadable right now ({e})"))
                    }
                }
            }
            "link" => {
                let Some(url) = &item.url else {
                    return Verdict::Quarantine("malformed batch (link without url)".into());
                };
                items.push(ImportItem::Link { url: url.clone(), title: item.name.clone() });
            }
            _ => unreachable!("kinds were screened above"),
        }
    }
    Verdict::Ready { items, batch }
}

fn media_path(root: &Path, device: &str, sha: &str, ext: &str) -> PathBuf {
    root.join("media").join(device).join(format!("{sha}.{ext}"))
}

enum Stage {
    /// The file vanished between the readiness gate and the copy.
    Gone,
    /// The bytes do not hash to the batch's claim — corruption, not latency.
    Mismatch,
    Io(String),
}

/// Verify the media file against its claimed sha, then land it in the
/// attachments home tmp+rename. Skip-if-present only AFTER verifying the
/// existing destination's bytes; a wrong-bytes destination is rewritten.
fn stage_media(src: &Path, sha: &str, ext: &str) -> Result<String, Stage> {
    let io = |e: std::io::Error| Stage::Io(e.to_string());
    if !src.is_file() {
        return Err(Stage::Gone);
    }
    if hash_of(src)? != sha {
        return Err(Stage::Mismatch);
    }

    let home = attachments_home();
    fs::create_dir_all(&home).map_err(io)?;
    let dest = home.join(format!("{sha}.{ext}"));
    let dest_str = dest
        .to_str()
        .ok_or_else(|| Stage::Io("non-utf8 attachments path".into()))?
        .to_string();
    if dest.is_file() && hash_of(&dest)? == sha {
        return Ok(dest_str); // already landed, verified — a re-drain no-op
    }
    let tmp = home.join(format!("{sha}.{ext}.tmp"));
    fs::copy(src, &tmp).map_err(io)?;
    if hash_of(&tmp)? != sha {
        let _ = fs::remove_file(&tmp);
        return Err(Stage::Io("the copy tore".into()));
    }
    fs::rename(&tmp, &dest).map_err(io)?;
    Ok(dest_str)
}

fn hash_of(path: &Path) -> Result<String, Stage> {
    let s = path.to_str().ok_or_else(|| Stage::Io("non-utf8 path".into()))?;
    let hash = liv_services::files::hash_file(s).map_err(|e| Stage::Io(e.to_string()))?;
    Ok(hex(&hash))
}

/// `~/liv/attachments` — the media home (design/ios.md §8).
fn attachments_home() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
    Path::new(&home).join("liv").join("attachments")
}

/// The ack, tmp+rename: delivery proof for the phone, provenance for a human.
fn write_ack(ack_path: &Path, batch: &Batch, imported: usize, deduped: usize) -> Result<(), String> {
    let dir = ack_path.parent().ok_or("ack path has no parent")?;
    fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    let ack = serde_json::json!({
        "v": 1,
        "batch": batch.batch,
        "device": batch.device,
        "imported": imported,
        "deduped": deduped,
        "drained_at": Local::now().format("%Y-%m-%d %H:%M").to_string(),
        "host": hostname(),
    });
    let tmp = dir.join(format!(
        "{}.tmp",
        ack_path.file_name().and_then(|n| n.to_str()).unwrap_or("ack")
    ));
    fs::write(&tmp, serde_json::to_vec(&ack).map_err(|e| e.to_string())?)
        .map_err(|e| e.to_string())?;
    fs::rename(&tmp, ack_path).map_err(|e| e.to_string())?;
    Ok(())
}

/// Move a provably-bad batch aside — out of the drain path, kept for eyes.
fn quarantine(root: &Path, slot: &Slot) -> Result<(), String> {
    let dir = root.join("quarantine");
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    fs::rename(&slot.path, dir.join(format!("batch-{}.json", slot.ulid)))
        .map_err(|e| e.to_string())?;
    Ok(())
}

// ---- satellite-export ----

/// `liv satellite-export SATELLITE-ROOT` — the desk snapshot, gzipped, landed
/// atomically at `snapshot/desk.json.gz`. The JSON is byte-identical to what
/// the FFI serves every shell: this goes through the liv-ffi crate itself
/// (the builder is private to it), via a small safe wrapper. The FFI call
/// opens — and locks — the box, so the caller must NOT hold a session.
pub fn export(log_path: &str, root: &str) -> Result<(), String> {
    let json = snapshot_json(log_path)?;
    let dir = Path::new(root).join("snapshot");
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;

    let tmp = dir.join("desk.json.gz.tmp");
    let file = fs::File::create(&tmp).map_err(|e| e.to_string())?;
    let mut encoder = flate2::write::GzEncoder::new(file, flate2::Compression::default());
    encoder.write_all(json.as_bytes()).map_err(|e| e.to_string())?;
    let file = encoder.finish().map_err(|e| e.to_string())?;
    file.sync_all().map_err(|e| e.to_string())?;
    let dest = dir.join("desk.json.gz");
    fs::rename(&tmp, &dest).map_err(|e| e.to_string())?;

    println!("wrote {} ({} bytes of snapshot, gzipped)", dest.display(), json.len());
    Ok(())
}

/// The one unsafe seam: call the C-ABI snapshot, copy the string out, free
/// it with the paired free. Rust-to-Rust through the rlib — no dylib loading.
fn snapshot_json(log_path: &str) -> Result<String, String> {
    let c_path = CString::new(log_path).map_err(|_| "the box path contains a NUL")?;
    let raw = unsafe { liv_ffi::liv_snapshot(c_path.as_ptr()) };
    if raw.is_null() {
        return Err("cannot snapshot the box (is it open elsewhere?)".into());
    }
    let json = unsafe { CStr::from_ptr(raw) }
        .to_str()
        .map(str::to_string)
        .map_err(|_| "the snapshot was not UTF-8".to_string());
    unsafe { liv_ffi::liv_string_free(raw) };
    json
}

// ---- little formatters ----

fn eight(s: &str) -> String {
    s.chars().take(8).collect()
}

fn hex(hash: &[u8; 32]) -> String {
    hash.iter().map(|b| format!("{b:02x}")).collect()
}

fn is_sha_hex(s: &str) -> bool {
    s.len() == 64 && s.chars().all(|c| c.is_ascii_hexdigit())
}

/// Device UUIDs and batch ULIDs are plain tokens; anything else (path
/// separators, dots, emptiness) never becomes part of a path we write.
fn plain_name(s: &str) -> bool {
    !s.is_empty() && s.chars().all(|c| c.is_ascii_alphanumeric() || c == '-')
}

/// A wire `due_civil` (YYYYMMDDHHMM) in the frontmatter grammar services
/// already parses: `YYYY-MM-DD HH:MM`, or the bare date when date-only.
fn due_string(civil: i64, date_only: bool) -> String {
    let (y, mo, d) = (civil / 100_000_000, (civil / 1_000_000) % 100, (civil / 10_000) % 100);
    let (h, mi) = ((civil / 100) % 100, civil % 100);
    if date_only {
        format!("{y:04}-{mo:02}-{d:02}")
    } else {
        format!("{y:04}-{mo:02}-{d:02} {h:02}:{mi:02}")
    }
}

/// The wire's civil stamp, `YYYY-MM-DD HH:MM` — no timezone, by design.
fn parse_stamp(raw: &str) -> Option<DateTime> {
    let (date, time) = raw.split_once(' ')?;
    let mut ymd = date.split('-');
    let year: i32 = ymd.next()?.parse().ok()?;
    let month: u32 = ymd.next()?.parse().ok()?;
    let day: u32 = ymd.next()?.parse().ok()?;
    let (hour, minute) = time.split_once(':')?;
    Some(DateTime::at(year, month, day, hour.parse().ok()?, minute.parse().ok()?))
}

fn now_civil() -> DateTime {
    let now = Local::now();
    DateTime::at(now.year(), now.month(), now.day(), now.hour(), now.minute())
}

fn hostname() -> String {
    std::process::Command::new("hostname")
        .output()
        .ok()
        .and_then(|out| String::from_utf8(out.stdout).ok())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "unknown".into())
}
