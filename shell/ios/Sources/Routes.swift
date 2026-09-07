// liv iOS — THE `liv://` DOOR, and the only way in from outside the app.
//
// design/ios.md §... : "Deep links unchanged: `liv://capture`,
// `liv://capture/photo`, `liv://inbox`, `liv://entity/<id>` (opens as a
// Desk tab), … used by widgets, quick actions, and notifications."
//
// That sentence was the whole specification and it had been true of
// nothing: `CFBundleURLTypes` was absent from both plists and no file in
// the shell had ever seen a `URL` coming IN (Camera opens Settings, which
// is the other direction). `design/what-liv-is-for.md` ranks catching
// things from other apps above any new feature, and the 2026-08-10 gap
// audit sized this at "two plist entries and one handler" — which turned
// out to be exactly right.
//
// WHAT THIS IS NOT. No share extension, no widgets, no App Intents:
// those need a real Xcode project with separate targets, and that
// blocker is theirs alone (design/ios-m1-eval.md). A URL scheme is a key
// in the main bundle's plist and one modifier, and both survive this
// tree's `swiftc Sources/*.swift` + `cp Info.plist` build.

import Foundation

/// One route, parsed. A URL becomes one of these or nothing — an
/// unknown host is dropped in silence rather than guessed at, because
/// the alternative is a link from another app deciding where you land.
enum Route: Equatable {
    /// A new note with the caret in it. The same door `+` opens, so the
    /// note IS an Inbox capture (`createNote` calls `adoptCapture`).
    case capture
    /// The camera, straight to the shutter.
    case capturePhoto
    /// A view, by name. The spec names `liv://inbox`; the other five
    /// come free because they are the same `Feature` enum, and the
    /// spec's own sentence trails off in a "…".
    case view(Feature)
    /// One entity, opened the way anything else opens it — `desk.open`
    /// decides tab or card from the entity's shape, so the spec's
    /// "opens as a Desk tab" comes out right for a note and correctly
    /// opens a card for a task.
    case entity(UInt64)

    /// PARSE ONLY — no side effects, so the suite can check every shape
    /// without a running desk.
    ///
    /// `liv://capture/photo` is a host with a path, and
    /// `liv://entity/<id>` is a host with an id in the path; the rest
    /// are bare hosts. Anything else is nil.
    init?(_ url: URL) {
        guard url.scheme?.lowercased() == "liv" else { return nil }
        let host = (url.host ?? "").lowercased()
        // `pathComponents` leads with "/" for a non-empty path.
        let rest = url.pathComponents.filter { $0 != "/" }
        switch (host, rest.first?.lowercased()) {
        case ("capture", nil):
            self = .capture
        case ("capture", "photo"):
            self = .capturePhoto
        case ("entity", let id?):
            guard let n = UInt64(id) else { return nil }
            self = .entity(n)
        case (let name, nil):
            guard let feature = Feature(rawValue: name) else { return nil }
            self = .view(feature)
        default:
            return nil
        }
    }
}

/// THE DOOR ITSELF: parks what it cannot yet do, and does the rest.
///
/// COLD LAUNCH IS THE WHOLE DIFFICULTY. A link tapped in Mail launches
/// the app and `onOpenURL` fires before `DeskHost`'s `.onAppear` has
/// wired `desk.newNote`, so a `liv://capture` on a cold launch would
/// call nil and do nothing at all. `Notify` met this exact problem with
/// a cold notification tap and solved it by parking the id until the
/// wiring assigns itself; this copies that shape rather than inventing a
/// second one (standing rule 4).
///
/// Two of the four need no parking — `go` and `open` work on a bare
/// model — but they are parked too when the chrome is not up yet, so
/// there is one rule and not a table of exceptions.
final class Routes {
    static let shared = Routes()

    /// Set by the chrome once its closures exist. Assigning it flushes
    /// whatever arrived before the app was ready.
    var apply: ((Route) -> Void)? {
        didSet {
            guard let apply, let waiting = pending else { return }
            pending = nil
            apply(waiting)
        }
    }
    private var pending: Route?

    /// ONE link at a time. A second arriving before the first is applied
    /// replaces it: two links tapped in the same instant is not a real
    /// case, and a queue would land you on two surfaces in a row.
    func handle(_ url: URL) {
        guard let route = Route(url) else { return }
        if let apply {
            apply(route)
        } else {
            pending = route
        }
    }
}
