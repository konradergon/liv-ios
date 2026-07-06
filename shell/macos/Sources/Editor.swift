// lotus — the editor lens. The venue for thought itself: one entity's
// content in a centered ~65-character column, spans in, spans out.
// Embedded references render as inline pills; an embedded task draws its
// live checkbox. No toolbar; keyboard only; native text, never a webview.
//
// The editor is the one renderer that holds state — exactly one draft of
// one entity (decided in interface.md). Every save presents the base
// fingerprint back to the seam: a save is to a value, never a moment.

import AppKit
import SwiftUI

// MARK: - spans (mirror core's serde encoding, verbatim)

enum SpanJSON: Codable, Equatable {
    case text(String)
    case ref(UInt64)

    private enum CodingKeys: String, CodingKey {
        case Text, Ref
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let t = try c.decodeIfPresent(String.self, forKey: .Text) {
            self = .text(t)
        } else {
            self = .ref(try c.decode(UInt64.self, forKey: .Ref))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let t): try c.encode(t, forKey: .Text)
        case .ref(let id): try c.encode(id, forKey: .Ref)
        }
    }
}

struct ContentDoc: Codable {
    let id: UInt64
    let name: String?
    let trashed: Bool
    /// True when the box opened fine but no such entity exists.
    let missing: Bool
    let fingerprint: UInt64
    let spans: [SpanJSON]
}

// MARK: - the codec: spans ⇄ attributed string, lossless by construction

/// What a pill needs at draw time and nothing more: a window into the
/// latest snapshot plus the two gestures a pill can make. Owned by the
/// editor model; cells hold it weakly and degrade to "#id" without it.
final class PillContext {
    var lookup: (UInt64) -> EntityRow? = { _ in nil }
    var onCheckbox: (UInt64) -> Void = { _ in }
    var onSelect: (UInt64) -> Void = { _ in }
}

enum SpanCodec {
    static var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.preferredFont(forTextStyle: .body),
            .foregroundColor: NSColor.labelColor,
        ]
    }

    static func attributed(_ spans: [SpanJSON], context: PillContext) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for span in spans {
            switch span {
            case .text(let t):
                result.append(NSAttributedString(string: t, attributes: baseAttributes))
            case .ref(let id):
                result.append(pill(id, context: context))
            }
        }
        return result
    }

    static func pill(_ id: UInt64, context: PillContext) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.attachmentCell = RefAttachmentCell(entityId: id, context: context)
        let pill = NSMutableAttributedString(attachment: attachment)
        // The attachment character carries the body attributes too, so
        // the caret right after a pill types body text — not the bare
        // 12pt default an attribute-less run would seed.
        pill.addAttributes(baseAttributes, range: NSRange(location: 0, length: pill.length))
        return pill
    }

    /// The inverse walk. Our cells become Ref spans; every other run is
    /// text with foreign attachment characters stripped; adjacent texts
    /// coalesce; empties drop. Round-trip equality is span equality.
    static func spans(from attributed: NSAttributedString) -> [SpanJSON] {
        var out: [SpanJSON] = []
        let ns = attributed.string as NSString
        attributed.enumerateAttribute(
            .attachment, in: NSRange(location: 0, length: attributed.length)
        ) { value, range, _ in
            if let cell = (value as? NSTextAttachment)?.attachmentCell as? RefAttachmentCell {
                out.append(.ref(cell.entityId))
                return
            }
            let text = ns.substring(with: range).replacingOccurrences(of: "\u{FFFC}", with: "")
            if text.isEmpty { return }
            if case .text(let prev) = out.last {
                out[out.count - 1] = .text(prev + text)
            } else {
                out.append(.text(text))
            }
        }
        return out
    }

    static func json(_ spans: [SpanJSON]) -> String {
        guard let data = try? JSONEncoder().encode(spans) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}

// MARK: - the pill: a live projection of one referenced entity

