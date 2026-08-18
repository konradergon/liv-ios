// liv iOS — Today (design/ios.md §6; rebuilt phase 5, owner-approved
// mockup 2026-08-05). Today answers "WHAT NOW?": what is late, what is
// happening, what is left. One column — the 7-day strip, the LATE strip
// (always visible when it has rows), the day as a single now-aware
// timeline, one "N done" line, the quick-add ghost, and one honest
// captured line that jumps to the Inbox. Reads ride the snapshot window
// [today-1, today+7]; every act goes through the one BoxModel.
// A row tap opens the entity as a Desk tab — no navigation stack here.

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
    /// The stored flag decides. Guessing from a 0000 stamp made a real
    /// midnight event read as all-day (review, 2026-08-06); the stamp is
    /// only consulted when the core did not say.
    var allDay: Bool { row.dueDateOnly ?? (stamp % 10_000 == 0) }
}

/// The row whose exact date and time is being picked (sheet item) — the
/// arbitrary-time door is everywhere a date can be set (owner, phase 5).
private struct TodayDuePick: Identifiable {
    let entity: UInt64
    var id: UInt64 { entity }
}

// MARK: - the screen

struct TodayView: View {
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var workspaces: WorkspaceModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedDay = Civil.todayDay()
    /// The task status vocabulary, board order; `completes` drives the
    /// ring, the LATE predicate and the done-collapse.
    @State private var taskOptions: [StatusOption] = []
    @State private var doneExpanded = false
    @State private var duePick: TodayDuePick?

