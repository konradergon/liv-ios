// liv iOS — files (owner, 2026-10-01: "files opened if they contain
// text, which is edited as a note").
//
// A file that holds words IS a note: added, it arrives as one; an older
// file entity that holds words becomes one the first time it is opened.
// Rust is the one judge of what holds words (`text_of`) and the file
// itself is never written — its words are copied into the box.
//
// Any other file is an ORDINARY entity, filed like everything else: its
// name, what it is, how big, and an Open button that hands it to the app
// that owns the format. No preview (owner, 2026-08-13: "preview should
// not be a functionality since it is absolutely useless").
//
// The phone keeps its copy beside the box, `files/<uuid>/<name>`, and the
// box remembers that path relative to its own folder — so a reinstalled
// app, whose folders move, still finds every file.

import SwiftUI
import UIKit

// MARK: - what the row says

/// The file an entity refers to. Nil for everything that is not a file,
/// which is most things.
struct FileFacts {
    /// The extension, lowercased, or "" — the core stores this as an
    /// ordinary `format` cell, so `format:pdf` filters for free.
    let format: String

    /// A file is what Rust says has one (`has_file`, on every row), so a
    /// row needs no cells to be one. The format is a cell; until the cells
    /// arrive a file reads as a plain "File".
    static func of(_ row: EntityRow?) -> FileFacts? {
        guard let row, row.hasFile == true else { return nil }
        let format = (row.cells ?? []).first { $0.word == "format" }?.value ?? ""
        return FileFacts(format: format.lowercased())
    }

    /// The format as a phrase, for the one place that says it in words
    /// rather than drawing it. "cpp file", "PDF", "Spreadsheet".
    var formatWord: String {
        switch fileClass {
        case .pdf: return "PDF"
        case .image: return "Image"
        case .sheet: return "Spreadsheet"
        case .slides: return "Slides"
        case .document: return "Document"
        case .text: return format.isEmpty ? "Text file" : "\(format) text file"
        case .other: return format.isEmpty ? "File" : "\(format) file"
        }
    }

    /// What KIND of file, for a glyph and for how to show it. Derived
    /// from the format, never stored — one function, so the icon in a
    /// list and the body of a tab can never disagree.
    enum Class: Equatable {
        case document, sheet, slides, pdf, image, text, other
    }

    var fileClass: Class {
        switch format {
        case "doc", "docx", "odt", "rtf", "pages": return .document
        case "xls", "xlsx", "ods", "csv", "tsv", "numbers": return .sheet
        case "ppt", "pptx", "odp", "key": return .slides
        case "pdf": return .pdf
        case "png", "jpg", "jpeg", "heic", "gif", "webp", "tiff": return .image
        case "txt", "md", "tex", "bib", "json", "yaml", "yml", "xml": return .text
        default: return .other
        }
    }
}

// MARK: - the body

/// A file's tab: its name, what it is, how big, and Open.
struct FileBody: View {
    let id: LivEntityID

    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel

    @State private var name = ""
    @State private var seeded = false
    @State private var pendingName: String?
    /// Where the file is and how big, once the box has looked. Nothing is
    /// drawn under the name until then, so a file never flashes "moved or
    /// deleted" on its way to being found.
    @State private var place: LivResync?
    @State private var asked = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        Group {
            if let row = box.entity(id), let facts = FileFacts.of(row) {
                VStack(alignment: .leading, spacing: 0) {
                    nameField(facts)
                    if let place {
                        if place.state == "broken" || place.path == nil {
                            brokenCard
                        } else {
                            heldCard(facts, place)
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else {
                EmptyHint("Deleted")
                    .frame(maxHeight: .infinity)
            }
        }
        .onAppear(perform: arrive)
        .onChange(of: storedName) { old, fresh in
            if pendingName == fresh { pendingName = nil }
            if let seed = LivName.reseed(draft: name, was: old, now: fresh) {
                name = seed
            }
        }
    }

    /// WHAT LIV IS HOLDING, said plainly, and the one verb that opens it.
    private func heldCard(_ facts: FileFacts, _ place: LivResync) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(facts.formatWord)
                    .font(.system(size: LivType.strong, weight: .semibold))
                    .foregroundStyle(LivTheme.text)
                if let bytes = place.bytes {
                    Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                        .font(.system(size: LivType.label).monospacedDigit())
                        .foregroundStyle(LivTheme.text3)
                }
            }
            Spacer(minLength: 0)
            ConfirmPill("Open", compact: true) { open(place) }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: LivTheme.radius).fill(LivTheme.surface))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: name — a file's name in the box is yours to change, and
    // changing it never touches the file on disk.

    private func nameField(_ facts: FileFacts) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Untitled", text: $name, axis: .vertical)
                .font(.system(size: LivType.hero, weight: .semibold))
                .foregroundStyle(LivTheme.text)
                .lineLimit(1...3)
                .focused($nameFocused)
                .submitLabel(.done)
                .onSubmit(commitName)
                .onChange(of: nameFocused) { _, now in
                    if !now { commitName() }
                }
            HStack(spacing: 8) {
                LivIcon(glyph: .file(facts.fileClass), color: LivTheme.text2, size: 22)
                if !facts.format.isEmpty { ValueChip(facts.format) }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        // Clear the chrome, the way every other surface does.
        .padding(.top, LivRow.topInset)
        .padding(.bottom, 12)
    }

