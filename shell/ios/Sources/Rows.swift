import SwiftUI

// MARK: - the one list row (surface pass, owner 2026-08-18)

/// The quietest fact on a row: a date, a time, a count. One ink, one
/// size, monospaced digits so a column of them lines up.
/// A FACT IS DRAWN ONLY WHEN IT CHANGES.
///
/// Measured off `everything.png`: fourteen consecutive rows read "Mon 31
/// Aug", right-aligned and monospaced, in the same ink as the titles
/// beside them — and since most titles are the placeholder "Untitled",
/// the screen was two ragged columns of near-identical grey. A date that
/// is true of every row on screen tells you nothing about any of them.
///
/// It compares the RENDERED STRING, never the day. Both `tasksDue` and
/// `whenLabel` return a TIME for today's rows, so comparing
/// `Civil.day(of:)` would delete the second of two things due today at
/// 09:00 and 20:00 — that is data loss, not a repeat.
///
/// Suppression rather than day-group headers, which two readings of this
/// screen proposed: a header is only honest where the printed key is the
/// SORT key, and Notes sorts on `recency` while printing `created`.
func livNewFact(_ s: String?, after prev: String?) -> String? {
    s == prev ? nil : s
}

/// IS THIS ROW DONE? One predicate, because it was written twice —
/// byte-identical bodies in `Calendar.swift` and `Today.swift`, which is
/// standing rule 4 in its smallest form. `design/one-core.md` wants the
/// tick predicate in Rust eventually, once entry status and cardinality
/// go with it; until that batch is scheduled it lives here, once.
///
/// `doneNames` is the set of status options whose `completes` is true —
/// the vocabulary decides what "done" means, never a hardcoded string.
func livIsDone(_ row: EntityRow, _ doneNames: Set<String>) -> Bool {
    row.status.map { doneNames.contains($0) } ?? false
}

struct LivRowFact: View {
    let text: String
    /// Past due and not done: the one fact on a row that turns RED (the
    /// clearer boards — "red only for late").
    var late: Bool = false

    var body: some View {
        // THE ROW'S SECOND VOICE, at `label` (16) with monospaced digits.
        //
        // text2 SINCE THE CLEARER BOARDS (2026-09-24). It was text3 from
        // 2026-09-05, on the argument that ink separates the voices — at
        // 3.52:1 against the title's full ink where text2 gives 2.26:1.
        // The boards draw every fact in text2 at 16 beside an 18 title and
        // rule "never text3 on a content row's fact": the size step and
        // the tier step together do the separating, and text3 on the
        // surface card (4.09:1) sat under the 4.5 floor text holds itself
        // to.
        Text(text)
            .font(.system(size: LivType.label).monospacedDigit())
            .foregroundStyle(late ? LivTheme.red : LivTheme.text2)
            .lineLimit(1)
    }
}


// MARK: - the press state (surface pass 2, owner's clips 2026-08-20)

/// A row answers the finger before it answers the tap.
///
/// The app had no custom button style at all: rows built on `Button`
/// got SwiftUI's plain style, which does nothing to a row, and the
/// eight rows built on `.onTapGesture` got less than that. Every app
/// in the owner's reference set — Apple Notes, Obsidian, ChatGPT —
/// lights the row under the finger. It is the cheapest possible signal
/// that the tap landed, and its absence is most of what "clunky" means
/// on a touch screen.
///
/// Slide-only motion (owner, 2026-07-31) is about NAVIGATION — areas
/// arriving and leaving. A press is not navigation and does not move:
/// it is a fill that is either there or not.
struct LivPress: ButtonStyle {
    /// A standalone row rounds its own corners; 0 is a square fill.
    var radius: CGFloat = 0
    /// A ROW ON A CARD fills the card's own shape for where it sits, so
    /// a pressed first or last row keeps the card's rounded corners
    /// instead of squaring them off.
    var position: LivCardPosition? = nil
    var fill: Color = LivTheme.pressed

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if configuration.isPressed {
                    if let position {
                        position.shape.fill(fill)
                    } else {
                        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill)
                    }
                }
            }
            .contentShape(Rectangle())
    }
}

extension View {
    /// A CONTROL ON A CARD ROW — an accept circle, a ✕, a ✓ — laid out at
    /// the mark's height, so a 52 row stays 52 (laid out at the 44 touch
    /// floor, a title-only row came out 62), and hit-tested out to 44 in
    /// the row's own vertical padding. The width is the control's own and
    /// does not grow, so two side by side never share a finger.
    func livRowControl(width: CGFloat) -> some View {
        frame(width: width, height: LivCards.mark)
            .contentShape(
                Rectangle()
                    .size(width: width, height: LivRow.touch)
                    .offset(y: (LivCards.mark - LivRow.touch) / 2))
    }

