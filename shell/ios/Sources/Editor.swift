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

/// The paragraph block a Break carries. The phone can only hold Body in a
/// plain buffer, so the decode keeps exactly one bit of it: is this the
/// plain body paragraph, or formatting the phone cannot edit yet? Unknown
/// shapes read as `.other` — a thrown error here would drop a whole note.
enum BlockJSON: Equatable {
    case body
    case other
}

/// One span. `marks` is the raw 4-bit set (D19); the phone renders none of
/// them and writes none of them — it keeps the value only so the editor can
/// say so out loud before flattening.
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
            // Unit variants ("Body"/"Quote"/"Rule") arrive as a bare string;
            // the rest as an object. Anything not exactly "Body" is
            // formatting this editor flattens.
            if let s = try? c.decode(String.self, forKey: .Break) {
                self = .brk(s == "Body" ? .body : .other)
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

    /// Only ever called on spans this editor built (textToSpans), which are
    /// plain Text/Body-Break/Ref. `.other` would encode as Body — the same
    /// flattening the buffer already performed, never a new surprise.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let t, _):
            try c.encode(t, forKey: .Text)  // unmarked = the bare string
        case .brk:
            try c.encode("Body", forKey: .Break)
        case .ref(let id):
            try c.encode(id, forKey: .Ref)
        }
    }
}

// MARK: - the codec: two pure functions, independently testable

