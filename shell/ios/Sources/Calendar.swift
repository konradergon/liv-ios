// liv iOS — Calendar (design/ios.md §6): a compact month grid (Mon-first,
// six fixed weeks, ≤3 neutral ink dots per day — never a color rainbow)
// over a FIXED day panel: all-day pills first, then rows chronologically.
// `dated` is the full set (bucketed by civil day client-side); only
// `occurrences` ride the snapshot window, so the grid re-windows over the
// VISIBLE six-week span on every month change. Occurrence rows project
// their SERIES entity — repeat glyph, read-only, tap opens the series.
// A row tap opens a Desk tab (desk.open dismisses this window by the
// chrome's own rule). Tapping an empty hour — or long-pressing a day for
// an all-day one — opens an inline DRAFT with a name field: the box
// learns nothing until you submit, and the workspace stamps what lands
// (every creation door stamps, M4).

import SwiftUI
import UIKit

// MARK: - day items

/// One calendar line: a dated entity, or an occurrence projecting its
/// series row. All-day is the core's own date-only flag; a stamp of 0000
/// is only consulted when the core did not say, so an event deliberately
/// set to midnight stays an event at midnight (review, 2026-08-06).
private struct CalendarDayItem: Identifiable {
    let key: String
    let row: EntityRow
    let stamp: Int64
    let occurrence: Bool
    var id: String { key }
    var allDay: Bool { row.dueDateOnly ?? (stamp % 10_000 == 0) }
}

// MARK: - the screen

