// lotus — the macOS shell, milestone 4: capture.
//
// A menu-bar agent, a global hotkey, a panel. Hotkey, type, enter, gone —
// the main window never opens, because there is no main window yet.
// The shell orchestrates; it owns no data. Everything it knows about the
// box goes through the three functions in lotus.h.

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A borderless panel that can take the keyboard without activating us.
final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    private var statusItem: NSStatusItem!
    private var panel: CapturePanel!
    private var field: NSTextField!
    private var hotKeyRef: EventHotKeyRef?
    private var window: NSWindow?

    /// The box admits one writer, so the shell never holds it: every
    /// capture, snapshot, and triage opens, acts, closes. The CLI stays
    /// usable while the app runs.
    private let boxPath =
        FileManager.default.homeDirectoryForCurrentUser.path
        + "/Library/Application Support/lotus/lotus.log"

    private lazy var model = BoxModel(path: boxPath)

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        makeStatusItem()
        makePanel()
        registerHotKey()
        makeWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            window?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    // MARK: the main window

    private func makeWindow() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        w.title = "lotus"
        // Unified chrome: the sidebar runs to the top, the traffic lights
        // float over it — the window-chrome decision, made here.
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.setFrameAutosaveName("lotus.main")
        w.contentViewController = NSHostingController(rootView: MainWindow(model: model))
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
    }

    /// The minimal menu: Quit, a working Edit menu for the text fields,
    /// and Close. Not a settings surface — there is no settings surface.
    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit lotus", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(NSMenuItem.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(
            withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu

        NSApp.mainMenu = main
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
        let id = lotus_capture_at(boxPath, text)
        if id == 0 {
            // The log said no — maybe the CLI holds the box this instant.
            // Keep the text on screen: never lose a thought. Enter retries.
            NSSound.beep()
            return
        }
        discardAndHide()
        model.refresh() // the window shows the new scrap at once
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
app.setActivationPolicy(.regular)
app.run()
