// liv iOS — THE ID, as sixteen bytes.
//
// The engine names a thing with a UUID. The shell has always named one
// with a `UInt64`, because that is what `core/`'s ids are, and it appears
// 236 times across 22 files — the navigation chain, the editor, the tab
// plane, the outbox. That type is the whole of what stands between the
// app and the engine (`design/rust-owns-the-mechanisms.md` §5, stage 4b).
//
// **Slice 4 flipped it.** `LivEntityID` IS this type now, everywhere —
// the navigation chain, the editor, the plane, the outbox. The four
// slices behind that, and the one still ahead:
//
//   1. The type itself, used only by the new seam's own rows, so its
//      Codable form, hashing and ordering got a real build first.
//   2. Every `UInt64` that MEANT an id was renamed to `LivEntityID`.
//      224 sites said `UInt64` and about ten meant a fingerprint, a seq
//      or a stamp; nothing distinguished them. (One of those ten was
//      renamed wrongly — `setContent`'s `base` is a content fingerprint
//      — and slice 4 is where the compiler would have said so.)
//   3. The written forms, below: an id leaves memory in nine places a
//      compiler cannot see — five of them found here, four more by the
//      flip in slice 4.
//   4. The alias flips and `LivID` carries a `core` half so the old ABI
//      still takes it.
//   5. The data source swaps to the engine verbs, and the `core` half —
//      `init(core:)`, `.core`, `ExpressibleByIntegerLiteral`, the
//      number wire form — goes with it.
//
// **Two words, not sixteen bytes in a tuple.** Swift has no fixed-size
// array, and a 16-tuple is neither `Hashable` nor pleasant. Two `UInt64`s
// hash and compare for free, and `hi` holds the FIRST eight bytes so that
// comparing `(hi, lo)` compares the bytes in their own order — which
// keeps id order meaning creation order, since a v7 id leads with its
// millisecond.

import Foundation

/// **What the shell calls a thing.** Sixteen bytes, as of slice 4.
///
/// The alias stays rather than being spelled away, because it is the one
/// line that says what the shell's id IS — and because the rename it came
/// from was the point, not the indirection. 224 sites said `UInt64` and
/// about ten meant something else entirely: a content fingerprint, the
/// log's seq, a recency key, a wall-clock stamp. A fingerprint quietly
/// turned into an id is the kind of bug that shows up as the wrong note
/// opening a month later.
typealias LivEntityID = LivID

/// **An id written DOWN.**
///
/// The type is not internal. Slice 3 found five places an id leaves the
/// app's memory; slice 4's flip found four more, and the count is not the
/// lesson — the SHAPE is. Every one is a string interpolation or a plain
/// integer that stays valid whatever the format becomes, so a compiler
/// sees none of them:
///
/// * the editor's `[[123]]` token, **inside a note's own text**;
/// * a `related` cell's `#123`, **inside the box**;
/// * five `UserDefaults` keys (`desk.v3.123`), which hold every saved
///   plane and desk position;
/// * the outbox ledger's JSON dictionary keys;
/// * a shared note's filename;
/// * a saved plane's tab token, which is an id or an opaque position;
/// * a scheduled reminder's notification identifier AND its `userInfo`;
/// * and two `UserDefaults` integer VALUES rather than keys — the active
///   workspace and the desk's live document. Those two are the quietest
///   of the lot: `UserDefaults.integer(forKey:)` answers 0 for a missing
///   key, a key holding a string and a key holding an unreadable number
///   alike, so a format change there reads as "you are on All", not as a
///   fault.
///
/// A silent format change in any of them is not a bug that shows up in a
/// build. It is every `[[…]]` in every note ceasing to resolve, every
/// saved plane orphaned, and every reminder opening nothing — discovered
/// later.
///
/// **Four of these had a `LivIDText` read and a raw write**, because
/// slice 3 moved the halves it could see and the two halves live in
/// different functions. Nothing but the flip would have said so, and for
/// one of them — the reminder — not even that. So the format is one
/// function AND the type refuses to stringify itself (see `LivID`).
enum LivIDText {
    /// The written form. **HEX, all sixteen bytes** (slice 5b,
    /// 2026-09-19).
    ///
    /// It was `String(id.core)` — the low eight bytes, in decimal — and
    /// while the shell read a `core/` id that WAS the id. Since the
    /// engine swap it is half of one, and the half it keeps is the half
    /// that carries no timestamp. Everything written through here was
    /// being written down wrong:
    ///
    ///  - the desk's saved tabs and its open document (`Plane`), so a
    ///    relaunch restored ids pointing at nothing;
    ///  - a reminder's identifier and payload (`Notify`), so tapping one
    ///    opened nothing;
    ///  - the outbox ledger's keys (`Outbox`);
    ///  - the tasks view's filter id (`engineTasks`), which the ABI
    ///    parses with `parse_id` — 32 hex characters or nothing — so
    ///    filtering by status or project quietly did no filtering;
    ///  - a link added from the properties card (`Links`), which crosses
    ///    as `#<id>` and is read by the engine's `thing_named` with
    ///    `from_hex`, so the write was refused.
    ///
    /// A truncated id is not a wrong id you can spot. It is a plausible
    /// one for something that does not exist, which is why five separate
    /// surfaces failed silently and none of them looked related.
    static func written(_ id: LivEntityID) -> String {
        id.hex
    }

