// lotus — the anchored editors (P11.5g, design §2.4). All four are one
// popover shape: anchored to the focused row, preferred edge toward the
// content pane, a filter field where the law asks for one, then a result
// list. ⏎ picks, Ctrl+⏎ creates, Esc closes. Writes ride the existing
// seams only — plus lotus_add_property_at, the one exception the failing
// test forced (the core refuses set on unknown names).

import AppKit
import SwiftUI

// MARK: - which editor a row takes

enum RowEditor {
    case inline, status, pool, date, toggle, none
}

/// The dispatch law: text-shaped rows edit inline; status takes its digit
/// picker; other selects, tags and references take the value pool; dates
/// take the role/span editor. `type` is deferred — its options are plumbing
/// entities the snapshot doesn't carry, and the write needs the schema
/// pass's set-type seam (recorded delta; the row renders read-only).
func rowEditor(for property: PropertyRow) -> RowEditor {
    switch property.kind {
    case "text", "number", "richtext": return .inline
    case "datetime": return .date
    case "bool": return .toggle
    case "select": return property.name == "status" ? .status : .pool
    case "tag": return .pool
    case "reference": return property.name == "type" ? .none : .pool
    default: return .none  // file cells are born through add-file
    }
}

// MARK: - civil parsing (the seam's civil_text, mirrored)

extension Civil {
    /// The seam's own text form ("yyyy-mm-dd[ hh:mm]") — ffi civil_text,
    /// mirrored. Civil.text is DISPLAY ("Wed, Jul 15", no year); editors
    /// must prefill with THIS or an untouched save re-parses to garbage.
    static func seamText(_ civil: Int64, dateOnly: Bool) -> String {
        let ymd = civil / 10_000
        let hm = civil % 10_000
        var out = String(
            format: "%04d-%02d-%02d", ymd / 10_000, (ymd / 100) % 100, ymd % 100)
        if !dateOnly {
            out += String(format: " %02d:%02d", hm / 100, hm % 100)
        }
        return out
    }

    /// "yyyy-mm-dd[ hh:mm]" → (packed civil, dateOnly). The exact inverse
    /// of seamText so a round-trip is provably lossless.
    static func parse(_ raw: String) -> (civil: Int64, dateOnly: Bool)? {
        let parts = raw.trimmingCharacters(in: .whitespaces)
            .split(separator: " ", omittingEmptySubsequences: true)
        guard let ymd = parts.first, parts.count <= 2 else { return nil }
        let d = ymd.split(separator: "-")
        guard d.count == 3, let y = Int64(d[0]), let m = Int64(d[1]), let day = Int64(d[2]),
            (1...12).contains(m), (1...31).contains(day)
        else { return nil }
        var hhmm: Int64 = 0
        var dateOnly = true
        if parts.count == 2 {
            let t = parts[1].split(separator: ":")
            guard t.count == 2, let h = Int64(t[0]), let minute = Int64(t[1]),
                (0...23).contains(h), (0...59).contains(minute)
            else { return nil }
            hhmm = h * 100 + minute
            dateOnly = false
        }
        return ((y * 10_000 + m * 100 + day) * 10_000 + hhmm, dateOnly)
    }
}

// MARK: - shared popover chrome

private struct PopCap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundColor(Theme.mutedFg)
            .padding(.init(top: 8, leading: 10, bottom: 4, trailing: 10))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PopRow: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> AnyView

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) { content() }
                .padding(.horizontal, 10)
                .frame(minHeight: 26)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? Theme.accentTint : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PopHint: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundColor(Theme.mutedFg)
            .padding(.init(top: 4, leading: 10, bottom: 8, trailing: 10))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - the value pool (badge 9, entry 666)

/// Pool order is the D08 three-tier law: ① this vault (distinct live
/// values, fetched ONCE on open through the box queue — type-to-filter is
/// client-side), ② the seeded option set, ③ Create on Ctrl+⏎ (text/tag
/// kinds only; generic select-option birth is deferred).
struct ValuePoolPopover: View {
    @ObservedObject var model: BoxModel
    let entity: EntityRow
    let spec: InspectorRowSpec
    var onDone: (Bool) -> Void