/// TextKit 1 attachment cell — the reason the editor builds its stack by
/// hand. Holds only the id; title, task-ness and checkbox state are read
/// from the latest snapshot at draw time, so a rename is a redraw.
/// Monochrome by law: the accent keeps its exactly-three jobs.
final class RefAttachmentCell: NSTextAttachmentCell {
    let entityId: UInt64
    weak var context: PillContext?

    init(entityId: UInt64, context: PillContext) {
        self.entityId = entityId
        self.context = context
        super.init(textCell: "")
    }

    required init(coder: NSCoder) {
        fatalError("pills are never archived")
    }

    private var pillFont: NSFont { NSFont.preferredFont(forTextStyle: .body) }

    /// (title, is a task, is done, is broken)
    private func info() -> (String, Bool, Bool, Bool) {
        guard let row = context?.lookup(entityId) else {
            // Missing or trashed: a broken link, shown, never repaired.
            return ("#\(entityId)!", false, false, true)
        }
        let isTask = row.kinds.contains("task") || row.status != nil
        return (row.title, isTask, row.status == "done", false)
    }

    override func cellSize() -> NSSize {
        let (title, isTask, _, _) = info()
        let width = title.size(withAttributes: [.font: pillFont]).width
            + 16 + (isTask ? 18 : 0)
        return NSSize(width: ceil(width), height: pillFont.boundingRectForFont.height + 3)
    }

    override func cellBaselineOffset() -> NSPoint {
        NSPoint(x: 0, y: pillFont.descender - 1.5)
    }