    // ---- the `[[id]]` token's id -----------------------------------
    //
    // **One grammar, three scanners** (standing rule 4, and it was
    // already three before the ids changed). They cannot share a loop —
    // one walks UTF-16 code units, one an NSString, one `[Character]` —
    // but they MUST agree on what an id looks like, and when that was
    // written out three times it drifted the moment ids did: the writer
    // emitted hex and all three readers still wanted decimal, so every
    // link in every note became literal text.
    //
    // So the rule itself lives here, once.

    /// How many characters an id is, written down.
    static let idLength = 32

    /// Is this one of the characters an id is made of? Lowercase hex.
    static func isIdChar(_ scalar: UInt16) -> Bool {
        (scalar >= 0x30 && scalar <= 0x39) || (scalar >= 0x61 && scalar <= 0x66)
    }

    static func isIdChar(_ c: Character) -> Bool {
        guard let a = c.asciiValue else { return false }
        return isIdChar(UInt16(a))
    }

    /// The id a token's characters spell, or nil.
    static func tokenId(_ text: String) -> LivEntityID? {
        guard text.count == idLength else { return nil }
        return LivEntityID(hex: text)
    }

    /// And read back. `nil` for anything that is not one — a token that
    /// does not parse is text, not a broken link.
    ///
    /// **A DECIMAL LEFT BY AN OLDER BUILD IS NOT AN ID, and reads as
    /// nil on purpose** (slice 5b). Those are `core/` ids, or engine ids
    /// with their top half thrown away; either way the box they name is
    /// not this box. Converting them would hand back a plausible id for
    /// something that does not exist, which is the failure this whole
    /// slice is about. Every caller already treats nil as "not one of
    /// ours" and drops it, so dead state clears itself on the way
    /// through: a stale reminder opens nothing instead of the wrong
    /// note, a stale ledger key is skipped, a stale tab is forgotten.
    static func read(_ text: some StringProtocol) -> LivEntityID? {
        LivEntityID(hex: String(text))
    }

    // ---- an id stored as a NUMBER ---------------------------------------
    //
    // Two of the places above are not keys but `UserDefaults` integer
    // VALUES: the active workspace, and the desk's live document. Same
    // format, named here so they are not three call sites either.

    /// The id under `key`, or `.absent` when there isn't one.
    ///
    /// **A STRING, and hex, because an engine id is sixteen bytes.** It
    /// was an integer, which held the low eight and silently dropped the
    /// rest — so the workspace you had open and the document the desk was
    /// showing came back as ids pointing at nothing. A truncated id is
    /// not a wrong id you can spot; it is a plausible one for something
    /// that does not exist.
    ///
    /// An integer left by an older build reads as `.absent` rather than
    /// being converted: those are `core/` ids, and the box they named is
    /// not the box any more.
    static func stored(
        forKey key: String, in defaults: UserDefaults = .standard
    ) -> LivEntityID {
        guard let text = defaults.string(forKey: key) else { return .absent }
        return LivEntityID(hex: text) ?? .absent
    }

