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

    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel

    @State private var options: [StatusOption] = []
    @State private var showDueSheet = false
    @State private var confirmTrash = false
    /// The field whose sheet is open. One sheet serves every property.
    @State private var editing: InspectorField?

    init(id: UInt64) {
        self.id = id
    }

    var body: some View {
        Group {
            if let row = box.entity(id) {
                list(row)
            } else {
                EmptyHint("This entity is gone.")
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .confirmationDialog(
            "Move to Trash?", isPresented: $confirmTrash,
            titleVisibility: .visible
        ) {
            // Soft, reversible, never cascades — still worth one ask.
            Button("Move to Trash", role: .destructive) {
                box.trash(id)
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

    private func list(_ row: EntityRow) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let kinds = row.kinds, !kinds.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(kinds, id: \.self) { ValueChip($0) }
                    }
                    .padding(.vertical, 8)
                }
                dueRow(row)
                statusRow(row)
                // Zero fill pressure: the core fields are always here, even
                // empty; everything else appears only once it holds a value
                // (design/editor-study.md §8). Two filled fields is a
                // finished object — the rows must never nag.
                ForEach(InspectorField.core, id: \.self) { property in
                    fieldRow(property, row)
                }
                ForEach(DetailCellGroup.groups(row, skipping: skipSet(row))) {
                    cellRow($0)
                }
                footer(row)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
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
                        .font(.system(size: 14).monospacedDigit())
                        .foregroundStyle(LivTheme.text)
                } else {
                    Text("—")
                        .font(.system(size: 14))
                        .foregroundStyle(LivTheme.muted)
                }
            }
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { DetailHairline() }
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
                            .font(.system(size: 14))
                            .foregroundStyle(LivTheme.muted)
                    }
                }
                .frame(minHeight: 40)
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
                                .font(.system(size: 14))
                                .foregroundStyle(LivTheme.muted)
                        }
                    }
                    .frame(minHeight: 40)
                    .contentShape(Rectangle())
                }
            }
        }
        .overlay(alignment: .bottom) { DetailHairline() }
    }

    // MARK: the general property rows

    private func skipSet(_ row: EntityRow) -> Set<String> {
        Set(["name", "status", dueProperty(row)] + InspectorField.core)
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
                        .font(.system(size: 14))
                        .foregroundStyle(LivTheme.muted)
                } else {
                    HStack(spacing: 5) {
                        ForEach(held.prefix(3), id: \.self) { ValueChip($0) }
                        if held.count > 3 {
                            Text("+\(held.count - 3)")
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(LivTheme.text3)
                        }
                    }
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { DetailHairline() }
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
        .frame(minHeight: 40)
        .overlay(alignment: .bottom) { DetailHairline() }
    }

    /// A reference chip navigates — open the target as a Desk tab, the
    /// Ref-span gesture grammar. Everything else just displays.
    @ViewBuilder private func cellValue(_ v: DetailCellValue, kind: String) -> some View {
        switch kind {
        case "reference":
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
                .font(.system(size: 14).monospacedDigit())
                .foregroundStyle(LivTheme.text)
        default:
            Text(v.value)
                .font(.system(size: 14))
                .foregroundStyle(LivTheme.text)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: trash + undo (toolbar verbs relocated; the inspector has no bar)

    private func footer(_ row: EntityRow) -> some View {
        HStack {
            Button {
                box.undo()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .medium))
                    Text("Undo")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(LivTheme.text2)
                .frame(height: 40)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            if row.trashed == true {
                Text("In the Trash — Undo restores it.")
                    .font(.system(size: 11))
                    .foregroundStyle(LivTheme.muted)
            } else {
                Button {
                    confirmTrash = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .medium))
                        Text("Move to Trash")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(LivTheme.red)
                    .frame(height: 40)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
    }
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
                .font(.system(size: 11, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(LivTheme.text3)
            if !field.closed {
                TextField("Search or create…", text: $typed)
                    .font(.system(size: 16))
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
        if field.multi {
            box.addCell(id, field.property, value)
        } else {
            box.set(id, field.property, value)
            dismiss()  // one value means the question is answered
        }
        typed = ""
    }

    private func remove(_ value: String) {
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
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(LivTheme.accent)
                        .frame(width: 16)
                } else {
                    Circle().fill(Hue.dot(label)).frame(width: 7, height: 7)
                        .frame(width: 16)
                }
                Text(label)
                    .font(.system(size: 16))
                    .foregroundStyle(accent ? LivTheme.accent : LivTheme.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(LivTheme.accent)
                }
            }
            .frame(height: 46)
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
                EmptyHint("This entity is gone.")
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
            .font(.system(size: 17, weight: .semibold))
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
        let stored = box.entity(id)?.title ?? ""
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
    var body: some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(LivTheme.text3)
            .lineLimit(1)
            .layoutPriority(1)
    }
}

private struct DetailHairline: View {
    var body: some View {
        Rectangle().fill(LivTheme.border).frame(height: 0.5)
    }
}

// MARK: - the due shortcuts sheet

/// M1 due editing is shortcuts + one date picker. No clear leg — the
/// model has no unset verb yet; setSpan writes, never erases. Internal:
/// the Tasks row's "Pick" swipe verb opens this same sheet.
struct DetailDueSheet: View {
    let model: BoxModel
    let id: UInt64
    let property: String

    @Environment(\.dismiss) private var dismiss
    @State private var picked = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Due")
                .padding(.top, 18)
                .padding(.bottom, 6)
            shortcut("Today", preview: preview(Civil.todayDay())) {
                commit(Civil.stamp(day: Civil.todayDay(), hhmm: 0), dateOnly: true)
            }
            shortcut("Tonight", preview: previewTonight) {
                commit(Civil.stamp(day: Civil.todayDay(), hhmm: 2000), dateOnly: false)
            }
            shortcut("Tomorrow", preview: preview(Civil.addDays(Civil.todayDay(), 1))) {
                commit(Civil.stamp(day: Civil.addDays(Civil.todayDay(), 1), hhmm: 0), dateOnly: true)
            }
            // On a Friday, Weekend IS tomorrow — one option, not two.
            if DetailFmt.nextSaturday() != Civil.addDays(Civil.todayDay(), 1) {
                shortcut("Weekend", preview: preview(DetailFmt.nextSaturday())) {
                    commit(Civil.stamp(day: DetailFmt.nextSaturday(), hhmm: 0), dateOnly: true)
                }
            }
            HStack {
                DatePicker(
                    "Pick a date", selection: $picked,
                    displayedComponents: .date
                )
                .font(.system(size: 13))
                .foregroundStyle(LivTheme.text)
                Button("Set") {
                    commit(Civil.stamp(day: DetailFmt.day(of: picked), hhmm: 0), dateOnly: true)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LivTheme.accent)
            }
            .frame(minHeight: 44)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .background(LivTheme.surface)
        .tint(LivTheme.accent)
    }

    private func commit(_ start: Int64, dateOnly: Bool) {
        model.setSpan(id, property, start: start, end: 0, dateOnly: dateOnly)
        dismiss()
    }

    private func shortcut(_ label: String, preview: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(LivTheme.text)
                Spacer()
                Text(preview)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(LivTheme.muted)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { DetailHairline() }
    }

    private var previewTonight: String {
        Civil.dayLabel(Civil.todayDay()) + " 20:00"
    }

    private func preview(_ day: Int64) -> String {
        Civil.dayLabel(day)
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

    static func day(of date: Date) -> Int64 {
        let c = gregorian.dateComponents([.year, .month, .day], from: date)
        return Int64(c.year ?? 0) * 10_000 + Int64((c.month ?? 0) * 100 + (c.day ?? 0))
    }

    /// The next Saturday strictly after today.
    static func nextSaturday() -> Int64 {
        var day = Civil.todayDay()
        for _ in 0..<7 {
            day = Civil.addDays(day, 1)
            var parts = DateComponents()
            parts.year = Int(day / 10_000)
            parts.month = Int((day / 100) % 100)
            parts.day = Int(day % 100)
            parts.hour = 12
            if let date = gregorian.date(from: parts),
                gregorian.component(.weekday, from: date) == 7
            {
                return day
            }
        }
        return day
    }
}
