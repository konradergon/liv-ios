// liv iOS — files (design/p7-files-model.md, p15, p20j; owner
// 2026-08-08: "how should the app be structured if it handles .docx,
// LaTeX, Excel…").
//
// A file of any format is an ORDINARY entity. The bytes stay where they
// are; the box records a reference — the path and a hash of the content
// — plus the same six fields everything else has. So a contract is
// filed by area and project like a note is, appears in the same
// searches, and answers to the same workspaces. That is the whole
// answer to "folders can only hold a thing in one place".
//
// Liv NEVER writes those bytes. It previews them, hands them to the app
// that owns the format, and notices when that app saved: opening a file
// re-hashes it, and a changed hash IS the integration. No watcher, no
// timer, no sync engine.
//
// There is no seventh kind. "Has a file" crosscuts the six — a scanned
// contract is a file AND can be a task. `FileFacts.of` reads the cells,
// it does not consult a type.

import SwiftUI
import UniformTypeIdentifiers

// MARK: - what the cells say

/// The file an entity refers to, read off its cells. Nil for everything
/// that is not a file, which is most things.
struct FileFacts {
    /// Where the bytes are, as the box recorded them.
    let path: String
    /// The extension, lowercased, or "" — the core stores this as an
    /// ordinary `format` cell, so `format:pdf` filters for free.
    let format: String

    static func of(_ row: EntityRow?) -> FileFacts? {
        guard let row else { return nil }
        guard
            let cell = (row.cells ?? []).first(where: { $0.kind == "file" }),
            let path = cell.value, !path.isEmpty
        else { return nil }
        let declared = (row.cells ?? [])
            .first { $0.property == "format" }?.value ?? ""
        let ext =
            declared.isEmpty
            ? (path as NSString).pathExtension.lowercased()
            : declared.lowercased()
        return FileFacts(path: path, format: ext)
    }

    var url: URL { URL(fileURLWithPath: path) }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }

    /// What KIND of file, for a glyph and for how to show it. Derived
    /// from the format, never stored — one function, so the icon in a
    /// list and the body of a tab can never disagree.
    /// The glyph each class wears is drawn in Glyph.swift — one file
    /// color, the format shown by the drawing (blueprints, 2026-08-12).
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

/// A file's tab: the name, then the BYTES, full bleed — the way a note
/// tab is the note. The facts live behind the (i) door exactly as they
/// do for a note; contents and properties never share a surface
/// (owner, 2026-08-09: "never display file contents directly in
/// property views"). The bytes are read-only on purpose: Word owns the
/// words.
struct FileBody: View {
    let id: UInt64

    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel

