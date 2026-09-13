//! The furniture, and the rules about what may go in a cell.
//!
//! **The furniture is compiled in, not seeded.** Everything Liv ships with
//! — every property, every kind, the six areas, the three statuses — is a
//! constant in the binary. It is not written by any op and it is not in any
//! box. That is the whole answer to the drift `core.md` §2 names: two
//! devices cannot seed slightly different versions of "Work" if neither
//! device ever seeds it.
//!
//! **But it is a floor, not a ceiling** (`rust-owns-the-mechanisms.md` §2,
//! owner 2026-09-13). The box may declare more, and it must: a fresh
//! `core/` box carries 51 property definitions, the product amended itself
//! on 2026-08-29 so that **areas grow**, and every piece of backstage
//! furniture the app has — workspaces, saved views, layers, widgets,
//! habits, pins — is an entity.
//!
//! The distinction that matters is not *compiled-in vs declared*, it is
//! **seeded vs minted**. The drift bug was seeding: each device making its
//! own "Work" on first launch, so two devices ended up with two. A thing
//! the user mints is created ONCE, on one device, and syncs as itself —
//! there is no second copy to disagree with. So:
//!
//! * what Liv ships with is compiled in, and never written;
//! * what the box adds is an entity, minted once;
//! * and **one rule covers both**: `kind_of` answers for a frozen id from
//!   its class nibble and for a minted one from its `kind` cell, so a
//!   reference constrained to a kind is checked the same way either way.
//!
//! `is_furniture` keeps its job — "did this ship with the app" is still
//! worth asking. It stops being the same question as "is this allowed to
//! exist".
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

/// Did this ship with the app, rather than being minted in a box?
///
/// **Not the same question as "may this exist".** A minted area, a user's
/// seventh field and every workspace are ordinary entities and answer
/// `false` here; that is correct and says nothing about whether they are
/// allowed. What this answers is whether the id is frozen in the binary —
/// which is what makes it identical on every device without a sync.
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

/// What kind of thing a piece of frozen furniture is.
///
/// **The bridge between the two halves.** A minted entity says what it is
/// in a `kind` cell; a frozen one says it in its class nibble. This maps
/// the second onto the first, so `Holds::RefTo(kind::AREA)` accepts the
/// compiled-in Work and a user's "Woodworking" by one rule rather than
/// two. The engine-side resolver (`Engine::kind_of_any`) is what joins
/// them.
pub fn furniture_kind(id: EntityId) -> Option<EntityId> {
    Some(match class_of(id)? {
        CLASS_PROP => kind::FIELD,
        CLASS_KIND => kind::KIND,
        CLASS_AREA => kind::AREA,
        CLASS_STATUS => kind::STATUS,
        _ => return None,
    })
}

// ---- properties -------------------------------------------------------

/// Every property Liv ships with.
///
/// **Ordinals are on disk forever.** Append only; never renumber, never
/// reuse. A gap where something was retired is correct and cheap.
///
/// The six the user picks from are `shown`; the rest is plumbing the app
/// needs and never offers as a field to fill in. All of it is compiled in
/// for the same reason: it is ours, so seeding it per device would be the
/// drift bug and declaring it per box would be 51 writes that say the same
/// thing in every box that will ever exist.
pub mod prop {
    use super::{frozen, CLASS_PROP};
    use crate::id::EntityId;

    // ---- the spine every entity has -----------------------------------
    pub const KIND: EntityId = frozen(CLASS_PROP, 0);
    pub const NAME: EntityId = frozen(CLASS_PROP, 1);
    pub const BODY: EntityId = frozen(CLASS_PROP, 2);
    /// Soft. A trashed entity still exists and can come back — `core.md`
    /// has no Delete, and Create's inverse is Trash.
    pub const TRASHED: EntityId = frozen(CLASS_PROP, 3);

    // ---- the six the user picks from ----------------------------------
    pub const DUE: EntityId = frozen(CLASS_PROP, 4);
    pub const STATUS: EntityId = frozen(CLASS_PROP, 5);
    pub const AREA: EntityId = frozen(CLASS_PROP, 6);
    pub const PROJECT: EntityId = frozen(CLASS_PROP, 7);
    pub const PEOPLE: EntityId = frozen(CLASS_PROP, 8);
    pub const TAGS: EntityId = frozen(CLASS_PROP, 9);

