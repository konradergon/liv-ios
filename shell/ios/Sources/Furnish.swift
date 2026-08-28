// liv iOS — the furnishing pass (design/ios.md §10, what-liv-is-for v2).
// The app arrives furnished: the area select with exactly six options,
// and the three text properties the
// capture chips write (project / tags / people — whose absence on a
// fresh box made the chips silently write NOTHING; `set` and `addCell`
// refuse unknown property names).
//
// Idempotence is the core seed's own pattern: run on EVERY launch, after
// the first decoded snapshot, each item presence-guarded against that
// snapshot. No UserDefaults sentinel — reinstall-safe; an existing box
// gains only what it is missing; a furnished box does zero writes. All of
// it lands from the shell via existing BoxModel verbs on the one serial
// lane, with one explicit refresh when the last write returns.

import Foundation

enum Furnish {
    /// The six areas — the RESEARCHED canon (PARA, Wheel of Life, Things,
    /// Ultimate Brain; 2026-07-27), not invention. Fixed. No create-new.
    static let areaNames = [
        "Work", "Health", "Money", "Home", "Family & Friends", "Learning",
    ]

    /// The text fields the capture/camera chips write. `area` is separate:
    /// it is a select, born with its options.
    static let textProperties = ["project", "tags", "people"]

    /// The name this field used to carry. The product says Tags and the
    /// engine says `tags`; the shell said `subjects`, which made three
    /// names for one field (owner, 2026-08-27: "rename subjects to tags").
    static let oldTagName = "subjects"

    /// Run one pass against a decoded snapshot. Call once per launch (the
    /// caller guards); cross-launch idempotence lives in the guards below,
    /// never in device state.
    static func run(_ snap: Snapshot, box: BoxModel) {
        FurnishPass(box: box).run(snap)
    }
}

/// One pass. A class so the chained verb callbacks (all on main) share the
/// outstanding-write count; when the last write lands, ONE refresh
/// publishes the furnished snapshot. Zero missing items = zero writes and
/// zero refreshes.
private final class FurnishPass {
    private let box: BoxModel
    private var outstanding = 0
    private var launched = false

    init(box: BoxModel) {
        self.box = box
    }

    func run(_ snap: Snapshot) {
        furnishProperties(snap)
        launched = true
        finishIfDone()
    }

    /// Rewrite `old:` to `new:` in every saved workspace and filter query.
    ///
    /// Only the QUALIFIER KEY is touched — `subjects:x` becomes `tags:x`,
    /// and the word "subjects" appearing as free text is left alone,
    /// because a person searching for that word still means the word.
    private func renameInQueries(_ snap: Snapshot, from old: String, to new: String) {
        let rows: [(UInt64, String)] =
            (snap.workspaces ?? []).compactMap { r in (r.query?.isEmpty ?? true) ? nil : (r.id, r.query!) }
            + (snap.views ?? []).compactMap { r in (r.query?.isEmpty ?? true) ? nil : (r.id, r.query!) }
        for (id, text) in rows {
            let rewritten = text
                .split(separator: " ", omittingEmptySubsequences: false)
                .map { token -> String in
                    let t = String(token)
                    for prefix in ["\(old):", "-\(old):", "\"\(old):", "\"-\(old):"] {
                        if t.hasPrefix(prefix) {
                            return prefix.replacingOccurrences(of: old, with: new)
                                + String(t.dropFirst(prefix.count))
                        }
                    }
                    // `has:subjects` / `no:subjects` name the property as a
                    // VALUE, so they need the other half rewritten.
                    for lead in ["has:", "no:"] where t.lowercased() == lead + old {
                        return lead + new
                    }
                    return t
                }
                .joined(separator: " ")
            guard rewritten != text else { continue }
            track()
            box.set(id, "query", rewritten) { [self] _ in landed() }
        }
    }

    // MARK: a+b — properties, and the area options

