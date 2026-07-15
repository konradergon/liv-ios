// lotus — Settings (P19a, bp13): the FOURTH overlay carve-out. A centered
// card over the scrim in the search-palette anatomy — header (search focused
// on open) · six-group nav · panel · the shared footbar. Changes apply
// instantly; NO SAVE BUTTON EXISTS. Every entry answers to the one search
// grammar; live property definitions fold into the pool at query time, so
// the data that IS objects really is searched as objects. Settings are never
// entities themselves (transient UI law) — a static shell table describes
// them.

import AppKit
import Carbon.HIToolbox
import Security
import SwiftUI

// MARK: - the groups + entries

enum SettingsGroup: String, CaseIterable {
    case appearance, vocabulary, shortcuts, capture, assist, startup

    var label: String {
        switch self {
        case .appearance: return "Appearance"
        case .vocabulary: return "Properties & Vocabulary"
        case .shortcuts: return "Shortcuts"
        case .capture: return "Capture & Store"
        case .assist: return "Assist"
        case .startup: return "Startup"
        }
    }
}

/// One searchable entry — a static description of a knob (the knob itself
/// lives in its panel; the entry is how the grammar finds it).
struct SettingEntry: Identifiable {
    let id: String
    let label: String
    let group: SettingsGroup
    /// vault = a cell in the box (travels); app = this Mac's pref.
    let vaultScoped: Bool
    let kind: String
    let keywords: String

    var scopeTag: String { vaultScoped ? "vault" : "app" }
}

let settingsEntries: [SettingEntry] = [
    SettingEntry(
        id: "appearance.theme", label: "Appearance", group: .appearance,
        vaultScoped: false, kind: "segmented", keywords: "light dark system theme"),
    SettingEntry(
        id: "shortcuts.hints", label: "Digit hints in the inspector", group: .shortcuts,
        vaultScoped: false, kind: "toggle", keywords: "digit keys hints inspector"),
    SettingEntry(
        id: "shortcuts.map", label: "Shortcut map", group: .shortcuts,
        vaultScoped: false, kind: "table", keywords: "keys bindings chords digit rebind"),
    SettingEntry(
        id: "capture.hotkey", label: "Capture hotkey", group: .capture,
        vaultScoped: false, kind: "key", keywords: "capture global hotkey jot"),
    SettingEntry(
        id: "capture.store", label: "Store location", group: .capture,
        vaultScoped: false, kind: "path", keywords: "box file location log reveal export"),
    SettingEntry(
        id: "vocabulary.properties", label: "Property definitions", group: .vocabulary,
        vaultScoped: true, kind: "table", keywords: "properties rename retype schema definitions"),
    SettingEntry(
        id: "vocabulary.shelves", label: "Vocabulary shelves", group: .vocabulary,
        vaultScoped: true, kind: "shelves", keywords: "values options seeds status priority rename"),
    SettingEntry(
        id: "assist.automation", label: "Automation (the clerk)", group: .assist,
        vaultScoped: true, kind: "toggle", keywords: "assist clerk proposals ai automation"),
    SettingEntry(
        id: "assist.byok", label: "Model key (BYOK)", group: .assist,
        vaultScoped: false, kind: "keychain", keywords: "api key model keychain byok"),
    SettingEntry(
        id: "startup.mode", label: "On launch", group: .startup,
        vaultScoped: false, kind: "radio", keywords: "startup launch open today continue workspace"),
]

// MARK: - the overlay

struct SettingsOverlay: View {
    @ObservedObject var model: BoxModel
    let dismiss: () -> Void
    let searchVault: (String) -> Void

    @AppStorage("app.settings.lastPanel.v1") private var lastPanelRaw =
        SettingsGroup.appearance.rawValue
    @State private var query = ""
    @State private var highlighted = 0
    /// Tri-state group facets while searching (digits 1–6): nil = off.
    @State private var facetInclude: Set<SettingsGroup> = []
    @State private var facetExclude: Set<SettingsGroup> = []
    /// The row to flash after a ⏎ jump (~1.6s accent-soft).
    @State private var flashed: String?
    @FocusState private var searchFocused: Bool

    private var panel: SettingsGroup {
        SettingsGroup(rawValue: lastPanelRaw) ?? .appearance
    }

    /// One result: a static entry, or a LIVE property definition.
    struct Hit: Identifiable {
        let id: String
        let label: String
        let group: SettingsGroup
        let scopeTag: String
        let kind: String
        let current: String
    }

