//! `liv` — a headless CLI over the app's own box: the VERIFICATION tool.
//!
//! **The app's verbs, and nothing else.** Every command goes through the C
//! ABI in `liv-ffi` — the same `liv_*` functions `Box.swift` calls — and
//! prints the JSON the app decodes. So "cross-check a write against the
//! box" asks the box exactly what the app asks it, through the same code;
//! a second implementation here would be a second opinion, and a check
//! that can disagree with the thing it checks is not a check.
//!
//! It reads and writes the engine's `liv.db`, the file the app opens. It
//! used to read only the core-era `.log`, which the app stopped opening at
//! slice 5b; this is stage 5 of `design/rust-owns-the-mechanisms.md`
//! (2026-09-29), where it moved first because everything after it is
//! verified with it.
//!
//! `history` is the one read that is not an app verb: the app has no
//! screen for the raw log, and "one transaction per user action" is a
//! claim about the log, so it opens the engine read-only for that alone.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use serde_json::{json, Value as J};

use liv_ffi::basics::*;
use liv_ffi::finding::*;
use liv_ffi::surfaces::*;
use liv_ffi::writes::*;

const USAGE: &str = "\
usage: liv --box <liv.db> <command> [args]      (or LIV_BOX=<liv.db>)

MAKING THINGS
  new KIND [NAME...] [--PROP VALUE]...   make a note/task/event/…, then set each
                                         property; an area/project/person/status
                                         named for the first time is minted, as
                                         the app's picker does. Prints the id.
  capture TEXT...                        catch words as an unsorted scrap
  option PROP NAME...                    mint a value of a property (an area…)
  field NAME HOLDS [--many]              declare a field (text, number, bool,
                                         datetime, reference, richtext, file)
  file PATH                              add a file

CHANGING THINGS
  set ID PROP VALUE...   add ID PROP VALUE...   remove ID PROP VALUE...
  unset ID PROP          trash ID               restore ID...  (several: one undo)
  content-set ID TEXT... replace a body with plain text
  rename-value PROP OLD NEW
  undo | redo
  accept ID PRINT        decline ID PRINT       (a suggestion from `inbox`)
  assist on|off

READING
  list [--all]           everything, as a table (--all adds the trash)
  library                every row, Notes, Unsorted and the panel's counts
  today | tasks | trash | day YYYY-MM-DD
  cells ID | links ID | content ID | versions ID
  options PROP | values PROP | properties | kinds | workspaces
  search WORDS... | lens QUERY... | terms QUERY...
  inbox [ID]             what the clerk suggests, about everything or one
                         thing (liv_sweep / liv_sweep_one)
  snapshot               one refresh: the ten reads the app makes after a write
  history                the log, one line per transaction
  probe | file-alerts    is the box readable; which files are missing

An ID is the 32-hex id the app uses, or any part of one (6+ characters) that
only one thing's id contains — the middle is what differs between things made
in the same second.";

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if let Err(message) = run(&args) {
        eprintln!("liv: {message}");
        std::process::exit(1);
    }
}

fn run(args: &[String]) -> Result<(), String> {
    let mut rest: Vec<&str> = args.iter().map(String::as_str).collect();
    let mut path = std::env::var("LIV_BOX").ok();
    if let Some(i) = rest.iter().position(|a| *a == "--box") {
        path = Some(rest.get(i + 1).ok_or("--box needs a path")?.to_string());
        rest.drain(i..=i + 1);
    }
    let Some((&verb, a)) = rest.split_first() else {
        println!("{USAGE}");
        return Ok(());
    };
    if matches!(verb, "help" | "--help" | "-h") {
        println!("{USAGE}");
        return Ok(());
    }
    if verb == "terms" {
        return show(call(|out| unsafe { liv_terms(c(&a.join(" ")).as_ptr(), out) })?);
    }
    let path = path.ok_or("no box: pass --box <liv.db> or set LIV_BOX")?;
    let liv = Liv { path: c(&path), file: path };
    liv.dispatch(verb, a)
}

