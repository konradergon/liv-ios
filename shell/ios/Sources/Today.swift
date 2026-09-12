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

    /// The task status vocabulary, board order; `completes` drives the
    /// ring, the LATE predicate and the done-collapse.
    @State private var taskOptions: [StatusOption] = []
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
        let now = Civil.nowStamp()
        let doneNames = Set(
            taskOptions.filter { $0.completes == true }.compactMap(\.name))
        let all = agenda(for: selectedDay)
        let allDay = all.filter(\.allDay)
        let timedOpen = all.filter { !$0.allDay && !livIsDone($0.row, doneNames) }
        let done = all.filter { !$0.allDay && livIsDone($0.row, doneNames) }
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
                header(
                    today: today,
                    rows: late + timedOpen.map(\.row) + allDay.map(\.row))
                TodayDateStrip(selected: dayBinding, today: today)
                    .padding(.vertical, 6)

                if !late.isEmpty {
                    let open = lateOpen ?? (late.count <= Self.lateOpenByDefault)
                    lateHeader(late.count, open: open)
                    if open {
                        ForEach(Array(late.enumerated()), id: \.element.id) { i, row in
                            lateLine(
                                row, today: today, doneNames: doneNames,
                                prev: i == 0 ? nil : late[i - 1])
                        }
                    }
                }

                if !allDay.isEmpty {
                    SectionLabel("All-day")
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
                // WHAT NEXT (BP-8's widget of that name, on the one
                // surface a phone has room for it): open tasks with NO
                // date. The timeline above answers "when"; this answers
                // "what", which is the object-based ordering the owner
                // asked for — and without it an undated commitment is
                // invisible until you go looking for it in Tasks.
                if onToday, !nextUp.isEmpty {
                    SectionLabel("What next")
                    ForEach(nextUp) { row in
                        nextLine(row)
                    }
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
        // The bar's create key inherits the day you are looking at.
        .onAppear { desk.contextDay = selectedDay }
        .onChange(of: selectedDay) { _, day in desk.contextDay = day }
        .onDisappear { desk.contextDay = nil }
    }

    // MARK: header + section furniture

    /// The DATE, not the view's name (owner, 2026-08-18: the name is on
    /// the bar; what this line is for is which day you are looking at).
    /// The "N left" count went with it — the list under it is the count.
    private func header(today: Int64, rows: [EntityRow]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                // THE SCREEN'S NAME, at the size the references give one.
                // Todoist's "Inbox" and Notion Calendar's "August" both lead
                // with a large bold left-aligned title and a lot of air
                // above it; ours was `title` (20) semibold, which read as a
                // section heading rather than as the name of where you are.
                LivScreenTitle(Civil.dayLabel(today))
                if box.busyRetrying { LivBusy() }
                Spacer(minLength: 0)
            }
            areaLine(rows)
        }
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    /// THE LINE ONLY LIV CAN PRINT: the day counted by AREA OF LIFE —
    /// "Work 3 · Home 1 · 2 unfiled" (2026-09-06, direction A). No other
    /// app ships with areas, so no other app can say this at the top of
    /// its first screen; it is the product page's "arrives already
    /// organised" made visible, and the unfiled count is the honest tail
    /// of it.
    ///
    /// It draws only when the day holds something. It is NOT the "N left"
    /// count the owner cut from this spot on 2026-08-18 — that said how
    /// many, this says where — but it is small text in the same place,
    /// and it is the easiest line here to cut if it grates.
    ///
    /// The numbers ANIMATE when the day changes: `numericText` rolls the
    /// digits rather than swapping them, the app's first use of it.
    @ViewBuilder private func areaLine(_ rows: [EntityRow]) -> some View {
        let counts = livAreaCounts(rows)
        if !rows.isEmpty {
            HStack(spacing: 8) {
                ForEach(Array(counts.named.enumerated()), id: \.offset) { i, pair in
                    if i > 0 { Text("·").foregroundStyle(LivTheme.text3) }
                    Text("\(pair.name) \(pair.count)")
                        .contentTransition(.numericText())
                }
                if counts.unfiled > 0 {
                    if !counts.named.isEmpty { Text("·").foregroundStyle(LivTheme.text3) }
                    Text("\(counts.unfiled) unfiled")
                        .foregroundStyle(LivTheme.text3)
                        .contentTransition(.numericText())
                }
            }
            .font(.system(size: LivType.label).monospacedDigit())
            .foregroundStyle(LivTheme.text2)
            .lineLimit(1)
            .animation(LivMotion.list, value: counts.key)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    /// LATE means only what can still be DONE: incomplete tasks whose day
    /// has passed (owner ruling, phase 5). A past event is not late — it
    /// happened.
    ///
    /// The header FOLDS the pile. It stays red and keeps its count, so
    /// nothing is hidden — the number is the honest headline, and the
    /// rows behind it are one tap away. This is the same collapse the
    /// done-today row already uses on this screen (standing rule 4).
    private func lateHeader(_ count: Int, open: Bool) -> some View {
        Button {
            park(lateOpen: .some(!open))
        } label: {
            // A HEADING, NOT AN ALARM (polish pass, 2026-08-30).
            //
            // It was a red dot, then the word LATE in red bold kerned
            // caps, then the count — three devices, and the dot said in
            // a circle what the word beside it already said in letters.
            // Being late is information, and information is what the
            // other headings on this screen are: same size, same weight,
            // same ink. The count is the honest headline and it stays.
            HStack(spacing: 7) {
                Text("Late")
                    .font(.system(size: LivType.label, weight: .medium))
                    .foregroundStyle(LivTheme.text2)
                Text("\(count)")
                    .font(.system(size: LivType.label).monospacedDigit())
                    .foregroundStyle(LivTheme.text3)
                Spacer()
                Image(systemName: open ? "chevron.up" : "chevron.down")
                    .font(.system(size: LivType.caption, weight: .semibold))
                    .foregroundStyle(LivTheme.text3)
            }
            .frame(minHeight: LivRow.band)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 14).padding(.bottom, 2)
        .accessibilityLabel("\(count) late task\(count == 1 ? "" : "s")")
        .accessibilityHint(open ? "Hides the list" : "Shows the list")
    }

    /// WHERE NOW IS. A hairline and a time, both in the accent — not a
    /// filled red capsule and a 1.5pt red rule. It marks a position on a
    /// list; it is not a warning, and red is the only word this app's
    /// palette has for one.
    private func nowLine(_ now: Int64) -> some View {
        HStack(spacing: 8) {
            // ONE CLOCK, ONE SIZE. This read 14 while `timedLine`'s
            // time — the same string, in a 52pt column of the same
            // width, twelve lines away — read 16.
            Text(Civil.timeString(now))
                .font(.system(size: LivType.label).monospacedDigit())
                .foregroundStyle(LivTheme.accent)
                .frame(width: 52, alignment: .leading)
            Rectangle().fill(LivTheme.accent).frame(height: 1)
        }
        // 22, because a 16pt line box is 19.1 and 20 left it 0.9pt.
        .frame(height: 22)
        .accessibilityHidden(true)
    }

    private func doneCollapse(_ count: Int) -> some View {
        Button {
            park(doneExpanded: !doneExpanded)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: doneExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: LivType.micro, weight: .semibold))
                Text("\(count) done today")
                    .font(.system(size: LivType.body).monospacedDigit())
                Spacer()
            }
            .foregroundStyle(LivTheme.text2)
            .frame(minHeight: LivRow.band)
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
            .frame(minHeight: LivRow.band)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    // MARK: rows — a tap opens the entity as a Desk tab

    /// A late task: ring, title, the day it was due (red), and one-tap
    /// Today. Swipe: Tomorrow / Pick (the arbitrary date-and-time door).
    private func lateLine(
        _ row: EntityRow, today: Int64, doneNames: Set<String>, prev: EntityRow?
    ) -> some View {
        let dayOf: (EntityRow) -> String = {
            Civil.dayLabel(Civil.day(of: $0.due ?? 0))
        }
        return HStack(spacing: 8) {
            StatusRing(done: false) { toggleStatus(row.id) }
            Text(displayTitle(row))
                .font(.system(size: LivType.strong))
                .foregroundStyle(LivTheme.text)
                .lineLimit(1)
            Spacer(minLength: 6)
            // QUIET, because the heading above already said it. This
            // was red on every row, and with 42 late tasks that is a
            // column of red running the length of the screen — the same
            // thing Tasks was doing until 2026-08-30, and the same fix:
            // a colour that appears on every row distinguishes nothing.
            // "Late 42" carries it once; the date says HOW late, which
            // is the part that differs per row and reads fine in ink.
            // Only when it changes: fourteen late rows all reading
            // "Sun 30 Aug" is one fact printed fourteen times.
            LivRowFact(text: livNewFact(dayOf(row), after: prev.map(dayOf)) ?? "")
            // THE RESCHEDULE VERBS ARE ALL IN ONE PLACE NOW.
            //
            // "Today" was a visible accent word on every late row, while
            // "Move to tomorrow" and "Pick a day" lived on the row's
            // swipe — two doors to one room, which is the thing standing
            // rule 4 exists to stop. It also meant a column of 42 accent
            // words down the screen: measured 2026-08-31, this surface
            // was back to 0.96% saturated pixels with the Late list open,
            // against the reference set's 0.01–0.58%, and the verb was
            // the whole of it.
            //
            // All three are on the leading swipe together (see
            // `rescheduleSwipe`), which is where iOS puts a row's verbs
            // and where this row already had two of them. The row itself
            // is now a name, a date and a tick.
        }
        .frame(minHeight: LivRow.height)
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
        let done = livIsDone(row, doneNames)
        let chips = contextChips(row)
        return HStack(spacing: 8) {
            Text(Civil.timeString(item.stamp))
                .font(.system(size: LivType.label).monospacedDigit())
                .foregroundStyle(dimmed ? LivTheme.text2 : LivTheme.text3)
                // Wide enough for "09:00" at the platform's body size —
                // it was cut for 15pt type and wrapped to two lines the
                // moment the scale grew (2026-08-18).
                .frame(width: 52, alignment: .leading)
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
                    .font(.system(size: LivType.strong))
                    .foregroundStyle(
                        dimmed || done ? LivTheme.text2 : LivTheme.text)
                    .lineLimit(1)
                if !chips.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(chips, id: \.self) { ValueChip($0) }
                    }
                }
            }
            Spacer(minLength: 6)
        }
        .frame(minHeight: LivRow.height)
        // NEXT IS A MARK, NOT A BAND. This row wore an edge-to-edge
        // accent-tinted background with square corners — the largest
        // coloured area on the screen, to say one row is the next one.
        // A 2pt rule in the leading margin says it in the space the
        // layout already leaves empty.
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(next ? LivTheme.accent : Color.clear)
                .frame(width: 2)
                // IN THE MARGIN, not in the row. Drawn at the row's own
                // leading edge it landed on the first digit of the time.
                .offset(x: -10)
        }
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
                                done: livIsDone(item.row, doneNames), compact: true
                            ) {
                                toggleStatus(item.row.id)
                            }
                        }
                        Button {
                            desk.open(item.row.id)
                        } label: {
                            Text(displayTitle(item.row))
                                .font(.system(size: LivType.strong))
                                .foregroundStyle(
                                    livIsDone(item.row, doneNames)
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
            reschedule(row, toDay: Civil.todayDay())
        } label: {
            Label("Move to today", systemImage: "arrow.turn.up.left")
        }
        .tint(LivTheme.accent)
        Button {
            reschedule(row, toDay: Civil.addDays(Civil.todayDay(), 1))
        } label: {
            Label("Move to tomorrow", systemImage: "arrow.turn.up.right")
        }
        // ONE TINT: all three are "move this to a different day". See
        // the same change in Tasks' tray.
        .tint(LivTheme.accent)
        Button {
            duePick = TodayDuePick(entity: row.id)
        } label: {
            Label("Pick a day", systemImage: "calendar")
        }
        .tint(LivTheme.accent)
    }

    // MARK: snapshot slices

    /// The lens (M4) + the archived filter Today always lacked (recon,
    /// phase 5 — Tasks and Everything both had it).
    private var datedRows: [EntityRow] {
        return (box.snap?.dated ?? []).compactMap { box.entity($0) }
            .filter {
                $0.trashed != true && $0.archived != true && workspaces.admits($0)
            }
    }

    /// Open, UNDATED tasks — what you have taken on that no clock is
    /// carrying. Capped: this is a nudge under the day, not a second
    /// Tasks screen, and the state key is one tap from the whole list.
    private var nextUp: [EntityRow] {
        // No `lensOn` guard any more: `admits` returns true when there is
        // no lens, so the two readings collapse into one. `isInert` was the
        // Swift parser's idea that a query it could not read filters
        // nothing — the core has no such notion, and a typo now shows
        // nothing rather than everything (owner, 2026-08-27).
        return (box.snap?.everything ?? [])
            .compactMap { box.entity($0) }
            .filter { row in
                row.trashed != true && row.archived != true
                    && livCanTick(row)
                    && (row.due ?? 0) == 0
                    && !isDoneStatus(row)
                    && workspaces.admits(row)
            }
            .sorted { ($0.recency ?? 0, $0.id) > ($1.recency ?? 0, $1.id) }
            .prefix(5)
            .map { $0 }
    }

    /// A status that closes the thing. The vocabulary is the box's, so
    /// this asks the option list rather than guessing at words.
    private func isDoneStatus(_ row: EntityRow) -> Bool {
        guard let status = row.status, !status.isEmpty else { return false }
        return taskOptions.first { $0.name == status }?.completes == true
    }

    /// One what-next row: the ring, the name, and the anchor it belongs
    /// to. No date — that is the whole point of the band.
    private func nextLine(_ row: EntityRow) -> some View {
        HStack(spacing: 8) {
            StatusRing(done: false) { toggleStatus(row.id) }
            Text(displayTitle(row))
                .font(.system(size: LivType.strong))
                .foregroundStyle(LivTheme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            // The ANCHOR, never the status: every row in this band is
            // open, so a column of "todo" chips says nothing (BP-6's
            // rule — the section carries the status, the chip carries
            // what the thing is attached to).
            if let chip = livAnchorChip(of: row) {
                chip.transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .frame(minHeight: LivRow.height)
        .contentShape(Rectangle())
        .onTapGesture { desk.open(row.id) }
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        // "MOVE TO TODAY", NOT "TODAY".
        //
        // A swipe verb labelled with a bare day name is ambiguous the
        // moment the app also has a VIEW called Today — and SwiftUI puts
        // swipe actions in the accessibility tree whether or not they are
        // revealed, so this screen carried six hidden buttons labelled
        // "Today" while the library's own Today row was on screen behind
        // the panel. Anything tapping by label got the wrong one, which
        // is how `drive.sh tour` started failing on 2026-08-31: a real
        // ambiguity that nothing had stood in the right place to notice.
        // It reads better for VoiceOver too — a verb should say what it
        // does, not name a day and leave the rest implied.
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button("Move to today") { reschedule(row, toDay: Civil.todayDay()) }
                .tint(LivTheme.accent)
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
        for occ in box.snap?.occurrences ?? [] {
            guard let series = occ.series, let civil = occ.civil,
                Civil.day(of: civil) == day, !dayIds.contains(series),
                let row = box.entity(series), row.trashed != true,
                row.archived != true, workspaces.admits(row)
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
            return Civil.day(of: due) < today && !livIsDone(row, doneNames)
        }
        .sorted { ($0.due ?? 0) > ($1.due ?? 0) }
    }

    private func capturedTodayCount(today: Int64) -> Int {
        return (box.snap?.unstructured ?? []).compactMap { box.entity($0) }
            .filter { row in
                guard row.trashed != true, let created = row.created else {
                    return false
                }
                return Civil.day(of: created) == today && workspaces.admits(row)
            }
            .count
    }

    // MARK: predicates + acts



    private func displayTitle(_ row: EntityRow) -> String { livRowTitle(row) }

    /// Context, never the row's own type: the type cell is a reference
    /// too, and it is the FIRST cell written — so the naive "first ref"
    /// chip read "task" on every task (recon, phase 5).
    /// WHAT A ROW IS ATTACHED TO — an area, a project, a person. Never
    /// its status.
    ///
    /// `status` was passing this filter because a select option is an
    /// entity like any other, so it has a reference target. The result
    /// was a "todo" chip under every open task on the screen: a column
    /// of identical grey pills saying what the ring beside them already
    /// says, under a heading that already scopes them. `nextLine` has
    /// refused to draw one since BP-6 and said why in a comment; this is
    /// the same rule, applied where it was being broken.
    private func contextChips(_ row: EntityRow) -> [String] {
        var out: [String] = []
        for cell in row.cells ?? [] {
            guard cell.property != "type", cell.property != "status",
                cell.refTarget != nil,
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
        let target = livIsDone(row, doneNames)
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
        // Only a PARKED day can go stale. With no tab there is nothing to
        // snap forward, and parking here would mint a tab on every launch
        // for someone who never asked for one.
        if desk.position(.today) != nil, selectedDay < today { park(day: today) }
        box.refreshWindow(
            from: Civil.stamp(day: Civil.addDays(today, -1), hhmm: 0),
            to: Civil.stamp(day: Civil.addDays(today, 7), hhmm: 2359))
    }
}

// MARK: - the 7-day strip

/// Seven days, each marked by `LivDayMark`: the selected day wears an
/// ink disc with its number knocked out, today wears the accent — and
/// when today IS the selected day, an accent disc says both at once.
///
/// (This read "Today ringed accent, the selected day filled; both =
/// filled wins" until 2026-09-07. Nothing has been ringed since rev 47
/// replaced the ring and the 2pt rule with the disc, and "filled wins"
/// described a collision the disc does not have.)
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
                    withAnimation(LivMotion.pick) { selected = day }
                } label: {
                    // A DISC, NOT A DOT AND A RULE (owner, 2026-09-07:
                    // "today's date is marked by a tiny dot that is
                    // completely hidden by a horizontal bar when
                    // selected. You have a tendency to make UI elements
                    // tiny and subtle. Try to go for the opposite.")
                    //
                    // The bug was literal: today wore a 4pt dot at the
                    // foot of the tile and the selected day wore a 2pt
                    // rule across the foot of the same tile, so selecting
                    // today drew the rule straight over the dot and the
                    // day you were on stopped being marked at all.
                    //
                    // What it replaces, and why that went: on 2026-08-30
                    // the selected day was a solid accent block 44pt tall
                    // which, with today's accent stroke beside it, made
                    // the strip the loudest thing in the app (Today
                    // measured 1.05% saturated pixels against Todoist's
                    // 0.58%). The answer then was to shrink both marks to
                    // almost nothing. The answer now is one mark that is
                    // unmistakable and still small in AREA: a 36pt disc
                    // behind the number is about 0.3% of the screen, a
                    // sixth of that block.
                    //
                    // One mark, three readings, no collision possible:
                    //   selected            — ink disc, number knocked out
                    //   today, selected     — ACCENT disc, number knocked out
                    //   today, not selected — accent number, no disc
                    // The MARK is `LivDayMark` (Kit.swift) since
                    // 2026-09-07 — this tile keeps only what is its own,
                    // the weekday letter. The calendar's month grid draws
                    // the same mark at its own diameter, so the app has
                    // one answer to "which day am I on" instead of two.
                    VStack(spacing: 4) {
                        Text(Civil.weekdayLetter(day))
                            .font(.system(size: LivType.label))
                            .foregroundStyle(isSelected ? LivTheme.text2 : LivTheme.text3)
                        LivDayMark(
                            number: Civil.dayNumber(day),
                            selected: isSelected,
                            today: isToday,
                            diameter: LivDay.disc)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: LivDay.strip)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// THE DAY BY AREA. Pure, so the cost check and the self-check can hold
/// it: one pass over the rows, counting each area cell, and the rows
/// with none as `unfiled`. Areas come out in the order the app ships
/// them, then any minted ones by name — so "Work" is always first when
/// present and the line does not shuffle as counts change.
struct LivAreaCounts: Equatable {
    var named: [(name: String, count: Int)] = []
    var unfiled = 0
    /// One value that changes whenever the line's words would, for the
    /// animation to key on.
    var key: String { named.map { "\($0.name)\($0.count)" }.joined() + "u\(unfiled)" }

    static func == (a: LivAreaCounts, b: LivAreaCounts) -> Bool { a.key == b.key }
}

func livAreaCounts(_ rows: [EntityRow]) -> LivAreaCounts {
    var tally: [String: Int] = [:]
    var out = LivAreaCounts()
    for row in rows {
        let area = (row.cells ?? []).first { $0.property == "area" }?.value ?? ""
        if area.isEmpty { out.unfiled += 1 } else { tally[area, default: 0] += 1 }
    }
    let shipped = LivArea.allCases.map(\.name)
    let ordered = shipped.filter { tally[$0] != nil }
        + tally.keys.filter { !shipped.contains($0) }.sorted()
    out.named = ordered.map { ($0, tally[$0] ?? 0) }
    return out
}
