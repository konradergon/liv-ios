# P16 — AI (the assist socket): finish the socket, fence the brain

P16 builds lotus's AI as the **deterministic, offline, rules-based assist layer**
over the clerk that already exists (`services/src/clerk.rs`: the pure sweep,
dates+mentions proposers, the declined sidecar). It finishes the *socket* — the
proposer family, the group/severable substrate, the halo→diff-card→REVIEW-tier
presence grammar, single-key triage — and **FENCES the generative brain**
(Copilot, Jarvis, the answerer, any model-backed proposer) behind the exact same
`Proposal`/accept contract it will later plug into. When the model swaps in, no
new UI is required and the write path is already quarantined by construction.

The whole phase is **additive to `services/clerk.rs`, two additive FFI surfaces,
and the macOS shell — zero `core/` change.** AI keeps its two doors and no third
(reads via queries, writes via proposals); accept calls the exact seam a manual
edit calls; the vocabulary is closed (vault ∪ seed, validated); every accepted
transaction is stamped `Author::Proposer` with always-on ⌘Z.

> Provenance: synthesized from a P16 design workflow (four angles —
> reconciliation, proposers-services, surfaces-shell, scope-generative — + a
> synthesis pass). All four converged on the fence. Where angles disagreed, §8
> records who won and why. Grounded against the landed clerk / FFI / InboxView,
> not invented.

## 0 · Owner decisions (forks)

**D1 — THE FENCE (lead decision): deterministic assist to completion, generative
LLM fenced.** RECOMMEND: build P16 as the *deterministic, offline* assist layer
only — the full proposer family, the group/severable substrate, the
halo→diff-card→REVIEW grammar, single-key triage — and FENCE Copilot, Jarvis,
the answerer, and any model-backed proposer behind the same `Proposal`/accept
contract they will later plug into. **Reasoning:** the constitution allows "at
most ONE integration until the core is proven"; local files was that one
integration and only landed in P15. A generative model is a *second, heavier*
integration. `clerk.rs:9` already frames the model as "a brain swap behind this
socket", so P16's job is to finish the socket — when the brain swaps in later,
**zero new UI** is required and the write path is already quarantined. All four
angles converge here. **Recommend adopt.** (Override = build a generative slice,
a materially larger phase.)

**D2 — If the fence ever cracks, which door first?** RECOMMEND recording (not
building) the order: the **answerer** (read-only: question→query→cited entities,
degrades to silence offline) opens *before* Copilot. Copilot writes the note
*body* — the highest-risk surface ("body is 100% human") — so it is last. No
Copilot surface, inert or not, in P16.

