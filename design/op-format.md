# The op format

> **Status:** draft, 2026-08-22. Phase 0 of `core-plan.md` says *"write down the
> op encoding and its version field before any op is written"*, because `core.md`
> promises a decoder forever and that is not promisable for a format nobody has
> specified.
>
> **Nothing here is decided.** Sizes marked *computed* come from the layout below,
> not from a running encoder. The block ops in §6 are provisional and wait on the
> blocks phase.

---

## 1. What it replaces, and the two lessons

The current log is JSON lines. Measured on a real box:

```
{"liv_log":1}
{"seq":16,"commands":[{"Create":{"entity":4155}},{"AddCell":{"entity":4155,
"cell":{"property":2,"value":{"Reference":4102}}}},...],"label":"new note",
"author":"User","time":1787391635,"reverses":null}
```

**318 bytes for a three-command transaction, of which 186 — 58% — is field names.**
`"reverses":null` costs 17 bytes on every line that does not use it, because no
field is ever skipped.

Those are the cheap lessons. The two expensive ones:

1. **The format is defined by a derive macro, not by a document.** `#[derive(Serialize)]`
   on `Transaction` means renaming a Rust field silently changes what is on disk
   forever. A macro's output cannot be a promise. **This document is the format.**
   Serde derive is banned on any type that reaches disk or the wire.
2. **The version fence has no test.** It is one `u32`, a `>` comparison, and a
   length-stable in-place rewrite — which caps the scheme at version 9 without
   changing byte length. A refusal path with no test is not a refusal path.

**What the current format got right and this keeps:** append-only with no rewrite;
a version fence that refuses the future outright; a box born at the lowest version
its content requires; a torn tail that drops rather than guesses; and — the
important one — **one line is one transaction, not one op.** That is already the
action-atomicity `core.md` §4 asks for.

---

## 2. Encoding

**A hand-specified binary record. Positional, no field names, no self-description.
The table in §4 is the schema.**

Why, in order:

- **The vocabulary is closed and tiny** — four op kinds and eight value kinds.
  Self-description buys nothing for twelve shapes with one writer.
- **The document has to exist anyway.** A self-describing format would be a second
  schema that can disagree with the first.
- **Determinism is required, not nice.** The replay gate is *byte-identical*, and
  drift detection is a digest exchange. Both need one logical op to have exactly one
  byte sequence. Positional layout gives that by construction; canonical CBOR gives
  it by rules you can get wrong.
- **No new dependency**, and **ops never cross the FFI** — the shell reads a
  snapshot, not ops — so no ecosystem argument applies.

**The honest alternative: canonical CBOR with integer keys.** One small dependency,
the same field table, an off-the-shelf decoder in any language, ~25–40% more bytes.
**Take it instead the day a non-Rust reader of the raw log is expected.** Nothing
needs one today.

Rejected: JSON (58% envelope, plus the derive-drift problem), `bincode`/`postcard`
(the format is "whatever the Rust type is" — the same defect one layer down),
protobuf (a schema compiler and a build step for twelve shapes).

**Rules the encoder obeys:**

- Integers are LEB128 varints unless a fixed width is stated. **Non-minimal varints
  are rejected on decode.**
- A record that decodes with bytes left over is an error.
- Strings are UTF-8, validated on decode.
- `NaN` and infinities are rejected on both sides.
- Reserved bits must be zero, and are checked.
- **The decoder never panics.** Hostile bytes produce a typed error.

---

## 3. Version — two levels

| Level | Where | Purpose |
|---|---|---|
| **Box format version** | one `meta` row; a stream header field on the wire | Refuse a whole box written by a newer build |
| **Record version** | byte 0 of every group header | Tell a new decoder which grammar this group uses |

**Refusal.** On open, `op_format > SUPPORTED` fails with a typed
`UnsupportedOpFormat { found, supported }`. The box is not partially read, not
repaired, not touched. This is `core.md` §13's *"refuse a newer box outright"* made
concrete, and it is the whole of forward compatibility.

