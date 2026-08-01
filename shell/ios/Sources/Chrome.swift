// liv iOS — the desk-first chrome (design/ios.md §6, revision 2): the body
// IS the desk (content tabs, the Obsidian idioms); features are transient
// windows summoned from the always-present menu button and presented OVER
// the whole chrome, bar included. The bar copies Obsidian's nav row:
// [features ^] ‹ › search + [tab count]. DeskModel is transient shell
// state — tabs persist per device in UserDefaults, never as cells.

import SwiftUI
import UIKit

/// Ink for solid amber fills (the desktop's onYellowInk).
private let chromeAmberInk = Color(red: 0x3A / 255, green: 0x2A / 255, blue: 0)

// MARK: - features

/// The lens roster. Calendar is a v1 placeholder — its body renders
/// EmptyHint("Calendar arrives with M3.") until M3.
enum Feature: String, CaseIterable, Identifiable {
    case today, everything, inbox, tasks, calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .everything: return "Everything"
        case .inbox: return "Inbox"
        case .tasks: return "Tasks"
        case .calendar: return "Calendar"
        }
    }

    var icon: String {
        switch self {
        case .today: return "sun.max"
        case .everything: return "tray.full"
        case .inbox: return "tray"
        case .tasks: return "checkmark.circle"
        case .calendar: return "calendar"
        }
    }
}

// MARK: - desk tabs

struct DeskTab: Identifiable {
    let id: UUID
    var content: DeskTabContent
}

enum DeskTabContent: Equatable {
    case new
    case entity(UInt64)
}

/// One capture-sheet presentation: the verb the door chose and the tab
/// that receives every entity committed this session (serial captures
/// reuse it — §6's tab-hygiene rule). The id is fresh per open so the
/// sheet's initial verb state can never be reused across presentations
/// (eval §5.5: "New task" opening on Idea mode).
struct CaptureRequest: Identifiable {
    let id = UUID()
    let verb: CaptureVerb
    let tabId: UUID
}

/// The chrome's one state object. Boots in Feature view on Today; the
/// desk keeps at least one tab alive at all times. Entity-tab ids + the
/// active index ride UserDefaults ("desk.tabs.v1.<workspace>"); ids missing
/// from the box are dropped LAZILY — the dead tab renders an EmptyHint,
/// never a crash and never an eager sweep against a box that may still be
/// opening.
///
/// M4: ONE tab plane whose open SET is remembered per workspace — never a
/// second tab bar (that was the old app's three-tab-system debt). Switching
/// workspace saves the current set and restores that workspace's; a
/// workspace with no saved set starts with one fresh `.new` tab, because
/// the desk is never empty.
final class DeskModel: ObservableObject {
    /// The feature window currently covering the chrome (sheet item);
    /// nil = the desk.
    @Published var featureShown: Feature?
    @Published private(set) var tabs: [DeskTab]
    @Published var activeTabId: UUID? {
        didSet { persist() }
    }
    @Published var switcherShown = false
    @Published var searchShown = false
    @Published var gridShown = false
    @Published var cameraShown = false
    /// The metadata inspector covers the active entity tab's body.
    /// Lifted to the model so DeskHost's floating chevron can drive it;
    /// reset on every tab move — metadata is a visit, not a mode.
    @Published var inspectorShown = UserDefaults.standard.bool(forKey: "desk.boot.inspector")
    /// The live capture sheet, presented by DeskHost — NOT by the .new tab
    /// body, which the first commit replaces (eval §5.2/§5.3).
    @Published var captureRequest: CaptureRequest?

    /// A just-born note whose editor should open with the caret already in
    /// it. Deliberately NOT @Published — it is consumed once by the editor
    /// that claims it, and a republish here would re-focus on every later
    /// visit to that tab.
    private var pendingFocus: UInt64?

    func requestFocus(_ id: UInt64) { pendingFocus = id }

    /// True exactly once, for the entity that was just created.
    func consumeFocus(_ id: UInt64) -> Bool {
        guard pendingFocus == id else { return false }
        pendingFocus = nil
        return true
    }

    /// Tab-activation history for the bar's ‹ › — device state, not cells.
    private var backIds: [UUID] = []
    private var forwardIds: [UUID] = []

