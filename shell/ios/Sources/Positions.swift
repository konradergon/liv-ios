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

    // A view with no plane shows its ROOT. No tabs has always meant
    // "you are looking at the list" in Notes; it means the same here.
    desk.go(.everything)
    check("an untouched view has no plane", desk.planes[.everything] == nil)
    check("and no position", desk.position(.everything) == nil)
    check("so the view falls back to its root", LivPosition.root(.everything) == "all")

    // MOVING IS WHAT MINTS THE TAB.
    desk.park(.everything, at: "upcoming")
    check("moving opens a tab", desk.tabs.count == 1, "\(desk.tabs.count)")
    check("parked where asked", desk.position(.everything) == "upcoming")

    // And moving again moves that tab — it does not collect them.
    desk.park(.everything, at: "unfiled")
    check("moving again reuses the tab", desk.tabs.count == 1, "\(desk.tabs.count)")
    check("at the new place", desk.position(.everything) == "unfiled")
    desk.park(.everything, at: "unfiled")
    check("parking where you already are is not a move", desk.tabs.count == 1)

    // A position is not a document, even though both are tabs.
    check("a position never becomes the open document", desk.openDoc == nil)

    // THE PLANES ARE SEPARATE.
    desk.go(.notes)
    check("switching view switches strip", desk.tabs.isEmpty, "\(desk.tabs.count)")
    desk.open(7)
    check("the note opened in the Notes plane", desk.tabs.count == 1 && desk.openDoc == 7)
    desk.go(.everything)
    check("and Everything kept its own", desk.tabs.count == 1 && desk.position(.everything) == "unfiled")
    check("Notes kept its own too", desk.planes[.notes]?.tabs.count == 1)
    check("the key counts the view you are in", desk.liveTabs.count == 1)

    // New tab: a root position here, the create menu in Notes.
    desk.newTab()
    check("a second tab opens at the root", desk.tabs.count == 2)
    check("and it is the active one", desk.position(.everything) == "all")
    desk.go(.notes)
    let notesBefore = desk.tabs.count
    desk.newTab()
    check("new tab in Notes appends nothing by itself", desk.tabs.count == notesBefore)

    // EVERY LIFTED VIEW, not just the first. A view whose position is
    // still `@State` is not in this list and is meant not to be.
    desk.go(.inbox)
    check("the Inbox opens at its root", desk.position(.inbox) == nil)
    desk.park(.inbox, at: InboxLens.tidy.rawValue)
    check("the Inbox parks", desk.position(.inbox) == "tidy")
    check("and Everything did not move", desk.planes[.everything]?.tabs.count == 2)

    // Tasks carries a STRUCTURED position, so its token has to survive a
    // round trip with everything in it.
    let wanted = TasksPosition(filter: .status("To do"), expanded: ["Done", "Archived"])
    desk.go(.tasks)
    desk.park(.tasks, at: wanted.token)
    let read = TasksPosition(token: desk.position(.tasks))
    check("the Tasks filter survives the token", read.filter == .status("To do"), "\(read.filter)")
    check("the open groups survive too", read.expanded == ["Archived", "Done"], "\(read.expanded)")
    check(
        "one position spells itself one way", wanted.token == read.token,
        "\n  wanted=\(wanted.token)\n  read  =\(read.token)")
    check("a name with punctuation survives", TasksPosition(token: TasksPosition(filter: .project("Roof: phase 2 | east"), expanded: []).token).filter == .project("Roof: phase 2 | east"))
    check("a token this build cannot read falls back to the root", TasksPosition(token: "{}}").filter == .all)
    check("Tasks reads as its filter", LivPosition.title(.tasks, wanted.token) == "To do")

    // Today and the Calendar hold a DAY, which is the position most
    // likely to be read back on a different day than it was written.
    desk.go(.today)
    desk.park(.today, at: TodayPosition(day: 20_700, doneExpanded: true, lateOpen: false).token)
    let day = TodayPosition(token: desk.position(.today))
    check("the day survives", day.day == 20_700, "\(day.day)")
    check("and both piles with it", day.doneExpanded && day.lateOpen == false)
    check("today reads as Today", TodayPosition().title == "Today")
    check("another day reads as that day", LivPosition.title(.today, day.token) == Civil.dayLabel(20_700))

    desk.go(.calendar)
    let march = CalGrid.firstOfMonth(Civil.stamp(day: 20_700, hhmm: 0) / 10_000)
    desk.park(.calendar, at: CalendarPosition(month: march, day: 20_700).token)
    let cal = CalendarPosition(token: desk.position(.calendar))
    check("the month survives", cal.month == march, "\(cal.month)")
    check("the day survives with it", cal.day == 20_700)
    check("the Calendar reads as its month", LivPosition.title(.calendar, cal.token) == CalGrid.title(march))

    // EVERY LIFTED VIEW has a root it can read back. A view still on
    // `@State` returns "" and is meant to.
    for feature in Feature.allCases where feature != .notes {
        let root = LivPosition.root(feature)
        check("\(feature.rawValue) has a root", !root.isEmpty)
        check("\(feature.rawValue)'s root has words", !LivPosition.title(feature, root).isEmpty)
        check("\(feature.rawValue)'s root has a line", !LivPosition.detail(feature, root).isEmpty)
    }

    // A token this build does not know still has words. Saved planes
    // outlive the code that wrote them.
    check("a known token reads as itself", LivPosition.title(.everything, "upcoming") == "Upcoming")
    check("an unknown token falls back to the view", LivPosition.title(.everything, "sideways") == "Everything")

    // ROUND TRIP. What is on screen and what is on disk must agree.
    desk.persist()
    let reopened = DeskModel.scratchForSelfCheck()
    check("Everything came back", reopened.planes[.everything]?.tabs.count == 2, "\(reopened.planes[.everything]?.tabs.count ?? -1)")
    check("at the position it was left", reopened.position(.everything) == "all")
    check("Notes came back", reopened.planes[.notes]?.tabs.count == 1)
    check("the Inbox came back", reopened.position(.inbox) == "tidy")
    check("Tasks came back whole", TasksPosition(token: reopened.position(.tasks)).expanded == ["Archived", "Done"])
    check("Today came back on its day", TodayPosition(token: reopened.position(.today)).day == 20_700)
    check("the Calendar came back on its month", CalendarPosition(token: reopened.position(.calendar)).month == march)
    reopened.go(.notes)
    check("with the note it held", reopened.openDoc == 7, "\(String(describing: reopened.openDoc))")

    // ---- phase 5: ONE attic, not six ------------------------------
    let savedDays = UserDefaults.standard.object(forKey: LivTabs.key)
    UserDefaults.standard.set(21, forKey: LivTabs.key)
    let now = Civil.nowStamp()
    let old = Civil.stamp(day: Civil.addDays(Civil.todayDay(), -60), hhmm: 900)

    desk.go(.notes)
    desk.replaceTabsForSelfCheck([
        DeskTab(id: UUID(), content: .entity(41), lastUsed: old),
        DeskTab(id: UUID(), content: .entity(42), lastUsed: now),
    ])
    desk.go(.calendar)
    desk.replaceTabsForSelfCheck([
        DeskTab(id: UUID(), content: .position(LivPosition.root(.calendar)), lastUsed: old),
        DeskTab(id: UUID(), content: .position(CalendarPosition(day: 20_700).token), lastUsed: now),
    ])

    check("the shelf spans the planes", desk.inactiveEverywhere.count == 2, "\(desk.inactiveEverywhere.count)")
    check("in the declared view order", desk.inactiveEverywhere.map(\.feature) == [.notes, .calendar])
    check("and counts every one of them", desk.inactiveCount == 2, "\(desk.inactiveCount)")
    check("while the grid shows only the view you are in", desk.inactiveTabs.count == 1)
    check("the active tab of a plane you left is never inactive",
        !desk.inactiveEverywhere.flatMap(\.tabs).contains { $0.id == desk.planes[.notes]?.activeTabId })

    // Closing in another plane leaves the one you are in alone.
    let stale = desk.inactive(in: .notes).first
    check("Notes has a stale tab to close", stale != nil)
    if let stale { desk.close(stale.id, in: .notes) }
    check("closing another view's tab took only that one", desk.planes[.notes]?.tabs.count == 1, "\(desk.planes[.notes]?.tabs.count ?? -1)")
    check("and left the view you are in", desk.tabs.count == 2, "\(desk.tabs.count)")
    check("the shelf is down to one view", desk.inactiveEverywhere.count == 1)

    desk.closeInactive()
    check("Close all empties every plane", desk.inactiveCount == 0, "\(desk.inactiveCount)")
    check("and never the tab you are on", desk.tabs.count == 1 && desk.planes[.notes]?.tabs.count == 1)

    // Reviving from another view TAKES YOU THERE.
    desk.replaceTabsForSelfCheck([
        DeskTab(id: UUID(), content: .position(LivPosition.root(.calendar)), lastUsed: now)
    ])
    desk.go(.everything)
    let elsewhere = desk.planes[.notes]?.tabs.first
    check("Notes still holds a tab to revive", elsewhere != nil)
    if let elsewhere { desk.focus(elsewhere.id, in: .notes) }
    check("reviving another view's tab changes view", desk.state == .notes, "\(desk.state)")
    check("and focuses it there", desk.activeTabId == desk.planes[.notes]?.tabs.first?.id)

    if let savedDays { UserDefaults.standard.set(savedDays, forKey: LivTabs.key) } else {
        UserDefaults.standard.removeObject(forKey: LivTabs.key)
    }
    DeskModel.forgetScratchForSelfCheck()
    return failures
}
