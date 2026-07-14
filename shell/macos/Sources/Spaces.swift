// lotus — P2 of the Liv port: workspaces and the left sidebar
// (liv-ui-map.md §2.2, §2.4, §2.7). One entity kind carries what Liv
// split across Workspace records and a TreeNode store: a workspace may
// reference a parent workspace, and the tree is that. Everything here
// renders from the snapshot and mutates through commands.

import AppKit
import SwiftUI

// MARK: - the workspace tree, derived from snapshot rows

struct WorkspaceTree {
    let rows: [WorkspaceRow]
    /// Live rows only, keyed by *effective* parent: a live child whose
    /// parent is trashed (absent) or archived re-roots to the top level,
    /// never vanishing. This is the "dangling parent → root" rule the
    /// non-cascading trash depends on (deletion never cascades).
    private let children: [UInt64: [WorkspaceRow]]
    private let liveIds: Set<UInt64>

    init(_ rows: [WorkspaceRow]) {
        self.rows = rows
        let live = rows.filter { !$0.archived }
        liveIds = Set(live.map(\.id))
        let liveSet = liveIds
        children = Dictionary(grouping: live.filter { liveSet.contains($0.parent) }) {
            $0.parent
        }
    }

    func row(_ id: UInt64) -> WorkspaceRow? {
        rows.first { $0.id == id }
    }

    /// A live row's parent, or 0 when that parent is absent or archived.
    private func effectiveParent(_ row: WorkspaceRow) -> UInt64 {
        liveIds.contains(row.parent) ? row.parent : 0
    }

    func kids(of id: UInt64) -> [WorkspaceRow] {
        (children[id] ?? []).sorted { $0.order < $1.order }
    }

    var topLevel: [WorkspaceRow] {
        rows.filter { !$0.archived && effectiveParent($0) == 0 }
            .sorted { $0.order < $1.order }
    }

    func isLive(_ row: WorkspaceRow) -> Bool {
        !row.archived
    }

    /// Favourites: starred, plus Home by default (§2.2.2).
    var favourites: [WorkspaceRow] {
        rows.filter { ($0.favorite || $0.builtin == "home") && !$0.archived }
            .sorted { $0.order < $1.order }
    }

    /// Spaces: top-level nodes with a live workspace anywhere below
    /// (§2.2.2). Membership is the live-descendant test, not merely
    /// "has children" — an area whose every child is archived is a Board.
    var spaces: [WorkspaceRow] {
        topLevel.filter { !kids(of: $0.id).isEmpty && $0.builtin.isEmpty }
    }

    /// Boards: standalone top-level workspaces with no live sub-space.
    var boards: [WorkspaceRow] {
        topLevel.filter { kids(of: $0.id).isEmpty && $0.builtin.isEmpty }
    }

    var archived: [WorkspaceRow] {
        rows.filter { $0.archived }.sorted { $0.order < $1.order }
    }

    func descendantCount(of id: UInt64) -> Int {
        kids(of: id).reduce(0) { $0 + 1 + descendantCount(of: $1.id) }
    }

    /// The child label follows hierarchy depth: area → project →
    /// sub-project → folder (§2.2.3).
    func childLabel(for id: UInt64) -> String {
        var depth = 0
        var cursor = row(id)
        while let current = cursor, current.parent != 0 {
            depth += 1
            cursor = row(current.parent)
        }
        switch depth {
        case 0: return "project"
        case 1: return "sub-project"
        default: return "folder"
        }
    }

    /// The stable per-workspace accent: FNV-1a of the id into a 10-hue
    /// palette (§2.2.3) — identity color, distinct from the app accent.
    static func accent(for id: UInt64) -> Color {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in withUnsafeBytes(of: id.littleEndian, Array.init) {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hues: [Double] = [0.02, 0.08, 0.13, 0.29, 0.45, 0.55, 0.62, 0.72, 0.83, 0.93]
        return Color(hue: hues[Int(hash % 10)], saturation: 0.45, brightness: 0.65)
    }
}

// MARK: - sidebar views (§2.2.1)

/// The two essential sidebar views — the workspace tree and the files
/// vault. Properties, Saved, and Graph were dropped from the picker (the
/// owner's call); their panels stay in the code for a later home.
enum SidebarView: String, CaseIterable {
    case tree, vault

    var tooltip: String {
        switch self {
        case .tree: return "Workspaces"
        case .vault: return "Files"
        }
    }

    var symbol: String {
        switch self {
        case .tree: return "square.grid.2x2"
        case .vault: return "folder"
        }
    }
}

/// The tree/vault toggle, living in the content top bar (not the panel) —
/// two quiet icons writing the shared sidebar-view preference the panel
/// reads. Only shown in the Notes surface, where the panel view it drives
/// lives.
struct SidebarViewToggle: View {
    @AppStorage("app.leftView.v1") private var viewRaw = SidebarView.tree.rawValue

    private var current: SidebarView { SidebarView(rawValue: viewRaw) ?? .tree }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SidebarView.allCases, id: \.rawValue) { item in
                Button {
                    viewRaw = item.rawValue
                } label: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 12))
                        .frame(width: 24, height: 24)
                        .foregroundColor(current == item ? Theme.primary : Theme.mutedFg)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(current == item ? Theme.primary.opacity(0.12) : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.tooltip)
            }
        }
    }
}

// MARK: - the sidebar

