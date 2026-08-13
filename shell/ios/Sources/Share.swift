// liv iOS — Share & Export (roadmap phase 7). The ••• menu earns its
// secondary actions: hand ONE note to the rest of the phone as plain
// markdown, either through the system share sheet (Share) or as a real
// .md file the share sheet can save to Files (Export).
//
// Both read the same two things the editor reads — the name cell and
// `liv_content_at`'s spans — and flatten them with `SpanText.spansToText`,
// the one flattener in the shell. Nothing new crosses the FFI, nothing is
// written to the box: sharing a note is a READ.

import SwiftUI
import UIKit

// MARK: - the document

/// One note, as markdown. Pure: spans + name in, text out — so the
/// self-check can pin the shape without a box, a file or a sheet.
enum NoteExport {
    /// The file's body: an `# H1` title line (only when the note carries
    /// a real name that its first line does not already state), then the
    /// content verbatim.
    ///
    /// Verbatim matters: the buffer already IS markdown (the editor
    /// stores the markers), so exporting must not re-render it. The one
    /// thing added is a title, because a file that opens with "- [ ] milk"
    /// tells the reader nothing about what it is.
    static func markdown(name: String, body: String) -> String {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return text }
        // Don't repeat a heading the note already opens with.
        let first = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        if livDisplayTitle(first).compare(title, options: .caseInsensitive) == .orderedSame {
            return text
        }
        return text.isEmpty ? "# \(title)" : "# \(title)\n\n\(text)"
    }

    /// A filename a human can find again: the note's own name, stripped
    /// of everything a filesystem argues about, capped so no path limit
    /// is ever the reason an export fails. Never empty.
    static func filename(_ name: String, id: UInt64) -> String {
        let bad = CharacterSet(charactersIn: "/\\?%*|\"<>:\n\r\t")
        let cleaned = name
            .components(separatedBy: bad).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let squeezed = cleaned.split(separator: " ").joined(separator: " ")
        let stem = squeezed.isEmpty ? "liv-note-\(id)" : String(squeezed.prefix(60))
        return stem + ".md"
    }
}

// MARK: - the sheet

/// UIActivityViewController, wrapped. SwiftUI's own ShareLink cannot
/// carry a value we only learn ASYNCHRONOUSLY (the content arrives on
/// the box's serial queue), so the desk fetches first and presents this
/// with the finished payload.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// What the desk is sharing: either the markdown itself, or a temporary
/// .md file holding it. `Identifiable` so one `.sheet(item:)` serves both.
struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]

    /// Text — the share sheet then offers Messages, Mail, Notes, copy…
    static func text(_ markdown: String) -> SharePayload {
        SharePayload(items: [markdown])
    }

    /// A real file, so "Save to Files" produces a .md rather than a .txt
    /// of the same words. Written to the caches directory under the
    /// note's own name; the system copies it out of there and the OS
    /// reclaims what is left.
    static func file(_ markdown: String, named filename: String) -> SharePayload? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try markdown.data(using: .utf8)?.write(to: url, options: .atomic)
        } catch {
            return nil
        }
        return SharePayload(items: [url])
    }
}

// MARK: - the self-check (no test target; rides -share.selfcheck 1)

func livShareSelfCheck() -> [String] {
    var failures: [String] = []
    func check(_ label: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        if !ok { failures.append("FAIL \(label) \(detail())") }
    }

    check(
        "a named note gets an H1",
        NoteExport.markdown(name: "Roof project", body: "- [ ] call")
            == "# Roof project\n\n- [ ] call",
        NoteExport.markdown(name: "Roof project", body: "- [ ] call"))
    check(
        "an unnamed note is its body, verbatim",
        NoteExport.markdown(name: "", body: "## Notes\n- [ ] milk")
            == "## Notes\n- [ ] milk")
    check(
        "a title the body already states is not repeated",
        NoteExport.markdown(name: "Roof project", body: "# Roof project\n\nbody")
            == "# Roof project\n\nbody",
        NoteExport.markdown(name: "Roof project", body: "# Roof project\n\nbody"))
    check(
        "the match ignores case and markers",
        NoteExport.markdown(name: "roof PROJECT", body: "## Roof project\ntail")
            == "## Roof project\ntail")
    check(
        "an empty note is just its title",
        NoteExport.markdown(name: "Empty", body: "   ") == "# Empty")
    check(
        "nothing at all is nothing",
        NoteExport.markdown(name: " ", body: "\n\n") == "")

    check(
        "the filename is the name",
        NoteExport.filename("Roof project", id: 7) == "Roof project.md",
        NoteExport.filename("Roof project", id: 7))
    check(
        "slashes and colons cannot reach the filesystem",
        !NoteExport.filename("a/b:c", id: 7).contains("/")
            && !NoteExport.filename("a/b:c", id: 7).contains(":"),
        NoteExport.filename("a/b:c", id: 7))
    check(
        "a nameless note still gets a findable file",
        NoteExport.filename("", id: 42) == "liv-note-42.md",
        NoteExport.filename("", id: 42))
    check(
        "a punctuation-only name is treated as nameless",
        NoteExport.filename("///", id: 9) == "liv-note-9.md",
        NoteExport.filename("///", id: 9))
    check(
        "a very long name is capped",
        NoteExport.filename(String(repeating: "x", count: 200), id: 1).count <= 63)
    check("every filename is markdown", NoteExport.filename("x", id: 1).hasSuffix(".md"))

    return failures
}
