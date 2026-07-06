//! Views — milestone 3: List / Table, one renderer, two densities.
//!
//! A renderer is the same move twice: position entities by one property,
//! draw an entity as a few properties. The list positions by nothing.
//!
//! A renderer holds no state and never writes: it takes a read-only store
//! and already-run query results, and emits inert display data the shell
//! walks. It keys on properties present in cells, never on type.

use lotus_core::{props, Entity, Id, Span, Store, Value};

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

/// One line for an entity: its name, else its content, else its id.
pub fn summary(store: &Store, entity: &Entity) -> String {
    if let Some(Value::Text(name)) = entity.get(props::NAME) {
        return name.clone();
    }
    if let Some(value) = entity.get(props::CONTENT) {
        let text = display(store, value);
        if !text.is_empty() {
            return truncate(&text, 72);
        }
    }
    format!("#{}", entity.id)
}

/// A property's display name is the name cell of its definition entity.
fn property_name(store: &Store, property: Id) -> String {
    match store.get(property).and_then(|e| e.get(props::NAME)) {
        Some(Value::Text(name)) => name.clone(),
        _ => format!("#{property}"),
    }
}

/// Draw one value as text. References draw as the target's name — the
/// renderer peeks, read-only, exactly like the editor peeking at an
/// embedded task's status. Public: every shell draws values through
/// this one function, so a date never renders two ways.
pub fn display(store: &Store, value: &Value) -> String {
    match value {
        Value::Text(t) => t.clone(),
        Value::RichText(rich) => rich
            .spans
            .iter()
            .map(|span| match span {
                Span::Text(t) => t.text.clone(),
                // A paragraph break reads as a space in a one-line
                // summary; the block kind is structure, not prose.
                Span::Break(_) => " ".to_string(),
                Span::Ref(id) => reference(store, *id),
            })
            .collect(),
        Value::Number(n) => format!("{n}"),
        Value::Bool(b) => if *b { "yes" } else { "no" }.to_string(),
        Value::DateTime(dt) => {
            let (ymd, hm) = (dt.civil / 10_000, dt.civil % 10_000);
            let (y, m, d) = (ymd / 10_000, (ymd / 100) % 100, ymd % 100);
            if dt.date_only {
                // No invented 00:00.
                format!("{y:04}-{m:02}-{d:02}")
            } else {
                format!("{y:04}-{m:02}-{d:02} {:02}:{:02}", hm / 100, hm % 100)
            }
        }
        Value::Select(id) | Value::Reference(id) => reference(store, *id),
        Value::File(f) => f.path.clone(),
    }
}

/// A reference draws shallow: the target's name, else its id — never the
/// target's content, so mutually-embedded entities cannot recurse. A missing
/// or trashed target is a broken link, shown, never repaired.
fn reference(store: &Store, id: Id) -> String {
    match store.get(id) {
        Some(target) if !target.trashed => match target.get(props::NAME) {
            Some(Value::Text(name)) => name.clone(),
            _ => format!("#{}", target.id),
        },
        _ => format!("#{id}!"),
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