struct AppSidebar: View {
    @ObservedObject var model: BoxModel
    @ObservedObject var chrome: ChromeModel
    @Binding var lens: Lens
    @Binding var query: String
    @Binding var selection: UInt64?
    var searchFocused: FocusState<Bool>.Binding
    /// The navigation gate: flush any open editor, then run the work
    /// only if the flush succeeded. A refused flush cancels the switch.
    var willNavigate: (@escaping () -> Void) -> Void = { $0() }
    var openEntity: (UInt64) -> Void = { _ in }
    var showDesk: (Lens) -> Void = { _ in }

    @AppStorage("app.leftView.v1") private var viewRaw = SidebarView.tree.rawValue
    @State private var filter = ""

    private var view: SidebarView {
        SidebarView(rawValue: viewRaw) ?? .tree
    }

    var body: some View {
        // The notes desk: the view-picker and its body. The panel around
        // it (header, surface nav, workspace footer) supplies the search
        // and the material background now.
        VStack(spacing: 0) {
            // The tree/vault toggle moved out of the panel to the content
            // top bar (SidebarViewToggle in the tab strip); the panel just
            // shows whichever view is chosen.
            switch view {
            case .tree:
                SpacesTree(
                    model: model, chrome: chrome, lens: $lens, query: $query,
                    selection: $selection, filter: $filter,
                    willNavigate: willNavigate, showDesk: showDesk,
                    openEntity: openEntity)
            case .vault:
                VaultTree(model: model, filter: $filter, openEntity: openEntity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

}

// MARK: - the Vault tree (BP-4 · P17)

/// The panel's files view: the pool grouped by format, one compact row per
/// file — click opens it in a tab. The SAME data the Library surface tables
/// (entities carrying a cell of kind "file"), rendered at panel density; the
/// Library stays the full browser, this is the always-there shortcut.
struct VaultTree: View {
    @ObservedObject var model: BoxModel
    @Binding var filter: String
    var openEntity: (UInt64) -> Void = { _ in }

    private var files: [EntityRow] {
        model.rows(model.snap?.everything ?? []).filter { row in
            row.cells.contains { $0.kind == "file" }
                && (filter.isEmpty || row.title.localizedCaseInsensitiveContains(filter))
        }
    }

    /// Pools by `format` (the file anchor, P15) — a fact, so plain groups, no
    /// value rainbow.
    private var pools: [(format: String, rows: [EntityRow])] {
        let grouped = Dictionary(grouping: files) { row in
            row.cells.first { $0.property == "format" && !$0.value.isEmpty }?.value ?? "file"
        }
        return grouped.keys.sorted().map { (format: $0, rows: grouped[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.mutedFg)
                TextField("Filter…", text: $filter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(Divider(), alignment: .bottom)

            if files.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 24))
                        .foregroundColor(Theme.foreground.opacity(0.12))
                    Text(filter.isEmpty
                        ? "No files yet. Import with ⌘⇧I, or drop files on the window."
                        : "Nothing matches.")
                        .font(.system(size: 11.5))
                        .foregroundColor(Theme.mutedFg)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(pools, id: \.format) { pool in
                            Text("\(pool.format.uppercased()) · \(pool.rows.count)")
                                .font(.system(size: 11, weight: .bold))
                                .kerning(0.6)
                                .foregroundColor(Theme.mutedFg)
                                .padding(.horizontal, 6)
                                .padding(.top, 8)
                                .padding(.bottom, 2)
                            ForEach(pool.rows, id: \.id) { row in
                                fileRow(row)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
    }

    private func fileRow(_ row: EntityRow) -> some View {
        Button { openEntity(row.id) } label: {
            HStack(spacing: 7) {
                Image(systemName: "doc")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.mutedFg)
                    .frame(width: 16)
                Text(row.title)
                    .font(.system(size: 12.5))
                    .foregroundColor(Theme.foreground.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - the Spaces tree (§2.2.2)

struct SpacesTree: View {
    @ObservedObject var model: BoxModel
    @ObservedObject var chrome: ChromeModel
    @Binding var lens: Lens
    @Binding var query: String
    @Binding var selection: UInt64?
    @Binding var filter: String
    var willNavigate: (@escaping () -> Void) -> Void
    /// The desk lens buttons land on the desk tab (and set the lens).
    var showDesk: (Lens) -> Void = { _ in }
    /// Open a bookmarked entity in a tab (the pin rows).
    var openEntity: (UInt64) -> Void = { _ in }

    @State private var expanded: Set<UInt64> = []
    @State private var archiveOpen = false
    @State private var creating = false
    @State private var newName = ""
    @State private var spacesDropActive = false
    @State private var boardsDropActive = false
    @FocusState private var newNameFocused: Bool

    /// The pinned entities — anything whose `bookmarked` cell is set, filtered
    /// like every other row here.
    private var bookmarkedRows: [EntityRow] {
        model.rows(model.snap?.everything ?? []).filter { row in
            row.bookmarked
                && (filter.isEmpty || row.title.localizedCaseInsensitiveContains(filter))
        }
    }

    private var tree: WorkspaceTree {
        WorkspaceTree(model.snap?.workspaces ?? [])
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter box: non-matching rows simply vanish (§2.2.2).
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.mutedFg)
                TextField("Filter…", text: $filter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(Divider(), alignment: .bottom)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    // Interim desk rows until tabs land (P3).
                    deskGroup
                    // ONE pin source (BP-4): favourite workspaces AND bookmarked
                    // entities share this section. A bookmark is the entity's
                    // existing `bookmarked` cell (the inspector's 🔖 writes it) —
                    // no new chrome row, no second pin system.
                    if !tree.favourites.isEmpty || !bookmarkedRows.isEmpty {
                        groupHeader("Favourites")
                        ForEach(tree.favourites, id: \.id) { row in
                            if matches(row) {
                                WorkspaceLeaf(row: row, tree: tree, actions: actions)
                            }
                        }
                        ForEach(bookmarkedRows, id: \.id) { row in
                            bookmarkRow(row)
                        }
                    }
                    groupHeader("Spaces")
                        .background(headerDropHighlight(spacesDropActive))
                        .onDrop(
                            of: [.plainText], delegate:
                                HeaderReroot(active: $spacesDropActive, actions: actions))
                    ForEach(tree.spaces, id: \.id) { row in
                        treeRows(row, depth: 0)
                    }
                    if !tree.boards.isEmpty {
                        Divider().padding(.vertical, 4)
                        groupHeader("Boards")
                            .background(headerDropHighlight(boardsDropActive))
                            .onDrop(
                                of: [.plainText], delegate:
                                    HeaderReroot(active: $boardsDropActive, actions: actions))
                        ForEach(tree.boards, id: \.id) { row in
                            if matches(row) {
                                WorkspaceLeaf(row: row, tree: tree, actions: actions)
                            }
                        }
                    }
                    if creating {
                        InlineInput(
                            placeholder: "New workspace…", text: $newName,
                            focused: $newNameFocused,
                            commit: {
                                let name = newName.trimmingCharacters(in: .whitespaces)
                                creating = false
                                newName = ""
                                if !name.isEmpty {
                                    model.createWorkspace(name: name, parent: 0) { id in
                                        if let id = id { actions.enter(id) }
                                    }
                                }
                            },
                            cancel: {
                                creating = false
                                newName = ""
                            })
                    }
                    if !tree.archived.isEmpty {
                        archiveGroup
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }

            Spacer(minLength: 0)
            if model.boxBusy {
                Label("box is busy — retrying", systemImage: "hourglass")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(8)
            }
            Button {
                creating = true
                DispatchQueue.main.async { newNameFocused = true }
            } label: {
                Label("New workspace", systemImage: "plus")
                    .font(.system(size: 12.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(Theme.mutedFg)
            .overlay(Divider(), alignment: .top)
        }
    }

    private var actions: WorkspaceActions {
        WorkspaceActions(model: model, chrome: chrome, tree: tree) { onSuccess in
            willNavigate {
                onSuccess()
                query = ""
                lens = .today
            }
        }
    }

    /// Interim: the desk's own views, until the tab strip owns them.
    private var deskGroup: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach([Lens.today, .capture, .everything]) { item in
                Button {
                    // Land on the desk tab, then set the lens — a lens
                    // switch while a note tab is active must show the desk.
                    showDesk(item)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 12))
                            .frame(width: 16)
                            .foregroundColor(lens == item ? Theme.primary : .secondary)
                        Text(item.rawValue)
                            .font(.system(size: 13, weight: lens == item ? .semibold : .regular))
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusMd)
                        .fill(lens == item ? Theme.primary.opacity(0.1) : .clear)
                )
            }
            Divider().padding(.vertical, 4)
        }
    }

    private func groupHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .kerning(0.6)
            .foregroundColor(Theme.mutedFg)
            .padding(.horizontal, 6)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }

    /// A pinned entity in Favourites: kind icon + title, click opens its tab.
    /// Unpin from the context menu — the same `bookmarked` cell the inspector's
    /// 🔖 toggles, one write path.
    private func bookmarkRow(_ row: EntityRow) -> some View {
        Button { openEntity(row.id) } label: {
            HStack(spacing: 7) {
                Image(systemName: rowKindIcon(row))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.mutedFg)
                    .frame(width: 16)
                Text(row.title)
                    .font(.system(size: 12.5))
                    .foregroundColor(Theme.foreground.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove bookmark") {
                model.set(row.id, property: "bookmarked", value: "false")
            }
        }
    }

    @ViewBuilder
    private func headerDropHighlight(_ active: Bool) -> some View {
        RoundedRectangle(cornerRadius: Theme.radiusSm)
            .fill(active ? Theme.primary.opacity(0.1) : .clear)
    }

    private var archiveGroup: some View {
        VStack(alignment: .leading, spacing: 1) {
            Button {
                archiveOpen.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: archiveOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Archive · \(tree.archived.count)")
                        .font(.system(size: 11, weight: .bold))
                        .kerning(0.6)
                }
                .foregroundColor(Theme.mutedFg)
                .padding(.horizontal, 6)
                .padding(.top, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if archiveOpen {
                ForEach(tree.archived, id: \.id) { row in
                    HStack(spacing: 8) {
                        WorkspaceGlyph(row: row, tree: tree, expanded: false)
                        Text(row.name).font(.system(size: 13)).foregroundColor(Theme.mutedFg)
                        Spacer()
                        Button("Restore") { actions.restore(row.id) }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.primary)
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 6)
                    .opacity(0.65)
                    .contextMenu {
                        Button("Restore workspace") { actions.restore(row.id) }
                    }
                }
            }
        }
    }

    private func matches(_ row: WorkspaceRow) -> Bool {
        guard !filter.isEmpty else { return true }
        if row.name.localizedCaseInsensitiveContains(filter) { return true }
        return tree.kids(of: row.id).contains { matches($0) }
    }

    @ViewBuilder
    private func treeRows(_ row: WorkspaceRow, depth: Int) -> AnyView {
        AnyView(
            Group {
                if matches(row) && !row.archived {
                    TreeItem(
                        row: row, tree: tree, depth: depth,
                        expanded: expanded.contains(row.id),
                        active: chrome.activeWorkspace == row.id,
                        toggle: {
                            if expanded.contains(row.id) {
                                expanded.remove(row.id)
                            } else {
                                expanded.insert(row.id)
                            }
                        },
                        actions: actions)
                    if expanded.contains(row.id) {
                        ForEach(tree.kids(of: row.id), id: \.id) { kid in
                            treeRows(kid, depth: depth + 1)
                        }
                    }
                }
            })
    }
}

/// Every workspace mutation, one place — each is one transaction.
struct WorkspaceActions {
    let model: BoxModel
    let chrome: ChromeModel
    let tree: WorkspaceTree
    /// The navigation gate: flush an open editor, then — only if the
    /// flush succeeds — run the passed work and land on the desk. A
    /// refused flush cancels the whole switch. Never mutate the active
    /// workspace outside this gate.
    let landed: (@escaping () -> Void) -> Void

    /// Entering scopes the notes surface. The active-workspace switch
    /// and the nav entry ride inside the flush gate, so a refused flush
    /// leaves both untouched.
    func enter(_ id: UInt64) {
        landed {
            chrome.activeWorkspace = id
            chrome.recordNav(.init(workspace: id, surface: .notes, selection: nil))
        }
    }

    func addChild(of id: UInt64, name: String) {
        model.createWorkspace(name: name, parent: id) { _ in }
    }

    func rename(_ id: UInt64) {
        let current = tree.row(id)?.name ?? ""
        Dialogs.shared.prompt(
            "Rename workspace", placeholder: current, initial: current, confirmLabel: "Rename"
        ) { name in
            guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
                return
            }
            model.set(id, property: "name", value: name)
        }
    }

    func changeEmoji(_ id: UInt64) {
        Dialogs.shared.prompt(
            "Change emoji", message: "One emoji, or empty to clear.",
            initial: tree.row(id)?.emoji ?? ""
        ) { emoji in
            guard let emoji = emoji?.trimmingCharacters(in: .whitespaces) else { return }
            if emoji.isEmpty {
                model.unset(id, property: "emoji")
            } else {
                model.set(id, property: "emoji", value: String(emoji.prefix(2)))
            }
        }
    }

    func favorite(_ id: UInt64, _ starred: Bool) {
        model.set(id, property: "favorite", value: starred ? "true" : "false")
    }

    func archive(_ id: UInt64) {
        model.set(id, property: "archived", value: "true")
        // An archived workspace is no longer a live scope; its live
        // children re-root and stay reachable, so only the archived id
        // itself can strand the active scope.
        if chrome.activeWorkspace == id {
            chrome.activeWorkspace = nil
        }
    }

    func restore(_ id: UInt64) {
        model.set(id, property: "archived", value: "false")
    }

    func makeTopLevel(_ id: UInt64) {
        model.unset(id, property: "parent")
    }

    /// Delete never cascades (the core law): only this workspace is
    /// trashed; its children keep their now-dangling parent and re-root
    /// to the top level. The confirm says so. (A dangling active scope
    /// left by any path is reconciled to Home on the next snapshot.)
    func trash(_ id: UInt64) {
        let children = tree.descendantCount(of: id)
        let message = children > 0
            ? "Its \(children) child workspace\(children == 1 ? "" : "s") will move to the top level. Undo with ⌘⌥Z."
            : "This can be undone with ⌘⌥Z."
        Dialogs.shared.confirm(
            "Delete workspace?", message: message, danger: true, confirmLabel: "Delete"
        ) { yes in
            guard yes else { return }
            model.trashWorkspace(id)
            if chrome.activeWorkspace == id {
                chrome.activeWorkspace = nil
            }
        }
    }

    /// 3-zone drop (§2.2.3): before/after reorder among the target's
    /// siblings; into re-parents to a trailing position.
    func drop(_ dragged: UInt64, onto target: UInt64, zone: DropZone) {
        guard dragged != target, let targetRow = tree.row(target) else { return }
        // Cycle guard: never drop onto your own descendant.
        var cursor: UInt64? = target
        while let current = cursor, current != 0 {
            if current == dragged { return }
            cursor = tree.row(current)?.parent
        }
        switch zone {
        case .into:
            model.set(dragged, property: "parent", value: "#\(target)")
        case .before, .after:
            let siblings = targetRow.parent == 0
                ? tree.topLevel : tree.kids(of: targetRow.parent)
            guard let at = siblings.firstIndex(where: { $0.id == target }) else { return }
            let neighbor: Double? = zone == .before
                ? (at > 0 ? siblings[at - 1].order : nil)
                : (at + 1 < siblings.count ? siblings[at + 1].order : nil)
            let order: Double = {
                switch (zone, neighbor) {
                case (_, .some(let n)): return (targetRow.order + n) / 2
                case (.before, nil): return targetRow.order - 10
                default: return targetRow.order + 10
                }
            }()
            if targetRow.parent == 0 {
                model.unset(dragged, property: "parent")
            } else {
                model.set(dragged, property: "parent", value: "#\(targetRow.parent)")
            }
            model.set(dragged, property: "order", value: String(order))
        }
    }
}

enum DropZone {
    case before, into, after
}

// MARK: - tree row (§2.2.3)

struct TreeItem: View {
    let row: WorkspaceRow
    let tree: WorkspaceTree
    let depth: Int
    let expanded: Bool
    let active: Bool
    let toggle: () -> Void
    let actions: WorkspaceActions

    @State private var hovering = false
    @State private var addingChild = false
    @State private var childName = ""
    @State private var dropZone: DropZone?
    @FocusState private var childFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Button(action: toggle) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Theme.mutedFg)
                        .frame(width: 16)
                        .opacity(tree.kids(of: row.id).isEmpty ? 0 : 1)
                }
                .buttonStyle(.plain)
                WorkspaceGlyph(row: row, tree: tree, expanded: expanded)
                Button {
                    actions.enter(row.id)
                } label: {
                    Text(row.name)
                        .font(.system(
                            size: 13,
                            weight: tree.kids(of: row.id).isEmpty ? .regular : .medium))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if hovering {
                    Button {
                        addingChild = true
                        DispatchQueue.main.async { childFocused = true }
                    } label: {
                        Image(systemName: "plus").font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.mutedFg)
                    .help("Add \(tree.childLabel(for: row.id))")
                    Menu {
                        menuItems
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 10))
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 20)
                }
            }
            .padding(.vertical, 4)
            .padding(.leading, CGFloat(depth) * 12 + 4)
            .padding(.trailing, 6)
            .background(rowBackground)
            .overlay(dropIndicator)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .contextMenu { menuItems }
            .onDrag {
                NSItemProvider(object: "workspace:\(row.id)" as NSString)
            }
            .onDrop(
                of: [.plainText],
                delegate: TreeDrop(target: row.id, zone: $dropZone, actions: actions))

            if addingChild {
                InlineInput(
                    placeholder: "New \(tree.childLabel(for: row.id))…", text: $childName,
                    focused: $childFocused,
                    commit: {
                        let name = childName.trimmingCharacters(in: .whitespaces)
                        addingChild = false
                        childName = ""
                        if !name.isEmpty {
                            actions.addChild(of: row.id, name: name)
                        }
                    },
                    cancel: {
                        addingChild = false
                        childName = ""
                    }
                )
                .padding(.leading, CGFloat(depth + 1) * 12 + 4)
            }
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("Change emoji") { actions.changeEmoji(row.id) }
        Button("Rename") { actions.rename(row.id) }
        if row.builtin.isEmpty {
            Button(row.favorite ? "Remove from favorites" : "Add to favorites") {
                actions.favorite(row.id, !row.favorite)
            }
            if row.parent != 0 {
                Button("Make top-level space") { actions.makeTopLevel(row.id) }
            }
            Button("Archive workspace") { actions.archive(row.id) }
            Divider()
            Button("Delete workspace", role: .destructive) { actions.trash(row.id) }
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: Theme.radiusMd)
            .fill(active ? Theme.primary.opacity(0.13) : .clear)
            .overlay(alignment: .leading) {
                if active {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Theme.primary)
                        .frame(width: 2)
                        .padding(.vertical, 3)
                }
            }
    }

