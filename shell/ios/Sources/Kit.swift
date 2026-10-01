// liv iOS — the shared kit (design/ios.md §6–7). Compact density is law:
// the budgets below are CODE, not convention. Chips render neutral, and
// wear a 6pt dot only when they stand for a KIND. Amber = AI presence — the Inbox
// proposal capsule is the app's ONE in-app badge.

import SwiftUI

// MARK: - SectionLabel

/// The two header tiers. SCREEN is a group's name over a card on the
/// canvas; SHEET is the quieter label over a card on a sheet (Properties,
/// Settings, the record card, the Insert menu).
enum LivHeaderStyle {
    case screen, sheet
}

/// A GROUP'S NAME, over the card that holds it.
///
/// THE CLEARER BOARDS (owner-approved, 2026-09-24) made it a real header:
/// 20 semibold in full ink, where it was 16 medium text2 (owner,
/// 2026-08-06: "headings and UI text are too subtle" — this is that
/// sentence taken all the way). Beside the name, its COUNT in text2;
/// at the right, a red NOTE ("2 late") or Today's red late COUNT, then an
/// optional accessory and an optional fold chevron.
///
/// The note is a short WARNING drawn once for the group, so individual
/// rows do not have to shout; the boards also colour a late row's own
/// date, and that is the row's business, not this.
///
/// NO ACCENT VERB. A tappable count drew as a blue word once (removed
/// 2026-09-15: the only clickable text is a link in a note). A header
/// that folds is tapped as a whole by its caller; a header with a verb
/// ("Accept all") passes a real Button as the accessory.
///
/// ONLY THE NAME IS THE HEADER, for VoiceOver — never
/// `.accessibilityElement(children: .combine)` here: one wide node the
/// height of a header lands inside `drive.sh rows`' band and reads as a
/// row.
struct SectionLabel<Accessory: View>: View {
    let text: String
    var count: String? = nil
    var note: String? = nil
    var late: Int? = nil
    /// nil draws no chevron; true is open (down), false is closed (right).
    var fold: Bool? = nil
    var style: LivHeaderStyle = .screen
    /// The first header under a control strip takes 16 above, not 26.
    var first: Bool = false
    @ViewBuilder var accessory: Accessory

    init(
        _ text: String, count: Int? = nil, note: String? = nil, late: Int? = nil,
        fold: Bool? = nil, style: LivHeaderStyle = .screen, first: Bool = false,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.text = text
        self.count = count.map(String.init)
        self.note = note
        self.late = late
        self.fold = fold
        self.style = style
        self.first = first
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LivHeader.gap) {
            Text(text)
                .font(
                    style == .screen
                        ? .system(size: LivType.strong, weight: .semibold)
                        : .system(size: LivType.label, weight: .medium))
                .foregroundStyle(style == .screen ? LivTheme.text : LivTheme.text2)
                .accessibilityAddTraits(.isHeader)
            if let count {
                Text(count)
                    .font(.system(size: LivType.body).monospacedDigit())
                    .foregroundStyle(LivTheme.text2)
            }
            Spacer(minLength: 0)
            if let note {
                Text(note)
                    .font(.system(size: LivType.label, weight: .medium))
                    .foregroundStyle(LivTheme.red)
            }
            if let late {
                Text("\(late)")
                    .font(.system(size: LivType.body, weight: .medium).monospacedDigit())
                    .foregroundStyle(LivTheme.red)
            }
            accessory
            if let fold {
                LivChevron(fold ? .down : .right)
            }
        }
        // THE HEADING OWNS ITS OWN ROOM (2026-08-21) — vertical AND,
        // since the clearer boards, horizontal: its words sit a fixed
        // step in from the CARD's edge (4 on a screen, landing at 20;
        // 20 on a sheet, landing at 36), so the caller places the card
        // edge and nothing else. Five sites once supplied their own
        // numbers and disagreed five ways (standing rule 3).
        .padding(
            .horizontal,
            (style == .screen ? LivTitle.side : LivHeader.sheetInset) - LivRow.cardInset)
        .padding(
            .top,
            first ? LivHeader.firstTop : (style == .screen ? LivHeader.top : LivHeader.sheetTop))
        .padding(.bottom, style == .screen ? LivHeader.bottom : LivHeader.sheetBottom)
    }
}

extension SectionLabel where Accessory == EmptyView {
    init(
        _ text: String, count: Int? = nil, note: String? = nil, late: Int? = nil,
        fold: Bool? = nil, style: LivHeaderStyle = .screen, first: Bool = false
    ) {
        self.init(
            text, count: count, note: note, late: late, fold: fold, style: style,
            first: first, accessory: { EmptyView() })
    }
}

// MARK: - the one chevron

/// THE ONE CHEVRON: drawn, 14pt, a 2pt stroke, text3 — the boards' own
/// paths on their 24 grid. It replaces SF's `chevron.*` on the surfaces
/// that have boards: SF draws a heavier, taller mark at every weight.
struct LivChevron: View {
    enum Direction { case right, down, up }

    let direction: Direction
    var ink: Color = LivTheme.text3

    init(_ direction: Direction = .right, ink: Color = LivTheme.text3) {
        self.direction = direction
        self.ink = ink
    }

    var body: some View {
        ChevronShape(direction: direction)
            .stroke(
                ink,
                style: StrokeStyle(
                    lineWidth: LivCards.chevronStroke, lineCap: .round, lineJoin: .round))
            .frame(width: LivCards.chevron, height: LivCards.chevron)
            .accessibilityHidden(true)
    }