    /// The workspace whose tab set is currently on the plane. 0 = "All".
    private(set) var workspaceId: UInt64 = 0

    /// The pre-M4 single-plane key. Migrated once into the All plane so no
    /// one loses their open tabs to this change.
    private static let legacyKey = "desk.tabs.v1"

    private var persistKey: String { WorkspaceModel.tabsKey(workspaceId) }

    var activeTab: DeskTab? {
        tabs.first { $0.id == activeTabId }
    }

    var canGoBack: Bool { backIds.contains { alive($0) } }
    var canGoForward: Bool { forwardIds.contains { alive($0) } }

    private func alive(_ id: UUID) -> Bool {
        tabs.contains { $0.id == id }
    }

    /// Activate a tab, recording history. Every activation path funnels
    /// here so ‹ › always tell the truth.
    func focus(_ tabId: UUID) {
        guard tabId != activeTabId else { return }
        if let current = activeTabId { backIds.append(current) }
        forwardIds.removeAll()
        activeTabId = tabId
        inspectorShown = false
        objectWillChange.send()
    }

    func goBack() {
        while let id = backIds.popLast() {
            guard alive(id) else { continue }
            if let current = activeTabId { forwardIds.append(current) }
            activeTabId = id
            objectWillChange.send()
            return
        }
    }

    func goForward() {
        while let id = forwardIds.popLast() {
            guard alive(id) else { continue }
            if let current = activeTabId { backIds.append(current) }
            activeTabId = id
            objectWillChange.send()
            return
        }
    }

    init() {
        // One-time migration: the old single plane becomes the All plane.
        let defaults = UserDefaults.standard
        if defaults.dictionary(forKey: WorkspaceModel.tabsKey(0)) == nil,
            let legacy = defaults.dictionary(forKey: Self.legacyKey)
        {
            defaults.set(legacy, forKey: WorkspaceModel.tabsKey(0))
        }
        workspaceId = UInt64(defaults.integer(forKey: WorkspaceModel.activeKey))
        let (restored, active) = Self.load(WorkspaceModel.tabsKey(workspaceId))
        tabs = restored
        activeTabId =
            restored.indices.contains(active) ? restored[active].id : restored.first?.id
    }

    /// One plane's saved set. Entity ids only — `.new` tabs are moments.
    /// An empty plane is one fresh `.new` tab: the desk is never empty.
    private static func load(_ key: String) -> ([DeskTab], Int) {
        var restored: [DeskTab] = []
        var active = -1
        if let stored = UserDefaults.standard.dictionary(forKey: key) {
            let ids = (stored["ids"] as? [String] ?? []).compactMap { UInt64($0) }
            restored = ids.map { DeskTab(id: UUID(), content: .entity($0)) }
            active = stored["active"] as? Int ?? -1
        }
        if restored.isEmpty { restored = [DeskTab(id: UUID(), content: .new)] }
        return (restored, active)
    }

    /// Swap the plane. The outgoing set is saved under ITS key first, so a
    /// switch is never a loss; the incoming set replaces the tabs whole and
    /// the ‹ › history resets — it belonged to the other workspace.
    func adopt(workspace id: UInt64) {
        guard id != workspaceId else { return }
        persist()  // the OUTGOING key — persistKey still points at it
        workspaceId = id
        let (restored, active) = Self.load(persistKey)
        backIds = []
        forwardIds = []
        tabs = restored
        activeTabId =
            restored.indices.contains(active) ? restored[active].id : restored.first?.id
        featureShown = nil
        switcherShown = false
        gridShown = false
        inspectorShown = false
        objectWillChange.send()
    }

    /// Focus the tab already holding this entity, or append one. Opening a
    /// row anywhere lands you at the desk — the desktop's rail→center
    /// gesture grammar.
    func open(_ entityId: UInt64) {
        if let existing = tabs.first(where: { $0.content == .entity(entityId) }) {
            focus(existing.id)
        } else {
            let tab = DeskTab(id: UUID(), content: .entity(entityId))
            tabs.append(tab)
            focus(tab.id)
        }
        featureShown = nil
        switcherShown = false
        gridShown = false
        // Search and the camera are covers too. A tapped reminder routes
        // here from anywhere, so leaving these up made the notification
        // look ignored: the tab was created and focused behind a cover the
        // user was still looking at, and closing it landed them on a tab
        // they never picked.
        searchShown = false
        cameraShown = false
        persist()
    }

