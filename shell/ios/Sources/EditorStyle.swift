// liv iOS — the markdown layer of the editor (design/editor-study.md,
// phase 1). Two pure halves, no UIKit, no box:
//
//   MarkScan — what a line IS (its block shape + inline runs), as UTF-16
//              ranges ready for NSAttributedString. Styling is a pure
//              function of the TEXT, never of the caret (ruling 3A:
//              markers render dimmed and identical in every state, so no
//              line ever reflows when you tap into it).
//   EditOps  — what the toolbar DOES: (text, selection) → (text,
//              selection). The view applies results through the system
//              text APIs so undo keeps working.
//
// The buffer itself stays plain text with markdown markers IN it (ruling
// 4: stored as-is for now; phase 5 converts to marks-and-blocks). The
// span codec in Editor.swift is untouched by all of this.

import Foundation

// MARK: - block shapes

enum LineBlock: Equatable {
    case body
    case heading(Int)  // 1...6
    case bullet
    case ordered(Int)  // the number as typed
    case task(checked: Bool)
    case quote
    case rule
}

/// One line, scanned. Ranges are UTF-16, relative to the LINE start.
/// `marker` covers the whole prefix including its trailing space;
/// `box` (tasks only) covers exactly "[ ]" / "[x]" — the checkbox glyphs.
struct LineShape: Equatable {
    var block: LineBlock
    var indent: Int  // leading whitespace utf16 length
    var marker: NSRange  // empty for body lines
    var box: NSRange?  // tasks only
}

/// An inline run inside a line's content. Ranges relative to LINE start.
enum InlineRun: Equatable {
    case marker(NSRange)  // the ** / * / ~~ / ` glyphs themselves
    case bold(NSRange)  // the text between the markers
    case italic(NSRange)
    case strike(NSRange)
    case code(NSRange)  // content between backticks
    case refToken(NSRange, name: NSRange?)  // whole [[…]]; name part if any
}

enum MarkScan {
    /// The block shape of one line (the line string, no newline).
    static func shape(_ line: String) -> LineShape {
        let u = Array(line.utf16)
        var i = 0
        while i < u.count, u[i] == 0x20 || u[i] == 0x09 { i += 1 }
        let indent = i

        // rule: --- / *** / ___ alone on the line (3+, whitespace after ok)
        if i < u.count, u[i] == 0x2D || u[i] == 0x2A || u[i] == 0x5F {
            let c = u[i]
            var j = i
            while j < u.count, u[j] == c { j += 1 }
            var k = j
            while k < u.count, u[k] == 0x20 || u[k] == 0x09 { k += 1 }
            if j - i >= 3, k == u.count {
                return LineShape(
                    block: .rule, indent: indent,
                    marker: NSRange(location: 0, length: u.count), box: nil)
            }
        }

        // heading: #{1,6} + space
        if i < u.count, u[i] == 0x23 {
            var j = i
            while j < u.count, u[j] == 0x23 { j += 1 }
            let level = j - i
            if level <= 6, j < u.count, u[j] == 0x20 {
                return LineShape(
                    block: .heading(level), indent: indent,
                    marker: NSRange(location: 0, length: j + 1), box: nil)
            }
        }

        // task: "- [ ] " / "- [x] "  (checked also accepts X)
        if i + 5 < u.count, u[i] == 0x2D, u[i + 1] == 0x20, u[i + 2] == 0x5B,
            u[i + 4] == 0x5D, u[i + 5] == 0x20,
            u[i + 3] == 0x20 || u[i + 3] == 0x78 || u[i + 3] == 0x58
        {
            return LineShape(
                block: .task(checked: u[i + 3] != 0x20), indent: indent,
                marker: NSRange(location: 0, length: i + 6),
                box: NSRange(location: i + 2, length: 3))
        }

        // bullet: "- " or "* " (not "- [" which is a half-typed task)
        if i + 1 < u.count, u[i] == 0x2D || u[i] == 0x2A, u[i + 1] == 0x20 {
            return LineShape(
                block: .bullet, indent: indent,
                marker: NSRange(location: 0, length: i + 2), box: nil)
        }

        // ordered: digits + ". "
        if i < u.count, u[i] >= 0x30, u[i] <= 0x39 {
            var j = i
            var n = 0
            while j < u.count, u[j] >= 0x30, u[j] <= 0x39, j - i < 4 {
                n = n * 10 + Int(u[j] - 0x30)
                j += 1
            }
            if j + 1 < u.count, u[j] == 0x2E, u[j + 1] == 0x20 {
                return LineShape(
                    block: .ordered(n), indent: indent,
                    marker: NSRange(location: 0, length: j + 2), box: nil)
            }
        }

        // quote: "> "
        if i < u.count, u[i] == 0x3E {
            let len = (i + 1 < u.count && u[i + 1] == 0x20) ? i + 2 : i + 1
            return LineShape(
                block: .quote, indent: indent,
                marker: NSRange(location: 0, length: len), box: nil)
        }

        return LineShape(
            block: .body, indent: indent, marker: NSRange(location: 0, length: 0),
            box: nil)
    }

