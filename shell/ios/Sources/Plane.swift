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

/// ONE DESK, and a spot in each tool (2026-08-28).
///
/// Until now this was six planes, one per view, and a plane could hold
/// either kind of tab. In practice it never did: `open(entity:)` was
/// called with `.notes` at both of its call sites, `park` only ever
/// wrote positions, and the sweep below already read `byFeature[.notes]`
/// under a comment saying "only Notes holds entities". The split was
/// real and undeclared.
///
/// Declaring it is the whole change. A DOCUMENT is plural — you keep
/// several open and come back to them — so the documents live in one
/// desk that follows you across every view. A TOOL is singular; there is
/// one Today. What a tool needs remembered is WHERE YOU LEFT IT, which
/// is one token, not a list of them. Six planes could hold three Todays,
/// and did.
///
/// A value type: DeskModel holds one behind `private(set)`, so mutating
/// it republishes the desk exactly as assigning the old dictionary did,
/// and no other file can move a tab.
struct DeskPlanes {
    /// The workspace these belong to. Every key is scoped by it, so a
    /// switch is a reload and never a merge.
    private(set) var workspaceId: UInt64
    /// The documents you have open. One set, for the whole app.
    private var desk: DeskPlane
    /// Where each tool was left, in that view's own vocabulary
    /// (`Positions.swift`). One token each; absent means its own root.
    private var spots: [Feature: String]

    init(workspace: UInt64) {
        workspaceId = workspace
        (desk, spots) = Self.load(workspace)
    }

    // MARK: reading

    var tabs: [DeskTab] { desk.tabs }

    var activeTabId: UUID? { desk.activeTabId }

    var activeTab: DeskTab? { desk.tabs.first { $0.id == desk.activeTabId } }

    /// Where a tool was left. `nil` means it shows its own root.
    func position(_ feature: Feature) -> String? { spots[feature] }

    /// The tabs the grid shows. Inactive tabs are NOT removed from the
    /// plane — they stay in the one array, so closing, de-duplicating,
    /// pruning and the saved plane all keep working on the whole set, and
    /// only what is DISPLAYED narrows.
    ///
    /// The active tab is never inactive, which guarantees this is
    /// non-empty whenever the plane is — and therefore that an empty desk
    /// means "no tabs at all", not "none you looked at lately".
    var live: [DeskTab] {
        let now = Civil.nowStamp()
        return desk.tabs.filter {
            $0.id == desk.activeTabId || !LivTabs.isInactive($0.lastUsed, now: now)
        }
    }

    /// Untouched long enough to be out of the way. Most recently used
    /// first, so the shelf reads newest-stale to oldest.
    ///
    /// The active tab of that plane is never inactive — including when
    /// you are not looking at that view. A plane you left three weeks ago
    /// keeps the tab you left it on.
    var inactive: [DeskTab] {
        let now = Civil.nowStamp()
        return desk.tabs
            .filter { $0.id != desk.activeTabId && LivTabs.isInactive($0.lastUsed, now: now) }
            .sorted { $0.lastUsed > $1.lastUsed }
    }

    /// **One attic, and now it needs no gathering.** This used to walk
    /// six planes so a Calendar tab parked in July would not be
    /// invisible until you happened to open the Calendar. With one desk
    /// there is one shelf and the question does not arise.
    var inactiveCount: Int { inactive.count }

    // MARK: moving a tab

    /// This tab is being used, now. The ONE place a tab's clock is set.
    mutating func touch(_ tabId: UUID) {
        guard let i = desk.tabs.firstIndex(where: { $0.id == tabId }) else { return }
        desk.tabs[i].lastUsed = Civil.nowStamp()
        persist()
    }

    mutating func setActive(_ tabId: UUID?) {
        desk.activeTabId = tabId
        persist()
    }

    /// Remember where a tool was left. It used to MINT A TAB — which is
    /// how a view you had merely scrolled ended up with two of itself,
    /// and then three. One token, overwritten.
    mutating func park(_ feature: Feature, at token: String) {
        guard spots[feature] != token else { return }
        spots[feature] = token
        persist()
    }