    private struct ChevronShape: Shape {
        let direction: Direction

        func path(in rect: CGRect) -> Path {
            // The boards' points on a 24 grid. Down and up are wider and
            // shallower than right (11 by 5.5 against 6 by 12), so each is
            // drawn as drawn rather than rotated.
            let points: [CGPoint]
            switch direction {
            case .right: points = [.init(x: 10, y: 6), .init(x: 16, y: 12), .init(x: 10, y: 18)]
            case .down: points = [.init(x: 6.5, y: 9.5), .init(x: 12, y: 15), .init(x: 17.5, y: 9.5)]
            case .up: points = [.init(x: 6.5, y: 14.5), .init(x: 12, y: 9), .init(x: 17.5, y: 14.5)]
            }
            let scale = rect.width / 24
            var path = Path()
            path.addLines(points.map {
                CGPoint(x: rect.minX + $0.x * scale, y: rect.minY + $0.y * scale)
            })
            return path
        }
    }
}

// MARK: - the two titles

/// A SCREEN'S OWN NAME — screen(34), bold, full ink, and an ACCENT full
/// stop after it ("Tasks.", "Thursday."), the clearer boards' signature
/// (owner-approved, 2026-09-24). The stop is the one accent a title
/// carries, and it is skipped after a title that already ends in
/// punctuation (`LivStop`). VoiceOver hears the bare name, as a header.
///
/// `size` is for the other titles that wear the stop — the Workspaces
/// card's 22 — so the stop is one recipe (standing rule 4). Sheet titles
/// (Properties, Settings, Trash, History) and menu headers do not.
///
/// WHY THIS IS A TYPE (2026-09-12). A weight-and-ink census found 149
/// pieces of text drawn in 64 combinations of size, weight and ink, and
/// named six jobs a reader would recognise. A screen's name was copied
/// identically at five sites and a sheet's at three, with no type.
///
/// A ROW'S TITLE had no canonical triple then — seven across 21 sites,
/// and nobody had picked one. The clearer boards picked it (18 regular,
/// full ink; text2 when muted), and it lives in `LivCardRow` now.
///
/// NO WEIGHT RAMP. `Theme.swift` declares sizes and no weights, and the
/// tempting fix is a weight scale beside the type scale. But a weight is
/// never chosen on its own: it is chosen WITH a size and an ink, for a
/// job, so it lives inside the job's own type.
///
/// THE FACE STAYS USABLE ON ITS OWN — the Calendar's title sits inside a
/// Button beside its chevron. A screen that has a title BLOCK (the name,
/// a subtitle, the room around them) uses `LivTitleBlock`, which owns the
/// frame the five callers used to disagree about.
struct LivScreenTitle: View {
    let text: String
    var size: CGFloat = LivType.screen

    init(_ text: String, size: CGFloat = LivType.screen) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Group {
            if LivStop.wanted(after: text) {
                Text(text) + Text(LivStop.mark).foregroundStyle(LivTheme.accent)
            } else {
                Text(text)
            }
        }
        .font(.system(size: size, weight: .bold))
        .foregroundStyle(LivTheme.text)
        .accessibilityLabel(text)
        .accessibilityAddTraits(.isHeader)
    }
}

/// THE ACCENT FULL STOP, as a rule rather than a character someone types.
/// One predicate for the SwiftUI titles and the editor's TextKit title.
enum LivStop {
    static let mark = "."

    /// Not after an empty title, and not after one that already ends in
    /// . ? ! … or : — "Lisbon?." is the stop arguing with the title.
    static func wanted(after text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else {
            return false
        }
        return !".?!…:".contains(last)
    }
}

/// A SCREEN'S TITLE BLOCK — the name, a subtitle 2 under it, and a slot
/// beside the name for `LivBusy` — with the room the boards give it: 6
/// above, 20 either side, 14 below. What comes next (a control, the
/// first card) sits straight on those 14.
///
/// Title and subtitle stay SEPARATE accessibility elements — never
/// `.combine`: the harness reads the subtitle on its own (Today's
/// "unfiled"), and one combined node would sit in `drive.sh rows`' band.
struct LivTitleBlock<Subtitle: View, Accessory: View>: View {
    let title: String
    @ViewBuilder var subtitle: Subtitle
    @ViewBuilder var accessory: Accessory

    init(
        _ title: String, @ViewBuilder subtitle: () -> Subtitle,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle()
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LivTitle.subtitleGap) {
            HStack(spacing: LivHeader.gap) {
                LivScreenTitle(title)
                accessory
            }
            subtitle
                .font(.system(size: LivType.label).monospacedDigit())
                .foregroundStyle(LivTheme.text2)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, LivTitle.top)
        .padding(.horizontal, LivTitle.side)
        .padding(.bottom, LivTitle.bottom)
    }
}

extension LivTitleBlock where Subtitle == Text?, Accessory == EmptyView {
    /// A plain subtitle; nil draws none.
    init(_ title: String, subtitle: String?) {
        self.init(title, subtitle: { subtitle.map { Text($0) } }, accessory: { EmptyView() })
    }
}

/// A SHEET'S OWN NAME — title(22), bold, full ink, and the inset and top
/// room all three callers already gave it.
///
/// Here the room DOES belong to the type: History, Settings and Trash
/// wrote the same `LivRow.cardInset + 4` and the same top 16 as well as
/// the same font and ink, so all four lines were the copy.
struct LivSheetTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: LivType.title, weight: .bold))
            .foregroundStyle(LivTheme.text)
            .padding(.horizontal, LivRow.cardInset + 4)
            .padding(.top, 16)
    }
}

