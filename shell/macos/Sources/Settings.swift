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
    // P20i (O9): the mockup's six-group nav. `capture`/`startup` folded
    // into General (recorded); raw values persist for saved prefs.
    case general, appearance, properties, vocabulary, shortcuts, assist

    var label: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .properties: return "Properties"
        case .vocabulary: return "Vocabulary"
        case .shortcuts: return "Shortcuts"
        case .assist: return "AI"
        }
    }

    var scopeTag: String {
        switch self {
        case .general: return "3 settings"
        case .properties, .vocabulary: return "vault"
        default: return "app"
        }
    }

    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .appearance: return "paintbrush"
        case .properties: return "tablecells"
        case .vocabulary: return "tag"
        case .shortcuts: return "keyboard"
        case .assist: return "sparkle"
        }
    }
}

/// Backstage plumbing definitions (display attributes, the consent switch):
/// real cells, but never user vocabulary — the definitions table must not
/// offer Rename/Retype on the machinery the renames themselves run on
/// (the P19 review). The assist switch property is matched by its CURRENT
/// name via `snap.assist?.prop`.
let plumbingProperties: Set<String> = [
    "order", "hue", "completes", "for-type", "icon", "digit-key", "hidden",
    "hide-when-empty", "hide-on-kind", "core-on-kind", "default-status",
    "parent", "automation",
]

func isPlumbing(_ name: String, model: BoxModel) -> Bool {
    plumbingProperties.contains(name) || model.snap?.assist?.prop == name
}

