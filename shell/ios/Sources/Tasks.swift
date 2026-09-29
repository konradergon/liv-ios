// liv iOS — Tasks (design/ios.md §6): a Feature-view lens — status-grouped
// flat list over every task in the box. Groups come from the vocabulary
// (liv_status_options_at, board order); `completes` groups collapse by
// default. Filters are client-side state only — the snapshot is never
// re-queried to filter: a segmented control of statuses, and a Project
// segment that is a menu. Done boxes wear the OPTION's hue (quantized to
// the semantic set). Full snapshot on appear — undated tasks must not
// drop. Tapping a row opens the entity as a Desk tab (desk.open). Rows
// sit on cards under headers (the clearer boards, 2026-09-24).

import SwiftUI
import UIKit

struct TasksView: View {
    @EnvironmentObject var model: BoxModel
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var workspaces: WorkspaceModel

    @State private var options: [StatusOption] = []
    @State private var projects: [String] = []
    /// The row whose "Pick" swipe verb is choosing a date (sheet item).
    @State private var duePick: TasksDuePick?

    /// WHAT IS IN THE ADD ROW. Not a position: a half-typed name is not
    /// a place you can come back to, and parking it would write to
    /// UserDefaults on every keystroke.
    @State private var adding = ""
    /// Guards a double return while the write is in flight, the same
    /// guard the create doors in `DeskHost` carry.
    @State private var addingBusy = false
    @FocusState private var addFocused: Bool
    /// The last add was refused by the box. Drawn on the row itself —
    /// a haptic alone is a message to a thumb, not to a reader.
    @State private var addFailed = false

    /// WHERE YOU ARE in this view: the segment that is on, and the
    /// completes-groups you have unfolded. Not `@State` since 2026-08-22
    /// — it is what a Tasks tab HOLDS (design/tabs.md, Reading B), so it
    /// lives in the plane and comes back with it.
    private var pos: TasksPosition { TasksPosition(token: desk.position(.tasks)) }
    private var filter: TasksPosition.Filter { pos.filter }
    private var expanded: Set<String> { Set(pos.expanded) }

    private func park(filter: TasksPosition.Filter? = nil, expanded: Set<String>? = nil) {
        let next = TasksPosition(
            filter: filter ?? pos.filter,
            expanded: expanded ?? Set(pos.expanded))
        desk.park(.tasks, at: next.token)
    }

    private struct TasksDuePick: Identifiable {
        let entity: LivEntityID
        var id: LivEntityID { entity }
    }

    private struct TasksGroup: Identifiable {
        var id: String { name }
        let name: String
        let completes: Bool
        let hue: Color?
        let isNoStatus: Bool
        var rows: [EntityRow]
    }

    // MARK: body

