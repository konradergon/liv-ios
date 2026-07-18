// lotus — P3 of the Liv port: the unified tab strip (liv-ui-map.md §2.3).
// The working set of a workspace, as the Notes content's top bar (not a
// chrome row — the Claude-style chrome put the strip here). Tabs are
// shell state, per workspace, persisted in UserDefaults — never entities
// (transient UI state is never content; Liv's cautionary tale #6).
//
// P3 ships note/desk/blank tabs: open many notes at once, rename, close,
// drag-reorder, the blank landing, close-neighbour semantics. Deferred
// to later slices (they need surfaces P12–P14 or are pure polish, marked
// where they'd attach): tab groups & composers (§2.3.3), split panes
// (§2.3.5), superspaces & saved groups (§2.3.4), tools-as-tabs, the
// rapid-close width freeze (§2.3.2), multi-select grouping.

import AppKit
import SwiftUI

// MARK: - the model

enum TabKind: Codable, Equatable {
    /// The desk: Today / Everything / Results, driven by the lens.
    case desk
    /// A new tab with nothing in it yet — the blank landing.
    case blank
    /// An open entity, shown in the editor.
    case note(UInt64)
    /// A file entity, shown read-only in BaseFileView — never the editor
    /// (read-only-by-decision is law).
    case file(UInt64)
}

struct WorkspaceTab: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: TabKind
    /// Tab group (bp4, 17e): a shared name; members wear the group's
    /// value-hue band. Optional so v1-persisted tabs decode unchanged.
    var group: String? = nil
    /// Category-lock (bp4): a locked tab refuses close (the close affordance
    /// hides; middle-click and ⌘W bounce). Optional for v1 decode.
    var locked: Bool? = nil

    var isLocked: Bool { locked == true }
}

/// Per-workspace tab sets, persisted as shell state. Home is workspace 0.
enum TabsStore {
    private static func key(_ workspace: UInt64) -> String { "app.tabs.v1.\(workspace)" }

    struct Saved: Codable {
        var tabs: [WorkspaceTab]
        var activeId: UUID?
        /// P20c.2b: the active CONTAINER (nil = Overview). Optional so
        /// v1-persisted sets decode unchanged.
        var container: String? = nil
    }

    static func load(_ workspace: UInt64) -> Saved {
        guard let data = UserDefaults.standard.data(forKey: key(workspace)),
            let saved = try? JSONDecoder().decode(Saved.self, from: data),
            !saved.tabs.isEmpty
        else {
            // A workspace always opens on its desk.
            let desk = WorkspaceTab(kind: .desk)
            return Saved(tabs: [desk], activeId: desk.id)
        }
        return saved
    }

    static func save(_ workspace: UInt64, _ saved: Saved) {
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: key(workspace))
        }
    }
}

final class TabsModel: ObservableObject {
    @Published private(set) var tabs: [WorkspaceTab] = []
    @Published private(set) var activeId: UUID?
    /// P20c.2b — the mockup's two-level anatomy: the GLOBAL row shows
    /// containers (Overview = the ungrouped set incl. the desk; one per
    /// tab group), the content row shows the active container's tabs.
    @Published private(set) var container: String? = nil
    /// Recently-closed ring (bp4 ▾ / ⌘⇧T) — session-only shell state,
    /// newest last, capped small.
    @Published private(set) var closed: [WorkspaceTab] = []
    private var workspace: UInt64 = 0

    var active: WorkspaceTab? { tabs.first { $0.id == activeId } }

    /// The active container's tabs — what the content row shows.
    var visibleTabs: [WorkspaceTab] { tabs.filter { $0.group == container } }

    /// Switch container; the selection follows into it (a container is
    /// never empty: groups exist through members, Overview mints a blank).
    func setContainer(_ name: String?) {
        guard name != container else { return }
        container = name
        if let first = visibleTabs.first, !visibleTabs.contains(where: { $0.id == activeId }) {
            activeId = first.id
        } else if visibleTabs.isEmpty {
            let blank = WorkspaceTab(kind: .blank, group: name)
            tabs.append(blank)
            activeId = blank.id
        }
        persist()
    }