// P20i (O9): the P19 SettingsOverlay retired — Settings is a SURFACE
// (SettingsNav + SettingsSurfaceView below). The overlay's digit-facet
// search grammar is recorded in the P19 doc; the surface search hands
// misses to the palette instead.

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
    // P20a: four named themes as token swaps (the mockup pane's cards,
    // direct-select; the rail button stays the cycler) + the Shape flavor.
    @ObservedObject private var themes = ThemeCore.shared
    @AppStorage("app.shape.v1") private var shape = "standard"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("skin, shape and type — everything here is a token swap. no layout, no behavior changes.")
                .font(.system(size: 10.5)).foregroundColor(Theme.mutedFg)
            HStack(spacing: 8) {
                ForEach(themeSpecs, id: \.id) { spec in
                    themeCard(spec)
                }
            }
            SettingRow(label: "Shape flavor", scope: "app") {
                Picker("", selection: $shape) {
                    Text("Standard").tag("standard")
                    Text("Soft · 12").tag("soft")
                    Text("Sharp · 4").tag("sharp")
                }
                .pickerStyle(.segmented).fixedSize().controlSize(.small)
                .onChange(of: shape) {
                    // Republish so every surface picks the radius up now —
                    // "changes apply instantly" is the law of this overlay.
                    themes.apply(themes.spec.id)
                }
            }
            LockedRow(
                label: "Accent",
                caption: "The accent means selection; amber means AI — in every theme. The palette is the product.")
            Text("The brand faces (Hanken Grotesk · Fraunces) light up when their fonts are present; reading mode and glyph strength arrive with the editor pass (P20c).")
                .font(.system(size: 10)).foregroundColor(Theme.mutedFg.opacity(0.8))
                .padding(.top, 4)
        }
    }

    private func themeCard(_ spec: ThemeSpec) -> some View {
        let on = themes.spec.id == spec.id
        return Button {
            themes.apply(spec.id)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                // The swatch: chrome | canvas | surface bands + accent dot.
                HStack(spacing: 0) {
                    Rectangle().fill(Color(nsColor: spec.chrome))
                    Rectangle().fill(Color(nsColor: spec.canvas))
                    Rectangle().fill(Color(nsColor: spec.surface))
                }
                .frame(width: 92, height: 34)
                .overlay(alignment: .bottomTrailing) {
                    Circle().fill(Color(nsColor: spec.accent))
                        .frame(width: 10, height: 10).padding(4)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
                Text(spec.label)
                    .font(.system(size: 10.5, weight: on ? .semibold : .regular))
                    .foregroundColor(on ? Theme.accent : Theme.mutedFg)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(on ? Theme.accentTint : .clear))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(on ? Theme.accent.opacity(0.6) : Theme.border))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            // Shift alone is not a chord: a ⇧-only GLOBAL hotkey eats
            // capital letters in every app on the Mac (the P19 review).
            let strong = event.modifierFlags.intersection([.control, .option, .command])
            guard carbon != 0, !strong.isEmpty else {
                refuse("add ⌃, ⌥ or ⌘ — shift alone would eat capitals")
                return nil
            }
            // The brick-proof pair stays reachable system-wide too.
            let chars = event.charactersIgnoringModifiers ?? ""
            if (strong == [.command] && chars == ",")
                || (strong == [.command, .option] && chars.lowercased() == "z")
            {
                refuse("that chord is reserved — it always answers in Liv")
                return nil
            }
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

    /// An explained refusal in the recorder's own slot — never a beep-only.
    private func refuse(_ why: String) {
        stop()
        display = why
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            if display == why { display = KeyRecorder.currentDisplay() }
        }
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
    /// P20i: the mockup splits Properties (definitions) from Vocabulary
    /// (shelves + status); one panel, gated sections.
    enum Show { case all, definitions, vocabulary }
    var show: Show = .all
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
                if show != .vocabulary { definitionsTable }
                if show != .definitions {
                    shelves
                    statusTable
                }
            }
            .padding(.bottom, 10)
        }
        // Pinned to the visible panel — a toast at the scroll tail is
        // off-screen exactly when the renamed row was near the top (P19
        // review).
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 7).fill(Theme.panel))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.accent.opacity(0.4)))
            }
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
        let visible = properties.filter { !isPlumbing($0.name, model: model) }
        let spine = visible.filter { $0.seeded ?? false }
        let custom = visible.filter { !($0.seeded ?? false) }
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
                        Button(kind.name + ((def.hideOnKinds ?? []).contains(kind.name) ? " ✓" : "")) {
                            PropertyActions.hideOnKind(model: model, def: def, kind: kind)
                        }
                    }
                }
                Menu("Core on kind") {
                    // The 19e core star: pinned to the kind's panel, shown
                    // even when empty.
                    ForEach(model.snap?.kinds ?? []) { kind in
                        Button(kind.name + ((def.coreOnKinds ?? []).contains(kind.name) ? " ★" : "")) {
                            PropertyActions.toggleCoreOnKind(model: model, def: def, kind: kind)
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
        // The partition is seeded-ness, not usage: a user-born option with
        // zero carriers is still the user's vocabulary and must land on a
        // shelf, or "+ option" looks dead (the P19 review). `seeded` is
        // already seeded-AND-unused on the wire.
        let vault = property.options.filter { !($0.seeded ?? false) && !$0.isHidden }
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
                    flash("The rename didn't commit — refused, or the box is busy. Try again.")
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
            statusRows(options)
            retiredRows
        }
    }

    @ViewBuilder
    private func statusRows(_ options: [OptionRow]) -> some View {
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

    /// Retire is reversible or it isn't retire (P19 review): the hidden
    /// status options stay reachable here, mirroring the shelves' Hidden.
    @ViewBuilder
    private var retiredRows: some View {
        let retired = (model.property(named: "status")?.options ?? []).filter { option in
            guard option.isHidden else { return false }
            let scoped = option.forTypes ?? []
            return scoped.isEmpty || scoped.contains(statusKind)
        }
        if !retired.isEmpty {
            DisclosureGroup {
                ForEach(retired) { option in
                    HStack(spacing: 8) {
                        Text(option.name).font(.system(size: 11.5))
                            .foregroundColor(Theme.mutedFg)
                        Spacer(minLength: 4)
                        Button("Restore") {
                            model.set(option.id, property: "hidden", value: "false")
                        }
                        .buttonStyle(.plain).font(.system(size: 10))
                        .foregroundColor(Theme.accent)
                    }
                    .padding(.vertical, 1)
                }
            } label: {
                Text("RETIRED · \(retired.count)")
                    .font(.system(size: 8.5, weight: .bold)).kerning(0.4)
                    .foregroundColor(Theme.mutedFg.opacity(0.8))
            }
            .font(.system(size: 10))
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
                } else {
                    flash("The rename didn't commit — refused, or the box is busy. Try again.")
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
    /// The digit-key steal handshake: assign the same key to the same
    /// definition twice and it moves (press-again-to-steal, prompt-shaped).
    @State private var pendingDigitSteal: (def: UInt64, key: String)?
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
            }
            .padding(.bottom, 10)
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.panel))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.accent.opacity(0.4)))
            }
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
                // Press-again-to-steal, the chord table's grammar (P19
                // review): the same assignment repeated moves the key.
                if pendingDigitSteal?.def == def.id && pendingDigitSteal?.key == key {
                    pendingDigitSteal = nil
                    model.set(holder.id, property: "digit-key", value: "")
                    model.set(def.id, property: "digit-key", value: key)
                    flash("\(key.uppercased()) moved from \(holder.name) to \(def.name) — two cells, ⌘⌥Z twice undoes.")
                } else {
                    pendingDigitSteal = (def.id, key)
                    flash("\(key.uppercased()) is on \(holder.name) — assign it again to steal.")
                }
                return
            }
            pendingDigitSteal = nil
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
        hotkey?.label ?? "—"
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
            guard !mods.isEmpty else { return nil }
            // Speak the matcher's language (P19 review): function keys type
            // private-use glyphs and control keys type control characters —
            // stored raw they render garbled AND never collide with the
            // named defaults, so conflicts() misses real double-bindings.
            let named: [UInt16: String] = [
                123: "ArrowLeft", 124: "ArrowRight", 125: "ArrowDown", 126: "ArrowUp",
                36: "Return", 49: " ", 120: "F2",
                50: "`", 39: "'", 43: ",", 47: ".", 33: "[", 30: "]",
            ]
            let key: String
            if let name = named[event.keyCode] {
                key = name
            } else if let chars = event.charactersIgnoringModifiers?.lowercased(),
                let scalar = chars.unicodeScalars.first, chars.count == 1,
                scalar.value >= 0x20, !(0xF700...0xF8FF).contains(scalar.value)
            {
                key = chars
            } else {
                flash("That key can't be a chord here — letters, digits, punctuation, arrows, Return, Space, F2.")
                stopRecording()
                return nil
            }
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
        if let holder {
            // The loser really lets go (P19 review): otherwise the chord
            // still fires whichever command registered first.
            registry.setUnbound(holder.id)
        }
        pendingSteal = nil
        stopRecording()
        epoch += 1
        let label = registry.allCommands.first { $0.id == id }?.label ?? id
        if let holder {
            flash("\(label) → \(chordLabel(chord)) — stolen from \(holder.label), now unbound; reset restores either.")
        } else {
            flash("\(label) → \(chordLabel(chord)) — reset on its row undoes.")
        }
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
    @State private var keyError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let assist = model.snap?.assist {
                SettingRow(label: "Automation (the clerk)", scope: "vault") {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { assist.on },
                            set: { on in
                                // The wire carries the switch property's
                                // CURRENT name — the write target survives a
                                // definition rename (P19 review).
                                model.set(
                                    assist.id, property: assist.prop ?? "automation",
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
                            // SecItemAdd can refuse (locked keychain, say):
                            // the draft survives and the row says so — never
                            // an optimistic "stored" over a lost key (P19
                            // review).
                            if AssistPanel.keychainStore(keyDraft) {
                                keyDraft = ""
                                keyStored = true
                                keyError = nil
                            } else {
                                keyError = "The Keychain refused — the key was NOT stored."
                            }
                        }
                        .buttonStyle(.plain).font(.system(size: 11))
                        .foregroundColor(Theme.accent)
                        if let keyError {
                            Text(keyError).font(.system(size: 10))
                                .foregroundColor(Color(nsColor: .systemRed).opacity(0.85))
                        }
                    }
                }
            }
            Text("Dormant, honestly: nothing reads this key yet. It waits in the Keychain for the fence to open — it appears nowhere in the log or prefs.")
                .font(.system(size: 10)).foregroundColor(Theme.mutedFg)
            // The fixed contract — the one amber outside the AI surfaces.
            VStack(alignment: .leading, spacing: 3) {
                Text("✦ THE CONTRACT").font(.system(size: 9, weight: .bold)).kerning(0.5)
                Text("AI only ever proposes — accepting runs the exact seam a manual edit runs. Amber marks every AI container. Dismissals are remembered by a deterministic id and never re-asked. ⌘⌥Z never expires.")
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

    @discardableResult
    static func keychainStore(_ key: String) -> Bool {
        keychainClear()
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecValueData as String: Data(key.utf8),
        ]
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func keychainClear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(query as CFDictionary)
    }
}


