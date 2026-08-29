// liv iOS — what a tab holds in a view that is not Notes.
//
// Reading B (design/tabs.md, team 2026-08-22): each view owns a tab
// strip, and a tab is a saved POSITION inside that view. In Notes that
// position is a document — which is what a tab always was. Everywhere
// else it is a place in the view: a slice, a filter, a month.
//
// WHY THIS FILE EXISTS. Three surfaces have to turn a saved position into
// words — the card in the switcher grid, the field that filters that
// grid, and the accessibility label — and a fourth (the view itself) has
// to turn it back into state. Four copies of one grammar is precisely the
// defect standing rule 4 names, so the grammar is here, once, and the
// views read it.
//
// A TOKEN IS ON DISK. `raw` values below are written into UserDefaults
// the moment a user parks a tab. Never re-mean one; add a new case and
// leave the old one readable.

import SwiftUI

/// Everything's slice. Lives here rather than in `Everything.swift`
/// because the slice is now the tab's content, and content is the plane's
/// vocabulary, not the view's private state.
enum EverythingLens: String, CaseIterable, Identifiable {
    case all, upcoming, unfiled
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All"
        case .upcoming: return "Upcoming"
        case .unfiled: return "Unfiled"
        }
    }
}

/// Route or Tidy — the blueprint's two questions (BP-5).
enum InboxLens: String, CaseIterable {
    case route, tidy

    var title: String {
        switch self {
        case .route: return "Route"
        case .tidy: return "Tidy"
        }
    }
}

/// Where you are in Tasks: which chip is on, and which completes-groups
/// you have unfolded.
///
/// **JSON, not a hand-rolled token.** A position with more than one field
/// needs an encoding, and `"status:To do|Done,Archived"` needs escaping
/// rules the moment a status is called "To do: later". One `Codable` is
/// one grammar with one parser (standing rule 4) and no escaping at all.
struct TasksPosition: Codable, Equatable {
    enum Filter: Codable, Equatable {
        case all
        case status(String)
        case project(String)
    }

    var filter: Filter = .all
    /// Sorted, always — so the same position produces the same token and
    /// a re-park with nothing changed is not mistaken for a move.
    var expanded: [String] = []

    init(filter: Filter = .all, expanded: Set<String> = []) {
        self.filter = filter
        self.expanded = expanded.sorted()
    }

    /// A token this build cannot read is not an error: it is an older or
    /// newer position, and the honest answer is the view's own root.
    init(token: String?) {
        guard let data = token?.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(TasksPosition.self, from: data)
        else {
            self = TasksPosition()
            return
        }
        self = decoded
    }

    /// **`.sortedKeys` is not tidiness — it is the format.** Without it
    /// Swift's per-process dictionary ordering encodes the same position
    /// to different bytes on different launches, so a token read back
    /// from disk never equals a freshly built one and `park` sees a move
    /// where nothing moved. One position, one spelling.
    var token: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    var title: String {
        switch filter {
        case .all: return "All tasks"
        case .status(let s): return s
        case .project(let p): return p
        }
    }
}

/// Where you are in Today: which day, and which two piles are open.
///
/// **A day, not "today".** A Today tab is a day you parked on — that is
/// what makes it a position rather than a bookmark. Nothing here has to
/// worry about the day going stale: `Today.loadWindow` has always snapped
/// a selection behind today forward, because the strip starts at today
/// and a selection behind it would be invisible.
struct TodayPosition: Codable, Equatable {
    var day: Int64 = Civil.todayDay()
    var doneExpanded: Bool = false
    /// nil = nobody has said, so the count decides.
    var lateOpen: Bool?

    init(day: Int64 = Civil.todayDay(), doneExpanded: Bool = false, lateOpen: Bool? = nil) {
        self.day = day
        self.doneExpanded = doneExpanded
        self.lateOpen = lateOpen
    }

    init(token: String?) {
        guard let data = token?.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(TodayPosition.self, from: data)
        else {
            self = TodayPosition()
            return
        }
        self = decoded
    }

    var token: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    var title: String {
        day == Civil.todayDay() ? "Today" : Civil.dayLabel(day)
    }
}

/// Where you are in the Calendar: the month on screen and the day
/// selected in it.
///
/// **Only these two.** The other eight `@State` fields on that screen are
/// a block in the air, a bin's frame, a page request, a learned width —
/// live interaction and layout, none of it a place you could return to.
struct CalendarPosition: Codable, Equatable {
    var month: Int64 = CalGrid.firstOfMonth(Civil.todayDay())
    var day: Int64 = Civil.todayDay()

