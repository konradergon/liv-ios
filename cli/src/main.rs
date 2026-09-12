//! liv — the headless CLI, and the VERIFICATION tool.
//!
//! It was written as a stand-in for a shell that had not arrived. One has:
//! `shell/ios` is the app. So this is not a placeholder any more, it is the
//! second reader of the same box — the way to check what the app claims,
//! from outside the app (CLAUDE.md: "cross-check writes against the box
//! with the CLI. A builder's own report is not evidence").
//!
//! That job sets its rule: it should reach every verb the shell can reach.
//! On 2026-09-05 it did not — no undo, trash, restore, search, snapshot or
//! birth verbs — and each gap was a thing the app could do that nothing
//! else could confirm. Those are here now. What is still missing is named
//! in the usage line, not in a comment that can drift from it.
//!
//! Still the thinnest possible orchestrator: parse arguments, open the
//! session, run services, print what the renderer emitted. It owns no data
//! and defines no commands.

mod satellite;

use chrono::{Datelike, Local, Timelike};

use liv_core::{props, Author, DateTime, Id, Session, Value};
use liv_services::{Constraint, Op, Query, Sort};
use liv_views::{render, Config, Density, Rendered};

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if let Err(message) = dispatch(&args) {
        eprintln!("liv: {message}");
        std::process::exit(1);
    }
}

/// The CLI and the menu-bar shell share one box by default.
/// The store's location is one of the budgeted settings; --log overrides.
fn default_log_path() -> String {
    match std::env::var("HOME") {
        Ok(home) => {
            let path = format!("{home}/Library/Application Support/liv/liv.log");
            // Boxes born before the product rename stay where they are: fall
            // back to the codename-era location while the new one doesn't exist.
            let legacy = format!("{home}/Library/Application Support/lotus/lotus.log");
            if !std::path::Path::new(&path).exists() && std::path::Path::new(&legacy).exists() {
                return legacy;
            }
            path
        }
        Err(_) => "liv.log".to_string(),
    }
}

fn dispatch(args: &[String]) -> Result<(), String> {
    let mut log_path = default_log_path();
    let mut rest: Vec<&str> = Vec::new();
    let mut i = 0;
    while i < args.len() {
        if args[i] == "--log" {
            i += 1;
            log_path = args.get(i).ok_or("--log needs a path")?.clone();
        } else {
            rest.push(&args[i]);
        }
        i += 1;
    }

    if let Some(dir) = std::path::Path::new(&log_path).parent() {
        std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }

    // Satellite export (design/ios.md §2.2) reads through the ffi seam, which
    // opens — and locks — the box itself, so it must run before this process
    // takes the session lock below.
    if let Some((&"satellite-export", export_args)) = rest.split_first() {
        let root = export_args
            .first()
            .ok_or("usage: liv satellite-export SATELLITE-ROOT")?;
        return satellite::export(&log_path, root);
    }

    // THE SNAPSHOT the shell decodes, printed verbatim — the one command
    // that can answer "is the app showing what the box holds?" for the
    // seven wire sections no other CLI command reaches (trashed, inbox,
    // assist, workspaces, views, noteTasks, occurrences).
    //
    // It goes here, above `Session::open`, for the same reason
    // satellite-export does: it reads through the C seam, which opens and
    // LOCKS the box itself, and the session below already holds that lock.
    if let Some((&"snapshot", flags)) = rest.split_first() {
        return snapshot(&log_path, flags);
    }

    let mut session = Session::open(&log_path).map_err(|e| e.to_string())?;
    liv_services::seed_if_fresh(&mut session).map_err(|e| e.to_string())?;

    // The clerk sweeps at every open; duplicates of anything pending or
    // declined never reach the queue.
    // One durable write. The CLI has no store cache, so EVERY invocation
    // is a cold open and paid the whole per-proposal fsync loop.
    session
        .propose_all(liv_services::clerk::sweep(session.store(), civil_today()))
        .map_err(|e| e.to_string())?;

    match rest.split_first() {
        None | Some((&"today", _)) => {
            today(&session);
            Ok(())
        }
        Some((&"add", text)) if !text.is_empty() => add(&mut session, &text.join(" ")),
        Some((&"list", flags)) => list(&session, flags),
        Some((&"inbox", _)) => {
            inbox(&session);
            Ok(())
        }
        Some((&"accept", target)) => accept(&mut session, target),
        Some((&"reject", target)) => reject(&mut session, target),
        Some((&"name", rest)) => name(&mut session, rest),
        Some((&"set", rest)) => set(&mut session, rest),
        Some((&"route", rest)) => route(&mut session, rest),
        Some((&"history", _)) => {
            history(&session);
            Ok(())
        }
        // P20j.5 — the vault door from the CLI: the same services seams
        // the shell drives, honoring the projector lock.
        Some((&"vault", sub)) => vault(&mut session, &log_path, sub),
        Some((&"habit", rest)) if !rest.is_empty() => habit_add(&mut session, rest),
        Some((&"checkin", rest)) if !rest.is_empty() => checkin(&mut session, rest),
        Some((&"habits", _)) => {
            habits(&session);
            Ok(())
        }
        Some((&"time", rest)) => time(&mut session, rest),
        Some((&"rename-value", rest)) => rename_value(&mut session, rest),
        // The satellite drain (design/ios.md §2.2): the phone's outbox
        // becomes box entities, one transaction per batch.
        Some((&"drain", rest)) => satellite::drain(&mut session, rest),
        // THE VERBS THE SHELL HAD AND THIS DID NOT (2026-09-05).
        Some((&"undo", rest)) => step_back(&mut session, rest, false),
        Some((&"redo", rest)) => step_back(&mut session, rest, true),
        Some((&"trash", rest)) => trash(&mut session, rest),
        Some((&"restore", rest)) => restore(&mut session, rest),
        Some((&"new", rest)) => birth(&mut session, rest),
        Some((&"content", rest)) => content(&session, rest),
        // The shell's History card reads this seam (2026-09-09); the
        // verification tool keeps every verb the shell can reach.
        Some((&"versions", rest)) => versions(&session, rest),
        Some((&"content-set", rest)) => content_set(&mut session, rest),
        Some((&"export", rest)) => export(&session, rest),
        Some((&"search", words)) if !words.is_empty() => find(&session, &log_path, words, false),
        Some((&"lens", words)) if !words.is_empty() => find(&session, &log_path, words, true),
        _ => Err("usage: liv [--log FILE] [today] | add TEXT... | \
                  list [--where P=V|P!=V|P?] [--sort P] [--desc] [--columns A,B,C] [--all] | \
                  inbox | accept ID [K] | reject ID [K] | name ID TEXT... | \
                  set ID PROP VALUE... | history | \
                  habit NAME... [--points N] [--cadence TEXT] | \
                  checkin HABIT-ID [DAY] | habits | \
                  time [TARGET-ID START END] | rename-value PROP OLD NEW... | \
                  drain SATELLITE-ROOT | satellite-export SATELLITE-ROOT | \
                  snapshot [--window FROM-YYYYMMDDHHMM TO-YYYYMMDDHHMM] | \
                  undo [N] | redo [N] | trash ID | restore ID | \
                  new note|task|event [NAME...] | \
                  content ID | content-set ID [--base N] TEXT... | versions ID | \
                  search WORDS... | lens WORDS... | \
                  export ID[,ID...] DEST [--group-by PROP]"
            .into()),
    }
}

