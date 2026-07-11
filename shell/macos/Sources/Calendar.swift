// lotus — the Calendar surface (P10), laid out EXACTLY as Liv's calendar
// (CalendarExtension.tsx): a left rail carrying the mini-month navigator and
// the "My calendars" kind checklist, a top bar (title · Month/Week/Day/Agenda ·
// ‹ Today › · + Event), the mode's body, and the day panel as a fixed right
// column. The layout is Liv's, 1:1; the rendering is native and the palette is
// lotus's — the accent's calendar jobs are today, the active mode, and + Event.

import AppKit
import SwiftUI

enum CalendarMode: String, CaseIterable {
    case month = "Month"
    case week = "Week"
    case day = "Day"
}

// MARK: - shared civil-date helpers (file-scoped)

private func civilDate(_ key: Int64) -> Date {
    var parts = DateComponents()
    parts.year = Int(key / 10000)
    parts.month = Int((key / 100) % 100)
    parts.day = Int(key % 100)
    return Civil.gregorian.date(from: parts) ?? Date()
}

private func timeHHmm(_ due: Int64) -> String {
    let hhmm = Int(due % 10000)
    return String(format: "%02d:%02d", hhmm / 100, hhmm % 100)
}

private func makeFormatter(_ format: String) -> DateFormatter {
    let f = DateFormatter()
    f.calendar = Civil.gregorian
    f.dateFormat = format
    return f
}

private enum Fmt {
    static let dow = makeFormatter("EEE")
    static let dayMonth = makeFormatter("d MMM")
    static let dayMonthYear = makeFormatter("d MMM yyyy")
    static let full = makeFormatter("EEEE d MMM yyyy")
    static let weekdayDay = makeFormatter("EEEE d")
    static let dayMonthYearLong = makeFormatter("d MMMM yyyy")
    static let monthYear = makeFormatter("MMMM yyyy")
}

// Explicit hairlines for the grids. SwiftUI's Divider picks its own
// orientation from the space it is offered — in a cell TALLER than wide it
// goes vertical, which turned the month cells' "top border" into a mid-cell
// vertical line (the doubled-columns bug). Fixed frames leave nothing to it.
private func hairlineV() -> some View {
    Rectangle().fill(Theme.border).frame(width: 0.5)
}

private func hairlineH() -> some View {
    Rectangle().fill(Theme.border).frame(height: 0.5)
}

// MARK: - the surface

struct CalendarView: View {
    @ObservedObject var model: BoxModel
    @Binding var selection: UInt64?
    var open: (UInt64) -> Void = { _ in }

    // Transient view state, never a cell (interface.md 0.5). selectedDay is
    // always a real day (today at first), as in Liv — the day panel always
    // has a day to show.
    @State private var viewYear = Civil.gregorian.component(.year, from: Date())
    @State private var viewMonth = Civil.gregorian.component(.month, from: Date())
    @State private var viewMode: CalendarMode = .month
    @State private var selectedDay: Int64 = Civil.todayYMD
    // Manual double-tap detection (a sibling count:2 gesture would stall
    // every single tap by the double-click interval — the tab-strip lesson).
    @State private var lastItemTap: (id: UInt64, at: Date)?

    // Which kinds land on the grid — the default calendar filter (bp9 has
    // no "My calendars" rail; these persist the sensible defaults below).
    @AppStorage("app.calendar.show.event") private var showEvents = true
    @AppStorage("app.calendar.show.task") private var showTasks = true
    @AppStorage("app.calendar.show.note") private var showNotes = true
    @AppStorage("app.calendar.show.file") private var showFiles = false
    @AppStorage("app.calendar.show.contact") private var showContacts = false
    @AppStorage("app.calendar.show.list") private var showLists = false
    // The right column is collapsible (the panel toggle in the top bar).
    @AppStorage("app.calendar.panel.open") private var panelOpen = true

