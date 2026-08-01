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


    /// The text fields the capture/camera chips write. `area` is separate:
    /// it is a select, born with its options.
    static let textProperties = ["project", "subjects", "people"]

    /// The marker that makes a note a template (design/editor-study.md §7).
    /// A text property, so a template is an ordinary note wearing one cell.
    static let templateProperty = Template.property

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
        furnishTemplates(snap)
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

    // MARK: c — the three built-in templates

    /// Presence-guarded by NAME, like everything else here: a box that
    /// already holds a template called "Daily note" gains nothing, and one
    /// the user renamed or trashed is never resurrected under its old
    /// name. Each built-in is an ordinary note carrying the marker cell.
    private func furnishTemplates(_ snap: Snapshot) {
        // The property must exist before any cell can be written to it —
        // `set` refuses an unknown name. If it is missing we mint it and
        // let the NEXT launch seed the notes, which keeps this pass free
        // of ordering games.
        let properties = snap.properties ?? []
        let hasProperty = properties.contains {
            ($0.name ?? "").compare(Furnish.templateProperty, options: .caseInsensitive)
                == .orderedSame
        }
        guard hasProperty else {
            track()
            box.addProperty(Furnish.templateProperty) { [self] _ in landed() }
            return
        }

        let held = Set(
            (snap.entities ?? [])
                .filter { row in
                    (row.cells ?? []).contains {
                        $0.property == Furnish.templateProperty && !($0.value ?? "").isEmpty
                    }
                }
                .compactMap { $0.title })
        for built in BuiltInTemplate.all where !held.contains(built.name) {
            seed(built)
        }
    }

    private func seed(_ built: BuiltInTemplate) {
        track()
        box.createNote { [self] id in
            guard id != 0 else {
                landed()
                return
            }
            box.set(id, "name", built.name)
            box.set(id, Furnish.templateProperty, Template.marker)
            let spans = SpanText.textToSpans(built.body)
            box.setContent(id, spansJson: SpanText.json(spans), base: 0) { [self] _, _ in
                landed()
            }
        }
    }

    // MARK: d — no workspaces

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
