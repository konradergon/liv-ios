# Next batch — context for the next session

## UI blueprints — owner feedback 2026-08-11

The five blueprint pages in design/mockups/blueprints/ are APPROVED,
with these rulings (none built yet — blueprints only):

- **The capture sheet is GONE (2026-08-12), all 1,129 lines.** Its verb
  menu was rejected, and "task and event don't belong in new tab" took
  away its only door. Recoverable from git if a capture redesign ever
  wants its parts (property offer chips, the workspace stamp chip, the
  undo toast). The create menu is note / file (templates left the app
  on 2026-08-15).
- **Raw query text must never show as a value.** A workspace row shows
  colored value chips (area in its hue, subject in its hue), never
  "area:Study subject:thesis" in mono. Mono query text lives only
  inside the folded Advanced field.
- **The icons themselves are BUILT (2026-08-13), in `Glyph.swift`.** The
  blueprints' own stroked drawings, not SF Symbols — that substitution
  was why the owner could not see his icon system in the app. `LivKind`
  is the one classifier and carries colour + glyph together; a second
  switch on kind strings anywhere is a defect. `-glyph.selfcheck 1`.
- **Icon style DECIDED (2026-08-12): solid color boxes with the glyph
  carved out** — the box is the kind color at full opacity, the icon is
  punched through in the dark surface color, like a stencil. Not tinted
  boxes, not bare glyphs (he liked bare second-best). Value chips/pills
  stay tinted; only icon boxes are solid.
