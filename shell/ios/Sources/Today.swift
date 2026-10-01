// liv iOS — Today (design/ios.md §6; rebuilt phase 5, owner-approved
// mockup 2026-08-05; the clearer boards 2026-09-24). Today answers "WHAT
// NOW?": what is late, what is happening, what is left. One column — the
// name over the date, the 7-day strip, the Late card (folds), the day as
// one now-aware Schedule card, a "N done today" fold, What next, and one
// honest captured line that goes to Unsorted. The screen is
// `liv_view_today`'s answer (`BoxModel.today`), and every rule behind it
// lives in `surface/src/today.rs`; the strip picks a day out of it. A row
// tap opens the entity as a Desk tab — no navigation stack here.

import SwiftUI

/// One row of the schedule card, and whether its time has passed.
private struct TodaySlot: Identifiable {
    let row: EntityRow
    let passed: Bool

    var id: LivEntityID { row.id }
}

/// WHERE THE NOW-LINE TOUCHES A ROW: it lies on the boundary between the
/// last passed row and the next, taking no height of its own (the clearer
/// board), so each of the two draws its own half.
private enum TodayNowEdge { case none, bottom, top }

/// The row whose exact date and time is being picked (sheet item) — the
/// arbitrary-time door is everywhere a date can be set (owner, phase 5).
private struct TodayDuePick: Identifiable {
    let entity: LivEntityID
    var id: LivEntityID { entity }
}

// MARK: - the screen

struct TodayView: View {
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var workspaces: WorkspaceModel
    @Environment(\.scenePhase) private var scenePhase

    /// The task status vocabulary, board order: which option a ring tap
    /// writes.
    @State private var taskOptions: [StatusOption] = []
    /// The row a swipe has lifted out of its card (`livSwipeLift`).
    @State private var lifted: AnyHashable?
    @State private var duePick: TodayDuePick?

    /// WHERE YOU ARE in this view: the day, and the two piles you have
    /// opened. Not `@State` since 2026-08-22 — it is what a Today tab
    /// HOLDS (design/tabs.md, Reading B), so it lives in the plane and
    /// comes back with it. With no tab, `pos` is today with both piles
    /// at their defaults, which is what this screen always did.
    private var pos: TodayPosition { TodayPosition(token: desk.position(.today)) }
    private var selectedDay: Int64 { pos.day }
    private var doneExpanded: Bool { pos.doneExpanded }
    private var lateOpen: Bool? { pos.lateOpen }

    private func park(day: Int64? = nil, doneExpanded: Bool? = nil, lateOpen: Bool?? = nil) {
        let next = TodayPosition(
            day: day ?? pos.day,
            doneExpanded: doneExpanded ?? pos.doneExpanded,
            lateOpen: lateOpen ?? pos.lateOpen)
        desk.park(.today, at: next.token)
    }

    /// The strip writes through the plane, so moving the day IS parking.
    private var dayBinding: Binding<Int64> {
        Binding(get: { pos.day }, set: { park(day: $0) })
    }

    /// A few late tasks are worth seeing; a pile of them is a wall.
    /// Owner, 2026-08-18: *"so much LATE stuff i can't see what's for
    /// today"* — thirteen rows at 44pt is 570pt of screen, which is the
    /// whole phone, so the day itself started below the fold. Above this
    /// many, the pile arrives folded and the day is the first thing you
    /// see.
    private static let lateOpenByDefault = 3