    /// Inline runs in one line, scanned AFTER the block marker. Pairs must
    /// close on the same line; an unclosed marker is literal text. `code`
    /// wins over everything inside it; ref tokens use the codec's own
    /// never-lenient grammar.
    static func inline(_ line: String, from start: Int) -> [InlineRun] {
        let u = Array(line.utf16)
        var out: [InlineRun] = []
        var i = start

        func find(_ glyphs: [UInt16], from: Int) -> Int? {
            var j = from
            while j + glyphs.count <= u.count {
                var hit = true
                for (k, g) in glyphs.enumerated() where u[j + k] != g { hit = false; break }
                if hit { return j }
                j += 1
            }
            return nil
        }

        while i < u.count {
            let c = u[i]
            // `code`
            if c == 0x60, let close = find([0x60], from: i + 1) {
                out.append(.marker(NSRange(location: i, length: 1)))
                out.append(.code(NSRange(location: i + 1, length: close - i - 1)))
                out.append(.marker(NSRange(location: close, length: 1)))
                i = close + 1
                continue
            }
            // [[ref]] — digits, optional |name, ]] (the codec's grammar,
            // including its UInt64 bound: an overflowing digit run is
            // literal text to the codec, so it must not LOOK like a link)
            if c == 0x5B, i + 1 < u.count, u[i + 1] == 0x5B {
                var j = i + 2
                var digitStr = ""
                while j < u.count, u[j] >= 0x30, u[j] <= 0x39 {
                    digitStr.append(Character(UnicodeScalar(u[j])!))
                    j += 1
                }
                if !digitStr.isEmpty, UInt64(digitStr) != nil {
                    if j + 1 < u.count, u[j] == 0x5D, u[j + 1] == 0x5D {
                        out.append(
                            .refToken(NSRange(location: i, length: j + 2 - i), name: nil))
                        i = j + 2
                        continue
                    }
                    if j < u.count, u[j] == 0x7C, let close = find([0x5D, 0x5D], from: j + 1) {
                        out.append(
                            .refToken(
                                NSRange(location: i, length: close + 2 - i),
                                name: NSRange(location: j + 1, length: close - j - 1)))
                        i = close + 2
                        continue
                    }
                }
            }
            // **bold**
            if c == 0x2A, i + 1 < u.count, u[i + 1] == 0x2A,
                let close = find([0x2A, 0x2A], from: i + 2), close > i + 2
            {
                out.append(.marker(NSRange(location: i, length: 2)))
                out.append(.bold(NSRange(location: i + 2, length: close - i - 2)))
                out.append(.marker(NSRange(location: close, length: 2)))
                i = close + 2
                continue
            }
            // *italic*
            if c == 0x2A, let close = find([0x2A], from: i + 1), close > i + 1,
                !(close + 1 < u.count && u[close + 1] == 0x2A)
            {
                out.append(.marker(NSRange(location: i, length: 1)))
                out.append(.italic(NSRange(location: i + 1, length: close - i - 1)))
                out.append(.marker(NSRange(location: close, length: 1)))
                i = close + 1
                continue
            }
            // ~~strike~~
            if c == 0x7E, i + 1 < u.count, u[i + 1] == 0x7E,
                let close = find([0x7E, 0x7E], from: i + 2), close > i + 2
            {
                out.append(.marker(NSRange(location: i, length: 2)))
                out.append(.strike(NSRange(location: i + 2, length: close - i - 2)))
                out.append(.marker(NSRange(location: close, length: 2)))
                i = close + 2
                continue
            }
            i += 1
        }
        return out
    }
}