struct Liv {
    path: CString,
    file: String,
}

impl Liv {
    fn p(&self) -> *const c_char {
        self.path.as_ptr()
    }

    fn dispatch(&self, verb: &str, a: &[&str]) -> Result<(), String> {
        let now = now_ms();
        match (verb, a) {
            // ---- making ------------------------------------------------
            ("new", [kind, rest @ ..]) => self.new_thing(kind, rest),
            ("capture", words) if !words.is_empty() => {
                let text = c(&words.join(" "));
                show(call(|out| unsafe { liv_capture(self.p(), text.as_ptr(), now, out) })?)
            }
            ("option", [prop, name @ ..]) if !name.is_empty() => {
                let (prop, name) = (self.prop(prop)?.id, c(&name.join(" ")));
                show(call(|out| unsafe {
                    liv_add_option(self.p(), prop.as_ptr(), name.as_ptr(), now, out)
                })?)
            }
            ("field", [name, holds, flags @ ..]) => {
                let (name, holds) = (c(name), c(holds));
                let many = flags.contains(&"--many");
                show(call(|out| unsafe {
                    liv_declare_field(self.p(), name.as_ptr(), holds.as_ptr(), many, now, out)
                })?)
            }
            ("file", [file]) => {
                let file = c(file);
                show(call(|out| unsafe { liv_add_file(self.p(), file.as_ptr(), now, out) })?)
            }

            // ---- changing ----------------------------------------------
            ("set" | "add" | "remove", [id, prop, value @ ..]) if !value.is_empty() => {
                let (id, prop, value) = (self.id(id)?, self.prop(prop)?.id, c(&value.join(" ")));
                let f = match verb {
                    "set" => liv_set,
                    "add" => liv_add,
                    _ => liv_remove,
                };
                status(unsafe { f(self.p(), id.as_ptr(), prop.as_ptr(), value.as_ptr(), now) })
            }
            ("unset", [id, prop]) => {
                let (id, prop) = (self.id(id)?, self.prop(prop)?.id);
                status(unsafe { liv_unset(self.p(), id.as_ptr(), prop.as_ptr(), now) })
            }
            ("trash", [id]) => {
                let id = self.id(id)?;
                status(unsafe { liv_trash(self.p(), id.as_ptr(), now) })
            }
            ("restore", [id]) => {
                let id = self.id(id)?;
                status(unsafe { liv_restore(self.p(), id.as_ptr(), now) })
            }
            ("restore", ids) if !ids.is_empty() => {
                let ids: Vec<String> = ids
                    .iter()
                    .map(|raw| Ok(self.id(raw)?.into_string().unwrap_or_default()))
                    .collect::<Result<_, String>>()?;
                let ids = c(&serde_json::to_string(&ids).map_err(|e| e.to_string())?);
                show(call(|out| unsafe { liv_restore_many(self.p(), ids.as_ptr(), now, out) })?)
            }
            ("content-set", [id, text @ ..]) => self.content_set(id, &text.join(" ")),
            ("rename-value", [prop, old, new]) => {
                let (prop, old, new) = (self.prop(prop)?.id, c(old), c(new));
                show(call(|out| unsafe {
                    liv_rename_value(self.p(), prop.as_ptr(), old.as_ptr(), new.as_ptr(), now, out)
                })?)
            }
            ("undo", []) => status(unsafe { liv_undo(self.p(), now) }),
            ("redo", []) => status(unsafe { liv_redo(self.p(), now) }),
            ("accept" | "decline", [id, print]) => {
                let id = self.id(id)?;
                let print: u64 = print.parse().map_err(|_| format!("not a print: {print}"))?;
                let f = if verb == "accept" { liv_accept } else { liv_decline };
                status(unsafe { f(self.p(), id.as_ptr(), print, now) })
            }
            ("assist", [on @ ("on" | "off")]) => {
                status(unsafe { liv_set_assist(self.p(), *on == "on", now) })
            }

            // ---- reading -----------------------------------------------
            ("list", flags) => self.list(flags.contains(&"--all")),
            ("today", []) => show(call(|out| unsafe {
                liv_view_today(self.p(), now as i64, local_offset_min(), std::ptr::null(), out)
            })?),
            ("tasks", []) => show(call(|out| unsafe {
                liv_view_tasks(self.p(), std::ptr::null(), today(), std::ptr::null(), out)
            })?),
            ("trash", []) => show(call(|out| unsafe { liv_view_trash(self.p(), out) })?),
            ("day", [date]) => {
                let day = day_of(date)?;
                show(call(|out| unsafe { liv_view_day(self.p(), day, day, std::ptr::null(), out) })?)
            }
            ("cells" | "links" | "content" | "versions", [id]) => {
                let id = self.id(id)?;
                let f = match verb {
                    "cells" => liv_cells,
                    "links" => liv_links,
                    "content" => liv_read_body,
                    _ => liv_body_history,
                };
                show(call(|out| unsafe { f(self.p(), id.as_ptr(), out) })?)
            }
            ("options" | "values", [prop]) => {
                let prop = self.prop(prop)?.id;
                let f = if verb == "options" { liv_options } else { liv_values_in_use };
                show(call(|out| unsafe { f(self.p(), prop.as_ptr(), out) })?)
            }
            ("properties", []) => show(call(|out| unsafe { liv_properties(self.p(), out) })?),
            ("kinds", []) => show(call(|out| unsafe { liv_kinds(self.p(), out) })?),
            ("workspaces", []) => show(call(|out| unsafe { liv_workspaces(self.p(), out) })?),
            ("search", words) => {
                let q = c(&words.join(" "));
                show(call(|out| unsafe {
                    liv_view_search(self.p(), q.as_ptr(), 50, std::ptr::null(), out)
                })?)
            }
            ("library", []) => show(self.library()?),
            ("lens", words) => {
                let q = c(&words.join(" "));
                show(call(|out| unsafe { liv_lens(self.p(), q.as_ptr(), out) })?)
            }
            ("inbox", []) => show(call(|out| unsafe { liv_sweep(self.p(), out) })?),
            ("inbox", [id]) => {
                let id = self.id(id)?;
                show(call(|out| unsafe { liv_sweep_one(self.p(), id.as_ptr(), out) })?)
            }
            ("snapshot", []) => show(self.snapshot()?),
            ("history", []) => self.history(),
            ("probe", []) => show(call(|out| unsafe { liv_probe_box(self.p(), out) })?),
            ("file-alerts", []) => show(call(|out| unsafe { liv_file_alerts(self.p(), out) })?),
            _ => Err(format!("unknown command or wrong arguments: {verb} {}\n\n{USAGE}", a.join(" "))),
        }
    }

