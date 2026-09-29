// liv iOS — the metadata editor (design/ios.md §6). EntityInspector is
// everything ABOUT a thing and nothing OF it: kinds, due shortcuts,
// status menu, one compact row per property, trash + undo. Add-property
// lives behind the Settings door (§10 — schema growth is not daily use).
//
// It is hosted twice and pushes nothing: the properties sheet card
// (App.swift) and the record card (Record.swift). The Desk body owns
// the title.
//
// CONTENT editing is not here. It lands through `Box.setContent`, a
// compare-and-swap on the base fingerprint with no force flag by
// design — a stale base is re-read, never overwritten.
//
// Hairline separators, no cards.
//
// (Rewritten 2026-09-07. Three of this header's claims had rotted: it
// called the inspector "the desktop right-panel inspector" — there is
// no desktop shell since Tauri was dropped on 2026-08-29 — it named a
// "Details chip row" that no longer exists anywhere in this file, and
// it said content editing "waits for M2 (CAS)", which shipped. It also
// carried a row height in prose, which is a token's job.)

import SwiftUI

// MARK: - the field descriptor: what a property IS, before any UI

/// One editable property, described from the SNAPSHOT rather than from a
/// hardcoded list. Every editing behaviour the sheet needs is a property
/// of the data, not a branch in the view: whether the vocabulary is
/// closed (a select — no create row, §10's fixed furniture), whether the
/// field holds several values at once, and how a value is written.
struct InspectorField: Identifiable {
    var id: String { property }
    /// THE TOKEN — `area`, `tags`. What every write and lookup spells,
    /// and never what is drawn.
    let property: String
    /// WHAT A PERSON READS. Usually the same word; `tags` reads
    /// "Subject" (owner, 2026-09-16: "what is 'Tags' in new filter and
    /// new workspace? should be Subject"), because a tag in this app is
    /// what a thing is ABOUT.
    ///
    /// **The box owns it, not this file.** A shell carrying its own copy
    /// of the furniture's words is the mistake `one-core.md` §4 records,
    /// so this is `liv_properties`' `name` — which also means a field
    /// someone renames shows the new word here with nothing to change.
    let shown: String
    /// The core's value kind: "select", "reference", "datetime", "text"…
    let kind: String
    /// Several values at once (membership, addCell) versus one (set).
    let multi: Bool
    /// The vocabulary a select already holds. NOT a closed one any more
    /// — see `closed`.
    let options: [String]
    /// The property's own id, so a new option can be minted against it.
    let propertyId: LivEntityID

    /// NOTHING IS CLOSED (owner, 2026-08-29: "make sure areas are not
    /// fixed anymore").
    ///
    /// A select used to refuse the create row, on §10's fixed furniture:
    /// six areas, researched not invented, and `what-liv-is-for.md` said
    /// in as many words that areas "don't grow". That is amended there,
    /// with the reason and the date.
    ///
    /// The six are still what the app arrives with, and that was always
    /// the more important half — a person opens Liv and does not have to
    /// design a system. What changes is that the walls the doc admitted
    /// to ("someone whose life doesn't divide into these six areas will
    /// feel the walls") are no longer walls.
    var closed: Bool { false }

    /// **ITS VALUES ARE ENTITIES, NOT STRINGS.** A name the vocabulary
    /// has never heard of is refused by the engine, so one typed here
    /// has to be minted before it can be written.
    ///
    /// This was spelled `kind == "select"` at the one place that needed
    /// it. `area` does not arrive as a select — the engine holds it as
    /// `RefTo(Area)`, which crosses the ABI as "reference" — so typing a
    /// new area minted nothing, the write was refused for a name with no
    /// entity behind it, and the area was neither assigned nor rendered
    /// while picking an EXISTING one worked perfectly (owner,
    /// 2026-09-14). A rule in a type rather than in a branch (standing
    /// rule 3).
    var mintsValues: Bool { kind == "select" || kind == "reference" }

    /// The fields every note shows even when empty — the "zero fill
    /// pressure" core (design/editor-study.md §8: two filled fields is a
    /// finished object). Everything else appears only once it has a value.
    static let core = ["area", "project", "tags", "people"]

    /// Multi-valued by name — the same rule the camera's chip editor uses
    /// (Camera.swift's CameraChipKind.multi): tags and people accumulate,
    /// area and project replace.
    static func isMulti(_ property: String) -> Bool {
        property == "tags" || property == "people"
    }

    /// Describe a property from the live snapshot.
    ///
    /// **MATCHED ON THE TOKEN, not on the word.** It compared against
    /// `name`, which is what a person reads — so the moment `tags` began
    /// reading "Subject" this would have found no row for it, and the
    /// field would have come back kind `text` with id 0: no vocabulary,
    /// no mint, nothing written. That is precisely how the area picker
    /// broke on 2026-09-14, so the two words ship together and the match
    /// moved in the same change.
    static func describe(_ property: String, in snap: Snapshot?) -> InspectorField {
        let row = (snap?.properties ?? []).first {
            ($0.word ?? $0.name ?? "").compare(property, options: .caseInsensitive)
                == .orderedSame
        }
        let options = (row?.options ?? [])
            .filter { $0.hidden != true }
            .compactMap { $0.name }
            .filter { !$0.isEmpty }
        return InspectorField(
            property: property,
            // The box's word, and the token when the box has never heard
            // of this property — which is a fault elsewhere, and drawing
            // the token is more use than drawing nothing.
            shown: row?.name ?? property,
            kind: row?.kind ?? "text",
            multi: isMulti(property),
            options: options,
            propertyId: row?.id ?? .absent)
    }
}

// MARK: - the inspector (full-body; no title, no nav chrome)

struct EntityInspector: View {
    let id: LivEntityID
    /// The panel scrolls; embedded as a record's body (Record.swift) it
    /// must NOT — a scroll view inside a scroll view eats the gesture.
    var scrolls: Bool = true
    /// A thing created a moment ago: open with the caret in the name.
    var autoFocus: Bool = false

    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel

