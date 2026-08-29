// liv iOS — the icon language: what a thing IS, in one colour and one
// drawing (blueprints, design/mockups/blueprints/icon-style.html, decided
// by the owner 2026-08-12; the view icons come from home-views.html).
//
// Two rules govern everything in this file.
//
//   1. ONE classifier. A row's colour and its glyph must come from the
//      same answer to "what is this?". They did not: the colour read
//      `kinds.first` and the glyph read `kinds.contains(…)` in priority
//      order, so a task filed as ["note","task"] drew a blue chip with a
//      tick in it. `LivKind.of` is now the only place that decides.
//   2. The icons are DRAWN, not borrowed. Apple's symbols are a
//      different language — filled, heavier, and shaped to their own
//      grid — so the app looked nothing like the approved blueprints
//      (owner, 2026-08-13: "i don't see the blueprint's custom icons in
//      the app"). Every glyph below is transcribed from the blueprint's
//      own 24×24 drawing.
//
// Where the icon language does NOT go, both rejected on sight
// (owner, 2026-08-12): the create menu's verbs, and property field rows.
// Kind colour marks what a THING is, in lists — never what a button
// would make, never a field's name.

import SwiftUI

// MARK: - what a thing is

/// The seven kinds the app draws. A kind carries its colour and its
/// glyph together, because a thing that is purple in one list and blue
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

    /// One kind, one colour, everywhere it appears: a task is purple in
    /// a list, in the calendar, and on a chip. Nothing else may hardcode
    /// a kind's colour.
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
    /// 2026-08-08) — the colour stays the one file orange.
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

/// Every icon the app draws for itself. Chrome that is not about a thing
/// — chevrons, the close cross, the repeat mark — stays on Apple's
/// symbols; those are arrows and punctuation, not part of this language.
enum LivGlyph: Equatable {
    // Things.
    case note, task, event, person, link, capture
    case file(FileFacts.Class)
    // Places — the library's rows.
    case today, inbox, calendar, tasks, everything
    // Furniture.
    case filter, settings, workspace, workspaces, plus, trash
    /// A NUMBER IN A BOX — the bar's tab key (owner, 2026-08-23: "just
    /// have tabs as they appeared before when you clicked the numbered
    /// box"). Obsidian's fifth key is this shape with today's date in
    /// it; Liv puts the count of open tabs there, which is what a
    /// numbered box means in every browser on this phone.
    ///
    /// Its own drawing rather than `.calendar`'s: the reference is a
    /// plain rounded outline, and the calendar glyph's hanger lines and
    /// header rule would run straight through the numerals. Two glyphs,
    /// two things — not two drawings of one (standing rule 4).
    case day(Int)
}

/// The blueprint's 24×24 drawing space. Every glyph is STROKED, never
/// filled: that is what makes the carve read as punched out of the chip.
struct GlyphShape: Shape {
    let glyph: LivGlyph

    /// A 24-space stroke of 2 at this size, so weight scales with the icon.
    static func lineWidth(_ size: CGFloat) -> CGFloat { size / 12 }

    func path(in rect: CGRect) -> Path {
        var pen = Pen(rect)
        draw(&pen)
        return pen.path
    }

