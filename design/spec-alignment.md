# Spec alignment — 2026-08-20

> **What this is.** The owner asked for a deliberate pass over the written
> record before more building: *"I think we should make sure the spec and
> constitution align with our current goals and situation."*
>
> Five auditors read 24,786 lines across 42 documents against the code and
> against each other. This file records what was corrected, what was
> deliberately NOT corrected, and the eleven questions only the owner can
> answer.

---

## The shape of the problem

The four documents that outrank everything — `productivity_app.md`,
`interface.md`, `liv-ui-map.md`, `feature-map.md`, 7,531 lines together —
are all dated **6–7 July**. Nothing has amended them in six weeks. In those
six weeks the Mac shell was deleted, capture was built and reverted, the
desktop pivoted onto a rival core, and the log's costs were measured for the
first time.

Three facts settled by this pass, because they were shaping decisions while
being wrong:

1. **There is one git repository, not two.** Both working copies are
   checkouts of `Dahlaren/lovable-notes-hub`. The phone is the branch
   `konrad/rewrite-mac`, which is on the remote and **93 commits behind
   local**. The desktop is `main` plus `viggo/*` and `viktor/*`. There is
   also `konrad/liv-core-pivot`, unpushed, holding the crate-merge attempt.
   CLAUDE.md called the desktop "the separate `lovable-notes-hub` repo".
2. **`~/src/friend-fixes` no longer exists.** `liv-ui-map.md` is a 4,578-line
   replication spec mined from a ~130k-line codebase that is gone from this
   machine. Its citations cannot be checked.
3. **The desktop is not the app the specs describe.** `lovable-notes-hub`
   begins 2026-04-30 from a TanStack template. The specs describe app A, the
   phone replicates app A, the team builds app B.

---

## Corrected (plain fact, no decision)

| File | Change |
|---|---|
| `CLAUDE.md` | `friend-fixes` named as gone, not as a live separate repo |
| `CLAUDE.md` | standing rule 1's count: **38 calls over 32 verbs**, measured — was "35" |
| `CLAUDE.md` | standing rule 2 widened to **the write path**, naming the new cost test |
| `CLAUDE.md` | the eight self-check launch flags documented under Build & test — `cargo test` does not run them |
| `design/ios.md` | status was "M1 in progress, accent lake green". Now ALPHA; the accent is the system tint and `2f7d6b` is nowhere in the shell |
| `design/ios.md` | the "capture satellite" framing marked as contradicted by two higher-ranked documents — **left in place**, not deleted |
| `design/next-batch.md` | `-tabs.selfcheck` → `-places.selfcheck` (renamed 2026-08-18); a documented command that silently ran seven of eight suites |
| `design/p11-spine-model.md` | dated 2027-01-01, a year in the future → 2026-07-09 |

## Refused (the plan proposed it; it was wrong)

**`productivity_app.md:1144` — "asynchronously, entity by entity".** The
alignment plan wanted to rewrite this to say the clerk sweep is *synchronous
and whole-box*, to match the code. **Refused.** The constitution is right and
the code is wrong: the shape it specifies is exactly the shape that would
have prevented the quadratic found on 2026-08-19, and the sweep is still
O(box) per write after the fix (`design/write-cost.md`). Rewriting it would
ratify unfinished work as spec and delete the only written statement of the
target. Recorded as a known gap instead.

Also refused, for the same class of reason: four edits to `interface.md` and
five to `productivity_app.md` that would have resolved open rulings by
editing the constitution to match the shipped app. A ruling cannot be listed
as open and applied as a correction in the same batch.

## Held (constitutional documents, pending the rulings below)

14 proposed corrections to `productivity_app.md`, `interface.md`,
`feature-map.md` and `liv-ui-map.md` are **not applied**. Every one of them
touches a statement that one of the eleven rulings decides. They are listed
in the workflow record and will land once the rulings do.

---

## The eleven rulings

Only the owner can answer these. Each is a place where two things the project
believes take opposite sides, and picking one changes what gets built.

