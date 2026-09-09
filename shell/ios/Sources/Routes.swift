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
    /// A capture. With NOTHING in it, a new note with the caret in it —
    /// the same door `+` opens. With a payload (`?text=`, `?url=`, or
    /// both), the text is SAVED first and then shown: a catch is not a
    /// draft. Either way the note is an Inbox capture.
    ///
    /// The payload is the half of "catching things from other apps" a
    /// URL scheme can do without a share extension (2026-09-09). Until
    /// then another app could open Liv to a blank, not hand it a
    /// sentence — which the thesis says makes it nobody's first reflex,
    /// however good the capture screen is.
    case capture(String?)
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
            self = .capture(Self.payload(of: url))
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

    /// The catch itself: `?text=` and/or `?url=`, each trimmed, joined on
    /// one line break with the words first, nil when there is nothing to
    /// catch. A blank payload is a bare capture, not an empty note with a
    /// space in it — `liv_capture_at` refuses empty text anyway, so the
    /// door decides before the box has to.
    ///
    /// Only `capture` reads this: a payload on any other route is
    /// ignored, on the same rule that drops an unknown host — a link
    /// from another app does not get to smuggle text onto a surface that
    /// did not ask for it.
    private static func payload(of url: URL) -> String? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func item(_ name: String) -> String? {
            let raw = items.first { $0.name.lowercased() == name }?.value ?? ""
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let parts = [item("text"), item("url")].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}

// MARK: - self-check (run: simctl launch … -routes.selfcheck 1)

/// EVERY SHAPE, NO DESK. `Route.init?` has said "PARSE ONLY — no side
/// effects, so the suite can check every shape" since the door was
/// built, and no suite did until 2026-09-09. These are the shapes
/// `drive.sh routes` cannot cheaply reach (a wrong scheme, a payload on
/// the wrong host) plus the ones it can, so a parser regression is
/// caught in a second rather than in a boot.
func livRoutesSelfCheck() -> [String] {
    var fail: [String] = []
    func check(_ label: String, _ ok: Bool) { if !ok { fail.append(label) } }
    func route(_ s: String) -> Route? { URL(string: s).flatMap(Route.init) }

    check("bare capture", route("liv://capture") == .capture(nil))
    check("photo", route("liv://capture/photo") == .capturePhoto)
    check("a view", route("liv://inbox") == .view(.inbox))
    check("an entity", route("liv://entity/42") == .entity(42))
    check("a bad entity id is nil", route("liv://entity/x") == nil)
    check("unknown host is nil", route("liv://nonsense") == nil)
    check("wrong scheme is nil", route("http://capture") == nil)
    check("scheme is case-blind", route("LIV://capture") == .capture(nil))

    // THE PAYLOAD.
    check("text", route("liv://capture?text=hello%20there") == .capture("hello there"))
    check("url", route("liv://capture?url=https%3A%2F%2Fx.y%2Fz") == .capture("https://x.y/z"))
    check("both, words first", route("liv://capture?url=b&text=a") == .capture("a\nb"))
    check("trimmed", route("liv://capture?text=%20%20a%20%20") == .capture("a"))
    check("blank is a bare capture", route("liv://capture?text=%20%20") == .capture(nil))
    check("payload on a view is ignored", route("liv://inbox?text=x") == .view(.inbox))
    check("payload on photo is ignored", route("liv://capture/photo?text=x") == .capturePhoto)
    return fail
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