// MARK: - edit operations

/// A pure edit: the whole new text plus the new selection. The view turns
/// it into a minimal system-API replacement so undo registration holds.
struct EditResult: Equatable {
    var text: String
    var selection: NSRange
}

enum EditOps {
    private static let indentUnit = "  "  // two spaces

    private static func ns(_ s: String) -> NSString { s as NSString }

    /// The line range containing `location` (never includes the newline).
    static func lineRange(_ text: String, at location: Int) -> NSRange {
        let n = ns(text)
        let loc = min(max(0, location), n.length)
        var r = n.lineRange(for: NSRange(location: loc, length: 0))
        while r.length > 0 {
            let last = n.character(at: r.location + r.length - 1)
            if last == 0x0A || last == 0x0D { r.length -= 1 } else { break }
        }
        return r
    }

    private static func line(_ text: String, at location: Int) -> (NSRange, String) {
        let r = lineRange(text, at: location)
        return (r, ns(text).substring(with: r))
    }

    /// Where a LINE index starts, in characters — nil when the buffer has
    /// no such line. The bridge between the wire's `note_tasks.line` and
    /// every op here, which all address the buffer by location: the Tasks
    /// view toggles a note's line through the SAME toggleTask the
    /// editor's own checkbox uses, never a second implementation
    /// (phase 3).
    static func lineStart(_ text: String, line index: Int) -> Int? {
        guard index >= 0 else { return nil }
        if index == 0 { return 0 }
        // Count newlines, not lineRange hops: lineRange happily walks to
        // the buffer's end and would answer with a location for a line
        // that does not exist (the self-check caught it, 2026-08-05).
        let n = ns(text)
        var seen = 0
        var i = 0
        while i < n.length {
            if n.character(at: i) == 0x0A {
                seen += 1
                if seen == index { return i + 1 }
            }
            i += 1
        }
        return nil
    }

    /// Tap on a task checkbox: flip it. `location` is anywhere in the line.
    static func toggleTask(_ text: String, at location: Int) -> EditResult? {
        let (r, l) = line(text, at: location)
        let shape = MarkScan.shape(l)
        guard case .task(let checked) = shape.block, let box = shape.box else { return nil }
        let flip = NSRange(location: r.location + box.location + 1, length: 1)
        let out = ns(text).replacingCharacters(in: flip, with: checked ? " " : "x")
        return EditResult(text: out, selection: NSRange(location: flip.location + 1, length: 0))
    }

    /// Return pressed. A marker line CONTINUES its list; return on a line
    /// that is only its marker ENDS the list (removes the marker). nil =
    /// let the system insert a plain newline.
    static func returnKey(_ text: String, selection: NSRange) -> EditResult? {
        guard selection.length == 0 else { return nil }
        let (r, l) = line(text, at: selection.location)
        // Only act at end-of-line — mid-line return splits the line plainly.
        guard selection.location == r.location + r.length else { return nil }
        let shape = MarkScan.shape(l)
        // The ORIGINAL whitespace, not a rebuild — a tab must stay a tab.
        let pad = ns(l).substring(to: shape.indent)
        let continuation: String
        switch shape.block {
        case .task: continuation = "\(pad)- [ ] "
        case .bullet: continuation = "\(pad)- "
        case .ordered(let n): continuation = "\(pad)\(n + 1). "
        case .quote: continuation = "\(pad)> "
        case .body, .heading, .rule: return nil
        }
        // Marker-only line → end the list: clear the line, stay on it.
        if l.utf16.count == shape.marker.length {
            let out = ns(text).replacingCharacters(in: r, with: "")
            return EditResult(text: out, selection: NSRange(location: r.location, length: 0))
        }
        let out = ns(text).replacingCharacters(
            in: NSRange(location: selection.location, length: 0), with: "\n" + continuation)
        return EditResult(
            text: out,
            selection: NSRange(
                location: selection.location + 1 + (continuation as NSString).length, length: 0))
    }