// MARK: - the one search field

/// THE ONE SEARCH FIELD: a magnifier, the words, a clear button, in a
/// filled capsule as tall as a touch. Search's bar and the trash both draw
/// it (standing rule 4); it was Search's own until the trash wanted one
/// (2026-09-29).
struct LivSearchField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: LivType.body))
                .foregroundStyle(LivTheme.text3)
            TextField("Search", text: $text)
                .font(.system(size: LivType.body))
                .foregroundStyle(LivTheme.text)
                .focused(focused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: LivType.body))
                        .foregroundStyle(LivTheme.text2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 14)
        // AS TALL AS A TOUCH. It was 34 against a 44pt touch floor —
        // under Apple's minimum, and visibly shorter than every other
        // control the app puts at the foot.
        .frame(height: LivRow.touch)
        // NO BORDER. Rev 83 took the hairline off the filter chips on the
        // owner's word; a field is the same shape making the same
        // promise, and a fill either reads as a well or it does not.
        .background(Capsule().fill(LivTheme.panel2))
    }
}

// MARK: - ValueChip / AddChip

/// The one chip recipe: a NEUTRAL capsule — one quiet fill, text2 ink,
/// and nothing else.
///
/// ONE DEVICE, NOT TWO (polish pass, 2026-08-30). It carried a fill AND
/// a hairline border, which is two ways of saying the same edge, and
/// between this and `AddChip` that pair reached forty-odd call sites —
/// the single biggest source of visual noise in the app. A filled shape
/// does not also need to be outlined.
///
/// THE DOT IS GONE with it. A chip standing for a thing wore that
/// thing's kind colour as a 6pt circle; the only remaining caller passed
/// one for a reference chip, where the words already name the thing. A
/// coloured dot next to a word that says the same thing is decoration.
struct ValueChip: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        // NEVER 11pt. The chip's text was `micro`, which is the size
        // reserved for a badge — a thing you glance at, not a word you
        // read — and these chips carry area names, project names and
        // dates. The properties card's larger chip went with the card's
        // chips (the clearer boards draw its values as plain words).
        Text(text)
            .font(.system(size: LivType.caption))
            .lineLimit(1)
        .foregroundStyle(LivTheme.text2)
        .padding(.horizontal, LivChip.pad)
        .frame(height: LivChip.height)
        // FLAT, NOT GLASS (the clearer boards, 2026-09-24: "glass is for
        // chrome only"). It wore the bar's glass from 2026-09-06 on the
        // argument that a chip is a thing you act on; but a chip sits in
        // CONTENT — a row, a card — and the boards' one content chip
        // (Unsorted's area guess) is a flat panel2 capsule.
        .background(Capsule().fill(LivTheme.panel2))
    }
}

/// A SEGMENTED CHOICE, in the app's own language.
///
/// It replaces `.pickerStyle(.segmented)`, whose selected thumb measures
/// #6D6D72 — a grey that is not neutral (blue five points over red) and
/// is not in `Palette`, sitting on a #232323 card. It was the single
/// most off-key object in the app, and the only place a control still
/// arrived with a colour nobody here chose.
///
/// THE TASKS BOARD'S SHAPE (2026-09-24): a panel2 track with rounded
/// ends, 32pt segments inside it, and the chosen one on a `thumb` plate
/// in full ink at semibold; the rest medium, text2. No accent, no
/// inversion — the plate is the mark. The track is 38 tall; the touch
/// target is the whole segment, which the track's own 3 of padding
/// surrounds.
///
/// Every option is a Button whose label is EXACTLY its word — the harness
/// taps "All" on Tasks. `trailing` is the slot for a control that is not
/// one of the options (Tasks' "Project" menu); draw it with
/// `LivSegmentFace` so it wears the same face.
struct LivSegment<Value: Hashable, Trailing: View>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    @ViewBuilder var trailing: Trailing

    init(
        options: [(value: Value, label: String)], selection: Binding<Value>,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.options = options
        self._selection = selection
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.value) { option in
                let on = option.value == selection
                // THE LIST UNDER IT SWAPS IN ONE FRAME (owner, 2026-09-29:
                // "apply same solution" — two states, as a fold). This set
                // the selection inside `withAnimation`, which animated
                // everything the choice changed: Tasks crossfaded its old
                // rows out while "No matches" faded in over them. Only the
                // plate moves now (`LivSegmentFace`).
                Button {
                    selection = option.value
                } label: {
                    LivSegmentFace(option.label, on: on)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
            trailing
        }
        .padding(LivSegmented.pad)
        .background(
            RoundedRectangle(cornerRadius: LivSegmented.trackRadius, style: .continuous)
                .fill(LivTheme.panel2))
    }
}

extension LivSegment where Trailing == EmptyView {
    init(options: [(value: Value, label: String)], selection: Binding<Value>) {
        self.init(options: options, selection: selection, trailing: { EmptyView() })
    }
}

/// ONE SEGMENT'S FACE — the word, and the plate when it is chosen. Shared
/// so a segment that is a Menu rather than a Button looks like the rest.
struct LivSegmentFace: View {
    let label: String
    let on: Bool

    init(_ label: String, on: Bool) {
        self.label = label
        self.on = on
    }

