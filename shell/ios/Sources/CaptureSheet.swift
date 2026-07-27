// liv iOS — the Capture sheet (design/ios.md §6): the doorway that asks
// nothing. One field, NO token grammar (a typed "due:" stays literal text);
// chips unlock only AFTER the save. The draft survives every interruption —
// the field clears only inside the confirmed-commit callback. The sheet is
// PERSISTENT (eval §4.2, ClickUp's create-and-start-another as the default):
// a commit clears the field, keeps focus, and drops a tappable toast —
// serial capture is type, return, type, return. Photo lives in
// Camera.swift; the verb here only opens it.

import SwiftUI
import UIKit

// MARK: - verbs / picks (Capture-prefixed by law)

/// Internal on purpose: the desk's new-tab body picks the opening verb.
enum CaptureVerb: String { case idea, task, event }

private enum CapturePick: String, Identifiable {
    case area, tag, project, person, due, type, status
    var id: String { rawValue }

    /// Layer-1 source (liv_distinct_values_at) + the write arity.
    var property: String {
        switch self {
        case .area: return "area"
        case .tag: return "subjects"
        case .project: return "project"
        case .person: return "people"
        case .type: return "type"
        case .due: return "due"
        case .status: return "status"
        }
    }
    /// Multi-valued picks addCell (membership); the rest set (replace).
    var multi: Bool { self == .tag || self == .person }
    var title: String {
        switch self {
        case .area: return "Area"
        case .tag: return "Tag"
        case .project: return "Project"
        case .person: return "Person"
        case .due: return "Due"
        case .type: return "Type"
        case .status: return "Status"
        }
    }
}

/// The six kinds of thing (what-liv-is-for): fixed furniture. The Type
/// picker offers exactly these — photos are born through the camera, so
/// the picker lists five. No create-a-type door anywhere.
let captureFixedKinds = ["note", "task", "event", "person", "link"]

/// A locally tracked applied chip — the snapshot refreshes behind us, but
/// the sheet's chip row must not wait for it.
private struct CaptureApplied: Identifiable {
    let pick: CapturePick
    let display: String
    let dotted: Bool
    var id: String { pick.rawValue + "|" + display }
}

/// One cell the active workspace stamped on the fresh capture (M4). It is
/// ALREADY written — this is the receipt, not a proposal — and one tap on
/// its ✕ takes it back off (`unset` on that property). Liv law: no silent
/// capture-time metadata (P12 §1.4).
private struct CaptureStamp: Identifiable {
    let property: String
    let value: String
    var id: String { property + "|" + value }
}

// MARK: - the sheet

struct CaptureSheet: View {
    let openCamera: () -> Void
    /// Fired exactly once per successfully created entity — every serial
    /// commit fires it again, and the desk routes each to the SAME tab
    /// (latest-wins; the §6 tab-hygiene rule, eval §3(b)1).
    let onCreated: ((UInt64) -> Void)?

    init(
        initialVerb: CaptureVerb = .idea,
        openCamera: @escaping () -> Void,
        onCreated: ((UInt64) -> Void)? = nil
    ) {
        self.openCamera = openCamera
        self.onCreated = onCreated
        _verb = State(initialValue: initialVerb)
    }

    @EnvironmentObject var model: BoxModel
    @EnvironmentObject var workspaces: WorkspaceModel
    @Environment(\.dismiss) private var dismiss