    init(month: Int64? = nil, day: Int64? = nil) {
        self.month = month ?? CalGrid.firstOfMonth(Civil.todayDay())
        self.day = day ?? Civil.todayDay()
    }

    init(token: String?) {
        guard let data = token?.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(CalendarPosition.self, from: data)
        else {
            self = CalendarPosition()
            return
        }
        self = decoded
    }

    var token: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    var title: String { CalGrid.title(month) }
}

/// Turning a saved position into words, and back.
enum LivPosition {
    /// Where a view opens when its plane has no tab yet.
    ///
    /// A plane is born EMPTY — the same as Notes, where no tabs has
    /// always meant "you are looking at the list". The first time the
    /// user moves, the move mints the tab.
    static func root(_ feature: Feature) -> String {
        switch feature {
        case .everything: return EverythingLens.all.rawValue
        case .inbox: return InboxLens.route.rawValue
        case .tasks: return TasksPosition().token
        case .today: return TodayPosition().token
        case .calendar: return CalendarPosition().token
        /// Notes is the one view where a tab holds an ENTITY, not a
        /// position — which is what a tab always was, and what "how tabs
        /// looked for notes before" names.
        case .notes: return ""
        }
    }

    /// One line about what this position shows, for the card's preview.
    /// A position has no cells to list, so without this the card would be
    /// a title over dead space.
    static func detail(_ feature: Feature, _ token: String) -> String {
        switch feature {
        case .everything:
            switch EverythingLens(rawValue: token) {
            case .all: return "Everything in the box, newest first."
            case .upcoming: return "Dated in the next seven days."
            case .unfiled: return "No area yet."
            case nil: return "A saved place in Everything."
            }
        case .inbox:
            switch InboxLens(rawValue: token) {
            case .route: return "Captures still waiting for an address."
            case .tidy: return "What the clerk is proposing."
            case nil: return "A saved place in the Inbox."
            }
        case .tasks:
            let pos = TasksPosition(token: token)
            let groups = pos.expanded.isEmpty
                ? "" : "\n\(pos.expanded.count) group\(pos.expanded.count == 1 ? "" : "s") open."
            switch pos.filter {
            case .all: return "Every task in the box.\(groups)"
            case .status(let s): return "Tasks whose status is \(s).\(groups)"
            case .project(let p): return "Tasks on \(p).\(groups)"
            }
        case .today:
            let pos = TodayPosition(token: token)
            return pos.day == Civil.todayDay()
                ? "The plan for today." : "The plan for \(Civil.dayLabel(pos.day))."
        case .calendar:
            let pos = CalendarPosition(token: token)
            return pos.day == Civil.todayDay()
                ? "\(CalGrid.title(pos.month)), on today."
                : "\(CalGrid.title(pos.month)), on \(Civil.dayLabel(pos.day))."
        case .notes:
            return "A saved place in Notes."
        }
    }

    /// What to call this position on a card.
    ///
    /// **A token this view does not recognise falls back to the view's
    /// own name**, never to a crash or a blank. Saved planes outlive the
    /// code that wrote them, and a card that says "Everything" for a
    /// token retired two versions ago is honest enough to tap.
    static func title(_ feature: Feature, _ token: String) -> String {
        switch feature {
        case .everything:
            return EverythingLens(rawValue: token)?.title ?? feature.title
        case .inbox:
            return InboxLens(rawValue: token)?.title ?? feature.title
        case .tasks:
            return TasksPosition(token: token).title
        case .today:
            return TodayPosition(token: token).title
        case .calendar:
            return CalendarPosition(token: token).title
        case .notes:
            return feature.title
        }
    }
}

// MARK: - the self-check: one plane per view