    // ---- describing a declared field ----------------------------------
    /// On a `kind::FIELD` entity: what it holds, as one of the words in
    /// `Holds::named`. This is `value-kind` in the box today.
    pub const HOLDS: EntityId = frozen(CLASS_PROP, 10);
    /// On a `kind::FIELD` entity: set rather than register.
    pub const MANY: EntityId = frozen(CLASS_PROP, 11);
    /// On a select field: the options it offers.
    pub const OPTIONS: EntityId = frozen(CLASS_PROP, 12);
    /// On a field: which kinds expect it.
    pub const FOR_KIND: EntityId = frozen(CLASS_PROP, 13);

    // ---- backstage --------------------------------------------------
    /// Plumbing on the shelf: real, addressable, and kept out of the
    /// front-of-house lists.
    pub const WORKING: EntityId = frozen(CLASS_PROP, 14);
    /// Excluded from machine context.
    pub const PRIVATE: EntityId = frozen(CLASS_PROP, 15);
    pub const ARCHIVED: EntityId = frozen(CLASS_PROP, 16);
    pub const BOOKMARKED: EntityId = frozen(CLASS_PROP, 17);
    pub const FAVORITE: EntityId = frozen(CLASS_PROP, 18);
    /// Float key: ordering without renumbering the neighbours.
    pub const ORDER: EntityId = frozen(CLASS_PROP, 19);
    pub const PARENT: EntityId = frozen(CLASS_PROP, 20);
    pub const QUERY: EntityId = frozen(CLASS_PROP, 21);
    pub const BUILTIN: EntityId = frozen(CLASS_PROP, 22);
    pub const WORKSPACE: EntityId = frozen(CLASS_PROP, 23);
    pub const EXTERNAL_ID: EntityId = frozen(CLASS_PROP, 24);

    // ---- display ------------------------------------------------------
    pub const EMOJI: EntityId = frozen(CLASS_PROP, 25);
    pub const ICON: EntityId = frozen(CLASS_PROP, 26);
    pub const HUE: EntityId = frozen(CLASS_PROP, 27);
    pub const DIGIT_KEY: EntityId = frozen(CLASS_PROP, 28);
    pub const HIDE_WHEN_EMPTY: EntityId = frozen(CLASS_PROP, 29);
    pub const HIDE_ON_KIND: EntityId = frozen(CLASS_PROP, 30);
    pub const CORE_ON_KIND: EntityId = frozen(CLASS_PROP, 31);
    /// On a status option: does reaching it finish the thing.
    pub const COMPLETES: EntityId = frozen(CLASS_PROP, 32);
    pub const DEFAULT_STATUS: EntityId = frozen(CLASS_PROP, 33);

    // ---- time ---------------------------------------------------------
    pub const RECURRENCE: EntityId = frozen(CLASS_PROP, 34);
    pub const EXCEPTION_OF: EntityId = frozen(CLASS_PROP, 35);
    pub const DATE: EntityId = frozen(CLASS_PROP, 36);
    pub const VALID_UNTIL: EntityId = frozen(CLASS_PROP, 37);
    pub const OCCURRED: EntityId = frozen(CLASS_PROP, 38);
    pub const PURCHASED_ON: EntityId = frozen(CLASS_PROP, 39);

    // ---- files and links ----------------------------------------------
    pub const FILE: EntityId = frozen(CLASS_PROP, 40);
    pub const FORMAT: EntityId = frozen(CLASS_PROP, 41);
    pub const URL: EntityId = frozen(CLASS_PROP, 42);

    // ---- people and events --------------------------------------------
    pub const LOCATION: EntityId = frozen(CLASS_PROP, 43);
    pub const ATTENDEES: EntityId = frozen(CLASS_PROP, 44);
    pub const ROLE: EntityId = frozen(CLASS_PROP, 45);
    pub const ORG: EntityId = frozen(CLASS_PROP, 46);
    pub const EMAIL: EntityId = frozen(CLASS_PROP, 47);
    pub const PHONE: EntityId = frozen(CLASS_PROP, 48);

