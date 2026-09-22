// liv iOS — A CATCH FROM OUTSIDE: what it is, and where one waits.
//
// Compiled into BOTH the app and the share extension (build.sh names
// this file in each swiftc), so it imports Foundation and nothing else.
// The extension writes, the app reads, and the rule for what words and
// a URL become is ONE function here — so the `liv://` door (Routes.swift)
// and the share sheet (ShareExtension/) cannot drift apart (standing
// rule 4).

import Foundation

/// The App Group both bundles are entitled to (Liv.entitlements). The
/// box lives here too (BoxPath.swift): one id, defined once.
enum LivGroup {
    static let id = "group.liv.app"

    /// The shared container, or nil where no group resolves — a device
    /// build whose provisioning profile carries no App Group (build.sh
    /// says how to get one). The simulator always resolves it.
    static var container: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }
}

enum Catch {
    /// The catch itself: the words and/or the URL, each trimmed, words
    /// first, one line break between; nil when there is nothing to
    /// catch. A blank catch is not an empty note with a space in it —
    /// `liv_capture_at` refuses empty text anyway, so the door decides
    /// before the box has to.
    static func text(_ words: String?, _ url: String?) -> String? {
        let parts = [words, url].compactMap { raw -> String? in
            let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}

/// THE SPOOL: a folder in the App Group container where the share
/// extension leaves what it caught, and the app picks it up at its next
/// foreground (RootView, `drainSpool`).
///
/// WHY A FOLDER AND NOT THE BOX. The extension could link the Rust seam
/// and call `liv_capture_at` itself — the box is in the same container.
/// It does not, for three reasons that each stand alone: every `liv_*`
/// call lives in Box.swift (standing rule 1, and the extension is a
/// second binary); an extension has a memory ceiling and a few seconds
/// to live, which is no place to open a box; and a second process
/// writing the log while the app is suspended is a lock the app would
/// then have to contend for. The cost is that a catch shows at the next
/// foreground rather than the instant it is shared — which is when you
/// would look for it anyway. `design/ios.md` §M1 sketched this exact
/// fallback ("busy flock ⇒ spool JSON drained by the main app"); here
/// it is the only path, and plain text rather than JSON, because a
/// catch is a sentence.
enum Spool {
    struct Item {
        let url: URL
        let text: String

        /// The box has it: the file is finished with. Called by the
        /// drain only after `liv_capture_at` answered with an id, so a
        /// catch the box refused waits for the next foreground rather
        /// than being lost.
        func done() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// `<group>/liv/spool/`, created on first use. Beside the box's own
    /// `liv/` folder, not inside `liv.log`'s business.
    static var dir: URL? {
        guard let base = LivGroup.container else { return nil }
        let dir = base.appendingPathComponent("liv/spool", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Leave one catch. Written to a `.tmp` and renamed into place, so
    /// the app can never read half a file. The name sorts by time, so
    /// three catches in a row land in the Inbox in the order they were
    /// made.
    @discardableResult
    static func put(_ text: String) -> Bool {
        guard let dir else { return false }
        let name = String(format: "%013.0f-%@", Date().timeIntervalSince1970 * 1000, UUID().uuidString)
        let tmp = dir.appendingPathComponent(name + ".tmp")
        let final = dir.appendingPathComponent(name + ".txt")
        do {
            try text.write(to: tmp, atomically: false, encoding: .utf8)
            try FileManager.default.moveItem(at: tmp, to: final)
            return true
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            return false
        }
    }

    /// Everything waiting, oldest first. A blank file is dropped here —
    /// the extension never writes one, but a folder in a shared
    /// container is not only ours to write.
    static func pending() -> [Item] {
        guard let dir,
            let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path)
        else { return [] }
        return names.filter { $0.hasSuffix(".txt") }.sorted().compactMap { name in
            let url = dir.appendingPathComponent(name)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            return Item(url: url, text: trimmed)
        }
    }
}
