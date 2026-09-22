//! Renaming ONE VALUE everywhere it is carried.
//!
//! **Why this cannot be N writes from a shell.** Renaming onto a name that
//! is already taken is a MERGE, and only the store can see every carrier
//! at once. So it is one verb, one grouped transaction, one undo step —
//! the same contract `core/`'s `rename_value` has, because the shell
//! already has a door for it and two of them behaving differently is a
//! defect.
//!
//! The shape of the work differs by what the property holds, and that
//! difference is the argument for references:
//!
//! * a **select or status** keeps its values as option entities, so a
//!   plain rename is ONE write to that option's name and every carrier
//!   re-renders for free;
//! * a **text** property carries the words in each cell, so every carrier
//!   is rewritten — found by an index seek here, where `core/` walked
//!   every user entity.

use crate::engine::Engine;
use crate::id::EntityId;
use crate::log::LogError;
use crate::model::{prop, Holds};
use crate::op::{Author, Op, Value};
use crate::write::{action, WriteError};

#[derive(Debug)]
pub enum RenameError {
    /// Said plainly, because a person reads it.
    Refused(String),
    /// Two options share the name, so the verb cannot tell which is meant.
    Ambiguous(String),
    Write(WriteError),
}

impl std::fmt::Display for RenameError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            RenameError::Refused(m) | RenameError::Ambiguous(m) => write!(f, "{m}"),
            RenameError::Write(e) => write!(f, "{e}"),
        }
    }
}

impl std::error::Error for RenameError {}

impl From<WriteError> for RenameError {
    fn from(e: WriteError) -> RenameError {
        RenameError::Write(e)
    }
}

impl From<LogError> for RenameError {
    fn from(e: LogError) -> RenameError {
        RenameError::Write(WriteError::Log(e))
    }
}

impl Engine {
    /// Rename one value of `property`, everywhere it is carried.
    ///
    /// Returns how many CARRIERS changed — which is zero for renaming an
    /// option nothing uses, and that is a success: the option is in the
    /// picker and the user is fixing its name.
    ///
    /// **By property id, not by name.** `core/` takes the word because its
    /// shell had nothing else; the snapshot carries the id, an id is never
    /// a name, and a box may hold two fields whose names differ only in
    /// case.
    pub fn rename_value(
        &mut self,
        property: EntityId,
        old: &str,
        new: &str,
        now_ms: u64,
    ) -> Result<usize, RenameError> {
        let old = old.trim();
        let new = new.trim();
        if new.is_empty() {
            return Err(RenameError::Refused("a value needs a name".into()));
        }
        if old.eq_ignore_ascii_case(new) {
            return Err(RenameError::Refused("that is already the name".into()));
        }

        let holds = self.holds_of(property)?;
        let (ops, count) = match holds {
            Holds::Text => self.rename_text(property, old, new)?,
            Holds::RefTo(k) if k == crate::model::kind::OPTION => {
                self.rename_option(property, old, new)?
            }
            Holds::RefTo(_) | Holds::Ref => {
                // A reference's words live on the thing it points at, and
                // renaming THAT is an ordinary `set` of its name. There is
                // nothing here to rename.
                return Err(RenameError::Refused(
                    "a reference is named by what it points at".into(),
                ));
            }
            _ => {
                return Err(RenameError::Refused(
                    "only vocabulary renames — text, select and status".into(),
                ))
            }
        };

        if ops.is_empty() {
            return Ok(0);
        }
        self.commit(ops, action::RENAME, Author::User, now_ms)?;
        Ok(count)
    }

    /// What a property holds, compiled-in or declared.
    fn holds_of(&self, property: EntityId) -> Result<Holds, RenameError> {
        if let Some(def) = crate::model::PROPS.iter().find(|d| d.id == property) {
            return Ok(def.holds);
        }
        match self.prop_shape(property)? {
            Some(shape) => Ok(shape.holds),
            None => Err(RenameError::Refused("no such property".into())),
        }
    }