/// spans ⇄ plain text. Pure: no box, no view, no state. The self-check at
/// the bottom of this file exercises them.
enum SpanText {
    /// A Ref span in the buffer. The id is the whole payload; the display
    /// name is cosmetic and re-derived on every load, so flattening its
    /// newlines and breaking a literal "]]" inside it costs nothing.
    static func token(_ id: UInt64, name: String?) -> String {
        let raw = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "[[\(id)]]" }
        let clean =
            raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "]]", with: "] ]")
        return "[[\(id)|\(clean)]]"
    }

    /// Spans → the editing buffer. A Break opens a paragraph, so a LEADING
    /// break writes no newline (mirrors the macOS codec's openParagraph):
    /// the span model cannot express an empty first paragraph.
    static func spansToText(
        _ spans: [SpanJSON], name: (UInt64) -> String? = { _ in nil }
    ) -> String {
        var out = ""
        for span in spans {
            switch span {
            case .brk:
                if !out.isEmpty { out.append("\n") }
            case .text(let t, _):
                out += t
            case .ref(let id):
                out += token(id, name: name(id))
            }
        }
        return out
    }

    /// The editing buffer → spans. Every newline is a Body Break; every
    /// well-formed "[[id]]" / "[[id|name]]" is a Ref; everything else is
    /// literal text. An empty buffer is NO spans — which removes the
    /// content cell, exactly as the seam documents.
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
        for (i, paragraph) in text.components(separatedBy: "\n").enumerated() {
            if i > 0 { out.append(.brk(.body)) }
            out.append(contentsOf: spans(inParagraph: paragraph, isKnown: isKnown))
        }
        return out
    }

    static func json(_ spans: [SpanJSON]) -> String {
        guard let data = try? JSONEncoder().encode(spans) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    /// True when the stored spans carry structure this buffer cannot hold —
    /// a non-Body block or any inline mark. The editor says so before a save
    /// flattens it; it never flattens silently.
    static func carriesFormatting(_ spans: [SpanJSON]) -> Bool {
        spans.contains { span in
            switch span {
            case .brk(let b): return b != .body
            case .text(_, let marks): return marks != 0
            case .ref: return false
            }
        }
    }

    // MARK: token scanning

    private static func spans(
        inParagraph paragraph: String, isKnown: (UInt64) -> Bool
    ) -> [SpanJSON] {
        var out: [SpanJSON] = []
        var buffer = ""
        let chars = Array(paragraph)
        var i = 0
        while i < chars.count {
            if chars[i] == "[", i + 1 < chars.count, chars[i + 1] == "[",
                let (id, end) = token(chars, from: i), isKnown(id)
            {
                if !buffer.isEmpty {
                    out.append(.text(buffer, marks: 0))
                    buffer = ""
                }
                out.append(.ref(id))
                i = end
            } else {
                buffer.append(chars[i])
                i += 1
            }
        }
        if !buffer.isEmpty { out.append(.text(buffer, marks: 0)) }
        return out
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
            self.flattens = SpanText.carriesFormatting(spans)
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
            self.flattens = SpanText.carriesFormatting(spans)
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

    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var workspaces: WorkspaceModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = NoteEditorModel()
    @StateObject private var bridge = EditorBridge()
    @State private var outlineShown = false
    @State private var templatesShown = false
    /// Plain state, not @FocusState — the UIKit text view reports focus
    /// through the representable's binding.
    @State private var focused = false

    /// Everything that is not the note gets out of the way while you write
    /// (owner, 2026-07-30): the notices are advisory and can wait. A
    /// conflict is the one exception — it is about the words being typed
    /// right now, so it stays.
    private var writing: Bool { focused }

    /// The automatic title: the note's first line with its markers off.
    /// Derived HERE, from the live buffer, because the wire's own summary
    /// flattens the WHOLE body into one string — a multi-line note would
    /// otherwise suggest "Sat 1 Aug ## Today - [ ] ## Notes" as its title.
    /// Empty once a human has named the note: their title is the title.
    private var derivedPrompt: String {
        title.isEmpty ? livDisplayTitle(model.text) : ""
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
            onOutline: { outlineShown = true },
            onTemplate: { templatesShown = true }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) { linkPicker }
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

    // MARK: the [[ picker

    /// Typing `[[` opens it, over the note and above the keyboard, with
    /// the caret still in the text so you keep typing to filter. Picking
    /// writes a reference to an ENTITY — never a file path, never a name
    /// resolved later (design/editor-study.md §5).
    @ViewBuilder private var linkPicker: some View {
        if let link = bridge.openLink {
            LinkPicker(
                query: link.query, excluding: id,
                onPick: { id, name in bridge.completeLink(id: id, name: name) },
                onDismiss: { bridge.dismissLink() }
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            .transition(.move(edge: .bottom))
        }
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
                                .font(.system(size: 16, weight: item.level == 1 ? .semibold : .regular))
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LivTheme.text)
            Text("The box's version is shown. Your edit is kept.")
                .font(.system(size: 13))
                .foregroundStyle(LivTheme.text3)
            HStack(spacing: 8) {
                Button("Re-apply my edit") { model.reapplyDraft() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LivTheme.onAccent)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: LivTheme.radiusSm).fill(LivTheme.accent))
                Button("Keep this one") { model.discardDraft() }
                    .font(.system(size: 13))
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
            .font(.system(size: 13))
            .foregroundStyle(LivTheme.text3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: LivTheme.radiusSm).fill(LivTheme.panel2))
            .padding(.horizontal, 10)
    }
}

// MARK: - the [[ picker

