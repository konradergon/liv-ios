//! Typing a value into a cell.
//!
//! **The shell sends a string; the property says what it means.** A user
//! types "friday", "3", "yes", "Work" — and which of those is a date, a
//! number, a bool or an option is a fact about the PROPERTY, not about
//! the text. So the parser asks the box for the shape and reads the text
//! against it, rather than making the shell say what it thinks it typed.
//!
//! This is the port of `services/src/content.rs`'s `parse_value`, which
//! is where the hard-won parts of this come from and which dies with
//! `core/`. Standing rule 4 — one grammar, one parser — is why it moves
//! rather than being written twice: the same strings a user types today
//! must mean the same things afterwards.
//!
//! Three behaviours are carried over deliberately, each because its
//! absence was a bug:
//!
//! 1. **A number must be FINITE.** Rust's f64 parser accepts `NaN` and
//!    `inf`, a knowledge log has no use for either, and NaN's
//!    non-reflexive equality once made such a cell impossible to remove
//!    — the value would not compare equal to itself, so nothing could
//!    name it. That is the poison-pill repro, and it is why this filters.
//! 2. **An option is matched BY NAME, case-insensitively**, against the
//!    options the property actually declares. Never minted: naming a new
//!    option is a decision, and typing a typo is not.
//! 3. **A file is refused.** Its cell holds a hash derived from bytes,
//!    which no typed string can express. Files are born through
//!    `add_file`, which hashes; the cell is read-only to this door.
//!
//! One thing does NOT carry over, and it is a real gap rather than an
//! omission: `core/` accepts a date SPAN (`"monday -> friday"`, one cell
//! holding a start and an end). `DateSpec` here is a day or an instant
//! with no span variant, so the span has nowhere to go and is refused
//! with a message saying so. Adding it is an op-format change.

use crate::engine::Engine;
use crate::log::LogError;
use crate::model::{self, prop, Holds};
use crate::op::{DateSpec, Value};

/// Why a typed value did not become a cell. Each is something to show a
/// person, which is why they carry their own words.
#[derive(Debug)]
pub enum ValueError {
    /// Nothing in the box declares this property.
    UnknownProperty,
    /// The text does not read as the kind the property holds.
    Unreadable(String),
    /// A reference to something the box does not hold. **Checked**, so a
    /// typo cannot leave a cell pointing at nothing.
    NoSuchEntity,
    /// No option of that property is called that.
    NoSuchOption(String),
    /// A cell no typed string can fill.
    NotTypeable(&'static str),
    Read(LogError),
}

impl From<LogError> for ValueError {
    fn from(e: LogError) -> Self {
        ValueError::Read(e)
    }
}

impl std::fmt::Display for ValueError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ValueError::UnknownProperty => write!(f, "no such property"),
            ValueError::Unreadable(s) => write!(f, "{s}"),
            ValueError::NoSuchEntity => write!(f, "no such thing"),
            ValueError::NoSuchOption(s) => write!(f, "no option named {s}"),
            ValueError::NotTypeable(s) => write!(f, "{s}"),
            ValueError::Read(_) => write!(f, "the box could not be read"),
        }
    }
}

impl Engine {
    /// Read `raw` as a value for `property`, or say why not.
    pub fn parse_value(&self, property: crate::id::EntityId, raw: &str) -> Result<Value, ValueError> {
        let Some(shape) = self.prop_shape(property)? else {
            return Err(ValueError::UnknownProperty);
        };
        match shape.holds {
            Holds::Text => Ok(Value::Text(raw.to_owned())),
            // A body typed as a flat string is one unmarked run. The
            // editor does not come through here — it sends spans — but
            // the CLI and a scripted set do.
            Holds::Rich => Ok(Value::Rich(vec![crate::rich::Span::text(raw.to_owned())])),
            Holds::Number => raw
                .parse::<f64>()
                .ok()
                .filter(|n| n.is_finite())
                .map(Value::Number)
                .ok_or_else(|| ValueError::Unreadable(format!("not a number: {raw}"))),
            Holds::Bool => match raw.trim().to_lowercase().as_str() {
                "true" | "yes" | "on" | "1" => Ok(Value::Bool(true)),
                "false" | "no" | "off" | "0" => Ok(Value::Bool(false)),
                _ => Err(ValueError::Unreadable(format!("not a yes or no: {raw}"))),
            },
            Holds::Date => parse_date(raw),
            Holds::Ref => {
                let id = self.thing_named(raw)?;
                Ok(Value::Ref(id))
            }
            Holds::RefTo(class) => {
                let id = self.of_class_named(class, raw)?;
                Ok(Value::Ref(id))
            }
            Holds::Blob => Err(ValueError::NotTypeable(
                "a file is added by reference, not typed",
            )),
        }
    }