> **Rulings 1 and 2 are DEFERRED (owner, 2026-08-20):** *"i don't even know
> what 'reversibility over friction' or 'capture over classification' mean to
> be honest, so we ignore those now."*
>
> That answer is itself the finding. Both are slogans from the constitution's
> five paired trade-offs, both were co-authored with an assistant in the first
> commit, and both have been used to justify architecture — while meaning
> nothing to the person they supposedly bind. In plain words: *reversibility
> over friction* means make everything undoable even where that costs speed or
> convenience (it is why the storage engine is an append-only log); *capture
> over classification* means let a thought in without saying what it is and
> sort it later (it is the rule the reverted capture sheet served).
>
> The pass therefore adds a twelfth item, and it outranks both: **the
> constitution needs translating into plain language before any of its
> principles can be ruled on.** A founding document its owner cannot read is
> not governing; it is a quarry for arguments. Rulings 7 and 10 below are
> written in the same register and have the same problem.

**1. Is "Reversibility over friction" still a founding value?** *(deferred)*
It arrived in the first commit (`dd57594`, 6 July 09:03), co-authored with an
assistant, before the product was named — and the whole core was built to
serve it. `design/what-liv-is-for.md`, which outranks the constitution on
product questions, never uses the word. Today reversibility wins absolutely in
the core and is almost absent from the product: `Store::redo` and
`Command::Restore` exist with no FFI verb, and the shell calls undo in two
places. *Recommendation: keep the log's shape, demote the line into the
architecture chapter where it is a true statement about the data model — but
note that the same shape is why permanent erasure is impossible today.*

**2. Does "capture over classification" still stand?** *(deferred)*
The constitution forbids asking "what type is this?" by name. After the Quick
Capture revert the `+` asks exactly that, five ways. *Recommendation: rule
that naming a kind at creation is allowed, but never a place, a name or a
form — and keep the speed test the original rule was protecting.*

**3. Is the box the truth and files a projection, or the reverse?**
This tree calls a second source of truth "Liv's disease". The desktop's D01
rules the opposite: files are the truth, the database is a rebuildable index.
*Recommendation: rule for the box, and permit a one-way projection out. A
folder written FROM the log is not a second truth; a folder written back INTO
it by a watcher is.*

**4. Which `liv-core` survives, and how do two checkouts of one remote become
one buildable thing?** Decided by 1 and 3. Needs a topology answer in the same
breath — publish the crates, vendor them, or merge the trees.

**5. Is the phone standalone or a capture satellite?**
Two higher-ranked documents say standalone. `Outbox.swift` still tracks every
creation for a desk that no longer exists. *Recommendation: rule standalone,
then decide Outbox's fate explicitly rather than leaving it running.*

**6. Where is the line between obligation the user set and obligation the
system invented?** "Absence creates no debt" currently forbids both, and
reminders ship. *Recommendation: an alarm for a moment the USER chose is not
the system generating obligation; a queue the system generates and counts at
you is. That makes Late and reminders legal in one sentence — and makes two
other things illegal.*

**7. Does the fence around external sources still hold?** The constitution
allows exactly one external source. `services/src/comms.rs` is a second, with
zero callers. *Recommendation: delete the verb, or move the fence
deliberately and rewrite the worked example in the same change.*

**8. What is the settings budget on a phone?** Two of the three budgeted
settings cannot exist on iOS, so the budget was never restated and was
quietly exceeded. Appearance and Fields are the questionable two.

**9. Are `interface.md` and `liv-ui-map.md` still ranked 1 and 3?**
One is a macOS window spec end to end; the other maps a codebase that is gone.
Neither is being followed, which is the real cost — a rank-1 spec that is
mostly inapplicable teaches people to skip it.

**10. "Renderers key on properties, never on types" — does it still stand?**
`views/` honours it exactly. The shell decides which surface an entity opens
in by its type. *Recommendation: move the test onto a cell — "is this entity
its own content?" is a property, not a type.*

**11. Does the editor-toolbar ban survive on a device with no modifier keys?**
"Keyboard formatting only" cannot be implemented on touch. *Recommendation:
amend with a platform clause, carrying the original scar forward.*

---

## Written nowhere (13 facts with no home)

The opposite failure: things now load-bearing that appear in no spec. Chief
among them — the log's measured costs (about 2× the note body per save, no
compaction, memory tracking history rather than live rows, an exclusive lock
refusing a second reader); that two crates are named `liv-core`; that the six
areas, the query lens parser and the stamping rule live only in Swift; that
the iOS editor knows 7 markdown block shapes against the core's 9, so code
fences are destroyed on edit; and that there is no restore verb, so trash is
one-way after the next write.

These want a home before the next person — or the next assistant — reads the
specs and believes them.
