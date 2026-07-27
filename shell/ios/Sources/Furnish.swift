// liv iOS — the furnishing pass (design/ios.md §10, what-liv-is-for v2).
// The app arrives furnished: six areas of life as workspaces, the area
// select with exactly six options, and the three text properties the
// capture chips write (project / subjects / people — whose absence on a
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

    /// The five area WORKSPACES to create. Home is deliberately absent:
    /// the protected builtin Home workspace BECOMES the Home area (it
    /// gains query + emoji below) — never a second "Home" beside it.
    static let areaWorkspaces: [(name: String, emoji: String)] = [
        ("Work", "\u{1F4BC}"),               // 💼
        ("Health", "\u{1F4AA}"),             // 💪
        ("Money", "\u{1F4B0}"),              // 💰
        ("Family & Friends", "\u{2764}\u{FE0F}"),  // ❤️
        ("Learning", "\u{1F4DA}"),           // 📚
    ]

    /// The text fields the capture/camera chips write. `area` is separate:
    /// it is a select, born with its options.
    static let textProperties = ["project", "subjects", "people"]

    /// A workspace query value, quoted where spaced (the DSL's tokenizer:
    /// `area:"Family & Friends"` is one token).
    static func areaQuery(_ name: String) -> String {
        name.contains(" ") ? "area:\"\(name)\"" : "area:\(name)"
    }

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
        furnishWorkspaces(snap)
        launched = true
        finishIfDone()
    }

    // MARK: a+b — properties, and the area options

    private func furnishProperties(_ snap: Snapshot) {
        let properties = snap.properties ?? []
        func existing(_ name: String) -> PropertyRow? {
            properties.first {
                ($0.name ?? "").compare(name, options: .caseInsensitive) == .orderedSame
            }
        }

        for name in Furnish.textProperties where existing(name) == nil {
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

    // MARK: c — the six areas as workspaces

    private func furnishWorkspaces(_ snap: Snapshot) {
        let rows = snap.workspaces ?? []

        // The builtin Home BECOMES the Home area: query + emoji, each only
        // where absent/empty — a re-aimed or re-emojied Home stays the
        // user's. Never create a workspace named Home.
        if let home = rows.first(where: { ($0.builtin ?? "") == "home" }) {
            if (home.query ?? "").isEmpty {
                track()
                box.set(home.id, "query", Furnish.areaQuery("Home")) { [self] _ in landed() }
            }
            if (home.emoji ?? "").isEmpty {
                track()
                box.set(home.id, "emoji", "\u{1F3E0}") { [self] _ in landed() }  // 🏠
            }
        }

        for area in Furnish.areaWorkspaces {
            guard area.name.compare("Home", options: .caseInsensitive) != .orderedSame,
                !rows.contains(where: {
                    ($0.name ?? "").compare(area.name, options: .caseInsensitive)
                        == .orderedSame
                })
            else { continue }
            track()
            box.createWorkspace(name: area.name) { [self] id in
                if id != 0 {
                    track()
                    box.set(id, "query", Furnish.areaQuery(area.name)) { [self] _ in landed() }
                    track()
                    box.set(id, "emoji", area.emoji) { [self] _ in landed() }
                }
                landed()
            }
        }
    }

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