    /// The block verbs (style keyboard): heading cycles ∅→#→##→###→∅;
    /// bullet/ordered/task/quote toggle. Applies to every line the
    /// selection touches; the selection comes back covering those lines.
    static func setBlock(_ text: String, selection: NSRange, verb: BlockVerb) -> EditResult {
        let n = ns(text)
        let start = lineRange(text, at: selection.location).location
        let endLine = lineRange(text, at: max(selection.location, NSMaxRange(selection) - (selection.length > 0 ? 1 : 0)))
        let whole = NSRange(location: start, length: NSMaxRange(endLine) - start)
        let block = n.substring(with: whole)
        let lines = block.components(separatedBy: "\n")

        var replaced: [String] = []
        for (idx, l) in lines.enumerated() {
            let shape = MarkScan.shape(l)
            // The ORIGINAL whitespace, not a rebuild — a tab must stay a tab.
            let pad = ns(l).substring(to: shape.indent)
            let stripped =
                shape.marker.length > 0
                ? ns(l).substring(from: shape.marker.length)
                : ns(l).substring(from: shape.indent)
            switch verb {
            case .headingCycle:
                let next: Int
                if case .heading(let h) = shape.block { next = h >= 3 ? 0 : h + 1 } else { next = 1 }
                replaced.append(
                    pad + (next == 0 ? stripped : String(repeating: "#", count: next) + " " + stripped))
            case .bullet:
                if case .bullet = shape.block { replaced.append(pad + stripped) } else { replaced.append(pad + "- " + stripped) }
            case .ordered:
                if case .ordered = shape.block { replaced.append(pad + stripped) } else { replaced.append(pad + "\(idx + 1). " + stripped) }
            case .task:
                if case .task = shape.block { replaced.append(pad + stripped) } else { replaced.append(pad + "- [ ] " + stripped) }
            case .quote:
                if case .quote = shape.block { replaced.append(pad + stripped) } else { replaced.append(pad + "> " + stripped) }
            case .rule:
                replaced.append(l)  // rule INSERTS, handled below
            }
        }

        if verb == .rule {
            // Insert a --- paragraph after the current line, and land the
            // caret on a FRESH line below it: parked at the end of the
            // --- itself, the next keystroke turned the divider into
            // "---text" — no longer a rule at all (found live,
            // 2026-08-05).
            let insert = "\n---\n"
            let out = n.replacingCharacters(
                in: NSRange(location: NSMaxRange(whole), length: 0), with: insert)
            return EditResult(
                text: out,
                selection: NSRange(location: NSMaxRange(whole) + (insert as NSString).length, length: 0))
        }

        let newBlock = replaced.joined(separator: "\n")
        let out = n.replacingCharacters(in: whole, with: newBlock)
        return EditResult(
            text: out,
            selection: NSRange(location: whole.location, length: (newBlock as NSString).length))
    }

    /// Inline verbs: wrap the selection, unwrap it if already wrapped, or
    /// (empty selection) insert the pair and park the caret inside. A
    /// selection spanning lines wraps each line separately — inline pairs
    /// must close on one line or they are literal text.
    static func toggleInline(_ text: String, selection: NSRange, marker: String) -> EditResult {
        let n = ns(text)
        let m = ns(marker).length
        if selection.length > 0, n.substring(with: selection).contains("\n") {
            let wrapped = n.substring(with: selection)
                .components(separatedBy: "\n")
                .map { $0.isEmpty ? $0 : marker + $0 + marker }
                .joined(separator: "\n")
            let out = n.replacingCharacters(in: selection, with: wrapped)
            return EditResult(
                text: out,
                selection: NSRange(
                    location: selection.location, length: (wrapped as NSString).length))
        }
        if selection.length == 0 {
            let out = n.replacingCharacters(in: selection, with: marker + marker)
            return EditResult(
                text: out, selection: NSRange(location: selection.location + m, length: 0))
        }
        let before = NSRange(location: selection.location - m, length: m)
        let after = NSRange(location: NSMaxRange(selection), length: m)
        if before.location >= 0, NSMaxRange(after) <= n.length,
            n.substring(with: before) == marker, n.substring(with: after) == marker
        {
            var out = n.replacingCharacters(in: after, with: "")
            out = ns(out).replacingCharacters(in: before, with: "")
            return EditResult(
                text: out, selection: NSRange(location: before.location, length: selection.length))
        }
        let inner = n.substring(with: selection)
        let out = n.replacingCharacters(in: selection, with: marker + inner + marker)
        return EditResult(
            text: out, selection: NSRange(location: selection.location + m, length: selection.length))
    }

