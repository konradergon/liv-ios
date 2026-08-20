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

/// Route or Tidy — the blueprint's two questions (BP-5).
enum InboxLens: String, CaseIterable {
    case route, tidy

    var title: String {
        switch self {
        case .route: return "Route"
        case .tidy: return "Tidy"
        }
    }
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

    /// Which question you are answering. The blueprint's Route / Tidy.
    @State private var lens: InboxLens = .route
    /// The orphan whose routing question is open — one at a time.
    @State private var routing: UInt64?

    /// The two lenses, as the blueprint names and counts them.
    private func lensRow(unrouted: Int, tidy: Int) -> some View {
        HStack(spacing: 8) {
            ForEach(InboxLens.allCases, id: \.self) { l in
                let count = l == .route ? unrouted : tidy
                Button { lens = l } label: {
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
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Capsule().fill(lens == l ? LivTheme.panel2 : .clear))
                    .overlay(
                        Capsule().strokeBorder(
                            lens == l ? Color.clear : LivTheme.border, lineWidth: 0.5))
                    .contentShape(Capsule())
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
                lensRow(unrouted: scraps.count, tidy: proposals.count)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                if workspaces.lensOn {
                    // It explains an EXCEPTION: this one list ignores the
                    // workspace (owner, 2026-08-06).
                    HStack(spacing: 8) {
                        ValueChip("all workspaces")
                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 6)
                }

                if lens == .route {
                    if scraps.isEmpty {
                        // The blueprint's own copy (BP-5 B8).
                        EmptyHint(
                            "Inbox zero",
                            detail: "Anything you capture without deciding what it is waits here.",
                            glyph: .inbox
                        )
                        .padding(.top, 32)
                    } else {
                        ForEach(scraps) { row in
                            routeCard(row)
                        }
                    }
                } else {
                    if groups.isEmpty && !assistOff {
                        EmptyHint("Nothing to tidy.")
                            .padding(.top, 32)
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
        Button {
            withAnimation(LivMotion.nav) {
                routing = routing == row.id ? nil : row.id
            }
        } label: {
            routeFace(row)
        }
        .livRowPress()
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                box.trash(row.id)  // soft, undoable
            } label: {
                Label("Trash", systemImage: "trash")
            }
            .tint(LivTheme.red)
        }
    }

    private func routeFace(_ row: EntityRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                // QUIET, because this list is one kind by construction
                // (owner, 2026-08-18: "colour only in mixed lists").
                // Everything is genuinely mixed and keeps its tint; the
                // Inbox is a pile of unrouted captures, so its colour
                // was twenty identical yellow marks telling nothing
                // apart — which is what the owner saw on 2026-08-20:
                // "so many color blips and tags".
                LivIcon(glyph: LivKind.glyph(of: row), color: LivTheme.text2, size: 19)
                    .frame(width: 22)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
                Text(displayTitle(row))
                    .font(.system(size: LivType.body, weight: .medium))
                    .foregroundStyle(LivTheme.text)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(stamp(row))
                    .font(.system(size: LivType.label).monospacedDigit())
                    .foregroundStyle(LivTheme.text3)
            }
            // THE VERBS ARE NOT ON EVERY ROW any more (BP-5 B3/B4): the
            // blueprint's orphan row is one line — icon, title, source,
            // one chip, age — and the routing question belongs to the
            // row you PICKED. Four buttons on every row made a list of
            // eight captures into thirty-two controls.
            if routing == row.id {
                HStack(spacing: 7) {
                    routeVerb("Task", .task) { routeTask(row) }
                    routeVerb("Event", .event) { routeEvent(row) }
                    routeVerb("Note", .note) { route(row, to: "note", as: "Note") }
                    routeVerb("Link", .link) { route(row, to: "link", as: "Link") }
                }
                .padding(.leading, LivRow.hairline)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
                .padding(.leading, LivRow.hairline)
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

    /// What this suggestion is ABOUT. The proposal carries the entity id;
    /// the shell already knows how to turn one into a title.
    private func title(of p: ProposalRow) -> String {
        guard let id = p.entity, let row = box.entity(id) else { return "Untitled" }
        return livRowTitle(row)
    }

    private func suggestionRow(_ p: ProposalRow) -> some View {
        HStack(alignment: .center, spacing: 0) {
            // A SENTENCE ABOUT YOUR THINGS, not a command diff (owner,
            // 2026-08-20: "so many color blips and tags, plus cryptic
            // messages crammed into rows"). The row used to lead with up
            // to three chips rendering the raw writes — "+ created ·
            // 2026-08-…", "– trash", "+ redirect" — which is the
            // proposal's implementation, not its meaning, and left the
            // reader to guess WHICH note was about to change. The name
            // was on the wire the whole time (`ProposalRow.entity`).
            VStack(alignment: .leading, spacing: 2) {
                Text(title(of: p))
                    .font(.system(size: LivType.body))
                    .foregroundStyle(LivTheme.text)
                    .lineLimit(1)
                if let reason = p.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.system(size: LivType.label))
                        .foregroundStyle(LivTheme.text2)
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