    /// The tab holding `entity`, minting one at the end of the plane if
    /// there is none. Returns the tab to focus — appending and focusing
    /// are the whole difference tabs make, and opening a second note no
    /// longer replaces the first.
    mutating func open(entity: UInt64) -> UUID {
        if let existing = desk.tabs.first(where: { $0.content == .entity(entity) }) {
            return existing.id
        }
        let tab = DeskTab(id: UUID(), content: .entity(entity), lastUsed: Civil.nowStamp())
        desk.tabs.append(tab)
        persist()
        return tab.id
    }

    /// Does this plane hold that tab? The chrome asks before it commits
    /// the keyboard, so a close that would do nothing does not also
    /// resign a field.
    func holds(_ tabId: UUID) -> Bool { desk.tabs.contains { $0.id == tabId } }

    /// Closing the last tab leaves the desk empty — and an empty desk is
    /// empty: a hint, and the `+` that ends it.
    mutating func close(_ tabId: UUID) {
        guard let index = desk.tabs.firstIndex(where: { $0.id == tabId }) else { return }
        var tabs = desk.tabs
        var activeTabId = desk.activeTabId
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
        desk.tabs = tabs
        desk.activeTabId = activeTabId
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
        desk.tabs.contains { tab in
            guard case .entity(let id) = tab.content else { return false }
            return shapeOf(id) == .record || !knows(id)
        }
    }

    mutating func dropRecordsAndStrangers(
        shapeOf: (UInt64) -> TabShape, knows: (UInt64) -> Bool
    ) {
        let before = desk.tabs.count
        desk.tabs.removeAll { tab in
            guard case .entity(let id) = tab.content else { return false }
            // ONLY records go for being records. A file is a document you
            // work on and keeps its tab (files, 2026-08-09).
            return shapeOf(id) == .record || !knows(id)
        }
        guard desk.tabs.count != before else { return }
        if let active = desk.activeTabId, !desk.tabs.contains(where: { $0.id == active }) {
            desk.activeTabId = desk.tabs.last?.id
        }
        persist()
    }

    /// Swap the workspace. The outgoing planes are saved under THEIR keys
    /// first, so a switch is never a loss; the incoming ones replace them.
    mutating func adopt(workspace id: UInt64) {
        persist()  // the OUTGOING workspace — `workspaceId` still points at it
        workspaceId = id
        (desk, spots) = Self.load(id)
    }

    // MARK: what is on disk

    /// The pre-M4 single plane, and the per-workspace tab sets that
    /// followed it. READ-ONLY: nothing writes these keys any more.
    private static let legacyKey = "desk.tabs.v1"

