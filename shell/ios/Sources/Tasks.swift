// liv iOS — Tasks (design/ios.md §6): a Feature-view lens — status-grouped
// flat list over every task in the box. Groups come from the vocabulary
// (liv_status_options_at, board order); `completes` groups collapse by
// default. Filters are client-side state only — the snapshot is never
// re-queried to filter. Status chips/rings wear the OPTION's hue (quantized
// to the semantic set); project chips wear no dot — a project has no colour
// in the box, and hashing its name into one was a code with nothing to
// decode (2026-08-29). Full snapshot on
// appear — undated tasks must not drop. Tapping a row opens the entity as a
// Desk tab (desk.open) — the rail→center gesture grammar; the chrome owns
// the frame, so this body keeps only a SectionLabel-scale header.

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

    /// WHERE YOU ARE in this view: the chip that is on, and the
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
        let entity: UInt64
        var id: UInt64 { entity }
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
            // THE SCREEN'S NAME — see the same addition in Notes and
            // Everything. This one sits above the filter chips, which
            // are a control, not a heading.
            LivScreenTitle("Tasks")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
                .padding(.bottom, 2)
                .listRowInsets(
                    EdgeInsets(top: 0, leading: LivRow.margin, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            chipRow
            addRow
            if groups.allSatisfy({ $0.rows.isEmpty }) {
                emptyRow
            }
            ForEach(groups) { group in
                groupHeader(group)
                if !group.completes || expanded.contains(group.name) {
                    ForEach(Array(group.rows.enumerated()), id: \.element.id) { i, row in
                        taskRow(row, prev: i == 0 ? nil : group.rows[i - 1])
                    }
                }
            }
            inNotesSection
        }
        .listStyle(.plain)
        // 10, like Today, Inbox and Everything: every openable row now
        // states `LivRow.height` itself, so the List's floor only has to
        // stay out of the way, and one number across the four lists
        // beats four.
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

    // MARK: header + filter chips

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                TasksFilterChip("All", selected: filter == .all) {
                    withAnimation(LivMotion.pick) { park(filter: .all) }
                }
                ForEach(options) { option in
                    let name = option.name ?? ""
                    TasksFilterChip(name, selected: filter == .status(name)) {
                        withAnimation(LivMotion.pick) {
                            park(filter: filter == .status(name) ? .all : .status(name))
                        }
                    }
                }
                ForEach(projects, id: \.self) { project in
                    TasksFilterChip(
                        project,
                        selected: filter == .project(project)
                    ) {
                        withAnimation(LivMotion.pick) {
                            park(
                                filter: filter == .project(project)
                                    ? .all : .project(project))
                        }
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
    /// it used to be here. It is the same spine as `taskRow` — a 15pt
    /// mark in a 31pt column, the name at `LivType.strong`, the hairline
    /// at 31 — because it becomes one of those rows the moment you hit
    /// return.
    ///
    /// **IT NEVER MAKES A TASK THAT VANISHES.** A typed task carries
    /// whatever the filter you are looking at demands: the chip's status,
    /// or the vocabulary's first status that does not complete; and the
    /// chip's project when a project chip is on. Without that, the row
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
        HStack(spacing: 0) {
            // THE MARK COLUMN, matching `StatusRing`'s geometry (15pt of
            // ink in 8pt of padding = 31) so the field starts exactly
            // where every task name does. Ink, never colour: an open box
            // is ink here (see `StatusRing`), and a `+` that is the only
            // accent on the screen would shout.
            //
            // IT GOES RED WHEN THE BOX REFUSED THE LAST ONE — the mark,
            // not a word. It is where the eye already is, it costs the
            // row no width, and (the reason it is not a label) it does
            // not change this row's STRUCTURE, which is the fault this
            // row was just fixed for.
            Image(systemName: "plus")
                .font(.system(size: LivType.caption, weight: .semibold))
                .foregroundStyle(addFailed ? LivTheme.red : LivTheme.text3)
                .frame(width: 15, height: 15)
                .padding(8)
                .frame(height: LivRow.touch)
            TextField("New task", text: $adding)
                .font(.system(size: LivType.strong))
                .foregroundStyle(LivTheme.text)
                .tint(LivTheme.accent)
                .focused($addFocused)
                .submitLabel(.return)
                .onSubmit { commitAdd() }
                // A refusal is about the words that were refused; the
                // next keystroke is a different sentence.
                .onChange(of: adding) { _, _ in
                    if addFailed { addFailed = false }
                }
            // ALWAYS IN THE TREE, dimmed when there is nothing to add —
            // the bar's own rule for a key that cannot fire (Bar.swift's
            // `disabledInk`), and not merely a style choice here.
            //
            // It was wrapped in `if !adding.isEmpty`, so the FIRST
            // keystroke inserted a sibling into this row while the field
            // beside it held first responder. A row whose structure
            // changes under an editing field is the one shape SwiftUI
            // handles badly: it re-identifies the row, and the text can
            // go with it — which looks exactly like typing doing nothing
            // (owner, 2026-09-11: "adding a task from the add row does
            // nothing visible"). Nothing is worth that; the row's width
            // is not short of eight points.
            Button(action: commitAdd) {
                Text("Add")
                    .font(.system(size: LivType.body, weight: .semibold))
                    .foregroundStyle(LivTheme.accent)
                    .opacity(typed.isEmpty ? LivBar.disabledInk : 1)
                    .padding(.leading, 8)
            }
            .buttonStyle(.plain)
            .disabled(typed.isEmpty)
        }
        .frame(minHeight: LivRow.height)
        // THE WHOLE ROW TAKES THE TAP, like `taskRow` beneath it — a
        // 31pt mark and a short field left most of the row inert, so a
        // thumb aimed at "the empty row" landed on nothing.
        .contentShape(Rectangle())
        .onTapGesture { addFocused = true }
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
                .padding(.leading, 31)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    /// What is in the field, trimmed — read by the verb and by whether
    /// the verb is live, so the two can never disagree about whether
    /// there is anything to add.
    private var typed: String {
        adding.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The status a typed task takes: the chip you are filtered to, or
    /// the first status in the vocabulary that does not complete — so a
    /// name typed with no thought lands in To do and not in Done.
    private var addStatus: String? {
        if case .status(let s) = filter { return s }
        return options.first { $0.completes != true }?.name
    }

    /// The project a typed task takes — only when a project chip is on,
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
        // READ THE FILTER NOW, not when the box answers. The chip you
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
            guard id != 0 else {
                // GIVE THE WORDS BACK. The field is cleared the moment
                // you hit return, because that IS the acknowledgment —
                // but a refused create then ate the sentence and said
                // nothing a person could see, which is the worst of both
                // (a verb only ever reaches the log: `BoxModel.verbFailed`
                // raises `boxFault` for a real fault and stays silent for
                // a plain refusal). Put the name back and let the chip
                // say so, so a failure is never mistaken for nothing.
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
        // The lens (M4) runs BEFORE the chip filter: the workspace scopes
        // the surface, the chips narrow inside it.
        let tasks = (model.snap?.entities ?? []).filter {
            ($0.kinds ?? []).contains("task") && $0.trashed != true
                && $0.archived != true && workspaces.admits($0)
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
        let isExpanded = expanded.contains(group.name)
        let trailing =
            group.completes
            ? "\(group.rows.count) \(isExpanded ? "▾" : "▸")"
            : "\(group.rows.count)"
        // THE LATENESS IS THE GROUP'S FACT, NOT EACH ROW'S. Measured
        // 2026-08-30: this screen was 1.85% saturated pixels against
        // Todoist's 0.58%, and 21,000 of those pixels were a column of
        // red dates — one per row, because in this box every task is
        // overdue. A colour that appears on every row distinguishes
        // nothing; it just makes the list shout. Todoist says it once,
        // in the heading, and leaves the rows grey.
        let late = group.rows.filter { row in
            guard let due = row.due, due > 0 else { return false }
            return Civil.day(of: due) < Civil.todayDay()
        }.count
        return SectionLabel(
            group.name, trailing: trailing,
            note: late > 0 && !group.completes ? "\(late) late" : nil,
            trailingAction: group.completes ? { toggleExpanded(group.name) } : nil
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if group.completes { toggleExpanded(group.name) }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
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
            SectionLabel("In notes", trailing: "\(lines.count)")
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            ForEach(lines) { line in
                noteLineRow(line)
            }
        }
    }

    private func noteLineRow(_ line: NoteTaskRow) -> some View {
        let owner = line.entity ?? 0
        // The wire computes this where the content is — EntityRow.title
        // would read "Roof project - [ ] call the surveyor - [x] paid…".
        let source = line.source ?? ""
        return HStack(spacing: 0) {
            Button {
                toggleNoteLine(line)
            } label: {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(LivTheme.text3, lineWidth: 1.5)
                    .frame(width: 16, height: 16)
                    .frame(width: 31, height: LivRow.touch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(line.text ?? "")")
            // Sub-lines ride along, inset — the note's own shape, kept.
            if (line.indent ?? 0) > 0 {
                Spacer().frame(width: 14)
            }
            Text((line.text ?? "").isEmpty ? "empty line" : (line.text ?? ""))
                .font(.system(size: LivType.strong))
                .foregroundStyle((line.text ?? "").isEmpty ? LivTheme.text2 : LivTheme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button {
                desk.open(owner)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: LivChip.glyph, weight: .semibold))
                    Text(source.isEmpty ? "note" : source)
                        .font(.system(size: LivType.caption, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(LivTheme.text3)
                .padding(.horizontal, 8)
                // The app's chip height, not a raw 20 under it.
                .frame(height: LivChip.height)
                .background(Capsule().fill(LivTheme.panel2))
                .overlay(Capsule().strokeBorder(LivTheme.border, lineWidth: 0.5))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(source.isEmpty ? "the note" : source)")
        }
        .frame(minHeight: LivRow.height)
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
                .padding(.leading, 31)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
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

    private func taskRow(_ row: EntityRow, prev: EntityRow?) -> some View {
        let option = options.first { $0.name == row.status }
        let done = option?.completes == true
        let due = livNewFact(tasksDue(row), after: prev.flatMap { tasksDue($0) })
        let chips = refChips(row)
        return HStack(spacing: 0) {
            StatusRing(done: done, hue: tasksOptionColor(option?.hue)) {
                toggleStatus(row, done: done)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    (row.title ?? "").isEmpty ? "untitled task" : (row.title ?? "")
                )
                .font(.system(size: LivType.strong))
                .foregroundStyle(
                    (row.title ?? "").isEmpty ? LivTheme.text2 : LivTheme.text
                )
                .lineLimit(1)
                if !chips.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(chips.enumerated()), id: \.offset) { $0.element }
                    }
                }
            }
            Spacer(minLength: 8)
            if let due {
                // Always text3 — see `groupHeader` for where the
                // lateness went — and only when it CHANGES, so five
                // rows due "Sun 16 Aug" say it once (`livNewFact`).
                LivRowFact(text: due)
            }
        }
        // NO VERTICAL PADDING. It was here from when the row was 40,
        // and it sits OUTSIDE the frame below — so it padded the content
        // first and the 56 floor then never bound: a row carrying a chip
        // drew 58 while its neighbours drew 56 (found 2026-09-05 by
        // `drive.sh rows`, which was written to catch exactly this).
        // Today draws the same title-over-chips stack with no padding.
        // THE APP'S ROW HEIGHT, not this list's own. It was a raw 40,
        // then a raw 44, while Notes, Everything and Inbox drew the same
        // kind of row at `LivRow.height` — so Tasks read shorter than
        // every list beside it and 40 was under Apple's touch minimum
        // besides, with the whole row as the target.
        .frame(minHeight: LivRow.height)
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
            // ONE TINT FOR ONE FAMILY OF VERBS. These are four ways of
            // saying the same thing — move this to a different day — and
            // they wore four different saturated colours, so the tray
            // read as four unrelated buttons and the colours carried no
            // information the WORDS did not already carry. iOS tints a
            // tray by what an action IS, not by which one it is: one
            // colour for scheduling, red for the destructive tray on the
            // other edge.
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

    /// Trailing due: today shows the time (or "Today"), everything else the
    /// day label. Danger strictly past — due today is not overdue.
    /// A row's date, as words. It used to return a `danger` flag with it
    /// and nothing reads that any more — the lateness moved to the group
    /// heading, so the flag went with it rather than sitting here unused
    /// (standing rule 6).
    private func tasksDue(_ row: EntityRow) -> String? {
        guard let due = row.due, due > 0 else { return nil }
        let day = Civil.day(of: due)
        if day == Civil.todayDay() {
            let time = Civil.timeString(due)
            return time.isEmpty ? "Today" : time
        }
        return Civil.dayLabel(day)
    }

    /// Ref cells become chips: the cell's own display value, else the
    /// target's title from the snapshot index. Three at most — density law.
    /// ONE chip, not three (BP-6: the tile's line 2 is "people, then
    /// exactly ONE date chip, then tier — and NEVER a status chip,
    /// because the column already carries status"; empty fields do not
    /// render at all). The date is the row's right-hand fact already, so
    /// what is left to say here is what the task is attached to.
    private func refChips(_ row: EntityRow) -> [ValueChip] {
        // One helper, one order (`livAnchor`); an area leads with its mark.
        livAnchorChip(of: row).map { [$0] } ?? []
    }
}

// MARK: - filter chip (selected state ValueChip doesn't carry)

/// The ValueChip recipe + a selected state: accentSoft fill, accent ink.
/// Neutral body always; the value's color stays in the dot.
/// One filter chip. `dot` is OPTIONAL and usually absent.
///
/// A status wears one because the box holds a colour for it — a status
/// option carries its own `hue`, chosen by a person. A project has no
/// colour anywhere in the box, so its chip used to hash the project's
/// NAME to one of five, which looked like a code and was not one
/// (2026-08-29).
private struct TasksFilterChip: View {
    let text: String
    let selected: Bool
    let action: () -> Void

    init(_ text: String, selected: Bool, action: @escaping () -> Void) {
        self.text = text
        self.selected = selected
        self.action = action
    }

    // FOUR DEVICES BECAME ONE (polish pass, 2026-08-30). A chosen chip
    // carried an accent fill, an accent border, accent ink and a heavier
    // weight; an unchosen one carried a fill AND a border. Beside them
    // sat a coloured dot repeating the status the chip spells out in
    // letters. What is left: the chosen chip is filled and its words are
    // full ink, the rest are bare. That is the same mark the lens row
    // and the day strip use — the app has one way of saying "this one".
    var body: some View {
        Button(action: action) {
            Text(text)
                // `body`, not `label` (2026-09-05). This row decides
                // which slice of the list you are looking at, and it sat
                // at the same size as the group heading below it — a
                // control reading as quietly as a caption.
                .font(.system(size: LivType.body, weight: selected ? .medium : .regular))
                .lineLimit(1)
                .foregroundStyle(selected ? LivTheme.text : LivTheme.text2)
                .padding(.horizontal, 12)
                .frame(height: LivChip.tall)
                .background(Capsule().fill(selected ? LivTheme.panel2 : .clear))
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
