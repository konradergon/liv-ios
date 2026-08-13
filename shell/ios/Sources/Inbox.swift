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
    @State private var confirmReject: ProposalRow?
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
        (box.snap?.inbox ?? []).filter { ($0.commands?.first?.kind ?? "") == "add" }
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

    var body: some View {
        let scraps = self.scraps
        let groups = proposalGroups

        List {
            Group {
                HStack(spacing: 8) {
                    SectionLabel("Inbox")
                    // The Inbox ignores the lens on purpose. A chip in
                    // the app's own language says so; a grey sentence
                    // under the header did not (owner, 2026-08-06).
                    if workspaces.lensOn { ValueChip("all workspaces") }
                    Spacer()
                }
                .padding(.top, 8)

                if scraps.isEmpty && groups.isEmpty && !assistOff {
                    EmptyHint("Inbox zero.")
                        .padding(.top, 32)
                }

                if !scraps.isEmpty {
                    SectionLabel("Route", trailing: "\(scraps.count)")
                        .padding(.top, 14).padding(.bottom, 2)
                    ForEach(scraps) { row in
                        routeCard(row)
                    }
                }

                suggestedSection(groups)
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
        .contentMargins(.bottom, 16, for: .scrollContent)
        .background(LivTheme.canvas)
        .sheet(item: $duePick) { pick in
            DetailDueSheet(model: box, id: pick.entity, property: "due")
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $settingsShown) { SettingsSheet() }
        .confirmationDialog(
            "The clerk never asks this again.",
            isPresented: Binding(
                get: { confirmReject != nil },
                set: { if !$0 { confirmReject = nil } }),
            titleVisibility: .visible
        ) {
            Button("Dismiss forever", role: .destructive) {
                if let p = confirmReject { box.reject(p) }
                confirmReject = nil
            }
        }
        .overlay(alignment: .top) {
            if let text = chipText { chip(text) }
        }
        .onAppear {
            box.refresh()
            box.statusOptions(kind: "task") { taskOptions = $0 }
        }
    }

    // MARK: route — a card per unrouted capture

    private func routeCard(_ row: EntityRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // What is waiting: a capture, in the capture colour.
                IconChip(
                    glyph: LivKind.glyph(of: row), color: LivKind.color(of: row),
                    size: 22
                )
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
                Text(displayTitle(row))
                    .font(.system(size: LivType.body, weight: .medium))
                    .foregroundStyle(LivTheme.text)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(stamp(row))
                    .font(.system(size: LivType.caption).monospacedDigit())
                    .foregroundStyle(LivTheme.text3)
            }
            HStack(spacing: 7) {
                // The verbs stay NEUTRAL — colour marks what a thing is,
                // never what a button would make (owner, 2026-08-12). They
                // do share the one glyph table, so a routed note wears the
                // same drawing the button promised.
                routeVerb("Task", .task) { routeTask(row) }
                routeVerb("Event", .event) { routeEvent(row) }
                routeVerb("Note", .note) { route(row, to: "note", as: "Note") }
                routeVerb("Link", .link) { route(row, to: "link", as: "Link") }
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { desk.open(row.id) }
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                box.trash(row.id)  // soft, undoable
            } label: {
                Label("Trash", systemImage: "trash")
            }
            .tint(LivTheme.red)
        }
    }

    /// Full-width 32pt verbs — the old 24pt capsules four-abreast were a
    /// mis-tap farm (phase-5 recon).
    private func routeVerb(
        _ label: String, _ glyph: LivGlyph, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                LivIcon(glyph: glyph, color: LivTheme.text2, size: 15)
                Text(label).font(.system(size: LivType.body, weight: .medium))
            }
            .foregroundStyle(LivTheme.text2)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 9).fill(LivTheme.panel2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(LivTheme.border, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.borderless)
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
                .padding(.top, 14).padding(.bottom, 2)
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
            .frame(minHeight: 40)
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
        HStack(spacing: 7) {
            Text("✦")
                .font(.system(size: LivType.label))
                .foregroundStyle(LivTheme.amber)
            Text(group.author.uppercased())
                .font(.system(size: LivType.label, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(LivTheme.text3)
            Text("\(group.rows.count)")
                .font(.system(size: LivType.label).monospacedDigit())
                .foregroundStyle(LivTheme.muted)
            Spacer()
            if group.rows.count > 1 {
                Button {
                    box.acceptGroup(group.rows.compactMap(\.fingerprint)) { ok in
                        if !ok { refused() }
                    }
                } label: {
                    Text("Accept all")
                        .font(.system(size: LivType.label, weight: .semibold))
                        .foregroundStyle(LivTheme.accent)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(Capsule().fill(LivTheme.panel2))
                        .overlay(
                            Capsule().strokeBorder(LivTheme.border, lineWidth: 0.5)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.top, 14).padding(.bottom, 2)
    }

    private func suggestionRow(_ p: ProposalRow) -> some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    ForEach(
                        Array((p.commands ?? []).prefix(3).enumerated()),
                        id: \.offset
                    ) { _, command in
                        diffChip(command)
                    }
                }
                if let reason = p.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.system(size: LivType.label))
                        .foregroundStyle(LivTheme.text3)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            Button {
                confirmReject = p
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: LivType.body, weight: .semibold))
                    .foregroundStyle(LivTheme.text3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            Button {
                box.accept(p)
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: LivType.body, weight: .semibold))
                    .foregroundStyle(LivTheme.accent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
        .frame(minHeight: LivRow.tall)
        .contentShape(Rectangle())
        .onTapGesture {
            if let entity = p.entity { desk.open(entity) }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
        }
    }

    @ViewBuilder private func diffChip(_ command: ProposalCommandRow) -> some View {
        let sign = (command.kind == "remove" || command.kind == "trash") ? "−" : "+"
        let label = [command.property, command.value]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        if !label.isEmpty {
            ValueChip("\(sign) \(label)")
        } else if let kind = command.kind, !kind.isEmpty {
            ValueChip("\(sign) \(kind)")
        }
    }

    // MARK: the acknowledgment chip

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
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
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
