// liv iOS — THE TAB PLANES: what a view's strip holds, and the
// UserDefaults behind it.
//
// Lifted out of Chrome.swift on 2026-08-23, which was 1,870 lines. The
// plane model is what pushed it over: on 2026-08-22 each view got its
// own strip (design/tabs.md phases 4 and 5), and one plane's worth of
// code became six. Standing rule 9 calls ~600 the signal to look for the
// seam; this is the seam.
//
// WHY A TYPE AND NOT AN EXTENSION. Swift keeps stored properties in the
// class body, so an `extension DeskModel` in another file could only
// reach the plane by opening its setter to the whole module — and
// "opening the setter to everyone is how a second file starts mutating
// the plane" is a note the old code left about itself. `DeskPlanes` is a
// value type instead: DeskModel holds ONE of them behind `private(set)`,
// so the plane still has exactly one mutator, and every verb that moves
// a tab lives here with the storage it writes.
//
// EVERY MOVE PERSISTS. Before the split `activeTabId` wrote through and
// `tabs` did not, which worked only because every caller happened to set
// the second after the first. A mutating verb here always saves; six
// small dictionaries is nothing, and it cannot get out of step.
//
// TOKENS ARE ON DISK. `ids` holds entity ids and position tokens
// (Positions.swift) written the moment a user parks a tab. Never re-mean
// one; add a case and leave the old one readable.

import SwiftUI

// MARK: - what a tab is

/// One tab. Restored 2026-08-22 with the model it had before
/// `0aa2af3` deleted it (design/tabs.md).
struct DeskTab: Identifiable {
    /// Minted fresh every launch. A tab's durable identity is the entity
    /// it holds, which is what the saved plane stores.
    let id: UUID
    var content: DeskTabContent
    /// When this tab was last USED — opened or focused. A packed civil
    /// stamp, the app's one time vocabulary. Tabs that go untouched long
    /// enough fall out of the grid onto the Inactive shelf; nothing about
    /// them is lost, they are just not in the way. No default on purpose:
    /// every place that mints a tab has to say when.
    var lastUsed: Int64
}

/// **Notes only, for now.** The team's ruling of 2026-08-22 is Reading B:
/// each view owns a tab strip, and a tab is a saved POSITION inside that
/// view. In Notes that position is a document, which is exactly what this
/// case was before. The other views' cases arrive with their planes; in
/// Tasks a tab will be a list, and tapping a task still raises a card —
/// so neither of the owner's 2026-08-07 and 2026-08-08 rulings is
/// reversed.
enum DeskTabContent: Equatable {
    /// Notes: the tab IS a document. What a tab always was.
    case entity(UInt64)
    /// Every other view: a saved POSITION, encoded by the view that owns
    /// it (Reading B, team 2026-08-22).
    ///
    /// A token rather than a case per view, deliberately. A case per view
    /// would put every view's vocabulary in this one enum and make adding
    /// a seventh view an edit here; a token keeps each view's meaning
    /// where that view is, and the plane stays a plane. What it costs: the
    /// engine cannot check a position the way it checks an entity, so a
    /// view is responsible for reading back only tokens it wrote.
    case position(String)

    /// What goes on disk for this tab. An entity is its id; a position is
    /// its own token. Read back by `readPlane`, which calls anything that
    /// is not a number a position.
    var token: String {
        switch self {
        case .entity(let id): return String(id)
        case .position(let p): return p
        }
    }
}

/// One view's tab strip.
struct DeskPlane {
    var tabs: [DeskTab] = []
    var activeTabId: UUID?
}

// MARK: - every view's strip, for one workspace

/// The six planes of one workspace, and the only thing that writes them.
///
/// A value type: DeskModel holds one behind `private(set)`, so mutating a
/// plane republishes the desk exactly as assigning the old dictionary
/// did, and no other file can move a tab.
struct DeskPlanes {
    /// The workspace these belong to. Every key is scoped by it, so a
    /// switch is a reload and never a merge.
    private(set) var workspaceId: UInt64
    private var byFeature: [Feature: DeskPlane]