    /// Load a workspace's set. Idempotent for the same workspace, so
    /// snapshot-driven re-renders never reset the tabs.
    func load(workspace: UInt64) {
        guard workspace != self.workspace || tabs.isEmpty else { return }
        self.workspace = workspace
        let saved = TabsStore.load(workspace)
        tabs = saved.tabs
        activeId = saved.activeId ?? saved.tabs.first?.id
        container = saved.container
    }

    private func persist() {
        TabsStore.save(workspace, .init(tabs: tabs, activeId: activeId, container: container))
    }

    func setActive(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        activeId = id
        // The container follows the selection (activating a grouped tab
        // fronts its container).
        container = tab.group
        persist()
    }

    /// Focus the tab already showing this entity, else append one. The
    /// universal dedup (Liv's findTabForObject): a note opens once.
    func openNote(_ entity: UInt64) -> WorkspaceTab {
        if let existing = tabs.first(where: { $0.kind == .note(entity) }) {
            return existing
        }
        // P20c.2b: a new tab lands in the ACTIVE container — unless it is
        // category-locked (a locked container takes no foreign opens; the
        // open routes to Overview instead — v0 of the map [7] affinity).
        let locked = container.map { g in
            tabs.contains { $0.group == g && $0.isLocked }
        } ?? false
        let tab = WorkspaceTab(kind: .note(entity), group: locked ? nil : container)
        if locked { container = nil }
        tabs.append(tab)
        persist()
        return tab
    }

    /// A file entity opens once, read-only, in its own file tab.
    func openFile(_ entity: UInt64) -> WorkspaceTab {
        if let existing = tabs.first(where: { $0.kind == .file(entity) }) {
            return existing
        }
        let tab = WorkspaceTab(kind: .file(entity))
        tabs.append(tab)
        persist()
        return tab
    }

    func openBlank() -> WorkspaceTab {
        let tab = WorkspaceTab(kind: .blank)
        tabs.append(tab)
        persist()
        return tab
    }

    /// Focus the desk tab (Today / Everything), minting one if the user
    /// closed it — the lens buttons always have somewhere to land.
    func openDesk() -> WorkspaceTab {
        if let existing = tabs.first(where: { $0.kind == .desk }) {
            return existing
        }
        let tab = WorkspaceTab(kind: .desk)
        tabs.append(tab)
        persist()
        return tab
    }

    /// A blank tab whose landing materialises content converts in place
    /// (Liv: never rewritten after) — so a fresh note lands in the very
    /// tab the user opened, not a second one.
    func convert(_ id: UUID, to kind: TabKind) {
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[i].kind = kind
        persist()
    }

    /// Close a tab; return the id to activate next (right neighbour then
    /// left, browser standard). Closing the last tab mints a fresh desk.
    @discardableResult
    /// A container whose last member closed vanishes — fall home to
    /// Overview and keep the selection inside the visible set (P20c.2b).
    private func reconcileContainer() {
        if let current = container, !groups.contains(current) {
            container = nil
        }
        if !visibleTabs.contains(where: { $0.id == activeId }) {
            activeId = visibleTabs.first?.id ?? tabs.first?.id
        }
    }