/// Name an entity: one cell, front of house. Names feed the gazetteer,
/// so the mentions proposer has something to notice.
fn name(session: &mut Session, rest: &[&str]) -> Result<(), String> {
    let (id_arg, words) = rest.split_first().ok_or("usage: liv name ID TEXT...")?;
    let id: Id = id_arg
        .trim_start_matches('#')
        .parse()
        .map_err(|_| format!("not an entity id: {id_arg}"))?;
    if session.store().get(id).is_none() {
        return Err(format!("no entity #{id}"));
    }
    if words.is_empty() {
        return Err("usage: liv name ID TEXT...".into());
    }
    let text = words.join(" ");
    session
        .commit(
            vec![liv_core::Command::AddCell {
                entity: id,
                cell: liv_core::Cell {
                    property: props::NAME,
                    value: Value::text(&text),
                },
            }],
            format!("name {text}"),
            Author::User,
        )
        .map_err(|e| e.to_string())?;
    println!("#{id} is now \"{text}\"");
    Ok(())
}

fn civil_today() -> DateTime {
    let now = Local::now();
    DateTime::date(now.year(), now.month(), now.day())
}

/// Today: the orientation surface, v0 — a dedicated list built from the
/// one lens that exists. Board-or-list stays open until daily use decides.
/// The sections come from services, so every shell shows the same morning.
fn today(session: &Session) {
    let store = session.store();
    let list_config = Config {
        density: Density::List,
        columns: vec![],
    };

    let sections = liv_services::today_sections(store, civil_today());
    if !sections.due.is_empty() {
        println!("due through today:");
        print_table(&render(store, &sections.due, &list_config));
        println!();
    }
    if !sections.unstructured.is_empty() {
        println!("captured, unstructured:");
        print_table(&render(store, &sections.unstructured, &list_config));
        println!();
    }

    match store.pending().len() {
        0 => {}
        1 => println!("1 proposal waiting — liv inbox"),
        n => println!("{n} proposals waiting — liv inbox"),
    }
}

/// Set one property to one value — the shared parser and replace-the-cell
/// semantics live in services; the window's inspector uses the same door.
/// `liv route ID TYPE` — stamp a scrap's type by NAME (set_property
/// can't: TYPE is a reference and wants "#id", but type entities are
/// backstage plumbing). The FFI shell has liv_set_type_at; the CLI
/// gets its own door so a captured scrap can be routed to a projectable
/// kind (note/task/person/…).
fn route(session: &mut Session, rest: &[&str]) -> Result<(), String> {
    let (id_arg, type_words) = rest.split_first().ok_or("usage: liv route ID TYPE")?;
    let id: Id = id_arg
        .trim_start_matches('#')
        .parse()
        .map_err(|_| format!("not an entity id: {id_arg}"))?;
    let type_name = type_words.join(" ");
    if type_name.is_empty() {
        return Err("usage: liv route ID TYPE".into());
    }
    liv_services::content::set_type(session, id, &type_name).map_err(|e| format!("{e:?}"))?;
    println!("#{id} → {type_name}");
    Ok(())
}

