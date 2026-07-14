// lotus — the BP-7 V2 chip-forward row kit (P11.5c, design §4). One chip
// recipe, one row budget, one anchor precedence — the density budget is
// CODE, not convention: what a tile may never show is a parameter that does
// not exist. Chips are colorful always-on (hue always means metadata value);
// objects render neutral; type is an icon. Owner-approved mockup.

import AppKit
import SwiftUI

// MARK: - the kind icon (type demoted to an icon, bp7 §16)

func rowKindIcon(_ row: EntityRow) -> String {
    if row.kinds.contains("task") || row.status != nil { return "checkmark.square" }
    if row.kinds.contains("event") { return "calendar" }
    if row.kinds.contains("person") { return "person" }
    if row.kinds.contains("project") { return "folder" }
    if row.kinds.contains("list") { return "list.bullet" }
    if row.cells.contains(where: { $0.kind == "file" }) { return "doc" }
    return "doc.text"
}

// MARK: - ValueChip — THE chip

/// The one chip recipe (bp7:150-160): pill, scheme-aware mixes from
/// Hues.swift's frozen constants. `hue: nil` is the `.neutral` variant —
/// the escape hatch dates/recurrence/tier are REQUIRED to use (the color
/// budget: hue always means metadata value).
struct ValueChip: View {
    let text: String
    var hue: NSColor? = nil
    var icon: String? = nil
    var dot: Color? = nil
    var tap: (() -> Void)? = nil
    var help: String? = nil

    var body: some View {
        let ink: Color = hue.map { Hues.chipInk($0) } ?? Color(nsColor: .secondaryLabelColor)
        let bg: Color = hue.map { Hues.chipBackground($0) } ?? Color.secondary.opacity(0.10)
        let border: Color = hue.map { Hues.chipBorder($0) } ?? Color.secondary.opacity(0.30)
        let label = HStack(spacing: 4) {
            if let dot {
                Circle().fill(dot).frame(width: 7, height: 7)
            }
            if let icon {
                Image(systemName: icon).font(.system(size: 9.5))
            }
            Text(text).font(.system(size: 11)).lineLimit(1)
        }
        .foregroundColor(ink)
        .padding(.horizontal, 7)
        .padding(.vertical, 1.5)
        .background(Capsule().fill(bg))
        .overlay(Capsule().strokeBorder(border, lineWidth: 0.5))
        .contentShape(Capsule())

        if let tap {
            // A chip is its OWN click target — clicking it never selects the
            // row (bp6 a14); the hover hint names the filter it applies.
            Button(action: tap) { label }
                .buttonStyle(.plain)
                .help(help ?? text)
        } else if let help {
            label.help(help)
        } else {
            label
        }
    }
}

// MARK: - StatusDot / StatusChip

/// 8pt: RING while open-ish, FILLED when the option completes (bp7 a20's
/// law). Hue = the option's own `hue` cell (degrees) — never VALUE_HEX.
/// Hover names it; click filters. No status → the caller renders nothing.
struct StatusDot: View {
    let option: OptionRow?
    let statusName: String
    var tap: (() -> Void)? = nil

    private var color: Color {
        option?.hue.map { Hues.degrees($0) } ?? Color(nsColor: .tertiaryLabelColor)
    }

    var body: some View {
        let filled = option?.isTerminal ?? false
        let dot = Circle()
            .strokeBorder(color, lineWidth: filled ? 0 : 1.5)
            .background(Circle().fill(filled ? color : .clear))
            .frame(width: 8, height: 8)
        if let tap {
            Button(action: tap) { dot.contentShape(Circle().scale(2)) }
                .buttonStyle(.plain)
                .help("status: \(statusName)")
        } else {
            dot.help("status: \(statusName)")
        }
    }
}

/// The labeled search variant (bp3:213-214): a neutral-framed chip carrying
/// the dot + the option name.
struct StatusChip: View {
    let option: OptionRow?
    let statusName: String
    var tap: (() -> Void)? = nil

    var body: some View {
        let color = option?.hue.map { Hues.degrees($0) }
            ?? Color(nsColor: .tertiaryLabelColor)
        ValueChip(
            text: statusName, hue: nil, dot: color, tap: tap,
            help: "status: \(statusName)")
    }
}

// MARK: - the anchor

