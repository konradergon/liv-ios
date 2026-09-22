//! Writing, with the merge rule built in.
//!
//! **A register write must name what it replaced**, or two devices can
//! never tell a correction from a collision. Getting that right is not
//! something callers should have to remember, so it lives here: `set`
//! reads what is live and names those dots, and a shell just says what it
//! wants the value to be.
//!
//! Every verb here is one user action — one group, one commit, one undo
//! step (`core-decisions.md` §4).

use crate::engine::Engine;
use crate::id::{Dot, EntityId};
use crate::log::LogError;
use crate::model::{self, prop, Refused};
use crate::op::{Author, Op, Value};

/// What the user did. **Frozen and append-only**: the number is on disk
/// forever, so a code is never reused and never re-meaned.
pub mod action {
    pub const CREATE: u16 = 1;
    pub const SET: u16 = 2;
    pub const ADD: u16 = 3;
    pub const REMOVE: u16 = 4;
    pub const TRASH: u16 = 5;
    pub const RESTORE: u16 = 6;
    pub const RENAME: u16 = 7;
    /// Minting a piece of vocabulary the app did not ship with: a seventh
    /// field, a seventh area, a status option.
    pub const DECLARE: u16 = 8;
    /// Taking one back. A redo carries this too — a redo IS an undo, of
    /// an undo, and the log says which by what its `reverses` points at.
    pub const UNDO: u16 = 9;
}

#[derive(Debug)]
pub enum WriteError {
    Log(LogError),
    /// The value does not belong in that cell.
    Refused(Refused),
    /// `add` or `remove` on a register, or `set` on a set. The caller
    /// asked for the wrong shape of write, which is a bug rather than a
    /// user error.
    WrongCardinality { prop: EntityId, many: bool },
    /// This device has done nothing that is still in effect.
    NothingToUndo,
    /// Nothing has been undone that has not since been redone or written
    /// over.
    NothingToRedo,
}

impl std::fmt::Display for WriteError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            WriteError::Log(e) => write!(f, "{e}"),
            WriteError::Refused(r) => write!(f, "refused: {r:?}"),
            WriteError::WrongCardinality { many, .. } => {
                write!(f, "that property is a {}", if *many { "set" } else { "register" })
            }
            WriteError::NothingToUndo => write!(f, "nothing to undo"),
            WriteError::NothingToRedo => write!(f, "nothing to redo"),
        }
    }
}

impl std::error::Error for WriteError {}

impl From<LogError> for WriteError {
    fn from(e: LogError) -> WriteError {
        WriteError::Log(e)
    }
}

/// What a property holds and how many — resolved for a compiled-in
/// property or a declared one, with nothing above having to know which it
/// was.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PropShape {
    pub holds: model::Holds,
    pub many: bool,
}

impl Engine {
    /// What kind of thing this is — **whichever half it came from**.
    ///
    /// Compiled-in furniture answers from its class nibble without
    /// touching the box; anything else answers from its `kind` cell. This
    /// is the join that lets `Holds::RefTo` accept the six areas and a
    /// seventh the user minted, by one rule.
    pub fn kind_of_any(&self, id: EntityId) -> Result<Option<EntityId>, LogError> {
        if let Some(k) = model::furniture_kind(id) {
            return Ok(Some(k));
        }
        self.kind_of(id)
    }

    /// What a property holds. Compiled-in first, then the box.
    ///
    /// **A declared field describes itself in cells**: `prop::HOLDS`
    /// carries one of `Holds::named`'s words — the same `value-kind`
    /// vocabulary a `core/` box already writes — and `prop::MANY` says
    /// whether it is a set. A property that is neither compiled in nor
    /// declared gets `None`, and the engine keeps its old promise about
    /// those: store it, have no opinion.
    pub fn prop_shape(&self, prop: EntityId) -> Result<Option<PropShape>, LogError> {
        if let Some(def) = model::prop_def(prop) {
            return Ok(Some(PropShape { holds: def.holds, many: def.many }));
        }
        // A frozen id that is not in PROPS is a retired ordinal or a
        // forgery; either way there is nothing to declare it.
        if model::is_furniture(prop) {
            return Ok(None);
        }
        let Some(Value::Text(word)) = self.one(prop, model::prop::HOLDS)? else {
            return Ok(None);
        };
        let Some(holds) = model::Holds::named(&word) else { return Ok(None) };
        let many = matches!(self.one(prop, model::prop::MANY)?, Some(Value::Bool(true)));
        Ok(Some(PropShape { holds, many }))
    }