fn set(session: &mut Session, rest: &[&str]) -> Result<(), String> {
    let (id_arg, rest) = rest.split_first().ok_or("usage: liv set ID PROP VALUE...")?;
    let (prop_name, words) = rest.split_first().ok_or("usage: liv set ID PROP VALUE...")?;
    let id: Id = id_arg
        .trim_start_matches('#')
        .parse()
        .map_err(|_| format!("not an entity id: {id_arg}"))?;
    if words.is_empty() {
        return Err("usage: liv set ID PROP VALUE...".into());
    }
    let raw = words.join(" ");
    liv_services::content::set_property(session, id, prop_name, &raw)?;
    println!("#{id} {prop_name} = {raw}");
    Ok(())
}

/// The inbox: the shell's one surface that is not a view. Proposals are
/// addressed by their subject's entity id — stable across invocations —
/// never by queue position, which shifts as the queue is triaged.
fn inbox(session: &Session) {
    let pending = session.store().pending();
    if pending.is_empty() {
        println!("(nothing waiting)");
        return;
    }
    for (i, proposal) in pending.iter().enumerate() {
        let author = match &proposal.author {
            Author::Proposer(name) => name.clone(),
            Author::User => "user".into(),
            Author::System => "system".into(),
        };
        let subject = subject_of(proposal);
        let nth = pending[..i]
            .iter()
            .filter(|p| subject_of(p) == subject)
            .count();
        let key = match subject {
            Some(id) if nth > 0 => format!("#{id} {}", nth + 1),
            Some(id) => format!("#{id}"),
            None => String::new(),
        };
        println!("{key:<10} {}  ({author})", proposal.reason);
    }
    println!("\nliv accept ID | liv reject ID   (add K when an id lists twice)");
}

fn subject_of(proposal: &liv_core::Proposal) -> Option<Id> {
    proposal.commands.first().map(|c| match c {
        liv_core::Command::Create { entity }
        | liv_core::Command::Trash { entity }
        | liv_core::Command::Restore { entity }
        | liv_core::Command::AddCell { entity, .. }
        | liv_core::Command::RemoveCell { entity, .. }
        | liv_core::Command::Redirect { entity, .. } => *entity,
    })
}

/// Resolve "ID [K]" against the queue as it exists right now.
fn resolve_target(session: &Session, args: &[&str]) -> Result<usize, String> {
    let id_arg = args
        .first()
        .ok_or("which one? liv inbox shows the ids")?;
    let id: Id = id_arg
        .trim_start_matches('#')
        .parse()
        .map_err(|_| format!("not an entity id: {id_arg}"))?;
    let matching: Vec<usize> = session
        .store()
        .pending()
        .iter()
        .enumerate()
        .filter(|(_, p)| subject_of(p) == Some(id))
        .map(|(i, _)| i)
        .collect();
    match (matching.len(), args.get(1)) {
        (0, _) => Err(format!("no proposal for #{id} — liv inbox")),
        (1, _) => Ok(matching[0]),
        (n, Some(k)) => {
            let k: usize = k.parse().map_err(|_| format!("not a number: {k}"))?;
            if k >= 1 && k <= n {
                Ok(matching[k - 1])
            } else {
                Err(format!("#{id} has {n} proposals — K is 1..={n}"))
            }
        }
        (n, None) => Err(format!(
            "#{id} has {n} proposals — liv inbox, then accept/reject {id} K"
        )),
    }
}

fn accept(session: &mut Session, args: &[&str]) -> Result<(), String> {
    let index = resolve_target(session, args)?;
    let label = session.store().pending()[index].label.clone();
    session.accept(index).map_err(|e| e.to_string())?;
    println!("accepted: {label}");
    Ok(())
}

fn reject(session: &mut Session, args: &[&str]) -> Result<(), String> {
    let index = resolve_target(session, args)?;
    let reason = session.store().pending()[index].reason.clone();
    session.reject(index).map_err(|e| e.to_string())?;
    println!("declined: {reason}  — the clerk won't ask again");
    Ok(())
}

/// Capture, CLI-grade: same scrap, same door as the menu-bar shell.
fn add(session: &mut Session, text: &str) -> Result<(), String> {
    let now = Local::now();
    let created = DateTime::at(
        now.year(),
        now.month(),
        now.day(),
        now.hour(),
        now.minute(),
    );
    let scrap = liv_services::capture(session, text, created).map_err(|e| e.to_string())?;
    println!("#{scrap}");

    // The clerk runs behind the write; whatever it noticed shows at once.
    let already = session.store().pending().len();
    session
        .propose_all(liv_services::clerk::sweep(session.store(), civil_today()))
        .map_err(|e| e.to_string())?;
    for proposal in session.store().pending().iter().skip(already) {
        let subject = subject_of(proposal)
            .map(|id| format!("{id}"))
            .unwrap_or_default();
        println!("clerk: {}  (liv accept {subject})", proposal.reason);
    }
    Ok(())
}