/// A block held by the drag, mid-flight.
private struct LiftedBlock: Equatable {
    let id: UInt64
    /// Minutes-of-day where its start currently sits.
    let minutes: Int
}

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
    /// The block currently in the air, and where its start sits now. Live
    /// only — the write happens when the finger lifts.
    @State private var lifted: LiftedBlock?
    /// A new event being NAMED in the grid. Nothing is written until the
    /// name is submitted: tapping an hour used to create an untitled
    /// event and throw you into the note editor to name it (owner,
    /// 2026-08-06 — "setting names of calendar items should be done in
    /// calendar", and an event is not a document).
    @State private var draft: EventDraft?
    /// Which way the last month change went, so the grid slides the way
    /// the finger did. +1 forward, -1 back.
    @State private var monthStep = 1
    /// How far the month grid has been dragged sideways, live.
    @State private var monthDrag: CGFloat = 0
    /// One month's width, learned from the layout, so the chevrons can
    /// slide by exactly one page too.
    @State private var pageWidth: CGFloat = 0

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
            monthPager(today: today, byDay: byDay)
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
                .font(.system(size: LivType.strong, weight: .semibold))
                .foregroundStyle(LivTheme.text)
            // Why the grid is sparse — never a mystery (M4).
            if workspaces.lensOn { LensChip(label: workspaces.lensLabel) }
            if box.busyRetrying { ProgressView().scaleEffect(0.7) }
            Spacer()
            // A VERB, dressed as one. As plain accent text beside the
            // date it read as a label saying which day was selected
            // (owner, 2026-08-10) — it is a button that takes you to
            // today, so it wears a button's face. The 26pt pill sits in
            // a 40pt tap target.
            Button {
                // One month away is a step and slides; a leap of many
                // has no direction worth animating, so it lands.
                let home = CalGrid.firstOfMonth(today)
                if home == CalGrid.addMonths(monthFirst, -1) {
                    page(-1)
                } else if home == CalGrid.addMonths(monthFirst, 1) {
                    page(1)
                } else {
                    monthDrag = 0
                    monthFirst = home
                    selectedDay = today
                }
            } label: {
                Text("Today")
                    .font(.system(size: LivType.body, weight: .semibold))
                    .foregroundStyle(LivTheme.accent)
                    .padding(.horizontal, 11)
                    .frame(height: 26)
                    .background(Capsule().fill(LivTheme.accent.opacity(0.16)))
                    .overlay(
                        Capsule().strokeBorder(
                            LivTheme.accent.opacity(0.5), lineWidth: 0.5)
                    )
                    .frame(height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Go to today")
            chevron("chevron.left", label: "Previous month") { page(-1) }
            chevron("chevron.right", label: "Next month") { page(1) }
        }
    }

    private func chevron(
        _ icon: String, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: LivType.strong, weight: .semibold))
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
    private func step(_ n: Int, animated: Bool = true) {
        let moved = CalGrid.addMonths(monthFirst, n)
        let today = Civil.todayDay()
        monthStep = n
        let land = {
            monthFirst = moved
            selectedDay = CalGrid.firstOfMonth(today) == moved ? today : moved
        }
        if animated { withAnimation(LivMotion.nav, land) } else { land() }
    }

    // MARK: the pager — three months side by side, the middle one shown
    //
    // The grid FOLLOWS the finger (owner, 2026-08-10: "not the
    // drag+swipe, which is nicer"). A fire-on-release swipe told you
    // nothing until it was over; this shows the next month arriving
    // while you are still deciding, and lets you change your mind by
    // sliding back. The neighbours are real grids, so what slides in is
    // what you get. ‹ › and Today drive the SAME path — one page(), one
    // place the settle rule lives.

    private func monthPager(
        today: Int64, byDay: [Int64: [CalendarDayItem]]
    ) -> some View {
        GeometryReader { geo in
            let span = geo.size.width
            HStack(spacing: 0) {
                ForEach(-1...1, id: \.self) { n in
                    monthGrid(
                        CalGrid.addMonths(monthFirst, n),
                        today: today, byDay: byDay
                    )
                    .padding(.horizontal, 16)
                    .frame(width: span)
                }
            }
            .offset(x: -span + monthDrag)
            .contentShape(Rectangle())
            .gesture(monthDragGesture(span: span))
            .onAppear { pageWidth = span }
            .onChange(of: span) { _, w in pageWidth = w }
        }
        .frame(height: CalGrid.gridHeight)
        .clipped()
    }

    /// Follow the finger, then settle. A flick commits from anywhere; a
    /// slow drag commits past a third of the way — the panel drag's own
    /// rule, so the two gestures in this app agree about what a
    /// deliberate pull means.
    private func monthDragGesture(span: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { g in
                // Vertical wins: the day panel below scrolls, and a
                // finger drifting down must not drag the month sideways.
                guard abs(g.translation.width) > abs(g.translation.height)
                else { return }
                monthDrag = g.translation.width
            }
            .onEnded { g in
                let dx = monthDrag
                guard dx != 0 else { return }
                let velocity = g.velocity.width
                let flicked = abs(velocity) > CalGrid.flickToPage
                let towards = flicked ? velocity : dx
                guard flicked || abs(dx) > span / 3 else {
                    withAnimation(LivMotion.nav) { monthDrag = 0 }
                    return
                }
                page(towards < 0 ? 1 : -1, over: span)
            }
    }

    /// Slide one month along, then swap the middle grid underneath
    /// without a second animation. Both the chevrons and the drag land
    /// here.
    private func page(_ n: Int, over width: CGFloat? = nil) {
        let span = width ?? pageWidth
        guard span > 0 else {
            step(n)
            return
        }
        monthStep = n
        withAnimation(LivMotion.nav) { monthDrag = CGFloat(-n) * span }
        // When the slide lands, the neighbour IS the month — move the
        // data under it and zero the offset in one un-animated beat, so
        // nothing is seen to jump back.
        DispatchQueue.main.asyncAfter(deadline: .now() + LivMotion.navSeconds) {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                step(n, animated: false)
                monthDrag = 0
            }
        }
    }

    // MARK: the grid — 6 fixed weeks, Mon-first, ~40pt cells

    private var weekdayRow: some View {
        HStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { i in
                Text(CalGrid.weekdayLetters[i])
                    .font(.system(size: LivType.label, weight: .semibold))
                    .foregroundStyle(LivTheme.text2)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Draws the six weeks of ONE month — whichever it is handed, so the
    /// pager can render the neighbours with the same code.
    private func monthGrid(
        _ month: Int64, today: Int64, byDay: [Int64: [CalendarDayItem]]
    ) -> some View {
        let start = CalGrid.gridStart(month)
        return VStack(spacing: CalGrid.rowGap) {
            ForEach(0..<6, id: \.self) { week in
                HStack(spacing: CalGrid.rowGap) {
                    ForEach(0..<7, id: \.self) { col in
                        let day = Civil.addDays(start, week * 7 + col)
                        dayCell(
                            day, month: month, today: today,
                            items: byDay[day] ?? [])
                    }
                }
            }
        }
    }

    /// Today ringed accent, the selected day filled; both = filled wins
    /// (the 7-day strip's rule). Long-press = the event door.
    ///
    /// The dots take the KIND colour of what is in the day (owner,
    /// 2026-08-13: "apply the kind colors everywhere"). They were neutral
    /// ink on the rule that "the calendar says WHEN, never what kind" —
    /// which the blueprints reverse: three grey dots said only "busy",
    /// and the same three in teal, purple and orange say what the day
    /// holds without opening it. On the SELECTED day they go back to one
    /// ink: the cell is filled accent, and colour on colour is unreadable.
    private func dayCell(
        _ day: Int64, month: Int64, today: Int64, items: [CalendarDayItem]
    ) -> some View {
        let inMonth = CalGrid.firstOfMonth(day) == month
        let isToday = day == today
        let isSelected = day == selectedDay
        let count = items.count
        return VStack(spacing: 3) {
            Text("\(Civil.dayNumber(day))")
                .font(
                    .system(size: LivType.body, weight: isToday ? .semibold : .regular)
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
                                ? (isSelected
                                    ? LivTheme.onAccent
                                    : LivKind.color(of: items[i].row))
                                : Color.clear
                        )
                        .frame(width: 4, height: 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: CalGrid.cellHeight)
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
    /// Tap an empty hour: an event AT that hour (phase 4). One tap, no
    /// dialog — it lands as a desk tab for naming, the same door the
    /// month grid's long-press opens.
    /// Long-press a month cell: an ALL-DAY event on that day — named in
    /// the all-day band, not in a note editor.
    private func createEvent(on day: Int64) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        selectedDay = day
        draft = EventDraft(day: day, minutes: 0, allDay: true)
    }

    /// The ONE write path for a drafted event: create, name, stamp. Called
    /// only with a non-empty name.
    private func commitDraft(_ d: EventDraft, name: String) {
        let stamp = Civil.stamp(
            day: d.day, hhmm: d.allDay ? 0 : Int64(CalClock.hhmm(d.minutes)))
        box.createEvent(dueCivil: stamp, dateOnly: d.allDay) { id in
            guard id != 0 else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            box.set(id, "name", name)
            workspaces.stamp(id, in: box)
            draft = nil
            loadWindow()
        }
    }

    // MARK: the day panel — pills, rows, quick-add (fixed, not a modal)

    /// The day, Apple Calendar's shape (phase 4): an all-day band, then an
    /// hour grid where a timed item is a positioned block. Tap an empty
    /// hour to create there; drag a block to move its time.
    private func dayPanel(
        items: [CalendarDayItem], today: Int64, doneNames: Set<String>
    ) -> some View {
        // All-day rides the band — including date-only TASKS, which keep
        // their ring there (a timeless task must stay checkable without
        // hunting the grid for a block it has no time for).
        let band = items.filter(\.allDay)
        let timed = items.filter { !$0.allDay }
        return VStack(spacing: 0) {
            SectionLabel(
                selectedDay == today
                    ? "Today · " + Civil.dayLabel(selectedDay)
                    : Civil.dayLabel(selectedDay),
                trailing: items.isEmpty ? nil : "\(items.count)"
            )
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
            if !band.isEmpty || draft?.allDay == true {
                allDayBand(band, doneNames: doneNames)
                Rectangle().fill(LivTheme.border).frame(height: 0.5)
            }
            hourGrid(timed: timed, today: today, doneNames: doneNames)
            CalendarQuickAddRow(day: selectedDay)
                .padding(.horizontal, 16)
        }
    }

    private func allDayBand(
        _ items: [CalendarDayItem], doneNames: Set<String>
    ) -> some View {
        HStack(spacing: 6) {
            Text("ALL DAY")
                .font(.system(size: LivType.label, weight: .semibold))
                .kerning(0.3)
                .foregroundStyle(LivTheme.text2)
                .frame(width: 56, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(items) { item in
                        if livCanTick(item.row) {
                            allDayTask(item, doneNames: doneNames)
                        } else {
                            allDayPill(item)
                        }
                    }
                    if let d = draft, d.allDay, d.day == selectedDay {
                        EventDraftField(
                            placeholder: "All day",
                            onCommit: { name in commitDraft(d, name: name) },
                            onCancel: { draft = nil }
                        )
                        .frame(width: 190, height: 26)
                        .background(Capsule().fill(LivTheme.accent.opacity(0.2)))
                        .overlay(Capsule().strokeBorder(LivTheme.accent, lineWidth: 1.5))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }

    /// A timeless task: pill-shaped like its neighbours, but the ring is
    /// its own control — the rest of the pill opens the tab.
    private func allDayTask(
        _ item: CalendarDayItem, doneNames: Set<String>
    ) -> some View {
        HStack(spacing: 5) {
            StatusRing(done: isDone(item.row, doneNames), compact: true) {
                toggleStatus(item.row.id)
            }
            Button {
                desk.open(item.row.id)
            } label: {
                Text(livRowTitle(item.row))
                    .font(.system(size: LivType.label))
                    .foregroundStyle(
                        isDone(item.row, doneNames) ? LivTheme.text3 : LivTheme.text
                    )
                    .lineLimit(1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 6)
        .padding(.trailing, 9)
        .frame(height: 24)
        .background(Capsule().fill(LivTheme.panel2))
        .overlay(Capsule().strokeBorder(LivTheme.border, lineWidth: 0.5))
    }

    // MARK: the hour grid

    /// One block's geometry, in the scroll view's CONTENT coordinates —
    /// computed once and used by BOTH the renderer and the drag's
    /// hit-testing, so what you grab is exactly what you see.
    private struct HourFrame: Identifiable {
        let item: CalendarDayItem
        let start: Int
        let length: Int
        let rect: CGRect
        var id: String { item.key }
        /// An occurrence projects a series — moving one instance is a
        /// recurrence edit, not a drag.
        var movable: Bool { !item.occurrence }
    }

    private func frames(_ timed: [CalendarDayItem], width: CGFloat) -> [HourFrame] {
        let unit = CalClock.hourHeight / 60
        let spans = timed.map { item in
            (
                start: CalClock.minutes(of: item.stamp),
                length: CalClock.duration(start: item.stamp, end: item.row.dueEnd)
            )
        }
        let slots = CalLayout.slots(spans)
        let left = CalClock.lane
        let right: CGFloat = 18
        let lane = max(40, width - left - right)
        return timed.indices.map { i in
            let slot = slots[i]
            let column = lane / CGFloat(slot.columns)
            return HourFrame(
                item: timed[i],
                start: spans[i].start,
                length: spans[i].length,
                rect: CGRect(
                    x: left + column * CGFloat(slot.column),
                    y: CGFloat(spans[i].start) * unit,
                    width: column - 2,
                    height: max(24, CGFloat(spans[i].length) * unit - 2)))
        }
    }

    @ViewBuilder private func hourGrid(
        timed: [CalendarDayItem], today: Int64, doneNames: Set<String>
    ) -> some View {
        let nowMinutes = CalClock.minutes(of: Civil.nowStamp())
        GeometryReader { geo in
            let frames = frames(timed, width: geo.size.width)
            ScrollViewReader { scroller in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        hourLines
                        ForEach(frames) { frame in
                            block(frame, doneNames: doneNames)
                        }
                        if let d = draft, d.day == selectedDay, !d.allDay {
                            draftBlock(d, width: geo.size.width)
                        }
                        if selectedDay == today {
                            nowLine(nowMinutes)
                        }
                        // The drag lives here: zero-sized, it installs a
                        // long-press on the enclosing UIScrollView — the
                        // only place a gesture can out-argue the scroll.
                        HourGridDrag(
                            targets: frames.filter(\.movable).map {
                                HourGridDrag.Target(id: $0.item.row.id, rect: $0.rect)
                            },
                            onLift: { id in
                                lifted = LiftedBlock(id: id, minutes: startMinutes(id, frames))
                            },
                            onMove: { id, dy in
                                guard let frame = frames.first(where: { $0.item.row.id == id })
                                else { return }
                                lifted = LiftedBlock(
                                    id: id,
                                    minutes: CalClock.dragged(
                                        start: frame.item.stamp, duration: frame.length, by: dy))
                            },
                            onDrop: { id, dy in
                                lifted = nil
                                guard let frame = frames.first(where: { $0.item.row.id == id })
                                else { return }
                                let landed = CalClock.dragged(
                                    start: frame.item.stamp, duration: frame.length, by: dy)
                                guard landed != frame.start else { return }
                                commitMove(frame.item, minutes: landed, length: frame.length)
                            },
                            onCancel: { lifted = nil }
                        )
                        .frame(width: 0, height: 0)
                    }
                    .frame(height: CalClock.hourHeight * 24)
                    // ONE tap gesture owns the grid. Per-band and
                    // per-block taps used to fight over the same point,
                    // and the band won: tapping an existing event
                    // drafted a new one on top of it (found live,
                    // 2026-08-06). A tap that knows WHERE it landed can
                    // simply answer the question.
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { point in
                        tapGrid(at: point, frames: frames)
                    }
                    // Room for the first hour to sit above its own rule.
                    // Applied OUTSIDE the tap gesture on purpose: the
                    // gesture reads the grid's own coordinates, and this
                    // must not shift what a tap means.
                    .padding(.top, CalClock.labelRise)
                }
                // No scroll bar: it sat exactly on top of in-block controls
                // (found live, 2026-08-05), and the hour labels already say
                // where you are — Apple's day view shows none either.
                .scrollIndicators(.hidden)
                .onAppear { openAtTheDay(today, nowMinutes: nowMinutes, scroller: scroller) }
                .onChange(of: selectedDay) { _, _ in
                    openAtTheDay(today, nowMinutes: nowMinutes, scroller: scroller)
                }
            }
        }
    }

    /// A tap in the grid: on a block it opens that block, on empty space
    /// it starts a draft at that hour. Blocks are checked first — what is
    /// already there outranks what might be.
    private func tapGrid(at point: CGPoint, frames: [HourFrame]) {
        if let hit = frames.first(where: { $0.rect.insetBy(dx: -1, dy: -1).contains(point) }) {
            desk.open(hit.item.row.id)
            return
        }
        // The grid DRAWS per hour; a tap LANDS on the quarter hour
        // (owner, 2026-08-07) — same 15-minute step the drag uses.
        let unit = CalClock.hourHeight / 60
        let minutes = max(
            0, min(24 * 60 - 60, CalClock.snap(Int(point.y / unit))))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        draft = EventDraft(day: selectedDay, minutes: minutes, allDay: false)
    }

    private func startMinutes(_ id: UInt64, _ frames: [HourFrame]) -> Int {
        frames.first { $0.item.row.id == id }?.start ?? 0
    }

    /// Open where the day is: now on today, else the morning.
    private func openAtTheDay(
        _ today: Int64, nowMinutes: Int, scroller: ScrollViewProxy
    ) {
        let hour = selectedDay == today ? max(0, nowMinutes / 60 - 1) : 8
        scroller.scrollTo(hourAnchor(hour), anchor: .top)
    }

    /// One write, whatever moved the block.
    private func commitMove(_ item: CalendarDayItem, minutes: Int, length: Int) {
        let property =
            (item.row.positionedBy?.isEmpty == false) ? item.row.positionedBy! : "due"
        let day = Civil.day(of: item.stamp)
        let hasEnd = (item.row.dueEnd ?? 0) > 0
        box.setSpan(
            item.row.id, property,
            start: Civil.stamp(day: day, hhmm: CalClock.hhmm(minutes)),
            end: hasEnd ? Civil.stamp(day: day, hhmm: CalClock.hhmm(minutes + length)) : 0,
            dateOnly: false
        ) { ok in
            if !ok { UINotificationFeedbackGenerator().notificationOccurred(.error) }
            loadWindow()
        }
    }

    private func hourAnchor(_ hour: Int) -> String { "hour-\(hour)" }

    /// The empty canvas: one tappable band per hour. A tap opens a NAMED
    /// draft at that hour, right where you tapped; the write happens on
    /// submit. Nothing untitled ever reaches the box.
    private var hourLines: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                // Hour lines only (owner, 2026-08-07: "grid per hour") —
                // the half-hour line was dimmer than every other line in
                // the app for a reason nobody could state.
                ZStack(alignment: .topLeading) {
                    // The rule starts AFTER the time column. Drawn from
                    // x=0 it crossed out the hour it was labelling.
                    Rectangle().fill(LivTheme.border).frame(height: 0.5)
                        .padding(.leading, CalClock.gutter)
                    Text(String(format: "%02d:00", hour))
                        .font(.system(size: LivType.caption).monospacedDigit())
                        .foregroundStyle(LivTheme.muted)
                        .frame(width: CalClock.gutter - 8, alignment: .trailing)
                        .offset(y: -CalClock.labelRise)
                }
                .frame(height: CalClock.hourHeight, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(hourAnchor(hour))
                .accessibilityLabel(String(format: "%02d:00", hour))
            }
        }
    }

    private func nowLine(_ minutes: Int) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(LivTheme.red)
                .frame(height: 1.5)
                .padding(.leading, CalClock.gutter)
            Text(Civil.timeString(Civil.nowStamp()))
                .font(.system(size: LivType.micro, weight: .semibold).monospacedDigit())
                .foregroundStyle(LivTheme.onAccent)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(LivTheme.red))
                .padding(.leading, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offset(y: CGFloat(minutes) / 60 * CalClock.hourHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// One timed item, drawn at its computed frame. A tap opens it; a
    /// long press lifts it and the finger sets its time (HourGridDrag).
    /// While it is in the air it draws at the LIVE minute, brighter, with
    /// its moving time — the finger is showing you the answer before it
    /// commits.
    private func block(_ frame: HourFrame, doneNames: Set<String>) -> some View {
        let item = frame.item
        let moving = lifted?.id == item.row.id
        let live = moving ? (lifted?.minutes ?? frame.start) : frame.start
        let task = livCanTick(item.row)
        // The block wears what the thing IS. It used to be purple for a
        // task and blue for everything else, so an event — the calendar's
        // whole reason to exist — came out in the note colour.
        let ink = LivKind.color(of: item.row)
        let unit = CalClock.hourHeight / 60
        let span = CalClock.range(frame.start, frame.length)
        let name = livRowTitle(item.row)
        let voice: String =
            item.occurrence ? "\(name), \(span), repeating" : "\(name), \(span)"

        return blockFace(
            item, name: name, span: span, length: frame.length, live: live,
            moving: moving, voice: voice, task: task, doneNames: doneNames
        )
        .frame(width: frame.rect.width, height: frame.rect.height, alignment: .topLeading)
        .background(blockFill(ink, moving ? 0.36 : 0.2))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(ink.opacity(moving ? 1 : 0.55), lineWidth: moving ? 1.5 : 0.5)
        )
        .shadow(color: .black.opacity(moving ? 0.5 : 0), radius: moving ? 10 : 0, y: 4)
        .offset(x: frame.rect.minX, y: CGFloat(live) * unit)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        // No label on the container: labelling it flattens the subtree and
        // hides the status ring from VoiceOver (found live, 2026-08-05) —
        // the block's voice rides its TITLE instead.
        .accessibilityElement(children: .contain)
    }

    /// What an item on the grid is filled with. OPAQUE, on purpose: the
    /// tint alone was 20% and the hour rule was drawn straight through
    /// every event (owner, 2026-08-10). Same colour as before — the tint
    /// now sits on the canvas rather than on whatever is behind it, so a
    /// block covers the grid instead of tinting it. ONE recipe, so a real
    /// event and a draft can never disagree.
    private func blockFill(_ ink: Color, _ amount: Double) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(LivTheme.canvas)
            .overlay(
                RoundedRectangle(cornerRadius: 8).fill(ink.opacity(amount))
            )
    }

    /// The draft, drawn as a block at the hour you tapped: same shape as
    /// a real event, with a live name field where the title goes. Return
    /// writes it; empty return or the ✗ throws it away, having touched
    /// nothing.
    private func draftBlock(_ d: EventDraft, width: CGFloat) -> some View {
        let unit = CalClock.hourHeight / 60
        let left = CalClock.lane
        let right: CGFloat = 18
        return EventDraftField(
            placeholder: CalClock.range(d.minutes, 60),
            onCommit: { name in commitDraft(d, name: name) },
            onCancel: { draft = nil }
        )
        .frame(width: max(40, width - left - right), height: CalClock.hourHeight - 2,
               alignment: .topLeading)
        .background(blockFill(LivTheme.accent, 0.2))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(LivTheme.accent, lineWidth: 1.5)
        )
        .offset(x: left, y: CGFloat(d.minutes) * unit)
        .id("draft-\(d.day)-\(d.minutes)")
    }

    @ViewBuilder private func blockFace(
        _ item: CalendarDayItem, name: String, span: String, length: Int,
        live: Int, moving: Bool, voice: String, task: Bool, doneNames: Set<String>
    ) -> some View {
        let done = isDone(item.row, doneNames)
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                if item.occurrence {
                    Image(systemName: "repeat")
                        .font(.system(size: LivType.micro, weight: .semibold))
                        .foregroundStyle(LivTheme.text3)
                } else if task {
                    StatusRing(done: done, compact: true) { toggleStatus(item.row.id) }
                }
                Text(name)
                    .font(.system(size: LivType.body, weight: .medium))
                    .foregroundStyle(done ? LivTheme.text3 : LivTheme.text)
                    .lineLimit(1)
                    .accessibilityLabel(voice)
            }
            if length >= 45 || moving {
                Text(moving ? CalClock.range(live, length) + " · moving" : span)
                    .font(.system(size: LivType.caption).monospacedDigit())
                    .foregroundStyle(LivTheme.text3)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
    }

    private func allDayPill(_ item: CalendarDayItem) -> some View {
        Button {
            desk.open(item.row.id)
        } label: {
            HStack(spacing: 5) {
                // An all-day pill holds no task (those go to allDayTask),
                // so the kind mark never competes with a ring here.
                LivIcon(
                    glyph: LivKind.glyph(of: item.row),
                    color: LivKind.color(of: item.row), size: 14)
                if item.occurrence {
                    Image(systemName: "repeat")
                        .font(.system(size: LivType.micro, weight: .semibold))
                        .foregroundStyle(LivTheme.text3)
                }
                Text(livRowTitle(item.row))
                    .font(.system(size: LivType.body))
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
    /// The visible six weeks PLUS the month either side, because the
    /// pager draws both neighbours: without them a month slid in blank
    /// and grew its dots a beat later.
    private func loadWindow() {
        let start = CalGrid.gridStart(CalGrid.addMonths(monthFirst, -1))
        let end = Civil.addDays(CalGrid.gridStart(CalGrid.addMonths(monthFirst, 1)), 41)
        box.refreshWindow(
            from: Civil.stamp(day: start, hhmm: 0),
            to: Civil.stamp(day: end, hhmm: 2359))
    }
}

// MARK: - naming an event where it lives

/// Where a new event is being drawn, before it exists. Held by the
/// calendar; the box learns about it only when a name is submitted.
private struct EventDraft: Equatable {
    let day: Int64
    /// Minutes from midnight. Ignored when `allDay`.
    let minutes: Int
    let allDay: Bool
}

/// The name field inside a draft block. It is a field and a Return key,
/// nothing else — an event's name is one line, and this is not a
/// document. Focus is taken on appear so the keyboard is already up.
private struct EventDraftField: View {
    let placeholder: String
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField(placeholder, text: $text)
                .font(.system(size: LivType.body, weight: .medium))
                .foregroundStyle(LivTheme.text)
                .textInputAutocapitalization(.never)  // capture-verbatim law
                .autocorrectionDisabled(true)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(commit)
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: LivType.caption, weight: .semibold))
                    .foregroundStyle(LivTheme.text3)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Discard")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .onAppear { focused = true }
    }

    private func commit() {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // An empty submit discards. An untitled event helps nobody.
        guard !name.isEmpty else { return onCancel() }
        onCommit(name)
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
    @EnvironmentObject var desk: DeskModel
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
                .font(.system(size: LivType.body))
                .foregroundStyle(LivTheme.text)
                .textInputAutocapitalization(.never)  // capture-verbatim law
                .autocorrectionDisabled(true)
                .focused($focused)
                .onSubmit(submit)
            // No post-save chip strip here, so the stamp is promised
            // BEFORE the write rather than shown after it.
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
            // 09:00, not a bare date — a task with no clock time has no
            // moment to ring at (owner, 2026-08-07).
            box.setSpan(
                id, "due", start: Civil.stamp(day: day, hhmm: LivDue.defaultHHMM),
                end: 0, dateOnly: false)
            // Every creation door stamps (M4) — the row's hint says so
            // before the write.
            workspaces.stamp(id, in: box)
            // Into properties, the standard way a task is made (owner,
            // 2026-08-11). The day is already set from the row it was
            // typed under; what is usually wanted next is everything
            // else. `as: .record` — the snapshot has not caught up.
            desk.open(id, as: .record)
            text = ""
            focused = false
        }
    }
}

