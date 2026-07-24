// liv — the ONE property-action set (P19e): the settings definitions table
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
    /// count-confirm seam — never a modal confirm). A collision re-prompts:
    /// two definitions of one name would corrupt every name-keyed write
    /// (`set` resolves properties by name — the P19 review).
    static func rename(model: BoxModel, def: PropertyRow, then: @escaping () -> Void = {}) {
        let carried = def.usage.map { "Carried by \($0) object\($0 == 1 ? "" : "s"). " } ?? ""
        promptRename(
            model: model, def: def,
            message: carried + "One cell on the definition — every carrier follows. ⌘⌥Z undoes.",
            then: then)
    }

    private static func promptRename(
        model: BoxModel, def: PropertyRow, message: String, then: @escaping () -> Void
    ) {
        Dialogs.shared.prompt(
            "Rename property", message: message,
            initial: def.name, confirmLabel: "Rename"
        ) { name in
            guard let name = name?.trimmingCharacters(in: .whitespaces).lowercased(),
                !name.isEmpty, name != def.name
            else { return }
            if model.properties().contains(where: { $0.id != def.id && $0.name == name }) {
                promptRename(
                    model: model, def: def,
                    message: "A property named \(name) already exists — one name, one definition.",
                    then: then)
                return
            }
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

    /// Hide this property on a kind — TOGGLED per kind through the kind-flag
    /// door (`set` replaces every cell of a property, so writing a second
    /// kind through it silently un-hid the first — the P19 review).
    static func hideOnKind(model: BoxModel, def: PropertyRow, kind: KindRow) {
        let on = !(def.hideOnKinds ?? []).contains(kind.name)
        model.kindFlag(def: def.id, property: "hide-on-kind", kind: kind.id, on: on)
    }

    /// The core star (19e): pin a property as core on a kind — always shown
    /// there, empty or not. The same additive kind-flag door.
    static func toggleCoreOnKind(model: BoxModel, def: PropertyRow, kind: KindRow) {
        let on = !(def.coreOnKinds ?? []).contains(kind.name)
        model.kindFlag(def: def.id, property: "core-on-kind", kind: kind.id, on: on)
    }

    static func toggleHideWhenEmpty(model: BoxModel, def: PropertyRow) {
        // nil defaults ON (hidesWhenEmpty) — toggling from unset must WRITE
        // false, not restate true (the P19 review's silent first click).
        let now = def.hidesWhenEmpty
        model.set(def.id, property: "hide-when-empty", value: now ? "false" : "true")
    }
}