    @ViewBuilder
    private var dropIndicator: some View {
        switch dropZone {
        case .before:
            VStack {
                Rectangle().fill(Theme.primary).frame(height: 2)
                Spacer()
            }
        case .after:
            VStack {
                Spacer()
                Rectangle().fill(Theme.primary).frame(height: 2)
            }
        case .into:
            RoundedRectangle(cornerRadius: Theme.radiusMd)
                .strokeBorder(Theme.primary.opacity(0.5), lineWidth: 1)
                .padding(1)
        case nil:
            EmptyView()
        }
    }
}

/// The 3-zone drop: top 28% before, bottom 28% after, middle into.
struct TreeDrop: DropDelegate {
    let target: UInt64
    @Binding var zone: DropZone?
    let actions: WorkspaceActions

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let height: CGFloat = 26
        let y = info.location.y
        zone = y < height * 0.28 ? .before : (y > height * 0.72 ? .after : .into)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        zone = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let landed = zone ?? .into
        zone = nil
        return loadWorkspaceDrop(info) { id in
            actions.drop(id, onto: target, zone: landed)
        }
    }
}

/// Load a "workspace:<id>" drag payload and run `handle` on the main
/// queue. Returns whether a provider was present.
func loadWorkspaceDrop(_ info: DropInfo, _ handle: @escaping (UInt64) -> Void) -> Bool {
    guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
    provider.loadObject(ofClass: NSString.self) { object, _ in
        guard let text = object as? String, text.hasPrefix("workspace:"),
            let id = UInt64(text.dropFirst("workspace:".count))
        else { return }
        DispatchQueue.main.async { handle(id) }
    }
    return true
}