    /// The desk and the tools' spots, for one workspace.
    ///
    /// NOTHING SAVED IS THROWN AWAY. Three generations of key are read,
    /// newest first, and the v2 per-view planes are folded rather than
    /// dropped: their ENTITY tabs join the desk, and each view's active
    /// POSITION becomes that tool's spot. A person upgrading keeps every
    /// document they had open and lands each tool where they left it.
    /// What they lose is the ability to have three Todays, which is the
    /// point.
    ///
    /// The old keys are left on disk, readable, rather than deleted —
    /// the same courtesy the 2026-08-22 migration paid v1.
    private static func load(_ workspace: UInt64) -> (DeskPlane, [Feature: String]) {
        var spots: [Feature: String] = [:]

        // v3: already migrated.
        if let desk = Self.readPlane(WorkspaceModel.deskKey(workspace)) {
            let stored =
                UserDefaults.standard.dictionary(forKey: WorkspaceModel.spotsKey(workspace))
                as? [String: String] ?? [:]
            for (raw, token) in stored {
                if let f = Feature(rawValue: raw) { spots[f] = token }
            }
            return (desk, spots)
        }

        // v2: six planes. Entities to the desk, active positions to spots.
        var desk = DeskPlane()
        var migrated = false
        for feature in Feature.inOrder {
            guard let plane = Self.readPlane(WorkspaceModel.planeKey(workspace, feature.rawValue))
            else { continue }
            migrated = true
            for tab in plane.tabs {
                switch tab.content {
                case .entity:
                    // De-duplicated: the same note could sit in two
                    // planes, and two tabs of one note is the bug the
                    // desk exists to prevent.
                    if !desk.tabs.contains(where: { $0.content == tab.content }) {
                        desk.tabs.append(tab)
                        if tab.id == plane.activeTabId, desk.activeTabId == nil {
                            desk.activeTabId = tab.id
                        }
                    }
                case .position(let token):
                    // Only the one you were ON survives. The rest were
                    // duplicates of a place there is one of.
                    if tab.id == plane.activeTabId { spots[feature] = token }
                }
            }
        }
        if migrated { return (desk, spots) }

        // v1, plus the four days when the desk held one document under
        // its own key — see `foldInLiveDocument`.
        let legacy =
            Self.readPlane(WorkspaceModel.tabsKey(workspace))
            ?? (workspace == 0 ? Self.readPlane(legacyKey) : nil)
        return (Self.foldInLiveDocument(legacy ?? DeskPlane(), workspace: workspace), spots)
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

    /// The desk under one key, and the tools' spots under another.
    func persist() {
        var ids: [String] = []
        var used: [String: Int] = [:]
        var active = -1
        // EVERY tab, inactive ones included. `active` indexes the array
        // being built here, so filtering any tab out would both point it
        // at the wrong tab and lose the inactive ones for good.
        for tab in desk.tabs {
            let token = tab.content.token
            if tab.id == desk.activeTabId { active = ids.count }
            ids.append(token)
            used[token] = Int(tab.lastUsed)
        }
        // ALWAYS WRITE THE KEY, EVEN EMPTY.
        //
        // The per-view planes deliberately did the opposite: "no plane"
        // and "a plane with no tabs" had to be one state, or a view that
        // once had a tab would stop looking untouched forever.
        //
        // That rule does not carry over, and carrying it over was a bug
        // (found 2026-08-28). An absent desk key means NOT YET MIGRATED,
        // so removing it on the last close sent the next launch back
        // through the v2 fold and resurrected every tab the person had
        // just closed. An empty desk is an empty desk; it has to be able
        // to say so.
        UserDefaults.standard.set(
            ["ids": ids, "active": active, "used": used],
            forKey: WorkspaceModel.deskKey(workspaceId))
        let spotKey = WorkspaceModel.spotsKey(workspaceId)
        if spots.isEmpty {
            UserDefaults.standard.removeObject(forKey: spotKey)
        } else {
            UserDefaults.standard.set(
                Dictionary(uniqueKeysWithValues: spots.map { ($0.key.rawValue, $0.value) }),
                forKey: spotKey)
        }
    }

    // MARK: the self-checks' own corner

    /// A workspace no user has. Self-check only.
    static let scratchWorkspace: UInt64 = .max

    /// Self-check only: leave nothing behind.
    static func forgetScratch() {
        UserDefaults.standard.removeObject(forKey: WorkspaceModel.deskKey(scratchWorkspace))
        UserDefaults.standard.removeObject(forKey: WorkspaceModel.spotsKey(scratchWorkspace))
        for feature in Feature.allCases {
            UserDefaults.standard.removeObject(
                forKey: WorkspaceModel.planeKey(scratchWorkspace, feature.rawValue))
        }
    }

    /// Self-check only: install a known set, focused on its last tab.
    mutating func replaceForSelfCheck(_ fresh: [DeskTab]) {
        desk.tabs = fresh
        setActive(fresh.last?.id)
    }

    /// Rehearsal only (`-desk.boot inactive`): age every tab except each
    /// plane's active one, so the shelf can be seen and photographed
    /// today.
    ///
    mutating func backdate(days: Int) {
        let old = Civil.stamp(day: Civil.addDays(Civil.todayDay(), -days), hhmm: 900)
        for i in desk.tabs.indices where desk.tabs[i].id != desk.activeTabId {
            desk.tabs[i].lastUsed = old - Int64(i)
        }
        persist()
    }
}
