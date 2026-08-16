// liv iOS — THINGS: one list of what you have, arranged three ways
// (owner, 2026-08-16, after four separate view tabs read as "a
// precursor to a sloppy version of ClickUp").
//
// Not three screens behind one header: ONE place, re-sorted. By DATE it
// is the day you are on and what is late; by STATUS it is the columns
// you work through; ALL is everything, newest first. The kinds do not
// divide it — a note with a due date is in Date, a note marked "doing"
// is in Status, and that is the object model showing through instead of
// a drawer per type.

import SwiftUI

struct ThingsView: View {
    @EnvironmentObject var desk: DeskModel

    var body: some View {
        VStack(spacing: 0) {
            arrangementRow
            Group {
                switch desk.arrangement {
                case .date: TodayView()
                case .status: TasksView()
                case .all: AllThings()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The one control on this page: how the list is arranged. A
    /// segmented control and not four tabs — the same things, ordered
    /// differently, is not four places.
    private var arrangementRow: some View {
        Picker("Arrangement", selection: $desk.arrangement) {
            ForEach(LivArrangement.allCases) { arrangement in
                Text(arrangement.title).tag(arrangement)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

/// EVERYTHING you have, newest first. The list that used to be its own
/// view (Everything) and then Find's empty state; it belongs here, as
/// the arrangement that does not arrange.
struct AllThings: View {
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var workspaces: WorkspaceModel

    var body: some View {
        let lens = workspaces.activeQuery
        let rows = (box.snap?.entities ?? [])
            .filter { row in
                guard row.trashed != true, row.archived != true else { return false }
                guard workspaces.lensOn, !lens.isInert else { return true }
                return lens.matches(row)
            }
            .sorted { $0.id > $1.id }
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(rows.prefix(300)) { row in
                    Button {
                        desk.open(row.id)
                    } label: {
                        ThingRow(row: row).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 96)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

/// One line of the All arrangement: what it is, what it is called, and
/// when — the same three facts every list in the app shows, in the same
/// order, with the kind's own colour doing the telling.
struct ThingRow: View {
    let row: EntityRow

    var body: some View {
        HStack(spacing: 10) {
            IconChip(
                glyph: LivKind.glyph(of: row), color: LivKind.color(of: row), size: 22,
                on: LivTheme.panel2)
            VStack(alignment: .leading, spacing: 1) {
                Text(livRowTitle(row))
                    .font(.system(size: LivType.strong))
                    .foregroundStyle(
                        livRowIsUntitled(row) ? LivTheme.text3 : LivTheme.text)
                    .lineLimit(1)
                if let status = row.status, !status.isEmpty {
                    Text(status)
                        .font(.system(size: LivType.caption))
                        .foregroundStyle(LivTheme.text3)
                }
            }
            Spacer(minLength: 8)
            if let due = row.due {
                Text(DetailFmt.due(due, end: row.dueEnd, dateOnly: row.dueDateOnly ?? false))
                    .font(.system(size: LivType.caption).monospacedDigit())
                    .foregroundStyle(LivTheme.text3)
            }
        }
        .frame(minHeight: LivRow.height)
        .overlay(alignment: .bottom) {
            Rectangle().fill(LivTheme.border).frame(height: 0.5)
        }
    }
}

// MARK: - the desk, as a place

/// THE DESK: the things you have open, as a grid you can stand on. It is
/// a PLACE in the bar like the others (owner, 2026-08-16: "'Open' isn't
/// a page yet it seems like one") — pressing Desk while you are reading
/// puts the grid back, pressing it from anywhere else brings back what
/// you were reading.
struct DeskFloor: View {
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var box: BoxModel

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    /// The inactive list, over the grid — the same overlay the tab
    /// switcher used to host, now that the Desk IS the switcher.
    @State private var inactiveShown = false

    var body: some View {
        ZStack {
            grid
            if inactiveShown {
                InactiveTabs(shown: $inactiveShown)
                    .environmentObject(desk)
                    .environmentObject(box)
                    .background(LivTheme.canvas.ignoresSafeArea())
                    .transition(.move(edge: .trailing))
                    .zIndex(2)
            }
        }
    }

    private var grid: some View {
        ScrollView {
            if desk.liveTabs.isEmpty {
                EmptyHint("Nothing open. The + makes a note.")
                    .padding(.top, 60)
            } else {
                inactiveRow
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(desk.liveTabs) { tab in
                        TabCard(
                            tab: tab,
                            active: tab.id == desk.activeTabId,
                            onOpen: {
                                desk.focus(tab.id)
                                desk.stand(on: .desk)
                            },
                            onClose: { desk.close(tab.id) })
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 8)
    }
}

extension DeskFloor {
    /// One row, above the grid. Hidden entirely at zero — an empty
    /// "Inactive 0" row is furniture explaining itself.
    @ViewBuilder fileprivate var inactiveRow: some View {
        let parked = desk.inactiveTabs
        if !parked.isEmpty {
            Button {
                withAnimation(LivMotion.nav) { inactiveShown = true }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: LivType.body))
                        .foregroundStyle(LivTheme.text3)
                        .frame(width: 16)
                    Text("Inactive")
                        .font(.system(size: LivType.body, weight: .medium))
                        .foregroundStyle(LivTheme.text)
                    ValueChip(LivTabs.label(LivTabs.days), dotted: false)
                    Spacer(minLength: 0)
                    Text("\(parked.count)")
                        .font(.system(size: LivType.body).monospacedDigit())
                        .foregroundStyle(LivTheme.text3)
                    Image(systemName: "chevron.right")
                        .font(.system(size: LivType.label, weight: .semibold))
                        .foregroundStyle(LivTheme.text3)
                }
                .padding(.horizontal, 12)
                .frame(height: LivRow.height)
                .background(
                    RoundedRectangle(cornerRadius: LivTheme.radius)
                        .fill(LivTheme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: LivTheme.radius)
                        .strokeBorder(LivTheme.border, lineWidth: 0.5)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 10)
        }
    }
}