    /// `new KIND [NAME...] [--PROP VALUE]...` — the seeder. The kind by its
    /// word, one `liv_make`, then each property the way the app's picker
    /// writes it: a value of a property that holds one kind of thing is
    /// minted first (`liv_add_option` hands back the one that exists), then
    /// set — or added, where the property takes many.
    fn new_thing(&self, kind: &str, rest: &[&str]) -> Result<(), String> {
        let now = now_ms();
        let flag = rest.iter().position(|a| a.starts_with("--")).unwrap_or(rest.len());
        let (name, pairs) = rest.split_at(flag);
        if pairs.len() % 2 != 0 {
            return Err("every --PROP needs a VALUE".into());
        }
        let kind = id_field(call(|out| unsafe { liv_kind_named(self.p(), c(kind).as_ptr(), out) })?)?;
        let name = c(&name.join(" "));
        let made =
            id_field(call(|out| unsafe { liv_make(self.p(), kind.as_ptr(), name.as_ptr(), now, out) })?)?;
        for pair in pairs.chunks(2) {
            let prop = self.prop(pair[0].trim_start_matches("--"))?;
            let value = c(pair[1]);
            if prop.holds == "reference" {
                // Refused is the answer for a property that holds ANY
                // thing, which has no list to add to; the set below then
                // resolves the name or says it cannot.
                let _ = call(|out| unsafe {
                    liv_add_option(self.p(), prop.id.as_ptr(), value.as_ptr(), now, out)
                });
            }
            let f = if prop.many { liv_add } else { liv_set };
            written(unsafe { f(self.p(), made.as_ptr(), prop.id.as_ptr(), value.as_ptr(), now) })
                .map_err(|e| format!("{} = {}: {e}", pair[0], pair[1]))?;
        }
        println!("{}", made.to_str().unwrap_or_default());
        Ok(())
    }

