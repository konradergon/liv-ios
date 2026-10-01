// liv iOS — Unsorted (rebuilt 2026-09-22; owner: "why have Tidy and
// Route instead of just one list?"). ONE LIST: every note, task and
// event with no area, newest first, each wearing the clerk's guess at
// where it goes — one tap says yes. Under it, the clerk's other
// questions (dates, mentions, priority). No lenses.
//
// Why it exists (owner, 2026-09-22): things WILL be made without anyone
// pressing the metadata button, and a box of a million anonymous things
// is a box nobody can search. This screen is where that pile is visible
// and cheap to clear; the guess on each row is what makes clearing it a
// tap instead of a chore.
//
// The feature's rawValue stays `inbox` — it is written into saved
// planes — and only the word a person reads changed.

import SwiftUI
import UIKit

/// The row a sheet is about: the date picker (the Event verb's second
/// half) or the area picker (New area…).
private struct InboxPick: Identifiable {
    let entity: LivEntityID
    var id: LivEntityID { entity }
}

struct InboxView: View {
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var workspaces: WorkspaceModel

    @State private var taskOptions: [StatusOption] = []
    @State private var duePick: InboxPick?
    @State private var areaPick: InboxPick?
    @State private var settingsShown = false
    /// The proposal a ✕ is about to dismiss — rejection is PERMANENT
    /// (the clerk never re-asks), so it costs one ask.
    /// The transient acknowledgment: what routed, and how many
    /// transactions its Undo must take back.
    /// The row a swipe has lifted out of its card (`livSwipeLift`).
    @State private var lifted: AnyHashable?
    @State private var chipText: String?
    @State private var chipUndo = 0

    /// WHAT IS UNSORTED is Rust's answer (`is_unsorted`, in
    /// `surface/src/library.rs`), newest first — the same list the library
    /// panel counts, so the number beside the door and the rows behind it
    /// cannot disagree (they did, twice, in September). Rust also keeps
    /// the safety rule: the workspace lens is never applied here
    /// (design/ios.md M4), or a capture made under the wrong lens would
    /// appear to vanish.
    private var scraps: [EntityRow] {
        // THE INDEX, NOT A CELL FETCH. `box.entity(id)` asks the box for
        // one row's cells, so mapping it over every id kicked off a
        // `liv_cells` call for the whole list on this screen's first
        // render and republished once per answer. `live` only looks.
        box.lists.unsorted.compactMap { box.live($0) }
    }

    /// The clerk's pending queue, minus the shapes the accept seam cannot
    /// take yet: triage() only matches AddCell-first proposals, so a
    /// Trash-first merge would render as a card whose ✓ returns 0 forever
    /// (the filed FFI chip). Until that lands, they stay out of the list.
    private var proposals: [ProposalRow] {
        // An area guess about an unsorted thing is asked ON ITS ROW
        // (`suggestedArea`), not a second time here: asking it twice
        // would count one decision twice.
        let unrouted = Set(scraps.map(\.id))
        // NO SHAPE GATE. It kept only proposals whose first command was
        // an `add`, and since the engine swap on 2026-09-14 no proposal
        // has carried commands at all — so this lens has been empty for
        // five days while the clerk swept five proposers (found
        // 2026-09-18). The gate guarded an accept seam that no longer
        // exists: accepting is `liv_accept` by fingerprint, which
        // re-derives the proposal on the engine and takes whatever shape
        // it is.
        return (box.snap?.inbox ?? []).filter {
            !($0.author == "area" && unrouted.contains($0.entity ?? .absent))
        }
    }