    var body: some View {
        GeometryReader { geo in
            // A tight window sheds panels instead of crushing the grid: the
            // rail goes first, then the right column — the grid is the point.
            let byDay = buildByDay()
            let showRight = panelOpen && geo.size.width >= 760
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    topBar
                    Divider()
                    switch viewMode {
                    case .month:
                        monthBody(byDay)
                    case .week:
                        WeekTimeGrid(
                            days: weekDays(selectedDay), byDay: byDay, today: Civil.todayYMD,
                            selected: selectedDay,
                            itemTap: itemTapped,
                            selectDay: { key in
                                selectedDay = key
                                loadWindow()
                            },
                            createAt: { key, hour in quickCreate(dayKey: key, hour: hour) })
                    case .day:
                        WeekTimeGrid(
                            days: [selectedDay], byDay: byDay, today: Civil.todayYMD,
                            selected: selectedDay,
                            itemTap: itemTapped,
                            selectDay: { key in
                                selectedDay = key
                                loadWindow()
                            },
                            createAt: { key, hour in quickCreate(dayKey: key, hour: hour) })
                    }
                }
                // Liv's fixed right column — the day panel, or (while an
                // entity is selected) the inspector embedded in its place.
                // Same width is load-bearing: selection must never reflow the
                // grid, or the second click of a double-tap lands on a moved
                // target (the review's high finding).
                if showRight {
                    Divider()
                    rightColumn(byDay)
                }
            }
        }
        .onAppear { loadWindow() }
        .onDisappear { model.resetWindow() }
    }

    // The right column: the day panel, or the embedded inspector with a back
    // button (the deselect path this surface otherwise lacks) and an Open
    // button (the open path for day-panel rows, whose own double-tap can't
    // survive the panel-to-inspector content swap).
    private func rightColumn(_ byDay: [Int64: [EntityRow]]) -> some View {
        Group {
            if let sel = selection {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Button { selection = nil } label: {
                            Label(
                                Fmt.weekdayDay.string(from: civilDate(selectedDay)),
                                systemImage: "chevron.left"
                            )
                            .font(.system(size: 12))
                            .foregroundColor(Theme.accent)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Back to the day")
                        Spacer()
                        Button { open(sel) } label: {
                            Image(systemName: "arrow.up.forward.square")
                                .font(.system(size: 12.5))
                                .foregroundColor(Theme.mutedFg)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Open")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    Divider()
                    InspectorPane(model: model, selection: $selection, topPadding: 0)
                }
            } else {
                dayPanel(selectedDay, items: byDay[selectedDay] ?? [])
            }
        }
        .frame(width: 320)
        .background(Theme.background)
    }

    // MARK: data

    // Liv's calendar-source filter, by kind; anything untyped-but-dated
    // counts as a note (Liv's default bucket).
    private func kindShown(_ row: EntityRow) -> Bool {
        if row.kinds.contains("event") { return showEvents }
        // A task is task-typed OR merely status-bearing — the same test
        // EntityLine's checkbox and taskStatusToggle apply.
        if row.kinds.contains("task") || row.status != nil { return showTasks }
        // A file is an entity CARRYING a file cell — files have no type (P7),
        // so a kinds check would never match one.
        if row.cells.contains(where: { $0.kind == "file" }) { return showFiles }
        if row.kinds.contains("person") || row.kinds.contains("contact") { return showContacts }
        if row.kinds.contains("list") { return showLists }
        return showNotes
    }

    // A day's contents: the dated one-offs unioned with the recurrence
    // engine's virtual occurrences (the series entity drawn on each day its
    // rule names), filtered by the checklist, in day order — all-day items
    // first (Liv's rail order), then by time.
    private func buildByDay() -> [Int64: [EntityRow]] {
        var byDay: [Int64: [EntityRow]] = [:]
        for row in model.rows(model.snap?.dated ?? []) where kindShown(row) {
            byDay[(row.due ?? 0) / 10_000, default: []].append(row)
        }
        for occurrence in model.snap?.occurrences ?? [] {
            if let series = model.entity(occurrence.series), kindShown(series) {
                byDay[occurrence.civil / 10_000, default: []].append(series)
            }
        }
        for key in byDay.keys {
            byDay[key]?.sort { a, b in
                let at = a.dueDateOnly ? -1 : Int((a.due ?? 0) % 10_000)
                let bt = b.dueDateOnly ? -1 : Int((b.due ?? 0) % 10_000)
                return at < bt
            }
        }
        return byDay
    }

    // Select on the first tap (cheap, idempotent), open on a second inside
    // the system interval — no sibling count:2 gesture, so nothing stalls.
    private func itemTapped(_ id: UInt64) {
        selection = id
        let now = Date()
        if let last = lastItemTap, last.id == id,
            now.timeIntervalSince(last.at) < NSEvent.doubleClickInterval
        {
            lastItemTap = nil
            open(id)
        } else {
            lastItemTap = (id, now)
        }
    }

    // MARK: the top bar — title · mode switcher · ‹ Today › · + Event (Liv's)

    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "calendar")
                    .font(.system(size: 15))
                    .foregroundColor(Theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Calendar")
                        .font(.system(size: 14.5, weight: .semibold))
                        .fixedSize()
                    Text(subtitleText())
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            HStack(spacing: 2) {
                ForEach(CalendarMode.allCases, id: \.self) { mode in
                    Button {
                        guard viewMode != mode else { return }
                        viewMode = mode
                        loadWindow()
                    } label: {
                        Text(mode.rawValue)
                            .font(.system(size: 12, weight: viewMode == mode ? .medium : .regular))
                            .foregroundColor(viewMode == mode ? .white : Theme.mutedFg)
                            .fixedSize()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(viewMode == mode ? Theme.accent : Color.clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 0) {
                navChevron("chevron.left") { step(-1) }
                Button(action: goToday) {
                    Text("Today")
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                navChevron("chevron.right") { step(1) }
            }
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border, lineWidth: 0.5))
            Button { quickCreate(dayKey: selectedDay) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 10.5, weight: .semibold))
                    Text("Event").font(.system(size: 12, weight: .medium)).fixedSize()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accent))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New event on the selected day")
            Button { panelOpen.toggle() } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 13))
                    .foregroundColor(panelOpen ? Theme.accent : Theme.mutedFg)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(panelOpen ? "Hide the day panel" : "Show the day panel")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func navChevron(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.mutedFg)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func subtitleText() -> String {
        switch viewMode {
        case .month:
            return monthYearText()
        case .week:
            let d = weekDays(selectedDay)
            guard let f = d.first, let l = d.last else { return monthYearText() }
            let left =
                f / 100 == l / 100
                ? "\(Int(f % 100))" : Fmt.dayMonth.string(from: civilDate(f))
            return "\(left)–\(Fmt.dayMonthYear.string(from: civilDate(l)))"
        case .day:
            return Fmt.full.string(from: civilDate(selectedDay))
        }
    }

    private func monthYearText() -> String {
        var parts = DateComponents()
        parts.year = viewYear
        parts.month = viewMonth
        parts.day = 1
        return Fmt.monthYear.string(from: Civil.gregorian.date(from: parts) ?? Date())
    }

    // MARK: the month grid — Monday-first, adjacent months greyed (Liv's)

    private let dowsMon = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

    private func monthBody(_ byDay: [Int64: [EntityRow]]) -> some View {
        let cells = monthCells()
        let weekCount = max(cells.count / 7, 1)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(dowsMon, id: \.self) { dow in
                    Text(dow)
                        .font(.system(size: 10.5, weight: .semibold))
                        .kerning(0.4)
                        .foregroundColor(Color.secondary.opacity(0.7))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 7)
            Divider()
            // Week rows dividing the WHOLE remaining height — the month
            // always fits and fills; no scroll, no dead space (Liv/Apple).
            GeometryReader { geo in
                let rowH = max(geo.size.height / CGFloat(weekCount), 40)
                VStack(spacing: 0) {
                    ForEach(0..<weekCount, id: \.self) { w in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { d in
                                let cell = cells[w * 7 + d]
                                DayCell(
                                    key: cell.key, inMonth: cell.inMonth,
                                    isToday: cell.key == Civil.todayYMD,
                                    isSelected: selectedDay == cell.key,
                                    events: byDay[cell.key] ?? [],
                                    rowHeight: rowH,
                                    addEvent: { quickCreate(dayKey: cell.key) },
                                    selectDay: { selectedDay = cell.key },
                                    itemTap: itemTapped)
                            }
                        }
                        .frame(height: rowH)
                    }
                }
            }
        }
    }

    /// The month's grid cells, Monday-first, padded with the adjacent
    /// months' days (drawn greyed, as Liv draws them) to whole weeks.
    private func monthCells() -> [(key: Int64, inMonth: Bool)] {
        let cal = Civil.gregorian
        var parts = DateComponents()
        parts.year = viewYear
        parts.month = viewMonth
        parts.day = 1
        guard let first = cal.date(from: parts) else { return [] }
        let daysInMonth = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let lead = (cal.component(.weekday, from: first) + 5) % 7  // Monday-first
        guard let start = cal.date(byAdding: .day, value: -lead, to: first) else { return [] }
        let total = ((lead + daysInMonth + 6) / 7) * 7
        return (0..<total).compactMap { off in
            guard let d = cal.date(byAdding: .day, value: off, to: start) else { return nil }
            let c = cal.dateComponents([.year, .month, .day], from: d)
            let key = Int64((c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0))
            return (key, c.month == viewMonth && c.year == viewYear)
        }
    }

    // MARK: the day panel — Liv's fixed right column

    private func dayPanel(_ key: Int64, items: [EntityRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Fmt.weekdayDay.string(from: civilDate(key)))
                    .font(.system(size: 16, weight: .semibold))
                if key == Civil.todayYMD {
                    Text("TODAY")
                        .font(.system(size: 9.5, weight: .semibold))
                        .kerning(0.6)
                        .foregroundColor(Theme.accent)
                }
                Spacer()
                Button { quickCreate(dayKey: key) } label: {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.mutedFg)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New event this day")
            }
            Text(Fmt.dayMonthYearLong.string(from: civilDate(key)))
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
                .padding(.top, 1)
            if items.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .font(.system(size: 30))
                        .foregroundColor(Color.secondary.opacity(0.35))
                    Text("Nothing on this day")
                        .font(.system(size: 12.5))
                        .foregroundColor(Theme.mutedFg)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(items) { row in
                            // An occurrence row carries its SERIES' anchor due —
                            // another day's date. Show the due text only when it
                            // genuinely is this day's.
                            EntityLine(
                                row: row,
                                showWhen: (row.due ?? 0) / 10_000 == key,
                                selected: selection == row.id,
                                toggle: taskStatusToggle(model, row)
                            ) {
                                itemTapped(row.id)
                            }
                        }
                    }
                    .padding(.top, 12)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
    }

    // MARK: navigation + the occurrence window

    private func step(_ delta: Int) {
        switch viewMode {
        case .month: stepMonthOnly(delta)
        case .week: moveAnchor(days: delta * 7)
        case .day: moveAnchor(days: delta)
        }
    }

    private func stepMonthOnly(_ delta: Int) {
        var m = viewMonth + delta
        var y = viewYear
        while m > 12 { m -= 12; y += 1 }
        while m < 1 { m += 12; y -= 1 }
        viewMonth = m
        viewYear = y
        loadWindow()
    }

    private func moveAnchor(days: Int) {
        let moved =
            Civil.gregorian.date(byAdding: .day, value: days, to: civilDate(selectedDay)) ?? Date()
        let c = Civil.gregorian.dateComponents([.year, .month, .day], from: moved)
        selectedDay = Int64((c.year ?? viewYear) * 10000 + (c.month ?? 1) * 100 + (c.day ?? 1))
        viewYear = c.year ?? viewYear
        viewMonth = c.month ?? viewMonth
        loadWindow()
    }

    private func goToday() {
        let cal = Civil.gregorian
        viewYear = cal.component(.year, from: Date())
        viewMonth = cal.component(.month, from: Date())
        selectedDay = Civil.todayYMD
        loadWindow()
    }

    /// The 7 civil-YMD keys (Mon..Sun) of the week containing `anchorKey`.
    private func weekDays(_ anchorKey: Int64) -> [Int64] {
        let cal = Civil.gregorian
        let anchor = civilDate(anchorKey)
        let weekday = cal.component(.weekday, from: anchor)  // 1=Sun .. 7=Sat
        let fromMonday = (weekday + 5) % 7  // Mon -> 0 .. Sun -> 6
        guard let monday = cal.date(byAdding: .day, value: -fromMonday, to: anchor) else {
            return []
        }
        return (0..<7).compactMap { off in
            guard let d = cal.date(byAdding: .day, value: off, to: monday) else { return nil }
            let c = cal.dateComponents([.year, .month, .day], from: d)
            return Int64((c.year ?? 2026) * 10000 + (c.month ?? 1) * 100 + (c.day ?? 1))
        }
    }

    // The occurrence window must cover every day the surface RENDERS, not
    // just the mode's core span: the month grid and the mini-month both draw
    // whole Monday-first weeks (adjacent months' greyed days included), and
    // selectedDay can sit outside the viewed month after navigation. A window
    // narrower than the rendered days silently drops recurring occurrences on
    // the edges while the unwindowed one-offs still show (the review's other
    // high finding). Civil YMD keys compare numerically, so min/max is a
    // contiguous union; the span stays ~6 weeks, far under the engine's cap.
    private func loadWindow() {
        let cells = monthCells()
        var lo = cells.first?.key ?? selectedDay
        var hi = cells.last?.key ?? selectedDay
        if viewMode == .week {
            let d = weekDays(selectedDay)
            if let f = d.first { lo = min(lo, f) }
            if let l = d.last { hi = max(hi, l) }
        }
        lo = min(lo, selectedDay)
        hi = max(hi, selectedDay)
        model.snapshotWindow(from: lo * 10000, to: hi * 10000)
    }

    // Create an event on a day (09:00, Liv's default hour). Liv births it
    // named "New event" and drops into renaming — a cancelled rename keeps a
    // name, never a bare #id on the grid. The prompt is asked directly with
    // the "New event" initial: the generic rename path reads the model, and
    // the snapshot carrying the newborn hasn't landed yet when it opens.
    private func quickCreate(dayKey: Int64, hour: Int = 9) {
        model.createEvent(dueCivil: dayKey * 10000 + Int64(hour) * 100, allDay: false) { id in
            guard let id = id else { return }
            model.set(id, property: "name", value: "New event") { _ in
                selection = id
                Dialogs.shared.prompt(
                    "Name the event", initial: "New event", confirmLabel: "Name"
                ) { name in
                    let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, trimmed != "New event" else { return }
                    model.set(id, property: "name", value: trimmed)
                }
            }
        }
    }
}