    /// The draft survives failure AND process death; cleared ONLY on
    /// confirmed commit.
    @AppStorage("capture.draft.v1") private var draft = ""
    @State private var verb: CaptureVerb
    @State private var name = ""  // task / event share the one name field
    @State private var eventDay: Int64 = Civil.todayDay()
    @State private var eventTimed = false
    @State private var eventHHMM: Int64 = 900
    @State private var savedId: UInt64? = nil
    @State private var savedTitle = ""
    @State private var savedText = ""  // Undo restores the field verbatim
    @State private var savedVerb: CaptureVerb = .idea  // Undo lands on ITS editor
    @State private var applied: [CaptureApplied] = []
    /// What the active workspace stamped on the last commit — shown as
    /// filled, already-applied, one-tap-removable chips.
    @State private var stamped: [CaptureStamp] = []
    @State private var pick: CapturePick? = nil
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            verbRow
            editor
            if savedId != nil {
                toast
                chipStrip
            }
            Spacer(minLength: 0)
            if savedId != nil {
                doneRow
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LivTheme.canvas)
        // One detent, the final one. Two detents auto-expanded when the
        // keyboard rose, and the animated re-layout stole first responder
        // and moved the verb row mid-tap (eval §5.1/§5.8).
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(item: $pick) { p in
            pickerSheet(p)
        }
        .onAppear {
            // First responder synchronously at presentation — a delayed
            // detent-settle focus is a window where typed text goes nowhere.
            focused = true
        }
    }

    // MARK: verb row — Idea / Task / Event / Photo

    private var verbRow: some View {
        HStack(spacing: 2) {
            segButton("Idea", "lightbulb", .idea)
            segButton("Task", "checkmark.circle", .task)
            segButton("Event", "calendar", .event)
            Button {
                openCamera()
            } label: {
                segLabel("Photo", "camera", on: false)
            }
            .buttonStyle(.plain)
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: LivTheme.radius).fill(LivTheme.panel2))
    }

    private func segButton(_ label: String, _ icon: String, _ v: CaptureVerb) -> some View {
        Button {
            select(v)
        } label: {
            segLabel(label, icon, on: verb == v)
        }
        .buttonStyle(.plain)
    }

    private func segLabel(_ label: String, _ icon: String, on: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 11))
            Text(label).font(.system(size: 12, weight: on ? .semibold : .regular))
        }
        .foregroundStyle(on ? LivTheme.text : LivTheme.text3)
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: LivTheme.radius - 2)
                .fill(on ? LivTheme.surface : .clear)
        )
        .contentShape(Rectangle())
    }

    /// Switching verbs keeps the toast — the last capture is committed and
    /// the chips still aim at it. Only the editor (and focus) moves.
    private func select(_ v: CaptureVerb) {
        verb = v
        focused = true
    }

    // MARK: the editors

    @ViewBuilder private var editor: some View {
        switch verb {
        case .idea: ideaEditor
        case .task: taskEditor
        case .event: eventEditor
        }
    }

    private var ideaEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("What's on your mind?", text: $draft, axis: .vertical)
                .font(.system(size: 15))
                .foregroundStyle(LivTheme.text)
                .lineLimit(4...10)
                .textInputAutocapitalization(.never)  // typed text stays literal
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(save)
            saveRow
        }
        .modifier(CaptureCard())
    }

    private var taskEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Task name", text: $name)
                .font(.system(size: 15))
                .foregroundStyle(LivTheme.text)
                .textInputAutocapitalization(.never)  // typed text stays literal
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(save)
            saveRow
        }
        .modifier(CaptureCard())
    }

    private var eventEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Event name", text: $name)
                .font(.system(size: 15))
                .foregroundStyle(LivTheme.text)
                .textInputAutocapitalization(.never)  // typed text stays literal
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(save)
            HStack(spacing: 10) {
                DatePicker("", selection: eventDateBinding, displayedComponents: .date)
                    .labelsHidden()
                    .tint(LivTheme.accent)
                if eventTimed {
                    Picker("", selection: $eventHHMM) {
                        ForEach(0..<24, id: \.self) { h in
                            Text(String(format: "%02d:00", h))
                                .monospacedDigit()
                                .tag(Int64(h * 100))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(LivTheme.accent)
                }
                Spacer()
                Toggle(isOn: $eventTimed) {
                    Text("Timed").font(.system(size: 12)).foregroundStyle(LivTheme.text2)
                }
                .toggleStyle(.switch)
                .tint(LivTheme.accent)
                .fixedSize()
            }
            saveRow
        }
        .modifier(CaptureCard())
    }

    private var saveRow: some View {
        HStack {
            Spacer()
            Button(action: save) {
                Text("Save")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LivTheme.onAccent)
                    .padding(.horizontal, 16)
                    .frame(height: 30)
                    .background(Capsule().fill(LivTheme.accent))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(trimmedInput.isEmpty)
            .opacity(trimmedInput.isEmpty ? 0.45 : 1)
        }
    }

    // MARK: save — clear ONLY inside the success callback

    private var trimmedInput: String {
        (verb == .idea ? draft : name).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        let text = trimmedInput
        guard !text.isEmpty else { return }
        // The return key resigns first responder; reassert NOW so serial
        // capture never drops the keyboard (commit reasserts again async).
        focused = true
        switch verb {
        case .idea:
            let full = draft
            model.capture(full) { id in
                guard id != 0 else { return captureFailed() }
                savedText = full
                draft = ""
                commit(id, title: captureFirstLine(full))
            }
        case .task:
            model.createTask { id in
                guard id != 0 else { return captureFailed() }
                model.set(id, "name", text)
                savedText = name
                name = ""
                commit(id, title: text)
            }
        case .event:
            let stamp = Civil.stamp(day: eventDay, hhmm: eventTimed ? eventHHMM : 0)
            model.createEvent(dueCivil: stamp, dateOnly: !eventTimed) { id in
                guard id != 0 else { return captureFailed() }
                model.set(id, "name", text)
                savedText = name
                name = ""
                commit(id, title: text)
            }
        }
    }

    /// The serial-capture pivot: every success callback lands here with the
    /// field already cleared — keep focus (zero taps to the next thought),
    /// raise the toast, hand the entity to the desk's one tab.
    private func commit(_ id: UInt64, title: String) {
        savedId = id
        savedTitle = title
        savedVerb = verb
        applied = []
        focused = true
        onCreated?(id)
        stamp(id)
    }

    /// The workspace's stamp (M4): the active workspace's plain `key:value`
    /// terms, written as cells on what was just created. Never silent —
    /// each lands as a filled chip in the strip below, removable in one tap.
    /// No active workspace, or a query with no equality term, changes
    /// nothing at all.
    private func stamp(_ id: UInt64) {
        stamped = workspaces.stamp(id, in: model).map {
            CaptureStamp(property: $0.property, value: $0.value)
        }
    }

    /// One tap takes a stamp back off — `unset` removes every cell of that
    /// property, the exact inverse of the `set` that put it there.
    private func unstamp(_ chip: CaptureStamp) {
        guard let id = savedId else { return }
        if chip.property == "type" {
            model.unset(id, "type")
        } else {
            model.unset(id, chip.property)
        }
        stamped.removeAll { $0.id == chip.id }
    }

    private func captureFailed() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    // MARK: the toast — the confirmation, one compact tappable row

    /// Replaces the old full saved-state card (eval §4.2). Tap the text =
    /// dismiss; the entity is already this tab's content via onCreated.
    private var toast: some View {
        HStack(spacing: 8) {
            Button {
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(LivTheme.accent)
                    Text(savedTitle)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(LivTheme.text)
                        .lineLimit(1)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer(minLength: 6)
            Button(action: undoSave) {
                Text("Undo")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LivTheme.accent)
                    .padding(.horizontal, 6)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: LivTheme.radius).fill(LivTheme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: LivTheme.radius)
                .strokeBorder(LivTheme.border, lineWidth: 0.5)
        )
    }

    /// Undo reverses the LAST commit and returns to composing it — but the
    /// text restores only into an EMPTY field: a next thought already being
    /// typed never loses to an undo.
    private func undoSave() {
        model.undo()
        verb = savedVerb
        if savedVerb == .idea {
            if draft.isEmpty { draft = savedText }
        } else if name.isEmpty {
            name = savedText
        }
        savedId = nil
        applied = []
        stamped = []
        focused = true
    }

    /// The chips-after-save law, one line shorter: a compact strip under
    /// the toast, writing to the LAST captured entity. The workspace's
    /// stamps lead — they are already written, so they read as FILLED
    /// chips with a ✕, not as offers.
    private var chipStrip: some View {
        CaptureFlow(spacing: 6) {
            ForEach(stamped) { s in
                CaptureStampChip(label: "\(s.property): \(s.value)") { unstamp(s) }
            }
            ForEach(applied) { a in
                Button {
                    pick = a.pick  // re-open to change / add more
                } label: {
                    ValueChip(a.display, dotted: a.dotted, big: true)
                }
                .buttonStyle(.plain)
            }
            // Fixed furniture leads: Area is the one filing question.
            if !isApplied(.area), !isStamped("area") {
                AddChip(CapturePick.area.title, big: true) { pick = .area }
            }
            if savedVerb == .task, !isApplied(.status) {
                AddChip(CapturePick.status.title, big: true) { pick = .status }
            }
            AddChip(CapturePick.tag.title, big: true) { pick = .tag }
            if !isApplied(.project) {
                AddChip(CapturePick.project.title, big: true) { pick = .project }
            }
            AddChip(CapturePick.person.title, big: true) { pick = .person }
            if !isApplied(.due) {
                AddChip(CapturePick.due.title, big: true) { pick = .due }
            }
            if !isApplied(.type) {
                AddChip(CapturePick.type.title, big: true) { pick = .type }
            }
        }
    }

    private func isApplied(_ p: CapturePick) -> Bool {
        applied.contains { $0.pick == p }
    }

    /// The workspace already stamped this property — the strip shows its
    /// filled chip, so the hollow offer would be a duplicate door.
    private func isStamped(_ property: String) -> Bool {
        stamped.contains { $0.property == property }
    }

    // MARK: apply — set / addCell / setType / setSpan against the saved id

    /// Chip honesty: the chip is recorded ONLY in the verb's success
    /// callback. A refused write buzzes and leaves no chip — the box is
    /// the truth, the strip its receipt (the fresh-box silent-chip bug).
    private func apply(_ p: CapturePick, value: String) {
        guard let id = savedId else { return }
        let done: (Bool) -> Void = { ok in
            guard ok else { return captureFailed() }
            record(p, display: value, dotted: true)
        }
        switch p {
        case .tag, .person:
            model.addCell(id, p.property, value, done: done)
        case .area, .project, .status:
            model.set(id, p.property, value, done: done)
        case .type:
            model.setType(id, value, done: done)
        case .due:
            return  // dates go through applyDue
        }
    }

    private func applyDue(day: Int64) {
        guard let id = savedId else { return }
        model.setSpan(
            id, "due", start: Civil.stamp(day: day, hhmm: 0), end: 0, dateOnly: true
        ) { ok in
            guard ok else { return captureFailed() }
            record(.due, display: "Due \(captureDayName(day))", dotted: false)
        }
    }

    private func record(_ p: CapturePick, display: String, dotted: Bool) {
        if !p.multi { applied.removeAll { $0.pick == p } }
        let chip = CaptureApplied(pick: p, display: display, dotted: dotted)
        guard !applied.contains(where: { $0.id == chip.id }) else { return }
        applied.append(chip)
    }

    // MARK: Done — dismiss; the desk tab already shows the last capture

    private var doneRow: some View {
        Button {
            dismiss()
        } label: {
            Text("Done")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LivTheme.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(RoundedRectangle(cornerRadius: LivTheme.radius).fill(LivTheme.accent))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: the picker sheets

    @ViewBuilder private func pickerSheet(_ p: CapturePick) -> some View {
        switch p {
        case .due:
            CaptureDuePicker { day in applyDue(day: day) }
        case .status:
            CaptureStatusPicker(model: model) { v in apply(.status, value: v) }
        case .area:
            CaptureAreaPicker(model: model) { v in apply(.area, value: v) }
        case .type:
            CaptureTypePicker { v in apply(.type, value: v) }
        default:
            CaptureValuePicker(pick: p, model: model) { v in apply(p, value: v) }
        }
    }

    // MARK: event date plumbing

    private var eventDateBinding: Binding<Date> {
        Binding(
            get: { CaptureCivil.date(ofDay: eventDay) },
            set: { eventDay = CaptureCivil.day(of: $0) }
        )
    }
}

// MARK: - the workspace stamp chip (M4)

/// A cell the workspace ALREADY wrote: filled accent body (not the hollow
/// AddChip's offer, not the neutral ValueChip's report), with a ✕ that
/// removes it in one tap. The ✕ carries a 24pt hit target inside a 24pt
/// chip — the whole trailing end is the button.
private struct CaptureStampChip: View {
    let label: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(LivTheme.accent)
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(LivTheme.accent)
                    .frame(width: 22, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove \(label)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 0)
        .frame(height: 24)
        .background(Capsule().fill(LivTheme.accentSoft))
        .overlay(Capsule().strokeBorder(LivTheme.accent.opacity(0.45), lineWidth: 0.5))
    }
}

