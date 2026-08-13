// liv iOS — the panel drag, as a real UIKit recognizer.
//
// The SwiftUI version had a flaw the owner caught (2026-08-09):
// "dragging over interactive elements should not trigger them." A
// simultaneous SwiftUI drag runs ALONGSIDE every button under the
// finger, so a drag that started on a library row both dragged the
// panel and opened Tasks. SwiftUI has no way to take a touch back.
// UIKit does: a recognizer with `cancelsTouchesInView` cancels every
// view's touch at the exact moment it claims the gesture — buttons
// under the finger die the instant the drag becomes a drag, and a
// plain tap (which never latches) still presses them.
//
// The recognizer is custom rather than a UIPanGestureRecognizer
// because the LATCH must decide when `.began` fires: a pan begins
// after ~10pt in any direction, which would cancel button touches on
// gestures that were never going to be panel drags. This one stays in
// `.possible` until the movement is horizontal, deliberate, and
// allowed to claim a panel — the same gate the SwiftUI version had —
// and only then begins.
//
// Installed on the WINDOW, the HourGridDrag recipe (design/ios.md rev
// 7): recognizers on SwiftUI's own views are never offered the touch.

import SwiftUI
import UIKit

final class PanelPanRecognizer: UIGestureRecognizer {
    /// Veto at touch time, BEFORE any movement: is the desk the active
    /// surface, and is this a place a panel drag may start (not a
    /// horizontal scroller, not text-selection chrome)?
    var mayStart: (CGPoint) -> Bool = { _ in true }
    /// Veto at latch time: is there a panel to claim in this direction?
    var mayClaim: (CGFloat) -> Bool = { _ in true }

    private(set) var startPoint: CGPoint = .zero
    private(set) var translationX: CGFloat = 0
    /// Points per second, from the last two samples — the flick test.
    private(set) var velocityX: CGFloat = 0
    private var lastSample: (time: TimeInterval, x: CGFloat)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .possible, touches.count == 1, let touch = touches.first,
            event.touches(for: self)?.count == 1
        else {
            state = .failed
            return
        }
        let p = touch.location(in: nil)
        guard mayStart(p) else {
            state = .failed
            return
        }
        startPoint = p
        translationX = 0
        velocityX = 0
        lastSample = (touch.timestamp, p.x)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        let p = touch.location(in: nil)
        let dx = p.x - startPoint.x
        let dy = p.y - startPoint.y

        if let last = lastSample, touch.timestamp > last.time {
            velocityX = (p.x - last.x) / CGFloat(touch.timestamp - last.time)
        }
        lastSample = (touch.timestamp, p.x)

        switch state {
        case .possible:
            // Vertical dominance early = this is a scroll; get out of the
            // way for good.
            if abs(dy) > 12, abs(dy) > abs(dx) {
                state = .failed
                return
            }
            // The latch: horizontal, deliberate, and a panel to claim.
            if abs(dx) > 18, abs(dx) > 2 * abs(dy) {
                guard mayClaim(dx) else {
                    state = .failed
                    return
                }
                translationX = dx
                state = .began
            }
        case .began, .changed:
            translationX = dx
            state = .changed
        default:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        state = state == .possible ? .failed : .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = state == .possible ? .failed : .cancelled
    }

    override func reset() {
        super.reset()
        translationX = 0
        velocityX = 0
        lastSample = nil
    }
}

/// Zero-sized installer, invisible to hit-testing (the HourGridDrag
/// idiom). DeskHost owns the drag's meaning; this owns its mechanics.
struct PanelDragInstaller: UIViewRepresentable {
    /// The desk is frontmost — nothing covers it. Read live; the window
    /// recognizer would otherwise drag panels invisibly behind a
    /// full-screen view.
    let active: () -> Bool
    /// A drag moving `dx` may claim a panel (something to open or close
    /// in that direction).
    let mayClaim: (CGFloat) -> Bool
    let onLatch: (CGFloat) -> Void
    let onMove: (CGFloat) -> Void
    let onEnd: (_ translation: CGFloat, _ velocity: CGFloat) -> Void