    func newTab() {
        let tab = DeskTab(id: UUID(), content: .new)
        tabs.append(tab)
        focus(tab.id)
        featureShown = nil
        persist()
    }

    /// Closing the last tab leaves one fresh .new tab — the desk is never
    /// empty.
    func close(_ tabId: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        tabs.remove(at: index)
        if tabs.isEmpty {
            let fresh = DeskTab(id: UUID(), content: .new)
            tabs = [fresh]
            activeTabId = fresh.id
        } else if activeTabId == tabId {
            activeTabId = tabs[min(index, tabs.count - 1)].id
        }
        persist()
    }

    /// A .new tab became an entity tab (the capture door committed).
    func setContent(_ tabId: UUID, entity: UInt64) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        tabs[index].content = .entity(entity)
        persist()
    }

    /// Entity ids only — .new tabs are moments, not state worth restoring.
    /// Always to the CURRENT workspace's key: opening something from search
    /// or the inbox joins the current workspace's set, by construction.
    private func persist() {
        var ids: [String] = []
        var active = -1
        for tab in tabs {
            guard case .entity(let entity) = tab.content else { continue }
            if tab.id == activeTabId { active = ids.count }
            ids.append(String(entity))
        }
        UserDefaults.standard.set(
            ["ids": ids, "active": active], forKey: persistKey)
    }
}

// MARK: - the workspace switcher (M4)

/// The hub's sheet: All (no lens), every workspace, the saved filters, and
/// the new-workspace form. Switching swaps the desk's open tabs — one tab
/// plane, remembered per workspace.
struct WorkspaceSwitcher: View {
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var workspaces: WorkspaceModel
    @Environment(\.dismiss) private var dismiss

    @State private var composing = false
    /// nil while composing a NEW workspace; the id being edited otherwise.
    /// Editing exists because the box ships a seeded "Home" workspace: with
    /// a create-only form it could never become a workspace at all.
    @State private var editing: UInt64?
    @State private var draftName = ""
    @State private var draftQuery = ""
    @State private var composingFilter = false
    @State private var filterName = ""
    @State private var filterQuery = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Workspace")
                    .padding(.bottom, 4)
                choice(
                    name: "All", detail: "Everything — no lens, no stamp",
                    active: workspaces.activeId == 0, icon: "square.grid.2x2"
                ) {
                    choose(0)
                }
                ForEach(workspaces.workspaces) { ws in
                    choice(
                        name: ws.display, detail: queryDetail(ws),
                        active: workspaces.activeId == ws.id, icon: "house",
                        emoji: ws.emoji
                    ) {
                        choose(ws.id)
                    }
                    .contextMenu {
                        Button {
                            editing = ws.id
                            draftName = ws.display
                            draftQuery = workspaces.query(of: ws.id) ?? ""
                            composing = true
                        } label: {
                            Label("Edit name + query", systemImage: "slider.horizontal.3")
                        }
                        Button(role: .destructive) {
                            workspaces.forgetQuery(ws.id)
                            if workspaces.activeId == ws.id { choose(0, close: false) }
                            box.trashWorkspace(ws.id)
                        } label: {
                            Label("Trash workspace", systemImage: "trash")
                        }
                    }
                }
                if composing {
                    newWorkspaceForm
                } else {
                    addRow("New workspace…") {
                        editing = nil
                        draftName = ""
                        draftQuery = ""
                        composing = true
                    }
                }

                SectionLabel("Filters")
                    .padding(.top, 18)
                    .padding(.bottom, 4)
                ForEach(workspaces.filters) { view in
                    choice(
                        name: view.display, detail: view.query ?? "",
                        active: workspaces.activeFilterId == view.id,
                        icon: "line.3.horizontal.decrease"
                    ) {
                        workspaces.activeFilterId =
                            workspaces.activeFilterId == view.id ? nil : view.id
                    }
                }
                if composingFilter {
                    newFilterForm
                } else {
                    addRow("New filter…") { composingFilter = true }
                }

            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .background(LivTheme.canvas)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// The lens, read straight off the wire.
    private func queryDetail(_ ws: WorkspaceRow) -> String {
        workspaces.query(of: ws.id) ?? "no query"
    }

