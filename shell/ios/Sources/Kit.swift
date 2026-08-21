// liv iOS — the shared kit (design/ios.md §6–7). Compact density is law:
// the budgets below are CODE, not convention. Chips render neutral; the
// value's color is only the 6pt Hue dot. Amber = AI presence — the Inbox
// proposal capsule is the app's ONE in-app badge.

import SwiftUI

// MARK: - SectionLabel

struct SectionLabel: View {
    let text: String
    var trailing: String? = nil
    var trailingAction: (() -> Void)? = nil
    /// A heading that names a KIND wears that kind's color as a small
    /// dot. Nothing else does — a dot on every heading would say nothing.
    var dot: Color? = nil

    init(
        _ text: String, trailing: String? = nil, dot: Color? = nil,
        trailingAction: (() -> Void)? = nil
    ) {
        self.text = text
        self.trailing = trailing
        self.dot = dot
        self.trailingAction = trailingAction
    }

    var body: some View {
        HStack(spacing: 7) {
            if let dot {
                Circle().fill(dot).frame(width: 7, height: 7)
            }
            // 13pt semibold text2, not 11pt bold text3 (owner,
            // 2026-08-06: "headings and UI text are too subtle"). One
            // recipe, 28 call sites — the whole app's section hierarchy
            // moves together, and the old grey was 6.5:1 against the
            // canvas where this is 11:1.
            // Sentence case, secondary ink, ordinary weight (surface
            // pass, owner 2026-08-18: "eliminate unnecessary small text
            // and labels"). UPPERCASE + semibold + kerning made every
            // heading shout; a heading's whole job is to be findable
            // when you look for it and invisible when you do not.
            Text(text)
                .font(.system(size: LivType.label, weight: .medium))
                .foregroundStyle(LivTheme.text2)
            Spacer()
            if let trailing {
                if let trailingAction {
                    Button(action: trailingAction) {
                        Text(trailing)
                            .font(.system(size: LivType.body, weight: .medium))
                            .foregroundStyle(LivTheme.accent)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(trailing)
                        .font(.system(size: LivType.body))
                        .foregroundStyle(LivTheme.muted)
                }
            }
        }
        // THE HEADING OWNS ITS OWN ROOM (2026-08-21). Leaving it to the
        // caller is exactly the drift standing rule 3 predicts: colours
        // are tokenised and have never moved; this was prose and moved
        // five ways across sixteen sites. A caller may still add
        // HORIZONTAL inset — that belongs to the surface, not the
        // heading.
        .padding(.top, LivRow.sectionTop)
        .padding(.bottom, LivRow.sectionBottom)
    }
}

// MARK: - ValueChip / AddChip

/// The one chip recipe (O2): NEUTRAL body — panel2 fill, text2 ink,
/// hairline capsule — with the value's color only as the 6pt leading Hue
/// dot. `dotted: false` is the variant dates/recurrence/tier REQUIRE.
struct ValueChip: View {
    let text: String
    var dotted: Bool = true
    var big: Bool = false
    /// Overrides the dot's color. A chip standing for a THING (a kind, a
    /// reference to another entity) wears that thing's kind color; every
    /// other chip keeps the Hue hash, which is stable per word and means
    /// nothing beyond "these two say the same thing".
    var hue: Color? = nil

    init(_ text: String, dotted: Bool = true, big: Bool = false, hue: Color? = nil) {
        self.text = text
        self.dotted = dotted
        self.big = big
        self.hue = hue
    }

    var body: some View {
        HStack(spacing: big ? 5 : 4) {
            if dotted {
                Circle().fill(hue ?? Hue.dot(text)).frame(width: 6, height: 6)
            }
            Text(text)
                .font(.system(size: big ? 13 : 11))
                .lineLimit(1)
        }
        .foregroundStyle(LivTheme.text2)
        .padding(.horizontal, big ? 10 : 7)
        .frame(height: big ? 24 : 17)
        .background(Capsule().fill(LivTheme.panel2))
        .overlay(Capsule().strokeBorder(LivTheme.border, lineWidth: 0.5))
    }
}

/// The chip-shaped add affordance (capture sheet's +Tag +Project row):
/// hollow, muted — never competes with real values.
struct AddChip: View {
    let label: String
    var big: Bool = false
    let action: () -> Void

