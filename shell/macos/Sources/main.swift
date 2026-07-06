// lotus — the macOS shell, milestone 4: capture.
//
// A menu-bar agent, a global hotkey, a panel. Hotkey, type, enter, gone —
// the main window never opens, because there is no main window yet.
// The shell orchestrates; it owns no data. Everything it knows about the
// box goes through the three functions in lotus.h.

import AppKit
import Carbon.HIToolbox

/// A borderless panel that can take the keyboard without activating us.
final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    private var statusItem: NSStatusItem!
    private var panel: CapturePanel!
    private var field: NSTextField!
    private var session: OpaquePointer?
    private var hotKeyRef: EventHotKeyRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = home + "/Library/Application Support/lotus/lotus.log"
        session = lotus_open(path)
        guard session != nil else {
            let alert = NSAlert()
            alert.messageText = "lotus cannot open its box"
            alert.informativeText =
                "Another copy of lotus may already be running, "
                + "or the log at \(path) is unreadable."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        makeStatusItem()
        makePanel()
        registerHotKey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        lotus_close(session)
        session = nil
    }

    // MARK: menu bar

    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "❧"

        let menu = NSMenu()
        let capture = menu.addItem(
            withTitle: "Capture  ⌃⌥Space", action: #selector(togglePanel), keyEquivalent: "")
        capture.target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            withTitle: "Quit lotus", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        statusItem.menu = menu
    }

    // MARK: the panel

    private func makePanel() {
        let width: CGFloat = 560
        let height: CGFloat = 48

        panel = CapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear

        let container = NSVisualEffectView(
            frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.material = .hudWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 10

        field = NSTextField(
            frame: NSRect(x: 14, y: 10, width: width - 28, height: height - 20))
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 20)
        field.placeholderString = "Capture…"
        field.delegate = self
        field.target = self
        field.action = #selector(commit)
        (field.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = false
        container.addSubview(field)
        panel.contentView = container
    }

    @objc func togglePanel() {
        if panel.isVisible {
            if panel.isKeyWindow {
                hidePanel()  // the draft survives; only Esc and Enter clear
            } else {
                showPanel()  // refocus a lingering panel instead of wiping it
            }
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let x = visible.midX - panel.frame.width / 2
            let y = visible.minY + visible.height * 0.68
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
    }

    /// Hiding never clears: a draft survives every hide and reappears on
    /// the next summon. Discarding is explicit — Esc, or a completed commit.
    private func hidePanel() {
        panel.orderOut(nil)
    }

    private func discardAndHide() {
        field.stringValue = ""
        hidePanel()
    }

    @objc private func commit() {
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            discardAndHide()
            return
        }
        let id = lotus_capture(session, text)
        if id == 0 {
            // The log said no. Keep the text on screen — never lose a thought.
            NSSound.beep()
            return
        }
        discardAndHide()
    }

    /// Esc closes; the draft is discarded deliberately, by the user.
    func control(
        _ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector
    ) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            discardAndHide()
            return true
        }
        return false
    }

    // MARK: the hotkey

    /// ⌃⌥Space, via Carbon — no permissions dialog, works everywhere.
    /// The binding is one of the budgeted settings; this is its default.
    private func registerHotKey() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData in
                guard let userData = userData else { return noErr }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData)
                    .takeUnretainedValue()
                DispatchQueue.main.async { delegate.togglePanel() }
                return noErr
            },
            1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            nil)

        let hotKeyID = EventHotKeyID(signature: OSType(0x4C4F_5453), id: 1)  // "LOTS"
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