    /// The press for a row on a card, in the card's own shape for where
    /// the row sits. Written as a modifier so a row that is NOT a button
    /// (a swipe row) can still be converted without changing its shape.
    func livRowPress(_ position: LivCardPosition) -> some View {
        buttonStyle(LivPress(position: position))
    }
}

// MARK: - the card (surface pass 2; the clearer boards, 2026-09-24)

/// Related rows on a raised panel, inset from the screen's edges.
///
/// This is the one shape every app in the owner's reference set agrees
/// on. Apple Notes puts a date group on a white card with the heading
/// OUTSIDE it; Obsidian's overflow sheet is four cards separated by
/// gaps instead of one list with headers; ChatGPT's settings is three.
/// The gap between two cards says "different things" far more quietly
/// than a heading does, and it needs no words.
///
/// Liv ran every list edge to edge with hairlines, which reads as one
/// undifferentiated column no matter how the rows inside are grouped.
///
/// THIS IS THE STACK FORM, for a card that is not in a `List` (Settings,
/// a sheet). A card whose rows swipe is built of List rows instead, each
/// wearing its piece of the card (`.livCardRow`) — the same fill, radius
/// and inset, so the two cannot be told apart.
struct LivCard<Content: View>: View {
    /// A heading above the card. Outside it, like the references: a
    /// label inside a card is a row that cannot be tapped.
    var label: String? = nil
    var labelStyle: LivHeaderStyle = .screen
    var inset: CGFloat = LivRow.cardInset
    /// `surface` on the canvas; `panel2` on a sheet or in a menu.
    var fill: Color = LivTheme.surface
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let label {
                SectionLabel(label, style: labelStyle)
                    .padding(.horizontal, inset)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(fill)
                .clipShape(
                    RoundedRectangle(cornerRadius: LivTheme.radiusLg, style: .continuous))
                .padding(.horizontal, inset)
        }
    }
}

/// WHERE A ROW SITS IN ITS CARD — which of the card's corners it owns,
/// and whether a hairline runs under it (every row but the last).
enum LivCardPosition {
    case first, middle, last, only

    /// Row `index` of a card holding `count` rows.
    static func of(_ index: Int, in count: Int) -> LivCardPosition {
        if count <= 1 { return .only }
        if index == 0 { return .first }
        return index == count - 1 ? .last : .middle
    }

    var divided: Bool { self == .first || self == .middle }

    /// This row's piece of the card: `radiusLg` on the corners it owns.
    var shape: UnevenRoundedRectangle {
        let top = self == .first || self == .only ? LivTheme.radiusLg : 0
        let bottom = self == .last || self == .only ? LivTheme.radiusLg : 0
        return UnevenRoundedRectangle(
            topLeadingRadius: top, bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom, topTrailingRadius: top, style: .continuous)
    }
}

extension View {
    /// A `List` row as its piece of a card. The row keeps being a List
    /// row — so `.swipeActions` keeps working — and its background draws
    /// the card: inset `cardInset` from the screen, rounded on the
    /// corners its position owns. The content spans the card, so a
    /// `LivCardRow` inside lays out in card coordinates.
    func livCardRow(position: LivCardPosition, fill: Color = LivTheme.surface) -> some View {
        listRowInsets(
            EdgeInsets(top: 0, leading: LivRow.cardInset, bottom: 0, trailing: LivRow.cardInset))
            .listRowSeparator(.hidden)
            .listRowBackground(
                position.shape.fill(fill).padding(.horizontal, LivRow.cardInset))
    }
}

/// A FOLD HAS TWO STATES, collapsed and expanded, and nothing between
/// (owner, 2026-09-27).
///
/// The List redraws a row that is already on screen — content and
/// background — a few frames AFTER the rows it inserts or removes. A fold
/// header that stayed one row across the change therefore lagged its own
/// rows: open, it kept its rounded bottom over the rows arriving under it
/// (a notch at the join); shut, it stayed square with nothing below. So
/// the header is a DIFFERENT row in each state (`.id(open)`): the List
/// swaps it in the same update as the rows, with no redraw to wait for.
/// And the switch is instant — `livToggleFold` — because a crossfade
/// between the two headers would be a third state of its own.
extension View {
    /// A fold's header: the card's only row while collapsed, its first
    /// while expanded.
    func livFoldRow(open: Bool) -> some View {
        let position: LivCardPosition = open ? .first : .only
        return livRowPress(position)
            .livCardRow(position: position)
            .id(open)
    }
}