    init(_ label: String, big: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.big = big
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: big ? 4 : 3) {
                Image(systemName: "plus")
                    .font(.system(size: big ? 9.5 : 8, weight: .semibold))
                Text(label)
                    .font(.system(size: big ? 13 : 11))
                    .lineLimit(1)
            }
            .foregroundStyle(LivTheme.text3)
            .padding(.horizontal, big ? 10 : 7)
            .frame(height: big ? 24 : 17)
            .overlay(Capsule().strokeBorder(LivTheme.border2, lineWidth: 0.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - StatusRing

/// The task toggle: 15pt rounded-square RING while open, FILLED + check
/// when the status completes. Hue = the option's own color; nil = neutral
/// open / accent done. Visual stays 15pt; the hit target is padded.
struct StatusRing: View {
    let done: Bool
    var hue: Color? = nil
    /// Tight variant for inline places that carry their own padding (a
    /// calendar block, an all-day pill): the glyph and its target shrink
    /// together, so the ring never dwarfs the pill it sits in.
    var compact: Bool = false
    let action: () -> Void

    init(
        done: Bool, hue: Color? = nil, compact: Bool = false,
        action: @escaping () -> Void
    ) {
        self.done = done
        self.hue = hue
        self.compact = compact
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if done {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(hue ?? LivTheme.accent)
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.system(size: LivType.micro, weight: .bold))
                                .foregroundStyle(LivTheme.onAccent)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(hue ?? LivTheme.muted, lineWidth: 1.5)
                }
            }
            .frame(width: compact ? 13 : 15, height: compact ? 13 : 15)
            .padding(compact ? 2 : 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - CountTile

/// The dashboard count tile (Today's 2×2, Tasks header): count over an
/// uppercase label. Danger = the Overdue red.
struct CountTile: View {
    let count: Int
    let label: String
    var danger: Bool = false
    let action: () -> Void

    init(
        count: Int, label: String, danger: Bool = false,
        action: @escaping () -> Void
    ) {
        self.count = count
        self.label = label
        self.danger = danger
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count)")
                    .font(.system(size: LivType.title, weight: .bold).monospacedDigit())
                    .foregroundStyle(danger ? LivTheme.red : LivTheme.text)
                Text(label.uppercased())
                    .font(.system(size: LivType.micro, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(LivTheme.text3)
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 12).fill(LivTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(LivTheme.border, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - EmptyHint

/// AN EMPTY SURFACE STILL SAYS SOMETHING (owner's clips, 2026-08-20).
///
/// The reference set answers a nothing-here the same way every time: a
/// glyph, a line in full-strength ink saying what is missing, and a
/// quieter line saying what the thing is for. ChatGPT's empty Projects
/// panel is the clearest example of the shape.
///
/// NO BUTTON, though the references have one: Liv's floating bar already
/// carries a `+` on every surface, and a second creation door here would
/// be the same rule written twice (standing rule 4).
///
/// The bare sentence stays the default, because most of the eighteen
/// call sites are a passing state ("This was deleted") rather than a
/// place you have landed and must now start from. Only a surface a user
/// can sit and look at earns the glyph and the button.
struct EmptyHint: View {
    let text: String
    /// The quieter second line. Says what the surface is FOR.
    var detail: String? = nil
    var glyph: LivGlyph? = nil

    init(_ text: String) { self.text = text }

    init(_ text: String, detail: String? = nil, glyph: LivGlyph? = nil) {
        self.text = text
        self.detail = detail
        self.glyph = glyph
    }

    private var furnished: Bool { detail != nil || glyph != nil }

    var body: some View {
        VStack(spacing: 10) {
            if let glyph {
                LivIcon(glyph: glyph, color: LivTheme.text3, size: 30)
                    .padding(.bottom, 2)
            }
            Text(text)
                .font(.system(size: LivType.strong, weight: furnished ? .semibold : .regular))
                .foregroundStyle(furnished ? LivTheme.text : LivTheme.muted)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.system(size: LivType.body))
                    .foregroundStyle(LivTheme.text2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - when something is due, if you did not say

/// The hour a due lands on when nobody picked one: 09:00, the start of
/// the day rather than the minute you happened to be holding the phone
/// (owner, 2026-08-07 — the current time meant a task typed at 23:47 was
/// due at 23:47). One constant, so the date sheet, the capture card and
/// every quick-add row agree.
enum LivDue {
    /// Packed HHMM.
    static let defaultHHMM: Int64 = 900

    /// Does this thing carry a clock time after you edit its date?
    ///
    /// All-day belongs to EVENTS. A holiday is not due at 09:00, so an
    /// all-day event keeps its all-day-ness until you actually touch the
    /// clock. A TASK always has a moment — that is what a task is — so a
    /// task stored without one gets `defaultHHMM` on its next change
    /// (owner, 2026-08-07).
    static func carriesTime(dateOnly: Bool, isEvent: Bool) -> Bool {
        !dateOnly || !isEvent
    }

    /// The default moment on a given day, as a Date, for seeding a
    /// time picker.
    static func defaultTime(on day: Int64) -> Date {
        Civil.date(day: day, hhmm: defaultHHMM) ?? Date()
    }
}

// MARK: - what to call a row

/// The one answer to "what is this called".
///
/// The core answers it now: since 2026-08-07 the snapshot's `title` is
/// the display name — the name cell, else the first line of the content
/// with ALL syntax off (block and inline markers both, services/src/
/// content.rs strip_marker), else "#id". Eight files used to re-derive
/// that, each with its own fallback and its own word for nothing.
/// This is the only one, and it cleans NOTHING — cleaning a title twice
/// was two code bits solving the same problem (owner, 2026-08-07).
///
/// The "#id" the core sends for an entity with no words at all is a
/// placeholder, not a name — no list shows it.
func livRowTitle(_ row: EntityRow) -> String {
    livRowIsUntitled(row) ? "Untitled" : (row.title ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Whether that name is a placeholder, asked directly. A list that greys
/// the nameless rows used to compare the RESULT against "untitled" in
/// lower case, which never matched — so nameless rows drew at full
/// strength, on the one screen built to show them quietly.
func livRowIsUntitled(_ row: EntityRow) -> Bool {
    let raw = (row.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return raw.isEmpty || raw == "#\(row.id)"
}

// The icon language — what a row looks like, and the carved chip it
// wears — lives in Glyph.swift.

/// Whether a row has something to TICK: the task kind, or any status at
/// all. Today and the calendar each had their own private copy of this.
///
/// This is deliberately NOT `LivKind.of(row) == .task`. They answer
/// different questions: the kind says what a thing IS, and gives event
/// and file precedence, while this asks only whether there is a status
/// to close. An event with a status is still an event — teal, with
/// a ring on it.
func livCanTick(_ row: EntityRow) -> Bool {
    row.kinds?.contains("task") == true || row.status != nil
}

/// The face every create-menu verb wears: 46pt tall, full width, rounded,
/// a hairline border, primary filled with the accent.
///
/// ONE recipe, because two of them already drifted: "Add a file" was
/// hand-dressed to match and copied the fill but not the BORDER. In dark
/// mode that passed, since surface (#1E1E20) reads against canvas
/// (#161618). In light mode both are #FFFFFF — the border IS the shape —
/// so the button had no shape at all (owner, 2026-08-10).
struct LivVerbFace: ViewModifier {
    var primary = false

    func body(content: Content) -> some View {
        content
            .font(.system(size: LivType.strong, weight: primary ? .semibold : .regular))
            .foregroundStyle(primary ? LivTheme.onAccent : LivTheme.text)
            .frame(maxWidth: .infinity)
            .frame(height: LivRow.height)
            .background(
                RoundedRectangle(cornerRadius: LivTheme.radius)
                    .fill(primary ? LivTheme.accent : LivTheme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LivTheme.radius)
                    .strokeBorder(
                        primary ? Color.clear : LivTheme.border, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: LivTheme.radius))
    }
}

extension View {
    func livVerbFace(primary: Bool = false) -> some View {
        modifier(LivVerbFace(primary: primary))
    }
}
