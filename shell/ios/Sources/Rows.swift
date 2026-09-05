import SwiftUI

// MARK: - the one list row (surface pass, owner 2026-08-18)

/// Every list in the app draws its rows through here.
///
/// The brief was "quiet, effortless, obvious", with ClickUp, Linear and
/// Notion as the level to match. What those have in common in a list is
/// restraint that is easy to name: ONE line of text at ordinary size, a
/// small icon that is not shouting, a fact on the right in the quietest
/// ink, a hairline that starts where the text starts, and nothing else —
/// no chevrons, no counts, no second row of chips.
///
/// **Colour only where it tells things apart** (owner, 2026-08-18). A
/// list of documents is all one kind, so its glyph is monochrome; Today,
/// Everything and the calendar mix tasks with events with notes, and
/// there the kind's colour is doing work. `tint: nil` is the quiet one.
struct LivListRow<Trailing: View>: View {
    let glyph: LivGlyph
    /// The kind's colour, or nil for the quiet monochrome glyph.
    var tint: Color? = nil
    let title: String
    /// A nameless thing reads in the muted ink, never in full strength.
    var untitled = false
    /// The hairline under the row. The LAST row in a group passes false —
    /// a line with nothing under it is a line that ends the screen.
    var divided = true
    @ViewBuilder var trailing: Trailing

    var body: some View {
        // ON THE ROW GRID, like every other row in the app.
        //
        // This drew its own numbers — a 22pt glyph slot, 12pt of air, and
        // 2pt of padding around the whole thing — inside containers that
        // pad 18. So its words began at 54 by coincidence while its
        // hairline, which asks for `LivRow.hairline` (54, measured from
        // the SCREEN), was applied INSIDE that inset frame and landed at
        // 72. Measured off notes.png: the line missed the words it
        // divides by eighteen points, down every list in the app.
        //
        // The tokens are the same ones the Inbox row uses, so there is
        // one spine now: mark 24, gap 14, words and hairline at 54.
        HStack(spacing: LivRow.markGap) {
            // A STEP DOWN from the title. The glyph was `text2`, the
            // same ink as the title beside it, so a row had no first and
            // second voice at all — and with most titles being the
            // placeholder "Untitled" (also text2) three things on the
            // row read at one strength.
            LivIcon(glyph: glyph, color: tint ?? LivTheme.text3, size: 19)
                .frame(width: LivRow.mark)
            Text(title)
                .font(.system(size: LivType.strong))
                .foregroundStyle(untitled ? LivTheme.text2 : LivTheme.text)
                .lineLimit(1)
            Spacer(minLength: 10)
            trailing
        }
        .frame(minHeight: LivRow.height)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if divided {
                Rectangle()
                    .fill(LivTheme.border)
                    .frame(height: 0.5)
                    // Starts where the TEXT starts: an inset hairline
                    // groups the rows, a full-width one cuts the screen
                    // into slabs. Measured from the ROW's own leading
                    // edge, which is already inside the margin — hence
                    // the subtraction, exactly as the Inbox does it.
                    .padding(.leading, LivRow.hairline - LivRow.margin)
            }
        }
    }
}

extension LivListRow where Trailing == EmptyView {
    init(glyph: LivGlyph, tint: Color? = nil, title: String, untitled: Bool = false, divided: Bool = true) {
        self.init(
            glyph: glyph, tint: tint, title: title, untitled: untitled, divided: divided,
            trailing: { EmptyView() })
    }
}

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
    var emphasis: Bool = false

    var body: some View {
        // THE ROW'S SECOND VOICE, and it has to sound like one. This was
        // `label` (16) in `text2` — one step under an 18pt title in the
        // SAME ink, which on a list of placeholder titles meant twelve
        // identical-looking pairs down the screen. A fact is caption
        // (14) in text3; only an emphasised one comes forward.
        Text(text)
            .font(.system(size: LivType.caption).monospacedDigit())
            .foregroundStyle(emphasis ? LivTheme.text : LivTheme.text3)
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
    /// Rows inside a card are already clipped by the card, so they take
    /// the square fill; a standalone row rounds its own corners.
    var radius: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(configuration.isPressed ? LivTheme.pressed : .clear))
            .contentShape(Rectangle())
    }
}

extension View {
    /// The whole app's row press. Written as a modifier so a row that is
    /// NOT a button (a `.onTapGesture` row, a swipe row) can still be
    /// converted without changing its shape.
    func livRowPress(radius: CGFloat = 0) -> some View {
        buttonStyle(LivPress(radius: radius))
    }
}

// MARK: - the card (surface pass 2)

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
struct LivCard<Content: View>: View {
    /// A quiet heading above the card. Outside it, like the references:
    /// a label inside a card is a row that cannot be tapped.
    var label: String? = nil
    var inset: CGFloat = LivRow.cardInset
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let label {
                SectionLabel(label)
                    .padding(.horizontal, inset + 4)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LivTheme.surface)
                .clipShape(
                    RoundedRectangle(cornerRadius: LivTheme.radiusLg, style: .continuous))
                .padding(.horizontal, inset)
        }
    }
}

/// The hairline BETWEEN two rows of a card. Inside a card the line never
/// runs to the edge — it starts where the text starts and stops short of
/// the card's own rounded corner, or it draws a chord across it.
struct LivCardRule: View {
    var inset: CGFloat = LivRow.hairline

    var body: some View {
        Rectangle()
            .fill(LivTheme.border)
            .frame(height: 0.5)
            .padding(.leading, inset)
    }
}