    private func checkboxRect(in frame: NSRect) -> NSRect {
        NSRect(x: frame.minX + 5, y: frame.midY - 8, width: 16, height: 16)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let (title, isTask, done, broken) = info()

        let back = NSBezierPath(
            roundedRect: cellFrame.insetBy(dx: 0.5, dy: 1), xRadius: 5, yRadius: 5)
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        back.fill()

        var x = cellFrame.minX + 8
        if isTask {
            let color: NSColor = done ? .labelColor : .secondaryLabelColor
            if let glyph = symbol(done ? "checkmark.square.fill" : "square", color: color) {
                glyph.draw(
                    in: checkboxRect(in: cellFrame), from: .zero, operation: .sourceOver,
                    fraction: 1, respectFlipped: true, hints: nil)
            }
            x += 18
        }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: pillFont,
            .foregroundColor: broken ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        if broken {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        let size = title.size(withAttributes: attributes)
        title.draw(
            at: NSPoint(x: x, y: cellFrame.midY - size.height / 2), withAttributes: attributes)
    }

    private func symbol(_ name: String, color: NSColor) -> NSImage? {
        guard
            let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        else { return nil }
        return NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    // The checkbox gesture edits the task entity; anywhere else on the
    // pill selects the target. Click selects — the grammar, uniform.
    override func wantsToTrackMouse() -> Bool { true }

    override func trackMouse(
        with theEvent: NSEvent, in cellFrame: NSRect, of controlView: NSView?,
        untilMouseUp flag: Bool
    ) -> Bool {
        guard let view = controlView, let context = context else { return false }
        let point = view.convert(theEvent.locationInWindow, from: nil)
        let (_, isTask, _, _) = info()
        if isTask && checkboxRect(in: cellFrame).contains(point) {
            context.onCheckbox(entityId)
        } else {
            context.onSelect(entityId)
        }
        return true
    }
}

// MARK: - the text view: TextKit 1 by hand, hygiene by override

final class LotusTextView: NSTextView {
    var onEscape: () -> Void = {}
    var pillContext: PillContext?
    /// title → id, rebuilt whenever the completion list is asked for.
    var completionIds: [String: UInt64] = [:]
    /// Armed when the completion list is built for an "@" mention. The
    /// buffer cannot be trusted at accept time — the popup's previews
    /// rewrite it, "@" included — so the session's nature is recorded
    /// here, while it is still visible.
    var mentionSession = false
    /// A cancelled session restores the "@" through the normal change
    /// machinery; eat exactly that one textDidChange, or Esc reopens
    /// the popup it just closed.
    var suppressAutoComplete = false

    /// The writing measure: ~65 characters of body text.
    static let measure: CGFloat = 620

    override func layout() {
        super.layout()
        let inset = max((bounds.width - Self.measure) / 2, 28)
        if textContainerInset.width != inset {
            textContainerInset = NSSize(width: inset, height: 48)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape()
    }

    /// Formatting cannot enter: paste arrives plain, drops arrive plain
    /// (readable types are the gate for both), the font panel is dead,
    /// and our attachments are the only non-text content possible — the
    /// round trip cannot lose anything.
    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [.string]
    }

    override func paste(_ sender: Any?) {
        pasteAsPlainText(sender)
    }

    override func changeFont(_ sender: Any?) {}

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(NSText.underline(_:)),
            #selector(NSTextView.raiseBaseline(_:)),
            #selector(NSTextView.lowerBaseline(_:)),
            #selector(NSTextView.alignLeft(_:)),
            #selector(NSTextView.alignRight(_:)),
            #selector(NSTextView.alignCenter(_:)):
            return false
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    /// "@" reaches back so the completion popup can replace the whole
    /// mention, @ included.
    override var rangeForUserCompletion: NSRange {
        let caret = selectedRange().location
        let text = string as NSString
        var i = caret
        while i > 0 {
            let ch = text.character(at: i - 1)
            if ch == 0x40 {  // "@"
                return NSRange(location: i - 1, length: caret - (i - 1))
            }
            guard let scalar = Unicode.Scalar(ch),
                !CharacterSet.whitespacesAndNewlines.contains(scalar)
            else { break }
            i -= 1
        }
        return super.rangeForUserCompletion
    }

    /// Accepting a completion swaps the mention for a pill — one undo
    /// step, through the same shouldChange/didChange gate as typing.
    /// The @-ness comes from the recorded session, never from the live
    /// buffer: the popup's previews already rewrote it.
    override func insertCompletion(
        _ word: String, forPartialWordRange charRange: NSRange, movement: Int, isFinal flag: Bool
    ) {
        if flag {
            let mention = mentionSession
            mentionSession = false
            if NSTextMovement(rawValue: movement) == .cancel {
                suppressAutoComplete = true
            } else if mention, let id = completionIds[word], let context = pillContext {
                let pill = SpanCodec.pill(id, context: context)
                if shouldChangeText(in: charRange, replacementString: pill.string) {
                    textStorage?.replaceCharacters(in: charRange, with: pill)
                    didChangeText()
                    setSelectedRange(NSRange(location: charRange.location + 1, length: 0))
                    typingAttributes = SpanCodec.baseAttributes
                }
                return
            }
        }
        super.insertCompletion(
            word, forPartialWordRange: charRange, movement: movement, isFinal: flag)
    }
}

// MARK: - the draft journal: written only when a quit-time flush fails

struct DraftFile: Codable {
    let entity: UInt64
    let base: UInt64
    let spans: [SpanJSON]
}

enum DraftJournal {
    static func url(box: String, id: UInt64) -> URL {
        URL(fileURLWithPath: box + ".draft-\(id).json")
    }

    static func write(box: String, draft: DraftFile) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        try? data.write(to: url(box: box, id: draft.entity), options: .atomic)
    }

    static func delete(box: String, id: UInt64) {
        try? FileManager.default.removeItem(at: url(box: box, id: id))
    }

    static func all(box: String) -> [DraftFile] {
        let boxURL = URL(fileURLWithPath: box)
        let dir = boxURL.deletingLastPathComponent()
        let prefix = boxURL.lastPathComponent + ".draft-"
        guard
            let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return [] }
        return names
            .filter { $0.hasPrefix(prefix) && $0.hasSuffix(".json") }
            .compactMap { name in
                guard let data = try? Data(contentsOf: dir.appendingPathComponent(name))
                else { return nil }
                return try? JSONDecoder().decode(DraftFile.self, from: data)
            }
    }
}