/// The Spaces / Boards group headers are drop targets that re-root the
/// dropped node to the top level (§2.2.2): dropping onto Spaces promotes
/// a flat workspace to a standalone space; dropping onto Boards pulls a
/// tree node back to top level. In lotus the Spaces/Boards split is
/// derived from live children, so both are one gesture: unset parent.
struct HeaderReroot: DropDelegate {
    @Binding var active: Bool
    let actions: WorkspaceActions

    func dropEntered(info: DropInfo) { active = true }
    func dropExited(info: DropInfo) { active = false }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        active = false
        return loadWorkspaceDrop(info) { id in actions.makeTopLevel(id) }
    }
}

/// Flat rows (Favourites / Boards) drag-reorder among themselves
/// (§2.2.3): two zones, before/after by the row's vertical halves.
struct LeafReorder: DropDelegate {
    let target: UInt64
    @Binding var zone: DropZone?
    let actions: WorkspaceActions

    func dropUpdated(info: DropInfo) -> DropProposal? {
        zone = info.location.y < 13 ? .before : .after
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) { zone = nil }

    func performDrop(info: DropInfo) -> Bool {
        let landed = zone ?? .after
        zone = nil
        return loadWorkspaceDrop(info) { id in
            actions.drop(id, onto: target, zone: landed)
        }
    }
}

