// liv iOS — Inbox (design/ios.md §6; rebuilt phase 5, owner-approved
// mockup 2026-08-05). The Inbox is THE DECISION QUEUE: exactly two
// things belong here — a capture the app knows nothing about yet, and a
// suggestion the clerk is waiting on. One list, two sections, no modes
// (the old fake Route/Tidy segments are gone). When both are empty the
// app has no questions for you: Inbox zero is a real, earned state.
//
// Routing FINISHES the object instead of stamping half of one: Task
// lands with its first status, Event opens the date editor (an event
// with no date cannot appear in the Calendar — owner-approved), Note and
// Link write directly. Every routing offers Undo on a transient chip; a
// refused write is a haptic, never silence.

import SwiftUI
import UIKit

/// The routed capture whose date is being picked (the Event verb's
/// second half — the arbitrary date-and-time door).
private struct InboxDuePick: Identifiable {
    let entity: UInt64
    var id: UInt64 { entity }
}

struct InboxView: View {
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var workspaces: WorkspaceModel

    @State private var taskOptions: [StatusOption] = []
    @State private var duePick: InboxDuePick?
    @State private var settingsShown = false
    /// The proposal a ✕ is about to dismiss — rejection is PERMANENT
    /// (the clerk never re-asks), so it costs one ask.
    /// The transient acknowledgment: what routed, and how many
    /// transactions its Undo must take back.
    @State private var chipText: String?
    @State private var chipUndo = 0

    /// (kinds empty) ∧ (contentPrint set) ∧ ¬trashed over the `everything`
    /// projection — the id lists exclude backstage plumbing.
    ///
    /// THE WORKSPACE LENS IS NOT APPLIED HERE, EVER (design/ios.md M4). An
    /// unfiled thing must be reachable from every workspace, or a capture
    /// made under the wrong lens appears to vanish. This is a stated
    /// safety rule, not an oversight; do not "fix" it.
    private var scraps: [EntityRow] {
        (box.snap?.everything ?? [])
            .compactMap { box.entity($0) }
            .filter {
                ($0.kinds ?? []).isEmpty && ($0.contentPrint ?? 0) != 0
                    && !($0.trashed ?? false)
            }
            .sorted {
                let a = $0.created ?? 0
                let b = $1.created ?? 0
                return a == b ? $0.id > $1.id : a > b
            }
    }

    /// The clerk's pending queue, minus the shapes the accept seam cannot
    /// take yet: triage() only matches AddCell-first proposals, so a
    /// Trash-first merge would render as a card whose ✓ returns 0 forever
    /// (the filed FFI chip). Until that lands, they stay out of the list.
    private var proposals: [ProposalRow] {
        // A question about an unrouted capture is asked ON ITS ROW, in
        // Route (`suggestedArea`), not a second time here: the clerk's
        // area guess for a scrap is the routing question with an answer
        // pencilled in, and two lenses both asking it would make the
        // Inbox count one decision twice.
        let unrouted = Set(scraps.map(\.id))
        return (box.snap?.inbox ?? []).filter {
            ($0.commands?.first?.kind ?? "") == "add"
                && !($0.author == "area" && unrouted.contains($0.entity ?? 0))
        }
    }

    /// THE CLERK'S GUESS AT WHERE THIS GOES (2026-09-09, owner's word):
    /// the pending `area` proposal for a scrap, and the area it names.
    /// The clerk reads it off what the capture mentions — a thought
    /// about Sam belongs where Sam is filed (`clerk.rs`, `propose_area`).
    private func suggestedArea(_ row: EntityRow) -> (p: ProposalRow, area: String)? {
        guard let p = box.proposals(for: row.id).first(where: { $0.author == "area" }),
            let area = p.commands?.first?.value, !area.isEmpty
        else { return nil }
        return (p, area)
    }

    /// Grouped by PROPOSER, first-appearance order — the archived shell's
    /// grammar, and the natural review unit ("all the dates at once").
    private var proposalGroups: [(author: String, rows: [ProposalRow])] {
        var order: [String] = []
        var byAuthor: [String: [ProposalRow]] = [:]
        for p in proposals {
            let author = p.author ?? "clerk"
            if byAuthor[author] == nil { order.append(author) }
            byAuthor[author, default: []].append(p)
        }
        return order.map { ($0, byAuthor[$0] ?? []) }
    }

