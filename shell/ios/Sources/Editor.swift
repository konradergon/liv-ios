// liv iOS — the note editor (design/ios.md §9, M3: "notes on the phone").
// The phone could capture a thought but not read it back; this is the
// surface that closes that hole. One entity's content, in the phone's own
// box, through liv_content_at / liv_set_content_at with the core's
// fingerprint compare-and-swap. No sync is involved anywhere here.
//
// The phone's buffer is PLAIN TEXT — a UITextView, not the desktop's
// TextKit stack. So the codec below is deliberately narrow and honest:
//
//   Text spans   ⇄ the characters themselves          (exact)
//   Break spans  ⇄ newlines                           (structure kept,
//                                                      block kind flattened)
//   Ref spans    ⇄ "[[id|Display Name]]" tokens       (EXACT — the id is
//                                                      what is stored; the
//                                                      name is cosmetic)
//
// A plain-text editor that dropped Ref spans would silently cut a note's
// links, so the token carries the id and nothing else matters. A mangled
// or deleted token is an ordinary edit: deleting it deletes the link,
// mangling it leaves literal text. Names are NEVER resolved back to ids —
// the editor never guesses.

import Combine
import Foundation
import SwiftUI
import os

// MARK: - spans (the log's own serde encoding; decoding is TOTAL)

/// The core's block vocabulary (core/src/value.rs `Block`), at FULL
/// fidelity. Until 2026-08-11 this was two cases — body and "other" —
/// because the codec flattened everything anyway (the recorded
/// deviation). Now the phone writes what the core stores. `.other`
/// remains for the shapes this editor cannot hold (Code fences,
/// Callouts, and whatever the core grows later): they still flatten,
/// behind the same banner as before.
enum BlockJSON: Equatable {
    case body
    case heading(Int)  // 1...6
    case quote
    case bullet(depth: Int)
    case ordered(depth: Int)
    case task(depth: Int, done: Bool)
    case rule
    case other
}

enum SpanJSON: Equatable {
    case text(String, marks: UInt8)
    case brk(BlockJSON)
    case ref(UInt64)
}

extension SpanJSON: Codable {
    private enum CodingKeys: String, CodingKey { case Text, Break, Ref }
    private struct MarkedText: Decodable {
        var text: String?
        var marks: UInt8?
    }
    /// One-key objects for the payload-carrying Break variants.
    private struct Depthed: Decodable { var depth: UInt8? }
    private struct TaskPayload: Decodable {
        var depth: UInt8?
        var done: Bool?
    }
    private struct BreakObject: Decodable {
        var Heading: UInt8?
        var Bullet: Depthed?
        var Ordered: Depthed?
        var Task: TaskPayload?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.Text) {
            // Bare string (unmarked, the legacy shape) or {text, marks}.
            if let bare = try? c.decode(String.self, forKey: .Text) {
                self = .text(bare, marks: 0)
            } else {
                let m = try? c.decode(MarkedText.self, forKey: .Text)
                self = .text(m?.text ?? "", marks: m?.marks ?? 0)
            }
        } else if c.contains(.Break) {
            // serde's external tagging: unit variants ride as a bare
            // string, payload variants as a one-key object. An unknown
            // variant of either shape is `.other` — kept, flattened on
            // save, never a decode failure.
            if let s = try? c.decode(String.self, forKey: .Break) {
                switch s {
                case "Body": self = .brk(.body)
                case "Quote": self = .brk(.quote)
                case "Rule": self = .brk(.rule)
                default: self = .brk(.other)
                }
            } else if let o = try? c.decode(BreakObject.self, forKey: .Break) {
                if let level = o.Heading {
                    self = .brk(.heading(max(1, min(6, Int(level)))))
                } else if let b = o.Bullet {
                    self = .brk(.bullet(depth: Int(b.depth ?? 0)))
                } else if let b = o.Ordered {
                    self = .brk(.ordered(depth: Int(b.depth ?? 0)))
                } else if let t = o.Task {
                    self = .brk(.task(depth: Int(t.depth ?? 0), done: t.done ?? false))
                } else {
                    self = .brk(.other)  // Code, Callout, or newer
                }
            } else {
                self = .brk(.other)
            }
        } else if let id = try? c.decode(UInt64.self, forKey: .Ref) {
            self = .ref(id)
        } else {
            // An unknown span kind: keep the document, lose nothing that was
            // ever displayable. (It cannot be written back — see json().)
            self = .text("", marks: 0)
        }
    }

    /// Encodes exactly what the core's serde parses — pinned by the
    /// self-check against the JSON strings in core/src/value.rs's own
    /// tests. An unmarked run stays the bare string so no fingerprint
    /// moves on untouched text; `.other` encodes as Body, which is only
    /// reachable when saving a doc the banner already said would flatten.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let t, let marks):
            if marks == 0 {
                try c.encode(t, forKey: .Text)
            } else {
                var o = c.nestedContainer(keyedBy: TextKeys.self, forKey: .Text)
                try o.encode(t, forKey: .text)
                try o.encode(marks, forKey: .marks)
            }
        case .brk(let b):
            switch b {
            case .body: try c.encode("Body", forKey: .Break)
            case .quote: try c.encode("Quote", forKey: .Break)
            case .rule: try c.encode("Rule", forKey: .Break)
            case .other: try c.encode("Body", forKey: .Break)
            case .heading(let n):
                var o = c.nestedContainer(keyedBy: BreakKeys.self, forKey: .Break)
                try o.encode(UInt8(n), forKey: .Heading)
            case .bullet(let d):
                var o = c.nestedContainer(keyedBy: BreakKeys.self, forKey: .Break)
                var p = o.nestedContainer(keyedBy: DepthKeys.self, forKey: .Bullet)
                try p.encode(UInt8(d), forKey: .depth)
            case .ordered(let d):
                var o = c.nestedContainer(keyedBy: BreakKeys.self, forKey: .Break)
                var p = o.nestedContainer(keyedBy: DepthKeys.self, forKey: .Ordered)
                try p.encode(UInt8(d), forKey: .depth)
            case .task(let d, let done):
                var o = c.nestedContainer(keyedBy: BreakKeys.self, forKey: .Break)
                var p = o.nestedContainer(keyedBy: TaskKeys.self, forKey: .Task)
                try p.encode(UInt8(d), forKey: .depth)
                try p.encode(done, forKey: .done)
            }
        case .ref(let id):
            try c.encode(id, forKey: .Ref)
        }
    }

    private enum TextKeys: String, CodingKey { case text, marks }
    private enum BreakKeys: String, CodingKey { case Heading, Bullet, Ordered, Task }
    private enum DepthKeys: String, CodingKey { case depth }
    private enum TaskKeys: String, CodingKey { case depth, done }
}

