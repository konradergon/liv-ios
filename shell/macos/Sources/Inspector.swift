// lotus — the V3 keyboard-compact inspector (P11.5f, design §2). BP-1's
// grammar rendered native: ONE component with six kind tunings, replacing
// the P5 pane in place — same signature, both mounts (the window's right
// pane and the calendar's embedded column). Static grammar + existing
// write paths only; the anchored editors arrive in 11.5g, the row menu
// and CONNECTIONS in 11.5h.

import AppKit
import SwiftUI

// MARK: - panel focus + the command block (§2.3)

/// Shared so command `enabled` closures can see whether a pane holds the
/// keyboard without a reference to the pane itself.
final class InspectorFocus: ObservableObject {
    static let shared = InspectorFocus()
    @Published var active = false
    /// A popover editor is up: the panel's scoped commands go inert so the
    /// popover's own key handling (digits pick, Esc closes) owns the event.
    @Published var editorOpen = false
}

extension Notification.Name {
    /// The inspector key bus: command actions post a key token; the one
    /// mounted pane acts on it (the calendar never coexists with the
    /// global pane — Window.swift's surface gate).
    static let lotusInspectorKey = Notification.Name("lotus.inspector.key")
    /// Open an entity in a (background) tab — CONNECTIONS' Ctrl/⌘-click.
    static let lotusOpenEntity = Notification.Name("lotus.openEntity")
}

/// Ordinary CommandDefs in the one registry (§2.3), registered once.
/// Alt+→ is the global doorway; everything else is gated on panel focus
/// AND allow-listed by the capture scope, so bare digits can never fire
/// while browsing. Nav history moved to ⌘[/⌘] for this (badge 32: the
/// blueprint assigns Alt+→/← to panel/doc).
enum InspectorCommands {
    private static var registered = false
    /// The capture-scope allow-list while the panel holds focus.
    static var scopeIds: Set<String> = []

    static func register() {
        guard !registered else { return }
        registered = true
        let registry = CommandRegistry.shared
        func post(_ key: String) {
            NotificationCenter.default.post(name: .lotusInspectorKey, object: key)
        }
        registry.register(
            CommandDef(
                id: "inspector:focus", label: "Focus inspector", scope: .global,
                category: "Inspector",
                binding: Hotkey(modifiers: [.alt], key: "ArrowRight"),
                enabled: { !InspectorFocus.shared.active }
            ) { post("focus") })

        var scoped: Set<String> = []
        func scopedCommand(_ id: String, _ label: String, _ binding: Hotkey, sends key: String) {
            scoped.insert(id)
            registry.register(
                CommandDef(
                    id: id, label: label, scope: .global, category: "Inspector",
                    binding: binding,
                    enabled: {
                        InspectorFocus.shared.active && !InspectorFocus.shared.editorOpen
                    }
                ) { post(key) })
        }
        scopedCommand(
            "inspector:blur", "Leave inspector",
            Hotkey(modifiers: [.alt], key: "ArrowLeft"), sends: "blur")
        for digit in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"] {
            scopedCommand(
                "inspector:digit-\(digit)", "Inspector field \(digit)",
                Hotkey(modifiers: [], key: digit), sends: digit)
        }
        // Task-field letters + the panel verbs. The view-config letters
        // L/F/G/S/W stay dormant (DigitMap.reserved holds their seats).
        for (letter, label) in [
            ("N", "Add property"), ("M", "Toggle MORE"), ("H", "Row menu"),
            ("D", "Due"), ("P", "Priority"), ("R", "Repeat"),
        ] {
            scopedCommand(
                "inspector:key-\(letter)", label,
                Hotkey(modifiers: [], key: letter.lowercased()), sends: letter)
        }
        scopedCommand(
            "inspector:rename", "Rename", Hotkey(modifiers: [], key: "F2"), sends: "F2")
        scopedCommand(
            "inspector:up", "Previous field",
            Hotkey(modifiers: [], key: "ArrowUp"), sends: "Up")
        scopedCommand(
            "inspector:down", "Next field",
            Hotkey(modifiers: [], key: "ArrowDown"), sends: "Down")
        scopedCommand(
            "inspector:edit", "Edit field", Hotkey(modifiers: [], key: "Return"),
            sends: "Return")
        scopedCommand(
            "inspector:space", "Cycle date role", Hotkey(modifiers: [], key: " "),
            sends: "Space")
        scopedCommand(
            "inspector:close", "Close editor / leave",
            Hotkey(modifiers: [], key: "Escape"), sends: "Escape")
        scopeIds = scoped
    }
}

// MARK: - the pane

struct InspectorPane: View {
    @ObservedObject var model: BoxModel
    @Binding var selection: UInt64?
    /// The standalone right pane breathes below the titlebar band; embedded
    /// (the calendar's column, under its own back-header) that space is a
    /// dead band, so the embedder passes 0.
    var topPadding: CGFloat = 24

    /// The focus-tracking sentinel for the `new…` add-property row.
    static let newRowId = UInt64.max

