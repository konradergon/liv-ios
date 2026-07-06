//! lotus — a stand-in shell for milestone 3.
//!
//! A real shell (window, hotkey, popup) arrives with milestone 4, where the
//! platform decision bites. Until then this binary is the thinnest possible
//! orchestrator: parse arguments, open the session, run services, print what
//! the renderer emitted. It owns no data and defines no commands.

use chrono::{Datelike, Local, Timelike};

use lotus_core::{props, Author, Cell, Command, DateTime, Id, RichText, Session, Span, Value};
use lotus_services::{Constraint, Op, Query, Sort};
use lotus_views::{render, Config, Density, Rendered};

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if let Err(message) = dispatch(&args) {
        eprintln!("lotus: {message}");
        std::process::exit(1);
    }
}

fn dispatch(args: &[String]) -> Result<(), String> {
    let mut log_path = "lotus.log".to_string();
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

    let mut session = Session::open(&log_path).map_err(|e| e.to_string())?;
    seed_if_fresh(&mut session)?;

    match rest.split_first() {
        Some((&"add", text)) if !text.is_empty() => add(&mut session, &text.join(" ")),
        Some((&"list", flags)) => list(&session, flags),
        Some((&"history", _)) => {
            history(&session);
            Ok(())
        }
        _ => Err("usage: lotus [--log FILE] add TEXT... | list [--where P=V|P!=V|P?] \
                  [--sort P] [--desc] [--columns A,B,C] [--all] | history"
            .into()),
    }
}

/// A fresh box seeds the bootstrap property definitions — entities like any
/// other, authored by the system. Property names live in the box, not in
/// application code, so views can look them up and the clerk can one day
/// reuse them as its gazetteer.
fn seed_if_fresh(session: &mut Session) -> Result<(), String> {
    if !session.store().history().is_empty() {
        return Ok(());
    }
    let definitions: [(Id, &str, &str); 14] = [
        (props::NAME, "name", "text"),
        (props::TYPE, "type", "reference"),
        (props::CREATED, "created", "datetime"),
        (props::CONTENT, "content", "richtext"),
        (props::VALUE_KIND, "value-kind", "text"),
        (props::OPTIONS, "options", "reference"),
        (props::EXPECTED, "expected", "reference"),
        (props::DEFAULT_VIEW, "default-view", "reference"),
        (props::QUERY, "query", "text"),
        (props::RENDERER, "renderer", "text"),
        (props::CONFIG, "config", "text"),
        (props::EXTERNAL_ID, "external-id", "text"),
        (props::WORKING, "working", "bool"),
        (props::PRIVATE, "private", "bool"),
    ];
    let mut commands = Vec::new();
    for (id, name, kind) in definitions {
        commands.push(Command::Create { entity: id });
        commands.push(Command::AddCell {
            entity: id,
            cell: Cell {
                property: props::NAME,
                value: Value::text(name),
            },
        });
        commands.push(Command::AddCell {
            entity: id,
            cell: Cell {
                property: props::VALUE_KIND,
                value: Value::text(kind),
            },
        });
        // Property definitions are plumbing on the shelf, not thoughts.
        commands.push(Command::AddCell {
            entity: id,
            cell: Cell {
                property: props::WORKING,
                value: Value::Bool(true),
            },
        });
    }
    session
        .commit(commands, "bootstrap properties", Author::System)
        .map_err(|e| e.to_string())?;
    Ok(())
}

/// Capture, CLI-grade: an untyped entity with content and a creation date.
/// Nothing else. The hotkey and popup are milestone 4; the shape of the
/// scrap is already the real one.
fn add(session: &mut Session, text: &str) -> Result<(), String> {
    let scrap = session.allocate_id();
    let now = Local::now();
    let created = DateTime::at(
        now.year(),
        now.month(),
        now.day(),
        now.hour(),
        now.minute(),
    );
    session
        .commit(
            vec![
                Command::Create { entity: scrap },
                Command::AddCell {
                    entity: scrap,
                    cell: Cell {
                        property: props::CONTENT,
                        value: Value::RichText(RichText {
                            spans: vec![Span::Text(text.to_string())],
                        }),
                    },
                },
                Command::AddCell {
                    entity: scrap,
                    cell: Cell {
                        property: props::CREATED,
                        value: Value::DateTime(created),
                    },
                },
            ],
            "capture",
            Author::User,
        )
        .map_err(|e| e.to_string())?;
    println!("#{scrap}");
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

/// Property definitions are entities, so name lookup is itself a query:
/// the entity carrying a value-kind whose name matches.
fn property_by_name(store: &lotus_core::Store, name: &str) -> Result<Id, String> {
    let query = Query {
        constraints: vec![
            Constraint {
                property: props::NAME,
                op: Op::Equals(Value::text(name)),
            },
            Constraint {
                property: props::VALUE_KIND,
                op: Op::Exists,
            },
        ],
        include_working: true, // definitions are plumbing, but we asked
        ..Query::default()
    };
    lotus_services::run(store, &query)
        .first()
        .copied()
        .ok_or(format!("no property named {name}"))
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