    @State private var options: [StatusOption] = []
    @State private var showDueSheet = false
    /// The name being typed. Seeded from the name CELL, never from
    /// `row.title` — the wire title is derived, and putting it in the
    /// field would make merely opening the card able to write it.
    @State private var draftName = ""
    @State private var nameSeeded = false
    /// The name already handed to the box and not yet visible in the
    /// snapshot. Return commits, then the blur commits again a beat
    /// later — without this the box logged the same rename twice
    /// (found live, 2026-08-06).
    @State private var pendingName: String?
    @State private var focusClaimed = false
    @FocusState private var nameFocused: Bool
    /// The field whose sheet is open. One sheet serves every property.
    @State private var editing: InspectorField?

    init(id: LivEntityID, scrolls: Bool = true, autoFocus: Bool = false) {
        self.id = id
        self.scrolls = scrolls
        self.autoFocus = autoFocus
    }

    var body: some View {
        Group {
            if let row = box.entity(id) {
                list(row)
            } else {
                EmptyHint("Deleted")
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .sheet(item: $editing) { field in
            InspectorValueSheet(
                field: field, id: id,
                current: values(of: field.property, in: box.entity(id))
            )
            .environmentObject(box)
        }
        .sheet(isPresented: $showDueSheet) {
            DetailDueSheet(
                model: box, id: id,
                property: dueProperty(box.entity(id))
            )
            .presentationDetents([.medium])
        }
        .tint(LivTheme.accent)
        .onAppear {
            seedName()
            claimFocus()
            box.statusOptions(kind: box.entity(id)?.kinds?.first ?? "") {
                options = $0
            }
        }
        // The record card sets `autoFocus` in ITS onAppear, which runs
        // AFTER this one — the same ordering the note editor works around.
        .onChange(of: autoFocus) { _, now in
            if now { claimFocus() }
        }
        .onChange(of: LivName.stored(box.entity(id))) { old, fresh in
            if pendingName == fresh { pendingName = nil }
            // The snapshot moved under us — an undo, or the desk's own
            // title field, which edits the same cell. Compared against
            // the OLD stored name; `LivName.reseed` carries the reason.
            if let seed = LivName.reseed(draft: draftName, was: old, now: fresh) {
                draftName = seed
            }
        }
    }

    /// Once per open. A note with no name cell seeds EMPTY, so the grey
    /// prompt (the derived title) shows through and typing over it is
    /// what writes the name — nothing is written by merely opening.
    private func seedName() {
        guard !nameSeeded else { return }
        draftName = LivName.stored(box.entity(id))
        nameSeeded = true
    }

    /// @FocusState set during a view update is dropped; one runloop hop
    /// later it takes.
    private func claimFocus() {
        guard autoFocus, !focusClaimed else { return }
        focusClaimed = true
        DispatchQueue.main.async { nameFocused = true }
    }

    private func commitName() {
        switch LivName.commit(typed: draftName, row: box.entity(id), pending: pendingName) {
        case .write(let typed):
            pendingName = typed
            box.set(id, "name", typed)
        case .revert(let stored): draftName = stored
        case .ignore: break
        }
    }

    @ViewBuilder private func list(_ row: EntityRow) -> some View {
        if scrolls {
            ScrollView { rows(row) }
        } else {
            rows(row)
        }
    }

    /// THE ITEM'S NAME, as a field — a note's can be renamed here as a
    /// record's can (owner, todo.org). Nothing under it: the board's
    /// "Note · edited today 21:04" line came off on the owner's word
    /// (2026-09-29).
    ///
    /// ONE HEADER FOR EVERY THING (owner, 2026-09-28): the record
    /// card drew its own name field — 32 semibold, its own commit —
    /// above this one switched off, and the two drifted apart.
    /// "name" stays in `skipSet`: this line IS the name row.
    private func header(_ row: EntityRow) -> some View {
        TextField(livRowTitle(row), text: $draftName, axis: .vertical)
            .font(.system(size: LivType.display, weight: .bold))
            .foregroundStyle(LivTheme.text)
            .lineLimit(1...3)
            .focused($nameFocused)
            .submitLabel(.done)
            .onSubmit(commitName)
            // See `livNameReturn`: a vertical-axis field never calls
            // `.onSubmit`.
            .livNameReturn($draftName, $nameFocused)
            .onChange(of: nameFocused) { _, now in
                if !now { commitName() }
            }
            .accessibilityLabel("Name")
            .padding(.top, LivHeader.sheetTop)
            .padding(.horizontal, LivTitle.side)
            .padding(.bottom, LivDetail.headerBottom)
    }

    private func rows(_ row: EntityRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(row)
            // SETTINGS-STYLE CARDS, no headings over properties: rows inside
            // a card are divided by a hairline and cards by air, which is
            // the grouping the headings never carried (owner, 2026-09-15).
            LivCard(fill: LivTheme.panel2) {
                dueRow(row, divided: showsStatus(row))
                if showsStatus(row) { statusRow(row) }
            }
            .padding(.top, LivDetail.firstCard)
            // Zero fill pressure: the core fields are always here, even
            // empty ("None"); everything else appears only once it holds a
            // value (design/editor-study.md §8).
            LivCard(fill: LivTheme.panel2) {
                ForEach(Array(InspectorField.core.enumerated()), id: \.element) { i, property in
                    fieldRow(property, row, divided: i < InspectorField.core.count - 1)
                }
            }
            .padding(.top, LivCards.gap)
            let extras = DetailCellGroup.groups(row, skipping: skipSet(row))
            if !extras.isEmpty {
                LivCard(fill: LivTheme.panel2) {
                    ForEach(Array(extras.enumerated()), id: \.element.id) { i, group in
                        cellRow(group, divided: i < extras.count - 1)
                    }
                }
                .padding(.top, LivCards.gap)
            }
            LinksSection(id: id)
            suggestions
            // Facts you cannot change are not rows (owner, 2026-08-06): the
            // birthday is a footnote under the cards.
            if let made = createdLine(row) {
                Text(made)
                    .font(.system(size: LivType.caption))
                    .foregroundStyle(LivTheme.text3)
                    .padding(.top, LivHeader.bottom)
                    .padding(.horizontal, LivHeader.sheetInset)
            }
        }
        .padding(.bottom, scrolls ? LivDetail.sheetBottom : 0)
    }

    /// "Note · edited today 21:04" — the kind, then when it was last
    /// touched, mid-sentence. No clause at all when the box never said.

    // MARK: suggestions — the clerk proposes, the user decides (rev 6)

    /// The clerk's pending proposals for THIS note. Deterministic Rust,
    /// no model, and NOTHING automatic: the sweep only fills a queue;
    /// the sole write path is the Accept button below. A decline is
    /// remembered — the clerk never asks the same thing twice.
    @ViewBuilder private var suggestions: some View {
        let pending = box.proposals(for: id)
        if !pending.isEmpty {
            // The label ON the card, so it takes the card's inset (36).
            LivCard(label: "Suggested", labelStyle: .sheet, fill: LivTheme.panel2) {
                ForEach(Array(pending.enumerated()), id: \.element.id) { i, proposal in
                    suggestionRow(proposal, divided: i < pending.count - 1)
                }
            }
        }
    }

    private func suggestionRow(_ proposal: ProposalRow, divided: Bool) -> some View {
        // One short summary names THIS proposal on both buttons, so two
        // suggestions never read identically to VoiceOver (audit,
        // 2026-08-04).
        let summary = proposal.reason?.isEmpty == false
            ? proposal.reason!
            : (proposal.proposed ?? "")
        // WHAT IT WOULD WRITE, then why: the answer as the title, the
        // reason as the second line.
        return LivCardRow(
            (proposal.proposed ?? "").isEmpty ? summary : (proposal.proposed ?? ""),
            detail: (proposal.proposed ?? "").isEmpty ? nil : proposal.reason,
            divided: divided, rule: LivCards.ruleBare,
            lead: { EmptyView() },
            trailing: {
                // A mis-tap here WRITES cells — so full 44pt targets.
                Button {
                    box.reject(proposal)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: LivType.body, weight: .semibold))
                        .foregroundStyle(LivTheme.text3)
                        .livRowControl(width: LivRow.touch)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss suggestion: \(summary)")
                Button {
                    box.accept(proposal)
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: LivType.body, weight: .semibold))
                        .foregroundStyle(LivTheme.accent)
                        .livRowControl(width: LivRow.touch)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Apply suggestion: \(summary)")
            })
    }

    // MARK: due — a row even when absent

    /// The property that positions the entity; "due" until the row says
    /// otherwise. One name feeds the row, the sheet, and the cell filter.
    private func dueProperty(_ row: EntityRow?) -> String {
        let name = row?.positionedBy ?? "due"
        return name.isEmpty ? "due" : name
    }

    private func dueRow(_ row: EntityRow, divided: Bool) -> some View {
        let label = dueProperty(row).prefix(1).uppercased() + dueProperty(row).dropFirst()
        return Button {
            showDueSheet = true
        } label: {
            DetailCardRow(label, divided: divided) {
                if let due = row.due {
                    // RED WHEN LATE — a TASK overdue and not done — which is
                    // what red means everywhere on the clearer boards. A
                    // past event is not late; it happened (Today's own
                    // ruling, `lateRows`).
                    DetailValue(
                        dueWords(due, end: row.dueEnd, dateOnly: row.dueDateOnly ?? false),
                        late: row.kinds?.contains("task") == true
                            && Civil.day(of: due) < Civil.todayDay()
                            && !livIsDone(row, doneNames))
                } else {
                    DetailValue(nil)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var doneNames: Set<String> {
        Set(options.filter { $0.completes == true }.compactMap(\.name))
    }

    /// The due in the app's words: "Tuesday 11:00", "Today", "18 Sep 09:00",
    /// a span's end after an arrow (its time alone on the same day).
    private func dueWords(_ due: Int64, end: Int64?, dateOnly: Bool) -> String {
        let day = Civil.day(of: due)
        var out = Civil.dayWord(day)
        if !dateOnly, !Civil.timeString(due).isEmpty { out += " " + Civil.timeString(due) }
        if let end, end > 0 {
            let endDay = Civil.day(of: end)
            let tail =
                endDay == day
                ? Civil.timeString(end)
                : Civil.dayWord(endDay) + (dateOnly ? "" : " " + Civil.timeString(end))
            if !tail.isEmpty { out += " → " + tail }
        }
        return out
    }

    // MARK: status

    /// Whether there is a status row at all. A kind with no status
    /// vocabulary and no status set has NOTHING here — no value to read
    /// and nothing to choose — so the row goes rather than explaining
    /// its own emptiness (owner, 2026-08-15: "when user can't interact
    /// with something it shouldn't be there unless it's locally dynamic
    /// or important for clarity"). It used to say "none for this kind",
    /// which is a sentence about the app, not about the note.
    private func showsStatus(_ row: EntityRow) -> Bool {
        !options.isEmpty || !(row.status ?? "").isEmpty
    }

    /// An empty scoped vocabulary (untyped scraps) must never render a
    /// live-looking Menu with zero items — a silent no-op (eval §5.4).
    /// A status already SET is still shown, read-only: it is the user's
    /// own data, and hiding data is worse than showing a chip that does
    /// not open. With a vocabulary, the whole row is the menu (full-width
    /// target, like the due row).
    @ViewBuilder private func statusRow(_ row: EntityRow) -> some View {
        if options.isEmpty {
            // Display-only: nothing to change it to, so no chevron.
            DetailCardRow("Status", divided: false, chevron: false) {
                DetailValue(row.status)
            }
        } else {
            Menu {
                ForEach(options) { option in
                    Button(option.name ?? "") {
                        box.set(id, "status", option.name ?? "")
                    }
                }
            } label: {
                DetailCardRow("Status", divided: false) {
                    DetailValue(row.status)
                }
            }
        }
    }

    // MARK: the general property rows

    /// Properties that must never appear as a row.
    ///
    /// "content" is the NOTE itself — the primary data, edited on the
    /// desk; listing it here treated the document as one of its own
    /// properties (owner, 2026-08-01). "type" and "created" are FACTS,
    /// not fields: nothing in this app can retype an entity or move its
    /// birthday, and the type already shows as a chip at the top
    /// (owner, 2026-08-06).
    private func skipSet(_ row: EntityRow) -> Set<String> {
        Set(
            [
                "name", "status", "content", "type", "created",
                // A file's path and format are FACTS, shown by the file
                // tab's own header. A row you cannot edit is a lie about
                // what this list is for (owner, 2026-08-06).
                "file", "format",
                // Templates left the app (2026-08-15); an older box may
                // still carry the marker cell, and it is not a field.
                "template", dueProperty(row),
                // THE KIND IS NOT A FIELD (owner, 2026-09-16: "remove
                // kind row in properties"). This card has said so since
                // 2026-08-29 — "NO KIND CHIP… you opened this panel from
                // a note; it is a note" — and then drew one anyway,
                // because the word here was `core/`'s "type" and the
                // engine's cell is `kind`. It is also not editable, and
                // a row you cannot edit is a lie about what this list is
                // for (the same 2026-08-06 ruling as `file` above).
                "kind",
                // Links have their own section below, with both
                // directions and a door that makes one. A read-only chip
                // row up here would be the same fact said twice
                // (2026-08-17).
                "related",
            ] + InspectorField.core)
    }

    /// "Created Monday at 21:04" this week, "Created Monday 14 September
    /// at 21:04" before it — or nothing, if the box never said.
    private func createdLine(_ row: EntityRow) -> String? {
        guard let made = row.created, made > 0 else { return nil }
        return "Created " + Civil.dayLong(stamp: made)
    }

    /// The values this entity holds for a property, in wire order.
    private func values(of property: String, in row: EntityRow?) -> [String] {
        (row?.cells ?? [])
            .filter { $0.property == property }
            .compactMap { $0.value }
            .filter { !$0.isEmpty }
    }

    /// A core field's row: tap anywhere on it to open the one editing
    /// sheet. Empty reads "None" — a value, never a prompt to fill it in.
    private func fieldRow(_ property: String, _ row: EntityRow, divided: Bool) -> some View {
        let held = values(of: property, in: row)
        // THE BOX'S WORD, not the token. `property` is what this writes
        // with; what it DRAWS comes off the snapshot, so a renamed field
        // shows its new name and `tags` reads "Subject".
        let field = InspectorField.describe(property, in: box.snap)
        let label = field.shown.prefix(1).uppercased() + field.shown.dropFirst()
        // TWO NAMES AND A COUNT beats three shortened ones.
        let shown = held.isEmpty
            ? nil : held.prefix(2).joined(separator: ", ") + (held.count > 2 ? " +\(held.count - 2)" : "")
        return Button {
            editing = field
        } label: {
            DetailCardRow(label, divided: divided) {
                if property == "people", shown != nil {
                    LivIcon(glyph: .person, color: LivTheme.text2, size: LivDetail.valueGlyph)
                }
                DetailValue(shown)
            }
        }
        .buttonStyle(.plain)
    }

    /// Anything else the entity holds. A reference opens what it names;
    /// every other kind just reads.
    @ViewBuilder private func cellRow(_ group: DetailCellGroup, divided: Bool) -> some View {
        let label = group.shown.prefix(1).uppercased() + group.shown.dropFirst()
        let targets = group.values.filter { $0.refTarget != nil }
        if group.kind == "reference", targets.count == 1, let target = targets[0].refTarget {
            Button {
                desk.open(target)
            } label: {
                DetailCardRow(label, divided: divided) { DetailValue(targets[0].value) }
            }
            .buttonStyle(.plain)
        } else if group.kind == "reference", targets.count > 1 {
            Menu {
                ForEach(Array(targets.enumerated()), id: \.offset) { _, v in
                    Button("Open \(v.value)") { if let t = v.refTarget { desk.open(t) } }
                }
            } label: {
                DetailCardRow(label, divided: divided) {
                    DetailValue(targets.map(\.value).joined(separator: ", "))
                }
            }
        } else {
            DetailCardRow(label, divided: divided, chevron: false) {
                DetailValue(
                    group.values.map { group.kind == "datetime" ? DetailFmt.datetime($0.value) : $0.value }
                        .joined(separator: ", "),
                    lines: 2)
            }
        }
    }

    // The verbs left this panel (owner, 2026-08-02): Move to Trash and
    // the rest act on the DOCUMENT, so they live in the desk's •••
    // menu; this panel only describes. The old Undo went with them — it
    // was the box-level "undo last transaction", which read as a
    // property-undo here and wasn't one.

}

// MARK: - the one editing sheet, driven by the field descriptor

/// Every property is edited the same way: the values in use are listed
/// with the current ones checked, tapping toggles, and an open vocabulary
/// gets a create row LAST (the furniture leads, the door does not — §10).
/// One sheet for area, project, tags and people, because the differences
/// between them live in InspectorField, not here.
struct InspectorValueSheet: View {
    let field: InspectorField
    let id: LivEntityID
    /// The values this entity currently holds for the field.
    let current: [String]
    /// When set, the sheet REPORTS the chosen value instead of writing a
    /// cell — the workspace form builds a lens, it does not edit an
    /// entity. One picker either way: the choices, the create row and
    /// the search all behave identically, which is the whole point of
    /// not writing a second one (standing rule 4).
    var onPick: ((String?) -> Void)? = nil
    /// Opened by a door that says "new…": the caret is already in the
    /// field (owner, 2026-09-22: "you have to manually select the text
    /// box"). Off for the inspector, where picking is the usual act.
    var startTyping = false

    @EnvironmentObject var box: BoxModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var typing: Bool
    @State private var typed = ""
    @State private var known: [String] = []
    /// The value being renamed everywhere, and the name being typed for
    /// it. One value at a time — a rename is one transaction.
    @State private var renaming: String?
    @State private var renameTo = ""
    @State private var renameSaid: String?

    private var trimmed: String { typed.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Everything offered: the closed vocabulary if there is one, else the
    /// values already in use across the box, plus whatever this entity
    /// holds (a value can outlive its neighbours).
    private var all: [String] {
        var out = field.closed ? field.options : known
        for v in current where !out.contains(where: { same($0, v) }) { out.append(v) }
        return out
    }

    private var filtered: [String] {
        trimmed.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }

    private var creatable: Bool {
        !field.closed && !trimmed.isEmpty && !all.contains { same($0, trimmed) }
    }

    private func same(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: .caseInsensitive) == .orderedSame
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // A SHEET TITLE, and sized like one (2026-09-05). It was
            // 16pt bold UPPERCASE with kerning, in the dimmest ink —
            // smaller and quieter than the 22pt rows underneath it, so
            // the header of the screen ranked below its own list.
            // Sentence case for the same reason the section labels
            // dropped theirs on 2026-08-18: uppercase made every
            // heading shout. Full ink plus weight is what outranks the
            // rows now, not size alone.
            // The word, not the token — `.capitalized` on the token is
            // where "Tags" came from, and the box now says "Subject".
            Text(field.shown.capitalized)
                .font(.system(size: LivType.title, weight: .semibold))
                .foregroundStyle(LivTheme.text)
            if !field.closed {
                TextField("Search or create…", text: $typed)
                    .font(.system(size: LivType.title))
                    .foregroundStyle(LivTheme.text)
                    .submitLabel(.done)
                    // Values are verbatim: "errands" must not become
                    // "Errands" on its way into a cell.
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .onSubmit { if creatable { add(trimmed) } }
                    .focused($typing)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: LivTheme.radiusSm).fill(LivTheme.surface))
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered, id: \.self) { value in
                        let on = current.contains { same($0, value) }
                        row(value, checked: on) { on ? remove(value) : add(value) }
                            // RENAME IT EVERYWHERE, not just here. The core
                            // rewrites every carrier in ONE transaction — and
                            // for a select it renames the option, or merges
                            // into an existing one. Only the core can see
                            // every carrier at once, so this cannot be N
                            // writes from the shell.
                            .contextMenu {
                                Button {
                                    renameTo = value
                                    renaming = value
                                } label: {
                                    Label("Rename everywhere…", systemImage: "pencil")
                                }
                            }
                    }
                    if creatable {
                        row("Create \u{201C}\(trimmed)\u{201D}", accent: true) { add(trimmed) }
                    }
                    if all.isEmpty && trimmed.isEmpty {
                        EmptyHint("Type to create")
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LivTheme.canvas)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            // Once per open, never per keystroke.
            guard !field.closed else { return }
            box.distinctValues(property: field.property) { known = $0 }
            // After the sheet's own motion: focus asked for mid-slide is
            // dropped by the system.
            if startTyping {
                DispatchQueue.main.asyncAfter(deadline: .now() + LivMotion.navSeconds) {
                    typing = true
                }
            }
        }
        .alert(
            "Rename everywhere",
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
        ) {
            TextField("New name", text: $renameTo)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") { commitRename() }
        } message: {
            if let renaming {
                let what = field.shown.lowercased()
                Text(verbatim:
                    "Every \(what) reading \u{201C}\(renaming)\u{201D} changes. "
                        + "One step, so one undo.")
            }
        }
        .overlay(alignment: .bottom) {
            if let renameSaid {
                Text(renameSaid)
                    .font(.system(size: LivType.label))
                    .foregroundStyle(LivTheme.text2)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(Capsule().fill(LivTheme.panel2))
                    .padding(.bottom, 18)
            }
        }
    }

    private func commitRename() {
        guard let old = renaming else { return }
        let new = renameTo.trimmingCharacters(in: .whitespacesAndNewlines)
        renaming = nil
        guard !new.isEmpty, new != old else { return }
        box.renameValue(property: field.property, from: old, to: new) { n in
            guard let n else {
                renameSaid = "Could not rename that."
                return
            }
            renameSaid = n == 1 ? "Renamed on 1 thing." : "Renamed on \(n) things."
            box.distinctValues(property: field.property) { known = $0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { renameSaid = nil }
        }
    }

    // MARK: writes — the box is the only truth; the sheet re-reads nothing

    private func add(_ value: String) {
        if let onPick {
            onPick(value)
            dismiss()
            return
        }
        // THE VALUE NEEDS TO EXIST FIRST. `set` refuses a name with no
        // entity behind it — that refusal is the core's, and it is right:
        // these values are things, not strings. So mint it, then write
        // it, and let the write wait for the mint.
        //
        // A mint that fails hands back `.absent`; writing the name anyway
        // would just be a second refusal, and the first one has already
        // told the user.
        if field.mintsValues, !field.propertyId.isAbsent,
            !field.options.contains(where: { same($0, value) })
        {
            box.addOption(field.propertyId, value) { [self] made in
                guard made != .absent else { return }
                write(value)
            }
            typed = ""
            if !field.multi { dismiss() }
            return
        }
        write(value)
        typed = ""
    }

    /// The write itself, once the vocabulary is known to hold the value.
    private func write(_ value: String) {
        if field.multi {
            box.addCell(id, field.property, value)
        } else {
            box.set(id, field.property, value)
            dismiss()  // one value means the question is answered
        }
    }

    private func remove(_ value: String) {
        if let onPick {
            onPick(nil)
            dismiss()
            return
        }
        if field.multi {
            box.removeCell(id, field.property, value)
        } else {
            box.unset(id, field.property)
        }
    }

    private func row(
        _ label: String, checked: Bool = false, accent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if accent {
                    Image(systemName: "plus")
                        .font(.system(size: LivType.body, weight: .semibold))
                        .foregroundStyle(LivTheme.accent)
                        .frame(width: 16)
                } else if field.property == "area" {
                    // AN AREA'S OWN MARK (2026-09-06, direction A): the
                    // column the coloured dot vacated on 2026-08-29 holds
                    // the area's drawing instead — a signal with something
                    // to decode, in ink. Sorting becomes six drawings you
                    // recognise, not six words.
                    LivIcon(glyph: .area, color: LivTheme.text2, size: 19)
                        .frame(width: 16)
                } else {
                    // NO DOT. `Hue.dot` hashed the property's NAME to one
                    // of five colours — its own comment said it "means
                    // nothing beyond 'these two say the same thing'". A
                    // reader takes a coloured dot for a signal, so five
                    // hues down a settings list read as a code with
                    // nothing to decode. The column stays, so the labels
                    // still line up (2026-08-29).
                    Color.clear.frame(width: 16, height: 7)
                }
                Text(label)
                    .font(.system(size: LivType.title))
                    .foregroundStyle(accent ? LivTheme.accent : LivTheme.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: LivType.body, weight: .semibold))
                        .foregroundStyle(LivTheme.accent)
                }
            }
            .frame(height: LivRow.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
        }
    }
}

