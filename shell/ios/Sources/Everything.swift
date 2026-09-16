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
//      All workspace: one switch away. (The old rule's text, for the
//      record: "a screen called Everything that hides things is a lie.")
//   2. Unfiled means NO AREA — not "no type". The Inbox's rule keys on
//      type, which is why a task you hesitated over was missing from every
//      area AND from the Inbox (the study's §2.6 hole).

import SwiftUI

struct EverythingView: View {
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var workspaces: WorkspaceModel
    @Environment(\.scenePhase) private var scenePhase

    /// NOT `@State` since 2026-08-22. The slice is what this view's tab
    /// HOLDS (design/tabs.md, Reading B), so it lives in the plane, is
    /// saved with it, and two tabs can sit on two different slices. The
    /// view derives it and never stores it.
    private var lens: EverythingLens {
        EverythingLens(rawValue: desk.position(.everything) ?? "") ?? .all
    }

    var body: some View {
        let slice = rows(lens)
        List {
            Group {
                // NO TITLE, no count (owner, 2026-08-18): the bar names
                // the state, and the number was furniture. The slice
                // picker is the only thing this screen needs at its
                // head, because it changes what the list IS.
                // THE SCREEN'S NAME. Notes, Everything and Tasks were the
                // three surfaces with nothing at the top saying where you
                // are — Today, Inbox and the Calendar all lead with one,
                // and a list that starts at its first row reads as a
                // fragment of a screen rather than a screen.
                LivScreenTitle("All")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                picker
                    .padding(.bottom, 8)
                if slice.isEmpty {
                    EmptyHint(empty)
                } else {
                    ForEach(Array(slice.enumerated()), id: \.element.id) { i, row in
                        line(row, prev: i == 0 ? nil : slice[i - 1])
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 10)
        .contentMargins(.bottom, LivBar.listRoom, for: .scrollContent)
        .livHidesChrome()  // full screen: no bar under it
        .background(LivTheme.canvas)
        .onAppear {
            box.refresh()
            // The selected slice may have just been hidden by a
            // workspace switch.
            if !lenses.contains(lens) { desk.park(.everything, at: EverythingLens.all.rawValue) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { box.refresh() }
        }
    }

    private var empty: String {
        switch lens {
        case .all: return "Empty"
        case .notes: return "Nothing written"
        case .upcoming: return "Nothing due"
        case .unfiled: return "All filed"
        }
    }

    /// Unfiled means NO AREA — structurally impossible inside a workspace
    /// whose query stamps one, so the segment hides there rather than
    /// promise an always-empty list (audit, 2026-08-04).
    private var lenses: [EverythingLens] {
        let stampsArea = workspaces.stampCells.contains { $0.property == "area" }
        return EverythingLens.allCases.filter { $0 != .unfiled || !stampsArea }
    }

    /// THE SAME CHIP TASKS DRAWS (owner, 2026-09-12: *"make everything
    /// buttons (All, Notes…) match style of equivalents in Tasks"*).
    ///
    /// It was this row's own recipe, and it differed three ways: a
    /// hairline border around every UNCHOSEN chip, semibold rather than
    /// medium on the chosen one, and 14pt of side padding against 12.
    /// The border is the whole visual gap — it made four outlined pills
    /// where Tasks has four words and one filled capsule. The height was
    /// a raw 30 rather than `LivChip.tall`, which is the same number and
    /// the same standing-rule-3 failure the row above it already fixed.
    ///
    /// It also picks with the app's own spring now, as Tasks and the
    /// Inbox both did and this row did not.
    ///
    /// THE OUTLINE WAS A RULING AND IT IS REVERSED ON HIS WORD. These
    /// were "ClickUp's shape (owner, 2026-08-18): compact, outlined when
    /// off, filled when on, and no well around them", replacing a
    /// segmented control that was a box inside a box. That was a real
    /// improvement and the outline came with it. Twelve days later the
    /// 2026-08-30 pass took the border off the Tasks chips and wrote
    /// that the app now had one way of saying "this one" — while leaving
    /// this row outlined. So the reversal is not new here; it is this
    /// row finally getting the change the sentence already claimed.
    private var picker: some View {
        // NO CHIP FOR `.all`. The view is called All (2026-09-16), so a
        // chip saying All would be its name said twice — the same
        // redundancy that briefly put a Notes chip inside a view called
        // Notes. Each chip is a LENS, a narrowing, and it is a TOGGLE:
        // tapping the lit one puts the view back to the whole, exactly
        // as a saved filter's row does in the library panel. None lit
        // means everything, which is what the title already says.
        HStack(spacing: 6) {
            ForEach(lenses.filter { $0 != .all }) { l in
                LivFilterChip(l.title, selected: lens == l) {
                    withAnimation(LivMotion.pick) {
                        desk.park(.everything, at: (lens == l ? EverythingLens.all : l).rawValue)
                    }
                }
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
        let all = (box.snap?.everything ?? [])
            .compactMap { box.entity($0) }
            .filter { $0.trashed != true && $0.archived != true && workspaces.admits($0) }
        switch lens {
        case .all:
            return all.sorted { ($0.created ?? 0, $0.id) > ($1.created ?? 0, $1.id) }
        case .notes:
            // NOTES, and only notes: a task is a record and opens as a
            // card, so a list of things that open as a PAGE is the honest
            // content of the word. Files count; a file is a document you
            // work on.
            //
            // ORDERED BY WHAT YOU TOUCHED LAST, not by when you made it,
            // which is why this can beat the tab switcher: the note you
            // were editing ten minutes ago is the first row, and unlike
            // the switcher it also reaches the note you did NOT leave
            // open. The key is the log's own `recency` — the seq of the
            // last transaction that touched the entity, which is what
            // search tiebreaks with, so the two can never disagree.
            // Reading a note without changing it does not bump it.
            return all.filter { TabShape.of($0) != .record }
                .sorted { ($0.recency ?? 0, $0.id) > ($1.recency ?? 0, $1.id) }
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

    private func line(_ row: EntityRow, prev: EntityRow?) -> some View {
        // A BUTTON, not a tap gesture (owner's clips, 2026-08-20). A
        // gesture opens the row and says nothing while it does it;
        // every app in the reference set lights the row under the
        // finger first. Eight rows in this app were gestures.
        Button { desk.open(row.id) } label: {
            row_(row, prev: prev)
        }
        .livRowPress()
    }

    private func row_(_ row: EntityRow, prev: EntityRow?) -> some View {
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
            if let chip = livAnchorChip(of: row) {
                chip.transition(.scale(scale: 0.85).combined(with: .opacity))
            }
            // Only when it changes — see `livNewFact`. Fourteen rows
            // reading "Mon 31 Aug" said nothing about any of them.
            if let trailing = livNewFact(
                trailing(row), after: prev.flatMap { trailing($0) })
            {
                LivRowFact(text: trailing, emphasis: lens == .upcoming)
            }
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing) {
            livTrashAction { box.trash(row.id) }
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

}
