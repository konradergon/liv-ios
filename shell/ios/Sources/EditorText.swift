// liv iOS — the live markdown text view (design/editor-study.md, phase 1).
// A UITextView on an explicit TextKit 1 stack. Why TextKit 1: the task
// checkbox is DRAWN in the layout manager over the "[ ]" glyphs (their ink
// set clear, their widths kept), which keeps the buffer pure text and the
// layout shift at zero — TextKit 2's custom-drawing route (fragment view
// providers) is heavier for the same result; revisit at phase 5.
//
// Styling is applied as attributes over the SAME plain string the codec
// saves — the marker characters never leave the text (ruling 4), they are
// just dimmed (ruling 3A: identical in every caret state, nothing ever
// reflows on tap).
//
// The toolbar is one scrollable row riding directly above the keyboard
// (owner, 2026-07-31 — the Bear shape). It appears and hides with the
// keyboard's own animation, so nothing ever jolts on its own schedule.

import SwiftUI
import UIKit

// MARK: - attribute keys the layout manager draws from

extension NSAttributedString.Key {
    /// On the 3-char "[ ]" / "[x]" of a task line. Value: NSNumber (checked).
    static let livTaskBox = NSAttributedString.Key("liv.taskBox")
    /// On a whole `[[id|Name]]` token. Value: NSNumber (the target id).
    static let livRef = NSAttributedString.Key("liv.ref")
    /// On the dashes of a `---` line. Value: NSNumber(true). The glyphs
    /// go clear and the layout manager draws a rule across the line —
    /// the same trick the checkbox uses, so the buffer stays plain text.
    static let livRule = NSAttributedString.Key("liv.rule")
    /// On the single "-" or "*" of a bullet line. Value: NSNumber(true).
    /// Same clear-ink trick again: a list marker should read as a point,
    /// not as a hyphen (owner, 2026-08-11).
    static let livBullet = NSAttributedString.Key("liv.bullet")
}

// MARK: - the bridge

/// The one object SwiftUI and the text view share. SwiftUI reads the
/// published state (is a `[[` being typed, what headings exist) and calls
/// the verbs; the view never reaches upward. Everything here is display
/// state — the box is never touched from this file.
final class EditorBridge: ObservableObject {
    /// The unfinished `[[` the caret sits in, or nil. Drives the picker.
    @Published var openLink: OpenLink?
    /// Headings, recomputed off the typing path (see `scheduleOutline`).
    @Published var outline: [OutlineItem] = []

    fileprivate weak var coordinator: MarkdownEditor.Coordinator?

    /// Finish the `[[` being typed with a real target.
    /// Write a link to `id` where the caret is: over the `[[query` being
    /// typed when there is one, else inserted whole.
    func placeLink(id: UInt64, name: String) {
        coordinator?.placeLink(id: id, name: name)
    }

    /// Put the picker away without touching the text — the brackets stay
    /// as typed, which is what they are: literal characters.
    /// Order matters: suppression reads the OPEN link's range, so it must
    /// run before the link is cleared — the other way around, suppression
    /// was always nil and the picker reopened on the very next keystroke
    /// (audit, 2026-08-04).
    func dismissLink() {
        coordinator?.suppressLink()
        openLink = nil
    }

    /// Jump to a heading and put the caret at its start.
    func scroll(to location: Int) { coordinator?.scroll(to: location) }

    /// Drop text in at the caret (a template's resolved body).
    func insert(_ text: String) { coordinator?.insert(text) }
}

// MARK: - fonts

private enum EditorFont {
    // Bumped one step across the board (owner, 2026-07-31: "clearer,
    // larger text") — reading comfort beats density in the editor.
    static let body = UIFont.systemFont(ofSize: 16)
    static let mono = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let codeInline = UIFont.monospacedSystemFont(ofSize: 14.5, weight: .regular)

    /// Where a hyphen's ink centre sits, measured DOWN from the line's
    /// top, for the body font. Read off the font itself so the drawn
    /// rule lands exactly where the literal dashes show when the caret
    /// reveals them — anchoring at half the line height drew the rule
    /// about 1.5pt below the dashes (owner, 2026-08-07).
    static let ruleCenterFromTop: CGFloat = {
        var ch: UniChar = 0x2D  // '-'
        var glyph = CGGlyph(0)
        guard CTFontGetGlyphsForCharacters(body as CTFont, &ch, &glyph, 1) else {
            return body.lineHeight / 2
        }
        var g = glyph
        let ink = CTFontGetBoundingRectsForGlyphs(body as CTFont, .default, &g, nil, 1)
        guard ink.height > 0 else { return body.lineHeight / 2 }
        // Glyph space measures UP from the baseline; the fragment
        // measures DOWN from its top.
        return body.ascender - ink.midY
    }()

    static func heading(_ level: Int) -> UIFont {
        switch level {
        case 1: return .systemFont(ofSize: 25, weight: .bold)
        case 2: return .systemFont(ofSize: 21, weight: .semibold)
        default: return .systemFont(ofSize: 18, weight: .semibold)
        }
    }

    /// One step heavier than the base — **bold** inside an H1 (already
    /// bold) must read HEAVIER than its line, never lighter.
    static func bolded(_ base: UIFont) -> UIFont {
        let raw =
            (base.fontDescriptor.object(forKey: .traits)
                as? [UIFontDescriptor.TraitKey: Any])?[.weight] as? CGFloat ?? 0
        let weight: UIFont.Weight =
            raw >= UIFont.Weight.bold.rawValue
            ? .heavy : raw >= UIFont.Weight.semibold.rawValue ? .bold : .semibold
        return UIFont.systemFont(ofSize: base.pointSize, weight: weight)
    }

    static func italicized(_ base: UIFont) -> UIFont {
        guard let d = base.fontDescriptor.withSymbolicTraits(.traitItalic) else { return base }
        return UIFont(descriptor: d, size: base.pointSize)
    }
}

// MARK: - the styler: text in, attributes over paragraph ranges out