// MARK: - shared row pieces

/// ONE ROW OF A PROPERTIES CARD, Settings-style (the clearer board): the
/// property's name on the left in full ink, then its value in text2 and a
/// chevron. 52 tall; the hairline runs from 16 in the card to its edge,
/// under every row but the last.
///
/// Its own recipe, not `LivCardRow`, for one reason: the LABEL is what
/// must never truncate. Names are short words and values can be long, so
/// a long project turns into "Long proj…", never "Pr…".
struct DetailCardRow<Value: View>: View {
    let label: String
    var divided = true
    var chevron = true
    @ViewBuilder var value: Value

    init(
        _ label: String, divided: Bool = true, chevron: Bool = true,
        @ViewBuilder value: () -> Value
    ) {
        self.label = label
        self.divided = divided
        self.chevron = chevron
        self.value = value()
    }

    var body: some View {
        HStack(spacing: LivCards.markGap) {
            Text(label)
                .font(.system(size: LivType.body))
                .foregroundStyle(LivTheme.text)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: LivCards.trailingGap)
            HStack(spacing: LivDetail.valueGap) { value }
            if chevron { LivChevron() }
        }
        .padding(.horizontal, LivCards.padX)
        .padding(.vertical, LivCards.padY)
        .frame(minHeight: LivCards.row)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if divided { LivCardRule(inset: LivCards.ruleBare) }
        }
    }
}