    /// A body is spans; plain text is one text span. No `- [ ]` parsing
    /// here — the editor is the one parser of that grammar (rule 4).
    fn content_set(&self, id: &str, text: &str) -> Result<(), String> {
        let id = self.id(id)?;
        let base = call(|out| unsafe { liv_read_body(self.p(), id.as_ptr(), out) })?["print"]
            .as_u64()
            .unwrap_or(0);
        let spans = if text.is_empty() {
            json!([])
        } else {
            json!([{ "Text": { "text": text, "marks": 0 } }])
        };
        let spans = c(&spans.to_string());
        show(call(|out| unsafe {
            liv_write_body(self.p(), id.as_ptr(), spans.as_ptr(), base, now_ms(), out)
        })?)
    }

    /// Everything the Notes list could show, as a table: id, kind, title,
    /// due, status, area. `--all` adds what is in the trash.
    fn list(&self, all: bool) -> Result<(), String> {
        let mut rows: Vec<J> = self.library()?["all"].as_array().cloned().unwrap_or_default();
        if all {
            let bin = call(|out| unsafe { liv_view_trash(self.p(), out) })?;
            rows.extend(bin.as_array().cloned().unwrap_or_default());
        }
        let text = |r: &J, k: &str| r[k].as_str().unwrap_or("").to_owned();
        println!("{:<32}  {:<8} {:<32} {:<16} {:<8} {}", "id", "kind", "title", "due", "status", "area");
        for r in &rows {
            let due = r["due_ms"].as_i64().map(|ms| civil(ms, r["all_day"] == true)).unwrap_or_default();
            let mut title = text(r, "title");
            if r["trashed"] == true {
                title = format!("(trash) {title}");
            }
            println!(
                "{:<32}  {:<8} {:<32} {:<16} {:<8} {}",
                text(r, "id"),
                text(r, "kind_word"),
                title.chars().take(32).collect::<String>(),
                due,
                text(r, "status_word"),
                text(r, "area_word"),
            );
        }
        Ok(())
    }

    /// The library, as the app reads it after every write: every row, the
    /// Notes and Unsorted lists, and the panel's counts.
    fn library(&self) -> Result<J, String> {
        call(|o| unsafe {
            liv_view_library(self.p(), now_ms() as i64, local_offset_min(), std::ptr::null(), o)
        })
    }

    /// One refresh: the reads `BoxModel.loadEverything` makes after every
    /// write once each screen has been opened — the suggestions only while
    /// Unsorted is open — as one JSON object. The calendar's window is this
    /// month and the one either side.
    fn snapshot(&self) -> Result<J, String> {
        let p = self.p();
        Ok(json!({
            "library": self.library()?,
            "trash": call(|o| unsafe { liv_view_trash(p, o) })?,
            "suggestions": call(|o| unsafe { liv_sweep(p, o) })?,
            "workspaces": call(|o| unsafe { liv_workspaces(p, o) })?,
            "tasks": call(|o| unsafe {
                liv_view_tasks(p, std::ptr::null(), today(), std::ptr::null(), o)
            })?,
            "today": call(|o| unsafe {
                liv_view_today(p, now_ms() as i64, local_offset_min(), std::ptr::null(), o)
            })?,
            "calendar": call(|o| unsafe {
                liv_view_day(p, today() - 40, today() + 60, std::ptr::null(), o)
            })?,
            "assist": call(|o| unsafe { liv_assist(p, o) })?,
            "properties": call(|o| unsafe { liv_properties(p, o) })?,
            "kinds": call(|o| unsafe { liv_kinds(p, o) })?,
        }))
    }

