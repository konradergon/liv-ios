// liv iOS — the metadata editor (design/ios.md §6). EntityInspector is
// the desktop right-panel inspector, full-bleed: kinds, due shortcuts,
// status menu, one compact row per property, trash + undo. Add-property
// moved behind the Settings door (§10 — schema growth is not daily use);
// the Details chip row still adds values for the fixed fields.
// The Desk body owns the title; EntityDetailView stays as a thin pushed
// wrapper (title + inspector) for the NavigationStack callers. Content
// editing waits for M2 (CAS). Rows 40pt+, hairline separators, no cards.

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
    /// A closed vocabulary: non-empty for a select. No create row.
    let options: [String]

    var closed: Bool { !options.isEmpty }

    /// The fields every note shows even when empty — the "zero fill
    /// pressure" core (design/editor-study.md §8: two filled fields is a
    /// finished object). Everything else appears only once it has a value.
    static let core = ["area", "project", "subjects", "people"]

    /// Multi-valued by name — the same rule the camera's chip editor uses
    /// (Camera.swift's CameraChipKind.multi): tags and people accumulate,
    /// area and project replace.
    static func isMulti(_ property: String) -> Bool {
        property == "subjects" || property == "people"
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
            options: options)
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
            box.statusOptions(kind: box.entity(id)?.kinds?.first ?? "") {
                options = $0
            }
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
                // field is directly above this.
                if scrolls {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(livRowTitle(row))
                            .font(.system(size: LivType.display, weight: .semibold))
                            .foregroundStyle(
                                hasName(row) ? LivTheme.text : LivTheme.text3)
                            .lineLimit(2)
                        Spacer(minLength: 4)
                    }
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                }
                HStack(spacing: 8) {
                    // The kind words the box actually holds, each in its
                    // own kind color — not the value hash, which spread
                    // "note" and "event" over the same green.
                    ForEach(row.kinds ?? [], id: \.self) {
                        ValueChip($0, hue: LivKind.named($0).color)
                    }
                    if LivKind.of(row) == .template {
                        ValueChip("template", hue: LivKind.template.color)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 4)
                SectionLabel("Schedule")
                    .padding(.top, 18)
                    .padding(.bottom, 2)
                dueRow(row)
                DetailHairline()
                statusRow(row)
                SectionLabel("Filing")
                    .padding(.top, 22)
                    .padding(.bottom, 2)
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
                        .padding(.top, 22)
                        .padding(.bottom, 2)
                    ForEach(Array(extras.enumerated()), id: \.element.id) { i, group in
                        if i > 0 { DetailHairline() }
                        cellRow(group)
                    }
                }
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
                .padding(.top, 22)
                .padding(.bottom, 2)
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
            // A mis-tap here WRITES cells — full 44pt targets, the
            // FloatCircle rule (audit, 2026-08-04).
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
                    Text("—")
                        .font(.system(size: LivType.strong))
                        .foregroundStyle(LivTheme.muted)
                }
            }
            .frame(minHeight: LivRow.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: status

    /// An empty scoped vocabulary (untyped scraps) must never render a
    /// live-looking Menu with zero items — a silent no-op (eval §5.4).
    /// Disabled-with-explainer instead; with a vocabulary, the whole row
    /// is the menu (full-width target, like the due row).
    @ViewBuilder private func statusRow(_ row: EntityRow) -> some View {
        Group {
            if options.isEmpty {
                HStack {
                    DetailRowLabel("status")
                    Spacer(minLength: 12)
                    if let status = row.status, !status.isEmpty {
                        ValueChip(status)  // display-only; nothing to change it to
                    } else {
                        Text("none for this kind")
                            .font(.system(size: LivType.strong))
                            .foregroundStyle(LivTheme.muted)
                    }
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
                            ValueChip(status)
                        } else {
                            Text("—")
                                .font(.system(size: LivType.strong))
                                .foregroundStyle(LivTheme.muted)
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
    /// (owner, 2026-08-06). The template marker is a chip too.
    private func skipSet(_ row: EntityRow) -> Set<String> {
        Set(
            [
                "name", "status", "content", "type", "created",
                // A file's path and format are FACTS, shown by the file
                // tab's own header. A row you cannot edit is a lie about
                // what this list is for (owner, 2026-08-06).
                "file", "format",
                Template.property, dueProperty(row),
            ] + InspectorField.core)
    }

    private func hasName(_ row: EntityRow) -> Bool {
        (row.cells ?? []).contains {
            $0.property == "name" && !($0.value ?? "").isEmpty
        }
    }

    /// The item's own name, or the derived title every list shows, or a
    /// grey "Untitled". The bare `#id` the core emits for an entity with
    /// nothing at all reads as "Untitled" here — an id is a fine label in
    /// a list of many, and no label at all above a single item.
    private func displayName(_ row: EntityRow) -> String {
        let derived = livRowTitle(row)
        return derived == "#\(row.id)" ? "Untitled" : derived
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
                    Text("—")
                        .font(.system(size: LivType.strong))
                        .foregroundStyle(LivTheme.muted)
                } else {
                    HStack(spacing: 5) {
                        ForEach(held.prefix(3), id: \.self) { ValueChip($0) }
                        if held.count > 3 {
                            Text("+\(held.count - 3)")
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
                    ValueChip(v.value, hue: LivKind.color(of: box.entity(target)))
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

    // The verbs left this panel (owner, 2026-08-02): Save as template and
    // Move to Trash act on the DOCUMENT, so they live in the desk's •••
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
            Text(field.property.uppercased())
                .font(.system(size: LivType.label, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(LivTheme.text3)
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
                    }
                    if creatable {
                        row("Create \u{201C}\(trimmed)\u{201D}", accent: true) { add(trimmed) }
                    }
                    if all.isEmpty && trimmed.isEmpty {
                        EmptyHint(
                            field.closed ? "Nothing to choose from." : "Type to create one.")
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
    }

    // MARK: writes — the box is the only truth; the sheet re-reads nothing

    private func add(_ value: String) {
        if let onPick {
            onPick(value)
            dismiss()
            return
        }
        if field.multi {
            box.addCell(id, field.property, value)
        } else {
            box.set(id, field.property, value)
            dismiss()  // one value means the question is answered
        }
        typed = ""
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
                } else {
                    Circle().fill(Hue.dot(label)).frame(width: 7, height: 7)
                        .frame(width: 16)
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

// MARK: - the pushed wrapper (title + inspector; Today/Tasks/Search still push it)

struct EntityDetailView: View {
    let id: UInt64

    @EnvironmentObject var box: BoxModel

    @State private var title = ""
    @State private var titleSeeded = false
    @FocusState private var titleFocused: Bool

    init(id: UInt64) {
        self.id = id
    }

    var body: some View {
        Group {
            if box.entity(id) != nil {
                VStack(alignment: .leading, spacing: 0) {
                    titleField
                        .padding(.horizontal, 16)
                    EntityInspector(id: id)
                }
            } else {
                EmptyHint("This was deleted.")
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .background(LivTheme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .tint(LivTheme.accent)
        .onAppear { seedTitle() }
        .onChange(of: box.entity(id)?.title) {
            // The snapshot moved under us (undo, another surface): reseed
            // unless the caret is in the field — a draft never loses.
            if !titleFocused {
                titleSeeded = false
                seedTitle()
            }
        }
    }

    private var titleField: some View {
        TextField("Untitled", text: $title, axis: .vertical)
            .font(.system(size: LivType.title, weight: .semibold))
            .foregroundStyle(LivTheme.text)
            .lineLimit(1...3)
            .focused($titleFocused)
            .submitLabel(.done)
            .onSubmit { commitTitle() }
            .onChange(of: titleFocused) {
                if !titleFocused { commitTitle() }
            }
            .padding(.vertical, 8)
    }

    private func seedTitle() {
        guard !titleSeeded else { return }
        title = box.entity(id)?.title ?? ""
        titleSeeded = true
    }

    private func commitTitle() {
        // Never onto a gone or trashed note (same guard as the desk's
        // title commit — a post-trash commit re-writes the old name).
        guard let row = box.entity(id), row.trashed != true else { return }
        let stored = row.title ?? ""
        let typed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard typed != stored, !typed.isEmpty else {
            title = stored  // an emptied field reverts, never erases the name
            return
        }
        box.set(id, "name", typed)
    }
}

// MARK: - shared row pieces

private struct DetailRowLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    /// Each field's COLOR — no glyph. Icons here were tried on
    /// 2026-08-12 and rejected the same day: a clock for "due" and a tag
    /// for "subjects" are pictures of the word beside them, which reads
    /// as noise rather than information (owner: "icons for properties
    /// are confusing, but color indication of some sort is ok"). A dot
    /// is the owner's own metaphor — it says which family a field
    /// belongs to and claims nothing more.
    ///
    /// Kind chips elsewhere (a note, a task, an event) keep their glyphs:
    /// there the icon says what a THING is, which a word does not.
    private static let hues: [String: Color] = [
        "due": LivTheme.teal,
        "status": LivTheme.accent,
        "area": LivTheme.amber,
        "project": LivTheme.green,
        "subjects": LivTheme.purple,
        "people": LivTheme.pink,
    ]

    var body: some View {
        HStack(spacing: 10) {
            if let color = Self.hues[text.lowercased()] {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .frame(width: 26, alignment: .center)
            }
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
                    .padding(.top, 18)
                    .padding(.bottom, 6)
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
                    .padding(.top, 22)
                    .padding(.bottom, 6)
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

    private var monthPicker: some View {
        DatePicker("Due date", selection: $date, displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .padding(.vertical, 4)
            .onChange(of: date) { commit() }
    }

    private var timeRow: some View {
        HStack(spacing: 8) {
            Text("At")
                .font(.system(size: LivType.strong))
                .foregroundStyle(LivTheme.text)
            Spacer(minLength: 12)
            DatePicker("Due time", selection: $time, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
        .frame(minHeight: LivRow.height)
        .onChange(of: time) {
            timed = true  // setting a clock time is how an all-day thing gets one
            commit()
        }
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