fn list(session: &Session, flags: &[&str]) -> Result<(), String> {
    let store = session.store();
    let mut query = Query::default();
    let mut columns: Vec<Id> = Vec::new();
    let mut descending = false;

    let mut i = 0;
    while i < flags.len() {
        match flags[i] {
            "--where" => {
                i += 1;
                let raw = flags.get(i).ok_or("--where needs P=V, P!=V or P?")?;
                query.constraints.push(parse_constraint(store, raw)?);
            }
            "--sort" => {
                i += 1;
                let name = flags.get(i).ok_or("--sort needs a property")?;
                query.sort = Some(Sort {
                    property: property_by_name(store, name)?,
                    descending: false,
                });
            }
            "--desc" => descending = true,
            "--columns" => {
                i += 1;
                let names = flags.get(i).ok_or("--columns needs A,B,C")?;
                for name in names.split(',') {
                    columns.push(property_by_name(store, name.trim())?);
                }
            }
            "--all" => {
                query.include_working = true;
                query.include_trashed = true;
            }
            other => return Err(format!("unknown flag {other}")),
        }
        i += 1;
    }
    if let Some(sort) = &mut query.sort {
        sort.descending = descending;
    }

    let results = liv_services::run(store, &query);
    let config = if columns.is_empty() {
        Config {
            density: Density::List,
            columns: vec![],
        }
    } else {
        Config {
            density: Density::Table,
            columns,
        }
    };
    print_table(&render(store, &results, &config));
    Ok(())
}

/// P=V, P!=V, or P? — the v0 operators, spelled flat.
fn parse_constraint(store: &liv_core::Store, raw: &str) -> Result<Constraint, String> {
    if let Some(name) = raw.strip_suffix('?') {
        return Ok(Constraint {
            property: property_by_name(store, name)?,
            op: Op::Exists,
        });
    }
    if let Some((name, value)) = raw.split_once("!=") {
        return Ok(Constraint {
            property: property_by_name(store, name)?,
            op: Op::NotEquals(Value::text(value)),
        });
    }
    if let Some((name, value)) = raw.split_once('=') {
        return Ok(Constraint {
            property: property_by_name(store, name)?,
            op: Op::Equals(Value::text(value)),
        });
    }
    Err(format!("cannot parse constraint {raw}"))
}

fn property_by_name(store: &liv_core::Store, name: &str) -> Result<Id, String> {
    liv_services::property_id(store, name).ok_or(format!("no property named {name}"))
}

fn print_table(rendered: &Rendered) {
    if rendered.rows.is_empty() {
        println!("(nothing)");
        return;
    }
    // Column widths from content; the id column leads.
    let mut widths: Vec<usize> = rendered
        .header
        .iter()
        .map(|h| h.chars().count())
        .collect();
    for row in &rendered.rows {
        for (i, cell) in row.cells.iter().enumerate() {
            widths[i] = widths[i].max(cell.chars().count());
        }
    }
    let id_width = rendered
        .rows
        .iter()
        .map(|r| format!("#{}", r.id).len())
        .max()
        .unwrap_or(2);

    let header: Vec<String> = rendered
        .header
        .iter()
        .enumerate()
        .map(|(i, h)| format!("{h:<width$}", width = widths[i]))
        .collect();
    println!("{:<id_width$}  {}", "", header.join("  "));
    for row in &rendered.rows {
        let cells: Vec<String> = row
            .cells
            .iter()
            .enumerate()
            .map(|(i, c)| format!("{c:<width$}", width = widths[i]))
            .collect();
        println!("{:<id_width$}  {}", format!("#{}", row.id), cells.join("  "));
    }
}

/// The log, human-readable: when, who, what. Provenance on display.
fn history(session: &Session) {
    for tx in session.store().history() {
        let author = match &tx.author {
            Author::User => "user".to_string(),
            Author::Proposer(name) => format!("proposer:{name}"),
            Author::System => "system".to_string(),
        };
        let reverses = tx
            .reverses
            .map(|seq| format!(" (reverses {seq})"))
            .unwrap_or_default();
        println!(
            "{:>4}  {:<16} {} [{} command{}]{}",
            tx.seq,
            author,
            tx.label,
            tx.commands.len(),
            if tx.commands.len() == 1 { "" } else { "s" },
            reverses
        );
    }
}

