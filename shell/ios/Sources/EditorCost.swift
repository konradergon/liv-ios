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

/// Best of `rounds` — the fastest run is the one least disturbed by
/// whatever else the phone was doing. A mean would measure the noise.
private func livCostBest(rounds: Int = 7, _ work: () -> Void) -> Double {
    var best = Double.greatestFiniteMagnitude
    for _ in 0..<rounds {
        let t0 = CFAbsoluteTimeGetCurrent()
        work()
        best = min(best, CFAbsoluteTimeGetCurrent() - t0)
    }
    return best
}

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
    // is wide enough that simulator noise cannot carry a fail across it.
    let short = livCostNote(lines: 2_000)
    let long = livCostNote(lines: 4_000)
    check(
        "the note fixture really doubles",
        Double(long.utf8.count) / Double(short.utf8.count) > 1.9)

    // THE DERIVED TITLE. An untitled note takes its title from its first
    // line, and the editor asks for it on every keystroke — so asking must
    // cost a line, not a document.
    let t1 = livCostBest { _ = livDisplayTitle(short) }
    let t2 = livCostBest { _ = livDisplayTitle(long) }
    let titleRatio = t2 / max(t1, 1e-9)
    check(
        "livDisplayTitle is flat in note length", titleRatio < 1.6,
        String(
            format: "ratio %.2f (%.3f ms -> %.3f ms). It reads the whole note to keep one line.",
            titleRatio, t1 * 1000, t2 * 1000))

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
