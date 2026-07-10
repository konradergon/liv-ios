// lotus — THE one global shortcut map (P11.5e, ruling R2 / D21). Keyed by
// property NAME. A key means the same row on every kind — kind-tuning moves
// a row between core and MORE, never its key. The registry is a pure
// function of the catalog: no stored state, no migration. P19's Settings →
// Shortcuts editor will EDIT it by writing `digit-key` cells — the box is
// the override store, this file is the reader. Nothing in P11.5 writes
// digit-key.

import Foundation

/// Hint display for the kbd column — pure display, never behavior.
enum DigitHintVisibility: String {
    case hover, always, off

    static var current: DigitHintVisibility {
        DigitHintVisibility(
            rawValue: UserDefaults.standard.string(forKey: "app.inspector.hints.v1") ?? "hover"
        ) ?? .hover
    }
}

enum DigitMap {
    /// The canonical defaults, frozen with the P11.5 design (bp1 badge 8,
    /// read off all six kind tabs). Keys are property NAMES; values are the
    /// key labels the kbd column renders and the capture scope matches.
    /// Task fields take LETTERS — digits never re-bind per kind (R2: one
    /// map). `recurrence` is the property behind the "repeat" row.
    static let defaults: [String: String] = [
        "form": "1",
        "type": "2",
        "subjects": "3",
        "project": "4",
        "area": "5",
        "people": "6",
        "tier": "7",
        "date": "8",
        "status": "9",
        "description": "0",
        "due": "D",
        "priority": "P",
        "recurrence": "R",
    ]

    /// Letters the map RESERVES for non-property commands so no future
    /// default collides with them: N add-property, M MORE, H row menu,
    /// and the dormant view-config block L/F/G/S/W (registered so the map
    /// never re-learns them when views become objects).
    static let reserved: Set<String> = ["N", "M", "H", "L", "F", "G", "S", "W"]

    /// The resolution: property name → key label, recomputed per snapshot.
    /// The layering law (design §3.1):
    ///   1. start from the defaults;
    ///   2. a `digit-key` CELL on a definition WINS its key — the displaced
    ///      default's property goes blank ('·' in the kbd column);
    ///   3. two cells claiming one key → the LOWEST definition id wins, the
    ///      loser renders blank. Deterministic; no key ever double-fires.
    /// Reserved letters are never assignable — a cell claiming one is
    /// ignored (renders blank; P19's editor is where that gets resolved).
    static func resolve(_ catalog: [PropertyRow]) -> [String: String] {
        var byKey: [String: String] = [:]  // key label -> property name
        for (name, key) in defaults {
            byKey[key] = name
        }
        // Cells win over defaults; among cells, the lowest definition id.
        let overrides = catalog
            .filter { $0.digitKey != nil }
            .sorted { $0.id < $1.id }
        var cellClaimed: Set<String> = []
        for row in overrides {
            guard let key = row.digitKey?.uppercased(), !key.isEmpty else { continue }
            guard !reserved.contains(key) else { continue }
            guard !cellClaimed.contains(key) else { continue }  // lowest id won
            cellClaimed.insert(key)
            // Displace whatever held the key (a default, silently — its
            // property goes blank).
            byKey[key] = row.name
        }
        var out: [String: String] = [:]
        for (key, name) in byKey {
            out[name] = key
        }
        return out
    }

    /// The key for one property under a resolved map — nil renders the
    /// dashed '·' blank (reachable by ↑↓ only).
    static func key(for property: String, in resolved: [String: String]) -> String? {
        resolved[property]
    }
}
