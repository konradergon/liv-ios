// lotus — the ONE property-action set (P19e): the settings definitions table
// and the inspector's row menu are two doors onto these same writers. Every
// write is an ordinary cell on the DEFINITION entity — vault-wide by
// construction (carriers key on the definition id, never on the name).

import AppKit
import SwiftUI

enum PropertyActions {
    /// The kinds a definition may retype to (the parser's set minus the
    /// born-not-typed ones: file hashes and rich text are born, never set).
    static let retypeKinds = ["text", "number", "bool", "datetime", "select", "reference"]

    /// Rename, with the pre-commit carrier count in the prompt (the
    /// count-confirm seam — never a modal confirm).
    static func rename(model: BoxModel, def: PropertyRow, then: @escaping () -> Void = {}) {
        let carried = def.usage.map { "Carried by \($0) object\($0 == 1 ? "" : "s"). " } ?? ""
        Dialogs.shared.prompt(
            "Rename property",
            message: carried + "One cell on the definition — every carrier follows. ⌘⌥Z undoes.",
            initial: def.name, confirmLabel: "Rename"
        ) { name in
            guard let name = name?.trimmingCharacters(in: .whitespaces).lowercased(),
                !name.isEmpty, name != def.name
            else { return }
            model.set(def.id, property: "name", value: name) { _ in then() }
        }
    }

    /// Retype = the `value-kind` cell ONLY (the recorded delta): carrier
    /// cells are never rewritten — schema-on-read re-renders them.
    static func retype(model: BoxModel, def: PropertyRow, to kind: String) {
        guard kind != def.kind else { return }
        model.set(def.id, property: "value-kind", value: kind)
    }

    static func setIcon(model: BoxModel, def: PropertyRow) {
        Dialogs.shared.prompt(
            "Row icon", message: "An SF Symbol name — e.g. flag, tag, person.",
            initial: def.icon ?? "", confirmLabel: "Set"
        ) { name in
            guard let name = name?.trimmingCharacters(in: .whitespaces) else { return }
            model.set(def.id, property: "icon", value: name)
        }
    }

    /// Hide this property on a kind — a REFERENCE cell to the kind entity,
    /// mintable since 19c put kind ids on the wire.
    static func hideOnKind(model: BoxModel, def: PropertyRow, kind: KindRow) {
        model.set(def.id, property: "hide-on-kind", value: "#\(kind.id)")
    }

    static func toggleHideWhenEmpty(model: BoxModel, def: PropertyRow) {
        let now = def.hideWhenEmpty ?? false
        model.set(def.id, property: "hide-when-empty", value: now ? "false" : "true")
    }
}