// MARK: - the editor card chrome

private struct CaptureCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(RoundedRectangle(cornerRadius: LivTheme.radius).fill(LivTheme.surface))
            .overlay(
                RoundedRectangle(cornerRadius: LivTheme.radius)
                    .strokeBorder(LivTheme.border, lineWidth: 0.5)
            )
    }
}

// MARK: - civil helpers the kit's Civil does not expose

private enum CaptureCivil {
    private static let gregorian = Calendar(identifier: .gregorian)

    /// Noon anchor dodges the DST-skipped-midnight edge.
    static func date(ofDay day: Int64) -> Date {
        var c = DateComponents()
        c.year = Int(day / 10_000)
        c.month = Int((day / 100) % 100)
        c.day = Int(day % 100)
        c.hour = 12
        return gregorian.date(from: c) ?? Date()
    }

    static func day(of date: Date) -> Int64 {
        let c = gregorian.dateComponents([.year, .month, .day], from: date)
        return Int64((c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0))
    }

    /// The coming Saturday, 1–7 days out (today-is-Saturday rolls a week).
    static func nextSaturday() -> Int64 {
        let today = Civil.todayDay()
        for n in 1...7 {
            let d = Civil.addDays(today, n)
            if gregorian.component(.weekday, from: date(ofDay: d)) == 7 { return d }
        }
        return Civil.addDays(today, 6)
    }
}