    // ---- tasks, habits, work ------------------------------------------
    pub const PRIORITY: EntityId = frozen(CLASS_PROP, 49);
    pub const POINTS: EntityId = frozen(CLASS_PROP, 50);
    pub const CADENCE: EntityId = frozen(CLASS_PROP, 51);
    pub const HABIT: EntityId = frozen(CLASS_PROP, 52);
    pub const AUTOMATION: EntityId = frozen(CLASS_PROP, 53);
    pub const RELATED: EntityId = frozen(CLASS_PROP, 54);
}

/// What a property may hold. Closed, so a value that does not fit is
/// refused at the door rather than found later.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Holds {
    Text,
    Number,
    Bool,
    Date,
    /// A reference to another entity — the mechanism that makes renaming
    /// a project one write.
    Ref,
    /// A reference that must point at a thing of one kind. **Compiled-in
    /// furniture and a minted entity are both acceptable**, and checked
    /// the same way: `furniture_kind` for the first, the `kind` cell for
    /// the second. That is what lets the six areas and a user's seventh
    /// live in the same cell.
    RefTo(EntityId),
    Blob,
}

impl Holds {
    /// The word a declared field carries in its `prop::HOLDS` cell. The
    /// box already speaks these — they are the `value-kind` vocabulary a
    /// `core/` box writes today, so a converter needs no table.
    pub fn named(word: &str) -> Option<Holds> {
        Some(match word {
            "text" | "richtext" => Holds::Text,
            "number" => Holds::Number,
            "bool" => Holds::Bool,
            "datetime" => Holds::Date,
            "reference" => Holds::Ref,
            "select" => Holds::RefTo(kind::OPTION),
            "file" => Holds::Blob,
            _ => return None,
        })
    }
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

macro_rules! props {
    ($($id:expr, $name:literal, $many:literal, $holds:expr, $shown:literal;)*) => {
        pub const PROPS: &[PropDef] = &[
            $(PropDef { id: $id, name: $name, many: $many, holds: $holds, shown: $shown },)*
        ];
    };
}

props! {
    // id                  name               many   holds                        shown
    prop::KIND,            "kind",            false, Holds::RefTo(kind::KIND),     false;
    prop::NAME,            "name",            false, Holds::Text,                  false;
    prop::BODY,            "content",         false, Holds::Text,                  false;
    prop::TRASHED,         "trashed",         false, Holds::Bool,                  false;

    prop::DUE,             "due",             false, Holds::Date,                  true;
    prop::STATUS,          "status",          false, Holds::RefTo(kind::STATUS),   true;
    prop::AREA,            "area",            false, Holds::RefTo(kind::AREA),     true;
    prop::PROJECT,         "project",         false, Holds::RefTo(kind::PROJECT),  true;
    prop::PEOPLE,          "people",          true,  Holds::RefTo(kind::PERSON),   true;
    prop::TAGS,            "tags",            true,  Holds::Ref,                   true;

    prop::HOLDS,           "value-kind",      false, Holds::Text,                  false;
    prop::MANY,            "many",            false, Holds::Bool,                  false;
    prop::OPTIONS,         "options",         true,  Holds::RefTo(kind::OPTION),   false;
    prop::FOR_KIND,        "for-type",        true,  Holds::RefTo(kind::KIND),     false;

    prop::WORKING,         "working",         false, Holds::Bool,                  false;
    prop::PRIVATE,         "private",         false, Holds::Bool,                  false;
    prop::ARCHIVED,        "archived",        false, Holds::Bool,                  false;
    prop::BOOKMARKED,      "bookmarked",      false, Holds::Bool,                  false;
    prop::FAVORITE,        "favorite",        false, Holds::Bool,                  false;
    prop::ORDER,           "order",           false, Holds::Number,                false;
    prop::PARENT,          "parent",          false, Holds::Ref,                   false;
    prop::QUERY,           "query",           false, Holds::Text,                  false;
    prop::BUILTIN,         "builtin",         false, Holds::Text,                  false;
    prop::WORKSPACE,       "workspace",       false, Holds::RefTo(kind::WORKSPACE),false;
    prop::EXTERNAL_ID,     "external-id",     false, Holds::Text,                  false;

    prop::EMOJI,           "emoji",           false, Holds::Text,                  false;
    prop::ICON,            "icon",            false, Holds::Text,                  false;
    prop::HUE,             "hue",             false, Holds::Number,                false;
    prop::DIGIT_KEY,       "digit-key",       false, Holds::Text,                  false;
    prop::HIDE_WHEN_EMPTY, "hide-when-empty", false, Holds::Bool,                  false;
    prop::HIDE_ON_KIND,    "hide-on-kind",    true,  Holds::RefTo(kind::KIND),     false;
    prop::CORE_ON_KIND,    "core-on-kind",    true,  Holds::RefTo(kind::KIND),     false;
    prop::COMPLETES,       "completes",       false, Holds::Bool,                  false;
    prop::DEFAULT_STATUS,  "default-status",  false, Holds::RefTo(kind::STATUS),   false;

    prop::RECURRENCE,      "recurrence",      false, Holds::Text,                  false;
    prop::EXCEPTION_OF,    "exception-of",    false, Holds::Ref,                   false;
    prop::DATE,            "date",            false, Holds::Date,                  false;
    prop::VALID_UNTIL,     "valid-until",     false, Holds::Date,                  false;
    prop::OCCURRED,        "occurred",        false, Holds::Date,                  false;
    prop::PURCHASED_ON,    "purchased-on",    false, Holds::Date,                  false;

    prop::FILE,            "file",            false, Holds::Blob,                  false;
    prop::FORMAT,          "format",          false, Holds::Text,                  false;
    prop::URL,             "url",             false, Holds::Text,                  false;

    prop::LOCATION,        "location",        false, Holds::Text,                  false;
    prop::ATTENDEES,       "attendees",       true,  Holds::RefTo(kind::PERSON),   false;
    prop::ROLE,            "role",            false, Holds::Text,                  false;
    prop::ORG,             "org",             false, Holds::Text,                  false;
    prop::EMAIL,           "email",           false, Holds::Text,                  false;
    prop::PHONE,           "phone",           false, Holds::Text,                  false;

    prop::PRIORITY,        "priority",        false, Holds::RefTo(kind::OPTION),   false;
    prop::POINTS,          "points",          false, Holds::Number,                false;
    prop::CADENCE,         "cadence",         false, Holds::Text,                  false;
    prop::HABIT,           "habit",           false, Holds::RefTo(kind::HABIT),    false;
    prop::AUTOMATION,      "automation",      false, Holds::Bool,                  false;
    prop::RELATED,         "related",         true,  Holds::Ref,                   false;
}

pub fn prop_def(id: EntityId) -> Option<&'static PropDef> {
    PROPS.iter().find(|p| p.id == id)
}