    @State private var focusedRow: UInt64? = nil
    @State private var editingRow: UInt64? = nil
    @State private var moreOpen = false
    @State private var lastEdited: UInt64? = nil
    @State private var scopePushed = false
    @State private var hoveringPane = false
    /// A hidden row a digit materialized (§2.5.3) — shown in MORE while set.
    @State private var materialized: UInt64? = nil
    /// The row whose ⋯ menu is up (⋯ click, H, or right-click).
    @State private var menuRow: UInt64? = nil
    @State private var backlinksOpen = false
    /// The trash undo affordance (badge 3: NO confirm dialog).
    @State private var undoOffer: String? = nil
    @State private var undoGeneration = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let entity = model.entity(selection) {
                        paneContent(entity)
                    } else {
                        emptyState
                    }
                }
                .padding(.top, topPadding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            if model.entity(selection) != nil {
                InspectorFootbar()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The right pane is an opaque panel card, the SAME fill as the left
        // sidebar — not the dim `underPageBackgroundColor` that let the window
        // material bleed through and read greyed-out.
        .background(Theme.panel)
        .onHover { hoveringPane = $0 }
        .onAppear { InspectorCommands.register() }
        .onDisappear { blur() }
        .onChange(of: selection) { blur() }
        .onChange(of: moreOpen) { reconcileFocusAfterFold() }
        .onChange(of: editingRow) {
            InspectorFocus.shared.editorOpen = editingRow != nil || menuRow != nil
        }
        .onChange(of: menuRow) {
            InspectorFocus.shared.editorOpen = editingRow != nil || menuRow != nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .lotusInspectorKey)) { note in
            guard let key = note.object as? String else { return }
            handle(key)
        }
    }

    // MARK: layout

    private func resolvedKeys() -> [String: String] {
        DigitMap.resolve(model.properties())
    }

    private func placement(for entity: EntityRow) -> InspectorLayout.Placement {
        var placement = InspectorLayout.place(
            kind: entity.kinds.first ?? "", catalog: model.properties(),
            cells: entity.cells, keys: resolvedKeys())
        // A digit reached a hidden row: it materializes in MORE, focused,
        // until the panel moves on (§2.5.3).
        if let materialized,
            !placement.core.contains(where: { $0.id == materialized }),
            !placement.taskFields.contains(where: { $0.id == materialized }),
            !placement.more.contains(where: { $0.id == materialized }),
            let prop = model.properties().first(where: { $0.id == materialized })
        {
            let cells = entity.cells.filter { $0.propertyId == prop.id }
            placement.more.append(
                InspectorRowSpec(
                    property: prop, cells: cells, key: resolvedKeys()[prop.name]))
        }
        return placement
    }

    @ViewBuilder
    private func paneContent(_ entity: EntityRow) -> some View {
        let placement = placement(for: entity)
        let hints = hintsVisible
        ObjectHeader(
            model: model, entity: entity,
            rename: { renamePrompt(entity) },
            trash: { trash(entity) })
        InspectorSect(title: "Properties")
        VStack(spacing: 0) {
            ForEach(placement.core) { spec in
                propertyRow(spec, entity: entity, hints: hints, inMore: false)
            }
            newPropertyRow(hints: hints)
        }
        .padding(.horizontal, 6)
        .padding(.top, 5)
        if !placement.taskFields.isEmpty {
            InspectorSect(title: "Task fields", aft: "only when object = task")
            VStack(spacing: 0) {
                ForEach(placement.taskFields) { spec in
                    propertyRow(spec, entity: entity, hints: hints, inMore: false)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 5)
        }
        moreSection(placement, entity: entity, hints: hints)
        connectionsSection(entity)
        // History lifted OUT of the inspector scroll into its own right-panel
        // lens (the bp4 five-lens bar, P17 — IA-5's Snapshots→History rename).
        Spacer(minLength: 12)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Select a row to see its cells.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            if let undoOffer {
                HStack(spacing: 8) {
                    Text("“\(undoOffer)” moved to Trash.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Button("Undo") {
                        model.undo()
                        self.undoOffer = nil
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.08)))
            }
        }
        .padding(20)
    }

    private func propertyRow(
        _ spec: InspectorRowSpec, entity: EntityRow, hints: Bool, inMore: Bool
    ) -> some View {
        let editor = rowEditor(for: spec.property)
        let isPopover = editor == .status || editor == .pool || editor == .date
        return PropertyRowView(
            model: model, entity: entity, spec: spec,
            focused: focusedRow == spec.id,
            editing: editingRow == spec.id && editor == .inline,
            editorPresented: Binding(
                get: { editingRow == spec.id && isPopover },
                set: { if !$0 && editingRow == spec.id { editingRow = nil } }),
            menuPresented: Binding(
                get: { menuRow == spec.id },
                set: { if !$0 && menuRow == spec.id { menuRow = nil } }),
            hints: hints, inMore: inMore,
            onFocus: { focusedRow = spec.id },
            onBeginEdit: { beginEdit(spec) },
            onEndEdit: { committed in
                if committed { lastEdited = spec.id }
                editingRow = nil
            },
            onCycleRole: { cycleRole(spec, entity: entity) })
    }

    /// The `new…` row (badge 13): kbd N, focusable now; its type-ahead
    /// popover ships with the editors in 11.5g.
    private func newPropertyRow(hints: Bool) -> some View {
        HStack(spacing: 7) {
            KeyCap(label: "N", visible: hints, accent: focusedRow == Self.newRowId)
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 12))
                Text("new…")
            }
            .font(.system(size: 12))
            .foregroundColor(Theme.mutedFg)
            .frame(width: 84, alignment: .leading)
            Text("add property (schema-on-read)")
                .font(.system(size: 12))
                .foregroundColor(Theme.mutedFg)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .frame(minHeight: 30)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(focusedRow == Self.newRowId ? Theme.accentTint : Color.clear))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(
                    focusedRow == Self.newRowId ? Theme.accent : Color.clear,
                    lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture {
            focusedRow = Self.newRowId
            editingRow = Self.newRowId
        }
        .popover(
            isPresented: Binding(
                get: { editingRow == Self.newRowId },
                set: { if !$0 && editingRow == Self.newRowId { editingRow = nil } }),
            arrowEdge: .leading
        ) {
            if let entity = model.entity(selection) {
                AddPropertyPopover(
                    model: model, entity: entity,
                    onReveal: { born in
                        reveal(born)
                        lastEdited = born
                    },
                    onDone: { editingRow = nil })
            }
        }
    }

    @ViewBuilder
    private func moreSection(
        _ placement: InspectorLayout.Placement, entity: EntityRow, hints: Bool
    ) -> some View {
        Button {
            withAnimation(Theme.springFast) { moreOpen.toggle() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(moreOpen ? 180 : 0))
                Text("More properties · \(moreCount(placement, entity: entity))")
                    .font(.system(size: 11.5, weight: .bold))
                    .kerning(0.5)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
            }
            .foregroundColor(Theme.mutedFg)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .overlay(Divider(), alignment: .top)
        if moreOpen {
            VStack(spacing: 0) {
                ForEach(placement.more) { spec in
                    propertyRow(spec, entity: entity, hints: hints, inMore: true)
                }
                if let created = entity.created {
                    systemRow(
                        icon: "clock.arrow.circlepath", name: "created",
                        value: "\(Civil.text(created, dateOnly: false)) · system")
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
        }
    }

    /// The MORE header's count: the placed rows PLUS the always-appended
    /// `created` system row, so the label matches what renders (the
    /// blueprint counts created/edited among the More rows; the review's
    /// off-by-one).
    private func moreCount(_ placement: InspectorLayout.Placement, entity: EntityRow) -> Int {
        placement.more.count + (entity.created != nil ? 1 : 0)
    }

    // MARK: CONNECTIONS (§2.7) — derived, three strata minus one

    /// Stratum 1: this entity's own reference cells (deliberate relations;
    /// `type` classifies, so it stays out). Stratum 2: the snapshot's
    /// reverse-reference index, collapsible. Stratum 3 (body wikilinks)
    /// is deferred with hover-peek. Click navigates the inspector;
    /// Ctrl/⌘-click opens a background tab.
    @ViewBuilder
    private func connectionsSection(_ entity: EntityRow) -> some View {
        let relations = entity.cells.filter {
            $0.kind == "reference" && $0.refTarget != nil && $0.property != "type"
        }
        let backlinks = model.backlinks(of: entity.id)
        InspectorSect(title: "Connections · \(relations.count + backlinks.count)")
            .padding(.top, 4)
            .overlay(Divider(), alignment: .top)
        if relations.isEmpty && backlinks.isEmpty {
            // Badge 31: empty is a valid resting state — the quiet dashed
            // box names the two ways in, no illustration.
            Text(
                "Nothing links here yet.\nRelate an object via its ⋯ menu, or type [[\(entity.title.isEmpty ? "Untitled" : entity.title)]] in any note."
            )
            .font(.system(size: 11.5))
            .foregroundColor(Theme.mutedFg)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .padding(12)
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        Color(nsColor: .separatorColor),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .padding(.init(top: 6, leading: 13, bottom: 12, trailing: 13))
        } else {
            ForEach(relations, id: \.self) { cell in
                if let target = cell.refTarget, let row = model.entity(target) {
                    connectionRow(
                        icon: "link", title: row.title.isEmpty ? "Untitled" : row.title,
                        detail: "relation · \(row.kinds.first ?? "object")",
                        target: target)
                }
            }
            if !backlinks.isEmpty {
                Button {
                    withAnimation(Theme.springFast) { backlinksOpen.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: backlinksOpen ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Backlinks · \(backlinks.count)").font(.system(size: 12))
                        Spacer(minLength: 6)
                        if !backlinksOpen {
                            Text(backlinkPreview(backlinks))
                                .font(.system(size: 10.5))
                                .foregroundColor(Theme.mutedFg)
                                .lineLimit(1)
                        }
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 13)
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if backlinksOpen {
                    ForEach(backlinks) { source in
                        connectionRow(
                            icon: "arrow.turn.up.left",
                            title: source.title.isEmpty ? "Untitled" : source.title,
                            detail: source.kinds.first ?? "object",
                            target: source.id)
                        .padding(.leading, 10)
                    }
                }
            }
            Spacer(minLength: 8).frame(height: 8)
        }
    }

    private func backlinkPreview(_ rows: [EntityRow]) -> String {
        let names = rows.prefix(2).map { $0.title.isEmpty ? "Untitled" : $0.title }
        let extra = rows.count - names.count
        return names.joined(separator: ", ") + (extra > 0 ? ", +\(extra)" : "")
    }

    private func connectionRow(
        icon: String, title: String, detail: String, target: UInt64
    ) -> some View {
        Button {
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            if flags.contains(.command) || flags.contains(.control) {
                NotificationCenter.default.post(name: .lotusOpenEntity, object: target)
            } else {
                selection = target
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 10))
                Text(title).font(.system(size: 12)).lineLimit(1)
                Spacer(minLength: 6)
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.mutedFg)
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 13)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open · ⌘-click for a background tab")
    }

    /// A read-only system row (created/edited in the blueprint's MORE) —
    /// no kbd, no menu, never editable.
    private func systemRow(icon: String, name: String, value: String) -> some View {
        HStack(spacing: 7) {
            KeyCap(label: "·", visible: hintsVisible, blank: true)
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 12))
                Text(name)
            }
            .font(.system(size: 12))
            .foregroundColor(Theme.mutedFg)
            .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(Theme.mutedFg)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
        .frame(minHeight: 30)
    }

    private var hintsVisible: Bool {
        switch DigitHintVisibility.current {
        case .always: return true
        case .hover: return hoveringPane || InspectorFocus.shared.active
        case .off: return false
        }
    }

    // MARK: choreography (§2.3)

    private func handle(_ key: String) {
        guard let entity = model.entity(selection) else { return }
        switch key {
        case "focus": focusPanel(entity)
        case "blur": blur()
        case "Escape":
            if editingRow != nil { editingRow = nil } else { blur() }
        case "Up": step(-1, in: entity)
        case "Down": step(1, in: entity)
        case "M": withAnimation(Theme.springFast) { moreOpen.toggle() }
        case "N":
            focusedRow = Self.newRowId
            editingRow = Self.newRowId
        case "H":
            if let focused = focusedRow, focused != Self.newRowId,
                isVisible(focused, in: entity)
            {
                menuRow = focused
            } else {
                NSSound.beep()
            }
        case "F2": renamePrompt(entity)
        case "Return":
            if focusedRow == Self.newRowId {
                editingRow = Self.newRowId
            } else if let spec = spec(of: focusedRow, in: entity) {
                beginEdit(spec)
            }
        case "Space":
            if let spec = spec(of: focusedRow, in: entity),
                spec.property.kind == "datetime"
            {
                cycleRole(spec, entity: entity)
            }
        default:
            jump(toKey: key, in: entity)
        }
    }

    private func focusPanel(_ entity: EntityRow) {
        if !scopePushed {
            CommandRegistry.shared.pushCaptureScope(allowing: InspectorCommands.scopeIds)
            scopePushed = true
        }
        InspectorFocus.shared.active = true
        if focusedRow == nil {
            let placement = placement(for: entity)
            // lastEdited is only a valid landing spot if that row still
            // exists on THIS entity — it leaks across a selection change
            // otherwise (the review's finding), landing focus on a ghost.
            let restored = lastEdited.flatMap { id in
                (placement.core + placement.taskFields).first { $0.id == id }?.id
            }
            focusedRow = restored ?? placement.core.first?.id
                ?? placement.taskFields.first?.id ?? Self.newRowId
        }
    }

    /// Is this row currently mounted? Core/task rows always are; a MORE row
    /// only while MORE is open; the add-property sentinel always. Used to
    /// keep H/⏎ from addressing an unmounted row whose editor/menu nothing
    /// could then dismiss (the keyboard-deadlock finding).
    private func isVisible(_ id: UInt64, in entity: EntityRow) -> Bool {
        if id == Self.newRowId { return true }
        let placement = placement(for: entity)
        if placement.core.contains(where: { $0.id == id }) { return true }
        if placement.taskFields.contains(where: { $0.id == id }) { return true }
        return moreOpen && placement.more.contains { $0.id == id }
    }

    /// When MORE folds shut under a focus that was sitting inside it, move
    /// focus to a still-mounted row and drop any editor/menu bound to the
    /// row that just unmounted — else editorOpen stays wedged true and the
    /// panel keyboard deadlocks (the review's medium).
    private func reconcileFocusAfterFold() {
        guard !moreOpen, let focused = focusedRow, focused != Self.newRowId,
            let entity = model.entity(selection), !isVisible(focused, in: entity)
        else { return }
        let placement = placement(for: entity)
        editingRow = nil
        menuRow = nil
        materialized = nil
        focusedRow = placement.core.last?.id
            ?? placement.taskFields.last?.id ?? Self.newRowId
    }

    private func blur() {
        editingRow = nil
        menuRow = nil
        focusedRow = nil
        materialized = nil
        lastEdited = nil
        if scopePushed {
            CommandRegistry.shared.popCaptureScope()
            scopePushed = false
        }
        InspectorFocus.shared.active = false
    }

    /// Digit / task-letter jump: focus the mapped row AND open its editor,
    /// unfolding MORE (or materializing a hidden row) on the way (badge 14).
    private func jump(toKey key: String, in entity: EntityRow) {
        let keys = resolvedKeys()
        guard let name = keys.first(where: { $0.value == key.uppercased() })?.key,
            let prop = model.properties().first(where: { $0.name == name })
        else {
            NSSound.beep()
            return
        }
        reveal(prop.id)
        if let spec = spec(of: prop.id, in: entity) { beginEdit(spec) }
    }

    private func step(_ delta: Int, in entity: EntityRow) {
        let ids = navigationIds(in: entity)
        guard !ids.isEmpty else { return }
        guard let current = focusedRow, let at = ids.firstIndex(of: current) else {
            focusedRow = delta > 0 ? ids.first : ids.last
            return
        }
        focusedRow = ids[max(0, min(ids.count - 1, at + delta))]
    }

    private func navigationIds(in entity: EntityRow) -> [UInt64] {
        let placement = placement(for: entity)
        var ids = placement.core.map(\.id)
        ids.append(Self.newRowId)
        ids += placement.taskFields.map(\.id)
        if moreOpen { ids += placement.more.map(\.id) }
        return ids
    }

    private func spec(of id: UInt64?, in entity: EntityRow) -> InspectorRowSpec? {
        guard let id, id != Self.newRowId else { return nil }
        let placement = placement(for: entity)
        return (placement.core + placement.taskFields + placement.more)
            .first { $0.id == id }
    }

    /// What ⏎ / a digit landing means per value kind: text-shaped rows
    /// edit inline; bool toggles; status/pool/date rows open their
    /// anchored popovers (§2.4); `type` and file rows refuse (deferred).
    private func beginEdit(_ spec: InspectorRowSpec) {
        // Never open an editor for a row that isn't on screen — its popover
        // would have nothing to anchor to and nothing to dismiss it.
        if let entity = model.entity(selection), !isVisible(spec.id, in: entity) {
            NSSound.beep()
            return
        }
        focusedRow = spec.id
        switch rowEditor(for: spec.property) {
        case .inline, .status, .pool, .date:
            editingRow = spec.id
        case .toggle:
            guard let id = selection else { return }
            let on = spec.cells.first.map { $0.value == "yes" || $0.value == "true" } ?? false
            model.set(id, property: spec.property.name, value: on ? "false" : "true")
            lastEdited = spec.id
        case .none:
            NSSound.beep()
        }
    }

    private func cycleRole(_ spec: InspectorRowSpec, entity: EntityRow) {
        model.cycleDateRole(id: entity.id, property: spec.property.name) { newRole in
            editingRow = nil
            guard let newRole,
                let target = model.properties().first(where: { $0.name == newRole })
            else { return }  // refusal already beeped
            // The cycle MOVED the value to the next role's property — the
            // row disappears here and appears there; focus follows it.
            reveal(target.id)
            lastEdited = target.id
        }
    }

    /// Focus one definition's row wherever the law placed it, unfolding
    /// MORE or materializing a hidden row on the way.
    private func reveal(_ propertyId: UInt64) {
        guard let entity = model.entity(selection) else { return }
        let placement = placement(for: entity)
        let inCore = placement.core.contains { $0.id == propertyId }
        let inTask = placement.taskFields.contains { $0.id == propertyId }
        if !inCore && !inTask {
            if !placement.more.contains(where: { $0.id == propertyId }) {
                materialized = propertyId
            }
            withAnimation(Theme.springFast) { moreOpen = true }
        }
        focusedRow = propertyId
    }

    private func renamePrompt(_ entity: EntityRow) {
        Dialogs.shared.prompt(
            "Rename", initial: entity.title, confirmLabel: "Rename"
        ) { name in
            guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty
            else { return }
            model.set(entity.id, property: "name", value: name)
        }
    }

    /// Badge 3: immediate trash, NO confirm — the undo affordance and
    /// ⌘⌥Z are the safety net.
    private func trash(_ entity: EntityRow) {
        let title = entity.title.isEmpty ? "Untitled" : entity.title
        model.trash(entity.id) { ok in
            guard ok else { return }
            undoOffer = title
            undoGeneration += 1
            let generation = undoGeneration
            selection = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                if undoGeneration == generation { undoOffer = nil }
            }
        }
    }
}

