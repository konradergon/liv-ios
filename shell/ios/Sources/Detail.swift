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
    let property: String
    /// The core's value kind: "select", "reference", "datetime", "text"…
    let kind: String
    /// Several values at once (membership, addCell) versus one (set).
    let multi: Bool
    /// The vocabulary a select already holds. NOT a closed one any more
    /// — see `closed`.
    let options: [String]
    /// The property's own id, so a new option can be minted against it.
    let propertyId: UInt64

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
    static func describe(_ property: String, in snap: Snapshot?) -> InspectorField {
        let row = (snap?.properties ?? []).first {
            ($0.name ?? "").compare(property, options: .caseInsensitive) == .orderedSame
        }
        let options = (row?.options ?? [])
            .filter { $0.hidden != true }
            .compactMap { $0.name }
            .filter { !$0.isEmpty }
        return InspectorField(
            property: property,
            kind: row?.kind ?? "text",
            multi: isMulti(property),
            options: options,
            propertyId: row?.id ?? 0)
    }
}

// MARK: - the inspector (full-body; no title, no nav chrome)

struct EntityInspector: View {
    let id: UInt64
    /// The panel scrolls; embedded as a record's body (Record.swift) it
    /// must NOT — a scroll view inside a scroll view eats the gesture.
    var scrolls: Bool = true

    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel

    @State private var options: [StatusOption] = []
    @State private var showDueSheet = false
    /// The name being typed. Seeded from the name CELL, never from
    /// `row.title` — the wire title is derived, and putting it in the
    /// field would make merely opening the card able to write it.
    @State private var draftName = ""
    @State private var nameSeeded = false
    @FocusState private var nameFocused: Bool
    /// The field whose sheet is open. One sheet serves every property.
    @State private var editing: InspectorField?

    init(id: UInt64, scrolls: Bool = true) {
        self.id = id
        self.scrolls = scrolls
    }