/// The six a user picks from, in the order the product states them.
pub fn shown_props() -> impl Iterator<Item = &'static PropDef> {
    PROPS.iter().filter(|p| p.shown)
}

// ---- kinds, areas, statuses -------------------------------------------

/// **Kinds stay ours.** The product says fields and kinds "do not grow in
/// daily use" (`what-liv-is-for.md`, as amended 2026-08-29 — that
/// amendment freed *areas*, and said kinds were unchanged). So this list
/// grows in a release and never from a box.
///
/// Ordinals 0–5 are the six the product names. The rest is furniture the
/// app already has and the engine had no word for — every one of them is
/// an entity in a `core/` box today.
pub mod kind {
    use super::{frozen, CLASS_KIND};
    use crate::id::EntityId;

    // The six, in product order.
    pub const NOTE: EntityId = frozen(CLASS_KIND, 0);
    pub const TASK: EntityId = frozen(CLASS_KIND, 1);
    pub const EVENT: EntityId = frozen(CLASS_KIND, 2);
    pub const PHOTO: EntityId = frozen(CLASS_KIND, 3);
    pub const PERSON: EntityId = frozen(CLASS_KIND, 4);
    pub const LINK: EntityId = frozen(CLASS_KIND, 5);

    // Things the user makes that are not one of the six.
    pub const PROJECT: EntityId = frozen(CLASS_KIND, 6);
    pub const FILE: EntityId = frozen(CLASS_KIND, 7);
    pub const LIST: EntityId = frozen(CLASS_KIND, 8);
    pub const HABIT: EntityId = frozen(CLASS_KIND, 9);
    pub const CHECKIN: EntityId = frozen(CLASS_KIND, 10);