enum MarkStyler {
    /// Restyle `charRange` (expanded to whole paragraphs) in place. Pure
    /// function of the text plus ONE piece of caret state: `revealing`,
    /// the paragraph the caret sits in. A divider on that line shows its
    /// literal dashes — "putting the cursor on a separator should make
    /// it appear as ---" (owner, 2026-08-07). Line-local by design, so
    /// the typing path never rescans the document.
    static func apply(
        to storage: NSTextStorage, in charRange: NSRange, revealing: NSRange? = nil
    ) {
        let n = storage.string as NSString
        guard n.length > 0 else { return }
        let safe = NSRange(
            location: min(charRange.location, n.length),
            length: min(charRange.length, n.length - min(charRange.location, n.length)))
        let range = n.paragraphRange(for: safe)

        storage.beginEditing()
        defer { storage.endEditing() }

        let para = NSMutableParagraphStyle()
        para.lineSpacing = 2
        storage.setAttributes(
            [.font: EditorFont.body, .foregroundColor: LivInk.text, .paragraphStyle: para],
            range: range)

        n.enumerateSubstrings(in: range, options: [.byLines, .substringNotRequired]) {
            _, lineRange, _, _ in
            style(
                line: n.substring(with: lineRange), at: lineRange.location,
                storage: storage,
                revealed: revealing.map { NSLocationInRange(lineRange.location, $0) } ?? false)
        }
    }

    /// The digits inside a `[[…]]` token — the same grammar the codec
    /// parses, so what is tappable and what is stored can never disagree.
    private static func refId(_ line: String, _ token: NSRange) -> UInt64? {
        let n = line as NSString
        guard token.length > 4 else { return nil }
        var digits = ""
        var i = token.location + 2
        while i < NSMaxRange(token) {
            let c = n.character(at: i)
            guard c >= 0x30, c <= 0x39 else { break }
            digits.append(Character(UnicodeScalar(c)!))
            i += 1
        }
        return UInt64(digits)
    }

    private static func style(
        line: String, at base: Int, storage: NSTextStorage, revealed: Bool = false
    ) {
        let shape = MarkScan.shape(line)
        let lineLen = (line as NSString).length

        func abs(_ r: NSRange) -> NSRange { NSRange(location: base + r.location, length: r.length) }
        /// A marker is greyed, NEVER resized. It used to be set to 12pt
        /// mono, which made it a different size from the text it belongs
        /// to and — because a line's height follows its tallest font —
        /// changed the LINE's metrics (owner, 2026-08-11: "the # before
        /// titles should be same font/size as the header text"; "the
        /// hyphen is slightly moved up"; "generated things move when
        /// created… should appear exactly where the source is").
        ///
        /// A freshly generated "- [ ] " is 100% marker, so the whole
        /// line was 12pt mono: 14.13pt tall instead of body's 18.84.
        /// The line shrank the moment the marker appeared, every line
        /// below jumped, and the drawn box — anchored to BODY metrics —
        /// no longer matched the risen hyphen. Typing one character
        /// brought the body font back and everything moved again.
        func dim(_ r: NSRange, font: UIFont = EditorFont.body) {
            guard r.length > 0 else { return }
            storage.addAttributes(
                [.font: font, .foregroundColor: LivInk.muted], range: abs(r))
        }

        var contentFont = EditorFont.body
        switch shape.block {
        case .heading(let level):
            contentFont = EditorFont.heading(level)
            storage.addAttribute(
                .font, value: contentFont,
                range: abs(NSRange(location: 0, length: lineLen)))
            // The hash wears the heading's own font, so it sits on the
            // same baseline at the same size as the words beside it.
            dim(shape.marker, font: contentFont)
        case .bullet:
            dim(shape.marker)
            // The dash's ink goes clear and a point is drawn in its
            // place; the trailing space keeps its width, so the text
            // still starts exactly where the source says it does.
            storage.addAttributes(
                [.foregroundColor: UIColor.clear, .livBullet: NSNumber(value: true)],
                range: abs(NSRange(location: shape.indent, length: 1)))
        case .ordered:
            dim(shape.marker)
        case .task(let checked):
            dim(NSRange(location: 0, length: shape.marker.length))
            if let box = shape.box {
                // The glyphs keep their widths; the ink goes clear and the
                // layout manager draws the box in their rect.
                storage.addAttributes(
                    [.foregroundColor: UIColor.clear, .livTaskBox: NSNumber(value: checked)],
                    range: abs(box))
            }
            if checked {
                let content = NSRange(
                    location: shape.marker.length, length: lineLen - shape.marker.length)
                if content.length > 0 {
                    storage.addAttributes(
                        [
                            .foregroundColor: LivInk.muted,
                            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                            .strikethroughColor: LivInk.muted,
                        ], range: abs(content))
                }
            }
        case .quote:
            dim(shape.marker)
            let content = NSRange(
                location: shape.marker.length, length: lineLen - shape.marker.length)
            if content.length > 0 {
                storage.addAttribute(.foregroundColor, value: LivInk.text2, range: abs(content))
            }
        case .rule:
            // A divider is a LINE, not three grey dashes — except under
            // the caret, where it is EDITABLE and shows its source, the
            // same way every other marker stays visible (owner,
            // 2026-08-07). Off the caret: clear the ink (widths kept,
            // buffer untouched) and let the layout manager draw the rule
            // — the checkbox's own mechanism.
            //
            // The hidden form must not wrap. A run of 50+ dashes wrapped
            // onto a second row whose characters are invisible, so the
            // note showed the rule followed by a blank gap nobody could
            // explain (review, 2026-08-06). The characters are invisible
            // anyway, so clipping them costs nothing.
            if revealed {
                // Muted ink, BODY font — not the small marker font. A
                // font change resizes the line, so the page jumped ~2pt
                // every time the caret entered or left the divider, and
                // the drawn rule could never sit where the dashes sat
                // (found measuring, 2026-08-07).
                storage.addAttribute(
                    .foregroundColor, value: LivInk.muted,
                    range: abs(NSRange(location: 0, length: lineLen)))
            } else {
                let ruleStyle = NSMutableParagraphStyle()
                ruleStyle.lineSpacing = 2
                ruleStyle.lineBreakMode = .byClipping
                let whole = NSRange(location: 0, length: lineLen)
                storage.addAttributes(
                    [
                        .foregroundColor: UIColor.clear,
                        .livRule: NSNumber(value: true),
                        .paragraphStyle: ruleStyle,
                    ],
                    range: abs(whole))
            }
        case .body:
            break
        }

        for run in MarkScan.inline(line, from: shape.marker.length) {
            switch run {
            case .marker(let r):
                dim(r)
            case .bold(let r):
                if r.length > 0 {
                    storage.addAttribute(
                        .font, value: EditorFont.bolded(contentFont), range: abs(r))
                }
            case .italic(let r):
                if r.length > 0 {
                    storage.addAttribute(
                        .font, value: EditorFont.italicized(contentFont), range: abs(r))
                }
            case .strike(let r):
                if r.length > 0 {
                    storage.addAttributes(
                        [
                            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                            .strikethroughColor: LivInk.text3,
                        ], range: abs(r))
                }
            case .code(let r):
                if r.length > 0 {
                    storage.addAttributes(
                        [
                            .font: EditorFont.codeInline,
                            .foregroundColor: LivInk.text2,
                            .backgroundColor: LivInk.panel2,
                        ], range: abs(r))
                }
            case .refToken(let whole, let name):
                // The link reads as a value: name (or id) in accent, the
                // bracket/id plumbing dimmed. The livRef attribute is what
                // makes a tap open the target (phase 2).
                dim(whole)
                if let id = refId(line, whole) {
                    storage.addAttribute(
                        .livRef, value: NSNumber(value: id), range: abs(whole))
                }
                if let name, name.length > 0 {
                    storage.addAttributes(
                        [.font: EditorFont.body, .foregroundColor: LivInk.accent],
                        range: abs(name))
                }
            }
        }
    }
}

