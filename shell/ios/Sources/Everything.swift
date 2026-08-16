// liv iOS — Everything (design/furnishing-study.md §6): the flat list of
// what is in the box, newest first.
//
// Why this exists: before it, the app had Today, Inbox, Tasks and Calendar
// and nothing else. A typed, undated note left the Inbox when routed, was
// in no time view, was not a task, and dropped out of Today's "captured"
// strip the next day — so from day two it was reachable only by searching
// for a word in it. Areas were being asked to carry all of navigation,
// which is why picking one felt compulsory.
//
// Rules:
//   1. RETIRED 2026-08-03 (owner, rev 6): this screen now WEARS the
//      workspace lens like every workspace view — "workspaces define
//      context consistently via property filtering" outranks the old
//      "Everything never hides" rule. The always-complete surface is the
//      All workspace: one switch away, and the LensChip in the header
//      says when a lens is on. (The old rule's text, for the record: "a
//      screen called Everything that hides things is a lie.")
//   2. Unfiled means NO AREA — not "no type". The Inbox's rule keys on
//      type, which is why a task you hesitated over was missing from every
//      area AND from the Inbox (the study's §2.6 hole).

import SwiftUI

/// Which slice of the box is on screen.
private enum EverythingLens: String, CaseIterable, Identifiable {
    case all, upcoming, unfiled
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .upcoming: return "Upcoming"
        case .unfiled: return "Unfiled"
        }
    }
}

struct EverythingView: View {
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var workspaces: WorkspaceModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var lens: EverythingLens = .all

