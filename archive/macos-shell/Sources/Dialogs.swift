// liv — DialogHost (liv-ui-map.md §2.26): the ONE themed replacement
// for prompt / confirm / alert, mounted once at the top of the z-stack.
// Enter accepts, Escape cancels, scrim-mousedown cancels. Every prompt
// and confirm in the spec routes through here.

import SwiftUI

enum DialogKind {
    case alert
    case confirm(danger: Bool)
    case prompt(placeholder: String, initial: String)
}

struct DialogRequest: Identifiable {
    let id = UUID()
    let kind: DialogKind
    let title: String
    let message: String
    let confirmLabel: String
    /// prompt → the text (nil on cancel); confirm → "" or nil; alert → "".
    let done: (String?) -> Void
}

final class Dialogs: ObservableObject {
    static let shared = Dialogs()
    @Published var current: DialogRequest?
    /// The prompt's live text, owned here so the key monitor's Return
    /// can confirm with what was typed.
    @Published var promptText = ""

    private func present(_ request: DialogRequest) {
        // Modal means modal: whatever was first responder (the editor,
        // a field) loses the keyboard before the dialog takes it.
        NSApp.keyWindow?.makeFirstResponder(nil)
        if case .prompt(_, let initial) = request.kind {
            promptText = initial
        }
        current = request
    }

    func alert(_ title: String, message: String = "", done: @escaping () -> Void = {}) {
        present(
            DialogRequest(
                kind: .alert, title: title, message: message, confirmLabel: "OK"
            ) { _ in done() })
    }

    func confirm(
        _ title: String, message: String = "", danger: Bool = false,
        confirmLabel: String? = nil, done: @escaping (Bool) -> Void
    ) {
        present(
            DialogRequest(
                kind: .confirm(danger: danger), title: title, message: message,
                confirmLabel: confirmLabel ?? (danger ? "Delete" : "OK")
            ) { done($0 != nil) })
    }

    func prompt(
        _ title: String, message: String = "", placeholder: String = "",
        initial: String = "", confirmLabel: String = "OK",
        done: @escaping (String?) -> Void
    ) {
        present(
            DialogRequest(
                kind: .prompt(placeholder: placeholder, initial: initial),
                title: title, message: message, confirmLabel: confirmLabel, done: done))
    }

    func cancelCurrent() {
        guard let request = current else { return }
        current = nil
        request.done(nil)
    }

    func confirmCurrent() {
        guard let request = current else { return }
        current = nil
        if case .prompt = request.kind {
            request.done(promptText)
        } else {
            request.done("")
        }
    }
}

/// The visual: scrim bg/70 + blur, card max-w-sm at 18vh from top,
/// title 14 semibold, message 12, footer bar right-aligned.
struct DialogHost: View {
    @ObservedObject var dialogs = Dialogs.shared
    @FocusState private var fieldFocused: Bool

    var body: some View {
        if let request = dialogs.current {
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    Theme.background.opacity(0.7)
                        .background(.ultraThinMaterial)
                        .ignoresSafeArea()
                        .onTapGesture { dialogs.cancelCurrent() }
                    card(request)
                        .frame(maxWidth: 384)
                        .padding(.top, geo.size.height * 0.18)
                }
            }
            .onAppear {
                if case .prompt = request.kind {
                    fieldFocused = true
                }
            }
        }
    }

    private func card(_ request: DialogRequest) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(request.title).font(.system(size: 14, weight: .semibold))
                if !request.message.isEmpty {
                    Text(request.message)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.mutedFg)
                }
                if case .prompt(let placeholder, _) = request.kind {
                    TextField(placeholder, text: $dialogs.promptText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12.5))
                        .focused($fieldFocused)
                        .onSubmit { dialogs.confirmCurrent() }
                        .padding(.top, 6)
                }
            }
            .padding(16)

            HStack(spacing: 8) {
                Spacer()
                if !isAlert(request) {
                    Button("Cancel") { dialogs.cancelCurrent() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12.5))
                        .foregroundColor(Theme.mutedFg)
                }
                Button(request.confirmLabel) { dialogs.confirmCurrent() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(isDanger(request) ? Theme.destructive : Theme.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.secondary.opacity(0.2))
            .overlay(Divider(), alignment: .top)
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusXl).fill(Theme.popover)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusXl).strokeBorder(Theme.border)
        )
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .frame(maxWidth: .infinity)
    }

    private func isAlert(_ request: DialogRequest) -> Bool {
        if case .alert = request.kind { return true }
        return false
    }

    private func isDanger(_ request: DialogRequest) -> Bool {
        if case .confirm(danger: true) = request.kind { return true }
        return false
    }
}