// MARK: - the layout manager: draws the task checkboxes

final class LivLayoutManager: NSLayoutManager {
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.livRule, in: charRange) { value, range, _ in
            guard (value as? NSNumber)?.boolValue == true else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = boundingRect(forGlyphRange: glyphs, in: container)
            rect.origin.x += origin.x
            rect.origin.y += origin.y
            // Full width of the text container, not of the three dashes:
            // a divider divides the page.
            //
            // Anchored to the TOP of the line, not its middle. Every
            // styled paragraph carries lineSpacing 2, and TextKit adds
            // that 2pt to the bottom of a line only when another line
            // follows it — so the moment you pressed Return after a
            // hand-typed `---` the box grew and the rule dropped 1pt
            // (owner, 2026-08-06). The top of the line does not move.
            // x and width must measure from the same edge. They did not:
            // x started at the container edge while the width subtracted
            // the text's own side padding, so the rule poked 3pt past the
            // text on the left and stopped 7pt short on the right
            // (review, 2026-08-06).
            let inset: CGFloat = 2
            let line = CGRect(
                x: origin.x + container.lineFragmentPadding + inset,
                y: rect.minY + EditorFont.ruleCenterFromTop - 0.5,
                width: container.size.width - container.lineFragmentPadding * 2 - inset * 2,
                height: 1)
            LivInk.muted.setFill()
            UIBezierPath(rect: line).fill()
        }
        storage.enumerateAttribute(.livBullet, in: charRange) { value, range, _ in
            guard (value as? NSNumber) != nil else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = boundingRect(forGlyphRange: glyphs, in: container)
            rect.origin.x += origin.x
            rect.origin.y += origin.y
            // Centred on the line's own height, exactly as the box is —
            // markers carry the body font now, so the two agree.
            let side: CGFloat = 5
            let dot = CGRect(
                x: rect.midX - side / 2,
                y: rect.minY + EditorFont.body.lineHeight / 2 - side / 2,
                width: side, height: side)
            LivInk.text2.setFill()
            UIBezierPath(ovalIn: dot).fill()
        }
        storage.enumerateAttribute(.livTaskBox, in: charRange) { value, range, _ in
            guard let checked = (value as? NSNumber)?.boolValue else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = boundingRect(forGlyphRange: glyphs, in: container)
            rect.origin.x += origin.x
            rect.origin.y += origin.y
            // A 15pt box, centred on the line's own height rather than
            // on the glyph box — same lineSpacing trap as the rule above.
            let side: CGFloat = 15
            let box = CGRect(
                x: rect.midX - side / 2,
                y: rect.minY + EditorFont.body.lineHeight / 2 - side / 2,
                width: side, height: side)
            let path = UIBezierPath(roundedRect: box, cornerRadius: 4.5)
            if checked {
                LivInk.accent.setFill()
                path.fill()
                let check = UIBezierPath()
                check.move(to: CGPoint(x: box.minX + 3.6, y: box.midY + 0.4))
                check.addLine(to: CGPoint(x: box.minX + 6.2, y: box.maxY - 3.6))
                check.addLine(to: CGPoint(x: box.maxX - 3.4, y: box.minY + 4.2))
                check.lineWidth = 1.8
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                LivInk.onAccent.setStroke()
                check.stroke()
            } else {
                path.lineWidth = 1.5
                LivInk.muted.setStroke()
                path.stroke()
            }
        }
    }
}

// MARK: - the text view

final class MarkdownTextView: UITextView {
    /// Clearance for the floating circles the title starts below.
    /// Clearance above the title, measured from the top of the text
    /// view. It has to clear the floating circles the desk hangs over
    /// the note — at 54 the title sat about 8pt under them, which read
    /// as crowded (owner, 2026-08-10: "titles in documents could still
    /// use some breathing room").
    private static let titleTop: CGFloat = 78
    private static let gutter: CGFloat = 15
    /// Between the title and the first line of the note. At 6 the note
    /// began almost against its own name.
    private static let titleGap: CGFloat = 20
    /// Embedded in a record card there is no floating bottom bar to
    /// clear and no title to reserve room for — the card supplies both.
    private static let embeddedTop: CGFloat = 4
    private static let embeddedBottom: CGFloat = 8

    /// A NOTE shows its title inside this scroll view. A record's notes
    /// do not: the name is edited above them by the card, and a second
    /// name field would be a lie about what you were editing. The flag
    /// is `let` — a view cannot grow or lose a title mid-life, and
    /// making it settable would invite exactly the inset mutation during
    /// layout that once blanked the whole document.
    let showsTitle: Bool

    /// The note's title, living INSIDE this scroll view (owner,
    /// 2026-08-01 — Obsidian's layout). A UITextView is a UIScrollView, so
    /// a subview placed in the space `textContainerInset.top` reserves
    /// scrolls with the body: the title starts below the floating circles
    /// and slides up under them as you read. A separate SwiftUI header
    /// could never do that — it would stay pinned.
    let titleView: UITextView = {
        let v = UITextView()
        v.isScrollEnabled = false
        v.backgroundColor = .clear
        v.font = .systemFont(ofSize: LivType.hero, weight: .bold)
        v.textColor = LivInk.text
        v.textContainerInset = .zero
        v.textContainer.lineFragmentPadding = 0
        v.returnKeyType = .done
        v.autocorrectionType = .no
        v.accessibilityLabel = "Note title"
        v.accessibilityIdentifier = "note.title"
        return v
    }()