    var body: some View {
        let today = Civil.todayDay()
        let answer = box.today
        let day = answer?.day(selectedDay)
        let allDay = day?.allDay ?? []
        // The timeline knows the time (today only): what passed dims, and
        // the now-line stands between it and what is still to come.
        let passed = day?.passed ?? []
        let ahead = day?.ahead ?? []
        let done = day?.done ?? []
        let late = answer?.late ?? []
        let onToday = selectedDay == today
        // THE SCHEDULE IS ONE CARD (the clearer board): all-day rows first,
        // then the day by clock. The all-day pill band went into it.
        let schedule: [TodaySlot] =
            allDay.map { TodaySlot(row: $0, passed: false) }
            + passed.map { TodaySlot(row: $0, passed: true) }
            + ahead.map { TodaySlot(row: $0, passed: false) }
        // The line only divides: something must stand above it and
        // something must still be to come. It falls above the first row
        // still ahead.
        let nowAt: Int? =
            onToday && !ahead.isEmpty && !(allDay.isEmpty && passed.isEmpty)
            ? allDay.count + passed.count : nil

        List {
            Group {
                header(today: today, day: day)
                    .listRowInsets(LivRow.fullWidth)
                TodayDateStrip(
                    selected: dayBinding, today: today,
                    busy: Set((answer?.days ?? []).filter { !$0.isEmpty }.compactMap(\.day)))
                    .listRowInsets(LivRow.fullWidth)

                if !late.isEmpty {
                    let open = lateOpen ?? (late.count <= Self.lateOpenByDefault)
                    lateHeader(late.count, open: open)
                    if open {
                        ForEach(livCardSlots(late)) { s in
                            lateLine(s.item, today: today, position: s.position)
                        }
                    }
                }

                if schedule.isEmpty && done.isEmpty {
                    EmptyHint("Nothing scheduled")
                } else if !schedule.isEmpty {
                    // A HEADING FOR THE DAY (the clearer board, 2026-09-24),
                    // reversing 2026-08-18's "no day heading here": with
                    // Late above it in its own card, the day needs a name
                    // to be told from the pile.
                    SectionLabel("Schedule", first: late.isEmpty)
                    ForEach(livCardSlots(schedule)) { s in
                        scheduleSlot(
                            s.item, position: s.position,
                            now: s.index + 1 == nowAt ? .bottom : (s.index == nowAt ? .top : .none))
                    }
                }
                if !done.isEmpty {
                    doneFold(done)
                }
                // WHAT NEXT (BP-8's widget of that name, on the one
                // surface a phone has room for it): open tasks with NO
                // date. The schedule answers "when"; this answers "what" —
                // without it an undated commitment is invisible until you
                // go looking for it in Tasks.
                if onToday, let next = answer?.whatNext, !next.isEmpty {
                    SectionLabel("What next")
                    ForEach(livCardSlots(next)) { s in
                        nextLine(s.item, position: s.position)
                    }
                }
                if let captured = answer?.captured, captured > 0 {
                    capturedFooter(captured)
                }
            }
            .listRowInsets(
                EdgeInsets()
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            LivCardListEnd()
        }
        .livCardList()
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 10)
        // Room under the last row for the add button to sit over.
        .contentMargins(.bottom, LivBar.listRoom, for: .scrollContent)
        .livHidesChrome()
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
        .onChange(of: workspaces.lensIds) { _, _ in loadWindow() }
        // The bar's create key inherits the day you are looking at.
        .onAppear { desk.contextDay = selectedDay }
        .onChange(of: selectedDay) { _, day in desk.contextDay = day }
        .onDisappear { desk.contextDay = nil }
    }

    // MARK: header + section furniture

    /// TODAY BY NAME — "Thursday." — over its date and the day counted by
    /// area (the clearer board). The title is always TODAY; the strip
    /// below chooses which day the list shows.
    private func header(today: Int64, day: LivTodayDay?) -> some View {
        LivTitleBlock(Civil.weekdayName(today)) {
            areaLine(today: today, day)
        } accessory: {
            if box.busyRetrying { LivBusy() }
        }
    }

    /// THE LINE ONLY LIV CAN PRINT: the date, then the day counted by AREA
    /// OF LIFE — "24 September · Home 1 · Work 3 · 2 unfiled" (2026-09-06,
    /// direction A; the date joined it on the clearer board). No other app
    /// ships with areas, so no other app can say this under its first
    /// screen's name; the unfiled count is the honest tail of it.
    ///
    /// ONE RUN, as the board draws it, and it CHANGES IN ONE FRAME. The
    /// numbers used to roll (`numericText`), so opening Today drew the date
    /// and then blurred " · Home 5" in beside it a beat later (owner,
    /// 2026-09-29: "a weird thing very briefly appearing/disappearing on the
    /// low right" of the title).
    private func areaLine(today: Int64, _ day: LivTodayDay?) -> some View {
        var parts = [Civil.dateLong(today)]
        parts += (day?.areas ?? []).map { "\($0.name ?? "") \($0.count ?? 0)" }
        if let unfiled = day?.unfiled, unfiled > 0 { parts.append("\(unfiled) unfiled") }
        return Text(parts.joined(separator: " · "))
    }