/// `-planes.selfcheck 1`. Phase 4 of `design/tabs.md`: each view owns a
/// tab strip, and a tab is a saved position inside it.
///
/// **It runs against a sentinel workspace**, never the one you are using.
/// Every verb here writes through to UserDefaults, so a suite on
/// workspace 0 would quietly rearrange the tabs of whoever ran it.
func livPlanesSelfCheck() -> [String] {
    var failures: [String] = []
    func check(_ label: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
        if !ok { failures.append("FAIL \(label) \(detail())") }
    }

    let desk = DeskModel.scratchForSelfCheck()
    desk.shapeOf = { _ in .document }

    // ---- a tool remembers ONE spot ----
    //
    // This is the whole of the 2026-08-28 change. Parking used to MINT A
    // TAB, so a view you had merely scrolled ended up with two of
    // itself, and then three: the switcher over Today really did show
    // "Today, Today, Wed 26 Aug". A place is singular; what it needs
    // remembered is where you left it.
    desk.go(.everything)
    check("an untouched tool has no spot", desk.position(.everything) == nil)
    check("so it falls back to its root", LivPosition.root(.everything) == "all")

    desk.park(.everything, at: "upcoming")
    check("parking remembers the spot", desk.position(.everything) == "upcoming")
    check("and mints NO tab", desk.tabs.isEmpty, "\(desk.tabs.count)")

    desk.park(.everything, at: "unfiled")
    desk.park(.everything, at: "all")
    check("parking again overwrites", desk.position(.everything) == "all")
    check("and still mints no tab", desk.tabs.isEmpty, "\(desk.tabs.count)")

    desk.park(.inbox, at: InboxLens.tidy.rawValue)
    check("each tool keeps its own", desk.position(.inbox) == "tidy")
    check("without disturbing the others", desk.position(.everything) == "all")

    // ---- the desk follows you ----
    desk.go(.notes)
    desk.open(7)
    check("a document opens onto the desk", desk.tabs.count == 1 && desk.openDoc == 7)
    desk.go(.calendar)
    check("and is still there from another view", desk.tabs.count == 1, "\(desk.tabs.count)")
    check("the key counts the same desk everywhere", desk.liveTabs.count == 1)
    desk.open(8)
    check("a document opened from a TOOL lands on the same desk", desk.tabs.count == 2)
    check("no duplicate for a note already open", { desk.open(7); return desk.tabs.count }() == 2)

    // A new tab is a new note, from anywhere — there is no second Today
    // to open, which is what `openRoot` used to do.
    desk.go(.today)
    let before = desk.tabs.count
    desk.newTab()
    check("new tab never mints a position tab", desk.tabs.count == before, "\(desk.tabs.count)")

    // ---- a structured position still round-trips ----
    let wanted = TasksPosition(filter: .status("To do"), expanded: ["Done", "Archived"])
    desk.park(.tasks, at: wanted.token)
    let read = TasksPosition(token: desk.position(.tasks))
    check("the Tasks filter survives the token", read.filter == .status("To do"), "\(read.filter)")
    check("the open groups survive too", read.expanded == ["Archived", "Done"], "\(read.expanded)")
    check("one position spells itself one way", wanted.token == read.token)
    check(
        "a name with punctuation survives",
        TasksPosition(
            token: TasksPosition(filter: .project("Roof: phase 2 | east"), expanded: []).token
        ).filter == .project("Roof: phase 2 | east"))
    check(
        "a token this build cannot read falls back to the root",
        TasksPosition(token: "{}}").filter == .all)
    check("Tasks reads as its filter", LivPosition.title(.tasks, wanted.token) == "To do")

    // ---- one shelf ----
    let savedDays = UserDefaults.standard.object(forKey: LivTabs.key)
    UserDefaults.standard.set(14, forKey: LivTabs.key)
    let now = Civil.nowStamp()
    let old = Civil.stamp(day: Civil.addDays(Civil.todayDay(), -30), hhmm: 900)

    desk.replaceTabsForSelfCheck([
        DeskTab(id: UUID(), content: .entity(41), lastUsed: old),
        DeskTab(id: UUID(), content: .entity(42), lastUsed: old),
        DeskTab(id: UUID(), content: .entity(43), lastUsed: now),
    ])
    check("stale tabs go to the shelf", desk.inactiveCount == 2, "\(desk.inactiveCount)")
    check("the active tab is never on it", desk.inactiveTabs.allSatisfy { $0.id != desk.activeTabId })
    check("and the grid shows the rest", desk.liveTabs.count == 1, "\(desk.liveTabs.count)")

    if let stale = desk.inactiveTabs.first { desk.close(stale.id) }
    check("closing from the shelf takes one", desk.tabs.count == 2, "\(desk.tabs.count)")
    desk.closeInactive()
    check("Close all empties the shelf", desk.inactiveCount == 0, "\(desk.inactiveCount)")
    check("and never the tab you are on", desk.tabs.count == 1, "\(desk.tabs.count)")

    // ---- the shelf's own arithmetic is unchanged ----
    check("a tab used today is live", !LivTabs.isInactive(now, now: now))
    check("one used a month ago is not", LivTabs.isInactive(old, now: now))

    if let savedDays { UserDefaults.standard.set(savedDays, forKey: LivTabs.key) } else {
        UserDefaults.standard.removeObject(forKey: LivTabs.key)
    }
    DeskModel.forgetScratchForSelfCheck()
    return failures
}