    /// The derived title, in grey, when no name cell exists.
    let titlePrompt: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: LivType.hero, weight: .bold)
        l.textColor = LivInk.muted
        l.numberOfLines = 3
        l.lineBreakMode = .byTruncatingTail
        l.isUserInteractionEnabled = false
        return l
    }()

    init(showsTitle: Bool = true) {
        self.showsTitle = showsTitle
        let storage = NSTextStorage()
        let layout = LivLayoutManager()
        let container = NSTextContainer(
            size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        backgroundColor = .clear
        font = EditorFont.body
        textColor = LivInk.text
        // Both of these belong to a view that scrolls ITSELF. Embedded,
        // the card's own ScrollView owns the swipe-to-dismiss
        // (scrollDismissesKeyboard) and there is nothing to bounce —
        // setting them here and undoing them in makeUIView was two
        // declarations of one thing.
        keyboardDismissMode = showsTitle ? .interactive : .none
        alwaysBounceVertical = showsTitle
        // Two hyphens must stay two hyphens — smart dashes would eat the
        // "---" rule (and any -- ) as it is typed. Smart quotes stay on;
        // nothing parses quote characters.
        smartDashesType = .no
        // Full-bleed: the text IS the screen. 15pt gutters (10 + the 5pt
        // lineFragmentPadding); the deep bottom inset lets the last lines
        // scroll clear of the floating bottom bar hovering over the text.
        // The TOP inset is recomputed per layout to hold the title.
        textContainerInset = UIEdgeInsets(
            top: showsTitle ? Self.titleTop + Self.titleFloor + Self.titleGap : Self.embeddedTop,
            // Embedded, the text must line up with the card's name field
            // and every inspector row, which sit at 16. The container
            // adds its own 5pt lineFragmentPadding, so 11 + 5 = 16.
            left: showsTitle ? 10 : 11,
            bottom: showsTitle ? 110 : Self.embeddedBottom,
            right: showsTitle ? 10 : 11)
        self.textContainer.lineFragmentPadding = 5
        // A record card is presented OVER a live note tab, so both text
        // views exist at once. One identifier for two live elements
        // makes every scripted check of the editor a coin flip.
        accessibilityLabel = showsTitle ? "Note content" : "Notes"
        accessibilityIdentifier = showsTitle ? "note.editor" : "record.notes"
        if showsTitle {
            addSubview(titleView)
            addSubview(titlePrompt)
        }
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    /// The title's measured height. Kept as state because the top inset
    /// must NOT be written during a layout pass: mutating
    /// textContainerInset re-invalidates text layout from inside
    /// layoutSubviews, and the whole document silently stops drawing
    /// (found live — the note went blank). Layout only positions; this
    /// runs from the update path instead.
    /// The title's minimum height — one line of LivType.hero. Shared
    /// with the initial inset above, which used to repeat the literal.
    static let titleFloor: CGFloat = 32
    private var titleHeight: CGFloat = MarkdownTextView.titleFloor

    func refreshTitleLayout() {
        guard showsTitle else { return }
        let width = max(bounds.width - Self.gutter * 2, 1)
        let fitted = titleView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude))
        let height = max(fitted.height, Self.titleFloor)
        guard abs(height - titleHeight) > 0.5 else {
            placeTitle(width: width)
            return
        }
        titleHeight = height
        textContainerInset.top = Self.titleTop + height + Self.titleGap
        placeTitle(width: width)
    }

    private func placeTitle(width: CGFloat) {
        let frame = CGRect(x: Self.gutter, y: Self.titleTop, width: width, height: titleHeight)
        if titleView.frame != frame {
            titleView.frame = frame
            titlePrompt.frame = frame
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard showsTitle else { return }
        placeTitle(width: max(bounds.width - Self.gutter * 2, 1))
    }
}

// MARK: - the SwiftUI face