/// A property's value: text2, or "None" in text3 when there is nothing;
/// red when it is a late date.
struct DetailValue: View {
    let text: String?
    var late = false
    var lines = 1

    init(_ text: String?, late: Bool = false, lines: Int = 1) {
        self.text = text
        self.late = late
        self.lines = lines
    }

    var body: some View {
        let empty = (text ?? "").isEmpty
        Text(empty ? "None" : text ?? "")
            .font(.system(size: LivType.body))
            .foregroundStyle(empty ? LivTheme.text3 : late ? LivTheme.red : LivTheme.text2)
            .lineLimit(lines)
            .multilineTextAlignment(.trailing)
            .truncationMode(.tail)
    }
}

// MARK: - the due sheet

/// Two groups, because there are two things to set: a DAY and a TIME.
///
/// Today, Tomorrow and "Choose a date" all answer the same question, so
/// all three look and behave the same — a row you tap. They used to wear
/// three different faces, which implied a grouping that did not exist
/// (owner, 2026-08-06). "Choose a date" opens a month calendar under it
/// rather than a small popup, so it is a real button like its two
/// neighbours.
///
/// The time is its own group and is always set. There is no "no time"
/// state and no 09:00 fallback hidden in the reminder code: a due you
/// set without thinking about the clock takes the time it is now
/// (owner, 2026-08-06). Changes save the moment you make them — no Set
/// button to forget. Clear removes the due entirely.
/// Internal: the Tasks row's "Pick" swipe verb opens this same sheet.
struct DetailDueSheet: View {
    @ObservedObject var model: BoxModel
    let id: LivEntityID
    let property: String

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var time: Date
    /// The month calendar under "Choose a date" is showing.
    @State private var calendarShown = false
    /// WHICH MONTH THE GRID IS LOOKING AT — deliberately not derived
    /// from `date`, so paging to March to check something does not move
    /// the due to March. Seeded from the due in `init`.
    @State private var shownMonth: Int64
    /// How long this thing lasts, kept across every edit.
    @State private var spanMinutes: Int
    /// Whether this thing carries a clock time. An all-day event is a
    /// real kind of thing — a holiday is not due at 09:00 — so opening
    /// this sheet and changing only the DAY must not quietly give it a
    /// time (review, 2026-08-06). Touching the clock sets this.
    @State private var timed: Bool

