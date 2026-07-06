// lotus — the main window. One window, three regions: sidebar, one lens,
// inspector. Every lens swaps in place; nothing floats free. The window
// renders one JSON snapshot from the seam and never holds the box.
//
// interface.md is the law here: system materials, Apple text styles,
// lake green in exactly three jobs, the inbox count as the only badge.

import SwiftUI

// MARK: - theme

enum Theme {
    /// The accent. Decided in interface.md 0.2: lake green.
    static let accent = Color(red: 47 / 255, green: 125 / 255, blue: 107 / 255)
    static let accentDeep = Color(red: 39 / 255, green: 100 / 255, blue: 86 / 255)
    static let accentTint = Color(red: 47 / 255, green: 125 / 255, blue: 107 / 255).opacity(0.12)
}

// MARK: - snapshot rows (mirror ffi/src/lib.rs, decoded from snake_case)

struct CellRow: Codable, Hashable {
    let property: String
    let value: String
}

struct EntityRow: Codable, Identifiable, Hashable {
    let id: UInt64
    let title: String
    let kinds: [String]
    let due: Int64?
    let dueDateOnly: Bool
    let status: String?
    let created: Int64?
    let cells: [CellRow]
}

struct ProposalRow: Codable, Identifiable, Hashable {
    var id: String { "\(entity).\(ordinal)" }
    let entity: UInt64
    let ordinal: UInt32
    let reason: String
    let author: String
}

struct Snapshot: Codable {
    let today: [UInt64]
    let unstructured: [UInt64]
    let everything: [UInt64]
    let dated: [UInt64]
    let inbox: [ProposalRow]
    let entities: [EntityRow]
}

// MARK: - the model: refresh-after-every-act, never hold the box

final class BoxModel: ObservableObject {
    let path: String
    @Published var snap: Snapshot?
    @Published var boxBusy = false

    init(path: String) {
        self.path = path
    }

    func entity(_ id: UInt64?) -> EntityRow? {
        guard let id = id else { return nil }
        return snap?.entities.first { $0.id == id }
    }

    func rows(_ ids: [UInt64]) -> [EntityRow] {
        ids.compactMap { entity($0) }
    }

    func refresh() {
        let path = self.path
        DispatchQueue.global(qos: .userInitiated).async {
            guard let raw = lotus_snapshot(path) else {
                DispatchQueue.main.async { self.boxBusy = true }
                return
            }
            let json = String(cString: raw)
            lotus_string_free(raw)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let snap = try? decoder.decode(Snapshot.self, from: Data(json.utf8))
            DispatchQueue.main.async {
                self.boxBusy = false
                if let snap = snap { self.snap = snap }
            }
        }
    }

    func capture(_ text: String) {
        act { lotus_capture_at(self.path, text) != 0 }
    }

    func accept(_ proposal: ProposalRow) {
        act { lotus_accept_at(self.path, proposal.entity, proposal.ordinal) == 1 }
    }

    func reject(_ proposal: ProposalRow) {
        act { lotus_reject_at(self.path, proposal.entity, proposal.ordinal) == 1 }
    }

    private func act(_ work: @escaping () -> Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = work()
            DispatchQueue.main.async {
                if !ok { NSSound.beep() }
                self.refresh()
            }
        }
    }
}

// MARK: - civil date display (one formatter for the whole shell)

enum Civil {
    static func text(_ civil: Int64, dateOnly: Bool) -> String {
        let ymd = civil / 10_000
        let hm = civil % 10_000
        var parts = DateComponents()
        parts.year = Int(ymd / 10_000)
        parts.month = Int((ymd / 100) % 100)
        parts.day = Int(ymd % 100)
        guard let date = Calendar.current.date(from: parts) else { return "\(civil)" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        var out = formatter.string(from: date)
        if !dateOnly {
            out += String(format: " %02d:%02d", hm / 100, hm % 100)
        }
        return out
    }

    static var todayYMD: Int64 {
        let now = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return Int64(now.year! * 10_000 + now.month! * 100 + now.day!)
    }
}

// MARK: - lenses

enum Lens: String, CaseIterable, Identifiable {
    case today = "Today"
    case calendar = "Calendar"
    case everything = "Everything"
    case inbox = "Inbox"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .today: return "sparkles"
        case .calendar: return "calendar"
        case .everything: return "line.3.horizontal"
        case .inbox: return "tray"
        }
    }
    var shortcut: KeyEquivalent {
        switch self {
        case .today: return "1"
        case .calendar: return "2"
        case .everything: return "3"
        case .inbox: return "4"
        }
    }
}