    var body: some View {
        let groups = visibleGroups()
        List {
            // THE CLEARER BOARD (2026-09-24): the name with its stop and a
            // line saying how much is open, then the filter, then cards.
            LivTitleBlock("Tasks", subtitle: subtitle)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            segmentRow
            gap(LivCards.gap)
            addRow
            if groups.allSatisfy({ $0.rows.isEmpty }) {
                emptyRow
            }
            ForEach(groups) { group in
                if group.completes {
                    foldCard(group)
                } else {
                    groupHeader(group)
                    ForEach(Array(group.rows.enumerated()), id: \.element.id) { i, row in
                        taskRow(
                            row, prev: i == 0 ? nil : group.rows[i - 1],
                            position: .of(i, in: group.rows.count))
                    }
                }
            }
            inNotesSection
        }
        .listStyle(.plain)
        // 10, like Today, Inbox and Everything: every row states its own
        // height (`LivCards.row` / `twoLine`), so the List's floor only
        // has to stay out of the way — and must stay under the 16 gaps.
        .environment(\.defaultMinListRowHeight, 10)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        // Room under the last row for the add button to sit over.
        .contentMargins(.bottom, LivBar.listRoom, for: .scrollContent)
        .livHidesChrome()
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

    /// "6 open · 2 late": every open task in the lens plus the open lines
    /// in notes, whatever the filter shows — the screen's size, not the
    /// slice's. Late is grey here; the group heading carries the red.
    private var subtitle: String {
        let open = lensTasks.filter { !isDone($0) }
        let late = open.filter(isLate).count
        let count = open.count + noteLines.count
        if count == 0 { return "Nothing open" }
        return late > 0 ? "\(count) open · \(late) late" : "\(count) open"
    }

    /// Clear air between two cards, as its own List row — never a top
    /// inset on the card's first row, which would bleed the card's fill
    /// into the gap.
    private func gap(_ height: CGFloat) -> some View {
        Color.clear
            .frame(height: height)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    // MARK: the filter

    /// A SEGMENTED CONTROL (the clearer board): All, then every status in
    /// the vocabulary. The board draws three segments; the app's own
    /// vocabulary decides how many, so Doing stays. Projects filtered as
    /// chips before, and the board has no room for them — they stay
    /// reachable as one trailing segment that is a menu, shown only when
    /// there are projects to pick.
    private var segmentRow: some View {
        let choices: [(value: TasksPosition.Filter, label: String)] =
            [(.all, "All")] + options.compactMap { o in o.name.map { (.status($0), $0) } }
        return LivSegment(
            options: choices,
            selection: Binding(get: { filter }, set: { park(filter: $0) })
        ) {
            if !projects.isEmpty { projectSegment }
        }
        .padding(.horizontal, LivRow.cardInset)
        .padding(.bottom, LivSegmented.under)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private var projectSegment: some View {
        let picked: String? = {
            if case .project(let p) = filter { return p }
            return nil
        }()
        return Menu {
            Button("All projects") { withAnimation(LivMotion.pick) { park(filter: .all) } }
            ForEach(projects, id: \.self) { project in
                Button(project) {
                    withAnimation(LivMotion.pick) { park(filter: .project(project)) }
                }
            }
        } label: {
            LivSegmentFace(picked ?? "Project", on: picked != nil)
        }
        .accessibilityLabel(picked.map { "Project, \($0)" } ?? "Project")
    }

    private var emptyRow: some View {
        // The lens case still NAMES the lens: "None here" would hide the
        // one fact that explains the emptiness.
        EmptyHint(
            filter != .all
                ? "No matches"
                : workspaces.lensOn
                    ? "None in \(workspaces.lensLabel)"
                    : "Empty"
        )
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    // MARK: the add row

    /// TYPE A TASK WHERE THE TASKS ARE (owner, 2026-09-10: *"tasks and
    /// calendar lets you add their objects directly"*).
    ///
    /// The bar's `+` makes a note in every view now, so this is the door
    /// it used to be here. It is its own card on the same spine as
    /// `taskRow` — a 22 mark in the 28 column, the name where every
    /// task's name starts — because it becomes one of those rows the
    /// moment you hit return.
    ///
    /// **IT NEVER MAKES A TASK THAT VANISHES.** A typed task carries
    /// whatever the filter you are looking at demands: the segment's
    /// status, or the vocabulary's first status that does not complete;
    /// and the project when the Project segment has one picked. Without that, the row
    /// you just typed would be filtered straight out of the list you
    /// typed it into.
    ///
    /// **AND IT SETS NOTHING THE ROW DOES NOT SHOW.** No due date: this
    /// row has no date on it, so it must not invent one. The `+` menu's
    /// Task still opens the card, where the due is the first row and
    /// `desk.contextDay` puts it on the day you are looking at — which is
    /// how Today keeps making dated tasks. Same rule as the Calendar,
    /// which takes the time from where your finger lands and nothing
    /// else.
    private var addRow: some View {
        // ITS OWN CARD, one row, on the card row's spine: the new-note mark
        // in the 28 column, the field where every task's name starts.
        LivCardRow(
            divided: false,
            lead: {
                // IT GOES RED WHEN THE BOX REFUSED THE LAST ONE — the mark,
                // not a word: it is where the eye already is, and it does
                // not change this row's STRUCTURE.
                LivIcon(
                    glyph: .new, color: addFailed ? LivTheme.red : LivTheme.text2,
                    size: LivCards.glyph
                )
                .frame(width: LivCards.mark)
            },
            title: {
                TextField(
                    "New task", text: $adding,
                    prompt: Text("New task").foregroundStyle(LivTheme.text3)
                )
                .tint(LivTheme.accent)
                .focused($addFocused)
                .submitLabel(.return)
                .onSubmit { commitAdd() }
                // A refusal is about the words that were refused; the
                // next keystroke is a different sentence.
                .onChange(of: adding) { _, _ in
                    if addFailed { addFailed = false }
                }
            },
            trailing: {
                // ALWAYS IN THE TREE, invisible while there is nothing to
                // add. It was once inserted on the first keystroke, and a
                // sibling appearing beside a field that holds first
                // responder re-identified the row and could take the text
                // with it (owner, 2026-09-11: "adding a task from the add
                // row does nothing visible"). The board draws no pill on an
                // empty field; this is how it gets that without the bug.
                ConfirmPill("Add", compact: true, action: commitAdd)
                    .opacity(typed.isEmpty ? 0 : 1)
                    .disabled(typed.isEmpty)
                    .accessibilityHidden(typed.isEmpty)
            }
        )
        // THE WHOLE ROW TAKES THE TAP: a thumb aimed at "the empty row"
        // must land in the field.
        .contentShape(Rectangle())
        .onTapGesture { addFocused = true }
        .livCardRow(position: .only)
    }

    /// What is in the field, trimmed — read by the verb and by whether
    /// the verb is live, so the two can never disagree about whether
    /// there is anything to add.
    private var typed: String {
        adding.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The status a typed task takes: the segment you are filtered to, or
    /// the first status in the vocabulary that does not complete — so a
    /// name typed with no thought lands in To do and not in Done.
    private var addStatus: String? {
        if case .status(let s) = filter { return s }
        return options.first { $0.completes != true }?.name
    }

    /// The project a typed task takes — only when one is picked,
    /// and only so the row does not vanish (see `addRow`).
    private var addProject: String? {
        if case .project(let p) = filter { return p }
        return nil
    }

    /// Create it, and keep the caret for the next one.
    ///
    /// The field is cleared BEFORE the write, not in its callback: the
    /// box answers a beat later and by then the next name is already
    /// being typed, so clearing there would eat it.
    private func commitAdd() {
        let name = typed
        guard !name.isEmpty, !addingBusy else { return }
        // READ THE FILTER NOW, not when the box answers. The segment you
        // were looking at when you typed is the one that decides where
        // this lands; a beat later it could be another.
        let status = addStatus
        let project = addProject
        addingBusy = true
        adding = ""
        // SwiftUI resigns the field on submit; asking for it back after
        // the submit has finished keeps the keyboard up for the second
        // task, which is the whole point of typing in a list.
        DispatchQueue.main.async { addFocused = true }
        model.createTask { id in
            addingBusy = false
            guard !id.isAbsent else {
                // GIVE THE WORDS BACK. The field is cleared the moment
                // you hit return, because that IS the acknowledgment —
                // but a refused create then ate the sentence and said
                // nothing a person could see, which is the worst of both
                // (a verb only ever reaches the log: `BoxModel.verbFailed`
                // raises `boxFault` for a real fault and stays silent for
                // a plain refusal). Put the name back and let the row's
                // mark say so, so a failure is never mistaken for nothing.
                adding = name
                addFocused = true
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                addFailed = true
                return
            }
            model.set(id, "name", name)
            if let status { model.set(id, "status", status) }
            if let project { model.set(id, "project", project) }
            // The same stamp every other create door applies, so a task
            // typed inside a filtered workspace belongs to it.
            _ = workspaces.stamp(id, in: model)
        }
    }

    // MARK: groups

    /// The vocabulary's groups in board order + a final "No status" catch-all
    /// (also holds statuses no longer in the vocabulary — every task shows).
    private func visibleGroups() -> [TasksGroup] {
        // The lens (M4) runs BEFORE the segment filter: the workspace
        // scopes the surface, the segments narrow inside it.
        let filtered = lensTasks.filter(matchesFilter)

        var used = Set<LivEntityID>()
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

        // An empty group is not a group. Quick-add used to hold one
        // open to host itself; the add button is outside the list now.
        return groups.filter { !$0.rows.isEmpty }
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
        // THE LATENESS IS SAID TWICE NOW: once here, "2 late" in red, and
        // once on each late row's date (the clearer board, 2026-09-24,
        // which reverses the 2026-08-30 rule of saying it once, here).
        let late = group.rows.filter(isLate).count
        return SectionLabel(
            group.name, count: group.rows.count,
            note: late > 0 ? "\(late) late" : nil
        )
        .listRowInsets(EdgeInsets(top: 0, leading: LivRow.cardInset, bottom: 0, trailing: LivRow.cardInset))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    /// A COMPLETES GROUP IS A FOLD, and the fold is a card row: the done
    /// box, the group's name, its count and a chevron (the clearer board's
    /// "Done ›"). Opened, its rows follow in the same card and the chevron
    /// turns down. It sits 16 under the card above it, with no heading.
    @ViewBuilder private func foldCard(_ group: TasksGroup) -> some View {
        let open = expanded.contains(group.name) && !group.rows.isEmpty
        gap(LivCards.gap)
        Button {
            livToggleFold { toggleExpanded(group.name) }
        } label: {
            LivCardRow(
                group.name, divided: open,
                lead: {
                    LivCheckbox(done: true, hue: group.hue)
                        .frame(width: LivCards.mark)
                        .accessibilityHidden(true)
                },
                trailing: {
                    LivRowFact(text: "\(group.rows.count)")
                    LivChevron(open ? .down : .right)
                })
        }
        .accessibilityValue(open ? "Open" : "Closed")
        .livFoldRow(open: open)
        if open {
            ForEach(Array(group.rows.enumerated()), id: \.element.id) { i, row in
                taskRow(
                    row, prev: i == 0 ? nil : group.rows[i - 1],
                    position: i == group.rows.count - 1 ? .last : .middle)
            }
        }
    }

    // MARK: - "In notes": the checkbox lines (phase 3, owner 2026-08-05)

    /// Every open `- [ ]` line in a live note, straight off the wire's
    /// projection (services/src/tasks.rs). Deliberately its OWN section,
    /// not folded into "To do": these lines have no status, and calling
    /// them To do would muddy what a status means. They wear a square box
    /// instead of the status ring, so the shape says what they are.
    ///
    /// The workspace lens applies to the SOURCE NOTE — a filtered surface
    /// filters whole (rev 6's consistency rule).
    private var noteLines: [NoteTaskRow] {
        return (model.snap?.noteTasks ?? []).filter { row in
            guard let owner = row.entity, let note = model.entity(owner) else { return false }
            return workspaces.admits(note)
        }
    }

    @ViewBuilder private var inNotesSection: some View {
        let lines = noteLines
        if !lines.isEmpty {
            SectionLabel("In notes", count: lines.count)
                .listRowInsets(EdgeInsets(top: 0, leading: LivRow.cardInset, bottom: 0, trailing: LivRow.cardInset))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            ForEach(Array(lines.enumerated()), id: \.element.id) { i, line in
                noteLineRow(line, position: .of(i, in: lines.count))
            }
        }
    }

    private func noteLineRow(_ line: NoteTaskRow, position: LivCardPosition) -> some View {
        let owner = line.entity ?? .absent
        // The wire computes this where the content is — EntityRow.title
        // would read "Roof project - [ ] call the surveyor - [x] paid…".
        let source = line.source ?? ""
        let text = line.text ?? ""
        // THE SOURCE IS THE SECOND LINE ("In Climbing log"), not a chip:
        // the whole row opens the note now, which is what the chip did.
        return LivCardRow(
            detail: "In \(source.isEmpty ? "a note" : source)",
            muted: text.isEmpty, divided: position.divided,
            lead: {
                Button {
                    toggleNoteLine(line)
                } label: {
                    LivCheckbox(done: false)
                        .frame(width: LivCards.mark, height: LivRow.touch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Complete \(text)")
            },
            title: {
                HStack(spacing: 0) {
                    // Sub-lines ride along, inset — the note's own shape.
                    if (line.indent ?? 0) > 0 { Spacer().frame(width: LivCards.indent) }
                    Text(text.isEmpty ? "empty line" : text)
                }
            },
            trailing: { EmptyView() }
        )
        .onTapGesture { desk.open(owner) }
        .accessibilityAction(named: "Open \(source.isEmpty ? "the note" : source)") {
            desk.open(owner)
        }
        .livCardRow(position: position)
    }

    /// Check the line: edit THAT NOTE's text — the same write the editor's
    /// own checkbox makes, through the same pure op (EditOps.toggleTask).
    /// The save presents the fingerprint the content was read at, so a
    /// stale view is REFUSED, never mis-landed; a refusal just refreshes.
    private func toggleNoteLine(_ line: NoteTaskRow) {
        guard let owner = line.entity, let index = line.line else { return }
        model.content(owner) { doc in
            guard let doc, doc.missing != true else { return }
            // This path re-encodes the WHOLE note through the buffer with
            // nobody looking at it. The editor guards that with a banner
            // and a choice; here there is no one to warn, so a note the
            // buffer cannot hold — a code fence, a callout — must not be
            // rewritten from a checkbox tap on an unrelated line. Open
            // the note and the editor will say so properly.
            guard !SpanText.carriesFormatting(doc.spans ?? []) else {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return
            }
            let text = SpanText.spansToText(doc.spans ?? [])
            guard let at = EditOps.lineStart(text, line: index),
                let edit = EditOps.toggleTask(text, at: at)
            else {
                // The note moved under us — the snapshot will catch up.
                model.refresh()
                return
            }
            // A [[…]] token whose target is not in this box must stay
            // TEXT. Re-encoding with the default "everything is known"
            // promoted it to a reference, and the core refuses content
            // that points at nothing — so ticking a box in such a note
            // failed silently, forever (review, 2026-08-06). The editor
            // has always passed this closure; this path did not.
            model.setContent(
                owner,
                spansJson: SpanText.json(
                    SpanText.textToSpans(edit.text, isKnown: { model.entity($0) != nil })),
                base: doc.fingerprint ?? 0
            ) { status, _ in
                if status != 1 { UINotificationFeedbackGenerator().notificationOccurred(.error) }
                model.refresh()
            }
        }
    }

    private func toggleExpanded(_ name: String) {
        var open = expanded
        if open.contains(name) { open.remove(name) } else { open.insert(name) }
        park(expanded: open)
    }

    // MARK: rows

    private func taskRow(_ row: EntityRow, prev: EntityRow?, position: LivCardPosition) -> some View {
        let option = options.first { $0.name == row.status }
        let done = option?.completes == true
        let due = livNewFact(tasksDue(row), after: prev.flatMap { tasksDue($0) })
        let title = (row.title ?? "").isEmpty ? "untitled task" : (row.title ?? "")
        // ONE SECOND LINE, not a chip: where the task lives. The list's rows
        // come off the snapshot, which carries no cells, so the anchor is
        // read from the model's own row — asking for it is what fetches
        // them — and the area, on the wire, shows at once.
        return LivCardRow(
            title, detail: livPlace(of: model.entity(row.id) ?? row),
            muted: (row.title ?? "").isEmpty,
            divided: position.divided,
            lead: {
                StatusRing(done: done, hue: tasksOptionColor(option?.hue), name: title) {
                    toggleStatus(row, done: done)
                }
            },
            trailing: {
                // Only when it CHANGES, so five rows due the same day say
                // it once (`livNewFact`); red when late and still open.
                if let due { LivRowFact(text: due, late: !done && isLate(row)) }
            }
        )
        .onTapGesture { desk.open(row.id) }  // rows open as Desk tabs
        .livCardRow(position: position)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            // The spec's full verb set (§6): Tonight / Tomorrow / Weekend /
            // Pick. Tonight matches the due sheet's 20:00; on a Friday,
            // Weekend IS tomorrow and drops out (eval §5.11).
            // ONE TINT FOR ONE FAMILY OF VERBS: four ways of saying "move
            // this to another day" wear the scheduling colour; red is for
            // the destructive tray on the other edge.
            Button("Tonight") {
                model.setSpan(
                    row.id, "due",
                    start: Civil.stamp(day: Civil.todayDay(), hhmm: 2000),
                    end: 0, dateOnly: false)
            }
            .tint(LivTheme.accent)
            Button("Tomorrow") { reschedule(row, to: TasksDates.tomorrow()) }
                .tint(LivTheme.accent)
            if TasksDates.weekend() != TasksDates.tomorrow() {
                Button("Weekend") { reschedule(row, to: TasksDates.weekend()) }
                    .tint(LivTheme.accent)
            }
            Button("Pick") { duePick = TasksDuePick(entity: row.id) }
                .tint(LivTheme.accent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            livTrashAction { model.trash(row.id) }
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

    /// Move the DAY and keep the time of day. It used to overwrite the
    /// time with nothing, so a task set for 14:00 came back as a bare
    /// date — which now means it never rings. A task with no time yet
    /// gets 09:00 (owner, 2026-08-07).
    private func reschedule(_ row: EntityRow, to day: Int64) {
        let hhmm: Int64 =
            (row.dueDateOnly ?? true) ? LivDue.defaultHHMM : ((row.due ?? 0) % 10_000)
        model.setSpan(
            row.id, "due",
            start: Civil.stamp(day: day, hhmm: hhmm), end: 0, dateOnly: false)
    }

    /// A row's date in Apple's words: "09:41" or "Today" today, then
    /// "Yesterday", a weekday this week, else "18 Sep" (`Civil.fact`).
    private func tasksDue(_ row: EntityRow) -> String? {
        guard let due = row.due, due > 0 else { return nil }
        return Civil.fact(due)
    }

    /// Every task the workspace lens admits, before the filter — the
    /// subtitle counts these, the groups narrow them.
    private var lensTasks: [EntityRow] {
        (model.snap?.entities ?? []).filter {
            ($0.kinds ?? []).contains("task") && $0.trashed != true
                && $0.archived != true && workspaces.admits($0)
        }
    }

    private func isDone(_ row: EntityRow) -> Bool {
        options.first { $0.name == row.status }?.completes == true
    }

    /// Late is strictly past: due today is not overdue.
    private func isLate(_ row: EntityRow) -> Bool {
        guard let due = row.due, due > 0 else { return false }
        return Civil.day(of: due) < Civil.todayDay()
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
            if Civil.weekday(day) == 7 { return day }  // Gregorian: 7 = Saturday
            day = Civil.addDays(day, 1)
        }
        return day
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