    /// LATE means only what can still be DONE: incomplete tasks whose day
    /// has passed (owner ruling, phase 5). A past event is not late — it
    /// happened.
    ///
    /// The header FOLDS the pile: the red count at the right says how many
    /// whether it is open or not, and the chevron says which it is. The
    /// whole header is the door.
    private func lateHeader(_ count: Int, open: Bool) -> some View {
        Button {
            park(lateOpen: .some(!open))
        } label: {
            SectionLabel("Late", late: count, fold: open, first: true)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(count) late task\(count == 1 ? "" : "s")")
        .accessibilityHint(open ? "Hides the list" : "Shows the list")
    }

    /// WHAT IS DONE TODAY, folded — a card row like Tasks' Done: the done
    /// box, the words, the count and a chevron. Opened, the done rows
    /// follow in the same card.
    @ViewBuilder private func doneFold(_ done: [EntityRow]) -> some View {
        let open = doneExpanded
        Color.clear.frame(height: LivCards.gap)
        Button {
            livToggleFold { park(doneExpanded: !open) }
        } label: {
            LivCardRow(
                "\(done.count) done today", divided: open,
                lead: {
                    LivCheckbox(done: true)
                        .frame(width: LivCards.mark)
                        .accessibilityHidden(true)
                },
                trailing: { LivChevron(open ? .down : .right) })
        }
        .accessibilityValue(open ? "Open" : "Closed")
        .livFoldRow(open: open)
        if open {
            // `above: 1` — the header is this card's first row.
            ForEach(livCardSlots(done, above: 1)) { s in
                scheduleSlot(
                    TodaySlot(row: s.item, passed: true), position: s.position, now: .none)
            }
        }
    }

    /// One honest line, not a tile that disagrees with its own section:
    /// today's captures, and the door to the place that routes them.
    /// THE COUNT IS PROSE, THE VERB IS A PILL — the pill is the only
    /// button, never the whole line.
    private func capturedFooter(_ count: Int) -> some View {
        HStack(spacing: LivAir.snug) {
            Text("\(count) captured today")
                .font(.system(size: LivType.caption).monospacedDigit())
                .foregroundStyle(LivTheme.text3)
            ConfirmPill("Route them", compact: true) { desk.go(.inbox) }
            Spacer()
        }
        .frame(minHeight: LivRow.band)
        .padding(.top, LivCards.gap)
        .padding(.horizontal, LivTitle.side - LivRow.cardInset)
    }

    // MARK: rows — a tap opens the entity as a Desk tab

    /// A late task: the box, the name over "Due Tuesday · Work", and the
    /// accent "Today" that moves it to today. Swipe: all three reschedule
    /// verbs, as before.
    ///
    /// "TODAY" IS BACK ON THE ROW (the clearer board, 2026-09-24), which
    /// reverses 2026-08-31's move of it onto the swipe alone. It is a real
    /// button, and its accessibility label is "Move to today": a control
    /// labelled bare "Today" beside the library's own Today row is what
    /// broke `drive.sh tour` on 2026-08-31.
    private func lateLine(
        _ row: EntityRow, today: Int64, position: LivCardPosition
    ) -> some View {
        let due = "Due " + Civil.dayWord(Civil.day(of: row.due ?? 0), today: today)
        let detail = ([due] + contextWords(row)).joined(separator: " · ")
        return LivCardRow(
            displayTitle(row), detail: detail, divided: position.divided,
            lead: {
                StatusRing(done: false, name: displayTitle(row)) { toggleStatus(row) }
            },
            trailing: {
                Button {
                    reschedule(row, toDay: today)
                } label: {
                    Text("Today")
                        .font(.system(size: LivType.label, weight: .medium))
                        .foregroundStyle(LivTheme.accent)
                        .frame(minHeight: LivRow.touch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Move to today")
            }
        )
        .onTapGesture { desk.open(row.id) }
        .livSwipeLift(row.id, $lifted)
        .livCardRow(position: position, lifted: livIsLifted(row.id, lifted))
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            rescheduleSwipe(row)
        }
    }

    /// ONE ROW OF THE SCHEDULE CARD, Apple Calendar's shape: the time
    /// column (start, and the end under it when there is one), then a bar
    /// in the kind's colour for anything that cannot be ticked or the box
    /// for a task, then the words. Passed rows read in text2. The now-line
    /// lies on the boundary between the last passed row and the next.
    @ViewBuilder private func scheduleSlot(
        _ slot: TodaySlot, position: LivCardPosition, now: TodayNowEdge
    ) -> some View {
        let passed = slot.passed
        let row = slot.row
        let tick = livCanTick(row)
        let done = row.done == true
        LivCardRow(
            displayTitle(row),
            detail: scheduleDetail(row),
            muted: passed || done,
            // The row directly above the now-line has no hairline: the
            // line is the division there.
            divided: position.divided && now != .bottom,
            rule: LivSchedule.rule,
            lead: {
                HStack(spacing: LivCards.markGap) {
                    timeColumn(row, passed: passed)
                    if tick {
                        StatusRing(
                            done: done, dim: passed, name: displayTitle(row)
                        ) { toggleStatus(row) }
                    } else {
                        // A BAR IN THE KIND'S COLOUR — the one place kind
                        // colour survives on this screen (icons are ink).
                        RoundedRectangle(cornerRadius: LivSchedule.barRadius)
                            .fill(LivKind.color(of: row))
                            .frame(width: LivSchedule.bar)
                            .frame(maxHeight: .infinity)
                            .padding(.vertical, LivSchedule.barInset)
                    }
                }
            },
            trailing: { EmptyView() }
        )
        // HALF THE NOW-LINE EACH, clipped to the row: centred on the
        // boundary, the row above shows its top half and the row below
        // its bottom half, whichever of the two the list paints last.
        .overlay(alignment: now == .top ? .top : .bottom) {
            if now != .none {
                nowLine.offset(y: (now == .top ? -1 : 1) * LivSchedule.nowDot / 2)
            }
        }
        .clipped()
        .onTapGesture { desk.open(row.id) }
        .livSwipeLift(slot.id, $lifted)
        .livCardRow(position: position, lifted: livIsLifted(slot.id, lifted))
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            rescheduleSwipe(row)
        }
    }

    /// The start, or "All day". 50 wide, so the column is one edge.
    private func timeColumn(_ row: EntityRow, passed: Bool) -> some View {
        VStack(alignment: .leading, spacing: LivCards.lineGap) {
            if row.allDay == true {
                Text("All day")
                    .font(.system(size: LivType.label, weight: .medium))
                    .foregroundStyle(LivTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(LivTitle.shrink)
            } else {
                Text(Civil.timeString(row.due ?? 0))
                    .font(.system(size: LivType.label, weight: .medium).monospacedDigit())
                    .foregroundStyle(passed ? LivTheme.text2 : LivTheme.text)
            }
        }
        .frame(width: LivSchedule.timeColumn, alignment: .leading)
    }

    /// WHERE NOW IS: a red dot on the time column's edge, then a red line
    /// to the card's end (the clearer board). No time printed — the
    /// schedule's own times say where it falls. RED, which reverses the
    /// accent it wore while red meant only a warning: on the clearer
    /// boards red means late AND now.
    private var nowLine: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(LivTheme.red)
                .frame(width: LivSchedule.nowDot, height: LivSchedule.nowDot)
            Rectangle()
                .fill(LivTheme.red)
                .frame(height: LivSchedule.nowLine)
        }
        // The dot's centre sits on the time column's trailing edge.
        .padding(.leading, LivCards.padX + LivSchedule.timeColumn - LivSchedule.nowDot / 2)
        .padding(.trailing, LivCards.padX)
        .frame(height: LivSchedule.nowDot)
        .accessibilityHidden(true)
    }