// MARK: - month math (packed civil days; Civil's private helpers re-derived)

/// Components-in, components-out within one Gregorian calendar — a stamp
/// never round-trips through a timezone. Noon anchor dodges the
/// DST-skipped-midnight edge (Civil's own rule).
private enum CalGrid {
    /// One day cell, and the six-week grid it lives in. The pager needs
    /// the grid's height as a NUMBER (a GeometryReader has none of its
    /// own), so it lives here rather than as a literal in two places.
    static let cellHeight: CGFloat = 40
    static let rowGap: CGFloat = 2
    static var gridHeight: CGFloat { cellHeight * 6 + rowGap * 5 }
    /// What counts as throwing the month, in points per second.
    /// DELIBERATELY lower than the panel drag's 700 (Desk.swift): a
    /// panel opening by accident costs you the screen you were reading,
    /// a month turning by accident costs one flick back. Measured: a
    /// brisk 80pt throw reports ~565, a long deliberate drag ~308, a
    /// slow nudge ~27.
    static let flickToPage: CGFloat = 400

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
        guard let date = Civil.date(ofDay: monthFirst),
            let moved = gregorian.date(byAdding: .month, value: n, to: date)
        else { return monthFirst }
        let c = gregorian.dateComponents([.year, .month], from: moved)
        return Int64(c.year ?? 0) * 10_000 + Int64(c.month ?? 0) * 100 + 1
    }

    /// The Monday on or before the month's first — the grid's first cell.
    static func gridStart(_ monthFirst: Int64) -> Int64 {
        let weekday = Civil.weekday(monthFirst)  // 1=Sun … 7=Sat
        guard weekday > 0 else { return monthFirst }
        return Civil.addDays(monthFirst, -((weekday + 5) % 7))
    }

    /// "July 2026"
    static func title(_ monthFirst: Int64) -> String {
        guard let date = Civil.date(ofDay: monthFirst) else { return "\(monthFirst)" }
        return titleFormatter.string(from: date)
    }

}

