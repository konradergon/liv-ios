// liv iOS — Today (design/ios.md §6). The day at a glance: 7-day strip,
// 2×2 count tiles, one merged agenda (events by civil time, then dues,
// then the inline quick-add ghost row), the captured-today strip. Reads
// ride the snapshot window [today-1, today+7]; every act goes through
// the one BoxModel, act-then-refresh.
// The chrome owns the top bar, settings, and the bottom bar; a row tap
// opens the entity as a Desk tab (desk.open) — no navigation stack here.

import SwiftUI

// MARK: - agenda assembly

/// One agenda line: a dated entity, or an occurrence projecting its series
/// row. Occurrences are projections — no swipes, no status ring.
private struct TodayAgendaItem: Identifiable {
    let key: String
    let row: EntityRow
    let stamp: Int64
    let occurrence: Bool
    var id: String { key }
}

// MARK: - the screen

struct TodayView: View {
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var workspaces: WorkspaceModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedDay = Civil.todayDay()
    /// The task status vocabulary, board order; `completes` drives the
    /// ring and the overdue predicate.
    @State private var taskOptions: [StatusOption] = []
    @State private var showOverdue = false
    @State private var capturedExpanded = false

    var body: some View {
        let today = Civil.todayDay()
        let doneNames = Set(
            taskOptions.filter { $0.completes == true }.compactMap(\.name))
        let items = agenda(for: selectedDay)
        let overdue = overdueRows(today: today, doneNames: doneNames)
        let captured = capturedRows(today: today)

        List {
            Group {
                HStack(spacing: 8) {
                    SectionLabel("Today · " + Civil.dayLabel(today))
                    // Why the list is short — never a mystery (M4).
                    if workspaces.lensOn { LensChip(label: workspaces.lensLabel) }
                    if box.busyRetrying { ProgressView().scaleEffect(0.7) }
                }
                .padding(.top, 8)
                TodayDateStrip(selected: $selectedDay, today: today)
                    .padding(.vertical, 6)
                countTiles(
                    today: today,
                    todayCount: selectedDay == today
                        ? items.count : agenda(for: today).count,
                    overdueCount: overdue.count,
                    capturedTotal: capturedTotal)
                if showOverdue && !overdue.isEmpty {
                    SectionLabel(
                        "Overdue", trailing: "Hide",
                        trailingAction: { showOverdue = false }
                    )
                    .padding(.top, 14).padding(.bottom, 2)
                    ForEach(overdue) { row in
                        overdueLine(row, doneNames: doneNames, today: today)
                    }
                }
                SectionLabel(
                    selectedDay == today
                        ? "Agenda · today"
                        : "Agenda · \(Civil.dayLabel(selectedDay))",
                    trailing: items.isEmpty ? nil : "\(items.count)"
                )
                .padding(.top, 14).padding(.bottom, 2)
                if items.isEmpty {
                    EmptyHint("Nothing scheduled")
                } else {
                    ForEach(items) { item in
                        agendaLine(item, doneNames: doneNames, today: today)
                    }
                }
                TodayQuickAddRow(day: selectedDay)
                if !captured.isEmpty {
                    SectionLabel(
                        "Captured today",
                        trailing: capturedExpanded
                            ? "Hide" : "Show \(captured.count)",
                        trailingAction: { capturedExpanded.toggle() }
                    )
                    .padding(.top, 14).padding(.bottom, 2)
                    if capturedExpanded {
                        ForEach(captured) { row in capturedLine(row) }
                    }
                }
            }
            .listRowInsets(
                EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 10)
        .contentMargins(.bottom, 76, for: .scrollContent)  // the floating bar
        .background(LivTheme.canvas)
        .onAppear {
            loadWindow()
            box.statusOptions(kind: "task") { taskOptions = $0 }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { loadWindow() }
        }
    }

    // MARK: tiles

    private func countTiles(
        today: Int64, todayCount: Int, overdueCount: Int, capturedTotal: Int
    ) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ],
            spacing: 8
        ) {
            CountTile(count: todayCount, label: "Today") {
                selectedDay = today
            }
            CountTile(
                count: overdueCount, label: "Overdue",
                danger: overdueCount > 0
            ) {
                showOverdue.toggle()
            }
            CountTile(count: upcomingCount(today: today), label: "Upcoming 7d") {
                selectedDay = Civil.addDays(today, 1)
            }
            CountTile(count: capturedTotal, label: "Captured") {
                capturedExpanded.toggle()
            }
        }
        .padding(.top, 2)
    }

    // MARK: rows — a tap opens the entity as a Desk tab

    @ViewBuilder
    private func agendaLine(
        _ item: TodayAgendaItem, doneNames: Set<String>, today: Int64
    ) -> some View {
        TodayRow(
            row: item.row,
            occurrence: item.occurrence,
            done: isDone(item.row, doneNames),
            toggle: !item.occurrence && isTask(item.row)
                ? { toggleStatus(item.row.id) } : nil,
            trailing: Civil.timeString(item.stamp),
            danger: isOverdue(item.row, doneNames: doneNames, today: today)
        )
        .contentShape(Rectangle())
        .onTapGesture { desk.open(item.row.id) }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !item.occurrence { rescheduleButtons(item.row) }
        }
        .swipeActions(edge: .trailing) {
            if !item.occurrence {
                Button(role: .destructive) {
                    box.trash(item.row.id)
                } label: {
                    Label("Trash", systemImage: "trash")
                }
            }
        }
    }

    /// An overdue line reads its DAY, not a time — "14:00" three days late
    /// says nothing.
    @ViewBuilder
    private func overdueLine(
        _ row: EntityRow, doneNames: Set<String>, today: Int64
    ) -> some View {
        TodayRow(
            row: row,
            occurrence: false,
            done: isDone(row, doneNames),
            toggle: isTask(row) ? { toggleStatus(row.id) } : nil,
            trailing: Civil.dayLabel(Civil.day(of: row.due ?? 0)),
            danger: true
        )
        .contentShape(Rectangle())
        .onTapGesture { desk.open(row.id) }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            rescheduleButtons(row)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                box.trash(row.id)
            } label: {
                Label("Trash", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func capturedLine(_ row: EntityRow) -> some View {
        TodayCapturedRow(row: row)
            .contentShape(Rectangle())
            .onTapGesture { desk.open(row.id) }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    box.trash(row.id)
                } label: {
                    Label("Trash", systemImage: "trash")
                }
            }
    }

    @ViewBuilder
    private func rescheduleButtons(_ row: EntityRow) -> some View {
        let property = row.positionedBy ?? "due"
        Button {
            box.setSpan(
                row.id, property,
                start: Civil.stamp(day: Civil.todayDay(), hhmm: 1800),
                end: 0, dateOnly: false)
        } label: {
            Label("18:00", systemImage: "sun.max")
        }
        .tint(LivTheme.accent)
        Button {
            box.setSpan(
                row.id, property,
                start: Civil.stamp(
                    day: Civil.addDays(Civil.todayDay(), 1), hhmm: 0),
                end: 0, dateOnly: true)
        } label: {
            Label("Tomorrow", systemImage: "arrow.turn.up.right")
        }
        .tint(LivTheme.green)
        // On a Friday, Weekend IS tomorrow — one option, not two.
        if Self.nextWeekend(after: Civil.todayDay()) != Civil.addDays(Civil.todayDay(), 1) {
            Button {
                box.setSpan(
                    row.id, property,
                    start: Civil.stamp(
                        day: Self.nextWeekend(after: Civil.todayDay()), hhmm: 0),
                    end: 0, dateOnly: true)
            } label: {
                Label("Weekend", systemImage: "beach.umbrella")
            }
            .tint(LivTheme.purple)
        }
    }

    // MARK: snapshot slices

    /// The lens (M4): the active workspace's query, run client-side over
    /// the rows the phone already holds. An inert query costs one branch.
    private var datedRows: [EntityRow] {
        let lens = workspaces.activeQuery
        return (box.snap?.dated ?? []).compactMap { box.entity($0) }
            .filter { $0.trashed != true && lens.matches($0) }
    }

    private func dueRows(on day: Int64) -> [EntityRow] {
        datedRows.filter { row in
            guard let due = row.due else { return false }
            return Civil.day(of: due) == day
        }
    }

    /// Events (kind "event") by time, then tasks/dues by time; occurrences
    /// merge into the event block, deduped against a series that is itself
    /// dated on the day.
    private func agenda(for day: Int64) -> [TodayAgendaItem] {
        let rows = dueRows(on: day)
        var events: [TodayAgendaItem] = []
        var tasks: [TodayAgendaItem] = []
        for row in rows {
            let item = TodayAgendaItem(
                key: "e\(row.id)", row: row, stamp: row.due ?? 0,
                occurrence: false)
            if row.kinds?.contains("event") == true {
                events.append(item)
            } else {
                tasks.append(item)
            }
        }
        let dayIds = Set(rows.map(\.id))
        for occ in box.snap?.occurrences ?? [] {
            guard let series = occ.series, let civil = occ.civil,
                Civil.day(of: civil) == day, !dayIds.contains(series),
                let row = box.entity(series), row.trashed != true
            else { continue }
            events.append(
                TodayAgendaItem(
                    key: "o\(series)-\(civil)", row: row, stamp: civil,
                    occurrence: true))
        }
        let byTime: (TodayAgendaItem, TodayAgendaItem) -> Bool = {
            $0.stamp != $1.stamp ? $0.stamp < $1.stamp : $0.row.id < $1.row.id
        }
        return events.sorted(by: byTime) + tasks.sorted(by: byTime)
    }

    /// Overdue = dated, day strictly before today, status not a completing
    /// one (no status counts as open).
    private func overdueRows(today: Int64, doneNames: Set<String>)
        -> [EntityRow]
    {
        datedRows.filter { row in
            guard let due = row.due else { return false }
            return Civil.day(of: due) < today && !isDone(row, doneNames)
        }
        .sorted { ($0.due ?? 0) < ($1.due ?? 0) }
    }

    private func upcomingCount(today: Int64) -> Int {
        let horizon = Civil.addDays(today, 7)
        return datedRows.filter { row in
            guard let due = row.due else { return false }
            let d = Civil.day(of: due)
            return d > today && d <= horizon
        }.count
    }

    /// The Captured tile counts what the lens shows — a tile that disagrees
    /// with the section under it is worse than no tile.
    private var capturedTotal: Int {
        let lens = workspaces.activeQuery
        return (box.snap?.unstructured ?? []).compactMap { box.entity($0) }
            .filter { $0.trashed != true && lens.matches($0) }
            .count
    }

    private func capturedRows(today: Int64) -> [EntityRow] {
        let lens = workspaces.activeQuery
        return (box.snap?.unstructured ?? []).compactMap { box.entity($0) }
            .filter { row in
                guard row.trashed != true, let created = row.created else {
                    return false
                }
                return Civil.day(of: created) == today && lens.matches(row)
            }
            .sorted { ($0.created ?? 0) > ($1.created ?? 0) }
    }

    // MARK: predicates + acts

    /// The reference shell's task test: the kind, or any status at all.
    private func isTask(_ row: EntityRow) -> Bool {
        row.kinds?.contains("task") == true || row.status != nil
    }

    private func isDone(_ row: EntityRow, _ doneNames: Set<String>) -> Bool {
        row.status.map { doneNames.contains($0) } ?? false
    }

    private func isOverdue(
        _ row: EntityRow, doneNames: Set<String>, today: Int64
    ) -> Bool {
        guard let due = row.due else { return false }
        return Civil.day(of: due) < today && !isDone(row, doneNames)
    }

    /// Ring tap: open -> first completing option, done -> first open one.
    /// No vocabulary, no write.
    private func toggleStatus(_ id: UInt64) {
        guard let row = box.entity(id) else { return }
        let doneNames = Set(
            taskOptions.filter { $0.completes == true }.compactMap(\.name))
        let target = isDone(row, doneNames)
            ? taskOptions.first { $0.completes != true }
            : taskOptions.first { $0.completes == true }
        guard let name = target?.name, !name.isEmpty else { return }
        box.set(id, "status", name)
    }

    /// The spec'd window: yesterday 00:00 through today+7 23:59. Also
    /// snaps a stale selection forward across midnight (the strip starts
    /// at today; a selection behind it would be invisible).
    private func loadWindow() {
        let today = Civil.todayDay()
        if selectedDay < today { selectedDay = today }
        box.refreshWindow(
            from: Civil.stamp(day: Civil.addDays(today, -1), hhmm: 0),
            to: Civil.stamp(day: Civil.addDays(today, 7), hhmm: 2359))
    }

    /// Next Saturday, strictly ahead — a weekend reschedule issued ON a
    /// weekend means the next one.
    private static func nextWeekend(after day: Int64) -> Int64 {
        var parts = DateComponents()
        parts.year = Int(day / 10_000)
        parts.month = Int((day / 100) % 100)
        parts.day = Int(day % 100)
        parts.hour = 12
        let cal = Calendar(identifier: .gregorian)
        guard let date = cal.date(from: parts) else {
            return Civil.addDays(day, 1)
        }
        let weekday = cal.component(.weekday, from: date)  // 1=Sun … 7=Sat
        let ahead = (7 - weekday) % 7
        return Civil.addDays(day, ahead == 0 ? 7 : ahead)
    }
}