    var body: some View {
        Group {
            if let row = box.entity(id) {
                list(row)
            } else {
                EmptyHint("This was deleted.")
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
            box.statusOptions(kind: box.entity(id)?.kinds?.first ?? "") {
                options = $0
            }
        }
        .onChange(of: LivName.stored(box.entity(id))) { old, fresh in
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

    private func commitName() {
        switch LivName.commit(typed: draftName, row: box.entity(id)) {
        case .write(let typed): box.set(id, "name", typed)
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

    private func rows(_ row: EntityRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
                // The top line names the ITEM, with its type as a chip
                // beside it. It used to be the chip alone, which meant a
                // panel swiped over a note announced "note" and never
                // said WHICH note; and the same type then appeared again
                // as a row further down (owner, 2026-08-06).
                //
                // Suppressed when embedded in a record, whose own name
                // field is directly above this — one card never shows
                // two name fields.
                //
                // IT IS A FIELD NOW, not a label (owner, todo.org: *"the
                // note property interface seems different from say task
                // properties; you can't rename it in properties"*). A
                // record card got an editable name and a note did not,
                // so the same card said two different things about what
                // a name is, and a note's could only be changed from the
                // desk's own title.
                //
                // "name" stays in `skipSet`: this line IS the name row,
                // and a second one further down would be the two-fields
                // problem again. The seed/commit rules are
                // `LivName`'s (Kit.swift) — the same ones the desk title
                // and the record card use.
                if scrolls {
                    TextField(livRowTitle(row), text: $draftName, axis: .vertical)
                        .font(.system(size: LivType.display, weight: .semibold))
                        .foregroundStyle(LivTheme.text)
                        .lineLimit(1...3)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit(commitName)
                        .onChange(of: nameFocused) { _, now in
                            if !now { commitName() }
                        }
                        .accessibilityLabel("Name")
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                }
                // NO KIND CHIP. It sat directly under the title as a
                // pill of 11pt lowercase with a dot in it — "• note" —
                // which is micro-text (owner, 2026-08-18: "eliminate
                // unnecessary small text and labels") saying what the
                // surface around it already says. You opened this panel
                // from a note; it is a note.
                //
                // The kind is not lost: it is the card's own label in the
                // switcher, the colour of a calendar block, and the hue
                // of a chip that links to another entity — every place
                // where two kinds sit side by side and the difference is
                // worth a word (2026-08-29).
                SectionLabel("Schedule")
                dueRow(row)
                if showsStatus(row) {
                    DetailHairline()
                    statusRow(row)
                }
                SectionLabel("Filing")
                // Zero fill pressure: the core fields are always here, even
                // empty; everything else appears only once it holds a value
                // (design/editor-study.md §8). Two filled fields is a
                // finished object — the rows must never nag.
                ForEach(
                    Array(InspectorField.core.enumerated()), id: \.element
                ) { i, property in
                    if i > 0 { DetailHairline() }
                    fieldRow(property, row)
                }
                let extras = DetailCellGroup.groups(row, skipping: skipSet(row))
                if !extras.isEmpty {
                    SectionLabel("Other")
                    ForEach(Array(extras.enumerated()), id: \.element.id) { i, group in
                        if i > 0 { DetailHairline() }
                        cellRow(group)
                    }
                }
            LinksSection(id: id)
            suggestions
            // Facts you cannot change are not rows. A row that looks like
            // every other row and does nothing when tapped is a lie about
            // what this list is for (owner, 2026-08-06).
            if let made = createdLine(row) {
                Text(made)
                    .font(.system(size: LivType.body).monospacedDigit())
                    .foregroundStyle(LivTheme.text3)
                    .padding(.top, 22)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, scrolls ? 14 : 0)
        .padding(.bottom, scrolls ? 24 : 0)
    }

    // MARK: suggestions — the clerk proposes, the user decides (rev 6)

    /// The clerk's pending proposals for THIS note. Deterministic Rust,
    /// no model, and NOTHING automatic: the sweep only fills a queue;
    /// the sole write path is the Accept button below. A decline is
    /// remembered — the clerk never asks the same thing twice.
    @ViewBuilder private var suggestions: some View {
        let pending = box.proposals(for: id)
        if !pending.isEmpty {
            SectionLabel("Suggested")
            ForEach(Array(pending.enumerated()), id: \.element.id) { i, proposal in
                if i > 0 { DetailHairline() }
                suggestionRow(proposal)
            }
        }
    }

    private func suggestionRow(_ proposal: ProposalRow) -> some View {
        // One short summary names THIS proposal on both buttons, so two
        // suggestions never read identically to VoiceOver (audit,
        // 2026-08-04).
        let summary = proposal.reason?.isEmpty == false
            ? proposal.reason!
            : (proposal.commands ?? []).prefix(3)
                .compactMap { c in
                    [c.property, c.value].compactMap { $0 }.filter { !$0.isEmpty }
                        .joined(separator: " ")
                }
                .joined(separator: ", ")
        return HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                // The diff: what would change, stated as chips.
                HStack(spacing: 5) {
                    ForEach(
                        Array((proposal.commands ?? []).prefix(3).enumerated()),
                        id: \.offset
                    ) { _, command in
                        commandChip(command)
                    }
                }
                if let reason = proposal.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.system(size: LivType.body))
                        .foregroundStyle(LivTheme.text3)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            // A mis-tap here WRITES cells — so full 44pt targets, the
            // platform's minimum and the app's own top-key size
            // (`livTopKeyShape`). Audit, 2026-08-04.
            Button {
                box.reject(proposal)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: LivType.body, weight: .semibold))
                    .foregroundStyle(LivTheme.text3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss suggestion: \(summary)")
            Button {
                box.accept(proposal)
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: LivType.body, weight: .semibold))
                    .foregroundStyle(LivTheme.accent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Apply suggestion: \(summary)")
        }
        .frame(minHeight: LivRow.tall)
    }

    @ViewBuilder private func commandChip(_ command: ProposalCommandRow) -> some View {
        let sign = (command.kind == "remove" || command.kind == "trash") ? "−" : "+"
        let label = [command.property, command.value]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        if !label.isEmpty {
            ValueChip("\(sign) \(label)")
        } else if let kind = command.kind, !kind.isEmpty {
            // A merge proposal's Trash/Redirect legs carry no property or
            // value — the verb itself is the diff (audit, 2026-08-04).
            ValueChip("\(sign) \(kind)")
        }
    }

    // MARK: due — a row even when absent

    /// The property that positions the entity; "due" until the row says
    /// otherwise. One name feeds the row, the sheet, and the cell filter.
    private func dueProperty(_ row: EntityRow?) -> String {
        let name = row?.positionedBy ?? "due"
        return name.isEmpty ? "due" : name
    }

    private func dueRow(_ row: EntityRow) -> some View {
        Button {
            showDueSheet = true
        } label: {
            HStack {
                DetailRowLabel(dueProperty(row))
                Spacer(minLength: 12)
                if let due = row.due {
                    Text(DetailFmt.due(due, end: row.dueEnd, dateOnly: row.dueDateOnly ?? false))
                        .font(.system(size: LivType.strong).monospacedDigit())
                        .foregroundStyle(LivTheme.text)
                } else {
                    DetailEmptyValue()
                }
            }
            .frame(minHeight: LivRow.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        Group {
            if options.isEmpty {
                HStack {
                    DetailRowLabel("status")
                    Spacer(minLength: 12)
                    // PLAIN TEXT. This row's own comment has said
                    // "display-only; nothing to change it to" since it
                    // was written, and it drew the value in the capsule
                    // this app uses for values you CAN act on — a
                    // control's clothes on a fact. Every other read-only
                    // value in this panel is text.
                    Text(row.status ?? "")
                        // The value column's own size, like every other
                        // read-only value on this card (2026-09-05).
                        .font(.system(size: LivType.strong))
                        .foregroundStyle(LivTheme.text2)
                }
                .frame(minHeight: LivRow.height)
            } else {
                Menu {
                    ForEach(options) { option in
                        Button(option.name ?? "") {
                            box.set(id, "status", option.name ?? "")
                        }
                    }
                } label: {
                    HStack {
                        DetailRowLabel("status")
                        Spacer(minLength: 12)
                        if let status = row.status, !status.isEmpty {
                            ValueChip(status, big: true)
                        } else {
                            DetailEmptyValue()
                        }
                    }
                    .frame(minHeight: LivRow.height)
                    .contentShape(Rectangle())
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
                // Links have their own section below, with both
                // directions and a door that makes one. A read-only chip
                // row up here would be the same fact said twice
                // (2026-08-17).
                "related",
            ] + InspectorField.core)
    }

    /// "Created Tue 4 Aug 18:52", or nothing if the box never said.
    private func createdLine(_ row: EntityRow) -> String? {
        let raw = (row.cells ?? [])
            .first { $0.property == "created" }?.value ?? ""
        guard !raw.isEmpty else { return nil }
        return "Created " + DetailFmt.datetime(raw)
    }

    /// The values this entity holds for a property, in wire order.
    private func values(of property: String, in row: EntityRow?) -> [String] {
        (row?.cells ?? [])
            .filter { $0.property == property }
            .compactMap { $0.value }
            .filter { !$0.isEmpty }
    }

    /// A core field's row: tap anywhere on it to open the one editing
    /// sheet. Empty reads as "—", never as a prompt to fill it in.
    private func fieldRow(_ property: String, _ row: EntityRow) -> some View {
        let held = values(of: property, in: row)
        return Button {
            editing = InspectorField.describe(property, in: box.snap)
        } label: {
            HStack {
                DetailRowLabel(property)
                Spacer(minLength: 12)
                if held.isEmpty {
                    DetailEmptyValue()
                } else {
                    // TWO, NOT THREE. The values are the column's own
                    // size now, and three 20pt capsules after a 20pt
                    // label do not fit the ~299pt left on the row — the
                    // label carries `layoutPriority(1)`, so the CHIPS
                    // are what gets squeezed, and a squeezed chip
                    // truncates a project's name to nothing (each is
                    // `lineLimit(1)`). Two whole names and a count beats
                    // three shortened ones.
                    HStack(spacing: 5) {
                        ForEach(held.prefix(2), id: \.self) { ValueChip($0, big: true) }
                        if held.count > 2 {
                            Text("+\(held.count - 2)")
                                .font(.system(size: LivType.body).monospacedDigit())
                                .foregroundStyle(LivTheme.text3)
                        }
                    }
                }
            }
            .frame(minHeight: LivRow.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func cellRow(_ group: DetailCellGroup) -> some View {
        HStack(alignment: .center) {
            DetailRowLabel(group.property)
            Spacer(minLength: 12)
            HStack(spacing: 5) {
                ForEach(Array(group.values.enumerated()), id: \.offset) { _, value in
                    cellValue(value, kind: group.kind)
                }
            }
            .lineLimit(2)
        }
        .frame(minHeight: LivRow.height)
    }

    /// A reference chip navigates — open the target as a Desk tab, the
    /// Ref-span gesture grammar. Everything else just displays.
    @ViewBuilder private func cellValue(_ v: DetailCellValue, kind: String) -> some View {
        switch kind {
        case "reference":
            // A reference IS another thing in the box, so its dot is that
            // thing's kind color — a linked task reads purple here and
            // purple in every list.
            if let target = v.refTarget {
                Button {
                    desk.open(target)
                } label: {
                    ValueChip(v.value)
                }
                .buttonStyle(.plain)
            } else {
                ValueChip(v.value)
            }
        case "select":
            ValueChip(v.value)
        case "datetime":
            Text(DetailFmt.datetime(v.value))
                .font(.system(size: LivType.strong).monospacedDigit())
                .foregroundStyle(LivTheme.text)
        default:
            Text(v.value)
                .font(.system(size: LivType.strong))
                .foregroundStyle(LivTheme.text)
                .multilineTextAlignment(.trailing)
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
    let id: UInt64
    /// The values this entity currently holds for the field.
    let current: [String]
    /// When set, the sheet REPORTS the chosen value instead of writing a
    /// cell — the workspace form builds a lens, it does not edit an
    /// entity. One picker either way: the choices, the create row and
    /// the search all behave identically, which is the whole point of
    /// not writing a second one (standing rule 4).
    var onPick: ((String?) -> Void)? = nil

    @EnvironmentObject var box: BoxModel
    @Environment(\.dismiss) private var dismiss
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
            Text(field.property.capitalized)
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
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: LivTheme.radiusSm).fill(LivTheme.panel))
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
                        EmptyHint("Type to create one.")
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
                let what = field.property.lowercased()
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
        // A SELECT NEEDS THE OPTION TO EXIST FIRST. `set` refuses a value
        // with no matching option — that refusal is the core's, and it is
        // right: a select's values are entities, not strings. So mint it,
        // then write it, and let the write wait for the mint.
        if field.kind == "select", field.propertyId != 0,
            !field.options.contains(where: { same($0, value) })
        {
            box.addOption(field.propertyId, value) { [self] _ in write(value) }
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
                    LivIcon(glyph: LivArea.glyph(named: label), color: LivTheme.text2, size: 19)
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

/// THE EMPTY VALUE — the em-dash a field shows when it holds nothing.
///
/// One view, because it was three copies (due, status, and every core
/// filing field), each spelling out the same dash, the same size and the
/// same ink. It is the TARGET the filled values were brought up to meet
/// on 2026-09-05, not a thing to shrink: an empty field read 20pt while
/// a filled one read 14, so the card said least about the fields that
/// held most.
private struct DetailEmptyValue: View {
    var body: some View {
        Text("—")
            .font(.system(size: LivType.strong))
            .foregroundStyle(LivTheme.muted)
    }
}

private struct DetailRowLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    /// NO DOT, AND NO GLYPH (owner, 2026-08-29: "the dots are a bit
    /// ugly, as well as colors in general").
    ///
    /// This reverses 2026-08-12, and the earlier decision is worth
    /// keeping visible because it was not arbitrary. Icons were tried
    /// that day and rejected the same day — a clock for "due" and a tag
    /// for "tags" are pictures of the word beside them — and a
    /// hand-picked colour per family went in instead, on the owner's
    /// "icons for properties are confusing, but color indication of some
    /// sort is ok".
    ///
    /// What changed is the company they kept. Six fully-saturated system
    /// hues at 8pt were the loudest thing on a screen that is otherwise
    /// greys, and they sat beside a hash-coloured dot that meant nothing
    /// at all, so the whole device read as decoration. The family a field
    /// belongs to is already said by the section it sits under —
    /// Schedule, Filing, Links — which is a word rather than a code.
    ///
    /// Kind chips elsewhere (a note, a task, an event) keep their colour:
    /// there it says what a THING is, and two kinds do sit side by side.
    /// NO GLYPH ON A VALUE ROW.
    ///
    /// One was added on 2026-08-29, following the desktop's
    /// `PropertyIcon`, and taken off the same day. Anytype for iOS —
    /// which does the same job on the same screen size — draws its
    /// property rows as label and value with nothing between, and shows
    /// a glyph only in the SCHEMA view, where you are picking among
    /// properties rather than reading one object's values. Its rows read
    /// cleaner, and the reason generalises: an icon beside "due" is a
    /// picture of the word next to it (the 2026-08-12 finding), whereas
    /// an icon beside a property in a list of forty is how you find the
    /// one you want.
    ///
    /// The glyphs moved to `Settings → Fields`, which is this app's
    /// schema view.
    var body: some View {
        HStack(spacing: 10) {
            Text(text)
                // 15pt + 46pt rows: the library panel's density (rev 6 —
                // "make the grouping UI akin to how the left panel looks").
                .font(.system(size: LivType.strong))
                .foregroundStyle(LivTheme.text3)
                .lineLimit(1)
        }
        .layoutPriority(1)
    }
}

private struct DetailHairline: View {
    var body: some View {
        Rectangle().fill(LivTheme.border).frame(height: 0.5)
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
    let id: UInt64
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

    init(model: BoxModel, id: UInt64, property: String) {
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
                SectionLabel("Date")
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
                SectionLabel("Time")
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
            if divided { DetailHairline() }
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

    /// THE CLOCK, ON THE QUARTER HOUR.
    ///
    /// This was a compact `DatePicker(.hourAndMinute)`, and its real
    /// fault was never that it looked like the system's: it let you dial
    /// 11:47, while every time the CALENDAR places goes through
    /// `CalClock.snap` on the rule that "times land on quarter hours —
    /// 11:47 is never what anyone meant". Two surfaces of one app
    /// disagreeing about what a time is (standing rule 4).
    ///
    /// Steppers rather than a wheel or a field: a due time is almost
    /// always a nudge from the one already there, the app has no
    /// time-string parser and standing rule 5 says a user does not type
    /// one, and this way the quarter-hour law is in the CONTROL rather
    /// than in a validator that has to reject what you typed.
    private var timeRow: some View {
        HStack(spacing: 8) {
            Text("At")
                .font(.system(size: LivType.strong))
                .foregroundStyle(LivTheme.text)
            Spacer(minLength: 12)
            Button { nudge(-CalClock.step) } label: {
                Image(systemName: "minus")
                    .font(.system(size: LivType.label, weight: .semibold))
                    .foregroundStyle(LivTheme.text2)
                    .frame(width: LivRow.touch, height: LivRow.touch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fifteen minutes earlier")
            // NOT `Civil.timeString`, which answers "" for 0000 on the
            // rule that a date-only stamp carries no time. Here the
            // clock always shows one, and midnight is a real 00:00.
            Text(clockLabel)
                .font(.system(size: LivType.strong).monospacedDigit())
                .foregroundStyle(LivTheme.text)
                .frame(minWidth: 68)
                .accessibilityLabel("Due time")
            Button { nudge(CalClock.step) } label: {
                Image(systemName: "plus")
                    .font(.system(size: LivType.label, weight: .semibold))
                    .foregroundStyle(LivTheme.text2)
                    .frame(width: LivRow.touch, height: LivRow.touch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fifteen minutes later")
        }
        .frame(minHeight: LivRow.height)
    }

    /// The clock face, always four digits — see the note at its call
    /// site for why this is not `Civil.timeString`.
    private var clockLabel: String {
        let hm = Civil.hhmm(of: time)
        return String(format: "%02d:%02d", hm / 100, hm % 100)
    }

    /// Move the clock by one step, snapped, and write.
    ///
    /// It wraps within the day rather than running off either end: a due
    /// at 23:45 nudged forward is 00:00 of the same day, not tomorrow —
    /// the DAY is the other control's job, and a time control that
    /// silently changed the date would be the "setting time after date
    /// erases everything" complaint again.
    private func nudge(_ minutes: Int) {
        let day = Civil.day(of: date)
        let now = CalClock.minutes(of: Civil.stamp(day: 0, hhmm: Civil.hhmm(of: time)))
        let moved = (CalClock.snap(now) + minutes + 24 * 60) % (24 * 60)
        if let stamped = Civil.date(day: day, hhmm: CalClock.hhmm(moved)) {
            time = stamped
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
                    .foregroundStyle(has ? LivTheme.red : LivTheme.muted)
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
    let refTarget: UInt64?
}

/// One row per property, values in cell order — a multi-valued property
/// stays one line, never N look-alike rows.
private struct DetailCellGroup: Identifiable {
    let id: Int
    let property: String
    let kind: String
    let values: [DetailCellValue]

    static func groups(_ row: EntityRow, skipping skip: Set<String>) -> [DetailCellGroup] {
        var order: [String] = []
        var kinds: [String: String] = [:]
        var values: [String: [DetailCellValue]] = [:]
        for cell in row.cells ?? [] {
            guard let property = cell.property, !property.isEmpty,
                !skip.contains(property)
            else { continue }
            if values[property] == nil {
                order.append(property)
                kinds[property] = cell.kind ?? ""
            }
            values[property, default: []].append(
                DetailCellValue(value: cell.value ?? "", refTarget: cell.refTarget))
        }
        return order.enumerated().map { i, property in
            DetailCellGroup(
                id: i, property: property, kind: kinds[property] ?? "",
                values: values[property] ?? [])
        }
    }
}

private enum DetailFmt {
    private static let gregorian = Calendar(identifier: .gregorian)

    /// The wire's datetime display ("YYYY-MM-DD[ HH:MM][ -> …]") redrawn
    /// through Civil — "Tue 21 Jul 14:00", spans joined with an arrow.
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
        var out = Civil.dayLabel(day)
        if parts.count > 1 { out += " " + parts[1] }
        return out
    }

    /// The entity row's packed due span, same voice as datetime().
    static func due(_ start: Int64, end: Int64?, dateOnly: Bool) -> String {
        var out = stamp(start, dateOnly: dateOnly)
        if let end, end > 0 {
            out += " → " + stamp(end, dateOnly: dateOnly)
        }
        return out
    }

    private static func stamp(_ civil: Int64, dateOnly: Bool) -> String {
        var out = Civil.dayLabel(Civil.day(of: civil))
        if !dateOnly {
            let time = Civil.timeString(civil)
            if !time.isEmpty { out += " " + time }
        }
        return out
    }

    /// The day a picker is sitting on, in the app's own day voice.
    static func dayLabel(_ date: Date) -> String {
        Civil.dayLabel(Civil.day(of: date))
    }

}