    init(workspace: UInt64) {
        workspaceId = workspace
        byFeature = Self.load(workspace)
    }

    // MARK: reading

    /// One view's plane, or nil when it has never had one. `nil` and "a
    /// plane with no tabs" are the same state and must not become two —
    /// see `persist`.
    subscript(feature: Feature) -> DeskPlane? { byFeature[feature] }

    func tabs(in feature: Feature) -> [DeskTab] { byFeature[feature]?.tabs ?? [] }

    func activeTabId(in feature: Feature) -> UUID? { byFeature[feature]?.activeTabId }

    func activeTab(in feature: Feature) -> DeskTab? {
        guard let plane = byFeature[feature] else { return nil }
        return plane.tabs.first { $0.id == plane.activeTabId }
    }

    /// Where the active tab of `feature` is parked, in that view's own
    /// vocabulary (`Positions.swift`). `nil` means the plane has no tab
    /// yet and the view shows its root — which is what no tabs has always
    /// meant in Notes.
    func position(_ feature: Feature) -> String? {
        guard let tab = activeTab(in: feature),
            case .position(let token) = tab.content
        else { return nil }
        return token
    }

    /// The tabs the grid shows. Inactive tabs are NOT removed from the
    /// plane — they stay in the one array, so closing, de-duplicating,
    /// pruning and the saved plane all keep working on the whole set, and
    /// only what is DISPLAYED narrows.
    ///
    /// The active tab is never inactive, which guarantees this is
    /// non-empty whenever the plane is — and therefore that an empty desk
    /// means "no tabs at all", not "none you looked at lately".
    func live(in feature: Feature) -> [DeskTab] {
        guard let plane = byFeature[feature] else { return [] }
        let now = Civil.nowStamp()
        return plane.tabs.filter {
            $0.id == plane.activeTabId || !LivTabs.isInactive($0.lastUsed, now: now)
        }
    }

    /// Untouched long enough to be out of the way. Most recently used
    /// first, so the shelf reads newest-stale to oldest.
    ///
    /// The active tab of that plane is never inactive — including when
    /// you are not looking at that view. A plane you left three weeks ago
    /// keeps the tab you left it on.
    func inactive(in feature: Feature) -> [DeskTab] {
        guard let plane = byFeature[feature] else { return [] }
        let now = Civil.nowStamp()
        return plane.tabs
            .filter { $0.id != plane.activeTabId && LivTabs.isInactive($0.lastUsed, now: now) }
            .sorted { $0.lastUsed > $1.lastUsed }
    }

    /// EVERY plane's shelf, in the declared view order, empty ones left
    /// out.
    ///
    /// **One attic, not six.** With a plane per view, a shelf that showed
    /// only the view you were standing in would hide five of them — a
    /// Calendar tab you stopped using in July would be invisible until
    /// you happened to open the Calendar. The grid above is the view you
    /// are in; the shelf is everything you have parked.
    var inactiveEverywhere: [(feature: Feature, tabs: [DeskTab])] {
        Feature.inOrder.compactMap { feature in
            let parked = inactive(in: feature)
            return parked.isEmpty ? nil : (feature, parked)
        }
    }

    var inactiveCount: Int {
        Feature.allCases.reduce(0) { $0 + inactive(in: $1).count }
    }

    // MARK: moving a tab

    /// This tab is being used, now. The ONE place a tab's clock is set.
    mutating func touch(_ tabId: UUID, in feature: Feature) {
        guard var plane = byFeature[feature],
            let i = plane.tabs.firstIndex(where: { $0.id == tabId })
        else { return }
        plane.tabs[i].lastUsed = Civil.nowStamp()
        byFeature[feature] = plane
        persist()
    }

    mutating func setActive(_ tabId: UUID?, in feature: Feature) {
        byFeature[feature, default: DeskPlane()].activeTabId = tabId
        persist()
    }