    /// Indent / outdent every line the selection touches by two spaces.
    static func indent(_ text: String, selection: NSRange, out outdent: Bool) -> EditResult {
        let n = ns(text)
        let start = lineRange(text, at: selection.location).location
        let endLine = lineRange(text, at: max(selection.location, NSMaxRange(selection) - (selection.length > 0 ? 1 : 0)))
        let whole = NSRange(location: start, length: NSMaxRange(endLine) - start)
        let lines = n.substring(with: whole).components(separatedBy: "\n")
        let replaced = lines.map { l -> String in
            if outdent {
                if l.hasPrefix(indentUnit) { return String(l.dropFirst(2)) }
                if l.hasPrefix(" ") { return String(l.dropFirst(1)) }
                if l.hasPrefix("\t") { return String(l.dropFirst(1)) }
                return l
            }
            return indentUnit + l
        }
        let newBlock = replaced.joined(separator: "\n")
        let out = n.replacingCharacters(in: whole, with: newBlock)
        return EditResult(
            text: out,
            selection: NSRange(location: whole.location, length: (newBlock as NSString).length))
    }

    enum BlockVerb: Equatable { case headingCycle, bullet, ordered, task, quote, rule }
}

// MARK: - links being typed

/// An unfinished `[[` the caret is sitting inside: the whole token range
/// (from the brackets to the caret) and what has been typed after them.
struct OpenLink: Equatable {
    var range: NSRange  // the "[[query" span, document-absolute
    var query: String
}

extension MarkScan {
    /// Is the caret inside an unclosed `[[`? Scans backwards from the caret
    /// to the line start only — a link never spans lines, and a closed
    /// `]]` between the brackets and the caret ends it.
    static func openLink(_ text: String, caret: Int) -> OpenLink? {
        let n = text as NSString
        guard caret >= 2, caret <= n.length else { return nil }
        let line = EditOps.lineRange(text, at: caret)
        var i = caret - 1
        while i >= line.location + 1 {
            let c = n.character(at: i)
            // A closed token, or a newline, means the caret is not in one.
            if c == 0x5D, n.character(at: i - 1) == 0x5D { return nil }
            if c == 0x5B, n.character(at: i - 1) == 0x5B {
                let start = i - 1
                let query = n.substring(with: NSRange(location: i + 1, length: caret - i - 1))
                // A query never contains the closer or a pipe — those end
                // the picker and hand the text back to the codec.
                if query.contains("]") || query.contains("|") { return nil }
                return OpenLink(
                    range: NSRange(location: start, length: caret - start), query: query)
            }
            i -= 1
        }
        return nil
    }
}

extension EditOps {
    /// Replace a half-typed `[[query` with the finished token. The id is
    /// the payload; the name is cosmetic (Editor.swift's codec re-derives
    /// it on every load), so a name carrying "]]" or newlines is cleaned
    /// exactly the way SpanText.token cleans it.
    static func completeLink(
        _ text: String, token: NSRange, id: UInt64, name: String
    ) -> EditResult {
        let clean =
            name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "]]", with: "] ]")
        let inserted = clean.isEmpty ? "[[\(id)]]" : "[[\(id)|\(clean)]]"
        let out = ns(text).replacingCharacters(in: token, with: inserted)
        return EditResult(
            text: out,
            selection: NSRange(
                location: token.location + (inserted as NSString).length, length: 0))
    }
}

// MARK: - outline

/// One heading, for the jump list.
struct OutlineItem: Identifiable, Equatable {
    let id: Int  // the heading line's start location — unique per note
    var level: Int
    var title: String
}