// MARK: - a month day cell (Liv's: number top-left, time-prefixed pills)

struct DayCell: View {
    let key: Int64
    var inMonth = true
    let isToday: Bool
    var isSelected = false
    let events: [EntityRow]
    let rowHeight: CGFloat
    var addEvent: () -> Void = {}
    var selectDay: () -> Void = {}
    var itemTap: (UInt64) -> Void = { _ in }

    @State private var hovering = false

    var body: some View {
        let maxPills = max(1, Int((rowHeight - 30) / 17))
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                if isToday {
                    Text("\(Int(key % 100))")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Theme.accent))
                } else {
                    Text("\(Int(key % 100))")
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundColor(inMonth ? .primary : Color.secondary.opacity(0.45))
                        .padding(.leading, 2)
                }
                Spacer(minLength: 0)
                // The cell is NOT a Button (day-select is a background tap
                // gesture), so the hover "+" captures its own tap.
                if hovering {
                    Button(action: addEvent) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Theme.mutedFg)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("New event")
                }
            }
            ForEach(events.prefix(maxPills)) { row in
                pill(row)
            }
            if events.count > maxPills {
                Text("+\(events.count - maxPills) more")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.leading, 3)
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(isSelected ? Theme.accent.opacity(0.06) : Color.clear)
        .overlay(Rectangle().stroke(Theme.accent.opacity(isSelected ? 0.55 : 0), lineWidth: 1))
        .overlay(alignment: .top) { hairlineH() }
        .overlay(alignment: .leading) { hairlineV() }
        .contentShape(Rectangle())
        .onTapGesture { selectDay() }
        .onHover { hovering = $0 }
    }

    // A filled pill, time-first like Liv's ("09:00 New event"); all-day items
    // are just the title. Neutral fill — the accent stays the today circle's.
    private func pill(_ row: EntityRow) -> some View {
        HStack(spacing: 4) {
            if let due = row.due, !row.dueDateOnly {
                Text(timeHHmm(due))
                    .font(.system(size: 9.5).monospacedDigit())
                    .foregroundColor(.secondary)
            }
            Text(row.title.isEmpty ? "Untitled" : row.title)
                .font(.system(size: 10.5))
                .lineLimit(1)
                .foregroundColor(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 1.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.14)))
        .overlay(
            Rectangle().fill(Color.secondary.opacity(0.5)).frame(width: 2), alignment: .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .contentShape(Rectangle())
        .onTapGesture { itemTap(row.id) }
    }
}