    /// The file is not where the box last saw it. Say so plainly and keep
    /// the entity — its filing is still real, and the file may come back.
    private var brokenCard: some View {
        Text("The file has moved or been deleted")
            .font(.system(size: LivType.strong, weight: .semibold))
            .foregroundStyle(LivTheme.text)
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: LivTheme.radius).fill(LivTheme.surface))
            .overlay(
                RoundedRectangle(cornerRadius: LivTheme.radius)
                    .strokeBorder(LivTheme.red.opacity(0.5), lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
    }

    // MARK: arrival

    /// Opening a file is when Liv catches up with it — a re-hash, once,
    /// here, which also says where it is and how big. A file that holds
    /// words becomes a note now, and the tab redraws as one.
    private func arrive() {
        if !seeded {
            name = storedName
            seeded = true
        }
        guard !asked else { return }
        asked = true
        box.resyncFile(id) { answer in
            guard let answer, answer.state != "broken", let path = answer.path else {
                place = answer ?? LivResync(state: "broken")
                return
            }
            box.fileText(path) { found in
                guard let text = found?.text else {
                    place = answer
                    return
                }
                FileWords.spans(text, box: box) { spans in
                    box.fileIntoNote(id, spansJson: spans) { ok in
                        if !ok { place = answer }
                    }
                }
            }
        }
    }

    private func open(_ place: LivResync) {
        guard let path = place.path else { return }
        desk.share = SharePayload(items: [URL(fileURLWithPath: path)])
    }

    /// The name cell, and the rules for writing it — `LivName` (Kit.swift).
    private var storedName: String { LivName.stored(box.entity(id)) }

    private func commitName() {
        switch LivName.commit(typed: name, row: box.entity(id), pending: pendingName) {
        case .write(let typed):
            pendingName = typed
            box.set(id, "name", typed)
        case .revert(let stored):
            name = stored
        case .ignore:
            break
        }
    }
}

// MARK: - words into a note

/// A file's words as a note's spans: the one markdown reader
/// (`SpanText.textToSpans`), off the main thread for a long file. A link
/// in the words counts only if this box knows its target — read on the
/// main thread first, since the box's index is the main thread's.
enum FileWords {
    static func spans(_ text: String, box: BoxModel, done: @escaping (String) -> Void) {
        let known = Set(box.entities.keys)
        DispatchQueue.global(qos: .userInitiated).async {
            let json = SpanText.json(SpanText.textToSpans(text, isKnown: { known.contains($0) }))
            DispatchQueue.main.async { done(json) }
        }
    }
}

// MARK: - where the bytes live on a phone

/// A phone cannot keep a reference to a file it does not own: the picker
/// hands back a path inside another app's container, readable only for
/// that one callback (verified live, 2026-08-09). So the phone COPIES,
/// beside the box, and Liv's copy becomes the truth.
enum FileStore {
    /// Copy into `<box folder>/files/<uuid>/<the file's own name>`, built
    /// from the very string the box was opened with — that is what lets the
    /// box remember it relative to itself. Nil when it cannot be copied.
    static func adopt(_ source: URL, box: BoxModel) -> String? {
        let folder = ((box.path as NSString).deletingLastPathComponent as NSString)
            .appendingPathComponent("files/\(UUID().uuidString)")
        let target = (folder as NSString).appendingPathComponent(source.lastPathComponent)
        do {
            try FileManager.default.createDirectory(
                atPath: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: URL(fileURLWithPath: target))
            return target
        } catch {
            try? FileManager.default.removeItem(atPath: folder)
            return nil
        }
    }

    /// A copy the box did not take: its folder goes.
    static func discard(_ copy: String) {
        try? FileManager.default.removeItem(atPath: (copy as NSString).deletingLastPathComponent)
    }
}

// MARK: - the door

/// The `+` menu's File row, after the picker. Each pick lands as its own
/// thing, stamped by the active workspace like every other creation door;
/// when every pick has answered, the last one that landed opens.
enum FileImport {
    static func adopt(
        _ urls: [URL], box: BoxModel, workspaces: WorkspaceModel, desk: DeskModel
    ) {
        var answered = 0
        var landed: [LivEntityID] = []
        func finish(_ id: LivEntityID) {
            answered += 1
            if id.isAbsent {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            } else {
                workspaces.stamp(id, in: box)
                landed.append(id)
            }
            if answered == urls.count, let last = landed.last { desk.open(last) }
        }
        for url in urls {
            // Open for as long as Rust reads it, or the copy is made.
            let scoped = url.startAccessingSecurityScopedResource()
            let close = { if scoped { url.stopAccessingSecurityScopedResource() } }
            box.fileText(url.path) { found in
                if let text = found?.text {
                    close()
                    FileWords.spans(text, box: box) { spans in
                        box.makeNote(name: found?.name, spansJson: spans, done: finish)
                    }
                    return
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    let copy = FileStore.adopt(url, box: box)
                    close()
                    DispatchQueue.main.async {
                        guard let copy else { return finish(.absent) }
                        box.addFile(copy) { id in
                            if id.isAbsent { FileStore.discard(copy) }
                            finish(id)
                        }
                    }
                }
            }
        }
    }
}