// MARK: - the header (.ohd)

struct ObjectHeader: View {
    @ObservedObject var model: BoxModel
    let entity: EntityRow
    var rename: () -> Void
    var trash: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            kindTile
            VStack(alignment: .leading, spacing: 1) {
                Text(entity.title.isEmpty ? "Untitled" : entity.title)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(entity.title.isEmpty ? .secondary : .primary)
                    .lineLimit(2)
                    .contentShape(Rectangle())
                    .onTapGesture { rename() }
                    .help("Rename (F2)")
                Text(subline)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.mutedFg)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 1) {
                addToListMenu
                // 🔖 = a PIN now (P17g, one pin source): the row appears in
                // Spaces › Favourites, ordered; unpin trashes the pin.
                headerAction(
                    model.isPinned(entity.id) ? "bookmark.fill" : "bookmark",
                    model.isPinned(entity.id) ? "Unpin from Favourites" : "Pin to Favourites",
                    active: model.isPinned(entity.id)
                ) {
                    if model.isPinned(entity.id) {
                        model.unpin(entity.id)
                    } else {
                        model.pin(entity.id)
                    }
                }
                headerAction(
                    entity.archived ? "archivebox.fill" : "archivebox",
                    entity.archived ? "Unarchive" : "Archive",
                    active: entity.archived
                ) {
                    model.set(
                        entity.id, property: "archived",
                        value: entity.archived ? "false" : "true")
                }
                headerAction("trash", "Move to Trash (undoable)", active: false) {
                    trash()
                }
            }
        }
        .padding(.init(top: 11, leading: 12, bottom: 8, trailing: 12))
    }

    /// The 26pt rounded kind tile: accent tint + kind symbol; a person
    /// renders initials (bp1:417).
    @ViewBuilder
    private var kindTile: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Theme.accentTint)
            .frame(width: 26, height: 26)
            .overlay {
                if entity.kinds.contains("person") {
                    Text(initials)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.accent)
                } else {
                    Image(systemName: rowKindIcon(entity))
                        .font(.system(size: 12))
                        .foregroundColor(Theme.accent)
                }
            }
    }

    private var initials: String {
        let words = entity.title.split(separator: " ").prefix(2)
        let letters = words.compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    /// `kind · type · anchoring-context` — mirrors the rows below, never
    /// editable (badge 2).
    private var subline: String {
        var parts: [String] = [entity.kinds.first ?? "object"]
        if let type = cellValue("type"), !type.isEmpty { parts.append(type) }
        if let project = cellValue("project"), !project.isEmpty {
            parts.append("in \(project.split(separator: "/").last.map(String.init) ?? project)")
        } else if let area = cellValue("area"), !area.isEmpty {
            parts.append("in \(area)")
        } else {
            parts.append("no project")
        }
        return parts.joined(separator: " · ")
    }

    private func cellValue(_ name: String) -> String? {
        entity.cells.first { $0.property == name }?.value
    }

    private var allLists: [EntityRow] {
        model.rows(model.snap?.everything ?? []).filter { $0.kinds.contains("list") }
    }
    private func isMember(of list: EntityRow) -> Bool {
        list.cells.contains { $0.property == "related" && $0.refTarget == entity.id }
    }

    // The 9b gesture, kept verbatim: lotus's Relate affordance rides the
    // header (design §2.1).
    @ViewBuilder private var addToListMenu: some View {
        let lists = allLists.filter { $0.id != entity.id }
        let onAny = lists.contains { isMember(of: $0) }
        Menu {
            if lists.isEmpty { Text("No lists yet") }
            ForEach(lists) { list in
                let member = isMember(of: list)
                Button {
                    if member { model.removeMember(list.id, entity.id) }
                    else { model.addMember(list.id, entity.id) }
                } label: {
                    if member {
                        Label(listTitle(list), systemImage: "checkmark")
                    } else {
                        Text(listTitle(list))
                    }
                }
            }
            Divider()
            Button {
                Dialogs.shared.prompt(
                    "New list", message: "Create a list and add this to it.",
                    placeholder: "List name", confirmLabel: "Create"
                ) { name in
                    let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    model.createList(trimmed) { newId in
                        if let newId = newId { model.addMember(newId, entity.id) }
                    }
                }
            } label: {
                Label("New list & add…", systemImage: "plus")
            }
        } label: {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 12))
                .foregroundColor(onAny ? Theme.accent : Theme.mutedFg)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Add to list")
    }

    private func listTitle(_ list: EntityRow) -> String {
        list.title.isEmpty ? "Untitled list" : list.title
    }

    private func headerAction(
        _ symbol: String, _ help: String, active: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundColor(active ? Theme.accent : Theme.mutedFg)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - section header (.sect)

struct InspectorSect: View {
    let title: String
    var aft: String? = nil

    var body: some View {
        HStack(spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .kerning(0.7)
            Spacer(minLength: 0)
            if let aft {
                Text(aft)
                    .font(.system(size: 11))
                    .textCase(nil)
                    .kerning(0)
            }
        }
        .foregroundColor(Theme.mutedFg)
        .padding(.init(top: 9, leading: 13, bottom: 2, trailing: 13))
    }
}

// MARK: - the key cap (.kbd)

struct KeyCap: View {
    let label: String
    var visible = true
    var blank = false
    var accent = false

    var body: some View {
        Group {
            if visible {
                Text(label)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(
                        accent ? Theme.accent : blank ? Theme.mutedFg : .secondary
                    )
                    .frame(minWidth: 17, minHeight: 17)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(
                                accent
                                    ? Theme.accent
                                    : Color(nsColor: .separatorColor),
                                style: StrokeStyle(lineWidth: 1, dash: blank ? [2, 2] : []))
                    )
            } else {
                Color.clear.frame(width: 17, height: 17)
            }
        }
        .frame(width: 20, alignment: .leading)
    }
}