    @State private var filter = ""
    @State private var vault: [DistinctValue] = []
    @State private var selected = 0
    @FocusState private var fieldFocused: Bool

    private var isMulti: Bool {
        // One chip each in the blueprint: project anchors, type classifies.
        !["project", "type"].contains(spec.property.name)
    }
    private var allowCreate: Bool { spec.property.kind == "tag" }

    private struct PoolEntry: Identifiable {
        let id: String
        let value: String
        let detail: String
    }

    private var entries: [PoolEntry] {
        let needle = filter.lowercased()
        var seen = Set<String>()
        var out: [PoolEntry] = []
        for v in vault where needle.isEmpty || v.value.lowercased().contains(needle) {
            guard seen.insert(v.value.lowercased()).inserted else { continue }
            out.append(
                PoolEntry(id: "v.\(v.value)", value: v.value, detail: "in vault · \(v.count) · ⏎ add"))
        }
        for option in spec.property.options
        where !option.isHidden
            && (needle.isEmpty || option.name.lowercased().contains(needle)) {
            guard seen.insert(option.name.lowercased()).inserted else { continue }
            out.append(PoolEntry(id: "s.\(option.name)", value: option.name, detail: "seeded"))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.mutedFg)
                TextField("filter…", text: $filter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($fieldFocused)
                    .onSubmit { pickSelected() }
                    .onExitCommand { onDone(false) }
            }
            .padding(.init(top: 9, leading: 10, bottom: 6, trailing: 10))
            Divider()
            let list = entries
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { at, entry in
                        PopRow(selected: at == selected, action: { pick(entry.value) }) {
                            AnyView(
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(nsColor: Hues.valueHex(entry.value)))
                                        .frame(width: 7, height: 7)
                                    Text(entry.value).font(.system(size: 12)).lineLimit(1)
                                    Spacer(minLength: 6)
                                    Text(entry.detail)
                                        .font(.system(size: 10))
                                        .foregroundColor(Theme.mutedFg)
                                })
                        }
                    }
                    if list.isEmpty && !allowCreate {
                        Text("nothing in the vault yet")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.mutedFg)
                            .padding(8)
                    }
                }
            }
            .frame(maxHeight: 190)
            if allowCreate {
                Divider()
                let typed = filter.trimmingCharacters(in: .whitespaces)
                PopRow(selected: false, action: { create() }) {
                    AnyView(
                        HStack(spacing: 8) {
                            Image(systemName: "plus").font(.system(size: 10))
                            Text(typed.isEmpty ? "Create…" : "Create “\(typed)”")
                                .font(.system(size: 12))
                            Spacer(minLength: 6)
                            Text("Ctrl+⏎").font(.system(size: 10))
                        }
                        .foregroundColor(Theme.mutedFg))
                }
            }
            PopHint(text: "pool: ① this vault → ② seeded → ③ create (D08)")
        }
        .frame(width: 240)
        .onAppear {
            fieldFocused = true
            model.distinctValues(property: spec.property.name) { vault = $0 }
        }
        .onChange(of: filter) { selected = 0 }
        .onKeyPress(.upArrow) {
            selected = max(0, selected - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selected = min(max(0, entries.count - 1), selected + 1)
            return .handled
        }
        .onKeyPress(.return, phases: .down) { press in
            if press.modifiers.contains(.control) && allowCreate {
                create()
                return .handled
            }
            return .ignored  // plain ⏎ rides the field's onSubmit
        }
    }

    private func pickSelected() {
        let list = entries
        if list.indices.contains(selected) {
            pick(list[selected].value)
        } else if allowCreate {
            create()
        } else {
            NSSound.beep()
        }
    }

    private func create() {
        let typed = filter.trimmingCharacters(in: .whitespaces)
        guard allowCreate, !typed.isEmpty else {
            NSSound.beep()
            return
        }
        write(typed)
    }

    private func pick(_ value: String) {
        write(value)
    }

    /// The write: tags by string; references resolve the display title to
    /// an entity id in the snapshot (`#id` through the ordinary seams) —
    /// plumbing entities aren't in it, which is exactly why `type` never
    /// reaches this editor.
    private func write(_ value: String) {
        var raw = value
        if spec.property.kind == "reference" {
            // Resolve the display title to an id. The pool carries titles,
            // not ids, so a duplicate title is genuinely ambiguous — REFUSE
            // rather than silently linking whichever entity sorts first (the
            // review's finding; the core's own "refuse, never guess" ethos).
            // Id disambiguation waits for an id-carrying pool (recorded).
            let matches = model.rows(model.snap?.everything ?? [])
                .filter { $0.title.lowercased() == value.lowercased() }
            guard matches.count == 1, let target = matches.first else {
                NSSound.beep()
                return
            }
            raw = "#\(target.id)"
        }
        let done: (Bool) -> Void = { ok in
            if !ok { NSSound.beep() }
            onDone(ok)
        }
        if isMulti {
            model.addCell(entity.id, property: spec.property.name, value: raw, done: done)
        } else {
            model.set(entity.id, property: spec.property.name, value: raw, done: done)
        }
    }
}

