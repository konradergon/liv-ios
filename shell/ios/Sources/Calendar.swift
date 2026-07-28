// liv iOS — Calendar (design/ios.md §6): a compact month grid (Mon-first,
// six fixed weeks, ≤3 neutral ink dots per day — never a color rainbow)
// over a FIXED day panel: all-day pills first, then rows chronologically.
// `dated` is the full set (bucketed by civil day client-side); only
// `occurrences` ride the snapshot window, so the grid re-windows over the
// VISIBLE six-week span on every month change. Occurrence rows project
// their SERIES entity — repeat glyph, read-only, tap opens the series.
// A row tap opens a Desk tab (desk.open dismisses this window by the
// chrome's own rule). Long-press a day = create an event on it — the
// capture-asks-nothing door: no dialog, the new event lands as a desk tab
// for naming, and the workspace stamps it (every creation door stamps, M4).

import SwiftUI
import UIKit

// MARK: - day items

/// One calendar line: a dated entity, or an occurrence projecting its
/// series row. All-day = a stamp with no time part (date-only writes 0000
/// by construction; a literal-midnight event is indistinguishable and
/// accepted — Today shows it timeless too).
private struct CalendarDayItem: Identifiable {
    let key: String
    let row: EntityRow
    let stamp: Int64
    let occurrence: Bool
    var id: String { key }
    var allDay: Bool { stamp % 10_000 == 0 }
}

// MARK: - the screen

struct CalendarView: View {
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var workspaces: WorkspaceModel
    @Environment(\.scenePhase) private var scenePhase

    /// First day of the shown month (packed civil), the grid's anchor.
    @State private var monthFirst = CalGrid.firstOfMonth(Civil.todayDay())
    @State private var selectedDay = Civil.todayDay()
    /// The task status vocabulary — the ring writes the `completes`-marked
    /// option, never a hardcoded "done" (same as Today).
    @State private var taskOptions: [StatusOption] = []