/// Every heading in the note, in order. A whole-document scan, so it is
/// called on a debounce and when a note loads — never on the typing path.
func livOutline(_ text: String) -> [OutlineItem] {
    let n = text as NSString
    var out: [OutlineItem] = []
    n.enumerateSubstrings(in: NSRange(location: 0, length: n.length), options: [.byLines]) {
        line, range, _, _ in
        guard let line else { return }
        let shape = MarkScan.shape(line)
        guard case .heading(let level) = shape.block else { return }
        let title = livDisplayTitle(line)
        out.append(
            OutlineItem(id: range.location, level: level, title: title.isEmpty ? "—" : title))
    }
    return out
}

// MARK: - display titles

/// A scrap's display name is its content's first line — which now
/// routinely carries markdown markers. Everywhere a title STRING is shown
/// (rows, cards, the ledger, notifications) the markers come off; the
/// buffer itself is never touched. Pure, line-local.
func livDisplayTitle(_ raw: String) -> String {
    let line = raw.components(separatedBy: "\n").first ?? raw
    let shape = MarkScan.shape(line)
    if case .rule = shape.block { return "" }
    let n = line as NSString
    let content = n.substring(from: min(shape.marker.length, n.length))
    let runs = MarkScan.inline(content, from: 0)
    guard !runs.isEmpty else {
        return content.trimmingCharacters(in: .whitespaces)
    }
    // Rebuild the line, skipping marker glyphs; a named ref token shows
    // its name, a nameless one stays as typed.
    let c = content as NSString
    var skip: [NSRange] = []
    for run in runs {
        switch run {
        case .marker(let r): skip.append(r)
        case .refToken(let whole, let name):
            if let name {
                skip.append(NSRange(location: whole.location, length: name.location - whole.location))
                skip.append(
                    NSRange(location: NSMaxRange(name), length: NSMaxRange(whole) - NSMaxRange(name)))
            }
        case .bold, .italic, .strike, .code: break
        }
    }
    skip.sort { $0.location < $1.location }
    var out = ""
    var i = 0
    for r in skip {
        if r.location > i { out += c.substring(with: NSRange(location: i, length: r.location - i)) }
        i = max(i, NSMaxRange(r))
    }
    if i < c.length { out += c.substring(from: i) }
    return out.trimmingCharacters(in: .whitespaces)
}

// MARK: - self-check (run: simctl launch … -editor.selfcheck 1)