// MARK: - the 7-day strip

/// Today ringed accent, the selected day filled; both = filled wins.
private struct TodayDateStrip: View {
    @Binding var selected: Int64
    let today: Int64

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                let day = Civil.addDays(today, i)
                let isSelected = day == selected
                let isToday = day == today
                Button {
                    selected = day
                } label: {
                    VStack(spacing: 2) {
                        Text(Civil.weekdayLetter(day))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(
                                isSelected ? LivTheme.onAccent : LivTheme.text3)
                        Text("\(Civil.dayNumber(day))")
                            .font(
                                .system(size: 13, weight: .semibold)
                                    .monospacedDigit()
                            )
                            .foregroundStyle(
                                isSelected ? LivTheme.onAccent : LivTheme.text)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: LivTheme.radius)
                            .fill(isSelected ? LivTheme.accent : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: LivTheme.radius)
                            .strokeBorder(
                                isToday && !isSelected
                                    ? LivTheme.accent : Color.clear,
                                lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - rows

/// The compact agenda row: leading slot (ring / repeat / calendar), title,
/// first reference chip, trailing time — 42pt, hairline underneath.
private struct TodayRow: View {
    let row: EntityRow
    let occurrence: Bool
    let done: Bool
    let toggle: (() -> Void)?
    let trailing: String
    let danger: Bool

    private var title: String {
        let t = row.title ?? ""
        return t.isEmpty ? "Untitled" : t
    }

    private var refValue: String? {
        row.cells?.first {
            $0.kind == "reference" && ($0.value?.isEmpty == false)
        }?.value
    }

    var body: some View {
        HStack(spacing: 6) {
            if occurrence {
                Image(systemName: "repeat")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(LivTheme.text3)
                    .frame(width: 31)
            } else if let toggle {
                StatusRing(done: done, action: toggle)
            } else {
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                    .foregroundStyle(LivTheme.text3)
                    .frame(width: 31)
            }
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(done ? LivTheme.text3 : LivTheme.text)
                .lineLimit(1)
            if let refValue { ValueChip(refValue) }
            Spacer(minLength: 6)
            if !trailing.isEmpty {
                Text(trailing)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(danger ? LivTheme.red : LivTheme.text3)
            }
        }
        .frame(minHeight: 42)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
        }
    }
}

/// The inline quick-add ghost row (eval §4.1 — ClickUp's context-inheriting
/// "New" row): a name typed under a day becomes a task DUE that day,
/// date-only, no picker — tap, type, return = a dated task, 3 gestures.
/// The field clears only on create success and keeps focus for serial adds.
private struct TodayQuickAddRow: View {
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var workspaces: WorkspaceModel
    let day: Int64

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            // Dashed StatusRing ghost — a task that isn't yet.
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(
                    LivTheme.muted,
                    style: StrokeStyle(lineWidth: 1.5, dash: [2.5])
                )
                .frame(width: 15, height: 15)
                .frame(width: 31)
            TextField("New for \(Civil.dayLabel(day))…", text: $text)
                .font(.system(size: 13))
                .foregroundStyle(LivTheme.text)
                .textInputAutocapitalization(.never)  // capture-verbatim law
                .autocorrectionDisabled(true)
                .focused($focused)
                .onSubmit(submit)
            // No post-save chip strip here, so the stamp is promised
            // BEFORE the write rather than shown after it.
            if !workspaces.stampHint.isEmpty {
                Text(workspaces.stampHint)
                    .font(.system(size: 10))
                    .foregroundStyle(LivTheme.muted)
                    .lineLimit(1)
                    .padding(.trailing, 4)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
        }
    }

    /// Create only on real text; on success (id != 0) name + due land as
    /// their own acts and the trailing refresh surfaces the row above.
    /// A refused create keeps the draft — the field never clears on failure.
    private func submit() {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let day = self.day
        box.createTask { id in
            guard id != 0 else { return }
            box.set(id, "name", name)
            box.setSpan(
                id, "due", start: Civil.stamp(day: day, hhmm: 0),
                end: 0, dateOnly: true)
            // The active workspace stamps here too (M4) — otherwise a task
            // added while looking at Work lacks Work's cells and vanishes
            // from the very list it was typed into. The row's hint says so
            // before the write.
            workspaces.stamp(id, in: box)
            text = ""
            focused = true
        }
    }
}

/// A captured scrap: muted dot, title, capture time. Untyped on purpose —
/// routing happens in the Inbox, not here.
private struct TodayCapturedRow: View {
    let row: EntityRow

    private var title: String {
        let t = row.title ?? ""
        return t.isEmpty ? "Untitled" : t
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(LivTheme.muted)
                .frame(width: 5, height: 5)
                .frame(width: 31)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(LivTheme.text2)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let created = row.created {
                Text(Civil.timeString(created))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(LivTheme.text3)
            }
        }
        .frame(minHeight: 40)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
        }
    }
}
