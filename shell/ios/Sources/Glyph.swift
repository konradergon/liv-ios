// liv iOS — the icon language: what a thing IS, drawn by one hand.
// The hand is the Icons board's (the "clearer" canvas, approved
// 2026-09-24): a 24 grid, a constant 1.75pt stroke (`LivPen`), round
// ends, corners at 3, and one signature — the filled dot — where an
// icon's meaning is.
//
// Three rules govern everything in this file.
//
//   1. ONE classifier. A row's kind and its glyph must come from the
//      same answer to "what is this?". They did not: the colour read
//      `kinds.first` and the glyph read `kinds.contains(…)` in priority
//      order, so a task filed as ["note","task"] drew a blue chip with a
//      tick in it. `LivKind.of` is now the only place that decides.
//   2. The icons are DRAWN, not borrowed. Apple's symbols are a
//      different language — filled, heavier, and shaped to their own
//      grid — so the app looked nothing like the approved blueprints
//      (owner, 2026-08-13: "i don't see the blueprint's custom icons in
//      the app"). Every glyph below is the board's own SVG path data,
//      pasted, and drawn by one parser (`GlyphPath`).
//   3. ICONS ARE INK. One colour per icon — the ink of the place it sits
//      in: `text` on the bar, the top keys, the library and the workspace
//      marks; `text2` in lists, menus and chips. A dot is filled in that
//      same ink. Kind colour survives only on marks that are NOT icons:
//      Today's event bars, the calendar's blocks, the tab card's dot.
//
// The create menu's verbs wear the family's drawings (the Create board
// draws them; 2026-08-12 had rejected that). Property field rows still
// wear none.

import SwiftUI

// MARK: - what a thing is

// **NO `LivArea`** (owner, 2026-09-21: *"Areas are all created by the
// user, so whatever fixed areas are in code should be removed"*).
//
// It was an enum of the six the app shipped, each with a mark — a
// briefcase for Work, a heart for Health — and `glyph(named:)` matched
// a row's area cell against those names, falling back to the field's
// own mark for anything minted. With no shipped area there is nothing
// left to match: every name is minted, so every one takes the fallback,
// and a table that always returns the same answer is not a table
// (standing rule 6).
//
// Giving a user's own area a mark of its own is a real thing to want —
// and it is a picker and a cell, not a switch over six strings.

/// The seven kinds the app draws. A kind carries its colour and its
/// glyph together, because a thing that is purple in one place and blue
/// in the next is the exact defect this type exists to prevent.
enum LivKind: CaseIterable {
    case note, task, event, file, link, person, capture

    /// The ONE classifier. Order is the priority: a file is a file
    /// whatever else it says, and anything unshaped is a capture.
    static func of(_ row: EntityRow?) -> LivKind {
        guard let row else { return .capture }
        if FileFacts.of(row) != nil { return .file }
        let kinds = row.kinds ?? []
        if kinds.contains("event") { return .event }
        // A status is what makes a thing a task, with or without the word.
        if kinds.contains("task") || (row.status?.isEmpty == false) { return .task }
        if kinds.contains("person") { return .person }
        if kinds.contains("link") { return .link }
        if kinds.contains("note") { return .note }
        return .capture
    }

    /// The name a snapshot uses, for the few places that hold a kind
    /// string and no row (a search group header, a wire field).
    static func named(_ kind: String) -> LivKind {
        LivKind.allCases.first { $0.wire == kind } ?? .capture
    }

    var wire: String {
        switch self {
        case .note: return "note"
        case .task: return "task"
        case .event: return "event"
        case .file: return "file"
        case .link: return "link"
        case .person: return "person"
        case .capture: return "capture"
        }
    }

    /// The kind's word, for the places that must SAY what a thing is
    /// rather than draw it — a menu's subject line, an accessibility
    /// label. `wire` is the snapshot's spelling and is not for reading.
    var word: String {
        switch self {
        case .note: return "Note"
        case .task: return "Task"
        case .event: return "Event"
        case .file: return "File"
        case .link: return "Link"
        case .person: return "Person"
        case .capture: return "Capture"
        }
    }

    /// One kind, one colour, wherever a kind is COLOURED — and since the
    /// Icons board (2026-09-24) that is only on marks that are not icons:
    /// Today's event bars, the calendar's blocks, the tab card's dot.
    /// An icon is ink (rule 3 above). Nothing else may hardcode a kind's
    /// colour.
    var color: Color {
        switch self {
        case .note: return LivTheme.noteViolet
        case .task: return LivTheme.purple
        case .event: return LivTheme.teal
        case .file, .link: return LivTheme.orange
        case .person: return LivTheme.pink
        case .capture: return LivTheme.yellow  // caught, not yet shaped
        }
    }

    /// The kind's own drawing. A file's glyph narrows by format, so a
    /// spreadsheet and a contract do not look identical (review,
    /// 2026-08-08).
    func glyph(_ row: EntityRow? = nil) -> LivGlyph {
        switch self {
        case .note: return .note
        case .task: return .task
        case .event: return .event
        case .link: return .link
        case .person: return .person
        case .capture: return .capture
        case .file: return .file(row.flatMap(FileFacts.of)?.fileClass ?? .other)
        }
    }

    static func color(of row: EntityRow?) -> Color { of(row).color }
    static func glyph(of row: EntityRow?) -> LivGlyph { of(row).glyph(row) }
}

// MARK: - the drawings