/// P18b: birth a habit (front of house). `liv habit Climb --points 2`.
fn habit_add(session: &mut Session, rest: &[&str]) -> Result<(), String> {
    let mut points: Option<f64> = None;
    let mut cadence: Option<String> = None;
    let mut words: Vec<&str> = Vec::new();
    let mut iter = rest.iter();
    while let Some(arg) = iter.next() {
        match *arg {
            "--points" => {
                points = iter.next().and_then(|v| v.parse().ok());
            }
            "--cadence" => {
                cadence = iter.next().map(|v| v.to_string());
            }
            word => words.push(word),
        }
    }
    if words.is_empty() {
        return Err("usage: liv habit NAME... [--points N] [--cadence TEXT]".into());
    }
    let id = liv_services::content::create_habit(
        session,
        &words.join(" "),
        points,
        cadence.as_deref(),
        civil_today(),
    )
    .map_err(|e| e.to_string())?;
    println!("habit #{id}");
    Ok(())
}

/// P18b: check a habit in (today, or a given civil day) — idempotent.
fn checkin(session: &mut Session, rest: &[&str]) -> Result<(), String> {
    let (id_arg, day_arg) = rest.split_first().ok_or("usage: liv checkin HABIT-ID [DAY]")?;
    let habit: Id =
        id_arg.trim_start_matches('#').parse().map_err(|_| "HABIT-ID must be a number")?;
    let day: i64 = match day_arg.first() {
        Some(d) => d.parse().map_err(|_| "DAY must be YYYYMMDD")?,
        None => civil_today().civil / 10_000,
    };
    let row = liv_services::content::check_in(session, habit, day, civil_today())
        .map_err(|e| e.to_string())?;
    println!("checked in #{row} ({day})");
    Ok(())
}

/// P18b: the habit card, in text — the same projection every shell reads.
fn habits(session: &Session) {
    let today = civil_today().civil / 10_000;
    let stats = liv_services::habits::habit_stats(session.store(), today);
    if stats.habits.is_empty() {
        println!("no habits yet — liv habit NAME [--points N]");
        return;
    }
    for line in &stats.habits {
        let mark = if line.today_check_in.is_some() { "x" } else { " " };
        let cadence = line.cadence.as_deref().unwrap_or("");
        println!("[{mark}] #{:<5} {:<28} +{} {}", line.id, line.name, line.points, cadence);
    }
    println!(
        "streak {}d · longest {}d · {} pts this week · {:.1} avg/active day",
        stats.streak, stats.longest, stats.week_points, stats.avg_active
    );
    let glyphs = [" ", "░", "▒", "▓"];
    let chain: String = stats
        .heat
        .iter()
        .map(|c| glyphs[(*c as usize).min(3)])
        .collect();
    println!("chain [{chain}]");
}

/// P18d: log a closed interval (`liv time ID 202607140900 202607141030`),
/// or with no args print the week's totals — the same projection the shell
/// reads.
fn time(session: &mut Session, rest: &[&str]) -> Result<(), String> {
    if rest.is_empty() {
        let today = civil_today().civil / 10_000;
        let summary = liv_services::timeviews::time_totals(session.store(), today);
        if summary.totals.is_empty() {
            println!("no time logged this week");
            return Ok(());
        }
        for total in &summary.totals {
            println!("#{:<5} {:<28} {}h {:02}m", total.target, total.name, total.minutes / 60, total.minutes % 60);
        }
        return Ok(());
    }
    let (id_arg, stamps) = rest.split_first().unwrap();
    let target: Id =
        id_arg.trim_start_matches('#').parse().map_err(|_| "TARGET-ID must be a number")?;
    let (start, end) = match stamps {
        [s, e] => (
            s.parse::<i64>().map_err(|_| "START must be YYYYMMDDHHMM")?,
            e.parse::<i64>().map_err(|_| "END must be YYYYMMDDHHMM")?,
        ),
        _ => return Err("usage: liv time TARGET-ID START END".into()),
    };
    let to_dt = |civil: i64| {
        DateTime::at(
            (civil / 100_000_000) as i32,
            ((civil / 1_000_000) % 100) as u32,
            ((civil / 10_000) % 100) as u32,
            ((civil / 100) % 100) as u32,
            (civil % 100) as u32,
        )
    };
    let id = liv_services::content::log_time(session, target, to_dt(start), to_dt(end))
        .map_err(|e| e.to_string())?;
    println!("logged #{id}");
    Ok(())
}

/// P19b: `liv rename-value subject uni university` — one transaction,
/// the true carrier count, one undo.
fn rename_value(session: &mut Session, rest: &[&str]) -> Result<(), String> {
    let (prop, rest) = rest.split_first().ok_or("usage: liv rename-value PROP OLD NEW...")?;
    let (old, new_words) = rest.split_first().ok_or("usage: liv rename-value PROP OLD NEW...")?;
    if new_words.is_empty() {
        return Err("usage: liv rename-value PROP OLD NEW...".into());
    }
    let new = new_words.join(" ");
    let count = liv_services::content::rename_value(session, prop, old, &new)
        .map_err(|e| format!("{e:?}"))?;
    println!("renamed {old} -> {new} on {count} carriers (one undo restores)");
    Ok(())
}