// MARK: - the window

struct MainWindow: View {
    @ObservedObject var model: BoxModel
    @State private var lens: Lens = .today
    @State private var query = ""
    @State private var selection: UInt64?
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(
                model: model, lens: $lens, query: $query,
                searchFocused: $searchFocused
            )
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if showInspector {
                Divider()
                InspectorPane(model: model, selection: $selection)
            }
        }
        .frame(minWidth: 980, minHeight: 620)
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear { model.refresh() }
    }

    private var showInspector: Bool {
        lens == .everything && query.isEmpty
    }

    @ViewBuilder
    private var content: some View {
        if !query.isEmpty {
            ResultsView(model: model, query: query)
        } else {
            switch lens {
            case .today: TodayView(model: model, lens: $lens)
            case .calendar: CalendarView(model: model)
            case .everything: EverythingView(model: model, selection: $selection)
            case .inbox: InboxView(model: model)
            }
        }
    }
}

// MARK: - sidebar

struct Sidebar: View {
    @ObservedObject var model: BoxModel
    @Binding var lens: Lens
    @Binding var query: String
    var searchFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 7) {
                Text("❧").foregroundColor(Theme.accent)
                Text("lotus").fontWeight(.semibold)
            }
            .font(.system(size: 15))
            .padding(.horizontal, 8)
            .padding(.top, 34) // room for the traffic lights

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

            VStack(spacing: 1) {
                ForEach(Lens.allCases) { item in
                    SidebarRow(
                        item: item,
                        active: lens == item && query.isEmpty,
                        badge: item == .inbox ? (model.snap?.inbox.count ?? 0) : 0
                    ) {
                        query = ""
                        lens = item
                    }
                    .keyboardShortcut(item.shortcut, modifiers: .command)
                }
            }

            Spacer()

            if model.boxBusy {
                Label("box is busy — retrying", systemImage: "hourglass")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
            }
        }
        .padding(12)
        .frame(width: 224)
        .background(SidebarMaterial().ignoresSafeArea())
    }
}

struct SidebarRow: View {
    let item: Lens
    let active: Bool
    let badge: Int
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 9) {
                Image(systemName: item.symbol)
                    .font(.system(size: 12.5))
                    .frame(width: 16)
                    .foregroundColor(active ? Theme.accent : .secondary)
                Text(item.rawValue)
                    .font(.system(size: 13, weight: active ? .semibold : .medium))
                    .foregroundColor(active ? Theme.accentDeep : .primary)
                Spacer()
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Capsule().fill(active ? Theme.accentDeep : Theme.accent))
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(active ? Theme.accentTint : .clear)
        )
    }
}

/// The native sidebar material, since SwiftUI alone won't hand it to us
/// inside a plain NSWindow.
struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

// MARK: - shared lens scaffolding

struct LensHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 21, weight: .bold))
            Spacer()
            Text(subtitle).font(.system(size: 13)).foregroundColor(.secondary)
        }
        .padding(.bottom, 18)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.5)
            .foregroundColor(.secondary)
            .padding(.bottom, 6)
    }
}

struct EntityLine: View {
    let row: EntityRow
    var showWhen = true

