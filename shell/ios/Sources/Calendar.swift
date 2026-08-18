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

// MARK: - the month grid's data, decided before it is drawn

/// One cell of the month grid, already decided: the number, whether it
/// belongs to the month, and the colours of its dots. Everything the
/// cell draws and nothing else, so a cell rebuilds when its DAY changes
/// and not because a finger moved.
private struct CalCell: Equatable {
    let day: Int64
    let number: Int
    let inMonth: Bool
    let isToday: Bool
    let count: Int
    /// Up to three, in kind colour (owner, 2026-08-13).
    let dots: [Color]
}

/// One month's six weeks, ready to draw.
private struct CalMonth: Equatable {
    let month: Int64
    let cells: [CalCell]
}

/// Build one month from the day buckets. Runs when the MONTH or the
/// SNAPSHOT moves — never per frame of a drag, which is the whole point
/// of the type (measured 2026-08-15: a 1.2s drag rebuilt 12,348 cells).
private func calMonth(
    _ month: Int64, today: Int64, byDay: [Int64: [CalendarDayItem]]
) -> CalMonth {
    let start = CalGrid.gridStart(month)
    var cells: [CalCell] = []
    cells.reserveCapacity(42)
    for i in 0..<42 {
        let day = Civil.addDays(start, i)
        let items = byDay[day] ?? []
        cells.append(
            CalCell(
                day: day,
                number: Civil.dayNumber(day),
                inMonth: CalGrid.firstOfMonth(day) == month,
                isToday: day == today,
                count: items.count,
                dots: items.prefix(3).map { LivKind.color(of: $0.row) }))
    }
    return CalMonth(month: month, cells: cells)
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

    /// The day the Today toggle came FROM, so its second tap can put you
    /// back. Cleared once used: a toggle remembers one step, not a
    /// history.
    @State private var wasOn: Int64?

    /// First day of the shown month (packed civil), the grid's anchor.
    @State private var monthFirst = CalGrid.firstOfMonth(Civil.todayDay())
    @State private var selectedDay = Civil.todayDay()
    /// The task status vocabulary — the ring writes the `completes`-marked
    /// option, never a hardcoded "done" (same as Today).
    @State private var taskOptions: [StatusOption] = []
    /// The block currently in the air, and where its start sits now. Live
    /// only — the write happens when the finger lifts.
    @State private var lifted: LiftedBlock?
    /// The box being PLACED: minutes from midnight, while the finger is
    /// down on empty grid. It is not in the box yet and nothing has been
    /// written — letting go is what writes it.
    @State private var placing: Int?
    /// The finger is over the bin, so the lifted block will be trashed.
    @State private var trashArmed = false
    /// Where the bin sits, in WINDOW space, so the drag (which reports
    /// the finger in the same space) can tell when it is over it.
    @State private var trashZone: CGRect = .zero
    /// A new event being NAMED in the grid. Nothing is written until the
    /// name is submitted: tapping an hour used to create an untitled
    /// event and throw you into the note editor to name it (owner,
    /// 2026-08-06 — "setting names of calendar items should be done in
    /// calendar", and an event is not a document).
    /// A page asked for by ‹ ›, Today or a month-away jump. The pager
    /// consumes it, slides, and hands the month back on landing — the
    /// drag itself lives down there, not here.
    @State private var pageRequest = 0
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
        // The bar's create key inherits the day you are looking at.
        .onAppear { desk.contextDay = selectedDay }
        .onChange(of: selectedDay) { _, day in desk.contextDay = day }
        .onDisappear { desk.contextDay = nil }
    }

    // MARK: header — month title, Today, prev/next

    private func header(today: Int64) -> some View {
        HStack(spacing: 8) {
            Text(CalGrid.title(monthFirst))
                .font(.system(size: LivType.strong, weight: .semibold))
                .foregroundStyle(LivTheme.text)
            if box.busyRetrying { ProgressView().scaleEffect(0.7) }
            Spacer()
            // A VERB, dressed as one. As plain accent text beside the
            // date it read as a label saying which day was selected
            // (owner, 2026-08-10) — it is a button that takes you to
            // today, so it wears a button's face. The 26pt pill sits in
            // a 40pt tap target.
            //
            // It is also the day heading now (owner, 2026-08-13): lit
            // means the day on screen is today, so nothing else has to
            // say so. And it TOGGLES — the second tap puts you back on
            // the day you left, which is what you want after a glance at
            // today.
            Button {
                if onToday {
                    guard let back = wasOn else { return }
                    wasOn = nil
                    go(to: back, today: today)
                } else {
                    wasOn = selectedDay
                    go(to: today, today: today)
                }
            } label: {
                // ON = the day on screen IS today. Bright, with the word
                // carved out of it — the same stencil the icon chips
                // wear, and the app's one way of saying "this is the
                // live one". OFF keeps the soft tint.
                Text("Today")
                    .font(.system(size: LivType.body, weight: .semibold))
                    .foregroundStyle(onToday ? LivTheme.canvas : LivTheme.accent)
                    .padding(.horizontal, 11)
                    .frame(height: 26)
                    .background(
                        Capsule().fill(
                            onToday ? LivTheme.accent : LivTheme.accentSoft)
                    )
                    .overlay(
                        Capsule().strokeBorder(
                            onToday ? Color.clear : LivTheme.accent.opacity(0.5),
                            lineWidth: 0.5)
                    )
                    .frame(height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Today")
            .accessibilityAddTraits(onToday ? [.isSelected] : [])
            chevron("chevron.left", label: "Previous month") { page(-1) }
            chevron("chevron.right", label: "Next month") { page(1) }
        }
    }

    /// Is the day on screen today's?
    private var onToday: Bool { selectedDay == Civil.todayDay() }

    /// Land on a day, sliding when it is one month away and jumping when
    /// it is further — a leap of many months has no direction worth
    /// animating.
    private func go(to day: Int64, today: Int64) {
        selectedDay = day
        let home = CalGrid.firstOfMonth(day)
        if home == CalGrid.addMonths(monthFirst, -1) {
            page(-1)
        } else if home == CalGrid.addMonths(monthFirst, 1) {
            page(1)
        } else {
            monthFirst = home
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
        let land = {
            monthFirst = moved
            selectedDay = CalGrid.firstOfMonth(today) == moved ? today : moved
        }
        if animated { withAnimation(LivMotion.nav, land) } else { land() }
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

    // MARK: the pager — three months side by side, the middle one shown
    //
    // The grid FOLLOWS the finger (owner, 2026-08-10: "not the
    // drag+swipe, which is nicer"). A fire-on-release swipe told you
    // nothing until it was over; this shows the next month arriving
    // while you are still deciding, and lets you change your mind by
    // sliding back. The neighbours are real grids, so what slides in is
    // what you get. ‹ › and Today drive the SAME path — one page(), one
    // place the settle rule lives.
    //
    // The pager is its own VIEW, and that is the fix for "minicalendar
    // lags when dragged" (owner, 2026-08-15). The drag used to be
    // @State on this screen, so every touch-move re-ran this whole
    // body: the day buckets, 126 day cells and the hour grid below,
    // 98 times in a 1.2-second drag (measured). With the offset held
    // one level down, a frame moves an offset and nothing else.

    private func monthPager(
        today: Int64, byDay: [Int64: [CalendarDayItem]]
    ) -> some View {
        MonthPagerView(
            months: (-1...1).map {
                calMonth(CalGrid.addMonths(monthFirst, $0), today: today, byDay: byDay)
            },
            selected: selectedDay,
            onSelect: { selectedDay = $0 },
            onHold: { createEvent(on: $0) },
            onPage: { step($0, animated: false) },
            request: $pageRequest,
            width: $pageWidth)
    }

    /// ‹ ›, Today and a month-away jump all ask the pager to slide; the
    /// pager owns the motion and calls `onPage` when it lands.
    private func page(_ n: Int) {
        guard pageWidth > 0 else {
            step(n)
            return
        }
        pageRequest = n
    }

    /// Long-press a month cell: an event on that day, at 09:00. It used
    /// to make an ALL-DAY one, which the band under the month grid drew
    /// — and that band is gone (owner, 2026-08-13), so an all-day event
    /// would now be created and never seen. A door that makes something
    /// invisible is a defect, so this door makes a TIMED thing, at the
    /// hour a day usually starts. The properties are up a beat later and
    /// the time is the first row in them.
    private func createEvent(on day: Int64) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        selectedDay = day
        create(on: day, minutes: 9 * 60, allDay: false)
    }

    /// The ONE write path: the event exists the instant you point at the
    /// hour, and its PROPERTIES rise with the caret already in the name
    /// (owner, 2026-08-13: "naming of items should be done in
    /// properties"). No draft block, no inline field, nothing to commit
    /// or cancel — the timeline places things in time, the card says
    /// what they are.
    ///
    /// The card rises OVER the calendar, which stays where it was
    /// (Option C). The shape is passed explicitly because the entity is
    /// a heartbeat old and may not be in the snapshot `shapeOf` reads.
    private func create(on day: Int64, minutes: Int, allDay: Bool) {
        let stamp = Civil.stamp(
            day: day, hhmm: allDay ? 0 : Int64(CalClock.hhmm(minutes)))
        box.createEvent(dueCivil: stamp, dateOnly: allDay) { id in
            guard id != 0 else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            workspaces.stamp(id, in: box)
            loadWindow()
            desk.requestFocus(id)
            desk.open(id, as: .record)
        }
    }

    // MARK: the day panel — the all-day band and the hour grid
    //
    // No quick-add row at the foot. It said "New for Tue 11 Aug…" and
    // made a date-only TASK, which is not what this screen is for: you
    // point at the hour you mean and the thing lands there (owner,
    // 2026-08-13, "redundant since users click where they want their
    // items to be in the timeline"). A dated task is still made in Tasks
    // and in Today, where the same row lives.

    /// The day, Apple Calendar's shape (phase 4): an all-day band, then an
    /// hour grid where a timed item is a positioned block. Tap an empty
    /// hour to create there; drag a block to move its time.
    private func dayPanel(
        items: [CalendarDayItem], today: Int64, doneNames: Set<String>
    ) -> some View {
        let timed = items.filter { !$0.allDay }
        return VStack(spacing: 0) {
            // NOTHING between the month grid and the timeline — no date
            // heading, no ALL DAY band (owner, 2026-08-13). The timeline
            // starts where the month ends.
            //
            // What that costs, said plainly: a thing with a DATE but no
            // time — an all-day event, a task due today — is not drawn
            // on this screen any more. It is still a dot on its day in
            // the month grid, and it is still in Today, in Tasks and in
            // search. The band that carried them is deleted, ring and
            // all.
            hourGrid(timed: timed, today: today, doneNames: doneNames)
        }
        // The bin rides OVER the foot of the timeline while something is
        // in the air, and takes no space when nothing is.
        .overlay(alignment: .bottom) {
            if lifted != nil { trashZone_ }
        }
        .animation(LivMotion.nav, value: lifted != nil)
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
                        // The box being placed, drawn exactly like the
                        // block it is about to become — no text: it has
                        // no name yet, and naming happens in the
                        // properties (owner, 2026-08-13).
                        if let minutes = placing {
                            placedBox(minutes, width: geo.size.width)
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
                            onMove: { id, dy, where_ in
                                trashArmed = overTrash(where_)
                                guard let frame = frames.first(where: { $0.item.row.id == id })
                                else { return }
                                lifted = LiftedBlock(
                                    id: id,
                                    minutes: CalClock.dragged(
                                        start: frame.item.stamp, duration: frame.length, by: dy))
                            },
                            onDrop: { id, dy, where_ in
                                lifted = nil
                                let onTrash = overTrash(where_)
                                trashArmed = false
                                guard let frame = frames.first(where: { $0.item.row.id == id })
                                else { return }
                                // Dropped on the bin: the item goes, soft
                                // and undoable like every trash here.
                                if onTrash {
                                    UINotificationFeedbackGenerator()
                                        .notificationOccurred(.success)
                                    box.trash(id)
                                    loadWindow()
                                    return
                                }
                                let landed = CalClock.dragged(
                                    start: frame.item.stamp, duration: frame.length, by: dy)
                                guard landed != frame.start else { return }
                                commitMove(frame.item, minutes: landed, length: frame.length)
                            },
                            onCancel: {
                                lifted = nil
                                trashArmed = false
                                placing = nil
                            },
                            onPlace: { minutes in placing = minutes },
                            onPlaceMove: { minutes in placing = minutes },
                            onPlaceDrop: { minutes in
                                placing = nil
                                create(on: selectedDay, minutes: minutes, allDay: false)
                            }
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

    /// The box under the finger while a new event is being placed.
    private func placedBox(_ minutes: Int, width: CGFloat) -> some View {
        let unit = CalClock.hourHeight / 60
        return RoundedRectangle(cornerRadius: 8)
            .fill(LivTheme.tint(LivKind.event.color, 0.3))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(LivKind.event.color, lineWidth: 1.5)
            )
            .overlay(alignment: .topLeading) {
                Text(CalClock.range(minutes, 60))
                    .font(.system(size: LivType.caption).monospacedDigit())
                    .foregroundStyle(LivTheme.text2)
                    .padding(.horizontal, 8)
                    .padding(.top, 5)
            }
            .frame(
                width: max(40, width - CalClock.lane - 18),
                height: CalClock.hourHeight - 2)
            .offset(x: CalClock.lane, y: CGFloat(minutes) * unit)
            .allowsHitTesting(false)
    }

    /// The bin, shown only while a block is in the air (owner,
    /// 2026-08-14: "hold down on existing item should make it possible to
    /// trash"). Drop a block on it and the block goes; drop it anywhere
    /// else and it just lands at its new time. It measures itself in
    /// WINDOW space because the drag reports the finger there.
    private var trashZone_: some View {
        HStack(spacing: 8) {
            Image(systemName: trashArmed ? "trash.fill" : "trash")
                .font(.system(size: LivType.title, weight: .medium))
            Text("Drop to trash")
                .font(.system(size: LivType.body, weight: .medium))
        }
        .foregroundStyle(trashArmed ? LivTheme.onAccent : LivTheme.red)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: LivTheme.radius)
                .fill(trashArmed ? LivTheme.red : LivTheme.tint(LivTheme.red, 0.18))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { trashZone = geo.frame(in: .global) }
                    .onChange(of: geo.frame(in: .global)) { _, f in trashZone = f }
            }
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .allowsHitTesting(false)
    }

    private func overTrash(_ point: CGPoint) -> Bool {
        trashZone != .zero && trashZone.contains(point)
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
        create(on: selectedDay, minutes: minutes, allDay: false)
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
            .fill(LivTheme.tint(ink, amount))
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

// MARK: - the pager and the grid, as views of their own

/// Three months side by side, the middle one shown, following the
/// finger. It owns the drag OFFSET — the one value a touch-move
/// changes — so a frame of dragging re-runs this body and nothing
/// above it (owner, 2026-08-15: "minicalendar lags when dragged").
private struct MonthPagerView: View {
    let months: [CalMonth]
    let selected: Int64
    let onSelect: (Int64) -> Void
    let onHold: (Int64) -> Void
    /// The slide landed: the screen above moves the month under us, with
    /// animations off, in the same beat the offset returns to zero.
    let onPage: (Int) -> Void
    /// ‹ ›, Today and a month-away jump ask for a page through this.
    @Binding var request: Int
    /// One month's width, learned from the layout and read by the screen
    /// above to know whether a slide is possible at all.
    @Binding var width: CGFloat

    @State private var drag: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let span = geo.size.width
            HStack(spacing: 0) {
                ForEach(months, id: \.month) { month in
                    MonthGridView(
                        month: month, selected: selected,
                        onSelect: onSelect, onHold: onHold
                    )
                    // Equatable: while the finger moves, the months and
                    // the selection are unchanged, so SwiftUI skips all
                    // 126 cells and just re-places the strip.
                    .equatable()
                    .padding(.horizontal, 16)
                    .frame(width: span)
                }
            }
            .offset(x: -span + drag)
            .contentShape(Rectangle())
            .gesture(gesture(span: span))
            .onAppear { width = span }
            .onChange(of: span) { _, w in width = w }
            .onChange(of: request) { _, n in
                guard n != 0 else { return }
                request = 0
                slide(n, over: span)
            }
        }
        .frame(height: CalGrid.gridHeight)
        .clipped()
    }

    /// Follow the finger, then settle. A flick commits from anywhere; a
    /// slow drag commits past a third of the way — the panel drag's own
    /// rule, so the two gestures in this app agree about what a
    /// deliberate pull means.
    private func gesture(span: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { g in
                // Vertical wins: the day panel below scrolls, and a
                // finger drifting down must not drag the month sideways.
                guard abs(g.translation.width) > abs(g.translation.height)
                else { return }
                drag = g.translation.width
            }
            .onEnded { g in
                let dx = drag
                guard dx != 0 else { return }
                let velocity = g.velocity.width
                let flicked = abs(velocity) > CalGrid.flickToPage
                let towards = flicked ? velocity : dx
                guard flicked || abs(dx) > span / 3 else {
                    withAnimation(LivMotion.nav) { drag = 0 }
                    return
                }
                slide(towards < 0 ? 1 : -1, over: span)
            }
    }

    /// Slide one month along, then swap the middle grid underneath
    /// without a second animation. Both the chevrons and the drag land
    /// here.
    private func slide(_ n: Int, over span: CGFloat) {
        guard span > 0 else {
            onPage(n)
            return
        }
        withAnimation(LivMotion.nav) { drag = CGFloat(-n) * span }
        // When the slide lands, the neighbour IS the month — move the
        // data under it and zero the offset in one un-animated beat, so
        // nothing is seen to jump back.
        DispatchQueue.main.asyncAfter(deadline: .now() + LivMotion.navSeconds) {
            var instant = Transaction()
            instant.disablesAnimations = true
            withTransaction(instant) {
                onPage(n)
                drag = 0
            }
        }
    }
}

/// Six weeks of one month, drawn from cells decided in advance.
/// Equatable on purpose: its inputs are values, so SwiftUI can skip the
/// whole grid while only the strip's offset is moving.
private struct MonthGridView: View, Equatable {
    let month: CalMonth
    let selected: Int64
    let onSelect: (Int64) -> Void
    let onHold: (Int64) -> Void

    /// The closures are the same code every time; only the data decides.
    static func == (a: MonthGridView, b: MonthGridView) -> Bool {
        a.month == b.month && a.selected == b.selected
    }

    var body: some View {
        VStack(spacing: CalGrid.rowGap) {
            ForEach(0..<6, id: \.self) { week in
                HStack(spacing: CalGrid.rowGap) {
                    ForEach(0..<7, id: \.self) { col in
                        cell(month.cells[week * 7 + col])
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
    private func cell(_ c: CalCell) -> some View {
        let isSelected = c.day == selected
        return VStack(spacing: 3) {
            Text("\(c.number)")
                .font(
                    .system(size: LivType.body, weight: c.isToday ? .semibold : .regular)
                        .monospacedDigit()
                )
                .foregroundStyle(
                    isSelected
                        ? LivTheme.onAccent
                        : c.inMonth ? LivTheme.text : LivTheme.muted)
            HStack(spacing: 2.5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(
                            i < c.dots.count
                                ? (isSelected ? LivTheme.onAccent : c.dots[i])
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
                    c.isToday && !isSelected ? LivTheme.accent : Color.clear,
                    lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect(c.day) }
        .onLongPressGesture(minimumDuration: 0.45) { onHold(c.day) }
        .accessibilityLabel(Civil.dayLabel(c.day))
        .accessibilityValue(c.count == 0 ? "" : "\(c.count) items")
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
    // Day arithmetic across boundaries — rescued from the tab suite
    // when tabs were deleted (2026-08-18). `Civil.daysBetween` still has
    // a live caller (Today.swift's "N days into a span"), and it is the
    // kind of hand-rolled maths that breaks at a month edge. It takes
    // DAY numbers, not stamps.
    let anchor = Civil.todayDay()
    func days(_ label: String, _ got: Int, _ want: Int) {
        if got != want { failures.append("FAIL \(label) got \(got) want \(want)") }
    }
    days("0 days", Civil.daysBetween(anchor, anchor), 0)
    days("1 day", Civil.daysBetween(Civil.addDays(anchor, -1), anchor), 1)
    days("21 days", Civil.daysBetween(Civil.addDays(anchor, -21), anchor), 21)
    days("40 days, across months", Civil.daysBetween(Civil.addDays(anchor, -40), anchor), 40)
    days("400 days, across a year", Civil.daysBetween(Civil.addDays(anchor, -400), anchor), 400)
    days("forwards is negative", Civil.daysBetween(Civil.addDays(anchor, 5), anchor), -5)

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

    // The month grid's DATA, which is what keeps a sideways drag cheap:
    // the cells are decided before they are drawn, so the grid can be
    // Equatable and SwiftUI can skip all 126 of them while only an
    // offset moves (owner, 2026-08-15: "minicalendar lags when
    // dragged"). Measured that day: 12,348 cell builds per drag before,
    // 0 after. These pin the shape the skip depends on.
    // Packed civil DAYS here (YYYYMMDD), not stamps — Civil.todayDay's
    // vocabulary, which the grid speaks.
    let august = CalGrid.firstOfMonth(2_026_08_15)
    let empty = calMonth(august, today: 2_026_08_15, byDay: [:])
    check("a month is six weeks", empty.cells.count == 42, "\(empty.cells.count)")
    check(
        "August has 31 days in the month",
        empty.cells.filter(\.inMonth).count == 31,
        "\(empty.cells.filter(\.inMonth).count)")
    check("an empty month has no dots", empty.cells.allSatisfy { $0.dots.isEmpty })
    check(
        "the same month twice is equal — this is the skip",
        calMonth(august, today: 2_026_08_15, byDay: [:]) == empty)
    check(
        "a different month is not equal",
        calMonth(CalGrid.addMonths(august, 1), today: 2_026_08_15, byDay: [:]) != empty)

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
    /// `where` is in WINDOW space, for anything positioned against the
    /// screen rather than against the grid's own scrolled content — the
    /// trash zone is.
    let onMove: (UInt64, CGFloat, CGPoint) -> Void
    let onDrop: (UInt64, CGFloat, CGPoint) -> Void
    let onCancel: () -> Void
    /// The same press, landing on EMPTY grid: a box is placed at that
    /// minute, dragged while the finger is down, and written on release
    /// (owner, 2026-08-14). `nil` minutes on drop = the press was
    /// cancelled.
    let onPlace: (Int) -> Void
    let onPlaceMove: (Int) -> Void
    let onPlaceDrop: (Int) -> Void

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
        context.coordinator.onPlace = onPlace
        context.coordinator.onPlaceMove = onPlaceMove
        context.coordinator.onPlaceDrop = onPlaceDrop
        host.attachIfNeeded()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var targets: [Target] = []
        var onLift: (UInt64) -> Void = { _ in }
        var onMove: (UInt64, CGFloat, CGPoint) -> Void = { _, _, _ in }
        var onDrop: (UInt64, CGFloat, CGPoint) -> Void = { _, _, _ in }
        var onCancel: () -> Void = {}
        var onPlace: (Int) -> Void = { _ in }
        var onPlaceMove: (Int) -> Void = { _ in }
        var onPlaceDrop: (Int) -> Void = { _ in }

        /// The view whose coordinate space the target rects are in (the
        /// grid's content), and the scroll view to suspend mid-lift.
        weak var content: UIView?
        weak var scroll: UIScrollView?

        private var lifted: UInt64?
        private var origin: CGPoint = .zero
        /// The minutes of the box being PLACED, while the finger is down
        /// on empty grid.
        private var placing: Int?

        /// Where the finger is, in the SAME space the rects were computed
        /// in — the grid's content view, not the window.
        private func point(_ g: UIGestureRecognizer) -> CGPoint? {
            guard let content else { return nil }
            return g.location(in: content)
        }

        /// The press begins anywhere on the VISIBLE grid — on a block to
        /// lift it, on empty space to place a new one.
        ///
        /// The visible test is not optional. This recognizer lives on the
        /// WINDOW (see the host), so it is offered every touch in the
        /// app; converting a touch on the month grid — or on a sheet over
        /// the calendar — into the scrolled content's coordinates lands
        /// it at some positive y deep inside a 24-hour column, where it
        /// would silently start placing a box. `scroll.bounds` IS the
        /// visible window into that content, so this is the one line that
        /// keeps the gesture inside the grid it belongs to.
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let p = point(g), let scroll else { return false }
            guard scroll.bounds.contains(g.location(in: scroll)) else { return false }
            return targets.contains { $0.rect.contains(p) } || true
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
                guard let p = point(press) else {
                    press.state = .failed
                    return
                }
                origin = p
                // The scroll must not compete while anything is in the air.
                scroll?.isScrollEnabled = false
                if let hit = targets.first(where: { $0.rect.contains(p) }) {
                    lifted = hit.id
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    onLift(hit.id)
                } else {
                    let minutes = Self.minutes(at: p.y)
                    placing = minutes
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                    onPlace(minutes)
                }
            case .changed:
                guard let p = point(press) else { return }
                if let id = lifted {
                    onMove(id, p.y - origin.y, press.location(in: nil))
                } else if placing != nil {
                    let minutes = Self.minutes(at: p.y)
                    placing = minutes
                    onPlaceMove(minutes)
                }
            case .ended:
                let id = lifted
                let placed = placing
                let dy = point(press).map { $0.y - origin.y }
                let where_ = press.location(in: nil)
                release()
                if let id, let dy {
                    onDrop(id, dy, where_)
                } else if let placed {
                    onPlaceDrop(placed)
                }
            case .cancelled, .failed:
                let had = lifted != nil || placing != nil
                release()
                if had { onCancel() }
            default:
                break
            }
        }

        private func release() {
            scroll?.isScrollEnabled = true
            lifted = nil
            placing = nil
        }

        /// The grid DRAWS per hour; a press LANDS on the quarter hour —
        /// the same 15-minute step the tap and the block drag use.
        static func minutes(at y: CGFloat) -> Int {
            let unit = CalClock.hourHeight / 60
            return max(0, min(24 * 60 - 60, CalClock.snap(Int(y / unit))))
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
