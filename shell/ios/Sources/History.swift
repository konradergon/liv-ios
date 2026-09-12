// liv iOS — HISTORY: every version of the open document, and a way back.
//
// The thesis promised this in its fourth paragraph — "Every version of
// every note is still there — read what you wrote three weeks ago, put
// it back" — and the core has kept it since the history was built:
// `liv_content_history_at` is in the ABI and tested three times. Until
// 2026-09-09 no screen read it, so the promise was core-only and a user
// of this app could not do the thing the product is named for.
//
// WHAT IT IS: a list, newest first, one row per saved value — when, who,
// and the first line of what was there — and a Restore on every row but
// the current one. WHAT RESTORE IS: an ordinary `setContent` of that
// version's spans over a freshly read base, which the core appends as a
// NEW version. The log is never rewritten, so a restore is itself
// undoable by restoring the one above it; no confirmation card is put
// in the way of a reversible verb.
//
// It is hosted as a system sheet in RootView beside the properties card,
// on purpose: one container for one idea, and the container that has
// already survived the bar-layering lesson (rev 54).
//
// RESTORING THE NOTE YOU ARE LOOKING AT needs nothing here. The editor
// asks "did my base move?" on every snapshot (`snapshotArrived`): a clean
// buffer reloads silently, so the restored words appear under the card;
// a dirty one flushes, hits the seam's stale path, and shows its own
// "This changed elsewhere" banner with both truths kept — the same
// non-destructive path an edit from the CLI takes. One rule for the
// world moving, not a second one for this door.

import SwiftUI

struct HistoryCard: View {
    let id: UInt64
    @EnvironmentObject var box: BoxModel
    @EnvironmentObject var desk: DeskModel

    @State private var versions: [ContentVersion] = []
    @State private var loaded = false
    /// The seq being written back, so a double tap is one restore.
    @State private var restoring: UInt64?
    /// A restore the box refused — a moved base twice over, or a busy
    /// box. Said once, in the row, rather than as a dialog.
    @State private var refused: UInt64?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LivSheetTitle("History")
                    .padding(.bottom, 8)
                if loaded && versions.isEmpty {
                    EmptyHint("No versions")
                    .padding(.top, 40)
                } else {
                    ForEach(Array(versions.enumerated()), id: \.offset) { i, v in
                        row(v, current: i == 0, divided: i < versions.count - 1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 24)
        }
        .background(LivTheme.surface)
        .onAppear(perform: load)
    }

    /// When, who, the first line, and — for every version but the one
    /// you are looking at — the way back.
    private func row(_ v: ContentVersion, current: Bool, divided: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(when(v))
                        .font(.system(size: LivType.label, weight: .medium).monospacedDigit())
                        .foregroundStyle(LivTheme.text)
                    if current {
                        Text("current")
                            .font(.system(size: LivType.caption))
                            .foregroundStyle(LivTheme.text3)
                    } else if let author = v.author, author != "user" {
                        // A version the clerk or the system wrote says so;
                        // the person's own need no badge.
                        Text(author)
                            .font(.system(size: LivType.caption))
                            .foregroundStyle(LivTheme.text3)
                    }
                }
                Text(firstLine(v))
                    .font(.system(size: LivType.body))
                    .foregroundStyle(current ? LivTheme.text2 : LivTheme.text3)
                    .lineLimit(2)
                if refused == v.seq {
                    Text("The note changed while restoring. Try again.")
                        .font(.system(size: LivType.caption))
                        .foregroundStyle(LivTheme.red)
                }
            }
            Spacer(minLength: 8)
            if !current {
                Button {
                    restore(v)
                } label: {
                    Text(restoring == v.seq ? "Restoring…" : "Restore")
                        .font(.system(size: LivType.body, weight: .semibold))
                        .foregroundStyle(LivTheme.accent)
                        .padding(.horizontal, 12)
                        .frame(height: LivRow.touch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(restoring != nil)
                .accessibilityLabel("Restore this version")
            }
        }
        .padding(.horizontal, LivRow.cardInset + 4)
        .frame(minHeight: LivRow.tall)
        .overlay(alignment: .bottom) {
            if divided {
                Rectangle().fill(LivTheme.border).frame(height: 0.5)
                    .padding(.leading, LivRow.cardInset + 4)
            }
        }
    }

    // MARK: reading

    private func load() {
        box.history(id) { list in
            versions = list
            loaded = true
        }
    }

    /// "Tue 8 Sep 21:14" — the day through `Civil`, the same face every
    /// stamp in the app wears, and the clock always shown: a version at
    /// midnight is a real 00:00.
    private func when(_ v: ContentVersion) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(v.time ?? 0))
        let hm = Civil.hhmm(of: date)
        return Civil.dayLabel(Civil.day(of: date))
            + String(format: " %02d:%02d", hm / 100, hm % 100)
    }

    /// The first line of that version's words, names resolved the way the
    /// editor resolves them, so a `[[link]]` reads as its target and not
    /// as a number.
    private func firstLine(_ v: ContentVersion) -> String {
        let text = SpanText.spansToText(v.spans ?? []) { id in
            box.entity(id).map(livRowTitle)
        }
        let line = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let shown = livDisplayTitle(line)
        return shown.isEmpty ? "(empty)" : shown
    }

    // MARK: putting it back

    /// Re-read the base, then save the old spans over it — the seam's own
    /// rule: a save is to a value, never a moment, and a refused (stale)
    /// save never overwrites. One retry on a moved base, because the
    /// editor may have flushed a keystroke between our read and our
    /// write; a second refusal is reported in the row and left there.
    private func restore(_ v: ContentVersion, retried: Bool = false) {
        guard let spans = v.spans, let seq = v.seq, restoring == nil || retried else { return }
        restoring = seq
        refused = nil
        box.content(id) { doc in
            guard let base = doc?.fingerprint, doc?.missing != true else {
                restoring = nil
                refused = seq
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            box.setContent(id, spansJson: SpanText.json(spans), base: base) { status, _ in
                switch status {
                case 1:
                    restoring = nil
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    load()
                case -1 where !retried:
                    restore(v, retried: true)
                default:
                    restoring = nil
                    refused = seq
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }
}
