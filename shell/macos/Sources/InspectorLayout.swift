// lotus — the V3 inspector's placement law (P11.5f, design §2.5 + §3.2).
// Pure: (kind, catalog, this entity's cells, resolved digit keys) → which
// rows render where. No SwiftUI, no model — the executed law check compiles
// this file against stub rows.

import Foundation

/// One renderable inspector row: a definition plus this entity's cells for
/// it (empty = the ghost/placeholder state) and its digit-map key.
struct InspectorRowSpec: Identifiable {
    let property: PropertyRow
    let cells: [CellRow]
    let key: String?
    var id: UInt64 { property.id }
    var isEmpty: Bool { cells.isEmpty || cells.allSatisfy { $0.value.isEmpty } }
}

enum InspectorLayout {
    /// Cells the header or the editor owns — never property rows. `type`
    /// LEFT this set with BP-1 (design §2.1): it is core row digit 2 now.
    /// `created` renders as a read-only system row in MORE, not from here.
    static let reserved: Set<String> = [
        "name", "content", "created", "bookmarked", "archived",
        "order", "builtin",
    ]

    /// The note/default core — also the universal base: a base property a
    /// kind's table omits FOLDS to MORE (visible even empty, keeping its
    /// digit) rather than hiding (§3.2: task keeps digits 1 and 3).
    static let noteBase = [
        "form", "type", "subjects", "project", "area", "people", "tier",
        "date", "status", "description",
    ]

    /// Per-kind core tables (§3.2) — candidates, not obligations: a name
    /// absent from the catalog simply doesn't render. Kinds not listed
    /// (note, project, list, "") take the note base.
    static let coreTables: [String: [String]] = [
        "task": ["type", "project", "area", "people", "tier", "status", "description"],
        "person": [
            "type", "role", "org", "email", "phone", "subjects", "area",
            "date", "status", "description",
        ],
        "event": ["type", "subjects", "area", "people", "tier", "date", "status", "description"],
        "file": [
            "type", "subjects", "area", "date", "valid-until", "tier",
            "status", "sources", "description",
        ],
    ]

    /// The task-fields group (badge 16) — its own section on task kind,
    /// ordinary properties everywhere else.
    static let taskFieldNames = ["due", "priority", "recurrence"]

    struct Placement {
        var core: [InspectorRowSpec] = []
        var taskFields: [InspectorRowSpec] = []
        var more: [InspectorRowSpec] = []
    }

    /// The resting-state law (§2.5):
    ///   1. core rows always render, ghosts included; a hide-on-kind cell
    ///      naming this kind removes the row from this kind entirely;
    ///      a core-on-kind cell promotes a property into core (appended,
    ///      alphabetical);
    ///   2. base-core properties the kind's table omits fold to MORE,
    ///      visible even empty, digits kept;
    ///   3. other non-core rows: valued → MORE alphabetical; empty →
    ///      hidden unless hide-when-empty was turned off on the definition
    ///      (nil defaults ON — the short resting panel).
    static func place(
        kind: String, catalog: [PropertyRow], cells: [CellRow], keys: [String: String]
    ) -> Placement {
        let coreNames = coreTables[kind] ?? noteBase
        let isTask = kind == "task"
        let cellsByProperty = Dictionary(grouping: cells, by: { $0.propertyId })

        func spec(_ prop: PropertyRow) -> InspectorRowSpec {
            InspectorRowSpec(
                property: prop, cells: cellsByProperty[prop.id] ?? [],
                key: keys[prop.name])
        }
        func hidden(_ prop: PropertyRow) -> Bool {
            reserved.contains(prop.name) || (prop.hideOnKinds?.contains(kind) ?? false)
        }
        func isTaskField(_ prop: PropertyRow) -> Bool {
            isTask && taskFieldNames.contains(prop.name)
        }

        var placement = Placement()
        var placed: Set<UInt64> = []

        if isTask {
            for name in taskFieldNames {
                guard let prop = catalog.first(where: { $0.name == name }), !hidden(prop)
                else { continue }
                placement.taskFields.append(spec(prop))
                placed.insert(prop.id)
            }
        }
        for name in coreNames {
            guard let prop = catalog.first(where: { $0.name == name }),
                !hidden(prop), !placed.contains(prop.id), !isTaskField(prop)
            else { continue }
            placement.core.append(spec(prop))
            placed.insert(prop.id)
        }
        // Cell-promoted core (core-on-kind), appended alphabetically.
        for prop in catalog.sorted(by: { $0.name < $1.name })
        where (prop.coreOnKinds?.contains(kind) ?? false)
            && !placed.contains(prop.id) && !hidden(prop) && !isTaskField(prop)
        {
            placement.core.append(spec(prop))
            placed.insert(prop.id)
        }
        // Folded base core → MORE, even empty, base order — EXCEPT an
        // empty datetime: a kind whose table omits `date` substitutes its
        // own dated field (task's due), and the blueprint's task MORE
        // shows no empty date row. A valued one still folds (§2.2: every
        // datetime role property with a cell renders its own row).
        for name in noteBase where !coreNames.contains(name) {
            guard let prop = catalog.first(where: { $0.name == name }),
                !hidden(prop), !placed.contains(prop.id), !isTaskField(prop)
            else { continue }
            let row = spec(prop)
            if prop.kind == "datetime" && row.isEmpty { continue }
            placement.more.append(row)
            placed.insert(prop.id)
        }
        // Everything else: valued → MORE; empty only if hide-when-empty
        // was switched off. Alphabetical, after the folded block.
        for prop in catalog.sorted(by: { $0.name < $1.name })
        where !placed.contains(prop.id) && !hidden(prop) && !isTaskField(prop) {
            let row = spec(prop)
            if !row.isEmpty || !prop.hidesWhenEmpty {
                placement.more.append(row)
                placed.insert(prop.id)
            }
        }
        return placement
    }
}