// MARK: - the codec: two pure functions, independently testable

/// spans ⇄ plain text. Pure: no box, no view, no state. The self-check at
/// the bottom of this file exercises them.
enum SpanText {
    /// A Ref span in the buffer. The id is the whole payload; the display
    /// name is cosmetic and re-derived on every load, so flattening its
    /// newlines and spacing out its brackets costs nothing.
    ///
    /// EVERY "]" is spaced, not just a "]]" pair. The pair rule was
    /// non-overlapping, so a name merely ENDING in "]" — "Q3 [final]",
    /// or any untitled note whose first line ends that way — rendered
    /// `[[4155|Q3 [final]]]`, whose first "]]" is the name's bracket plus
    /// the token's. The scanner closed there, the leftover "]" fell into
    /// the note as text, and it compounded: one bracket per save, five
    /// saves gave "]]]]] today" (measured, 2026-08-11).
    static func token(_ id: UInt64, name: String?) -> String {
        let raw = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "[[\(id)]]" }
        let clean =
            raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "]", with: "] ")
        return "[[\(id)|\(clean)]]"
    }

    /// Spans → the editing buffer. A Break opens a paragraph, so a LEADING
    /// break writes no newline (mirrors the macOS codec's openParagraph):
    /// the span model cannot express an empty first paragraph.
    ///
    /// Since 2026-08-11 the block RENDERS as its marker — `Heading(2)`
    /// becomes "## ", `Task{done}` becomes "- [x] " — and marks render
    /// their delimiters. The markers live only in the buffer; the box
    /// stores the structure. Ordered numbers are presentation: each
    /// consecutive run counts from 1, per depth, whatever was typed.
    static func spansToText(
        _ spans: [SpanJSON], name: (UInt64) -> String? = { _ in nil }
    ) -> String {
        var out = ""
        var wrote = false
        // Ordered-list counters, one per depth, cleared by any
        // non-ordered paragraph.
        var counters: [Int] = []
        for span in spans {
            switch span {
            case .brk(let block):
                if wrote { out.append("\n") }
                wrote = true
                if case .ordered(let d) = block {
                    let depth = max(0, d)
                    if counters.count > depth + 1 { counters.removeLast(counters.count - depth - 1) }
                    while counters.count < depth + 1 { counters.append(0) }
                    counters[depth] += 1
                    out += indent(depth) + "\(counters[depth]). "
                } else {
                    counters.removeAll()
                    out += marker(block)
                }
            case .text(let t, let marks):
                wrote = true
                out += delimited(t, marks: marks)
            case .ref(let id):
                wrote = true
                out += token(id, name: name(id))
            }
        }
        return out
    }

    private static func indent(_ depth: Int) -> String {
        String(repeating: "  ", count: max(0, min(15, depth)))
    }

    private static func marker(_ block: BlockJSON) -> String {
        switch block {
        case .body, .other: return ""
        case .heading(let n): return String(repeating: "#", count: max(1, min(6, n))) + " "
        case .quote: return "> "
        case .rule: return "---"
        case .bullet(let d): return indent(d) + "- "
        case .task(let d, let done): return indent(d) + (done ? "- [x] " : "- [ ] ")
        case .ordered(let d): return indent(d) + "1. "  // spansToText renumbers
        }
    }

    /// A run's delimiters, outermost to innermost: ~~ ** * `. Single
    /// marks are the whole supported set — the scanner is flat, so a
    /// combination cannot be re-derived and carriesFormatting says so.
    private static func delimited(_ t: String, marks: UInt8) -> String {
        var out = t
        if marks & 4 != 0 { out = "`\(out)`" }
        if marks & 2 != 0 { out = "*\(out)*" }
        if marks & 1 != 0 { out = "**\(out)**" }
        if marks & 8 != 0 { out = "~~\(out)~~" }
        return out
    }

    /// The editing buffer → spans, through the ONE scanner (MarkScan) the
    /// styler renders with — so what you see on screen and what the box
    /// stores can never disagree. Each line's block marker becomes its
    /// Break; each inline delimiter pair becomes a mark bit; each
    /// well-formed "[[id]]" token becomes a Ref. An empty buffer is NO
    /// spans — which removes the content cell, exactly as the seam
    /// documents.
    ///
    /// `isKnown` demotes tokens whose id is not in this box to literal
    /// text (owner ruling 5, 2026-07-30). The core refuses a whole save
    /// that carries a Ref to nothing (`services/src/content.rs`), so
    /// pasting a note containing "[[123]]" from elsewhere used to loop
    /// forever on "The box refused this save". The characters stay exactly
    /// as typed — only their meaning is demoted.
    static func textToSpans(
        _ text: String, isKnown: (UInt64) -> Bool = { _ in true }
    ) -> [SpanJSON] {
        var out: [SpanJSON] = []
        for (i, line) in text.components(separatedBy: "\n").enumerated() {
            let shape = MarkScan.shape(line)
            let block = blockJSON(of: shape, line: line)
            if i > 0 {
                out.append(.brk(block))
            } else if block != .body {
                // A non-body FIRST paragraph needs its leading Break —
                // the core counts lines the same way ("a leading break
                // opens no line", services/src/tasks.rs).
                out.append(.brk(block))
            }
            if case .rule = shape.block { continue }  // the marker IS the line
            let content = (line as NSString).substring(from: shape.marker.length)
            out.append(contentsOf: lineSpans(content, isKnown: isKnown))
        }
        return out
    }

    /// LineShape → wire block. Depth counts the buffer's own indent
    /// unit: one tab or two spaces per level (EditOps.indentUnit); a
    /// lone leftover space floors.
    private static func blockJSON(of shape: LineShape, line: String) -> BlockJSON {
        func depth() -> Int {
            let u = Array(line.utf16)
            var units = 0
            var i = 0
            while i < u.count {
                if u[i] == 0x09 { units += 1; i += 1 }
                else if u[i] == 0x20, i + 1 < u.count, u[i + 1] == 0x20 { units += 1; i += 2 }
                else { break }
            }
            return min(15, units)
        }
        switch shape.block {
        case .body: return .body
        case .heading(let n): return .heading(n)
        case .bullet: return .bullet(depth: depth())
        case .ordered: return .ordered(depth: depth())  // the number is presentation
        case .task(let checked): return .task(depth: depth(), done: checked)
        case .quote: return .quote
        case .rule: return .rule
        }
    }

    /// One line's content (after the block marker) → spans, off
    /// MarkScan.inline's runs: delimiters are dropped, their content
    /// carries the mark bit, ref tokens become Refs (or stay literal
    /// when unknown). Plain stretches between runs are plain text.
    private static func lineSpans(
        _ content: String, isKnown: (UInt64) -> Bool
    ) -> [SpanJSON] {
        let n = content as NSString
        var out: [SpanJSON] = []
        var plain = ""
        func flush() {
            if !plain.isEmpty { out.append(.text(plain, marks: 0)) }
            plain = ""
        }
        var cursor = 0
        for run in MarkScan.inline(content, from: 0) {
            let range: NSRange
            let marks: UInt8
            switch run {
            case .marker(let r):
                if r.location > cursor {
                    plain += n.substring(with: NSRange(location: cursor, length: r.location - cursor))
                }
                cursor = NSMaxRange(r)
                continue
            case .bold(let r): range = r; marks = 1
            case .italic(let r): range = r; marks = 2
            case .code(let r): range = r; marks = 4
            case .strike(let r): range = r; marks = 8
            case .refToken(let r, _):
                if r.location > cursor {
                    plain += n.substring(with: NSRange(location: cursor, length: r.location - cursor))
                }
                let tokenText = n.substring(with: r)
                if let (id, _) = token(Array(tokenText), from: 0), isKnown(id) {
                    flush()
                    out.append(.ref(id))
                } else {
                    plain += tokenText  // demoted: the characters stay
                }
                cursor = NSMaxRange(r)
                continue
            }
            if range.location > cursor {
                plain += n.substring(with: NSRange(location: cursor, length: range.location - cursor))
            }
            flush()
            out.append(.text(n.substring(with: range), marks: marks))
            cursor = NSMaxRange(range)
        }
        if cursor < n.length {
            plain += n.substring(from: cursor)
        }
        flush()
        return out
    }

    static func json(_ spans: [SpanJSON]) -> String {
        let encoder = JSONEncoder()
        // Deterministic key order: serde happens to declare fields
        // alphabetically (depth, done), so sorted keys reproduce its
        // exact output and the self-check can pin the wire strings.
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(spans) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    /// True when the stored spans carry something the buffer cannot hold,
    /// so the editor can say so before a save flattens it — it never
    /// flattens silently.
    ///
    /// The question is LOSS, not change. A whole-document round trip
    /// cannot tell the two apart: a legacy note holding the literal text
    /// `- [x] Slides` comes back as a real `Task` block, which changes
    /// the stored value and loses NOTHING — it is the promotion this
    /// codec exists to do. Comparing documents flagged every old note in
    /// the box with a banner saying the editor could not keep what it
    /// was about to keep perfectly well (seen on the simulator,
    /// 2026-08-11). So each way of losing something is asked about
    /// directly, and each is decided by RENDERING AND RESCANNING the
    /// piece in question rather than by reasoning about delimiters.
    ///
    /// KNOWN AND ACCEPTED: an ESCAPED marker — `\#` in a vault note,
    /// which the Rust importer stores as Body text beginning `# ` — is
    /// indistinguishable at this layer from a legacy note's literal
    /// marker, and is promoted to a heading rather than flagged. Old
    /// notes are the common case by orders of magnitude; a banner on
    /// every one of them to catch an escaped hash is the wrong trade.
    static func carriesFormatting(
        _ spans: [SpanJSON],
        name: (UInt64) -> String? = { _ in nil },
        isKnown: (UInt64) -> Bool = { _ in true }
    ) -> Bool {
        spans.contains { span in
            switch span {
            case .brk(let b):
                // Code and Callout have no buffer form at all.
                return b == .other
            case .text(let t, let marks):
                // An UNMARKED run is only ever text, whatever it holds —
                // including raw newlines, which older writers put in one
                // span (the core's own model says a Text never contains
                // one, so splitting it into paragraphs is another
                // promotion, not a loss). A MARKED run carrying a
                // newline IS a loss, and the round trip below catches it
                // without a rule of its own: "**a\nb**" rescans as two
                // paragraphs of literal asterisks.
                guard marks != 0 else { return false }
                return roundTrip([.text(t, marks: marks)]) != [.text(t, marks: marks)]
            case .ref(let id):
                // The display name lands INSIDE the token's delimiters,
                // and the shell's "is this known" is narrower than the
                // core's — both can turn a link back into text.
                return roundTrip([.ref(id)], name: name, isKnown: isKnown) != [.ref(id)]
            }
        }
    }

    private static func roundTrip(
        _ spans: [SpanJSON],
        name: (UInt64) -> String? = { _ in nil },
        isKnown: (UInt64) -> Bool = { _ in true }
    ) -> [SpanJSON] {
        normalised(textToSpans(spansToText(spans, name: name), isKnown: isKnown))
    }

    /// A LEADING Body break is not structure: it opens the first
    /// paragraph, which the buffer opens anyway ("a leading break opens
    /// no line", services/src/tasks.rs). Two values differing only by
    /// one are the same document, so the comparison ignores it.
    private static func normalised(_ spans: [SpanJSON]) -> [SpanJSON] {
        guard case .brk(.body) = spans.first else { return spans }
        return Array(spans.dropFirst())
    }

    /// "[[" digits ("|" anything-without-"]]")? "]]" — or nil, and the "[["
    /// stays literal text. Never lenient: a half-typed token is text.
    private static func token(_ c: [Character], from start: Int) -> (UInt64, Int)? {
        var i = start + 2
        var digits = ""
        while i < c.count, c[i].isASCII, c[i].isNumber {
            digits.append(c[i])
            i += 1
        }
        guard !digits.isEmpty, let id = UInt64(digits) else { return nil }
        if i + 1 < c.count, c[i] == "]", c[i + 1] == "]" { return (id, i + 2) }
        guard i < c.count, c[i] == "|" else { return nil }
        i += 1
        while i + 1 < c.count {
            if c[i] == "]", c[i + 1] == "]" { return (id, i + 2) }
            i += 1
        }
        return nil
    }
}

