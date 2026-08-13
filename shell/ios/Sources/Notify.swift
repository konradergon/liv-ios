// liv iOS — local notifications (design/ios.md §3 + §9 M5). Shell
// territory: the pending queue is a PROJECTION of the snapshot —
// recomputed whole on every decode, never patched, so it can never drift
// from the box (the core stays timerless; staleness is accepted, "absence
// creates no debt"). Identifier "liv-<entityId>" + remove-all-then-re-add
// makes every rebuild idempotent — simple first.

import Combine
import Foundation
import UserNotifications

// MARK: - the scheduler

/// The one notification authority: snapshot in, pending queue out, plus
/// the UNUserNotificationCenter delegate seam. The master toggle is
/// DEVICE state (UserDefaults) — never cells; Settings never writes cells.
///
/// A reminder rings AT the time the thing is due. There is no lead time
/// and no separate idea of an all-day reminder (owner, 2026-08-06). The
/// two lead-time pickers that used to live in Settings were invented,
/// not specified, and they only ever touched dues that carried a clock
/// time; everything else rang at a hidden 09:00 that nobody chose and
/// nobody could change. Both are gone. Where a due still carries no
/// clock time — an all-day calendar event — the reminder rings at the
/// start of that day.
final class Notify: NSObject, ObservableObject {
    static let shared = Notify()

    /// Where a tapped notification lands: the entity opens as a desk tab.
    /// Wired by the chrome once it exists; a cold-launch tap that beats
    /// the wiring parks its id here and flushes on assignment.
    var onOpen: ((UInt64) -> Void)? {
        didSet {
            if let id = pendingOpen, let onOpen {
                pendingOpen = nil
                onOpen(id)
            }
        }
    }
    private var pendingOpen: UInt64?

    /// What the pending queue holds — Settings' honesty line.
    @Published private(set) var scheduledCount = 0
    /// Future dues beyond iOS's 64-slot budget: soonest kept, rest dropped.
    @Published private(set) var droppedCount = 0
    /// The user said no at the system prompt; Settings says so instead of
    /// pretending to schedule.
    @Published private(set) var denied = false

    private enum Keys {
        static let enabled = "notify.enabled"
    }