    private var hits: [Hit] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return [] }
        var out: [Hit] = []
        for entry in settingsEntries
        where entry.label.lowercased().contains(needle)
            || entry.keywords.contains(needle)
        {
            out.append(
                Hit(
                    id: entry.id, label: entry.label, group: entry.group,
                    scopeTag: entry.scopeTag, kind: entry.kind, current: ""))
        }
        // The live pool: property definitions ARE objects — searched as such.
        for property in model.snap?.properties ?? []
        where property.name.lowercased().contains(needle) {
            out.append(
                Hit(
                    id: "prop.\(property.id)", label: property.name,
                    group: .vocabulary, scopeTag: "vault",
                    kind: property.kind, current: ""))
        }
        return out.filter { hit in
            if facetExclude.contains(hit.group) { return false }
            if !facetInclude.isEmpty { return facetInclude.contains(hit.group) }
            return true
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
            VStack(spacing: 0) {
                header
                Divider()
                HStack(spacing: 0) {
                    nav
                    panelBody
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                Divider()
                footbar
            }
            .frame(maxWidth: 880, maxHeight: 520)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
            .padding(30)
        }
        .onAppear { searchFocused = true }
    }

    // MARK: header — the search IS the front door

    private var header: some View {
        HStack(spacing: 10) {
            Text("⚙ Settings").font(.system(size: 13, weight: .bold))
            ZStack(alignment: .topLeading) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 10))
                        .foregroundColor(Theme.mutedFg)
                    TextField("Search settings…", text: $query)
                        .textFieldStyle(.plain).font(.system(size: 12))
                        .focused($searchFocused)
                        .onSubmit { jump() }
                        .onExitCommand {
                            // Esc layers: the dropdown clears first, then the
                            // overlay closes.
                            if query.isEmpty { dismiss() } else { query = "" }
                        }
                        .onKeyPress(.downArrow) {
                            highlighted = min(highlighted + 1, max(0, hits.count - 1))
                            return .handled
                        }
                        .onKeyPress(.upArrow) {
                            highlighted = max(highlighted - 1, 0)
                            return .handled
                        }
                        .onKeyPress { press in
                            // Digits 1–6 cycle group facets include→exclude→off.
                            guard !query.isEmpty,
                                let digit = Int(press.characters),
                                (1...SettingsGroup.allCases.count).contains(digit)
                            else { return .ignored }
                            let group = SettingsGroup.allCases[digit - 1]
                            if facetInclude.contains(group) {
                                facetInclude.remove(group)
                                facetExclude.insert(group)
                            } else if facetExclude.contains(group) {
                                facetExclude.remove(group)
                            } else {
                                facetInclude.insert(group)
                            }
                            return .handled
                        }
                }
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Theme.accent.opacity(searchFocused ? 0.55 : 0.25)))
            }
            .frame(maxWidth: 330)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 11))
                    .foregroundColor(Theme.mutedFg).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .overlay(alignment: .topLeading) { dropdown.offset(x: 92, y: 38) }
        .zIndex(2)
    }

    @ViewBuilder
    private var dropdown: some View {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                if hits.isEmpty {
                    HStack(spacing: 6) {
                        Text("No settings match.").font(.system(size: 11.5))
                            .foregroundColor(Theme.mutedFg)
                        Text("⏎ search the vault instead")
                            .font(.system(size: 10.5)).foregroundColor(Theme.accent)
                    }
                    .padding(10)
                } else {
                    ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                        Button {
                            highlighted = index
                            jump()
                        } label: {
                            HStack(spacing: 8) {
                                Text(hit.label).font(.system(size: 12, weight: .semibold))
                                scopeChip(hit.scopeTag)
                                Text(hit.group.label).font(.system(size: 9.5))
                                    .foregroundColor(Theme.mutedFg)
                                Text(hit.kind).font(.system(size: 9.5))
                                    .foregroundColor(Theme.mutedFg.opacity(0.7))
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 11).padding(.vertical, 5)
                            .background(
                                index == highlighted
                                    ? Theme.accent.opacity(0.12) : .clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Text("1–6 filter by group · ⏎ jump")
                        .font(.system(size: 9)).foregroundColor(Theme.mutedFg)
                        .padding(.horizontal, 11).padding(.vertical, 4)
                }
            }
            .frame(width: 400)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        }
    }

    private func scopeChip(_ tag: String) -> some View {
        Text(tag)
            .font(.system(size: 8.5)).kerning(0.3)
            .padding(.horizontal, 5)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(
                        tag == "vault"
                            ? Theme.accent.opacity(0.5) : Theme.border))
            .foregroundColor(tag == "vault" ? Theme.accent : Theme.mutedFg)
    }

    private func jump() {
        let ordered = hits
        guard ordered.indices.contains(highlighted) else {
            // 0 results: hand the query to the vault's one engine.
            if !query.isEmpty {
                let handoff = query
                dismiss()
                searchVault(handoff)
            }
            return
        }
        let hit = ordered[highlighted]
        lastPanelRaw = hit.group.rawValue
        flashed = hit.id
        query = ""
        facetInclude = []
        facetExclude = []
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if flashed == hit.id { flashed = nil }
        }
    }

    // MARK: nav + panels (19a: real headers, stub bodies)

    private var nav: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsGroup.allCases, id: \.rawValue) { group in
                Button {
                    lastPanelRaw = group.rawValue
                } label: {
                    Text(group.label)
                        .font(.system(size: 12, weight: panel == group ? .semibold : .regular))
                        .foregroundColor(panel == group ? Theme.accent : Theme.mutedFg)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(panel == group ? Theme.accent.opacity(0.13) : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: 186)
        .overlay(Divider(), alignment: .trailing)
    }

    @ViewBuilder
    private var panelBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(panel.label.uppercased())
                .font(.system(size: 10, weight: .bold)).kerning(0.6)
                .foregroundColor(Theme.mutedFg)
            switch panel {
            case .appearance:
                AppearancePanel()
            case .vocabulary:
                VocabularyPanel(model: model)
            case .shortcuts:
                ShortcutsPanel(model: model)
            case .capture:
                SettingsCapturePanel(model: model, dismiss: dismiss)
            case .assist:
                AssistPanel(model: model)
            case .startup:
                StartupPanel(model: model)
            }
            if let flashed, flashed.hasPrefix("prop.") || hitGroup(flashed) == panel {
                Text("→ \(flashLabel(flashed))")
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 7).fill(Theme.accent.opacity(0.13)))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private func hitGroup(_ id: String) -> SettingsGroup? {
        settingsEntries.first { $0.id == id }?.group
    }

    private func flashLabel(_ id: String) -> String {
        if id.hasPrefix("prop."),
            let pid = UInt64(id.dropFirst(5)),
            let property = (model.snap?.properties ?? []).first(where: { $0.id == pid })
        {
            return property.name
        }
        return settingsEntries.first { $0.id == id }?.label ?? id
    }

    private func stub(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5)).foregroundColor(Theme.mutedFg)
            .frame(maxWidth: 460, alignment: .leading)
    }

    private var footbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) { Text("⌘,").keycap(); Text("open").quiet() }
            HStack(spacing: 3) { Text("Esc").keycap(); Text("close").quiet() }
            HStack(spacing: 3) { Text("↑↓").keycap(); Text("pick").quiet() }
            HStack(spacing: 3) { Text("⏎").keycap(); Text("jump").quiet() }
            Spacer()
            Text("changes apply instantly — there is no Save button")
                .font(.system(size: 10)).foregroundColor(Theme.mutedFg)
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
    }
}