// MARK: - the one editor at a time, findable by AppKit

/// The quit path and the ⌘Z fallthrough live in AppKit, the editor lives
/// in SwiftUI; this is the seam between them. One window, one editor.
final class EditorRegistry {
    static let shared = EditorRegistry()
    weak var active: EditorModel?
}

// MARK: - the model: the draft's keeper

enum FlushOutcome {
    case clean, saved, stale, busy, invalid
}

final class EditorModel: ObservableObject {
    let box: BoxModel
    let id: UInt64
    /// Focus the title on open — the create-then-rename flow.
    let bornBlank: Bool

    @Published var title = ""
    @Published var dirty = false
    /// The base moved under a dirty draft; both truths shown, user picks.
    @Published var conflicted = false
    @Published var trashed = false
    /// Gone from the box entirely (merged away, or never there).
    @Published var missing = false
    @Published var loaded = false

    private(set) var base: UInt64 = 0
    private var lastLoadedName = ""
    private weak var textView: LotusTextView?
    private var idleTimer: Timer?
    private var checkpointTimer: Timer?
    /// Bumped on every keystroke; a save only marks clean if untyped-over.
    private var generation = 0
    /// One save in flight at a time: overlapping flush requests queue and
    /// are served by a single follow-up running with then-current state —
    /// a save must never race its own predecessor's base.
    private var saving = false
    private var queuedFlush: [(FlushOutcome) -> Void] = []
    /// A sidecar draft waiting to be adopted instead of the stored value.
    private var journaled: DraftFile?

    let pills = PillContext()
    var onSelect: (UInt64) -> Void = { _ in }
    var onCloseRequest: () -> Void = {}

    init(box: BoxModel, id: UInt64, bornBlank: Bool = false) {
        self.box = box
        self.id = id
        self.bornBlank = bornBlank
        pills.lookup = { [weak box] target in box?.entity(target) }
        pills.onCheckbox = { [weak self] task in self?.toggle(task: task) }
        pills.onSelect = { [weak self] target in self?.onSelect(target) }
        EditorRegistry.shared.active = self
    }

    func attach(_ view: LotusTextView) {
        textView = view
        view.pillContext = pills
        view.onEscape = { [weak self] in self?.onCloseRequest() }
    }

    /// Adopt a journaled draft: it loads dirty and conflicted when stale,
    /// so the user's own quit flush completes visibly, never silently.
    func adopt(_ draft: DraftFile) {
        journaled = draft
    }