    private func choose(_ id: UInt64, close: Bool = true) {
        workspaces.setActive(id)
        if close { dismiss() }
    }

    /// A workspace's own emoji leads its row (the furnished areas each
    /// carry one); the SF Symbol is the emoji-less fallback.
    private func choice(
        name: String, detail: String, active: Bool, icon: String,
        emoji: String? = nil, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let emoji, !emoji.isEmpty {
                    Text(emoji)
                        .font(.system(size: 13))
                        .frame(width: 18)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(active ? LivTheme.accent : LivTheme.text3)
                        .frame(width: 18)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 13.5, weight: active ? .semibold : .regular))
                        .foregroundStyle(active ? LivTheme.accent : LivTheme.text)
                        .lineLimit(1)
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(LivTheme.text3)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                if active {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(LivTheme.accent)
                }
            }
            .frame(minHeight: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
        }
    }

    private func addRow(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 18)
                Text(label).font(.system(size: 13))
                Spacer()
            }
            .foregroundStyle(LivTheme.accent)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: the new-workspace form — name + query + the stamp hint

    private var newWorkspaceForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            field("Name", text: $draftName, mono: false)
            field("Query — e.g. area:Work", text: $draftQuery, mono: true)
            Text(stampHint(draftQuery))
                .font(.system(size: 10.5))
                .foregroundStyle(
                    LivQuery.parse(draftQuery).stampCells.isEmpty
                        ? LivTheme.muted : LivTheme.accent)
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") {
                    composing = false
                    editing = nil
                }
                .font(.system(size: 12))
                .foregroundStyle(LivTheme.text3)
                .buttonStyle(.plain)
                Button(action: saveWorkspace) {
                    Text(editing == nil ? "Create" : "Save")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(LivTheme.onAccent)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(Capsule().fill(LivTheme.accent))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(trimmed(draftName).isEmpty)
                .opacity(trimmed(draftName).isEmpty ? 0.45 : 1)
            }
        }
        .padding(.vertical, 10)
    }

    private var newFilterForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            field("Name", text: $filterName, mono: false)
            field("Query — e.g. has:due -status:done", text: $filterQuery, mono: true)
            Text("A filter only filters — it never stamps.")
                .font(.system(size: 10.5))
                .foregroundStyle(LivTheme.muted)
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { composingFilter = false }
                    .font(.system(size: 12))
                    .foregroundStyle(LivTheme.text3)
                    .buttonStyle(.plain)
                Button(action: createFilter) {
                    Text("Save")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(LivTheme.onAccent)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(Capsule().fill(LivTheme.accent))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(trimmed(filterName).isEmpty || trimmed(filterQuery).isEmpty)
                .opacity(
                    trimmed(filterName).isEmpty || trimmed(filterQuery).isEmpty ? 0.45 : 1)
            }
        }
        .padding(.vertical, 10)
    }

    private func field(_ prompt: String, text: Binding<String>, mono: Bool) -> some View {
        TextField(prompt, text: text)
            .font(.system(size: 13, design: mono ? .monospaced : .default))
            .foregroundStyle(LivTheme.text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: LivTheme.radiusSm).fill(LivTheme.panel))
            .overlay(
                RoundedRectangle(cornerRadius: LivTheme.radiusSm)
                    .strokeBorder(LivTheme.border, lineWidth: 0.5)
            )
    }

    /// The honesty line: exactly what a capture in this workspace inherits.
    private func stampHint(_ query: String) -> String {
        let parsed = LivQuery.parse(query)
        let summary = parsed.stampSummary
        if !summary.isEmpty { return summary }
        return parsed.isInert
            ? "Stamps nothing — plain key:value terms are what stamp."
            : "Filters only — no plain key:value term to stamp."
    }

    private func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Birth (or re-aim) the workspace: write its `query` cell, and mint any
    /// property the stamp names but the box has never seen — `set` REFUSES
    /// an unknown property name, so without this the stamp would silently do
    /// nothing. One serial lane, so these land in order.
    private func saveWorkspace() {
        let name = trimmed(draftName)
        let query = trimmed(draftQuery)
        guard !name.isEmpty else { return }
        if let id = editing {
            box.set(id, "name", name)
            write(query, to: id)
            finish(id)
        } else {
            box.createWorkspace(name: name) { id in
                guard id != 0 else { return }
                write(query, to: id)
                finish(id)
            }
        }
    }

    /// The `query` cell IS the workspace. An emptied query clears the cell
    /// rather than leaving a stale lens behind.
    private func write(_ query: String, to id: UInt64) {
        if query.isEmpty {
            box.unset(id, "query")
        } else {
            box.set(id, "query", query)
            for cell in LivQuery.parse(query).stampCells where cell.property != "type" {
                box.addProperty(cell.property)
            }
        }
        workspaces.rememberQuery(id, query)
    }

    private func finish(_ id: UInt64) {
        draftName = ""
        draftQuery = ""
        composing = false
        editing = nil
        choose(id)
    }

    private func createFilter() {
        let name = trimmed(filterName)
        let query = trimmed(filterQuery)
        guard !name.isEmpty, !query.isEmpty else { return }
        box.createView(name: name, query: query) { id in
            guard id != 0 else { return }
            filterName = ""
            filterQuery = ""
            composingFilter = false
            workspaces.activeFilterId = id
        }
    }
}

