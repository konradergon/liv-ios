// liv iOS — THE ID, as sixteen bytes.
//
// The engine names a thing with a UUID. The shell has always named one
// with a `UInt64`, because that is what `core/`'s ids are, and it appears
// 236 times across 22 files — the navigation chain, the editor, the tab
// plane, the outbox. That type is the whole of what stands between the
// app and the engine (`design/rust-owns-the-mechanisms.md` §5, stage 4b).
//
// **This is slice one of three, and it touches nothing that draws.** Only
// the new seam's own rows use it, so the type's shape — its Codable form,
// its hashing, its ordering — gets a real build before 236 sites move to
// it. The other two slices:
//
//   2. `EntityRow.id` and the snapshot path become `LivID`. The
//      mechanical one; the compiler finds every site.
//   3. The data source swaps from the snapshot to the engine verbs.
//
// **Two words, not sixteen bytes in a tuple.** Swift has no fixed-size
// array, and a 16-tuple is neither `Hashable` nor pleasant. Two `UInt64`s
// hash and compare for free, and `hi` holds the FIRST eight bytes so that
// comparing `(hi, lo)` compares the bytes in their own order — which
// keeps id order meaning creation order, since a v7 id leads with its
// millisecond.

import Foundation

struct LivID: Hashable, Comparable, Codable, CustomStringConvertible {
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

    var description: String { hex }

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

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = LivID(hex: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "not a 32-character hex id: \(raw)")
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