    init(model: BoxModel, id: LivEntityID, property: String) {
        self.model = model
        self.id = id
        self.property = property
        // Start where the value already is. A due with no clock time
        // seeds the time control with NOW, so the control never opens on
        // a number nobody chose.
        let row = model.entity(id)
        let now = Date()
        // How long the thing lasts, in minutes, so a day or time change
        // MOVES it instead of truncating it. write() used to hardcode no
        // end, so touching the time wheel on a 09:00–11:00 meeting
        // deleted the 11:00 (review, 2026-08-06).
        _spanMinutes = State(initialValue: Self.spanLength(row))
        if let due = row?.due {
            let day = Civil.day(of: due)
            let hm = due % 10_000
            _date = State(initialValue: Civil.date(day: day, hhmm: 1200) ?? now)
            _shownMonth = State(initialValue: CalGrid.firstOfMonth(day))
            // The stored flag is the authority on whether this carries a
            // clock time. Also testing `hm != 0` re-read a real midnight
            // as "no time" and then quietly replaced it (review).
            let has = (row?.dueDateOnly ?? false) == false
            _timed = State(
                initialValue: LivDue.carriesTime(
                    dateOnly: !has, isEvent: (row?.kinds ?? []).contains("event")))
            _time = State(
                initialValue: has
                    ? (Civil.date(day: day, hhmm: hm) ?? now)
                    : LivDue.defaultTime(on: day))
        } else {
            let today = Civil.todayDay()
            _date = State(initialValue: now)
            _shownMonth = State(initialValue: CalGrid.firstOfMonth(today))
            _timed = State(initialValue: true)
            _time = State(initialValue: LivDue.defaultTime(on: today))
        }
    }