    var body: some View {
        let today = Civil.todayDay()
        let now = Civil.nowStamp()
        let doneNames = Set(
            taskOptions.filter { $0.completes == true }.compactMap(\.name))
        let all = agenda(for: selectedDay)
        let allDay = all.filter(\.allDay)
        let timedOpen = all.filter { !$0.allDay && !isDone($0.row, doneNames) }
        let done = all.filter { !$0.allDay && isDone($0.row, doneNames) }
        let late = lateRows(today: today, doneNames: doneNames)
        let captured = capturedTodayCount(today: today)
        // The timeline knows the time (today only): what passed dims,
        // the next thing up is lit.
        let onToday = selectedDay == today
        let passed = onToday ? timedOpen.filter { $0.stamp < now } : []
        let ahead = onToday ? timedOpen.filter { $0.stamp >= now } : timedOpen
        let nextKey = onToday ? ahead.first?.key : nil

        List {
            Group {
                header(today: today, left: timedOpen.count + late.count)
                TodayDateStrip(selected: $selectedDay, today: today)
                    .padding(.vertical, 6)

                if !late.isEmpty {
                    lateHeader(late.count)
                    ForEach(late) { row in
                        lateLine(row, today: today, doneNames: doneNames)
                    }
                }

                if !allDay.isEmpty {
                    SectionLabel("All-day")
                        .padding(.top, 14).padding(.bottom, 4)
                    allDayBand(allDay, doneNames: doneNames)
                }

                // No day heading here (owner, 2026-08-18): the line at
                // the top of the screen and the lit chip in the strip
                // both already say which day this is, and the count was
                // furniture — the list under it is the count.
                if timedOpen.isEmpty && done.isEmpty && allDay.isEmpty {
                    EmptyHint("Nothing scheduled")
                }
                ForEach(passed) { item in
                    timedLine(item, dimmed: true, next: false, doneNames: doneNames)
                }
                if onToday, !timedOpen.isEmpty || !done.isEmpty {
                    nowLine(now)
                }
                ForEach(ahead) { item in
                    timedLine(
                        item, dimmed: false, next: item.key == nextKey,
                        doneNames: doneNames)
                }
                if !done.isEmpty {
                    doneCollapse(done.count)
                    if doneExpanded {
                        ForEach(done) { item in
                            timedLine(
                                item, dimmed: true, next: false,
                                doneNames: doneNames)
                        }
                    }
                }
                if captured > 0 {
                    capturedFooter(captured)
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
        // Room under the last row for the add button to sit over.
        .contentMargins(.bottom, 88, for: .scrollContent)
        .background(LivTheme.canvas)
        .sheet(item: $duePick) { pick in
            DetailDueSheet(
                model: box, id: pick.entity,
                property: dueProperty(box.entity(pick.entity)))
            .presentationDetents([.medium])
        }
        .onAppear {
            loadWindow()
            box.statusOptions(kind: "task") { taskOptions = $0 }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { loadWindow() }
        }
        // The bar's create key inherits the day you are looking at.
        .onAppear { desk.contextDay = selectedDay }
        .onChange(of: selectedDay) { _, day in desk.contextDay = day }
        .onDisappear { desk.contextDay = nil }
    }

    // MARK: header + section furniture

    /// The DATE, not the view's name (owner, 2026-08-18: the name is on
    /// the bar; what this line is for is which day you are looking at).
    /// The "N left" count went with it — the list under it is the count.
    private func header(today: Int64, left: Int) -> some View {
        HStack(spacing: 8) {
            Text(Civil.dayLabel(today))
                .font(.system(size: LivType.title, weight: .semibold))
                .foregroundStyle(LivTheme.text)
            if box.busyRetrying { ProgressView().scaleEffect(0.7) }
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    /// LATE means only what can still be DONE: incomplete tasks whose day
    /// has passed (owner ruling, phase 5). A past event is not late — it
    /// happened.
    private func lateHeader(_ count: Int) -> some View {
        HStack(spacing: 7) {
            Circle().fill(LivTheme.red).frame(width: 7, height: 7)
            Text("LATE")
                .font(.system(size: LivType.label, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(LivTheme.red)
            Text("\(count) task\(count == 1 ? "" : "s")")
                .font(.system(size: LivType.caption).monospacedDigit())
                .foregroundStyle(LivTheme.muted)
            Spacer()
        }
        .padding(.top, 14).padding(.bottom, 2)
    }

    private func nowLine(_ now: Int64) -> some View {
        HStack(spacing: 6) {
            Text(Civil.timeString(now))
                .font(.system(size: LivType.micro, weight: .bold).monospacedDigit())
                .foregroundStyle(LivTheme.onAccent)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(LivTheme.red))
            Rectangle().fill(LivTheme.red).frame(height: 1.5)
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }

    private func doneCollapse(_ count: Int) -> some View {
        Button {
            doneExpanded.toggle()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: doneExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: LivType.micro, weight: .semibold))
                Text("\(count) done today")
                    .font(.system(size: LivType.body).monospacedDigit())
                Spacer()
            }
            .foregroundStyle(LivTheme.muted)
            .frame(minHeight: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
        }
    }

    /// One honest line, not a tile that disagrees with its own section:
    /// today's captures, and the door to the place that routes them.
    private func capturedFooter(_ count: Int) -> some View {
        Button {
            desk.go(.inbox)
        } label: {
            HStack(spacing: 6) {
                Text("\(count) captured today")
                    .font(.system(size: LivType.body).monospacedDigit())
                    .foregroundStyle(LivTheme.text3)
                Text("· Route them")
                    .font(.system(size: LivType.body, weight: .semibold))
                    .foregroundStyle(LivTheme.accent)
                Spacer()
            }
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    // MARK: rows — a tap opens the entity as a Desk tab

    /// A late task: ring, title, the day it was due (red), and one-tap
    /// Today. Swipe: Tomorrow / Pick (the arbitrary date-and-time door).
    private func lateLine(
        _ row: EntityRow, today: Int64, doneNames: Set<String>
    ) -> some View {
        HStack(spacing: 8) {
            StatusRing(done: false) { toggleStatus(row.id) }
            Text(displayTitle(row))
                .font(.system(size: LivType.body))
                .foregroundStyle(LivTheme.text)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(Civil.dayLabel(Civil.day(of: row.due ?? 0)))
                .font(.system(size: LivType.caption).monospacedDigit())
                .foregroundStyle(LivTheme.red)
            // A VERB, in plain accent text (surface pass, owner
            // 2026-08-18). It wore a filled capsule with a border, and
            // eleven of them down a column of late tasks was the
            // loudest thing on the screen — louder than the lateness it
            // was offering to fix.
            Button {
                reschedule(row, toDay: today)
            } label: {
                Text("Today")
                    .font(.system(size: LivType.body, weight: .medium))
                    .foregroundStyle(LivTheme.accent)
                    .padding(.leading, 6)
                    .frame(height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture { desk.open(row.id) }
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            rescheduleSwipe(row)
        }
    }

    /// A timed line: time, the Calendar's colour for its kind (purple
    /// task, blue event, grey note), title, context chips — never the
    /// row's own type.
    private func timedLine(
        _ item: TodayAgendaItem, dimmed: Bool, next: Bool,
        doneNames: Set<String>
    ) -> some View {
        let row = item.row
        let task = livCanTick(row)
        let done = isDone(row, doneNames)
        let chips = contextChips(row)
        return HStack(spacing: 8) {
            Text(Civil.timeString(item.stamp))
                .font(.system(size: LivType.label).monospacedDigit())
                .foregroundStyle(dimmed ? LivTheme.muted : LivTheme.text3)
                .frame(width: 40, alignment: .leading)
            // ONE mark, in a fixed column so every title starts at the
            // same place. The coloured vertical bar is gone (owner,
            // 2026-08-08) — it said "task or event" a third time. This
            // slot never doubles up either: a tickable row shows its
            // ring and nothing else, and the kind glyph appears only
            // where the row had no mark at all (an event, a note, a
            // file), drawn bare so it sits at the ring's weight.
            Group {
                if item.occurrence {
                    Image(systemName: "repeat")
                        .font(.system(size: LivType.caption, weight: .semibold))
                        .foregroundStyle(LivTheme.text3)
                } else if task {
                    StatusRing(done: done, compact: true) { toggleStatus(row.id) }
                } else {
                    LivIcon(
                        glyph: LivKind.glyph(of: row),
                        color: LivKind.color(of: row), size: 17)
                }
            }
            .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle(row))
                    .font(.system(size: LivType.body))
                    .foregroundStyle(
                        dimmed || done ? LivTheme.muted : LivTheme.text)
                    .lineLimit(1)
                if !chips.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(chips, id: \.self) { ValueChip($0) }
                    }
                }
            }
            Spacer(minLength: 6)
        }
        .frame(minHeight: 44)
        .background(next ? LivTheme.tint(LivTheme.accent, 0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { desk.open(row.id) }
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !item.occurrence { rescheduleSwipe(row) }
        }
    }

    /// The all-day band: pills; a timeless TASK keeps its ring (checking
    /// it off must never require hunting).
    private func allDayBand(
        _ items: [TodayAgendaItem], doneNames: Set<String>
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items) { item in
                    HStack(spacing: 5) {
                        if item.occurrence {
                            Image(systemName: "repeat")
                                .font(.system(size: LivType.micro, weight: .semibold))
                                .foregroundStyle(LivTheme.text3)
                        } else if !livCanTick(item.row) {
                            LivIcon(
                                glyph: LivKind.glyph(of: item.row),
                                color: LivKind.color(of: item.row), size: 14)
                        } else if livCanTick(item.row) {
                            StatusRing(
                                done: isDone(item.row, doneNames), compact: true
                            ) {
                                toggleStatus(item.row.id)
                            }
                        }
                        Button {
                            desk.open(item.row.id)
                        } label: {
                            Text(displayTitle(item.row))
                                .font(.system(size: LivType.body))
                                .foregroundStyle(
                                    isDone(item.row, doneNames)
                                        ? LivTheme.text3 : LivTheme.text)
                                .lineLimit(1)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(LivTheme.panel2))
                    .overlay(Capsule().strokeBorder(LivTheme.border, lineWidth: 0.5))
                }
            }
        }
    }

    /// Tomorrow keeps the span AND the time of day; Pick opens the real
    /// date-and-time editor. (The old swipe wrote end:0 + dateOnly:true —
    /// "Tomorrow" on a two-hour meeting destroyed both, phase-5 recon.)
    @ViewBuilder private func rescheduleSwipe(_ row: EntityRow) -> some View {
        Button {
            reschedule(row, toDay: Civil.addDays(Civil.todayDay(), 1))
        } label: {
            Label("Tomorrow", systemImage: "arrow.turn.up.right")
        }
        .tint(LivTheme.green)
        Button {
            duePick = TodayDuePick(entity: row.id)
        } label: {
            Label("Pick", systemImage: "calendar")
        }
        .tint(LivTheme.accent)
    }

    // MARK: snapshot slices

    /// The lens (M4) + the archived filter Today always lacked (recon,
    /// phase 5 — Tasks and Everything both had it).
    private var datedRows: [EntityRow] {
        let lens = workspaces.activeQuery
        return (box.snap?.dated ?? []).compactMap { box.entity($0) }
            .filter {
                $0.trashed != true && $0.archived != true && lens.matches($0)
            }
    }

    private func dueRows(on day: Int64) -> [EntityRow] {
        datedRows.filter { row in
            guard let due = row.due else { return false }
            return Civil.day(of: due) == day
        }
    }

    /// One time-ordered timeline — events and tasks interleave by clock,
    /// the way the day actually runs (the old view kept them in separate
    /// blocks). Occurrences merge in, deduped against a series dated on
    /// the day itself.
    private func agenda(for day: Int64) -> [TodayAgendaItem] {
        var items = dueRows(on: day).map { row in
            TodayAgendaItem(
                key: "e\(row.id)", row: row, stamp: row.due ?? 0,
                occurrence: false)
        }
        let dayIds = Set(items.map(\.row.id))
        // The lens applies to occurrence SERIES rows too — a filtered
        // surface filters whole.
        let lens = workspaces.activeQuery
        for occ in box.snap?.occurrences ?? [] {
            guard let series = occ.series, let civil = occ.civil,
                Civil.day(of: civil) == day, !dayIds.contains(series),
                let row = box.entity(series), row.trashed != true,
                row.archived != true, lens.matches(row)
            else { continue }
            items.append(
                TodayAgendaItem(
                    key: "o\(series)-\(civil)", row: row, stamp: civil,
                    occurrence: true))
        }
        return items.sorted {
            $0.stamp != $1.stamp ? $0.stamp < $1.stamp : $0.row.id < $1.row.id
        }
    }

    /// LATE = incomplete TASKS whose day has passed (owner ruling). Not
    /// events, not notes — a thing is late only if it can still be done.
    private func lateRows(today: Int64, doneNames: Set<String>) -> [EntityRow] {
        datedRows.filter { row in
            guard row.kinds?.contains("task") == true, let due = row.due
            else { return false }
            return Civil.day(of: due) < today && !isDone(row, doneNames)
        }
        .sorted { ($0.due ?? 0) > ($1.due ?? 0) }
    }

    private func capturedTodayCount(today: Int64) -> Int {
        let lens = workspaces.activeQuery
        return (box.snap?.unstructured ?? []).compactMap { box.entity($0) }
            .filter { row in
                guard row.trashed != true, let created = row.created else {
                    return false
                }
                return Civil.day(of: created) == today && lens.matches(row)
            }
            .count
    }

    // MARK: predicates + acts


    private func isDone(_ row: EntityRow, _ doneNames: Set<String>) -> Bool {
        row.status.map { doneNames.contains($0) } ?? false
    }

    private func displayTitle(_ row: EntityRow) -> String { livRowTitle(row) }

    /// Context, never the row's own type: the type cell is a reference
    /// too, and it is the FIRST cell written — so the naive "first ref"
    /// chip read "task" on every task (recon, phase 5).
    private func contextChips(_ row: EntityRow) -> [String] {
        var out: [String] = []
        for cell in row.cells ?? [] {
            guard cell.property != "type", cell.refTarget != nil,
                let value = cell.value, !value.isEmpty
            else { continue }
            if !out.contains(value) { out.append(value) }
            if out.count == 2 { break }
        }
        return out
    }

    private func dueProperty(_ row: EntityRow?) -> String {
        let name = row?.positionedBy ?? "due"
        return name.isEmpty ? "due" : name
    }

    /// Move the DAY, keep everything else: the time of day survives, and
    /// a span's end shifts by the same number of days.
    private func reschedule(_ row: EntityRow, toDay day: Int64) {
        let start = row.due ?? Civil.stamp(day: day, hhmm: 0)
        let hhmm = start % 10_000
        var end: Int64 = 0
        if let e = row.dueEnd, e > 0 {
            let delta = Civil.daysBetween(Civil.day(of: start), day)
            end = Civil.stamp(
                day: Civil.addDays(Civil.day(of: e), delta), hhmm: e % 10_000)
        }
        box.setSpan(
            row.id, dueProperty(row),
            start: Civil.stamp(day: day, hhmm: hhmm), end: end,
            dateOnly: row.dueDateOnly ?? (hhmm == 0))
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
                            .font(.system(size: LivType.micro, weight: .semibold))
                            .foregroundStyle(
                                isSelected ? LivTheme.onAccent : LivTheme.text3)
                        Text("\(Civil.dayNumber(day))")
                            .font(
                                .system(size: LivType.body, weight: .semibold)
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