    func close(_ id: UUID) -> UUID? {
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return activeId }
        // A locked tab refuses close — unlock first (bp4 category-lock).
        guard !tabs[i].isLocked else { return activeId }
        let wasActive = activeId == id
        // Content tabs are reopenable (▾ / ⌘⇧T); desk/blank carry nothing.
        switch tabs[i].kind {
        case .note, .file:
            closed.append(tabs[i])
            if closed.count > 10 { closed.removeFirst() }
        default: break
        }
        tabs.remove(at: i)
        reconcileContainer()
        if tabs.isEmpty {
            let desk = WorkspaceTab(kind: .desk)
            tabs = [desk]
            activeId = desk.id
            persist()
            return wasActive ? desk.id : activeId
        }
        if wasActive {
            // The neighbor pick stays INSIDE the visible container; a
            // cross-container index neighbor would flip the strip (P20c.2b).
            let neighbor = tabs[min(i, tabs.count - 1)]
            let next = neighbor.group == container
                ? neighbor.id
                : (visibleTabs.first?.id ?? neighbor.id)
            activeId = next
            persist()
            return next
        }
        persist()
        return activeId
    }

    func reorder(_ id: UUID, before target: UUID) {
        guard let from = tabs.firstIndex(where: { $0.id == id }),
            let to = tabs.firstIndex(where: { $0.id == target }), from != to
        else { return }
        let tab = tabs.remove(at: from)
        let insert = tabs.firstIndex(where: { $0.id == target }) ?? tabs.count
        tabs.insert(tab, at: insert)
        persist()
    }

    func reorder(_ id: UUID, after target: UUID) {
        guard let from = tabs.firstIndex(where: { $0.id == id }),
            tabs.contains(where: { $0.id == target }), id != target
        else { return }
        let tab = tabs.remove(at: from)
        let insert = (tabs.firstIndex(where: { $0.id == target }) ?? tabs.count - 1) + 1
        tabs.insert(tab, at: min(insert, tabs.count))
        persist()
    }

    // ---- the 17e muscle: groups · lock · reopen ----

    func setGroupFollowingContainer(_ id: UUID, _ group: String?) {
        setGroup(id, group)
        if id == activeId { container = group }
        persist()
    }

    func setGroup(_ id: UUID, _ group: String?) {
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[i].group = group
        persist()
    }

    func toggleLock(_ id: UUID) {
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[i].locked = tabs[i].isLocked ? nil : true
        persist()
    }

    /// The distinct group names among open tabs, first-seen order — the
    /// context menu's "add to" list.
    var groups: [String] {
        var seen: [String] = []
        for tab in tabs {
            if let g = tab.group, !seen.contains(g) { seen.append(g) }
        }
        return seen
    }

    /// Replace the whole tab set (a layout-layer restore, P17i) — pure
    /// shell state; the desk always survives at the front. Returns the tab
    /// to activate.
    @discardableResult
    func adopt(_ set: [WorkspaceTab]) -> WorkspaceTab {
        var next = set
        if !next.contains(where: { $0.kind == .desk }) {
            next.insert(WorkspaceTab(kind: .desk), at: 0)
        }
        tabs = next
        let active = next.first { $0.kind != .desk } ?? next[0]
        activeId = active.id
        persist()
        return active
    }

    /// Reopen the most recent closed tab (⌘⇧T), or a specific one (the ▾
    /// menu). Returns it activated, or nil if the ring is empty.
    func reopen(_ id: UUID? = nil) -> WorkspaceTab? {
        let index: Int? =
            id.flatMap { wanted in closed.firstIndex { $0.id == wanted } }
            ?? (closed.isEmpty ? nil : closed.count - 1)
        guard let index else { return nil }
        let tab = closed.remove(at: index)
        tabs.append(tab)
        activeId = tab.id
        persist()
        return tab
    }

    /// Drop note tabs whose entity vanished (trashed here or by the CLI),
    /// mirroring the workspace-scope reconcile. Returns the id to
    /// activate if the active tab was pruned, else nil.
    @discardableResult
    func reconcile(liveIds: Set<UInt64>) -> UUID? {
        let stale = tabs.filter {
            if case .note(let id) = $0.kind { return !liveIds.contains(id) }
            if case .file(let id) = $0.kind { return !liveIds.contains(id) }
            return false
        }
        guard !stale.isEmpty else { return nil }
        var reactivate: UUID?
        for tab in stale {
            if tab.id == activeId {
                reactivate = close(tab.id)
            } else {
                close(tab.id)
            }
        }
        return reactivate
    }
}

// MARK: - the strip

