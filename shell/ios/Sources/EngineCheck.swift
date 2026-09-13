// liv iOS — THE ENGINE, ON A DEVICE.
//
// One card in Settings whose only job is to answer the question no test
// in this repo can: does the whole new chain work on a phone?
//
//   Rust → SQLite linked into the staticlib → the new C ABI → a Swift
//   decode → pixels.
//
// Every layer under this is tested (479 of them), and none of that says
// anything about whether `rusqlite`'s bundled SQLite links for
// aarch64-apple-ios, or whether `char **out` crosses the way it should on
// a real device. Phase 1 of `core-plan.md` proved the first in isolation
// in 2026-08; `build.sh` has never linked it.
//
// **Why a card and not a repointed screen.** An engine id is 16 bytes and
// `EntityRow.id` is a `UInt64` that appears 236 times across 22 Swift
// files. Moving one surface means moving that type through all of them,
// which is a refactor to do with a compiler, not by hand on a machine
// with no Swift toolchain. So the plumbing lands, this card proves it
// runs, and the refactor follows on evidence rather than on hope.
//
// **It reads and never writes.** The core box is still the truth; the
// engine box is built from it and can be deleted at any time. Rebuild
// throws it away and makes it again.
//
// DELETION DATE: this card goes when the surfaces move
// (`design/rust-owns-the-mechanisms.md` §5, stage 4 proper). It is a
// diagnostic, not a feature, and standing rule 7 says say so.

import SwiftUI

/// One fact, said the way this sheet says facts: the name quiet, the
/// value in the reading tier.
private struct CheckRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: LivType.label))
                .foregroundStyle(LivTheme.text2)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: LivType.label))
                .foregroundStyle(LivTheme.text)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct EngineCheckCard: View {
    @EnvironmentObject var box: BoxModel

    @State private var report: LivConvertReport?
    @State private var today: LivTodayView?
    @State private var fault: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let fault {
                CheckRow(label: "Problem", value: fault)
            }
            if let report {
                CheckRow(label: "Converted", value: "\(report.entities ?? 0) things")
                CheckRow(label: "Resolved", value: "\(report.resolved ?? 0) onto built-in")
                if (report.mintedVocabulary ?? 0) > 0 {
                    CheckRow(label: "Minted", value: "\(report.mintedVocabulary ?? 0) options")
                }
                if report.clean != true {
                    // Named, not counted: a list of numbers is not
                    // actionable and a dropped file is not a detail.
                    if (report.filesDropped ?? 0) > 0 {
                        CheckRow(label: "Files dropped", value: "\(report.filesDropped ?? 0)")
                    }
                    ForEach(report.unknownKinds ?? [], id: \.self) { name in
                        CheckRow(label: "No kind for", value: name)
                    }
                }
            }
            if let today {
                CheckRow(label: "Today · late", value: "\((today.late ?? []).count)")
                CheckRow(label: "Today · on the day", value: "\(today.onTheDay.count)")
                // THE PROOF, in one line: a title that came out of SQLite,
                // through the new ABI, into a SwiftUI Text.
                if let first = today.onTheDay.first ?? (today.late ?? []).first {
                    CheckRow(label: "First row", value: first.display)
                }
            }

            HStack(spacing: 8) {
                ConfirmPill(box.engineBoxExists ? "Read" : "Convert") { run() }
                    .disabled(busy)
                if box.engineBoxExists {
                    Button("Rebuild") { rebuild() }
                        .font(.system(size: LivType.body, weight: .medium))
                        .foregroundStyle(LivTheme.text2)
                        .disabled(busy)
                }
            }
            .padding(.top, 2)
        }
    }

    /// Convert if there is nothing there yet, then read Today out of it.
    private func run() {
        busy = true
        fault = nil
        if box.engineBoxExists {
            readToday()
        } else {
            box.convertToEngine { result in
                switch result {
                case .success(let r):
                    report = r
                    readToday()
                case .failure(let why):
                    fault = why
                    busy = false
                }
            }
        }
    }

    private func rebuild() {
        busy = true
        fault = nil
        today = nil
        box.rebuildEngineBox { result in
            switch result {
            case .success(let r):
                report = r
                readToday()
            case .failure(let why):
                fault = why
                busy = false
            }
        }
    }

    private func readToday() {
        // DAYS SINCE THE EPOCH, not the packed civil the old ABI uses.
        // `Civil.epochDay` exists so that conversion is named once.
        let day = Civil.epochDay(Civil.todayDay())
        box.engineToday(day: day, today: day, nowMs: Civil.nowMs()) { result in
            switch result {
            case .success(let t): today = t
            case .failure(let why): fault = why
            }
            busy = false
        }
    }
}
