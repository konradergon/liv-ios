//! The furniture, and the rules about what may go in a cell.
//!
//! **The furniture is compiled in, not seeded.** The six fields, six
//! kinds and six areas are constants in the binary — they are not written
//! by any op and they are not in any box. That is the whole answer to the
//! drift `core.md` §2 names: two devices cannot seed slightly different
//! versions of "Area" if neither device ever seeds it. It is also why the
//! product can say *areas, fields and kinds are ours, and they don't
//! grow*: growth would require a write, and there is nowhere to write.
//!
//! **A user-created field is data**, because the product allows one
//! "behind a door in Settings". So a property id resolves either to a
//! definition here or to an entity in the box, and callers ask rather than
//! assume.
//!
//! ## The discriminator
//!
//! `core-decisions.md` flagged that `id < FIRST_USER_ID` — the old trick
//! for "is this plumbing" — dies with UUIDv7, because v7 sorts by time
//! rather than by namespace, and that a **real** discriminator was needed.
//! This is it: furniture ids are UUID version 8, the variant reserved for
//! custom layouts, with the class in the low nibble and a readable marker
//! in the tail. Checking is one nibble, and a stray furniture id is
//! obvious in a hex dump.
//!
//! Their timestamp bytes are zero, so they also sort before every id that
//! was ever minted — which keeps "oldest first" meaningful without
//! anything having to special-case them.

use crate::id::EntityId;
use crate::op::Value;

const CLASS_PROP: u8 = 1;
const CLASS_KIND: u8 = 2;
const CLASS_AREA: u8 = 3;
const CLASS_STATUS: u8 = 4;

/// Build a frozen id. `const fn`, so these are real constants rather than
/// something computed at startup that could vary between builds.
const fn frozen(class: u8, ordinal: u8) -> EntityId {
    EntityId([
        0, 0, 0, 0, 0, 0, // timestamp zero: sorts before everything minted
        0x80 | class,     // UUID version 8, class in the low nibble
        ordinal,
        0x80,             // RFC 4122 variant
        b'L', b'I', b'V', b'F', b'U', b'R', b'N',
    ])
}

/// Is this one of ours, rather than something a user made?
pub fn is_furniture(id: EntityId) -> bool {
    id.0[6] >> 4 == 0x8 && &id.0[9..16] == b"LIVFURN"
}

fn class_of(id: EntityId) -> Option<u8> {
    if is_furniture(id) {
        Some(id.0[6] & 0x0f)
    } else {
        None
    }
}

// ---- properties -------------------------------------------------------

/// The six the user picks from, plus the plumbing every entity needs.
pub mod prop {
    use super::{frozen, CLASS_PROP};
    use crate::id::EntityId;

    // Plumbing. Never offered as a field to fill in.
    pub const KIND: EntityId = frozen(CLASS_PROP, 0);
    pub const NAME: EntityId = frozen(CLASS_PROP, 1);
    pub const BODY: EntityId = frozen(CLASS_PROP, 2);
    /// Soft. A trashed entity still exists and can come back — `core.md`
    /// has no Delete, and Create's inverse is Trash.
    pub const TRASHED: EntityId = frozen(CLASS_PROP, 3);

    // The six.
    pub const DUE: EntityId = frozen(CLASS_PROP, 4);
    pub const STATUS: EntityId = frozen(CLASS_PROP, 5);
    pub const AREA: EntityId = frozen(CLASS_PROP, 6);
    pub const PROJECT: EntityId = frozen(CLASS_PROP, 7);
    pub const PEOPLE: EntityId = frozen(CLASS_PROP, 8);
    pub const TAGS: EntityId = frozen(CLASS_PROP, 9);
}

/// What a property may hold. Closed, so a value that does not fit is
/// refused at the door rather than found later.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Holds {
    Text,
    Bool,
    Date,
    /// A reference to another entity — the mechanism that makes renaming
    /// a project one write.
    Ref,
    /// A reference that must point at furniture of a given class.
    Furniture(u8),
    Blob,
}

pub struct PropDef {
    pub id: EntityId,
    pub name: &'static str,
    /// A set rather than a register: many live values are members, not a
    /// conflict.
    pub many: bool,
    pub holds: Holds,
    /// One of the six a user picks from, rather than plumbing.
    pub shown: bool,
}

pub const PROPS: &[PropDef] = &[
    PropDef { id: prop::KIND, name: "kind", many: false, holds: Holds::Furniture(CLASS_KIND), shown: false },
    PropDef { id: prop::NAME, name: "name", many: false, holds: Holds::Text, shown: false },
    PropDef { id: prop::BODY, name: "body", many: false, holds: Holds::Text, shown: false },
    PropDef { id: prop::TRASHED, name: "trashed", many: false, holds: Holds::Bool, shown: false },
    PropDef { id: prop::DUE, name: "due", many: false, holds: Holds::Date, shown: true },
    PropDef { id: prop::STATUS, name: "status", many: false, holds: Holds::Furniture(CLASS_STATUS), shown: true },
    PropDef { id: prop::AREA, name: "area", many: false, holds: Holds::Furniture(CLASS_AREA), shown: true },
    PropDef { id: prop::PROJECT, name: "project", many: false, holds: Holds::Ref, shown: true },
    PropDef { id: prop::PEOPLE, name: "people", many: true, holds: Holds::Ref, shown: true },
    PropDef { id: prop::TAGS, name: "tags", many: true, holds: Holds::Ref, shown: true },
];