/// Ranked candidates from the box, plus a create row when nothing matches.
/// It never steals focus: the caret stays in the note, so typing keeps
/// filtering and the keyboard never flinches.
private struct LinkPicker: View {
    let query: String
    /// The note doing the linking. A note cannot link to itself, and while
    /// you type `[[kitchen` its own content contains that text, so without
    /// this it ranks itself first.
    let excluding: UInt64
    let onPick: (UInt64, String) -> Void
    let onDismiss: () -> Void

    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var workspaces: WorkspaceModel
    @State private var hits: [UInt64] = []
    @State private var searched = ""

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Front-of-house rows only, and never a link to nothing: an entity
    /// that is not in the box cannot be a target.
    private var rows: [EntityRow] {
        hits.compactMap { box.entity($0) }
            .filter { $0.trashed != true && $0.id != excluding }
            .prefix(4)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(rows) { row in
                Button {
                    onPick(row.id, title(row))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: glyph(row))
                            .font(.system(size: 11))
                            .foregroundStyle(LivTheme.text3)
                            .frame(width: 16)
                        Text(title(row))
                            .font(.system(size: 13))
                            .foregroundStyle(LivTheme.text)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                    }
                    .frame(height: 38)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(LivTheme.border).frame(height: 0.5)
                }
            }
            if !trimmed.isEmpty { createRow }
            if rows.isEmpty && trimmed.isEmpty {
                Text("Type to find something to link to.")
                    .font(.system(size: 11))
                    .foregroundStyle(LivTheme.muted)
                    .frame(height: 34)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LivTheme.radius).fill(LivTheme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LivTheme.radius)
                .strokeBorder(LivTheme.border, lineWidth: 0.5)
        )
        .onAppear { run(trimmed) }
        .onChange(of: query) { _, now in
            run(now.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("LINK TO")
                .font(.system(size: 9.5, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(LivTheme.text3)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(LivTheme.text3)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close link picker")
        }
        .frame(height: 32)
    }

    /// Find-or-create: an unmatched query becomes an entity, then the
    /// link. Capture asks nothing — the query is the content verbatim —
    /// and the workspace stamps it, exactly like Search's create door.
    private var createRow: some View {
        Button {
            box.capture(trimmed) { id in
                guard id != 0 else { return }
                workspaces.stamp(id, in: box)
                onPick(id, trimmed)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 16)
                Text("Create “\(trimmed)”")
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 6)
            }
            .foregroundStyle(LivTheme.accent)
            .frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func run(_ q: String) {
        guard q != searched else { return }
        searched = q
        guard !q.isEmpty else {
            hits = []
            return
        }
        box.search(q) { ids in
            guard q == searched else { return }  // a stale answer never lands
            hits = ids
        }
    }

    private func title(_ row: EntityRow) -> String {
        let raw = row.title ?? "#\(row.id)"
        let clean = livDisplayTitle(raw)
        return clean.isEmpty ? raw : clean
    }

    private func glyph(_ row: EntityRow) -> String {
        let kinds = row.kinds ?? []
        if kinds.contains("event") { return "calendar" }
        if kinds.contains("task") || (row.status?.isEmpty == false) { return "checkmark.circle" }
        if kinds.contains("person") { return "person" }
        if kinds.contains("link") { return "link" }
        if kinds.contains("note") { return "doc.text" }
        return "circle.dotted"
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

    // 2. spans → text → spans: Text and Ref exactly; Break keeps the
    //    paragraph, flattens the block (the documented v1 delta).
    let refDoc: [SpanJSON] = [
        .text("see ", marks: 0), .ref(4155), .text(" now", marks: 0),
        .brk(.body), .text("line two", marks: 0),
    ]
    check("ref round-trip", SpanText.textToSpans(SpanText.spansToText(refDoc, name: names)) == refDoc)

    let heading: [SpanJSON] = [.brk(.other), .text("Title", marks: 0), .brk(.body), .text("body", marks: 0)]
    check(
        "leading break opens paragraph 1",
        SpanText.spansToText(heading, name: names) == "Title\nbody")
    check(
        "block flattens to Body",
        SpanText.textToSpans("Title\nbody")
            == [.text("Title", marks: 0), .brk(.body), .text("body", marks: 0)])

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

    // 7. The wire shapes the core will parse.
    check(
        "json of a ref doc",
        SpanText.json([.text("a", marks: 0), .brk(.body), .ref(9)])
            == #"[{"Text":"a"},{"Break":"Body"},{"Ref":9}]"#,
        SpanText.json([.text("a", marks: 0), .brk(.body), .ref(9)]))

    // 8. Decoding is total: marked text, unit and struct blocks, refs.
    let wire = #"[{"Text":{"text":"m","marks":3}},{"Break":"Quote"},{"Break":{"Bullet":{"depth":0}}},{"Ref":9},{"Text":"z"}]"#
    let decoded = (try? JSONDecoder().decode([SpanJSON].self, from: Data(wire.utf8))) ?? []
    check("total decode", decoded.count == 5, "\(decoded.count)")
    check("marks survive the decode", decoded.first == .text("m", marks: 3))
    check("formatting is detected", SpanText.carriesFormatting(decoded))
    check("plain doc is not flagged", !SpanText.carriesFormatting(refDoc))

    return failures
}
