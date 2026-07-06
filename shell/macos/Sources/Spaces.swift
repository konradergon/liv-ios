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
    private let children: [UInt64: [WorkspaceRow]]

    init(_ rows: [WorkspaceRow]) {
        self.rows = rows
        children = Dictionary(grouping: rows.filter { $0.parent != 0 }) { $0.parent }
    }

    func row(_ id: UInt64) -> WorkspaceRow? {
        rows.first { $0.id == id }
    }

    func kids(of id: UInt64) -> [WorkspaceRow] {
        (children[id] ?? []).sorted { $0.order < $1.order }
    }

    var topLevel: [WorkspaceRow] {
        rows.filter { $0.parent == 0 }.sorted { $0.order < $1.order }
    }

    /// Live = not archived, not under an archived ancestor.
    func isLive(_ row: WorkspaceRow) -> Bool {
        !row.archived
    }

    /// Favourites: starred, plus Home by default (§2.2.2).
    var favourites: [WorkspaceRow] {
        rows.filter { ($0.favorite || $0.builtin == "home") && !$0.archived }
            .sorted { $0.order < $1.order }
    }

    /// Spaces: top-level nodes with a live workspace anywhere below.
    var spaces: [WorkspaceRow] {
        topLevel.filter { !$0.archived && !kids(of: $0.id).isEmpty && $0.builtin.isEmpty }
    }

    /// Boards: standalone top-level workspaces (no children, non-Home).
    var boards: [WorkspaceRow] {
        topLevel.filter { !$0.archived && kids(of: $0.id).isEmpty && $0.builtin.isEmpty }
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

enum SidebarView: String, CaseIterable {
    case tree, vault, properties, bookmarks, graph

    var label: String {
        switch self {
        case .tree: return "Spaces"
        case .vault: return "Vault"
        case .properties: return "Props"
        case .bookmarks: return "Saved"
        case .graph: return "Graph"
        }
    }

    var tooltip: String {
        switch self {
        case .tree: return "Workspaces"
        case .vault: return "Vault"
        case .properties: return "Properties"
        case .bookmarks: return "Bookmarks"
        case .graph: return "Vault graph"
        }
    }

    var symbol: String {
        switch self {
        case .tree: return "square.grid.2x2"
        case .vault: return "folder"
        case .properties: return "slider.horizontal.3"
        case .bookmarks: return "bookmark"
        case .graph: return "point.3.connected.trianglepath.dotted"
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
    /// Navigation away flushes any open editor first.
    var willNavigate: () -> Void = {}
    var openEntity: (UInt64) -> Void = { _ in }

    @AppStorage("app.leftView.v1") private var viewRaw = SidebarView.tree.rawValue
    @State private var filter = ""

    private var view: SidebarView {
        SidebarView(rawValue: viewRaw) ?? .tree
    }

    var body: some View {
        VStack(spacing: 0) {
            // The interim search field (QuickSwitcher arrives in P6).
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TextField("Search", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused(searchFocused)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.7))
            )
            .padding(10)

            pickerStrip
            Divider()

            switch view {
            case .tree:
                SpacesTree(
                    model: model, chrome: chrome, lens: $lens, query: $query,
                    selection: $selection, filter: $filter,
                    willNavigate: willNavigate)
            case .properties:
                PropertiesBrowser(model: model, selection: $selection, openEntity: openEntity)
            case .bookmarks:
                BookmarksPanel(model: model, selection: $selection, openEntity: openEntity)
            case .vault:
                sidebarStub(
                    "folder",
                    "The Vault view becomes the import staging browser — it arrives with P12.")
            case .graph:
                sidebarStub("point.3.connected.trianglepath.dotted", "Coming soon.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SidebarMaterial().ignoresSafeArea())
    }

    /// The pinned h-10 view picker: five segmented boxes, icon above an
    /// 11px label (§2.2.1).
    private var pickerStrip: some View {
        HStack(spacing: 2) {
            ForEach(SidebarView.allCases, id: \.rawValue) { item in
                Button {
                    viewRaw = item.rawValue
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: item.symbol).font(.system(size: 12.5))
                        Text(item.label).font(.system(size: 11))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .foregroundColor(view == item ? Theme.primary : Theme.mutedFg)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.radiusMd)
                            .fill(view == item ? Theme.primary.opacity(0.1) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.tooltip)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
        .frame(height: 40)
    }

    private func sidebarStub(_ symbol: String, _ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundColor(Theme.foreground.opacity(0.12))
            Text(message)
                .font(.system(size: 11.5))
                .foregroundColor(Theme.mutedFg)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    var willNavigate: () -> Void

    @State private var expanded: Set<UInt64> = []
    @State private var archiveOpen = false
    @State private var creating = false
    @State private var newName = ""
    @FocusState private var newNameFocused: Bool

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
                    if !tree.favourites.isEmpty {
                        groupHeader("Favourites")
                        ForEach(tree.favourites, id: \.id) { row in
                            if matches(row) {
                                WorkspaceLeaf(row: row, tree: tree, actions: actions)
                            }
                        }
                    }
                    groupHeader("Spaces")
                    ForEach(tree.spaces, id: \.id) { row in
                        treeRows(row, depth: 0)
                    }
                    if !tree.boards.isEmpty {
                        Divider().padding(.vertical, 4)
                        groupHeader("Boards")
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
        WorkspaceActions(model: model, chrome: chrome, tree: tree) {
            willNavigate()
            query = ""
            lens = .today
        }
    }

    /// Interim: the desk's own views, until the tab strip owns them.
    private var deskGroup: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach([Lens.today, .everything]) { item in
                Button {
                    willNavigate()
                    query = ""
                    lens = item
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
    /// Runs after entering a workspace: land on the desk.
    let landed: () -> Void

    func enter(_ id: UInt64) {
        chrome.activeWorkspace = id
        chrome.recordNav(.init(surface: .notes, selection: nil))
        landed()
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

    func trash(_ id: UInt64) {
        let children = tree.descendantCount(of: id)
        let warning = children > 0
            ? "\(children) child workspace\(children == 1 ? "" : "s") will be trashed too."
            : "This can be undone with ⌘⌥Z."
        Dialogs.shared.confirm(
            "Delete workspace?", message: warning, danger: true, confirmLabel: "Delete"
        ) { yes in
            guard yes else { return }
            model.trashTree(id)
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
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? String, text.hasPrefix("workspace:"),
                let id = UInt64(text.dropFirst("workspace:".count))
            else { return }
            DispatchQueue.main.async {
                actions.drop(id, onto: target, zone: landed)
            }
        }
        return true
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
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open") { actions.enter(row.id) }
            if row.builtin.isEmpty {
                Button(row.favorite ? "Remove from favorites" : "Add to favorites") {
                    actions.favorite(row.id, !row.favorite)
                }
                Divider()
                Button("Archive workspace") { actions.archive(row.id) }
                Button("Delete workspace", role: .destructive) { actions.trash(row.id) }
            }
        }
        .onDrag {
            NSItemProvider(object: "workspace:\(row.id)" as NSString)
        }
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

    private var tree: WorkspaceTree {
        WorkspaceTree(model.snap?.workspaces ?? [])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
        .frame(width: 288)
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

// MARK: - SlotsBar (§2.4)

struct SlotChip: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case link, workspace, memo
    }

    var id = UUID()
    let kind: Kind
    var label: String
    /// link: URL / "note:<id>"; workspace: the id; memo: the text.
    var target: String
}

enum SlotStore {
    static func load() -> [SlotChip] {
        guard let data = UserDefaults.standard.data(forKey: "app.slots.v1"),
            let chips = try? JSONDecoder().decode([SlotChip].self, from: data)
        else { return [] }
        return chips
    }

    static func save(_ chips: [SlotChip]) {
        if let data = try? JSONEncoder().encode(chips) {
            UserDefaults.standard.set(data, forKey: "app.slots.v1")
        }
    }
}

struct SlotsBar: View {
    @ObservedObject var model: BoxModel
    @ObservedObject var chrome: ChromeModel
    var openNote: (UInt64) -> Void = { _ in }
    var enterWorkspace: (UInt64) -> Void = { _ in }

    @State private var chips = SlotStore.load()
    @State private var adderOpen = false
    @State private var memoOpen: UUID?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(chips) { chip in
                SlotChipView(
                    chip: chip,
                    isOpenMemo: memoOpen == chip.id,
                    activate: { activate(chip) },
                    remove: {
                        chips.removeAll { $0.id == chip.id }
                        SlotStore.save(chips)
                    },
                    memoText: memoBinding(chip)
                )
            }
            Button {
                adderOpen.toggle()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.mutedFg)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $adderOpen, arrowEdge: .bottom) {
                SlotAdder(model: model) { chip in
                    chips.append(chip)
                    SlotStore.save(chips)
                    adderOpen = false
                }
            }
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private func memoBinding(_ chip: SlotChip) -> Binding<String> {
        Binding(
            get: { chips.first { $0.id == chip.id }?.target ?? "" },
            set: { text in
                if let at = chips.firstIndex(where: { $0.id == chip.id }) {
                    chips[at].target = text
                    SlotStore.save(chips)
                }
            })
    }

    private func activate(_ chip: SlotChip) {
        switch chip.kind {
        case .memo:
            memoOpen = memoOpen == chip.id ? nil : chip.id
        case .workspace:
            if let id = UInt64(chip.target) {
                enterWorkspace(id)
            }
        case .link:
            if chip.target.hasPrefix("note:"), let id = UInt64(chip.target.dropFirst(5)) {
                openNote(id)
            } else if let url = normalized(chip.target) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func normalized(_ raw: String) -> URL? {
        if raw.contains("://") { return URL(string: raw) }
        return URL(string: "https://\(raw)")
    }
}

struct SlotChipView: View {
    let chip: SlotChip
    let isOpenMemo: Bool
    let activate: () -> Void
    let remove: () -> Void
    @Binding var memoText: String

    @State private var hovering = false

    private var symbol: String {
        switch chip.kind {
        case .link: return chip.target.hasPrefix("note:") ? "doc.text" : "link"
        case .workspace: return "square.grid.2x2"
        case .memo: return "note.text"
        }
    }

    var body: some View {
        Button(action: activate) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10.5))
                Text(chip.label).font(.system(size: 11.5)).lineLimit(1)
                if chip.kind == .memo && !memoText.isEmpty {
                    Circle().fill(Theme.primary).frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .frame(maxWidth: 140)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMd)
                    .fill(Theme.secondary.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd)
                    .strokeBorder(Theme.border.opacity(0.7))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(chip.kind == .memo ? String(memoText.prefix(120)) : chip.target)
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.mutedFg)
                        .background(Circle().fill(Theme.background))
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)
            }
        }
        .onHover { hovering = $0 }
        .popover(
            isPresented: Binding(
                get: { isOpenMemo },
                set: { open in if !open { activate() } }
            ), arrowEdge: .bottom
        ) {
            TextEditor(text: $memoText)
                .font(.system(size: 12))
                .frame(width: 288, height: 96)
                .padding(6)
        }
    }
}

/// The adder popover (§2.4): search over workspaces + bookmarked
/// notes; memo row; footer "Add link or /route" form.
struct SlotAdder: View {
    @ObservedObject var model: BoxModel
    let add: (SlotChip) -> Void

    @State private var search = ""
    @State private var linkLabel = ""
    @State private var linkTarget = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Search workspaces and bookmarks…", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(8)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    Button {
                        add(SlotChip(kind: .memo, label: "Memo", target: ""))
                    } label: {
                        adderRow("note.text", "Memory memo")
                    }
                    .buttonStyle(.plain)
                    ForEach(workspaceMatches, id: \.id) { row in
                        Button {
                            add(
                                SlotChip(
                                    kind: .workspace, label: row.name,
                                    target: "\(row.id)"))
                        } label: {
                            adderRow("square.grid.2x2", row.name)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(bookmarkMatches) { row in
                        Button {
                            add(
                                SlotChip(
                                    kind: .link, label: row.title,
                                    target: "note:\(row.id)"))
                        } label: {
                            adderRow("bookmark", row.title)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 200)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Add link").font(.system(size: 10, weight: .bold))
                    .foregroundColor(Theme.mutedFg)
                TextField("Label (optional)", text: $linkLabel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5))
                HStack(spacing: 6) {
                    TextField("URL", text: $linkTarget)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5))
                    Button("Add") {
                        let target = linkTarget.trimmingCharacters(in: .whitespaces)
                        guard !target.isEmpty else { return }
                        add(
                            SlotChip(
                                kind: .link,
                                label: linkLabel.isEmpty ? target : linkLabel,
                                target: target))
                        linkLabel = ""
                        linkTarget = ""
                    }
                    .controlSize(.small)
                }
            }
            .padding(8)
        }
        .frame(width: 320)
    }

    private var workspaceMatches: [WorkspaceRow] {
        let all = (model.snap?.workspaces ?? []).filter { !$0.archived }
        guard !search.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var bookmarkMatches: [EntityRow] {
        (model.snap?.entities ?? []).filter { row in
            row.cells.contains { $0.property == "bookmarked" && $0.value == "yes" }
                && (search.isEmpty || row.title.localizedCaseInsensitiveContains(search))
        }
    }

    private func adderRow(_ symbol: String, _ label: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundColor(Theme.mutedFg)
            Text(label).font(.system(size: 12)).lineLimit(1)
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}