extension Text {
    fileprivate func keycap() -> some View {
        self.font(.system(size: 9, design: .monospaced))
            .padding(.horizontal, 4)
            .overlay(RoundedRectangle(cornerRadius: 3.5).strokeBorder(Theme.border))
            .foregroundColor(Theme.mutedFg)
    }
    fileprivate func quiet() -> some View {
        self.font(.system(size: 10)).foregroundColor(Theme.mutedFg)
    }
}

// MARK: - the settings row kit (P19d)

/// One settings row: label + scope tag on the left, the control on the right.
/// Every control applies INSTANTLY per its scope — no Save exists.
struct SettingRow<Control: View>: View {
    let label: String
    let scope: String
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.system(size: 12))
            }
            .frame(width: 170, alignment: .leading)
            Text(scope)
                .font(.system(size: 8.5)).kerning(0.3)
                .padding(.horizontal, 5)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(scope == "vault" ? Theme.accent.opacity(0.5) : Theme.border))
                .foregroundColor(scope == "vault" ? Theme.accent : Theme.mutedFg)
            control()
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }
}

/// A LOCKED convention row (bp13 a26's own move): the story kept, no control.
struct LockedRow: View {
    let label: String
    let caption: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label).font(.system(size: 12)).frame(width: 170, alignment: .leading)
            Text("convention — not configurable")
                .font(.system(size: 9)).kerning(0.2)
                .padding(.horizontal, 5)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border))
                .foregroundColor(Theme.mutedFg)
            Text(caption).font(.system(size: 10.5)).foregroundColor(Theme.mutedFg)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }
}

// MARK: - Appearance (P19d)

struct AppearancePanel: View {
    @AppStorage("app.appearance") private var appearance = "system"

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SettingRow(label: "Appearance", scope: "app") {
                Picker("", selection: $appearance) {
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                    Text("System").tag("system")
                }
                .pickerStyle(.segmented).fixedSize().controlSize(.small)
                .onChange(of: appearance) {
                    switch appearance {
                    case "light": NSApp.appearance = NSAppearance(named: .aqua)
                    case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
                    default: NSApp.appearance = nil  // follow the system
                    }
                }
            }
            LockedRow(
                label: "Accent",
                caption: "Lake green means selection and today; amber means AI. The palette is the product.")
            Text("Reading mode and glyph strength are deferred — display-only knobs land when a surface earns them.")
                .font(.system(size: 10)).foregroundColor(Theme.mutedFg.opacity(0.8))
                .padding(.top, 6)
        }
    }
}

// MARK: - Startup (P19d)

struct StartupPanel: View {
    @ObservedObject var model: BoxModel
    @AppStorage("app.startup.v1") private var mode = "continue"
    @AppStorage("app.startup.workspace.v1") private var fixedWorkspace = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SettingRow(label: "On launch", scope: "app") {
                Picker("", selection: $mode) {
                    Text("Continue where I left off").tag("continue")
                    Text("A fixed workspace").tag("workspace")
                    Text("Today's note").tag("today")
                }
                .pickerStyle(.radioGroup).controlSize(.small)
            }
            if mode == "workspace" {
                SettingRow(label: "Workspace", scope: "app") {
                    Menu {
                        Button("Home") { fixedWorkspace = 0 }
                        ForEach(model.snap?.workspaces ?? []) { workspace in
                            if !workspace.archived {
                                Button(workspace.name) { fixedWorkspace = Int(workspace.id) }
                            }
                        }
                    } label: {
                        Text(workspaceName).font(.system(size: 11.5)).foregroundColor(Theme.accent)
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                }
            }
            Text("Honored at the next launch — nothing moves under you now.")
                .font(.system(size: 10)).foregroundColor(Theme.mutedFg.opacity(0.8))
                .padding(.top, 6)
        }
    }

    private var workspaceName: String {
        guard fixedWorkspace != 0,
            let row = (model.snap?.workspaces ?? []).first(where: { $0.id == UInt64(fixedWorkspace) })
        else { return "Home" }
        return row.name
    }
}

// MARK: - Capture & Store (P19d)

struct SettingsCapturePanel: View {
    @ObservedObject var model: BoxModel
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SettingRow(label: "Capture hotkey", scope: "app") {
                KeyRecorder()
            }
            LockedRow(
                label: "Capture behavior",
                caption: "One field, from anywhere; Esc closes; it asks nothing else.")
            SettingRow(label: "Store", scope: "app") {
                HStack(spacing: 8) {
                    Text(model.path)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(Theme.mutedFg)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 300, alignment: .leading)
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [URL(fileURLWithPath: model.path)])
                    }
                    .buttonStyle(.plain).font(.system(size: 11))
                    .foregroundColor(Theme.accent)
                    Button("Export…") {
                        dismiss()
                        NotificationCenter.default.post(name: .lotusOpenExport, object: nil)
                    }
                    .buttonStyle(.plain).font(.system(size: 11))
                    .foregroundColor(Theme.accent)
                }
            }
            Text("Your vault is this one file. Sync it with anything that syncs files — nothing phones home.")
                .font(.system(size: 10)).foregroundColor(Theme.mutedFg.opacity(0.8))
                .padding(.top, 6)
        }
    }
}