struct TabStrip: View {
    @ObservedObject var tabs: TabsModel
    @ObservedObject var model: BoxModel
    @ObservedObject var chrome: ChromeModel
    let activate: (WorkspaceTab) -> Void
    let close: (WorkspaceTab) -> Void
    let openNew: () -> Void
    let rename: (UInt64) -> Void

    // The lane's geometry, all deterministic (no per-tab measurement, so no
    // render loop): pills clamp between MIN and MAX width; when even MIN-width
    // pills can't all fit, the excess collapses into a compact +N overflow menu
    // and the window slides so the ACTIVE tab is always visible. The + never
    // moves and the lane can never overflow its slot.
    private static let minTab: CGFloat = 76
    private static let maxTab: CGFloat = 170
    private static let gap: CGFloat = 6
    private static let plusWidth: CGFloat = 24
    private static let overflowWidth: CGFloat = 34

    /// Rapid-close width freeze (17e): after a close, pill widths hold so the
    /// next tab's ✕ lands under the cursor; released when the pointer leaves.
    @State private var frozenWidth: CGFloat?
    /// The pill under the pointer — the middle-click close target.
    @State private var hoveredTab: UUID?
    @State private var midMonitor: Any?

    var body: some View {
        GeometryReader { geo in
            let all = tabs.visibleTabs
            let lane = max(0, geo.size.width - Self.plusWidth - Self.gap)
            // How many MIN-width pills fit (leave room for the +N chip when
            // some don't).
            let fitAll = Int((lane + Self.gap) / (Self.minTab + Self.gap))
            let overflowing = all.count >= 2 && fitAll < all.count
            let usable = overflowing ? max(0, lane - Self.overflowWidth - Self.gap) : lane
            let visibleCount = overflowing
                ? max(1, Int((usable + Self.gap) / (Self.minTab + Self.gap)))
                : all.count
            // Slide the window so the active tab is in view; prefer the front.
            let activeAt = all.firstIndex { $0.id == tabs.activeId } ?? 0
            let start = overflowing
                ? min(max(0, activeAt - visibleCount + 1), max(0, all.count - visibleCount))
                : 0
            let end = min(start + visibleCount, all.count)
            let visible = all.count >= 2 ? Array(all[start..<end]) : []
            let width = visible.isEmpty
                ? 0
                : min(Self.maxTab,
                      max(Self.minTab,
                          (usable - Self.gap * CGFloat(visible.count - 1)) / CGFloat(visible.count)))
            let hidden = all.count >= 2 ? Array(all[..<start]) + Array(all[end...]) : []

            HStack(spacing: Self.gap) {
                ForEach(visible) { tab in
                    TabPill(
                        tab: tab,
                        title: title(tab),
                        icon: icon(tab),
                        active: tabs.activeId == tab.id,
                        activate: { activate(tab) },
                        close: {
                            frozenWidth = frozenWidth ?? width
                            close(tab)
                        },
                        rename: {
                            if case .note(let id) = tab.kind { rename(id) }
                        },
                        existingGroups: tabs.groups,
                        setGroup: { name in tabs.setGroupFollowingContainer(tab.id, name) },
                        newGroup: {
                            Dialogs.shared.prompt(
                                "New tab group", placeholder: "Name", confirmLabel: "Group"
                            ) { name in
                                guard let name = name?.trimmingCharacters(in: .whitespaces),
                                    !name.isEmpty
                                else { return }
                                tabs.setGroupFollowingContainer(tab.id, name)
                            }
                        },
                        toggleLock: { tabs.toggleLock(tab.id) },
                        hoverChanged: { inside in
                            if inside {
                                hoveredTab = tab.id
                            } else if hoveredTab == tab.id {
                                hoveredTab = nil
                            }
                        }
                    )
                    .frame(width: frozenWidth ?? width)
                }
                if !hidden.isEmpty {
                    Menu {
                        ForEach(hidden) { tab in
                            Button(title(tab)) { activate(tab) }
                        }
                    } label: {
                        Text("+\(hidden.count)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Theme.mutedFg)
                            .frame(width: Self.overflowWidth - 6, height: 22)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.secondary.opacity(0.4)))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("\(hidden.count) more tab\(hidden.count == 1 ? "" : "s")")
                }
                Spacer(minLength: 0)
                // ▾ recently closed (bp4, ⌘⇧T) — only when there IS something
                // to reopen; reopening restores the tab and activates it.
                if !tabs.closed.isEmpty {
                    Menu {
                        ForEach(tabs.closed.reversed()) { closedTab in
                            Button(title(closedTab)) {
                                if let tab = tabs.reopen(closedTab.id) { activate(tab) }
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Theme.mutedFg)
                            .frame(width: 18, height: 24)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Recently closed (⌘⇧T)")
                }
                Button(action: openNew) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: Self.plusWidth, height: 24)
                        .foregroundColor(Theme.mutedFg)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New tab (⌘T)")
            }
            .frame(height: geo.size.height)
        }
        .frame(maxHeight: Theme.headerBandHeight)
        // Release the width freeze when the pointer leaves the lane.
        .onHover { inside in
            if !inside { frozenWidth = nil }
        }
        // Middle-click closes the hovered tab (bp4) — locked tabs bounce.
        .onAppear {
            midMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { event in
                guard let id = hoveredTab,
                    let tab = tabs.tabs.first(where: { $0.id == id })
                else { return event }
                if !tab.isLocked { close(tab) }
                return nil
            }
        }
        .onDisappear {
            if let monitor = midMonitor {
                NSEvent.removeMonitor(monitor)
                midMonitor = nil
            }
        }
    }

    private func title(_ tab: WorkspaceTab) -> String {
        switch tab.kind {
        case .desk:
            if let id = chrome.activeWorkspace,
                let row = (model.snap?.workspaces ?? []).first(where: { $0.id == id })
            {
                return row.name
            }
            return "Home"
        case .blank:
            return "New tab"
        case .note(let id):
            let raw = model.entity(id)?.title ?? "#\(id)"
            // P20c.2: daily notes wear their civil face in the chrome.
            return civilDailyTitle(raw) ?? raw
        case .file(let id):
            return model.entity(id)?.title ?? "#\(id)"
        }
    }

    private func icon(_ tab: WorkspaceTab) -> String {
        switch tab.kind {
        case .desk: return "sparkles"
        case .blank: return "plus.rectangle"
        case .note(let id):
            let row = model.entity(id)
            if row?.kinds.contains("task") == true || row?.status != nil {
                return "checkmark.square"
            }
            return "doc.text"
        case .file: return "doc"
        }
    }
}

struct TabPill: View {
    let tab: WorkspaceTab
    let title: String
    let icon: String
    let active: Bool
    let activate: () -> Void
    let close: () -> Void
    let rename: () -> Void
    /// Group verbs (17e) — the strip supplies them so the pill's context
    /// menu stays dumb.
    var existingGroups: [String] = []
    var setGroup: (String?) -> Void = { _ in }
    var newGroup: () -> Void = {}
    var toggleLock: () -> Void = {}
    /// Hover report for the strip's middle-click close.
    var hoverChanged: (Bool) -> Void = { _ in }