    static func store(
        _ id: LivEntityID, forKey key: String, in defaults: UserDefaults = .standard
    ) {
        if id.isAbsent {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(id.hex, forKey: key)
        }
    }
}

// **NOT `CustomStringConvertible`, and that is the point of this file.**
//
// It was, until slice 4 found what the conformance costs. `Notify`
// scheduled every reminder under `identifier: "liv-\(slot.entity)"` and
// read the id back with `LivIDText.read`. With a `description` that
// conformance compiles — as HEX — and every tap then parses to nil. No
// error, no warning, no test: reminders simply stop opening anything.
//
// The only reason it was found is that the `userInfo` line two above it
// said `String(entity)`, which has no such overload and did not build.
// Luck, in a file whose whole subject is that luck is not a mechanism.
// Three more write halves had gone the same way — the plane's tab token,
// the outbox ledger's keys, and this — each one paired with a READ that
// slice 3 had correctly moved onto `LivIDText`.
//
// So the type refuses to stringify itself. `\(id)` is now a compile
// error everywhere, and the only ways to write an id down are
// `LivIDText.written` (the form on disk — hex since slice 5b) and `.hex`
// (the ABI's, which is now the same sixteen bytes; they stay two names
// because one is a format this app owns and the other is a contract).
// Standing rule 3: a rule that matters lives in a type, not in prose —
// and the prose above this line had been there since slice 3.
struct LivID: Hashable, Comparable, Codable, ExpressibleByIntegerLiteral {
    // **`ExpressibleByIntegerLiteral` IS TRANSITIONAL, and it has the same
    // deletion date as `core`.** It exists so that slice 4 — which cannot
    // compile in halves, since the fixes and the flip must land together —
    // does not also have to rewrite every `= 0`, `?? 0`, `!= 0` and
    // `== 4155` in twenty-two files on a machine with no compiler. While
    // the shell reads `core/` ids, an integer literal genuinely IS one.
    //
    // It is a footgun kept on purpose and briefly: it lets a number stand
    // where an id belongs, which is exactly what this whole refactor is
    // ending. Slice 5 removes it and the compiler then names the handful
    // of sites that were leaning on it.
    init(integerLiteral value: UInt64) {
        self.init(core: value)
    }
    /// Bytes 0–7, big-endian. The v7 timestamp lives in the top 48 bits,
    /// which is why this one leads.
    let hi: UInt64
    /// Bytes 8–15, big-endian.
    let lo: UInt64

    init(hi: UInt64, lo: UInt64) {
        self.hi = hi
        self.lo = lo
    }

    /// From the 32 lowercase hex characters the ABI sends. `nil` for
    /// anything else — a wrong-length or non-hex id is not an id, and
    /// guessing at one would put a row under the wrong thing.
    init?(hex: String) {
        guard hex.count == 32 else { return nil }
        let mid = hex.index(hex.startIndex, offsetBy: 16)
        guard let hi = UInt64(hex[hex.startIndex..<mid], radix: 16),
            let lo = UInt64(hex[mid...], radix: 16)
        else { return nil }
        self.hi = hi
        self.lo = lo
    }

    private static let digits = Array("0123456789abcdef")

    /// The 32 characters back again.
    ///
    /// Built byte by byte rather than with `String(format:)`: a format
    /// string is a runtime contract the compiler does not check, and
    /// `%lx` against a `UInt64` is exactly the kind of thing that is
    /// right on one platform and wrong on another.
    var hex: String {
        var out = ""
        out.reserveCapacity(32)
        for word in [hi, lo] {
            var shift = 56
            while shift >= 0 {
                let byte = UInt8((word >> UInt64(shift)) & 0xff)
                out.append(Self.digits[Int(byte >> 4)])
                out.append(Self.digits[Int(byte & 0x0f)])
                shift -= 8
            }
        }
        return out
    }