    /// Park the active tab at `token`. **Moving is what mints the tab**:
    /// a view whose plane is empty gets one here, so a user who never
    /// leaves a view's root never accumulates a tab they did not ask for.
    mutating func park(_ feature: Feature, at token: String) {
        var plane = byFeature[feature] ?? DeskPlane()
        if let active = plane.activeTabId,
            let i = plane.tabs.firstIndex(where: { $0.id == active })
        {
            guard plane.tabs[i].content != .position(token) else { return }
            plane.tabs[i].content = .position(token)
            plane.tabs[i].lastUsed = Civil.nowStamp()
        } else {
            let tab = DeskTab(id: UUID(), content: .position(token), lastUsed: Civil.nowStamp())
            plane.tabs.append(tab)
            plane.activeTabId = tab.id
        }
        byFeature[feature] = plane
        persist()
    }

    /// The tab holding `entity`, minting one at the end of the plane if
    /// there is none. Returns the tab to focus — appending and focusing
    /// are the whole difference tabs make, and opening a second note no
    /// longer replaces the first.
    mutating func open(entity: UInt64, in feature: Feature) -> UUID {
        var plane = byFeature[feature] ?? DeskPlane()
        if let existing = plane.tabs.first(where: { $0.content == .entity(entity) }) {
            return existing.id
        }
        let tab = DeskTab(id: UUID(), content: .entity(entity), lastUsed: Civil.nowStamp())
        plane.tabs.append(tab)
        byFeature[feature] = plane
        persist()
        return tab.id
    }

    /// A new tab at the view's own root, focused. The switcher's `+` in
    /// every view but Notes, where a tab needs a document to hold and the
    /// create menu answers instead.
    mutating func openRoot(in feature: Feature) {
        var plane = byFeature[feature] ?? DeskPlane()
        let tab = DeskTab(
            id: UUID(), content: .position(LivPosition.root(feature)),
            lastUsed: Civil.nowStamp())
        plane.tabs.append(tab)
        plane.activeTabId = tab.id
        byFeature[feature] = plane
        persist()
    }

    /// Does this plane hold that tab? The chrome asks before it commits
    /// the keyboard, so a close that would do nothing does not also
    /// resign a field.
    func holds(_ tabId: UUID, in feature: Feature) -> Bool {
        byFeature[feature]?.tabs.contains { $0.id == tabId } ?? false
    }

    /// Closing the last tab leaves the desk empty — and an empty desk is
    /// empty: a hint, and the `+` that ends it.
    mutating func close(_ tabId: UUID, in feature: Feature) {
        guard var plane = byFeature[feature],
            let index = plane.tabs.firstIndex(where: { $0.id == tabId })
        else { return }
        var tabs = plane.tabs
        var activeTabId = plane.activeTabId
        tabs.remove(at: index)
        if tabs.isEmpty {
            activeTabId = nil
        } else if activeTabId == tabId {
            // The nearest tab you have actually been using. Stepping to
            // the plain index neighbour could land the desk on a
            // three-week-old note you never asked for.
            let now = Civil.nowStamp()
            let fresh = tabs.filter { !LivTabs.isInactive($0.lastUsed, now: now) }
            let nextDoor = tabs[min(index, tabs.count - 1)]
            let landing =
                LivTabs.isInactive(nextDoor.lastUsed, now: now)
                ? (fresh.max { $0.lastUsed < $1.lastUsed } ?? nextDoor)
                : nextDoor
            activeTabId = landing.id
            if let i = tabs.firstIndex(where: { $0.id == landing.id }) {
                tabs[i].lastUsed = Civil.nowStamp()
            }
        }
        plane.tabs = tabs
        plane.activeTabId = activeTabId
        byFeature[feature] = plane
        persist()
    }

