//! lotus — a stand-in shell for milestone 3.
//!
//! A real shell (window, hotkey, popup) arrives with milestone 4, where the
//! platform decision bites. Until then this binary is the thinnest possible
//! orchestrator: parse arguments, open the session, run services, print what
//! the renderer emitted. It owns no data and defines no commands.

use chrono::{Datelike, Local, Timelike};

use lotus_core::{props, Author, DateTime, Id, Session, Value};
use lotus_services::{Constraint, Op, Query, Sort};
use lotus_views::{render, Config, Density, Rendered};

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if let Err(message) = dispatch(&args) {
        eprintln!("lotus: {message}");
        std::process::exit(1);
    }
}

/// The CLI and the menu-bar shell share one box by default.
/// The store's location is one of the budgeted settings; --log overrides.
fn default_log_path() -> String {
    match std::env::var("HOME") {
        Ok(home) => format!("{home}/Library/Application Support/lotus/lotus.log"),
        Err(_) => "lotus.log".to_string(),
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
    let mut session = Session::open(&log_path).map_err(|e| e.to_string())?;
    lotus_services::seed_if_fresh(&mut session).map_err(|e| e.to_string())?;

    // The clerk sweeps at every open; duplicates of anything pending or
    // declined never reach the queue.
    for proposal in lotus_services::clerk::sweep(session.store(), civil_today()) {
        session.propose(proposal).map_err(|e| e.to_string())?;
    }

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
        Some((&"history", _)) => {
            history(&session);
            Ok(())
        }
        Some((&"habit", rest)) if !rest.is_empty() => habit_add(&mut session, rest),
        Some((&"checkin", rest)) if !rest.is_empty() => checkin(&mut session, rest),
        Some((&"habits", _)) => {
            habits(&session);
            Ok(())
        }
        Some((&"time", rest)) => time(&mut session, rest),
        _ => Err("usage: lotus [--log FILE] [today] | add TEXT... | \
                  list [--where P=V|P!=V|P?] [--sort P] [--desc] [--columns A,B,C] [--all] | \
                  inbox | accept ID [K] | reject ID [K] | name ID TEXT... | \
                  set ID PROP VALUE... | history | \
                  habit NAME... [--points N] [--cadence TEXT] | \
                  checkin HABIT-ID [DAY] | habits | \
                  time [TARGET-ID START END]"
            .into()),
    }
}

