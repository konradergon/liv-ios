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
        session.propose(proposal);
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
        Some((&"accept", index)) => accept(&mut session, index),
        Some((&"reject", index)) => reject(&mut session, index),
        Some((&"history", _)) => {
            history(&session);
            Ok(())
        }
        _ => Err("usage: lotus [--log FILE] [today] | add TEXT... | \
                  list [--where P=V|P!=V|P?] [--sort P] [--desc] [--columns A,B,C] [--all] | \
                  inbox | accept N | reject N | history"
            .into()),
    }
}

fn civil_today() -> DateTime {
    let now = Local::now();
    DateTime::date(now.year(), now.month(), now.day())
}

/// Today: the orientation surface, v0 — a dedicated list built from the
/// one lens that exists. Board-or-list stays open until daily use decides.
fn today(session: &Session) {
    let store = session.store();
    let list_config = Config {
        density: Density::List,
        columns: vec![],
    };

    if let Some(due) = lotus_services::property_id(store, "due") {
        let now = Local::now();
        let tonight = DateTime::at(now.year(), now.month(), now.day(), 23, 59);
        let due_now = lotus_services::run(
            store,
            &Query {
                constraints: vec![Constraint {
                    property: due,
                    op: Op::AtMost(Value::DateTime(tonight)),
                }],
                sort: Some(Sort {
                    property: due,
                    descending: false,
                }),
                ..Query::default()
            },
        );
        if !due_now.is_empty() {
            println!("due through today:");
            print_table(&render(store, &due_now, &list_config));
            println!();
        }

        let scraps = lotus_services::run(
            store,
            &Query {
                constraints: vec![
                    Constraint {
                        property: props::CONTENT,
                        op: Op::Exists,
                    },
                    Constraint {
                        property: due,
                        op: Op::Missing,
                    },
                ],
                sort: Some(Sort {
                    property: props::CREATED,
                    descending: true,
                }),
                ..Query::default()
            },
        );
        if !scraps.is_empty() {
            println!("captured, unstructured:");
            print_table(&render(store, &scraps, &list_config));
            println!();
        }
    }

    match store.pending().len() {
        0 => {}
        1 => println!("1 proposal waiting — lotus inbox"),
        n => println!("{n} proposals waiting — lotus inbox"),
    }
}

/// The inbox: the shell's one surface that is not a view.
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
        let subject = proposal
            .commands
            .first()
            .map(|c| match c {
                lotus_core::Command::AddCell { entity, .. } => format!("#{entity}"),
                _ => String::new(),
            })
            .unwrap_or_default();
        println!("[{i}] {subject}  {}  ({author})", proposal.reason);
    }
    println!("\nlotus accept N | lotus reject N");
}

fn accept(session: &mut Session, args: &[&str]) -> Result<(), String> {
    let index: usize = parse_index(args)?;
    let label = session
        .store()
        .pending()
        .get(index)
        .map(|p| p.label.clone())
        .ok_or("no such proposal — lotus inbox")?;
    session.accept(index).map_err(|e| e.to_string())?;
    println!("accepted: {label}");
    Ok(())
}

fn reject(session: &mut Session, args: &[&str]) -> Result<(), String> {
    let index: usize = parse_index(args)?;
    session.reject(index).map_err(|e| e.to_string())?;
    println!("declined — the clerk won't ask again");
    Ok(())
}

fn parse_index(args: &[&str]) -> Result<usize, String> {
    args.first()
        .and_then(|s| s.parse().ok())
        .ok_or_else(|| "which one? lotus inbox shows the numbers".to_string())
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
        session.propose(proposal);
    }
    for (i, proposal) in session.store().pending().iter().enumerate().skip(already) {
        println!("clerk: {}  (lotus accept {i})", proposal.reason);
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