// MARK: - the status picker (badge 17, entry 680)

/// Cap `status · digits pick`; the kind's vocabulary in board order, each
/// with its digit, its hue dot, its name. A pick is ONE set — replacing,
/// so a future board column moves on the same write. `New option… Ctrl+⏎`
/// rides lotus_add_status_option_at (hue −1: the vocabulary editor is a
/// board-pass feature).
struct StatusPickerPopover: View {
    @ObservedObject var model: BoxModel
    let entity: EntityRow
    let spec: InspectorRowSpec
    var onDone: (Bool) -> Void

    @State private var creating = false
    @State private var newName = ""
    @FocusState private var nameFocused: Bool

    private var vocabulary: [OptionRow] {
        statusVocabulary(model, kind: entity.kinds.first ?? "")
    }
    private var current: String { spec.cells.first?.value ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PopCap(text: "status · digits pick")
            ForEach(Array(vocabulary.prefix(9).enumerated()), id: \.element.id) { at, option in
                PopRow(selected: option.name == current, action: { pick(option.name) }) {
                    AnyView(
                        HStack(spacing: 8) {
                            KeyCap(label: "\(at + 1)")
                            Circle()
                                .fill(
                                    option.hue.map { Hues.degrees($0) }
                                        ?? Color(nsColor: .tertiaryLabelColor)
                                )
                                .frame(width: 7, height: 7)
                            Text(option.name).font(.system(size: 12))
                            Spacer(minLength: 6)
                            if option.name == current {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(Theme.accent)
                            }
                        })
                }
            }
            Divider()
            if creating {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.mutedFg)
                    TextField("option name", text: $newName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($nameFocused)
                        .onSubmit { createOption() }
                        .onExitCommand { creating = false }
                }
                .padding(.init(top: 6, leading: 10, bottom: 6, trailing: 10))
            } else {
                PopRow(selected: false, action: { creating = true; nameFocused = true }) {
                    AnyView(
                        HStack(spacing: 8) {
                            Image(systemName: "plus").font(.system(size: 10))
                            Text("New option…").font(.system(size: 12))
                            Spacer(minLength: 6)
                            Text("Ctrl+⏎").font(.system(size: 10))
                        }
                        .foregroundColor(Theme.mutedFg))
                }
            }
        }
        .frame(width: 220)
        .padding(.bottom, 6)
        .onKeyPress(phases: .down) { press in
            if press.key == .escape {
                onDone(false)
                return .handled
            }
            if press.key == .return && press.modifiers.contains(.control) {
                creating = true
                nameFocused = true
                return .handled
            }
            // Digits pick — the popover's own local key handling (§2.3).
            if !creating, let digit = press.characters.first?.wholeNumberValue,
                (1...9).contains(digit), digit <= vocabulary.count
            {
                pick(vocabulary[digit - 1].name)
                return .handled
            }
            return .ignored
        }
    }

    private func pick(_ name: String) {
        model.set(entity.id, property: "status", value: name) { ok in
            if !ok { NSSound.beep() }
            onDone(ok)
        }
    }

    private func createOption() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            NSSound.beep()
            return
        }
        model.addStatusOption(kind: entity.kinds.first ?? "", name: name) { id in
            guard id != nil else { return }  // refusal already beeped
            pick(name)
        }
    }
}