    @State private var hovering = false
    @State private var lastTap = Date.distantPast

    private var groupHue: Color? {
        tab.group.map { Color(nsColor: Hues.valueHex($0)) }
    }

    var body: some View {
        // A clean, native macOS tab (Safari/Arc idiom): a rounded pill,
        // the active one raised into the content colour, inactive quiet
        // with a hover tint. The MELT (§6-18): no border at all — the
        // active pill is fill only, one sheet with the canvas.
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11.5))
                .foregroundColor(active ? Theme.foreground : Theme.mutedFg)
            Text(title)
                .font(.system(size: 12, weight: active ? .medium : .regular))
                .foregroundColor(active ? Theme.foreground : Theme.foreground.opacity(0.72))
                .lineLimit(1)
            Spacer(minLength: 2)
            if tab.isLocked {
                // Locked: the lock replaces the close slot — no close affordance.
                Image(systemName: "lock.fill")
                    .font(.system(size: 8.5))
                    .foregroundColor(Theme.mutedFg)
                    .frame(width: 15, height: 15)
                    .help("Locked — unlock from the tab menu")
            } else {
                // The close slot holds its width so the title doesn't jump
                // on hover.
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(Theme.mutedFg)
                        .frame(width: 15, height: 15)
                        .background(
                            Circle().fill(Theme.secondary.opacity(hovering ? 0.6 : 0)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0)
                .help("Close tab")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(active ? Theme.secondary.opacity(0.9) : (hovering ? Theme.secondary.opacity(0.4) : .clear))
        )
        // The group band (17e): a value-hue underline — colour, not lines;
        // never the accent, and adjacent members read as one band.
        .overlay(alignment: .bottom) {
            if let hue = groupHue {
                Capsule().fill(hue.opacity(0.65))
                    .frame(height: 2.5)
                    .padding(.horizontal, 6)
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            hoverChanged(inside)
        }
        .contextMenu {
            Button(tab.isLocked ? "Unlock tab" : "Lock tab") { toggleLock() }
            Menu("Group") {
                Button("New group…") { newGroup() }
                if !existingGroups.isEmpty {
                    Divider()
                    ForEach(existingGroups, id: \.self) { name in
                        Button(name + (tab.group == name ? " ✓" : "")) { setGroup(name) }
                    }
                }
                if tab.group != nil {
                    Divider()
                    Button("Remove from group") { setGroup(nil) }
                }
            }
            if !tab.isLocked {
                Divider()
                Button("Close tab") { close() }
            }
        }
        // Select on single tap, rename on double — but detect the double
        // MANUALLY. A sibling `.onTapGesture(count: 2)` makes SwiftUI hold every
        // single tap for the system double-click interval to disambiguate, which
        // is a fixed ~250ms delay on every tab select. Firing activate on each
        // tap (idempotent when already active) keeps selection instant; a second
        // tap inside the interval also renames.
        .onTapGesture {
            activate()
            let now = Date()
            if now.timeIntervalSince(lastTap) < NSEvent.doubleClickInterval {
                lastTap = .distantPast
                rename()
            } else {
                lastTap = now
            }
        }
    }
}

/// Drag-reorder: the hovered half decides before/after (§2.3.2). Group
/// membership does not exist yet, so a reorder is a pure move.
struct TabDrop: DropDelegate {
    let target: WorkspaceTab
    let tabs: TabsModel
    let width: CGFloat
    @Binding var dropTarget: UUID?
    @Binding var dropAfter: Bool