pub fn prop_def(id: EntityId) -> Option<&'static PropDef> {
    PROPS.iter().find(|p| p.id == id)
}

/// The six a user picks from, in the order the product states them.
pub fn shown_props() -> impl Iterator<Item = &'static PropDef> {
    PROPS.iter().filter(|p| p.shown)
}

// ---- kinds, areas, statuses -------------------------------------------

pub mod kind {
    use super::{frozen, CLASS_KIND};
    use crate::id::EntityId;
    pub const NOTE: EntityId = frozen(CLASS_KIND, 0);
    pub const TASK: EntityId = frozen(CLASS_KIND, 1);
    pub const EVENT: EntityId = frozen(CLASS_KIND, 2);
    pub const PHOTO: EntityId = frozen(CLASS_KIND, 3);
    pub const PERSON: EntityId = frozen(CLASS_KIND, 4);
    pub const LINK: EntityId = frozen(CLASS_KIND, 5);
}

pub mod area {
    use super::{frozen, CLASS_AREA};
    use crate::id::EntityId;
    pub const WORK: EntityId = frozen(CLASS_AREA, 0);
    pub const HEALTH: EntityId = frozen(CLASS_AREA, 1);
    pub const MONEY: EntityId = frozen(CLASS_AREA, 2);
    pub const HOME: EntityId = frozen(CLASS_AREA, 3);
    pub const FAMILY: EntityId = frozen(CLASS_AREA, 4);
    pub const LEARNING: EntityId = frozen(CLASS_AREA, 5);
}

pub mod status {
    use super::{frozen, CLASS_STATUS};
    use crate::id::EntityId;
    pub const TODO: EntityId = frozen(CLASS_STATUS, 0);
    pub const DOING: EntityId = frozen(CLASS_STATUS, 1);
    pub const DONE: EntityId = frozen(CLASS_STATUS, 2);
}

/// The name to show for a piece of furniture.
///
/// **The only place these words exist.** A shell asks rather than
/// carrying its own copy — the current tree keeps the six area names as a
/// Swift constant, which is precisely the shell-side furnishing
/// `one-core.md` §4 records as a mistake.
pub fn label(id: EntityId) -> Option<&'static str> {
    match class_of(id)? {
        CLASS_PROP => prop_def(id).map(|p| p.name),
        CLASS_KIND => Some(match id.0[7] {
            0 => "Note",
            1 => "Task",
            2 => "Event",
            3 => "Photo",
            4 => "Person",
            5 => "Link",
            _ => return None,
        }),
        CLASS_AREA => Some(match id.0[7] {
            0 => "Work",
            1 => "Health",
            2 => "Money",
            3 => "Home",
            4 => "Family & Friends",
            5 => "Learning",
            _ => return None,
        }),
        CLASS_STATUS => Some(match id.0[7] {
            0 => "To do",
            1 => "Doing",
            2 => "Done",
            _ => return None,
        }),
        _ => None,
    }
}

/// Every kind, in product order.
pub const KINDS: &[EntityId] =
    &[kind::NOTE, kind::TASK, kind::EVENT, kind::PHOTO, kind::PERSON, kind::LINK];

/// Every area, in product order — the six researched rather than
/// invented (`what-liv-is-for.md`, 2026-07-27).
pub const AREAS: &[EntityId] =
    &[area::WORK, area::HEALTH, area::MONEY, area::HOME, area::FAMILY, area::LEARNING];

pub const STATUSES: &[EntityId] = &[status::TODO, status::DOING, status::DONE];

// ---- what may go in a cell --------------------------------------------

#[derive(Debug, PartialEq, Eq)]
pub enum Refused {
    /// A property nothing knows about, and not a user-created one either.
    UnknownProperty,
    /// The right shape of value, but the wrong kind of thing.
    WrongKind,
    /// A furniture reference pointing at the wrong class — an area where
    /// a status belongs.
    WrongClass,
}

/// May this value go in this cell?
///
/// **Refused at the door.** `core.md` §2 calls the value set closed and
/// says a value that does not fit is refused rather than discovered
/// later; this is where that happens. A property the model does not know
/// is allowed to hold anything — it is a user-created field, and the
/// engine has no opinion about those beyond storing them.
pub fn check(prop: EntityId, value: &Value) -> Result<(), Refused> {
    let Some(def) = prop_def(prop) else {
        return if is_furniture(prop) { Err(Refused::UnknownProperty) } else { Ok(()) };
    };
    let ok = match (def.holds, value) {
        (Holds::Text, Value::Text(_)) => true,
        (Holds::Bool, Value::Bool(_)) => true,
        (Holds::Date, Value::Date(_)) => true,
        (Holds::Blob, Value::Blob(_)) => true,
        (Holds::Ref, Value::Ref(_)) => true,
        (Holds::Furniture(class), Value::Ref(target)) => {
            return if class_of(*target) == Some(class) { Ok(()) } else { Err(Refused::WrongClass) }
        }
        _ => false,
    };
    if ok {
        Ok(())
    } else {
        Err(Refused::WrongKind)
    }
}

/// Is this property a set rather than a register? Unknown properties —
/// user-created fields — are registers, which is the safer default: a
/// register shows contention rather than silently accumulating.
pub fn is_many(prop: EntityId) -> bool {
    prop_def(prop).map(|p| p.many).unwrap_or(false)
}
