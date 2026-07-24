// liv iOS — the Capture sheet (design/ios.md §6): the doorway that asks
// nothing. One field, NO token grammar (a typed "due:" stays literal text);
// chips unlock only AFTER the save. The draft survives every interruption —
// the field clears only inside the confirmed-commit callback. "Another" is
// serial capture. Photo lives in Camera.swift; the verb here only opens it.

import SwiftUI
import UIKit

// MARK: - verbs / picks (Capture-prefixed by law)

/// Internal on purpose: the desk's new-tab body picks the opening verb.
enum CaptureVerb: String { case idea, task, event }

private enum CapturePick: String, Identifiable {
    case tag, project, person, due, type, status
    var id: String { rawValue }

    /// Layer-1 source (liv_distinct_values_at) + the write arity.
    var property: String {
        switch self {
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
        case .tag: return "Tag"
        case .project: return "Project"
        case .person: return "Person"
        case .due: return "Due"
        case .type: return "Type"
        case .status: return "Status"
        }
    }
}

/// A locally tracked applied chip — the snapshot refreshes behind us, but
/// the sheet's chip row must not wait for it.
private struct CaptureApplied: Identifiable {
    let pick: CapturePick
    let display: String
    let dotted: Bool
    var id: String { pick.rawValue + "|" + display }
}

// MARK: - the sheet

struct CaptureSheet: View {
    let openCamera: () -> Void
    /// Fired exactly once per successfully created entity, inside the same
    /// success callback that flips the sheet to its saved state ("Another"
    /// fires it again for the NEXT entity — one call per commit).
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
    @State private var applied: [CaptureApplied] = []
    @State private var pick: CapturePick? = nil
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            verbRow
            if savedId != nil {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        committedCard
                        chipSection
                    }
                }
                anotherDoneRow
            } else {
                editor
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LivTheme.canvas)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(item: $pick) { p in
            pickerSheet(p)
        }
        .onAppear {
            // Sheets steal first responder; focus after the slide settles.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focused = true }
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
            segLabel(label, icon, on: verb == v && savedId == nil)
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

    /// Switching verbs abandons a saved-state chip row (the entity is
    /// committed; chips were optional) — never the idea draft.
    private func select(_ v: CaptureVerb) {
        if savedId != nil {
            savedId = nil
            applied = []
            name = ""
        }
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

    /// The one flip to saved state — every success callback lands here, so
    /// onCreated fires exactly once per committed entity.
    private func commit(_ id: UInt64, title: String) {
        savedId = id
        savedTitle = title
        applied = []
        focused = false
        onCreated?(id)
    }

    private func captureFailed() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    // MARK: saved state — the committed card + the unlocked chips

    private var committedCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(LivTheme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(savedTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LivTheme.text)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Text("Captured — no questions asked ·")
                        .font(.system(size: 11))
                        .foregroundStyle(LivTheme.text3)
                    Button(action: undoSave) {
                        Text("Undo")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(LivTheme.accent)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: LivTheme.radius).fill(LivTheme.surface))
        .overlay(
            RoundedRectangle(cornerRadius: LivTheme.radius)
                .strokeBorder(LivTheme.border, lineWidth: 0.5)
        )
    }

    private func undoSave() {
        model.undo()
        if verb == .idea { draft = savedText } else { name = savedText }
        savedId = nil
        applied = []
        focused = true
    }

    private var chipSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Details")
            CaptureFlow(spacing: 6) {
                ForEach(applied) { a in
                    Button {
                        pick = a.pick  // re-open to change / add more
                    } label: {
                        ValueChip(a.display, dotted: a.dotted, big: true)
                    }
                    .buttonStyle(.plain)
                }
                if verb == .task, !isApplied(.status) {
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
    }

    private func isApplied(_ p: CapturePick) -> Bool {
        applied.contains { $0.pick == p }
    }

    // MARK: apply — set / addCell / setType / setSpan against the saved id

    private func apply(_ p: CapturePick, value: String) {
        guard let id = savedId else { return }
        switch p {
        case .tag, .person:
            model.addCell(id, p.property, value)
        case .project, .status:
            model.set(id, p.property, value)
        case .type:
            model.setType(id, value)
        case .due:
            return  // dates go through applyDue
        }
        record(p, display: value, dotted: true)
    }

    private func applyDue(day: Int64) {
        guard let id = savedId else { return }
        model.setSpan(id, "due", start: Civil.stamp(day: day, hhmm: 0), end: 0, dateOnly: true)
        record(.due, display: "Due \(captureDayName(day))", dotted: false)
    }

    private func record(_ p: CapturePick, display: String, dotted: Bool) {
        if !p.multi { applied.removeAll { $0.pick == p } }
        let chip = CaptureApplied(pick: p, display: display, dotted: dotted)
        guard !applied.contains(where: { $0.id == chip.id }) else { return }
        applied.append(chip)
    }

    // MARK: Another / Done

    private var anotherDoneRow: some View {
        HStack(spacing: 10) {
            Button {
                another()
            } label: {
                Text("Another")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LivTheme.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: LivTheme.radius)
                            .strokeBorder(LivTheme.accent.opacity(0.5), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
    }

    /// Serial capture: back to a fresh idea state, sheet stays up.
    private func another() {
        verb = .idea
        savedId = nil
        applied = []
        name = ""
        focused = true
    }

    // MARK: the picker sheets

    @ViewBuilder private func pickerSheet(_ p: CapturePick) -> some View {
        switch p {
        case .due:
            CaptureDuePicker { day in applyDue(day: day) }
        case .status:
            CaptureStatusPicker(model: model) { v in apply(.status, value: v) }
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
                .onSubmit { if creatable { choose(trimmed) } }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: LivTheme.radiusSm).fill(LivTheme.panel))
            ScrollView {
                LazyVStack(spacing: 0) {
                    if creatable {
                        row(icon: "plus", tint: LivTheme.accent, label: "Create \u{201C}\(trimmed)\u{201D}") {
                            choose(trimmed)
                        }
                    }
                    ForEach(filtered, id: \.self) { v in
                        row(dot: Hue.dot(v), label: v) { choose(v) }
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
                shortcut("Weekend", day: CaptureCivil.nextSaturday())
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
