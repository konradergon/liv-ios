// liv iOS — the satellite outbox (design/ios.md §2.1–2.3): the phone's
// side of the wire. A persistent ledger tracks every entity created on
// this phone; closing a batch serializes the pending ones into one
// write-once batch-<ULID>.json + content-addressed media, ships them into
// the satellite root, and the desk's ack flips them Delivered. Re-delivery
// is dedup-safe by external-id (ios://<device>/<uuid>), so the only rules
// that matter here: shipped entries never re-batch, a failed copy leaves
// everything pending for the next close, every satellite write is
// tmp+rename, and nothing here ever touches a path containing ".liv" or
// ".trash". No retries, no queues — the lifecycle hooks are the schedule.
//
// All entry points are main-thread (scenePhase handlers + BoxModel's
// main-queue done callbacks), so the ledger needs no lock.

import CryptoKit
import Foundation
import UIKit
import os

// MARK: - public shapes

/// What the entity was born as on this phone — the wire `kind`. (No
/// create path emits .link yet; the case is the wire's, kept complete.)
enum OutboxKind: String, Codable {
    case idea, task, event, photo, link
}

/// Pending → shipped (batch in the satellite) → delivered (desk acked).
enum OutboxState: String, Codable {
    case pending, shipped, delivered
}

/// One published row for the UI (Settings owns the rendering). Title is
/// resolved at publish time via the app-injected closure. The field set is
/// the agreed observable contract (the OutboxContract stub, now retired).
struct OutboxEntry: Identifiable {
    let id: UInt64  // entity id
    let itemUuid: UUID
    let kind: OutboxKind
    let state: OutboxState
    let title: String
    /// Civil YYYYMMDDHHMM at track time — the newest-first sort key.
    let capturedCivil: Int64
}

// MARK: - ledger records (outbox-ledger.json)

private struct LedgerRecord: Codable {
    /// The item's forever identity half: ios://<device>/<this uuid>.
    var uuid: String
    var state: OutboxState
    var kind: OutboxKind
    /// Civil YYYYMMDDHHMM at track time — the wire's `captured`.
    var captured: Int64
    /// The ULID of the batch this entry shipped in (ack matching).
    var batch: String?
    /// Photos: the shipped media identity, for post-ack cleanup.
    var mediaSha: String?
    var mediaExt: String?

    enum CodingKeys: String, CodingKey {
        case uuid, state, kind, captured, batch
        case mediaSha = "media_sha"
        case mediaExt = "media_ext"
    }
}

private struct LedgerFile: Codable {
    var v: Int
    var entries: [String: LedgerRecord]  // key = decimal entity id
}

// MARK: - wire shapes (THE satellite contract; encoder omits nils)

private struct WireItem: Encodable {
    let uuid: String
    let kind: String
    var text: String? = nil
    var name: String? = nil
    var dueCivil: Int64? = nil
    var dateOnly: Bool? = nil
    var status: String? = nil
    var url: String? = nil
    var mediaSha: String? = nil
    var mediaExt: String? = nil
    var captured: String = ""

    enum CodingKeys: String, CodingKey {
        case uuid, kind, text, name, status, url, captured
        case dueCivil = "due_civil"
        case dateOnly = "date_only"
        case mediaSha = "media_sha"
        case mediaExt = "media_ext"
    }
}

private struct WireBatch: Encodable {
    let v: Int
    let batch: String
    let device: String
    let deviceName: String
    let created: String
    let items: [WireItem]

    enum CodingKeys: String, CodingKey {
        case v, batch, device, created, items
        case deviceName = "device_name"
    }
}

/// The desk's ack — only `batch` matters to the phone; the rest is report.
private struct WireAck: Decodable {
    var batch: String?
}

// MARK: - the outbox

final class Outbox: ObservableObject {
    static let shared = Outbox()

    // MARK: published state (main thread)

    @Published private(set) var pendingCount = 0
    @Published private(set) var lastShipDate: Date?
    /// Newest first. Rebuilt on every ledger change.
    @Published private(set) var entries: [OutboxEntry] = []
    /// The satellite root path. nil = shipping off — entries stay pending,
    /// silently. UserDefaults "satellite.path" wins (the Settings surface
    /// writes it via setSatellitePath); LIV_SATELLITE_PATH is the
    /// simulator-rehearsal door.
    @Published private(set) var satellitePath: String?

