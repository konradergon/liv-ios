//! What a picker and an inspector need to draw themselves.
//!
//! **The words come from the box, never from the shell.** The current
//! tree keeps the six area names as a Swift constant, which
//! `one-core.md` §4 records as a mistake: a shell carrying its own copy
//! of the furniture drifts from the box that stores it, and the drift is
//! invisible until someone renames something. So a picker asks.
//!
//! The other half of the same rule: compiled-in furniture and a user's
//! own come back in ONE list. That is what the cell accepts — a
//! `RefTo(kind::AREA)` takes the frozen Work and a minted "Woodworking"
//! by one rule — so a picker that separated them would be inventing a
//! distinction the model does not have.

use crate::engine::Engine;
use crate::id::EntityId;
use crate::log::LogError;
use crate::model::{self, prop, Holds};
use crate::op::Value;

/// One row of the inspector.
pub struct Cell {
    pub property: EntityId,
    /// The property's current name, which a rename moves.
    pub name: String,
    /// `text`, `number`, `bool`, `datetime`, `reference`, `richtext`,
    /// `file` — so a shell can pick an editor without knowing the id.
    pub holds: &'static str,
    pub many: bool,
    /// What to show. Always a string, so a row renders without the shell
    /// knowing the kind.
    pub shown: String,
    /// Where to go when the row is tapped, when there is anywhere.
    pub target: Option<EntityId>,
    /// **Two devices left this register holding two values.** The model's
    /// rule is that nothing silently wins, so the shell must be able to
    /// show the choice rather than pick one.
    pub contended: bool,
}

impl Engine {
    /// Everything a `RefTo` property may point at, named, in the order a
    /// picker should show them: the property's own declared options
    /// first, then compiled-in furniture of that kind, then the user's
    /// own.
    ///
    /// Empty for a property that holds no references — which is an
    /// answer, not a failure: a text field has no options and a picker
    /// asking is not a picker doing anything wrong.
    pub fn options_for(&self, property: EntityId) -> Result<Vec<(EntityId, String)>, LogError> {
        let Some(shape) = self.prop_shape(property)? else { return Ok(Vec::new()) };
        let mut out: Vec<(EntityId, String)> = Vec::new();
        let mut seen = std::collections::HashSet::new();
        let mut push = |id: EntityId, name: Option<String>, out: &mut Vec<(EntityId, String)>| {
            if let Some(n) = name {
                if seen.insert(id) {
                    out.push((id, n));
                }
            }
        };

        // What the property itself declares. A `status` narrowed to three
        // options is narrower than "everything of kind Status", and the
        // narrower answer is the right one.
        for (_, v) in self.cell(property, prop::OPTIONS)? {
            if let Value::Ref(option) = v {
                push(option, self.display_name(option)?, &mut out);
            }
        }
        let Holds::RefTo(class) = shape.holds else { return Ok(out) };
        for &id in model::furniture_of(class) {
            push(id, self.display_name(id)?, &mut out);
        }
        for id in self.of_kind(class)? {
            if !self.is_trashed(id)? {
                push(id, self.display_name(id)?, &mut out);
            }
        }
        Ok(out)
    }

    /// The kinds a create menu offers — the six the product names, in
    /// product order, plus anything the user declared.
    ///
    /// Not every kind that exists: `kind::WORKSPACE` and the rest are
    /// furniture the app draws with, and a person never picks one from a
    /// list.
    pub fn offered_kinds(&self) -> Result<Vec<(EntityId, String)>, LogError> {
        let mut out = Vec::new();
        for &id in model::KINDS {
            if let Some(n) = self.display_name(id)? {
                out.push((id, n));
            }
        }
        for id in self.of_kind(model::kind::KIND)? {
            if !self.is_trashed(id)? {
                if let Some(n) = self.display_name(id)? {
                    out.push((id, n));
                }
            }
        }
        Ok(out)
    }

