// liv — the vault projection's shell surface (P20j.7): the read-only
// FSEvents watcher and the divergence banner. The watcher NEVER writes —
// it only schedules a debounced sync (the same verb the user triggers),
// and sync is echo-proof (kill-shot B: an own-write never re-ingests), so
// no write loop is constructible. Scan-at-open is canonical; the watcher
// is the convenience that keeps a cloud-synced folder current.

import AppKit
import SwiftUI

// MARK: - one divergence finding (the wire shape of liv_vault_findings_at)

struct VaultFinding: Decodable, Identifiable, Equatable {
    let kind: String
    let entityId: UInt64?
    let path: String?
    let count: Int?

    enum CodingKeys: String, CodingKey {
        case kind, path, count
        case entityId = "id"
    }

    var id: String { "\(kind)|\(path ?? "")|\(entityId ?? 0)" }
}

// MARK: - the read-only FSEvents watcher

final class VaultWatcher {
    private let root: String
    private let onChange: () -> Void
    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?

    init(root: String, onChange: @escaping () -> Void) {
        self.root = root
        self.onChange = onChange
    }

    func start() {
        guard stream == nil else { return }
        var ctx = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        // The callback is a bare C function pointer — no captures; it
        // recovers `self` through the context info and marks the change.
        let callback: FSEventStreamCallback = { _, info, count, pathsPtr, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<VaultWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(pathsPtr, to: UnsafePointer<UnsafePointer<CChar>>.self)
            for index in 0..<count {
                let path = String(cString: paths[index])
                // Exclude our OWN writes (`.liv/` = manifest, tmp, box, lock);
                // a change anywhere else is worth a scan.
                if !path.contains("/.liv/") {
                    watcher.schedule()
                    return
                }
            }
        }
        // 0.8s FSEvents latency coalesces a storm into few callbacks; the
        // work-item debounce below collapses those into ONE scan.
        stream = FSEventStreamCreate(
            nil, callback, &ctx,
            [root] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.8,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagFileEvents))
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    /// Every event cancels and reschedules the ONE pending scan, so any
    /// burst — 10 events or 10 000 — fires exactly one sync once quiet.
    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func stop() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        pending?.cancel()
        pending = nil
    }

    deinit { stop() }
}

// MARK: - the divergence banner

/// Shown only when unresolved divergences exist. Conflicts carry the
/// editor's keep-mine/take-theirs grammar; a missing file offers restore
/// or trash; a mass burst expands on demand. Nothing here was auto-applied.
struct DivergenceBanner: View {
    @ObservedObject var model: BoxModel
    @State private var expanded = false

    var body: some View {
        if !model.vaultFindings.isEmpty {
            VStack(spacing: 0) {
                header
                if expanded {
                    VStack(spacing: 4) {
                        ForEach(model.vaultFindings) { finding in
                            row(finding)
                        }
                    }
                    .padding(.horizontal, 12).padding(.bottom, 8)
                }
            }
            .background(Theme.warning.opacity(0.08))
            .overlay(Rectangle().fill(Theme.warning.opacity(0.5)).frame(height: 1), alignment: .bottom)
        }
    }

    private var header: some View {
        Button { expanded.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11)).foregroundColor(Theme.warning)
                Text(summary).font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(Theme.text2)
                Text("nothing was applied — you decide")
                    .font(.system(size: 10)).foregroundColor(Theme.mutedFg)
                Spacer()
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9)).foregroundColor(Theme.mutedFg)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var summary: String {
        if let mass = model.vaultFindings.first(where: { $0.kind == "masschange" }) {
            return "\(mass.count ?? 0) files changed at once on disk"
        }
        let n = model.vaultFindings.count
        return "\(n) file\(n == 1 ? "" : "s") on disk diverge from the vault"
    }

    @ViewBuilder
    private func row(_ finding: VaultFinding) -> some View {
        HStack(spacing: 8) {
            Text(finding.path ?? "—")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Theme.text2).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            switch finding.kind {
            case "conflict":
                Text("changed both here and on disk")
                    .font(.system(size: 9.5)).foregroundColor(Theme.mutedFg)
                verdict("Keep mine", finding, "keep-app")
                verdict("Take disk", finding, "take-disk")
            case "missing":
                Text("the file is gone from disk")
                    .font(.system(size: 9.5)).foregroundColor(Theme.mutedFg)
                verdict("Restore it", finding, "keep-app")
                verdict("Trash it", finding, "trash")
            case "masschange":
                Button("Review individually") {
                    model.refreshVaultFindings(all: true)
                }
                .buttonStyle(.plain).font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.accent)
            case "orphan":
                Text("a stray copy — re-project reclaims it")
                    .font(.system(size: 9.5)).foregroundColor(Theme.mutedFg)
            default:
                // edited/newfile shouldn't linger (sync ingests them), but
                // if surfaced via `all`, offer to take the disk version.
                verdict("Take disk", finding, "take-disk")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.surface))
    }

    private func verdict(_ label: String, _ finding: VaultFinding, _ verdict: String) -> some View {
        Button(label) {
            guard let id = finding.entityId, let path = finding.path else { return }
            model.vaultResolve(id: id, path: path, verdict: verdict)
        }
        .buttonStyle(.plain)
        .font(.system(size: 10, weight: .medium))
        .foregroundColor(verdict == "trash" ? Color(nsColor: .systemRed) : Theme.accent)
        .disabled(finding.entityId == nil)
    }
}