/// Every icon the app draws for itself — the bar's back and forward
/// included, because the boards draw them in this hand. Disclosure
/// chevrons are drawn too, by `LivChevron` (Kit.swift); the close cross
/// and the repeat mark stay on Apple's symbols — punctuation, not part of
/// this language.
enum LivGlyph: Equatable {
    // Things.
    case note, task, event, person, link, capture
    case file(FileFacts.Class)
    // Places — the library's rows.
    case today, inbox, calendar, tasks, everything
    // AREAS OF LIFE — the furniture the product page calls the product,
    // drawn (2026-09-06, direction A: "the furniture shows"). Family &
    // Friends reuses `.people`; the sixth mark is the field's own `.area`
    // for any area a person mints later.
    case work, health, money, home, learning
    // Furniture.
    case filter, settings, workspaces, trash
    /// THE PROPERTIES DOOR: a card with two label-and-value rows. It was
    /// Apple's sliders, which read as "adjust" (the Icons board).
    case properties
    // The bar's keys, and the camera's verb in the create menu.
    case back, forward, search, scan
    /// A PAGE WITH A PLUS — the bar's `+`, which makes a note. Its
    /// hold-for-more tick is `HoldTick`, beside it, not part of it.
    case new
    /// A WORKSPACE IS ITS LETTER: the first grapheme of its name,
    /// uppercased, set like an icon (`LivGlyph.initial`). It was a bare
    /// circle, identical for every workspace. Drawn as TEXT, so it has
    /// no path — the self-check knows. A name with no letter shows its
    /// site; "All" is never a letter, it is `.workspaces`.
    case letter(String)
    /// THE BOARD'S TICK — the chosen workspace, "File N by their
    /// guesses". A mark, not a thing: it says "yes, this one".
    case check
    /// A PLUS, bare — the door that adds a row to a card ("Add link").
    case plus
    /// FIELDS — one per property family, for the properties panel.
    ///
    /// Icons here were tried on 2026-08-12 and rejected the same day
    /// ("icons for properties are confusing"), and hand-picked colours
    /// went in instead. Those colours came out on 2026-08-29 for being
    /// the loudest thing on a grey screen — which left the rows bare.
    ///
    /// The desktop had already found the third answer: its `PropertyIcon`
    /// is "flat, monochrome LINE icons (Obsidian-style)", with a note
    /// that coloured tiles were removed for reading "heavy and
    /// 'designed'" and that colour is reserved for file identity, never
    /// metadata fields. These are that, drawn with this app's own pen so
    /// the two shells read as one product.
    ///
    /// TWO OF THE SIX FIELD MARKS SURVIVE, and they survive as AREA
    /// marks rather than as field marks: `.area` is what EVERY area
    /// wears now that none is compiled in (2026-09-21), and `.people`
    /// is the mark the old Family & Friends area wore.
    ///
    /// `due`, `status`, `project` and `tags` went on 2026-09-12 with the
    /// Settings Fields card, which was the last thing that could show
    /// one. Their only route to a screen had been `LivGlyph.field(_:)`,
    /// the name-to-mark lookup that card called, and the inspector is
    /// closed to them by a dated ruling: the properties card's label said "NO DOT,
    /// AND NO GLYPH" (owner, 2026-08-29), recording that field icons
    /// were tried on 2026-08-12 and rejected the same day because "a
    /// clock for 'due' and a tag for 'tags' are pictures of the word
    /// beside them". So there was nowhere for them to go back to.
    ///
    /// The drawings were careful and two of them record a failed first
    /// attempt. `git log --diff-filter=D -S'case .tags'` finds them if a
    /// desktop shell ever wants the vocabulary back.
    case area, people

    /// THE SWIPE VERBS that move a task to another day (2026-09-29): the
    /// buttons behind a swiped row draw these, not SF Symbols, so a row's
    /// trash is the panel's trash (owner: "the icons in bubbles in rows
    /// should be consistent"). "Move to today" wears `.today` and "Pick" the
    /// calendar; these are the three the family did not have.
    case tonight, tomorrow, weekend

    /// THE NUMBERED BOX — the bar's tab key, the count inside as Text
    /// (`LivIcon`), so the path does not depend on it. The Icons board of
    /// 2026-09-24 made it two stacked sheets, because the box "read as a
    /// date"; the owner took the box back on 2026-09-29 ("the old open tabs
    /// [n] style was better").
    case tabs(Int)

    /// A workspace's letter: the first grapheme of its name, leading
    /// whitespace skipped, uppercased. "" for a blank name.
    ///
    /// THE FIRST LETTER, or failing that the first character (owner,
    /// 2026-09-29: "first letter if there are any, otherwise first unicode
    /// character (like an emoji)"). So "🏠 Home" is H, and "🏠" is 🏠.
    static func initial(of name: String) -> String {
        if let letter = name.first(where: \.isLetter) { return String(letter).uppercased() }
        return name.drop(while: \.isWhitespace).first.map(String.init) ?? ""
    }
}

/// ONE DRAWING, AS DATA: the board's own numbers, pasted rather than
/// transcribed, so a redrawn icon is a new string and not new code.
///
/// Two layers, both in the icon's one ink:
/// - `ink`, stroked — the drawing;
/// - `fill`, filled — the dot, and the odd solid block (a PDF's label
///   bar, the hold tick, All workspaces' four dots).
///
/// A third, `faint` — a stroke at 55% for a "second voice" — went on
/// 2026-09-29 with its last two users, Unsorted's falling stroke and the
/// back square of All workspaces.
struct GlyphDrawing: Equatable {
    enum Mark: Equatable {
        /// SVG path data, in the strict grammar `GlyphPath` reads.
        case d(String)
        /// x, y, width, height, corner radius — a circular corner, as SVG's `rx`.
        case rect(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
        /// cx, cy, r.
        case circle(CGFloat, CGFloat, CGFloat)
    }
    enum Layer: CaseIterable { case ink, fill }

    /// The side of the square the numbers live in: 24 for every glyph,
    /// 7 for the hold tick.
    var grid: CGFloat = 24
    var ink: [Mark] = []
    var fill: [Mark] = []

    func marks(_ layer: Layer) -> [Mark] {
        switch layer {
        case .ink: return ink
        case .fill: return fill
        }
    }

    /// One layer in grid units, or nil when a `d` breaks the grammar.
    func path(_ layer: Layer) -> Path? {
        var path = Path()
        for mark in marks(layer) {
            switch mark {
            case .d(let d):
                guard let part = GlyphPath.parse(d) else { return nil }
                path.addPath(part)
            case .rect(let x, let y, let w, let h, let r):
                path.addRoundedRect(
                    in: CGRect(x: x, y: y, width: w, height: h),
                    cornerSize: CGSize(width: r, height: r), style: .circular)
            case .circle(let cx, let cy, let r):
                path.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
            }
        }
        return path
    }

    /// HOLD FOR MORE: a filled quarter-round in the corner of a key whose
    /// hold opens a menu (the five bar boards). Its own 7 grid.
    static let holdTick = GlyphDrawing(grid: 7, fill: [.d("M6 1V4.5A1.5 1.5 0 0 1 4.5 6H1Z")])
}

/// THE ONE PARSER for every drawing (standing rule 4): the glyphs, the
/// hold tick and the PDF bar all go through it.
///
/// STRICT ON PURPOSE. Every board draws with absolute M L H V A Z only,
/// never an implicit repeat, and every arc is circular (rx == ry, no
/// rotation) — so anything else is a typo, and it fails (nil) rather than
/// drawing something nearby. The self-check parses every string.
enum GlyphPath {
    private static let arity: [Character: Int] = ["M": 2, "L": 2, "H": 1, "V": 1, "A": 7, "Z": 0]