    var body: some View {
        HStack(spacing: 12) {
            if row.kinds.contains("task") || row.status != nil {
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1.5)
                    .frame(width: 16, height: 16)
            }
            Text(row.title)
                .font(.system(size: 14))
                .lineLimit(1)
            Spacer()
            if showWhen, let due = row.due {
                Text(Civil.text(due, dateOnly: row.dueDateOnly))
                    .font(.system(size: 12.5).monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .overlay(Divider(), alignment: .bottom)
    }
}

// MARK: - Today

struct TodayView: View {
    @ObservedObject var model: BoxModel
    @Binding var lens: Lens
    @State private var draft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LensHeader(title: "Today", subtitle: todayLine)

                HStack(spacing: 9) {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    TextField("Capture a thought…", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .onSubmit {
                            let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty else { return }
                            model.capture(text)
                            draft = ""
                        }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.25))
                )

                if let snap = model.snap {
                    if !snap.today.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            SectionLabel(text: "Due")
                            ForEach(model.rows(snap.today)) { EntityLine(row: $0) }
                        }
                    }
                    if !snap.unstructured.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            SectionLabel(text: "Captured · unstructured")
                            ForEach(model.rows(snap.unstructured)) {
                                EntityLine(row: $0, showWhen: false)
                            }
                        }
                    }
                    if snap.today.isEmpty && snap.unstructured.isEmpty {
                        Text("Nothing waiting. Absence creates no debt.")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    if !snap.inbox.isEmpty {
                        HStack(spacing: 4) {
                            Text(snap.inbox.count == 1
                                 ? "1 proposal waiting —"
                                 : "\(snap.inbox.count) proposals waiting —")
                                .foregroundColor(.secondary)
                            Button("open the inbox") { lens = .inbox }
                                .buttonStyle(.plain)
                                .foregroundColor(Theme.accent)
                                .fontWeight(.semibold)
                        }
                        .font(.system(size: 13))
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 40)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var todayLine: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }
}

// MARK: - Inbox

struct InboxView: View {
    @ObservedObject var model: BoxModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LensHeader(
                    title: "Inbox",
                    subtitle: "\(model.snap?.inbox.count ?? 0) waiting"
                )
                if let inbox = model.snap?.inbox, !inbox.isEmpty {
                    ForEach(inbox) { proposal in
                        ProposalLine(model: model, proposal: proposal)
                    }
                    Text("Decline once and the clerk never asks again.")
                        .font(.system(size: 12))
                        .foregroundColor(Color.secondary.opacity(0.8))
                        .padding(.top, 20)
                } else {
                    Text("Nothing waiting.")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 40)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ProposalLine: View {
    @ObservedObject var model: BoxModel
    let proposal: ProposalRow

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                subjectAndReason
                Text("#\(String(proposal.entity)) · \(Text("clerk · \(proposal.author)").foregroundColor(Theme.accent))")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Accept") { model.accept(proposal) }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            Button("Decline") { model.reject(proposal) }
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 14)
        .overlay(Divider(), alignment: .bottom)
    }

    private var subjectAndReason: some View {
        let subject = model.entity(proposal.entity)?.title ?? "#\(proposal.entity)"
        return Text(
            "\(subject) — \(Text(proposal.reason).fontWeight(.semibold).foregroundColor(Theme.accentDeep))"
        )
        .font(.system(size: 14))
        .lineLimit(2)
    }
}

// MARK: - Everything

struct EverythingView: View {
    @ObservedObject var model: BoxModel
    @Binding var selection: UInt64?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LensHeader(
                title: "Everything",
                subtitle: "\(model.snap?.everything.count ?? 0) items"
            )
            .padding(.horizontal, 32)
            .padding(.top, 40)

