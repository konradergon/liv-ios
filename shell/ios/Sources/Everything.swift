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
        let slice = rows(lens)
        List {
            Group {
                // NO TITLE, no count (owner, 2026-08-18): the bar names
                // the state, and the number was furniture. The slice
                // picker is the only thing this screen needs at its
                // head, because it changes what the list IS.
                picker
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                if slice.isEmpty {
                    EmptyHint(empty)
                } else {
                    ForEach(slice) { row in line(row) }
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

    /// The slice pills (ClickUp's shape, owner 2026-08-18): compact,
    /// outlined when off, filled when on, and no well around them. The
    /// segmented control this replaces was a box inside a box.
    private var picker: some View {
        HStack(spacing: 8) {
            ForEach(lenses) { l in
                Button {
                    lens = l
                } label: {
                    Text(l.title)
                        .font(.system(size: LivType.body, weight: lens == l ? .semibold : .regular))
                        .foregroundStyle(lens == l ? LivTheme.text : LivTheme.text2)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
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

    // MARK: one row

    private func line(_ row: EntityRow) -> some View {
        // A BUTTON, not a tap gesture (owner's clips, 2026-08-20). A
        // gesture opens the row and says nothing while it does it;
        // every app in the reference set lights the row under the
        // finger first. Eight rows in this app were gestures.
        Button { desk.open(row.id) } label: {
            row_(row)
        }
        .livRowPress()
    }

    private func row_(_ row: EntityRow) -> some View {
        LivListRow(
            glyph: LivKind.glyph(of: row),
            // A MIXED list: the kind's colour is doing work here, so it
            // stays (owner, 2026-08-18: "colour only in mixed lists").
            tint: LivKind.color(of: row),
            title: display(row),
            untitled: livRowIsUntitled(row)
        ) {
            // ONE anchor chip, then when — the blueprint's row budget
            // (BP-3: "type icon · title · anchor chip · status dot ·
            // modified", and "empty fields do not render"). It was three
            // chips before the surface pass and none after it; one is
            // what the spec asks for, and it answers the question a
            // mixed list actually raises: what is this attached to.
            if let anchor = anchorChip(row) {
                ValueChip(anchor)
            }
            if let trailing = trailing(row) {
                LivRowFact(text: trailing, emphasis: lens == .upcoming)
            }
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                box.trash(row.id)
            } label: {
                Label("Trash", systemImage: "trash")
            }
        }
    }


    /// The row's ONE anchor, in the blueprint's own order: project →
    /// subject → people → area. First one that exists wins; nothing
    /// renders when none does.
    private func anchorChip(_ row: EntityRow) -> String? {
        for property in ["project", "subjects", "people", "area"] {
            let hit = (row.cells ?? []).first {
                $0.property == property && !($0.value ?? "").isEmpty
            }
            if let value = hit?.value, !value.isEmpty { return value }
        }
        return nil
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

}