/// The ONE anchor chip a row may carry (bp7 a19): project → first subject →
/// people → role-date. VALUE_HEX-hued for the first three legs; the
/// role-date leg renders NEUTRAL (ruling §9.1 — dates are never hued).
/// The pure shell function the spine deliberately left out.
struct Anchor {
    let text: String
    let hue: NSColor?
    let filter: String?  // "<property>:<value>" — the chip-click search
    /// The role-date leg — the row suppresses its trailing date (the chip
    /// already shows it) and the chip carries no filter (a bare "due:"
    /// qualifier is a junk query, the review's finding).
    var isDate = false
}

func anchorChip(for row: EntityRow) -> Anchor? {
    for name in ["project", "subjects", "people"] {
        if let cell = row.cells.first(where: { $0.property == name && !$0.value.isEmpty }) {
            return Anchor(
                text: cell.value,
                hue: Hues.valueHex(cell.value),
                filter: searchQualifier(name, cell.value))
        }
    }
    if let due = row.due {
        return Anchor(
            text: Civil.text(due, dateOnly: row.dueDateOnly),
            hue: nil, filter: nil, isDate: true)
    }
    // A file entity's anchor is its `format` — text + neutral, never the value
    // rainbow (a format is a fact, not a value; P15/LB7). Chip-click filters.
    // Gated to file entities so a non-file that happens to carry a format cell
    // doesn't sprout one.
    if row.cells.contains(where: { $0.kind == "file" }),
        let cell = row.cells.first(where: { $0.property == "format" && !$0.value.isEmpty })
    {
        return Anchor(text: cell.value, hue: nil, filter: searchQualifier("format", cell.value))
    }
    return nil
}

// MARK: - ObjectRow

/// The V2 row budget as code (bp7 a18): kind icon · title · exactly ONE
/// anchor chip · StatusDot · modified — and NOTHING else at rest; empty
/// fields never render. Hover swaps `modified` for ↗ open · ⋯ handled by
/// the caller's accessory. Selection = the accent inset bar. Single-click
/// selects, double-click opens (manual double-tap — a sibling count:2
/// gesture would stall every selection by the double-click interval).
struct ObjectRow: View {
    let row: EntityRow
    var statusOption: OptionRow? = nil
    var selected = false
    /// A leading interactive toggle (the Tasks checkbox) replaces the kind
    /// icon when present — the Tasks mount's gesture, kept verbatim.
    var toggle: (() -> Void)? = nil
    var trailing: AnyView? = nil
    var chipTap: ((String) -> Void)? = nil
    var select: () -> Void = {}
    var openRow: () -> Void = {}
    /// In-place AI halo (P16f): the count of pending proposals for this row's
    /// entity. 0 renders nothing — the density budget is intact.
    var haloCount: Int = 0
    var onHalo: () -> Void = {}

    @State private var hovering = false
    @State private var lastTap: Date? = nil

    private var anchor: Anchor? { anchorChip(for: row) }
    private var isDone: Bool { statusOption?.isTerminal ?? (row.status == "done") }