// MARK: - the hour grid (Liv's WeekGrid/DayGrid: one renderer, 7 or 1 columns)

struct WeekTimeGrid: View {
    let days: [Int64]
    let byDay: [Int64: [EntityRow]]
    let today: Int64
    var selected: Int64? = nil
    var itemTap: (UInt64) -> Void = { _ in }
    var selectDay: (Int64) -> Void = { _ in }
    var createAt: (Int64, Int) -> Void = { _, _ in }

    private let hourHeight: CGFloat = 44
    private let gutter: CGFloat = 50

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            if hasAllDay {
                Divider()
                allDayRail
            }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        gutterColumn
                        ForEach(days, id: \.self) { key in
                            dayColumn(key)
                        }
                    }
                }
                .onAppear {
                    // Liv opens the grid at the working morning, not 00:00.
                    DispatchQueue.main.async { proxy.scrollTo("cal-hour-7", anchor: .top) }
                }
            }
        }
    }

    private var hasAllDay: Bool {
        days.contains { (byDay[$0] ?? []).contains { $0.dueDateOnly } }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutter, height: 1)
            ForEach(days, id: \.self) { key in
                VStack(spacing: 3) {
                    Text(Fmt.dow.string(from: civilDate(key)).uppercased())
                        .font(.system(size: 10.5, weight: .medium))
                        .kerning(0.4)
                        .foregroundColor(Color.secondary.opacity(0.8))
                    if key == today {
                        Text("\(Int(key % 100))")
                            .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                            .foregroundColor(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Theme.accent))
                    } else {
                        Text("\(Int(key % 100))")
                            .font(.system(size: 12.5, weight: .medium).monospacedDigit())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    key == today
                        ? Color.secondary.opacity(0.08)
                        : (key == selected ? Color.secondary.opacity(0.06) : Color.clear))
                // Liv: click a day header to select that day (drives the
                // day panel and the day-view anchor).
                .contentShape(Rectangle())
                .onTapGesture { selectDay(key) }
            }
        }
    }

    // The all-day rail — items whose due is date_only (the structural bit,
    // no time-string parsing). Only rendered when the week has one (Liv).
    private var allDayRail: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("all-day")
                .font(.system(size: 9.5))
                .foregroundColor(Theme.mutedFg)
                .frame(width: gutter, alignment: .trailing)
                .padding(.top, 6)
            ForEach(days, id: \.self) { key in
                VStack(spacing: 2) {
                    ForEach((byDay[key] ?? []).filter { $0.dueDateOnly }) { row in
                        Text(row.title.isEmpty ? "Untitled" : row.title)
                            .font(.system(size: 10.5))
                            .lineLimit(1)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.secondary.opacity(0.15)))
                            .contentShape(Rectangle())
                            .onTapGesture { itemTap(row.id) }
                    }
                }
                .padding(3)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .leading) { hairlineV() }
            }
        }
        .frame(minHeight: 24)
    }

    private var gutterColumn: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                // The label's breathing room lives INSIDE the gutter width, so
                // the scrolling columns align with the pinned header's exactly.
                Text(h == 0 ? "" : String(format: "%02d:00", h))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundColor(Theme.mutedFg)
                    .padding(.trailing, 4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .frame(height: hourHeight, alignment: .top)
                    .offset(y: -6)
                    .id("cal-hour-\(h)")
            }
        }
        .frame(width: gutter)
    }

    private func dayColumn(_ key: Int64) -> some View {
        let blocks = laidOut((byDay[key] ?? []).filter { !$0.dueDateOnly && $0.due != nil })
        return GeometryReader { geo in
            let colW = geo.size.width
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: hourHeight)
                            .overlay(alignment: .top) { hairlineH() }
                    }
                }
                // A transparent double-click layer per hour, under the blocks:
                // double-click an empty slot to create an event there. A lone
                // count:2 gesture (no sibling single-tap), so nothing stalls.
                VStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { h in
                        Color.clear
                            .frame(height: hourHeight)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { createAt(key, h) }
                    }
                }
                ForEach(blocks) { b in
                    let w = colW / CGFloat(b.lanes)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(b.row.title.isEmpty ? "Untitled" : b.row.title)
                            .font(.system(size: 10.5, weight: .medium))
                            .lineLimit(1)
                            .foregroundColor(.primary)
                        Text(rangeText(b.row.due ?? 0))
                            .font(.system(size: 9.5).monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .frame(width: max(w - 3, 0), height: hourHeight - 2, alignment: .topLeading)
                    .background(
                        RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.16)))
                    .overlay(
                        Rectangle().fill(Color.secondary.opacity(0.55)).frame(width: 2),
                        alignment: .leading
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .contentShape(Rectangle())
                    .onTapGesture { itemTap(b.row.id) }
                    .offset(x: CGFloat(b.lane) * w + 1, y: CGFloat(b.start) * hourHeight + 1)
                }
                if key == today {
                    // Liv's "now" indicator: a functional-red line + dot on
                    // today's column only.
                    Circle()
                        .fill(Color(red: 0.85, green: 0.31, blue: 0.23))
                        .frame(width: 6, height: 6)
                        .offset(x: -2, y: CGFloat(nowHours()) * hourHeight - 3)
                    Rectangle()
                        .fill(Color(red: 0.85, green: 0.31, blue: 0.23))
                        .frame(height: 1.5)
                        .offset(y: CGFloat(nowHours()) * hourHeight)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 24 * hourHeight)
        .overlay(alignment: .leading) { hairlineV() }
    }

    // ---- geometry ----

    private func startHours(_ row: EntityRow) -> Double {
        let hhmm = Int((row.due ?? 0) % 10000)
        return Double(hhmm / 100) + Double(hhmm % 100) / 60.0
    }

    private func nowHours() -> Double {
        let c = Civil.gregorian.dateComponents([.hour, .minute], from: Date())
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60.0
    }

    // "09:00–10:00" — events carry no end yet, so each gets a default hour.
    private func rangeText(_ due: Int64) -> String {
        let start = timeHHmm(due)
        let hhmm = Int(due % 10000)
        let endH = hhmm / 100 + 1
        guard endH <= 23 else { return start }
        return "\(start)–\(String(format: "%02d:%02d", endH, hhmm % 100))"
    }

    private struct Placed: Identifiable {
        let row: EntityRow
        let start: Double
        let lane: Int
        let lanes: Int
        var id: UInt64 { row.id }
    }

    // Interval-partition a day's timed items into lanes: overlapping events
    // (each spanning a default 1h) form a cluster and split its width;
    // non-overlapping ones keep the full width.
    private func laidOut(_ items: [EntityRow]) -> [Placed] {
        let dur = 1.0
        let sorted = items.sorted { startHours($0) < startHours($1) }
        var out: [Placed] = []
        var i = 0
        while i < sorted.count {
            var clusterEnd = startHours(sorted[i]) + dur
            var j = i + 1
            while j < sorted.count && startHours(sorted[j]) < clusterEnd {
                clusterEnd = max(clusterEnd, startHours(sorted[j]) + dur)
                j += 1
            }
            var laneEnds: [Double] = []
            var laneOf: [Int] = []
            for k in i..<j {
                let s = startHours(sorted[k])
                if let l = laneEnds.firstIndex(where: { $0 <= s }) {
                    laneEnds[l] = s + dur
                    laneOf.append(l)
                } else {
                    laneOf.append(laneEnds.count)
                    laneEnds.append(s + dur)
                }
            }
            let lanes = laneEnds.count
            for (offset, k) in (i..<j).enumerated() {
                out.append(
                    Placed(
                        row: sorted[k], start: startHours(sorted[k]), lane: laneOf[offset],
                        lanes: lanes))
            }
            i = j
        }
        return out
    }
}
