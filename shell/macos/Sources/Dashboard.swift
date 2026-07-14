// lotus — the Dashboard surface (P18e, bp8): survey and launch, never work.
// A real Surface in the chrome (the owner's 07-14 ruling — never an overlay);
// board cards float on the bare material; every row opens its real surface.
// Widgets are LENSES over existing collections — small backstage entities
// (kind + scope + span + order); adding one is a lens pointed at what already
// exists, config is the standard Inspector over the widget entity, and there
// is no template builder anywhere (the anti-Notion fence).

import AppKit
import SwiftUI

/// The widget registry: ONLY built kinds are listed (no dead gallery rows).
/// 18f–18h grow this list as their bodies land.
struct WidgetSpec {
    let kind: String
    let title: String
    let reads: String
    let defaultSpan: Double
}

let widgetRegistry: [WidgetSpec] = [
    WidgetSpec(
        kind: "tasks", title: "Tasks summary",
        reads: "reads → the task pool, counts by status", defaultSpan: 2),
    WidgetSpec(
        kind: "pinned", title: "Pinned",
        reads: "reads → the Favourites shelf (pins)", defaultSpan: 1),
]

struct DashboardView: View {
    @ObservedObject var model: BoxModel
    @ObservedObject var chrome: ChromeModel
    @Binding var selection: UInt64?
    var open: (UInt64) -> Void = { _ in }
    var navigate: (Surface) -> Void = { _ in }

    @State private var galleryOpen = false
    @State private var galleryFilter = ""
    @State private var hoveredCard: UInt64?
    @FocusState private var surfaceFocused: Bool

    /// This scope's widgets (Home = 0), in float-key order.
    private var widgets: [BoardWidgetRow] {
        (model.snap?.widgets ?? [])
            .filter { $0.workspace == (chrome.activeWorkspace ?? 0) }
    }

