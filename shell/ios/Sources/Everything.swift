// liv iOS — Notes: the list of what you have written, by what you touched
// last. The raw value of this view is still `everything` (Navigate.swift),
// because that word is in every stored position and every `liv://` route;
// the file keeps the name of the view it was, for the same reason.
//
// WHAT IT WAS. Everything (design/furnishing-study.md §6) was the flat
// list of every item in the box, newest first, with lenses over it — All,
// Notes, Upcoming, Unfiled — and it existed because a typed, undated note
// that had left the Inbox was in no view at all. On 2026-09-16 it was
// drawn as Notes for a day, then as All for an hour, and the owner ruled
// on sight: "make all just a notes list. remove 'everything' or 'all'."
// A task in this app is a card and a row in Tasks; an event is a block on
// the Calendar; the thing that had no view of its own was always the
// NOTE, and this is that view. The lenses went with the mixed list they
// narrowed (standing rule 6).
//
// Rules:
//   1. It WEARS the workspace lens like every workspace view (owner, rev
//      6, 2026-08-03: "workspaces define context consistently via
//      property filtering"). The always-complete surface is the All
//      workspace, one switch away.
//   2. NOTES, and only notes: a task is a record and opens as a card, so
//      a list of things that open as a PAGE is the honest content of the
//      word. Files count; a file is a document you work on.

import SwiftUI

struct EverythingView: View {
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var workspaces: WorkspaceModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let slice = rows
        List {
            Group {
                // THE SCREEN'S NAME. Notes, Everything and Tasks were the
                // three surfaces with nothing at the top saying where you
                // are — Today, Inbox and the Calendar all lead with one,
                // and a list that starts at its first row reads as a
                // fragment of a screen rather than a screen.
                LivScreenTitle("Notes")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                if slice.isEmpty {
                    EmptyHint("Nothing written")
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
        .onAppear { box.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { box.refresh() }
        }
    }

    /// `everything` is the curated front-of-house list — backstage entities
    /// (properties, options, types, workspaces) are already excluded by the
    /// core, so this screen never shows engine plumbing.
    ///
    /// ORDERED BY WHAT YOU TOUCHED LAST, not by when you made it, which is
    /// why this can beat the tab switcher: the note you were editing ten
    /// minutes ago is the first row, and unlike the switcher it also
    /// reaches the note you did NOT leave open. The key is the log's own
    /// `recency` — the seq of the last transaction that touched the
    /// entity, which is what search tiebreaks with, so the two can never
    /// disagree. Reading a note without changing it does not bump it: no
    /// verb writes a visit, and a device-side one would disagree with
    /// search on every other surface.
    private var rows: [EntityRow] {
        (box.snap?.everything ?? [])
            .compactMap { box.entity($0) }
            .filter {
                $0.trashed != true && $0.archived != true && workspaces.admits($0)
                    && TabShape.of($0) != .record
            }
            .sorted { ($0.recency ?? 0, $0.id) > ($1.recency ?? 0, $1.id) }
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
            // Notes and files share this list, so the kind's colour is
            // still doing work (owner, 2026-08-18: "colour only in mixed
            // lists").
            tint: LivKind.color(of: row),
            title: display(row),
            untitled: livRowIsUntitled(row)
        ) {
            // ONE anchor chip, then when — the blueprint's row budget
            // (BP-3: "type icon · title · anchor chip · status dot ·
            // modified", and "empty fields do not render"). It answers
            // the question a list actually raises: what is this attached
            // to.
            if let chip = livAnchorChip(of: row) {
                chip.transition(.scale(scale: 0.85).combined(with: .opacity))
            }
            // Only when it changes — see `livNewFact`. Fourteen rows
            // reading "Mon 31 Aug" said nothing about any of them.
            if let trailing = livNewFact(
                trailing(row), after: prev.flatMap { trailing($0) })
            {
                LivRowFact(text: trailing, emphasis: false)
            }
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing) {
            livTrashAction { box.trash(row.id) }
        }
    }

    /// When you caught it. Today reads as a time — a column of identical
    /// dates tells you nothing.
    private func trailing(_ row: EntityRow) -> String? {
        guard let stamp = row.created, stamp > 0 else { return nil }
        let day = Civil.day(of: stamp)
        if day == Civil.todayDay() {
            let time = Civil.timeString(stamp)
            return time.isEmpty ? "today" : time
        }
        return Civil.dayLabel(day)
    }

    /// A scrap carries no name cell — its display name is its first content
    /// line, the same rule the desk and the outbox ledger use. Markdown
    /// markers come off for display (livDisplayTitle): a note that starts
    /// "# Trip planning" is titled "Trip planning", never "# Trip planning".
    private func display(_ row: EntityRow) -> String { livRowTitle(row) }
}