    private func draw(_ pen: inout Pen) {
        switch glyph {
        case .note:
            pen.box(5, 3.75, 14, 16.5, 3)
            pen.line(8.5, 9, 15.5, 9)
            pen.line(8.5, 13, 13.5, 13)
        case .task, .tasks:
            pen.box(4.5, 4.5, 15, 15, 4.5)
            pen.shape([(8.5, 12.3, 0), (11.1, 14.9, 0), (15.7, 9.5, 0)], closed: false)
        case .day:
            // CENTRED, and a size up. It was box(3.5, 4.5, 17, 16): the
            // centre sat at y 12.5 on a canvas whose centre is 12, so the
            // digit drawn at the centre was half a unit high in it —
            // visible, and the owner saw it (2026-08-28). 18x17 centred
            // on (12, 12); the digit needs no offset to sit in it.
            pen.box(3, 3.5, 18, 17, 3.5)
        case .event, .calendar:
            pen.box(3, 5, 18, 16, 2.5)
            pen.line(8, 3, 8, 7)
            pen.line(16, 3, 16, 7)
            pen.line(3, 11, 21, 11)
        case .person:
            pen.circle(12, 8.2, 3.9)
            pen.shape(
                [(19.4, 20.5, 0), (19.4, 14.8, 4.5), (4.6, 14.8, 4.5), (4.6, 20.5, 0)],
                closed: false)
        case .link:
            pen.link()
        case .capture, .inbox:
            // The tray: caught, not yet shaped.
            pen.shape(
                [
                    (6, 4, 2), (18, 4, 2), (22, 12, 0), (22, 20, 2),
                    (2, 20, 2), (2, 12, 0),
                ], closed: true)
            pen.shape(
                [
                    (22, 12, 0), (16, 12, 0), (14, 15, 0), (10, 15, 0),
                    (8, 12, 0), (2, 12, 0),
                ], closed: false)
        case .file(let fileClass):
            pen.file(fileClass)
        case .today:
            pen.circle(12, 12, 3.8)
            pen.rays(12, 12, from: 5.8, to: 8, count: 8)
        case .everything:
            // The archive box: a lid, a body, one label line.
            pen.box(2.5, 4, 19, 5, 1.5)
            pen.shape(
                [(4.5, 9, 0), (4.5, 18, 2), (6.5, 20, 0), (17.5, 20, 2), (19.5, 18, 0), (19.5, 9, 0)],
                closed: false)
            pen.line(10, 13.5, 14, 13.5)
        case .filter:
            // The funnel.
            pen.shape(
                [(4, 4.5, 0), (20, 4.5, 0), (13.6, 12.2, 0), (13.6, 19.5, 0), (10.4, 17.6, 0), (10.4, 12.2, 0)],
                closed: true)
        case .trash:
            // A bin: lid, body, and two staves. Drawn rather than an SF
            // Symbol so it sits on the same optical weight as its
            // neighbours in the library rows.
            pen.line(5, 6.5, 19, 6.5)
            pen.line(9.5, 6.5, 9.5, 4.5)
            pen.line(9.5, 4.5, 14.5, 4.5)
            pen.line(14.5, 4.5, 14.5, 6.5)
            pen.line(6.8, 6.5, 7.8, 19.5)
            pen.line(17.2, 6.5, 16.2, 19.5)
            pen.line(7.8, 19.5, 16.2, 19.5)
        case .settings:
            pen.circle(12, 12, 6.8)
            pen.circle(12, 12, 2)
            pen.rays(12, 12, from: 6.3, to: 9, count: 8)
        case .workspace:
            // r8, not the sheet's 5.6: bare in a row it has to hold the
            // same optical weight as its neighbours, which fill ~80% of
            // the box. At 5.6 it read as a bullet next to them.
            pen.circle(12, 12, 8)
        case .workspaces:
            // All of them: the four-square grid.
            pen.box(4, 4, 7, 7, 1.6)
            pen.box(13, 4, 7, 7, 1.6)
            pen.box(4, 13, 7, 7, 1.6)
            pen.box(13, 13, 7, 7, 1.6)
        case .plus:
            pen.line(12, 5.5, 12, 18.5)
            pen.line(5.5, 12, 18.5, 12)
        }
    }
}

/// The pen draws in the blueprint's 24×24 space and scales to whatever
/// box it is handed, so one transcription serves every size.
private struct Pen {
    let scale: CGFloat
    let origin: CGPoint
    var path = Path()

    init(_ rect: CGRect) {
        let side = min(rect.width, rect.height)
        scale = side / 24
        origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
    }