    /// Declare a field the app did not ship with — the product's "new kind
    /// of field behind a door in Settings".
    ///
    /// It is an ordinary entity of `kind::FIELD` carrying its name and its
    /// shape, minted ONCE on one device. That is why it cannot drift the
    /// way a seeded copy does: there is no second copy.
    /// **ASKING TWICE ASKS ONCE** (2026-09-22). `declare_value` below has
    /// always handed back the one that exists rather than a second thing
    /// by the same name; this minted unconditionally, and the difference
    /// was invisible because nothing can reach a shadowed field:
    /// `property_named` reads the compiled-in `PROPS` first, and a minted
    /// field carries `working` so no list shows it.
    ///
    /// A caller that has to ASK is the whole point of the verb — the
    /// shell mints a workspace's properties precisely because `set`
    /// refuses a name the box has never seen, and it cannot know in
    /// advance. So every save of such a workspace left another "area"
    /// behind, in an append-only box that was never going to tidy up.
    pub fn declare_field(
        &mut self,
        name: &str,
        holds: &str,
        many: bool,
        now_ms: u64,
    ) -> Result<EntityId, WriteError> {
        if model::Holds::named(holds).is_none() {
            return Err(WriteError::Refused(Refused::UnknownProperty));
        }
        // A NAME THE APP SHIPPED IS ALREADY DECLARED, and the frozen id
        // is the one every reader resolves to — minting beside it would
        // make a field nothing can reach.
        if let Some(def) = model::PROPS.iter().find(|d| d.name.eq_ignore_ascii_case(name)) {
            return Ok(def.id);
        }
        for id in self.of_kind(model::kind::FIELD)? {
            if self.name(id)?.is_some_and(|n| n.eq_ignore_ascii_case(name)) {
                return Ok(id);
            }
        }
        let id = self.mint(now_ms);
        let ops = vec![
            Op::CreateEntity { entity: id },
            Op::SetCell { entity: id, prop: prop::KIND, value: Value::Ref(model::kind::FIELD), replaces: vec![] },
            Op::SetCell { entity: id, prop: prop::NAME, value: Value::Text(name.to_owned()), replaces: vec![] },
            Op::SetCell { entity: id, prop: model::prop::HOLDS, value: Value::Text(holds.to_owned()), replaces: vec![] },
            Op::SetCell { entity: id, prop: model::prop::MANY, value: Value::Bool(many), replaces: vec![] },
            Op::SetCell { entity: id, prop: model::prop::WORKING, value: Value::Bool(true), replaces: vec![] },
        ];
        self.commit(ops, action::DECLARE, Author::User, now_ms)?;
        Ok(id)
    }

    /// Mint a piece of vocabulary the app did not ship with: a seventh
    /// area, a status option, a select's choice.
    ///
    /// **Areas grow** (`what-liv-is-for.md`, amended 2026-08-29). The six
    /// stay what the app arrives with; this is the create row the
    /// amendment asked for.
    pub fn declare(
        &mut self,
        kind: EntityId,
        name: &str,
        now_ms: u64,
    ) -> Result<EntityId, WriteError> {
        let id = self.mint(now_ms);
        let ops = vec![
            Op::CreateEntity { entity: id },
            Op::SetCell { entity: id, prop: prop::KIND, value: Value::Ref(kind), replaces: vec![] },
            Op::SetCell { entity: id, prop: prop::NAME, value: Value::Text(name.to_owned()), replaces: vec![] },
            Op::SetCell { entity: id, prop: model::prop::WORKING, value: Value::Bool(true), replaces: vec![] },
        ];
        self.commit(ops, action::DECLARE, Author::User, now_ms)?;
        Ok(id)
    }

    /// The same gate, for one op whose shape a caller did not choose —
    /// which is what a PROPOSAL is. Consent is not a bypass.
    pub(crate) fn vet_op(&self, op: &Op) -> Result<(), WriteError> {
        match op {
            Op::CreateEntity { .. } => Ok(()),
            Op::SetCell { prop, value, .. } => self.vet(*prop, value, false),
            Op::AddToSet { prop, value, .. } | Op::RemoveFromSet { prop, value, .. } => {
                self.vet(*prop, value, true)
            }
        }
    }

