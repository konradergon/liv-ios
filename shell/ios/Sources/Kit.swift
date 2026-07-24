// liv iOS — the shared kit (design/ios.md §6–7). Compact density is law:
// the budgets below are CODE, not convention. Chips render neutral; the
// value's color is only the 6pt Hue dot. Amber = AI presence — the Inbox
// proposal capsule is the app's ONE in-app badge.

import SwiftUI

/// Ink for solid amber fills — one value in every scheme (the desktop's
/// onYellowInk).
private let onAmberInk = Color(red: 0x3A / 255, green: 0x2A / 255, blue: 0)

// MARK: - Tab / PillBar

enum Tab: String, CaseIterable { case today, inbox, tasks, search }

/// The floating pill bottom bar — persistent everywhere, even on pushes
/// (ClickUp hides it on detail screens; users hate it). Center + is its own
/// proud circle: tap = Capture sheet, long-press = straight to camera.
struct PillBar: View {
    @Binding var selected: Tab
    let inboxBadge: Int
    let onPlus: () -> Void
    let onCamera: () -> Void

    init(
        selected: Binding<Tab>, inboxBadge: Int,
        onPlus: @escaping () -> Void, onCamera: @escaping () -> Void
    ) {
        self._selected = selected
        self.inboxBadge = inboxBadge
        self.onPlus = onPlus
        self.onCamera = onCamera
    }

    private func icon(_ tab: Tab) -> String {
        switch tab {
        case .today: return selected == tab ? "sun.max.fill" : "sun.max"
        case .inbox: return selected == tab ? "tray.fill" : "tray"
        case .tasks:
            return selected == tab ? "checkmark.circle.fill" : "checkmark.circle"
        case .search: return "magnifyingglass"
        }
    }

    private func label(_ tab: Tab) -> String {
        switch tab {
        case .today: return "Today"
        case .inbox: return "Inbox"
        case .tasks: return "Tasks"
        case .search: return "Search"
        }
    }

    private func tabButton(_ tab: Tab) -> some View {
        Button {
            selected = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon(tab))
                    .font(.system(size: 17))
                    .frame(height: 20)
                    .overlay(alignment: .topTrailing) {
                        if tab == .inbox, inboxBadge > 0 {
                            Text(inboxBadge > 99 ? "99+" : "\(inboxBadge)")
                                .font(
                                    .system(size: 9, weight: .bold)
                                        .monospacedDigit()
                                )
                                .foregroundStyle(onAmberInk)
                                .padding(.horizontal, 3.5)
                                .frame(minWidth: 13, minHeight: 13)
                                .background(Capsule().fill(LivTheme.amber))
                                .offset(x: 9, y: -5)
                        }
                    }
                Text(label(tab)).font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(selected == tab ? LivTheme.accent : LivTheme.text3)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.today)
            tabButton(.inbox)
            Circle()
                .fill(LivTheme.accent)
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(LivTheme.onAccent)
                )
                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
                .offset(y: -10)  // proud of the bar
                .onTapGesture { onPlus() }
                .onLongPressGesture(minimumDuration: 0.35) { onCamera() }
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Capture")
                .accessibilityHint("Long press for camera")
            tabButton(.tasks)
            tabButton(.search)
        }
        .frame(height: 52)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(LivTheme.border, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)  // floater
        .padding(.horizontal, 16)
    }
}

// MARK: - SectionLabel

struct SectionLabel: View {
    let text: String
    var trailing: String? = nil
    var trailingAction: (() -> Void)? = nil

    init(
        _ text: String, trailing: String? = nil,
        trailingAction: (() -> Void)? = nil
    ) {
        self.text = text
        self.trailing = trailing
        self.trailingAction = trailingAction
    }

    var body: some View {
        HStack {
            Text(text.uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .kerning(0.6)
                .foregroundStyle(LivTheme.text3)
            Spacer()
            if let trailing {
                if let trailingAction {
                    Button(action: trailingAction) {
                        Text(trailing)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(LivTheme.accent)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(trailing)
                        .font(.system(size: 10.5))
                        .foregroundStyle(LivTheme.muted)
                }
            }
        }
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

    init(_ text: String, dotted: Bool = true, big: Bool = false) {
        self.text = text
        self.dotted = dotted
        self.big = big
    }

    var body: some View {
        HStack(spacing: big ? 5 : 4) {
            if dotted {
                Circle().fill(Hue.dot(text)).frame(width: 6, height: 6)
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
    let action: () -> Void

    init(done: Bool, hue: Color? = nil, action: @escaping () -> Void) {
        self.done = done
        self.hue = hue
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
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(LivTheme.onAccent)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(hue ?? LivTheme.muted, lineWidth: 1.5)
                }
            }
            .frame(width: 15, height: 15)
            .padding(8)
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
                    .font(.system(size: 16, weight: .bold).monospacedDigit())
                    .foregroundStyle(danger ? LivTheme.red : LivTheme.text)
                Text(label.uppercased())
                    .font(.system(size: 9.5, weight: .semibold))
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

struct EmptyHint: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(LivTheme.muted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }
}