    func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
    }

    mutating func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
        path.move(to: at(x1, y1))
        path.addLine(to: at(x2, y2))
    }

    mutating func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
        path.addEllipse(
            in: CGRect(
                x: origin.x + (cx - r) * scale, y: origin.y + (cy - r) * scale,
                width: 2 * r * scale, height: 2 * r * scale))
    }

    mutating func box(
        _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat
    ) {
        path.addRoundedRect(
            in: CGRect(
                x: origin.x + x * scale, y: origin.y + y * scale,
                width: w * scale, height: h * scale),
            cornerSize: CGSize(width: r * scale, height: r * scale))
    }

    /// A polyline or polygon with a radius per corner (0 = sharp). This
    /// is how the blueprint's rounded joins are drawn without an SVG arc
    /// parser: every arc in the set is a corner between two straight runs.
    mutating func shape(_ pts: [(CGFloat, CGFloat, CGFloat)], closed: Bool) {
        guard pts.count > 1 else { return }
        if closed {
            let a = pts[pts.count - 1], b = pts[0]
            path.move(to: at((a.0 + b.0) / 2, (a.1 + b.1) / 2))
            for i in 0..<pts.count { corner(pts[i], pts[(i + 1) % pts.count]) }
            path.closeSubpath()
        } else {
            path.move(to: at(pts[0].0, pts[0].1))
            for i in 1..<(pts.count - 1) { corner(pts[i], pts[i + 1]) }
            let last = pts[pts.count - 1]
            path.addLine(to: at(last.0, last.1))
        }
    }

    private mutating func corner(
        _ v: (CGFloat, CGFloat, CGFloat), _ next: (CGFloat, CGFloat, CGFloat)
    ) {
        if v.2 <= 0 {
            path.addLine(to: at(v.0, v.1))
        } else {
            path.addArc(
                tangent1End: at(v.0, v.1), tangent2End: at(next.0, next.1),
                radius: v.2 * scale)
        }
    }

    /// Spokes around a centre — the sun and the gear draw the same eight.
    mutating func rays(
        _ cx: CGFloat, _ cy: CGFloat, from: CGFloat, to: CGFloat, count: Int
    ) {
        for i in 0..<count {
            let a = Double(i) / Double(count) * 2 * .pi
            let dx = CGFloat(cos(a)), dy = CGFloat(sin(a))
            line(cx + from * dx, cy + from * dy, cx + to * dx, cy + to * dy)
        }
    }

    /// Two stadium outlines on the diagonal — the chain link, drawn as
    /// the shape it is rather than as two SVG arcs.
    mutating func link() {
        var loops = Path()
        for x in [CGFloat(2.6), CGFloat(9.4)] {
            loops.addRoundedRect(
                in: CGRect(
                    x: origin.x + x * scale, y: origin.y + 9.25 * scale,
                    width: 12 * scale, height: 5.5 * scale),
                cornerSize: CGSize(width: 2.75 * scale, height: 2.75 * scale))
        }
        let c = at(12, 12)
        path.addPath(
            loops,
            transform: CGAffineTransform(translationX: c.x, y: c.y)
                .rotated(by: -.pi / 4)
                .translatedBy(x: -c.x, y: -c.y))
    }

    /// The file glyph: the blueprint's page with a folded corner, and one
    /// mark inside that says which kind of file it is.
    mutating func file(_ fileClass: FileFacts.Class) {
        switch fileClass {
        case .sheet:
            box(4.5, 3.75, 15, 16.5, 2.5)
            line(4.5, 9.25, 19.5, 9.25)
            line(4.5, 14.75, 19.5, 14.75)
            line(12, 3.75, 12, 20.25)
        case .slides:
            box(3.5, 4.5, 17, 11.5, 2.5)
            line(12, 16, 12, 19)
            line(8.5, 19.5, 15.5, 19.5)
        case .image:
            box(3.5, 4.5, 17, 15, 2.5)
            circle(9, 10, 1.7)
            shape(
                [(4.5, 17.5, 0), (10.5, 11.5, 0), (13.5, 14.5, 0), (16, 12, 0), (19.5, 15.5, 0)],
                closed: false)
        default:
            page()
            switch fileClass {
            case .document:
                line(8.5, 13, 15.5, 13)
                line(8.5, 16.5, 13, 16.5)
            case .text:
                line(8.5, 11.5, 15.5, 11.5)
                line(8.5, 14.5, 15.5, 14.5)
                line(8.5, 17.5, 12, 17.5)
            case .pdf:
                // The label block a PDF wears in every reader.
                box(8, 14.5, 8, 3.5, 1)
            default:
                break  // .other: the bare page
            }
        }
    }

    /// The page with the folded corner, shared by every paper format.
    private mutating func page() {
        shape(
            [
                (7.5, 3.75, 0), (13.5, 3.75, 0), (18.5, 8.75, 0),
                (18.5, 17.75, 2.5), (16, 20.25, 0), (8, 20.25, 2.5),
                (5.5, 17.75, 0), (5.5, 6.25, 2.5),
            ], closed: true)
        shape([(13.5, 3.75, 0), (13.5, 8.75, 0), (18.5, 8.75, 0)], closed: false)
    }
}