// MARK: - the hour grid's arithmetic (phase 4; pure, self-checked)

/// Minutes-of-day maths for the day grid. Pure in, pure out — the view
/// does no clock arithmetic of its own, and `livCalendarSelfCheck` pins
/// every rule below.
/// Where overlapping blocks go. Pure: spans in, column assignments out —
/// so the geometry the view draws and the geometry the drag hit-tests are
/// the same arithmetic, and `livCalendarSelfCheck` can pin it.
enum CalLayout {
    struct Slot: Equatable {
        /// 0-based column inside this block's overlap cluster.
        let column: Int
        /// How many columns that cluster needs — the block's width divisor.
        let columns: Int
    }

    /// Overlapping blocks split the width instead of hiding each other
    /// (before this they stacked, and the one underneath was unreachable).
    /// A CLUSTER is a run of spans connected by overlap; its width is the
    /// most columns any moment in it needs. Answers ride the INPUT order.
    static func slots(_ spans: [(start: Int, length: Int)]) -> [Slot] {
        let order = spans.indices.sorted {
            spans[$0].start != spans[$1].start
                ? spans[$0].start < spans[$1].start : $0 < $1
        }
        var out = [Slot](repeating: Slot(column: 0, columns: 1), count: spans.count)
        var cluster: [Int] = []  // indices, in input space
        var columnEnds: [Int] = []  // per column: the end minute in use
        var assigned: [Int: Int] = [:]  // index -> column

        func flush() {
            let width = max(1, columnEnds.count)
            for i in cluster {
                out[i] = Slot(column: assigned[i] ?? 0, columns: width)
            }
            cluster = []
            columnEnds = []
            assigned = [:]
        }

        for i in order {
            let start = spans[i].start
            let end = start + max(1, spans[i].length)
            // A new cluster begins where nothing open reaches this start.
            if !columnEnds.contains(where: { $0 > start }) { flush() }
            if let free = columnEnds.firstIndex(where: { $0 <= start }) {
                columnEnds[free] = end
                assigned[i] = free
            } else {
                columnEnds.append(end)
                assigned[i] = columnEnds.count - 1
            }
            cluster.append(i)
        }
        flush()
        return out
    }
}