    /// Minutes between a due's start and its end. The arithmetic lives
    /// in CalClock, where the calendar's self-check covers it.
    private static func spanLength(_ row: EntityRow?) -> Int {
        guard let start = row?.due else { return 0 }
        return CalClock.span(start: start, end: row?.dueEnd)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // The SHEET face, but no card under it: these rows sit
                // flush, so the label takes back the step a card would add
                // and lines up with them.
                SectionLabel("Date", style: .sheet)
                    .padding(.horizontal, LivRow.cardInset - LivHeader.sheetInset)
                // Neither shortcut closes the sheet: setting a day and
                // THEN a time is the common pair, and being thrown out
                // after the day meant reopening to finish (owner,
                // 2026-08-11). They must also MOVE `date`, because
                // every later write reads it — leaving it behind made
                // the next time-change silently rewrite the day back to
                // whatever the sheet opened on. The dismissal was hiding
                // that; removing one without the other would have
                // shipped the bug.
                choice("Today", value: Civil.dayLabel(Civil.todayDay())) {
                    pick(day: Civil.todayDay())
                }
                choice(
                    "Tomorrow",
                    value: Civil.dayLabel(Civil.addDays(Civil.todayDay(), 1)),
                    divided: true
                ) {
                    pick(day: Civil.addDays(Civil.todayDay(), 1))
                }
                choice(
                    "Choose a date", value: DetailFmt.dayLabel(date),
                    chevron: calendarShown ? "chevron.up" : "chevron.down",
                    divided: true
                ) {
                    withAnimation(LivMotion.nav) { calendarShown.toggle() }
                }
                if calendarShown { monthPicker }
                SectionLabel("Time", style: .sheet)
                    .padding(.horizontal, LivRow.cardInset - LivHeader.sheetInset)
                timeRow
                // ALWAYS rendered, disabled when there is nothing to
                // clear. It used to appear only once a due existed —
                // which meant it materialised directly under the time
                // control the instant you set a date, exactly where a
                // finger was already travelling, and it unsets the whole
                // value with no confirmation and no undo. The layout is
                // fixed from the moment the sheet opens now, so nothing
                // arrives under your thumb (owner, 2026-08-11:
                // "setting time after date sometimes erases everything").
                clearRow.padding(.top, 12)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(LivTheme.surface)
        .tint(LivTheme.accent)
    }