/// Collapse or expand a fold: one update, no animation (see `livFoldRow`).
func livToggleFold(_ toggle: () -> Void) {
    var instant = Transaction()
    instant.disablesAnimations = true
    withTransaction(instant, toggle)
}

/// The hairline BETWEEN two rows of a card: 0.5 in `border`, from where
/// the words start (`LivCards.rule`, 56 in card coordinates) to the
/// card's right edge, which the card's own clip ends. None under the last
/// row. A row with no mark passes `LivCards.ruleBare`; the schedule,
/// `LivSchedule.rule`.
struct LivCardRule: View {
    var inset: CGFloat = LivCards.rule

    var body: some View {
        Rectangle()
            .fill(LivTheme.border)
            .frame(height: 0.5)
            .padding(.leading, inset)
    }
}

// MARK: - the card row (the clearer boards, 2026-09-24)

/// ONE ROW ON A CARD: a lead (a 28 mark by default), the title with an
/// optional second line under it, and a trailing cluster (a fact, then a
/// chevron or a control, 10 apart). 52 tall with a title alone, 64 with
/// a second line; padded 16 across and 9 above and below; a hairline
/// from `rule` unless it is the card's last row.
///
/// The row draws no background and no press — the card (`LivCard`, or
/// `.livCardRow` in a List) does the one and `livRowPress` the other.
/// It is NOT one accessibility element: a Button row gets its combined
/// label from the Button, as every row always has.
struct LivCardRow<Lead: View, Title: View, Trailing: View>: View {
    /// The second line: 15 text2, one line, parts joined with " · ".
    var detail: String? = nil
    /// A nameless thing's title reads text2, never full strength.
    var muted = false
    var divided = true
    /// 1, or 2 where a title may wrap (Unsorted).
    var titleLines = 1
    /// Where the hairline starts: `LivCards.rule` behind a 28 mark.
    var rule: CGFloat = LivCards.rule
    let lead: Lead
    let title: Title
    let trailing: Trailing

    init(
        detail: String? = nil, muted: Bool = false, divided: Bool = true,
        titleLines: Int = 1, rule: CGFloat = LivCards.rule,
        @ViewBuilder lead: () -> Lead, @ViewBuilder title: () -> Title,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.detail = detail
        self.muted = muted
        self.divided = divided
        self.titleLines = titleLines
        self.rule = rule
        self.lead = lead()
        self.title = title()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: LivCards.markGap) {
            lead
            VStack(alignment: .leading, spacing: LivCards.lineGap) {
                title
                    .font(.system(size: LivType.body))
                    .foregroundStyle(muted ? LivTheme.text2 : LivTheme.text)
                    .lineLimit(titleLines)
                if let detail {
                    Text(detail)
                        .font(.system(size: LivType.detail))
                        .foregroundStyle(LivTheme.text2)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: LivCards.trailingGap) { trailing }
        }
        .padding(.horizontal, LivCards.padX)
        .padding(.vertical, LivCards.padY)
        .frame(minHeight: detail == nil ? LivCards.row : LivCards.twoLine)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if divided { LivCardRule(inset: rule) }
        }
    }
}

/// The default lead: a kind glyph at 22 in text2, centred in the 28 mark
/// column. ICONS ARE INK — kind colour survives only on Today's event
/// bars and the calendar's blocks.
struct LivCardMark: View {
    let glyph: LivGlyph

    var body: some View {
        LivIcon(glyph: glyph, color: LivTheme.text2, size: LivCards.glyph)
            .frame(width: LivCards.mark)
    }
}

extension LivCardRow where Title == Text {
    /// A plain title, with any lead.
    init(
        _ title: String, detail: String? = nil, muted: Bool = false, divided: Bool = true,
        titleLines: Int = 1, rule: CGFloat = LivCards.rule,
        @ViewBuilder lead: () -> Lead, @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            detail: detail, muted: muted, divided: divided, titleLines: titleLines,
            rule: rule, lead: lead, title: { Text(title) }, trailing: trailing)
    }
}

extension LivCardRow where Lead == LivCardMark, Title == Text {
    /// The common row: a kind glyph, a title, a trailing cluster.
    init(
        glyph: LivGlyph, title: String, detail: String? = nil, muted: Bool = false,
        divided: Bool = true, titleLines: Int = 1,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.init(
            detail: detail, muted: muted, divided: divided, titleLines: titleLines,
            lead: { LivCardMark(glyph: glyph) }, title: { Text(title) }, trailing: trailing)
    }
}