/// The KeyRecorder (P19d, proven here first — 19g's table reuses it): click,
/// press a chord, done. Esc cancels; a modifier is required; the capture
/// hotkey re-registers LIVE via .lotusRebindCapture.
struct KeyRecorder: View {
    @State private var recording = false
    @State private var monitor: Any?
    @State private var display = KeyRecorder.currentDisplay()

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? "press a chord… (Esc cancels)" : display)
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(recording ? Theme.accent : Theme.border))
                .foregroundColor(recording ? Theme.accent : Theme.foreground.opacity(0.85))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {  // Esc — cancel, unchanged
                stop()
                return nil
            }
            var carbon = 0
            if event.modifierFlags.contains(.control) { carbon |= controlKey }
            if event.modifierFlags.contains(.option) { carbon |= optionKey }
            if event.modifierFlags.contains(.command) { carbon |= cmdKey }
            if event.modifierFlags.contains(.shift) { carbon |= shiftKey }
            guard carbon != 0 else { return nil }  // a bare key can't be global
            let label = KeyRecorder.chord(
                flags: event.modifierFlags, key: event.charactersIgnoringModifiers ?? "?")
            UserDefaults.standard.set(
                [
                    "keyCode": Int(event.keyCode), "modifiers": carbon,
                    "display": label,
                ], forKey: "app.capture.hotkey.v1")
            NotificationCenter.default.post(
                name: Notification.Name("lotus.rebindCapture"), object: nil)
            display = label
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    static func currentDisplay() -> String {
        (UserDefaults.standard.dictionary(forKey: "app.capture.hotkey.v1")?["display"] as? String)
            ?? "⌃⌥Space"
    }

    static func chord(flags: NSEvent.ModifierFlags, key: String) -> String {
        var out = ""
        if flags.contains(.control) { out += "⌃" }
        if flags.contains(.option) { out += "⌥" }
        if flags.contains(.shift) { out += "⇧" }
        if flags.contains(.command) { out += "⌘" }
        let name = key == " " ? "Space" : key.uppercased()
        return out + name
    }
}

// MARK: - Properties & Vocabulary (P19e + P19f)

/// The definitions editor + the shelves — the inspector's MIRROR, not a
/// second editor: every write is the same cell the row menu writes.
struct VocabularyPanel: View {
    @ObservedObject var model: BoxModel
    /// Which select property's shelves are open.
    @State private var shelfProperty: UInt64?
    /// Which kind's status vocabulary is open.
    @State private var statusKind = "task"
    /// The count-confirm toast: "Renamed on N — ⌘⌥Z undoes."
    @State private var toast: String?