// MARK: - the model: one draft of one entity, the loss budget copied

enum SaveOutcome {
    case clean, saved, stale, busy, invalid
}

/// The editor's whole state machine. Every save presents the base
/// fingerprint back to the seam — a save is to a value, never a moment —
/// and a refused (stale) save NEVER overwrites: the fresh content comes
/// back, the draft waits in memory behind a banner.
final class NoteEditorModel: ObservableObject {
    /// The editing buffer. The one place the user's words live.
    @Published var text = ""
    @Published private(set) var loaded = false
    /// The box opened and holds no such entity.
    @Published private(set) var missing = false
    /// The base moved under a draft; the buffer shows the box's truth and
    /// `draft` holds the user's words, one tap from being re-applied.
    @Published private(set) var conflicted = false
    /// The stored content carries blocks or marks a plain buffer cannot
    /// hold. Said out loud, never flattened in silence.
    @Published private(set) var flattens = false
    /// A save the box refused for its own reasons (a Ref to something not
    /// in this box is the realistic one). Stays dirty; retries on the next
    /// keystroke or flush.
    @Published private(set) var saveFailed = false
    @Published private(set) var savedOnce = false

    private(set) var draft: String?
    private(set) var base: UInt64 = 0

    /// What the box holds right now, as text. Dirty is a comparison, so a
    /// note that is merely READ is never re-written — no open-and-flatten.
    private var storedText = ""
    var dirty: Bool { loaded && !missing && text != storedText }

