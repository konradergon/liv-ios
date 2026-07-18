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
    /// The rehearsal harness (P19c, H6): LOTUS_BOX_PATH points the whole app
    /// at any box — the onboarding tour is rehearsed on throwaway boxes from
    /// the shell, end to end, instead of being discovered once at the finish.
    private let boxPath =
        ProcessInfo.processInfo.environment["LOTUS_BOX_PATH"]
        ?? FileManager.default.homeDirectoryForCurrentUser.path
            + "/Library/Application Support/lotus/lotus.log"

    private lazy var model = BoxModel(path: boxPath)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The theme engine (P20a): apply the persisted theme — migrating
        // the P19 light/dark pref on first boot — before any window draws.
        ThemeCore.shared.boot()
        buildMenu()
        makeStatusItem()
        makePanel()
        registerHotKey()
        makeWindow()
        NSApp.activate(ignoringOtherApps: true)
        // Complete any quit flush that failed last time — through the
        // same fingerprinted door as every save. A draft the box refuses
        // (stale, or its note gone) opens its editor so the user's own
        // words resolve visibly; a journal is never silently orphaned.
        model.replayDrafts { draft in
            NotificationCenter.default.post(name: .lotusOpenStaleDraft, object: draft)
        }
    }

    /// Quit waits for the draft — words or a typed name: a few tries,
    /// then the journal. Nothing typed ever dies with the process.
    /// The reply must come after this method returns .terminateLater,
    /// so it is always deferred to the next runloop turn.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let active = EditorRegistry.shared.active, active.needsQuitFlush else {
            return .terminateNow
        }
        active.flushForQuit {
            DispatchQueue.main.async {
                NSApp.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
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
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        w.title = "lotus"
        // Hidden title, traffic lights overlaying the app's own top band.
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.isMovableByWindowBackground = true
        w.setFrameAutosaveName("lotus.main")
        let hosting = NSHostingController(rootView: WindowChrome(model: model))
        // Let the content run under the titlebar so the header controls
        // and the tab strip sit in the traffic-light band at the very
        // top (Claude-style), not a row below it.
        if #available(macOS 13.3, *) {
            hosting.safeAreaRegions = []
        }
        w.contentViewController = hosting
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w

        // Coming back to the window re-reads the box: a CLI capture made
        // while we were behind shows the moment we are front again.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: w, queue: .main
        ) { [weak self] _ in
            self?.model.refresh()
        }
        // Leaving the window flushes the draft — the typed name too: the
        // box catches up the moment attention moves elsewhere.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: w, queue: .main
        ) { _ in
            guard let active = EditorRegistry.shared.active else { return }
            active.renameIfNeeded()
            active.flush()
        }
    }

    @objc private func focusSearch() {
        window?.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .lotusFocusSearch, object: nil)
    }

    @objc private func focusCapture() {
        window?.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .lotusFocusCapture, object: nil)
    }

    @objc private func openDailyNote() {
        window?.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .lotusOpenDailyNote, object: nil)
    }

    /// ⌘⌥Z is always the box. Under a dirty draft it flushes first —
    /// box undo over unsaved words is unreachable by construction.
    @objc private func undoLastChange() {
        if let active = EditorRegistry.shared.active {
            active.flushThenBoxUndo()
        } else {
            model.undo()
        }
    }

    /// ⌘Z, routed: the focused text's own undo wins — the field editor,
    /// the editor's per-view manager, any text. With no text focus,
    /// plain undo means the box's last transaction.
    @objc func undo(_ sender: Any?) {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView {
            text.undoManager?.undo()
            return
        }
        undoLastChange()
    }

    @objc private func newNote() {
        window?.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .lotusNewNote, object: nil)
    }

    /// The native menu, Liv's shape (§2.1): custom items carry NO
    /// accelerators — the app's own key dispatch owns shortcuts, and a
    /// native accelerator would double-fire.
    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        let settingsItem = appMenu.addItem(
            withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: "Hide Liv", action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h")
        let hideOthers = appMenu.addItem(
            withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(
            withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        // The brick-proof escape hatch (P19g): a FIXED menu item no keymap
        // can touch — shortcuts reset even if every chord is scrambled.
        let resetShortcutsItem = appMenu.addItem(
            withTitle: "Reset Shortcuts", action: #selector(resetShortcuts), keyEquivalent: "")
        resetShortcutsItem.target = self
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(
            withTitle: "Quit Liv", action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem()
        main.addItem(fileItem)
        let file = NSMenu(title: "File")
        file.autoenablesItems = false
        let note = file.addItem(
            withTitle: "New Note", action: #selector(newNote), keyEquivalent: "")
        note.target = self
        // ⌘⌥D is owned by the CommandRegistry (daily:open-today), which is
        // correctly suppressed behind modals/overlays; a native menu
        // key-equivalent would punch through that guard (the review), so the
        // item stays clickable without an accelerator.
        let daily = file.addItem(
            withTitle: "Daily Note", action: #selector(openDailyNote), keyEquivalent: "")
        daily.target = self
        fileItem.submenu = file

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        // Explicit target: a nil-targeted undo: never falls past the key
        // window — NSWindow answers it with its own empty manager and ⌘Z
        // goes dead. We route it ourselves: focused text first, then
        // the box.
        let undoItem = edit.addItem(
            withTitle: "Undo", action: #selector(undo(_:)), keyEquivalent: "z")
        undoItem.target = self
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(NSMenuItem.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(
            withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let view = NSMenu(title: "View")
        view.autoenablesItems = false
        let home = view.addItem(withTitle: "Home", action: #selector(goHome), keyEquivalent: "")
        home.target = self
        let dashboard = view.addItem(withTitle: "Dashboard", action: nil, keyEquivalent: "")
        dashboard.isEnabled = false  // Mission Control arrives with P16
        let inbox = view.addItem(withTitle: "Inbox", action: #selector(goInbox), keyEquivalent: "")
        inbox.target = self
        view.addItem(NSMenuItem.separator())
        let search = view.addItem(
            withTitle: "Search…", action: #selector(focusSearch), keyEquivalent: "f")
        search.target = self  // ⌘F canonical (P13)
        // "Command Palette…" is REFUSED (the constitution's palette ban;
        // ⌘F searches entities) — the item is gone, not disabled.
        // P20b: View gains the mockup's items. Mission Control's ⇧⇥ is
        // owned by the CommandRegistry (the ⌘⌥D review rule) — clickable,
        // no accelerator.
        view.addItem(NSMenuItem.separator())
        let mission = view.addItem(
            withTitle: "Mission Control", action: #selector(goDashboard), keyEquivalent: "")
        mission.target = self
        let tourView = view.addItem(
            withTitle: "✦ Take the Tour", action: #selector(replayTour), keyEquivalent: "")
        tourView.target = self
        viewItem.submenu = view

        // P20b: the Go menu (the mockup draws one; contents = the sim's
        // nav verbs). ⌥←/⌥→ live HERE as key equivalents — the inspector's
        // scoped focus chords consume them first when it owns the keyboard,
        // and the menu answers everywhere else.
        let goItem = NSMenuItem()
        main.addItem(goItem)
        let go = NSMenu(title: "Go")
        go.autoenablesItems = false
        let goHomeItem = go.addItem(
            withTitle: "Home", action: #selector(goHome), keyEquivalent: "")
        goHomeItem.target = self
        let goInboxItem = go.addItem(
            withTitle: "Inbox", action: #selector(goInbox), keyEquivalent: "")
        goInboxItem.target = self
        let goDaily = go.addItem(
            withTitle: "Daily Note", action: #selector(openDailyNote), keyEquivalent: "")
        goDaily.target = self
        go.addItem(NSMenuItem.separator())
        let back = go.addItem(
            withTitle: "Back", action: #selector(navBack),
            keyEquivalent: String(UnicodeScalar(NSLeftArrowFunctionKey)!))
        back.keyEquivalentModifierMask = [.option]
        back.target = self
        let forward = go.addItem(
            withTitle: "Forward", action: #selector(navForward),
            keyEquivalent: String(UnicodeScalar(NSRightArrowFunctionKey)!))
        forward.keyEquivalentModifierMask = [.option]
        forward.target = self
        goItem.submenu = go

        let helpItem = NSMenuItem()
        main.addItem(helpItem)
        let help = NSMenu(title: "Help")
        help.autoenablesItems = false
        let tour = help.addItem(
            withTitle: "Replay the Tour", action: #selector(replayTour), keyEquivalent: "")
        tour.target = self
        helpItem.submenu = help
        NSApp.helpMenu = help

        NSApp.mainMenu = main
    }

    @objc private func replayTour() {
        window?.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .lotusReplayTour, object: nil)
    }

    @objc private func openSettings() {
        window?.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: Notification.Name("lotus.openSettings"), object: nil)
    }

    @objc private func goDashboard() {
        window?.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: Notification.Name("lotus.goDashboard"), object: nil)
    }

    @objc private func navBack() {
        NotificationCenter.default.post(name: Notification.Name("lotus.navBack"), object: nil)
    }

    @objc private func navForward() {
        NotificationCenter.default.post(name: Notification.Name("lotus.navForward"), object: nil)
    }

    @objc private func goHome() {
        window?.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .lotusGoHome, object: nil)
    }

    @objc private func goInbox() {
        window?.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .lotusGoInbox, object: nil)
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
            withTitle: "Quit Liv", action: #selector(NSApplication.terminate(_:)),
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
        // Through the model's serial lane, so the panel never races the
        // window for the box. The draft clears only when the log said yes:
        // never lose a thought. A beep means Enter retries.
        model.capture(text) { [weak self] ok in
            if ok {
                self?.discardAndHide()
            }
        }
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

    /// P19g: the fixed escape hatch — clears every chord override.
    @objc private func resetShortcuts() {
        CommandRegistry.shared.resetOverrides()
    }

    // MARK: the hotkey

    /// ⌃⌥Space by default, via Carbon — no permissions dialog, works
    /// everywhere. The binding is a budgeted setting (P19d): the KeyRecorder
    /// writes `app.capture.hotkey.v1` and posts `.lotusRebindCapture`; the
    /// hotkey re-registers LIVE, no relaunch.
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
        applyCaptureHotKey()
        NotificationCenter.default.addObserver(
            forName: Notification.Name("lotus.rebindCapture"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.applyCaptureHotKey()
        }
        // P20b: the rail's Capture door fronts the same panel the global
        // hotkey does — one doorway, two knocks.
        NotificationCenter.default.addObserver(
            forName: Notification.Name("lotus.toggleCapture"), object: nil, queue: .main
        ) { [weak self] _ in
            self?.togglePanel()
        }
    }

    /// (Re-)register from the pref — the old registration is torn down first
    /// so a rebind never leaves a ghost chord.
    private func applyCaptureHotKey() {
        if let existing = hotKeyRef {
            UnregisterEventHotKey(existing)
            hotKeyRef = nil
        }
        var keyCode = UInt32(kVK_Space)
        var modifiers = UInt32(controlKey | optionKey)
        if let saved = UserDefaults.standard.dictionary(forKey: "app.capture.hotkey.v1") {
            // Total validation, the keymap's own rule (P19 review): a
            // negative/oversized value would TRAP in UInt32(_:) — a launch
            // crash loop. A corrupted pref self-heals to the default.
            if let code = saved["keyCode"] as? Int,
                let mods = saved["modifiers"] as? Int,
                let validCode = UInt32(exactly: code),
                let validMods = UInt32(exactly: mods)
            {
                keyCode = validCode
                modifiers = validMods
            } else {
                NSLog("lotus: app.capture.hotkey.v1 malformed — back on ⌃⌥Space")
                UserDefaults.standard.removeObject(forKey: "app.capture.hotkey.v1")
            }
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C4F_5453), id: 1)  // "LOTS"
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef)
        if status != noErr && keyCode != UInt32(kVK_Space) {
            // The saved chord can't register (stale key code from another
            // keyboard, say) — fall back rather than launch capture-less.
            NSLog("lotus: capture hotkey rejected (\(status)) — back on ⌃⌥Space")
            UserDefaults.standard.removeObject(forKey: "app.capture.hotkey.v1")
            RegisterEventHotKey(
                UInt32(kVK_Space), UInt32(controlKey | optionKey), hotKeyID,
                GetEventDispatcherTarget(), 0, &hotKeyRef)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