// MARK: - the date editor (badge 23, entry 695)

/// Role ring + span + repeat. Space (or a click on the ring) cycles via
/// lotus_cycle_date_role_at — the value MOVES to the next role's row, so
/// the pane's focus follows it. Span writes ride lotus_set_span_at; end 0
/// collapses to a plain date; end ≤ start is refused before the box opens
/// (shake, no toast). Repeat displays and writes the recurrence property
/// the P11 engine already reads.
struct DateEditorPopover: View {
    @ObservedObject var model: BoxModel
    let entity: EntityRow
    let spec: InspectorRowSpec
    var onCycleRole: () -> Void
    var onDone: (Bool) -> Void

    /// content.rs's RING, mirrored — the one place the shell names it.
    static let ring = ["due", "date", "valid-until", "occurred", "purchased-on"]

    /// Which text field, if any, holds the caret — Space must type a space
    /// there, and cycle the role only when focus is on the role list (the
    /// review: the old single startFocused guard broke end/repeat input).
    private enum Field { case start, end, repeatRule }

    @State private var start = ""
    @State private var end = ""
    @State private var repeatRule = ""
    @FocusState private var focus: Field?

    private var isPositioning: Bool { entity.positionedBy == spec.property.name }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PopCap(text: "date role · Space cycles")
            let known = Set(model.properties().map(\.name))
            ForEach(Self.ring.filter { known.contains($0) }, id: \.self) { role in
                let isCurrent = role == spec.property.name
                PopRow(selected: isCurrent, action: { if !isCurrent { onCycleRole() } }) {
                    AnyView(
                        HStack(spacing: 8) {
                            Image(systemName: isCurrent ? "checkmark" : "circle.dashed")
                                .font(.system(size: 9))
                                .foregroundColor(isCurrent ? Theme.accent : Theme.mutedFg)
                            Text(role).font(.system(size: 12))
                            Spacer(minLength: 6)
                            Text(
                                isCurrent && isPositioning
                                    ? "calendar · renders on calendar" : "lookup"
                            )
                            .font(.system(size: 10))
                            .foregroundColor(Theme.mutedFg)
                        })
                }
            }
            Divider()
            PopCap(text: "span")
            HStack(spacing: 6) {
                TextField("yyyy-mm-dd [hh:mm]", text: $start)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12).monospacedDigit())
                    .focused($focus, equals: .start)
                    .onSubmit { save() }
                    .onExitCommand { onDone(false) }
                Text("→").font(.system(size: 11)).foregroundColor(Theme.mutedFg)
                TextField("end (optional)", text: $end)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12).monospacedDigit())
                    .focused($focus, equals: .end)
                    .onSubmit { save() }
                    .onExitCommand { onDone(false) }
                if !end.isEmpty {
                    Button {
                        end = ""
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.mutedFg)
                    }
                    .buttonStyle(.plain)
                    .help("Collapse to a plain date")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            if model.property(named: "recurrence") != nil {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "repeat")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.mutedFg)
                    TextField("Repeat… (every week, every 2 days)", text: $repeatRule)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($focus, equals: .repeatRule)
                        .onSubmit { saveRepeat() }
                        .onExitCommand { onDone(false) }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            PopHint(text: "⏎ saves · Esc reverts · end 0 = plain date")
        }
        .frame(width: 250)
        .onAppear {
            focus = .start
            if isPositioning, let due = entity.due {
                start = Civil.seamText(due, dateOnly: entity.dueDateOnly)
                if let dueEnd = entity.dueEnd {
                    end = Civil.seamText(dueEnd, dateOnly: entity.dueDateOnly)
                }
            } else if let value = spec.cells.first?.value {
                // The cell serializes a span as ASCII "start -> end"
                // (lotus_views::display); splitting on the display arrow
                // U+2192 left the whole string in `start`, and save() then
                // refused the 3-token parse (the review's high).
                let parts = value.components(separatedBy: " -> ")
                start = parts.first?.trimmingCharacters(in: .whitespaces) ?? value
                if parts.count > 1 {
                    end = parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
            repeatRule =
                entity.cells.first { $0.property == "recurrence" }?.value ?? ""
        }
        .onKeyPress(.space, phases: .down) { _ in
            // Space cycles the role only when NO text field holds the caret
            // (focus is on the role list); inside any span/repeat field a
            // space stays a space (the review's finding).
            if focus != nil { return .ignored }
            onCycleRole()
            return .handled
        }
    }

    private func save() {
        guard let (startCivil, startDateOnly) = Civil.parse(start) else {
            NSSound.beep()
            return
        }
        var endCivil: Int64 = 0
        if !end.isEmpty {
            guard let (parsed, _) = Civil.parse(end) else {
                NSSound.beep()
                return
            }
            endCivil = parsed
        }
        model.setSpan(
            id: entity.id, property: spec.property.name,
            start: startCivil, end: endCivil, dateOnly: startDateOnly
        ) { ok in
            if !ok { NSSound.beep() }  // end ≤ start and kin: shake, no toast
            onDone(ok)
        }
    }

    private func saveRepeat() {
        let rule = repeatRule.trimmingCharacters(in: .whitespaces)
        let stored = entity.cells.first { $0.property == "recurrence" }?.value ?? ""
        guard rule != stored else {
            onDone(false)
            return
        }
        if rule.isEmpty {
            model.unset(entity.id, property: "recurrence")
            onDone(true)
        } else {
            model.set(entity.id, property: "recurrence", value: rule) { ok in
                if !ok { NSSound.beep() }
                onDone(ok)
            }
        }
    }
}