    /// One thing's cells, in the order the inspector shows them.
    ///
    /// The six `shown` properties first, in the order the product names
    /// them, then everything else that has a value — so the rows a person
    /// expects do not move as the plumbing changes underneath.
    pub fn inspect(&self, entity: EntityId) -> Result<Vec<Cell>, LogError> {
        let mut by_prop: std::collections::BTreeMap<[u8; 16], Vec<Value>> = Default::default();
        for (property, _, value) in self.cells_of(entity)? {
            by_prop.entry(property.0).or_default().push(value);
        }

        let mut out = Vec::new();
        let mut done = std::collections::HashSet::new();
        let ordered = model::PROPS.iter().filter(|p| p.shown).map(|p| p.id);
        for id in ordered {
            if let Some(values) = by_prop.get(&id.0) {
                done.insert(id.0);
                out.push(self.one_cell(id, values)?);
            }
        }
        for (raw, values) in &by_prop {
            if done.contains(raw) {
                continue;
            }
            let id = EntityId(*raw);
            // Backstage cells are the app's own bookkeeping, not
            // something a person put there, so they stay out of a list of
            // what this thing HAS.
            if matches!(id, x if x == prop::BODY || x == prop::TRASHED || x == prop::DECLINED) {
                continue;
            }
            out.push(self.one_cell(id, values)?);
        }
        Ok(out)
    }

    fn one_cell(&self, property: EntityId, values: &[Value]) -> Result<Cell, LogError> {
        let shape = self.prop_shape(property)?;
        let target = values.iter().find_map(|v| match v {
            Value::Ref(t) => Some(*t),
            _ => None,
        });
        let mut shown = Vec::new();
        for v in values {
            shown.push(self.show(v)?);
        }
        Ok(Cell {
            property,
            name: self.display_name(property)?.unwrap_or_else(|| property.hex()),
            holds: shape.map(|s| holds_word(s.holds)).unwrap_or("text"),
            many: shape.map(|s| s.many).unwrap_or(false),
            // A contended register shows both, separated, rather than one
            // of them chosen silently.
            shown: shown.join(" / "),
            target,
            contended: values.len() > 1 && !shape.map(|s| s.many).unwrap_or(false),
        })
    }

    /// A value as a person reads it.
    pub(crate) fn show(&self, v: &Value) -> Result<String, LogError> {
        Ok(match v {
            Value::Text(s) => s.clone(),
            Value::Number(n) => {
                // An integer-valued float reads as an integer: "3 seats",
                // never "3 seats" spelled 3.
                if n.fract() == 0.0 && n.abs() < 1e15 {
                    format!("{}", *n as i64)
                } else {
                    format!("{n}")
                }
            }
            Value::Bool(b) => (if *b { "Yes" } else { "No" }).to_owned(),
            Value::Date(d) => show_date(d),
            Value::Ref(t) => self.display_name(*t)?.unwrap_or_else(|| t.hex()),
            Value::Blob(h) => h.iter().take(4).map(|b| format!("{b:02x}")).collect(),
            Value::Rich(spans) => crate::rich::plain(spans),
        })
    }

    /// A thing's name: its own if it has one, else the label its
    /// compiled-in definition carries. `None` for something nameless,
    /// which the caller decides how to fill.
    pub fn display_name(&self, id: EntityId) -> Result<Option<String>, LogError> {
        Ok(self.name(id)?.or_else(|| model::label(id).map(str::to_owned)))
    }
}

fn holds_word(h: Holds) -> &'static str {
    match h {
        Holds::Text => "text",
        Holds::Number => "number",
        Holds::Bool => "bool",
        Holds::Date => "datetime",
        Holds::Ref | Holds::RefTo(_) => "reference",
        Holds::Blob => "file",
        Holds::Rich => "richtext",
    }
}

