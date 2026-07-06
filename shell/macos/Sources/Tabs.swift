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
}

struct WorkspaceTab: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: TabKind
}

/// Per-workspace tab sets, persisted as shell state. Home is workspace 0.
enum TabsStore {
    private static func key(_ workspace: UInt64) -> String { "app.tabs.v1.\(workspace)" }

    struct Saved: Codable {
        var tabs: [WorkspaceTab]
        var activeId: UUID?
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
    private var workspace: UInt64 = 0

    var active: WorkspaceTab? { tabs.first { $0.id == activeId } }

    /// Load a workspace's set. Idempotent for the same workspace, so
    /// snapshot-driven re-renders never reset the tabs.
    func load(workspace: UInt64) {
        guard workspace != self.workspace || tabs.isEmpty else { return }
        self.workspace = workspace
        let saved = TabsStore.load(workspace)
        tabs = saved.tabs
        activeId = saved.activeId ?? saved.tabs.first?.id
    }

    private func persist() {
        TabsStore.save(workspace, .init(tabs: tabs, activeId: activeId))
    }

    func setActive(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeId = id
        persist()
    }

    /// Focus the tab already showing this entity, else append one. The
    /// universal dedup (Liv's findTabForObject): a note opens once.
    func openNote(_ entity: UInt64) -> WorkspaceTab {
        if let existing = tabs.first(where: { $0.kind == .note(entity) }) {
            return existing
        }
        let tab = WorkspaceTab(kind: .note(entity))
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
    func close(_ id: UUID) -> UUID? {
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return activeId }
        let wasActive = activeId == id
        tabs.remove(at: i)
        if tabs.isEmpty {
            let desk = WorkspaceTab(kind: .desk)
            tabs = [desk]
            activeId = desk.id
            persist()
            return wasActive ? desk.id : activeId
        }
        if wasActive {
            let next = tabs[min(i, tabs.count - 1)].id
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

    /// Drop note tabs whose entity vanished (trashed here or by the CLI),
    /// mirroring the workspace-scope reconcile. Returns the id to
    /// activate if the active tab was pruned, else nil.
    @discardableResult
    func reconcile(liveIds: Set<UInt64>) -> UUID? {
        let stale = tabs.filter {
            if case .note(let id) = $0.kind { return !liveIds.contains(id) }
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

    @State private var dropTarget: UUID?
    @State private var dropAfter = false

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(tabs.tabs) { tab in
                        TabPill(
                            tab: tab,
                            title: title(tab),
                            icon: icon(tab),
                            active: tabs.activeId == tab.id,
                            insertionBefore: dropTarget == tab.id && !dropAfter,
                            insertionAfter: dropTarget == tab.id && dropAfter,
                            activate: { activate(tab) },
                            close: { close(tab) },
                            rename: {
                                if case .note(let id) = tab.kind { rename(id) }
                            }
                        )
                        .onDrag { NSItemProvider(object: tab.id.uuidString as NSString) }
                        .onDrop(
                            of: [.plainText],
                            delegate: TabDrop(
                                target: tab, tabs: tabs,
                                dropTarget: $dropTarget, dropAfter: $dropAfter))
                    }
                }
            }
            // Trailing cluster: + opens a blank tab (founder-locked — the
            // landing, never an instant note). The ⌄ container picker,
            // Group N, and saved-groups Layers menu attach here in the
            // groups/composers slice.
            Button(action: openNew) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 34, height: 34)
                    .foregroundColor(Theme.mutedFg)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New tab")
        }
        .frame(height: 36)
        .background(WindowDragRegion())
        .background(Theme.panel.opacity(0.35))
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
        }
    }
}

struct TabPill: View {
    let tab: WorkspaceTab
    let title: String
    let icon: String
    let active: Bool
    let insertionBefore: Bool
    let insertionAfter: Bool
    let activate: () -> Void
    let close: () -> Void
    let rename: () -> Void

    @State private var hovering = false

    var body: some View {
        // TAB_BASE (§2.3.2): flat square tab, active = page bg + a 2px
        // primary bar along the top edge (the melt into the content),
        // inactive = quiet secondary tint; icon + name + hover close.
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(active ? Theme.primary : Theme.mutedFg)
                .opacity(active ? 1 : 0.8)
            Text(title)
                .font(.system(size: 12, weight: active ? .medium : .regular))
                .foregroundColor(active ? Theme.foreground : Theme.foreground.opacity(0.7))
                .lineLimit(1)
            Spacer(minLength: 2)
            if hovering {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Theme.mutedFg)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close tab")
            }
        }
        .padding(.horizontal, 10)
        .frame(minWidth: 110, maxWidth: 200)
        .frame(height: 36)
        .background(active ? Theme.background : Theme.secondary.opacity(hovering ? 0.5 : 0.25))
        .overlay(alignment: .top) {
            if active {
                Rectangle().fill(Theme.primary).frame(height: 2)
            }
        }
        .overlay(alignment: .trailing) {
            Divider().opacity(0.4)
        }
        .overlay(alignment: .leading) {
            if insertionBefore { Rectangle().fill(Theme.primary).frame(width: 2) }
        }
        .overlay(alignment: .trailing) {
            if insertionAfter { Rectangle().fill(Theme.primary).frame(width: 2) }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: rename)
        .onTapGesture(perform: activate)
    }
}

/// Drag-reorder: the hovered half decides before/after (§2.3.2). Group
/// membership does not exist yet, so a reorder is a pure move.
struct TabDrop: DropDelegate {
    let target: WorkspaceTab
    let tabs: TabsModel
    @Binding var dropTarget: UUID?
    @Binding var dropAfter: Bool

    func dropUpdated(info: DropInfo) -> DropProposal? {
        dropTarget = target.id
        dropAfter = info.location.x > 100  // past the pill's mid — floor width
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