func livEditorSelfCheck() -> [String] {
    var failures: [String] = []
    func check(_ label: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        if !ok { failures.append("FAIL \(label) \(detail())") }
    }

    // block shapes
    check("h2", MarkScan.shape("## Title").block == .heading(2))
    check("h7 is body", MarkScan.shape("####### x").block == .body)
    check("hash no space is body", MarkScan.shape("#hash").block == .body)
    check("bullet", MarkScan.shape("- item").block == .bullet)
    check("star bullet", MarkScan.shape("* item").block == .bullet)
    check("task open", MarkScan.shape("- [ ] go").block == .task(checked: false))
    check("task done", MarkScan.shape("- [x] go").block == .task(checked: true))
    check("half task is bullet", MarkScan.shape("- [] go").block == .bullet)
    check("ordered", MarkScan.shape("12. go").block == .ordered(12))
    check("quote", MarkScan.shape("> words").block == .quote)
    check("rule", MarkScan.shape("---").block == .rule)
    check("rule spaced", MarkScan.shape("***   ").block == .rule)
    check("two dashes is body", MarkScan.shape("--").block == .body)
    check(
        "indented task keeps indent",
        MarkScan.shape("  - [ ] x") == LineShape(
            block: .task(checked: false), indent: 2,
            marker: NSRange(location: 0, length: 8),
            box: NSRange(location: 4, length: 3)))

    // inline runs
    let runs = MarkScan.inline("a **b** and `c` [[42|Home]]", from: 0)
    check("bold found", runs.contains(.bold(NSRange(location: 4, length: 1))), "\(runs)")
    check("code found", runs.contains(.code(NSRange(location: 13, length: 1))), "\(runs)")
    check(
        "ref found",
        runs.contains(
            .refToken(NSRange(location: 16, length: 11), name: NSRange(location: 21, length: 4))),
        "\(runs)")
    check("unclosed bold is text", MarkScan.inline("**open", from: 0).isEmpty)
    check(
        "italic not bold tail",
        MarkScan.inline("*i*", from: 0).contains(.italic(NSRange(location: 1, length: 1))))

    // toggleTask
    let t1 = EditOps.toggleTask("- [ ] go", at: 3)
    check("toggle on", t1?.text == "- [x] go", t1?.text ?? "nil")
    let t2 = EditOps.toggleTask("- [x] go", at: 0)
    check("toggle off", t2?.text == "- [ ] go")
    check("toggle on body is nil", EditOps.toggleTask("plain", at: 2) == nil)

    // returnKey
    let r1 = EditOps.returnKey("- [x] done", selection: NSRange(location: 10, length: 0))
    check("task continues unchecked", r1?.text == "- [x] done\n- [ ] ", r1?.text ?? "nil")
    let r2 = EditOps.returnKey("- ", selection: NSRange(location: 2, length: 0))
    check("empty item ends list", r2?.text == "", r2?.text ?? "nil")
    let r3 = EditOps.returnKey("2. b", selection: NSRange(location: 4, length: 0))
    check("ordered continues counting", r3?.text == "2. b\n3. ")
    check(
        "mid-line return is plain",
        EditOps.returnKey("- item", selection: NSRange(location: 3, length: 0)) == nil)
    check(
        "body return is plain",
        EditOps.returnKey("words", selection: NSRange(location: 5, length: 0)) == nil)

    // setBlock
    let b1 = EditOps.setBlock("title", selection: NSRange(location: 0, length: 0), verb: .headingCycle)
    check("cycle to h1", b1.text == "# title", b1.text)
    let b2 = EditOps.setBlock(b1.text, selection: NSRange(location: 0, length: 0), verb: .headingCycle)
    check("cycle to h2", b2.text == "## title")
    let b3 = EditOps.setBlock("### t", selection: NSRange(location: 0, length: 0), verb: .headingCycle)
    check("cycle off after h3", b3.text == "t")
    let b4 = EditOps.setBlock("a\nb", selection: NSRange(location: 0, length: 3), verb: .task)
    check("two lines become tasks", b4.text == "- [ ] a\n- [ ] b", b4.text)
    let b5 = EditOps.setBlock(b4.text, selection: b4.selection, verb: .task)
    check("task toggles off", b5.text == "a\nb", b5.text)
    let b6 = EditOps.setBlock("- x", selection: NSRange(location: 0, length: 0), verb: .quote)
    check("bullet swaps to quote", b6.text == "> x")
    // lineStart — the wire's line index → a buffer location (phase 3).
    check("line 0 starts at 0", EditOps.lineStart("a\nb\nc", line: 0) == 0)
    check("line 1 after one newline", EditOps.lineStart("a\nb\nc", line: 1) == 2)
    check("line 2", EditOps.lineStart("a\nb\nc", line: 2) == 4)
    check("no line 3", EditOps.lineStart("a\nb\nc", line: 3) == nil)
    check("empty buffer has line 0", EditOps.lineStart("", line: 0) == 0)
    check("blank middle line counts", EditOps.lineStart("a\n\nc", line: 2) == 3)
    check("a trailing newline opens one empty line", EditOps.lineStart("a\n", line: 1) == 2)
    check("but not two", EditOps.lineStart("a\n", line: 2) == nil)
    check("negative is nothing", EditOps.lineStart("a", line: -1) == nil)
    check(
        "a wire line index toggles the right box",
        {
            let text = "notes\n- [ ] first\n- [ ] second"
            guard let at = EditOps.lineStart(text, line: 2),
                let out = EditOps.toggleTask(text, at: at)
            else { return false }
            return out.text == "notes\n- [ ] first\n- [x] second"
        }())

    let b7 = EditOps.setBlock("line", selection: NSRange(location: 4, length: 0), verb: .rule)
    check("rule inserts below", b7.text == "line\n---\n", b7.text)
    check(
        "caret lands AFTER the rule, on a fresh line",
        b7.selection == NSRange(location: 9, length: 0),
        "\(b7.selection)")

    // toggleInline
    let i1 = EditOps.toggleInline("pick me", selection: NSRange(location: 5, length: 2), marker: "**")
    check("wrap bold", i1.text == "pick **me**", i1.text)
    let i2 = EditOps.toggleInline(i1.text, selection: i1.selection, marker: "**")
    check("unwrap bold", i2.text == "pick me", i2.text)
    let i3 = EditOps.toggleInline("x", selection: NSRange(location: 1, length: 0), marker: "*")
    check("empty caret lands inside", i3.text == "x**" && i3.selection.location == 2)

    // indent
    let d1 = EditOps.indent("a\nb", selection: NSRange(location: 0, length: 3), out: false)
    check("indent both", d1.text == "  a\n  b")
    let d2 = EditOps.indent(d1.text, selection: d1.selection, out: true)
    check("outdent both", d2.text == "a\nb")

    // audit round: tabs survive, heading keeps indent, multi-line inline,
    // overflowing ref digits stay text, display titles drop markers
    let tab = EditOps.returnKey("\t- item", selection: NSRange(location: 7, length: 0))
    check("tab indent survives return", tab?.text == "\t- item\n\t- ", tab?.text ?? "nil")
    let hIndent = EditOps.setBlock(
        "  note", selection: NSRange(location: 2, length: 0), verb: .headingCycle)
    check("heading keeps indent", hIndent.text == "  # note", hIndent.text)
    let multi = EditOps.toggleInline(
        "a\nb", selection: NSRange(location: 0, length: 3), marker: "**")
    check("multi-line wraps per line", multi.text == "**a**\n**b**", multi.text)
    check(
        "overflow digits are not a link",
        !MarkScan.inline("[[99999999999999999999999]]", from: 0).contains { run in
            if case .refToken = run { return true } else { return false }
        })
    check("title drops heading marker", livDisplayTitle("# Trip planning") == "Trip planning")
    check("title drops task marker", livDisplayTitle("- [ ] Call the bank") == "Call the bank")
    check(
        "title drops inline markers",
        livDisplayTitle("**Pack** the `van` for [[4155|Kitchen rebuild]]")
            == "Pack the van for Kitchen rebuild")
    check("plain title unchanged", livDisplayTitle("Call the dentist") == "Call the dentist")
    check("rule line titles empty", livDisplayTitle("---") == "")

    // phase 2: the [[ picker, link completion, outline
    check(
        "open link found",
        MarkScan.openLink("see [[kit", caret: 9)
            == OpenLink(range: NSRange(location: 4, length: 5), query: "kit"))
    check("open link with empty query", MarkScan.openLink("a [[", caret: 4)?.query == "")
    check("closed link is not open", MarkScan.openLink("see [[42]] now", caret: 14) == nil)
    check("single bracket is not a link", MarkScan.openLink("a [x", caret: 4) == nil)
    check(
        "link does not cross lines",
        MarkScan.openLink("[[a\nplain", caret: 9) == nil)
    check("a pipe ends the picker", MarkScan.openLink("[[42|na", caret: 7) == nil)
    let done = EditOps.completeLink(
        "see [[kit", token: NSRange(location: 4, length: 5), id: 4155, name: "Kitchen rebuild")
    check("link completes", done.text == "see [[4155|Kitchen rebuild]]", done.text)
    check("caret lands after the token", done.selection.location == (done.text as NSString).length)
    let noName = EditOps.completeLink(
        "x [[q", token: NSRange(location: 2, length: 3), id: 7, name: "  ")
    check("nameless token when the name is blank", noName.text == "x [[7]]", noName.text)
    let outline = livOutline("# One\nbody\n### Three\n- not a heading\n## Two")
    check("outline finds three headings", outline.count == 3, "\(outline.count)")
    check("outline keeps levels", outline.map(\.level) == [1, 3, 2], "\(outline.map(\.level))")
    check("outline strips markers", outline.first?.title == "One", outline.first?.title ?? "nil")

    // the codec demotes ids the box does not hold (ruling 5)
    check(
        "unknown id saves as text",
        SpanText.textToSpans("see [[999]]", isKnown: { _ in false })
            == [.text("see [[999]]", marks: 0)])
    check(
        "known id still saves as a ref",
        SpanText.textToSpans("see [[999]]", isKnown: { $0 == 999 })
            == [.text("see ", marks: 0), .ref(999)])

    return failures
}