// MARK: - settings (relocated from Today's header; the chrome owns the gear)

/// Facts and notes — plus the ONE schema door (§10): Fields, where a new
/// property definition is minted. Settings still never writes cells on
/// entities; the inspector's old "+ property" moved here because schema
/// growth is possible, not daily use. The Handoff section
/// (design/ios.md §2.2) is the funnel's honesty surface: the status card,
/// the per-item Pending/Shipped/Delivered ledger, "Ship now", and the
/// satellite-path row (dev-grade paste field — file pickers arrive with
/// the real Xcode project). Setting the path is device config, not a cell.
struct SettingsSheet: View {
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var outbox: Outbox
    @ObservedObject private var notify = Notify.shared
    @State private var pathDraft = ""
    @State private var addingField = false
    @State private var fieldDraft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Settings")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(LivTheme.text)
                    .padding(.bottom, 4)
                SectionLabel("Box")
                Text(box.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(LivTheme.text2)
                    .textSelection(.enabled)
                Text("\(box.snap?.entities?.count ?? 0) entities")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(LivTheme.text3)
                SectionLabel("Fields")
                    .padding(.top, 10)
                fieldsRow
                SectionLabel("Notifications")
                    .padding(.top, 10)
                notifyRows
                SectionLabel("Handoff")
                    .padding(.top, 10)
                statusCard
                ledger
                shipRow
                satellitePathRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(LivTheme.surface)
        // Read-only refresh: acks on disk become Delivered chips.
        .onAppear { outbox.scanAcks() }
    }

    // The Fields door (§10): the schema the box holds, and the ONE place a
    // new field is born. Relocated from the inspector's "+ property" row —
    // adding a kind of field is possible, never in the flow of daily use.

    /// The box's field vocabulary, usage-desc, off the live snapshot.
    private var fieldNames: [String] {
        (box.snap?.properties ?? [])
            .sorted { ($0.usage ?? 0) > ($1.usage ?? 0) }
            .compactMap { $0.name }
            .filter { !$0.isEmpty }
    }