    /// The one gate every write goes through.
    fn vet(&self, prop: EntityId, value: &Value, many: bool) -> Result<(), WriteError> {
        let Some(shape) = self.prop_shape(prop)? else { return Ok(()) };
        if shape.many != many {
            return Err(WriteError::WrongCardinality { prop, many: shape.many });
        }
        // Resolve the target's kind before checking, so the closure does
        // not have to borrow across the check.
        let target_kind = match value {
            Value::Ref(t) => self.kind_of_any(*t)?,
            _ => None,
        };
        model::check(shape.holds, value, |_| target_kind).map_err(WriteError::Refused)
    }

    /// A new thing of a kind, named or not.
    ///
    /// One action, so one undo step: creating a note and giving it its
    /// kind is not two things the user did.
    pub fn create(
        &mut self,
        kind: EntityId,
        name: Option<&str>,
        now_ms: u64,
    ) -> Result<EntityId, WriteError> {
        let id = self.mint(now_ms);
        let mut ops = vec![
            Op::CreateEntity { entity: id },
            Op::SetCell {
                entity: id,
                prop: prop::KIND,
                value: Value::Ref(kind),
                replaces: vec![],
            },
        ];
        if let Some(n) = name {
            ops.push(Op::SetCell {
                entity: id,
                prop: prop::NAME,
                value: Value::Text(n.to_owned()),
                replaces: vec![],
            });
        }
        self.commit(ops, action::CREATE, Author::User, now_ms)?;
        Ok(id)
    }

    /// Capture a scrap: one UNTYPED thing whose body is this text, in one
    /// action.
    ///
    /// **Untyped is the point, not an omission.** A capture is a thought,
    /// and deciding what kind of thing it is comes later — the clerk's
    /// promotion proposer is what offers to make it a task, and it can
    /// only offer that because nothing here decided first (it returns
    /// early the moment a `kind` cell exists).
    ///
    /// Until this existed there was no way to make one: `create` always
    /// writes a `kind`, so the promotion test had to hand-write a
    /// `RemoveFromSet` to take it back off again. A test forced to build
    /// something the app cannot build is a missing door.
    ///
    /// One group, so one undo takes the whole capture back rather than
    /// leaving an empty note behind.
    pub fn capture(&mut self, text: &str, now_ms: u64) -> Result<EntityId, WriteError> {
        let id = self.mint(now_ms);
        let mut ops = vec![Op::CreateEntity { entity: id }];
        if !text.is_empty() {
            ops.push(Op::SetCell {
                entity: id,
                prop: prop::BODY,
                value: Value::Rich(vec![crate::rich::Span::text(text.to_owned())]),
                replaces: vec![],
            });
        }
        self.commit(ops, action::CREATE, Author::User, now_ms)?;
        Ok(id)
    }

    /// Empty a cell.
    ///
    /// **Not the same as setting it to nothing** — an unset cell has no
    /// value at all, which is what a picker's "None" means and what a due
    /// date cleared off a task means. The four ops give exactly one shape
    /// for it: retire the live dots and put nothing back.
    ///
    /// Unsetting what is already unset writes nothing rather than logging
    /// an empty action, so a picker set to "None" twice does not leave two
    /// things in the undo history.
    pub fn unset(
        &mut self,
        entity: EntityId,
        prop: EntityId,
        now_ms: u64,
    ) -> Result<Option<Dot>, WriteError> {
        let replaces: Vec<Dot> = self.cell(entity, prop)?.into_iter().map(|(d, _)| d).collect();
        if replaces.is_empty() {
            return Ok(None);
        }
        let ops = vec![Op::RemoveFromSet {
            entity,
            prop,
            value: Value::Text(String::new()),
            replaces,
        }];
        Ok(Some(self.commit(ops, action::SET, Author::User, now_ms)?))
    }