    func dropUpdated(info: DropInfo) -> DropProposal? {
        dropTarget = target.id
        dropAfter = info.location.x > width / 2  // past this pill's real mid
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if dropTarget == target.id { dropTarget = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        let after = dropAfter
        dropTarget = nil
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String, let id = UUID(uuidString: text) else { return }
            DispatchQueue.main.async {
                if after {
                    tabs.reorder(id, after: target.id)
                } else {
                    tabs.reorder(id, before: target.id)
                }
            }
        }
        return true
    }
}

// MARK: - the blank landing (§2.3.2 BlankGlobalView)

struct BlankTabLanding: View {
    let createNote: () -> Void
    let search: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "plus.rectangle")
                .font(.system(size: 44))
                .foregroundColor(Theme.foreground.opacity(0.12))
            Text("New tab").font(.system(size: 16, weight: .semibold))
            VStack(spacing: 8) {
                landingRow("square.and.pencil", "Create new note", "⌘N", createNote)
                landingRow("magnifyingglass", "Search", "⌘O", search)
            }
            .frame(width: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func landingRow(
        _ symbol: String, _ label: String, _ key: String, _ action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.primary)
                    .frame(width: 20)
                Text(label).font(.system(size: 13))
                Spacer()
                KbdChip(label: key)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: Theme.radiusMd).fill(Theme.secondary.opacity(0.3)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