    func makeUIView(context: Context) -> PanelDragHost {
        let host = PanelDragHost()
        host.coordinator = context.coordinator
        return host
    }

    func updateUIView(_ host: PanelDragHost, context: Context) {
        context.coordinator.active = active
        context.coordinator.mayClaim = mayClaim
        context.coordinator.onLatch = onLatch
        context.coordinator.onMove = onMove
        context.coordinator.onEnd = onEnd
        host.attachIfNeeded()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var active: () -> Bool = { true }
        var mayClaim: (CGFloat) -> Bool = { _ in true }
        var onLatch: (CGFloat) -> Void = { _ in }
        var onMove: (CGFloat) -> Void = { _ in }
        var onEnd: (CGFloat, CGFloat) -> Void = { _, _ in }
        weak var window: UIWindow?

        /// Places a panel drag must not start:
        /// - inside a HORIZONTALLY scrollable area (the editor's
        ///   toolbar, chip rows) — a horizontal gesture there is that
        ///   view's scroll;
        /// - on text-selection chrome (handles, the loupe) — extending a
        ///   selection across a line must never move a panel, the
        ///   guarantee the old flick gate gave (audit, 2026-08-04).
        func startAllowed(_ point: CGPoint) -> Bool {
            guard active(), let window else { return false }
            // The screen's edges belong to the panels, whatever sits
            // under them — a file tab is one full-bleed zoomable
            // preview, and without this a panel could not be dragged in
            // at all while one was open (found live, 2026-08-09).
            if point.x < 24 || point.x > window.bounds.width - 24 {
                return true
            }
            var view = window.hitTest(point, with: nil)
            while let v = view {
                let name = String(describing: type(of: v))
                if name.contains("Selection") || name.contains("Loupe")
                    || name.contains("Magnif")
                {
                    return false
                }
                if let scroll = v as? UIScrollView,
                    scroll.contentSize.width > scroll.bounds.width + 1
                {
                    return false
                }
                view = v.superview
            }
            return true
        }

        /// MUST be true — refusing simultaneity starves the scroll pans
        /// entirely (the HourGridDrag lesson, found live 2026-08-05).
        /// This does NOT protect buttons; nothing at the UIKit layer
        /// does. SwiftUI's touch forwarding ignores touch cancellation,
        /// recognizer exclusion, and delayed delivery alike (all three
        /// tried and beaten, 2026-08-09). The protection is SwiftUI's
        /// own: DeskHost disables its whole tree while a drag is
        /// latched, which cancels any in-flight press.
        func gestureRecognizer(
            _ g: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }

        @objc func handle(_ g: PanelPanRecognizer) {
            switch g.state {
            case .began:
                onLatch(g.translationX)
            case .changed:
                onMove(g.translationX)
            case .ended:
                onEnd(g.translationX, g.velocityX)
            case .cancelled, .failed:
                onEnd(0, 0)
            default:
                break
            }
        }
    }
}

final class PanelDragHost: UIView {
    weak var coordinator: PanelDragInstaller.Coordinator?
    private var recognizer: PanelPanRecognizer?

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attachIfNeeded()
    }

    override func removeFromSuperview() {
        if let recognizer { recognizer.view?.removeGestureRecognizer(recognizer) }
        recognizer = nil
        super.removeFromSuperview()
    }

    func attachIfNeeded() {
        guard let coordinator, recognizer == nil, let window else { return }
        coordinator.window = window
        // The bisect door, same as the calendar's: `-drag.off 1`.
        if UserDefaults.standard.bool(forKey: "drag.off") { return }
        let g = PanelPanRecognizer(
            target: coordinator, action: #selector(PanelDragInstaller.Coordinator.handle(_:)))
        g.mayStart = { [weak coordinator] p in coordinator?.startAllowed(p) ?? false }
        g.mayClaim = { [weak coordinator] dx in coordinator?.mayClaim(dx) ?? false }
        g.delegate = coordinator
        // The whole point: when the latch claims the drag, every button
        // under the finger is cancelled. A tap never latches, so taps
        // still press.
        g.cancelsTouchesInView = true
        g.delaysTouchesBegan = false
        window.addGestureRecognizer(g)
        recognizer = g
    }
}