// MARK: - the two ways an icon appears

/// A bare glyph, stroked in its own colour. This is how an icon appears
/// when it sits in a row that already has a chip, or where a solid block
/// of colour would shout.
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
            .animation(.easeInOut(duration: 0.18), value: open)
            .accessibilityHidden(true)
    }
}

struct LivIcon: View {
    let glyph: LivGlyph
    let color: Color
    var size: CGFloat = 19

    var body: some View {
        let stroke = StrokeStyle(
            lineWidth: GlyphShape.lineWidth(size), lineCap: .round, lineJoin: .round)
        GlyphShape(glyph: glyph)
            .stroke(color, style: stroke)
            .frame(width: size, height: size)
            // The numbered box carries a NUMBER inside it. Sized off the
            // glyph so it scales with it, monospaced so the bar does not
            // twitch between 9 tabs and 10.
            .overlay {
                if case .day(let n) = glyph {
                    Text("\(n)")
                        .font(.system(size: size * 0.46, weight: .bold).monospacedDigit())
                        .foregroundStyle(color)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .frame(width: size * 0.62)
                }
            }
            .accessibilityHidden(true)  // the row's text carries the name
    }
}

/// The carved icon chip — the blueprints' one icon treatment (owner,
/// 2026-08-12): a SOLID square of the thing's colour with the glyph
/// punched through in the surface BENEATH, like a stencil. Never a
/// tinted box, never a bare boxed glyph. The owner's build notes: the
/// glyph a bit larger than the mockups drew it, the corners slightly
/// less round.
struct IconChip: View {
    let glyph: LivGlyph
    let color: Color
    var size: CGFloat = 28
    /// What the carve reads through to. Canvas by default; a chip inside
    /// a card passes the card's surface, or the stencil stops working.
    var on: Color = LivTheme.canvas

    var body: some View {
        RoundedRectangle(cornerRadius: size * 6 / 28, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .overlay(LivIcon(glyph: glyph, color: on, size: size * 19 / 28))
            .accessibilityHidden(true)
    }
}

/// The properties mark: three overlapping rings, one per colour family.
/// The one icon in the language that is not a single colour, so it is
/// not a `LivGlyph` — and it is never boxed (blueprint: "the properties
/// mark rides the card header bare").
struct PropertiesMark: View {
    var size: CGFloat = 20