/// `liv vault status|sync|rebuild` (P20j.5): the projection from the
/// CLI. Legacy boxes (no `.liv/box/` ancestor) report and refuse — the
/// projection never turns itself on.
fn vault(session: &mut Session, log_path: &str, sub: &[&str]) -> Result<(), String> {
    use liv_services::projection as proj;
    let Some(root) = proj::vault_root_of(std::path::Path::new(log_path)) else {
        println!("legacy box — no vault (the box is not at <root>/.liv/box/)");
        return Ok(());
    };
    match sub.first() {
        None | Some(&"status") => {
            let io = proj::RealVaultIo::new(&root);
            let manifest = proj::load_manifest(&io);
            println!("vault: {}", root.display());
            println!("files: {}", manifest.rows.len());
            let findings = proj::scan(&io, session.store(), &manifest);
            if findings.is_empty() {
                println!("in sync — nothing diverges");
            } else {
                println!("{} finding(s) — run `liv vault sync`", findings.len());
            }
            Ok(())
        }
        Some(&"sync") => {
            let io = proj::RealVaultIo::new(&root);
            let mut manifest = proj::load_manifest(&io);
            let findings = proj::scan(&io, session.store(), &manifest);
            let outcome = proj::ingest(session, &io, &manifest, &findings)
                .map_err(|e| format!("{e:?}"))?;
            proj::adopt_into(&mut manifest, &outcome.adopted);
            let (ops, next) = proj::plan_projection(session.store(), &manifest);
            proj::apply_locked(&root, &ops, &next).map_err(|e| e.to_string())?;
            println!(
                "synced — {} edited · {} created · {} surfaced (cards wait in the app)",
                outcome.edited, outcome.created, outcome.surfaced
            );
            Ok(())
        }
        Some(&"rebuild") => {
            let (ops, next) =
                proj::plan_projection(session.store(), &proj::Manifest::default());
            proj::apply_locked(&root, &ops, &next).map_err(|e| e.to_string())?;
            println!("rebuilt — {} file(s) materialized from the log", next.rows.len());
            Ok(())
        }
        Some(other) => Err(format!("unknown vault subcommand: {other}")),
    }
}

// ---- the verbs the shell had and this did not (2026-09-05) ----

/// THE WHOLE SNAPSHOT, as JSON, exactly as the shell decodes it.
///
/// `list` renders a table through `liv-views`; this prints the wire. They
/// answer different questions: `list` says what the box holds, this says
/// what the app was HANDED. Seven sections have no other reader outside
/// the app — trashed, inbox, assist, workspaces, views, noteTasks,
/// occurrences — so a bug in any of them was previously only visible on
/// a phone screen.
fn snapshot(log_path: &str, flags: &[&str]) -> Result<(), String> {
    let json = match flags {
        [] => satellite::snapshot_json(log_path)?,
        ["--window", from, to] => {
            let from: i64 = from.parse().map_err(|_| "--window FROM must be YYYYMMDDHHMM")?;
            let to: i64 = to.parse().map_err(|_| "--window TO must be YYYYMMDDHHMM")?;
            satellite::snapshot_window_json(log_path, from, to)?
        }
        _ => return Err("usage: liv snapshot [--window FROM TO]".into()),
    };
    println!("{json}");
    Ok(())
}

/// UNDO, AND REDO. The shell has only the first — there is no `liv_redo_at`
/// verb, so the app's undo is one-way (design/spec-alignment.md) — but
/// `Session::redo` exists and the CLI links the crate rather than the C
/// ABI, so it can reach it. That asymmetry is worth being able to
/// demonstrate rather than only describe.
///
/// N repeats, because the Inbox's undo chip is itself a loop: one tap
/// there reverses a whole accept-all.
fn step_back(session: &mut Session, rest: &[&str], forward: bool) -> Result<(), String> {
    let times: u32 = match rest.first() {
        None => 1,
        Some(n) => n.parse().map_err(|_| format!("not a count: {n}"))?,
    };
    let word = if forward { "redo" } else { "undo" };
    for step in 0..times {
        let done = if forward {
            session.redo(Author::User)
        } else {
            session.undo(Author::User)
        };
        match done {
            Ok(seq) => println!("{word} → seq {seq}"),
            Err(e) => {
                if step == 0 {
                    return Err(e.to_string());
                }
                println!("nothing left to {word} after {step}");
                return Ok(());
            }
        }
    }
    Ok(())
}

/// The id every command takes: bare or with a leading '#'.
fn entity_id(arg: &str) -> Result<Id, String> {
    arg.trim_start_matches('#')
        .parse()
        .map_err(|_| format!("not an entity id: {arg}"))
}

/// TRASH — the same seam both shell verbs use. `liv_trash_at` and
/// `liv_trash_workspace_at` both land on `content::trash_workspace`, so
/// one command covers the pair.
fn trash(session: &mut Session, rest: &[&str]) -> Result<(), String> {
    let id = entity_id(rest.first().ok_or("usage: liv trash ID")?)?;
    if session.store().get(id).is_none() {
        return Err(format!("no entity #{id}"));
    }
    liv_services::content::trash_workspace(session, id).map_err(|e| format!("{e:?}"))?;
    println!("#{id} → Trash");
    Ok(())
}