    /// Called once, on the first snapshot — the first moment the box can
    /// say what a saved id IS.
    ///
    /// **The NOTES plane, whatever view you launched into.** Only Notes
    /// holds entities, and the app opens on Today, so sweeping "the
    /// current plane" would sweep the wrong one — or nothing at all.
    ///
    /// Two sweeps, and both wait for this moment on purpose. A record
    /// cannot be a tab, so tabs holding one close (owner, 2026-08-08).
    /// And a tab whose entity is not in the box at all is a card that can
    /// only ever say "this was deleted" — the plane restored on
    /// 2026-08-22 had 65 of them on a test device whose box had been
    /// rebuilt underneath it.
    ///
    /// The original rule was that missing ids drop LAZILY, "never an
    /// eager sweep against a box that may still be opening". This is not
    /// that sweep: the box has opened, which is the whole reason this
    /// runs here and not at init.
    /// Is there anything for the sweep to take? A plain read, so a
    /// caller can ask without touching the `@Published` struct that
    /// holds it — see `DeskModel.dropRecordDocument`.
    func hasStrangers(shapeOf: (UInt64) -> TabShape, knows: (UInt64) -> Bool) -> Bool {
        guard let plane = byFeature[.notes] else { return false }
        return plane.tabs.contains { tab in
            guard case .entity(let id) = tab.content else { return false }
            return shapeOf(id) == .record || !knows(id)
        }
    }

    mutating func dropRecordsAndStrangers(
        shapeOf: (UInt64) -> TabShape, knows: (UInt64) -> Bool
    ) {
        guard var plane = byFeature[.notes] else { return }
        let before = plane.tabs.count
        plane.tabs.removeAll { tab in
            guard case .entity(let id) = tab.content else { return false }
            // ONLY records go for being records. A file is a document you
            // work on and keeps its tab (files, 2026-08-09).
            return shapeOf(id) == .record || !knows(id)
        }
        guard plane.tabs.count != before else { return }
        if let active = plane.activeTabId, !plane.tabs.contains(where: { $0.id == active }) {
            plane.activeTabId = plane.tabs.last?.id
        }
        byFeature[.notes] = plane
        persist()
    }

    /// Swap the workspace. The outgoing planes are saved under THEIR keys
    /// first, so a switch is never a loss; the incoming ones replace them.
    mutating func adopt(workspace id: UInt64) {
        persist()  // the OUTGOING workspace — `workspaceId` still points at it
        workspaceId = id
        byFeature = Self.load(id)
    }

    // MARK: what is on disk

    /// The pre-M4 single plane, and the per-workspace tab sets that
    /// followed it. READ-ONLY: nothing writes these keys any more.
    private static let legacyKey = "desk.tabs.v1"

    /// Every view's plane for one workspace.
    ///
    /// **Notes migrates; the rest are born empty.** The pre-2026-08-22
    /// key held one plane, and it was the Notes one — so it is read into
    /// `.notes` and left where it is, readable, rather than deleted. The
    /// other five views have never had a plane and start without one; a
    /// view with no plane shows its own root, which is what it did
    /// yesterday.
    private static func load(_ workspace: UInt64) -> [Feature: DeskPlane] {
        var out: [Feature: DeskPlane] = [:]
        for feature in Feature.allCases {
            let key = WorkspaceModel.planeKey(workspace, feature.rawValue)
            if let plane = Self.readPlane(key) {
                out[feature] = plane
            }
        }
        if out[.notes] == nil {
            // v1, plus the four days when the desk held one document
            // under its own key — see `foldInLiveDocument`.
            let legacy =
                Self.readPlane(WorkspaceModel.tabsKey(workspace))
                ?? (workspace == 0 ? Self.readPlane(legacyKey) : nil)
            out[.notes] = Self.foldInLiveDocument(legacy ?? DeskPlane(), workspace: workspace)
        }
        return out
    }

    /// One saved plane. Entity ids and position tokens only — a tab's
    /// UUID is minted fresh every launch, so what is stored is the only
    /// identity a saved plane actually has.
    private static func readPlane(_ key: String) -> DeskPlane? {
        guard let stored = UserDefaults.standard.dictionary(forKey: key) else { return nil }
        let now = Civil.nowStamp()
        // A plane saved before tabs had clocks counts as used NOW.
        // Reading a missing stamp as "never used" would sweep every tab
        // you own on the first launch after the upgrade.
        let used = stored["used"] as? [String: Int] ?? [:]
        var plane = DeskPlane()
        for token in stored["ids"] as? [String] ?? [] {
            let content: DeskTabContent =
                UInt64(token).map { .entity($0) } ?? .position(token)
            plane.tabs.append(
                DeskTab(
                    id: UUID(), content: content,
                    lastUsed: used[token].map(Int64.init) ?? now))
        }
        let active = stored["active"] as? Int ?? -1
        plane.activeTabId = plane.tabs.indices.contains(active) ? plane.tabs[active].id : nil
        return plane
    }