/// The representable the NoteEditor embeds. It owns nothing but the view:
/// text and focus flow through the bindings; the save engine stays in
/// NoteEditorModel, untouched.
struct MarkdownEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    /// The note's name cell, edited in the scrolling title line.
    @Binding var title: String
    /// The derived title shown in grey while no name cell exists.
    var titlePrompt: String
    var onTitleCommit: () -> Void
    var editable: Bool
    /// The shared display state (the `[[` in flight, the outline) and the
    /// verbs SwiftUI calls back with.
    var bridge: EditorBridge
    /// A tapped `[[…]]` — the desk opens it as a tab.
    var onOpenRef: (UInt64) -> Void
    /// The toolbar's link key — NoteEditor presents SEARCH.
    var onLink: () -> Void
    /// The toolbar's `+` — NoteEditor raises the insert menu.
    var onInsert: () -> Void
    /// The toolbar's outline key — NoteEditor presents the sheet.
    var onOutline: () -> Void
    /// The toolbar's template key — NoteEditor presents the picker.
    var onTemplate: () -> Void
    /// A note carries its title inside the scroll view; a record's notes
    /// are titled by the card above them.
    var showsTitle: Bool = true
    /// EMBEDDED: the text view stops scrolling itself and grows to its
    /// content, so it can sit inside the card's own ScrollView. Two
    /// scroll views nested is the fight that has bitten this codebase
    /// before (HourGridDrag, PanelDrag); the answer here is to have only
    /// one — the card's.
    var embedded: Bool = false

    func makeUIView(context: Context) -> MarkdownTextView {
        let view = MarkdownTextView(showsTitle: showsTitle)
        view.isScrollEnabled = !embedded
        view.delegate = context.coordinator
        context.coordinator.install(on: view)
        if showsTitle { view.titleView.delegate = context.coordinator.title }
        bridge.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: MarkdownTextView, context: Context) {
        context.coordinator.parent = self
        view.isEditable = editable
        if view.showsTitle {
            view.titleView.isEditable = editable
            if view.titleView.text != title {
                view.titleView.text = title
                view.setNeedsLayout()
            }
            if view.titlePrompt.text != titlePrompt {
                view.titlePrompt.text = titlePrompt
            }
            view.titlePrompt.isHidden = !title.isEmpty
            view.refreshTitleLayout()
        }
        if view.text != text {
            // Programmatic set (load, conflict swap, re-apply): keep the
            // caret sane. Styling arrives via the storage delegate — every
            // character mutation flows through it.
            let selected = view.selectedRange
            view.text = text
            let n = (text as NSString).length
            view.selectedRange = NSRange(location: min(selected.location, n), length: 0)
            // A load or a conflict swap is a whole new document: the
            // outline has to catch up too (it is not on the typing path,
            // so nothing else recomputes it here).
            context.coordinator.scheduleOutline(text)
        }
        if focused, !view.isFirstResponder, view.window != nil, editable {
            view.becomeFirstResponder()
        }
    }

    /// How tall the text wants to be. Only asked when embedded; a
    /// full-screen note keeps its own scrolling and fills what it is
    /// given. A floor keeps an empty notes field tappable.
    func sizeThatFits(
        _ proposal: ProposedViewSize, uiView: MarkdownTextView, context: Context
    ) -> CGSize? {
        guard embedded else { return nil }
        let width = proposal.width ?? uiView.bounds.width
        guard width > 0 else { return nil }
        let fitted = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(fitted.height, 88))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: coordinator

    final class Coordinator: NSObject, UITextViewDelegate, NSTextStorageDelegate,
        UIGestureRecognizerDelegate
    {
        var parent: MarkdownEditor
        private weak var view: MarkdownTextView?
        /// Character edits made during IME composition (CJK etc.) — styled
        /// only when the composition commits, so the input system's marked
        /// text is never touched mid-flight.
        private var pendingIME: NSRange?
        /// A `[[` the user dismissed: the picker stays away until the caret
        /// leaves that token, so Escape means escape.
        private var suppressedLink: NSRange?
        private var outlineWork: DispatchWorkItem?
        /// The title line has its own delegate so none of the body's text
        /// machinery (styling, the [[ tracker, the outline) ever sees it.
        let title = TitleDelegate()

        init(_ parent: MarkdownEditor) { self.parent = parent }

        func install(on view: MarkdownTextView) {
            self.view = view
            title.onChange = { [weak self, weak view] text in
                self?.parent.title = text
                view?.titlePrompt.isHidden = !text.isEmpty
                view?.refreshTitleLayout()
            }
            title.onCommit = { [weak self] in self?.parent.onTitleCommit() }
            // Return in the title commits and drops into the body — the
            // title is one line of intent, not a place to live.
            title.onReturn = { [weak self] in
                guard let self, let view = self.view else { return }
                view.titleView.resignFirstResponder()
                view.becomeFirstResponder()
                view.selectedRange = NSRange(location: 0, length: 0)
            }
            // Styling rides the STORAGE, not the caret: every character
            // mutation (typing, paste, drop, undo, programmatic replace)
            // flows through didProcessEditing with the range that actually
            // changed. This is what keeps styling a pure function of the
            // text under multi-paragraph edits — the audit's top finding.
            view.textStorage.delegate = self
            // The toolbar rides directly above the keyboard, horizontally
            // scrollable — the Bear shape, by the owner's word 2026-07-31
            // (§6 rev 3; this reverses rev 2's hidden-Aa model, which the
            // owner tried and rejected). It appears and hides with the
            // keyboard's own animation, so nothing ever jolts on its own.
            view.inputAccessoryView = EditorToolbar(embedded: !view.showsTitle) {
                [weak self] verb in
                self?.perform(verb)
            }
            // Checkbox taps: the recognizer only RECEIVES touches that land
            // on a drawn box, so caret placement everywhere else is native.
            let tap = UITapGestureRecognizer(target: self, action: #selector(boxTapped(_:)))
            tap.delegate = self
            view.addGestureRecognizer(tap)
        }

        // MARK: text flow

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorage.EditActions,
            range editedRange: NSRange, changeInLength delta: Int
        ) {
            // Attribute-only edits are our own restyle re-entering — skip,
            // or this recurses forever.
            guard editedMask.contains(.editedCharacters) else { return }
            if view?.markedTextRange != nil {
                pendingIME = pendingIME.map { NSUnionRange($0, editedRange) } ?? editedRange
                return
            }
            apply(around: editedRange, to: textStorage)
        }

        /// The paragraph whose divider is currently shown as dashes
        /// because the caret is on it. nil = no divider revealed.
        private var revealedRule: NSRange?

        /// Reveal follows the caret: entering a divider line restyles it
        /// to its literal dashes, leaving restyles it back to a drawn
        /// line. One runloop hop — the selection callback fires inside
        /// the edit cycle, where storage edits are not safe (the same
        /// rule setOpenLink documents below).
        private func updateRuleReveal(_ textView: UITextView) {
            let n = textView.text as NSString
            var fresh: NSRange?
            let sel = textView.selectedRange
            if sel.length == 0, n.length > 0 {
                let para = n.paragraphRange(
                    for: NSRange(location: min(sel.location, n.length), length: 0))
                var lineRange = para
                if lineRange.length > 0,
                    n.character(at: NSMaxRange(lineRange) - 1) == 0x0A
                {
                    lineRange.length -= 1
                }
                if case .rule = MarkScan.shape(n.substring(with: lineRange)).block {
                    fresh = para
                }
            }
            guard fresh != revealedRule else { return }
            let stale = revealedRule
            revealedRule = fresh
            DispatchQueue.main.async { [weak self] in
                guard let self, let view = self.view else { return }
                for range in [stale, self.revealedRule].compactMap({ $0 }) {
                    MarkStyler.apply(
                        to: view.textStorage, in: range, revealing: self.revealedRule)
                }
            }
        }

        /// Widened one character each side: a return that SPLITS a line
        /// edits only the newline, but both halves need restyling.
        private func apply(around range: NSRange, to storage: NSTextStorage) {
            let n = (storage.string as NSString).length
            let lo = max(0, min(range.location, n) - 1)
            let hi = min(n, NSMaxRange(range) + 1)
            MarkStyler.apply(
                to: storage, in: NSRange(location: lo, length: hi - lo),
                revealing: revealedRule)
        }

        func textViewDidChange(_ textView: UITextView) {
            // Mid-composition text is the input system's, not ours: no
            // binding push (a half-composed syllable must not autosave).
            guard textView.markedTextRange == nil else { return }
            if let pending = pendingIME {
                pendingIME = nil
                apply(around: pending, to: textView.textStorage)
            }
            parent.text = textView.text
            trackLink(in: textView)
            scheduleOutline(textView.text)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            trackLink(in: textView)
            updateRuleReveal(textView)
        }

        // MARK: the [[ picker

        /// Publish (or clear) the unfinished `[[` the caret sits in. Pure
        /// scan of one line — cheap enough for every keystroke.
        private func trackLink(in textView: UITextView) {
            guard textView.isEditable, textView.selectedRange.length == 0 else {
                setOpenLink(nil)
                return
            }
            let found = MarkScan.openLink(textView.text, caret: textView.selectedRange.location)
            if let suppressed = suppressedLink {
                // Stay quiet until the caret leaves the token it was
                // dismissed on.
                if let found, found.range.location == suppressed.location {
                    setOpenLink(nil)
                    return
                }
                suppressedLink = nil
            }
            setOpenLink(found)
        }

        /// NEVER publish synchronously from a UIKit text callback.
        /// textViewDidChangeSelection fires inside the edit cycle, before
        /// textViewDidChange has pushed the new text up; publishing there
        /// re-enters SwiftUI, updateUIView sees a view newer than its
        /// binding, and it resets the view — which silently ate every
        /// keystroke typed after `[[`. One hop to the next runloop turn is
        /// the whole fix.
        private func setOpenLink(_ link: OpenLink?) {
            guard parent.bridge.openLink != link else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.parent.bridge.openLink != link else { return }
                self.parent.bridge.openLink = link
            }
        }

        /// The search sheet came back with a thing. If a `[[` is being
        /// typed, the token replaces it; otherwise it lands at the caret.
        /// The published range can lapse while the sheet is up — the
        /// text view is no longer first responder — so this rescans
        /// before giving up on it.
        func placeLink(id: UInt64, name: String) {
            if parent.bridge.openLink == nil, let view,
                let fresh = MarkScan.openLink(
                    view.text, caret: view.selectedRange.location)
            {
                parent.bridge.openLink = fresh
            }
            guard parent.bridge.openLink != nil else {
                insert(SpanText.token(id, name: name))
                return
            }
            completeLink(id: id, name: name)
        }

        private func completeLink(id: UInt64, name: String) {
            guard let view, let link = parent.bridge.openLink else { return }
            // The published range can only lag by a runloop hop, but a hop
            // is enough if the buffer moved: verify before replacing, and
            // fall back to a fresh scan at the caret.
            let buffer = view.text as NSString
            var token = link.range
            let intact =
                NSMaxRange(token) <= buffer.length
                && buffer.substring(with: token) == "[[" + link.query
            if !intact {
                guard let fresh = MarkScan.openLink(view.text, caret: view.selectedRange.location)
                else { return }
                token = fresh.range
            }
            // Tapping the picker resigned first responder, so replace()
            // would not fire textViewDidChange — push the text up by hand.
            let result = EditOps.completeLink(
                view.text, token: token, id: id, name: name)
            applyThroughSystem(result, to: view)
            parent.text = view.text
            parent.bridge.openLink = nil
            suppressedLink = nil
            scheduleOutline(view.text)
        }

        func suppressLink() {
            suppressedLink = parent.bridge.openLink?.range
        }

        // MARK: the outline

        /// A whole-document scan, so it runs on a debounce — never on the
        /// typing path (design/editor-study.md phase 1: no whole-note
        /// rescans per keystroke).
        func scheduleOutline(_ text: String) {
            outlineWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let items = livOutline(text)
                if self.parent.bridge.outline != items { self.parent.bridge.outline = items }
            }
            outlineWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }

        /// Insert at the caret, through the system API so undo registers
        /// and the storage delegate styles what arrived.
        func insert(_ text: String) {
            guard let view else { return }
            let sel = view.selectedRange
            let out = (view.text as NSString).replacingCharacters(in: sel, with: text)
            applyThroughSystem(
                EditResult(
                    text: out,
                    selection: NSRange(
                        location: sel.location + (text as NSString).length, length: 0)),
                to: view)
            parent.text = view.text
            scheduleOutline(view.text)
        }

        func scroll(to location: Int) {
            guard let view else { return }
            let n = (view.text as NSString).length
            let target = NSRange(location: min(location, n), length: 0)
            view.selectedRange = target
            view.scrollRangeToVisible(target)
        }

        func textView(
            _ textView: UITextView, shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            guard replacement == "\n", range.length == 0,
                let result = EditOps.returnKey(textView.text, selection: range)
            else { return true }
            applyThroughSystem(result, to: textView)
            return false
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.focused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.focused = false
        }

        /// Inline formatting rides the SELECTION menu: it exists exactly
        /// while there is a selection to format, and leaves with it. No
        /// standing chrome, and the menu is a control everyone already
        /// knows (design/editor-study.md §6 rev 2).
        func textView(
            _ textView: UITextView, editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard range.length > 0, textView.isEditable else { return nil }
            func action(_ title: String, _ symbol: String, _ marker: String) -> UIAction {
                UIAction(title: title, image: UIImage(systemName: symbol)) { [weak self] _ in
                    guard let self, let view = self.view else { return }
                    let selection = view.selectedRange
                    self.applyThroughSystem(
                        EditOps.toggleInline(view.text, selection: selection, marker: marker),
                        to: view)
                }
            }
            let format = UIMenu(
                options: .displayInline,
                children: [
                    action("Bold", "bold", "**"),
                    action("Italic", "italic", "*"),
                    action("Strikethrough", "strikethrough", "~~"),
                    action("Code", "chevron.left.forwardslash.chevron.right", "`"),
                ])
            // Straight after Cut/Copy/Paste, ahead of Look Up and Share:
            // appended at the end it lands three pages into the menu, which
            // is not "one effortless action away".
            var children = suggestedActions
            children.insert(format, at: min(1, children.count))
            return UIMenu(children: children)
        }

        /// Route an EditResult through the UITextInput API as ONE minimal
        /// replacement, so the system registers undo for it.
        private func applyThroughSystem(_ result: EditResult, to textView: UITextView) {
            let old = textView.text as NSString
            let new = result.text as NSString
            var prefix = 0
            while prefix < old.length, prefix < new.length,
                old.character(at: prefix) == new.character(at: prefix)
            { prefix += 1 }
            var suffix = 0
            while suffix < old.length - prefix, suffix < new.length - prefix,
                old.character(at: old.length - 1 - suffix)
                    == new.character(at: new.length - 1 - suffix)
            { suffix += 1 }
            let replaced = NSRange(location: prefix, length: old.length - prefix - suffix)
            let with = new.substring(
                with: NSRange(location: prefix, length: new.length - prefix - suffix))
            guard let start = textView.position(from: textView.beginningOfDocument, offset: replaced.location),
                let end = textView.position(from: start, offset: replaced.length),
                let range = textView.textRange(from: start, to: end)
            else { return }
            textView.replace(range, withText: with)
            let n = (textView.text as NSString).length
            textView.selectedRange = NSRange(
                location: min(result.selection.location, n),
                length: min(result.selection.length, n - min(result.selection.location, n)))
        }

        // MARK: the toolbar verbs

        private func perform(_ verb: StyleVerb) {
            guard let view = view else { return }
            let sel = view.selectedRange
            switch verb {
            case .heading:
                applyThroughSystem(
                    EditOps.setBlock(view.text, selection: sel, verb: .headingCycle), to: view)
            case .bold:
                applyThroughSystem(
                    EditOps.toggleInline(view.text, selection: sel, marker: "**"), to: view)
            case .italic:
                applyThroughSystem(
                    EditOps.toggleInline(view.text, selection: sel, marker: "*"), to: view)
            case .strike:
                applyThroughSystem(
                    EditOps.toggleInline(view.text, selection: sel, marker: "~~"), to: view)
            case .code:
                applyThroughSystem(
                    EditOps.toggleInline(view.text, selection: sel, marker: "`"), to: view)
            case .bullet:
                applyThroughSystem(
                    EditOps.setBlock(view.text, selection: sel, verb: .bullet), to: view)
            case .ordered:
                applyThroughSystem(
                    EditOps.setBlock(view.text, selection: sel, verb: .ordered), to: view)
            case .task:
                applyThroughSystem(
                    EditOps.setBlock(view.text, selection: sel, verb: .task), to: view)
            case .quote:
                applyThroughSystem(
                    EditOps.setBlock(view.text, selection: sel, verb: .quote), to: view)
            case .rule:
                applyThroughSystem(
                    EditOps.setBlock(view.text, selection: sel, verb: .rule), to: view)
            case .indent:
                applyThroughSystem(
                    EditOps.indent(view.text, selection: sel, out: false), to: view)
            case .outdent:
                applyThroughSystem(
                    EditOps.indent(view.text, selection: sel, out: true), to: view)
            case .undo:
                view.undoManager?.undo()
            case .redo:
                view.undoManager?.redo()
            case .link:
                // Straight to search — no "[[" typed into the note first.
                // The whole token is written when something is picked.
                parent.onLink()
            case .insert:
                // Put the keyboard away FIRST, through UIKit — the
                // toolbar is the keyboard's own accessory view, and a
                // SwiftUI focus binding leaves it standing over the menu
                // that is sliding up underneath it.
                view.resignFirstResponder()
                parent.onInsert()
            case .outline:
                parent.onOutline()
            case .template:
                parent.onTemplate()
            case .dismiss:
                view.resignFirstResponder()
            }
        }

        // MARK: checkbox taps

        @objc private func boxTapped(_ gesture: UITapGestureRecognizer) {
            guard let view = view else { return }
            let point = gesture.location(in: view)
            // A tap on a link follows it (Obsidian's shipped iOS grammar —
            // long-press still places the caret through the native loupe).
            if let id = hit(.livRef, at: point)?.value {
                parent.onOpenRef(UInt64(truncating: id))
                return
            }
            guard let result = EditOps.toggleTask(view.text, at: characterIndex(of: point))
            else { return }
            // Toggle WITHOUT stealing focus or moving the caret: this is a
            // control tap, not an edit gesture. Undo still registers if the
            // view is editing; a non-editing toggle goes through storage +
            // binding directly.
            let wasEditing = view.isFirstResponder
            let selected = view.selectedRange
            if wasEditing {
                applyThroughSystem(result, to: view)
                view.selectedRange = selected
            } else {
                // Styling arrives via the storage delegate; the binding
                // push must be explicit (no textViewDidChange for
                // programmatic sets).
                view.text = result.text
                parent.text = result.text
            }
        }

        private func characterIndex(of point: CGPoint) -> Int {
            guard let view = view else { return 0 }
            let inContainer = CGPoint(
                x: point.x - view.textContainerInset.left,
                y: point.y - view.textContainerInset.top)
            return view.layoutManager.characterIndex(
                for: inContainer, in: view.textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil)
        }

        /// Only claim touches GEOMETRICALLY inside a drawn control (plus
        /// small slack). characterIndex alone returns the NEAREST character
        /// for any point — an index-only gate would swallow taps in empty
        /// space below a trailing task line and silently toggle it (the
        /// audit's finding). Everything else stays native text handling.
        private func hit(
            _ key: NSAttributedString.Key, at point: CGPoint, slack: CGFloat = 6
        ) -> (range: NSRange, value: NSNumber)? {
            guard let view = view, (view.text as NSString).length > 0 else { return nil }
            let index = characterIndex(of: point)
            let n = (view.text as NSString).length
            var found: (NSRange, NSNumber)?
            for probe in [index, index - 1, index + 1] where probe >= 0 && probe < n {
                var effective = NSRange(location: 0, length: 0)
                if let value = view.textStorage.attribute(key, at: probe, effectiveRange: &effective)
                    as? NSNumber
                {
                    found = (effective, value)
                    break
                }
            }
            guard let (range, value) = found else { return nil }
            let glyphs = view.layoutManager.glyphRange(
                forCharacterRange: range, actualCharacterRange: nil)
            // A wrapped token spans several line fragments. Test each piece
            // separately — a UNION of pieces is a rectangle that can cover
            // the whole line between them, which made the entire line act
            // like the control (found live: a tap on plain text opened a
            // link two words away).
            var hit = false
            view.layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: view.textContainer
            ) { piece, _ in
                var rect = piece
                rect.origin.x += view.textContainerInset.left
                rect.origin.y += view.textContainerInset.top
                if rect.insetBy(dx: -slack, dy: -slack).contains(point) { hit = true }
            }
            return hit ? (range, value) : nil
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch
        ) -> Bool {
            let point = touch.location(in: view ?? UIView())
            return hit(.livRef, at: point) != nil || hit(.livTaskBox, at: point, slack: 10) != nil
        }
    }
}