    /// Injected by the app (RootView): entityId -> current title. Called
    /// only at publish time, on main.
    var titleResolver: (UInt64) -> String? = { _ in nil } {
        didSet { publish() }
    }

    private var ledger: [UInt64: LedgerRecord]

    private static let log = Logger(subsystem: "app.liv.ios", category: "outbox")
    private static let lastShipKey = "satellite.lastShip"

    private init() {
        ledger = Self.loadLedger()
        lastShipDate = UserDefaults.standard.object(forKey: Self.lastShipKey) as? Date
        satellitePath = Self.resolveSatellitePath()
        publish()
    }

    // MARK: identity + roots

    /// This phone's forever half of every external id. Minted once.
    static var deviceId: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: "satellite.device"), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: "satellite.device")
        return fresh
    }

    /// Device config, never a cell. nil (or empty) clears the setting —
    /// the env-var fallback, if any, then shows through.
    func setSatellitePath(_ path: String?) {
        if let path, !path.isEmpty {
            UserDefaults.standard.set(path, forKey: "satellite.path")
        } else {
            UserDefaults.standard.removeObject(forKey: "satellite.path")
        }
        satellitePath = Self.resolveSatellitePath()
    }

    private static func resolveSatellitePath() -> String? {
        if let stored = UserDefaults.standard.string(forKey: "satellite.path"), !stored.isEmpty {
            return (stored as NSString).expandingTildeInPath
        }
        if let env = ProcessInfo.processInfo.environment["LIV_SATELLITE_PATH"], !env.isEmpty {
            return env
        }
        return nil
    }

    private var satelliteRoot: URL? {
        satellitePath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    // MARK: track — entities enter the ledger at birth

    /// Called from the BoxModel create paths (via `tracking`). Idempotent;
    /// 0 is never an id.
    func track(entityId: UInt64, kind: OutboxKind) {
        guard entityId != 0, ledger[entityId] == nil else { return }
        ledger[entityId] = LedgerRecord(
            uuid: UUID().uuidString, state: .pending, kind: kind,
            captured: Civil.nowStamp())
        saveLedger()
        publish()
    }

    /// The one-line Box.swift hook: wrap a create path's `done` so every
    /// committed entity enters the ledger before the caller sees the id.
    static func tracking(_ kind: OutboxKind, _ done: ((UInt64) -> Void)?) -> (UInt64) -> Void {
        { id in
            if id != 0 { Outbox.shared.track(entityId: id, kind: kind) }
            done?(id)
        }
    }

    // MARK: batch close + ship (scenePhase .background)

    /// Serialize every .pending entry from the snapshot's CURRENT cells,
    /// write batch-<ULID>.json to staging, then ship batch + media into
    /// the satellite root. Shipped entries flip .shipped; any failure
    /// leaves every entry .pending — the next close re-emits them in a
    /// fresh batch, which the desk dedupes by external id.
    func closeBatch(snapshot: Snapshot?) {
        guard let snapshot, let root = satelliteRoot, !Self.denied(root) else { return }

        var rows = [UInt64: EntityRow](minimumCapacity: snapshot.entities?.count ?? 0)
        for row in snapshot.entities ?? [] { rows[row.id] = row }

        var items: [WireItem] = []
        var toShip: [UInt64] = []
        var mediaCopies: [(from: URL, sha: String, ext: String)] = []
        var mediaByEntity: [UInt64: (sha: String, ext: String)] = [:]
        var toDrop: [UInt64] = []
        for (entityId, record) in ledger where record.state == .pending {
            guard let row = rows[entityId] else {
                // Not in the snapshot: a fresh capture may simply outrun
                // the last refresh — wait. An OLD absence means the entity
                // was undone — drop it, it can never ship.
                if Self.stale(record) { toDrop.append(entityId) }
                continue
            }
            if row.trashed == true {
                toDrop.append(entityId)  // deleted before shipping — never ship
                continue
            }
            switch build(record, row: row) {
            case .ship(let item, let media):
                items.append(item)
                toShip.append(entityId)
                if let media {
                    mediaCopies.append(media)
                    mediaByEntity[entityId] = (media.sha, media.ext)
                }
            case .wait:
                continue
            case .drop:
                toDrop.append(entityId)
            }
        }
        for entityId in toDrop { ledger[entityId] = nil }
        guard !items.isEmpty else {
            if !toDrop.isEmpty {
                saveLedger()
                publish()
            }
            return
        }
        items.sort { ($0.captured, $0.uuid) < ($1.captured, $1.uuid) }

        // The batch file, staged first (Application Support/liv/outbox/).
        let ulid = ULID.make()
        let device = Self.deviceId
        let wire = WireBatch(
            v: 1, batch: ulid, device: device,
            deviceName: UIDevice.current.name,
            created: Self.civilString(Civil.nowStamp()), items: items)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(wire) else { return }
        let staged = Self.stagingDir.appendingPathComponent("batch-\(ulid).json")
        guard Self.writeAtomic(data, to: staged) else { return }
        func abort() { try? FileManager.default.removeItem(at: staged) }

        // Ship: media first — the batch file is the desk's commit point,
        // so it must land last (a batch with missing media defers whole).
        let outboxDir = root.appendingPathComponent("outbox", isDirectory: true)
            .appendingPathComponent(device, isDirectory: true)
        let mediaDir = root.appendingPathComponent("media", isDirectory: true)
            .appendingPathComponent(device, isDirectory: true)
        guard Self.ensureDir(outboxDir), Self.ensureDir(mediaDir) else {
            return abort()
        }
        for media in mediaCopies {
            let dest = mediaDir.appendingPathComponent("\(media.sha).\(media.ext)")
            guard Self.copyAtomic(from: media.from, to: dest) else {
                Self.log.notice("media copy failed, batch stays pending: \(media.sha, privacy: .public)")
                return abort()
            }
        }
        let batchDest = outboxDir.appendingPathComponent("batch-\(ulid).json")
        guard Self.copyAtomic(from: staged, to: batchDest) else {
            Self.log.notice("batch copy failed, stays pending: \(ulid, privacy: .public)")
            return abort()
        }
        try? FileManager.default.removeItem(at: staged)  // shipped — staging done

        for entityId in toShip {
            ledger[entityId]?.state = .shipped
            ledger[entityId]?.batch = ulid
            if let media = mediaByEntity[entityId] {
                ledger[entityId]?.mediaSha = media.sha
                ledger[entityId]?.mediaExt = media.ext
            }
        }
        saveLedger()
        lastShipDate = Date()
        UserDefaults.standard.set(lastShipDate, forKey: Self.lastShipKey)
        publish()
        Self.log.info("shipped batch \(ulid, privacy: .public): \(items.count) item(s)")
    }

    // MARK: ack scan (scenePhase .active)

    /// Read ack/<device>/: matching shipped entries flip .delivered, and
    /// this phone deletes its OWN now-redundant batch + media files. Acks
    /// are an optimization — losing them costs a redundant re-drain, never
    /// a duplicate.
    func scanAcks() {
        guard let root = satelliteRoot, !Self.denied(root) else { return }
        let device = Self.deviceId
        let fm = FileManager.default
        let ackDir = root.appendingPathComponent("ack", isDirectory: true)
            .appendingPathComponent(device, isDirectory: true)
        guard let names = try? fm.contentsOfDirectory(atPath: ackDir.path) else { return }
        var acked: Set<String> = []
        for name in names where name.hasPrefix("batch-") && name.hasSuffix(".json") {
            var ulid = String(name.dropFirst("batch-".count).dropLast(".json".count))
            if let data = try? Data(contentsOf: ackDir.appendingPathComponent(name)),
                let ack = try? JSONDecoder().decode(WireAck.self, from: data),
                let batch = ack.batch, !batch.isEmpty
            {
                ulid = batch
            }
            acked.insert(ulid)
        }
        guard !acked.isEmpty else { return }

        var changed = false
        for (entityId, record) in ledger where record.state == .shipped {
            guard let batch = record.batch, acked.contains(batch) else { continue }
            ledger[entityId]?.state = .delivered
            changed = true
        }

        // Own-file cleanup, idempotent. A media file survives while ANY
        // not-yet-delivered entry still references its sha (the same bytes
        // captured twice land in two batches but one satellite file).
        let outboxDir = root.appendingPathComponent("outbox", isDirectory: true)
            .appendingPathComponent(device, isDirectory: true)
        let mediaDir = root.appendingPathComponent("media", isDirectory: true)
            .appendingPathComponent(device, isDirectory: true)
        for ulid in acked {
            let batchFile = outboxDir.appendingPathComponent("batch-\(ulid).json")
            if !Self.denied(batchFile) { try? fm.removeItem(at: batchFile) }
        }
        for record in ledger.values
        where record.state == .delivered && record.batch.map(acked.contains) == true {
            guard let sha = record.mediaSha, let ext = record.mediaExt else { continue }
            let stillNeeded = ledger.values.contains {
                $0.state != .delivered && $0.mediaSha == sha
            }
            guard !stillNeeded else { continue }
            let mediaFile = mediaDir.appendingPathComponent("\(sha).\(ext)")
            if !Self.denied(mediaFile) { try? fm.removeItem(at: mediaFile) }
        }

        if changed {
            saveLedger()
            publish()
        }
    }

    // MARK: item building (snapshot cells -> wire)

    private enum ItemBuild {
        case ship(WireItem, media: (from: URL, sha: String, ext: String)?)
        /// Not shippable in THIS batch; stays pending.
        case wait
        /// Never shippable; leaves the ledger.
        case drop
    }

    private func build(_ record: LedgerRecord, row: EntityRow) -> ItemBuild {
        let captured = Self.civilString(record.captured)
        switch record.kind {
        case .idea:
            // The scrap's full text is its content cell (display form —
            // the box is the truth, edits since capture included).
            let content = cellValue(row, "content")
            let text = (content?.isEmpty == false ? content : row.title) ?? ""
            return .ship(
                WireItem(uuid: record.uuid, kind: "idea", text: text, captured: captured),
                media: nil)
        case .task:
            var item = WireItem(
                uuid: record.uuid, kind: "task", name: row.title ?? "", captured: captured)
            if let due = row.due, due > 0 {
                item.dueCivil = due
                item.dateOnly = row.dueDateOnly ?? false
            }
            if let status = row.status, !status.isEmpty { item.status = status }
            return .ship(item, media: nil)
        case .event:
            var item = WireItem(
                uuid: record.uuid, kind: "event", name: row.title ?? "", captured: captured)
            if let due = row.due, due > 0 {
                item.dueCivil = due
                item.dateOnly = row.dueDateOnly ?? false
            }
            return .ship(item, media: nil)
        case .photo:
            guard let path = cellValue(row, "file"), !path.isEmpty else { return .drop }
            let url = URL(fileURLWithPath: path)
            guard let data = try? Data(contentsOf: url) else {
                Self.log.notice("photo bytes unreadable, dropping: \(path, privacy: .public)")
                return .drop
            }
            var ext = url.pathExtension.lowercased()
            if ext == "jpeg" { ext = "jpg" }
            guard ["heic", "jpg", "png", "webp"].contains(ext) else {
                Self.log.notice("unshippable media ext, dropping: \(ext, privacy: .public)")
                return .drop
            }
            let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            var item = WireItem(uuid: record.uuid, kind: "photo", captured: captured)
            item.mediaSha = sha
            item.mediaExt = ext
            if let title = row.title, !title.isEmpty, title != url.lastPathComponent {
                item.name = title  // a real caption, never the machine filename
            }
            return .ship(item, media: (from: url, sha: sha, ext: ext))
        case .link:
            guard let link = cellValue(row, "url"), !link.isEmpty else { return .drop }
            var item = WireItem(uuid: record.uuid, kind: "link", url: link, captured: captured)
            if let title = row.title, !title.isEmpty, title != link { item.name = title }
            return .ship(item, media: nil)
        }
    }

    private func cellValue(_ row: EntityRow, _ property: String) -> String? {
        (row.cells ?? []).first { $0.property == property }?.value
    }

    // MARK: publish

    private func publish() {
        pendingCount = ledger.values.filter { $0.state == .pending }.count
        entries =
            ledger
            .map { entityId, record in
                OutboxEntry(
                    id: entityId,
                    itemUuid: UUID(uuidString: record.uuid) ?? UUID(),
                    kind: record.kind, state: record.state,
                    title: titleResolver(entityId) ?? "#\(entityId)",
                    capturedCivil: record.captured)
            }
            .sorted { ($0.capturedCivil, $0.id) > ($1.capturedCivil, $1.id) }
    }

    // MARK: ledger persistence (tmp+rename, like everything else)

    private static var supportDir: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("liv", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static var ledgerURL: URL {
        supportDir.appendingPathComponent("outbox-ledger.json")
    }

    private static var stagingDir: URL {
        let dir = supportDir.appendingPathComponent("outbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func saveLedger() {
        var out: [String: LedgerRecord] = [:]
        for (entityId, record) in ledger { out[String(entityId)] = record }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(LedgerFile(v: 1, entries: out)) else { return }
        if !Self.writeAtomic(data, to: Self.ledgerURL) {
            Self.log.error("ledger save failed")
        }
    }

    private static func loadLedger() -> [UInt64: LedgerRecord] {
        guard let data = try? Data(contentsOf: ledgerURL),
            let file = try? JSONDecoder().decode(LedgerFile.self, from: data)
        else { return [:] }
        var out: [UInt64: LedgerRecord] = [:]
        for (key, record) in file.entries {
            if let entityId = UInt64(key) { out[entityId] = record }
        }
        return out
    }

    // MARK: file plumbing — deny-law checked, tmp+rename, write-once

    /// The deny-law: this code never writes OR deletes such a path.
    private static func denied(_ url: URL) -> Bool {
        url.path.contains(".liv") || url.path.contains(".trash")
    }

    private static func ensureDir(_ url: URL) -> Bool {
        guard !denied(url) else { return false }
        return (try? FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true)) != nil
    }

    /// Same-directory tmp then rename(2) — atomic on one volume, replaces.
    private static func writeAtomic(_ data: Data, to dest: URL) -> Bool {
        guard !denied(dest) else { return false }
        let tmp = dest.deletingLastPathComponent()
            .appendingPathComponent(".tmp-\(UUID().uuidString)")
        do {
            try data.write(to: tmp)
        } catch {
            return false
        }
        guard rename(tmp.path, dest.path) == 0 else {
            try? FileManager.default.removeItem(at: tmp)
            return false
        }
        return true
    }

    /// Write-once copy: an existing destination is the same content
    /// already there (content-addressed / ULID-unique) — success, skip.
    private static func copyAtomic(from source: URL, to dest: URL) -> Bool {
        guard !denied(dest) else { return false }
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) { return true }
        let tmp = dest.deletingLastPathComponent()
            .appendingPathComponent(".tmp-\(UUID().uuidString)")
        do {
            try fm.copyItem(at: source, to: tmp)
        } catch {
            return false
        }
        guard rename(tmp.path, dest.path) == 0 else {
            try? fm.removeItem(at: tmp)
            return false
        }
        return true
    }

    // MARK: civil helpers

    /// "YYYY-MM-DD HH:MM" from a packed civil stamp.
    private static func civilString(_ stamp: Int64) -> String {
        String(
            format: "%04d-%02d-%02d %02d:%02d",
            Int(stamp / 100_000_000), Int((stamp / 1_000_000) % 100),
            Int((stamp / 10_000) % 100), Int((stamp / 100) % 100), Int(stamp % 100))
    }

    /// Old enough that "absent from the snapshot" means undone, not merely
    /// newer than the last refresh (which follows every act within
    /// seconds). Ten minutes is comfortably past any refresh race.
    private static func stale(_ record: LedgerRecord) -> Bool {
        var parts = DateComponents()
        parts.year = Int(record.captured / 100_000_000)
        parts.month = Int((record.captured / 1_000_000) % 100)
        parts.day = Int((record.captured / 10_000) % 100)
        parts.hour = Int((record.captured / 100) % 100)
        parts.minute = Int(record.captured % 100)
        guard let then = Calendar(identifier: .gregorian).date(from: parts) else { return true }
        return Date().timeIntervalSince(then) > 600
    }
}

// MARK: - ULID (time-ordered, dependency-free)

/// 26 Crockford-base32 chars: 48-bit millisecond timestamp + 80 random
/// bits. Lexicographic order IS creation order — the drain order.
enum ULID {
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    static func make(now: Date = Date()) -> String {
        var out = [Character](repeating: "0", count: 26)
        var millis = UInt64(now.timeIntervalSince1970 * 1000) & 0xFFFF_FFFF_FFFF
        for i in stride(from: 9, through: 0, by: -1) {
            out[i] = alphabet[Int(millis & 0x1F)]
            millis >>= 5
        }
        for i in 10..<26 {
            out[i] = alphabet[Int.random(in: 0..<32)]
        }
        return String(out)
    }
}