    @State private var name = ""
    @State private var seeded = false
    @State private var pendingName: String?
    @State private var resynced = false
    /// True while an old markdown file is turning into a note. The screen
    /// stays blank for that beat rather than flashing the file view.
    @State private var converting = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        Group {
            if converting {
                Color.clear
            } else if let row = box.entity(id), let facts = FileFacts.of(row) {
                body(row, facts)
            } else {
                EmptyHint("This file is not in the box anymore.")
                    .frame(maxHeight: .infinity)
            }
        }
        .onAppear(perform: arrive)
        .onChange(of: storedName) { old, fresh in
            if pendingName == fresh { pendingName = nil }
            if name != fresh, name == "" || name == old { name = fresh }
        }
    }

    /// A file tab is its NAME and its filing, and that is all (owner,
    /// 2026-08-13: "preview should not be a functionality since it is
    /// absolutely useless"). Reading a Word file means opening Word —
    /// ••• → "Open in…" — and a read-only render of it inside Liv was
    /// a screen that looked like an editor and was not one.
    private func body(_ row: EntityRow, _ facts: FileFacts) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            nameField(facts)
            if !facts.exists { brokenCard(facts) }
            Spacer(minLength: 0)
        }
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
            // No "Open in…" here any more (owner, 2026-08-13). Handing
            // the bytes to the app that owns the format is a SECONDARY
            // verb, and secondary verbs live in the ••• menu — the app's
            // own rule. It was the only button on the screen, which made
            // a file look like something you could not read.
            HStack(spacing: 8) {
                IconChip(glyph: .file(facts.fileClass), color: LivKind.file.color, size: 22)
                if !facts.format.isEmpty { ValueChip(facts.format) }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 56)
        .padding(.bottom, 12)
    }

    /// The reference points at nothing. Say so plainly and keep the
    /// entity — its filing is still real, and the file may come back.
    private func brokenCard(_ facts: FileFacts) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("The file has moved or been deleted")
                .font(.system(size: LivType.strong, weight: .semibold))
                .foregroundStyle(LivTheme.text)
            Text(facts.path)
                .font(.system(size: LivType.label, design: .monospaced))
                .foregroundStyle(LivTheme.text3)
                .lineLimit(2)
                .truncationMode(.head)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: LivTheme.radius).fill(LivTheme.panel))
        .overlay(
            RoundedRectangle(cornerRadius: LivTheme.radius)
                .strokeBorder(LivTheme.red.opacity(0.5), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: arrival

    /// Opening a file is when Liv catches up with whatever edited it —
    /// a re-hash, once, here. No watcher and no timer: the core's own
    /// rule, and the only moment the answer matters.
    private func arrive() {
        if !seeded {
            name = storedName
            seeded = true
        }
        guard !resynced else { return }
        resynced = true
        if becomeNote() { return }
        box.resyncFile(id)
    }

    /// A markdown file added BEFORE the rule above existed is still a
    /// file reference in the box. Opening it converts it, once: the words
    /// move in, the file cell comes off, and the tab redraws as the note
    /// it should always have been. Nothing is lost — the log keeps every
    /// version, and the file on disk is never written.
    private func becomeNote() -> Bool {
        guard let row = box.entity(id), let facts = FileFacts.of(row),
            NoteBytes.isNote(facts.format), facts.exists,
            let text = NoteBytes.read(facts.url)
        else { return false }
        converting = true
        let stored = storedName
        box.content(id) { doc in
            box.setContent(
                id, spansJson: SpanText.json(SpanText.textToSpans(text)),
                base: doc?.fingerprint ?? 0
            ) { status, _ in
                guard status == 1 else {
                    converting = false
                    return
                }
                // The name loses its extension with the file: every note
                // is markdown, so ".md" in the name says nothing.
                box.set(id, "name", NoteBytes.name(of: stored))
                box.unset(id, "format")
                box.unset(id, "file")
            }
        }
        return true
    }

    private var storedName: String {
        (box.entity(id)?.cells ?? []).first { $0.property == "name" }?.value ?? ""
    }

    private func commitName() {
        guard let row = box.entity(id), row.trashed != true else { return }
        let stored = storedName
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else {
            name = stored
            return
        }
        guard typed != stored, typed != pendingName else { return }
        pendingName = typed
        box.set(id, "name", typed)
    }
}

// MARK: - the bytes that are not foreign at all

/// Markdown is not a foreign format — it is what a note IS. A .md file
/// added to Liv therefore becomes a NOTE, with its words in the box:
/// editable, searchable, rendered, versioned like everything else. It
/// does not become a file reference with a read-only preview beside an
/// "Open in…" button, which is what it used to do (owner, 2026-08-13:
/// "totally broken … .md should work like any note").
///
/// This is NOT in-app editing of foreign bytes, the thing the product
/// refuses. Nothing writes back to the file: its words are copied into
/// the box once, at the door, and the file goes its own way.
///
/// UTF-8 only (owner, 2026-08-11). Bytes that are not UTF-8 are not text
/// we can honestly claim to hold, so they stay a file.
enum NoteBytes {
    /// Markdown only. Deliberately narrow: `.txt` is somebody else's
    /// text file, and `.tex`/`.bib` are SOURCE for another program —
    /// swallowing a thesis into the box the first time it was added is
    /// the opposite of what files are for. Markdown is the one format
    /// that IS a note.
    static let formats: Set<String> = ["md", "markdown"]

    static func isNote(_ format: String) -> Bool {
        formats.contains(format.lowercased())
    }

    /// The words, or nil when they are not UTF-8 text.
    static func read(_ url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The name a person reads: the file name with its extension off.
    /// "Linux Installation.md" is a note called "Linux Installation" —
    /// every note is markdown, so saying so in the name is noise.
    static func name(of fileName: String) -> String {
        let stem = (fileName as NSString).deletingPathExtension
        return stem.isEmpty ? fileName : stem
    }

    /// Land text as a real note: born, named, then filled in one pass.
    /// The content write is a compare-and-swap like every other, so the
    /// fresh note's own fingerprint is read back first.
    static func land(
        _ text: String, named: String, box: BoxModel,
        done: @escaping (UInt64) -> Void
    ) {
        box.createNote { id in
            guard id != 0 else { return done(0) }
            if !named.isEmpty { box.set(id, "name", named) }
            box.content(id) { doc in
                let spans = SpanText.textToSpans(text)
                box.setContent(
                    id, spansJson: SpanText.json(spans),
                    base: doc?.fingerprint ?? 0
                ) { status, _ in
                    done(status == 1 ? id : id)
                }
            }
        }
    }
}

// MARK: - where the bytes live on a phone

/// A phone cannot keep a reference to a file it does not own.
///
/// The picker hands back a path inside another app's container (iCloud
/// Drive, Files, Dropbox…), readable only for the length of that one
/// callback. Recording that path produces an entity whose file is
/// "moved or deleted" the moment you look at it again — verified live,
/// 2026-08-09.
///
/// So a phone import COPIES, exactly as the camera already does
/// (Camera.swift's CameraStore). Liv's copy becomes the truth and the
/// original goes its own way; the import says so out loud. On the
/// desktop, where paths are stable and the user owns their folders, the
/// same core verb records the path in place — that is the difference
/// between the two, and it lives here rather than in the core.
enum FileStore {
    /// Copy into <Application Support>/liv/files/<uuid>.<ext> and
    /// return the new path. Nil when the bytes cannot be read.
    static func adopt(_ source: URL) -> String? {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        do {
            let dir = try directory()
            // The name is kept for the extension only — the box holds
            // the name a person reads, and renaming there must never
            // touch a file on disk.
            let ext = source.pathExtension
            var url = dir.appendingPathComponent(UUID().uuidString)
            if !ext.isEmpty { url = url.appendingPathExtension(ext) }
            let bytes = try Data(contentsOf: source)
            try bytes.write(to: url, options: .atomic)
            return url.path
        } catch {
            return nil
        }
    }

    private static func directory() throws -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        .appendingPathComponent("liv", isDirectory: true)
        .appendingPathComponent("files", isDirectory: true)
        try FileManager.default.createDirectory(
            at: base, withIntermediateDirectories: true)
        return base
    }
}

// MARK: - the door

/// What one pick turned out to be: Liv's own words, or foreign bytes.
private enum Pick {
    case note(text: String, name: String)
    case file(path: String, name: String)
}

/// The system file picker, lowered to the librarian verb.
struct FileImportButton: View {
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var workspaces: WorkspaceModel
    @State private var picking = false

    var body: some View {
        // Wears the create menu's face, it does not imitate it. The
        // imitation lost the border and vanished in light mode
        // (owner, 2026-08-10).
        Button {
            picking = true
        } label: {
            HStack(spacing: 8) {
                // The drawn file page, not Apple's folder: three verbs
                // in one menu drawn in two different languages is what
                // the icon system exists to stop.
                LivIcon(glyph: .file(.other), color: LivTheme.text, size: 18)
                Text("Add a file")
            }
            .livVerbFace()
        }
        .buttonStyle(.plain)
        .fileImporter(
            isPresented: $picking, allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            adopt(urls)
        }
    }

    /// Each pick lands as its own entity, stamped by the active
    /// workspace exactly as every other creation door stamps — so things
    /// dropped while standing in a project arrive already filed. The
    /// last one opens.
    ///
    /// Markdown becomes a NOTE (NoteBytes); everything else is copied in
    /// and referenced as a file.
    private func adopt(_ urls: [URL]) {
        DispatchQueue.global(qos: .userInitiated).async {
            let picks: [Pick] = urls.compactMap { url in
                let name = url.lastPathComponent
                if NoteBytes.isNote(url.pathExtension), let text = NoteBytes.read(url) {
                    return .note(text: text, name: NoteBytes.name(of: name))
                }
                return FileStore.adopt(url).map { .file(path: $0, name: name) }
            }
            DispatchQueue.main.async {
                var landed: [UInt64] = []
                let finish: (UInt64) -> Void = { id in
                    guard id != 0 else { return }
                    workspaces.stamp(id, in: box)
                    landed.append(id)
                    if landed.count == picks.count, let last = landed.last {
                        desk.open(last)
                    }
                }
                for pick in picks {
                    switch pick {
                    case .note(let text, let name):
                        NoteBytes.land(text, named: name, box: box, done: finish)
                    case .file(let path, let name):
                        box.addFile(path) { id in
                            guard id != 0 else { return }
                            // The copy is named by a random id on disk;
                            // the name a person reads is the one they
                            // picked.
                            box.set(id, "name", name)
                            finish(id)
                        }
                    }
                }
            }
        }
    }
}
