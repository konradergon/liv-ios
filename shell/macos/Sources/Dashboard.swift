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
        kind: "agenda", title: "Agenda · today",
        reads: "reads → today's events + dated objects + the daily note", defaultSpan: 2),
    WidgetSpec(
        kind: "tasks", title: "Tasks summary",
        reads: "reads → the task pool, counts by status", defaultSpan: 2),
    WidgetSpec(
        kind: "pinned", title: "Pinned",
        reads: "reads → the Favourites shelf (pins)", defaultSpan: 1),
    WidgetSpec(
        kind: "metric", title: "Metric chart",
        reads: "reads → a collection's cadence over 30 days", defaultSpan: 2),
    WidgetSpec(
        kind: "view", title: "Saved view",
        reads: "reads → any saved view, rendered as a card", defaultSpan: 2),
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
        case "agenda":
            agendaBody
        case "metric":
            MetricChartBody(model: model, widget: widget)
        case "view":
            SavedViewBody(model: model, widget: widget, open: open)
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

    // MARK: Agenda · today (bp8 16/17) — the calendar's OWN derivation

    /// One derivation rule: the same calendarByDay the grid uses, so a
    /// lookup-role date (valid-until, purchased-on) can never appear here —
    /// the positioning projection excludes it by construction.
    private var agendaBody: some View {
        let today = Civil.todayYMD
        let items = calendarByDay(model)[today] ?? []
        let countdown = upcomingSpan(within: 7)
        return VStack(alignment: .leading, spacing: 3) {
            if let (row, label) = countdown {
                Button {
                    open(row.id)
                } label: {
                    Text("⏳ \(row.title) — \(label)")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.mutedFg)
                        .lineLimit(1)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if items.isEmpty {
                Text("Nothing on today.").font(.system(size: 11)).foregroundColor(Theme.mutedFg)
                    .padding(.vertical, 2)
            }
            ForEach(items.prefix(5)) { row in
                Button {
                    open(row.id)
                } label: {
                    HStack(spacing: 7) {
                        Text(agendaTime(row))
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundColor(Theme.mutedFg)
                            .frame(width: 34, alignment: .leading)
                        Image(systemName: rowKindIcon(row))
                            .font(.system(size: 10)).foregroundColor(Theme.mutedFg)
                        Text(row.title).font(.system(size: 12)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            // The one daily note, never a second Today (P12 D1): this row
            // LAUNCHES into it.
            Button {
                NotificationCenter.default.post(name: .lotusGoHome, object: nil)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "sun.max.fill").font(.system(size: 10))
                    Text("Today's daily note").font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 0)
                }
                .foregroundColor(Theme.accent)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func agendaTime(_ row: EntityRow) -> String {
        guard let due = row.due, !row.dueDateOnly, due / 10_000 == Civil.todayYMD else {
            return "—"
        }
        let hhmm = Int(due % 10_000)
        return String(format: "%02d:%02d", hhmm / 100, hhmm % 100)
    }

    /// The nearest multi-day span touching or approaching today — ONE strip,
    /// never duplicate rows (the same object drives the calendar span).
    private func upcomingSpan(within days: Int) -> (EntityRow, String)? {
        let today = Civil.todayYMD
        let dated = model.rows(model.snap?.dated ?? [])
        var best: (EntityRow, Int)?
        for row in dated {
            guard let due = row.due, let end = row.dueEnd else { continue }
            let startDay = due / 10_000
            let endDay = end / 10_000
            guard endDay > startDay, endDay >= today else { continue }
            let dayDiff = civilDayDiff(from: today, to: startDay)
            guard dayDiff <= days else { continue }
            if best == nil || dayDiff < best!.1 {
                best = (row, dayDiff)
            }
        }
        guard let (row, diff) = best else { return nil }
        let label: String
        if diff > 0 {
            label = "in \(diff) day\(diff == 1 ? "" : "s")"
        } else {
            label = "through \(shortDay(row.dueEnd! / 10_000))"
        }
        return (row, label)
    }

    private func civilDayDiff(from: Int64, to: Int64) -> Int {
        guard let a = civilAsDate(from), let b = civilAsDate(to) else { return .max }
        return Civil.gregorian.dateComponents([.day], from: a, to: b).day ?? .max
    }

    private func civilAsDate(_ ymd: Int64) -> Date? {
        var parts = DateComponents()
        parts.year = Int(ymd / 10_000)
        parts.month = Int((ymd / 100) % 100)
        parts.day = Int(ymd % 100)
        return Civil.gregorian.date(from: parts)
    }

    private func shortDay(_ ymd: Int64) -> String {
        guard let date = civilAsDate(ymd) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date)
    }
}

/// Metric chart (bp8 12): a collection's creation cadence over 30 days —
/// NEUTRAL ink (owner call #7), avg/max footer, computed client-side.
/// Re-aim it at a saved view from the Inspector (`target`); unaimed it reads
/// the whole vault and never nags.
struct MetricChartBody: View {
    @ObservedObject var model: BoxModel
    let widget: BoardWidgetRow
    @State private var series: [Int] = []

    var body: some View {
        let maxValue = max(series.max() ?? 0, 1)
        let avg = series.isEmpty ? 0 : Double(series.reduce(0, +)) / Double(series.count)
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width / CGFloat(max(series.count, 1))
                HStack(alignment: .bottom, spacing: 1) {
                    ForEach(Array(series.enumerated()), id: \.offset) { _, value in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Theme.foreground.opacity(value == 0 ? 0.06 : 0.35))
                            .frame(
                                width: max(1, w - 1),
                                height: max(2, geo.size.height * CGFloat(value) / CGFloat(maxValue)))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 44)
            HStack {
                Text(aimLabel).font(.system(size: 9.5)).foregroundColor(Theme.mutedFg)
                Spacer()
                Text("avg \(String(format: "%.1f", avg)) · max \(series.max() ?? 0) / day")
                    .font(.system(size: 9.5).monospacedDigit()).foregroundColor(Theme.mutedFg)
            }
        }
        .onAppear { refresh() }
        .onChange(of: model.snap?.everything.count ?? 0) { refresh() }
    }

    private var aimLabel: String {
        if let view = widget.view,
            let saved = (model.snap?.views ?? []).first(where: { $0.id == view })
        {
            return "created · \(saved.name) · 30d"
        }
        return "created · everything · 30d"
    }

    private func refresh() {
        let compute: ([EntityRow]) -> Void = { rows in
            let today = Civil.todayYMD
            var buckets = [Int](repeating: 0, count: 30)
            for row in rows {
                guard let created = row.created else { continue }
                let day = created / 10_000
                var parts = DateComponents()
                parts.year = Int(day / 10_000)
                parts.month = Int((day / 100) % 100)
                parts.day = Int(day % 100)
                var todayParts = DateComponents()
                todayParts.year = Int(today / 10_000)
                todayParts.month = Int((today / 100) % 100)
                todayParts.day = Int(today % 100)
                guard let a = Civil.gregorian.date(from: parts),
                    let b = Civil.gregorian.date(from: todayParts),
                    let diff = Civil.gregorian.dateComponents([.day], from: a, to: b).day,
                    diff >= 0, diff < 30
                else { continue }
                buckets[29 - diff] += 1
            }
            series = buckets
        }
        if let view = widget.view,
            let saved = (model.snap?.views ?? []).first(where: { $0.id == view })
        {
            model.runQuery(saved.query) { ids in compute(model.rows(ids)) }
        } else {
            compute(model.rows(model.snap?.everything ?? []))
        }
    }
}

/// Saved view (bp8 8): any saved view as a card. Unaimed = the dashed
/// specimen with "Choose view…" over EXISTING views only (never a builder);
/// aimed = the query's rows through the one engine, header re-runs it there.
struct SavedViewBody: View {
    @ObservedObject var model: BoxModel
    let widget: BoardWidgetRow
    var open: (UInt64) -> Void = { _ in }
    @State private var hits: [UInt64] = []

    var body: some View {
        let views = model.snap?.views ?? []
        let aimed = widget.view.flatMap { id in views.first { $0.id == id } }
        return Group {
            if let view = aimed {
                VStack(alignment: .leading, spacing: 2) {
                    Button {
                        NotificationCenter.default.post(
                            name: .lotusSearchFor, object: view.query)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 10))
                            Text(view.name).font(.system(size: 11.5, weight: .semibold))
                            Text("\(hits.count)")
                                .font(.system(size: 10).monospacedDigit())
                                .foregroundColor(Theme.mutedFg)
                            Spacer(minLength: 0)
                        }
                        .foregroundColor(Theme.accent)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    ForEach(model.rows(Array(hits.prefix(5))), id: \.id) { row in
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
                    if hits.count > 5 {
                        Text("+\(hits.count - 5) more — open in search")
                            .font(.system(size: 10)).foregroundColor(Theme.mutedFg)
                    }
                }
                .onAppear { refresh(view.query) }
                .onChange(of: model.snap?.everything.count ?? 0) { refresh(view.query) }
            } else if views.isEmpty {
                // Idles without nagging: saving a view is the ⌘F palette's job.
                Text("No saved views yet. Save one from the search palette (⌘F → Save view…).")
                    .font(.system(size: 11)).foregroundColor(Theme.mutedFg)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Point this card at a view:")
                        .font(.system(size: 11)).foregroundColor(Theme.mutedFg)
                    Menu {
                        ForEach(views) { view in
                            Button(view.name) {
                                model.set(widget.id, property: "target", value: "#\(view.id)")
                            }
                        }
                    } label: {
                        Text("Choose view…")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(Theme.accent)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .padding(-4))
            }
        }
    }

    private func refresh(_ query: String) {
        model.runQuery(query) { ids in hits = ids }
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