    var body: some View {
        let rows = rows(lens)
        List {
            Group {
                HStack(spacing: 8) {
                    SectionLabel("Everything")
                    if workspaces.lensOn { LensChip(label: workspaces.lensLabel) }
                    Spacer(minLength: 0)
                    Text("\(rows.count)")
                        .font(.system(size: LivType.label).monospacedDigit())
                        .foregroundStyle(LivTheme.text3)
                }
                .padding(.top, 8)
                picker
                    .padding(.vertical, 6)
                if rows.isEmpty {
                    EmptyHint(empty)
                } else {
                    ForEach(rows) { row in line(row) }
                }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 10)
        .contentMargins(.bottom, 16, for: .scrollContent)  // full screen: no bar under it
        .background(LivTheme.canvas)
        .onAppear {
            box.refresh()
            // The selected slice may have just been hidden by a
            // workspace switch.
            if !lenses.contains(lens) { lens = .all }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { box.refresh() }
        }
    }

    private var empty: String {
        switch lens {
        case .all: return "Nothing yet. Everything you capture lands here."
        case .upcoming: return "Nothing dated in the next seven days."
        case .unfiled: return "Nothing unfiled — every item has an area."
        }
    }

    /// Unfiled means NO AREA — structurally impossible inside a workspace
    /// whose query stamps one, so the segment hides there rather than
    /// promise an always-empty list (audit, 2026-08-04).
    private var lenses: [EverythingLens] {
        let stampsArea = workspaces.stampCells.contains { $0.property == "area" }
        return EverythingLens.allCases.filter { $0 != .unfiled || !stampsArea }
    }

    private var picker: some View {
        HStack(spacing: 2) {
            ForEach(lenses) { l in
                Button {
                    lens = l
                } label: {
                    Text(l.title)
                        .font(.system(size: LivType.body, weight: lens == l ? .semibold : .regular))
                        .foregroundStyle(lens == l ? LivTheme.text : LivTheme.text3)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: LivTheme.radius - 2)
                                .fill(lens == l ? LivTheme.surface : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: LivTheme.radius).fill(LivTheme.panel2))
    }

    // MARK: one row

    private func line(_ row: EntityRow) -> some View {
        let chips = chips(row)
        return HStack(spacing: 9) {
            // The carved kind chip: what a thing IS, said in its color
            // (blueprints, 2026-08-12).
            IconChip(
                glyph: LivKind.glyph(of: row), color: LivKind.color(of: row), size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(display(row))
                    .font(.system(size: LivType.strong))
                    .foregroundStyle(
                        livRowIsUntitled(row) ? LivTheme.muted : LivTheme.text
                    )
                    .lineLimit(1)
                if !chips.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(chips, id: \.self) { ValueChip($0) }
                    }
                }
            }
            Spacer(minLength: 8)
            if let trailing = trailing(row) {
                Text(trailing)
                    .font(.system(size: LivType.body).monospacedDigit())
                    .foregroundStyle(
                        lens == .upcoming ? LivTheme.text2 : LivTheme.text3)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 40)
        .contentShape(Rectangle())
        .onTapGesture { desk.open(row.id) }
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                box.trash(row.id)
            } label: {
                Label("Trash", systemImage: "trash")
            }
        }
    }

    // MARK: the slice

    /// `everything` is the curated front-of-house list — backstage entities
    /// (properties, options, types, workspaces) are already excluded by the
    /// core, so this screen never shows engine plumbing.
    private func rows(_ lens: EverythingLens) -> [EntityRow] {
        // The workspace lens applies here since rev 6 — the All workspace
        // is the complete view.
        let wsLens = workspaces.activeQuery
        let all = (box.snap?.everything ?? [])
            .compactMap { box.entity($0) }
            .filter { $0.trashed != true && $0.archived != true && wsLens.matches($0) }
        switch lens {
        case .all:
            return all.sorted { ($0.created ?? 0, $0.id) > ($1.created ?? 0, $1.id) }
        case .unfiled:
            return all.filter { area($0) == nil }
                .sorted { ($0.created ?? 0, $0.id) > ($1.created ?? 0, $1.id) }
        case .upcoming:
            // The next seven days, soonest first — the one slice sorted
            // FORWARD, because "what is coming" reads in the order it will
            // arrive. Today included: a thing due in an hour is upcoming.
            let today = Civil.todayDay()
            let horizon = Civil.addDays(today, 7)
            return all
                .filter { row in
                    guard let due = row.due, due > 0 else { return false }
                    let day = Civil.day(of: due)
                    return day >= today && day <= horizon
                }
                .sorted { ($0.due ?? 0, $0.id) < ($1.due ?? 0, $1.id) }
        }
    }

    /// Upcoming answers "when is it due"; the other slices answer "when did
    /// I catch it". Today reads as a time either way — a column of identical
    /// dates tells you nothing.
    private func trailing(_ row: EntityRow) -> String? {
        let stamp = lens == .upcoming ? row.due : row.created
        guard let stamp, stamp > 0 else { return nil }
        let day = Civil.day(of: stamp)
        if day == Civil.todayDay() {
            let time = Civil.timeString(stamp)
            return time.isEmpty ? "today" : time
        }
        return Civil.dayLabel(day)
    }

    private func area(_ row: EntityRow) -> String? {
        let value = (row.cells ?? []).first { $0.property == "area" }?.value
        return (value?.isEmpty ?? true) ? nil : value
    }

    /// A scrap carries no name cell — its display name is its first content
    /// line, the same rule the desk and the outbox ledger use. Markdown
    /// markers come off for display (livDisplayTitle): a note that starts
    /// "# Trip planning" is titled "Trip planning", never "# Trip planning".
    private func display(_ row: EntityRow) -> String { livRowTitle(row) }

    /// The task test is the shell's own: a typed task OR anything carrying a
    /// status. A capture given a status is a task in Today, in Tasks, and to
    /// the reminder scheduler — it must not wear the scrap icon here.

    /// Area first — it is the one filing question — then status, then the
    /// first reference value. Three at most; the row must stay one line.
    private func chips(_ row: EntityRow) -> [String] {
        var out: [String] = []
        if let area = area(row) { out.append(area) }
        if let status = row.status, !status.isEmpty { out.append(status) }
        for cell in row.cells ?? [] {
            guard out.count < 3 else { break }
            // Never the TYPE: the carved chip at the head of the row
            // already says it, and the word "note" beside a blue note
            // icon is the same fact twice (Today has always skipped it).
            guard cell.property != "type", cell.refTarget != nil else { continue }
            let value = cell.value ?? ""
            if !value.isEmpty, !out.contains(value) { out.append(value) }
        }
        return out
    }
}