**D3 — Group-accept-as-one-transaction needs a new FFI verb.** RECOMMEND yes: one
purely-additive `lotus_accept_group_at`. Without it, "Accept all" is an N-call
loop = N undo steps = a visible violation of constitution 1.3 ("commit as ONE
transaction"). Flagged to the owner per the boundary rule; ships failing-test-first.

**D4 — In-place halos: how far do they mount?** RECOMMEND the contained reading:
the **inspector ✦ pulse/wand** for the focused entity is the always-on in-place
pointer; **object-row halos are built as an optional param but mounted on Tasks
rows only** in P16, deferring Everything/Route row-halos. Keeps the mechanism
alive without marigold proliferation. Owner may widen later.

**D5 — interface.md §246 edit.** Retire the accent's "clerk's affordances" clause
to amber (Delta #1) — the accent then means only *selection + today*; all AI
presence is amber (`Theme.warning`). One-line spec edit.

**D6 — Metadata-rank proposer in P16 or not?** Decides whether the digit-pick
*alternatives* row ships populated (ranks in-pool values by frequency) or hidden.
RECOMMEND: stretch goal — build if P16a lands with room; else hide the row (the
deterministic proposers emit single-value proposals with no alternatives).

## 1 · Load-bearing decisions (recorded deltas)

1. **Amber is the one AI hue; the accent retires its "clerk's affordances" job.**
   `Theme.warning` (#e37400 / #fdd663) carries all AI presence so it never
   collides with lake-green selection. DELTA to interface.md §246 (amber is
   orange not red, so §248 "nothing else is ever red" holds).
2. **The halo-on-host layer collapses to the card + one pulse.** bp10's three
   halo hosts are inactive tabs (a6), workspace chips (a7), list rows (a8). lotus
   has no tabs and no workspaces by law, so two hosts don't exist; the third is
   contained per D4. Presence = card in the one queue + inspector pulse. DELTA.
3. **One appear-pulse is the single sanctioned animation exception.** A single
   system-eased one-shot fade, opt-in, never a loop (interface.md §264 bans
   beyond-system animation; bp10 a2 wants one pulse). DELTA.
4. **The 30s undo toast is a confirmation, not a deadline.** interface.md §205
   guarantees unbounded single-step ⌘Z; lotus's contract is stronger than Liv's
   timed toast. Undo never expires. DELTA.
5. **Tier ladder: REVIEW is the only inhabited rung in P16.** Every deterministic
   proposal is a reversible AddCell → REVIEW (diff + accept + undo). AUTO has
   nothing to audit (the clerk reads only the user's own box); BLOCK has no
   action (soft-trash, no send/external). Build the per-proposal tier field + a
   small REVIEW chip now; build **no** AUTO/BLOCK machinery. DELTA:
   documented-but-uninhabited.
6. **"Cannot accept twice" is structural, not a UI convention.** A proposal's
   seam identity is `(entity, ordinal, fingerprint)` verified on accept; the
   sweep is deterministic, re-derived every open. Row halo, inspector wand, and
   queue card all address the *same fingerprint* → a third accept is refused by
   the guard. Keep verbatim.
7. **The persisted dismiss contract already outlives value drift.** "Remembered
   forever, never re-asks" = the landed declined sidecar keyed by
   `decline_key = (proposer, entity, property)`. Extend the key (§3) for
   multi-command proposals; do not reinvent.
8. **Provenance is already satisfied — verify, don't build.** `store.accept()`
   commits under `proposal.author = Author::Proposer(name)`. ACTION: verify
   `lotus_accept_at` does not launder this to `User`; if confirmed, no work (only
   surface a `by:assist` reading in History later).

## 2 · Reconciliation table

| bp10 / catalog item | Verdict | Note |
|---|---|---|
| Card grammar: ✦ badge → −/+ diff → filled/dashed → ⏎/Esc → remembered id (a10-a14) | **KEEP** | The one card, four-mounts-collapsed-to-one. |
| Shared-id / cannot-accept-twice (a30) | **KEEP** | Already structural (fingerprint guard). |
| Persisted dismiss (a14) | **KEEP** | = declined sidecar + decline_key. |
| Closed vocabulary, vault ∪ seed (a1③) | **KEEP** | Coded via find_option / gazetteer. |
| Accept = the normal save seam (a1②, a13) | **KEEP** | Proposal's `Vec<Command>` through the manual-edit commit. |
| Empty-state = absence (a9) | **KEEP** | No proposal → zero AI chrome. |
| "AI never touches tier" (catalog a13) | **KEEP + make explicit** | Tested clerk exclusion: no AddCell where property ∈ {tier, private}. |
| Single-key triage a/r (Inbox) | **KEEP → build** | Declared in interface.md §221 but unwired; wire in Tidy only. |
| Halo on inactive tabs (a6) / workspace chips (a7) | **REFUSE** | No tabs, no workspaces. No host exists. |
| Halo on list rows (a8) | **RECONCILE (D4)** | Inspector pulse always; Tasks-row halo only; broad rows deferred. |
| −/+ diff before buttons (a11) | **RECONCILE** | Render AddCell as `− due: — / + due: 2026-07-15`; needs structured wire fields (§4). |
| Digit-pick *alternatives* (a12) | **RECONCILE** | Alternate **values** for one slot (metadata-rank), NOT group members. |
| Group + severable, commit-as-one (1.3, a4/a30) | **RECONCILE → build** | Build group_key(pure)/groups/accept_group. |
| 30s undo (a13/a17) | **RECONCILE** | → always-on ⌘Z. Delta #4. |
| One appear-pulse (a2) | **RECONCILE** | Single one-shot fade. Delta #3. |
| Amber hue (a2/a10) | **RECONCILE** | Retire accent's clerk job. Delta #1. |
| Tier ladder AUTO/REVIEW/BLOCK (§3) | **RECONCILE** | REVIEW inhabited; field built, AUTO/BLOCK stubbed. Delta #5. |
| Copilot pane (§4, a20-24) | **REFUSE / FENCE** | Second heavy integration; writes the body; "5th tab" has no host. |
| Jarvis vault chat (§5, a25-29) | **REFUSE / FENCE** | Second integration + chat-silo tension (T4). |
| Press-and-hold BLOCK gesture (a18) | **REFUSE** | No irreversible AI action exists (soft-trash only). |
| Suggestion toasts / 5-min poll (O6) | **REFUSE** | Violates "nothing on a timer." |
| Ghost-text autocomplete (W1) | **REFUSE** | LLM + typing-timer + body write. |
| AUTO tool-log chrome (a16) | **REFUSE (premature)** | Clerk reads only the user's own box; nothing to audit. |
| Metadata family (M1/M3/M4) | **KEEP (deterministic subset)** | metadata-rank feeds alternatives; missing-type is a read query, not a proposer. |
| Naming family (N1-N3) | **REFUSE (generative)** | No deterministic title/name guesser. |
| Organization/Tidy, Tasks, Import-folder families | **KEEP (deterministic)** | Priority-word, promotion, dedupe/merge, mentions-on-import. |
| Writing/Agents-generative, Tabs family | **REFUSE** | Fenced or no host. |

## 3 · Proposers (services/clerk.rs) — deterministic, offline, closed-vocabulary

All are `&Store` reads (so they **cannot** allocate ids — `allocate_id` is
`&mut Session`; this shapes promotion + merge). Each rides the existing `retain()`
dedupe (pending by exact commands; declined by decline_key OR exact commands).
Failing-test-first.

**Build:**
1. `propose_priority(store)` — candidates: not-trashed, not-WORKING, content
   exists, **no** priority cell. Scan a CLOSED trigger lexicon
   (`urgent`/`asap`/`!!!`→"high"; `low priority`/`whenever`→"low"), first trigger
   wins, resolve via `find_option(store, priority, name)` → propose only if it
   resolves to `Value::Select(option)`. Commands: `[AddCell{entity,
   priority→Select}]`. decline_key: existing `(name, entity, priority_prop)` arm.
2. `propose_promotion(store)` — candidates: content exists ∧ type missing ∧ the
   content's first `Break` is `Block::Task` (the capture literally is a checkbox).
   Commands: `[AddCell{scrap, type→Reference(task)}, AddCell{scrap,
   status→Select(todo)}]` (omit status if unresolvable; quiet if no task type).
   **Promotes the scrap in place** — line-item extraction from inside a note is
   the Agent's door (needs id allocation), deferred. decline_key: new
   multi-AddCell arm.
3. `propose_dedupe(store)` — bucket entities by an **EXACT identity key**:
   `(type, casefold(name))` OR `url` OR `external-id`; emit a merge for each
   bucket ≥2, survivor = older id (deterministic). Pre-compute the exact vector
   `store.merge` produces (AddCell each loser cell the survivor lacks; **skip**
   `tier`/`private` + single-valued conflicts, named in `reason`; Trash{loser};
   Redirect{loser→survivor}). **Vertex-disjoint pairs per sweep** (no chains).
   decline_key: new Redirect arm. **No fuzzy** ("Anna" ≠ "Annabel") — fuzzy is the
   LLM audit tier.
4. mentions-on-import — **no new proposer**; run the existing `propose_mentions`
   over freshly-imported entities so folder/source names matching the gazetteer
   yield severable related-references (feature-map #33/#37).

**Stretch (D6):** `propose_metadata_rank` (ranks in-pool values by frequency —
*this is what populates the digit-pick alternatives*); calendar-date match.

**Refused (record):** no type/title/name guesser (generative); no
missing-type-as-proposer (a read query + the union of concrete proposers); no
note-default guess on bare captures ("absence creates no debt"); no fuzzy
near-duplicate.

**`decline_key` extension** (signature stays `(&str, Id, Id)`): keep the
single-`[AddCell]` arm; ADD (a) multi-AddCell-on-one-entity → `(name, entity,
first_cell.property)` (promotion); (b) contains-Redirect → `(name,
redirect.survivor, redirect.loser)` (dedupe).

**Grouping / severability — PURE, in services, the group is DERIVABLE not stored:**
- `group_key(&Proposal) -> GroupKey{ author, Facet::{Property(Id) | Merge | Promote} }`
- `groups(&[Proposal]) -> Vec<Group{ key, members: Vec<usize> }>` — bucket in
  first-seen (entity-id) order.
- `accept_group(session, &[selected]) -> Result<u64>` — concatenate selected
  members' commands, `session.commit(all, label, members[0].author.clone())`
  **once** (one seq → one undo), **then** `session.retract()` each selected
  member (descending). Commit-first-then-retract is crash-safe *because clerk
  proposals are re-derivable*. **Composed 100% from existing public Session
  methods — zero core change.** (This ordering's safety does NOT transfer to a
  future Agent's non-re-derivable draft — flag at the seam.)

**"AI never touches tier" invariant:** a hard, tested exclusion — no proposer
emits an AddCell where property ∈ {tier, private}.

**Failing-test-first list:** priority (proposes_existing_option /
only_when_absent / quiet_when_no_such_option / decline_remembered); promotion
(checkbox_capture_promoted / only_when_untyped / quiet_without_task_type /
decline_binds_entity_type); dedupe (same_name_same_type_proposes_merge /
commands_equal_store_merge / exact_identity_only_no_fuzzy /
survivor_is_deterministic / skips_conflicting_single_valued /
never_copies_tier_or_private / decline_binds_pair / vertex_disjoint); grouping
(alike_share_group_key / unlike_dont_group / accept_group_is_one_transaction_one_undo
/ severing_leaves_member_pending / accept_group_verifies_fingerprints_no_partial);
ffi (lotus_accept_group_at_drains_only_accepted_members).

## 4 · Surfaces (macOS shell) — mockup-first

**Surface/tab budget: ZERO new tabs, ZERO new panes.** One net-new kit file, one
queue upgrade, wiring of existing inert frames.

**Net-new `Halo.swift`:**
- `extension View { func halo(_ active: Bool, pulse: Bool = false) -> some View }`
  — the extracted AssistCard overlay (1px `Theme.warning` border + 3px
  opacity-0.14 wash). `pulse` = a single one-shot fade, never a loop (Delta #3).
- `HaloHead` — hover peek: ✦ + one-line reason + dismiss ×.
- `SuggestionCard(proposal:, alternatives:, onAccept:, onReject:)` — the
  AssistCard upgraded: ✦-author chip → **DiffBlock** → **AlternativesRow** →
  small REVIEW tier chip → Accept ⏎ / Dismiss Esc. Anchored, never modal.
- `DiffBlock` — `− <old-or-empty> / + <new>` built from ValueChip + Hues, **one
  line per command** (promotion = 2 lines, merge = N lines; never collapse — the
  diff is the trust primitive).
- `AlternativesRow` — dashed chips = alternate **values** for one slot, card-local
  digits 1..n, live only while the card is focused; hidden when singular.

**`TidyQueueView` (upgrade the tidyLens):** group `proposals` by author into
`[ProposalGroup]`; render group header (✦ author · count · "Accept all A / Reject
all R") over member SuggestionCards. Cursor = `@State selectedFingerprint:
UInt64?` (identity survives requeue — **never index/ordinal**); j/k or ↑↓ move;
`a`/`r` accept/reject focused member then advance; `A`/`R` whole group (via
`lotus_accept_group_at`). Wire interface.md §221's a/r **here and only here**.

**In-place pointers (D4):**
- Inspector ✦ wand: in the inspector header, shown only when the selected entity
  has pending proposals; opens the same SuggestionCard as a popover.
- `ObjectRow`: add `var haloCount: Int = 0` (0 renders nothing). Marigold ✦ badge
  in the trailing slot opens a popover SuggestionCard for that entity's proposals
  (same fingerprint seam). **Mount on Tasks rows only in P16.**

**Wire the inert frames:**
- `agentsButton`: replace the beep with navigate to Inbox › Tidy. Keep the amber
  frame — it becomes the doorway, not a second queue.
- "Suggest for all" / "Suggest a merge": inert or a refresh-read only — **never a
  write on click** (no timer law). "Suggest a merge" surfaces the dedupe group.
- Import.swift reviewBody INHERITED block: a **read-only** ✦ preview chip ("will
  suggest: subjects · <folder>") announcing the post-import sweep. **No accept
  path in the funnel** — the real proposals ride the open-sweep into Tidy.

**Owner-gated FFI (additive; mirror with_box + Committed; ship tests; flag in PR):**
1. **LAND FIRST** — optional structured fields on `ProposalRow`: `property:
   Option<String>`, `value: Option<String>`, `value_kind: Option<String>`,
   `ref_target: Option<Id>`, `replaces: Option<String>`, `group: Option<String>`.
   All None-today = pure addition; each optional per the snapshot-decoder rule.
   The honest source for DiffBlock — **refuse string-parsing `reason`**.
2. **LAND SECOND** — `lotus_accept_group_at(path, entities[], ordinals[],
   fingerprints[], n)` — flat parallel arrays, all-or-nothing, fingerprint-verifies
   EACH (refuse wholesale on any mismatch, no partial commit), then `accept_group`.

## 5 · Slice plan (services before surfaces)

- **P16a — proposer family** (services, failing-test-first): priority-word,
  promotion, dedupe + the tier/private exclusion + decline_key extension. Gate:
  red tests first, all green; sweep determinism proven.
- **P16b — group/severable substrate** (services, failing-test-first):
  group_key/groups (pure) + accept_group (commit-then-retract). Gate:
  one-transaction-one-undo + severing-leaves-pending green.
- **P16c — FFI** (additive, failing-test-first, flag to owner): ProposalRow
  structured fields (first) + `lotus_accept_group_at` (second). Gate: atomic
  group commit + severed-member drop + decoder tolerates missing fields.
- **P16d — Halo.swift + SuggestionCard/DiffBlock** (shell, mockup-first): the
  card grammar with the real −/+ diff, REVIEW chip, one-shot pulse. Gate: mockup.
- **P16e — TidyQueueView + single-key triage** (shell, mockup-first): grouped
  queue, a/r/j/k, A/R group-accept. Gate: cursor re-anchors by fingerprint;
  "Accept all" is one undo.
- **P16f — wiring** (shell): Agents-button doorway, inspector wand, Tasks-row
  halo, import ✦ preview chip. Gate: no second queue; haloCount and queue count
  agree on fingerprints.

**Minimal-lovable milestone (end of P16b, proven in Tidy):** a note with
`!high call anna friday` produces a grouped, diff-previewed, single-transaction
proposal accepted with one keystroke — no model, fully offline.

## 6 · Deferred / FENCED (named)

- **Copilot** (bp10 §4) — second heavy integration; writes the note body; no host.
  No new surface, inert or not. FENCED.
- **Jarvis vault chat** (bp10 §5) — second integration + chat-silo tension (T4).
  FENCED.
- **The answerer** (T3 #1) — the *first* fence to open (read door, degrades to
  silence), but still the model integration. Deferred.
- **LLM brain-swap of the clerk** — the socket is built in P16; the brain is the
  second integration. Deferred.
- **Ghost-text autocomplete, suggestion toasts / 5-min poll, press-and-hold BLOCK,
  AUTO tool-log chrome** — refused outright (timer law, no irreversible action,
  nothing to audit).
- **Tabs / workspace-chip families** — no host by law.
- **Broad row-halos** (Everything/Route) — mechanism built, mounting deferred (D4).
- **Metadata-backfill over old thin objects** — owner-fenced in Liv; confirm first.

## 7 · Open owner calls recap

1. **D1** — ratify deterministic-only P16, generative fenced. (Recommend yes.)
2. **D3** — approve the additive `lotus_accept_group_at` verb + ProposalRow
   structured fields (boundary flag).
3. **D4** — how wide do row-halos mount? (Recommend Tasks-only in P16.)
4. **D5 / interface.md §246** — retire the accent's "clerk's affordances" clause
   to amber.
5. **Provenance verification** — confirm `lotus_accept_at` preserves
   `Author::Proposer` (expect satisfied; fix failing-test-first if not).
6. **D6 — metadata-rank in P16 or not** — decides whether the alternatives row
   ships populated or hidden.

## 8 · Where the angles disagreed (and who is right)

- **A. Inert Copilot frame** — surfaces wanted a static inline Copilot frame;
  fence wins (a new surface for a fenced feature is scope leak).
- **B. Deterministic name/title guesser** — proposers-services right: guessing a
  title from prose invents a value (violates closed vocabulary).
- **C. group_key stored on Proposal vs pure fn** — pure fn right (a stored group
  breaks "re-derived by every process" + forces a needless core change).
- **D. Row-halo breadth** — split (D4): inspector always, Tasks-only rows in P16.
- **E. missing-type as a proposer** — read-query wins (nothing deterministic can
  guess a type value).
- **F. Digit-pick alternatives = group members vs alternate values** —
  alternate-values wins (bp10's dashed chips are alternate values for one slot).
- **Provenance** — resolved as a verification step, expected green.

The angles otherwise agree on the spine: one queue by law, accept = the normal
seam (no AI-only write path), closed vocabulary, deterministic decline ids that
never re-ask, always-on undo, and the generative fence.