    /// The log, oldest first, one line per transaction — the check that
    /// one user action wrote one group.
    fn history(&self) -> Result<(), String> {
        let e = liv_engine::Engine::open_local(std::path::Path::new(&self.file))
            .map_err(|e| format!("the box would not open: {e:?}"))?;
        let groups = e.groups().map_err(|e| format!("the log would not read: {e:?}"))?;
        for g in groups {
            let what = match g.action {
                liv_engine::action::CREATE => "create",
                liv_engine::action::SET => "set",
                liv_engine::action::ADD => "add",
                liv_engine::action::REMOVE => "remove",
                liv_engine::action::TRASH => "trash",
                liv_engine::action::RESTORE => "restore",
                liv_engine::action::RENAME => "rename",
                liv_engine::action::DECLARE => "declare",
                liv_engine::action::UNDO => "undo",
                _ => "other",
            };
            println!(
                "{:>6}  {}  {:<8} {:?}  {} op{}",
                g.first_seq,
                civil(g.hlc.wall_ms as i64, false),
                what,
                g.author,
                g.ops.len(),
                if g.ops.len() == 1 { "" } else { "s" },
            );
        }
        Ok(())
    }

    /// A property by its token (`area`, `tags`) or the word a person sees
    /// (`Subject`), compiled-in or declared.
    fn prop(&self, name: &str) -> Result<Prop, String> {
        let rows = call(|out| unsafe { liv_properties(self.p(), out) })?;
        let found = rows.as_array().into_iter().flatten().find(|r| {
            [&r["word"], &r["name"]].iter().any(|v| v.as_str().is_some_and(|s| s.eq_ignore_ascii_case(name)))
        });
        if let Some(r) = found {
            return Ok(Prop {
                id: c(r["id"].as_str().unwrap_or_default()),
                holds: r["holds"].as_str().unwrap_or("text").to_owned(),
                many: r["many"] == true,
            });
        }
        // Backstage properties (`name`, `private`, …) are not in the list
        // the inspector shows, and `liv_property_named` knows them.
        let named = call(|out| unsafe { liv_property_named(self.p(), c(name).as_ptr(), out) })
            .map_err(|_| format!("no property called {name}"))?;
        Ok(Prop { id: id_field(named)?, holds: "text".into(), many: false })
    }

    /// An id as typed: all 32 hex characters, or a part of one that only
    /// one thing's id contains, among everything and the trash. A part,
    /// not a prefix: things made in one second share their first twelve
    /// characters, and the device-seeded tail repeats between runs — the
    /// middle is what tells them apart.
    fn id(&self, raw: &str) -> Result<CString, String> {
        let raw = raw.to_ascii_lowercase();
        if raw.len() == 32 && raw.chars().all(|ch| ch.is_ascii_hexdigit()) {
            return Ok(c(&raw));
        }
        if raw.len() < 6 {
            return Err(format!("{raw}: give the whole id, or at least six characters of it"));
        }
        let mut ids: Vec<String> = Vec::new();
        for list in [
            self.library()?["all"].clone(),
            call(|out| unsafe { liv_view_trash(self.p(), out) })?,
        ] {
            for r in list.as_array().into_iter().flatten() {
                if let Some(id) = r["id"].as_str().filter(|id| id.contains(&raw)) {
                    ids.push(id.to_owned());
                }
            }
        }
        match ids.as_slice() {
            [one] => Ok(c(one)),
            [] => Err(format!("no thing's id contains {raw}")),
            _ => Err(format!("{} things' ids contain {raw}; give more of it", ids.len())),
        }
    }
}

struct Prop {
    id: CString,
    holds: String,
    many: bool,
}

// ---- the ABI's calling convention ---------------------------------------