    /// The words are in each cell, so each carrier is rewritten.
    fn rename_text(
        &self,
        property: EntityId,
        old: &str,
        new: &str,
    ) -> Result<(Vec<Op>, usize), RenameError> {
        let want = Value::Text(old.to_owned());
        let mut ops = Vec::new();
        let mut count = 0;
        for entity in self.with_value(property, &want)? {
            // **Backstage plumbing is not a carrier.** Options, declared
            // fields and the rest are name-keyed working entities, and
            // `rename_value(NAME, …)` over them would rewrite the lookups
            // themselves — `core/`'s P19 review, which is why its text
            // branch walks user entities only.
            if self.is_working(entity)? {
                continue;
            }
            let replaces = self
                .cell(entity, property)?
                .into_iter()
                .filter(|(_, v)| *v == want)
                .map(|(d, _)| d)
                .collect();
            ops.push(Op::SetCell {
                entity,
                prop: property,
                value: Value::Text(new.to_owned()),
                replaces,
            });
            count += 1;
        }
        Ok((ops, count))
    }

    /// The value is an entity, so a rename is one write — unless the new
    /// name is taken, and then it is a merge.
    fn rename_option(
        &self,
        property: EntityId,
        old: &str,
        new: &str,
    ) -> Result<(Vec<Op>, usize), RenameError> {
        let options: Vec<EntityId> = self
            .cell(property, prop::OPTIONS)?
            .into_iter()
            .filter_map(|(_, v)| match v {
                Value::Ref(t) => Some(t),
                _ => None,
            })
            .collect();

        let named = |want: &str| -> Result<Vec<EntityId>, LogError> {
            let mut out = Vec::new();
            for o in &options {
                if self.name(*o)?.is_some_and(|n| n.eq_ignore_ascii_case(want)) {
                    out.push(*o);
                }
            }
            Ok(out)
        };

        // **Ambiguous refuses, never guesses.** Two kinds sharing an
        // option name is the DESIGNED state of `status` — options are
        // scoped by `for-type`, with no cross-kind dedup — so a rename
        // keyed by the word alone cannot pick one.
        let from = named(old)?;
        if from.len() > 1 {
            return Err(RenameError::Ambiguous(format!(
                "two options are named {old} — this rename is ambiguous"
            )));
        }
        let into = named(new)?;
        if into.len() > 1 {
            return Err(RenameError::Ambiguous(format!(
                "two options are named {new} — this merge is ambiguous"
            )));
        }
        let Some(option) = from.first().copied() else {
            return Err(RenameError::Refused(format!("no value named {old}")));
        };

        let carriers = self.with_value(property, &Value::Ref(option))?;
        let target = into.first().copied().filter(|t| *t != option);

        let Some(existing) = target else {
            // A PLAIN RENAME: the option's name cell moves, and every
            // carrier re-renders for free. This is what references are
            // for, and it is why the count is of carriers rather than of
            // writes — one write, three rows changed on screen.
            let replaces = self.cell(option, prop::NAME)?.into_iter().map(|(d, _)| d).collect();
            return Ok((
                vec![Op::SetCell {
                    entity: option,
                    prop: prop::NAME,
                    value: Value::Text(new.to_owned()),
                    replaces,
                }],
                carriers.len(),
            ));
        };

        // A MERGE: repoint every carrier, detach the loser from the
        // picker, trash it. All one group, un-merged by one undo.
        let mut ops = Vec::new();
        for c in &carriers {
            let replaces = self
                .cell(*c, property)?
                .into_iter()
                .filter(|(_, v)| *v == Value::Ref(option))
                .map(|(d, _)| d)
                .collect();
            ops.push(Op::SetCell {
                entity: *c,
                prop: property,
                value: Value::Ref(existing),
                replaces,
            });
        }
        let detach: Vec<crate::id::Dot> = self
            .cell(property, prop::OPTIONS)?
            .into_iter()
            .filter(|(_, v)| *v == Value::Ref(option))
            .map(|(d, _)| d)
            .collect();
        if !detach.is_empty() {
            ops.push(Op::RemoveFromSet {
                entity: property,
                prop: prop::OPTIONS,
                value: Value::Ref(option),
                replaces: detach,
            });
        }
        ops.push(Op::SetCell {
            entity: option,
            prop: prop::TRASHED,
            value: Value::Bool(true),
            replaces: self.cell(option, prop::TRASHED)?.into_iter().map(|(d, _)| d).collect(),
        });
        Ok((ops, carriers.len()))
    }

    /// Is this backstage plumbing rather than something the user made?
    fn is_working(&self, entity: EntityId) -> Result<bool, LogError> {
        Ok(matches!(self.one(entity, prop::WORKING)?, Some(Value::Bool(true))))
    }
}