    private weak var box: BoxModel?
    private var id: UInt64 = 0
    private var idleTimer: Timer?
    private var checkpointTimer: Timer?
    private var saving = false
    private var queued: [(SaveOutcome) -> Void] = []
    private var stopped = false

    private static let log = Logger(subsystem: "app.liv.ios", category: "editor")

    // MARK: lifecycle

    func attach(box: BoxModel, id: UInt64) {
        guard self.box == nil else {
            // Re-appear after a full-screen cover (a feature window, the
            // tab view, search, the camera): the cover fired onDisappear →
            // stop(), so re-arm and catch up on anything the box did while
            // covered. Without this the editor stopped following the box
            // for the rest of the tab's life.
            stopped = false
            snapshotArrived()
            return
        }
        self.box = box
        self.id = id
        load()
    }

    /// Tab switch / dismiss: flush first (never lose text), then disarm.
    func stop() {
        flush()
        stopped = true
        idleTimer?.invalidate()
        checkpointTimer?.invalidate()
        idleTimer = nil
        checkpointTimer = nil
    }

    private func title(_ target: UInt64) -> String? {
        guard let row = box?.entity(target), let t = row.title, !t.isEmpty else { return nil }
        return t
    }

    func load() {
        guard let box = box, !stopped else { return }
        box.content(id) { [weak self] doc in
            guard let self = self else { return }
            guard let doc = doc else {
                // The box would not open — that says nothing about the note.
                // Stay unloaded (the buffer stays read-only, so no words can
                // land in limbo) and try again shortly.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self = self, !self.loaded, !self.stopped else { return }
                    self.load()
                }
                return
            }
            if doc.missing == true {
                self.missing = true
                self.loaded = true
                return
            }
            let spans = doc.spans ?? []
            self.base = doc.fingerprint ?? 0
            self.flattens = SpanText.carriesFormatting(
                spans,
                name: { [weak self] in self?.title($0) },
                isKnown: { [weak box] id in box?.entity(id) != nil })
            let fresh = SpanText.spansToText(spans, name: { [weak self] in self?.title($0) })
            self.storedText = fresh
            self.text = fresh
            self.loaded = true
        }
    }

    // MARK: typing → transactions (the macOS loss budget, verbatim)

    /// A keystroke arms two clocks: 2s of idle commits the burst, and a 30s
    /// checkpoint bounds the loss under unbroken typing. Background, tab
    /// switch and dismiss flush outright.
    func textChanged() {
        guard loaded, !missing else { return }
        idleTimer?.invalidate()
        guard dirty else {
            checkpointTimer?.invalidate()
            checkpointTimer = nil
            return
        }
        saveFailed = false
        idleTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) {
            [weak self] _ in
            self?.flush()
        }
        if checkpointTimer == nil {
            checkpointTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) {
                [weak self] _ in
                self?.checkpointTimer = nil
                self?.flush()
            }
        }
    }

    func flush(_ done: ((SaveOutcome) -> Void)? = nil) {
        guard let box = box, loaded, !missing else {
            done?(.invalid)
            return
        }
        guard dirty else {
            done?(.clean)
            return
        }
        if saving {
            // Coalesce: one follow-up runs with then-current text and base
            // and answers every queued caller. A save must never race its
            // own predecessor's base.
            if let done = done { queued.append(done) }
            return
        }
        saving = true
        idleTimer?.invalidate()
        checkpointTimer?.invalidate()
        checkpointTimer = nil
        let payload = text
        // Ruling 5: a token pointing at nothing in THIS box saves as text,
        // never as a Ref the core would refuse.
        let known: (UInt64) -> Bool = { [weak box] id in box?.entity(id) != nil }
        let spans = SpanText.textToSpans(payload, isKnown: known)
        attempt(box: box, json: SpanText.json(spans), payload: payload, base: base, retries: 3) {
            [weak self] outcome in
            guard let self = self else {
                done?(outcome)
                return
            }
            self.saving = false
            done?(outcome)
            let waiting = self.queued
            self.queued = []
            if !waiting.isEmpty {
                self.flush { follow in waiting.forEach { $0(follow) } }
            }
        }
    }

    /// The base rides with the payload, captured together in flush(): a
    /// retry may never re-read a base that moved under it.
    private func attempt(
        box: BoxModel, json: String, payload: String, base: UInt64, retries: Int,
        done: @escaping (SaveOutcome) -> Void
    ) {
        box.setContent(id, spansJson: json, base: base) { [weak self] status, fresh in
            guard let self = self else {
                done(.busy)
                return
            }
            switch status {
            case 1:
                self.base = fresh
                // What the box now holds. Anything typed since stays dirty
                // by comparison — no generation counter needed.
                self.storedText = payload
                self.flattens = false  // the stored value is this plain text now
                self.conflicted = false
                self.saveFailed = false
                self.savedOnce = true
                done(.saved)
            case -1:
                self.stale(done: done)
            default:
                if retries > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                        guard let self = self else {
                            done(.busy)
                            return
                        }
                        self.attempt(
                            box: box, json: json, payload: payload, base: base,
                            retries: retries - 1, done: done)
                    }
                } else {
                    Self.log.notice("content save refused for \(self.id, privacy: .public)")
                    self.saveFailed = true
                    done(.busy)
                }
            }
        }
    }

    /// The core's compare-and-swap said no. Do NOT overwrite: re-read, show
    /// the box's truth, and keep the whole live buffer as a draft the user
    /// can re-apply. There is no force flag by design.
    private func stale(done: @escaping (SaveOutcome) -> Void) {
        guard let box = box else {
            done(.stale)
            return
        }
        let mine = text  // the LIVE buffer, not the payload: never lose keystrokes
        box.content(id) { [weak self] doc in
            guard let self = self else {
                done(.stale)
                return
            }
            guard let doc = doc, doc.missing != true else {
                if doc?.missing == true { self.missing = true }
                self.draft = mine
                self.conflicted = true
                done(.stale)
                return
            }
            let spans = doc.spans ?? []
            self.base = doc.fingerprint ?? 0
            self.flattens = SpanText.carriesFormatting(
                spans,
                name: { [weak self] in self?.title($0) },
                isKnown: { [weak box] id in box?.entity(id) != nil })
            let theirs = SpanText.spansToText(spans, name: { [weak self] in self?.title($0) })
            self.draft = mine
            self.storedText = theirs
            self.text = theirs
            self.conflicted = true
            done(.stale)
        }
    }

    /// Keep mine: the draft returns to the buffer over the fresh base, and
    /// saves the ordinary way (re-read then save — the seam's only overwrite).
    func reapplyDraft() {
        guard let draft = draft else { return }
        text = draft
        self.draft = nil
        conflicted = false
        flush()
    }

    /// Keep theirs: the draft is discarded deliberately, by the user.
    func discardDraft() {
        draft = nil
        conflicted = false
    }

    // MARK: the world moving underneath

    /// Every snapshot answers "did my base move?" for free via
    /// content_print. Clean → silent reload; dirty → flush now, so the CAS
    /// surfaces the conflict through the one stale path.
    func snapshotArrived() {
        guard loaded, !missing, !stopped, let row = box?.entity(id) else { return }
        guard (row.contentPrint ?? 0) != base else { return }
        if dirty || saving {
            flush()
        } else {
            load()
        }
    }
}