/// Call a verb that answers through an out-pointer, and free the answer.
fn call(f: impl FnOnce(*mut *mut c_char) -> i32) -> Result<J, String> {
    let mut out: *mut c_char = std::ptr::null_mut();
    let code = f(&mut out);
    if code != LIV_OK {
        return Err(fault(code));
    }
    if out.is_null() {
        return Ok(J::Null);
    }
    let text = unsafe { CStr::from_ptr(out) }.to_string_lossy().into_owned();
    unsafe { liv_ffi::liv_string_free(out) };
    serde_json::from_str(&text).map_err(|e| format!("the answer was not JSON: {e}"))
}

/// A write's answer, said out loud: `ok`, or why not.
fn status(code: i32) -> Result<(), String> {
    written(code)?;
    println!("ok");
    Ok(())
}

fn written(code: i32) -> Result<(), String> {
    if code == LIV_OK {
        Ok(())
    } else {
        Err(fault(code))
    }
}

/// The ABI's codes, in words. A write refused while the app holds the box
/// comes back as `open` — the engine sets no busy timeout, so a CLI write
/// racing the app is refused rather than waited on.
fn fault(code: i32) -> String {
    let word = match code {
        LIV_ERR_PATH => "no such path",
        LIV_ERR_OPEN => "the box would not open (in use, or not a box)",
        LIV_ERR_ARG => "an argument was not understood",
        LIV_ERR_READ => "the box would not read",
        LIV_ERR_ENCODE => "the answer would not encode",
        LIV_ERR_STALE => "stale: the body changed underneath",
        LIV_ERR_REFUSED => "refused: that value does not belong there",
        LIV_ERR_NOTHING => "nothing to do",
        _ => "failed",
    };
    format!("{word} (code {code})")
}

fn id_field(v: J) -> Result<CString, String> {
    v["id"].as_str().map(c).ok_or_else(|| format!("no id in the answer: {v}"))
}

fn show(v: J) -> Result<(), String> {
    println!("{}", serde_json::to_string_pretty(&v).unwrap_or_default());
    Ok(())
}

fn c(s: &str) -> CString {
    CString::new(s.replace('\0', "")).expect("no NUL left")
}

// ---- time ---------------------------------------------------------------

/// The wall clock — or `LIV_NOW_MS`, so a box can be seeded as it would
/// look after a week of use (the trash's Today / Yesterday / Earlier needs
/// things thrown away on other days). Writes must still go forward in
/// time: the engine's clock never runs backwards, so seed oldest first.
fn now_ms() -> u64 {
    if let Some(ms) = std::env::var("LIV_NOW_MS").ok().and_then(|v| v.parse().ok()) {
        return ms;
    }
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// Today, as the app counts it: the LOCAL date, in days since the epoch.
/// This machine's distance from UTC, in minutes — what the phone passes.
fn local_offset_min() -> i32 {
    chrono::Local::now().offset().local_minus_utc() / 60
}

fn today() -> i32 {
    use chrono::Datelike;
    let d = chrono::Local::now().date_naive();
    liv_engine::days_from_civil(d.year(), d.month(), d.day())
}

fn day_of(raw: &str) -> Result<i32, String> {
    let parts: Vec<&str> = raw.split('-').collect();
    match parts.as_slice() {
        [y, m, d] => Ok(liv_engine::days_from_civil(
            y.parse().map_err(|_| format!("not a date: {raw}"))?,
            m.parse().map_err(|_| format!("not a date: {raw}"))?,
            d.parse().map_err(|_| format!("not a date: {raw}"))?,
        )),
        _ => Err(format!("not a date (YYYY-MM-DD): {raw}")),
    }
}

/// A stamp for a person: "2026-09-13 14:30", or the day alone.
fn civil(ms: i64, day_only: bool) -> String {
    let (y, m, d) = liv_engine::civil_from_days(ms.div_euclid(86_400_000) as i32);
    if day_only {
        return format!("{y:04}-{m:02}-{d:02}");
    }
    let min = ms.rem_euclid(86_400_000) / 60_000;
    format!("{y:04}-{m:02}-{d:02} {:02}:{:02}", min / 60, min % 60)
}
