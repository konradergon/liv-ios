// lotus — onboarding (P19i, bp2): first-run, the tour, replay. The tour is
// three coach-bubble moments over the AS-BUILT surfaces — never a slideshow,
// never a fake screenshot. Input passes through: every bubble leaves the
// surface beneath it fully live. Fresh box + fresh prefs → the tour; a
// non-empty box never tours regardless of prefs; skip anywhere lands in the
// after-state (seeds intact) and it never auto-shows again. State survives
// kill/relaunch at every dot (resume with surface validation). Rehearse it:
//   LOTUS_BOX_PATH=$(mktemp -d)/tour.log ./shell/macos/build/lotus

import AppKit
import SwiftUI

// MARK: - the state (an app pref, never the box)

enum TourState {
    private static let key = "app.onboarding.v1"

    static var done: Bool {
        (UserDefaults.standard.dictionary(forKey: key)?["done"] as? Bool) ?? false
    }
    static var dot: Int {
        (UserDefaults.standard.dictionary(forKey: key)?["dot"] as? Int) ?? 0
    }
    /// Which box the dot belongs to — a mid-tour pref from ANOTHER box
    /// must not resume over this one (P19 review).
    static var box: String? {
        UserDefaults.standard.dictionary(forKey: key)?["box"] as? String
    }
    static func save(done: Bool, dot: Int, box: String) {
        UserDefaults.standard.set(["done": done, "dot": dot, "box": box], forKey: key)
    }
    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// The scripted captures — MUST mirror services/src/lib.rs TOUR_CAPTURES
/// (the frozen strings; a services test asserts each fires a proposer, so
/// the assist moment can never demo a dead wand).
let tourCaptures = [
    "Call the dentist tomorrow 10:00",
    "Renew the passport asap",
    "Team retro friday 14:00",
]

// MARK: - the coach bubble (lake-green, anchored, pass-through)

struct CoachBubble: View {
    let dot: Int
    let total: Int
    let title: String
    let text: String
    var continueLabel = "Continue"
    var canContinue = true
    let onContinue: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(1...total, id: \.self) { index in
                    Circle()
                        .fill(index <= dot ? Theme.accent : Theme.accent.opacity(0.25))
                        .frame(width: 6, height: 6)
                }
                Text("TOUR · \(dot) of \(total)")
                    .font(.system(size: 9, weight: .bold)).kerning(0.5)
                    .foregroundColor(Theme.accent)
                Spacer()
                Button("Skip tour") { onSkip() }
                    .buttonStyle(.plain).font(.system(size: 10))
                    .foregroundColor(Theme.mutedFg)
            }
            Text(title).font(.system(size: 13, weight: .bold))
            Text(text).font(.system(size: 11.5)).foregroundColor(Theme.foreground.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button {
                    onContinue()
                } label: {
                    Text(continueLabel)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.accent))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canContinue)
                .opacity(canContinue ? 1 : 0.5)
            }
        }
        .padding(13)
        .frame(width: 360)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
    }
}

// MARK: - the tour overlay

struct TourOverlay: View {
    @ObservedObject var model: BoxModel
    /// 0 = welcome · 1 capture · 2 assist · 3 the vault · 4 finish strip.
    @Binding var dot: Int
    let boxPath: String
    /// Replay shows an existing vault, not a promise to create one.
    let fresh: Bool
    /// The window's seams the tour drives. goTidy reports back: navigation
    /// can be REFUSED (an editor flush declined) and the dot must not
    /// advance over a surface that never changed (P19 review).
    let goTidy: (@escaping () -> Void) -> Void
    let goHome: () -> Void
    let finish: () -> Void

    @State private var picks: Set<String> = []
    @FocusState private var welcomeFocused: Bool

    private let topics = ["Studies", "Work", "Climbing", "Home & money"]