    // ---- what the vocabulary itself is made of ------------------------
    //
    // A kind is a kind of thing too: `furniture_kind` maps the frozen
    // classes onto these, so "what kind is this?" has ONE answer whether
    // the subject shipped with the app or was minted in a box.
    pub const KIND: EntityId = frozen(CLASS_KIND, 11);
    /// A property definition — the user's seventh field is one of these.
    pub const FIELD: EntityId = frozen(CLASS_KIND, 12);
    pub const AREA: EntityId = frozen(CLASS_KIND, 13);
    pub const STATUS: EntityId = frozen(CLASS_KIND, 14);
    /// One choice offered by a select field.
    pub const OPTION: EntityId = frozen(CLASS_KIND, 15);

    // ---- backstage: the chrome the app already draws -------------------
    pub const WORKSPACE: EntityId = frozen(CLASS_KIND, 16);
    pub const VIEW: EntityId = frozen(CLASS_KIND, 17);
    pub const LAYER: EntityId = frozen(CLASS_KIND, 18);
    pub const WIDGET: EntityId = frozen(CLASS_KIND, 19);
    pub const PIN: EntityId = frozen(CLASS_KIND, 20);
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
            6 => "Project",
            7 => "File",
            8 => "List",
            9 => "Habit",
            10 => "Check-in",
            11 => "Kind",
            12 => "Field",
            13 => "Area",
            14 => "Status",
            15 => "Option",
            16 => "Workspace",
            17 => "View",
            18 => "Layer",
            19 => "Widget",
            20 => "Pin",
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

/// **The six the product names**, in product order — what a create menu
/// offers. Not every kind that exists: `kind::WORKSPACE` and the rest are
/// furniture the app draws with, and a person never picks one from a list.
pub const KINDS: &[EntityId] =
    &[kind::NOTE, kind::TASK, kind::EVENT, kind::PHOTO, kind::PERSON, kind::LINK];

/// Every kind there is, the backstage ones included. For a converter or an
/// inspector, never for a picker.
pub const ALL_KINDS: &[EntityId] = &[
    kind::NOTE, kind::TASK, kind::EVENT, kind::PHOTO, kind::PERSON, kind::LINK,
    kind::PROJECT, kind::FILE, kind::LIST, kind::HABIT, kind::CHECKIN,
    kind::KIND, kind::FIELD, kind::AREA, kind::STATUS, kind::OPTION,
    kind::WORKSPACE, kind::VIEW, kind::LAYER, kind::WIDGET, kind::PIN,
];

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
/// says a value that does not fit is refused rather than discovered later;
/// this is where that happens.
///
/// `holds` is the shape the property declares — compiled-in from `PROPS`,
/// or read off a `kind::FIELD` entity. `kind_of` answers what a referenced
/// entity is, and it is a closure because a minted target's kind lives in
/// the box: `Engine::kind_of_any` is the one that knows. A `None` from it
/// means the target has no kind, which fails any constrained reference.
pub fn check(
    holds: Holds,
    value: &Value,
    kind_of: impl Fn(EntityId) -> Option<EntityId>,
) -> Result<(), Refused> {
    let ok = match (holds, value) {
        (Holds::Text, Value::Text(_)) => true,
        (Holds::Number, Value::Number(_)) => true,
        (Holds::Bool, Value::Bool(_)) => true,
        (Holds::Date, Value::Date(_)) => true,
        (Holds::Blob, Value::Blob(_)) => true,
        (Holds::Ref, Value::Ref(_)) => true,
        (Holds::RefTo(want), Value::Ref(target)) => {
            // ONE RULE FOR BOTH HALVES. The compiled-in Work answers from
            // its class nibble and a minted "Woodworking" from its `kind`
            // cell; neither is privileged, and that is what lets areas
            // grow without the cell losing its meaning.
            return if kind_of(*target) == Some(want) {
                Ok(())
            } else {
                Err(Refused::WrongClass)
            };
        }
        _ => false,
    };
    if ok {
        Ok(())
    } else {
        Err(Refused::WrongKind)
    }
}

/// Is this property a set rather than a register?
///
/// Only answers for the compiled-in ones; a declared field says so in its
/// `prop::MANY` cell and `Engine::prop_shape` reads it. An unknown
/// property is a register, which is the safer default: a register shows
/// contention rather than silently accumulating.
pub fn is_many(prop: EntityId) -> bool {
    prop_def(prop).map(|p| p.many).unwrap_or(false)
}