    private var scopeName: String {
        guard let id = chrome.activeWorkspace,
            let row = (model.snap?.workspaces ?? []).first(where: { $0.id == id })
        else { return "Home · all areas" }
        return row.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if widgets.isEmpty {
                emptyBoard
            } else {
                ScrollView {
                    boardGrid
                        .padding(.horizontal, 24)
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .focusable()
        .focusEffectDisabled()
        .focused($surfaceFocused)
        .onAppear { surfaceFocused = true }
        // Esc = places-history back — "returns exactly where you were"
        // without an overlay (the ported bp8 ㉔ trick).
        .onExitCommand { chrome.goBack() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Dashboard").font(.system(size: 21, weight: .bold))
            Text(scopeName)
                .font(.system(size: 10.5))
                .padding(.horizontal, 9).padding(.vertical, 1)
                .overlay(Capsule().strokeBorder(Theme.border))
                .foregroundColor(Theme.mutedFg)
            Text(Self.today.string(from: Date()))
                .font(.system(size: 11.5)).foregroundColor(Theme.mutedFg)
            Spacer()
            Button {
                galleryFilter = ""
                galleryOpen = true
            } label: {
                Text("＋ Add widget")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(Theme.accent)
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Theme.accent.opacity(0.45)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $galleryOpen, arrowEdge: .bottom) { gallery }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private static let today: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE · MMM d, yyyy"
        return f
    }()

    // MARK: the gallery (bp8 ④): type-to-filter, ⏎ adds and stays

    private var gallery: some View {
        let matches = widgetRegistry.filter {
            galleryFilter.isEmpty
                || $0.title.localizedCaseInsensitiveContains(galleryFilter)
        }
        let added = Set(widgets.map(\.kind))
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 10))
                    .foregroundColor(Theme.mutedFg)
                TextField("Filter widgets…", text: $galleryFilter)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .onSubmit {
                        if let first = matches.first(where: { !added.contains($0.kind) }) {
                            add(first)
                        }
                    }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            ForEach(matches, id: \.kind) { spec in
                let already = added.contains(spec.kind)
                Button {
                    if !already { add(spec) }
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            Text(spec.title).font(.system(size: 12, weight: .semibold))
                            Spacer()
                            if already {
                                Text("Added ✓").font(.system(size: 10))
                                    .foregroundColor(Theme.mutedFg)
                            }
                        }
                        Text(spec.reads).font(.system(size: 10.5))
                            .foregroundColor(Theme.mutedFg)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(already ? 0.45 : 1)
            }
            Divider()
            Text("A widget points at a collection that already exists — nothing here builds templates.")
                .font(.system(size: 9.5)).foregroundColor(Theme.mutedFg)
                .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .frame(width: 300)
    }

    private func add(_ spec: WidgetSpec) {
        model.addWidget(
            kind: spec.kind, workspace: chrome.activeWorkspace ?? 0, span: spec.defaultSpan)
        // ⏎ adds and STAYS (bp8) — the popover remains for the next pick.
    }

    // MARK: the board

    private var emptyBoard: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 30)).foregroundColor(Theme.foreground.opacity(0.12))
            Text("An empty board.")
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
            Text("Widgets are lenses over what already exists — nothing here builds templates.")
                .font(.system(size: 11.5)).foregroundColor(Theme.mutedFg)
            Button("＋ Add your first widget") {
                galleryFilter = ""
                galleryOpen = true
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(Theme.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var boardGrid: some View {
        // Spans on a 6-column budget, wrapped as adaptive rows. v0 keeps it
        // simple: each card takes span/6 of the width, flowing left→right.
        let columns = [GridItem(.adaptive(minimum: 220), spacing: 13)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 13) {
            ForEach(widgets) { widget in
                widgetCard(widget)
            }
        }
    }

    @ViewBuilder
    private func widgetCard(_ widget: BoardWidgetRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title(for: widget.kind).uppercased())
                    .font(.system(size: 10.5, weight: .bold)).kerning(0.5)
                    .foregroundColor(Theme.mutedFg)
                Spacer()
                if hoveredCard == widget.id {
                    Button {
                        if selection == widget.id { selection = nil }
                        model.trash(widget.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundColor(Theme.mutedFg)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Remove widget (one undo brings it back)")
                }
            }
            widgetBody(widget)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    selection == widget.id ? Theme.accent : Theme.border,
                    lineWidth: selection == widget.id ? 1.5 : 0.5))
        .contentShape(Rectangle())
        .onHover { inside in hoveredCard = inside ? widget.id : (hoveredCard == widget.id ? nil : hoveredCard) }
        .onTapGesture {
            // Select the WIDGET ENTITY: the right card's Metadata lens is the
            // config surface (the no-gear ruling) — its rows edit real cells.
            selection = widget.id
        }
        .onDrag { NSItemProvider(object: "widget:\(widget.id)" as NSString) }
        .onDrop(
            of: [.plainText],
            delegate: WidgetReorderDrop(model: model, over: widget, all: widgets))
    }

    private func title(for kind: String) -> String {
        widgetRegistry.first { $0.kind == kind }?.title ?? kind
    }

    @ViewBuilder
    private func widgetBody(_ widget: BoardWidgetRow) -> some View {
        switch widget.kind {
        case "tasks":
            tasksSummary
        case "pinned":
            pinnedBody
        default:
            // A kind from a newer box/CLI this build doesn't render yet —
            // honest, quiet, never a crash.
            Text("This widget kind (\(widget.kind)) arrives with a later slice.")
                .font(.system(size: 11)).foregroundColor(Theme.mutedFg)
        }
    }

    // MARK: v0 widget bodies

    /// Tasks summary (bp8): counts by status; each opens the board.
    private var tasksSummary: some View {
        let rows = model.rows(model.snap?.everything ?? [])
            .filter { $0.kinds.contains("task") || $0.status != nil }
        var order: [String] = []
        var counts: [String: Int] = [:]
        for row in rows {
            let status = row.status ?? "no status"
            if counts[status] == nil { order.append(status) }
            counts[status, default: 0] += 1
        }
        return HStack(spacing: 9) {
            if order.isEmpty {
                Text("No tasks yet.").font(.system(size: 11)).foregroundColor(Theme.mutedFg)
            }
            ForEach(order, id: \.self) { status in
                Button {
                    navigate(.tasks)
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(counts[status] ?? 0)")
                            .font(.system(size: 16, weight: .semibold).monospacedDigit())
                        Text(status).font(.system(size: 9.5)).foregroundColor(Theme.mutedFg)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.border))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Pinned (bp8's tier-1, re-aimed at the P17g shelf — the recorded delta).
    private var pinnedBody: some View {
        let pins = (model.snap?.pins ?? []).compactMap { model.entity($0.target) }
        return VStack(alignment: .leading, spacing: 2) {
            if pins.isEmpty {
                Text("Nothing pinned. 🔖 or ⌘⇧B pins anything here.")
                    .font(.system(size: 11)).foregroundColor(Theme.mutedFg)
            }
            ForEach(pins.prefix(6), id: \.id) { row in
                Button {
                    open(row.id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: rowKindIcon(row))
                            .font(.system(size: 10)).foregroundColor(Theme.mutedFg)
                            .frame(width: 14)
                        Text(row.title).font(.system(size: 12)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Card drag-reorder — the pins grammar: drop on a card, land before it,
/// one set on the float order key, one undo.
struct WidgetReorderDrop: DropDelegate {
    let model: BoxModel
    let over: BoardWidgetRow
    let all: [BoardWidgetRow]

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.plainText]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let raw = object as? String, raw.hasPrefix("widget:"),
                let dragged = UInt64(raw.dropFirst(7)),
                dragged != over.id
            else { return }
            let index = all.firstIndex { $0.id == over.id } ?? 0
            let before = index > 0 ? all[index - 1].order : over.order - 20
            let order = (before + over.order) / 2
            DispatchQueue.main.async {
                model.set(dragged, property: "order", value: String(order))
            }
        }
        return true
    }
}