    /// One row of the Date group. All three wear this face: the word on
    /// the left is the tap target, the value on the right is what you
    /// would get.
    private func choice(
        _ label: String, value: String, chevron: String? = nil,
        divided: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: LivType.strong))
                    .foregroundStyle(LivTheme.text)
                Spacer(minLength: 8)
                Text(value)
                    .font(.system(size: LivType.strong).monospacedDigit())
                    .foregroundStyle(LivTheme.text3)
                if let chevron {
                    Image(systemName: chevron)
                        .font(.system(size: LivType.label, weight: .semibold))
                        .foregroundStyle(LivTheme.text3)
                }
            }
            .frame(minHeight: LivRow.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            if divided { LivCardRule(inset: 0) }
        }
    }

    /// THE APP'S OWN MONTH, not the system's.
    ///
    /// This was `DatePicker(.graphical)` until 2026-09-07. It took the
    /// app's accent from the subtree's `.tint`, so it was never wearing
    /// the system's blue — but it painted its own selected-day fill and
    /// its own red "today", against an app whose month grid says
    /// selection with `LivDayMark`'s disc and marks today inside it.
    /// Two month grids with two grammars, invisible only because they
    /// never appeared on the same screen (standing rule 4).
    ///
    /// The grid it draws now is the calendar's, moved to `Month.swift`
    /// in the same change so both screens can reach it. It is given no
    /// counts — a due picker has no items to be busy with — and no
    /// `onHold`: holding a day in the calendar creates an all-day event,
    /// and there is nothing here to create.
    ///
    /// `shownMonth` is its own state and NOT derived from `date`,
    /// because paging to look at March must not move the due to March.
    private var monthPicker: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(LivMotion.nav) {
                        shownMonth = CalGrid.addMonths(shownMonth, -1)
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: LivType.label, weight: .semibold))
                        .foregroundStyle(LivTheme.text2)
                        .frame(width: LivRow.touch, height: LivRow.touch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Previous month")
                Text(CalGrid.title(shownMonth))
                    .font(.system(size: LivType.label, weight: .medium))
                    .foregroundStyle(LivTheme.text)
                    .frame(maxWidth: .infinity)
                Button {
                    withAnimation(LivMotion.nav) {
                        shownMonth = CalGrid.addMonths(shownMonth, 1)
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: LivType.label, weight: .semibold))
                        .foregroundStyle(LivTheme.text2)
                        .frame(width: LivRow.touch, height: LivRow.touch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next month")
            }
            MonthWeekdayRow()
            MonthGridView(
                month: calMonth(
                    shownMonth, today: Civil.todayDay(), counts: [:]),
                selected: Civil.day(of: date),
                onSelect: { pick(day: $0) }
            )
            .equatable()
        }
        .padding(.vertical, 4)
    }

    /// THE CLOCK — the system's own time picker, any minute.
    ///
    /// It was a pair of ±15-minute steppers, so that the quarter-hour law
    /// the CALENDAR applies to a dragged block (`CalClock.snap`, "11:47 is
    /// never what anyone meant") lived in the control rather than in a
    /// validator. The owner's word, 2026-09-14: "it doesn't let you set
    /// arbitrary time with the normal picker and forces you to use the
    /// clumsy arrows (remove those)."
    ///
    /// The two surfaces do NOT now disagree about what a time is: dragging
    /// a block across a grid is an imprecise gesture and still snaps;
    /// naming a time outright is exact and is taken as given. The law is
    /// about the gesture, not about the value.
    ///
    /// Standing rule 5 (a user never types a query language) is untouched
    /// — the wheel is a picker, and no time string is ever parsed.
    private var timeRow: some View {
        HStack(spacing: 8) {
            Text("At")
                .font(.system(size: LivType.strong))
                .foregroundStyle(LivTheme.text)
            Spacer(minLength: 12)
            DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .accessibilityLabel("Due time")
                // The wheel reports every intermediate value while it
                // spins, so this writes more than once per change. Each
                // is one `set`, and `Box.swift` coalesces the refreshes
                // (standing rule 8).
                .onChange(of: time) { _, _ in retime() }
        }
        .frame(minHeight: LivRow.height)
    }

    /// The clock moved. Keep it on the sheet's own day — the DAY is the
    /// other control's job, and a time control that silently changed the
    /// date was the "setting time after date erases everything"
    /// complaint.
    private func retime() {
        let day = Civil.day(of: date)
        if let stamped = Civil.date(day: day, hhmm: Civil.hhmm(of: time)), stamped != time {
            time = stamped
            // Re-entering through onChange; that pass does the write.
            return
        }
        // Setting a clock time is how an all-day thing gets one.
        timed = true
        commit()
    }

    private var clearRow: some View {
        let has = model.entity(id)?.due != nil
        return Button {
            model.unset(id, property)
            dismiss()
        } label: {
            HStack {
                Text("Clear")
                    .font(.system(size: LivType.strong))
                    .foregroundStyle(has ? LivTheme.red : LivTheme.text2)
                Spacer()
            }
            .frame(minHeight: LivRow.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!has)
    }

    /// The one write. dateOnly rides !hasTime, so the row and the
    /// calendar know whether "when" includes a clock.
    private func commit() {
        write(day: Civil.day(of: date))
    }

    /// A shortcut day: move the sheet's own `date` to it, then write.
    /// Every other write reads `date`, so a day set without moving it is
    /// a day the next edit throws away.
    private func pick(day: Int64) {
        if let moved = Civil.date(day: day, hhmm: 1200) { date = moved }
        write(day: day)
    }

    /// Always a day AND a clock time. The "no time" state is gone: a due
    /// with no time had to invent one somewhere, and it invented 09:00
    /// inside the reminder code where nobody could see it.
    ///
    /// A thing that lasts an hour still lasts an hour afterwards. The end
    /// moves with the start rather than being dropped.
    private func write(day: Int64) {
        let hhmm = timed ? Civil.hhmm(of: time) : 0
        let start = Civil.stamp(day: day, hhmm: hhmm)
        model.setSpan(
            id, property, start: start,
            end: timed ? CalClock.end(start: start, length: spanMinutes) : 0,
            dateOnly: !timed)
    }
}

