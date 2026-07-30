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

    static func bolded(_ base: UIFont) -> UIFont {
        UIFont.systemFont(ofSize: base.pointSize, weight: .semibold)
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
        textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
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
    var editable: Bool

    func makeUIView(context: Context) -> MarkdownTextView {
        let view = MarkdownTextView()
        view.delegate = context.coordinator
        context.coordinator.install(on: view)
        return view
    }

    func updateUIView(_ view: MarkdownTextView, context: Context) {
        view.isEditable = editable
        if view.text != text {
            // Programmatic set (load, conflict swap, re-apply): keep the
            // caret sane, restyle the whole document once.
            let selected = view.selectedRange
            view.text = text
            MarkStyler.apply(
                to: view.textStorage,
                in: NSRange(location: 0, length: (text as NSString).length))
            let n = (text as NSString).length
            view.selectedRange = NSRange(location: min(selected.location, n), length: 0)
        }
        if focused, !view.isFirstResponder, view.window != nil, editable {
            view.becomeFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: coordinator

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        private let parent: MarkdownEditor
        private weak var view: MarkdownTextView?

        init(_ parent: MarkdownEditor) { self.parent = parent }

        func install(on view: MarkdownTextView) {
            self.view = view
            view.inputAccessoryView = EditorToolbar(
                onVerb: { [weak self] verb in self?.toolbar(verb) },
                height: 44)
            // Checkbox taps: the recognizer only RECEIVES touches that land
            // on a drawn box, so caret placement everywhere else is native.
            let tap = UITapGestureRecognizer(target: self, action: #selector(boxTapped(_:)))
            tap.delegate = self
            view.addGestureRecognizer(tap)
        }

        // MARK: text flow

        func textViewDidChange(_ textView: UITextView) {
            // Restyle only the paragraph(s) around the edit — the caret
            // marks where the edit landed.
            MarkStyler.apply(to: textView.textStorage, in: textView.selectedRange)
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
                view.styleKeyboardShown = false
                view.inputView = nil
            }
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

        private func toolbar(_ verb: ToolbarVerb) {
            guard let view = view else { return }
            switch verb {
            case .styleKeyboard:
                view.styleKeyboardShown.toggle()
                view.inputView =
                    view.styleKeyboardShown
                    ? StyleKeyboard(onVerb: { [weak self] v in self?.style(v) }) : nil
                view.reloadInputViews()
            case .task:
                applyThroughSystem(
                    EditOps.setBlock(view.text, selection: view.selectedRange, verb: .task),
                    to: view)
            case .indent:
                applyThroughSystem(
                    EditOps.indent(view.text, selection: view.selectedRange, out: false), to: view)
            case .outdent:
                applyThroughSystem(
                    EditOps.indent(view.text, selection: view.selectedRange, out: true), to: view)
            case .undo:
                view.undoManager?.undo()
            case .redo:
                view.undoManager?.redo()
            case .dismiss:
                view.resignFirstResponder()
            }
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
                view.text = result.text
                MarkStyler.apply(
                    to: view.textStorage,
                    in: NSRange(location: 0, length: (result.text as NSString).length))
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

        /// Only claim touches that land on a drawn checkbox (with a little
        /// slack); everything else stays native text handling.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch
        ) -> Bool {
            guard let view = view, (view.text as NSString).length > 0 else { return false }
            let index = characterIndex(of: touch.location(in: view))
            let n = (view.text as NSString).length
            guard index < n else { return false }
            var effective = NSRange(location: 0, length: 0)
            let value = view.textStorage.attribute(
                .livTaskBox, at: index, effectiveRange: &effective)
            if value != nil { return true }
            // One glyph of slack on either side of the box.
            for probe in [index - 1, index + 1]
            where probe >= 0 && probe < n
                && view.textStorage.attribute(.livTaskBox, at: probe, effectiveRange: nil) != nil {
                return true
            }
            return false
        }
    }
}

// MARK: - the toolbar (rides the keyboard's own animation — rule 4)

enum ToolbarVerb { case styleKeyboard, task, indent, outdent, undo, redo, dismiss }
enum StyleVerb { case heading, bold, italic, strike, code, bullet, ordered, task, quote, rule }

/// One 44pt row: Aa pinned left, verbs scrolling in the middle, dismiss
/// pinned right. Opaque surface, hairline top edge, no accent spent.
final class EditorToolbar: UIInputView {
    private let onVerb: (ToolbarVerb) -> Void

    init(onVerb: @escaping (ToolbarVerb) -> Void, height: CGFloat) {
        self.onVerb = onVerb
        super.init(
            frame: CGRect(x: 0, y: 0, width: 0, height: height), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        backgroundColor = LivInk.surface

        let hairline = UIView()
        hairline.backgroundColor = LivInk.border
        hairline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hairline)

        let aa = key(title: "Aa") { [weak self] in self?.onVerb(.styleKeyboard) }
        aa.accessibilityLabel = "Formatting"
        let dismiss = key(symbol: "keyboard.chevron.compact.down") { [weak self] in
            self?.onVerb(.dismiss)
        }
        dismiss.accessibilityLabel = "Hide keyboard"

        let scroller = UIScrollView()
        scroller.showsHorizontalScrollIndicator = false
        let middle = UIStackView(arrangedSubviews: [
            key(symbol: "checkmark.square") { [weak self] in self?.onVerb(.task) },
            key(symbol: "increase.indent") { [weak self] in self?.onVerb(.indent) },
            key(symbol: "decrease.indent") { [weak self] in self?.onVerb(.outdent) },
            key(symbol: "arrow.uturn.backward") { [weak self] in self?.onVerb(.undo) },
            key(symbol: "arrow.uturn.forward") { [weak self] in self?.onVerb(.redo) },
        ])
        middle.axis = .horizontal
        middle.spacing = 2
        middle.translatesAutoresizingMaskIntoConstraints = false
        scroller.addSubview(middle)
        scroller.translatesAutoresizingMaskIntoConstraints = false

        let row = UIStackView(arrangedSubviews: [aa, scroller, dismiss])
        row.axis = .horizontal
        row.spacing = 2
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            hairline.topAnchor.constraint(equalTo: topAnchor),
            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 0.5),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 0.5),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            row.heightAnchor.constraint(equalToConstant: height - 0.5),
            middle.topAnchor.constraint(equalTo: scroller.contentLayoutGuide.topAnchor),
            middle.bottomAnchor.constraint(equalTo: scroller.contentLayoutGuide.bottomAnchor),
            middle.leadingAnchor.constraint(equalTo: scroller.contentLayoutGuide.leadingAnchor),
            middle.trailingAnchor.constraint(equalTo: scroller.contentLayoutGuide.trailingAnchor),
            middle.heightAnchor.constraint(equalTo: scroller.frameLayoutGuide.heightAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    private func key(
        title: String? = nil, symbol: String? = nil, action: @escaping () -> Void
    ) -> UIButton {
        let button = UIButton(type: .system)
        if let title {
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        }
        if let symbol {
            button.setImage(
                UIImage(
                    systemName: symbol,
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)),
                for: .normal)
        }
        button.tintColor = LivInk.text2
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        return button
    }
}

/// The Aa panel: the system keyboard swapped for full-size formatting keys
/// (Bear's style keyboard). Two rows of honest 52pt targets; Aa again (or
/// ending editing) brings the letters back.
final class StyleKeyboard: UIInputView {
    private let onVerb: (StyleVerb) -> Void

    init(onVerb: @escaping (StyleVerb) -> Void) {
        self.onVerb = onVerb
        super.init(
            frame: CGRect(x: 0, y: 0, width: 0, height: 220), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        backgroundColor = LivInk.surface

        func row(_ keys: [(String, Bool, StyleVerb)]) -> UIStackView {
            let stack = UIStackView(
                arrangedSubviews: keys.map { (label, isSymbol, verb) in
                    key(label: label, isSymbol: isSymbol) { [weak self] in self?.onVerb(verb) }
                })
            stack.axis = .horizontal
            stack.spacing = 6
            stack.distribution = .fillEqually
            return stack
        }

        let rows = UIStackView(arrangedSubviews: [
            row([
                ("H", false, .heading),
                ("bold", true, .bold),
                ("italic", true, .italic),
                ("strikethrough", true, .strike),
                ("chevron.left.forwardslash.chevron.right", true, .code),
            ]),
            row([
                ("list.bullet", true, .bullet),
                ("list.number", true, .ordered),
                ("checkmark.square", true, .task),
                ("text.quote", true, .quote),
                ("minus", true, .rule),
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
            rows.heightAnchor.constraint(equalToConstant: 110),
        ])
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    private func key(label: String, isSymbol: Bool, action: @escaping () -> Void) -> UIButton {
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
        button.tintColor = LivInk.text
        button.backgroundColor = LivInk.panel2
        button.layer.cornerRadius = 8
        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: 52)
        ])
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }
}
