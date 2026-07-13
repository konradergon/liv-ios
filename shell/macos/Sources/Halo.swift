// lotus — AI presence (P16). Amber (Theme.warning) is the ONE AI hue; lake-green
// stays for selection + today. The bp10 halo→card grammar, collapsed to lotus's
// substrate: the card in the one queue + an in-place ✦ badge/wand. Every AI
// container is amber-framed; nothing else in the app uses this framing.

import SwiftUI

extension View {
    /// The AI halo (bp10 a2): a 1px amber edge + a soft outer wash. `pulse` = a
    /// single one-shot fade on appearance — the ONE sanctioned AI animation
    /// (Delta #3), never a loop, never blocking.
    func halo(_ active: Bool, cornerRadius: CGFloat = 8, pulse: Bool = false) -> some View {
        modifier(HaloModifier(active: active, cornerRadius: cornerRadius, pulse: pulse))
    }
}

private struct HaloModifier: ViewModifier {
    let active: Bool
    let cornerRadius: CGFloat
    let pulse: Bool
    @State private var settled = false

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Theme.warning.opacity(active ? 1 : 0), lineWidth: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Theme.warning.opacity(active ? 0.14 : 0), lineWidth: 3)
            )
            .opacity(pulse && !settled ? 0.55 : 1)
            .task {
                guard pulse, !settled else { return }
                withAnimation(.easeOut(duration: 0.5)) { settled = true }
            }
    }
}

/// The +/- diff (bp10 a11): one line per command, the trust primitive — never
/// collapsed. It mirrors the proposal's structured command list EXACTLY (P16c):
/// a core AddCell only ever appends, so an `add` is a pure `+` — the card never
/// synthesizes a `−` from current state (that lied about append-valued
/// properties like relations; the review's finding). A genuine replacement
/// arrives as its own RemoveCell, rendered by the `remove` branch.
struct DiffBlock: View {
    let commands: [ProposalCommandRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(commands.enumerated()), id: \.offset) { _, command in
                line(command)
            }
        }
        .font(.system(size: 11.5).monospaced())
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.surface2))
    }

    @ViewBuilder
    private func line(_ command: ProposalCommandRow) -> some View {
        switch command.kind {
        case "add":
            // Foreground (not the lake-green accent — that stays reserved for
            // selection + today): the added value is emphasis, not a commit.
            Text("+ \(command.property ?? "?"): \(command.value ?? "")")
                .foregroundColor(Theme.foreground)
        case "remove":
            Text("− \(command.property ?? "?"): \(command.value ?? "")").foregroundColor(Theme.mutedFg)
        case "trash":
            Text("− trash the duplicate").foregroundColor(Theme.mutedFg)
        case "redirect":
            Text("↳ redirect → #\(command.refTarget.map(String.init(describing:)) ?? "?")")
                .foregroundColor(Theme.mutedFg)
        default:
            Text(command.kind).foregroundColor(Theme.mutedFg)
        }
    }
}

/// The ✦ suggestion card (bp10 §2, P16d): the ✦ author chip → the plain-language
/// reason → the visible +/- diff → a REVIEW tier chip → Accept ⏎ / Dismiss Esc.
/// Amber-framed; anchored to its object, never a modal. Accept runs the exact
/// save seam a manual edit runs — there is no AI-only write path.
struct SuggestionCard: View {
    @ObservedObject var model: BoxModel
    let proposal: ProposalRow
    var onAct: () -> Void = {}

    private var subject: String { model.entity(proposal.entity)?.title ?? "#\(proposal.entity)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text("✦ \(proposal.author)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.warning)
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .background(Capsule().fill(Theme.warning.opacity(0.14)))
                Text(proposal.reason).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 8)
                Text("REVIEW")
                    .font(.system(size: 9, weight: .bold)).foregroundColor(Theme.warning)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Theme.warning.opacity(0.5), lineWidth: 0.5))
            }
            Text(subject).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
            if let commands = proposal.commands, !commands.isEmpty {
                DiffBlock(commands: commands)
            }
            HStack(spacing: 7) {
                // A custom amber capsule with a dark label: macOS keeps a white
                // label on .borderedProminent regardless of tint, and dark-mode
                // Theme.warning (#fdd663) is a light gold — white-on-gold is
                // unreadable (the review's finding). Black-on-amber mirrors the
                // header badge and stays legible in both appearances.
                Button {
                    model.accept(proposal)
                    onAct()
                } label: {
                    Text("Accept · ⏎")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(nsColor: .black).opacity(0.85))
                        .padding(.horizontal, 11).padding(.vertical, 4)
                        .background(Capsule().fill(Theme.warning))
                }
                .buttonStyle(.plain)
                Button("Dismiss · r") {
                    model.reject(proposal)
                    onAct()
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 11).fill(Color(nsColor: .textBackgroundColor)))
        .halo(true, cornerRadius: 11)
        .frame(maxWidth: 520, alignment: .leading)
    }
}