    var body: some View {
        if dot == 0 {
            welcome
        } else {
            // Moments 1–3 + the finish strip: a bottom-center bubble, NO
            // scrim — the surface beneath stays fully live (pass-through).
            VStack {
                Spacer()
                bubble
                    .padding(.bottom, 46)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(true)
        }
    }

    // MARK: welcome (the one scrimmed step)

    private var welcome: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 10) {
                Text("Liv").font(.system(size: 22, weight: .bold))
                Text("Notes, tasks, and everything between — on a core that never forgets and never acts without you.")
                    .font(.system(size: 12.5))
                // The trust beat: the one-file truth, before anything exists.
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(fresh ? "will create" : "your vault") → \(boxPath)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(Theme.mutedFg)
                        .lineLimit(1).truncationMode(.middle)
                    Text("One file, on your Mac. Sync it with anything that syncs files — nothing phones home.")
                        .font(.system(size: 10.5)).foregroundColor(Theme.mutedFg)
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
                // The optional topic picks — each becomes a real workspace.
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rooms to start with — optional:")
                        .font(.system(size: 10.5)).foregroundColor(Theme.mutedFg)
                    HStack(spacing: 6) {
                        ForEach(topics, id: \.self) { topic in
                            Button {
                                if picks.contains(topic) {
                                    picks.remove(topic)
                                } else {
                                    picks.insert(topic)
                                }
                            } label: {
                                Text(topic)
                                    .font(.system(size: 11))
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(picks.contains(topic)
                                                ? Theme.accent.opacity(0.18) : .clear))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(
                                                picks.contains(topic)
                                                    ? Theme.accent.opacity(0.6) : Theme.border))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    Button("Skip — just open") { finish() }
                        .buttonStyle(.plain).font(.system(size: 11))
                        .foregroundColor(Theme.mutedFg)
                    Spacer()
                    Button {
                        start()
                    } label: {
                        Text("Start the tour · ⌘⏎")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accent))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: .command)
                }
            }
            .padding(20)
            .frame(width: 470)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
            .focusable()
            .focused($welcomeFocused)
            .onAppear { welcomeFocused = true }
            .onExitCommand { finish() }  // Esc = skip, seeds intact
        }
    }

    private func start() {
        // Real writes, ordinary doors: picked rooms become workspaces; the
        // frozen strings become scraps the assist moment derives from.
        for topic in picks {
            model.createWorkspace(name: topic, parent: 0) { _ in }
        }
        for text in tourCaptures {
            model.capture(text)
        }
        advance(to: 1)
    }

    private func advance(to next: Int) {
        dot = next
        TourState.save(done: false, dot: next, box: boxPath)
    }

    // MARK: the moments

    @ViewBuilder
    private var bubble: some View {
        switch dot {
        case 1:
            CoachBubble(
                dot: 1, total: 3, title: "Words in, nothing lost",
                text: "⌃⌥Space captures from anywhere — one field, Esc closes, it asks nothing. Three scraps just landed for you. Everything is appended to the one file; ⌘⌥Z never expires.",
                onContinue: {
                    // The switch may be OFF (a replay after opting out):
                    // never demo a dead wand — the vocabulary moment is next
                    // (P19 review). Consent is never flipped for a demo.
                    if model.snap?.assist?.on == false {
                        goHome()
                        advance(to: 3)
                    } else {
                        goTidy { advance(to: 2) }
                    }
                },
                onSkip: finish)
        case 2:
            CoachBubble(
                dot: 2, total: 3, title: "The clerk proposes — you decide",
                // No gate needed: the frozen-strings test guarantees the wand
                // is never dead here, and triaging the queue empty IS the
                // moment working (the surface is fully live).
                text: "It read your scraps and proposed dates and priorities — amber, in one queue, applied never. a accepts · r declines; a dismissal is remembered and never re-asked.",
                onContinue: {
                    goHome()
                    advance(to: 3)
                },
                onSkip: finish)
        case 3:
            CoachBubble(
                dot: 3, total: 3, title: "A vocabulary that is yours",
                text: "The seeded words render dashed until you use them — keep or hide them in ⌘, → Vocabulary. ⌘F finds anything. Values wear one color everywhere, by law.",
                continueLabel: "Finish",
                onContinue: { advance(to: 4) },
                onSkip: finish)
        default:
            // The finish strip.
            VStack(alignment: .leading, spacing: 5) {
                Text("You're in.").font(.system(size: 13, weight: .bold))
                Text("⌃⌥Space capture · ⌘F find · ⌘, settings · ⌃⇧G the map · replay from Help → Tour")
                    .font(.system(size: 11)).foregroundColor(Theme.mutedFg)
                HStack {
                    Spacer()
                    Button {
                        finish()
                    } label: {
                        Text("Done")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.accent))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(13)
            .frame(width: 360)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.6), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
        }
    }
}

// MARK: - the seeded banner (the after-state's one pointer)

struct SeededBanner: View {
    @AppStorage("app.seedbanner.v1") private var dismissed = false
    let openVocabulary: () -> Void

    var body: some View {
        if !dismissed {
            HStack(spacing: 7) {
                Text("Seeded vocabulary — yours to keep or hide.")
                    .font(.system(size: 10.5)).foregroundColor(Theme.mutedFg)
                Button("Settings → Vocabulary") { openVocabulary() }
                    .buttonStyle(.plain).font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(Theme.accent)
                Spacer(minLength: 0)
                Button {
                    dismissed = true
                } label: {
                    Image(systemName: "xmark").font(.system(size: 8))
                        .foregroundColor(Theme.mutedFg).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .overlay(Divider(), alignment: .bottom)
        }
    }
}