    static func parse(_ d: String) -> Path? {
        // Commands, each with the numbers after it.
        var ops: [(Character, [CGFloat])] = []
        var number = ""
        func flush() -> Bool {
            guard !number.isEmpty else { return true }
            guard let v = Double(number), !ops.isEmpty else { return false }
            ops[ops.count - 1].1.append(CGFloat(v))
            number = ""
            return true
        }
        for ch in d {
            if arity[ch] != nil {
                guard flush() else { return nil }
                ops.append((ch, []))
            } else if ch == " " || ch == "," {
                guard flush() else { return nil }
            } else if "0123456789.-".contains(ch) {
                number.append(ch)
            } else {
                return nil
            }
        }
        guard flush(), ops.first?.0 == "M" else { return nil }

        var path = Path()
        var at = CGPoint.zero
        var start = CGPoint.zero
        for (command, n) in ops {
            guard n.count == arity[command] else { return nil }
            switch command {
            case "M":
                at = CGPoint(x: n[0], y: n[1])
                start = at
                path.move(to: at)
            case "L":
                at = CGPoint(x: n[0], y: n[1])
                path.addLine(to: at)
            case "H":
                at.x = n[0]
                path.addLine(to: at)
            case "V":
                at.y = n[0]
                path.addLine(to: at)
            case "A":
                guard n[0] == n[1], n[2] == 0, [0, 1].contains(n[3]), [0, 1].contains(n[4])
                else { return nil }
                let end = CGPoint(x: n[5], y: n[6])
                arc(&path, from: at, to: end, radius: n[0], large: n[3] == 1, sweep: n[4] == 1)
                at = end
            default:  // Z
                path.closeSubpath()
                at = start
            }
        }
        return path
    }