// MARK: - add-property (badge 13, entry 670)

/// Type-ahead over the catalog ranked by usage descending, rendered
/// `name · kind · on N objects`. Picking an existing property reveals its
/// row with the editor open. The create leg (Ctrl+⏎) asks for the first
/// value, infers the kind from it (number → date → bool → text), and
/// births the definition through lotus_add_property_at — the seam the
/// failing test forced.
struct AddPropertyPopover: View {
    @ObservedObject var model: BoxModel
    let entity: EntityRow
    /// Called with the definition id to reveal (existing pick or fresh birth).
    var onReveal: (UInt64) -> Void
    var onDone: () -> Void

    @State private var filter = ""
    @State private var selected = 0
    @State private var creating = false
    @State private var firstValue = ""
    @FocusState private var fieldFocused: Bool
    @FocusState private var valueFocused: Bool

    private var candidates: [PropertyRow] {
        let needle = filter.lowercased()
        return model.properties()
            .filter { !InspectorLayout.reserved.contains($0.name) }
            .filter { needle.isEmpty || $0.name.lowercased().contains(needle) }
            .sorted { ($0.carrierCount, $1.name) > ($1.carrierCount, $0.name) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.mutedFg)
                TextField("property…", text: $filter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($fieldFocused)
                    .onSubmit { pickSelected() }
                    .onExitCommand { onDone() }
            }
            .padding(.init(top: 9, leading: 10, bottom: 6, trailing: 10))
            Divider()
            let list = candidates
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { at, prop in
                        PopRow(selected: at == selected, action: { onReveal(prop.id); onDone() }) {
                            AnyView(
                                HStack(spacing: 8) {
                                    Text(prop.name).font(.system(size: 12))
                                    Spacer(minLength: 6)
                                    Text("\(prop.kind) · on \(prop.carrierCount)")
                                        .font(.system(size: 10))
                                        .foregroundColor(Theme.mutedFg)
                                })
                        }
                    }
                }
            }
            .frame(maxHeight: 170)
            Divider()
            if creating {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.mutedFg)
                    TextField("first value (infers the kind)", text: $firstValue)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($valueFocused)
                        .onSubmit { create() }
                        .onExitCommand { creating = false }
                }
                .padding(.init(top: 6, leading: 10, bottom: 6, trailing: 10))
            } else {
                let typed = filter.trimmingCharacters(in: .whitespaces)
                PopRow(selected: false, action: { beginCreate() }) {
                    AnyView(
                        HStack(spacing: 8) {
                            Image(systemName: "plus").font(.system(size: 10))
                            Text(
                                typed.isEmpty
                                    ? "Create as new property…"
                                    : "Create “\(typed)” as new property"
                            )
                            .font(.system(size: 12))
                            Spacer(minLength: 6)
                            Text("Ctrl+⏎").font(.system(size: 10))
                        }
                        .foregroundColor(Theme.mutedFg))
                }
            }
            PopHint(text: "type inferred from the first value · exists vault-wide at once")
        }
        .frame(width: 250)
        .onAppear { fieldFocused = true }
        .onChange(of: filter) { selected = 0 }
        .onKeyPress(.upArrow) {
            selected = max(0, selected - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selected = min(max(0, candidates.count - 1), selected + 1)
            return .handled
        }
        .onKeyPress(.return, phases: .down) { press in
            if press.modifiers.contains(.control) {
                beginCreate()
                return .handled
            }
            return .ignored
        }
    }

    private func pickSelected() {
        let list = candidates
        if list.indices.contains(selected) {
            onReveal(list[selected].id)
            onDone()
        } else {
            beginCreate()
        }
    }

    private func beginCreate() {
        guard !filter.trimmingCharacters(in: .whitespaces).isEmpty else {
            NSSound.beep()
            return
        }
        creating = true
        valueFocused = true
    }

    /// Kind inference, in the order a typed value disambiguates: a parseable
    /// number is a number, a parseable date is a date, a yes/no is a bool,
    /// everything else is text. Empty value → a text property, no cell.
    private func create() {
        let name = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let value = firstValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            NSSound.beep()
            return
        }
        let kind: String
        if value.isEmpty {
            kind = "text"
        } else if Double(value) != nil {
            kind = "number"
        } else if Civil.parse(value) != nil {
            kind = "datetime"
        } else if ["true", "false", "yes", "no"].contains(value.lowercased()) {
            kind = "bool"
        } else {
            kind = "text"
        }
        model.addProperty(name: name, kind: kind) { born in
            guard let born else { return }  // refusal already beeped
            if value.isEmpty {
                onReveal(born)
                onDone()
            } else {
                model.set(entity.id, property: name, value: value) { _ in
                    onReveal(born)
                    onDone()
                }
            }
        }
    }
}