fn show_date(d: &crate::op::DateSpec) -> String {
    match d {
        crate::op::DateSpec::Day(days) => {
            let (y, m, dd) = crate::civil::civil_from_days(*days);
            format!("{y:04}-{m:02}-{dd:02}")
        }
        crate::op::DateSpec::Instant { ms, .. } => {
            let days = ms.div_euclid(86_400_000) as i32;
            let rest = ms.rem_euclid(86_400_000);
            let (y, m, dd) = crate::civil::civil_from_days(days);
            let (hh, mm) = (rest / 3_600_000, (rest % 3_600_000) / 60_000);
            format!("{y:04}-{m:02}-{dd:02} {hh:02}:{mm:02}")
        }
    }
}

/// One file this device cannot open, and why.
pub struct FileAlert {
    pub entity: EntityId,
    pub name: String,
    /// Where this device last saw it — `None` for a file that arrived by
    /// sync and has no copy here.
    pub path: Option<String>,
    /// `absent` when this device never had it; `gone` when the path it
    /// knows no longer holds a file.
    pub why: &'static str,
}

/// One value some cell of this property actually holds.
pub struct InUse {
    pub label: String,
    /// The target, when the value is a reference — so a chip can be
    /// tapped through to the thing it names.
    pub target: Option<EntityId>,
    pub count: usize,
}

impl Engine {
    /// Every value this property is actually carrying, commonest first.
    ///
    /// **Not the same question as `options_for`.** That asks what a cell
    /// MAY hold; this asks what it does. A picker over a free-text field
    /// has no options and still wants to offer what the user has typed
    /// before, and a facet row counting areas wants the ones in use
    /// rather than the six that exist.
    pub fn values_in_use(&self, property: EntityId) -> Result<Vec<InUse>, LogError> {
        let trashed: std::collections::HashSet<EntityId> = self
            .with_value(prop::TRASHED, &Value::Bool(true))?
            .into_iter()
            .collect();
        let mut counts: Vec<(String, Option<EntityId>, usize)> = Vec::new();
        for (entity, values) in crate::view::with_prop(self.conn(), property)? {
            // A trashed thing's cells are not "in use" — offering what the
            // trash holds is offering the user their own deletions back.
            if trashed.contains(&entity) {
                continue;
            }
            for v in values {
                let target = match v {
                    Value::Ref(t) => Some(t),
                    _ => None,
                };
                let label = self.show(&v)?;
                match counts.iter_mut().find(|(l, t, _)| *l == label && *t == target) {
                    Some((_, _, n)) => *n += 1,
                    None => counts.push((label, target, 1)),
                }
            }
        }
        // Commonest first, then alphabetical — a stable order, so a
        // picker does not reshuffle between two equally common values.
        counts.sort_by(|a, b| b.2.cmp(&a.2).then_with(|| a.0.cmp(&b.0)));
        Ok(counts
            .into_iter()
            .map(|(label, target, count)| InUse { label, target, count })
            .collect())
    }

    /// Every file reference this device cannot open.
    ///
    /// **A hash travels and a path does not**, which is the whole reason
    /// these two states are told apart. A file added on the laptop arrives
    /// on the phone as a real, valid reference with no local copy —
    /// `absent`, and the answer is "find it for me", not "this is broken".
    /// A path this device knows that no longer holds a file is `gone`, and
    /// that one IS broken.
    ///
    /// Neither touches the stored hash. A file on an unplugged drive is
    /// not a file whose contents changed.
    pub fn file_alerts(&self) -> Result<Vec<FileAlert>, LogError> {
        let mut out = Vec::new();
        for (entity, values) in crate::view::with_prop(self.conn(), prop::FILE)? {
            if self.is_trashed(entity)? {
                continue;
            }
            if !values.iter().any(|v| matches!(v, Value::Blob(_))) {
                continue;
            }
            let path = self.path_of(entity)?;
            let why = match &path {
                None => "absent",
                Some(p) if !std::path::Path::new(p).exists() => "gone",
                Some(_) => continue,
            };
            out.push(FileAlert {
                entity,
                name: self.display_name(entity)?.unwrap_or_else(|| entity.hex()),
                path,
                why,
            });
        }
        Ok(out)
    }
}
