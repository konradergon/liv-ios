// lotus — the command system (liv-ui-map.md §2.28).
// One registry, one keydown listener walking it in insertion order:
// earlier defines win conflicts. "Mod" is ⌘ on macOS. Unmodified keys
// are suppressed while focus is in a text view. A capture scope (facet
// modes, the Decide tray) suppresses the dispatcher for everything not
// on its allow-list, so bare I/X/O/1–9 never double-fire.

import AppKit
import SwiftUI

// MARK: hotkeys (§2.28.1)

struct Hotkey {
    struct Modifiers: OptionSet {
        let rawValue: Int
        static let mod = Modifiers(rawValue: 1 << 0)  // ⌘ on macOS
        static let shift = Modifiers(rawValue: 1 << 1)
        static let alt = Modifiers(rawValue: 1 << 2)  // ⌥
        static let ctrl = Modifiers(rawValue: 1 << 3)
    }

    let modifiers: Modifiers
    /// A single letter/digit (case-insensitive), or a named key
    /// ("ArrowLeft", "F2", ".", "`").
    let key: String

    /// Matching: all declared modifiers pressed AND no extras. Digits
    /// match by key code (layout-safe); letters case-insensitively.
    func matches(_ event: NSEvent) -> Bool {
        var required = NSEvent.ModifierFlags()
        if modifiers.contains(.mod) { required.insert(.command) }
        if modifiers.contains(.shift) { required.insert(.shift) }
        if modifiers.contains(.alt) { required.insert(.option) }
        if modifiers.contains(.ctrl) { required.insert(.control) }
        let pressed = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard pressed == required else { return false }

        switch key {
        case "ArrowLeft": return event.keyCode == 123
        case "ArrowRight": return event.keyCode == 124
        case "ArrowDown": return event.keyCode == 125
        case "ArrowUp": return event.keyCode == 126
        case "Escape": return event.keyCode == 53
        case "Return": return event.keyCode == 36
        case "Tab": return event.keyCode == 48
        // Function keys type private-use glyphs, so they match by code.
        case "F2": return event.keyCode == 120
        // Digits match by physical key code (layout-safe): on a shifted-
        // number-row layout (AZERTY) the unmodified top-row key yields a
        // glyph, not the digit, so charactersIgnoringModifiers would never
        // match — the inspector's digit-jump grammar (bp1) depends on this.
        case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
            let digitCodes: [UInt16] = [29, 18, 19, 20, 21, 23, 22, 26, 28, 25]
            return event.keyCode == digitCodes[Int(key)!]
        // Punctuation matches by key code: charactersIgnoringModifiers
        // applies Shift, so ⌘⇧` would read "~" and never match a
        // character comparison. (Same philosophy as Liv matching digits
        // by e.code.)
        case "`": return event.keyCode == 50
        case "'": return event.keyCode == 39
        case ",": return event.keyCode == 43
        case ".": return event.keyCode == 47
        case "[": return event.keyCode == 33
        case "]": return event.keyCode == 30
        default:
            // With ⌥ held, charactersIgnoringModifiers still yields the
            // glyph the chord names on macOS.
            let typed = event.charactersIgnoringModifiers?.lowercased() ?? ""
            return typed == key.lowercased()
        }
    }

    /// Mac label: a glyph run, no separators — ⌘⇧B.
    var label: String {
        var out = ""
        if modifiers.contains(.ctrl) { out += "⌃" }
        if modifiers.contains(.alt) { out += "⌥" }
        if modifiers.contains(.shift) { out += "⇧" }
        if modifiers.contains(.mod) { out += "⌘" }
        switch key {
        case "ArrowLeft": out += "←"
        case "ArrowRight": out += "→"
        case "ArrowUp": out += "↑"
        case "ArrowDown": out += "↓"
        case "Return": out += "⏎"
        case "Escape": out += "⎋"
        case "Tab": out += "⇥"
        case " ": out += "Space"
        case "F2": out += "F2"
        default: out += key.uppercased()
        }
        return out
    }
}

// MARK: the registry (§2.28.2)

enum CommandScope {
    case global
    case composer
    case editor
}

struct CommandDef {
    let id: String
    let label: String
    let scope: CommandScope
    let category: String
    let binding: Hotkey?
    /// A disabled command never consumes its key — Escape, for one,
    /// only bites when focus mode is on and no overlay is above it.
    var enabled: () -> Bool = { true }
    let action: () -> Void
}