/// RESTORE — the other half, and the reason the verb was added in August:
/// a door that only goes one way is the bug, not the feature.
fn restore(session: &mut Session, rest: &[&str]) -> Result<(), String> {
    let id = entity_id(rest.first().ok_or("usage: liv restore ID")?)?;
    if session.store().get(id).is_none() {
        return Err(format!("no entity #{id}"));
    }
    session
        .commit(
            vec![liv_core::Command::Restore { entity: id }],
            format!("restore {id}"),
            Author::User,
        )
        .map_err(|e| e.to_string())?;
    println!("#{id} restored");
    Ok(())
}

/// BIRTH: note, task or event.
///
/// `add` is CAPTURE — an untyped scrap the clerk quarantines — and
/// `route` types one afterwards. That pair is NOT the same as being born:
/// `create_task` writes the type's default status in the SAME
/// transaction, and `create_event` writes a due cell at birth. A CLI
/// task built the old way differed from an app task in its cells, which
/// is exactly the kind of drift this tool exists to catch.
fn birth(session: &mut Session, rest: &[&str]) -> Result<(), String> {
    let (kind, words) = rest
        .split_first()
        .ok_or("usage: liv new note|task|event [NAME...]")?;
    let now = civil_today();
    let id = match *kind {
        "note" => liv_services::content::create_note(session, now),
        "task" => liv_services::content::create_task(session, now),
        // The app dates an event from the surface you stand on; the CLI
        // stands nowhere, so today at 09:00 — the same default the bar
        // uses when it has no day of its own.
        "event" => liv_services::content::create_event(session, now, now),
        other => return Err(format!("liv new takes note, task or event, not {other}")),
    }
    .map_err(|e| e.to_string())?;
    if !words.is_empty() {
        let text = words.join(" ");
        session
            .commit(
                vec![liv_core::Command::AddCell {
                    entity: id,
                    cell: liv_core::Cell {
                        property: props::NAME,
                        value: Value::text(&text),
                    },
                }],
                format!("name {text}"),
                Author::User,
            )
            .map_err(|e| e.to_string())?;
    }
    println!("#{id} is a new {kind}");
    Ok(())
}

/// A NOTE'S BODY, with its LINE STRUCTURE and its fingerprint.
///
/// `list --columns content` already prints the words, but the renderer
/// flattens every break to a space — and the Tasks view's "In notes"
/// section is projected off exactly those lines, so a flattened body
/// cannot answer whether a checkbox line is really there. This prints one
/// line per break and the fingerprint the editor's compare-and-swap uses.
/// Every past version of one entity's content, NEWEST first — the same
/// list the phone's History card draws. `seq` is what a restore appends
/// after, so `versions` before and after a restore is how you prove the
/// log was appended to and never rewritten.
fn versions(session: &Session, rest: &[&str]) -> Result<(), String> {
    let id = entity_id(rest.first().ok_or("usage: liv versions ID")?)?;
    let store = session.store();
    store.get(id).ok_or(format!("no entity #{id}"))?;
    let mut list = liv_services::content::content_history(store, id);
    list.reverse();
    if list.is_empty() {
        println!("no content versions for #{id}");
        return Ok(());
    }
    for v in &list {
        let author = match &v.author {
            Author::User => "user".to_string(),
            Author::Proposer(name) => format!("proposer:{name}"),
            Author::System => "system".to_string(),
        };
        println!(
            "{:>4}  {}  {:<16} {} [{} span{}]",
            v.seq,
            v.time,
            author,
            v.label,
            v.spans.len(),
            if v.spans.len() == 1 { "" } else { "s" }
        );
    }
    Ok(())
}

fn content(session: &Session, rest: &[&str]) -> Result<(), String> {
    let id = entity_id(rest.first().ok_or("usage: liv content ID")?)?;
    let store = session.store();
    let entity = store.get(id).ok_or(format!("no entity #{id}"))?;
    let spans = liv_services::content::content_spans(entity);
    let fingerprint = liv_services::content::content_fingerprint(entity.get(props::CONTENT));
    let mut line = String::new();
    for span in &spans {
        match span {
            liv_core::Span::Break(_) => {
                println!("{line}");
                line.clear();
            }
            other => line.push_str(&span_text(other)),
        }
    }
    if !line.is_empty() {
        println!("{line}");
    }
    println!("fingerprint: {fingerprint}");
    Ok(())
}

/// The words in one span, whatever kind it is. A Ref prints as the id it
/// points at, in the app's own `#id` shape.
fn span_text(span: &liv_core::Span) -> String {
    match span {
        liv_core::Span::Text(t) => t.text.clone(),
        liv_core::Span::Ref(id) => format!("#{id}"),
        _ => String::new(),
    }
}