    /// A thing by id, for an untyped reference.
    fn thing_named(&self, raw: &str) -> Result<crate::id::EntityId, ValueError> {
        let id = crate::id::EntityId::from_hex(raw.trim().trim_start_matches('#'))
            .ok_or_else(|| ValueError::Unreadable(format!("not a thing's id: {raw}")))?;
        if !self.exists(id)? {
            return Err(ValueError::NoSuchEntity);
        }
        Ok(id)
    }

    /// A reference that must point at one class of thing: an option of
    /// this property by NAME, or a bare id of the right class.
    ///
    /// Name first, because that is what a person types. An id is the
    /// escape hatch for a shell that already knows exactly which thing it
    /// means and should not have to spell its name.
    fn of_class_named(
        &self,
        class: crate::id::EntityId,
        raw: &str,
    ) -> Result<crate::id::EntityId, ValueError> {
        let want = raw.trim();
        if let Some(id) = crate::id::EntityId::from_hex(want.trim_start_matches('#')) {
            if self.exists(id)? {
                return Ok(id);
            }
            return Err(ValueError::NoSuchEntity);
        }
        let lowered = want.to_lowercase();
        // What the box says this property may hold.
        for (_, v) in self.cell(class, prop::OPTIONS)? {
            let Value::Ref(option) = v else { continue };
            if self.is_called(option, &lowered)? {
                return Ok(option);
            }
        }
        // Otherwise anything of that class, compiled-in furniture
        // included — which is what lets the six areas and a user's
        // seventh be typed the same way.
        for id in self.of_kind(class)? {
            if self.is_called(id, &lowered)? {
                return Ok(id);
            }
        }
        for &id in model::furniture_of(class) {
            if self.is_called(id, &lowered)? {
                return Ok(id);
            }
        }
        Err(ValueError::NoSuchOption(want.to_owned()))
    }

    /// Is this thing called that? Its own name if it has one, else the
    /// label its compiled-in definition carries.
    fn is_called(&self, id: crate::id::EntityId, lowered: &str) -> Result<bool, ValueError> {
        let name = self
            .name(id)?
            .or_else(|| model::label(id).map(str::to_owned));
        Ok(name.is_some_and(|n| n.to_lowercase() == lowered))
    }
}

/// `yyyy-mm-dd`, optionally with `hh:mm`.
///
/// A bare day is a **floating** day — no zone, so it never shifts under a
/// traveller. A day with a time is an instant.
fn parse_date(raw: &str) -> Result<Value, ValueError> {
    let raw = raw.trim();
    if raw.contains("->") {
        // `core/` takes a span in one cell. `DateSpec` has no span
        // variant, so accepting the text and dropping the end would be
        // worse than refusing it.
        return Err(ValueError::NotTypeable(
            "a date range needs two cells here, not one",
        ));
    }
    let (day, time) = match raw.split_once(char::is_whitespace) {
        Some((d, t)) => (d, Some(t.trim())),
        None => (raw, None),
    };
    let b = day.as_bytes();
    if b.len() != 10 || b[4] != b'-' || b[7] != b'-' {
        return Err(ValueError::Unreadable(format!(
            "not a date: {raw} (yyyy-mm-dd [hh:mm])"
        )));
    }
    let digits = |r: std::ops::Range<usize>| b[r].iter().all(u8::is_ascii_digit);
    if !digits(0..4) || !digits(5..7) || !digits(8..10) {
        return Err(ValueError::Unreadable(format!("not a date: {raw}")));
    }
    let (y, m, d) = (
        day[0..4].parse::<i32>().unwrap_or(0),
        day[5..7].parse::<u32>().unwrap_or(0),
        day[8..10].parse::<u32>().unwrap_or(0),
    );
    if !(1..=12).contains(&m) || d == 0 || d > days_in_month(y, m) {
        return Err(ValueError::Unreadable(format!("no such day: {raw}")));
    }
    let days = crate::civil::days_from_civil(y, m, d);
    let Some(time) = time.filter(|t| !t.is_empty()) else {
        return Ok(Value::Date(DateSpec::Day(days)));
    };
    let (hh, mm) = time
        .split_once(':')
        .ok_or_else(|| ValueError::Unreadable(format!("not a time: {time} (hh:mm)")))?;
    let (hh, mm) = match (hh.parse::<i64>(), mm.parse::<i64>()) {
        (Ok(h), Ok(m)) if (0..24).contains(&h) && (0..60).contains(&m) => (h, m),
        _ => return Err(ValueError::Unreadable(format!("not a time: {time} (hh:mm)"))),
    };
    // tz 0 is UTC. A shell that knows the user's zone sends the cell
    // itself; this door is for text, and text has no zone in it.
    Ok(Value::Date(DateSpec::Instant {
        ms: (days as i64) * 86_400_000 + hh * 3_600_000 + mm * 60_000,
        tz: 0,
    }))
}

fn days_in_month(year: i32, month: u32) -> u32 {
    match month {
        1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
        4 | 6 | 9 | 11 => 30,
        2 if (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 => 29,
        2 => 28,
        _ => 0,
    }
}
