// liv iOS — WHAT A KEYSTROKE COSTS, and whether it grows with the note.
//
// Standing rule 2 asks for a COST test on anything on the write path, and
// says to assert the SHAPE — doubling the input roughly doubles the work,
// or it does not — never a millisecond budget. Every cost test in this
// repo was Rust and scaled the NUMBER of notes (`services/tests/scale.rs`);
// none scaled the LENGTH of one. That is the gap this closes.
//
// It exists because of a bad argument. On 2026-09-06 the editor's per-
// keystroke work was defended with "the largest note on this machine is
// under 3,000 characters", and the owner rejected that reasoning outright:
// the notes here are test junk, and a design has to hold for a note of any
// length. Measured afterwards with a 4,000-line note in the app, typing
// cost about 2 ms a keystroke; at 8,000 lines, about 6 ms. Under the frame
// budget, and growing — which is exactly the thing a shape test catches
// and a stopwatch on today's data does not.
//
// Run it: `simctl launch … -editor-cost.selfcheck 1`, or
// `./suites.sh editor-cost`.

import Foundation

/// A note of `lines` lines, mixed markdown, deterministic.
private func livCostNote(lines: Int) -> String {
    var out: [String] = []
    out.reserveCapacity(lines)
    for i in 0..<lines {
        switch i % 9 {
        case 0: out.append("# Heading \(i)")
        case 1: out.append("- a bullet with some words in it, number \(i)")
        case 2: out.append("- [ ] a task with some words in it, number \(i)")
        case 3: out.append("> a quote with some words in it, number \(i)")
        case 4: out.append("")
        default:
            out.append(
                "body line \(i) with **bold** and *italic* and `code` and a "
                    + "few more ordinary words to make it a realistic length")
        }
    }
    return out.joined(separator: "\n")
}

/// Best of `rounds`, each round doing the work `times` over — the fastest
/// run is the one least disturbed by whatever else the phone was doing. A
/// mean would measure the noise.
///
/// **`times` IS WHAT MAKES THE RATIO MEAN ANYTHING** (2026-09-22). One
/// `livDisplayTitle` is about a microsecond, and `CFAbsoluteTimeGetCurrent`
/// moves in steps of roughly that size — so ONE TICK of difference read
/// as `ratio 2.00 (0.001 ms -> 0.002 ms)` and failed a gate of 1.6,
/// about a function that is flat by construction: `livFirstLine` stops
/// at the first newline and everything after it works on that one line.
///
/// The check was right to assert a SHAPE rather than a budget (standing
/// rule 2). It was measuring below the resolution it needed to see one.
/// Repeating the work lifts both readings into hundreds of microseconds,
/// where a doubling is a doubling and not a rounding.
private func livCostBest(rounds: Int = 7, times: Int = livCostTimes, _ work: () -> Void) -> Double {
    var best = Double.greatestFiniteMagnitude
    for _ in 0..<rounds {
        let t0 = CFAbsoluteTimeGetCurrent()
        for _ in 0..<times { work() }
        best = min(best, CFAbsoluteTimeGetCurrent() - t0)
    }
    return best
}

/// How many times `livCostBest` repeats the work. ONE NUMBER: the
/// default above reads it, and the failure text divides by it to report
/// a per-call figure, so the two can never disagree about how big a
/// batch was.
private let livCostTimes = 500

/// SOMEWHERE FOR THE ANSWER TO GO.
///
/// A timing loop that throws its result away is a loop the optimiser is
/// allowed to delete, and `build.sh release` runs at `-O`. Both readings
/// would then be zero, the ratio would be 1.0, and the check would pass
/// while measuring nothing — the worst way for a cost test to fail.
/// Feeding the result somewhere the compiler cannot see the end of
/// keeps the work. The "batch is long enough to time" check below is
/// the second line of that defence: a deleted loop cannot take 0.1 ms.
private var livCostSink = 0

func livEditorCostSelfCheck() -> [String] {
    var failures: [String] = []
    func check(_ label: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        if !ok { failures.append("FAIL \(label) \(detail())") }
    }

    // ---- the shape: a keystroke must not read the whole note ----
    //
    // The ratio, not the milliseconds. A function that reads the whole
    // note doubles when the note doubles; one that reads a line does not.
    // 1.6 is the gate: linear lands near 2.0, flat near 1.0, and the gap
    // is wide enough that simulator noise cannot carry a fail across it
    // — PROVIDED THE READING IS ABOVE THE CLOCK, which is what
    // `livCostTimes` is for and what the batch check below confirms. On
    // 2026-09-22 it was not, and one microsecond against two failed
    // this gate at exactly 2.00 about code that never changed.
    let short = livCostNote(lines: 2_000)
    let long = livCostNote(lines: 4_000)
    check(
        "the note fixture really doubles",
        Double(long.utf8.count) / Double(short.utf8.count) > 1.9)

    // THE DERIVED TITLE. An untitled note takes its title from its first
    // line, and the editor asks for it on every keystroke — so asking must
    // cost a line, not a document.
    livCostSink = 0
    let t1 = livCostBest { livCostSink &+= livDisplayTitle(short).utf8.count }
    let t2 = livCostBest { livCostSink &+= livDisplayTitle(long).utf8.count }
    check("the timed work actually ran", livCostSink != 0)

    // **IS THE READING ABOVE THE CLOCK?** Asked first and separately, so
    // that an unmeasurable batch says exactly that instead of handing
    // the next check a ratio built out of rounding and letting it blame
    // the code (2026-09-22 — it did, for a whole run).
    check(
        "the batch is long enough to time", t1 > 1e-4,
        String(
            format: "%d calls took %.4f ms, which is at the clock's own step.",
            livCostTimes, t1 * 1000))

    let titleRatio = t2 / max(t1, 1e-9)
    check(
        "livDisplayTitle is flat in note length", titleRatio < 1.6,
        String(
            format:
                "ratio %.2f (%.4f ms -> %.4f ms per call, %d calls a batch). "
                + "It reads the whole note to keep one line.",
            titleRatio, t1 * 1000 / Double(livCostTimes), t2 * 1000 / Double(livCostTimes),
            livCostTimes))

    // ---- the state: dirty is COUNTED now, and counting is delicate ----
    //
    // Dirty used to be `text != storedText`, which was O(note) but got one
    // thing right for free: text typed WHILE a save was in flight stayed
    // dirty, because the comparison ran against what that save actually
    // wrote. A flag would lose those keystrokes. A counter keeps them, and
    // these pin it.
    var e = LivEdits()
    check("a loaded note is clean", !e.dirty)
    e.edited()
    check("a keystroke makes it dirty", e.dirty)
    let mark = e.inFlight()
    e.landed(mark)
    check("the save that carried it makes it clean", !e.dirty)

    // THE CASE THE COMPARISON GOT RIGHT: type, start saving, type again.
    var f = LivEdits()
    f.edited()
    let flight = f.inFlight()  // the save leaves with this much typed
    f.edited()  // and one more character arrives while it is away
    f.landed(flight)
    check(
        "a keystroke typed during a save survives it", f.dirty,
        "the save landed at \(flight); the buffer is at \(f.typed)")

    // Two saves can be in flight after a retry; the LAST to land must not
    // mark the buffer clean past what it carried.
    var g = LivEdits()
    g.edited()
    let first = g.inFlight()
    g.edited()
    let second = g.inFlight()
    g.landed(second)
    check("the newer save cleans it", !g.dirty)
    g.landed(first)
    check("an older save landing late does not re-dirty it", !g.dirty)

    return failures
}