enum CalClock {
    /// One hour's height. The grid's ONE magic number: block geometry,
    /// the now-line and the drag all derive from it.
    static let hourHeight: CGFloat = 56
    /// The time column on the left. Everything that draws across the day
    /// starts here, so nothing is ever drawn through the times: the hour
    /// rule, the now-line and the blocks all measure from this one
    /// number. Before it existed there were four (0, 16, 44 and 60) and
    /// the hour rule ran straight through "09:00" (owner, 2026-08-10).
    static let gutter: CGFloat = 46
    /// The gap between the times and the first block, so a block's
    /// rounded corner never touches the rule's start.
    static let gutterGap: CGFloat = 14
    /// Where a block's lane begins.
    static var lane: CGFloat { gutter + gutterGap }
    /// How far each time sits ABOVE its own rule, so the two read as one
    /// mark. It is also how much room the grid must leave at the top:
    /// without it the first hour of the day was sliced in half by the
    /// edge of the scroll (owner, 2026-08-10).
    static let labelRise: CGFloat = 6
    /// Times land on quarter hours — 11:47 is never what anyone meant.
    static let step = 15

    /// A civil stamp's minutes-of-day (its HHMM part).
    static func minutes(of stamp: Int64) -> Int {
        let hm = Int(stamp % 10_000)
        return (hm / 100) * 60 + hm % 100
    }

