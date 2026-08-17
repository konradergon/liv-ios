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
                header
                if rows.isEmpty {
                    EmptyHint("Nothing written yet. The + below starts one.")
                        .padding(.top, 40)
                } else {
                    ForEach(rows, id: \.id) { row in
                        DocsRow(row: row) { desk.open(row.id) }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .contentMargins(.bottom, 88, for: .scrollContent)
        .background(LivTheme.canvas)
        .safeAreaInset(edge: .top) { LivTopScrim() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            SectionLabel("Docs")
            Spacer(minLength: 8)
            if workspaces.lensOn, !workspaces.activeQuery.isInert {
                LensChip(label: workspaces.activeName)
            }
            Text("\(rows.count)")
                .font(.system(size: LivType.body).monospacedDigit())
                .foregroundStyle(LivTheme.text3)
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
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

// MARK: - one row

/// The same row Everything draws — carved kind chip, title, quiet
/// trailing fact — because a list of things should not look different
/// depending on which list it is (standing rule 4). The trailing fact
/// here is WHEN, taken from `created`: the recency that orders the list
/// is a transaction seq, which is not a date and must never be printed
/// as one.
private struct DocsRow: View {
    let row: EntityRow
    let open: () -> Void

    @EnvironmentObject var box: BoxModel

    var body: some View {
        Button(action: open) {
            HStack(spacing: 9) {
                IconChip(
                    glyph: LivKind.glyph(of: row), color: LivKind.color(of: row), size: 26)
                Text(livRowTitle(row))
                    .font(.system(size: LivType.strong))
                    .foregroundStyle(livRowIsUntitled(row) ? LivTheme.muted : LivTheme.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let when = created {
                    Text(when)
                        .font(.system(size: LivType.body).monospacedDigit())
                        .foregroundStyle(LivTheme.text3)
                }
            }
            .padding(.vertical, 4)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private var created: String? {
        guard let stamp = row.created, stamp > 0 else { return nil }
        let day = Civil.day(of: stamp)
        return day == Civil.todayDay() ? Civil.timeString(stamp) : Civil.dayLabel(day)
    }
}
