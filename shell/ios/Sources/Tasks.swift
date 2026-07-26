// liv iOS — Tasks (design/ios.md §6): a Feature-view lens — status-grouped
// flat list over every task in the box. Groups come from the vocabulary
// (liv_status_options_at, board order); `completes` groups collapse by
// default. Filters are client-side state only — the snapshot is never
// re-queried to filter. Status chips/rings wear the OPTION's hue (quantized
// to the semantic set); project chips wear the Hue dot. Full snapshot on
// appear — undated tasks must not drop. Tapping a row opens the entity as a
// Desk tab (desk.open) — the rail→center gesture grammar; the chrome owns
// the frame, so this body keeps only a SectionLabel-scale header.

import SwiftUI

struct TasksView: View {
    @EnvironmentObject var model: BoxModel
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var workspaces: WorkspaceModel

    @State private var options: [StatusOption] = []
    @State private var projects: [String] = []
    @State private var filter: TasksFilter = .all
    /// Names of completes-groups the user opened; default = collapsed.
    @State private var expanded: Set<String> = []
    @State private var quickAdd = ""
    @FocusState private var quickAddFocused: Bool
    /// The row whose "Pick" swipe verb is choosing a date (sheet item).
    @State private var duePick: TasksDuePick?

    private struct TasksDuePick: Identifiable {
        let entity: UInt64
        var id: UInt64 { entity }
    }

    private enum TasksFilter: Equatable {
        case all
        case status(String)
        case project(String)
    }

    private struct TasksGroup: Identifiable {
        var id: String { name }
        let name: String
        let completes: Bool
        let hue: Color?
        let isNoStatus: Bool
        var rows: [EntityRow]
        var hostsQuickAdd = false
    }

    // MARK: body

