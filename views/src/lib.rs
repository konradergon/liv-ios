//! Views — milestone 3: List / Table, one renderer, two densities.
//!
//! A renderer is the same move twice: position entities by one property,
//! draw an entity as a few properties. The list positions by nothing.
//!
//! A renderer holds no state and never writes: it takes a read-only store
//! and already-run query results, and emits inert display data the shell
//! walks. It keys on properties present in cells, never on type.

use liv_core::{props, Entity, Id, Span, Store, Value};

/// One renderer, two densities.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Density {
    /// One line per entity: a summary drawn from name or content.
    List,
    /// Chosen properties as columns.
    Table,
}

/// Renderer configuration is data: which properties become columns.
#[derive(Debug, Clone)]
pub struct Config {
    pub density: Density,
    /// Table columns, ignored by List density.
    pub columns: Vec<Id>,
}

/// Inert display data. Strings and ids only — nothing here can write.
#[derive(Debug, Clone, PartialEq)]
pub struct Rendered {
    pub header: Vec<String>,
    pub rows: Vec<Row>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Row {
    pub id: Id,
    pub cells: Vec<String>,
}

/// The only code in this lens.
pub fn render(store: &Store, results: &[Id], config: &Config) -> Rendered {
    match config.density {
        Density::List => Rendered {
            header: vec!["entity".into()],
            rows: results
                .iter()
                .filter_map(|id| store.get(*id))
                .map(|e| Row {
                    id: e.id,
                    cells: vec![summary(store, e)],
                })
                .collect(),
        },
        Density::Table => Rendered {
            header: config
                .columns
                .iter()
                .map(|p| property_name(store, *p))
                .collect(),
            rows: results
                .iter()
                .filter_map(|id| store.get(*id))
                .map(|e| Row {
                    id: e.id,
                    cells: config
                        .columns
                        .iter()
                        .map(|p| {
                            e.get(*p)
                                .map(|v| display(store, v))
                                .unwrap_or_default()
                        })
                        .collect(),
                })
                .collect(),
        },
    }
}

/// One line for an entity: its name, else its content, else a name made
/// for it.
///
/// **AN ID IS NEVER A NAME** (owner, 2026-09-13: *"LivID shouldn't be read
/// by the user"*). This used to end `format!("#{}", entity.id)`, and that
/// string went everywhere a name goes: the snapshot's `title`, a search
/// result, a reference chip, and the `title:` front-matter of an exported
/// file. The shell mapped it away on ONE surface — lists — and three
/// others showed it: the workspace switcher, the outbox ledger, and every
/// export.
pub fn summary(store: &Store, entity: &Entity) -> String {
    if let Some(Value::Text(name)) = entity.get(props::NAME) {
        let trimmed = name.trim();
        if !trimmed.is_empty() {
            return trimmed.to_string();
        }
    }
    if let Some(value) = entity.get(props::CONTENT) {
        let text = display(store, value);
        if !text.trim().is_empty() {
            return truncate(text.trim(), 72);
        }
    }
    made_name(store, entity)
}

/// What to call a thing nobody has named.
///
/// **Owner, 2026-09-13:** *"Unnamed task/event/note should get a sensible
/// name."* This amends the 2026-09-06 ruling, which was that a nameless
/// row says what it IS — "Task", "Note" — rather than "Untitled", the
/// word Obsidian, Apple Notes and Notion all use for a failure to name.
/// That was right and it was not enough: fourteen rows reading "Task"
/// distinguish each other no better than fourteen reading "Untitled", and
/// the harness had already tripped over exactly that, unable to aim at
/// one of three notes sharing a label.
///
/// So: the kind's word, and WHEN. `Task · 13 Sep 14:32`.
///
/// **The words are Rust's, and that is the point.** `one-core.md` §4
/// records a shell carrying its own copy of the app's vocabulary as the
/// mistake; a made name is vocabulary. The month abbreviations are
/// English, like every other word this crate and the model own.
pub fn made_name(store: &Store, entity: &Entity) -> String {
    let kind = kind_word(store, entity);
    match entity.get(props::CREATED) {
        Some(Value::DateTime(dt)) if dt.civil > 0 => {
            format!("{kind} · {}", stamp_words(dt.civil))
        }
        _ => kind,
    }
}

/// The word for what this is — its first type's name, else the most
/// neutral thing true of everything in the box.
fn kind_word(store: &Store, entity: &Entity) -> String {
    for value in entity.all(props::TYPE) {
        if let Value::Reference(t) = value {
            if let Some(Value::Text(name)) = store.get(*t).and_then(|e| e.get(props::NAME)) {
                let mut chars = name.chars();
                if let Some(first) = chars.next() {
                    return first.to_uppercase().collect::<String>() + chars.as_str();
                }
            }
        }
    }
    // An untyped capture. "Note" would be a claim about its kind that
    // nothing in the box makes.
    "Capture".to_string()
}

/// `13 Sep 14:32` from a packed `YYYYMMDDHHMM`.
///
/// Zone-free, like the stamp it reads: this is the civil moment the thing
/// was caught, not an instant to be re-localised.
fn stamp_words(civil: i64) -> String {
    const MONTHS: [&str; 12] = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ];
    let day_part = civil / 10_000;
    let time = (civil % 10_000).max(0);
    let month = ((day_part / 100) % 100) as usize;
    let day = day_part % 100;
    let month_word = MONTHS.get(month.saturating_sub(1)).copied().unwrap_or("");
    if month_word.is_empty() || day == 0 {
        return String::new();
    }
    format!("{day} {month_word} {:02}:{:02}", time / 100, time % 100)
}