            Table(model.rows(model.snap?.everything ?? []), selection: $selection) {
                TableColumn("Title") { row in
                    Text(row.title).font(.system(size: 13.5, weight: .medium))
                }
                TableColumn("Type") { row in
                    Text(row.kinds.joined(separator: ", "))
                        .foregroundColor(.secondary)
                }
                .width(90)
                TableColumn("Due") { row in
                    if let due = row.due {
                        Text(Civil.text(due, dateOnly: row.dueDateOnly))
                            .font(.system(size: 13).monospacedDigit())
                    } else {
                        Text("—").foregroundColor(Color.secondary.opacity(0.5))
                    }
                }
                .width(120)
                TableColumn("Status") { row in
                    if let status = row.status {
                        HStack(spacing: 7) {
                            Circle().fill(statusColor(status)).frame(width: 8, height: 8)
                            Text(status)
                        }
                    } else {
                        Text("—").foregroundColor(Color.secondary.opacity(0.5))
                    }
                }
                .width(90)
            }
            .tableStyle(.inset)
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "done": return Color(red: 74 / 255, green: 158 / 255, blue: 134 / 255)
        case "doing": return Color(red: 207 / 255, green: 154 / 255, blue: 63 / 255)
        default: return Color.secondary.opacity(0.6)
        }
    }
}

// MARK: - Results (search is navigation)

struct ResultsView: View {
    @ObservedObject var model: BoxModel
    let query: String

    var body: some View {
        let hits = (model.snap?.entities ?? []).filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.cells.contains { c in c.value.localizedCaseInsensitiveContains(query) }
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LensHeader(
                    title: "Results",
                    subtitle: hits.count == 1 ? "1 match" : "\(hits.count) matches"
                )
                ForEach(hits) { EntityLine(row: $0) }
                if hits.isEmpty {
                    Text("Nothing matches.")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Calendar

struct CalendarView: View {
    @ObservedObject var model: BoxModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let dows = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        let now = Date()
        let cal = Calendar.current
        let parts = cal.dateComponents([.year, .month], from: now)
        let first = cal.date(from: parts)!
        let range = cal.range(of: .day, in: .month, for: first)!
        let lead = cal.component(.weekday, from: first) - 1
        let monthKey = Int64(parts.year! * 100 + parts.month!)
        let byDay = Dictionary(grouping: model.rows(model.snap?.dated ?? [])) {
            row -> Int64 in (row.due ?? 0) / 10_000
        }

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LensHeader(title: monthTitle(first), subtitle: "month")
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(dows, id: \.self) { dow in
                        Text(dow.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .kerning(0.4)
                            .foregroundColor(Color.secondary.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 8)
                    }
                    ForEach(0..<lead, id: \.self) { _ in
                        Color.clear.frame(height: 92)
                    }
                    ForEach(range, id: \.self) { day in
                        let key = monthKey * 100 + Int64(day)
                        DayCell(
                            day: day,
                            isToday: key == Civil.todayYMD,
                            events: byDay[key] ?? []
                        )
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 40)
            .padding(.bottom, 24)
        }
    }

    private func monthTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
}

struct DayCell: View {
    let day: Int
    let isToday: Bool
    let events: [EntityRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if isToday {
                Text("\(day)")
                    .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                    .foregroundColor(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.accent))
            } else {
                Text("\(day)")
                    .font(.system(size: 12.5).monospacedDigit())
            }
            ForEach(events.prefix(3)) { row in
                Text(row.title)
                    .font(.system(size: 11.5))
                    .lineLimit(1)
                    .foregroundColor(Theme.accentDeep)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Theme.accentTint))
            }
            Spacer(minLength: 0)
        }
        .padding(7)
        .frame(minHeight: 92, alignment: .topLeading)
        .overlay(Divider(), alignment: .bottom)
    }
}

// MARK: - Inspector

struct InspectorPane: View {
    @ObservedObject var model: BoxModel
    @Binding var selection: UInt64?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let entity = model.entity(selection) {
                Text("SELECTED")
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.5)
                    .foregroundColor(Color.secondary.opacity(0.7))
                    .padding(.bottom, 8)
                Text(entity.title)
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.bottom, 20)
                ForEach(entity.cells, id: \.self) { cell in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(cell.property)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .frame(width: 72, alignment: .leading)
                        Text(cell.value)
                            .font(.system(size: 13))
                            .lineLimit(3)
                    }
                    .padding(.vertical, 7)
                    .overlay(Divider(), alignment: .bottom)
                }
            } else {
                Text("Select a row to see its cells.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(20)
        .padding(.top, 24)
        .frame(width: 260, alignment: .topLeading)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}