**Born old, bumped late.** A box is created at the lowest version its content
requires, and bumped only when a record an older decoder would misread is first
written. The bump is a normal row update inside the same transaction as the record
that forced it — **so the length-stable rewrite constraint disappears, and with it
the version-9 ceiling.**

**Why a per-record byte as well.** A sync mesh upgrades one device at a time. Device
A writes v2 groups into a box that device B, still on v1, is also writing v1 groups
into. The box-level number can only say *refuse*; it cannot tell a v2 decoder which
grammar each group uses. One byte per group does. Today it earns nothing, and it is
one byte.

**Required by this spec:** a test that forges `op_format = SUPPORTED + 1` and asserts
the typed error and that nothing was written. That test does not exist today.

---

## 4. The record

`core.md` §2 names the op row as `(version, device, seq, hlc, author, entity, prop,
value, replaces)`. **Every op still has all nine.** Four are physically stored once
per *action* rather than once per op, because a group has exactly one device, one
instant and one author by construction, and its ops have consecutive seqs.

### Group header

| Size | Field | Notes |
|---|---|---|
| 1 | `version` | record grammar, currently `1` |
| 8 | `device` | 8 random bytes at install, never reused |
| varint | `first_seq` | the `seq` of this group's first op |
| varint | `op_count` | ≥ 1 |
| 6 | `hlc_wall` | u48 LE, ms since epoch — good to year 10889 |
| varint | `hlc_ctr` | the HLC counter |
| 1 | `author_tag` | `0` = user, `1` = proposer |
| varint + bytes | `proposer` | UTF-8 name, only when `author_tag = 1` |
| varint | `action` | code from the frozen action table |
| 1 | `reverses_tag` | `0` = none, `1` = a dot follows |
| 8 + varint | `reverses` | the `(device, seq)` this group undoes |

The HLC's third component is a device id and always equals the header's, so it is
not stored. `reverses` costs **1 byte when absent instead of 17**.

### Op record — repeated `op_count` times

Op *i* has `seq = first_seq + i`; its device, HLC and author are the header's.

| Size | Field |
|---|---|
| 1 | `kind` |
| 16 | `entity` |
| 16 | `prop` — kinds `0x02`–`0x04` only |
| var | `value` — kinds that carry one |
| var | `replaces` — kinds that carry one |

**`prop` is an entity id, 16 bytes, always.** The compiled-in properties get frozen
constant ids baked into the binary; a user-created field is an entity like any other.
There is no small-integer property space and no special case — which also removes the
`id < FIRST_USER_ID` trick that three sites use today to mean *is this plumbing*.

### Value kinds

| Tag | Kind | Payload |
|---|---|---|
| `0x01` | `Text` | varint length + UTF-8 bytes |
| `0x02` | `Number` | 8, f64 LE bits; NaN and infinities refused both ways |
| `0x03` | `Bool` | 1 |
| `0x04` | `Date::Day` | 4, i32 LE — days since the epoch, floating, no zone |
| `0x05` | `Date::Instant` | 8 i64 LE ms + 2 u16 LE zone |
| `0x06` | `Ref` | 16, an entity id |
| `0x07` | `Blob` | 32, a content hash — never a path |
| `0x08` | `Rich` | varint span count + that many spans |

**`Rich` is a value kind, not span JSON inside a `Text` cell.** A serde document
nested inside this format would be the derive-drift defect of §1 one layer down and
out of sight; and the fold could not see the references a body carries, so *what
links here* would be a scan of every note in the box rather than a seek.

#### Span — repeated `count` times

| Tag | Span | Payload |
|---|---|---|
| `0x01` | `Text` | 1 marks byte + varint length + UTF-8 bytes |
| `0x02` | `Break` | a block |
| `0x03` | `Ref` | 16, an entity id |

The marks byte is a bitflag set — bold, italic, code, strike in bits 0–3. **Bits 4–7
are reserved and must be zero.** Order is meaningless in a set and duplicates are
impossible, so one mark set has exactly one encoding, which is what the digest needs.

#### Block