final class CommandRegistry {
    static let shared = CommandRegistry()

    /// Insertion order is precedence: earlier defines win conflicts.
    private var order: [String] = []
    private var commands: [String: CommandDef] = [:]
    private var monitor: Any?

    /// The capture-scope stack: while non-empty, only allow-listed ids
    /// dispatch (§2.28.2 keyboard scopes).
    private var captureScopes: [Set<String>] = []

    /// True when a keyboard-owning overlay is up (the workspace
    /// switcher, a launcher). Like a dialog, it swallows the command
    /// map so nothing fires behind the scrim.
    var overlayActive: () -> Bool = { false }

    /// Chord OVERRIDES (P19g): app.keymap.v1, this Mac only — never the box.
    /// Load-time validation is total: ANY malformed entry discards the whole
    /// map (defaults win + one log line) — a corrupted pref can never brick
    /// keyboard access.
    private var overrides: [String: Hotkey] = [:]
    /// Commands whose chord was STOLEN (P19 review): the loser must really
    /// let go, or the winner fires only when insertion order favors it.
    /// Persisted in the same map as {mods: 0, key: ""}.
    private var unbound: Set<String> = []

    /// The chords no override may touch: settings and undo must always
    /// answer (Esc is not a command; menus are AppKit's).
    static let unstealable: Set<String> = ["app:open-settings", "lotus:undo-last-change"]
    /// Their fixed chords, known before any command registers — load-time
    /// validation rejects overrides that would shadow them (P19 review).
    static let unstealableChords: [Hotkey] = [
        Hotkey(modifiers: [.mod], key: ","),
        Hotkey(modifiers: [.mod, .alt], key: "z"),
    ]
    /// Deliberate alias pairs in the stock map — same chord on purpose,
    /// disambiguated by enabled(): never a conflict to warn about.
    static let sanctionedAliases: [Set<String>] = [
        ["tab:new", "workspace:new-tab"],
        ["inspector:close", "app:exit-focus"],
    ]

    func register(_ command: CommandDef) {
        if commands[command.id] == nil {
            order.append(command.id)
        }
        commands[command.id] = command
    }

    func run(_ id: String) {
        commands[id]?.action()
    }

    func binding(for id: String) -> Hotkey? {
        commands[id]?.binding
    }

    /// The default with the override applied — what actually fires.
    func effectiveBinding(for id: String) -> Hotkey? {
        if unbound.contains(id) { return nil }
        return overrides[id] ?? commands[id]?.binding
    }

    func hasOverride(_ id: String) -> Bool {
        overrides[id] != nil || unbound.contains(id)
    }

    /// Every registered command, insertion order — the editor's table.
    var allCommands: [CommandDef] { order.compactMap { commands[$0] } }

    func setOverride(_ id: String, _ hotkey: Hotkey?) {
        guard !Self.unstealable.contains(id) else { return }
        unbound.remove(id)
        if let hotkey {
            overrides[id] = hotkey
        } else {
            overrides.removeValue(forKey: id)
        }
        persistOverrides()
    }

    /// Unbind a command outright — the steal flow's other half (P19
    /// review): the stolen-from chord must go silent, not linger to shadow.
    func setUnbound(_ id: String) {
        guard !Self.unstealable.contains(id) else { return }
        overrides.removeValue(forKey: id)
        unbound.insert(id)
        persistOverrides()
    }

    func resetOverrides() {
        overrides = [:]
        unbound = []
        UserDefaults.standard.removeObject(forKey: "app.keymap.v1")
    }

    private func persistOverrides() {
        var raw = overrides.mapValues { hotkey in
            ["mods": hotkey.modifiers.rawValue, "key": hotkey.key] as [String: Any]
        }
        for id in unbound {
            raw[id] = ["mods": 0, "key": ""]
        }
        UserDefaults.standard.set(raw, forKey: "app.keymap.v1")
    }

