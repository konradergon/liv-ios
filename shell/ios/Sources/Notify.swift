// liv iOS — local notifications. WHAT rings is Rust's answer
// (`liv_view_reminders`, `surface/src/reminders.rs`); this file is the
// phone's half: permission, turning a wall-clock due into an alarm, and
// iOS's cap on pending alarms. The pending queue is rebuilt whole from each
// answer, never patched, so it cannot drift from the box. Identifier
// "liv-<entityId>" + remove-all-then-re-add makes every rebuild idempotent.

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
    var onOpen: ((LivEntityID) -> Void)? {
        didSet {
            if let id = pendingOpen, let onOpen {
                pendingOpen = nil
                onOpen(id)
            }
        }
    }
    private var pendingOpen: LivEntityID?

    /// iOS keeps at most this many pending notifications; the soonest win.
    static let budget = 64

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

    // MARK: rebuild — Rust's answer in, pending queue out

    /// Recompute the whole schedule from Rust's answer. Called whenever the
    /// answer changes (App.swift) and on every Settings change.
    func rebuild(_ reminders: LivReminders?) {
        guard enabled else {
            clear()
            return
        }
        guard let reminders else { return }
        var kept: [Slot] = []
        for row in reminders.soonest ?? [] {
            guard let due = row.due, let fire = Self.date(of: due) else { continue }
            kept.append(
                Slot(entity: row.id, title: row.title ?? "", body: Self.body(due: due), fire: fire))
        }
        let dropped = max(0, (reminders.total ?? 0) - kept.count)
        schedule(kept, dropped: dropped)
    }

    private struct Slot {
        let entity: LivEntityID
        let title: String
        let body: String
        let fire: Date
    }

    /// Ask once, lazily, then commit — main thread.
    private func schedule(_ kept: [Slot], dropped: Int) {
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
            // BOTH halves through `LivIDText`. The `userInfo` one did not
            // compile after slice 4's flip; the identifier's interpolation
            // did, silently, as hex — and the tap handler reads it back
            // with `LivIDText.read`, which would have returned nil for
            // every one of them. This is the exact failure `LivID.swift`
            // warns about, and the only reason it was found is that its
            // twin two lines up happened not to build.
            content.userInfo = ["entity": LivIDText.written(slot.entity)]
            // No badge: the app's one badge is the proposal-inbox count, by law.
            center.add(
                UNNotificationRequest(
                    identifier: "liv-\(LivIDText.written(slot.entity))", content: content,
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

    /// Only timed dues reach here, so this always names a clock time —
    /// spelled out rather than routed through the date-aware helper,
    /// which returns nothing for a stamp ending 0000 and left a reminder
    /// for a midnight event reading just "due" (review, 2026-08-06).
    private static func body(due: Int64) -> String {
        "due " + Civil.clock(due % 10_000)
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
            let id = LivIDText.read(raw)
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
