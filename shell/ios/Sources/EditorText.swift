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
// The toolbar is a UIInputView riding the keyboard's own animation —
// chrome rule 4 as narrowed by the owner 2026-07-30. The Aa key swaps the
// system keyboard for the full-height style keyboard (Bear's trick).

import SwiftUI
import UIKit

// MARK: - attribute keys the layout manager draws from

extension NSAttributedString.Key {
    /// On the 3-char "[ ]" / "[x]" of a task line. Value: NSNumber (checked).
    static let livTaskBox = NSAttributedString.Key("liv.taskBox")
}

// MARK: - fonts

private enum EditorFont {
    static let body = UIFont.systemFont(ofSize: 15)
    static let mono = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    static let codeInline = UIFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)

    static func heading(_ level: Int) -> UIFont {
        switch level {
        case 1: return .systemFont(ofSize: 22, weight: .bold)
        case 2: return .systemFont(ofSize: 19, weight: .semibold)
        default: return .systemFont(ofSize: 17, weight: .semibold)
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
    /// function of the text — no caret, no state. Line-local by design, so
    /// the typing path never rescans the document.
    static func apply(to storage: NSTextStorage, in charRange: NSRange) {
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
            style(line: n.substring(with: lineRange), at: lineRange.location, storage: storage)
        }
    }

    private static func style(line: String, at base: Int, storage: NSTextStorage) {
        let shape = MarkScan.shape(line)
        let lineLen = (line as NSString).length

        func abs(_ r: NSRange) -> NSRange { NSRange(location: base + r.location, length: r.length) }
        func dim(_ r: NSRange) {
            guard r.length > 0 else { return }
            storage.addAttributes(
                [.font: EditorFont.mono, .foregroundColor: LivInk.muted], range: abs(r))
        }

        var contentFont = EditorFont.body
        switch shape.block {
        case .heading(let level):
            contentFont = EditorFont.heading(level)
            storage.addAttribute(
                .font, value: contentFont,
                range: abs(NSRange(location: 0, length: lineLen)))
            dim(shape.marker)
        case .bullet, .ordered:
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
            dim(NSRange(location: 0, length: lineLen))
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
                // bracket/id plumbing dimmed. Tap-to-open is phase 2.
                dim(whole)
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
        storage.enumerateAttribute(.livTaskBox, in: charRange) { value, range, _ in
            guard let checked = (value as? NSNumber)?.boolValue else { return }
            let glyphs = glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = boundingRect(forGlyphRange: glyphs, in: container)
            rect.origin.x += origin.x
            rect.origin.y += origin.y
            // A 15pt box, vertically centered on the glyph line.
            let side: CGFloat = 15
            let box = CGRect(
                x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
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
    /// Swapped in by the Aa key; nil = the system keyboard.
    var styleKeyboardShown = false

    init() {
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
        keyboardDismissMode = .interactive
        alwaysBounceVertical = true
        // Two hyphens must stay two hyphens — smart dashes would eat the
        // "---" rule (and any -- ) as it is typed. Smart quotes stay on;
        // nothing parses quote characters.
        smartDashesType = .no
        // left/right 0: the 5pt lineFragmentPadding plus the SwiftUI-side
        // 4pt matches the placeholder's 9pt exactly.
        textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        self.textContainer.lineFragmentPadding = 5
        accessibilityLabel = "Note content"
        accessibilityIdentifier = "note.editor"
    }

    required init?(coder: NSCoder) { fatalError("unused") }
}

// MARK: - the SwiftUI face

/// The representable the NoteEditor embeds. It owns nothing but the view:
/// text and focus flow through the bindings; the save engine stays in
/// NoteEditorModel, untouched.
struct MarkdownEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    /// The style keyboard is up. Owned by the SwiftUI side because the
    /// quiet `Aa` that summons it floats over the note, not in a bar.
    @Binding var styleShown: Bool
    var editable: Bool

    func makeUIView(context: Context) -> MarkdownTextView {
        let view = MarkdownTextView()
        view.delegate = context.coordinator
        context.coordinator.install(on: view)
        return view
    }

    func updateUIView(_ view: MarkdownTextView, context: Context) {
        context.coordinator.parent = self
        view.isEditable = editable
        if styleShown != view.styleKeyboardShown {
            context.coordinator.setStyleKeyboard(styleShown, on: view)
        }
        if view.text != text {
            // Programmatic set (load, conflict swap, re-apply): keep the
            // caret sane. Styling arrives via the storage delegate — every
            // character mutation flows through it.
            let selected = view.selectedRange
            view.text = text
            let n = (text as NSString).length
            view.selectedRange = NSRange(location: min(selected.location, n), length: 0)
        }
        if focused, !view.isFirstResponder, view.window != nil, editable {
            view.becomeFirstResponder()
        }
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

        init(_ parent: MarkdownEditor) { self.parent = parent }

        func install(on view: MarkdownTextView) {
            self.view = view
            // Styling rides the STORAGE, not the caret: every character
            // mutation (typing, paste, drop, undo, programmatic replace)
            // flows through didProcessEditing with the range that actually
            // changed. This is what keeps styling a pure function of the
            // text under multi-paragraph edits — the audit's top finding.
            view.textStorage.delegate = self
            // No inputAccessoryView, on purpose (design/editor-study.md §6
            // rev 2): while you type there is the note and the keyboard and
            // nothing else. Inline formatting lives in the selection menu,
            // blocks behind the floating `Aa`.
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

        /// Widened one character each side: a return that SPLITS a line
        /// edits only the newline, but both halves need restyling.
        private func apply(around range: NSRange, to storage: NSTextStorage) {
            let n = (storage.string as NSString).length
            let lo = max(0, min(range.location, n) - 1)
            let hi = min(n, NSMaxRange(range) + 1)
            MarkStyler.apply(to: storage, in: NSRange(location: lo, length: hi - lo))
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
            if let view = view, view.styleKeyboardShown {
                setStyleKeyboard(false, on: view)
                parent.styleShown = false
            }
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

        // MARK: the style keyboard

        /// Swap the system keyboard for the style panel, or back. The panel
        /// replaces the keyboard rather than sitting above it, so the note
        /// never loses more room than the keyboard already took.
        func setStyleKeyboard(_ shown: Bool, on view: MarkdownTextView) {
            guard view.styleKeyboardShown != shown else { return }
            view.styleKeyboardShown = shown
            view.inputView =
                shown ? StyleKeyboard(onVerb: { [weak self] v in self?.style(v) }) : nil
            view.reloadInputViews()
        }

        private func style(_ verb: StyleVerb) {
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
            case .dismiss:
                view.resignFirstResponder()
            }
        }

        // MARK: checkbox taps

        @objc private func boxTapped(_ gesture: UITapGestureRecognizer) {
            guard let view = view,
                let result = EditOps.toggleTask(
                    view.text, at: characterIndex(of: gesture.location(in: view)))
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

        /// Only claim touches GEOMETRICALLY inside a drawn checkbox (plus
        /// small slack). characterIndex alone returns the NEAREST character
        /// for any point — an index-only gate would swallow taps in empty
        /// space below a trailing task line and silently toggle it (the
        /// audit's finding). Everything else stays native text handling.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch
        ) -> Bool {
            guard let view = view, (view.text as NSString).length > 0 else { return false }
            let point = touch.location(in: view)
            let index = characterIndex(of: point)
            let n = (view.text as NSString).length
            var boxRange: NSRange?
            for probe in [index, index - 1, index + 1] where probe >= 0 && probe < n {
                var effective = NSRange(location: 0, length: 0)
                if view.textStorage.attribute(.livTaskBox, at: probe, effectiveRange: &effective)
                    != nil
                {
                    boxRange = effective
                    break
                }
            }
            guard let boxRange else { return false }
            let glyphs = view.layoutManager.glyphRange(
                forCharacterRange: boxRange, actualCharacterRange: nil)
            var rect = view.layoutManager.boundingRect(
                forGlyphRange: glyphs, in: view.textContainer)
            rect.origin.x += view.textContainerInset.left
            rect.origin.y += view.textContainerInset.top
            return rect.insetBy(dx: -10, dy: -6).contains(point)
        }
    }
}


// MARK: - the style keyboard (summoned by the floating `Aa`)

enum StyleVerb {
    case heading, bold, italic, strike, code
    case bullet, ordered, task, quote, rule
    case outdent, indent, undo, redo, dismiss
}

/// The Aa panel: the system keyboard swapped for full-size formatting keys
/// (Bear's style keyboard). Three rows of honest 52pt targets — inline,
/// blocks, then structure and history. Aa again (or ending editing) brings
/// the letters back. This is the app's ONLY formatting chrome: nothing
/// stands over the note while you type (design/editor-study.md §6 rev 2).
final class StyleKeyboard: UIInputView {
    private let onVerb: (StyleVerb) -> Void

    init(onVerb: @escaping (StyleVerb) -> Void) {
        self.onVerb = onVerb
        super.init(
            frame: CGRect(x: 0, y: 0, width: 0, height: 220), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        backgroundColor = LivInk.surface

        func row(_ keys: [(String, Bool, String, StyleVerb)]) -> UIStackView {
            let stack = UIStackView(
                arrangedSubviews: keys.map { (label, isSymbol, access, verb) in
                    key(label: label, isSymbol: isSymbol, access: access) { [weak self] in
                        self?.onVerb(verb)
                    }
                })
            stack.axis = .horizontal
            stack.spacing = 6
            stack.distribution = .fillEqually
            return stack
        }

        let rows = UIStackView(arrangedSubviews: [
            row([
                ("H", false, "Heading", .heading),
                ("bold", true, "Bold", .bold),
                ("italic", true, "Italic", .italic),
                ("strikethrough", true, "Strikethrough", .strike),
                ("chevron.left.forwardslash.chevron.right", true, "Code", .code),
            ]),
            row([
                ("list.bullet", true, "Bulleted list", .bullet),
                ("list.number", true, "Numbered list", .ordered),
                ("checkmark.square", true, "Task list", .task),
                ("text.quote", true, "Quote", .quote),
                ("minus", true, "Divider", .rule),
            ]),
            // Structure and history — the controls that used to stand in a
            // bar over the note. Undo/redo are here rather than on the
            // writing surface: the system shake gesture still works, and
            // this is where a user goes when they are fixing, not writing.
            row([
                ("decrease.indent", true, "Outdent", .outdent),
                ("increase.indent", true, "Indent", .indent),
                ("arrow.uturn.backward", true, "Undo", .undo),
                ("arrow.uturn.forward", true, "Redo", .redo),
                ("keyboard.chevron.compact.down", true, "Hide keyboard", .dismiss),
            ]),
        ])
        rows.axis = .vertical
        rows.spacing = 6
        rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            rows.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            rows.heightAnchor.constraint(equalToConstant: 168),
        ])
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    private func key(
        label: String, isSymbol: Bool, access: String, action: @escaping () -> Void
    ) -> UIButton {
        let button = UIButton(type: .system)
        if isSymbol {
            button.setImage(
                UIImage(
                    systemName: label,
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)),
                for: .normal)
        } else {
            button.setTitle(label, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        }
        button.accessibilityLabel = access
        button.tintColor = LivInk.text
        button.backgroundColor = LivInk.keyFill
        button.layer.cornerRadius = 8
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 52)
        ])
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }
}