    var body: some View {
        Text(label)
            .font(.system(size: LivType.label, weight: on ? .semibold : .medium))
            .foregroundStyle(on ? LivTheme.text : LivTheme.text2)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: LivSegmented.height)
            .background(
                RoundedRectangle(cornerRadius: LivSegmented.radius, style: .continuous)
                    .fill(on ? LivTheme.thumb : .clear))
            .contentShape(Rectangle())
            // The plate's own motion, and only its own — see `LivSegment`.
            .animation(LivMotion.pick, value: on)
    }
}

/// A SWITCH, in the app's own language.
///
/// The two `Toggle(…).tint(accent)` this replaces were the app's LOUDEST
/// stock controls, and a system switch is a saturated slab about 51x31 —
/// on a screen measured at 0.74% saturated pixels against 0.05–0.19%
/// everywhere else, the two of them were most of the difference.
///
/// AND THE LAST ONES SINCE 2026-09-07. This said two `DatePicker`s
/// remained in `Detail.swift` and that replacing them was "real work,
/// not a token change, and it is not done". It was real work: the
/// calendar's month grid moved to `Month.swift` so both screens could
/// draw one grid, and the compact clock became a quarter-hour stepper —
/// its true fault was never the look but that it let you dial 11:47
/// while `CalClock` says times land on quarter hours. No stock control
/// in this app now arrives with a colour or a grammar nobody here
/// chose.
///
/// The colour moves into the TRACK at a quarter strength rather than
/// filling it, so "on" is legible without the control being the
/// brightest thing on the screen. The knob is ink.
struct LivSwitch: View {
    @Binding var isOn: Bool
    /// A switch the app has disabled still has to READ disabled — the
    /// platform dims a stock control for free and a hand-built one gets
    /// nothing.
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button {
            withAnimation(LivMotion.pick) { isOn.toggle() }
        } label: {
            Capsule()
                .fill(isOn ? LivTheme.tint(LivTheme.accent, 0.55) : LivTheme.panel2)
                .frame(width: 46, height: 28)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(isOn ? LivTheme.text : LivTheme.text3)
                        .frame(width: 20, height: 20)
                        .padding(4)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// EDITING A NAME CELL — the rules, once.
///
/// Three surfaces let you type a name: the desk's document title, the
/// record card's field, and (since 2026-09-07) the properties card. The
/// first two each carried their own `storedName` + seed + commit, and
/// the two had already diverged — the desk's version carries two guards
/// that were each bought with a live bug, and the record's carries
/// neither. A third hand-written copy in the inspector would have
/// reintroduced both (standing rule 4).
///
/// These are pure decisions, not a view: each surface keeps its own
/// `@State` draft and its own field, and asks here what to do.
enum LivName {
    /// THE NAME CELL, never `row.title`. The wire title is a derived
    /// display string — "#id" for an empty note, the first content line
    /// for a scrap, the KIND word for anything unnamed — and belongs in
    /// the grey prompt, never in the field you are typing into.
    static func stored(_ row: EntityRow?) -> String {
        (row?.cells ?? []).first { $0.property == "name" }?.value ?? ""
    }

    /// What a commit should do.
    enum Commit: Equatable {
        /// Write this to the name cell.
        case write(String)
        /// Put this back in the field and write nothing — an emptied
        /// field REVERTS, it never erases the name.
        case revert(String)
        /// Nothing to do.
        case ignore
    }

    /// Decide, given what was typed and what the box holds.
    ///
    /// A GONE OR TRASHED ENTITY TAKES NO NAME. After a trash the entity
    /// stops resolving, `stored` reads empty, and a naive equality guard
    /// happily writes the old name back onto the trashed thing — the
    /// stray transaction that broke the chip's Undo (found live,
    /// 2026-08-02). That is why this takes the row and not just a string.
    ///
    /// `pending` is the last value the caller wrote, so a field that
    /// commits twice (blur after submit) does not write twice.
    static func commit(typed raw: String, row: EntityRow?, pending: String? = nil) -> Commit {
        guard let row, row.trashed != true else { return .ignore }
        let stored = stored(row)
        let typed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty { return .revert(stored) }
        guard typed != stored, typed != pending else { return .ignore }
        return .write(typed)
    }

    /// The snapshot moved under us (an undo, another surface). Returns
    /// the value to put in the field, or nil to leave the draft alone.
    ///
    /// COMPARED AGAINST THE OLD STORED NAME. Comparing against the new
    /// one cannot work: by the time the change is observed the property
    /// already reads the new value, so the guard could only ever fire on
    /// an empty field — an external rename froze the title, and a later
    /// commit then silently reverted it (audit, 2026-08-04).
    static func reseed(draft: String, was old: String, now fresh: String) -> String? {
        guard draft != fresh, draft.isEmpty || draft == old else { return nil }
        return fresh
    }

    /// RETURN ENDS A NAME. It does not type a blank line into one.
    ///
    /// Both name fields — the properties panel's and the record card's —
    /// are `TextField(axis: .vertical)` so a long name WRAPS rather than
    /// scrolling sideways. A vertical-axis field treats the return key
    /// as a newline and **never calls `.onSubmit`**, so the
    /// `.submitLabel(.done)` on both of them drew a key that put a line
    /// break in the title and nothing else (owner, 2026-09-15: "entering
    /// title in property card and pressing the confirm button enters a
    /// new line instead of setting title").
    ///
    /// Wrapping is worth keeping and a name is still one line, so the
    /// newline is taken back out and the field gives up focus — which is
    /// where BOTH fields already commit from, so there is one commit and
    /// one write.
    ///
    /// The same rule in one place rather than in two views (standing
    /// rule 4); a paste carrying line breaks reads as the same intent.
    static func endsAt(newlineIn text: inout String) -> Bool {
        guard text.contains(where: \.isNewline) else { return false }
        text = text.filter { !$0.isNewline }
        return true
    }
}

extension View {
    /// `LivName.endsAt` wired to a field: strip the newline, drop focus,
    /// and let the field's existing blur-commit do the write.
    func livNameReturn(
        _ text: Binding<String>, _ focused: FocusState<Bool>.Binding
    ) -> some View {
        onChange(of: text.wrappedValue) { _, _ in
            var typed = text.wrappedValue
            guard LivName.endsAt(newlineIn: &typed) else { return }
            text.wrappedValue = typed
            focused.wrappedValue = false
        }
    }
}

/// A DAY'S NUMBER, AND THE DISC THAT SAYS IT IS THE ONE YOU ARE ON.
///
/// One mark, three readings, no collision possible:
///   selected            — ink disc, number in the ground
///   today, selected     — ACCENT disc, number in `onAccent` (white)
///   today, not selected — accent number, no disc
///
/// The ink disc's number is the GROUND, which reads in both schemes. The
/// accent disc's is `onAccent`, as the Today board draws it and as every
/// other thing on the accent wears — the ground was near-black on the
/// denim in dark, a knock-out that read as a hole. A resting day is full
/// ink (the board's 18/400 text), not text2.
///
/// This is the correction rev 47 made standing (owner: *"today's date is
/// marked by a tiny dot that is completely hidden by a horizontal bar
/// when selected… you have a tendency to make UI elements tiny and
/// subtle. Try to go for the opposite."*). It landed on Today's week
/// strip and nowhere else, so until 2026-09-07 the calendar's month grid
/// still drew the 4pt dot and 2pt rule the owner had just named — two
/// marks for one idea, in one app (standing rule 4).
///
/// ONLY THE NUMBER AND ITS DISC. The two grids are not the same tile:
/// the strip carries a weekday letter, and the month cell carries
/// out-of-month dimming, three busy dots, a long press and its own
/// accessibility label. Each caller keeps its tile; this is the mark
/// they share. The diameter comes in because a month cell cannot carry
/// the strip's 38 — see `LivDay` for the arithmetic.
struct LivDayMark: View {
    let number: Int
    let selected: Bool
    let today: Bool
    var diameter: CGFloat = LivDay.disc
    /// The ink when the day is neither selected nor today — the caller's
    /// own, so the month grid can dim a day outside its month.
    var rest: Color = LivTheme.text

    var body: some View {
        Text("\(number)")
            .font(
                .system(
                    size: LivType.body,
                    weight: (selected || today) ? .semibold : .regular
                )
                .monospacedDigit()
            )
            .foregroundStyle(
                selected
                    ? (today ? LivTheme.onAccent : LivTheme.canvas)
                    : (today ? LivTheme.accent : rest))
            .frame(width: diameter, height: diameter)
            .background(
                Circle()
                    .fill(
                        selected
                            ? (today ? LivTheme.accent : LivTheme.text)
                            : Color.clear))
    }
}

/// THE ONE BUSY MARK.
///
/// The box is merely locked and a retry is scheduled — quiet busyness,
/// never a fault, which is why it is `text3` and not the red.
///
/// It was drawn twice and identically (Today's header and the
/// calendar's), and it was the last untinted system control left after
/// the 2026-09-05 stock-control inventory that produced `LivSwitch` and
/// `LivSegment` above: no `.tint`, so it came out in the system's
/// secondary grey rather than a colour anybody here chose.
///
/// `scaleEffect`, NOT `controlSize` — `controlSize` does not resize a
/// circular `ProgressView` on iOS, so swapping it silently restores the
/// spinner to full size. The 0.7 stays in here rather than in
/// `Theme.swift` because a recipe holds its own geometry, the way
/// `LivSwitch` holds 46x28.
struct LivBusy: View {
    var body: some View {
        ProgressView()
            .scaleEffect(0.7)
            .tint(LivTheme.text3)
    }
}

/// THE TRASH SWIPE, once.
///
/// Soft and undoable at every call site — never a hard delete; the row
/// goes to Trash and comes back from it.
///
/// It was hand-built four times (Everything, Tasks, Notes, Inbox) and
/// three of them passed no `.tint`, so SwiftUI painted them its own
/// ~100%-saturation destructive red — the loudest pixels left in an app
/// whose palette tops out at 62%.
///
/// This returns ONLY THE BUTTON, deliberately, so each site keeps its
/// own `edge:` and its own `allowsFullSwipe:`. Those are not the same:
/// Inbox passes `false` on purpose, so an unrouted capture cannot be
/// thrown away by a thumb that kept going. A helper that wrapped the
/// whole `.swipeActions` container would have flattened that.
@MainActor @ViewBuilder
func livTrashAction(_ action: @escaping () -> Void) -> some View {
    Button(role: .destructive, action: action) {
        livSwipeLabel("Trash", .trash)
    }
    .tint(LivTheme.red)
}

/// A SWIPE BUTTON'S FACE: the app's own glyph in the bubble, its word under
/// it (iOS lays it out so on a `LivCards.swipeRow` row).
///
/// OUR GLYPHS, NOT SF SYMBOLS (owner, 2026-09-29: "the icons in bubbles in
/// rows should be consistent. the trash icon is different from trash in the
/// panel"). A swipe action draws only an `Image`, so the glyph is rendered
/// to one once per kind and kept — white, as a template the bubble tints.
@MainActor
func livSwipeLabel(_ title: String, _ glyph: LivGlyph) -> some View {
    Label {
        Text(title)
    } icon: {
        LivSwipeGlyph.image(glyph)
    }
}

@MainActor
enum LivSwipeGlyph {
    private static var made: [String: UIImage] = [:]

    static func image(_ glyph: LivGlyph) -> Image {
        let key = String(describing: glyph)
        if let hit = made[key] { return Image(uiImage: hit) }
        let renderer = ImageRenderer(
            content: LivIcon(glyph: glyph, color: .white, size: LivCards.glyph))
        renderer.scale = 3
        guard let image = renderer.uiImage?.withRenderingMode(.alwaysTemplate) else {
            return Image(uiImage: UIImage())
        }
        made[key] = image
        return Image(uiImage: image)
    }
}

/// The switch above, as a `ToggleStyle`, so the two call sites keep
/// reading as `Toggle(isOn:) { label }` and only the control changes.
struct LivSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 8)
            LivSwitch(isOn: configuration.$isOn)
        }
    }
}