// MARK: - the row menu (badge 26, entry 700)

/// Opened by ⋯, H, or right-click. Property definitions are entities and
/// PropertyRow.id IS the definition's entity id, so the writes are the
/// ordinary seams. Two items wait for the schema pass: "Change type"
/// (vault-wide re-parse story) and "Hide on <kind>" — hide-on-kind is a
/// REFERENCE cell to the kind entity, whose id the snapshot doesn't
/// carry (the same gap that defers the type editor; recorded delta).
struct RowMenuPopover: View {
    @ObservedObject var model: BoxModel
    let entity: EntityRow
    let spec: InspectorRowSpec
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PopCap(text: "property · \(spec.property.name)")
            PopRow(selected: false, action: { editName() }) {
                AnyView(
                    HStack(spacing: 8) {
                        Image(systemName: "pencil").font(.system(size: 10))
                        Text("Edit name").font(.system(size: 12))
                        Spacer(minLength: 6)
                        Text("vault-wide").font(.system(size: 10)).foregroundColor(Theme.mutedFg)
                    })
            }
            // Un-grayed by P19c's kind-id seam + P19e's retype delta: retype
            // writes value-kind ONLY (schema-on-read re-renders carriers) and
            // hide-on-kind mints a real #id reference.
            Menu {
                ForEach(PropertyActions.retypeKinds, id: \.self) { kind in
                    Button(kind + (kind == spec.property.kind ? " ✓" : "")) {
                        onDone()
                        PropertyActions.retype(model: model, def: spec.property, to: kind)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "textformat").font(.system(size: 10))
                    Text("Change type").font(.system(size: 12))
                    Spacer(minLength: 6)
                    Text("\(spec.property.kind) ▸").font(.system(size: 10))
                        .foregroundColor(Theme.mutedFg)
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 26)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Sets value-kind only — carrier cells are never rewritten (schema-on-read).")
            Divider().padding(.vertical, 2)
            PopRow(selected: false, action: { hideOnThisKind() }) {
                AnyView(
                    HStack(spacing: 8) {
                        Image(systemName: "eye.slash").font(.system(size: 10))
                        Text("Hide on \(entity.kinds.first ?? "this kind")").font(.system(size: 12))
                        Spacer(minLength: 6)
                        Text("per kind").font(.system(size: 10)).foregroundColor(Theme.mutedFg)
                    })
            }
            PopRow(selected: false, action: { toggleHideWhenEmpty() }) {
                AnyView(
                    HStack(spacing: 8) {
                        Image(
                            systemName: spec.property.hidesWhenEmpty
                                ? "checkmark.square" : "square"
                        )
                        .font(.system(size: 10))
                        Text("Hide when empty").font(.system(size: 12))
                        Spacer(minLength: 6)
                        Text("vault-wide").font(.system(size: 10)).foregroundColor(Theme.mutedFg)
                    })
            }
            // Always shown (bp1's row-menu exhibit is on an empty tier row):
            // unset of an absent cell is a harmless no-op, and hiding it made
            // the menu jump depending on fill state (the review's finding).
            Divider().padding(.vertical, 2)
            PopRow(selected: false, action: { removeFromObject() }) {
                AnyView(
                    HStack(spacing: 8) {
                        Image(systemName: "trash").font(.system(size: 10))
                        Text("Remove from this object").font(.system(size: 12))
                        Spacer(minLength: 6)
                        Text("this object").font(.system(size: 10)).opacity(0.7)
                    }
                    .foregroundColor(Theme.destructive))
            }
            PopHint(text: "H or right-click on any row · Obsidian parity is the floor")
        }
        .frame(width: 250)
        .padding(.bottom, 2)
        .onKeyPress(.escape) {
            onDone()
            return .handled
        }
    }

    private func deferredRow(
        icon: String, label: String, detail: String, help: String
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 10))
            Text(label).font(.system(size: 12))
            Spacer(minLength: 6)
            Text(detail).font(.system(size: 10))
        }
        .foregroundColor(Theme.mutedFg.opacity(0.55))
        .padding(.horizontal, 10)
        .frame(minHeight: 26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(help)
    }

    private func hideOnThisKind() {
        onDone()
        guard let kindName = entity.kinds.first,
            let kind = (model.snap?.kinds ?? []).first(where: { $0.name == kindName })
        else { return }
        PropertyActions.hideOnKind(model: model, def: spec.property, kind: kind)
    }

    private func editName() {
        onDone()
        Dialogs.shared.prompt(
            "Rename property",
            message: "One property, vault-wide — every object using it follows.",
            initial: spec.property.name, confirmLabel: "Rename"
        ) { name in
            guard let name = name?.trimmingCharacters(in: .whitespaces).lowercased(),
                !name.isEmpty, name != spec.property.name
            else { return }
            model.set(spec.property.id, property: "name", value: name)
        }
    }

    private func toggleHideWhenEmpty() {
        model.set(
            spec.property.id, property: "hide-when-empty",
            value: spec.property.hidesWhenEmpty ? "false" : "true")
        onDone()
    }

    private func removeFromObject() {
        model.unset(entity.id, property: spec.property.name)
        onDone()
    }
}