// MARK: - Settings as a SURFACE (P20i, O9 — the overlay retires)

/// The left panel: search (the grammar hint; 0 results hand the query to
/// the palette) + the six OPTIONS with icons and scope aft tags.
struct SettingsNav: View {
    @ObservedObject var model: BoxModel
    @AppStorage("app.settings.lastPanel.v1") private var lastPanelRaw =
        SettingsGroup.general.rawValue
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 9))
                    .foregroundColor(Theme.mutedFg)
                TextField("search settings…", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 11))
                    .onSubmit {
                        // 0 results never dead-ends: ⏎ hands the query to
                        // the palette.
                        if hits.isEmpty, !query.isEmpty {
                            NotificationCenter.default.post(
                                name: .lotusSearchFor, object: query)
                            query = ""
                        } else if let first = hits.first {
                            lastPanelRaw = first.rawValue
                            query = ""
                        }
                    }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().strokeBorder(Theme.border))
            .padding(.horizontal, 8).padding(.top, 8)
            Text("entries carry group · scope · kind — the same grammar as vault search. 0 results never dead-ends: ⏎ hands the query to the palette.")
                .font(.system(size: 9)).foregroundColor(Theme.mutedFg.opacity(0.8))
                .padding(.horizontal, 10)
            Text("OPTIONS").font(.system(size: 9.5, weight: .bold)).kerning(0.5)
                .foregroundColor(Theme.mutedFg)
                .padding(.horizontal, 10).padding(.top, 6)
            ForEach(shown, id: \.rawValue) { group in
                let on = lastPanelRaw == group.rawValue
                Button {
                    lastPanelRaw = group.rawValue
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: group.icon).font(.system(size: 10.5))
                            .foregroundColor(on ? Theme.accent : Theme.mutedFg)
                            .frame(width: 15)
                        Text(group.label)
                            .font(.system(size: 12, weight: on ? .medium : .regular))
                        Spacer(minLength: 4)
                        Text(group.scopeTag)
                            .font(.system(size: 8.5)).kerning(0.3)
                            .foregroundColor(
                                group.scopeTag == "vault" ? Theme.accent : Theme.mutedFg)
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(on ? Theme.accentTint : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private var hits: [SettingsGroup] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return SettingsGroup.allCases }
        return SettingsGroup.allCases.filter { $0.label.lowercased().contains(needle) }
    }

    private var shown: [SettingsGroup] { hits }
}