    /// SVG's endpoint arc as a centre arc (SVG 1.1, F.6.5, for circles).
    ///
    /// A radius shorter than half the chord GROWS to it, as a browser
    /// draws it: the link's arcs ask for 3.8 across a 4.6 half-chord and
    /// are semicircles. SVG's sweep 1 turns the angle up, which in this
    /// y-down space Core Graphics calls counter-clockwise — hence
    /// `clockwise: !sweep`.
    private static func arc(
        _ path: inout Path, from p: CGPoint, to q: CGPoint,
        radius: CGFloat, large: Bool, sweep: Bool
    ) {
        let hx = (q.x - p.x) / 2, hy = (q.y - p.y) / 2
        let half = (hx * hx + hy * hy).squareRoot()
        guard half > 0, radius > 0 else {
            path.addLine(to: q)
            return
        }
        let r = max(radius, half)
        let k = (large == sweep ? -1 : 1) * max(0, r * r - half * half).squareRoot() / half
        let c = CGPoint(x: p.x + hx - k * hy, y: p.y + hy + k * hx)
        path.addArc(
            center: c, radius: r,
            startAngle: .radians(atan2(p.y - c.y, p.x - c.x)),
            endAngle: .radians(atan2(q.y - c.y, q.x - c.x)),
            clockwise: !sweep)
    }
}

extension LivGlyph {
    /// THE TABLE: every glyph's drawing, in the board's own numbers (the
    /// Icons, Create, Note and Panel boards). Cases the boards do not
    /// draw are drawn in the same hand: the file formats, the area marks,
    /// the funnel and the archive box.
    var drawing: GlyphDrawing {
        switch self {
        // ---- the family ----
        case .today:
            return GlyphDrawing(
                ink: [
                    .circle(12, 12, 4),
                    .d(
                        "M12 2.8V4.8M12 19.2V21.2M2.8 12H4.8M19.2 12H21.2M5.5 5.5L6.9 6.9"
                            + "M17.1 17.1L18.5 18.5M5.5 18.5L6.9 17.1M17.1 6.9L18.5 5.5"),
                ],
                fill: [.circle(12, 12, 1.5)])
        case .inbox, .capture:
            // Something dropping into a tray: caught, not yet shaped.
            // The dot alone says "falling in" (clearer spec, 2026-09-29);
            // the faint stroke above it went.
            return GlyphDrawing(
                ink: [
                    .d("M3.5 12.5V17A3 3 0 0 0 6.5 20H17.5A3 3 0 0 0 20.5 17V12.5"),
                    .d("M3.5 12.5H8.3L9.8 15H14.2L15.7 12.5H20.5"),
                ],
                fill: [.circle(12, 8.3, 1.7)])
        case .note:
            return GlyphDrawing(
                ink: [.rect(5, 3.5, 14, 17, 3), .d("M8.5 8.5H15.5M8.5 12H15.5M8.5 15.5H11.5")],
                fill: [.circle(14.3, 15.5, 1.25)])
        // A TASK IS A BOX WITH A RULE; THE TASKS PLACE IS THE TICKED BOX
        // (the clearer spec, 2026-09-29, which splits what the boards of
        // 2026-09-24 had shared: a thing to do is not yet done).
        case .task:
            return GlyphDrawing(ink: [.rect(4.5, 4.5, 15, 15, 3.5), .d("M9.5 12H14.5")])
        case .tasks:
            return GlyphDrawing(ink: [.rect(4.5, 4.5, 15, 15, 3.5), .d("M8.6 12.3L11 14.7L15.5 9.6")])
        case .event, .calendar:
            return GlyphDrawing(
                ink: [.rect(3.5, 5, 17, 15.5, 3), .d("M8 3V6.5M16 3V6.5M3.5 10H20.5")],
                fill: [.circle(15.5, 15.2, 1.7)])
        case .search:
            return GlyphDrawing(ink: [.circle(10.5, 10.5, 6.3), .d("M15.2 15.2L20 20")])
        case .back:
            return GlyphDrawing(ink: [.d("M14.5 5.5L8 12L14.5 18.5")])
        case .forward:
            return GlyphDrawing(ink: [.d("M9.5 5.5L16 12L9.5 18.5")])
        case .person:
            return GlyphDrawing(ink: [
                .circle(12, 8.3, 3.8),
                .d("M4.8 20V19A4.5 4.5 0 0 1 9.3 14.5H14.7A4.5 4.5 0 0 1 19.2 19V20"),
            ])
        case .link:
            return GlyphDrawing(ink: [
                .d("M10 14L14 10"),
                .d("M11 6.5L12.8 4.7A3.8 3.8 0 0 1 19.3 11.2L17.5 13"),
                .d("M13 17.5L11.2 19.3A3.8 3.8 0 0 1 4.7 12.8L6.5 11"),
            ])
        case .file(let fileClass):
            return Self.file(fileClass)
        case .scan:
            return GlyphDrawing(ink: [
                .d(
                    "M4 8.5V6.5A2.5 2.5 0 0 1 6.5 4H8.5M15.5 4H17.5A2.5 2.5 0 0 1 20 6.5V8.5"
                        + "M20 15.5V17.5A2.5 2.5 0 0 1 17.5 20H15.5M8.5 20H6.5A2.5 2.5 0 0 1 4 17.5V15.5"),
                .d("M8 10H16M8 14H13"),
            ])
        case .trash:
            return GlyphDrawing(ink: [
                .d(
                    "M4.5 6.5H19.5M9.5 6.5V4.5H14.5V6.5M6.5 6.5L7.4 18.3A2 2 0 0 0 9.4 20.2"
                        + "H14.6A2 2 0 0 0 16.6 18.3L17.5 6.5")
            ])
        case .settings:
            // A PLAIN COGWHEEL (owner, 2026-09-15: an earlier drawing was
            // "a pirate ship steering wheel"). SIX teeth, the first
            // pointing up, round a 3.1 hub (owner, 2026-09-29: "revert to
            // the old gear icon but with less bumps"): the eight-tooth cog
            // read as too many. The approved mockup's own path.
            return GlyphDrawing(ink: [
                .d(
                    "M8.56 6.03L9.44 5.52A0.45 0.45 0 0 0 9.66 5.2L9.93 3.4A0.45 0.45 0 0 1 10.38 3.02"
                        + "L13.62 3.02A0.45 0.45 0 0 1 14.07 3.4L14.34 5.2A0.45 0.45 0 0 0 14.56 5.52"
                        + "L16.33 6.55A0.45 0.45 0 0 0 16.72 6.57L18.41 5.91A0.45 0.45 0 0 1 18.97 6.11"
                        + "L20.59 8.91A0.45 0.45 0 0 1 20.48 9.49L19.06 10.63A0.45 0.45 0 0 0 18.89 10.98"
                        + "L18.89 13.02A0.45 0.45 0 0 0 19.06 13.37L20.48 14.51A0.45 0.45 0 0 1 20.59 15.09"
                        + "L18.97 17.89A0.45 0.45 0 0 1 18.41 18.09L16.72 17.43A0.45 0.45 0 0 0 16.33 17.45"
                        + "L14.56 18.48A0.45 0.45 0 0 0 14.34 18.8L14.07 20.6A0.45 0.45 0 0 1 13.62 20.98"
                        + "L10.38 20.98A0.45 0.45 0 0 1 9.93 20.6L9.66 18.8A0.45 0.45 0 0 0 9.44 18.48"
                        + "L7.67 17.45A0.45 0.45 0 0 0 7.28 17.43L5.59 18.09A0.45 0.45 0 0 1 5.03 17.89"
                        + "L3.41 15.09A0.45 0.45 0 0 1 3.52 14.51L4.94 13.37A0.45 0.45 0 0 0 5.11 13.02"
                        + "L5.11 10.98A0.45 0.45 0 0 0 4.94 10.63L3.52 9.49A0.45 0.45 0 0 1 3.41 8.91"
                        + "L5.03 6.11A0.45 0.45 0 0 1 5.59 5.91L7.28 6.57A0.45 0.45 0 0 0 7.67 6.55Z"),
                .circle(12, 12, 3.1),
            ])
        // ---- the cards ----
        case .letter:
            return GlyphDrawing()  // Text, drawn by `LivIcon`
        case .check:
            return GlyphDrawing(ink: [.d("M5 12.5L9.8 17.2L19 7.2")])
        case .plus:
            return GlyphDrawing(ink: [.d("M12 5V19M5 12H19")])
        case .workspaces:
            // ALL WORKSPACES IS FOUR DOTS, and no strokes (clearer spec,
            // 2026-09-29, the owner: the "All" icon "doesn't fit in"). It
            // was two stacked squares — the drawing the area mark had.
            return GlyphDrawing(fill: [
                .circle(7.5, 7.5, 3), .circle(16.5, 7.5, 3),
                .circle(7.5, 16.5, 3), .circle(16.5, 16.5, 3),
            ])
        case .tabs:
            // THE NUMBERED BOX (owner, 2026-09-29: "the old open tabs [n]
            // style was better"), where two stacked sheets stood.
            return GlyphDrawing(ink: [.rect(3, 3.5, 18, 17, 3.5)])
        case .new:
            return GlyphDrawing(ink: [
                .d("M11.5 4H7A3 3 0 0 0 4 7V17A3 3 0 0 0 7 20H17A3 3 0 0 0 20 17V12.5"),
                .d("M18 2.8V9.2M14.8 6H21.2"),
                .d("M8 12.5H13M8 16H11"),
            ])
        case .area:
            // A BOX YOUR THINGS ARE FILED INTO (clearer spec, 2026-09-29;
            // the owner: "'Areas' icon is ugly"). It was a quartered circle.
            return GlyphDrawing(ink: [
                .d(
                    "M8.1 5.25L11.2 3.46A1.6 1.6 0 0 1 12.8 3.46L19 7.04A1.6 1.6 0 0 1 19.8 8.42"
                        + "L19.8 15.58A1.6 1.6 0 0 1 19 16.96L12.8 20.54A1.6 1.6 0 0 1 11.2 20.54"
                        + "L5 16.96A1.6 1.6 0 0 1 4.2 15.58L4.2 8.42A1.6 1.6 0 0 1 5 7.04Z"),
                .d("M4.46 7.65L12 12L19.54 7.65M12 12V20.7"),
            ])
        case .tonight:
            // A crescent: the moon bitten out of by a smaller circle.
            return GlyphDrawing(ink: [
                .d("M11.46 4.32A8.2 8.2 0 1 0 20.07 13.93A6.6 6.6 0 0 1 11.46 4.32Z")
            ])
        case .tomorrow:
            // The sun on the horizon, rising.
            return GlyphDrawing(ink: [
                .d("M3 18.5H21M7.5 18.5A4.5 4.5 0 0 1 16.5 18.5"),
                .d("M12 12V10M16.6 13.9L18 12.5M7.4 13.9L6 12.5"),
            ])
        case .weekend:
            // The calendar with its last two days marked.
            return GlyphDrawing(
                ink: [.rect(3.5, 5, 17, 15.5, 3), .d("M8 3V6.5M16 3V6.5M3.5 10H20.5")],
                fill: [.circle(12.3, 15.2, 1.5), .circle(16.2, 15.2, 1.5)])
        case .properties:
            return GlyphDrawing(
                ink: [.rect(3.5, 4.5, 17, 15, 3), .d("M7 9.5H11M7 14.5H11")],
                fill: [.circle(15.5, 9.5, 1.4), .circle(15.5, 14.5, 1.4)])
        // ---- not on the boards; the same hand ----
        case .filter:
            // A V and a stem: two open strokes, no enclosed wedge to fill
            // in at row size (owner, 2026-09-11: the closed funnel was "a
            // bit ugly").
            return GlyphDrawing(ink: [.d("M4 5.5L12 13.5L20 5.5M12 13.5V19.5")])
        case .everything:
            // The archive box: a lid, a body, one label line.
            return GlyphDrawing(ink: [
                .rect(3.5, 4, 17, 5, 2),
                .d("M5 9V17A3 3 0 0 0 8 20H16A3 3 0 0 0 19 17V9"),
                .d("M10 13H14"),
            ])
        case .work:
            // A case with a handle: the day's work carried in.
            return GlyphDrawing(ink: [
                .rect(3.5, 7.5, 17, 12.5, 3),
                .d("M9 7.5V6A1.5 1.5 0 0 1 10.5 4.5H13.5A1.5 1.5 0 0 1 15 6V7.5"),
                .d("M3.5 12.5H20.5"),
            ])
        case .health:
            // A pulse: one beat across the line.
            return GlyphDrawing(ink: [.d("M3 12.5H8L10.2 6.5L13.6 18L15.8 12.5H21")])
        case .money:
            // A note with its coin.
            return GlyphDrawing(ink: [.rect(3, 6.5, 18, 11, 3), .circle(12, 12, 2.8)])
        case .home:
            // A roof over a room.
            return GlyphDrawing(ink: [
                .d("M3.5 11.5L12 4.5L20.5 11.5"),
                .d("M5.5 10V16.5A3 3 0 0 0 8.5 19.5H15.5A3 3 0 0 0 18.5 16.5V10"),
            ])
        case .learning:
            // An open book: two leaves from one spine.
            return GlyphDrawing(ink: [
                .d("M12 7V20.5"),
                .d("M12 7A3 3 0 0 0 9 4H5.5A2 2 0 0 0 3.5 6V15.5A2 2 0 0 0 5.5 17.5H9A3 3 0 0 1 12 20.5"),
                .d("M12 7A3 3 0 0 1 15 4H18.5A2 2 0 0 1 20.5 6V15.5A2 2 0 0 1 18.5 17.5H15A3 3 0 0 0 12 20.5"),
            ])
        case .people:
            // Two, because the field is plural: a head and shoulders, and
            // a second head with one shoulder behind it.
            return GlyphDrawing(ink: [
                .circle(9, 8.8, 3.2),
                .d("M3 20V19.3A4 4 0 0 1 7 15.3H11A4 4 0 0 1 15 19.3V20"),
                .circle(17.2, 7.2, 2.4),
                .d("M17.5 13.2H18A3.5 3.5 0 0 1 21.5 16.7V18"),
            ])
        }
    }