/// THE EDITOR'S SAVE, compare-and-swap included.
///
/// `set ID content "..."` already writes, but it makes ONE span with no
/// breaks and checks no base, where the shell's save refuses a stale
/// write outright. Multi-line text goes in with `\n`; the base defaults
/// to what is there now, which still refuses a change made mid-flight.
fn content_set(session: &mut Session, rest: &[&str]) -> Result<(), String> {
    let (id_arg, rest) = rest
        .split_first()
        .ok_or("usage: liv content-set ID [--base N] TEXT...")?;
    let id = entity_id(id_arg)?;
    let (base, words): (Option<u64>, &[&str]) = match rest {
        ["--base", n, tail @ ..] => (
            Some(n.parse().map_err(|_| format!("not a fingerprint: {n}"))?),
            tail,
        ),
        all => (None, all),
    };
    if words.is_empty() {
        return Err("usage: liv content-set ID [--base N] TEXT...".into());
    }
    let store = session.store();
    let entity = store.get(id).ok_or(format!("no entity #{id}"))?;
    let base = base
        .unwrap_or_else(|| liv_services::content::content_fingerprint(entity.get(props::CONTENT)));
    let text = words.join(" ").replace("\\n", "\n");
    let spans = liv_services::content::plain_spans(&text);
    let fingerprint = liv_services::content::set_content(session, id, spans, base)
        .map_err(|e| format!("{e:?}"))?;
    println!("#{id} written, fingerprint: {fingerprint}");
    Ok(())
}

/// SEARCH AND LENS — the grammar the app's filters are actually written
/// in, which `list --where` is not.
///
/// The two modes are OPPOSITE for the same token: search WIDENS on
/// `is:archived`, a lens RESTRICTS. Saved views and workspaces store
/// their query as one of these strings, so without this nothing outside
/// the app could answer "does this lens admit these ids" — `drive.sh
/// lens` could only assert what a screen showed.
fn find(session: &Session, log_path: &str, words: &[&str], lens: bool) -> Result<(), String> {
    use liv_services::search;
    let store = session.store();
    let raw = words.join(" ");
    let mode = if lens { search::Mode::Lens } else { search::Mode::Search };
    let sq = search::parse_mode(store, &raw, mode);
    // The file text a hit can match on — the same closure `liv_search_at`
    // builds, so a CLI search and an app search see one corpus.
    let file_prop = property_by_name(store, "file").ok();
    let format_prop = property_by_name(store, "format").ok();
    let cache = liv_services::files::cache_dir(log_path);
    let extracted = |entity: &liv_core::Entity| -> String {
        let Some(fp) = file_prop else { return String::new() };
        let Some(Value::File(file)) = entity.get(fp) else { return String::new() };
        let format = format_prop
            .and_then(|p| entity.get(p))
            .and_then(|v| match v {
                Value::Text(t) => Some(t.as_str()),
                _ => None,
            })
            .unwrap_or("");
        liv_services::files::extracted_text(&cache, file, format)
    };
    let hits = search::search(store, &sq, 200, extracted);
    if hits.is_empty() {
        println!("no {}", if lens { "matches" } else { "hits" });
        return Ok(());
    }
    for hit in &hits {
        let name = store
            .get(hit.id)
            .and_then(|e| e.get(props::NAME))
            .map(|v| liv_views::display(store, v))
            .unwrap_or_else(|| "untitled".into());
        println!("#{:<6} {}", hit.id, name);
    }
    println!("{} shown", hits.len());
    Ok(())
}

/// BULK EXPORT — the box out to a folder of markdown.
///
/// `liv_export_at` has shipped since P15c with no caller in either
/// client, so the whole planner (collision-safe names, group-by folders)
/// was untested outside its unit tests. The door belongs here rather
/// than on the phone: a phone has nowhere to put a folder.
fn export(session: &Session, rest: &[&str]) -> Result<(), String> {
    let (ids_arg, rest) = rest
        .split_first()
        .ok_or("usage: liv export ID[,ID...] DEST [--group-by PROP]")?;
    let (dest, rest) = rest
        .split_first()
        .ok_or("usage: liv export ID[,ID...] DEST [--group-by PROP]")?;
    let store = session.store();
    let ids: Vec<Id> = ids_arg
        .split(',')
        .map(|one| entity_id(one.trim()))
        .collect::<Result<_, _>>()?;
    for id in &ids {
        if store.get(*id).is_none() {
            return Err(format!("no entity #{id}"));
        }
    }
    let group_by: Vec<Id> = match rest {
        [] => Vec::new(),
        ["--group-by", prop] => vec![property_by_name(store, prop)?],
        _ => return Err("usage: liv export ID[,ID...] DEST [--group-by PROP]".into()),
    };
    let plan = liv_services::export::export_plan(store, &ids, &group_by);
    let written = liv_services::export::export_write(&plan, std::path::Path::new(dest))
        .map_err(|e| e.to_string())?;
    // `export_write` counts FILES, not bytes — it returns one per file
    // actually written, which can be fewer than the plan holds if a copy
    // source has gone missing.
    println!("{written} of {} file(s) → {dest}", plan.files.len());
    Ok(())
}