// MARK: - the title line's delegate

/// Kept apart from the body's coordinator on purpose: the title is plain
/// text with no markdown, no links and no outline.
final class TitleDelegate: NSObject, UITextViewDelegate {
    var onChange: (String) -> Void = { _ in }
    var onCommit: () -> Void = {}
    var onReturn: () -> Void = {}

    func textViewDidChange(_ textView: UITextView) { onChange(textView.text) }

    func textViewDidEndEditing(_ textView: UITextView) { onCommit() }

    func textView(
        _ textView: UITextView, shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        guard text == "\n" else { return true }
        onReturn()
        return false
    }
}

// MARK: - the toolbar (rides the keyboard's own animation)

/// Everything the editor can do to text, one verb each.
enum StyleVerb {
    case undo, redo, link, insert
    case heading, bold, italic, strike, code
    case task, bullet, ordered, quote, indent, outdent, rule
    case outline, template, dismiss
}

/// One row directly above the keyboard, horizontally scrollable — the
/// owner's 2026-07-31 direction, the Bear shape. The keyboard covers the
/// bottom bar; this row covers nothing else and moves only with the
/// keyboard. The dismiss key is pinned at the right so the way out never
/// scrolls away.
final class EditorToolbar: UIInputView, UIScrollViewDelegate {
    private let onVerb: (StyleVerb) -> Void