    /// Between 2026-08-18 and 2026-08-22 the desk held one document under
    /// its own key while the old plane sat beside it untouched. Restoring
    /// the plane alone would bring back a four-day-old tab set and
    /// silently drop the note actually in use, so the live document is
    /// added and focused, and its key is then removed. One truth, once.
    private static func foldInLiveDocument(_ plane: DeskPlane, workspace: UInt64) -> DeskPlane {
        var plane = plane
        let docKey = WorkspaceModel.docKey(workspace)
        guard let saved = UserDefaults.standard.object(forKey: docKey) as? NSNumber,
            saved.uint64Value != 0
        else { return plane }
        let live = saved.uint64Value
        if let already = plane.tabs.first(where: { $0.content == .entity(live) }) {
            plane.activeTabId = already.id
        } else {
            let tab = DeskTab(id: UUID(), content: .entity(live), lastUsed: Civil.nowStamp())
            plane.tabs.append(tab)
            plane.activeTabId = tab.id
        }
        UserDefaults.standard.removeObject(forKey: docKey)
        return plane
    }

    /// Every plane, under its own key. Six small dictionaries written
    /// when a tab changes — cheaper than tracking which plane moved, and
    /// it cannot get out of step with itself.
    func persist() {
        for (feature, plane) in byFeature {
            var ids: [String] = []
            var used: [String: Int] = [:]
            var active = -1
            // EVERY tab, inactive ones included. `active` indexes the
            // array being built here, so filtering any tab out would both
            // point it at the wrong tab and lose the inactive ones for
            // good.
            for tab in plane.tabs {
                let token = tab.content.token
                if tab.id == plane.activeTabId { active = ids.count }
                ids.append(token)
                used[token] = Int(tab.lastUsed)
            }
            let key = WorkspaceModel.planeKey(workspaceId, feature.rawValue)
            // NO KEY FOR AN EMPTY PLANE. "No plane" and "a plane with no
            // tabs" are the same state and must not become two, or a view
            // that once had a tab would stop looking untouched forever.
            if ids.isEmpty {
                UserDefaults.standard.removeObject(forKey: key)
            } else {
                UserDefaults.standard.set(["ids": ids, "active": active, "used": used], forKey: key)
            }
        }
    }

    // MARK: the self-checks' own corner

    /// A workspace no user has. Self-check only.
    static let scratchWorkspace: UInt64 = .max

    /// Self-check only: leave nothing behind.
    static func forgetScratch() {
        for feature in Feature.allCases {
            UserDefaults.standard.removeObject(
                forKey: WorkspaceModel.planeKey(scratchWorkspace, feature.rawValue))
        }
    }

    /// Self-check only: install a known set, focused on its last tab.
    mutating func replaceForSelfCheck(_ fresh: [DeskTab], in feature: Feature) {
        byFeature[feature, default: DeskPlane()].tabs = fresh
        setActive(fresh.last?.id, in: feature)
    }

    /// Rehearsal only (`-desk.boot inactive`): age every tab except each
    /// plane's active one, so the shelf can be seen and photographed
    /// today.
    ///
    /// **Every plane**, since 2026-08-22 — the shelf spans them now, and
    /// a rehearsal that aged one would show a screen no user will ever
    /// see.
    mutating func backdate(days: Int) {
        let old = Civil.stamp(day: Civil.addDays(Civil.todayDay(), -days), hhmm: 900)
        for (feature, var plane) in byFeature {
            for i in plane.tabs.indices where plane.tabs[i].id != plane.activeTabId {
                plane.tabs[i].lastUsed = old - Int64(i)
            }
            byFeature[feature] = plane
        }
        persist()
    }
}