    private var properties: [PropertyRow] { model.snap?.properties ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                definitionsTable
                shelves
                statusTable
                if let toast {
                    Text(toast)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 7).fill(Theme.accent.opacity(0.13)))
                }
            }
            .padding(.bottom, 10)
        }
    }

    private func flash(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if toast == text { toast = nil }
        }
    }

    // MARK: 19e — the definitions table (spine first, customs last)

    private var definitionsTable: some View {
        let spine = properties.filter { $0.seeded ?? false }
        let custom = properties.filter { !($0.seeded ?? false) }
        return VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text("PROPERTY DEFINITIONS")
                    .font(.system(size: 9.5, weight: .bold)).kerning(0.5)
                    .foregroundColor(Theme.mutedFg)
                Spacer()
                Button("＋ property") {
                    Dialogs.shared.prompt(
                        "New property",
                        message: "Born as text — retype from its row. Schema-on-read: setting a value on any object offers it too.",
                        placeholder: "name", confirmLabel: "Create"
                    ) { name in
                        guard let name = name?.trimmingCharacters(in: .whitespaces).lowercased(),
                            !name.isEmpty
                        else { return }
                        model.addProperty(name: name, kind: "text")
                    }
                }
                .buttonStyle(.plain).font(.system(size: 10.5, weight: .medium))
                .foregroundColor(Theme.accent)
            }
            ForEach(spine) { def in definitionRow(def, custom: false) }
            if !custom.isEmpty {
                Text("CUSTOM")
                    .font(.system(size: 8.5, weight: .bold)).kerning(0.5)
                    .foregroundColor(Theme.mutedFg.opacity(0.8))
                    .padding(.top, 6)
                ForEach(custom) { def in definitionRow(def, custom: true) }
            }
        }
    }

    private func definitionRow(_ def: PropertyRow, custom: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: def.icon ?? "circle.dashed")
                .font(.system(size: 10)).foregroundColor(Theme.mutedFg)
                .frame(width: 16)
            Text(def.name).font(.system(size: 12))
            Text(def.kind).font(.system(size: 10)).foregroundColor(Theme.mutedFg)
            if custom {
                Text("custom · on \(def.carrierCount)")
                    .font(.system(size: 9)).foregroundColor(Theme.accent.opacity(0.8))
            } else if def.carrierCount > 0 {
                Text("on \(def.carrierCount)")
                    .font(.system(size: 9)).foregroundColor(Theme.mutedFg)
            }
            Spacer(minLength: 4)
            Menu {
                Button("Rename…") {
                    PropertyActions.rename(model: model, def: def) {
                        flash("Renamed — every carrier follows. ⌘⌥Z undoes.")
                    }
                }
                Menu("Change type") {
                    ForEach(PropertyActions.retypeKinds, id: \.self) { kind in
                        Button(kind + (kind == def.kind ? " ✓" : "")) {
                            PropertyActions.retype(model: model, def: def, to: kind)
                            flash("Retyped to \(kind) — cells untouched, re-read as \(kind).")
                        }
                    }
                }
                Button("Icon…") { PropertyActions.setIcon(model: model, def: def) }
                Menu("Hide on kind") {
                    ForEach(model.snap?.kinds ?? []) { kind in
                        Button(kind.name) {
                            PropertyActions.hideOnKind(model: model, def: def, kind: kind)
                        }
                    }
                }
                Button(def.hidesWhenEmpty ? "Show when empty" : "Hide when empty") {
                    PropertyActions.toggleHideWhenEmpty(model: model, def: def)
                }
                if custom {
                    Divider()
                    Button("Delete definition") {
                        model.trash(def.id)
                        flash("Deleted — carriers keep their cells (delete only un-indexes).")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10)).foregroundColor(Theme.mutedFg)
                    .frame(width: 20, height: 18).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.vertical, 1)
    }

    // MARK: 19f — the shelves (vault · seeded · hidden)

    private var selectProperties: [PropertyRow] {
        properties.filter { $0.kind == "select" && $0.name != "status" }
    }

    @ViewBuilder
    private var shelves: some View {
        let selects = selectProperties
        if !selects.isEmpty {
            let chosen = selects.first { $0.id == shelfProperty } ?? selects[0]
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("VOCABULARY SHELVES")
                        .font(.system(size: 9.5, weight: .bold)).kerning(0.5)
                        .foregroundColor(Theme.mutedFg)
                    Picker("", selection: Binding(
                        get: { chosen.id },
                        set: { shelfProperty = $0 })
                    ) {
                        ForEach(selects) { property in
                            Text(property.name).tag(property.id)
                        }
                    }
                    .pickerStyle(.menu).fixedSize().controlSize(.small)
                    Spacer()
                    Button("＋ option") {
                        Dialogs.shared.prompt(
                            "New \(chosen.name) option", placeholder: "name",
                            confirmLabel: "Add"
                        ) { name in
                            guard let name = name?.trimmingCharacters(in: .whitespaces),
                                !name.isEmpty
                            else { return }
                            model.addOption(property: chosen.id, name: name)
                        }
                    }
                    .buttonStyle(.plain).font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(Theme.accent)
                }
                shelfRows(chosen)
            }
        }
    }

    @ViewBuilder
    private func shelfRows(_ property: PropertyRow) -> some View {
        let vault = property.options.filter { ($0.count ?? 0) > 0 && !$0.isHidden }
        let seeded = property.options.filter { ($0.seeded ?? false) && !$0.isHidden }
        let hidden = property.options.filter { $0.isHidden }
        VStack(alignment: .leading, spacing: 4) {
            if !vault.isEmpty {
                shelfLine("IN THE VAULT", vault, property: property, dashed: false)
            }
            if !seeded.isEmpty {
                shelfLine("SEEDED — unused, yours to keep or hide", seeded, property: property, dashed: true)
            }
            if !hidden.isEmpty {
                DisclosureGroup {
                    shelfChips(hidden, property: property, dashed: true, restore: true)
                } label: {
                    Text("HIDDEN · \(hidden.count)")
                        .font(.system(size: 8.5, weight: .bold)).kerning(0.4)
                        .foregroundColor(Theme.mutedFg.opacity(0.8))
                }
                .font(.system(size: 10))
            }
            if vault.isEmpty && seeded.isEmpty && hidden.isEmpty {
                Text("No options yet — ＋ option starts the vocabulary.")
                    .font(.system(size: 10.5)).foregroundColor(Theme.mutedFg)
            }
        }
    }

    private func shelfLine(
        _ label: String, _ options: [OptionRow], property: PropertyRow, dashed: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8.5, weight: .bold)).kerning(0.4)
                .foregroundColor(Theme.mutedFg.opacity(0.8))
            shelfChips(options, property: property, dashed: dashed, restore: false)
        }
    }

    private func shelfChips(
        _ options: [OptionRow], property: PropertyRow, dashed: Bool, restore: Bool
    ) -> some View {
        // A wrapping row of value chips in their true VALUE_HEX hue; seeded =
        // dashed + muted until first use (the seed skin).
        let columns = [GridItem(.adaptive(minimum: 110), spacing: 6)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 5) {
            ForEach(options) { option in
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(nsColor: Hues.valueHex(option.name)).opacity(dashed ? 0.45 : 1))
                        .frame(width: 8, height: 8)
                    Text(option.name)
                        .font(.system(size: 11))
                        .foregroundColor(dashed ? Theme.mutedFg : Theme.foreground.opacity(0.9))
                        .lineLimit(1)
                    if let count = option.count, count > 0 {
                        Text("\(count)").font(.system(size: 9).monospacedDigit())
                            .foregroundColor(Theme.mutedFg)
                    }
                }
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(
                            Theme.border,
                            style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 3] : [])))
                .contextMenu {
                    Button("Rename everywhere…") { renameOption(option, in: property) }
                    if restore {
                        Button("Restore") {
                            model.set(option.id, property: "hidden", value: "false")
                        }
                    } else {
                        Button("Hide") { hideOption(option) }
                    }
                }
            }
        }
    }

    private func renameOption(_ option: OptionRow, in property: PropertyRow) {
        let carried = option.count ?? 0
        Dialogs.shared.prompt(
            "Rename \(option.name)",
            message: "Carried by \(carried) object\(carried == 1 ? "" : "s") — one transaction; a collision merges. ⌘⌥Z undoes.",
            initial: option.name, confirmLabel: "Rename"
        ) { name in
            guard let name = name?.trimmingCharacters(in: .whitespaces),
                !name.isEmpty, name != option.name
            else { return }
            model.renameValue(property: property.name, old: option.name, new: name) { count in
                if count >= 0 {
                    flash("Renamed on \(count) object\(count == 1 ? "" : "s") — ⌘⌥Z undoes.")
                } else {
                    flash("The rename was refused.")
                }
            }
        }
    }

    private func hideOption(_ option: OptionRow) {
        // The hidden property may not exist yet — birth it through the same
        // add-property door, then set (schema-on-read).
        if (model.snap?.properties ?? []).first(where: { $0.name == "hidden" }) == nil {
            model.addProperty(name: "hidden", kind: "bool") { _ in
                model.set(option.id, property: "hidden", value: "true")
            }
        } else {
            model.set(option.id, property: "hidden", value: "true")
        }
    }

    // MARK: 19f — the per-kind status vocabulary

    private var statusTable: some View {
        let options = statusVocabulary(model, kind: statusKind)
        let kinds = ["task", "event", "note"]
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("STATUS VOCABULARY")
                    .font(.system(size: 9.5, weight: .bold)).kerning(0.5)
                    .foregroundColor(Theme.mutedFg)
                Picker("", selection: $statusKind) {
                    ForEach(kinds, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu).fixedSize().controlSize(.small)
                Spacer()
                Button("＋ column") {
                    Dialogs.shared.prompt(
                        "New \(statusKind) status", placeholder: "name", confirmLabel: "Add"
                    ) { name in
                        guard let name = name?.trimmingCharacters(in: .whitespaces),
                            !name.isEmpty
                        else { return }
                        model.addStatusOption(kind: statusKind, name: name)
                    }
                }
                .buttonStyle(.plain).font(.system(size: 10.5, weight: .medium))
                .foregroundColor(Theme.accent)
            }
            ForEach(options) { option in
                HStack(spacing: 8) {
                    StatusDot(option: option, statusName: option.name)
                    Text(option.name).font(.system(size: 12))
                    if let count = option.count, count > 0 {
                        Text("\(count)").font(.system(size: 9).monospacedDigit())
                            .foregroundColor(Theme.mutedFg)
                    }
                    if option.isTerminal {
                        Text("completes").font(.system(size: 8.5))
                            .foregroundColor(Theme.mutedFg)
                    }
                    Spacer(minLength: 4)
                    Menu {
                        Button("Rename everywhere…") {
                            renameStatus(option)
                        }
                        Menu("Recolor") {
                            ForEach([0, 45, 90, 145, 210, 260, 320], id: \.self) { hue in
                                Button("hue \(hue)°") {
                                    model.set(option.id, property: "hue", value: String(hue))
                                }
                            }
                        }
                        Button("Move up") { reorderStatus(option, in: options, delta: -1) }
                        Button("Move down") { reorderStatus(option, in: options, delta: 1) }
                        Divider()
                        Button("Retire (hide)") { hideOption(option) }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 10)).foregroundColor(Theme.mutedFg)
                            .frame(width: 20, height: 18).contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func renameStatus(_ option: OptionRow) {
        let carried = option.count ?? 0
        Dialogs.shared.prompt(
            "Rename \(option.name)",
            message: "Carried by \(carried) — boards re-key, one transaction. ⌘⌥Z undoes.",
            initial: option.name, confirmLabel: "Rename"
        ) { name in
            guard let name = name?.trimmingCharacters(in: .whitespaces),
                !name.isEmpty, name != option.name
            else { return }
            model.renameValue(property: "status", old: option.name, new: name) { count in
                if count >= 0 {
                    flash("Renamed on \(count) — the board re-keyed. ⌘⌥Z undoes.")
                }
            }
        }
    }

    private func reorderStatus(_ option: OptionRow, in options: [OptionRow], delta: Int) {
        guard let at = options.firstIndex(where: { $0.id == option.id }) else { return }
        let to = at + delta
        guard options.indices.contains(to) else { return }
        // The pins grammar: land between neighbors by the float key.
        let neighbor = options[to].boardOrder
        let beyond = options.indices.contains(to + delta)
            ? options[to + delta].boardOrder
            : neighbor + Double(delta) * 2
        model.set(option.id, property: "order", value: String((neighbor + beyond) / 2))
    }
}

// MARK: - Shortcuts (P19g): ONE table, two scopes

struct ShortcutsPanel: View {
    @ObservedObject var model: BoxModel
    @AppStorage("app.inspector.hints.v1") private var digitHints = true
    @State private var recordingId: String?
    @State private var pendingSteal: (id: String, chord: String)?
    @State private var monitor: Any?
    @State private var toast: String?
    /// Bumped after every keymap write so the table re-reads the registry.
    @State private var epoch = 0

    /// Digit keys reserved by the inspector's own grammar.
    static let reservedKeys: Set<String> = ["n", "m", "h", "l", "f", "g", "s", "w"]

    var body: some View {
        let _ = epoch
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SettingRow(label: "Digit hints in the inspector", scope: "app") {
                    Toggle("", isOn: $digitHints).toggleStyle(.switch).controlSize(.mini)
                        .labelsHidden()
                }
                digitSection
                chordSection
                if let toast {
                    Text(toast)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 7).fill(Theme.accent.opacity(0.13)))
                }
            }
            .padding(.bottom, 10)
        }
        .onDisappear { stopRecording() }
    }

    private func flash(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { if toast == text { toast = nil } }
    }

    // MARK: property digit keys (vault cells — they travel with the box)

    private var digitSection: some View {
        let keyed = (model.snap?.properties ?? []).filter { $0.digitKey != nil }
        let unkeyed = (model.snap?.properties ?? []).filter { $0.digitKey == nil }
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("PROPERTY KEYS")
                    .font(.system(size: 9.5, weight: .bold)).kerning(0.5)
                    .foregroundColor(Theme.mutedFg)
                Text("vault — they travel with the box")
                    .font(.system(size: 9)).foregroundColor(Theme.mutedFg.opacity(0.8))
                Spacer()
                Menu {
                    ForEach(unkeyed) { def in
                        Button(def.name) { assignDigitKey(def) }
                    }
                } label: {
                    Text("＋ assign").font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(Theme.accent)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            ForEach(keyed) { def in
                HStack(spacing: 8) {
                    Text(def.name).font(.system(size: 12)).frame(width: 150, alignment: .leading)
                    Text(def.digitKey ?? "")
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 5)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border))
                    Spacer()
                    Button("Clear") {
                        model.set(def.id, property: "digit-key", value: "")
                        flash("Key cleared — one cell, ⌘⌥Z undoes.")
                    }
                    .buttonStyle(.plain).font(.system(size: 10))
                    .foregroundColor(Theme.mutedFg)
                }
                .padding(.vertical, 1)
            }
            Text("Reserved: N M H L F G S W — the inspector's own grammar.")
                .font(.system(size: 9)).foregroundColor(Theme.mutedFg.opacity(0.8))
        }
    }

    private func assignDigitKey(_ def: PropertyRow) {
        Dialogs.shared.prompt(
            "Key for \(def.name)",
            message: "One letter or digit; it works in the inspector, the palette, and suggestion chips at once. Reserved: N M H L F G S W.",
            placeholder: "key", confirmLabel: "Assign"
        ) { raw in
            guard let key = raw?.trimmingCharacters(in: .whitespaces).lowercased(),
                key.count == 1
            else { return }
            if Self.reservedKeys.contains(key) {
                flash("\(key.uppercased()) is reserved by the inspector — pick another.")
                return
            }
            if let holder = (model.snap?.properties ?? []).first(where: {
                $0.digitKey?.lowercased() == key && $0.id != def.id
            }) {
                flash("\(key.uppercased()) is on \(holder.name) — clear it there first.")
                return
            }
            model.set(def.id, property: "digit-key", value: key)
            flash("\(def.name) answers to \(key.uppercased()) — everywhere, one cell.")
        }
    }

    // MARK: command chords (app prefs — this Mac only, never the box)

    private var chordSection: some View {
        let registry = CommandRegistry.shared
        let commands = registry.allCommands.filter { $0.binding != nil }
        let grouped = Dictionary(grouping: commands, by: \.category)
        let conflicted = Set(registry.conflicts().values.flatMap { $0 })
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("COMMAND CHORDS")
                    .font(.system(size: 9.5, weight: .bold)).kerning(0.5)
                    .foregroundColor(Theme.mutedFg)
                Text("app — this Mac only")
                    .font(.system(size: 9)).foregroundColor(Theme.mutedFg.opacity(0.8))
                Spacer()
                Button("Reset all") {
                    registry.resetOverrides()
                    epoch += 1
                    flash("Every chord back on its default.")
                }
                .buttonStyle(.plain).font(.system(size: 10.5, weight: .medium))
                .foregroundColor(Theme.accent)
            }
            if !conflicted.isEmpty {
                Text("⚠ Two commands share a chord — insertion order decides until one moves.")
                    .font(.system(size: 10)).foregroundColor(Color(nsColor: .systemRed).opacity(0.85))
            }
            ForEach(grouped.keys.sorted(), id: \.self) { category in
                Text(category.uppercased())
                    .font(.system(size: 8.5, weight: .bold)).kerning(0.4)
                    .foregroundColor(Theme.mutedFg.opacity(0.8))
                    .padding(.top, 5)
                ForEach(grouped[category] ?? [], id: \.id) { command in
                    chordRow(command, conflicted: conflicted.contains(command.id))
                }
            }
        }
    }

    private func chordRow(_ command: CommandDef, conflicted: Bool) -> some View {
        let registry = CommandRegistry.shared
        let locked = CommandRegistry.unstealable.contains(command.id)
        let chord = registry.effectiveBinding(for: command.id)
        return HStack(spacing: 8) {
            Text(command.label).font(.system(size: 12))
                .frame(width: 190, alignment: .leading)
                .foregroundColor(conflicted ? Color(nsColor: .systemRed) : Theme.foreground)
            if locked {
                Text(chordLabel(chord)).font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.mutedFg)
                Text("always answers — not rebindable")
                    .font(.system(size: 9)).foregroundColor(Theme.mutedFg.opacity(0.8))
            } else {
                Button {
                    recordingId == command.id ? stopRecording() : startRecording(command.id)
                } label: {
                    Text(recordingId == command.id
                        ? (pendingSteal != nil ? "press again to steal" : "press a chord…")
                        : chordLabel(chord))
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(
                                    recordingId == command.id ? Theme.accent : Theme.border))
                        .foregroundColor(
                            recordingId == command.id ? Theme.accent : Theme.foreground.opacity(0.85))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if registry.hasOverride(command.id) {
                    Button("reset") {
                        registry.setOverride(command.id, nil)
                        epoch += 1
                        flash("\(command.label) back on its default.")
                    }
                    .buttonStyle(.plain).font(.system(size: 9.5))
                    .foregroundColor(Theme.mutedFg)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
    }

    private func chordLabel(_ hotkey: Hotkey?) -> String {
        guard let hotkey else { return "—" }
        var out = ""
        if hotkey.modifiers.contains(.ctrl) { out += "⌃" }
        if hotkey.modifiers.contains(.alt) { out += "⌥" }
        if hotkey.modifiers.contains(.shift) { out += "⇧" }
        if hotkey.modifiers.contains(.mod) { out += "⌘" }
        return out + (hotkey.key == " " ? "Space" : hotkey.key.uppercased())
    }

    private func startRecording(_ id: String) {
        stopRecording()
        recordingId = id
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {  // Esc cancels — and stays unstealable
                stopRecording()
                return nil
            }
            var mods: Hotkey.Modifiers = []
            if event.modifierFlags.contains(.command) { mods.insert(.mod) }
            if event.modifierFlags.contains(.shift) { mods.insert(.shift) }
            if event.modifierFlags.contains(.option) { mods.insert(.alt) }
            if event.modifierFlags.contains(.control) { mods.insert(.ctrl) }
            guard !mods.isEmpty, let key = event.charactersIgnoringModifiers?.lowercased(),
                !key.isEmpty
            else { return nil }
            apply(chord: Hotkey(modifiers: mods, key: key), to: id)
            return nil
        }
    }

    /// The brick-proof apply: unstealable chords refuse with the reason
    /// inline; a chord another command holds needs a SECOND identical press
    /// (press-again-to-steal); everything lands as an app pref, undoable by
    /// its reset link — never a modal.
    private func apply(chord: Hotkey, to id: String) {
        let registry = CommandRegistry.shared
        let signature = "\(chord.modifiers.rawValue)+\(chord.key)"
        // Unstealable: ⌘, and ⌘⌥Z always answer.
        for lockedId in CommandRegistry.unstealable {
            if let locked = registry.effectiveBinding(for: lockedId),
                locked.modifiers == chord.modifiers,
                locked.key.lowercased() == chord.key
            {
                flash("That chord opens \(lockedId == "app:open-settings" ? "Settings" : "Undo") — it always answers.")
                stopRecording()
                return
            }
        }
        // Held elsewhere → press again to steal.
        let holder = registry.allCommands.first { other in
            guard other.id != id, let binding = registry.effectiveBinding(for: other.id) else {
                return false
            }
            return binding.modifiers == chord.modifiers && binding.key.lowercased() == chord.key
        }
        if let holder, pendingSteal?.id != id || pendingSteal?.chord != signature {
            pendingSteal = (id, signature)
            flash("\(chordLabel(chord)) is on \(holder.label) — press it again to steal.")
            epoch += 1
            return
        }
        registry.setOverride(id, chord)
        pendingSteal = nil
        stopRecording()
        epoch += 1
        let label = registry.allCommands.first { $0.id == id }?.label ?? id
        flash("\(label) → \(chordLabel(chord)) — reset on its row undoes.")
    }

    private func stopRecording() {
        recordingId = nil
        pendingSteal = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

// MARK: - Assist (P19h): the automation switch + BYOK

/// The consent panel. The switch is a VAULT cell (the CLI honors it too);
/// the key lives in the KEYCHAIN and appears nowhere in the log or prefs.
/// The amber rulebox is the one amber outside the AI surfaces — it states
/// the fixed contract those surfaces live under.
struct AssistPanel: View {
    @ObservedObject var model: BoxModel
    @State private var keyDraft = ""
    @State private var keyStored = AssistPanel.keychainHas()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let assist = model.snap?.assist {
                SettingRow(label: "Automation (the clerk)", scope: "vault") {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { assist.on },
                            set: { on in
                                model.set(
                                    assist.id, property: "automation",
                                    value: on ? "true" : "false")
                            })
                    )
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                }
                Text(assist.on
                    ? "The clerk sweeps at every open — deterministic proposers only, one queue, nothing applied without you."
                    : "Silence. No proposals anywhere — the shell, the CLI, every process honors this cell.")
                    .font(.system(size: 10)).foregroundColor(Theme.mutedFg)
            }
            SettingRow(label: "Model key (BYOK)", scope: "app") {
                HStack(spacing: 8) {
                    if keyStored {
                        Text("stored in the Keychain")
                            .font(.system(size: 11)).foregroundColor(Theme.mutedFg)
                        Button("Clear") {
                            AssistPanel.keychainClear()
                            keyStored = false
                        }
                        .buttonStyle(.plain).font(.system(size: 11))
                        .foregroundColor(Theme.accent)
                    } else {
                        SecureField("sk-…", text: $keyDraft)
                            .textFieldStyle(.plain).font(.system(size: 11, design: .monospaced))
                            .frame(width: 180)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.border))
                        Button("Store") {
                            guard !keyDraft.isEmpty else { return }
                            AssistPanel.keychainStore(keyDraft)
                            keyDraft = ""
                            keyStored = true
                        }
                        .buttonStyle(.plain).font(.system(size: 11))
                        .foregroundColor(Theme.accent)
                    }
                }
            }
            Text("Dormant, honestly: nothing reads this key yet. It waits in the Keychain for the fence to open — it appears nowhere in the log or prefs.")
                .font(.system(size: 10)).foregroundColor(Theme.mutedFg)
            // The fixed contract — the one amber outside the AI surfaces.
            VStack(alignment: .leading, spacing: 3) {
                Text("✦ THE CONTRACT").font(.system(size: 9, weight: .bold)).kerning(0.5)
                Text("AI only ever proposes — accepting runs the exact seam a manual edit runs. Amber marks every AI container. Dismissals are remembered by a deterministic id and never re-asked. ⌘Z never expires.")
                    .font(.system(size: 10.5))
            }
            .foregroundColor(Theme.warning)
            .padding(10)
            .frame(maxWidth: 460, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.warning.opacity(0.55)))
        }
    }

    // ---- the Keychain seam (Security.framework via the C API) ----

    private static let service = "com.lotus.byok"

    static func keychainHas() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: false,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func keychainStore(_ key: String) {
        keychainClear()
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecValueData as String: Data(key.utf8),
        ]
        SecItemAdd(add as CFDictionary, nil)
    }

    static func keychainClear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