// MARK: - grouping + formatting helpers (file-private, Detail-prefixed)

/// One value of a grouped property row; references carry their target so
/// a chip tap can open it as a Desk tab.
private struct DetailCellValue {
    let value: String
    let refTarget: LivEntityID?
}

/// One row per property, values in cell order — a multi-valued property
/// stays one line, never N look-alike rows.
private struct DetailCellGroup: Identifiable {
    let id: Int
    /// The token, for the skip list and for writes.
    let property: String
    /// What the row draws.
    let shown: String
    let kind: String
    let values: [DetailCellValue]

    /// **SKIPPED BY TOKEN, DRAWN BY WORD.** It skipped by the shown name
    /// and the two were the same string, so nobody noticed — until they
    /// were not:
    ///
    ///   - the list carries "type", which is `core/`'s word. The engine's
    ///     cell is `kind`, so it never matched and the card drew a
    ///     read-only chip saying "Note" on a note (owner, 2026-09-16:
    ///     "remove kind row in properties");
    ///   - and `tags` reads "Subject" as of the same day, so the four
    ///     core fields in the skip list would have stopped hiding it and
    ///     the card would have drawn that field twice.
    static func groups(_ row: EntityRow, skipping skip: Set<String>) -> [DetailCellGroup] {
        var order: [String] = []
        var kinds: [String: String] = [:]
        var shown: [String: String] = [:]
        var values: [String: [DetailCellValue]] = [:]
        for cell in row.cells ?? [] {
            let token = cell.word ?? cell.property ?? ""
            guard !token.isEmpty, !skip.contains(token) else { continue }
            if values[token] == nil {
                order.append(token)
                kinds[token] = cell.kind ?? ""
                shown[token] = cell.property ?? token
            }
            values[token, default: []].append(
                DetailCellValue(value: cell.value ?? "", refTarget: cell.refTarget))
        }
        return order.enumerated().map { i, property in
            DetailCellGroup(
                id: i, property: property, shown: shown[property] ?? property,
                kind: kinds[property] ?? "", values: values[property] ?? [])
        }
    }
}

private enum DetailFmt {
    private static let gregorian = Calendar(identifier: .gregorian)

    /// The wire's datetime display ("YYYY-MM-DD[ HH:MM][ -> …]") redrawn
    /// in the row's day words — "Tuesday 14:00", "18 Sep" — the same
    /// voice as the Due row above it; spans joined with an arrow.
    static func datetime(_ raw: String) -> String {
        raw.components(separatedBy: " -> ").map(side).joined(separator: " → ")
    }

    private static func side(_ text: String) -> String {
        let parts = text.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ")
        guard let first = parts.first,
            let day = Int64(first.replacingOccurrences(of: "-", with: "")),
            first.count == 10
        else { return text }
        var out = Civil.dayWord(day)
        if parts.count > 1 { out += " " + parts[1] }
        return out
    }

    /// The day a picker is sitting on, in the app's own day voice.
    static func dayLabel(_ date: Date) -> String {
        Civil.dayLabel(Civil.day(of: date))
    }

}
