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

extension LivCardPosition {
    /// The piece of the card this row draws: its position's corners, or
    /// all four while it is swiped out of the card (`livSwipeLift`).
    func shape(lifted: Bool) -> UnevenRoundedRectangle {
        lifted ? LivCardPosition.only.shape : shape
    }
}

extension View {
    /// A `List` row as its piece of a card. The row keeps being a List
    /// row — so `.swipeActions` keeps working — and its background draws
    /// the card, rounded on the corners its position owns.
    ///
    /// THE CELL IS THE CARD'S WIDTH (2026-09-29). The list is inset-grouped
    /// (`livCardList`), so a cell stands `cardInset` in from each edge and
    /// clips what it holds: a swiped row slides out under the card's own
    /// edge instead of across the screen (owner: "the row should disappear
    /// at the edges of the rows card"). The insets are therefore zero, and
    /// the background needs no padding of its own.
    func livCardRow(
        position: LivCardPosition, lifted: Bool = false, fill: Color = LivTheme.surface
    ) -> some View {
        listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(LivCardPiece(position: position, lifted: lifted, fill: fill))
            .environment(\.livCardRowLifted, lifted)
    }
}

/// A row's piece of the card, easing into a card of its own while it is
/// swiped and back when it is let go — slowly (owner, 2026-09-29: "the
/// rounding and derounding should happen slowly").
private struct LivCardPiece: View {
    let position: LivCardPosition
    let lifted: Bool
    let fill: Color

    var body: some View {
        position.shape(lifted: lifted)
            .fill(fill)
            .animation(LivMotion.lift, value: lifted)
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

// MARK: - a row that changes place is a new row (2026-09-29)

/// THE FOLD'S RULE FOR EVERY CARD ROW (owner, 2026-09-29: the Done-card gap
/// "seems to be present throughout where lists with rounded corners
/// change… apply same solution to them").
///
/// The List redraws a row that is already on screen a few frames AFTER a
/// snapshot inserts or removes rows around it. Measured the same day: tick
/// the last task of a card and the one above it — now the last — kept its
/// square bottom for two frames before rounding. The same happens to a row
/// that becomes first, stops being first or last, or moves when a date
/// write re-sorts the card. A fold header had exactly this, and was fixed by
/// being a different row in each state (`livFoldRow`).
///
/// So a card row's identity is WHAT it is and WHERE it sits at rest
/// (`LivCardKey`). A row whose place changes is, to the List, a new row,
/// swapped in by the same update that moved it, with its right corners from
/// its first frame. Rows whose place did not change keep their identity and
/// are not redrawn.
///
/// A swipe (`livSwipeLift`) changes the corners a row DRAWS but not where
/// it sits, so it stays out of the key: a row re-made mid-swipe would drop
/// the swipe.
struct LivCardKey<ID: Hashable>: Hashable {
    let id: ID
    let rest: LivCardPosition
}

/// One row of a card, ready for a `ForEach`.
struct LivCardSlot<Item: Identifiable>: Identifiable {
    let item: Item
    /// Its index among the card's ITEMS (not counting a fold header).
    let index: Int
    /// Where it sits — half its identity, and the corners it draws.
    let position: LivCardPosition
    var id: LivCardKey<Item.ID> { LivCardKey(id: item.id, rest: position) }
}

/// A card's rows as slots. `above` counts rows of the same card drawn before
/// these (a fold's header), so the positions are the card's and not the
/// list's.
func livCardSlots<Item: Identifiable>(_ items: [Item], above: Int = 0) -> [LivCardSlot<Item>] {
    let count = above + items.count
    return items.enumerated().map { i, item in
        LivCardSlot(item: item, index: i, position: .of(above + i, in: count))
    }
}

/// Collapse or expand a fold: one update, no animation (see `livFoldRow`).
func livToggleFold(_ toggle: () -> Void) {
    var instant = Transaction()
    instant.disablesAnimations = true
    withTransaction(instant, toggle)
}

// MARK: - a swiped row is a card of its own (2026-09-29)

/// A SWIPED ROW ROUNDS, AND ONLY IT (owner, 2026-09-29: "when you slide a
/// row, only that row should get rounded. the rounding and derounding should
/// happen slowly. it should deround itself when you release it").
///
/// A List swipe slides the row's background with its content, and that
/// background is the row's piece of the card — so a swiped row dragged a
/// square-edged strip of card out with it (the owner's screenshot: "what a
/// mess"). Now, the moment it moves, its piece eases into a card of its own
/// (`LivCardPiece`), and eases back as it returns. The rows around it keep
/// their corners: a first attempt re-rounded them too, split the card into
/// three, and was not what he wanted.
///
/// The card's own edge clips the slide (`livCardRow`).
/// WHERE THE LIST STANDS ON THE SCREEN, handed to its rows, so a row can
/// tell a swipe (the row moved in the list) from the list moving with it —
/// the whole desk sliding aside under the library panel.
///
/// A named coordinate space cannot do this: inside a List's cells every
/// space, named or `.scrollView`, comes back as the screen's (measured
/// 2026-09-29: a row read 16, 57, then 219 in all three as the panel
/// opened), so the first attempt lifted a row whenever the panel was out
/// (owner: "with the panel open the top row get rounded corners as if it
/// was held"). The List itself is not in a cell, so its own screen x is
/// exact; the row compares against it.
private struct LivCardListX: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    fileprivate var livCardListX: CGFloat {
        get { self[LivCardListX.self] }
        set { self[LivCardListX.self] = newValue }
    }
}

/// WHETHER A ROW MAY READ ITS OWN MOVEMENT AS A SWIPE: not while the desk
/// itself is travelling (owner, 2026-09-29: "when panel opens/closes the
/// top row gets pressed somehow"). The List and its rows report their new
/// screen positions a frame apart while the desk slides, so for that frame
/// a row stands off the list's edge and reads as swiped. `DeskHost` sets
/// this false while the library is drawn or dragged.
private struct LivSwipesLive: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var livSwipesLive: Bool {
        get { self[LivSwipesLive.self] }
        set { self[LivSwipesLive.self] = newValue }
    }
}