    /// Minutes-of-day back to a packed HHMM.
    static func hhmm(_ minutes: Int) -> Int64 {
        let m = max(0, min(24 * 60 - 1, minutes))
        return Int64((m / 60) * 100 + m % 60)
    }

    /// Nearest quarter hour.
    static func snap(_ minutes: Int) -> Int {
        let s = step
        return ((minutes + s / 2) / s) * s
    }

    /// A timed span's length in minutes: the stored end when it is real,
    /// else one hour — a zero-height block would be untappable, and an
    /// event with no end still occupies the time you gave it.
    static func duration(start: Int64, end: Int64?) -> Int {
        guard let end, end > start, Civil.day(of: end) == Civil.day(of: start) else {
            return 60
        }
        return max(step, minutes(of: end) - minutes(of: start))
    }

    /// How long a span lasts, in minutes: 0 when it has no end, the end
    /// is not after the start, or the end is on another day. Distinct
    /// from `duration`, which answers "how tall do I draw this" and so
    /// invents an hour when there is no end.
    static func span(start: Int64, end: Int64?) -> Int {
        guard let end, end > start, Civil.day(of: end) == Civil.day(of: start)
        else { return 0 }
        return minutes(of: end) - minutes(of: start)
    }

    /// The end stamp for a span of `length` minutes starting at `start`.
    /// 0 when there is no length, or when the end would fall on the next
    /// day — the core refuses an end that is not after its start, so a
    /// span that would spill is left open rather than written broken.
    static func end(start: Int64, length: Int) -> Int64 {
        guard length > 0 else { return 0 }
        let total = minutes(of: start) + length
        guard total < 24 * 60 else { return 0 }
        return Civil.stamp(day: Civil.day(of: start), hhmm: hhmm(total))
    }

    /// Where a drag lands: snapped to the quarter hour, and kept inside
    /// the day it started in — a block dragged off the bottom must not
    /// silently change date.
    static func dragged(start: Int64, duration: Int, by offset: CGFloat) -> Int {
        let moved = minutes(of: start) + Int((offset / hourHeight * 60).rounded())
        return max(0, min(24 * 60 - duration, snap(moved)))
    }

    /// "09:30 – 10:30" — a block's own label.
    static func range(_ startMinutes: Int, _ duration: Int) -> String {
        func clock(_ m: Int) -> String {
            String(format: "%02d:%02d", (m / 60) % 24, m % 60)
        }
        return clock(startMinutes) + " – " + clock(startMinutes + duration)
    }
}