/// Glyph rules (§2.2.3): emoji override; parent → tinted folder
/// (open when expanded); leaf → duotone dashboard glyph in the accent.
struct WorkspaceGlyph: View {
    let row: WorkspaceRow
    let tree: WorkspaceTree
    let expanded: Bool

    var body: some View {
        if let emoji = row.emoji, !emoji.isEmpty {
            Text(emoji).font(.system(size: 15))
        } else if row.builtin == "home" {
            Image(systemName: "house")
                .font(.system(size: 12))
                .foregroundColor(Theme.mutedFg)
        } else if !tree.kids(of: row.id).isEmpty {
            Image(systemName: expanded ? "folder.fill" : "folder")
                .font(.system(size: 12))
                .foregroundColor(WorkspaceTree.accent(for: row.id))
        } else {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 12))
                .foregroundColor(WorkspaceTree.accent(for: row.id))
        }
    }
}

/// A flat workspace row (Favourites / Boards): §2.2.3 WorkspaceListItem.
struct WorkspaceLeaf: View {
    let row: WorkspaceRow
    let tree: WorkspaceTree
    let actions: WorkspaceActions

    @State private var hovering = false
    @State private var dropZone: DropZone?

    var body: some View {
        HStack(spacing: 8) {
            WorkspaceGlyph(row: row, tree: tree, expanded: false)
            Button {
                actions.enter(row.id)
            } label: {
                Text(row.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if hovering && row.builtin.isEmpty {
                Button {
                    actions.favorite(row.id, !row.favorite)
                } label: {
                    Image(systemName: row.favorite ? "star.fill" : "star")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.mutedFg)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMd)
                .fill(
                    actions.chrome.activeWorkspace == row.id
                        ? Theme.primary.opacity(0.13) : .clear)
        )
        .overlay(alignment: dropZone == .before ? .top : .bottom) {
            if dropZone != nil {
                Rectangle().fill(Theme.primary).frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open") { actions.enter(row.id) }
            if row.builtin.isEmpty {
                Button(row.favorite ? "Remove from favorites" : "Add to favorites") {
                    actions.favorite(row.id, !row.favorite)
                }
                Button("Make top-level space") { actions.makeTopLevel(row.id) }
                Divider()
                Button("Archive workspace") { actions.archive(row.id) }
                Button("Delete workspace", role: .destructive) { actions.trash(row.id) }
            }
        }
        .onDrag {
            NSItemProvider(object: "workspace:\(row.id)" as NSString)
        }
        .onDrop(
            of: [.plainText],
            delegate: LeafReorder(target: row.id, zone: $dropZone, actions: actions))
    }
}

/// Enter commits, Escape cancels, blur cancels (§2.2.2 InlineInput).
struct InlineInput: View {
    let placeholder: String
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let commit: () -> Void
    let cancel: () -> Void

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .focused(focused)
            .onSubmit(commit)
            .onExitCommand(perform: cancel)
            .onChange(of: focused.wrappedValue) {
                if !focused.wrappedValue { cancel() }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMd)
                    .strokeBorder(Theme.primary.opacity(0.5))
            )
    }
}

// MARK: - properties browser (§2.2.5)

struct PropertiesBrowser: View {
    @ObservedObject var model: BoxModel
    @Binding var selection: UInt64?
    var openEntity: (UInt64) -> Void