// MARK: - the view: the note IS the screen

struct NoteEditor: View {
    let id: UInt64
    /// The note's name cell, edited in the title line that scrolls with
    /// the body (Obsidian's layout — owner, 2026-08-01).
    @Binding var title: String
    var onTitleCommit: () -> Void
    /// A tapped `[[…]]` lands as a desk tab — the shell's one rule for
    /// opening anything from anywhere.
    var onOpenRef: (UInt64) -> Void = { _ in }
    /// A note created a moment ago: open with the caret already in it, so
    /// "Create a note" lands you writing, not looking at a blank screen.
    var autoFocus: Bool = false
    /// Where a template's {{cursor}} asked the caret to land.
    var autoCaret: Int? = nil
    /// A note owns its title line; a record's notes are titled by the
    /// card above them (owner, 2026-08-10: "there is already a note
    /// editor — can this and other app mechanisms be reused?").
    var showsTitle: Bool = true
    /// Sits inside someone else's scroll view and grows to its content,
    /// rather than filling the screen and scrolling itself.
    var embedded: Bool = false

    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var workspaces: WorkspaceModel
    @EnvironmentObject var desk: DeskModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = NoteEditorModel()
    @StateObject private var bridge = EditorBridge()
    @State private var outlineShown = false
    @State private var templatesShown = false
    /// The link door: search, presented to pick what to link to.
    @State private var linkShown = false
    /// Plain state, not @FocusState — the UIKit text view reports focus
    /// through the representable's binding.
    @State private var focused = false

    /// Everything that is not the note gets out of the way while you write
    /// (owner, 2026-07-30): the notices are advisory and can wait. A
    /// conflict is the one exception — it is about the words being typed
    /// right now, so it stays.
    private var writing: Bool { focused }