| Tag | Block | Payload |
|---|---|---|
| `0x01` | `Body` | — |
| `0x02` | `Heading` | 1, **1–6; anything else is refused** |
| `0x03` | `Quote` | — |
| `0x04` | `Bullet` | 1 depth |
| `0x05` | `Ordered` | 1 depth |
| `0x06` | `Task` | 1 depth + 1 done, **0 or 1 only** |
| `0x07` | `Code` | 1 presence + (varint + UTF-8 when present) |
| `0x08` | `Callout` | varint + UTF-8 kind |
| `0x09` | `Rule` | — |

`Code`'s language uses a presence byte rather than an empty string, because `None`
and `Some("")` are different documents and each needs one encoding.

**The nested refusals above only ever fire on a FORGED group.** The frame's checksum
catches accidental corruption first, every time — which the tests for them found out
by passing while the checks were removed. They exist for a group that arrives from a
sync peer with a valid checksum over bad bytes, and a test that means to reach them
has to re-seal the frame the way a peer would.

### Op kinds

| Code | Kind | Carries |
|---|---|---|
| `0x01` | `CreateEntity` | entity |
| `0x02` | `SetCell` | entity, prop, value, replaces |
| `0x03` | `AddToSet` | entity, prop, value |
| `0x04` | `RemoveFromSet` | entity, prop, value, replaces |
| `0x10`–`0x13` | block ops | **provisional** — §6 |

**Trash, restore and redirect are `SetCell` on reserved properties**, not their own
kinds. That keeps the vocabulary at four and gives them merge rules for free, which
`core.md` §5 currently lists as having none.

**A refusal is one too** (added 2026-09-13, owner's ruling that declining on one
device must decline on all of them): `AddToSet` of the refused proposal's
fingerprint onto the thing it was about, on the reserved `declined` property. It
was a table beside the log before that, as it is in `core/`, and so it did not
travel.

The fingerprint is stored as its **16-character hex spelling, not a number**. A
`Number` value is an f64 and a fingerprint is 64 bits of identity: putting one in
the other rounds it, and two proposals differing only in the low bits would start
refusing each other. Nothing ever adds or orders these, so exactness is the only
thing the encoding owes them.

Being a set rather than a register is what gives concurrent refusals on two devices
the right answer for free — both are members, and the thing stays refused. It does
NOT make the verb idempotent: this is an observed-remove set, so every `AddToSet` is
its own element with its own dot (which is what lets a member added on one device
survive a removal on another). `decline` checks before writing, so a repeated tap
adds nothing and one undo is enough to take the refusal back.

---

## 5. Grouping, and the torn tail

**One user action is one group.** A group is length-prefixed, so a reader that runs
out of bytes mid-group drops the whole group — action atomicity by construction,
which is the property the current line-per-transaction format already has and the
first draft of `core.md` §4 lost by appending op lines separately.

Each group is followed by its own checksum over exactly the bytes written. A group
whose checksum fails is treated as a torn tail: everything before it stands,
everything from it is dropped. **Nothing is ever guessed at or repaired.**

---

## 6. Deliberately not in this format

- **Block ops are provisional.** `0x10`–`0x13` are reserved and unspecified until
  blocks exist. Writing them down before the model exists would freeze a guess.
- **No compression.** Tens of megabytes over five years.
- **No field names, ever.** That is the point.
- **No schema evolution beyond the version byte.** A new grammar is a new version, and
  old decoders refuse rather than degrade.
- **Photo and file bytes.** Content-addressed beside the log. Note that `FileRef`
  today carries a **device-local path**, which does not survive a device boundary —
  that is a model bug, recorded in `core.md` §14.

---

## 7. What this costs

*Computed from the layout, not measured.* The three-command transaction in §1 —
318 bytes as JSON — becomes roughly **120 bytes**: a 30-byte group header plus three
op records of 17, 35 and 38 bytes. Most of the saving is the envelope; the payload is
unchanged, and 16-byte ids make some records *larger* than their integer equivalents.

**The log shrinks by roughly 60%, and the 16-byte id switch adds back about half of
what JSON's envelope cost.** Neither number is worth optimising for on its own; both
are worth knowing before someone claims the format is about size. It is about a
decoder that can be promised forever.