- **Where carved chips DO NOT go** (both rejected on sight, 2026-08-12):
  the create menu's verbs ("color / boxed icons in new tab looks bad")
  and property field rows ("icons for properties are confusing, but
  color indication of some sort is ok" — they wear a color dot instead).
  The rule that survived: kind color marks what a THING is, in lists;
  never what a button would make, never a field's name.
- **Person icons DECIDED: silhouette, never an initial.** Same carved
  treatment in the person pink. icon-style.html is now the icon-system
  reference sheet.


## Inactive tabs SHIPPED 2026-08-10

Owner asked for it pointing at Chrome for iOS. Built shell-only; the
rule lives in `LivTabs` (Tabs.swift), the clock is `DeskTab.lastUsed`,
and inactive is a PREDICATE over the one `tabs` array — never a second
collection. See changelog. Two things to keep in mind if you touch it:

1. **Never filter `tabs` itself.** `persist()` writes `active` as an
   INDEX into the ids it emits, and `openDocument` de-duplicates by
   entity across the whole array. Filtering breaks both, silently.
2. **The two invariants are load-bearing**: the active tab is never
   inactive, so the live set is never empty while tabs is not. That is
   what keeps the empty desk meaning "no tabs at all". Both are asserted
   in `-tabs.selfcheck 1`.

Not built, deliberately, from the same Chrome screenshot: tab search,
tab groups, pinned tabs, incognito. The owner asked for one thing.

Worth raising with the owner some time: the ORIGINAL Liv had parked
tabs as a MANUAL verb ("Hide tab (parks it)", liv-ui-map.md:3984) and
its bulk close explicitly SPARED them ("Close others (keeps parked)").
Chrome's model and the blueprint's disagree — the owner picked Chrome's,
knowingly or not, and a manual "keep this one aside" verb is still
available as a future addition.

## Blueprint audit, 2026-08-10 — read this first

`design/blueprint-gap-2026-08-10.md` holds the full audit of the phone
against the blueprints (58 findings raised, 37 survived an adversarial
check) and the five-batch plan proposal. The one-line finding: **nothing
has drifted architecturally; eleven features are finished in the core
with no button in the app.** Awaiting the owner's word on the batches.

Note the governing rule the audit turned up: `interface.md`'s 2026-07-06
pivot makes `liv-ui-map.md` the interface spec of record and annuls
every refusal that was taste rather than architecture. Some items listed
as "explicitly refused" in `feature-map.md` (the favourites shelf, for
one) are therefore live again.

## Data model — re-evaluated 2026-08-09, KEEP with six trims

The owner asked whether the model should be simplified or replaced with
a Notion-like one. Three designs, three judges, all measured. Verdict:
KEEP. The Notion block tree fixes one recorded scar, costs ~3,000 lines
in the settled core and the editor, and forces a one-shot migration of
every box; user-designed schemas are the exact disease the product
exists to kill. The REAL criticism stands: schema-as-data plus
name-lookup-by-scan caused four of the eight recorded scars.

SHIPPED 2026-08-09: T1 (name index + shape test), T2 (three dead
bootstrap properties unseeded — QUERY was NOT dead, the review
over-claimed), T4 (user_entities helper; full 58-site audit still open),
T6 (ffi split into lib/snapshot/tests). NEXT: T3 with a pre-trim box
fixture, plus the T4 audit.

**Markdown-as-storage — RESOLVED 2026-08-11.** The deviation is
retired: the iOS codec now writes the core's real blocks and marks
(design/ios.md rev 16). The checkbox tick IS a structural edit on new
saves; the three protections the refusal existed for all hold. Legacy
notes (literal markers as Body text) convert wholesale on their first
edit; until then `services/src/tasks.rs`'s form-2 branch still reads
them — it is now a LEGACY path, deletable only when old boxes stop
mattering, which is not soon.

The six trims (T1-T6), sized, none breaking a box:
- T1 name→id INDEX in the store (small) — retires the quadratic-lookup
  bug class behind ~197 call sites; needs its own scale-shape test.
- T2 delete QUERY/RENDERER/CONFIG/DEFAULT_VIEW dead code (small).
- T3 table-drive the 18 seed functions, ~300 lines (medium).
- T4 one "user entities" iterator wrapping the WORKING filter — audit
  all 58 sites (small).
- T5 ID-only writes (owner-gated; the assist-toggle chip).
- T6 split ffi/src/lib.rs (5,785 lines) into verb families (medium).
REFUSED and recorded: hardcoded fixed-row struct, markdown-as-storage,
folding Select into Text, typed-row snapshot rewrite.
All of T1-T4/T6 are settled-zone work: owner's word, failing-test-first.

State as of 2026-08-09. Phases 1–7 closed. Option C SHIPPED (a tab is a
document; records open as a card, minimise to a pill). FILES slice 1
SHIPPED — see design/ios.md §14 and the changelog.

## Files: what shipped and what is left

DONE: the file view (preview, name, facts, Open in…, broken-reference
card); TabShape's file arm, checked first; the three unused core verbs
wired (add-by-reference, re-hash on open, extracted text); phone imports
copy into Liv's own store; one glyph table keyed off format; the file
door in the create menu; static file rows removed from the facts list.

LEFT, in order:
1. **Workspace stamping on import is IN, inbox filing chips are not.**
   The chips are the highest product value per unit of work left:
   an inbox file row offering project/area in one tap.
2. **Real text extractors.** .tex/.bib are trivial (plain text). docx
   and xlsx are zip+XML with pure-Rust crates. pdf last. SETTLED ZONE —
   failing test first, owner sign-off, new crate dependencies. Until
   this ships, "search your files by their words" is unearned: the
   extractor stub returns empty for pdf/docx/xlsx
   (services/src/files.rs).
3. **The share extension** should accept anything, not just text, and
   lower to the same import.
4. **The Library view** — saved views over file entities with format
   chips (designed in P7 §7.3, built only in the archived Mac shell).
5. **Minimal-create doors** ("New Word doc") — write template bytes
   once, open the external editor, never touch the bytes again.
6. **P20j slice 20j.8** — vault pools on desktop. Large, designed,
   owner-gated.
7. **The gathered section** on a project record (reverse references).
   Settled zone, one additive FFI verb; every new wire field must be
   optional or the whole snapshot drops.

Owner decisions still open on files:
- The split-import escape hatch: the satellite defers a whole batch if
  one file has not downloaded — fine for photos, batch-starving for an
  80 MB spreadsheet. Plus a phone-side size cap; is video out of scope?
- The media-home fork (`~/liv/attachments/` vs vault pools) on desktop.
- Sanction PDF markup via QuickLook (Apple writes the bytes, Liv
  resyncs) — or refuse it explicitly.

**Do NOT build:** in-app editing of foreign bytes. It breaks "we never
write your bytes" and "everything is kept" at once — Liv would keep
every version of a note and zero versions of a thesis.

## Then: AI titles (owner: cloud is fine)

Approved order: after files. The seam is decided —
`liv_propose_title_at(box, entity, fingerprint, suggested_title)`; the
model call is per-platform; the Rust proposal queue (THIS repo's) files
and gates it. The proposal-survives-typing defect is FIXED (2026-08-07,
`clerk::rederivable`). Cloud is sanctioned by the owner 2026-08-08.
design/p16-ai.md still says REFUSE on paper — amend it when this is
built.

## Cross-platform (owner raised it 2026-08-07; Android "probably")

**SwiftUI stays.** The two hardest screens do not use it: the editor is
Apple's low-level text engine with a custom layout class, and the
calendar drag needed a recogniser on the window because SwiftUI's scroll
view never offered the touch. Every cross-platform toolkit adds a layer
between you and those same pieces; none removes the work.

Do NOT pre-emptively move shell logic into Rust. The markdown scanner
works in UTF-16 positions — which is how both Swift and Kotlin count
text, and is not how Rust counts it. Porting it to Kotlin is nearly
mechanical; porting it to Rust means converting positions on the typing
path. Extract against real Kotlin that needs it, not an imagined caller.

Priced, unstarted, and easy to forget:

- **The C header is free on iOS and not on Android.** build.sh hands
  `ffi/liv.h` straight to the Swift compiler, so Swift and the 55 C
  functions cannot drift. Java has no equivalent — the bridge is
  hand-written, all 55, and is its own piece of work.
- **Sync rides iCloud Drive** (design/ios.md §2), which Android cannot
  join. A product hole, not a code hole. Either Android ships without
  sync or the transport changes. The owner's call.
- **Build the Android editor FIRST.** Everything else assumes Android's
  text system can paint a checkbox over blanked-out characters the way
  `LivLayoutManager` does. If it cannot, the SwiftUI decision reopens,
  and week one is when to find out.

## Style rules the owner has stated

- **No jargon in anything he reads.** "Wire", "blur", "commit", "CAS",
  "binding" — say what they mean. He asked for this explicitly.
- Plain English, short sentences, lead with the answer, bold facts not
  drama, few dashes.
- No unrequested features. Accessibility affordances beyond correct
  labels are a feature and are asked for, not assumed.

## Verification loop

Run `build.sh` from `shell/ios`, never from `Sources` (it fails with a
confusing lstat error). Simulator 8E699FF6 — NEVER the owner's 00E539E0.

    xcrun simctl launch --console-pty <udid> app.liv.ios \
      -spans.selfcheck 1 -workspace.selfcheck 1 -calendar.selfcheck 1 \
      -share.selfcheck 1 -tabs.selfcheck 1 -glyph.selfcheck 1 \
      -palette.selfcheck 1 -editor.selfcheck 1
    # EIGHT suites since templates left (2026-08-15); there is no
    # -template.selfcheck any more, and its silence is not a failure

`--console` hangs; use `--console-pty` under `timeout 15`.

**Verify pixels, not just the saved data.** The divider shipped once
with its text confirmed in the log and nothing drawn on screen. For
anything positional, take two screenshots and compare pixel rows.

## Device

The owner's iPhone has the phase-5 build. Neither of today's batches has
been pushed to it (`shell/ios/build.sh device run`).

## Uncommitted

Everything since "templates with nothing to set up (phase 4)". The
owner's throwaway Xcode signing project is staged in the index but
deleted on disk (`AD Liv/...`) — unstage before any commit. Commit only
when the owner asks.
