// liv iOS — templates (design/editor-study.md §7, phase 4). The whole
// design in one sentence: a template IS a note carrying a `template`
// cell, so there is no folder to configure, no setting to find, no
// plugin to install, and no second kind of object to learn.
//
// Two verbs: start a new note from one (offered where things are
// created), or drop one in at the caret. Both are copies — the template
// itself is never moved or consumed (owner ruling 6).
//
// Variables are plain text tokens, resolved ONLY when a template is
// copied. That is the deviation from the study, and it is deliberate: the
// span model has three shapes (Text, Break, Ref) and a fourth would be a
// core change, which is not ours to make. Text tokens cost nothing, and
// they survive a round trip through the desktop, which structured spans
// the desktop does not know would not.
//
// The law they must not break — "typed text is never parsed into
// meaning" — is intact: NOTHING scans an ordinary note. A `{{date}}` in a
// normal note is literal forever. It resolves only in the copy path, only
// out of a note the user explicitly marked as a template, which is the
// one place the syntax means something.

import Foundation

// MARK: - the marker

enum Template {
    /// The presence of this property makes a note a template. The value
    /// is a marker, never a name — the template's name is its own name
    /// cell, so renaming it in the editor renames it in the picker.
    static let property = "template"
    static let marker = "1"

    /// Where the caret should land. Removed from the copy.
    static let cursor = "{{cursor}}"

    /// The variables, and what each resolves to at copy time. Deliberately
    /// three, not the study's four: `{{title}}` is dropped because nothing
    /// on this phone asks for a name when it creates a note — the title is
    /// DERIVED from the body — so there is no title to interpolate at the
    /// moment of instantiation.
    static func resolve(_ body: String, now: Int64) -> (text: String, caret: Int?) {
        let day = Civil.day(of: now)
        var out = body
            .replacingOccurrences(of: "{{date}}", with: Civil.dayLabel(day))
            .replacingOccurrences(of: "{{time}}", with: Civil.timeString(now))
        // The caret marker goes last so the offsets above are already
        // settled, and it is measured in UTF-16 to match the text view.
        var caret: Int?
        let n = out as NSString
        let found = n.range(of: cursor)
        if found.location != NSNotFound {
            caret = found.location
            out = n.replacingCharacters(in: found, with: "")
        }
        return (out, caret)
    }

    /// The cells a copy inherits. Never the marker itself (a note made
    /// from a template is a note, not another template), never identity
    /// or content, never the derived stamps.
    static let notInherited: Set<String> = [
        Template.property, "name", "content", "created", "type",
    ]
}

// MARK: - the built-ins

/// Three templates a fresh box ships with, so the feature is usable the
/// day it appears rather than after you build your own. Each is an
/// ordinary note — open one and edit it like any other.
struct BuiltInTemplate {
    let name: String
    let body: String

    static let all: [BuiltInTemplate] = [
        BuiltInTemplate(
            name: "Daily note",
            body: """
                # {{date}}

                ## Today
                - [ ] {{cursor}}

                ## Notes
                """),
        BuiltInTemplate(
            name: "Meeting",
            body: """
                # Meeting — {{date}} {{time}}

                **Who:** {{cursor}}

                ## Agenda

                ## Next steps
                - [ ]
                """),
        BuiltInTemplate(
            name: "Person",
            body: """
                # {{cursor}}

                ## How we met

                ## Notes
                """),
    ]
}

// MARK: - the self-check (no test target; rides -template.selfcheck 1)

func livTemplateSelfCheck() -> [String] {
    var failures: [String] = []
    func check(_ label: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        if !ok { failures.append("FAIL \(label) \(detail())") }
    }

    // A civil stamp: 2026-08-01 09:30.
    let now: Int64 = 202_608_010_930

    let plain = Template.resolve("nothing to see", now: now)
    check("plain body is untouched", plain.text == "nothing to see")
    check("no marker means no caret", plain.caret == nil)

    let dated = Template.resolve("on {{date}} at {{time}}", now: now)
    check(
        "date and time resolve",
        dated.text == "on \(Civil.dayLabel(Civil.day(of: now))) at \(Civil.timeString(now))",
        dated.text)

    let caret = Template.resolve("a{{cursor}}b", now: now)
    check("cursor marker is removed", caret.text == "ab", caret.text)
    check("caret lands where it was", caret.caret == 1, "\(caret.caret ?? -1)")

    let both = Template.resolve("{{date}}\n{{cursor}}tail", now: now)
    let head = Civil.dayLabel(Civil.day(of: now))
    check("caret offset counts resolved text", both.caret == (head as NSString).length + 1,
        "\(both.caret ?? -1) vs \((head as NSString).length + 1)")

    // Emoji before the marker: the offset must be UTF-16, or the caret
    // lands mid-character in the text view.
    let emoji = Template.resolve("🌧{{cursor}}x", now: now)
    check("caret offset is utf-16", emoji.caret == 2, "\(emoji.caret ?? -1)")

    check(
        "the marker itself is never inherited",
        Template.notInherited.contains(Template.property))
    check("built-ins are named and non-empty", BuiltInTemplate.all.allSatisfy {
        !$0.name.isEmpty && !$0.body.isEmpty
    })

    return failures
}