    /// The consent switch. nil = no switch in this box = ON by core
    /// semantics (owner-approved default).
    private var assistOff: Bool { box.snap?.assist?.on == false }

    /// Which question you are answering. The blueprint's Route / Tidy.
    ///
    /// NOT `@State` since 2026-08-22 — it is what this view's tab HOLDS
    /// (design/tabs.md, Reading B), so it lives in the plane and is saved
    /// with it.
    private var lens: InboxLens {
        InboxLens(rawValue: desk.position(.inbox) ?? "") ?? .route
    }

    /// The two lenses, as the blueprint names and counts them.
    private func lensRow(unrouted: Int, tidy: Int) -> some View {
        HStack(spacing: 8) {
            ForEach(InboxLens.allCases, id: \.self) { l in
                let count = l == .route ? unrouted : tidy
                Button {
                    withAnimation(LivMotion.pick) { desk.park(.inbox, at: l.rawValue) }
                } label: {
                    HStack(spacing: 6) {
                        Text(l.title)
                            .font(.system(size: LivType.body, weight: lens == l ? .semibold : .regular))
                            .foregroundStyle(lens == l ? LivTheme.text : LivTheme.text2)
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: LivType.label).monospacedDigit())
                                .foregroundStyle(LivTheme.text3)
                        }
                    }
                    // THE SAME MARK THE DAY STRIP USES: full ink, full
                    // weight, and a 2pt rule under the chosen one.
                    //
                    // This was a pair of capsules — a fill on the chosen
                    // one, an outline on the other — so both states were
                    // decorated and the row read as two competing
                    // buttons sitting under the title. The app now has
                    // ONE way of saying "this is the one you are on"
                    // (standing rule 4), and it is the quietest of the
                    // three it used to have.
                    .padding(.trailing, 18)
                    .frame(height: 34)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(lens == l ? LivTheme.text : Color.clear)
                            .frame(height: 2)
                            .padding(.trailing, 18)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    var body: some View {
        let scraps = self.scraps
        let groups = proposalGroups

        List {
            Group {
                // TWO LENSES, the blueprint's own pair (BP-5 B1): ROUTE
                // is the orphans waiting for an address, TIDY is the
                // assist queue. One cleanup home, two questions — "where
                // does this go" and "what did the clerk notice" — and
                // they were stacked in one scroll before, so a full
                // Route list buried the suggestions under it.
                // BOTH COUNTS IN THE SAME UNIT — items (owner,
                // 2026-08-20: the two numbers meant different things, so
                // "Route 6 · Tidy 2" could mean six things and twenty
                // edits). Tidy counted PROPOSERS, which is a grouping
                // detail nobody outside this file can see.
                // THE SCREEN'S NAME. It had none — the surface opened
                // straight onto a row of filter pills, so nothing on it
                // said where you were. Every reference leads with a
                // large bold left-aligned title (Todoist's "Inbox" is
                // the same word this screen is missing), and the whole
                // top of the screen reads as chrome without it.
                LivScreenTitle("Inbox")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
                lensRow(unrouted: scraps.count, tidy: proposals.count)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                if workspaces.lensOn {
                    // It explains an EXCEPTION: this one list ignores the
                    // workspace (owner, 2026-08-06).
                    // PROSE, NOT A PILL. A capsule is the shape this app
                    // uses for a value you can act on; this is a
                    // sentence explaining why the list ignores the
                    // workspace, and it cannot be tapped. It was also
                    // the one chip on the screen with no neighbours, so
                    // it read as a control that had lost its row.
                    HStack(spacing: 8) {
                        Text("All workspaces")
                            .font(.system(size: LivType.caption))
                            .foregroundStyle(LivTheme.text3)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 2)
                    .padding(.bottom, 6)
                }

                if lens == .route {
                    if scraps.isEmpty {
                        // The blueprint's own copy (BP-5 B8).
                        // "Nothing to route", not "Inbox zero" — that is
                        // GTD's slogan, and this screen's own word for
                        // its job is on the lens above it.
                        EmptyHint("Nothing to route")
                    } else {
                        ForEach(scraps) { row in
                            routeCard(row)
                        }
                    }
                } else {
                    if groups.isEmpty && !assistOff {
                        EmptyHint("Nothing to tidy")
                    }
                    suggestedSection(groups)
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
        // THE LIST CLOSES ITS OWN GAPS.
        //
        // Ticking a suggestion made it vanish and the rows below jump up
        // a notch — the list simply redrew, because nothing here was
        // animated (the app's old rule was "nothing springs", lifted by
        // the owner on 2026-08-31). The motion is not decoration: it is
        // what tells you the tick landed on the row you aimed at, and
        // which gap closed.
        //
        // Keyed on the COUNTS rather than on the arrays, so it fires
        // when something is accepted, dismissed or routed and not on
        // every unrelated snapshot the box publishes.
        .animation(LivMotion.list, value: scraps.count)
        .animation(LivMotion.list, value: proposals.count)
        .contentMargins(.bottom, LivBar.listRoom, for: .scrollContent)
        .livHidesChrome()
        .background(LivTheme.canvas)
        .sheet(item: $duePick) { pick in
            DetailDueSheet(model: box, id: pick.entity, property: "due")
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $settingsShown) { SettingsSheet() }
        .overlay(alignment: .top) {
            if let text = chipText { chip(text) }
        }
        .onAppear {
            box.refresh()
            box.statusOptions(kind: "task") { taskOptions = $0 }
        }
    }

    // MARK: route — a card per unrouted capture

    /// THE ROUTING QUESTION IS A CARD, NOT AN ACCORDION.
    ///
    /// Tapping a capture used to push four buttons INTO the list under
    /// the row, shoving everything below it down the screen (owner,
    /// 2026-08-31: "the menu that appears clicking on items shouldn't
    /// pop up in the list like that… look more like what you see in
    /// Todoist"). Todoist answers a tap with a card from the bottom, and
    /// so does this app already — `LivMenu` has taken a `from: .bottom`
    /// since it was written, and the record card and the properties card
    /// both work that way. One recipe, used (standing rule 4).
    ///
    /// The card also has room to say WHICH capture it is asking about,
    /// which the four inline buttons never did.
    private func routeCard(_ row: EntityRow) -> some View {
        Button {
            desk.menu = routeMenu(row)
        } label: {
            routeFace(row)
        }
        .livRowPress()
        // `allowsFullSwipe: false` on purpose: an unrouted capture must
        // not be thrown away by a thumb that kept going.
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            livTrashAction { box.trash(row.id) }
        }
    }

    private func routeFace(_ row: EntityRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: LivRow.markGap) {
                // QUIET, because this list is one kind by construction
                // (owner, 2026-08-18: "colour only in mixed lists").
                // Everything is genuinely mixed and keeps its tint; the
                // Inbox is a pile of unrouted captures, so its colour
                // was twenty identical yellow marks telling nothing
                // apart — which is what the owner saw on 2026-08-20:
                // "so many color blips and tags".
                LivIcon(
                    glyph: LivKind.glyph(of: row), color: LivTheme.text3,
                    size: LivRow.glyph)
                    .frame(width: LivRow.mark)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
                // REGULAR, like every other row title in the app and
                // like the reference's. It was `medium`, which made this
                // one list's titles heavier than the same words
                // everywhere else.
                Text(displayTitle(row))
                    .font(.system(size: LivType.body))
                    .foregroundStyle(LivTheme.text)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if let guess = suggestedArea(row) {
                    // THE ANSWER, PENCILLED IN. One tap says yes and
                    // files it — the same two writes tapping the area in
                    // the route card makes, with the clerk's consent
                    // recorded on the way. The date the chip replaces is
                    // the row's second voice; a question the row can
                    // answer outranks it. Tapping the row still opens the
                    // card, with every other area in it — the guess is
                    // offered, never imposed.
                    Button {
                        fileSuggested(row, guess.p, under: guess.area)
                    } label: {
                        ValueChip("\(guess.area)?", glyph: LivArea.glyph(named: guess.area))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("File under \(guess.area)")
                } else {
                    LivRowFact(text: stamp(row))
                }
            }
        }
        // A ROW YOU CAN HIT. Measured on 2026-08-31 these came out at
        // 40pt — under Apple's 44 touch minimum, and the tightest list
        // in the app. The reference's single-line row is about 46 and
        // its two-line row 57; `LivRow.height` is the app's own answer
        // to the same question, so this asks for it rather than keeping
        // a padding literal that agrees with nothing (standing rule 3).
        .padding(.vertical, 11)
        .frame(minHeight: LivRow.height)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
                .padding(.leading, LivRow.hairline - LivRow.margin)
        }
    }

    /// DISMISSING ASKS IN THE SAME CARD EVERYTHING ELSE ASKS IN.
    ///
    /// It was a `.confirmationDialog`, and SwiftUI drew it as a POPOVER
    /// with a little arrow tail, anchored part-way down the list and
    /// lying across the bottom bar (owner, 2026-08-31: "a message
    /// popping up at a random place at the bottom"). Where a system
    /// dialog decides to put itself is not something this app can
    /// control from here — but it does not need to, because it already
    /// owns a card that comes up from the bottom edge every time and
    /// knows how to draw a destructive row.
    ///
    /// It also gains what the dialog could not show: WHICH suggestion is
    /// about to be dismissed forever.
    private func rejectMenu(_ p: ProposalRow) -> LivMenu {
        LivMenu(
            id: "reject-\(p.id)",
            from: .bottom,
            subject: title(of: p),
            subjectDetail: "The clerk never asks this again",
            items: [
                LivMenuItem(
                    label: "Dismiss forever", glyph: .trash, destructive: true
                ) { box.reject(p) }
            ])
    }

    /// ROUTE ASKS WHERE, NOT WHAT (2026-09-09).
    ///
    /// This offered four KINDS — Task, Event, Note, Link — which is the
    /// question the constitution refuses in as many words: *"where does
    /// this go?" must not be reincarnated as "what type is this?"*
    /// (productivity_app.md). And it did not file anything: a scrap
    /// routed to Note left the Inbox with no area, and dropped into
    /// Everything's Unfiled slice, which nothing opens for you. So
    /// Inbox-zero and filed were two different states, and the app
    /// celebrated the first (`Inbox.swift:6`).
    ///
    /// Now the six areas lead — the furniture the thesis says makes
    /// filing "a tap, not a project" — plus any the person has added,
    /// read from the same property the inspector reads. Tapping one
    /// makes the scrap a filed note in one gesture: area set, kind set,
    /// out of the Inbox and out of Unfiled together. The kinds that are
    /// not a note stand one door further, behind "Not a note…", so the
    /// place question is asked first and the type question only when
    /// the answer is not the default.
    ///
    /// The clerk proposes an area since 2026-09-09 (`clerk.rs`,
    /// `propose_area`, on the owner's word); the row wears its guess as
    /// a chip (`suggestedArea`), and this card is the door past it.
    private func routeMenu(_ row: EntityRow) -> LivMenu {
        let areas = InspectorField.describe("area", in: box.snap).options
        var items: [LivMenuItem] = areas.map { name in
            LivMenuItem(label: name, glyph: LivArea.glyph(named: name)) {
                file(row, under: name)
            }
        }
        items.append(
            LivMenuItem(label: "Not a note…", symbol: "ellipsis.circle", chevron: true) {
                desk.menu = kindMenu(row)
            })
        return LivMenu(
            id: "route-\(row.id)",
            from: .bottom,
            subject: displayTitle(row),
            subjectDetail: "Unfiled capture — where does it go?",
            items: items)
    }

    /// The kinds that are not a note, one door behind the areas.
    /// "Note" is not here: choosing an area already makes one.
    private func kindMenu(_ row: EntityRow) -> LivMenu {
        LivMenu(
            id: "route-kind-\(row.id)",
            from: .bottom,
            subject: displayTitle(row),
            subjectDetail: "What is it, then?",
            items: [
                LivMenuItem(label: "Task", glyph: .task) { routeTask(row) },
                LivMenuItem(label: "Event", glyph: .event) { routeEvent(row) },
                LivMenuItem(label: "Link", glyph: .link) {
                    route(row, to: "link", as: "Link")
                },
            ])
    }

    /// FILED, in one tap: a note, under an area. Two writes, so two
    /// undos — the same count `routeTask` uses for type + status, and
    /// for the same reason: one gesture, one undo, however many cells.
    /// The type goes first so a failure there files nothing, rather
    /// than leaving an area on a thing with no kind.
    private func file(_ row: EntityRow, under area: String) {
        box.setType(row.id, "note") { ok in
            guard ok else { return refused() }
            box.set(row.id, "area", area) { ok in
                ok ? flash("Filed under \(area)", undo: 2) : flash("Routed to Note", undo: 1)
            }
        }
    }

    /// YES to the clerk's guess: the consent lands the area (its own
    /// transaction, so the clerk's ledger records that this one was
    /// taken), then the kind. Same two writes as `file`, same undo
    /// count. A refused consent — the proposal went stale under the
    /// finger — files nothing; the row simply redraws without the chip.
    private func fileSuggested(_ row: EntityRow, _ p: ProposalRow, under area: String) {
        box.accept(p) { ok in
            guard ok else { return refused() }
            box.setType(row.id, "note") { ok in
                ok ? flash("Filed under \(area)", undo: 2) : flash("Area \(area) set", undo: 1)
            }
        }
    }

    /// Task = type + first open status, so it never lands in "No status"
    /// (the old verbs wrote one cell and abandoned the object).
    private func routeTask(_ row: EntityRow) {
        box.setType(row.id, "task") { ok in
            guard ok else { return refused() }
            if let first = taskOptions.first(where: { $0.completes != true })?.name,
                !first.isEmpty
            {
                box.set(row.id, "status", first)
                flash("Routed to Task", undo: 2)
            } else {
                flash("Routed to Task", undo: 1)
            }
        }
    }

    /// Event = type + the date editor, because an event without a date
    /// cannot appear in the Calendar (owner-approved). The sheet is its
    /// own confirmation; dismissing it leaves a dateless event to finish
    /// on the desk.
    private func routeEvent(_ row: EntityRow) {
        box.setType(row.id, "event") { ok in
            guard ok else { return refused() }
            duePick = InboxDuePick(entity: row.id)
        }
    }

    private func route(_ row: EntityRow, to type: String, as label: String) {
        box.setType(row.id, type) { ok in
            ok ? flash("Routed to \(label)", undo: 1) : refused()
        }
    }

    private func refused() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    // MARK: suggested — the clerk's questions, grouped by proposer

    @ViewBuilder private func suggestedSection(
        _ groups: [(author: String, rows: [ProposalRow])]
    ) -> some View {
        if assistOff {
            SectionLabel("Suggested")
            HStack(spacing: 8) {
                Text("Suggestions are off")
                    .font(.system(size: LivType.body))
                    .foregroundStyle(LivTheme.text2)
                Spacer()
                Button("Settings") { settingsShown = true }
                    .font(.system(size: LivType.body, weight: .semibold))
                    .foregroundStyle(LivTheme.accent)
                    .buttonStyle(.borderless)
            }
            .frame(minHeight: LivRow.band)
        } else {
            ForEach(groups, id: \.author) { group in
                groupHeader(group)
                ForEach(group.rows) { p in
                    suggestionRow(p)
                }
            }
        }
    }

    private func groupHeader(
        _ group: (author: String, rows: [ProposalRow])
    ) -> some View {
        // THE SAME HEADING EVERY OTHER LIST USES. It was a literal ✦
        // in amber, then the proposer's name in bold kerned caps, then
        // the count — a decoration and a shout, on a heading whose job
        // is to be findable when you look for it and invisible when you
        // do not. `SectionLabel`'s own comment has said exactly that
        // since 2026-08-18; this heading was hand-rolled and never got
        // the message (standing rule 4).
        HStack(spacing: 7) {
            Text(group.author.capitalized)
                .font(.system(size: LivType.label, weight: .medium))
                .foregroundStyle(LivTheme.text2)
            Text("\(group.rows.count)")
                .font(.system(size: LivType.label).monospacedDigit())
                .foregroundStyle(LivTheme.text3)
            Spacer()
            if group.rows.count > 1 {
                Button {
                    box.acceptGroup(group.rows.compactMap(\.fingerprint)) { ok in
                        if !ok { refused() }
                    }
                } label: {
                    // A WORD, the way `SectionLabel` draws its trailing
                    // verb — not a filled and outlined capsule. Three
                    // devices for one link.
                    Text("Accept all")
                        .font(.system(size: LivType.label, weight: .medium))
                        .foregroundStyle(LivTheme.accent)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            }
        }
        // THE ROOM A HEADING OWNS, from the type that owns it. 14 and 2
        // were this heading's own numbers, from before `sectionTop` and
        // `sectionBottom` existed — so it was the one heading in the app
        // standing on 35.1 while every `SectionLabel` stood on 41.1.
        // Its own comment above already confesses the shape of this:
        // hand-rolled, and it never got the message.
        //
        // The verb's `.frame(height: 24)` went in the same change. It
        // was what made this row 40 with an Accept-all and 35.1
        // without — two heights for one heading — and `SectionLabel`'s
        // trailing verb, on all seventeen of its call sites, has never
        // had one. The `contentShape` is what carries the hit area,
        // there as here. If the verb wants a bigger target it wants one
        // in `SectionLabel`, for all eighteen.
        .padding(.top, LivRow.sectionTop).padding(.bottom, LivRow.sectionBottom)
    }

    /// What this suggestion is ABOUT. The proposal carries the entity id;
    /// the shell already knows how to turn one into a title.
    private func title(of p: ProposalRow) -> String {
        guard let id = p.entity, let row = box.entity(id) else { return "Untitled" }
        return livRowTitle(row)
    }

    /// A SUGGESTION, IN THE SHAPE OF A TASK.
    ///
    /// Rebuilt 2026-08-30 against `~/Desktop/Throwaway/new/todoist-inbox.mov`,
    /// measured frame by frame rather than approximated: an 18pt screen
    /// margin, a 24pt circle, 15pt of air, the words at 57, a 17pt title
    /// with a 13pt metadata line under it, and a hairline that starts at
    /// the WORDS rather than at the screen edge. Ours is that shape at
    /// this app's own 16pt margin — `LivRow.margin`, `.mark`, `.markGap`,
    /// `.text`, which is also `.hairline`.
    ///
    /// THE CIRCLE IS THE ACCEPT. This row used to carry two 44pt buttons
    /// on the right, so nine suggestions meant eighteen controls and a
    /// column of ticks down the edge. Todoist empties its inbox by
    /// ticking a circle on the left, and agreeing with a suggestion is
    /// the same motion: you tick it and it goes. Accepting is not
    /// destructive so it acts at once; dismissing IS a discard, so it
    /// keeps a control of its own and still asks first — in the same
    /// card the routing question uses (`rejectMenu`).
    ///
    /// What that buys beyond the look: the Inbox reads as a pile you can
    /// empty, which is what an inbox is.
    private func suggestionRow(_ p: ProposalRow) -> some View {
        HStack(alignment: .center, spacing: 0) {
            Button { box.accept(p) } label: {
                // DRAWN AT 21, TAPPED AT 24 WIDE BY 44 TALL. The column
                // is the reference's 24 and cannot grow without pushing
                // every title right, but its HEIGHT is free — the row is
                // taller than the circle either way. A `.padding(10)
                // .contentShape().padding(-10)` pair was tried first to
                // widen it and it made the button stop responding
                // altogether: measured, reverted, not guessed at.
                Circle()
                    .strokeBorder(LivTheme.text3, lineWidth: 1.5)
                    .frame(width: 21, height: 21)
                    .frame(width: LivRow.mark, height: 44)
                    .contentShape(Rectangle())
            }
            // BORDERLESS, NOT PLAIN. Inside a `List`, `.plain` hands the
            // whole row to one tap target, so this circle drew correctly
            // and did nothing at all — caught by tapping it and watching
            // the Tidy count stay at 12. `.borderless` is what lets two
            // controls in one row be pressed independently, which is why
            // the buttons this replaced used it.
            .buttonStyle(.borderless)
            .accessibilityLabel("Accept")
            .padding(.trailing, LivRow.markGap)

            // A SENTENCE ABOUT YOUR THINGS, not a command diff (owner,
            // 2026-08-20: "so many color blips and tags, plus cryptic
            // messages crammed into rows"). The row used to lead with up
            // to three chips rendering the raw writes — "+ created ·
            // 2026-08-…", "– trash", "+ redirect" — which is the
            // proposal's implementation, not its meaning, and left the
            // reader to guess WHICH note was about to change. The name
            // was on the wire the whole time (`ProposalRow.entity`).
            // ONE LINE: the NAME of the thing, and nothing else.
            //
            // The row carried the proposal's reason under the title —
            // "exact duplicate → merge into #4269?" — at 13pt in the
            // dimmest ink (owner, 2026-08-31: "tiny and should not
            // appear directly there (if at all)"). Three things were
            // wrong with it and they compound: it is small enough to be
            // unreadable, it repeats what the group heading two rows up
            // already says ("Dedupe"), and the part that is NOT in the
            // heading is `#4269` — a raw entity id, which is jargon in a
            // surface the owner reads (his rule, 2026-08-07: no jargon,
            // say what it means).
            //
            // What is left is what Todoist's row is: a circle, a name,
            // and a way out. The heading carries the reason for the
            // whole group, which is the level the reason is actually
            // true at.
            Text(title(of: p))
                .font(.system(size: LivType.body))
                .foregroundStyle(LivTheme.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let value = proposedValue(p) {
                // WHAT SAYING YES WRITES. The heading names the field and
                // the title names the note; until 2026-09-09 nothing on
                // the row named the VALUE, and an "Area" row read as
                // "something with area" (owner, on the simulator). For a
                // date or a mention the value is usually in the title's
                // own words; for an area it never is.
                ValueChip(value)
                    .padding(.trailing, 6)
            }
            Button {
                desk.menu = rejectMenu(p)
            } label: {
                // THE APP'S OWN RECIPE for this exact action — the
                // properties card's reject draws it at `body` semibold
                // in 44x44. This was 16pt regular in 40x40: 60% of the
                // accept circle's ink beside it, and under Apple's
                // touch minimum in both axes.
                Image(systemName: "xmark")
                    .font(.system(size: LivType.body, weight: .semibold))
                    .foregroundStyle(LivTheme.text3)
                    .frame(width: LivRow.touch, height: LivRow.touch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss")
        }
        .padding(.vertical, 6)
        .frame(minHeight: LivRow.height)
        .contentShape(Rectangle())
        .onTapGesture {
            if let entity = p.entity { desk.open(entity) }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
                .padding(.leading, LivRow.hairline - LivRow.margin)
        }
    }

    /// The one value a ONE-CELL suggestion would write — an area, a date,
    /// a name, a priority — as the wire displays it. Nothing for a
    /// proposal of several commands: a merge's first cell is whatever the
    /// loser happened to carry and says nothing about the merge, and a
    /// promotion's heading already says what it makes.
    private func proposedValue(_ p: ProposalRow) -> String? {
        guard let commands = p.commands, commands.count == 1,
            let value = commands[0].value, !value.isEmpty
        else { return nil }
        return value
    }

    private func flash(_ text: String, undo: Int) {
        withAnimation(LivMotion.nav) {
            chipText = text
            chipUndo = undo
        }
        let shown = text
        // 5s, the desk's trash-chip window — an undo offer must outlive
        // the glance that notices it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            guard chipText == shown else { return }
            withAnimation(LivMotion.nav) { chipText = nil }
        }
    }

    private func chip(_ text: String) -> some View {
        HStack(spacing: 12) {
            Text(text)
                .font(.system(size: LivType.body, weight: .medium))
                .foregroundStyle(LivTheme.text)
            Button("Undo") {
                for _ in 0..<max(1, chipUndo) { box.undo() }
                withAnimation(LivMotion.nav) { chipText = nil }
            }
            .font(.system(size: LivType.body, weight: .semibold))
            .foregroundStyle(LivTheme.accent)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(LivTheme.panel2, in: Capsule())
        .overlay(Capsule().strokeBorder(LivTheme.border, lineWidth: 0.5))
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: small helpers

    private func displayTitle(_ row: EntityRow) -> String { livRowTitle(row) }

    private func stamp(_ row: EntityRow) -> String {
        guard let created = row.created, created > 0 else { return "" }
        let day = Civil.day(of: created)
        if day == Civil.todayDay() {
            let t = Civil.timeString(created)
            return t.isEmpty ? "today" : t
        }
        return Civil.dayLabel(day)
    }
}
