// liv iOS — where the box lives. The App Group container, so the share
// extension and widgets read the same place; the app's own Application
// Support when no group entitlement resolves.

import Foundation

enum BoxPath {
    /// LIV_BOX_PATH wins (simulator rehearsal: it names a `liv.db`). Else
    /// `<container>/liv/liv.db`, intermediate dirs created.
    ///
    /// THE ENGINE'S FILE, named directly (stage 5, 2026-09-29). Until then
    /// this named the core-era `liv.log` and the box opened the `liv.db`
    /// beside it — the same file this names now, so no box moved.
    static func resolve() -> String {
        let fm = FileManager.default
        if let env = ProcessInfo.processInfo.environment["LIV_BOX_PATH"], !env.isEmpty {
            let dir = URL(fileURLWithPath: env).deletingLastPathComponent()
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return env
        }
        let base =
            LivGroup.container
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("liv", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("liv.db").path
    }
}
