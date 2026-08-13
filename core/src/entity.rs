use serde::{Deserialize, Serialize};

use crate::value::{Id, Value};

/// One property instance on one entity.
/// A repeated property id is a multi-valued property.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Cell {
    pub property: Id,
    pub value: Value,
}

/// A stable identifier plus a set of cells. There is nothing else.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Entity {
    pub id: Id,
    /// Soft; references to trashed entities render as broken links.
    pub trashed: bool,
    pub cells: Vec<Cell>,
}

impl Entity {
    pub fn new(id: Id) -> Self {
        Entity {
            id,
            trashed: false,
            cells: Vec::new(),
        }
    }

    /// The first value of a property, if any.
    pub fn get(&self, property: Id) -> Option<&Value> {
        self.cells
            .iter()
            .find(|c| c.property == property)
            .map(|c| &c.value)
    }

    /// Every value of a property, in cell order.
    pub fn all(&self, property: Id) -> impl Iterator<Item = &Value> {
        self.cells
            .iter()
            .filter(move |c| c.property == property)
            .map(|c| &c.value)
    }

    pub fn has(&self, property: Id, value: &Value) -> bool {
        self.all(property).any(|v| v == value)
    }
}

/// Bootstrap: the ids the system needs to describe itself.
/// Property definitions are themselves entities; these are their ids.
pub mod props {
    use crate::value::Id;

    pub const NAME: Id = 1;
    /// Multi-valued reference.
    pub const TYPE: Id = 2;
    /// Written once at birth; modification time is derived from history.
    pub const CREATED: Id = 3;
    pub const CONTENT: Id = 4;
    /// On property definitions.
    pub const VALUE_KIND: Id = 5;
    /// On select property definitions.
    pub const OPTIONS: Id = 6;
    /// On types.
    pub const EXPECTED: Id = 7;
    /// On types.
    /// RESERVED, no longer seeded (T2, 2026-08-09): early boxes carry
    /// these three definitions, so the ids can never be reused.
    pub const DEFAULT_VIEW: Id = 8;
    /// On saved queries and views.
    pub const QUERY: Id = 9;
    /// On views.
    pub const RENDERER: Id = 10;
    /// On views: property -> visual dimension.
    pub const CONFIG: Id = 11;
    /// Import dedup.
    pub const EXTERNAL_ID: Id = 12;
    /// Backstage plumbing, filtered by default.
    pub const WORKING: Id = 13;
    /// Excluded from machine context.
    pub const PRIVATE: Id = 14;

    pub const FIRST_USER_ID: Id = 4096;
}
