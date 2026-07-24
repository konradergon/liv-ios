// liv iOS — where the box lives. The App Group container so the share
// extension and widgets read the same log; the app's own Application
// Support when no group entitlement resolves.

import Foundation

enum BoxPath {
    /// LIV_BOX_PATH wins (simulator rehearsal). Else
    /// <container>/liv/liv.log, intermediate dirs created.
    static func resolve() -> String {
        let fm = FileManager.default
        if let env = ProcessInfo.processInfo.environment["LIV_BOX_PATH"], !env.isEmpty {
            let dir = URL(fileURLWithPath: env).deletingLastPathComponent()
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return env
        }
        let base =
            fm.containerURL(forSecurityApplicationGroupIdentifier: "group.liv.app")
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("liv", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("liv.log").path
    }
}