/// Whether this row is swiped out of its card (`livCardRow`): its line
/// goes with its square corners, since a card of its own has no row under it.
private struct LivCardRowLifted: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    fileprivate var livCardRowLifted: Bool {
        get { self[LivCardRowLifted.self] }
        set { self[LivCardRowLifted.self] = newValue }
    }
}

/// The least a card row may be tall — set by `livSwipeLift`.
private struct LivCardRowFloor: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    fileprivate var livCardRowFloor: CGFloat {
        get { self[LivCardRowFloor.self] }
        set { self[LivCardRowFloor.self] = newValue }
    }
}

private struct LivCardListFrame: ViewModifier {
    @State private var x: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .environment(\.livCardListX, x)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: { x = $0 }
    }
}

/// Whether `id` is the lifted row — for a fold header, asking about the row
/// under it.
func livIsLifted(_ id: (some Hashable)?, _ lifted: AnyHashable?) -> Bool {
    guard let id, let lifted else { return false }
    return AnyHashable(id) == lifted
}

extension View {
    /// A List of cards: inset-grouped, so each cell is the card's width and
    /// clips its row (`livCardRow`), with the system's own card look turned
    /// off — the margins are the app's `cardInset`, there are no section
    /// gaps or headers, and every row draws its own piece of card. It is
    /// also the space its rows measure a swipe in.
    ///
    /// ONE SECTION PER SCREEN, framed by clear rows. The system rounds the
    /// first and last cell of a section with ITS radius, not the app's; a
    /// screen's title is its first cell and `livCardListEnd` its last, so
    /// no card row is ever either.
    func livCardList() -> some View {
        listStyle(.insetGrouped)
            .listSectionSpacing(0)
            .environment(\.defaultMinListHeaderHeight, 0)
            .contentMargins(.horizontal, LivRow.cardInset, for: .scrollContent)
            .contentMargins(.top, 0, for: .scrollContent)
            .modifier(LivCardListFrame())
    }

