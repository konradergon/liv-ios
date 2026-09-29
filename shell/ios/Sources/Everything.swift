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
                // THE SCREEN'S NAME, with how many notes it holds (the
                // clearer board: "Notes." over "134 notes").
                LivTitleBlock(
                    "Notes",
                    subtitle: slice.isEmpty
                        ? nil : "\(slice.count) note\(slice.count == 1 ? "" : "s")"
                )
                .listRowInsets(EdgeInsets())
                if slice.isEmpty {
                    EmptyHint("Nothing written")
                } else {
                    // ONE CARD of every note, most recently touched first.
                    ForEach(Array(slice.enumerated()), id: \.element.id) { i, row in
                        line(row, prev: i == 0 ? nil : slice[i - 1], position: .of(i, in: slice.count))
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: LivRow.cardInset, bottom: 0, trailing: LivRow.cardInset))
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

    private func line(_ row: EntityRow, prev: EntityRow?, position: LivCardPosition) -> some View {
        // A BUTTON, not a tap gesture (owner's clips, 2026-08-20): every
        // app in the reference set lights the row under the finger first.
        Button { desk.open(row.id) } label: {
            // ICONS ARE INK (the clearer boards): the kind's glyph in text2,
            // where it wore the kind's colour. Where the note lives is the
            // second line; when it was last touched is the fact — the same
            // key the list is sorted on.
            LivCardRow(
                glyph: LivKind.glyph(of: row), title: display(row),
                detail: livPlace(of: row), muted: livRowIsUntitled(row),
                divided: position.divided
            ) {
                // Only when it changes — see `livNewFact`. Fourteen rows
                // reading the same day said nothing about any of them.
                if let fact = livNewFact(touched(row), after: prev.flatMap { touched($0) }) {
                    LivRowFact(text: fact)
                }
            }
        }
        .livRowPress(position)
        .livCardRow(position: position)
        .swipeActions(edge: .trailing) {
            livTrashAction { box.trash(row.id) }
        }
    }

    /// When you last touched it, in Apple's words: "21:04" today, then
    /// "Yesterday", the weekday, "18 Sep" (`Civil.fact`).
    private func touched(_ row: EntityRow) -> String? {
        guard let ms = row.touchedMs, ms > 0 else { return nil }
        return Civil.fact(Civil.civil(ofInstantMs: ms))
    }

    /// A scrap carries no name cell — its display name is its first content
    /// line, the same rule the desk and the outbox ledger use. Markdown
    /// markers come off for display (livDisplayTitle): a note that starts
    /// "# Trip planning" is titled "Trip planning", never "# Trip planning".
    private func display(_ row: EntityRow) -> String { livRowTitle(row) }
}