// MARK: - one row (.krow) — grid 20 · 84 · 1fr · 16 at 7pt gaps (§2.2)

struct PropertyRowView: View {
    @ObservedObject var model: BoxModel
    let entity: EntityRow
    let spec: InspectorRowSpec
    let focused: Bool
    let editing: Bool
    /// The anchored editor (11.5g): pane-owned presentation state.
    var editorPresented: Binding<Bool>
    /// The ⋯ row menu (11.5h): pane-owned so H can open it too.
    var menuPresented: Binding<Bool>
    let hints: Bool
    let inMore: Bool
    var onFocus: () -> Void
    var onBeginEdit: () -> Void
    /// `committed` = a write happened (tracks last-edited for Alt+→).
    var onEndEdit: (Bool) -> Void
    var onCycleRole: () -> Void

    @State private var hovering = false

    /// Values whose hue never comes from VALUE_HEX (the frozen color
    /// budget): status dots use option hue; these render neutral.
    private static let neverHue: Set<String> = ["status", "priority", "tier", "type"]

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            KeyCap(
                label: spec.key ?? "·", visible: hints,
                blank: spec.key == nil, accent: focused)
            HStack(spacing: 7) {
                Image(systemName: propertySymbol)
                    .font(.system(size: 12))
                Text(displayName)
                    .lineLimit(1)
            }
            .font(.system(size: 12))
            .foregroundColor(inMore ? Theme.mutedFg : .secondary)
            .frame(width: 84, alignment: .leading)
            valueCell
                .frame(maxWidth: .infinity, alignment: .leading)
            rowMenu
        }
        .padding(.horizontal, 7)
        .frame(minHeight: focused ? 36 : 30)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(focused ? Theme.accentTint : hovering ? Color.secondary.opacity(0.07) : Color.clear))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(focused ? Theme.accent : Color.clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture { onFocus() }
        .onHover { hovering = $0 }
        .popover(isPresented: editorPresented, arrowEdge: .leading) {
            popoverEditor
        }
        .popover(isPresented: menuPresented, arrowEdge: .leading) {
            RowMenuPopover(
                model: model, entity: entity, spec: spec,
                onDone: { menuPresented.wrappedValue = false })
        }
        // Right-click = the same menu (entry 700's third doorway).
        .contextMenu {
            Button("Property menu…") {
                onFocus()
                menuPresented.wrappedValue = true
            }
        }
    }

    /// The anchored editor by row kind (§2.4) — one popover shape, edge
    /// toward the content pane.
    @ViewBuilder
    private var popoverEditor: some View {
        switch rowEditor(for: spec.property) {
        case .status:
            StatusPickerPopover(
                model: model, entity: entity, spec: spec,
                onDone: { onEndEdit($0) })
        case .pool:
            ValuePoolPopover(
                model: model, entity: entity, spec: spec,
                onDone: { onEndEdit($0) })
        case .date:
            DateEditorPopover(
                model: model, entity: entity, spec: spec,
                onCycleRole: onCycleRole,
                onDone: { onEndEdit($0) })
        default:
            EmptyView()
        }
    }

    private var displayName: String {
        // The blueprint compresses the one long core label (bp1: "descr.").
        spec.property.name == "description" ? "descr." : spec.property.name
    }

    /// The key cell's symbol: an `icon` display attribute on the definition
    /// wins; else the name/kind default (§3.1's three-layer law).
    private var propertySymbol: String {
        if let icon = spec.property.icon, !icon.isEmpty { return icon }
        switch spec.property.name {
        case "form": return "square.3.layers.3d"
        case "type": return "textformat"
        case "subjects": return "tag"
        case "project": return "folder"
        case "area": return "square.grid.2x2"
        case "people": return "person.2"
        case "tier": return "number"
        case "date", "due": return "calendar"
        case "status", "priority": return "flag"
        case "description": return "text.alignleft"
        case "recurrence": return "repeat"
        case "email": return "at"
        case "phone": return "phone"
        case "role": return "person.text.rectangle"
        case "org": return "building.2"
        case "sources", "related": return "link"
        default:
            switch spec.property.kind {
            case "number": return "number"
            case "datetime": return "calendar"
            case "bool": return "checkmark.square"
            case "select": return "flag"
            case "reference": return "link"
            case "tag": return "tag"
            case "file": return "paperclip"
            default: return "textformat"
            }
        }
    }

    // MARK: value dispatch (§2.2)

    @ViewBuilder
    private var valueCell: some View {
        if editing {
            InlineCellEditor(
                model: model, entityId: entity.id, spec: spec, onDone: onEndEdit)
        } else if spec.isEmpty {
            emptyValue
        } else {
            switch spec.property.kind {
            case "bool":
                boolValue
            case "select":
                selectValue
            case "datetime":
                dateValue
            case "reference", "tag":
                chips
            default:
                textValue
            }
        }
    }

    @ViewBuilder
    private var emptyValue: some View {
        if inMore {
            // A folded base-core row resting empty (bp1 task tab: "—").
            Text("—")
                .font(.system(size: 12))
                .foregroundColor(Theme.mutedFg)
        } else if spec.property.kind == "bool" {
            Button { toggleBool() } label: { ghost(ghostLabel) }
                .buttonStyle(.plain)
        } else {
            Button {
                onFocus()
                onBeginEdit()
            } label: {
                ghost(ghostLabel)
            }
            .buttonStyle(.plain)
        }
    }

    private var ghostLabel: String {
        switch spec.property.name {
        case "status": return "set status"
        case "project": return "add to project"
        case "recurrence": return "off"
        default: return "add \(displayName)"
        }
    }

    /// The dashed ghost CTA (badge 11: zero fill-pressure — empty reads
    /// as valid, not as a form to complete).
    private func ghost(_ label: String) -> some View {
        HStack(spacing: 4) {
            if label != "off" {
                Image(systemName: "plus").font(.system(size: 9))
            }
            Text(label).font(.system(size: 11))
        }
        .foregroundColor(Theme.mutedFg)
        .padding(.horizontal, 8)
        .padding(.vertical, 1.5)
        .overlay(
            Capsule().strokeBorder(
                Color(nsColor: .separatorColor),
                style: StrokeStyle(lineWidth: 1, dash: [3, 2.5])))
        .contentShape(Capsule())
    }

    private var boolValue: some View {
        let on = spec.cells.first.map { $0.value == "yes" || $0.value == "true" } ?? false
        return Button { toggleBool() } label: {
            Image(systemName: on ? "checkmark" : "square")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(on ? Color(nsColor: .systemGreen) : Theme.mutedFg)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleBool() {
        let on = spec.cells.first.map { $0.value == "yes" || $0.value == "true" } ?? false
        model.set(entity.id, property: spec.property.name, value: on ? "false" : "true")
        onEndEdit(true)
    }

    /// A select value: click opens the anchored picker (status gets the
    /// vocabulary dot beside its name).
    private var selectValue: some View {
        let value = spec.cells.first?.value ?? ""
        return Button {
            onFocus()
            onBeginEdit()
        } label: {
            Group {
                if spec.property.name == "status" {
                    // A neutral chip framing the statusdot + name (bp1 task
                    // tab: <span class=chip><span class=statusdot>waiting).
                    HStack(spacing: 5) {
                        StatusDot(
                            option: spec.property.options.first { $0.name == value },
                            statusName: value)
                        Text(value).font(.system(size: 11))
                    }
                    .foregroundColor(Color(nsColor: .secondaryLabelColor))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(Color.secondary.opacity(0.10)))
                    .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.30), lineWidth: 0.5))
                } else {
                    Text(value)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The date row: role pill (solid accent = positions the entity on the
    /// calendar; dashed muted = lookup), the date (a span as start → end),
    /// and the `.rec` tag when this row anchors the recurrence (§2.2).
    @ViewBuilder
    private var dateValue: some View {
        let isPositioning = entity.positionedBy == spec.property.name
        HStack(spacing: 5) {
            Button(action: onCycleRole) {
                // The pill ALWAYS names the concrete role (due/valid-until/
                // occurred/purchased-on); solid accent vs dashed muted is
                // what signals positioning (bp1:310/555 — "lookup" is only
                // the popover's aft label, never the pill).
                Text(spec.property.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isPositioning ? Theme.accent : Theme.mutedFg)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(isPositioning ? Theme.accentTint : Color.clear))
                    .overlay(
                        Capsule().strokeBorder(
                            isPositioning ? Color.clear : Color(nsColor: .separatorColor),
                            style: StrokeStyle(lineWidth: 1, dash: isPositioning ? [] : [3, 2.5]))
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Cycle date role (Space)")
            Text(dateText(isPositioning: isPositioning))
                .font(.system(size: 12).monospacedDigit())
                .foregroundColor(.primary)
            if isPositioning,
                let rec = entity.cells.first(where: { $0.property == "recurrence" })?.value,
                !rec.isEmpty
            {
                HStack(spacing: 3) {
                    Image(systemName: "repeat").font(.system(size: 9))
                    Text(rec).font(.system(size: 11))
                }
                .foregroundColor(Theme.mutedFg)
            }
        }
    }

    private func dateText(isPositioning: Bool) -> String {
        if isPositioning, let due = entity.due {
            var text = Civil.text(due, dateOnly: entity.dueDateOnly)
            if let end = entity.dueEnd {
                text += " → \(Civil.text(end, dateOnly: entity.dueDateOnly))"
            }
            return text
        }
        return spec.cells.first?.value ?? ""
    }

    private var chips: some View {
        // Wrap-free chip run; VALUE_HEX per value, neutral for the
        // never-hue classes (frozen law). Clicking opens the pool —
        // except `type`, whose editor waits for the schema pass.
        let editable = rowEditor(for: spec.property) != RowEditor.none
        return HStack(spacing: 5) {
            ForEach(spec.cells, id: \.self) { cell in
                ValueChip(
                    text: chipText(cell),
                    hue: Self.neverHue.contains(spec.property.name)
                        ? nil : Hues.valueHex(chipText(cell)),
                    tap: editable ? { onFocus(); onBeginEdit() } : nil)
            }
        }
    }

    private func chipText(_ cell: CellRow) -> String {
        // Project chips display the leaf only (badge 9).
        if spec.property.name == "project" {
            return cell.value.split(separator: "/").last.map(String.init) ?? cell.value
        }
        return cell.value
    }

    @ViewBuilder
    private var textValue: some View {
        let value = spec.cells.map(\.value).filter { !$0.isEmpty }.joined(separator: " · ")
        let isDescription = spec.property.name == "description"
        let isMono = ["email", "phone", "url"].contains(spec.property.name)
        Text(value)
            .font(.system(size: isDescription ? 11.5 : 12, design: isMono ? .monospaced : .default))
            .foregroundColor(isDescription || inMore ? Theme.mutedFg : .primary)
            .lineLimit(isDescription ? 2 : 1)
            .contentShape(Rectangle())
            .onTapGesture {
                onFocus()
                onBeginEdit()
            }
    }

    /// The ⋯ cell: opacity 0 at rest, fades on hover. In the static slice
    /// it carries the one per-object action; the display-attribute items
    /// arrive with 11.5h.
    private var rowMenu: some View {
        Button {
            onFocus()
            menuPresented.wrappedValue = true
        } label: {
            Text("⋯")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Theme.mutedFg)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(hovering ? 1 : 0)
        .help("Row menu (H)")
    }
}

/// Commit-on-Return/blur inline editor for text/number/datetime rows —
/// the P5 write contract kept verbatim (one commit per edit; a refused
/// value beeps and reverts).
struct InlineCellEditor: View {
    @ObservedObject var model: BoxModel
    let entityId: UInt64
    let spec: InspectorRowSpec
    var onDone: (Bool) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $draft)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .focused($focused)
            .onAppear {
                draft = spec.cells.first?.value ?? ""
                focused = true
            }
            .onSubmit { focused = false }
            .onExitCommand {
                draft = spec.cells.first?.value ?? ""
                focused = false
            }
            .onChange(of: focused) {
                if !focused { commit() }
            }
    }

    private func commit() {
        let stored = spec.cells.first?.value ?? ""
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        guard trimmed != stored else {
            onDone(false)
            return
        }
        if trimmed.isEmpty {
            if !stored.isEmpty { model.unset(entityId, property: spec.property.name) }
            onDone(!stored.isEmpty)
        } else {
            model.set(entityId, property: spec.property.name, value: trimmed) { ok in
                if !ok { NSSound.beep() }
                onDone(ok)
            }
        }
    }
}

// MARK: - the footbar (badge 32): the shortcut contract, always visible

struct InspectorFootbar: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                pair("⌥→", "panel")
                pair("⌥←", "doc")
                pair("↑↓", "fields")
                pair("⏎", "edit")
            }
            HStack(spacing: 8) {
                pair("⎋", "close")
                pair("H", "row menu")
                pair("M", "more")
            }
        }
        .padding(.init(top: 9, leading: 12, bottom: 9, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Divider(), alignment: .top)
    }

    private func pair(_ cap: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(cap)
                .font(.system(size: 10.5, design: .monospaced))
                .padding(.horizontal, 3)
                .frame(minWidth: 17, minHeight: 16)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
            Text(label).font(.system(size: 11))
        }
        .foregroundColor(Theme.mutedFg)
    }
}