    var body: some View {
        HStack(spacing: 9) {
            if let toggle {
                Button(action: toggle) {
                    Group {
                        if isDone {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Theme.accent)
                                .overlay(
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white))
                        } else {
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1.5)
                        }
                    }
                    .frame(width: 15, height: 15)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: rowKindIcon(row))
                    .font(.system(size: 13))
                    .foregroundColor(Theme.mutedFg)
                    .frame(width: 15)
            }
            Text(row.title.isEmpty ? "Untitled" : row.title)
                .font(.system(size: 13))
                .lineLimit(1)
                .foregroundColor(isDone && toggle != nil ? .secondary : .primary)
                .strikethrough(isDone && toggle != nil, color: .secondary)
            Spacer(minLength: 8)
            if haloCount > 0 {
                Button(action: onHalo) {
                    HStack(spacing: 2) {
                        Image(systemName: "sparkle").font(.system(size: 8.5))
                        Text("\(haloCount)").font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(Theme.warning)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Theme.warning.opacity(0.13)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("\(haloCount) suggestion\(haloCount == 1 ? "" : "s") — review in Inbox › Tidy")
            }
            if let trailing { trailing }
            if let anchor {
                ValueChip(
                    text: anchor.text, hue: anchor.hue,
                    tap: anchor.filter.flatMap { f in chipTap.map { tap in { tap(f) } } },
                    help: anchor.filter.map { "filter: \($0)" })
            }
            if row.status != nil {
                StatusDot(option: statusOption, statusName: row.status ?? "")
            }
            if hovering {
                HStack(spacing: 7) {
                    Button(action: openRow) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11.5))
                            .foregroundColor(Theme.mutedFg)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open")
                }
            } else if let stamp = (anchor?.isDate == true ? nil : row.due) ?? row.created {
                // The date-leg anchor already shows the due date; the
                // trailing slot then falls back to created/modified.
                let showsDue = anchor?.isDate != true && row.due != nil
                Text(Civil.text(stamp, dateOnly: !showsDue || row.dueDateOnly))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(Color.secondary.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .background(selected ? Theme.accentTint : Color.clear)
        .overlay(
            Rectangle().fill(Theme.accent).frame(width: 2.5)
                .opacity(selected ? 1 : 0),
            alignment: .leading
        )
        .onTapGesture {
            // Select immediately; open on the second tap inside the system
            // interval — the row never stalls (the tab-strip lesson).
            select()
            let now = Date()
            if let last = lastTap, now.timeIntervalSince(last) < NSEvent.doubleClickInterval {
                lastTap = nil
                openRow()
            } else {
                lastTap = now
            }
        }
        .contextMenu {
            // The timer's row door (P18h): start writes NOTHING — the pref
            // flips; the widget's strip picks it up on its next tick.
            Button("Start timer") {
                NotificationCenter.default.post(name: .lotusStartTimer, object: row.id)
            }
            Button("Open") { openRow() }
        }
        .onHover { hovering = $0 }
        .overlay(Divider(), alignment: .bottom)
    }
}

// MARK: - ObjectCard / ObjectTile (components ship; mounts arrive with
// their surfaces — the board/gallery passes)

/// Card budget (bp6 a15): type + title + a 2-line description clamp +
/// ≤3 chips + overflow. NO status dot — cards are for galleries, where the
/// grouping carries state.
struct ObjectCard: View {
    let row: EntityRow
    var descriptionText: String = ""
    var chips: [Anchor] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: rowKindIcon(row))
                    .font(.system(size: 12))
                    .foregroundColor(Theme.mutedFg)
                Text(row.title.isEmpty ? "Untitled" : row.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
            }
            if !descriptionText.isEmpty {
                Text(descriptionText)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 4) {
                ForEach(Array(chips.prefix(3).enumerated()), id: \.offset) { _, a in
                    ValueChip(text: a.text, hue: a.hue)
                }
                if chips.count > 3 {
                    Text("+\(chips.count - 3)")
                        .font(.system(size: 10.5))
                        .foregroundColor(Theme.mutedFg)
                }
            }
        }
        .padding(10)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border, lineWidth: 0.5))
    }
}

/// The tightest budget — and the prohibition IS the initializer: no status
/// parameter exists (bp7 a25; bp1:706 "NEVER status — the column carries
/// it"). Date renders neutral, tier as the accent flag, people as VALUE_HEX.
struct ObjectTile: View {
    let title: String
    var person: String? = nil
    var dateText: String? = nil
    var tier: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.isEmpty ? "Untitled" : title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
            HStack(spacing: 4) {
                if let person {
                    ValueChip(text: person, hue: Hues.valueHex(person))
                }
                if let dateText {
                    ValueChip(text: dateText, hue: nil)
                }
                if let tier {
                    ValueChip(text: tier, hue: nil, icon: "flag")
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.border, lineWidth: 0.5))
    }
}

// MARK: - the vocabulary sections helper (the Tasks mount)

/// A kind's status vocabulary in board order, derived CLIENT-SIDE from the
/// snapshot's catalog (no async hop): the one `status` definition's options,
/// kept when for_types names the kind or is empty (offered everywhere).
func statusVocabulary(_ model: BoxModel, kind: String) -> [OptionRow] {
    guard let status = model.property(named: "status") else { return [] }
    return status.options
        .filter { option in
            let scoped = option.forTypes ?? []
            return scoped.isEmpty || scoped.contains(kind)
        }
        .sorted {
            ($0.boardOrder, $0.id) < ($1.boardOrder, $1.id)
        }
}