private func captureFirstLine(_ s: String) -> String {
    let line = s.split(separator: "\n", omittingEmptySubsequences: true).first
    return (line.map(String.init) ?? s).trimmingCharacters(in: .whitespaces)
}

private func captureDayName(_ day: Int64) -> String {
    let today = Civil.todayDay()
    if day == today { return "Today" }
    if day == Civil.addDays(today, 1) { return "Tomorrow" }
    return Civil.dayLabel(day)
}

// MARK: - a wrapping chip row (Layout, iOS 16+)

private struct CaptureFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > width {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: width.isFinite ? width : max(x - spacing, 0), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + sz.width > bounds.maxX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

// MARK: - the three-layer value picker (layer 2 — seed vocab — none in M1)

private struct CaptureValuePicker: View {
    let pick: CapturePick
    let model: BoxModel
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var values: [String] = []  // count-desc, as the seam sent them
    @FocusState private var focused: Bool

    private var trimmed: String {
        typed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var filtered: [String] {
        trimmed.isEmpty
            ? values
            : values.filter { $0.localizedCaseInsensitiveContains(trimmed) }
    }
    private var creatable: Bool {
        !trimmed.isEmpty
            && !values.contains { $0.compare(trimmed, options: .caseInsensitive) == .orderedSame }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(pick.title.uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(LivTheme.text3)
            TextField("Search or create…", text: $typed)
                .font(.system(size: 14))
                .foregroundStyle(LivTheme.text)
                .focused($focused)
                .submitLabel(.done)
                // Values are verbatim too — "errands" must not become
                // "Errands" on its way into a cell.
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .onSubmit { if creatable { choose(trimmed) } }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: LivTheme.radiusSm).fill(LivTheme.panel))
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered, id: \.self) { v in
                        row(dot: Hue.dot(v), label: v) { choose(v) }
                    }
                    // Create-new stays — real life varies here — but LAST:
                    // the furniture leads, the door does not (§10).
                    if creatable {
                        row(icon: "plus", tint: LivTheme.accent, label: "Create \u{201C}\(trimmed)\u{201D}") {
                            choose(trimmed)
                        }
                    }
                    if values.isEmpty && trimmed.isEmpty {
                        EmptyHint("No values yet — type to create one.")
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LivTheme.canvas)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            // Once per open, never per keystroke.
            model.distinctValues(property: pick.property) { values = $0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focused = true }
        }
    }

    private func choose(_ v: String) {
        onPick(v)
        dismiss()
    }

    private func row(
        icon: String? = nil, tint: Color = LivTheme.text2, dot: Color? = nil,
        label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                }
                if let dot {
                    Circle().fill(dot).frame(width: 6, height: 6)
                }
                Text(label)
                    .font(.system(size: 13.5))
                    .foregroundStyle(icon == nil ? LivTheme.text : tint)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
        }
    }
}