    /// What the title line shows when the note has no name of its own:
    /// its first line with the markdown markers taken off, or a grey
    /// "Untitled" when there is no first line either (owner,
    /// 2026-08-06). Derived HERE, from the live text, because the title
    /// the core sends is the WHOLE body squashed into one line — a
    /// multi-line note would otherwise propose "Sat 1 Aug ## Today - [ ]
    /// ## Notes" as its name. Empty once a person has named the note:
    /// their title is the title.
    private var derivedPrompt: String {
        // Embedded there is no title line to prompt, and this scans the
        // WHOLE text — on every keystroke, for something never drawn.
        guard showsTitle, title.isEmpty else { return "" }
        let derived = livDisplayTitle(model.text)
        return derived.isEmpty ? "Untitled" : derived
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.conflicted { banner }
            if !writing, model.flattens { notice(
                "This note carries desk formatting this editor can't keep. "
                    + "Saving replaces it with what you see here.") }
            if !writing, model.saveFailed {
                notice("The box refused this save. It will try again.")
            }
            editor
        }
        .animation(LivMotion.nav, value: writing)
        .onAppear {
            model.attach(box: box, id: id)
            if autoFocus {
                focused = true
                if let autoCaret { bridge.scroll(to: autoCaret) }
            }
        }
        .onChange(of: autoFocus) { _, now in
            guard now else { return }
            focused = true
            if let autoCaret { bridge.scroll(to: autoCaret) }
        }
        .onDisappear { model.stop() }
        // A panel or the chooser sliding over a live [[ picker would
        // strand it: the keyboard resigns but the picker floats on.
        // Dismissing HERE (not on every resign) keeps picker-row taps
        // working — they too resign focus for a moment (audit,
        // 2026-08-04). The typed [[ token stays as text, as always.
        .onChange(of: desk.libraryShown || desk.inspectorShown || desk.newTabShown
            || desk.recordCard != nil) { _, up in
            if up { bridge.dismissLink() }
        }
        .onChange(of: model.text) { _, _ in model.textChanged() }
        .onChange(of: focused) { _, now in
            if !now { model.flush() }
        }
        .onChange(of: scenePhase) { _, phase in
            // .inactive comes first and is the reliable one; .background
            // flushes again in case the app went straight there.
            if phase != .active { model.flush() }
        }
        .onReceive(box.$snap) { _ in model.snapshotArrived() }
    }

    // MARK: the buffer — full-bleed, no card, no chrome of its own

    /// No placeholder, no "Write…", no instructional text (owner,
    /// 2026-08-01): an empty note is a blinking caret on a dark page.
    private var editor: some View {
        // The live markdown surface (EditorText.swift). Styling is a
        // pure function of the text; the buffer the codec saves is the
        // same plain string. Swipe down inside the text to dismiss the
        // keyboard (keyboardDismissMode = .interactive).
        MarkdownEditor(
            text: $model.text, focused: $focused,
            title: $title, titlePrompt: derivedPrompt, onTitleCommit: onTitleCommit,
            editable: model.loaded && !model.missing,
            bridge: bridge, onOpenRef: onOpenRef,
            onLink: { linkShown = true },
            onOutline: { outlineShown = true },
            onTemplate: { templatesShown = true },
            showsTitle: showsTitle, embedded: embedded
        )
        .frame(
            maxWidth: .infinity,
            maxHeight: embedded ? nil : .infinity,
            alignment: .topLeading)
        // Typing `[[` is the same door. Dismissing without picking
        // SUPPRESSES that token, so the sheet does not reappear on the
        // brackets you meant literally until the caret leaves them.
        .onChange(of: bridge.openLink) { _, link in
            if link != nil { linkShown = true }
        }
        .sheet(isPresented: $linkShown, onDismiss: { bridge.dismissLink() }) {
            linkSearchSheet
        }
        .sheet(isPresented: $outlineShown) { outlineSheet }
        .sheet(isPresented: $templatesShown) {
            TemplateSheet(verb: .insert) { template in
                box.templateBody(template.id, now: Civil.nowStamp()) { body in
                    guard !body.isEmpty else { return }
                    bridge.insert(body)
                }
            }
            .environmentObject(box)
        }
    }

    // MARK: the link door

    /// Creating a link opens SEARCH (owner, 2026-08-13): the same screen
    /// that finds anything finds what you are linking to, and the whole
    /// `[[id|Name]]` is written for you. Typing `[[` is the shortcut to
    /// the same door — it seeds the query with whatever you had typed.
    ///
    /// What was here before: a four-row picker of its own, with its own
    /// search, its own create row and its own list style. A second
    /// search screen is a second thing to keep true (standing rule 4).
    private var linkSearchSheet: some View {
        SearchView(
            onPick: { id, name in bridge.placeLink(id: id, name: name) },
            seed: bridge.openLink?.query ?? ""
        )
        .environmentObject(box)
        .environmentObject(desk)
        .environmentObject(workspaces)
    }

    // MARK: the outline

    private var outlineSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if bridge.outline.isEmpty {
                    EmptyHint("No headings yet.")
                }
                ForEach(bridge.outline) { item in
                    Button {
                        outlineShown = false
                        bridge.scroll(to: item.id)
                    } label: {
                        HStack(spacing: 8) {
                            Text(item.title)
                                .font(.system(size: LivType.title, weight: item.level == 1 ? .semibold : .regular))
                                .foregroundStyle(item.level == 1 ? LivTheme.text : LivTheme.text2)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, CGFloat(item.level - 1) * 16)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(LivTheme.border).frame(height: 0.5)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .background(LivTheme.canvas)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: the world moved — non-destructive, both truths kept

    private var banner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("This changed elsewhere")
                .font(.system(size: LivType.strong, weight: .semibold))
                .foregroundStyle(LivTheme.text)
            Text("The box's version is shown. Your edit is kept.")
                .font(.system(size: LivType.body))
                .foregroundStyle(LivTheme.text3)
            HStack(spacing: 8) {
                Button("Re-apply my edit") { model.reapplyDraft() }
                    .font(.system(size: LivType.body, weight: .semibold))
                    .foregroundStyle(LivTheme.onAccent)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: LivTheme.radiusSm).fill(LivTheme.accent))
                Button("Keep this one") { model.discardDraft() }
                    .font(.system(size: LivType.body))
                    .foregroundStyle(LivTheme.text2)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: LivTheme.radiusSm).fill(LivTheme.panel2))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: LivTheme.radius).fill(LivTheme.panel))
        .padding(.horizontal, 10)
    }

    /// Advisory notices only — the routine Saved/Unsaved footnote is gone
    /// (owner, 2026-07-31: no informational micro-text). Autosave's honesty
    /// surfaces are the conflict banner and the refusal notice.
    private func notice(_ text: String) -> some View {
        Text(text)
            .font(.system(size: LivType.body))
            .foregroundStyle(LivTheme.text3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: LivTheme.radiusSm).fill(LivTheme.panel2))
            .padding(.horizontal, 10)
    }
}

// MARK: - the codec's self-check (pure in, pure out; no test target here)