    // ---- the core box's ids, while the core box is the source ---------
    //
    // **A TRANSITIONAL HALF OF THIS TYPE, and it has a deletion date**
    // (standing rule 7): it goes when slice 5 swaps the data source to the
    // engine and the shell stops seeing a `core/` id at all.
    //
    // Until then the snapshot sends a `UInt64` and every `liv_*_at` verb
    // takes one, so a `LivID` has to be able to BE one. It holds it in
    // `lo` with `hi` zero — which cannot collide with an engine id, whose
    // `hi` carries a v7 millisecond and is never zero for anything minted
    // after 1970.

    /// A `core/` id, as an id.
    init(core: UInt64) {
        self.init(hi: 0, lo: core)
    }

    /// And back, for the ABI. Meaningless for an engine id, which is why
    /// slice 5 deletes it rather than leaving it to be misread.
    var core: UInt64 { lo }

    /// The absent id. `0` in the old ABI, where it means BOTH "no id" and
    /// "the verb failed" — a conflation the new seam's error channel
    /// exists to end.
    ///
    /// **Not called `none`**, though that is the word: `Optional` already
    /// has a `.none`, so `entity ?? .none` would resolve to the optional's
    /// and quietly hand back a `LivEntityID?`. A name that only one of the
    /// two types has can only mean that one.
    static let absent = LivID(hi: 0, lo: 0)

    var isAbsent: Bool { self == LivID.absent }

    /// The scratch workspace's sentinel, which was `UInt64.max`.
    ///
    /// **A `core` id, not sixteen ones**, and the self-check is what said
    /// so: the sentinel is interpolated into three `UserDefaults` keys
    /// (`DeskPlanes.forget`), so it has to survive `LivIDText` like any
    /// other id — and the written form can only carry the low word. `hi:
    /// 0` also keeps it out of the engine's range, where a v7 id's high
    /// word is a millisecond.
    static let max = LivID(core: .max)

    /// Byte order, which for a v7 id is creation order.
    static func < (a: LivID, b: LivID) -> Bool {
        a.hi == b.hi ? a.lo < b.lo : a.hi < b.hi
    }

    // ---- the wire form ------------------------------------------------
    //
    // ONE HEX STRING, not an object. A single-value container means the
    // JSON reads `"id":"0199…"` rather than `"id":{"hi":…,"lo":…}`, which
    // is what `ffi/src/surfaces.rs` sends and what a person reading a
    // payload would expect.

    /// **Two wire forms, for as long as there are two sources.** The new
    /// seam sends 32 hex characters; the snapshot sends a JSON number,
    /// because a `core/` id is a `UInt64`. Accepting both is what lets one
    /// type serve both paths through slices 4 and 5 — and the number half
    /// goes with `core`, when the snapshot does.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(UInt64.self) {
            self.init(core: number)
            return
        }
        let raw = try container.decode(String.self)
        guard let parsed = LivID(hex: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "neither a number nor a 32-character hex id: \(raw)")
        }
        self = parsed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}