    /// The page with its folded corner (the board's File), and one mark
    /// inside that says which kind of file it is. Sheets, slides and
    /// pictures are not paper, so they draw their own outline.
    private static func file(_ fileClass: FileFacts.Class) -> GlyphDrawing {
        let page: [GlyphDrawing.Mark] = [
            .d("M13.5 3.5H8A3 3 0 0 0 5 6.5V17.5A3 3 0 0 0 8 20.5H16A3 3 0 0 0 19 17.5V9Z"),
            .d("M13.5 3.5V9H19"),
        ]
        switch fileClass {
        case .other:
            return GlyphDrawing(ink: page)
        case .document:
            return GlyphDrawing(ink: page + [.d("M8.5 13H15.5M8.5 16.5H12.5")])
        case .text:
            return GlyphDrawing(ink: page + [.d("M8.5 12H15.5M8.5 14.75H15.5M8.5 17.5H12")])
        case .pdf:
            // The label block a PDF wears in every reader.
            return GlyphDrawing(ink: page, fill: [.rect(8, 14, 8, 3.5, 1.75)])
        case .sheet:
            return GlyphDrawing(ink: [
                .rect(4.5, 3.5, 15, 17, 3), .d("M4.5 9H19.5M4.5 14.5H19.5M12 3.5V20.5"),
            ])
        case .slides:
            return GlyphDrawing(ink: [.rect(3.5, 4.5, 17, 11.5, 3), .d("M12 16V19.5M8.5 19.5H15.5")])
        case .image:
            return GlyphDrawing(
                ink: [.rect(3.5, 4.5, 17, 15, 3), .d("M4.5 17.5L10.5 11.5L13.5 14.5L16 12L19.5 15.5")],
                fill: [.circle(8.8, 9.5, 1.6)])
        }
    }
}

/// One layer of a drawing, its grid scaled onto the square in the middle
/// of whatever frame it is handed — so one set of numbers serves every
/// size.
struct GlyphShape: Shape {
    let drawing: GlyphDrawing
    let layer: GlyphDrawing.Layer

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let scale = side / drawing.grid
        let place = CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2)
            .scaledBy(x: scale, y: scale)
        return (drawing.path(layer) ?? Path()).applying(place)
    }
}

// MARK: - the ways an icon appears

/// THE PANEL DOOR, drawn here rather than borrowed from SF Symbols
/// (owner, 2026-08-18: "a bit rounder. it looks like a desktop icon").
///
/// The symbol we had — `rectangle.leftthird.inset.filled` — is a WINDOW:
/// wide, squarish corners, the proportions of a Mac. This is the same
/// idea at a phone's proportions and a phone's radius: a nearly square
/// plate, generously rounded, with one rounded bar sitting inside its
/// left edge. Nothing else — no lines, no dots, no second bar.
/// The library door's glyph: a panel, with its leading column filled.
///
/// `open` WIDENS THE COLUMN instead of recolouring the whole mark. The
/// button used to turn `LivTheme.accent` when the panel was showing,
/// which the owner called amateur (2026-08-28) and which was also the
/// wrong idea: a tint says "selected", and this is not a selection — it
/// is a door that is currently standing open. Widening the column says
/// that in the drawing, at any size, in any theme, and to anyone who
/// cannot tell blue from grey.
struct PanelMark: View {
    let color: Color
    var open: Bool = false
    var size: CGFloat = 22

    var body: some View {
        let height = size * 0.88
        // 0.30 read as a squircle rather than as a panel (owner,
        // 2026-08-28: "make some icons, especially the panel button, a
        // bit less round"). A panel has corners; this keeps them.
        let radius = size * 0.20
        let line = max(1.4, size / 14)
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(color, lineWidth: line)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: radius * 0.5, style: .continuous)
                    .fill(color)
                    .frame(width: size * (open ? 0.42 : 0.20))
                    .padding(.vertical, size * 0.17)
                    .padding(.leading, size * 0.16)
            }
            .frame(width: size, height: height)
            // A MARK MOVING BETWEEN ITS STATES is `pick`'s whole job.
            // This was a raw `.easeInOut(duration: 0.18)`, the one
            // animation in the shell that named its own curve — which is
            // exactly the drift standing rule 3 exists to stop.
            .animation(LivMotion.pick, value: open)
            .accessibilityHidden(true)
    }
}

/// A glyph, in ONE ink. Two layers — ink, fill — the ink stroked with
/// `LivPen.stroke(size)`, the same drawn weight at every size, and
/// composited as one, so an ancestor's opacity (a dead bar key) dims the
/// icon without the layers showing through each other.
struct LivIcon: View {
    let glyph: LivGlyph
    let color: Color
    /// NO DEFAULT. It was `= 19`, a hand-typed second copy of a row
    /// token, and every call site passes `size:` anyway — so the number
    /// was never read and only stood there waiting to disagree with the
    /// token (standing rules 3 and 6).
    let size: CGFloat

    var body: some View {
        let drawing = glyph.drawing
        let pen = StrokeStyle(lineWidth: LivPen.stroke(size), lineCap: .round, lineJoin: .round)
        ZStack {
            GlyphShape(drawing: drawing, layer: .ink).stroke(color, style: pen)
            if !drawing.fill.isEmpty {
                GlyphShape(drawing: drawing, layer: .fill).fill(color)
            }
        }
        .frame(width: size, height: size)
        .overlay { words }
        .compositingGroup()
        .accessibilityHidden(true)  // the row's text carries the name
    }

