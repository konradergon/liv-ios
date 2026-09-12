// liv iOS — THE SHARE SHEET (2026-09-09, owner's word).
//
// Liv in the row of apps every share button shows. This is a share
// extension: a second bundle inside Liv.app, with its own binary, plist
// and entitlements, built by a second swiftc in build.sh — no Xcode
// project, the same as the app itself. What it does is deliberately the
// least it can: read the words and the URL it was handed, write ONE
// text file into the App Group spool (Catch.swift), say so, and go. The
// app turns the file into a capture at its next foreground.
//
// Save-first, nothing asked (design/ios.md §M1, and the thesis: "if you
// can start it, it's saved"). No compose sheet, no chips, no account —
// a share is a two-second gesture and this keeps it one.
//
// UIKit, not SwiftUI, and none of the app's Theme: this binary links
// Foundation and UIKit only, so it stays small enough to launch inside
// an extension's memory ceiling, and it draws with the system's colours
// because it sits over another app's screen, not over Liv's.

import UIKit
import UniformTypeIdentifiers

/// The principal class the extension's plist names. `@objc` with an
/// explicit name so the plist can say `ShareViewController` and be
/// right whatever the Swift module is called.
@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private let card = UIView()
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 14
        card.layer.cornerCurve = .continuous
        card.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .label
        label.textAlignment = .center
        label.numberOfLines = 2
        label.text = "Catching…"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.accessibilityIdentifier = "liv.share.verdict"
        card.addSubview(label)
        view.addSubview(card)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -48),
            label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
            label.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            label.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
        ])

        collect { [weak self] text in self?.finish(text) }
    }

    /// Spool it, say so, leave. The verdict stays up just long enough
    /// to be read: a catch that flashed and vanished would leave you
    /// wondering whether it happened.
    private func finish(_ text: String?) {
        guard let text else {
            return leave("Nothing to catch", after: 1.2, ok: false)
        }
        if Spool.put(text) {
            leave("Saved to Liv", after: 0.7, ok: true)
        } else {
            leave("Could not save", after: 1.2, ok: false)
        }
    }

    private func leave(_ verdict: String, after seconds: Double, ok: Bool) {
        label.text = verdict
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let context = self?.extensionContext else { return }
            if ok {
                context.completeRequest(returningItems: nil)
            } else {
                context.cancelRequest(withError: NSError(domain: "app.liv.ios.share", code: 1))
            }
        }
    }

    /// What was handed over: the words and/or the URL. Safari hands a
    /// page as a URL, sometimes with its title as text; a selection
    /// arrives as text alone; Notes and Mail put the words on the item
    /// itself rather than on an attachment. All three are read, and
    /// `Catch.text` decides what they become.
    private func collect(_ done: @escaping (String?) -> Void) {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        var words: String? = items.first?.attributedContentText?.string
        var url: String?
        let lock = NSLock()
        let group = DispatchGroup()

        for provider in items.flatMap({ $0.attachments ?? [] }) {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                    let found = (item as? URL)?.absoluteString
                        ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
                    lock.lock()
                    if url == nil { url = found }
                    lock.unlock()
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                    let found = (item as? String)
                        ?? (item as? NSAttributedString)?.string
                        ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
                    lock.lock()
                    if words == nil { words = found }
                    lock.unlock()
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            lock.lock()
            let caught = Catch.text(words, url)
            lock.unlock()
            done(caught)
        }
    }
}