/// Round-trips the two pure functions and returns the failures. Run with
/// `simctl launch … app.liv.ios -spans.selfcheck 1` (the launch arg lands
/// in UserDefaults); an empty result is a pass.
func livSpanCodecSelfCheck() -> [String] {
    var failures: [String] = []
    func check(_ label: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        if !ok { failures.append("FAIL \(label) \(detail())") }
    }
    let names: (UInt64) -> String? = { id in id == 4155 ? "Kitchen rebuild" : nil }

    // 1. text → spans → text, over every shape the buffer can hold.
    for sample in [
        "",
        "one line",
        "first\nsecond\nthird",
        "a\n\nb",  // blank paragraph between
        "trailing\n",
        "see [[4155|Kitchen rebuild]] tomorrow",
        "[[7]] leads",
        "not a token [[abc]] nor [[12|half",
        "brackets [ [ ] ] survive",
    ] {
        let round = SpanText.spansToText(SpanText.textToSpans(sample), name: names)
        check("text↔spans", round == sample, "\(sample.debugDescription) → \(round.debugDescription)")
    }

    // 2. spans → text → spans: Text, Ref AND blocks exactly. The v1
    //    "flattens the block" delta is retired (owner, 2026-08-11) —
    //    only `.other` (Code, Callout, unknown) still flattens.
    let refDoc: [SpanJSON] = [
        .text("see ", marks: 0), .ref(4155), .text(" now", marks: 0),
        .brk(.body), .text("line two", marks: 0),
    ]
    check("ref round-trip", SpanText.textToSpans(SpanText.spansToText(refDoc, name: names)) == refDoc)

    let heading: [SpanJSON] = [
        .brk(.heading(1)), .text("Title", marks: 0),
        .brk(.body), .text("body", marks: 0),
    ]
    check(
        "leading heading renders its marker",
        SpanText.spansToText(heading, name: names) == "# Title\nbody",
        SpanText.spansToText(heading, name: names).debugDescription)
    check(
        "heading derives from the buffer",
        SpanText.textToSpans("# Title\nbody") == heading)
    check(
        "other still flattens",
        SpanText.textToSpans(SpanText.spansToText(
            [.brk(.other), .text("x", marks: 0)], name: names))
            == [.text("x", marks: 0)])

    // 2b. Every supported block derives, renders, and round-trips.
    let structural = "# H\nbody\n- [ ] milk\n- [x] paid\n- item\n1. a\n2. b\n> q\n---"
    let structSpans: [SpanJSON] = [
        .brk(.heading(1)), .text("H", marks: 0),
        .brk(.body), .text("body", marks: 0),
        .brk(.task(depth: 0, done: false)), .text("milk", marks: 0),
        .brk(.task(depth: 0, done: true)), .text("paid", marks: 0),
        .brk(.bullet(depth: 0)), .text("item", marks: 0),
        .brk(.ordered(depth: 0)), .text("a", marks: 0),
        .brk(.ordered(depth: 0)), .text("b", marks: 0),
        .brk(.quote), .text("q", marks: 0),
        .brk(.rule),
    ]
    check(
        "structural derive", SpanText.textToSpans(structural) == structSpans,
        "\(SpanText.textToSpans(structural))")
    check(
        "structural render", SpanText.spansToText(structSpans, name: names) == structural,
        SpanText.spansToText(structSpans, name: names).debugDescription)

    // 2c. Depth: two spaces or one tab per level; a lone space floors.
    check("two spaces is depth 1",
        SpanText.textToSpans("  - deep") == [.brk(.bullet(depth: 1)), .text("deep", marks: 0)])
    check("tab is depth 1",
        SpanText.textToSpans("\t- deep") == [.brk(.bullet(depth: 1)), .text("deep", marks: 0)])
    check("lone space floors to 0",
        SpanText.textToSpans(" - x") == [.brk(.bullet(depth: 0)), .text("x", marks: 0)])
    check("depth renders as two spaces",
        SpanText.spansToText([.brk(.task(depth: 1, done: false)), .text("b", marks: 0)], name: names)
            == "  - [ ] b")
    check("body keeps its literal indent",
        SpanText.textToSpans("  foo") == [.text("  foo", marks: 0)])

    // 2d. Ordered numbering is canonical: derived numbers are dropped,
    //     rendering counts each consecutive run per depth from 1.
    check("typed numbers are presentation",
        SpanText.spansToText(SpanText.textToSpans("7. a\n8. b"), name: names) == "1. a\n2. b")
    check("nested ordered counts per depth",
        SpanText.spansToText([
            .brk(.ordered(depth: 0)), .text("a", marks: 0),
            .brk(.ordered(depth: 1)), .text("b", marks: 0),
            .brk(.ordered(depth: 0)), .text("c", marks: 0),
        ], name: names) == "1. a\n  1. b\n2. c")

    // 2e. Inline marks: the four single marks derive and render; the
    //     delimiter characters live in the buffer, never in the box.
    check("bold derives",
        SpanText.textToSpans("**b** and `c`") == [
            .text("b", marks: 1), .text(" and ", marks: 0), .text("c", marks: 4),
        ])
    check("italic and strike derive",
        SpanText.textToSpans("*i* ~~s~~") == [
            .text("i", marks: 2), .text(" ", marks: 0), .text("s", marks: 8),
        ])
    check("marks render their delimiters",
        SpanText.spansToText([
            .text("b", marks: 1), .text(" ", marks: 0), .text("s", marks: 8),
        ], name: names) == "**b** ~~s~~")
    check("unclosed marker stays literal",
        SpanText.textToSpans("**x") == [.text("**x", marks: 0)])
    check("marks round-trip through the buffer",
        SpanText.textToSpans(SpanText.spansToText([
            .brk(.task(depth: 0, done: false)), .text("call ", marks: 0),
            .ref(4155), .text(" ", marks: 0), .text("now", marks: 1),
        ], name: names)) == [
            .brk(.task(depth: 0, done: false)), .text("call ", marks: 0),
            .ref(4155), .text(" ", marks: 0), .text("now", marks: 1),
        ])

    // 2f. What still cannot be held says so — and ONLY that.
    check("plain structure is not flagged", !SpanText.carriesFormatting(structSpans))
    check("single marks are not flagged",
        !SpanText.carriesFormatting([.text("b", marks: 1)]))
    check("other is flagged", SpanText.carriesFormatting([.brk(.other)]))
    check("combined marks are flagged",
        SpanText.carriesFormatting([.text("x", marks: 3)]))
    check("a delimiter inside its own mark is flagged",
        SpanText.carriesFormatting([.text("a**b", marks: 1)]))
    check("an empty marked run is flagged",
        SpanText.carriesFormatting([.text("", marks: 1)]))
    check("a trailing star inside bold is flagged",
        SpanText.carriesFormatting([.text("a*", marks: 1)]))
    check("a mid-run star inside bold is fine",
        !SpanText.carriesFormatting([.text("a*b", marks: 1)]))
    check("a newline in plain text is not flagged",
        !SpanText.carriesFormatting([.text("a\nb", marks: 0)]))
    check("a whole legacy note in one span is not flagged",
        !SpanText.carriesFormatting([.text("- milk\n- bread\n# H", marks: 0)]))
    check("a newline inside a MARKED run is flagged",
        SpanText.carriesFormatting([.text("a\nb", marks: 1)]))
    check("a ref-lookalike inside bold is fine",
        !SpanText.carriesFormatting([.text("[[7]]", marks: 1)]))
    // A legacy note — literal markers as Body text — is the COMMON case
    // and must NOT be flagged: it is promoted, not flattened. The
    // escaped-marker case rides along with it, knowingly (see
    // carriesFormatting's note).
    check("a legacy marker line is not flagged",
        !SpanText.carriesFormatting([.text("- [x] Slides", marks: 0)]))
    check("a legacy heading line is not flagged",
        !SpanText.carriesFormatting([.text("# Plan", marks: 0)]))
    check("a whole legacy note is not flagged",
        !SpanText.carriesFormatting([
            .text("# H", marks: 0), .brk(.body), .text("- [ ] milk", marks: 0),
        ]))
    check("a hash mid-line is fine",
        !SpanText.carriesFormatting([.text("a # b", marks: 0)]))
    check("a heading whose text starts with a hash survives",
        !SpanText.carriesFormatting([.brk(.heading(1)), .text("# real", marks: 0)]))
    check("a leading body break is not structure",
        !SpanText.carriesFormatting([.brk(.body), .text("plain", marks: 0)]))
    check("the structural corpus survives the round trip",
        !SpanText.carriesFormatting(structSpans))
    check("a ref survives the round trip",
        !SpanText.carriesFormatting(refDoc))

    // 2h. A DISPLAY NAME is attacker-shaped text: it lands inside the
    //     token's own delimiters, so any "]" in it can close the token
    //     early. The buffer must survive being written with the name and
    //     read back — repeatedly, since a leak compounds every save.
    let bracket: (UInt64) -> String? = { _ in "Q3 [final]" }
    var cycled: [SpanJSON] = [.text("see ", marks: 0), .ref(4155), .text(" today", marks: 0)]
    for _ in 0..<5 {
        cycled = SpanText.textToSpans(SpanText.spansToText(cycled, name: bracket))
    }
    check(
        "a name ending in ] does not leak into the note",
        cycled == [.text("see ", marks: 0), .ref(4155), .text(" today", marks: 0)],
        "\(cycled)")
    check(
        "a name full of brackets still round-trips",
        SpanText.textToSpans(SpanText.spansToText(
            [.ref(4155)], name: { _ in "]]] [[[ ]" }))
            == [.ref(4155)])

    // 2g. Canonicalisations, pinned: reload may normalise these exact
    //     forms (and no others in this corpus).
    check("rule variants canonicalise",
        SpanText.spansToText(SpanText.textToSpans("***"), name: names) == "---")
    check("spaceless quote gains its space",
        SpanText.spansToText(SpanText.textToSpans(">x"), name: names) == "> x")
    check("odd indent floors",
        SpanText.spansToText(SpanText.textToSpans("   - x"), name: names) == "  - x")
    // The full pinned set — a reload may rewrite THESE forms and no
    // others. Widening it is a decision, not an accident.
    check("a tab becomes two spaces",
        SpanText.spansToText(SpanText.textToSpans("\t- x"), name: names) == "  - x")
    check("a star bullet becomes a dash",
        SpanText.spansToText(SpanText.textToSpans("* item"), name: names) == "- item")
    check("an indented heading loses its indent",
        SpanText.spansToText(SpanText.textToSpans("  # H"), name: names) == "# H")
    check("an indented quote loses its indent",
        SpanText.spansToText(SpanText.textToSpans("  > q"), name: names) == "> q")
    check("depth clamps at 15",
        SpanText.textToSpans(String(repeating: "  ", count: 20) + "- x")
            == [.brk(.bullet(depth: 15)), .text("x", marks: 0)])

    // 3. A Ref survives a name it has never heard of, and a nameless one.
    check(
        "unknown target keeps the id",
        SpanText.spansToText([.ref(999)], name: names) == "[[999]]")
    check("nameless token parses", SpanText.textToSpans("[[999]]") == [.ref(999)])

    // 4. A mangled token is literal text — never a guess.
    check(
        "mangled token is text",
        SpanText.textToSpans("[[4155|Kitchen rebuild]")
            == [.text("[[4155|Kitchen rebuild]", marks: 0)])

    // 5. Deleting the token deletes the link, and nothing else.
    check("deleted token drops the ref", SpanText.textToSpans("see  now")
        == [.text("see  now", marks: 0)])

    // 6. An empty buffer is no spans at all (the seam removes content).
    check("empty buffer removes content", SpanText.textToSpans("").isEmpty)

    // 7. The wire shapes the core will parse — the JSON strings are the
    //    ones core/src/value.rs's own serde tests assert (key ORDER is
    //    ours — sorted — since serde parses objects order-independently
    //    and the fingerprint is FNV over the core's own re-encoding,
    //    never over the wire bytes).
    check(
        "json of a ref doc",
        SpanText.json([.text("a", marks: 0), .brk(.body), .ref(9)])
            == #"[{"Text":"a"},{"Break":"Body"},{"Ref":9}]"#,
        SpanText.json([.text("a", marks: 0), .brk(.body), .ref(9)]))
    let vocab: [SpanJSON] = [
        .brk(.heading(2)), .text("b", marks: 1),
        .brk(.task(depth: 0, done: false)),
        .brk(.bullet(depth: 1)), .brk(.ordered(depth: 0)),
        .brk(.quote), .brk(.rule),
    ]
    check(
        "json of the block vocabulary",
        SpanText.json(vocab)
            == #"[{"Break":{"Heading":2}},{"Text":{"marks":1,"text":"b"}},"#
            + #"{"Break":{"Task":{"depth":0,"done":false}}},"#
            + #"{"Break":{"Bullet":{"depth":1}}},{"Break":{"Ordered":{"depth":0}}},"#
            + #"{"Break":"Quote"},{"Break":"Rule"}]"#,
        SpanText.json(vocab))

    // 8. Decoding is total AND faithful: every variant lands on its own
    //    case; Code and Callout land on .other; nothing throws.
    let wire = #"[{"Text":{"text":"m","marks":3}},{"Break":"Quote"},{"Break":{"Bullet":{"depth":2}}},"#
        + #"{"Break":{"Code":{"lang":"swift"}}},{"Break":{"Callout":{"kind":"note"}}},"#
        + #"{"Break":{"Task":{"depth":1,"done":true}}},{"Ref":9},{"Text":"z"}]"#
    let decoded = (try? JSONDecoder().decode([SpanJSON].self, from: Data(wire.utf8))) ?? []
    check("total decode", decoded.count == 8, "\(decoded.count)")
    check("marks survive the decode", decoded.first == .text("m", marks: 3))
    check("quote decodes", decoded.count > 1 && decoded[1] == .brk(.quote))
    check("bullet keeps depth", decoded.count > 2 && decoded[2] == .brk(.bullet(depth: 2)))
    check("code is other", decoded.count > 3 && decoded[3] == .brk(.other))
    check("callout is other", decoded.count > 4 && decoded[4] == .brk(.other))
    check("task keeps done", decoded.count > 5 && decoded[5] == .brk(.task(depth: 1, done: true)))
    check("combined marks flag", SpanText.carriesFormatting(decoded))
    check("plain doc is not flagged", !SpanText.carriesFormatting(refDoc))

    return failures
}
