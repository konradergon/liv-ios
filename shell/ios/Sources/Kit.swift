// liv iOS — the shared kit (design/ios.md §6–7). Compact density is law:
// the budgets below are CODE, not convention. Chips render neutral, and
// wear a 6pt dot only when they stand for a KIND. Amber = AI presence — the Inbox
// proposal capsule is the app's ONE in-app badge.

import SwiftUI

// MARK: - SectionLabel

struct SectionLabel: View {
    let text: String
    var trailing: String? = nil
    var trailingAction: (() -> Void)? = nil
    /// A short WARNING about the group, drawn once beside its name — "12
    /// late". It is the only place this app raises its voice in a list,
    /// and it exists so that individual rows do not have to: colouring
    /// every overdue date turned a column of forty-seven dates red and
    /// told you nothing you could act on.
    var note: String? = nil

    init(
        _ text: String, trailing: String? = nil, note: String? = nil,
        trailingAction: (() -> Void)? = nil
    ) {
        self.text = text
        self.trailing = trailing
        self.note = note
        self.trailingAction = trailingAction
    }

    var body: some View {
        HStack(spacing: 7) {
            // NO DOT. A heading that named a kind used to wear that
            // kind's colour as a 7pt circle. Nothing passed one — the
            // parameter had zero callers on 2026-08-30 — and the device
            // itself is the kind the polish pass is removing: a coloured
            // dot beside a word that already says the thing (rule 6).
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
            if let note {
                Text(note)
                    .font(.system(size: LivType.label))
                    .foregroundStyle(LivTheme.red)
            }
            Spacer()
            if let trailing {
                if let trailingAction {
                    // THE SAME SIZE AS THE HEADING IT SITS BESIDE.
                    // It was `body` (17) against the heading's `label`
                    // (15), so the verb outweighed the words it belongs
                    // to on all 28 of these. It keeps the accent — it is
                    // the one live thing in the row — but it no longer
                    // shouts over the heading.
                    Button(action: trailingAction) {
                        Text(trailing)
                            .font(.system(size: LivType.label, weight: .medium))
                            .foregroundStyle(LivTheme.accent)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(trailing)
                        .font(.system(size: LivType.label))
                        .foregroundStyle(LivTheme.text2)
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

/// The one chip recipe: a NEUTRAL capsule — one quiet fill, text2 ink,
/// and nothing else.
///
/// ONE DEVICE, NOT TWO (polish pass, 2026-08-30). It carried a fill AND
/// a hairline border, which is two ways of saying the same edge, and
/// between this and `AddChip` that pair reached forty-odd call sites —
/// the single biggest source of visual noise in the app. A filled shape
/// does not also need to be outlined.
///
/// THE DOT IS GONE with it. A chip standing for a thing wore that
/// thing's kind colour as a 6pt circle; the only remaining caller passed
/// one for a reference chip, where the words already name the thing. A
/// coloured dot next to a word that says the same thing is decoration.
struct ValueChip: View {
    let text: String
    var big: Bool = false
    /// A leading GLYPH. Used by the Fields list, which is this app's
    /// schema view: there a row of forty names needs finding, which is
    /// what an icon is for.
    var glyph: LivGlyph? = nil

    init(_ text: String, big: Bool = false, glyph: LivGlyph? = nil) {
        self.text = text
        self.big = big
        self.glyph = glyph
    }

    var body: some View {
        HStack(spacing: big ? 5 : 4) {
            if let glyph {
                LivIcon(glyph: glyph, color: LivTheme.text3, size: LivChip.glyph)
            }
            // NEVER 11pt. The small chip's text was `micro`, which is the
            // size reserved for a badge — a thing you glance at, not a
            // word you read — and these chips carry area names, project
            // names and dates. Both sizes are `caption` now, and the two
            // variants differ in their padding alone.
            Text(text)
                .font(.system(size: LivType.caption))
                .lineLimit(1)
        }
        .foregroundStyle(LivTheme.text2)
        .padding(.horizontal, big ? 10 : 8)
        .frame(height: big ? LivChip.tall : LivChip.height)
        .background(Capsule().fill(LivTheme.panel2))
    }
}

/// A SEGMENTED CHOICE, in the app's own language.
///
/// It replaces `.pickerStyle(.segmented)`, whose selected thumb measures
/// #6D6D72 — a grey that is not neutral (blue five points over red) and
/// is not in `Palette`, sitting on a #232323 card. It was the single
/// most off-key object in the app, and the only place a control still
/// arrived with a colour nobody here chose.
///
/// The mark is the one this app uses everywhere else for "this is the
/// one you are on": a quiet fill and full ink, no accent, no inversion.
/// 44pt tall, because a control is a touch target before it is a shape.
struct LivSegment<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.value) { option in
                let on = option.value == selection
                Button {
                    withAnimation(LivMotion.pick) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.system(size: LivType.label, weight: on ? .medium : .regular))
                        .foregroundStyle(on ? LivTheme.text : LivTheme.text2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            RoundedRectangle(
                                cornerRadius: LivTheme.radiusSm, style: .continuous
                            )
                            .fill(on ? LivTheme.panel2 : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .frame(height: 44)
    }
}

/// A SWITCH, in the app's own language.
///
/// The two `Toggle(…).tint(accent)` this replaces were the app's LOUDEST
/// stock controls, and a system switch is a saturated slab about 51x31 —
/// on a screen measured at 0.74% saturated pixels against 0.05–0.19%
/// everywhere else, the two of them were most of the difference.
///
/// Not the only ones, which this said until 2026-09-05: two `DatePicker`s
/// remain in `Detail.swift` (a graphical month, a compact clock). They
/// take the app's accent from the subtree's `.tint`, so they are not
/// wearing the system's blue — but the graphical one paints its own
/// selected day and its own red "today", and the app has had its own
/// month grid since the calendar's picker card. Replacing it is real
/// work, not a token change, and it is not done.
///
/// The colour moves into the TRACK at a quarter strength rather than
/// filling it, so "on" is legible without the control being the
/// brightest thing on the screen. The knob is ink.
struct LivSwitch: View {
    @Binding var isOn: Bool
    /// A switch the app has disabled still has to READ disabled — the
    /// platform dims a stock control for free and a hand-built one gets
    /// nothing.
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button {
            withAnimation(LivMotion.pick) { isOn.toggle() }
        } label: {
            Capsule()
                .fill(isOn ? LivTheme.tint(LivTheme.accent, 0.55) : LivTheme.panel2)
                .frame(width: 46, height: 28)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(isOn ? LivTheme.text : LivTheme.text3)
                        .frame(width: 20, height: 20)
                        .padding(4)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// The switch above, as a `ToggleStyle`, so the two call sites keep
/// reading as `Toggle(isOn:) { label }` and only the control changes.
struct LivSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 8)
            LivSwitch(isOn: configuration.$isOn)
        }
    }
}

/// THE FORM CONFIRM: Create, Save — the one filled control on a sheet.
///
/// A primary action earns the accent, and there is exactly one per form,
/// so this is not the kind of colour the polish pass went after. What it
/// went after was the DUPLICATION: `WorkspaceSwitch` carried this shape
/// twice, byte for byte, once for a workspace and once for a filter
/// (standing rule 4 — the same shape drawn from two places is how two
/// shapes start).
struct ConfirmPill: View {
    let label: String
    let action: () -> Void

    init(_ label: String, action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: LivType.label, weight: .semibold))
                .foregroundStyle(LivTheme.onAccent)
                .padding(.horizontal, 16)
                .frame(height: LivChip.tall + 4)
                .background(Capsule().fill(LivTheme.accent))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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
            HStack(spacing: big ? 5 : 4) {
                Image(systemName: "plus")
                    .font(.system(size: LivChip.glyph - 3, weight: .semibold))
                Text(label)
                    .font(.system(size: LivType.caption))
                    .lineLimit(1)
            }
            .foregroundStyle(LivTheme.text3)
            .padding(.horizontal, big ? 10 : 8)
            .frame(height: big ? LivChip.tall : LivChip.height)
            // HOLLOW is this chip's whole meaning — it is the ADD
            // affordance, and standing empty beside filled values is how
            // it says so. So it keeps its outline and takes no fill:
            // still one device, the other one.
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
                    // AN OPEN BOX IS INK, NOT COLOUR.
                    //
                    // The ring wore the status option's own hue whether
                    // it was ticked or not, so a list of forty-seven
                    // open tasks drew forty-seven coloured outlines down
                    // its left edge — every reference draws that column
                    // grey. The hue is what TICKING it means, so it is
                    // kept for the filled state and only there: the
                    // colour then marks the few rows that carry it
                    // rather than the many that do not.
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(LivTheme.text3, lineWidth: 1.5)
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