/// Name an entity: one cell, front of house. Names feed the gazetteer,
/// so the mentions proposer has something to notice.
fn name(session: &mut Session, rest: &[&str]) -> Result<(), String> {
    let (id_arg, words) = rest.split_first().ok_or("usage: lotus name ID TEXT...")?;
    let id: Id = id_arg
        .trim_start_matches('#')
        .parse()
        .map_err(|_| format!("not an entity id: {id_arg}"))?;
    if session.store().get(id).is_none() {
        return Err(format!("no entity #{id}"));
    }
    if words.is_empty() {
        return Err("usage: lotus name ID TEXT...".into());
    }
    let text = words.join(" ");
    session
        .commit(
            vec![lotus_core::Command::AddCell {
                entity: id,
                cell: lotus_core::Cell {
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

    let sections = lotus_services::today_sections(store, civil_today());
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
        1 => println!("1 proposal waiting — lotus inbox"),
        n => println!("{n} proposals waiting — lotus inbox"),
    }
}

/// Set one property to one value — the shared parser and replace-the-cell
/// semantics live in services; the window's inspector uses the same door.
fn set(session: &mut Session, rest: &[&str]) -> Result<(), String> {
    let (id_arg, rest) = rest.split_first().ok_or("usage: lotus set ID PROP VALUE...")?;
    let (prop_name, words) = rest.split_first().ok_or("usage: lotus set ID PROP VALUE...")?;
    let id: Id = id_arg
        .trim_start_matches('#')
        .parse()
        .map_err(|_| format!("not an entity id: {id_arg}"))?;
    if words.is_empty() {
        return Err("usage: lotus set ID PROP VALUE...".into());
    }
    let raw = words.join(" ");
    lotus_services::content::set_property(session, id, prop_name, &raw)?;
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
    println!("\nlotus accept ID | lotus reject ID   (add K when an id lists twice)");
}

fn subject_of(proposal: &lotus_core::Proposal) -> Option<Id> {
    proposal.commands.first().map(|c| match c {
        lotus_core::Command::Create { entity }
        | lotus_core::Command::Trash { entity }
        | lotus_core::Command::Restore { entity }
        | lotus_core::Command::AddCell { entity, .. }
        | lotus_core::Command::RemoveCell { entity, .. }
        | lotus_core::Command::Redirect { entity, .. } => *entity,
    })
}

/// Resolve "ID [K]" against the queue as it exists right now.
fn resolve_target(session: &Session, args: &[&str]) -> Result<usize, String> {
    let id_arg = args
        .first()
        .ok_or("which one? lotus inbox shows the ids")?;
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
        (0, _) => Err(format!("no proposal for #{id} — lotus inbox")),
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
            "#{id} has {n} proposals — lotus inbox, then accept/reject {id} K"
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
    let scrap = lotus_services::capture(session, text, created).map_err(|e| e.to_string())?;
    println!("#{scrap}");

    // The clerk runs behind the write; whatever it noticed shows at once.
    let already = session.store().pending().len();
    for proposal in lotus_services::clerk::sweep(session.store(), civil_today()) {
        session.propose(proposal).map_err(|e| e.to_string())?;
    }
    for proposal in session.store().pending().iter().skip(already) {
        let subject = subject_of(proposal)
            .map(|id| format!("{id}"))
            .unwrap_or_default();
        println!("clerk: {}  (lotus accept {subject})", proposal.reason);
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

    let results = lotus_services::run(store, &query);
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
fn parse_constraint(store: &lotus_core::Store, raw: &str) -> Result<Constraint, String> {
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

fn property_by_name(store: &lotus_core::Store, name: &str) -> Result<Id, String> {
    lotus_services::property_id(store, name).ok_or(format!("no property named {name}"))
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

/// P18b: birth a habit (front of house). `lotus habit Climb --points 2`.
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
        return Err("usage: lotus habit NAME... [--points N] [--cadence TEXT]".into());
    }
    let id = lotus_services::content::create_habit(
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
    let (id_arg, day_arg) = rest.split_first().ok_or("usage: lotus checkin HABIT-ID [DAY]")?;
    let habit: Id =
        id_arg.trim_start_matches('#').parse().map_err(|_| "HABIT-ID must be a number")?;
    let day: i64 = match day_arg.first() {
        Some(d) => d.parse().map_err(|_| "DAY must be YYYYMMDD")?,
        None => civil_today().civil / 10_000,
    };
    let row = lotus_services::content::check_in(session, habit, day, civil_today())
        .map_err(|e| e.to_string())?;
    println!("checked in #{row} ({day})");
    Ok(())
}

/// P18b: the habit card, in text — the same projection every shell reads.
fn habits(session: &Session) {
    let today = civil_today().civil / 10_000;
    let stats = lotus_services::habits::habit_stats(session.store(), today);
    if stats.habits.is_empty() {
        println!("no habits yet — lotus habit NAME [--points N]");
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

/// P18d: log a closed interval (`lotus time ID 202607140900 202607141030`),
/// or with no args print the week's totals — the same projection the shell
/// reads.
fn time(session: &mut Session, rest: &[&str]) -> Result<(), String> {
    if rest.is_empty() {
        let today = civil_today().civil / 10_000;
        let summary = lotus_services::timeviews::time_totals(session.store(), today);
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
        _ => return Err("usage: lotus time TARGET-ID START END".into()),
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
    let id = lotus_services::content::log_time(session, target, to_dt(start), to_dt(end))
        .map_err(|e| e.to_string())?;
    println!("logged #{id}");
    Ok(())
}