    func loadOverrides() {
        overrides = [:]
        unbound = []
        func discard() {
            // Total validation: one bad entry discards the whole map.
            NSLog("lotus: app.keymap.v1 malformed — booting on default shortcuts")
            overrides = [:]
            unbound = []
            UserDefaults.standard.removeObject(forKey: "app.keymap.v1")
        }
        guard let raw = UserDefaults.standard.dictionary(forKey: "app.keymap.v1") else { return }
        var parsed: [String: Hotkey] = [:]
        var parsedUnbound: Set<String> = []
        for (id, value) in raw {
            guard let dict = value as? [String: Any],
                let mods = dict["mods"] as? Int,
                let key = dict["key"] as? String,
                !Self.unstealable.contains(id)
            else {
                return discard()
            }
            if key.isEmpty {
                // The unbound sentinel — a stolen-from command let go.
                guard mods == 0 else { return discard() }
                parsedUnbound.insert(id)
                continue
            }
            let hotkey = Hotkey(modifiers: Hotkey.Modifiers(rawValue: mods), key: key)
            // A persisted entry must never shadow the brick-proof pair
            // either (P19 review) — the recorder refuses these live, so a
            // matching entry can only be hand-edited or corrupt.
            if Self.unstealableChords.contains(where: {
                $0.modifiers == hotkey.modifiers && $0.key == hotkey.key.lowercased()
            }) {
                return discard()
            }
            parsed[id] = hotkey
        }
        overrides = parsed
        unbound = parsedUnbound
    }

    /// The pure conflict function (P19g): every effective chord that two
    /// commands share.
    func conflicts() -> [String: [String]] {
        var byChord: [String: [String]] = [:]
        for id in order {
            guard let binding = effectiveBinding(for: id) else { continue }
            let chord = "\(binding.modifiers.rawValue)+\(binding.key.lowercased())"
            byChord[chord, default: []].append(id)
        }
        return byChord.filter { entry in
            guard entry.value.count > 1 else { return false }
            // A group entirely inside one sanctioned alias set is design,
            // not conflict — the stock map must not boot with a warnline.
            let members = Set(entry.value)
            return !Self.sanctionedAliases.contains { members.isSubset(of: $0) }
        }
    }

    func pushCaptureScope(allowing ids: Set<String>) {
        captureScopes.append(ids)
    }

    func popCaptureScope() {
        _ = captureScopes.popLast()
    }

    /// The one keydown listener. Returns nil (consumes) when a command
    /// fires. Editor-scope commands never dispatch from here — the
    /// editor's own key handling owns them.
    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if event.isARepeat,
                let arrows = event.charactersIgnoringModifiers,
                arrows.first == "\u{F702}" || arrows.first == "\u{F703}"
            {
                return event  // the e.repeat guard on Alt+Arrow history
            }
            let textFocused =
                NSApp.keyWindow?.firstResponder is NSTextView
                || NSApp.keyWindow?.firstResponder is NSText
            let unmodified = event.modifierFlags
                .intersection([.command, .option, .control])
                .isEmpty
            // A dialog above everything owns the keyboard: Escape
            // cancels, Return confirms (the prompt's own field keeps its
            // Return), and no command underneath may fire.
            if Dialogs.shared.current != nil {
                if event.keyCode == 53 {
                    Dialogs.shared.cancelCurrent()
                    return nil
                }
                if event.keyCode == 36 && !textFocused {
                    Dialogs.shared.confirmCurrent()
                    return nil
                }
                return event
            }
            // A modal overlay (the workspace switcher) owns the keyboard:
            // its own field and monitor handle typing / arrows / Enter /
            // Escape; no global command may fire behind it.
            if self.overlayActive() {
                // The brick-proof pair still answers over any overlay (P19
                // review: rename toasts in Settings advertise the undo chord
                // — it must work right there). Both are modifier chords no
                // overlay text field could be typing.
                for id in Self.unstealable {
                    guard let command = self.commands[id],
                        let binding = self.effectiveBinding(for: id),
                        binding.matches(event),
                        command.enabled()
                    else { continue }
                    command.action()
                    return nil
                }
                return event
            }
            for id in self.order {
                guard let command = self.commands[id],
                    command.scope != .editor,
                    let binding = self.effectiveBinding(for: id),
                    binding.matches(event),
                    command.enabled()
                else { continue }
                if let scope = self.captureScopes.last, !scope.contains(id) {
                    return event
                }
                if textFocused && unmodified {
                    return event  // bare keys stay typable
                }
                command.action()
                return nil
            }
            return event
        }
    }
}