/// A property's display name is the name cell of its definition entity.
///
/// A definition with no name is plumbing that got away; it is still never
/// shown as an id.
fn property_name(store: &Store, property: Id) -> String {
    match store.get(property).and_then(|e| e.get(props::NAME)) {
        Some(Value::Text(name)) if !name.trim().is_empty() => name.trim().to_string(),
        _ => "Field".to_string(),
    }
}

/// Draw one value as text. References draw as the target's name — the
/// renderer peeks, read-only, exactly like the editor peeking at an
/// embedded task's status. Public: every shell draws values through
/// this one function, so a date never renders two ways.
pub fn display(store: &Store, value: &Value) -> String {
    match value {
        Value::Text(t) => t.clone(),
        Value::RichText(rich) => {
            // A paragraph break reads as a single space between content —
            // but never leading, and never doubled, so a doc that starts
            // with a heading (a leading Break) has no stray first space.
            let mut out = String::new();
            for span in &rich.spans {
                match span {
                    Span::Text(t) => out.push_str(&t.text),
                    Span::Ref(id) => out.push_str(&reference(store, *id)),
                    Span::Break(_) => {
                        if !out.is_empty() && !out.ends_with(' ') {
                            out.push(' ');
                        }
                    }
                }
            }
            out
        }
        Value::Number(n) => format!("{n}"),
        Value::Bool(b) => if *b { "yes" } else { "no" }.to_string(),
        Value::DateTime(dt) => {
            let one = |civil: i64| {
                let (ymd, hm) = (civil / 10_000, civil % 10_000);
                let (y, m, d) = (ymd / 10_000, (ymd / 100) % 100, ymd % 100);
                if dt.date_only {
                    // No invented 00:00.
                    format!("{y:04}-{m:02}-{d:02}")
                } else {
                    format!("{y:04}-{m:02}-{d:02} {:02}:{:02}", hm / 100, hm % 100)
                }
            };
            match dt.end {
                None => one(dt.civil),
                // The span names its end in EXACTLY the parseable form —
                // display and parse are one grammar, so a text write-back
                // (the inspector's field row) is a lossless no-op, never a
                // silent end-destroyer (the review's finding).
                Some(end) => format!("{} -> {}", one(dt.civil), one(end)),
            }
        }
        Value::Select(id) | Value::Reference(id) => reference(store, *id),
        Value::File(f) => f.path.clone(),
    }
}

/// A reference draws shallow: the target's name, else a name made for it —
/// never the target's content, so mutually-embedded entities cannot
/// recurse. A missing or trashed target is a broken link, shown, never
/// repaired.
///
/// **Still never an id.** A chip reading `#4142` told a person nothing
/// they could act on and leaked ours (owner, 2026-09-13). A broken link
/// says it is broken, in words.
fn reference(store: &Store, id: Id) -> String {
    match store.get(id) {
        Some(target) if !target.trashed => match target.get(props::NAME) {
            Some(Value::Text(name)) if !name.trim().is_empty() => name.trim().to_string(),
            _ => made_name(store, target),
        },
        Some(target) => format!("{} (trashed)", made_name(store, target)),
        None => "(missing)".to_string(),
    }
}

fn truncate(text: &str, max: usize) -> String {
    if text.chars().count() <= max {
        text.to_string()
    } else {
        let cut: String = text.chars().take(max - 1).collect();
        format!("{cut}…")
    }
}