    @ViewBuilder private var fieldsRow: some View {
        if !fieldNames.isEmpty {
            Text(fieldNames.joined(separator: " · "))
                .font(.system(size: 11))
                .foregroundStyle(LivTheme.text3)
                .lineLimit(3)
        }
        if addingField {
            HStack(spacing: 8) {
                TextField("Name the new field", text: $fieldDraft)
                    .font(.system(size: 12))
                    .foregroundStyle(LivTheme.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(createField)
                Button("Create", action: createField)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(fieldDraftReady ? LivTheme.accent : LivTheme.muted)
                    .buttonStyle(.plain)
                    .disabled(!fieldDraftReady)
                Button {
                    addingField = false
                    fieldDraft = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(LivTheme.text3)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: LivTheme.radiusSm).fill(LivTheme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LivTheme.radiusSm)
                    .strokeBorder(LivTheme.border, lineWidth: 0.5)
            )
        } else {
            Button {
                addingField = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Add your own field…")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(LivTheme.accent)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add your own field")
        }
    }

    private var fieldDraftReady: Bool {
        let name = fieldDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        // Minting a duplicate is refused by the core anyway; disable the
        // button rather than offer a refusal.
        return !fieldNames.contains {
            $0.compare(name, options: .caseInsensitive) == .orderedSame
        }
    }

    /// Births a TEXT property — the same implicit kind the inspector's old
    /// flow assumed. Other kinds stay a desktop/CLI affair for now.
    private func createField() {
        let name = fieldDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard fieldDraftReady else { return }
        box.addProperty(name) { id in
            guard id != 0 else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            fieldDraft = ""
            addingField = false
        }
    }

    // The Notifications section (M5, Notify.swift): master toggle, the two
    // per-kind lead pickers, and the 64-cap honesty line. All DEVICE state
    // (UserDefaults) — Settings never writes cells. Every change rebuilds
    // the pending queue from the snapshot in hand. Quiet hours: DEFERRED —
    // reminders currently ring at any hour.

    @ViewBuilder private var notifyRows: some View {
        Toggle(isOn: notifyEnabled) {
            Text("Due reminders")
                .font(.system(size: 13))
                .foregroundStyle(LivTheme.text)
        }
        .tint(LivTheme.accent)
        .frame(minHeight: 30)
        if notify.enabled {
            leadRow("Tasks", selection: notifyLead(\.taskLead))
            leadRow("Events", selection: notifyLead(\.eventLead))
            Text(notifyCountLine)
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(notify.denied ? LivTheme.red : LivTheme.muted)
        }
    }

    private func leadRow(_ label: String, selection: Binding<NotifyLead>) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(LivTheme.text2)
                .frame(width: 44, alignment: .leading)
            Picker(label, selection: selection) {
                ForEach(NotifyLead.allCases) { lead in
                    Text(lead.label).tag(lead)
                }
            }
            .pickerStyle(.segmented)
        }
        .frame(minHeight: 30)
    }

    private var notifyEnabled: Binding<Bool> {
        Binding(
            get: { notify.enabled },
            set: {
                notify.enabled = $0
                notify.rebuild(snapshot: box.snap, box: box)
            })
    }

    private func notifyLead(
        _ path: ReferenceWritableKeyPath<Notify, NotifyLead>
    ) -> Binding<NotifyLead> {
        Binding(
            get: { notify[keyPath: path] },
            set: {
                notify[keyPath: path] = $0
                notify.rebuild(snapshot: box.snap, box: box)
            })
    }

    /// The honesty line: what the queue actually holds, and the iOS cap
    /// that bounds it. A denial is stated, never papered over.
    private var notifyCountLine: String {
        if notify.denied {
            return "Notifications are off for Liv in iOS Settings."
        }
        var line = "\(notify.scheduledCount) scheduled · iOS caps at 64"
        if notify.droppedCount > 0 {
            line += " — soonest kept, \(notify.droppedCount) dropped"
        }
        return line
    }

    // The status card: honest counts, or the shipping-off notice.

    private static let shipDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:mm"
        return f
    }()

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 3) {
            if outbox.satellitePath == nil {
                Text("Shipping is off — set a satellite folder.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LivTheme.text)
                Text("Captures stay in this phone's own box until a folder is set.")
                    .font(.system(size: 11))
                    .foregroundStyle(LivTheme.text3)
            } else {
                Text(
                    outbox.pendingCount == 0
                        ? "Nothing waiting for your desk"
                        : "\(outbox.pendingCount) drop\(outbox.pendingCount == 1 ? "" : "s") waiting for your desk"
                )
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(LivTheme.text)
                Text(
                    outbox.lastShipDate.map {
                        "Last shipped \(Self.shipDate.string(from: $0))"
                    } ?? "Nothing shipped from this phone yet"
                )
                .font(.system(size: 11))
                .foregroundStyle(LivTheme.text3)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LivTheme.radius).fill(LivTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LivTheme.radius)
                .strokeBorder(LivTheme.border, lineWidth: 0.5)
        )
    }

    // The per-item honesty ledger — newest first, hairline rows.

    @ViewBuilder private var ledger: some View {
        if outbox.entries.isEmpty {
            Text("Nothing in the ledger yet — captures land here on their way to the desk.")
                .font(.system(size: 11))
                .foregroundStyle(LivTheme.muted)
        } else {
            VStack(spacing: 0) {
                ForEach(outbox.entries) { entry in
                    ledgerRow(entry)
                    if entry.id != outbox.entries.last?.id {
                        Rectangle().fill(LivTheme.border).frame(height: 0.5)
                    }
                }
            }
        }
    }

    private func ledgerRow(_ entry: OutboxEntry) -> some View {
        HStack(spacing: 6) {
            Text(entry.title.isEmpty ? "Untitled" : entry.title)
                .font(.system(size: 12))
                .foregroundStyle(LivTheme.text)
                .lineLimit(1)
            Spacer(minLength: 6)
            ValueChip(entry.kind.rawValue, dotted: false)
            OutboxStateChip(state: entry.state)
        }
        .frame(height: 34)
    }

    // "Ship now" — closes the open batch into the satellite outbox.

    private var shipRow: some View {
        Button {
            outbox.closeBatch(snapshot: box.snap)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "paperplane")
                    .font(.system(size: 11, weight: .semibold))
                Text("Ship now")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if outbox.pendingCount > 0 {
                    Text("\(outbox.pendingCount)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(LivTheme.text3)
                }
            }
            .foregroundStyle(
                outbox.satellitePath == nil ? LivTheme.muted : LivTheme.accent
            )
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(outbox.satellitePath == nil)
        .accessibilityLabel("Ship now")
    }

    // The satellite-path row (dev-grade: paste + Clear).

    private var satellitePathRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let path = outbox.satellitePath {
                HStack(spacing: 8) {
                    Text(path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(LivTheme.text2)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer(minLength: 6)
                    Button("Clear") { outbox.setSatellitePath(nil) }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LivTheme.accent)
                        .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                TextField("Paste a satellite folder path", text: $pathDraft)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(LivTheme.text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(setPath)
                Button("Set", action: setPath)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(draftReady ? LivTheme.accent : LivTheme.muted)
                    .buttonStyle(.plain)
                    .disabled(!draftReady)
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: LivTheme.radiusSm).fill(LivTheme.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LivTheme.radiusSm)
                    .strokeBorder(LivTheme.border, lineWidth: 0.5)
            )
        }
    }

    private var draftReady: Bool {
        !pathDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func setPath() {
        let trimmed = pathDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        outbox.setSatellitePath(trimmed)
        pathDraft = ""
    }
}