    func load() {
        box.content(id) { [weak self] read in
            guard let self = self else { return }
            switch read {
            case .unavailable:
                // The box would not open — that says nothing about the
                // note. Stay unloaded (the view stays read-only, so no
                // words can land in limbo) and try again shortly; the
                // sidebar's busy line is already telling the truth.
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let self = self, !self.loaded else { return }
                    self.load()
                }
            case .missing:
                self.missing = true
                self.loaded = true
                // A journaled draft over a gone note: show the words,
                // read-only, so they can be taken somewhere.
                if let draft = self.journaled {
                    self.showOnly(spans: draft.spans)
                }
            case .doc(let doc):
                self.trashed = doc.trashed
                self.title = doc.name ?? ""
                self.lastLoadedName = self.title
                self.loaded = true
                if let draft = self.journaled, draft.base != doc.fingerprint {
                    // The world moved past the journal: show the draft
                    // dirty, over the banner, exactly like any other
                    // stale flush. (The journal file survives until a
                    // save or a deliberate discard resolves it.)
                    self.journaled = nil
                    self.base = doc.fingerprint
                    self.reload(spans: draft.spans)
                    self.dirty = true
                    self.conflicted = true
                    return
                }
                self.base = doc.fingerprint
                let adopted = self.journaled
                self.journaled = nil
                self.reload(spans: adopted?.spans ?? doc.spans)
                if adopted != nil {
                    self.dirty = true
                    self.flush()
                }
            }
        }
    }

    /// Any draft reload clears the text undo stack — a post-rebase ⌘Z
    /// must never resurrect pre-rebase content into a silent revert —
    /// and breaks typing coalescing first, so no cached undo holds
    /// ranges into a storage that no longer exists.
    private func reload(spans: [SpanJSON]) {
        guard let view = textView, let storage = view.textStorage else { return }
        view.breakUndoCoalescing()
        storage.setAttributedString(SpanCodec.attributed(spans, context: pills))
        view.typingAttributes = SpanCodec.baseAttributes
        view.undoManager?.removeAllActions()
        view.isEditable = true
        dirty = false
    }

    /// The read-only face: a draft whose note no longer exists is shown,
    /// never edited — there is nothing left to save into.
    private func showOnly(spans: [SpanJSON]) {
        guard let view = textView, let storage = view.textStorage else { return }
        storage.setAttributedString(SpanCodec.attributed(spans, context: pills))
        view.isEditable = false
    }

    // MARK: typing → transactions

    /// A keystroke arms two clocks: 2s of idle commits the burst, and a
    /// 30s checkpoint bounds the loss budget under unbroken typing.
    func edited() {
        dirty = true
        generation += 1
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
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

    private func currentSpans() -> [SpanJSON] {
        guard let storage = textView?.textStorage else { return [] }
        return SpanCodec.spans(from: storage)
    }

    func flush(_ done: @escaping (FlushOutcome) -> Void = { _ in }) {
        // A clean draft has nothing to lose, whatever the load state —
        // Esc out of a still-loading editor must not beep-lock it.
        guard dirty else {
            done(.clean)
            return
        }
        guard loaded, !missing else {
            done(.invalid)
            return
        }
        if saving {
            // Coalesce: the follow-up flush runs once, with then-current
            // spans and base, and answers every queued caller.
            queuedFlush.append(done)
            return
        }
        saving = true
        let spans = currentSpans()
        let asOf = generation
        attemptSave(spans: spans, asOf: asOf, base: base, retries: 3) { [weak self] outcome in
            guard let self = self else {
                done(outcome)
                return
            }
            self.saving = false
            done(outcome)
            let waiting = self.queuedFlush
            self.queuedFlush = []
            if !waiting.isEmpty {
                self.flush { followUp in waiting.forEach { $0(followUp) } }
            }
        }
    }

    /// The base rides with the payload, captured together in flush():
    /// a retry may never re-read a base that moved under it — that is
    /// how an old draft would clobber a newer save through the guard.
    private func attemptSave(
        spans: [SpanJSON], asOf: Int, base: UInt64, retries: Int,
        done: @escaping (FlushOutcome) -> Void
    ) {
        box.saveContent(id: id, spansJSON: SpanCodec.json(spans), base: base) {
            [weak self] result in
            guard let self = self else {
                done(.busy)
                return
            }
            switch result {
            case .saved(let fresh):
                self.base = fresh
                if self.generation == asOf {
                    self.dirty = false
                    self.idleTimer?.invalidate()
                    self.checkpointTimer?.invalidate()
                    self.checkpointTimer = nil
                }
                self.conflicted = false
                // The burst is committed; undo groups segment with it,
                // so no text undo straddles a save boundary.
                self.textView?.breakUndoCoalescing()
                DraftJournal.delete(box: self.box.path, id: self.id)
                done(.saved)
            case .stale:
                self.conflicted = true
                done(.stale)
            case .busy:
                if retries > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                        guard let self = self else {
                            done(.busy)
                            return
                        }
                        self.attemptSave(
                            spans: spans, asOf: asOf, base: base, retries: retries - 1,
                            done: done)
                    }
                } else {
                    done(.busy)  // stays dirty; the dot shows; clocks re-arm on the next keystroke
                }
            }
        }
    }

    // MARK: the world moving underneath

    /// Every snapshot answers "did my base move?" for free via
    /// content_print. Clean → silent rebase; dirty → the banner. Pills
    /// redraw from the new snapshot either way. Takes the snapshot the
    /// publisher emitted: @Published fires on willSet, so reading
    /// box.snap here would compare against the world one snapshot ago —
    /// and call every autosave a conflict.
    func snapshotArrived(_ snap: Snapshot?) {
        guard loaded, !missing, let snap = snap else { return }
        defer { redrawPills() }
        guard let row = snap.entities.first(where: { $0.id == id }) else {
            // Filtered out: trashed, merged away, or gone. Ask the box
            // which — never infer "gone" from a box that would not open.
            box.content(id) { [weak self] read in
                guard let self = self else { return }
                switch read {
                case .doc(let doc): self.trashed = doc.trashed
                case .missing: self.missing = true
                case .unavailable: break
                }
            }
            return
        }
        trashed = false
        if row.contentPrint != base {
            if dirty || saving {
                conflicted = true
            } else {
                box.content(id) { [weak self] read in
                    guard let self = self, case .doc(let doc) = read, !self.dirty else { return }
                    self.base = doc.fingerprint
                    self.title = doc.name ?? ""
                    self.lastLoadedName = self.title
                    self.reload(spans: doc.spans)
                }
            }
        }
    }

    private func redrawPills() {
        guard let view = textView, let storage = view.textStorage,
            let layout = view.layoutManager
        else { return }
        let range = NSRange(location: 0, length: storage.length)
        // Layout too, not just display: a renamed target changes the
        // pill's cellSize, and TextKit caches attachment sizes at
        // layout time.
        layout.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
        layout.invalidateDisplay(forCharacterRange: range)
    }

    /// Keep mine: re-read then save — the seam has no force flag.
    func keepMine() {
        box.content(id) { [weak self] read in
            guard let self = self, case .doc(let doc) = read else { return }
            self.base = doc.fingerprint
            self.dirty = true
            self.flush { [weak self] outcome in
                if case .saved = outcome { self?.conflicted = false }
            }
        }
    }

    /// Take theirs: the draft is discarded deliberately, by the user —
    /// which resolves its journal too, or the discarded words would
    /// resurrect at every launch.
    func takeTheirs() {
        conflicted = false
        dirty = false
        journaled = nil
        DraftJournal.delete(box: box.path, id: id)
        load()
    }

    // MARK: gestures on pills and title

    /// The checkbox edits the task entity — a separate transaction, after
    /// the draft flushes, so log order equals gesture order. ⌘Z right
    /// after the click undoes exactly the click (the registered inverse).
    func toggle(task: UInt64) {
        let current = box.entity(task)?.status
        let next = current == "done" ? "todo" : "done"
        flush { [weak self] _ in
            guard let self = self else { return }
            self.box.set(task, property: "status", value: next) { ok in
                guard ok else { return }
                self.redrawPills()
                self.registerToggleUndo(task: task, undoTo: current ?? "todo", redoTo: next)
            }
        }
    }

    /// Undo and redo alternate by re-registration: each run sets the
    /// status back and registers its own inverse, so ⇧⌘Z after ⌘Z
    /// re-toggles instead of doing nothing.
    private func registerToggleUndo(task: UInt64, undoTo: String, redoTo: String) {
        textView?.undoManager?.registerUndo(withTarget: self) { model in
            model.box.set(task, property: "status", value: undoTo) { _ in
                model.redrawPills()
            }
            model.registerToggleUndo(task: task, undoTo: redoTo, redoTo: undoTo)
        }
        textView?.undoManager?.setActionName("Toggle Task")
    }

    /// A typed title that differs from the stored name — flushed by the
    /// same gestures that flush content, checked by the quit gate.
    var titlePending: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != lastLoadedName
    }

    /// Anything the quit gate must not lose: words or a name.
    var needsQuitFlush: Bool { dirty || titlePending }

    func renameIfNeeded(_ done: @escaping () -> Void = {}) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            title = lastLoadedName  // empty costs nothing; it just isn't a rename
            done()
            return
        }
        guard trimmed != lastLoadedName else {
            done()
            return
        }
        box.set(id, property: "name", value: trimmed) { [weak self] ok in
            if ok { self?.lastLoadedName = trimmed }
            done()
        }
    }

    // MARK: ⌘⌥Z and quit

    /// Box undo under a dirty draft is unreachable by construction:
    /// flush first, then undo, then the refresh rebases the clean editor.
    func flushThenBoxUndo() {
        flush { [weak self] outcome in
            switch outcome {
            case .clean, .saved: self?.box.undo()
            default: NSSound.beep()
            }
        }
    }

    /// The quit path: the pending rename first (quit must not outrun the
    /// boxQueue), then the flush, then — only on refusal — the journal:
    /// the one moment the draft may outlive the process outside the log.
    func flushForQuit(_ completion: @escaping () -> Void) {
        renameIfNeeded { [weak self] in
            guard let self = self else {
                completion()
                return
            }
            self.flush { [weak self] outcome in
                guard let self = self else {
                    completion()
                    return
                }
                switch outcome {
                case .clean, .saved:
                    completion()
                default:
                    DraftJournal.write(
                        box: self.box.path,
                        draft: DraftFile(
                            entity: self.id, base: self.base, spans: self.currentSpans())
                    )
                    completion()
                }
            }
        }
    }

    /// Closing a gone note resolves its draft deliberately: unseen words
    /// (still dirty) go to the journal and return next launch; words
    /// already shown read-only are discarded by the click the banner
    /// warned about.
    func resolveMissingClose() {
        if dirty {
            DraftJournal.write(
                box: box.path,
                draft: DraftFile(entity: id, base: base, spans: currentSpans()))
        } else {
            DraftJournal.delete(box: box.path, id: id)
        }
    }

    func closed() {
        idleTimer?.invalidate()
        checkpointTimer?.invalidate()
        if EditorRegistry.shared.active === self {
            EditorRegistry.shared.active = nil
        }
    }
}