/// The center: the active group's pane in a max-880 column + the footbar.
struct SettingsSurfaceView: View {
    @ObservedObject var model: BoxModel
    @AppStorage("app.settings.lastPanel.v1") private var lastPanelRaw =
        SettingsGroup.general.rawValue

    private var group: SettingsGroup {
        SettingsGroup(rawValue: lastPanelRaw) ?? .general
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(group.label).font(.system(size: 16, weight: .bold))
                        Text(group.scopeTag)
                            .font(.system(size: 9)).kerning(0.3)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .overlay(
                                Capsule().strokeBorder(
                                    group.scopeTag == "vault"
                                        ? Theme.accent.opacity(0.5) : Theme.border))
                            .foregroundColor(
                                group.scopeTag == "vault" ? Theme.accent : Theme.mutedFg)
                    }
                    switch group {
                    case .general:
                        GeneralPanel(model: model, jump: { lastPanelRaw = $0.rawValue })
                    case .appearance:
                        AppearancePanel()
                    case .properties:
                        VocabularyPanel(show: .definitions, model: model)
                    case .vocabulary:
                        VocabularyPanel(show: .vocabulary, model: model)
                    case .shortcuts:
                        VStack(alignment: .leading, spacing: 8) {
                            SettingRow(label: "Capture hotkey", scope: "app") {
                                KeyRecorder()
                            }
                            ShortcutsPanel(model: model)
                        }
                    case .assist:
                        VStack(alignment: .leading, spacing: 8) {
                            Text("the one switch, who pays for the model, and how loud the suggestions are. nothing here changes WHAT the AI may do — that contract is fixed.")
                                .font(.system(size: 10.5)).foregroundColor(Theme.mutedFg)
                            AssistPanel(model: model)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(18)
                .frame(maxWidth: 880, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            HStack(spacing: 10) {
                HStack(spacing: 3) { KbdChip(label: "⌘,", size: 9); footText("open settings") }
                HStack(spacing: 3) { KbdChip(label: "type", size: 9); footText("filters everything") }
                HStack(spacing: 3) { KbdChip(label: "⏎", size: 9); footText("jump to the exact row") }
                Spacer()
                footText("changes apply instantly — there is no Save button")
            }
            .padding(.horizontal, 18).padding(.vertical, 6)
            .overlay(Divider(), alignment: .top)
        }
    }

    private func footText(_ text: String) -> some View {
        Text(text).font(.system(size: 10)).foregroundColor(Theme.mutedFg)
    }
}

/// General (P20i map [3]): the honest page — exactly three user settings;
/// everything else in here is vocabulary and display. Startup + the
/// capture convention keep quiet homes below (recorded keeps).
struct GeneralPanel: View {
    @ObservedObject var model: BoxModel
    var jump: (SettingsGroup) -> Void = { _ in }
    @ObservedObject private var themes = ThemeCore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("the honest page. Liv keeps very few real settings — the rest of this surface tunes display, density and vocabulary.")
                .font(.system(size: 10.5)).foregroundColor(Theme.mutedFg)
            Text("exactly three user settings: where the store lives · what it looks like · whether the assist layer runs. everything else in here is vocabulary and display — a setting never forks behavior.")
                .font(.system(size: 11, weight: .medium))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.accent.opacity(0.45)))
            generalRow(
                "Store location", tag: "1 OF 3",
                sub: model.inVault
                    ? "one plain folder of markdown and files — that folder IS the database. a cloud-synced local folder works too. moving the store moves your files; nothing else changes."
                    : "one store on this Mac — that file is the vault. the folder-of-markdown presentation turns on when the store lives at a vault root (…/.liv/box/).",
                trailing: AnyView(
                    HStack(spacing: 6) {
                        Text(model.inVault ? (model.vaultRoot ?? model.path) : model.path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.mutedFg)
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: 240)
                        Button("Reveal") {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [URL(fileURLWithPath: model.inVault ? (model.vaultRoot ?? model.path) : model.path)])
                        }
                        .buttonStyle(.plain).font(.system(size: 10.5))
                        .foregroundColor(Theme.accent)
                    }))
            generalRow(
                "What it looks like", tag: "2 OF 3",
                sub: "theme, shape, type — a token swap, never a layout or behavior change",
                trailing: AnyView(
                    Button("\(themes.spec.label) ›") { jump(.appearance) }
                        .buttonStyle(.plain).font(.system(size: 11))
                        .foregroundColor(Theme.accent)))
            generalRow(
                "Whether the assist layer runs", tag: "3 OF 3",
                sub: "the automation switch — the consent boundary. it lives on the AI page, next to who pays for the model.",
                trailing: AnyView(
                    Button {
                        jump(.assist)
                    } label: {
                        Text(model.snap?.assist?.on == false ? "off ›" : "✦ on ›")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(
                                model.snap?.assist?.on == false ? Theme.mutedFg : Theme.warning)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(
                                Capsule().fill(
                                    model.snap?.assist?.on == false
                                        ? Theme.panel2 : Theme.warning.opacity(0.12)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)))
            Divider().padding(.vertical, 4)
            StartupPanel(model: model)
            LockedRow(
                label: "Capture behavior",
                caption: "One field, from anywhere; Esc closes; it asks nothing else.")
            Text("scope tags on every row · vault rows travel with the store · app rows stay on this machine.")
                .font(.system(size: 9.5)).foregroundColor(Theme.mutedFg.opacity(0.8))
        }
    }

    private func generalRow(
        _ label: String, tag: String, sub: String, trailing: AnyView
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Text(label).font(.system(size: 12.5, weight: .semibold))
                Text(tag).font(.system(size: 8, weight: .bold)).kerning(0.4)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Theme.panel2))
                    .foregroundColor(Theme.mutedFg)
                Spacer()
                trailing
            }
            Text(sub).font(.system(size: 10.5)).foregroundColor(Theme.mutedFg)
        }
        .padding(.vertical, 6)
        .overlay(Divider(), alignment: .bottom)
    }
}
