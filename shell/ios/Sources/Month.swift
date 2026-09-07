// liv iOS — THE MONTH GRID, and the two screens that draw it.
//
// Six fixed weeks, Monday-first, one `LivDayMark` per day. It lived
// inside Calendar.swift and was `private` there until 2026-09-07, which
// meant the due sheet could not reach it and drew a system
// `DatePicker(.graphical)` instead — a second month grid, with its own
// selected-day fill and its own red "today", against an app whose month
// says selection with a disc. Two grids, two grammars, invisible only
// because they never appeared on the same screen (standing rule 4).
//
// It is here rather than in Kit.swift because it is a surface, not a
// control, and because Calendar.swift is 1,900 lines — the seam standing
// rule 9 asks you to look for.
//
// WHAT STAYED BEHIND, on purpose: `MonthPagerView` and `loadWindow` are
// the calendar's own. The pager holds `@EnvironmentObject var desk` and
// publishes `desk.pagerZone` so the window-level panel recognizer keeps
// off it; a due picker has no desk to negotiate with and no snapshot
// window to steer. `CalGrid` (the month math) was already internal —
// `Positions.swift` names a month too.

import SwiftUI

// MARK: - the weekday header

/// M T W T F S S, Monday-first, over a grid.
///
/// It was `weekdayRow`, a private var on the Calendar SCREEN — so
/// extracting only the grid would have forced the due sheet to hand-roll
/// a second copy of `CalGrid.weekdayLetters`, which is the rule-4
/// violation the extraction exists to prevent. The caller supplies its
/// own padding; the row supplies the letters and their spacing.
struct MonthWeekdayRow: View {
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { i in
                Text(CalGrid.weekdayLetters[i])
                    .font(.system(size: LivType.label, weight: .semibold))
                    .foregroundStyle(LivTheme.text2)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - the month grid's data, decided before it is drawn

/// One cell of the month grid, already decided: the number, whether it
/// belongs to the month, and how many busy dots it draws. Everything the
/// cell draws and nothing else, so a cell rebuilds when its DAY changes
/// and not because a finger moved.
struct CalCell: Equatable {
    let day: Int64
    let number: Int
    let inMonth: Bool
    let isToday: Bool
    let count: Int
    /// HOW MANY DOTS, capped at three.
    ///
    /// It was `[Color]` — up to three kind colours (owner, 2026-08-13) —
    /// until 2026-09-07. The colours were removed on 2026-08-31 and the
    /// array they fed was left behind: the only read left in the tree
    /// was `i < c.dots.count`, so every `Color` built here was allocated
    /// and thrown away, once per cell, 126 cells per pager evaluation
    /// (standing rule 6). It also makes `CalMonth`'s `Equatable` — which
    /// is the whole reason the grid can skip a redraw — compare Ints
    /// instead of Colors.
    let dots: Int
}

/// One month's six weeks, ready to draw.
struct CalMonth: Equatable {
    let month: Int64
    let cells: [CalCell]
}

/// Build one month from a count of what each day holds. Runs when the
/// MONTH or the SNAPSHOT moves — never per frame of a drag, which is the
/// whole point of the type (measured 2026-08-15: a 1.2s drag rebuilt
/// 12,348 cells).
///
/// COUNTS, NOT ITEMS. It took `[Int64: [CalendarDayItem]]` until
/// 2026-09-07 and read `.count` off each bucket — the rest of the item
/// was only ever used to pick a dot's kind colour, and those went on
/// 2026-08-31. Taking counts is what lets this file stand on its own:
/// the due sheet has no calendar items and passes `[:]`.
func calMonth(_ month: Int64, today: Int64, counts: [Int64: Int]) -> CalMonth {
    let start = CalGrid.gridStart(month)
    var cells: [CalCell] = []
    cells.reserveCapacity(42)
    for i in 0..<42 {
        let day = Civil.addDays(start, i)
        let held = counts[day] ?? 0
        cells.append(
            CalCell(
                day: day,
                number: Civil.dayNumber(day),
                inMonth: CalGrid.firstOfMonth(day) == month,
                isToday: day == today,
                count: held,
                dots: min(3, held)))
    }
    return CalMonth(month: month, cells: cells)
}

// MARK: - the grid

/// Six weeks of one month, drawn from cells decided in advance.
/// Equatable on purpose: its inputs are values, so SwiftUI can skip the
/// whole grid while only the strip's offset is moving.
struct MonthGridView: View, Equatable {
    let month: CalMonth
    let selected: Int64
    let onSelect: (Int64) -> Void
    /// The long-press door. OPTIONAL, because only the calendar has one:
    /// holding a day there creates an all-day event, and a due picker
    /// has nothing to create. Nil means no gesture is attached at all,
    /// rather than one that fires into a no-op and eats the press.
    var onHold: ((Int64) -> Void)? = nil

    /// The closures are the same code every time; only the data decides.
    /// NOTE that this compares `month` and `selected` ONLY — so if a
    /// display option is ever added here it will be invisible to the
    /// skip, and the grid will not repaint when it changes. Keep any
    /// such option constant per call site, or add it here too.
    static func == (a: MonthGridView, b: MonthGridView) -> Bool {
        a.month == b.month && a.selected == b.selected
    }

    var body: some View {
        VStack(spacing: CalGrid.rowGap) {
            ForEach(0..<6, id: \.self) { week in
                HStack(spacing: CalGrid.rowGap) {
                    ForEach(0..<7, id: \.self) { col in
                        cell(month.cells[week * 7 + col])
                    }
                }
            }
        }
    }

    /// One day: the mark, then how busy it is. Long-press = the event
    /// door.
    ///
    /// THE MARK IS `LivDayMark`, THE SAME ONE THE WEEK STRIP DRAWS
    /// (2026-09-07). Rev 47 replaced a tiny dot and a horizontal bar with
    /// a disc after the owner named them — *"today's date is marked by a
    /// tiny dot that is completely hidden by a horizontal bar when
    /// selected… you have a tendency to make UI elements tiny and subtle.
    /// Try to go for the opposite."* — but that landed on Today's strip
    /// only, and this grid kept the exact pair: a 4pt accent dot above
    /// the number and a 22x2 ink rule below it. Two marks for one idea,
    /// and the older of the two was the one the owner had just rejected.
    ///
    /// The disc is 28 here against the strip's 36, in a cell grown 40 →
    /// 46 — sized to what forty-two cells can carry rather than copied
    /// (see `LivDay`). An out-of-month day dims to `text3`, which is why
    /// the mark takes a `rest` ink.
    ///
    /// HOW BUSY, NOT WHAT KIND (polish pass, 2026-08-31). Each dot wore
    /// its entity's kind colour, so a month grid drew up to sixty
    /// saturated dots in six hues — the only colour on the screen, and
    /// confetti at 4pt. The kind language is not lost; it is on every
    /// ROW, where a glyph is big enough to tell apart.
    private func cell(_ c: CalCell) -> some View {
        let isSelected = c.day == selected
        return VStack(spacing: 3) {
            LivDayMark(
                number: c.number,
                selected: isSelected,
                today: c.isToday,
                diameter: LivDay.gridDisc,
                rest: c.inMonth ? LivTheme.text : LivTheme.text3)
            // Three dots mean busy — see the doc above for why they are
            // ink and not kind colours.
            HStack(spacing: 2.5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(
                            i < c.dots ? LivTheme.text3 : Color.clear
                        )
                        .frame(width: 4, height: 4)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: CalGrid.cellHeight)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(LivMotion.pick) { onSelect(c.day) } }
        .modifier(MonthHold(day: c.day, onHold: onHold))
        .accessibilityLabel(Civil.dayLabel(c.day))
        .accessibilityValue(c.count == 0 ? "" : "\(c.count) items")
    }
}

/// The long-press, attached only when there is somewhere for it to go.
///
/// A `ViewModifier` rather than an `if` inside the cell's chain: the two
/// branches of an `if` are different view types, and switching between
/// them tears the cell down and rebuilds it. Here the branch is decided
/// once per call site and never changes.
private struct MonthHold: ViewModifier {
    let day: Int64
    let onHold: ((Int64) -> Void)?

    func body(content: Content) -> some View {
        if let onHold {
            content.onLongPressGesture(minimumDuration: 0.45) { onHold(day) }
        } else {
            content
        }
    }
}