    @State private var filter = ""
    @State private var drilldown: (key: String, value: String?)?

    private var counted: [(key: String, total: Int, values: [(String, Int)])] {
        var byKey: [String: [String]] = [:]
        for entity in model.snap?.entities ?? [] {
            for cell in entity.cells {
                byKey[cell.property, default: []].append(cell.value)
            }
        }
        return byKey
            .filter { filter.isEmpty || $0.key.localizedCaseInsensitiveContains(filter) }
            .map { key, values in
                var counts: [String: Int] = [:]
                for value in values {
                    counts[value, default: 0] += 1
                }
                let sorted = counts.sorted {
                    $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
                }
                return (key, values.count, Array(sorted.prefix(140)).map { ($0.key, $0.value) })
            }
            .sorted { $0.total > $1.total }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.mutedFg)
                TextField("Filter properties…", text: $filter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(Divider(), alignment: .bottom)

            if counted.isEmpty {
                Text(filter.isEmpty ? "No properties yet." : "No properties match.")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.mutedFg)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(counted, id: \.key) { entry in
                            Button {
                                drilldown = (entry.key, nil)
                            } label: {
                                HStack {
                                    Text(entry.key).font(.system(size: 12, weight: .semibold))
                                    Spacer()
                                    Text("\(entry.total)")
                                        .font(.system(size: 11).monospacedDigit())
                                        .foregroundColor(Theme.mutedFg)
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            ForEach(entry.values.prefix(12), id: \.0) { value, count in
                                Button {
                                    drilldown = (entry.key, value)
                                } label: {
                                    HStack {
                                        Text(value).font(.system(size: 12)).lineLimit(1)
                                        Spacer()
                                        Text("\(count)")
                                            .font(.system(size: 11).monospacedDigit())
                                            .foregroundColor(Theme.mutedFg)
                                    }
                                    .padding(.vertical, 2)
                                    .padding(.leading, 18)
                                    .padding(.trailing, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            if let active = drilldown {
                drilldownSection(active)
            }
        }
    }

    /// Single-click focuses, double-click opens (§2.2.5).
    private func drilldownSection(_ active: (key: String, value: String?)) -> some View {
        let hits = (model.snap?.entities ?? []).filter { entity in
            entity.cells.contains { cell in
                cell.property == active.key
                    && (active.value == nil || cell.value == active.value)
            }
        }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("\(active.key)\(active.value.map { " \($0)" } ?? "") (\(hits.count))")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Button {
                    drilldown = nil
                } label: {
                    Image(systemName: "xmark").font(.system(size: 9))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.secondary.opacity(0.3))
            if hits.isEmpty {
                Text("No objects.")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.mutedFg)
                    .padding(10)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(hits) { row in
                            Button {
                                selection = row.id
                            } label: {
                                HStack {
                                    Text(row.title).font(.system(size: 12)).lineLimit(1)
                                    Spacer()
                                    Text(row.kinds.first ?? "")
                                        .font(.system(size: 10.5))
                                        .foregroundColor(Theme.mutedFg)
                                }
                                .padding(.vertical, 3)
                                .padding(.horizontal, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(
                                selection == row.id ? Theme.primary.opacity(0.1) : .clear
                            )
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded { openEntity(row.id) }
                            )
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .overlay(Divider(), alignment: .top)
    }
}

// MARK: - bookmarks (§2.2.1 Saved)

struct BookmarksPanel: View {
    @ObservedObject var model: BoxModel
    @Binding var selection: UInt64?
    var openEntity: (UInt64) -> Void

    private var starred: [EntityRow] {
        (model.snap?.entities ?? []).filter { row in
            row.cells.contains { $0.property == "bookmarked" && $0.value == "yes" }
        }
    }

    var body: some View {
        if starred.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "bookmark")
                    .font(.system(size: 26))
                    .foregroundColor(Theme.foreground.opacity(0.12))
                Text("Nothing saved yet. ⌘⇧B bookmarks the selected object.")
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.mutedFg)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(starred) { row in
                        Button {
                            selection = row.id
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "bookmark.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(Theme.mutedFg)
                                Text(row.title).font(.system(size: 13)).lineLimit(1)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(selection == row.id ? Theme.primary.opacity(0.1) : .clear)
                        .simultaneousGesture(TapGesture(count: 2).onEnded { openEntity(row.id) })
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - HomeHub popover (§2.7.2)

struct HomeHubPopover: View {
    @ObservedObject var model: BoxModel
    @ObservedObject var chrome: ChromeModel
    let actions: WorkspaceActions
    let dismiss: () -> Void

    /// bp4 ⑦: type-to-filter on top — never a full dump. Typing swaps the
    /// tree for flat matches; ↑↓ move, ⏎ enters, Esc closes.
    @State private var filter = ""
    @State private var highlighted = 0
    @FocusState private var filterFocused: Bool

    private var tree: WorkspaceTree {
        WorkspaceTree(model.snap?.workspaces ?? [])
    }

    private var matches: [WorkspaceRow] {
        tree.rows
            .filter { !$0.archived && $0.name.localizedCaseInsensitiveContains(filter) }
            .sorted { $0.order < $1.order }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.mutedFg)
                TextField("Switch workspace…", text: $filter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($filterFocused)
                    .onSubmit {
                        if matches.indices.contains(highlighted) {
                            actions.enter(matches[highlighted].id)
                        }
                        dismiss()
                    }
                    .onExitCommand { dismiss() }
                    .onKeyPress(.downArrow) {
                        highlighted = min(highlighted + 1, max(0, matches.count - 1))
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        highlighted = max(highlighted - 1, 0)
                        return .handled
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            Divider()
            if !filter.isEmpty {
                filteredList
            } else {
                if chrome.surface.isGlobalTool {
                    Text("Vault-wide tool — open a workspace:")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.mutedFg)
                        .padding(10)
                } else {
                    scopeSection
                }
                Divider()
                ScrollView {
                    WorkspaceList(model: model, chrome: chrome, actions: actions, dismiss: dismiss)
                }
                .frame(maxHeight: 280)
                Divider()
                footer
            }
        }
        .frame(width: 288)
        .onChange(of: filter) { highlighted = 0 }
    }

    @ViewBuilder
    private var filteredList: some View {
        if matches.isEmpty {
            Text("No workspace matches \"\(filter)\".")
                .font(.system(size: 12))
                .foregroundColor(Theme.mutedFg)
                .padding(12)
        } else {
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { index, row in
                        Button {
                            actions.enter(row.id)
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                WorkspaceGlyph(row: row, tree: tree, expanded: false)
                                Text(row.name).font(.system(size: 12.5))
                                Spacer()
                                if chrome.activeWorkspace == row.id
                                    || (chrome.activeWorkspace == nil && row.builtin == "home")
                                {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(Theme.accent)
                                }
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.radiusMd)
                                .fill(index == highlighted ? Theme.primary.opacity(0.12) : .clear)
                        )
                        .onHover { inside in if inside { highlighted = index } }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 280)
        }
    }

    private var scopeSection: some View {
        let active = chrome.activeWorkspace.flatMap { tree.row($0) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let emoji = active?.emoji, !emoji.isEmpty {
                    Text(emoji)
                }
                Text(active?.name ?? "Home").font(.system(size: 13, weight: .semibold))
            }
            HStack(spacing: 6) {
                scopeChip("area", "—")
                scopeChip("project", "—")
            }
        }
        .padding(10)
    }

    private func scopeChip(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 10)).foregroundColor(Theme.mutedFg)
            Text(value).font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Theme.secondary.opacity(0.5)))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            popoverRow("New workspace") {
                dismiss()
                Dialogs.shared.prompt(
                    "New workspace", placeholder: "Name", confirmLabel: "Create"
                ) { name in
                    guard let name = name?.trimmingCharacters(in: .whitespaces),
                        !name.isEmpty
                    else { return }
                    model.createWorkspace(name: name, parent: 0) { id in
                        if let id = id { actions.enter(id) }
                    }
                }
            }
            let active = chrome.activeWorkspace.flatMap { tree.row($0) }
            popoverRow("Rename current", disabled: active == nil || active?.builtin == "home") {
                if let id = active?.id {
                    dismiss()
                    actions.rename(id)
                }
            }
            popoverRow("Archive current", disabled: active == nil || active?.builtin == "home") {
                if let id = active?.id {
                    dismiss()
                    actions.archive(id)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func popoverRow(
        _ label: String, disabled: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .foregroundColor(disabled ? Theme.mutedFg.opacity(0.5) : Theme.foreground)
    }
}

/// Shared by HomeHub and (later) pickers: favourites → spaces with
/// children → boards. Rows show glyph · name · star on hover.
struct WorkspaceList: View {
    @ObservedObject var model: BoxModel
    @ObservedObject var chrome: ChromeModel
    let actions: WorkspaceActions
    let dismiss: () -> Void

    private var tree: WorkspaceTree {
        WorkspaceTree(model.snap?.workspaces ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if !tree.favourites.isEmpty {
                listHeader("Favorites")
                ForEach(tree.favourites, id: \.id) { row in listRow(row) }
            }
            listHeader("Workspaces")
            ForEach(tree.spaces, id: \.id) { row in
                listRow(row)
                ForEach(tree.kids(of: row.id), id: \.id) { kid in
                    listRow(kid, indent: true)
                }
            }
            ForEach(tree.boards, id: \.id) { row in listRow(row) }
        }
        .padding(6)
    }

    private func listHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .kerning(0.5)
            .foregroundColor(Theme.mutedFg)
            .padding(.horizontal, 6)
            .padding(.top, 6)
    }

    private func listRow(_ row: WorkspaceRow, indent: Bool = false) -> some View {
        Button {
            actions.enter(row.id)
            dismiss()
        } label: {
            HStack(spacing: 7) {
                WorkspaceGlyph(row: row, tree: tree, expanded: false)
                Text(row.name).font(.system(size: 12.5)).lineLimit(1)
                Spacer()
                if chrome.activeWorkspace == row.id
                    || (chrome.activeWorkspace == nil && row.builtin == "home")
                {
                    Text("current")
                        .font(.system(size: 9.5))
                        .foregroundColor(Theme.mutedFg)
                }
            }
            .padding(.vertical, 4)
            .padding(.leading, indent ? 22 : 6)
            .padding(.trailing, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMd)
                .fill(chrome.activeWorkspace == row.id ? Theme.primary.opacity(0.1) : .clear)
        )
    }
}

// MARK: - workspace switcher (§2.7.3)

struct WorkspaceSwitcher: View {
    @ObservedObject var model: BoxModel
    @ObservedObject var chrome: ChromeModel
    let actions: WorkspaceActions
    let dismiss: () -> Void

    @State private var filter = ""
    @State private var highlighted = 0
    @State private var keyMonitor: Any?
    @FocusState private var fieldFocused: Bool

    private var matches: [WorkspaceRow] {
        let tree = WorkspaceTree(model.snap?.workspaces ?? [])
        let live = tree.rows.filter { !$0.archived }.sorted { $0.order < $1.order }
        guard !filter.isEmpty else { return live }
        return live.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.background.opacity(0.6)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
            VStack(spacing: 0) {
                TextField("Switch workspace…", text: $filter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($fieldFocused)
                    .padding(12)
                    .onSubmit {
                        if matches.indices.contains(highlighted) {
                            actions.enter(matches[highlighted].id)
                        }
                        dismiss()
                    }
                    .onExitCommand { dismiss() }
                Divider()
                if matches.isEmpty {
                    Text("No workspace matches \"\(filter)\".")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.mutedFg)
                        .padding(14)
                } else {
                    ScrollView {
                        VStack(spacing: 1) {
                            ForEach(Array(matches.enumerated()), id: \.element.id) {
                                index, row in
                                Button {
                                    actions.enter(row.id)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 8) {
                                        WorkspaceGlyph(
                                            row: row,
                                            tree: WorkspaceTree(model.snap?.workspaces ?? []),
                                            expanded: false)
                                        Text(row.name).font(.system(size: 13))
                                        Spacer()
                                        if chrome.activeWorkspace == row.id {
                                            Text("current")
                                                .font(.system(size: 10))
                                                .foregroundColor(Theme.mutedFg)
                                        }
                                    }
                                    .padding(.vertical, 5)
                                    .padding(.horizontal, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .background(
                                    RoundedRectangle(cornerRadius: Theme.radiusMd)
                                        .fill(
                                            index == highlighted
                                                ? Theme.primary.opacity(0.12) : .clear)
                                )
                                .onHover { inside in
                                    if inside { highlighted = index }
                                }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 300)
                }
            }
            .frame(maxWidth: 448)
            .background(RoundedRectangle(cornerRadius: Theme.radiusXl).fill(Theme.popover))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusXl).strokeBorder(Theme.border)
            )
            .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
            .padding(.top, 120)
            .onAppear {
                fieldFocused = true
                // ↑/↓ step the highlight while the palette is open —
                // the filter field keeps every other key.
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    switch event.keyCode {
                    case 125:
                        highlighted = min(max(matches.count - 1, 0), highlighted + 1)
                        return nil
                    case 126:
                        highlighted = max(0, highlighted - 1)
                        return nil
                    default:
                        return event
                    }
                }
            }
            .onDisappear {
                if let monitor = keyMonitor {
                    NSEvent.removeMonitor(monitor)
                    keyMonitor = nil
                }
            }
            .onChange(of: filter) { highlighted = 0 }
        }
    }
}