/// The honesty chip (design/ios.md §2.2): Pending muted, Shipped accent,
/// Delivered green with a check. Kit's chip recipe, state ink only.
private struct OutboxStateChip: View {
    let state: OutboxState

    private var label: String {
        switch state {
        case .pending: return "Pending"
        case .shipped: return "Shipped"
        case .delivered: return "Delivered"
        }
    }

    private var ink: Color {
        switch state {
        case .pending: return LivTheme.muted
        case .shipped: return LivTheme.accent
        case .delivered: return LivTheme.green
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            if state == .delivered {
                Image(systemName: "checkmark")
                    .font(.system(size: 7.5, weight: .bold))
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 6)
        .frame(height: 16)
        .overlay(Capsule().strokeBorder(LivTheme.border, lineWidth: 0.5))
    }
}

// MARK: - bottom bar

/// The Obsidian nav row under Liv law: the features menu button far left
/// (always present — it summons the grid; a chosen feature covers the
/// whole chrome), then ‹ › search + [tab count], always there. One 46pt
/// hairline pill on ultra-thin material + the features circle beside it.
struct BottomBar: View {
    @EnvironmentObject var desk: DeskModel
    /// The proposal count — the app's one in-app badge (amber). 0 until
    /// assist lands (M2).
    var inboxBadge: Int = 0