    var body: some View {
        let today = Civil.todayDay()
        let byDay = itemsByDay()
        let items = byDay[selectedDay] ?? []
        let doneNames = Set(
            taskOptions.filter { $0.completes == true }.compactMap(\.name))

        VStack(spacing: 0) {
            header(today: today)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            weekdayRow
                .padding(.horizontal, 16)
                .padding(.top, 10)
            monthGrid(today: today, byDay: byDay)
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 8)
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
            dayPanel(items: items, today: today, doneNames: doneNames)
        }
        .background(LivTheme.canvas)
        .onAppear {
            loadWindow()
            box.statusOptions(kind: "task") { taskOptions = $0 }
        }
        .onChange(of: monthFirst) { _, _ in loadWindow() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { loadWindow() }
        }
    }

    // MARK: header — month title, Today, prev/next

    private func header(today: Int64) -> some View {
        HStack(spacing: 8) {
            Text(CalGrid.title(monthFirst))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LivTheme.text)
            // Why the grid is sparse — never a mystery (M4).
            if workspaces.lensOn { LensChip(label: workspaces.lensLabel) }
            if box.busyRetrying { ProgressView().scaleEffect(0.7) }
            Spacer()
            Button {
                monthFirst = CalGrid.firstOfMonth(today)
                selectedDay = today
            } label: {
                Text("Today")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LivTheme.accent)
                    .padding(.horizontal, 6)
                    .frame(height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Today")
            chevron("chevron.left", label: "Previous month") { step(-1) }
            chevron("chevron.right", label: "Next month") { step(1) }
        }
    }

    private func chevron(
        _ icon: String, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LivTheme.text2)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Month step keeps the selection sensible: today when the shown month
    /// holds it, else the month's first day — a selected day the grid can't
    /// show would make the panel a mystery.
    private func step(_ n: Int) {
        let moved = CalGrid.addMonths(monthFirst, n)
        monthFirst = moved
        let today = Civil.todayDay()
        selectedDay = CalGrid.firstOfMonth(today) == moved ? today : moved
    }

    // MARK: the grid — 6 fixed weeks, Mon-first, ~40pt cells

    private var weekdayRow: some View {
        HStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { i in
                Text(CalGrid.weekdayLetters[i])
                    .font(.system(size: 9, weight: .semibold))
                    .kerning(0.3)
                    .foregroundStyle(LivTheme.text3)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func monthGrid(
        today: Int64, byDay: [Int64: [CalendarDayItem]]
    ) -> some View {
        let start = CalGrid.gridStart(monthFirst)
        return VStack(spacing: 2) {
            ForEach(0..<6, id: \.self) { week in
                HStack(spacing: 2) {
                    ForEach(0..<7, id: \.self) { col in
                        let day = Civil.addDays(start, week * 7 + col)
                        dayCell(
                            day, today: today,
                            count: byDay[day]?.count ?? 0)
                    }
                }
            }
        }
    }

    /// Today ringed accent, the selected day filled; both = filled wins
    /// (the 7-day strip's rule). Dots are neutral ink only — the calendar
    /// says WHEN, never what kind. Long-press = the event door.
    private func dayCell(_ day: Int64, today: Int64, count: Int) -> some View {
        let inMonth = CalGrid.firstOfMonth(day) == monthFirst
        let isToday = day == today
        let isSelected = day == selectedDay
        return VStack(spacing: 3) {
            Text("\(Civil.dayNumber(day))")
                .font(
                    .system(size: 13, weight: isToday ? .semibold : .regular)
                        .monospacedDigit()
                )
                .foregroundStyle(
                    isSelected
                        ? LivTheme.onAccent
                        : inMonth ? LivTheme.text : LivTheme.muted)
            HStack(spacing: 2.5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(
                            i < min(count, 3)
                                ? (isSelected ? LivTheme.onAccent : LivTheme.text3)
                                : Color.clear
                        )
                        .frame(width: 4, height: 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: LivTheme.radiusSm)
                .fill(isSelected ? LivTheme.accent : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LivTheme.radiusSm)
                .strokeBorder(
                    isToday && !isSelected ? LivTheme.accent : Color.clear,
                    lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedDay = day }
        .onLongPressGesture(minimumDuration: 0.45) { createEvent(on: day) }
        .accessibilityLabel(Civil.dayLabel(day))
        .accessibilityValue(count == 0 ? "" : "\(count) items")
    }

    /// The event door: create-then-open, capture-asks-nothing — no dialog;
    /// the fresh event lands as a desk tab for naming. The workspace stamps
    /// it (every creation door stamps, M4). desk.open also dismisses this
    /// window — the chrome's own rule.
    private func createEvent(on day: Int64) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        box.createEvent(
            dueCivil: Civil.stamp(day: day, hhmm: 0), dateOnly: true
        ) { id in
            guard id != 0 else { return }
            workspaces.stamp(id, in: box)
            desk.open(id)
        }
    }

    // MARK: the day panel — pills, rows, quick-add (fixed, not a modal)

    private func dayPanel(
        items: [CalendarDayItem], today: Int64, doneNames: Set<String>
    ) -> some View {
        // Pills = all-day non-tasks; a date-only TASK keeps its row (and
        // its StatusRing — a pill would swallow the toggle) and sorts
        // first, its time column empty.
        let pills = items.filter { $0.allDay && !isTask($0.row) }
        let rows = items.filter { !($0.allDay && !isTask($0.row)) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(
                    selectedDay == today
                        ? "Today · " + Civil.dayLabel(selectedDay)
                        : Civil.dayLabel(selectedDay),
                    trailing: items.isEmpty ? nil : "\(items.count)"
                )
                .padding(.top, 10)
                .padding(.bottom, 2)
                if !pills.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(pills) { allDayPill($0) }
                        }
                    }
                    .padding(.vertical, 6)
                }
                if items.isEmpty {
                    EmptyHint("Nothing on this day")
                }
                ForEach(rows) { item in
                    dayLine(item, doneNames: doneNames)
                }
                CalendarQuickAddRow(day: selectedDay)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }

    private func allDayPill(_ item: CalendarDayItem) -> some View {
        Button {
            desk.open(item.row.id)
        } label: {
            HStack(spacing: 4) {
                if item.occurrence {
                    Image(systemName: "repeat")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(LivTheme.text3)
                }
                Text(title(item.row))
                    .font(.system(size: 12))
                    .foregroundStyle(LivTheme.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(LivTheme.panel2))
            .overlay(Capsule().strokeBorder(LivTheme.border, lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// 13pt tabular time column, then the leading slot (ring / repeat /
    /// calendar), title — 44pt, hairline underneath. Tap opens the entity
    /// (an occurrence opens its SERIES) as a desk tab.
    private func dayLine(
        _ item: CalendarDayItem, doneNames: Set<String>
    ) -> some View {
        HStack(spacing: 6) {
            Text(item.allDay ? "" : Civil.timeString(item.stamp))
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(LivTheme.text3)
                .frame(width: 44, alignment: .leading)
            if item.occurrence {
                Image(systemName: "repeat")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(LivTheme.text3)
                    .frame(width: 31)
            } else if isTask(item.row) {
                StatusRing(done: isDone(item.row, doneNames)) {
                    toggleStatus(item.row.id)
                }
            } else {
                Image(systemName: "calendar")
                    .font(.system(size: 11))
                    .foregroundStyle(LivTheme.text3)
                    .frame(width: 31)
            }
            Text(title(item.row))
                .font(.system(size: 13))
                .foregroundStyle(
                    isDone(item.row, doneNames) ? LivTheme.text3 : LivTheme.text
                )
                .lineLimit(1)
            Spacer(minLength: 6)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
        }
        .onTapGesture { desk.open(item.row.id) }
    }

    // MARK: snapshot slices

    /// One pass over `dated` + `occurrences`, lens-filtered (M4), bucketed
    /// by civil day, each bucket time-sorted. An occurrence whose series is
    /// itself dated on the day dedupes away (Today's rule). The lens applies
    /// to occurrence SERIES rows too — a filtered surface filters whole.
    private func itemsByDay() -> [Int64: [CalendarDayItem]] {
        let lens = workspaces.activeQuery
        var out: [Int64: [CalendarDayItem]] = [:]
        var datedIds: [Int64: Set<UInt64>] = [:]
        for id in box.snap?.dated ?? [] {
            guard let row = box.entity(id), row.trashed != true,
                let due = row.due, lens.matches(row)
            else { continue }
            let day = Civil.day(of: due)
            out[day, default: []].append(
                CalendarDayItem(
                    key: "e\(id)", row: row, stamp: due, occurrence: false))
            datedIds[day, default: []].insert(id)
        }
        for occ in box.snap?.occurrences ?? [] {
            guard let series = occ.series, let civil = occ.civil,
                let row = box.entity(series), row.trashed != true,
                lens.matches(row)
            else { continue }
            let day = Civil.day(of: civil)
            guard datedIds[day]?.contains(series) != true else { continue }
            out[day, default: []].append(
                CalendarDayItem(
                    key: "o\(series)-\(civil)", row: row, stamp: civil,
                    occurrence: true))
        }
        for (day, items) in out {
            out[day] = items.sorted {
                $0.stamp != $1.stamp ? $0.stamp < $1.stamp : $0.row.id < $1.row.id
            }
        }
        return out
    }

    // MARK: predicates + acts (Today's, file-private there — local copies)

    private func title(_ row: EntityRow) -> String {
        let t = row.title ?? ""
        return t.isEmpty ? "Untitled" : t
    }

    /// The reference shell's task test: the kind, or any status at all.
    private func isTask(_ row: EntityRow) -> Bool {
        row.kinds?.contains("task") == true || row.status != nil
    }

    private func isDone(_ row: EntityRow, _ doneNames: Set<String>) -> Bool {
        row.status.map { doneNames.contains($0) } ?? false
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

    /// Window the snapshot over the VISIBLE six-week span (the shown month
    /// plus its spill days — their dots must be as honest as the month's).
    /// The window steers recurrence expansion; `dated` is full regardless.
    private func loadWindow() {
        let start = CalGrid.gridStart(monthFirst)
        let end = Civil.addDays(start, 41)
        box.refreshWindow(
            from: Civil.stamp(day: start, hhmm: 0),
            to: Civil.stamp(day: end, hhmm: 2359))
    }
}

// MARK: - the quick-add ghost row

/// Today's inline quick-add under the selected day, here under the panel:
/// a name typed becomes a task DUE the selected day, date-only, no picker.
/// (TodayQuickAddRow is file-private to Today.swift; this is its mirror —
/// same acts, same stamp promise, kept in lockstep by eye.)
private struct CalendarQuickAddRow: View {
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var workspaces: WorkspaceModel
    let day: Int64

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            // The time column stays blank — a quick-add is date-only.
            Color.clear.frame(width: 44, height: 1)
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
            // Every creation door stamps (M4) — the row's hint says so
            // before the write.
            workspaces.stamp(id, in: box)
            text = ""
            focused = true
        }
    }
}

// MARK: - month math (packed civil days; Civil's private helpers re-derived)

/// Components-in, components-out within one Gregorian calendar — a stamp
/// never round-trips through a timezone. Noon anchor dodges the
/// DST-skipped-midnight edge (Civil's own rule).
private enum CalGrid {
    private static let gregorian = Calendar(identifier: .gregorian)

    /// Thread-safe since iOS 7; display format, current locale.
    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = gregorian
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    /// Mon-first weekday letters (the symbols array is Sun-first).
    static let weekdayLetters: [String] = {
        let s = gregorian.veryShortWeekdaySymbols
        return Array(s[1...]) + [s[0]]
    }()

    static func firstOfMonth(_ day: Int64) -> Int64 {
        (day / 100) * 100 + 1
    }

    static func addMonths(_ monthFirst: Int64, _ n: Int) -> Int64 {
        guard let date = date(ofDay: monthFirst),
            let moved = gregorian.date(byAdding: .month, value: n, to: date)
        else { return monthFirst }
        let c = gregorian.dateComponents([.year, .month], from: moved)
        return Int64(c.year ?? 0) * 10_000 + Int64(c.month ?? 0) * 100 + 1
    }

    /// The Monday on or before the month's first — the grid's first cell.
    static func gridStart(_ monthFirst: Int64) -> Int64 {
        guard let date = date(ofDay: monthFirst) else { return monthFirst }
        let weekday = gregorian.component(.weekday, from: date)  // 1=Sun … 7=Sat
        return Civil.addDays(monthFirst, -((weekday + 5) % 7))
    }

    /// "July 2026"
    static func title(_ monthFirst: Int64) -> String {
        guard let date = date(ofDay: monthFirst) else { return "\(monthFirst)" }
        return titleFormatter.string(from: date)
    }

    private static func date(ofDay day: Int64) -> Date? {
        var parts = DateComponents()
        parts.year = Int(day / 10_000)
        parts.month = Int((day / 100) % 100)
        parts.day = Int(day % 100)
        parts.hour = 12
        return gregorian.date(from: parts)
    }
}