// MARK: - the area picker: the six areas of life, NO create-new (§10)

/// The one filing question — "which part of life?" — answered from fixed
/// furniture. Rows are the canonical six unioned with whatever the box
/// already holds (live select options off the snapshot, plus distinct
/// values for a legacy text `area`); there is deliberately no create row
/// and no type-to-create field.
struct CaptureAreaPicker: View {
    let model: BoxModel
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var extras: [String] = []

    /// Canonical six first, then anything extra the box carries.
    private var rows: [String] {
        var out = Furnish.areaNames
        for v in extras
        where !out.contains(where: { $0.compare(v, options: .caseInsensitive) == .orderedSame }) {
            out.append(v)
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AREA")
                .font(.system(size: 9.5, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(LivTheme.text3)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows, id: \.self) { v in
                        areaRow(v)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LivTheme.canvas)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            // Live options off the snapshot the model already holds…
            let held = (model.snap?.properties ?? [])
                .first { ($0.name ?? "").compare("area", options: .caseInsensitive) == .orderedSame }?
                .options?.filter { $0.hidden != true }.compactMap { $0.name } ?? []
            extras = held
            // …unioned with distinct live values (a legacy text `area`).
            model.distinctValues(property: "area") { live in
                var merged = held
                for v in live
                where !merged.contains(where: { $0.compare(v, options: .caseInsensitive) == .orderedSame }) {
                    merged.append(v)
                }
                extras = merged
            }
        }
    }

    private func areaRow(_ v: String) -> some View {
        Button {
            onPick(v)
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Circle().fill(Hue.dot(v)).frame(width: 6, height: 6)
                Text(v)
                    .font(.system(size: 13.5))
                    .foregroundStyle(LivTheme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
        }
    }
}

// MARK: - the type picker: the fixed kinds, NO create-new (§10)

/// Kinds are ours and they don't grow: note · task · event · person ·
/// link (photos are born through the camera). The old picker offered a
/// create-a-type row whose write the core refused anyway.
struct CaptureTypePicker: View {
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TYPE")
                .font(.system(size: 9.5, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(LivTheme.text3)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(captureFixedKinds, id: \.self) { kind in
                        typeRow(kind)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LivTheme.canvas)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func typeRow(_ kind: String) -> some View {
        Button {
            onPick(kind)
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Circle().fill(Hue.dot(kind)).frame(width: 6, height: 6)
                Text(kind)
                    .font(.system(size: 13.5))
                    .foregroundStyle(LivTheme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
        }
    }
}

// MARK: - the due picker: shortcuts, then a real date

private struct CaptureDuePicker: View {
    let onPick: (Int64) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DUE")
                .font(.system(size: 9.5, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(LivTheme.text3)
            VStack(spacing: 0) {
                shortcut("Today", day: Civil.todayDay())
                shortcut("Tomorrow", day: Civil.addDays(Civil.todayDay(), 1))
                // On a Friday, Weekend IS tomorrow — one option, not two.
                if CaptureCivil.nextSaturday() != Civil.addDays(Civil.todayDay(), 1) {
                    shortcut("Weekend", day: CaptureCivil.nextSaturday())
                }
            }
            HStack(spacing: 10) {
                DatePicker("", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                    .tint(LivTheme.accent)
                Spacer()
                Button {
                    choose(CaptureCivil.day(of: date))
                } label: {
                    Text("Set date")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(LivTheme.onAccent)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(Capsule().fill(LivTheme.accent))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LivTheme.canvas)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func choose(_ day: Int64) {
        onPick(day)
        dismiss()
    }

    private func shortcut(_ label: String, day: Int64) -> some View {
        Button {
            choose(day)
        } label: {
            HStack {
                Text(label)
                    .font(.system(size: 13.5))
                    .foregroundStyle(LivTheme.text)
                Spacer()
                Text(Civil.dayLabel(day))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(LivTheme.text3)
            }
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
        }
    }
}

// MARK: - the status picker: the task vocabulary, board order

private struct CaptureStatusPicker: View {
    let model: BoxModel
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var options: [StatusOption] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("STATUS")
                .font(.system(size: 9.5, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(LivTheme.text3)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(options) { o in
                        if let name = o.name {
                            row(o, name: name)
                        }
                    }
                    if options.isEmpty {
                        EmptyHint("No status vocabulary yet.")
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LivTheme.canvas)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            model.statusOptions(kind: "task") { options = $0 }
        }
    }

    private func row(_ o: StatusOption, name: String) -> some View {
        Button {
            onPick(name)
            dismiss()
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(captureStatusColor(o))
                    .frame(width: 10, height: 10)
                Text(name)
                    .font(.system(size: 13.5))
                    .foregroundStyle(LivTheme.text)
                Spacer()
                if o.completes == true {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(LivTheme.text3)
                }
            }
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
        }
    }
}

/// Status hue from the option entity (a degree on the wire); no hue =
/// neutral.
private func captureStatusColor(_ o: StatusOption) -> Color {
    guard let h = o.hue else { return LivTheme.muted }
    let deg = Double(((h % 360) + 360) % 360)
    return Color(hue: deg / 360, saturation: 0.55, brightness: 0.75)
}

// MARK: - the persistent Details chip row (the saved entity's body)

/// design/ios.md §6: the +Tag +Project +Person +Due +Type row lives on the
/// saved entity body itself, not only on the capture sheet's transient
/// confirmation (eval §5.6). Values come off the live row — the box is the
/// truth — and every write rides the same verbs the sheet uses.
struct EntityChipRow: View {
    let id: UInt64

    @EnvironmentObject var model: BoxModel
    @State private var pick: CapturePick? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Details")
            CaptureFlow(spacing: 6) {
                ForEach(valueChips) { chip in
                    Button {
                        pick = chip.pick  // re-open to change / add more
                    } label: {
                        ValueChip(chip.display, dotted: chip.dotted, big: true)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(addChips) { p in
                    AddChip(p.title, big: true) { pick = p }
                }
            }
        }
        .sheet(item: $pick) { p in
            pickerSheet(p)
        }
    }

    private var row: EntityRow? { model.entity(id) }

    private var valueChips: [CaptureApplied] {
        guard let row else { return [] }
        var out: [CaptureApplied] = []
        if (row.kinds ?? []).contains("task"), let status = row.status, !status.isEmpty {
            out.append(CaptureApplied(pick: .status, display: status, dotted: true))
        }
        let picks: [(CapturePick, String)] = [
            (.area, "area"), (.tag, "subjects"), (.project, "project"), (.person, "people"),
        ]
        for (pick, property) in picks {
            for cell in row.cells ?? [] where cell.property == property {
                guard let v = cell.value, !v.isEmpty else { continue }
                let chip = CaptureApplied(pick: pick, display: v, dotted: true)
                if !out.contains(where: { $0.id == chip.id }) { out.append(chip) }
            }
        }
        if let due = row.due, due > 0 {
            out.append(
                CaptureApplied(
                    pick: .due, display: "Due \(captureDayName(Civil.day(of: due)))",
                    dotted: false))
        }
        return out
    }

    /// Mirrors the capture sheet's chipSection: Area leads (the one filing
    /// question); Status only for tasks; Tag and Person always
    /// (multi-valued); the rest only while absent.
    private var addChips: [CapturePick] {
        guard let row else { return [] }
        let kinds = row.kinds ?? []
        var out: [CapturePick] = []
        if !hasCell("area") { out.append(.area) }
        if kinds.contains("task"), (row.status ?? "").isEmpty { out.append(.status) }
        out.append(.tag)
        if !hasCell("project") { out.append(.project) }
        out.append(.person)
        if (row.due ?? 0) == 0 { out.append(.due) }
        if kinds.isEmpty { out.append(.type) }
        return out
    }

    private func hasCell(_ property: String) -> Bool {
        (row?.cells ?? []).contains { $0.property == property && !($0.value ?? "").isEmpty }
    }

    @ViewBuilder private func pickerSheet(_ p: CapturePick) -> some View {
        switch p {
        case .due:
            CaptureDuePicker { day in
                model.setSpan(
                    id, "due", start: Civil.stamp(day: day, hhmm: 0), end: 0,
                    dateOnly: true, done: buzzUnless)
            }
        case .status:
            CaptureStatusPicker(model: model) { v in
                model.set(id, "status", v, done: buzzUnless)
            }
        case .area:
            CaptureAreaPicker(model: model) { v in
                model.set(id, "area", v, done: buzzUnless)
            }
        case .type:
            CaptureTypePicker { v in model.setType(id, v, done: buzzUnless) }
        default:
            CaptureValuePicker(pick: p, model: model) { v in
                switch p {
                case .tag, .person: model.addCell(id, p.property, v, done: buzzUnless)
                case .project: model.set(id, p.property, v, done: buzzUnless)
                default: break
                }
            }
        }
    }

    /// The chips here render off the live row — the box is the truth — so
    /// honesty needs only the failure signal: a refused write buzzes.
    private func buzzUnless(_ ok: Bool) {
        if !ok { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    }
}