    /// The two glyphs that carry TEXT: the tab count on the front sheet,
    /// and a workspace's letter. Sized off the glyph so they scale with it.
    @ViewBuilder private var words: some View {
        switch glyph {
        case .tabs(let n):
            // Monospaced so the bar does not twitch between 9 tabs and
            // 10; centred in the box, and shrinking to stay inside it.
            Text("\(n)")
                .font(.system(size: size * LivPen.count, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(LivPen.countFloor)
                .frame(width: size * LivPen.countBox)
        case .letter(let name):
            Text(LivGlyph.initial(of: name))
                .font(.system(size: (size * LivPen.letter).rounded(), weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
        default:
            EmptyView()
        }
    }
}

/// HOLD FOR MORE — the corner tick on a key whose hold opens a menu
/// (the bar's `+`). Always `text2`, whatever the key's ink: it is a hint
/// beside the glyph, not part of it. The caller places it: bottom
/// trailing of the glyph, `LivPen.tickOffset` out.
struct HoldTick: View {
    var body: some View {
        GlyphShape(drawing: .holdTick, layer: .fill)
            .fill(LivTheme.text2)
            .frame(width: LivPen.tick, height: LivPen.tick)
            .accessibilityHidden(true)
    }
}

// `IconChip` IS GONE (2026-08-31). It filled a rounded square with the
// kind's colour and carved the glyph out of it as a stencil — one per
// row in Files, Search and the minimised record pill, so a mixed list
// drew a column of saturated blocks. The references draw the glyph
// itself on no fill at all, which says the same thing with a fraction
// of the ink; that is exactly `LivIcon`, which this app already had.
// Two recipes for one mark is standing rule 4, and the three call sites
// pass `LivIcon` now.

// `PropertiesMark` IS GONE with it — three overlapping coloured rings,
// and `grep` finds no caller anywhere in the shell. Dead when the
// properties door became the ••• menu's first item (2026-08-29) and
// never removed; the polish audit found it still drawing itself in the
// source. When a decision makes code unnecessary, delete it in the same
// change (owner, 2026-08-07).

// MARK: - the contrast floor, measured

/// WCAG relative luminance, then the ratio. The palette is built to a
/// FLOOR (7:1, the Modus themes' bar, which the owner brought them here
/// for) and a floor nobody measures is a wish: the set this replaced had
/// six colours under it, including the accent behind every link and
/// button label at 4.95:1.
enum LivContrast {
    static func ratio(_ a: Color, _ b: Color, dark: Bool) -> Double {
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let la = luminance(UIColor(a).resolvedColor(with: traits))
        let lb = luminance(UIColor(b).resolvedColor(with: traits))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// How far apart two colours LOOK, 0…1 — a plain RGB distance.
    /// Contrast cannot answer this: two colours of the same lightness
    /// and opposite hue have a ratio of 1.0 and are obviously different,
    /// which is exactly the case a kind palette lives in.
    static func distance(_ a: Color, _ b: Color, dark: Bool) -> Double {
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        let x = UIColor(a).resolvedColor(with: traits)
        let y = UIColor(b).resolvedColor(with: traits)
        var xr: CGFloat = 0, xg: CGFloat = 0, xb: CGFloat = 0, xa: CGFloat = 0
        var yr: CGFloat = 0, yg: CGFloat = 0, yb: CGFloat = 0, ya: CGFloat = 0
        x.getRed(&xr, green: &xg, blue: &xb, alpha: &xa)
        y.getRed(&yr, green: &yg, blue: &yb, alpha: &ya)
        let d = pow(Double(xr - yr), 2) + pow(Double(xg - yg), 2) + pow(Double(xb - yb), 2)
        return (d / 3).squareRoot()
    }

    private static func luminance(_ color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        func c(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * c(r) + 0.7152 * c(g) + 0.0722 * c(b)
    }
}

/// Every colour a person reads, against the ground it is read on, in
/// BOTH schemes: `simctl launch … -palette.selfcheck 1`.
///
/// THE FLOOR WENT BACK UP ON 2026-08-30, as this comment promised it
/// would. From 2026-08-15 it was WCAG AA (4.5:1) because the palette was
/// the system's own semantic set, and Apple designs those to AA — so
/// holding them to the AAA 7:1 they do not claim would only have failed
/// on colours nobody here chose. The palette is ours again (the surface
/// pass), so the two tiers a person READS clear 7:1, and marks are held
/// to 3:1 against the ground for the first time.
func livPaletteSelfCheck() -> [String] {
    var fail: [String] = []
    // What a colour has to do decides what is asserted about it.
    //
    // INK is read: WCAG AA is 4.5:1, and the system's label colours are
    // designed to exactly that. (It was 7:1 until 2026-08-15, which the
    // app's own hand-mixed palette could reach; the palette is the
    // system's now — owner: "revert colors and faces to as system like
    // as possible" — and Apple does not claim AAA for it.)
    //
    // A MARK is not read, it is TOLD APART: a dot, a chip, a glyph's
    // tint. Two things are asserted about one: that no two kinds look
    // alike, and — since 2026-08-30 — that each is at least 3:1 against
    // the ground it sits on. That floor was not applied while the marks
    // were Apple's vivid set, which is 1.5–2.3:1 on white; ours are
    // chosen, so they can be held to it.
    // READ tiers clear AAA. `text3` is the dimmest tier and it is held
    // to AA instead:
    // pushing it to 7:1 would land it on top of `text2` and the app
    // would have two secondary greys and no tertiary one. The
    // references agree: Anytype draws its placeholders at about 3.4:1,
    // and this is stricter than that.
    let inkFloor = 7.0
    let dimFloor = 4.5
    // THE EXEMPTION IS SOUND; ITS STATED SCOPE IS NOT. This comment used
    // to say text3 is "a placeholder, a timestamp, the ✕ on a chip", and
    // that is the argument for holding it to AA rather than AAA. Measured
    // 2026-09-12, 16 of its Text sites are none of those: whole sentences
    // ("Showing N of M — narrow the search"; "The saved version is shown.
    // Your edit is kept."), file paths, and — the loudest one —
    // the properties card's labels, which drew EVERY property name at
    // strong(20) in this tier until the clearer boards (2026-09-24) moved
    // them to full ink at 18 with the value in text2.
    //
    // Nothing is changed here, because the fix is a visible one and it is
    // not a blanket swap: moving both halves of a label/value pair to
    // text2 leaves them equally undifferentiated, one step brighter. The
    // decision about which half comes forward is the owner's, and the
    // exemption stays exactly as it is until he makes it. What is fixed
    // is the sentence claiming the tier is only used for things it is not.

    let inks: [(String, Color, Double)] = [
        ("text", LivTheme.text, inkFloor), ("text2", LivTheme.text2, inkFloor),
        ("text3", LivTheme.text3, dimFloor),
    ]
    let marks: [(String, Color)] =
        [("accent", LivTheme.accent)] + LivKind.allCases.map { ($0.wire, $0.color) }
    for dark in [true, false] {
        let scheme = dark ? "dark" : "light"
        for (name, color, floor) in inks {
            let r = LivContrast.ratio(color, LivTheme.canvas, dark: dark)
            if r < floor {
                fail.append(
                    "\(scheme): \(name) is \(String(format: "%.2f", r)):1 on the canvas "
                        + "(floor \(String(format: "%.1f", floor)))")
            }
        }
        // A MARK against the ground. New on 2026-08-30 and the other
        // half of the promise above: a dot or a glyph tint you cannot
        // separate from the canvas is not quiet, it is missing.
        for (name, color) in marks {
            let r = LivContrast.ratio(color, LivTheme.canvas, dark: dark)
            if r < 3.0 {
                fail.append(
                    "\(scheme): the \(name) mark is \(String(format: "%.2f", r)):1 on the canvas")
            }
        }
        // Ink ON the tint — a filled button, a lit toggle. 3:1 is the
        // large-text and UI-component floor, and white-on-systemBlue is
        // Apple's own pairing at 3.5:1.
        let onAccent = LivContrast.ratio(LivTheme.onAccent, LivTheme.accent, dark: dark)
        if onAccent < 3.0 {
            fail.append("\(scheme): onAccent is \(String(format: "%.2f", onAccent)):1 on the accent")
        }
        // No two marks may look alike — including the chrome's tint,
        // because chrome and content saying the same word was the old
        // palette's flaw.
        // A file and a link share one colour ON PURPOSE — both are
        // something from outside the box — so that pair is not a clash.
        let oneFamily: Set<Set<String>> = [["file", "link"]]
        for i in marks.indices {
            for j in marks.indices where j > i {
                if oneFamily.contains([marks[i].0, marks[j].0]) { continue }
                let d = LivContrast.distance(marks[i].1, marks[j].1, dark: dark)
                if d < 0.12 {
                    fail.append(
                        "\(scheme): \(marks[i].0) and \(marks[j].0) look alike "
                            + "(\(String(format: "%.2f", d)))")
                }
            }
        }
    }
    return fail
}


// MARK: - the sheet (`simctl launch … -glyph.sheet 1`)

/// EVERY GLYPH, DRAWN, at the sizes the app uses them.
///
/// Mockup-first is the house rule for visible UI, and a glyph is the one
/// thing you cannot review in prose — "a folder with a lid" describes a
/// hundred drawings. This renders the set so a change can be looked at,
/// beside the Icons board, before it is wired into anything.
struct GlyphSheet: View {
    /// The Icons board's family row, in its order.
    private static let family: [(String, LivGlyph)] = [
        ("Today", .today), ("Unsorted", .inbox), ("Note", .note), ("Task", .task),
        ("Event", .event), ("Search", .search), ("Back", .back), ("Forward", .forward),
        ("Person", .person), ("Link", .link), ("File", .file(.other)), ("Scan", .scan),
        ("Trash", .trash), ("Settings", .settings),
    ]
    /// The board's cards: the marks it redrew with a reason.
    private static let cards: [(String, LivGlyph)] = [
        ("Personal", .letter("Personal")), ("All", .workspaces), ("Tabs", .tabs(4)),
        ("New", .new), ("Area", .area), ("Properties", .properties),
        ("Tonight", .tonight), ("Tomorrow", .tomorrow), ("Weekend", .weekend),
    ]
    private static let files: [(String, LivGlyph)] = [
        ("doc", .file(.document)), ("text", .file(.text)), ("pdf", .file(.pdf)),
        ("sheet", .file(.sheet)), ("slides", .file(.slides)), ("image", .file(.image)),
    ]
    /// Not on the board, drawn in its hand — and the two counts the tab
    /// key has to survive.
    private static let more: [(String, LivGlyph)] = [
        ("archive", .everything), ("filter", .filter), ("people", .people),
        ("18 tabs", .tabs(18)), ("128 tabs", .tabs(128)),
    ]
    /// THE MARKS AN AREA COULD WEAR, by what each one DRAWS.
    ///
    /// This was `LivArea.allCases`, labelled by the six area names the
    /// app shipped. It ships none (2026-09-21), so there is no area to
    /// name them after — but the drawings are still the drawings, and
    /// this sheet is the icon reference. They are kept for the day a
    /// person gets to choose a mark for an area they made.
    private static let areas: [(String, LivGlyph)] = [
        ("briefcase", .work), ("heart", .health), ("coin", .money),
        ("house", .home), ("book", .learning),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                block("The family", Self.family)
                block("Cards", Self.cards)
                block("Files", Self.files)
                block("In the same hand", Self.more)
                block("Marks an area could wear", Self.areas)
            }
            .padding(.horizontal, 20)
            .padding(.top, LivRow.topInset)
            .padding(.bottom, 40)
        }
        .background(LivTheme.canvas.ignoresSafeArea())
        // In the app's own scheme (dark unless set), which `RootView`
        // applies and this sheet, standing in for it, never reached.
        .onAppear { LivAppearance.current.applyToWindows() }
    }

    private func block(_ title: String, _ items: [(String, LivGlyph)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 16) {
                ForEach(items, id: \.0) { name, glyph in cell(name, glyph) }
            }
        }
    }

    /// One glyph at the board's sizes: 28 in `text` (its specimens), 22
    /// in `text2` (a list row, a menu) and 15 in `text2` (a chip, at the
    /// fine line) — a stroke that reads at one can close up at another.
    private func cell(_ name: String, _ glyph: LivGlyph) -> some View {
        VStack(spacing: 6) {
            LivIcon(glyph: glyph, color: LivTheme.text, size: 28)
                .overlay(alignment: .bottomTrailing) {
                    if glyph == .new {
                        HoldTick().offset(x: LivPen.tickOffset, y: LivPen.tickOffset)
                    }
                }
            HStack(spacing: 6) {
                LivIcon(glyph: glyph, color: LivTheme.text2, size: 22)
                LivIcon(glyph: glyph, color: LivTheme.text2, size: LivPen.chip)
            }
            Text(name)
                .font(.system(size: LivType.micro))
                .foregroundStyle(LivTheme.text3)
                .lineLimit(1)
        }
    }
}

// MARK: - self-check (`simctl launch … -glyph.selfcheck 1`)

/// The icon language has no test target to live in. This asserts what
/// actually matters: one answer per row, a drawing that parses and lands
/// inside its box, dots exactly where the board puts
/// them, and a parser that is as strict as it claims.
func livGlyphSelfCheck() -> [String] {
    var fail: [String] = []

    // A row named by a SMALL NUMBER, through `livSampleId`. This suite
    // is about kinds and glyphs; the id is only there to tell one
    // fixture from another, and `row(1, …)` says that where a 32-digit
    // hex id would bury it.
    func row(
        _ n: UInt64, kinds: [String]? = nil, status: String? = nil,
        cells: [CellRow]? = nil
    ) -> EntityRow {
        EntityRow(
            id: livSampleId(n), title: "t", kinds: kinds, status: status, cells: cells)
    }

    // 1. ONE classifier — colour and glyph never disagree.
    let cases: [(String, EntityRow, LivKind)] = [
        ("plain note", row(1, kinds: ["note"]), .note),
        ("task by kind", row(2, kinds: ["task"]), .task),
        // **A thing has ONE kind now.** The two cases here used to give a
        // row several — `["note","task"]` — because `core/` let a thing
        // be both, and the defect this type was built for was
        // `kinds.first` answering "note". The engine's `kind` is one
        // cell, so that row cannot exist and a test asserting it would be
        // testing a model nobody has.
        //
        // What survives is the rule that actually decides: a STATUS
        // makes a thing a task whatever it calls itself, and an event
        // outranks even that.
        ("task by status alone", row(4, kinds: ["note"], status: "To do"), .task),
        ("event beats a status", row(5, kinds: ["event"], status: "To do"), .event),
        ("person", row(6, kinds: ["person"]), .person),
        ("link", row(7, kinds: ["link"]), .link),
        ("nothing at all", row(8), .capture),
        (
            // A file is marked by a cell of KIND "file" (FileFacts.of),
            // not by a property name — the first draft of this test got
            // that wrong and the check caught it.
            "file beats everything",
            row(
                10, kinds: ["note"],
                cells: [CellRow(property: "file", kind: "file", value: "/tmp/a.pdf")]),
            .file
        ),
    ]
    for (name, r, want) in cases {
        let got = LivKind.of(r)
        if got != want { fail.append("\(name): kind \(got) ≠ \(want)") }
        if LivKind.color(of: r) != want.color { fail.append("\(name): colour ≠ kind's") }
        if LivKind.glyph(of: r) != want.glyph(r) { fail.append("\(name): glyph ≠ kind's") }
    }

    // 2. Every kind has its own colour and its own glyph.
    var seen: [LivGlyph] = []
    for kind in LivKind.allCases {
        let g = kind.glyph(nil)
        if seen.contains(g) { fail.append("\(kind.wire): shares a glyph") }
        seen.append(g)
        if LivKind.named(kind.wire) != kind { fail.append("\(kind.wire): name round trip") }
    }

    // 3. Every drawing parses, has ink, and lands inside its box — all
    //    three layers of it. A glyph that overflows would be clipped by
    //    its chip; one that is empty is a case someone forgot to draw.
    //    `.letter` is Text and has no path, so it is checked in 4.
    let fileClasses: [FileFacts.Class] = [
        .document, .sheet, .slides, .pdf, .image, .text, .other,
    ]
    let drawn: [LivGlyph] =
        [
            .note, .task, .event, .person, .link, .capture,
            .today, .inbox, .calendar, .tasks, .everything,
            .work, .health, .money, .home, .learning, .area, .people,
            .filter, .settings, .workspaces, .trash, .properties,
            .back, .forward, .search, .new, .scan, .check, .plus,
            .tonight, .tomorrow, .weekend,
            // The count is Text in the box, not part of the path, so one
            // count stands for all of them.
            .tabs(0),
        ] + fileClasses.map { LivGlyph.file($0) }
    // THE DOT, where the board puts one (and the PDF's label bar).
    // Asserted both ways: a dot that goes missing and a dot that turns up
    // where none is drawn both fail. All workspaces is dots and nothing
    // else.
    let dotted: [LivGlyph] = [
        .note, .event, .calendar, .inbox, .capture, .today, .properties, .workspaces, .weekend,
        .file(.image), .file(.pdf),
    ]
    let dotsOnly: [LivGlyph] = [.workspaces]
    for glyph in drawn {
        let drawing = glyph.drawing
        var all = Path()
        for layer in GlyphDrawing.Layer.allCases {
            guard let path = drawing.path(layer) else {
                fail.append("\(glyph): its \(layer) layer breaks the path grammar")
                continue
            }
            all.addPath(path)
        }
        if drawing.ink.isEmpty != dotsOnly.contains(glyph) {
            fail.append("\(glyph): \(drawing.ink.isEmpty ? "draws nothing" : "draws strokes the board does not")")
        }
        if drawing.fill.isEmpty == dotted.contains(glyph) {
            fail.append("\(glyph): \(drawing.fill.isEmpty ? "lost its dot" : "has a dot the board does not")")
        }
        // 1pt of slack: a stroke sits half outside its own path.
        let b = all.cgPath.boundingBoxOfPath
        if !all.isEmpty, b.minX < -1 || b.minY < -1 || b.maxX > 25 || b.maxY > 25 {
            fail.append("\(glyph): \(b) leaves the box")
        }
    }
    if GlyphDrawing.holdTick.path(.fill)?.isEmpty != false {
        fail.append("hold tick: does not parse, or draws nothing")
    }

    // 4. A workspace's letter: Text, never a path, from the name's first
    //    grapheme past any leading space.
    let letter = LivGlyph.letter("Personal").drawing
    if !(letter.ink.isEmpty && letter.fill.isEmpty) {
        fail.append("letter: draws a path; it is Text")
    }
    for (name, want) in [("personal", "P"), ("  work", "W"), ("", "")] {
        let got = LivGlyph.initial(of: name)
        if got != want { fail.append("letter of \"\(name)\": \(got) ≠ \(want)") }
    }

    // 5. The parser: an arc lands where a browser draws it, and anything
    //    outside the grammar fails rather than drawing something nearby.
    //    The link's upper arc asks for r 3.8 across a 4.6 half-chord, so
    //    it must GROW to a semicircle about (16.05, 7.95) and bulge up and
    //    right (sweep 1). A flipped sweep bulges down-left; an ungrown
    //    radius misses both edges.
    if let arc = GlyphPath.parse("M12.8 4.7A3.8 3.8 0 0 1 19.3 11.2") {
        let b = arc.cgPath.boundingBoxOfPath
        if abs(b.maxX - 20.646) > 0.05 || abs(b.minY - 3.354) > 0.05 {
            fail.append("arc: the link's semicircle lands at \(b)")
        }
    } else {
        fail.append("arc: the link's semicircle does not parse")
    }
    for bad in [
        "L1 2", "M1 2L3", "M1 2l3 4", "M1 2L3 4 5 6", "M1 2Q3 4 5 6",
        "M1 2A3 4 0 0 1 5 6", "M1 2A3 3 30 0 1 5 6", "M1 2A3 3 0 2 1 5 6",
    ] where GlyphPath.parse(bad) != nil {
        fail.append("parser accepts \"\(bad)\"")
    }

    return fail
}