    /// Today, Tomorrow (keeping the span AND the time of day) and Pick,
    /// the real date-and-time editor. (The old swipe wrote end:0 +
    /// dateOnly:true — "Tomorrow" on a two-hour meeting destroyed both,
    /// phase-5 recon.)
    @ViewBuilder private func rescheduleSwipe(_ row: EntityRow) -> some View {
        Button {
            reschedule(row, toDay: Civil.todayDay())
        } label: {
            livSwipeLabel("Move to today", .today)
        }
        .tint(LivTheme.accent)
        Button {
            reschedule(row, toDay: Civil.addDays(Civil.todayDay(), 1))
        } label: {
            livSwipeLabel("Move to tomorrow", .tomorrow)
        }
        // ONE TINT: all three are "move this to a different day".
        .tint(LivTheme.accent)
        Button {
            duePick = TodayDuePick(entity: row.id)
        } label: {
            livSwipeLabel("Pick a day", .calendar)
        }
        .tint(LivTheme.accent)
    }

    // MARK: rows and their words

    /// One what-next row: the box, the name, and the anchor it belongs to
    /// as the second line. No date — that is the whole point of the band.
    private func nextLine(_ row: EntityRow, position: LivCardPosition) -> some View {
        // The ANCHOR, never the status: every row here is open, so a
        // column of "todo" would say nothing (BP-6's rule).
        LivCardRow(
            displayTitle(row), detail: livAnchor(of: withCells(row))?.value,
            divided: position.divided,
            lead: {
                StatusRing(done: false, name: displayTitle(row)) { toggleStatus(row) }
            },
            trailing: { EmptyView() }
        )
        .onTapGesture { desk.open(row.id) }
        .livSwipeLift(row.id, $lifted)
        .livCardRow(position: position, lifted: livIsLifted(row.id, lifted))
        // "MOVE TO TODAY", NOT "TODAY". Swipe actions are in the
        // accessibility tree whether or not they are revealed, and a bare
        // "Today" beside the library's own Today row broke `drive.sh tour`
        // on 2026-08-31. A verb should say what it does.
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                reschedule(row, toDay: Civil.todayDay())
            } label: {
                livSwipeLabel("Move to today", .today)
            }
            .tint(LivTheme.accent)
        }
    }

    // MARK: predicates + acts

    private func displayTitle(_ row: EntityRow) -> String { livRowTitle(row) }

    /// The same row with its cells, which the answer does not carry: the
    /// second line reads them. Asking the model is what fetches them.
    private func withCells(_ row: EntityRow) -> EntityRow {
        box.entity(row.id) ?? row
    }

    /// WHAT A ROW IS ATTACHED TO — its area, project, people, subject —
    /// as plain words for its second line ("Work · Mira"), two at most.
    /// Named properties, not "any reference": type, status and priority
    /// are references too, and "Task · medium" says what the row already
    /// shows or nothing a person asked for.
    private func contextWords(_ row: EntityRow) -> [String] {
        // The area FIRST, from the wire: it is there before the cells are,
        // so a row does not grow from 52 to 64 when they arrive.
        var out: [String] = [row.areaWord].compactMap { $0 }.filter { !$0.isEmpty }
        for property in ["area", "project", "people", "tags"] {
            for cell in withCells(row).cells ?? [] where cell.property == property {
                guard let value = cell.value, !value.isEmpty, !out.contains(value) else { continue }
                out.append(value)
                if out.count == 2 { return out }
            }
        }
        return out
    }

    /// A schedule row's second line: where it is (an event's location),
    /// then what it is attached to.
    private func scheduleDetail(_ row: EntityRow) -> String? {
        let location = (withCells(row).cells ?? []).first { $0.property == "location" }?.value
        let words = [location].compactMap { $0 }.filter { !$0.isEmpty } + contextWords(row)
        return words.isEmpty ? nil : words.joined(separator: " · ")
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
    private func toggleStatus(_ row: EntityRow) {
        let target = row.done == true
            ? taskOptions.first { $0.completes != true }
            : taskOptions.first { $0.completes == true }
        guard let name = target?.name, !name.isEmpty else { return }
        box.set(row.id, "status", name)
    }

    /// Ask for the screen, with the clock as it reads now. Also snaps a
    /// stale selection forward across midnight (the strip starts at today;
    /// a selection behind it would be invisible).
    private func loadWindow() {
        let today = Civil.todayDay()
        // Only a PARKED day can go stale. With no tab there is nothing to
        // snap forward, and parking here would mint a tab on every launch
        // for someone who never asked for one.
        if desk.position(.today) != nil, selectedDay < today { park(day: today) }
        box.watchToday(TodayAsk(lens: workspaces.lensIds))
    }
}