// MARK: - the representable: an explicit TextKit 1 stack

struct NoteTextView: NSViewRepresentable {
    @ObservedObject var model: EditorModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        // Hand-built TK1: NSTextAttachmentCell requires it, and building
        // the stack explicitly means no silent TextKit 2 surprise.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(
            size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)

        let view = LotusTextView(frame: .zero, textContainer: container)
        view.isRichText = true
        view.allowsUndo = true
        view.usesFontPanel = false
        view.usesFindPanel = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.font = NSFont.preferredFont(forTextStyle: .body)
        view.textColor = .labelColor
        view.typingAttributes = SpanCodec.baseAttributes
        view.drawsBackground = false
        // The rest of the canonical hand-built recipe: without an
        // unbounded maxSize the document view pins to the first viewport
        // and a long note becomes unscrollable.
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.minSize = NSSize(width: 0, height: 0)
        view.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.autoresizingMask = [.width]
        view.textContainerInset = NSSize(width: 28, height: 48)
        // Read-only until the box answers: a keystroke must never land
        // in a view the load is about to overwrite.
        view.isEditable = false
        view.delegate = context.coordinator

        let scroll = NSScrollView()
        scroll.documentView = view
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        model.attach(view)
        return scroll
    }

    func updateNSView(_ view: NSScrollView, context: Context) {
        // The model owns the content; SwiftUI re-renders must not touch it.
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: EditorModel
        /// Per-editor undo: the window's shared manager would entangle
        /// the draft with every other field in the window.
        let undo = UndoManager()

        init(model: EditorModel) {
            self.model = model
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            undo
        }

        func textDidChange(_ notification: Notification) {
            model.edited()
            guard let view = notification.object as? LotusTextView else { return }
            // A cancelled completion restores the "@" through this very
            // notification; eat that one, or Esc reopens the popup.
            if view.suppressAutoComplete {
                view.suppressAutoComplete = false
                return
            }
            // Typing "@" summons the reference picker — the native
            // completion control, no popup of our own.
            let caret = view.selectedRange().location
            if caret > 0, (view.string as NSString).character(at: caret - 1) == 0x40 {
                view.complete(nil)
            }
        }

        func textView(
            _ textView: NSTextView, completions words: [String],
            forPartialWordRange charRange: NSRange,
            indexOfSelectedItem index: UnsafeMutablePointer<Int>?
        ) -> [String] {
            guard let view = textView as? LotusTextView else { return words }
            let mention = (view.string as NSString).substring(with: charRange)
            guard mention.hasPrefix("@") else { return words }
            // Recorded here, while the "@" is still in the buffer: the
            // accept path keys off this, not off what the previews left.
            view.mentionSession = true
            let partial = mention.dropFirst().lowercased()
            view.completionIds.removeAll()
            var titles: [String] = []
            for row in model.box.snap?.entities ?? [] where row.id != model.id {
                guard partial.isEmpty || row.title.lowercased().hasPrefix(partial),
                    view.completionIds[row.title] == nil
                else { continue }
                view.completionIds[row.title] = row.id
                titles.append(row.title)
            }
            return titles
        }
    }
}