/// No test target (no Xcode project): `simctl launch … -calendar.selfcheck 1`
/// runs the hour grid's arithmetic and prints the failures.
func livCalendarSelfCheck() -> [String] {
    var failures: [String] = []
    // The due sheet moves a span by re-deriving its end from its length.
    // These pin that arithmetic — it silently deleted every event's end
    // until a review caught it (2026-08-06).
    func span(_ label: String, _ got: Int, _ want: Int) {
        if got != want { failures.append("FAIL \(label) got \(got) want \(want)") }
    }
    func stamp(_ label: String, _ got: Int64, _ want: Int64) {
        if got != want { failures.append("FAIL \(label) got \(got) want \(want)") }
    }
    span("span 0900->1100", CalClock.span(start: 202608070900, end: 202608071100), 120)
    span("span no end", CalClock.span(start: 202608070900, end: nil), 0)
    span("span zero end", CalClock.span(start: 202608070900, end: 0), 0)
    span("span end before start", CalClock.span(start: 202608071100, end: 202608070900), 0)
    span("span crossing days", CalClock.span(start: 202608072300, end: 202608080100), 0)
    stamp("end 1400 +120", CalClock.end(start: 202608071400, length: 120), 202608071600)
    stamp("end 0930 +45", CalClock.end(start: 202608070930, length: 45), 202608071015)
    stamp("end no length", CalClock.end(start: 202608071400, length: 0), 0)
    stamp("end would spill", CalClock.end(start: 202608072330, length: 60), 0)
    // A span moved to another day keeps its length.
    let moved = CalClock.end(
        start: 202608081015,
        length: CalClock.span(start: 202608070900, end: 202608071100))
    stamp("moved span keeps 2h", moved, 202608081215)
    // Who keeps "no clock time" through an edit, and who does not.
    func timed(_ label: String, _ got: Bool, _ want: Bool) {
        if got != want { failures.append("FAIL \(label) got \(got) want \(want)") }
    }
    timed(
        "all-day event stays all-day",
        LivDue.carriesTime(dateOnly: true, isEvent: true), false)
    timed(
        "timed event stays timed",
        LivDue.carriesTime(dateOnly: false, isEvent: true), true)
    timed(
        "date-only task gains a time",
        LivDue.carriesTime(dateOnly: true, isEvent: false), true)
    timed(
        "timed task stays timed",
        LivDue.carriesTime(dateOnly: false, isEvent: false), true)
    func check(_ label: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        if !ok { failures.append("FAIL \(label) \(detail())") }
    }

    check("minutes of 09:30", CalClock.minutes(of: 202_608_040_930) == 570)
    check("minutes of midnight", CalClock.minutes(of: 202_608_040_000) == 0)
    check("hhmm round trip", CalClock.hhmm(570) == 930)
    check("hhmm clamps past midnight", CalClock.hhmm(24 * 60) == 2359)
    check("hhmm clamps negative", CalClock.hhmm(-10) == 0)

    check("snap down", CalClock.snap(7) == 0)
    check("snap up", CalClock.snap(8) == 15)
    check("snap exact", CalClock.snap(30) == 30)

    check(
        "duration from a real end",
        CalClock.duration(start: 202_608_040_930, end: 202_608_041_045) == 75)
    check("no end is an hour", CalClock.duration(start: 202_608_040_930, end: nil) == 60)
    check("zero end is an hour", CalClock.duration(start: 202_608_040_930, end: 0) == 60)
    check(
        "an end on another day is an hour, never a negative block",
        CalClock.duration(start: 202_608_040_930, end: 202_608_050_930) == 60)

    // One hour down = +60 minutes, snapped and clamped to the day.
    check(
        "drag one hour down",
        CalClock.dragged(start: 202_608_040_900, duration: 60, by: CalClock.hourHeight) == 600)
    check(
        "drag up past midnight clamps to 00:00",
        CalClock.dragged(start: 202_608_040_030, duration: 60, by: -CalClock.hourHeight * 3) == 0)
    check(
        "drag down keeps the block inside the day",
        CalClock.dragged(start: 202_608_042_300, duration: 60, by: CalClock.hourHeight * 5)
            == 23 * 60)
    check(
        "half an hour of travel snaps to the half hour",
        CalClock.dragged(start: 202_608_040_900, duration: 60, by: CalClock.hourHeight / 2)
            == 570)
    check(
        "a nudge smaller than half a step does not move",
        CalClock.dragged(start: 202_608_040_900, duration: 60, by: 5) == 540)

    // CalLayout — overlapping blocks split the width.
    let alone = CalLayout.slots([(540, 60), (720, 60)])
    check(
        "separate blocks are full width",
        alone == [CalLayout.Slot(column: 0, columns: 1), CalLayout.Slot(column: 0, columns: 1)],
        "\(alone)")
    let pair = CalLayout.slots([(540, 60), (540, 60)])
    check(
        "two at the same time share two columns",
        pair == [CalLayout.Slot(column: 0, columns: 2), CalLayout.Slot(column: 1, columns: 2)],
        "\(pair)")
    let chain = CalLayout.slots([(540, 60), (570, 60), (720, 60)])
    check(
        "a chained overlap is one cluster; the loner stays wide",
        chain == [
            CalLayout.Slot(column: 0, columns: 2), CalLayout.Slot(column: 1, columns: 2),
            CalLayout.Slot(column: 0, columns: 1),
        ],
        "\(chain)")
    // Butting up against the end is NOT an overlap: the next block starts
    // its own cluster and gets the full width back.
    let butted = CalLayout.slots([(540, 60), (540, 60), (600, 60)])
    check(
        "a block that starts where the others end is full width",
        butted[2] == CalLayout.Slot(column: 0, columns: 1), "\(butted)")
    // Real reuse: A spans both hours, so C joins the cluster and takes the
    // column B has finished with.
    let reuse = CalLayout.slots([(540, 120), (540, 60), (600, 60)])
    check(
        "a column is reused once it is free",
        reuse == [
            CalLayout.Slot(column: 0, columns: 2), CalLayout.Slot(column: 1, columns: 2),
            CalLayout.Slot(column: 1, columns: 2),
        ],
        "\(reuse)")
    let three = CalLayout.slots([(540, 120), (550, 60), (560, 30)])
    check("three deep needs three columns", three.allSatisfy { $0.columns == 3 }, "\(three)")
    check(
        "input order is preserved",
        CalLayout.slots([(720, 60), (540, 60)])[0] == CalLayout.Slot(column: 0, columns: 1))

    check("range label", CalClock.range(570, 60) == "09:30 – 10:30", CalClock.range(570, 60))

    return failures
}