    /// Master toggle, default ON — permission is still only ASKED once
    /// there is something real to schedule (the lazy-request rule).
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: Keys.enabled) as? Bool ?? true }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: Keys.enabled)
        }
    }

    // MARK: rebuild — snapshot in, pending queue out

    /// Recompute the whole schedule from one decoded snapshot. Called on
    /// every decode (App.swift's onReceive) and on every Settings change.
    /// The task vocabulary rides first: a `completes` status silences a
    /// task's reminder — a done task must not ring.
    func rebuild(snapshot: Snapshot?, box: BoxModel) {
        guard enabled else {
            clear()
            return
        }
        guard let snapshot else { return }
        box.statusOptions(kind: "task") { [weak self] options in
            let completes = Set(
                options.filter { $0.completes == true }.compactMap { $0.name })
            self?.schedule(snapshot, completes: completes)
        }
    }

    private struct Slot {
        let entity: UInt64
        let title: String
        let body: String
        let fire: Date
    }

    /// Main-thread (statusOptions completes there). Dues + events only;
    /// occurrences stay off the queue in v1 — "liv-<seriesId>" would
    /// collide with the series entity's own slot.
    private func schedule(_ snap: Snapshot, completes: Set<String>) {
        let now = Date()
        var slots: [Slot] = []
        for row in snap.entities ?? [] {
            guard row.trashed != true, row.archived != true else { continue }
            guard let due = row.due, due > 0 else { continue }
            let kinds = row.kinds ?? []
            // The shell's own task predicate (Today/Tasks): typed task OR a
            // status-carrying row. What shows a ring and a due must also
            // ring — a scrap given status+due is a task everywhere else.
            let isEvent = kinds.contains("event")
            let isTask = !isEvent && (kinds.contains("task") || row.status != nil)
            guard isTask || isEvent else { continue }
            if isTask, let status = row.status, completes.contains(status) { continue }
            // It rings when the thing is due. A due with NO clock time
            // does not ring at all: "a date reminder shouldn't be a
            // thing" (owner, 2026-08-06). Without this the quick-add
            // rows, which still write a bare date, rang at midnight —
            // worse than the hidden 09:00 they replaced (review).
            let dateOnly = row.dueDateOnly ?? (due % 10_000 == 0)
            guard !dateOnly else { continue }
            guard let fire = Self.date(of: due) else { continue }
            guard fire > now else { continue }  // future only — never re-ring the past
            slots.append(
                Slot(
                    entity: row.id, title: Self.title(row),
                    body: Self.body(due: due), fire: fire))
        }
        slots.sort { $0.fire < $1.fire }
        let kept = Array(slots.prefix(64))  // iOS's own budget: the soonest win
        let dropped = slots.count - kept.count
        guard !kept.isEmpty else {
            clear()
            return
        }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                // The lazy ask: the first attempt to schedule something real.
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    DispatchQueue.main.async {
                        self?.denied = !granted
                        if granted { self?.commit(kept, dropped: dropped) }
                    }
                }
            case .denied:
                DispatchQueue.main.async {
                    self?.denied = true
                    self?.publish(scheduled: 0, dropped: 0)
                }
            default:
                DispatchQueue.main.async {
                    self?.denied = false
                    self?.commit(kept, dropped: dropped)
                }
            }
        }
    }

    /// Wholesale replace on the main thread. Identifiers are stable
    /// ("liv-<id>"), so a re-add supersedes; remove-all also sweeps out
    /// entities whose due left the box since the last rebuild.
    private func commit(_ slots: [Slot], dropped: Int) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        var added = 0
        for slot in slots {
            // Re-check now: the auth round-trip may have outlived the fire.
            let interval = slot.fire.timeIntervalSinceNow
            guard interval > 0 else { continue }
            let content = UNMutableNotificationContent()
            content.title = slot.title
            content.body = slot.body
            content.sound = .default
            content.userInfo = ["entity": String(slot.entity)]
            // No badge: the app's one badge is the proposal-inbox count, by law.
            center.add(
                UNNotificationRequest(
                    identifier: "liv-\(slot.entity)", content: content,
                    trigger: UNTimeIntervalNotificationTrigger(
                        timeInterval: interval, repeats: false)))
            added += 1
        }
        publish(scheduled: added, dropped: dropped)
    }

    private func clear() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        publish(scheduled: 0, dropped: 0)
    }

    /// Main-thread only — these feed Settings directly.
    private func publish(scheduled: Int, dropped: Int) {
        scheduledCount = scheduled
        droppedCount = dropped
    }

    // MARK: content helpers

    /// Title = the entity's name, else its first content line (the display
    /// name the rest of the shell shows — a scrap carries no name cell).
    private static func title(_ row: EntityRow) -> String { livRowTitle(row) }

    /// Only timed dues reach here, so this always names a clock time —
    /// spelled out rather than routed through the date-aware helper,
    /// which returns nothing for a stamp ending 0000 and left a reminder
    /// for a midnight event reading just "due" (review, 2026-08-06).
    private static func body(due: Int64) -> String {
        let hhmm = due % 10_000
        return String(format: "due %02d:%02d", hhmm / 100, hhmm % 100)
    }

    /// Packed civil YYYYMMDDHHMM → a wall-clock Date in the current zone.
    /// Gregorian by construction (the core's civil law).
    private static let gregorian = Calendar(identifier: .gregorian)
    private static func date(of stamp: Int64) -> Date? {
        var parts = DateComponents()
        let day = stamp / 10_000
        let hm = stamp % 10_000
        parts.year = Int(day / 10_000)
        parts.month = Int((day / 100) % 100)
        parts.day = Int(day % 100)
        parts.hour = Int(hm / 100)
        parts.minute = Int(hm % 100)
        return gregorian.date(from: parts)
    }
}

// MARK: - the delegate seam (banner in foreground, tap → desk tab)

extension Notify: UNUserNotificationCenterDelegate {
    /// Foreground delivery still shows — banner + sound; an in-app moment
    /// is exactly when a due is easiest to act on.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    /// A tap opens the entity as a desk tab — the notification IS a row.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let raw = response.notification.request.content.userInfo["entity"] as? String,
            let id = UInt64(raw)
        {
            if let onOpen {
                onOpen(id)
            } else {
                pendingOpen = id  // cold launch: the chrome is not built yet
            }
        }
        completionHandler()
    }
}