// MARK: - the lens

struct EditorView: View {
    @ObservedObject var model: EditorModel
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            banner
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("Untitled", text: $model.title)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                    .focused($titleFocused)
                    .onSubmit { model.renameIfNeeded() }
                    .onExitCommand { model.onCloseRequest() }
                Spacer()
                if model.dirty {
                    Circle()
                        .fill(Color.secondary.opacity(0.55))
                        .frame(width: 7, height: 7)
                        .help("Unsaved changes")
                }
            }
            .frame(maxWidth: LotusTextView.measure - 10)
            .padding(.top, 44)
            .padding(.horizontal, 28)

            NoteTextView(model: model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            model.load()
            if model.bornBlank {
                DispatchQueue.main.async { titleFocused = true }
            }
        }
        .onChange(of: titleFocused) {
            if !titleFocused { model.renameIfNeeded() }
        }
        .onReceive(model.box.$snap) { snap in
            // Pass the emitted value: @Published fires on willSet, so
            // box.snap still holds the previous snapshot here.
            model.snapshotArrived(snap)
        }
    }

    /// One line, system styles, no accent: the banner states a truth and
    /// offers the two honest exits.
    @ViewBuilder
    private var banner: some View {
        if model.missing {
            noticeBar(
                model.dirty
                    ? "This note is gone from the box. Close keeps the draft for next launch."
                    : "This note is gone from the box. Close discards this draft."
            ) {
                Button("Close") { model.onCloseRequest() }
            }
        } else if model.conflicted {
            noticeBar("Changed outside the editor.") {
                Button("Keep mine") { model.keepMine() }
                Button("Take theirs") { model.takeTheirs() }
            }
        } else if model.trashed {
            noticeBar("This note is in the trash. Edits still land.") {
                Button("Close") { model.onCloseRequest() }
            }
        }
    }

    private func noticeBar<Actions: View>(
        _ message: String, @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(spacing: 10) {
            Text(message).font(.system(size: 12.5))
            Spacer()
            actions().controlSize(.small)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 14)
        .background(Color(nsColor: .underPageBackgroundColor))
        .overlay(Divider(), alignment: .bottom)
    }
}