// MARK: - the UIKit drag (owner-directed 2026-08-05: "do it properly")

/// Move a block by dragging it. SwiftUI cannot do this: a vertical drag
/// inside a vertically scrolling view never reaches the app, because
/// UIScrollView's own pan recognizer claims the touch first — plain drag,
/// press-then-drag and a high-priority grip were each instrumented and
/// produced zero events (2026-08-05).
///
/// So the recognizer goes where it can win: **on the scroll view itself**.
/// A UILongPressGestureRecognizer added to the enclosing UIScrollView sees
/// every touch in the content, and a long press is the arbiter Apple
/// Calendar uses — hold to lift, then move. Two rules make it coexist
/// perfectly with scrolling:
///
///   1. `gestureRecognizerShouldBegin` returns false unless the touch
///      lands inside a MOVABLE block, so ordinary scrolls and taps are
///      untouched — the recognizer simply never begins.
///   2. Scrolling is switched off for the duration of a lift and restored
///      on end/cancel, so the two can never fight mid-drag.
///
/// The view itself is a zero-sized, non-interactive host: it exists only
/// to own the recognizer and to hold the block geometry SwiftUI hands it,
/// so hit-testing for taps is completely undisturbed.
struct HourGridDrag: UIViewRepresentable {
    /// One movable block, in the scroll view's CONTENT coordinates.
    struct Target {
        let id: UInt64
        let rect: CGRect
    }

    let targets: [Target]
    let onLift: (UInt64) -> Void
    let onMove: (UInt64, CGFloat) -> Void
    let onDrop: (UInt64, CGFloat) -> Void
    let onCancel: () -> Void

    func makeUIView(context: Context) -> HourGridDragHost {
        let host = HourGridDragHost()
        host.coordinator = context.coordinator
        return host
    }

    func updateUIView(_ host: HourGridDragHost, context: Context) {
        context.coordinator.targets = targets
        context.coordinator.onLift = onLift
        context.coordinator.onMove = onMove
        context.coordinator.onDrop = onDrop
        context.coordinator.onCancel = onCancel
        host.attachIfNeeded()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var targets: [Target] = []
        var onLift: (UInt64) -> Void = { _ in }
        var onMove: (UInt64, CGFloat) -> Void = { _, _ in }
        var onDrop: (UInt64, CGFloat) -> Void = { _, _ in }
        var onCancel: () -> Void = {}

        /// The view whose coordinate space the target rects are in (the
        /// grid's content), and the scroll view to suspend mid-lift.
        weak var content: UIView?
        weak var scroll: UIScrollView?

        private var lifted: UInt64?
        private var origin: CGPoint = .zero

        /// Where the finger is, in the SAME space the rects were computed
        /// in — the grid's content view, not the window.
        private func point(_ g: UIGestureRecognizer) -> CGPoint? {
            guard let content else { return nil }
            return g.location(in: content)
        }

        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let p = point(g) else { return false }
            return targets.contains { $0.rect.contains(p) }
        }

        /// MUST be true. Refusing simultaneity here starved the scroll
        /// view's own pan completely — the grid would not scroll at all
        /// (found live, 2026-08-05). Coexistence is safe because the press
        /// can only begin ON a block after a dwell, and the instant it
        /// does it switches scrolling off for the duration of the lift.
        func gestureRecognizer(
            _ g: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        @objc func handle(_ press: UILongPressGestureRecognizer) {
            switch press.state {
            case .began:
                guard let p = point(press),
                    let hit = targets.first(where: { $0.rect.contains(p) })
                else {
                    press.state = .failed
                    return
                }
                lifted = hit.id
                origin = p
                // The scroll must not compete while a block is in the air.
                scroll?.isScrollEnabled = false
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                onLift(hit.id)
            case .changed:
                guard let id = lifted, let p = point(press) else { return }
                onMove(id, p.y - origin.y)
            case .ended:
                let id = lifted
                let dy = point(press).map { $0.y - origin.y }
                release()
                if let id, let dy { onDrop(id, dy) }
            case .cancelled, .failed:
                let had = lifted != nil
                release()
                if had { onCancel() }
            default:
                break
            }
        }

        private func release() {
            scroll?.isScrollEnabled = true
            lifted = nil
        }
    }
}

/// The recognizer's host: zero-sized and invisible to hit-testing. It only
/// finds the pieces the coordinator needs and installs the press on the
/// WINDOW — recognizers added to SwiftUI's hosting scroll view are never
/// offered the touch (instrumented 2026-08-05: `shouldBegin` was not
/// called even for a real 0.8s press), while the window sees every touch
/// in the app. Hit-testing happens in the grid's own content space, so the
/// rects the view drew are the rects the finger grabs.
final class HourGridDragHost: UIView {
    weak var coordinator: HourGridDrag.Coordinator?
    private var press: UILongPressGestureRecognizer?

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attachIfNeeded()
    }

    override func removeFromSuperview() {
        if let press { press.view?.removeGestureRecognizer(press) }
        press = nil
        super.removeFromSuperview()
    }

    func attachIfNeeded() {
        guard let coordinator else { return }
        // The rects were computed in the grid's content space: that is this
        // view's own superview (the ZStack that holds the blocks).
        coordinator.content = superview
        coordinator.scroll = enclosingScroll
        // A door for bisecting gesture conflicts: `-drag.off 1` skips the
        // recognizer entirely, so scrolling can be compared with and
        // without it in the SAME build.
        if UserDefaults.standard.bool(forKey: "drag.off") { return }
        guard press == nil, let window else { return }
        let g = UILongPressGestureRecognizer(
            target: coordinator, action: #selector(HourGridDrag.Coordinator.handle(_:)))
        // Apple Calendar's dwell: deliberate, but short of a scroll flick.
        g.minimumPressDuration = 0.28
        // A finger is never perfectly still.
        g.allowableMovement = 12
        g.delegate = coordinator
        // Touches keep flowing until this recognizes, so a plain tap still
        // opens the block; recognition then cancels the tap.
        g.cancelsTouchesInView = true
        g.delaysTouchesBegan = false
        window.addGestureRecognizer(g)
        press = g
    }

    private var enclosingScroll: UIScrollView? {
        var view: UIView? = superview
        while let current = view {
            if let scroll = current as? UIScrollView { return scroll }
            view = current.superview
        }
        return nil
    }
}
