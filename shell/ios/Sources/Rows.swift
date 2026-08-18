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
        HStack(spacing: 12) {
            LivIcon(glyph: glyph, color: tint ?? LivTheme.text2, size: 20)
                .frame(width: 22)
            Text(title)
                .font(.system(size: LivType.strong))
                .foregroundStyle(untitled ? LivTheme.text2 : LivTheme.text)
                .lineLimit(1)
            Spacer(minLength: 10)
            trailing
        }
        .padding(.horizontal, 2)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if divided {
                Rectangle()
                    .fill(LivTheme.border)
                    .frame(height: 0.5)
                    // Starts where the TEXT starts: an inset hairline
                    // groups the rows, a full-width one cuts the screen
                    // into slabs.
                    .padding(.leading, 36)
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
struct LivRowFact: View {
    let text: String
    var emphasis: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: LivType.label).monospacedDigit())
            .foregroundStyle(emphasis ? LivTheme.text : LivTheme.text2)
            .lineLimit(1)
    }
}