    private func furnishProperties(_ snap: Snapshot) {
        let properties = snap.properties ?? []
        func existing(_ name: String) -> PropertyRow? {
            properties.first {
                ($0.name ?? "").compare(name, options: .caseInsensitive) == .orderedSame
            }
        }

        // MIGRATE BEFORE MINTING. A property is an entity and its name is
        // a cell, so renaming it is ONE write — and every cell keeps
        // pointing at it, because a cell references a property by name
        // resolved at read, not by a copy of the string.
        //
        // Changing the constant alone would have minted a second property
        // called `tags` and left every existing tag stranded on a
        // `subjects` no screen mentions any more. The data would still be
        // in the box and invisible, which is worse than losing it.
        var renamedTags = false
        if let old = existing(Furnish.oldTagName), let pid = old.id,
            existing("tags") == nil
        {
            renamedTags = true
            track()
            box.set(pid, "name", "tags") { [self] _ in landed() }
        }

        // AND EVERY SAVED QUERY THAT NAMES IT. Renaming the property
        // moved the data; a workspace or filter whose text still says
        // `subjects:` now names a property that does not exist, and an
        // unresolvable property is a REQUIRED WORD (owner, 2026-08-27:
        // "typo shows nothing") — so the saved filter silently stops
        // matching anything. Found by reading a real box: a filter called
        // `foo` held `area:Health subjects:psychopathy`.
        // NOT guarded on `renamedTags`. A box whose property was renamed
        // on an earlier launch still holds saved text naming the old one,
        // and that box is exactly the one nobody would think to check. The
        // rewrite writes only when a query actually changes, so a clean
        // box does nothing.
        renameInQueries(snap, from: Furnish.oldTagName, to: "tags")

        for name in Furnish.textProperties where existing(name) == nil {
            // The rename above lands after this snapshot was taken, so
            // `existing("tags")` is still nil in this pass. Minting here
            // would produce the exact duplicate the rename exists to avoid.
            if name == "tags" && renamedTags { continue }
            track()
            box.addProperty(name) { [self] _ in landed() }
        }

        if let area = existing("area") {
            // Present. Add only the missing options (liv_add_option_at is
            // idempotent anyway; the guard just skips the round-trip). A
            // legacy TEXT `area` refuses options harmlessly — values keep
            // flowing as text, and the picker unions live values in.
            let held = (area.options ?? []).compactMap { $0.name }
            addOptions(to: area.id ?? 0, skipping: held)
        } else {
            track()
            box.addProperty("area", kind: "select") { [self] id in
                if id != 0 { addOptions(to: id, skipping: []) }
                landed()
            }
        }
    }

    private func addOptions(to property: UInt64, skipping held: [String]) {
        guard property != 0 else { return }
        for name in Furnish.areaNames {
            guard
                !held.contains(where: {
                    $0.compare(name, options: .caseInsensitive) == .orderedSame
                })
            else { continue }
            track()
            box.addOption(property, name) { [self] _ in landed() }
        }
    }

    // MARK: c — no workspaces

    /// The six areas are FIELD VALUES, not places (design/furnishing-study.md).
    /// They were furnished as six workspaces until 2026-07-29; that made
    /// filing a mode you had to enter BEFORE typing, and put the app's most
    /// ambiguous question — is the child's dentist Health or Family? — in
    /// front as the primary navigation. The study measured 4 of 7 ordinary
    /// captures with no defensible area.
    ///
    /// A workspace is now what the owner says it is: a working context the
    /// USER makes, which presets fields on new objects and filters the
    /// surfaces to match. The app ships with none, and the builtin Home is
    /// left as the plain default — never re-aimed at an "area:Home" lens.
    ///
    /// Existing boxes keep whatever workspaces they already have. Nothing is
    /// deleted; the app simply stops creating these.

    // MARK: the outstanding-write ledger (main-thread only)

    /// Every write passes through track() before it is issued — so `wrote`
    /// is exactly "this pass touched the box".
    private var wrote = false

    private func track() {
        outstanding += 1
        wrote = true
    }

    private func landed() {
        outstanding -= 1
        finishIfDone()
    }

    private func finishIfDone() {
        guard launched, outstanding == 0, wrote else { return }
        // The one refresh at the end; a furnished box stays silent.
        box.refresh()
    }
}