/// THE FORM CONFIRM: Create, Save — the one filled control on a sheet.
///
/// A primary action earns the accent, and there is exactly one per form,
/// so this is not the kind of colour the polish pass went after. What it
/// went after was the DUPLICATION: `WorkspaceSwitch` carried this shape
/// twice, byte for byte, once for a workspace and once for a filter
/// (standing rule 4 — the same shape drawn from two places is how two
/// shapes start).
struct ConfirmPill: View {
    let label: String
    /// THE VERB AT THE END OF A ROW, rather than at the foot of a form.
    ///
    /// **Nine places wanted this and none of them had it**, so each
    /// wrote an accent word instead: Add (twice), Done, Close all, Put
    /// back, Restore, Accept all, Route them, Create. A bare accent word
    /// is a hyperlink, and the only clickable text in this app is a link
    /// inside a note (owner, 2026-09-15). They were written on nine
    /// different days by someone who only had the one in front of them,
    /// which is what a missing shape costs.
    ///
    /// `value` height (34) rather than `touch` (44): these sit INSIDE a
    /// row that is itself 44 or 52, and a pill as tall as its row reads
    /// as a second row. The text stays `body` — the same word at the
    /// same size, in a capsule.
    var compact: Bool = false
    let action: () -> Void

    init(_ label: String, compact: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.compact = compact
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                // THE APP'S VERB FACE, and as tall as what it sits
                // beside (2026-09-13). It was `label`(16) in a 34pt
                // capsule: under the 44pt touch floor, and SMALLER than
                // the Cancel word next to it — a primary quieter than the
                // way out. `body`/semibold is the face rev 81 settled on
                // for a tappable word, and 44 matches the name field
                // above it in both forms that draw this.
                .font(.system(size: LivType.body, weight: .semibold))
                .foregroundStyle(LivTheme.onAccent)
                .padding(.horizontal, compact ? 14 : 20)
                .frame(height: compact ? LivChip.value : LivRow.touch)
                .background(Capsule().fill(LivTheme.accent))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The chip-shaped add affordance (capture sheet's +Tag +Project row):
/// hollow, muted — never competes with real values.
struct AddChip: View {
    let label: String
    /// The mark it wears. `plus` because adding is what it nearly always
    /// does.
    var symbol: String = "plus"
    let action: () -> Void

    init(_ label: String, symbol: String = "plus", action: @escaping () -> Void) {
        self.label = label
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: LivChip.glyph - 1, weight: .semibold))
                Text(label)
                    .font(.system(size: LivType.label))
                    .lineLimit(1)
            }
            .foregroundStyle(LivTheme.text2)
            .padding(.horizontal, LivChip.addPad)
            .frame(height: LivChip.add)
            // HOLLOW is this chip's whole meaning — it is the ADD
            // affordance, and standing empty beside filled values is how
            // it says so. So it keeps its outline and takes no fill:
            // still one device, the other one.
            .overlay(Capsule().strokeBorder(LivTheme.border2, lineWidth: LivChip.addOutline))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - the one checkbox

/// THE ONE CHECKBOX (the clearer boards, 2026-09-24): a 20pt rounded
/// square, radius 6, stroked 1.7 in text2 while open (text3 when dim — a
/// passed row); DONE is filled in the option's own hue, else green, with
/// a drawn white tick. The same numbers draw the editor's TextKit box
/// (`LivCheck`, and `LivCheck.tickPath` for the tick), so a task line in
/// a note and a task row in a list are one object (standing rule 4).
///
/// AN OPEN BOX IS INK, NOT COLOUR. The ring once wore the status
/// option's hue whether it was ticked or not, so forty-seven open tasks
/// drew forty-seven coloured outlines down the list's left edge — every
/// reference draws that column grey. The hue is what TICKING it means,
/// so it is kept for the filled state and only there.
///
/// The tick is white on green at 2.47:1, under the 3:1 `onAccent` is
/// held to — accepted as drawn (DECISIONS), and not in the palette check.
///
/// Only the drawing: it has no action and no label. `StatusRing` is the
/// toggle; a mark that is not a button (the Tasks "Done" fold) draws this.
struct LivCheckbox: View {
    let done: Bool
    var dim: Bool = false
    var hue: Color? = nil
    var side: CGFloat = LivCheck.size

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: LivCheck.radius * side / LivCheck.size, style: .continuous)
        Group {
            if done {
                shape
                    .fill(hue ?? LivTheme.green)
                    .overlay {
                        TickShape()
                            .stroke(
                                LivTheme.onAccent,
                                style: StrokeStyle(
                                    lineWidth: LivCheck.tickStroke * side / LivCheck.size,
                                    lineCap: .round, lineJoin: .round))
                    }
            } else {
                shape.strokeBorder(
                    dim ? LivTheme.text3 : LivTheme.text2, lineWidth: LivCheck.stroke)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    private struct TickShape: Shape {
        func path(in rect: CGRect) -> Path { Path(LivCheck.tickPath(in: rect)) }
    }
}

extension LivCheck {
    /// The tick, fitted to a box — for SwiftUI (`Path(_:)`) and for the
    /// editor's UIKit drawing (`UIBezierPath(cgPath:)`) alike.
    static func tickPath(in rect: CGRect) -> CGPath {
        let scale = rect.width / size
        let path = CGMutablePath()
        path.addLines(between: tick.map {
            CGPoint(x: rect.minX + $0.x * scale, y: rect.minY + $0.y * scale)
        })
        return path
    }
}

// MARK: - StatusRing

/// THE TASK TOGGLE: `LivCheckbox` as a Button. Hue = the status option's
/// own colour, used only once it is ticked; nil = green.
///
/// `name` is the thing it ticks, so VoiceOver says "Complete Pay rent"
/// rather than a column of identical "Complete"s — the label Tasks'
/// note-line box has always carried.
struct StatusRing: View {
    let done: Bool
    var hue: Color? = nil
    /// Tight variant for a calendar block, which carries its own padding:
    /// the box and its target shrink together, so it never dwarfs the
    /// block it sits in.
    var compact: Bool = false
    /// A passed row's box: text3 rather than text2.
    var dim: Bool = false
    var name: String? = nil
    let action: () -> Void

    init(
        done: Bool, hue: Color? = nil, compact: Bool = false, dim: Bool = false,
        name: String? = nil, action: @escaping () -> Void
    ) {
        self.done = done
        self.hue = hue
        self.compact = compact
        self.dim = dim
        self.name = name
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            LivCheckbox(
                done: done, dim: dim, hue: hue,
                side: compact ? LivCheck.compact : LivCheck.size)
                // THE FINGER, NOT THE INK — and not the LAYOUT either. The
                // box sits in the row's 28 mark column and lays out at 28,
                // so a 52 row stays 52; its hit shape reaches out into the
                // row's padding to the 44 touch floor. (Laid out at 44, it
                // made every title-only row 62.) Compact boxes live inside
                // a 26pt capsule and must not grow at all.
                .frame(
                    width: compact ? LivCheck.compactTarget : LivCards.mark,
                    height: compact ? LivCheck.compactTarget : LivCards.mark)
                .contentShape(
                    Rectangle().inset(by: compact ? 0 : (LivCards.mark - LivRow.touch) / 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var label: String {
        let verb = done ? "Reopen" : "Complete"
        guard let name, !name.isEmpty else { return verb }
        return "\(verb) \(name)"
    }
}

// MARK: - EmptyHint

/// AN EMPTY SURFACE STILL SAYS SOMETHING (owner's clips, 2026-08-20).
///
/// The reference set answers a nothing-here the same way every time: a
/// glyph, a line in full-strength ink saying what is missing, and a
/// quieter line saying what the thing is for. ChatGPT's empty Projects
/// panel is the clearest example of the shape.
///
/// NO BUTTON, though the references have one: Liv's floating bar already
/// carries a `+` on every surface, and a second creation door here would
/// be the same rule written twice (standing rule 4).
///
/// The bare sentence stays the default, because most of the eighteen
/// call sites are a passing state ("This was deleted") rather than a
/// place you have landed and must now start from. Only a surface a user
/// can sit and look at earns the glyph and the button.
/// WHAT AN EMPTY SURFACE SAYS: one or two words, in the muted ink, and
/// nothing else (owner, 2026-09-11: *"Ugly messages littered all over.
/// For example when today is empty, you get a verbose message saying so.
/// Should be two to one word indications, such as 'empty' or similar."*).
///
/// It used to take a `detail` sentence and a 30pt glyph as well, and six
/// surfaces passed all three — so an empty day answered "Nothing
/// scheduled" and then explained, in a sentence that named your six
/// areas, what a day is for. An empty screen is the worst place in the
/// app to teach it: you came to read something and there is nothing, and
/// a paragraph is the app talking about itself.
///
/// THE RULE IS THE TYPE, not prose (standing rule 3). There is nowhere
/// to put the sentence any more, so it cannot come back one surface at a
/// time — which is how it arrived.
///
/// The furnished/unfurnished fork went with it: every empty state now
/// draws at one weight in one ink, so none of them shouts louder than
/// another about having nothing to say.
struct EmptyHint: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: LivType.strong))
            .foregroundStyle(LivTheme.text2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }
}

// MARK: - when something is due, if you did not say

/// The hour a due lands on when nobody picked one: 09:00, the start of
/// the day rather than the minute you happened to be holding the phone
/// (owner, 2026-08-07 — the current time meant a task typed at 23:47 was
/// due at 23:47). One constant, so the date sheet, the capture card and
/// every quick-add row agree.
enum LivDue {
    /// Packed HHMM.
    static let defaultHHMM: Int64 = 900

    /// Does this thing carry a clock time after you edit its date?
    ///
    /// All-day belongs to EVENTS. A holiday is not due at 09:00, so an
    /// all-day event keeps its all-day-ness until you actually touch the
    /// clock. A TASK always has a moment — that is what a task is — so a
    /// task stored without one gets `defaultHHMM` on its next change
    /// (owner, 2026-08-07).
    static func carriesTime(dateOnly: Bool, isEvent: Bool) -> Bool {
        !dateOnly || !isEvent
    }

    /// The default moment on a given day, as a Date, for seeding a
    /// time picker.
    static func defaultTime(on day: Int64) -> Date {
        Civil.date(day: day, hhmm: defaultHHMM) ?? Date()
    }
}

// MARK: - what to call a row

/// The one answer to "what is this called".
///
/// The core answers it now: since 2026-08-07 the snapshot's `title` is
/// the display name — the name cell, else the first line of the content
/// with ALL syntax off (block and inline markers both, services/src/
/// content.rs strip_marker), else "#id". Eight files used to re-derive
/// that, each with its own fallback and its own word for nothing.
/// This is the only one, and it cleans NOTHING — cleaning a title twice
/// was two code bits solving the same problem (owner, 2026-08-07).
///
/// The "#id" the core sends for an entity with no words at all is a
/// placeholder, not a name — no list shows it.
func livRowTitle(_ row: EntityRow) -> String {
    // A NAMELESS ROW SAYS WHAT IT IS, AND WHEN — "Task · 13 Sep 14:32".
    //
    // "Untitled" is Obsidian's word, and Apple Notes' and Notion's: the
    // vault's word for a failure to name. The 2026-09-06 ruling replaced
    // it with the kind's word, which was right and not enough — fourteen
    // rows reading "Task" distinguish each other no better than fourteen
    // reading "Untitled", and the harness had already tripped over
    // exactly that, unable to aim at one of three notes sharing a label.
    // Amended 2026-09-13 on his word: "Unnamed task/event/note should get
    // a sensible name."
    //
    // **THE SHELL NO LONGER PICKS THE WORDS.** The core sends a name that
    // is never empty and never an id, so this returns it — and the muted
    // ink comes from `livRowIsUntitled`, which is now a flag the core
    // sets rather than a string the shell recognises.
    (row.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}

/// THE ROW'S ONE ANCHOR — the thing it is attached to — in one order:
/// project, people, tags, area. Three surfaces carried their own copy of
/// this loop and two of them disagreed on the order (Everything put tags
/// before people). One helper, one order (standing rule 4, 2026-09-06).
///
/// Returns the property too, so a caller can give an AREA its mark.
func livAnchor(of row: EntityRow) -> (property: String, value: String)? {
    for property in ["project", "people", "tags", "area"] {
        let hit = (row.cells ?? []).first {
            $0.property == property && !($0.value ?? "").isEmpty
        }
        if let value = hit?.value, !value.isEmpty { return (property, value) }
    }
    return nil
}

/// WHERE A ROW LIVES, for its second line: its area, which rides the wire
/// with the row (`areaWord`) so the line never arrives a beat late and a
/// row never jumps from 52 to 64; else what it is attached to, which
/// needs the row's cells (`BoxModel.entity` fetches them).
func livPlace(of row: EntityRow) -> String? {
    if let area = row.areaWord, !area.isEmpty { return area }
    return livAnchor(of: row)?.value
}

/// Whether that name was MADE rather than given — asked of the core,
/// which is the only thing that knows.
///
/// It has been wrong twice, both times because the shell was inferring it
/// from the string: once comparing the RESULT against "untitled" in lower
/// case, which never matched, so nameless rows drew at full strength on
/// the one screen built to show them quietly; and once against `"#<id>"`,
/// a placeholder the core stopped sending on 2026-09-13. A fact about a
/// thing is not recoverable from how it reads.
func livRowIsUntitled(_ row: EntityRow) -> Bool {
    row.untitled ?? (row.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

// The icon language — what a row looks like, and the carved chip it
// wears — lives in Glyph.swift.

/// Whether a row has something to TICK: the task kind, or any status at
/// all. Today and the calendar each had their own private copy of this.
///
/// This is deliberately NOT `LivKind.of(row) == .task`. They answer
/// different questions: the kind says what a thing IS, and gives event
/// and file precedence, while this asks only whether there is a status
/// to close. An event with a status is still an event — teal, with
/// a ring on it.
func livCanTick(_ row: EntityRow) -> Bool {
    row.kinds?.contains("task") == true || row.status != nil
}

/// THE ACKNOWLEDGMENT CHIP — what just happened, and Undo when it can be
/// taken back. One view for the desk and Unsorted, which had one each.
///
/// AT THE FOOT, over the bar (owner, 2026-09-22: the undo message
/// appeared "inconveniently at the top"). The thumb that just acted is
/// at the bottom of the screen; the offer to take it back belongs there
/// too. Callers place it with `.livAckChip`.
struct LivAckChip: View {
    let text: String
    var undo: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Text(text)
                .font(.system(size: LivType.body, weight: .medium))
                .foregroundStyle(LivTheme.text)
            if let undo {
                ConfirmPill("Undo", compact: true) { undo() }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(LivTheme.panel2, in: Capsule())
        .overlay(Capsule().strokeBorder(LivTheme.border, lineWidth: 0.5))
    }
}

extension View {
    /// Hang the acknowledgment chip above the bottom bar.
    func livAckChip(_ text: String?, undo: (() -> Void)?) -> some View {
        overlay(alignment: .bottom) {
            if let text {
                LivAckChip(text: text, undo: undo)
                    .padding(.bottom, LivBar.room + LivAir.tight)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
            }
        }
    }
}