    /// Set a single-valued property.
    ///
    /// **Names every value it can see.** A device that had not seen a
    /// concurrent write does not name it, so that value survives and the
    /// cell becomes contended — which is the whole of the register rule
    /// and the reason nothing silently wins.
    pub fn set(
        &mut self,
        entity: EntityId,
        prop: EntityId,
        value: Value,
        now_ms: u64,
    ) -> Result<Dot, WriteError> {
        self.vet(prop, &value, false)?;
        let replaces: Vec<Dot> = self.cell(entity, prop)?.into_iter().map(|(d, _)| d).collect();
        let ops = vec![Op::SetCell { entity, prop, value, replaces }];
        Ok(self.commit(ops, action::SET, Author::User, now_ms)?)
    }

    /// Add one member to a multi-valued property.
    pub fn add(
        &mut self,
        entity: EntityId,
        prop: EntityId,
        value: Value,
        now_ms: u64,
    ) -> Result<Dot, WriteError> {
        self.vet(prop, &value, true)?;
        let ops = vec![Op::AddToSet { entity, prop, value }];
        Ok(self.commit(ops, action::ADD, Author::User, now_ms)?)
    }

    /// Remove one member.
    ///
    /// **Add-wins.** This names only the adds it can see, so a member
    /// added concurrently on another device survives the removal — which
    /// is the set rule from `core.md` §5, and the reason a tag added on
    /// the phone is not lost by a removal on the laptop.
    pub fn remove(
        &mut self,
        entity: EntityId,
        prop: EntityId,
        value: &Value,
        now_ms: u64,
    ) -> Result<Dot, WriteError> {
        self.vet(prop, value, true)?;
        let replaces: Vec<Dot> = self
            .cell(entity, prop)?
            .into_iter()
            .filter(|(_, v)| v == value)
            .map(|(d, _)| d)
            .collect();
        let ops = vec![Op::RemoveFromSet {
            entity,
            prop,
            value: value.clone(),
            replaces,
        }];
        Ok(self.commit(ops, action::REMOVE, Author::User, now_ms)?)
    }

    /// Soft, and reversible. There is no Delete — `core.md` says
    /// Create's inverse is Trash, and a trashed thing still exists.
    pub fn trash(&mut self, entity: EntityId, now_ms: u64) -> Result<Dot, WriteError> {
        let replaces: Vec<Dot> =
            self.cell(entity, prop::TRASHED)?.into_iter().map(|(d, _)| d).collect();
        let ops = vec![Op::SetCell {
            entity,
            prop: prop::TRASHED,
            value: Value::Bool(true),
            replaces,
        }];
        Ok(self.commit(ops, action::TRASH, Author::User, now_ms)?)
    }

    pub fn restore(&mut self, entity: EntityId, now_ms: u64) -> Result<Dot, WriteError> {
        let replaces: Vec<Dot> =
            self.cell(entity, prop::TRASHED)?.into_iter().map(|(d, _)| d).collect();
        let ops = vec![Op::SetCell {
            entity,
            prop: prop::TRASHED,
            value: Value::Bool(false),
            replaces,
        }];
        Ok(self.commit(ops, action::RESTORE, Author::User, now_ms)?)
    }

    // ---- reading ------------------------------------------------------

    /// The one live value of a register, or `None` when it is unset —
    /// **or contended**. A caller that must handle contention asks
    /// `cell` and gets all of them; a caller that just wants to show
    /// something gets an honest "not one answer".
    pub fn one(&self, entity: EntityId, prop: EntityId) -> Result<Option<Value>, LogError> {
        let live = self.cell(entity, prop)?;
        Ok(if live.len() == 1 { Some(live.into_iter().next().unwrap().1) } else { None })
    }

    pub fn contended(&self, entity: EntityId, prop: EntityId) -> Result<bool, LogError> {
        Ok(self.cell(entity, prop)?.len() > 1)
    }

    pub fn name(&self, entity: EntityId) -> Result<Option<String>, LogError> {
        Ok(match self.one(entity, prop::NAME)? {
            Some(Value::Text(s)) => Some(s),
            _ => None,
        })
    }

    pub fn kind_of(&self, entity: EntityId) -> Result<Option<EntityId>, LogError> {
        Ok(match self.one(entity, prop::KIND)? {
            Some(Value::Ref(k)) => Some(k),
            _ => None,
        })
    }

    pub fn is_trashed(&self, entity: EntityId) -> Result<bool, LogError> {
        Ok(matches!(self.one(entity, prop::TRASHED)?, Some(Value::Bool(true))))
    }
}
