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
                stub("The definitions editor and the vocabulary shelves — land with 19e/19f. The rename engine underneath is live (try `lotus rename-value` from the CLI).")
            case .shortcuts:
                stub("One table, two scopes — property digit-keys travel with the box, command chords stay on this Mac. Lands with 19g.")
            case .capture:
                SettingsCapturePanel(model: model, dismiss: dismiss)
            case .assist:
                stub("The automation switch (a vault cell — the CLI honors it too) and the dormant BYOK Keychain row — land with 19h.")
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