    init(embedded: Bool = false, onVerb: @escaping (StyleVerb) -> Void) {
        self.onVerb = onVerb
        super.init(
            frame: CGRect(x: 0, y: 0, width: 0, height: 46), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        // TRANSPARENT (owner, 2026-08-03 — Notesnook): with no background
        // color, `.keyboard` style supplies the system keyboard's own
        // material, so the row reads as part of the keyboard rather than
        // a bar over it. Known delta from rule 2 ("nothing reads
        // through"): with a hardware keyboard the material samples the
        // note behind it — accepted by the owner's explicit ask.
        backgroundColor = nil

        // GROUPED, most-used first, with a hairline between groups —
        // the Notesnook shape the owner asked for (2026-08-13). Fifteen
        // identical squares in a row is a wall; six groups is something
        // the eye can aim at. Link is IN the row, not behind the `+`:
        // it is a daily verb, not an advanced one.
        let groups: [[(String, String, StyleVerb)]] = [
            [
                ("arrow.uturn.backward", "Undo", .undo),
                ("arrow.uturn.forward", "Redo", .redo),
            ],
            [
                ("bold", "Bold", .bold),
                ("italic", "Italic", .italic),
                ("strikethrough", "Strikethrough", .strike),
            ],
            [("link", "Link", .link)],
            [
                ("textformat.size", "Heading", .heading),
                ("checkmark.square", "Task list", .task),
                ("list.bullet", "Bulleted list", .bullet),
                ("list.number", "Numbered list", .ordered),
            ],
            [
                ("increase.indent", "Indent", .indent),
                ("decrease.indent", "Outdent", .outdent),
            ],
            [
                ("text.quote", "Quote", .quote),
                ("chevron.left.forwardslash.chevron.right", "Code", .code),
                ("minus", "Divider", .rule),
            ],
        ]
        // Behind the `+`: what is NOT universal. Template and Outline are
        // Liv's own tools rather than ways to shape text, and this is
        // where anything advanced lands later (the owner named maths).
        //
        // Embedded in a record card, neither has a door: Outline scrolls
        // a view whose scrolling is switched off, and Template would land
        // a document's boilerplate in a task. A menu item that does
        // nothing is a lie, so the `+` itself goes away there.
        // The `+` opens the app's ONE menu, sliding up (Menu.swift). It
        // was a UIKit UIMenu — a fourth look for the same idea, and the
        // only one that could not follow the house motion.
        var keys: [UIView] = []
        if !embedded {
            let plus = UIButton(type: .system)
            plus.setImage(
                UIImage(
                    systemName: "plus",
                    withConfiguration: UIImage.SymbolConfiguration(
                        pointSize: 17, weight: .medium)),
                for: .normal)
            plus.tintColor = LivInk.accent
            plus.accessibilityLabel = "Insert"
            plus.addAction(
                UIAction { [onVerb] _ in onVerb(.insert) }, for: .touchUpInside)
            NSLayoutConstraint.activate([
                plus.widthAnchor.constraint(greaterThanOrEqualToConstant: 46)
            ])
            keys.append(plus)
            keys.append(rule())
        }
        for (i, group) in groups.enumerated() {
            if i > 0 { keys.append(rule()) }
            keys += group.map { (symbol, access, verb) in
                key(symbol, access) { [weak self] in self?.onVerb(verb) }
            }
        }
        let middle = UIStackView(arrangedSubviews: keys)
        middle.axis = .horizontal
        middle.spacing = 0
        middle.alignment = .center
        middle.translatesAutoresizingMaskIntoConstraints = false

        let scroller = UIScrollView()
        scroller.showsHorizontalScrollIndicator = false
        scroller.showsVerticalScrollIndicator = false
        // This row scrolls HORIZONTALLY only. Without these, the scroll
        // view's automatic safe-area inset (added while the keyboard
        // animates through the home-indicator zone) makes the content
        // taller than the frame and the keys wiggle vertically.
        scroller.alwaysBounceVertical = false
        scroller.contentInsetAdjustmentBehavior = .never
        // The constraints below already make the content exactly as tall
        // as the frame, and the two flags above already refuse a vertical
        // bounce — and the row STILL drifted vertically (owner, twice).
        // So the axis is nailed shut in the one place nothing can argue
        // with: every scroll event puts y back to zero.
        scroller.delegate = self
        // A drag that starts vertical must not drift the row at all.
        scroller.isDirectionalLockEnabled = true
        scroller.translatesAutoresizingMaskIntoConstraints = false
        scroller.addSubview(middle)

        let dismiss = key("keyboard.chevron.compact.down", "Hide keyboard") { [weak self] in
            self?.onVerb(.dismiss)
        }

        let row = UIStackView(arrangedSubviews: [scroller, dismiss])
        row.axis = .horizontal
        row.spacing = 2
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        // No hairline: the keyboard material IS the separation now.
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 0.5),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            row.heightAnchor.constraint(equalToConstant: 45.5),
            middle.topAnchor.constraint(equalTo: scroller.contentLayoutGuide.topAnchor),
            middle.bottomAnchor.constraint(equalTo: scroller.contentLayoutGuide.bottomAnchor),
            middle.leadingAnchor.constraint(equalTo: scroller.contentLayoutGuide.leadingAnchor),
            middle.trailingAnchor.constraint(equalTo: scroller.contentLayoutGuide.trailingAnchor),
            middle.heightAnchor.constraint(equalTo: scroller.frameLayoutGuide.heightAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    /// The vertical lock. Belt over braces: whatever nudges y — an inset
    /// the system adds while the keyboard animates, a rubber-band from a
    /// diagonal flick — is undone in the same frame.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.contentOffset.y != 0 {
            scrollView.contentOffset.y = 0
        }
    }

    /// The hairline BETWEEN two groups of keys — 1pt of ink, short, with
    /// its own breathing room, so it reads as a divider and never as a
    /// key.
    private func rule() -> UIView {
        let holder = UIView()
        let line = UIView()
        line.backgroundColor = LivInk.border
        line.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(line)
        NSLayoutConstraint.activate([
            holder.widthAnchor.constraint(equalToConstant: 13),
            line.widthAnchor.constraint(equalToConstant: 1),
            line.heightAnchor.constraint(equalToConstant: 22),
            line.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
            line.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
        ])
        return holder
    }

    private func key(
        _ symbol: String, _ access: String, action: @escaping () -> Void
    ) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(
            UIImage(
                systemName: symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)),
            for: .normal)
        button.accessibilityLabel = access
        button.tintColor = LivInk.text2
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 46)
        ])
        return button
    }
}
