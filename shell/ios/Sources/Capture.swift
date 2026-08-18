import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Vision

// MARK: - Quick Capture: the app's one door in (owner, 2026-08-18)

/// The `+` opens THIS. One field with the keyboard already up, and a
/// Save that does not ask you to file anything: the words land in the
/// Inbox as a capture, and the Inbox's Route lens is where they get an
/// address later. Deciding what a thought is at the moment you have it
/// is the tax every "New ▸ Note / Task / Event" menu charges; this sheet
/// stops charging it, and keeps the four kinds for when you already know.
///
/// It replaced the create MENU (2026-08-13 – 2026-08-18). That menu made
/// you choose a kind before you could type a word, and then dropped you
/// in a full-screen editor or a properties card — three surfaces to
/// write one line down.
///
/// **What is deliberately not here** (owner: "make sure you have thought
/// about everything and we don't get useless functionality in"):
///   * no name field — the first line names it, which is what the core
///     already does for anything unnamed (`services/src/content.rs`
///     `source_name`), so nothing is ever typed twice;
///   * no destination line — there is one Inbox, and a sentence saying
///     so on every capture is furniture;
///   * no property chips — the workspace stamps silently here exactly as
///     it does at every other door;
///   * no File row in the kind list — the paperclip IS the file door,
///     and one door per thing (standing rule 4).
struct CaptureSheet: View {
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel
    @EnvironmentObject var workspaces: WorkspaceModel
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    /// What Save will make. `.capture` — unrouted — is the default, and
    /// the whole point of the sheet.
    @State private var kind: CaptureKind = .capture
    /// Photos shot into this capture. Each is already a file entity in
    /// the box (the camera commits at the shutter); the capture links to
    /// them when it saves.
    @State private var shots: [CaptureShot] = []
    @State private var reading = 0
    @State private var saving = false
    @State private var picking = false
    @State private var shooting = false
    @State private var kindMenu: LivMenu?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            field
            ForEach(Array(shots.enumerated()), id: \.element.id) { i, shot in
                shotRow(shot, number: i + 1)
            }
            actions
        }
        .background(LivTheme.canvas)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(LivTheme.canvas)
        .livMenu($kindMenu)
        .onAppear { DispatchQueue.main.async { focused = true } }
        .fileImporter(
            isPresented: $picking, allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            // A picked file is a document in its own right, not an
            // attachment to a thought: it takes the same landing it has
            // always taken, and the sheet gets out of the way.
            FileImport.adopt(urls, box: box, workspaces: workspaces, desk: desk)
            dismiss()
        }
        .fullScreenCover(isPresented: $shooting) {
            // ONE camera (standing rule 4) — in scanning dress, because
            // this capture owns the words and the filing.
            CameraFlow(scanning: true, onShot: { id, path in read(id, at: path) })
                .environmentObject(box)
                .environmentObject(desk)
                .environmentObject(workspaces)
        }
    }

    // MARK: the field

    private var field: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Write something")
                    .font(.system(size: LivType.body))
                    .foregroundStyle(LivTheme.text3)
                    .padding(.horizontal, 21)
                    .padding(.top, 16)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.system(size: LivType.body))
                .foregroundStyle(LivTheme.text)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .padding(.horizontal, 16)
                .padding(.top, 8)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: what the camera read

    /// One line per photo: that it is there, and — while Vision is
    /// working — that its words are still coming. Never a preview tile:
    /// a thumbnail here would push the field off a small screen, and the
    /// photo you just took is the one thing you do not need shown back.
    ///
    /// It says "Photo", not the file's name: a shot straight off the
    /// camera is called `031000DC-07F4-….heic`, which tells a reader
    /// nothing. The photo is NAMED on save, after the capture's first
    /// line — the same rule that names everything else here.
    private func shotRow(_ shot: CaptureShot, number: Int) -> some View {
        HStack(spacing: 9) {
            LivIcon(glyph: .file(.image), color: LivTheme.text3, size: 17)
            Text(
                shot.words == nil
                    ? "Reading the photo…"
                    : (shots.count > 1 ? "Photo \(number)" : "Photo"))
                .font(.system(size: LivType.label))
                .foregroundStyle(LivTheme.text2)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button {
                drop(shot)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: LivType.caption, weight: .semibold))
                    .foregroundStyle(LivTheme.text3)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove photo")
        }
        .padding(.leading, 18)
        .padding(.trailing, 4)
        .frame(height: 38)
    }

    // MARK: the one action row

    private var actions: some View {
        HStack(spacing: 2) {
            iconKey("camera", label: "Photo") { shoot() }
            iconKey("paperclip", label: "File") { focused = false; picking = true }
            Spacer(minLength: 6)
            kindKey
            saveKey
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    /// ONE control for what this becomes, showing the current answer —
    /// not four buttons that all look like the primary one.
    private var kindKey: some View {
        Button {
            // The menu comes from the bottom, where the keyboard is. The
            // keyboard goes first and comes back after the pick, so the
            // two never fight over the same strip of screen.
            focused = false
            kindMenu = kindChoices()
        } label: {
            HStack(spacing: 4) {
                Text(kind.title)
                    .font(.system(size: LivType.body))
                    .foregroundStyle(LivTheme.text2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: LivType.micro, weight: .semibold))
                    .foregroundStyle(LivTheme.text3)
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Save as \(kind.title)")
    }

    private var saveKey: some View {
        Button(action: save) {
            Text("Save")
                .font(.system(size: LivType.body, weight: .semibold))
                .foregroundStyle(savable ? LivTheme.onAccent : LivTheme.text3)
                .padding(.horizontal, 17)
                .frame(height: 36)
                .background(
                    Capsule().fill(savable ? LivTheme.accent : LivTheme.panel2)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!savable || saving)
    }

    private func iconKey(
        _ symbol: String, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: LivType.title, weight: .light))
                .foregroundStyle(LivTheme.text2)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Not while a photo is still being read: saving a heartbeat before
    /// Vision answers would drop the words the photo was taken FOR, and
    /// the read takes well under a second.
    private var savable: Bool {
        reading == 0 && (!words.isEmpty || !shots.isEmpty)
    }

    private var words: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func kindChoices() -> LivMenu {
        LivMenu(
            id: "capture-kind", from: .bottom, title: "Save as",
            items: CaptureKind.allCases.map { choice in
                LivMenuItem(label: choice.title, glyph: choice.glyph) {
                    kind = choice
                    DispatchQueue.main.async { focused = true }
                }
            })
    }

    // MARK: the camera, and the words in a photo

    private func shoot() {
        focused = false
        shooting = true
    }

    /// A shot landed. The picture is filed as itself — Liv never rewrites
    /// your bytes — and what it SAYS is read on the device and appended
    /// to the words, where search, links and the first-line name can all
    /// reach it. This is the camera's whole job here (owner, 2026-08-18:
    /// "Photo with OCR into the body").
    private func read(_ id: UInt64, at path: String) {
        shots.append(CaptureShot(id: id))
        reading += 1
        CaptureOCR.read(path) { found in
            reading -= 1
            guard let at = shots.firstIndex(where: { $0.id == id }) else { return }
            shots[at].words = found
            guard !found.isEmpty else { return }
            text = words.isEmpty ? found : words + "\n\n" + found
        }
    }

    /// Taking a photo back off the capture unlinks it and takes its words
    /// with it. The file entity itself stays — it was committed at the
    /// shutter, and deleting someone's photo because they retyped a line
    /// is not a thing this app does.
    private func drop(_ shot: CaptureShot) {
        shots.removeAll { $0.id == shot.id }
        guard let read = shot.words, !read.isEmpty else { return }
        text =
            text
            .replacingOccurrences(of: "\n\n" + read, with: "")
            .replacingOccurrences(of: read, with: "")
    }

    // MARK: saving

    /// One entity, then its links, then out. Every kind keeps every word
    /// that was typed — a record puts its first line in the name and the
    /// rest in its content, so nothing typed here is ever dropped.
    private func save() {
        guard savable, !saving else { return }
        saving = true
        let typed = words
        let land: (UInt64) -> Void = { id in
            saving = false
            guard id != 0 else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            workspaces.stamp(id, in: box)
            for shot in shots {
                // The link property — the same edge a `[[ ]]` writes
                // (services/src/links.rs), so the photo shows in the
                // capture's Links and the capture shows on the photo's.
                box.addCell(id, "related", "#\(shot.id)")
                if let name = firstLine(typed), !name.isEmpty {
                    // Otherwise the links row reads "B3F1…-9C2.heic".
                    box.set(shot.id, "name", name)
                }
            }
            dismiss()
            open(id)
        }

        switch kind {
        case .capture:
            box.capture(typed.isEmpty ? "Photo" : typed, done: land)
        case .note:
            box.createNote { id in
                guard id != 0 else { return land(0) }
                write(typed, into: id) { land(id) }
            }
        case .task, .event:
            let stamp = Civil.stamp(
                day: desk.contextDay ?? Civil.todayDay(),
                hhmm: Int64(LivDue.defaultHHMM))
            let named: (UInt64) -> Void = { id in
                guard id != 0 else { return land(0) }
                box.set(id, "name", firstLine(typed) ?? "")
                // Anything past the first line is the record's own body,
                // reachable in the editor. A capture never loses a word.
                write(rest(typed), into: id) { land(id) }
            }
            if kind == .event {
                box.createEvent(dueCivil: stamp, dateOnly: false, done: named)
            } else {
                box.createTask { id in
                    guard id != 0 else { return named(0) }
                    box.setSpan(id, "due", start: stamp, end: 0, dateOnly: false)
                    named(id)
                }
            }
        }
    }

    private func write(_ body: String, into id: UInt64, then: @escaping () -> Void) {
        guard !body.isEmpty else { return then() }
        let spans = SpanText.textToSpans(body, isKnown: { box.entity($0) != nil })
        box.setContent(id, spansJson: SpanText.json(spans), base: 0) { _, _ in then() }
    }

    /// Where you end up. A capture goes nowhere — that is what makes it
    /// quick. Anything you named a kind for opens, because you already
    /// said you meant to work on it.
    private func open(_ id: UInt64) {
        switch kind {
        case .capture: break
        case .note: desk.open(id)
        case .task, .event: desk.open(id, as: .record)
        }
    }

    private func firstLine(_ body: String) -> String? {
        body.split(separator: "\n").first.map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
    }

    private func rest(_ body: String) -> String {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1 else { return "" }
        return lines.dropFirst().joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - what a capture can become

/// The four the create menu had, minus File — the paperclip is that door.
enum CaptureKind: String, CaseIterable {
    case capture, note, task, event

    /// LITERAL names (owner's standing rule): each says what the thing
    /// will be, not what will happen to it.
    var title: String {
        switch self {
        case .capture: return "Capture"
        case .note: return "Note"
        case .task: return "Task"
        case .event: return "Event"
        }
    }

    var glyph: LivGlyph {
        switch self {
        case .capture: return .capture
        case .note: return .note
        case .task: return .task
        case .event: return .event
        }
    }
}

/// A photo shot into this capture: the file entity the camera committed,
/// and what Vision read out of it (nil until the read finishes — which
/// is both the "still reading" state and what lets removing the photo
/// take its words back out).
private struct CaptureShot: Identifiable {
    let id: UInt64
    var words: String?
}

// MARK: - reading a photo

/// Vision, on the device. No network, no key, no service: the words on a
/// photographed receipt, whiteboard or page become ordinary text in the
/// capture, which is the only thing that makes a picture findable three
/// weeks later. A photo whose words are never read is a photo you have to
/// remember taking.
enum CaptureOCR {
    static func read(_ path: String, done: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let found = recognise(path)
            DispatchQueue.main.async { done(found) }
        }
    }

    /// Empty is a perfectly good answer — most photos have no words in
    /// them, and a picture of a dog must not put "dog" in your note.
    private static func recognise(_ path: String) -> String {
        guard let image = UIImage(contentsOfFile: path)?.cgImage else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // The owner's two languages, in the order the phone reads them.
        request.recognitionLanguages = ["sv-SE", "en-US"]
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