/// `-livid.selfcheck 1`.
///
/// The round trip and the ordering, because both are claims this type
/// makes and neither is checked by anything else in the app. A hex form
/// that loses a byte would put a row under the wrong thing, silently.
func livIdSelfCheck() -> [String] {
    var fail: [String] = []

    // Round trip, including the edges: all zeroes, all ones, and a real
    // v7-shaped id with a leading zero nibble in both words.
    let cases = [
        "00000000000000000000000000000000",
        "ffffffffffffffffffffffffffffffff",
        "0199a1b2c3d47000800a0b0c0d0e0f10",
        "0f0e0d0c0b0a09080706050403020100",
    ]
    for hex in cases {
        guard let id = LivID(hex: hex) else {
            fail.append("would not parse: \(hex)")
            continue
        }
        if id.hex != hex {
            fail.append("round trip: \(hex) came back \(id.hex)")
        }
    }

    // Anything that is not 32 hex characters is not an id.
    for bad in ["", "abc", String(repeating: "z", count: 32), "0199a1b2c3d47000800a0b0c0d0e0f1"] {
        if LivID(hex: bad) != nil {
            fail.append("accepted a non-id: \(bad.isEmpty ? "(empty)" : bad)")
        }
    }

    // Ordering is BYTE ordering, which for a v7 id is creation order —
    // the property twenty-one sites in the tree lean on.
    let older = LivID(hex: "0199a1b2c3d47000800000000000000f")
    let newer = LivID(hex: "0199ffffffff7000800000000000000a")
    if let older, let newer {
        if !(older < newer) { fail.append("an earlier timestamp must sort first") }
        if older == newer { fail.append("two different ids compared equal") }
    } else {
        fail.append("the ordering cases would not parse")
    }
    // The low word breaks a tie, and is not compared before the high one.
    if let a = LivID(hex: String(repeating: "0", count: 31) + "1"),
        let b = LivID(hex: String(repeating: "0", count: 31) + "2")
    {
        if !(a < b) { fail.append("the low word must break a tie") }
    }

    // The WRITTEN form round-trips, which is the claim that matters most
    // in this file: it is the format inside a note's `[[…]]` token, inside
    // a `related` cell, and inside every saved plane's UserDefaults key.
    // A change to it that nobody noticed would unlink every note.
    for hex in cases {
        guard let n = LivID(hex: hex) else { continue }
        let text = LivIDText.written(n)
        if LivIDText.read(text) != n {
            fail.append(
                "written form: \(text) came back "
                    + (LivIDText.read(text).map(LivIDText.written) ?? "nothing"))
        }
    }
    for notAnId in ["", "abc", "12x", "-1", " 7"] {
        if LivIDText.read(notAnId) != nil {
            fail.append("read a non-id as one: \(notAnId.isEmpty ? "(empty)" : notAnId)")
        }
    }
    // THE WRITTEN FORM IS ALL SIXTEEN BYTES (slice 5b). It was the low
    // eight in decimal, which was the whole id while the shell read a
    // `core/` box and is half of one now — the half with no timestamp in
    // it. Five surfaces were writing ids down wrong and every one of
    // them failed silently; see `LivIDText.written`.
    if LivIDText.written(LivID(hex: "0199a1b2c3d47000800a0b0c0d0e0f10")!) != "0199a1b2c3d47000800a0b0c0d0e0f10" {
        fail.append("the written form is not the whole id — five surfaces just broke again")
    }
    // A DECIMAL LEFT BY AN OLDER BUILD IS NOT AN ID. It names something
    // in a box that is no longer this box, and reading it back as one
    // would hand every caller a plausible id for a thing that does not
    // exist. Callers drop a nil, which is how dead state clears itself.
    for legacy in ["4155", "0", "18446744073709551615"] {
        if LivIDText.read(legacy) != nil {
            fail.append("read a core-era decimal as an id: \(legacy)")
        }
    }

    // The stored form, in a scratch suite of its own so the real key is
    // never touched. `.absent` is the claim that matters here: it is
    // what "you are on All" means, and it must not come from a key that
    // holds something unreadable.
    let defaults = UserDefaults(suiteName: "liv.livid.selfcheck") ?? .standard
    defaults.removeObject(forKey: "k")
    if LivIDText.stored(forKey: "k", in: defaults) != .absent {
        fail.append("an absent key is not the absent id")
    }
    LivIDText.store(4155, forKey: "k", in: defaults)
    if LivIDText.stored(forKey: "k", in: defaults) != 4155 {
        fail.append("the stored form did not come back")
    }
    LivIDText.store(.absent, forKey: "k", in: defaults)
    if LivIDText.stored(forKey: "k", in: defaults) != .absent {
        fail.append("the absent id did not store as absent")
    }
    defaults.removeObject(forKey: "k")

    // The wire form is ONE STRING, not an object.
    if let id = LivID(hex: "0199a1b2c3d47000800a0b0c0d0e0f10") {
        if let data = try? JSONEncoder().encode(id),
            let text = String(data: data, encoding: .utf8)
        {
            if text != "\"0199a1b2c3d47000800a0b0c0d0e0f10\"" {
                fail.append("encoded as \(text), not a bare hex string")
            }
            if let back = try? JSONDecoder().decode(LivID.self, from: data), back != id {
                fail.append("did not survive its own JSON")
            }
        } else {
            fail.append("would not encode")
        }
    }

    return fail
}