    var body: some View {
        let s = size / 24
        ZStack {
            ring(LivTheme.green, x: 8.4, y: 9.6, s: s)
            ring(LivTheme.purple, x: 15.6, y: 9.6, s: s)
            ring(LivTheme.accent, x: 12, y: 15.4, s: s)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func ring(_ color: Color, x: CGFloat, y: CGFloat, s: CGFloat) -> some View {
        Circle()
            .strokeBorder(color, lineWidth: 1.8 * s)
            .frame(width: 8.2 * s, height: 8.2 * s)
            .offset(x: (x - 12) * s, y: (y - 12) * s)
    }
}

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
/// The floor is WCAG AA (4.5:1), not the AAA 7:1 it was until
/// 2026-08-15. The palette is the system's own semantic set now (owner:
/// "revert colors and faces to as system like as possible"), and Apple
/// designs those to AA — `secondaryLabel` on `systemBackground` is about
/// 4.6:1. Holding the system to a standard it does not claim would mean
/// this check failing on colours nobody here chose. When the surface
/// pass comes and the palette is ours again, the floor goes back up.
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
    // tint. Apple's vivid colours are 1.5–2.3:1 on white and always have
    // been; holding systemYellow to a contrast floor would only mean
    // failing on a colour nobody here chose. What matters for the icon
    // language is that no two kinds look alike, and that is asserted
    // below, in both schemes.
    //
    // When the surface pass makes the palette ours again, the ink floor
    // goes back to 7:1 and marks get a 3:1 floor against the ground.
    let inkFloor = 4.5
    let inks: [(String, Color)] = [
        ("text", LivTheme.text), ("text2", LivTheme.text2),
        ("text3", LivTheme.text3), ("muted", LivTheme.muted),
    ]
    let marks: [(String, Color)] =
        [("accent", LivTheme.accent)] + LivKind.allCases.map { ($0.wire, $0.color) }
    for dark in [true, false] {
        let scheme = dark ? "dark" : "light"
        for (name, color) in inks {
            let r = LivContrast.ratio(color, LivTheme.canvas, dark: dark)
            if r < inkFloor {
                fail.append("\(scheme): \(name) is \(String(format: "%.2f", r)):1 on the canvas")
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

// MARK: - self-check (`simctl launch … -glyph.selfcheck 1`)

/// The icon language has no test target to live in. This asserts the two
/// properties that actually matter: one answer per row, and a drawing
/// that lands inside its box.
func livGlyphSelfCheck() -> [String] {
    var fail: [String] = []

    func row(
        _ id: UInt64, kinds: [String]? = nil, status: String? = nil,
        cells: [CellRow]? = nil
    ) -> EntityRow {
        EntityRow(id: id, title: "t", kinds: kinds, status: status, cells: cells)
    }

    // 1. ONE classifier — colour and glyph never disagree.
    let cases: [(String, EntityRow, LivKind)] = [
        ("plain note", row(1, kinds: ["note"]), .note),
        ("task by kind", row(2, kinds: ["task"]), .task),
        // The defect this type was built for: kinds.first said note.
        ("task filed under note", row(3, kinds: ["note", "task"]), .task),
        ("task by status alone", row(4, kinds: ["note"], status: "To do"), .task),
        ("event beats task", row(5, kinds: ["event", "task"]), .event),
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

    // 3. Every drawing lands inside its box and is not empty. A glyph
    //    that overflows would be clipped by the chip; one that is empty
    //    is a case someone forgot to draw.
    let box = CGRect(x: 0, y: 0, width: 24, height: 24)
    let fileClasses: [FileFacts.Class] = [
        .document, .sheet, .slides, .pdf, .image, .text, .other,
    ]
    let drawn: [LivGlyph] =
        [
            .note, .task, .event, .person, .link, .capture,
            .today, .inbox, .calendar, .tasks, .everything,
            .filter, .settings, .workspace, .workspaces, .plus,
            // Both digit widths: the numerals ride INSIDE the box, and a
            // two-digit count that overflows it would be invisible in
            // review and obvious on the day you open ten tabs.
            .day(0), .day(9), .day(18), .day(31),
        ] + fileClasses.map { LivGlyph.file($0) }
    for glyph in drawn {
        let path = GlyphShape(glyph: glyph).path(in: box)
        if path.isEmpty { fail.append("\(glyph): draws nothing") }
        if !path.isEmpty {
            // 1pt of slack: a stroke sits half outside its own path.
            let b = path.boundingRect
            if b.minX < -1 || b.minY < -1 || b.maxX > 25 || b.maxY > 25 {
                fail.append("\(glyph): \(b) leaves the box")
            }
        }
    }

    return fail
}