    var body: some View {
        HStack(spacing: 8) {
            featuresButton
            HStack(spacing: 0) {
                navButton("chevron.left", enabled: desk.canGoBack, label: "Back") {
                    desk.goBack()
                }
                navButton("chevron.right", enabled: desk.canGoForward, label: "Forward") {
                    desk.goForward()
                }
                navButton("magnifyingglass", enabled: true, label: "Search") {
                    desk.searchShown = true
                }
                navButton("plus", enabled: true, label: "New tab") {
                    desk.newTab()
                }
                tabCountButton
            }
            .padding(.horizontal, 4)
            .frame(height: 46)
            .frame(maxWidth: .infinity)
            // Solid, never a blur: the body must not read through the bar.
            .background(LivTheme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(LivTheme.border, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
        }
        .padding(.horizontal, 16)
    }

    /// The `^` of the sketch: always far left, badge-carrying (the inbox
    /// proposal count surfaces here since Inbox lives behind this menu).
    private var featuresButton: some View {
        Button {
            withAnimation(LivMotion.nav) { desk.gridShown.toggle() }
        } label: {
            Image(systemName: "chevron.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(desk.gridShown ? LivTheme.accent : LivTheme.text2)
                .frame(width: 46, height: 46)
                .background(LivTheme.surface, in: Circle())
                .overlay(Circle().strokeBorder(
                    desk.gridShown ? LivTheme.accent : LivTheme.border,
                    lineWidth: desk.gridShown ? 1 : 0.5))
                .overlay(alignment: .topTrailing) {
                    if inboxBadge > 0 { badge }
                }
                .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Features")
    }

    private var badge: some View {
        Text(inboxBadge > 99 ? "99+" : "\(inboxBadge)")
            .font(.system(size: 9, weight: .bold).monospacedDigit())
            .foregroundStyle(chromeAmberInk)
            .padding(.horizontal, 3.5)
            .frame(minWidth: 13, minHeight: 13)
            .background(Capsule().fill(LivTheme.amber))
            .offset(x: 2, y: -2)
    }

    private func navButton(
        _ icon: String, enabled: Bool, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(enabled ? LivTheme.text2 : LivTheme.muted.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    /// The Obsidian tab square: the open-tab count inside its own outline.
    private var tabCountButton: some View {
        Button {
            desk.switcherShown = true
        } label: {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(LivTheme.text2, lineWidth: 1.5)
                .frame(width: 20, height: 20)
                .overlay(
                    Text(desk.tabs.count > 99 ? "99" : "\(desk.tabs.count)")
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundStyle(LivTheme.text2)
                )
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tabs")
    }
}

// MARK: - feature grid

/// The `^` menu (ClickUp's "More"): a solid panel pinned to the bottom
/// edge that COVERS the bar it was summoned from (owner, 2026-07-29). No
/// blur and no translucency — nothing underneath may read through it. Its
/// own far-left `v` sits exactly where the `^` sits, so the toggle never
/// appears to jump. Tap swaps the body or fires the verb, then closes.
struct FeatureGrid: View {
    @EnvironmentObject var desk: DeskModel

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Feature.allCases) { f in
                    cell(f.title, f.icon, on: desk.featureShown == f) {
                        desk.featureShown = f
                    }
                }
                cell("Capture", "square.and.pencil", on: false) {
                    desk.newTab()
                }
                cell("Camera", "camera", on: false) {
                    desk.cameraShown = true
                }
            }
            closeRow
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .frame(maxWidth: .infinity)
        .background(
            LivTheme.surface
                .overlay(alignment: .top) {
                    Rectangle().fill(LivTheme.border).frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }

    /// 12pt inside the panel's own 16pt gutter = 28pt from the screen edge,
    /// which is where the bar's `^` circle is (App's 12 + BottomBar's 16).
    private var closeRow: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(LivMotion.nav) { desk.gridShown = false }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LivTheme.accent)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(LivTheme.panel))
                    .overlay(Circle().strokeBorder(LivTheme.accent, lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Features")
            Spacer(minLength: 0)
        }
        .padding(.leading, 12)
        .padding(.bottom, 4)
    }

    private func cell(
        _ label: String, _ icon: String, on: Bool, action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(LivMotion.nav) { desk.gridShown = false }
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 17))
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(on ? LivTheme.accent : LivTheme.text2)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(on ? LivTheme.accentSoft : LivTheme.panel)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}