    /// THE CLERK'S GUESS AT WHERE THIS GOES (2026-09-09, owner's word):
    /// the pending `area` proposal for a scrap, and the area it names.
    /// The clerk reads it off what the capture mentions — a thought
    /// about Sam belongs where Sam is filed (`clerk.rs`, `propose_area`).
    private func suggestedArea(_ row: EntityRow) -> (p: ProposalRow, area: String)? {
        guard
            let p = (box.snap?.inbox ?? []).first(where: {
                $0.entity == row.id && $0.author == "area"
            }),
            let area = p.proposed, !area.isEmpty
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

    /// The clerk's area guesses standing on this list's rows, for the
    /// one-tap accept-all.
    private func guesses(_ scraps: [EntityRow]) -> [ProposalRow] {
        scraps.compactMap { suggestedArea($0)?.p }
    }

    var body: some View {
        let scraps = self.scraps
        let groups = proposalGroups
        let guessed = guesses(scraps)

        List {
            Group {
                // THE NAME, AND HOW MANY (the clearer board): "6 things
                // without an area". The lens note rides in the same line —
                // it explains an EXCEPTION: this one list ignores the
                // workspace (owner, 2026-08-06), so a thing made under the
                // wrong workspace cannot vanish.
                LivTitleBlock("Unsorted", subtitle: subtitle(scraps.count))
                    .listRowInsets(LivRow.fullWidth)

                if scraps.isEmpty {
                    EmptyHint("Nothing unsorted")
                } else {
                    if guessed.count > 1 && !assistOff {
                        fileAllByGuess(guessed)
                    }
                    ForEach(livCardSlots(scraps)) { s in
                        routeCard(s.item, position: s.position)
                    }
                }

                // THE CLERK'S OTHER QUESTIONS, under the pile rather than
                // behind a second lens. Area guesses on unsorted rows are
                // not repeated here — they are on their rows above.
                if !groups.isEmpty || assistOff {
                    suggestedSection(groups)
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
        .sheet(item: $areaPick) { pick in
            // THE INSPECTOR'S OWN PICKER, reporting instead of writing, so
            // filing from here stays one gesture with one Undo whether
            // the area is old or typed new.
            InspectorValueSheet(
                field: InspectorField.describe("area", in: box.snap),
                id: pick.entity, current: [],
                onPick: { (value: String?) in
                    guard let value, let row = box.entity(pick.entity) else { return }
                    fileNew(row, under: value)
                },
                startTyping: true
            )
            .environmentObject(box)
        }
        .sheet(isPresented: $settingsShown) { SettingsSheet() }
        .livAckChip(chipText) {
            for _ in 0..<max(1, chipUndo) { box.undo() }
            withAnimation(LivMotion.nav) { chipText = nil }
        }
        // No refresh here. This `onAppear` asked for a whole one back when
        // the sweep was part of every refresh; the sweep is read while
        // Unsorted is on screen now (`BoxModel.screenChanged`), and when
        // it comes back.
        .onAppear {
            box.statusOptions(kind: "task") { taskOptions = $0 }
        }
    }

    // MARK: the pile — a card per unsorted thing

    /// "6 things", "1 thing" — a count, never an explanation (owner,
    /// 2026-09-29: "the interface should explain itself"). The list still
    /// ignores the workspace lens (M4); it no longer says so. Nothing to
    /// count: no line.
    private func subtitle(_ count: Int) -> String? {
        count == 0 ? nil : "\(count) thing\(count == 1 ? "" : "s")"
    }

    /// SAY YES TO EVERY GUESS AT ONCE — when the clerk has guessed for two
    /// or more. The guesses are on the rows, so you have read what you
    /// are accepting. It was the "Accept N guesses" chip beside the count;
    /// on the clearer board it is a flat capsule of its own under the
    /// title, the same call and the same rule for when it shows.
    private func fileAllByGuess(_ guessed: [ProposalRow]) -> some View {
        HStack {
            Button {
                box.acceptGroup(guessed.compactMap(\.fingerprint)) { ok in
                    if !ok { refused() }
                }
            } label: {
                HStack(spacing: LivChip.verbGap) {
                    LivIcon(glyph: .check, color: LivTheme.text, size: LivPen.chip)
                    Text("File all \(guessed.count)")
                        .font(.system(size: LivType.label, weight: .semibold))
                        .foregroundStyle(LivTheme.text)
                }
                .padding(.horizontal, LivChip.verbPad)
                .frame(height: LivChip.verb)
                .background(Capsule().fill(LivTheme.panel2))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        // 4 under the capsule plus the 14 the board leaves before the card
        // — on this row, never as padding inside the card's first row.
        .padding(.bottom, LivChip.verbUnder + LivTitle.bottom)
    }

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
    private func routeCard(_ row: EntityRow, position: LivCardPosition) -> some View {
        Button {
            desk.menu = routeMenu(row)
        } label: {
            routeFace(row, divided: position.divided)
        }
        .livRowPress(position)
        .livDoor()
        .livSwipeLift(row.id, $lifted)
        .livCardRow(position: position, lifted: livIsLifted(row.id, lifted))
        // `allowsFullSwipe: false` on purpose: an unrouted capture must
        // not be thrown away by a thumb that kept going.
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            livTrashAction { box.trash(row.id) }
        }
    }

    /// The card row: the kind's glyph in ink, the title over "Note · 09:41"
    /// (what it is, and when it came in), and the clerk's guess, if any.
    private func routeFace(_ row: EntityRow, divided: Bool) -> some View {
        let kind = LivKind.of(row).word
        let when = stamp(row)
        return LivCardRow(
            glyph: LivKind.glyph(of: row), title: displayTitle(row),
            detail: when.isEmpty ? kind : "\(kind) · \(when)",
            divided: divided, titleLines: 2
        ) {
            if let guess = suggestedArea(row) {
                // THE ANSWER, PENCILLED IN. One tap says yes and files it
                // — the same two writes tapping the area in the route card
                // makes, with the clerk's consent recorded on the way.
                // Tapping the row still opens the card, with every other
                // area in it: the guess is offered, never imposed.
                Button {
                    fileSuggested(row, guess.p, under: guess.area)
                } label: {
                    HStack(spacing: LivChip.guessGap) {
                        LivIcon(glyph: .area, color: LivTheme.text2, size: LivPen.chip)
                        Text("\(guess.area)?")
                            .font(.system(size: LivType.label, weight: .medium))
                            .foregroundStyle(LivTheme.text)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, LivChip.guessPad)
                    .frame(height: LivChip.guess)
                    .background(Capsule().fill(LivTheme.panel2))
                    .contentShape(Capsule())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("File under \(guess.area)")
            }
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
    /// Now the person's areas lead, read from the same property the
    /// inspector reads, with a door to make a new one. Tapping one
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
            LivMenuItem(label: name, glyph: .area) {
                file(row, under: name)
            }
        }
        // A NEW AREA FROM HERE. Areas are the user's own since 2026-09-21
        // and a fresh box has none, so without this door the card asked
        // "where does it go?" and offered nowhere.
        items.append(
            LivMenuItem(label: areas.isEmpty ? "Make an area…" : "New area…", symbol: "plus", chevron: true) {
                areaPick = InboxPick(entity: row.id)
            })
        // THE KIND DOOR IS ONLY FOR A THING WITH NO KIND. Since the
        // Inbox became the unfiled queue (2026-09-19) a task or an event
        // can stand in this list, and for those the card has exactly one
        // question — where does it go. What a thing IS, once it is
        // something, is changed on its own card, not behind the filing
        // menu.
        let untyped = LivKind.of(row) == .capture
        if untyped {
            items.append(
                LivMenuItem(label: "Not a note…", symbol: "ellipsis.circle", chevron: true) {
                    desk.menu = kindMenu(row)
                })
        }
        return LivMenu(
            id: "route-\(LivIDText.written(row.id))",
            from: .bottom,
            subject: displayTitle(row),
            items: items,
            atDoor: true)
    }

    /// The kinds that are not a note, one door behind the areas.
    /// "Note" is not here: choosing an area already makes one.
    private func kindMenu(_ row: EntityRow) -> LivMenu {
        LivMenu(
            id: "route-kind-\(LivIDText.written(row.id))",
            from: .bottom,
            subject: displayTitle(row),
            items: [
                LivMenuItem(label: "Task", glyph: .task) { routeTask(row) },
                LivMenuItem(label: "Event", glyph: .event) { routeEvent(row) },
                LivMenuItem(label: "Link", glyph: .link) {
                    route(row, to: "link", as: "Link")
                },
            ],
            atDoor: true)
    }

    /// FILED, in one tap: a note, under an area. Two writes, so two
    /// undos — the same count `routeTask` uses for type + status, and
    /// for the same reason: one gesture, one undo, however many cells.
    /// The type goes first so a failure there files nothing, rather
    /// than leaving an area on a thing with no kind.
    private func file(_ row: EntityRow, under area: String) {
        // A ROW THAT ALREADY KNOWS WHAT IT IS KEEPS ITS KIND. Filing
        // answers WHERE; only a thing with no kind at all also needs
        // WHAT. Since the Inbox became the unfiled queue (2026-09-19) an
        // unanswered task or event can stand in this list, and writing
        // "note" over it would answer a question nobody asked — and lose
        // the row's status or its date along with its kind.
        guard LivKind.of(row) == .capture else {
            return box.set(row.id, "area", area) { ok in
                ok ? flash("Filed under \(area)", undo: 1) : refused()
            }
        }
        box.setType(row.id, "note") { ok in
            guard ok else { return refused() }
            box.set(row.id, "area", area) { ok in
                ok ? flash("Filed under \(area)", undo: 2) : flash("Routed to Note", undo: 1)
            }
        }
    }

    /// Filing under an area the picker may have just been TYPED into: a
    /// name the vocabulary lacks is minted first (the engine refuses a
    /// value with no entity behind it), then filed as usual.
    private func fileNew(_ row: EntityRow, under area: String) {
        let field = InspectorField.describe("area", in: box.snap)
        guard !field.options.contains(where: { $0.compare(area, options: .caseInsensitive) == .orderedSame })
        else { return file(row, under: area) }
        guard !field.propertyId.isAbsent else { return refused() }
        box.addOption(field.propertyId, area) { made in
            made == .absent ? refused() : file(row, under: area)
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
            // Same rule as `file`: the consent lands the area, and only
            // an untyped thing also gets a kind.
            guard LivKind.of(row) == .capture else {
                return flash("Filed under \(area)", undo: 1)
            }
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
            guard let first = taskOptions.first(where: { $0.completes != true })?.name,
                !first.isEmpty
            else { return stillUnfiled("task", undo: 1) }
            // THE FLASH WAITS FOR THE WRITE. It promised two undos before
            // the status write had landed, so a refused one sent the
            // second undo past the routing and into whatever came
            // before — for a fresh capture, the capture itself, which
            // Undo then took back with no trash entry to find it in.
            // `file` has always done it this way.
            box.set(row.id, "status", first) { ok in
                stillUnfiled("task", undo: ok ? 2 : 1)
            }
        }
    }

    /// A KIND IS NOT AN ADDRESS. These verbs answer WHAT, and the Inbox
    /// lists what has no WHERE — so the row stays, now wearing its kind,
    /// and the card it opens has one question left. Saying "routed"
    /// would promise a departure that does not happen (2026-09-19).
    private func stillUnfiled(_ kind: String, undo: Int) {
        flash("Now a \(kind)", undo: undo)
    }

    /// Event = type + the date editor, because an event without a date
    /// cannot appear in the Calendar (owner-approved). The sheet is its
    /// own confirmation; dismissing it leaves a dateless event to finish
    /// on the desk.
    private func routeEvent(_ row: EntityRow) {
        box.setType(row.id, "event") { ok in
            guard ok else { return refused() }
            duePick = InboxPick(entity: row.id)
        }
    }

    private func route(_ row: EntityRow, to type: String, as label: String) {
        box.setType(row.id, type) { ok in
            ok ? stillUnfiled(label.lowercased(), undo: 1) : refused()
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
            LivCardRow(
                "Suggestions are off", muted: true, divided: false, rule: LivCards.ruleBare,
                lead: { EmptyView() },
                trailing: {
                    // A CHIP, not an accent word: a quiet secondary verb
                    // wears the hollow chip; the only clickable TEXT in
                    // this app is a link inside a note.
                    AddChip("Settings", symbol: "gearshape") { settingsShown = true }
                })
                .livCardRow(position: .only)
        } else {
            ForEach(groups, id: \.author) { group in
                groupHeader(group)
                ForEach(livCardSlots(group.rows)) { s in
                    suggestionRow(s.item, position: s.position)
                }
            }
        }
    }

    /// One heading per proposer, the app's own: the name, its count beside
    /// it, and — for two or more — "Accept all" as the heading's trailing
    /// button (a flat row-size capsule, like the board's other quiet verbs).
    private func groupHeader(
        _ group: (author: String, rows: [ProposalRow])
    ) -> some View {
        SectionLabel(group.author.capitalized, count: group.rows.count) {
            if group.rows.count > 1 {
                Button {
                    box.acceptGroup(group.rows.compactMap(\.fingerprint)) { ok in
                        if !ok { refused() }
                    }
                } label: {
                    Text("Accept all")
                        .font(.system(size: LivType.label, weight: .medium))
                        .foregroundStyle(LivTheme.text)
                        .padding(.horizontal, LivChip.guessPad)
                        .frame(height: LivChip.guess)
                        .background(Capsule().fill(LivTheme.panel2))
                        .contentShape(Capsule())
                }
                .buttonStyle(.borderless)
            }
        }
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
    /// the WORDS rather than at the screen edge. Ours is a `LivCardRow`
    /// on the card metrics (`LivCards`), with the accept circle at
    /// `LivCheck.size`.
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
    private func suggestionRow(_ p: ProposalRow, position: LivCardPosition) -> some View {
        LivCardRow(
            title(of: p), detail: proposedValue(p), divided: position.divided,
            lead: {
                // THE CIRCLE IS THE ACCEPT — Todoist empties its inbox by
                // ticking a circle on the left, and agreeing with a
                // suggestion is the same motion. BORDERLESS, NOT PLAIN:
                // inside a List, `.plain` hands the whole row to one tap
                // target and this circle would do nothing at all.
                Button { box.accept(p) } label: {
                    Circle()
                        .strokeBorder(LivTheme.text2, lineWidth: LivCheck.stroke)
                        .frame(width: LivCheck.size, height: LivCheck.size)
                        .livRowControl(width: LivCards.mark)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Accept")
            },
            trailing: {
                // Dismissing IS a discard, so it keeps a control of its
                // own and still asks first (`rejectMenu`).
                Button {
                    desk.menu = rejectMenu(p)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: LivType.body, weight: .semibold))
                        .foregroundStyle(LivTheme.text2)
                        .livRowControl(width: LivRow.touch)
                }
                .buttonStyle(.borderless)
                .livDoor()
                .accessibilityLabel("Dismiss")
            }
        )
        .onTapGesture {
            if let entity = p.entity { desk.open(entity) }
        }
        .livCardRow(position: position)
    }

    /// The one value a ONE-CELL suggestion would write — an area, a date,
    /// a name, a priority — as the wire displays it. Nothing for a
    /// proposal of several commands: a merge's first cell is whatever the
    /// loser happened to carry and says nothing about the merge, and a
    /// promotion's heading already says what it makes.
    private func proposedValue(_ p: ProposalRow) -> String? {
        guard let value = p.proposed, !value.isEmpty else { return nil }
        return value
    }

    private func flash(_ text: String, undo: Int) {
        withAnimation(LivMotion.nav) {
            chipText = text
            chipUndo = undo
        }
        let shown = text
        DispatchQueue.main.asyncAfter(deadline: .now() + LivMotion.offerSeconds) {
            guard chipText == shown else { return }
            withAnimation(LivMotion.nav) { chipText = nil }
        }
    }

    // MARK: small helpers

    private func displayTitle(_ row: EntityRow) -> String { livRowTitle(row) }

    /// When it came in, in Apple's words: "09:41" today, "Yesterday", the
    /// weekday this week, else "18 Sep". Empty when it has no stamp.
    private func stamp(_ row: EntityRow) -> String {
        guard let created = row.created, created > 0 else { return "" }
        return Civil.fact(created)
    }
}