    var body: some View {
        let groups = visibleGroups()
        List {
            headerRow
            chipRow
            if groups.allSatisfy({ $0.rows.isEmpty }) {
                emptyRow
            }
            ForEach(groups) { group in
                groupHeader(group)
                if group.hostsQuickAdd {
                    quickAddRow(status: group.isNoStatus ? nil : group.name)
                }
                if !group.completes || expanded.contains(group.name) {
                    ForEach(group.rows) { row in
                        taskRow(row)
                    }
                }
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 40)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .contentMargins(.bottom, 76, for: .scrollContent)  // the bottom bar floats over
        .background(LivTheme.canvas.ignoresSafeArea())
        .sheet(item: $duePick) { p in
            DetailDueSheet(model: model, id: p.entity, property: "due")
                .presentationDetents([.medium])
        }
        .onAppear {
            model.refresh()  // full snapshot — undated tasks must not drop
            model.statusOptions(kind: "task") { fetched in
                options = fetched.filter { !($0.name ?? "").isEmpty }
            }
            model.distinctValues(property: "project") { values in
                projects = Array(values.prefix(6))  // count-desc; top few only
            }
        }
    }

    // MARK: header + filter chips

    /// SectionLabel-scale only — the chrome's top bar is the big header now.
    private var headerRow: some View {
        HStack(spacing: 8) {
            SectionLabel("Tasks")
            // Why the list is short — never a mystery (M4).
            if workspaces.lensOn { LensChip(label: workspaces.lensLabel) }
        }
        .padding(.top, 8)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                TasksFilterChip("All", dot: nil, selected: filter == .all) {
                    filter = .all
                }
                ForEach(options) { option in
                    let name = option.name ?? ""
                    TasksFilterChip(
                        name, dot: tasksOptionColor(option.hue),
                        selected: filter == .status(name)
                    ) {
                        filter = filter == .status(name) ? .all : .status(name)
                    }
                }
                ForEach(projects, id: \.self) { project in
                    TasksFilterChip(
                        project, dot: Hue.dot(project),
                        selected: filter == .project(project)
                    ) {
                        filter =
                            filter == .project(project) ? .all : .project(project)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var emptyRow: some View {
        EmptyHint(
            filter != .all
                ? "Nothing matches this filter."
                : workspaces.lensOn
                    ? "No tasks in \(workspaces.lensLabel). Switch to All to see the rest."
                    : "No tasks yet. Add one below."
        )
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    // MARK: groups

    /// The vocabulary's groups in board order + a final "No status" catch-all
    /// (also holds statuses no longer in the vocabulary — every task shows).
    private func visibleGroups() -> [TasksGroup] {
        // The lens (M4) runs BEFORE the chip filter: the workspace scopes
        // the surface, the chips narrow inside it.
        let lens = workspaces.activeQuery
        let tasks = (model.snap?.entities ?? []).filter {
            ($0.kinds ?? []).contains("task") && $0.trashed != true
                && $0.archived != true && lens.matches($0)
        }
        let filtered = tasks.filter(matchesFilter)

        var used = Set<UInt64>()
        var groups: [TasksGroup] = []
        for option in options {
            guard let name = option.name, !name.isEmpty else { continue }
            let rows = filtered.filter { $0.status == name }
            rows.forEach { used.insert($0.id) }
            groups.append(
                TasksGroup(
                    name: name, completes: option.completes == true,
                    hue: tasksOptionColor(option.hue), isNoStatus: false,
                    rows: sortRows(rows)))
        }
        let rest = filtered.filter { !used.contains($0.id) }
        groups.append(
            TasksGroup(
                name: "No status", completes: false, hue: nil, isNoStatus: true,
                rows: sortRows(rest)))

        // Quick-add lives at the top of the first non-completes group — under
        // a status filter, that filter's own group (none if it completes).
        let hostIndex: Int?
        switch filter {
        case .status(let s):
            hostIndex = groups.firstIndex { $0.name == s && !$0.completes }
        default:
            hostIndex = groups.firstIndex { !$0.completes }
        }
        if let hostIndex { groups[hostIndex].hostsQuickAdd = true }

        return groups.enumerated().compactMap { i, group in
            group.rows.isEmpty && i != hostIndex ? nil : group
        }
    }

    private func matchesFilter(_ row: EntityRow) -> Bool {
        switch filter {
        case .all:
            return true
        case .status(let s):
            return row.status == s
        case .project(let p):
            return (row.cells ?? []).contains {
                $0.property == "project" && $0.value == p
            }
        }
    }

    /// Due ascending (undated last), then title — stable across refreshes.
    private func sortRows(_ rows: [EntityRow]) -> [EntityRow] {
        rows.sorted { a, b in
            let da = a.due ?? .max
            let db = b.due ?? .max
            if da != db { return da < db }
            let ta = (a.title ?? "").lowercased()
            let tb = (b.title ?? "").lowercased()
            if ta != tb { return ta < tb }
            return a.id < b.id
        }
    }

    private func groupHeader(_ group: TasksGroup) -> some View {
        let isExpanded = expanded.contains(group.name)
        let trailing =
            group.completes
            ? "\(group.rows.count) \(isExpanded ? "▾" : "▸")"
            : "\(group.rows.count)"
        return SectionLabel(
            group.name, trailing: trailing,
            trailingAction: group.completes ? { toggleExpanded(group.name) } : nil
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if group.completes { toggleExpanded(group.name) }
        }
        .padding(.top, 14)
        .padding(.bottom, 2)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func toggleExpanded(_ name: String) {
        if expanded.contains(name) {
            expanded.remove(name)
        } else {
            expanded.insert(name)
        }
    }

    // MARK: quick-add

    private func quickAddRow(status: String?) -> some View {
        HStack(spacing: 0) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(LivTheme.muted)
                .frame(width: 31)  // aligns with the 15pt ring + its 8pt pads
            TextField("Add a task", text: $quickAdd)
                .font(.system(size: 14))
                .foregroundStyle(LivTheme.text)
                .focused($quickAddFocused)
                .submitLabel(.done)
                .onSubmit { submitQuickAdd(status: status) }
        }
        .frame(minHeight: 40)
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
                .padding(.leading, 31)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func submitQuickAdd(status: String?) {
        let text = quickAdd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        model.createTask { id in
            guard id != 0 else { return }  // failure already surfaced by the model
            model.set(id, "name", text)
            if let status { model.set(id, "status", status) }
        }
        quickAdd = ""
        quickAddFocused = true  // serial entry
    }

    // MARK: rows

    private func taskRow(_ row: EntityRow) -> some View {
        let option = options.first { $0.name == row.status }
        let done = option?.completes == true
        let due = tasksDue(row)
        let chips = refChips(row)
        return HStack(spacing: 0) {
            StatusRing(done: done, hue: tasksOptionColor(option?.hue)) {
                toggleStatus(row, done: done)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    (row.title ?? "").isEmpty ? "untitled task" : (row.title ?? "")
                )
                .font(.system(size: 14))
                .foregroundStyle(
                    (row.title ?? "").isEmpty ? LivTheme.muted : LivTheme.text
                )
                .lineLimit(1)
                if !chips.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(chips, id: \.self) { ValueChip($0) }
                    }
                }
            }
            Spacer(minLength: 8)
            if let due {
                Text(due.label)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(due.danger ? LivTheme.red : LivTheme.text3)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 40)
        .contentShape(Rectangle())
        .onTapGesture { desk.open(row.id) }  // rows open as Desk tabs
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
                .padding(.leading, 31)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            // The spec's full verb set (§6): Tonight / Tomorrow / Weekend /
            // Pick. Tonight matches the due sheet's 20:00; on a Friday,
            // Weekend IS tomorrow and drops out (eval §5.11).
            Button("Tonight") {
                model.setSpan(
                    row.id, "due",
                    start: Civil.stamp(day: Civil.todayDay(), hhmm: 2000),
                    end: 0, dateOnly: false)
            }
            .tint(LivTheme.accent)
            Button("Tomorrow") { reschedule(row.id, to: TasksDates.tomorrow()) }
                .tint(LivTheme.green)
            if TasksDates.weekend() != TasksDates.tomorrow() {
                Button("Weekend") { reschedule(row.id, to: TasksDates.weekend()) }
                    .tint(LivTheme.purple)
            }
            Button("Pick") { duePick = TasksDuePick(entity: row.id) }
                .tint(LivTheme.text2)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                model.trash(row.id)  // soft, reversible — never a hard delete
            } label: {
                Label("Trash", systemImage: "trash")
            }
        }
    }

    /// The ring writes the vocabulary's completes option; tapping a done
    /// task reopens it to the first non-completes option. No vocabulary =
    /// no write.
    private func toggleStatus(_ row: EntityRow, done: Bool) {
        if done {
            if let open = options.first(where: { $0.completes != true })?.name {
                model.set(row.id, "status", open)
            }
        } else if let completes = options.first(where: { $0.completes == true })?
            .name
        {
            model.set(row.id, "status", completes)
        }
    }

    private func reschedule(_ id: UInt64, to day: Int64) {
        model.setSpan(
            id, "due", start: Civil.stamp(day: day, hhmm: 0), end: 0,
            dateOnly: true)
    }

    /// Trailing due: today shows the time (or "Today"), everything else the
    /// day label. Danger strictly past — due today is not overdue.
    private func tasksDue(_ row: EntityRow) -> (label: String, danger: Bool)? {
        guard let due = row.due, due > 0 else { return nil }
        let day = Civil.day(of: due)
        let today = Civil.todayDay()
        if day == today {
            let time = Civil.timeString(due)
            return (time.isEmpty ? "Today" : time, false)
        }
        return (Civil.dayLabel(day), day < today)
    }

    /// Ref cells become chips: the cell's own display value, else the
    /// target's title from the snapshot index. Three at most — density law.
    private func refChips(_ row: EntityRow) -> [String] {
        var out: [String] = []
        for cell in row.cells ?? [] {
            guard let target = cell.refTarget else { continue }
            let value = cell.value ?? ""
            let text = value.isEmpty ? (model.entity(target)?.title ?? "") : value
            if !text.isEmpty, !out.contains(text) { out.append(text) }
            if out.count == 3 { break }
        }
        return out
    }
}

// MARK: - filter chip (selected state ValueChip doesn't carry)

/// The ValueChip recipe + a selected state: accentSoft fill, accent ink.
/// Neutral body always; the value's color stays in the dot.
private struct TasksFilterChip: View {
    let text: String
    let dot: Color?
    let selected: Bool
    let action: () -> Void

    init(_ text: String, dot: Color?, selected: Bool, action: @escaping () -> Void)
    {
        self.text = text
        self.dot = dot
        self.selected = selected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let dot {
                    Circle().fill(dot).frame(width: 6, height: 6)
                }
                Text(text)
                    .font(.system(size: 12, weight: selected ? .medium : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? LivTheme.accent : LivTheme.text2)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                Capsule().fill(selected ? LivTheme.accentSoft : LivTheme.panel2)
            )
            .overlay(
                Capsule().strokeBorder(
                    selected ? LivTheme.accent.opacity(0.5) : LivTheme.border,
                    lineWidth: 0.5)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - reschedule targets

private enum TasksDates {
    static func tomorrow() -> Int64 {
        Civil.addDays(Civil.todayDay(), 1)
    }

    /// The upcoming Saturday, strictly after today.
    static func weekend() -> Int64 {
        var day = Civil.addDays(Civil.todayDay(), 1)
        for _ in 0..<7 {
            if weekday(day) == 7 { return day }  // Gregorian: 7 = Saturday
            day = Civil.addDays(day, 1)
        }
        return day
    }

    private static func weekday(_ day: Int64) -> Int {
        var parts = DateComponents()
        parts.year = Int(day / 10_000)
        parts.month = Int((day / 100) % 100)
        parts.day = Int(day % 100)
        parts.hour = 12  // noon dodges DST-skipped midnights
        let gregorian = Calendar(identifier: .gregorian)
        guard let date = gregorian.date(from: parts) else { return 0 }
        return gregorian.component(.weekday, from: date)
    }
}

// MARK: - option hue → semantic token

/// A status option's `hue` cell (degrees) quantized to the nearest semantic
/// token — the desktop's Hues.degrees ported to this set. Canonical wheel
/// stops: red 5 · amber 40 · green 150 · accent 250 · purple 270.
private func tasksOptionColor(_ degrees: Int?) -> Color? {
    guard let degrees else { return nil }
    let wheel = Double((degrees % 360 + 360) % 360)
    let stops: [(Double, Color)] = [
        (5, LivTheme.red), (40, LivTheme.amber), (150, LivTheme.green),
        (250, LivTheme.accent), (270, LivTheme.purple),
    ]
    func distance(_ stop: Double) -> Double {
        min(abs(stop - wheel), 360 - abs(stop - wheel))
    }
    return stops.min { distance($0.0) < distance($1.0) }?.1
}