    /// Say while THIS row is swiped: `lifted` holds its id while the row
    /// is off its rest place, and goes back to nil when it returns.
    ///
    /// SwiftUI has no "this row is swiped" — but a swipe moves the row, and
    /// where it stands against its LIST is the one thing the swipe cannot
    /// hide. At rest a card row starts `cardInset` in from the list's edge;
    /// a swipe either way moves it off that (`LivCardListFrame`).
    ///
    /// AND A ROW THAT SWIPES IS `LivCards.swipeRow` TALL, one line or two,
    /// so iOS draws its actions with the word under the icon.
    func livSwipeLift(_ id: some Hashable, _ lifted: Binding<AnyHashable?>) -> some View {
        modifier(LivSwipeLift(id: AnyHashable(id), lifted: lifted))
            .environment(\.livCardRowFloor, LivCards.swipeRow)
    }
}

private struct LivSwipeLift: ViewModifier {
    let id: AnyHashable
    @Binding var lifted: AnyHashable?
    @Environment(\.livCardListX) private var listX
    @Environment(\.livSwipesLive) private var live
    /// Until when a movement is the desk's settling, not a swipe: the
    /// desk's own spring outlasts the flag that says it is moving.
    @State private var quietUntil = Date.distantPast

    func body(content: Content) -> some View {
        content.onGeometryChange(for: Bool.self) { proxy in
            // At rest a row starts at the card's edge: the list's own x
            // plus the inset its cells stand in by.
            abs(proxy.frame(in: .global).minX - listX - LivRow.cardInset) > 1
        } action: { moved in
            // Let go, the frame reports the rest place at once while the
            // row still slides home — which is exactly when it should start
            // to square off again.
            if !live {
                quietUntil = Date().addingTimeInterval(LivMotion.navSeconds)
                if lifted == id { lifted = nil }
                return
            }
            if moved, Date() < quietUntil { return }
            if moved, lifted != id {
                lifted = id
            } else if !moved, lifted == id {
                lifted = nil
            }
        }
    }
}

/// The last cell of a card list: clear, and there so that no card row is
/// the section's last (see `livCardList`).
struct LivCardListEnd: View {
    var body: some View {
        Color.clear
            .frame(height: 1)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .accessibilityHidden(true)
    }
}

/// The hairline BETWEEN two rows of a card, from where the words start
/// (`LivCards.rule`, 56 in card coordinates) to the card's right edge. None
/// under the last row. A row with no mark passes `LivCards.ruleBare`; the
/// schedule, `LivSchedule.rule`.
struct LivCardRule: View {
    var inset: CGFloat = LivCards.rule

    var body: some View {
        LivHairline().padding(.leading, inset)
    }
}

/// THE ONE HAIRLINE: exactly one device pixel, in `LivTheme.rule` (owner,
/// 2026-09-29: "separators between rows should be dim but visible and
/// consistent").
///
/// It was 0.5pt of `border` (#2E2E2E on a #232323 card). Half a point is a
/// pixel and a half at 3x, so every line landed on the pixel grid
/// differently and drew as one or two antialiased pixels — some rows
/// ruled, some nearly not — and the colour was a whisper to begin with.
struct LivHairline: View {
    @Environment(\.displayScale) private var scale

    var body: some View {
        Rectangle()
            .fill(LivTheme.rule)
            .frame(height: 1 / scale)
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
    /// The least a row may be: `LivCards.swipeRow` on a row that swipes
    /// (`livSwipeLift`), so its actions draw as Apple Notes' do.
    @Environment(\.livCardRowFloor) private var floor
    @Environment(\.livCardRowLifted) private var lifted
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
                        .font(.system(size: LivType.label))
                        .foregroundStyle(LivTheme.text2)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: LivCards.trailingGap) { trailing }
        }
        .padding(.horizontal, LivCards.padX)
        .padding(.vertical, LivCards.padY)
        .frame(minHeight: max(floor, detail == nil ? LivCards.row : LivCards.twoLine))
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if divided {
                LivCardRule(inset: rule)
                    .opacity(lifted ? 0 : 1)
                    .animation(LivMotion.lift, value: lifted)
            }
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