// MARK: - the 7-day strip

/// Seven days, each marked by `LivDayMark`: the selected day wears an
/// ink disc with its number knocked out, today wears the accent — and
/// when today IS the selected day, an accent disc says both at once
/// (owner, 2026-09-07: a disc, not "a tiny dot hidden by a bar"). Under
/// each day that holds something, a small dot — except under the day you
/// are on, whose disc already marks it (the clearer board).
private struct TodayDateStrip: View {
    @Binding var selected: Int64
    let today: Int64
    /// The days that hold something, as days since the epoch.
    let busy: Set<Int32>

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                let day = Civil.addDays(today, i)
                let isSelected = day == selected
                let hasItems = busy.contains(Civil.epochDay(day))
                // The day's list swaps in one frame; only the disc moves
                // (as `LivSegment`, 2026-09-29). Picked inside
                // `withAnimation`, the two days' rows crossfaded over each
                // other, "Nothing scheduled" printed across the old header.
                Button {
                    selected = day
                } label: {
                    VStack(spacing: LivDay.gap) {
                        Text(Civil.weekdayLetter(day))
                            .font(.system(size: LivType.caption, weight: .medium))
                            .foregroundStyle(LivTheme.text2)
                        LivDayMark(
                            number: Civil.dayNumber(day),
                            selected: isSelected,
                            today: day == today,
                            diameter: LivDay.disc)
                        Circle()
                            .fill(hasItems && !isSelected ? LivTheme.text3 : .clear)
                            .frame(width: LivDay.dot, height: LivDay.dot)
                    }
                    .animation(LivMotion.pick, value: isSelected)
                    .frame(maxWidth: .infinity)
                    .frame(height: LivDay.strip)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // The dot, spoken — the way the month's cells say it.
                .accessibilityValue(hasItems ? "has items" : "")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, LivDay.inset)
    }
}
