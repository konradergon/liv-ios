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
            for id in self.order {
                guard let command = self.commands[id],
                    command.scope != .editor,
                    let binding = command.binding,
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
