import SwiftUI

// MARK: - Docs: the list of what you have written (owner, 2026-08-18)

/// The root of the Docs state, and the thing that replaced tabs.
///
/// **Ordered by what you touched last**, not by when you made it. That
/// ordering is the whole reason this can be faster than a grid of open
/// tabs: the note you were editing ten minutes ago is the first row, so
/// "get me back to that one" is the same two taps a tab switcher cost —
/// and unlike the grid it can also reach the note you did NOT leave
/// open. The signal is the log's own (`recency` on the wire, the seq of
/// the last transaction that touched the entity — the same key search
/// tiebreaks with, so the two lists can never disagree).
///
/// What it deliberately does not do: track "opened". Reading a note
/// without changing it does not bump it. Opening is not in the log at
/// all — no verb writes a visit — and inventing a device-side one would
/// make this list disagree with search on every other surface.
struct DocsList: View {
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var workspaces: WorkspaceModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if rows.isEmpty {
                    EmptyHint("Nothing written yet. The + below starts one.")
                        .padding(.top, 40)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        Button { desk.open(row.id) } label: {
                            LivListRow(
                                glyph: LivKind.glyph(of: row),
                                title: livRowTitle(row),
                                untitled: livRowIsUntitled(row),
                                divided: i < rows.count - 1
                            ) {
                                if let when = whenLabel(row) { LivRowFact(text: when) }
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { box.trash(row.id) } label: {
                                Label("Trash", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
        }
        .contentMargins(.bottom, 88, for: .scrollContent)
        .background(LivTheme.canvas)
        .safeAreaInset(edge: .top) { LivTopScrim() }
    }

    /// NO TITLE and no count (owner, 2026-08-18: "the view name doesn't
    /// need to be repeated"). The bar names the state; a heading over
    /// the list would say it twice, and the number was furniture.
    ///
    /// The workspace lens has no chip here either — the workspace's own
    /// name is at the top of the screen.
    private func whenLabel(_ row: EntityRow) -> String? {
        guard let stamp = row.created, stamp > 0 else { return nil }
        let day = Civil.day(of: stamp)
        return day == Civil.todayDay() ? Civil.timeString(stamp) : Civil.dayLabel(day)
    }

    /// Documents only — a task is a record and opens as a card, so a
    /// list of things that open HERE is the honest content of this
    /// state. Files count: a file is a document you work on.
    ///
    /// The sort key is the wire's `recency`, with the id as the
    /// tiebreak so the order is total and never flickers.
    private var rows: [EntityRow] {
        let lens = workspaces.activeQuery
        let lensOn = workspaces.lensOn && !lens.isInert
        return (box.snap?.everything ?? [])
            .compactMap { box.entity($0) }
            .filter { row in
                row.trashed != true && row.archived != true
                    && TabShape.of(row) != .record
                    && (!lensOn || lens.matches(row))
            }
            .sorted { ($0.recency ?? 0, $0.id) > ($1.recency ?? 0, $1.id) }
    }
}
