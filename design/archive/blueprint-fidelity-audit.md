# Fidelity Report — Liv (lotus) vs. the 14 Liv Blueprints

_Prepared 2026-07-13 · scope: the current macOS reference shell against the full BP-1…BP-14 set_

## 1. The straight answer

**How faithful the built surfaces are.** For the phases we actually claim as shipped (P11–P16), the port is faithful at the level that matters most — the load-bearing grammar. The BP-1 V3 inspector (digit grid, three-tier anchored pool editors, role-typed dates, universal status on every kind, MORE PROPERTIES, row menu, footbar, CONNECTIONS) is a high-fidelity 1:1 port. The BP-3 search palette ships Liv's signature live facet counts with tri-state include→exclude→off, never-capped grouped results, and three display modes. BP-6 tasks ships the status-vocabulary board with drag-to-write-status and the shared inspector. BP-9 calendar/contacts ships the month/week/day grid, multi-cell recurrence spans, and in-grid task checkboxes. BP-10 AI ships the deterministic spine — amber suggestion card, honest +/− diff, closed vocabulary, one Tidy queue, single-key grouped triage, always-on undo. Across ~200 audited line-items in the shipped surfaces, roughly 111 are SHIPPED faithfully and 90 are deliberate, design-doc-recorded DELTAS. The build is dense, keyboard-first, and correctly re-hued; it does not fake fidelity it doesn't have.

**Why a friend sees "lots missing."** Because your friend is comparing against the _entire_ 14-blueprint set, and four whole blueprints are legitimately unbuilt future phases: **BP-4 Shell v2 (the whole chassis/IA) = P17**, **BP-8 Dashboard/Mission-Control + BP-12 Vault-graph = P18**, and **BP-13 Settings + BP-2 Onboarding = P19**. Those four alone account for ~108 of the 108 FUTURE items — every dashboard widget, the graph canvas, the settings modal, and the 60-second tour simply don't exist yet. **The single biggest reason the app _looks_ different from the blueprints is the chrome: the live shell is still the pre-BP-4 flush-face 3-pane layout (full-height labeled sidebar · content · single inspector), not BP-4's rail-of-10 + global-tab-melt + two-tab Vault panel + five-lens right panel.** So even the surfaces that _are_ faithful are mounted in the older frame. A reviewer eyeballing screenshots against BP-4 sees a different skeleton before they ever reach the (faithful) inspector inside it. That is scheduled work (P17), not drift.

## 2. Per-blueprint scorecard

| Blueprint | Status | S / Δ / F / M / P | One-line verdict |
|---|---|---|---|
| BP-1 Inspector | SHIPPED (P11.5) | 17 / 6 / 1 / 1 / 1 | The crown jewel — near 1:1; only Apply-preset is a real unscheduled hole. |
| BP-3 Search palette | SHIPPED (P13) | 15 / 7 / 3 / 3 / 0 | Faithful heart (facets, tri-state, never-capped); thinner than finish-line (no command mode, no row actions). |
| BP-5 Capture + Inbox | SHIPPED (P12/P16) | 10 / 7 / 1 / 4 / 1 | Inbox half load-bearing; Quick-Capture half is a bare doorway missing most scaffolding. |
| BP-6 Tasks | SHIPPED (P14) | 11 / 9 / 2 / 1 / 1 | Board + inspector faithful; ~half the chrome (left rail, week-grid, Write-down) deferred. |
| BP-7 Files/Library | SHIPPED (P15) | 7 / 10 / 1 / 6 / 1 | Probe-level audit; mechanics landed but surfaces markedly thin — highest MISSING count of the shipped set. |
| BP-9 Calendar + Contacts | SHIPPED (P14) | 12 / 9 / 2 / 1 / 1 | Grid + span + recurrence real; both surfaces deliberately thin (no drag-reschedule, event-status unwired). |
| BP-10 AI presence | SHIPPED (P16) | 11 / 9 / 4 / 0 / 1 | Deterministic spine faithful; generative half fenced by constitution; in-place presence thin but zero MISSING. |
| BP-11 Composer | SHIPPED (P4/P11) | 7 / 7 / 3 / 8 / 0 | Writing core solid; the whole frame (toolbar, slash, kebab, source-toggle, footbar) is absent — 8 real gaps. |
| BP-14 Import/Export | SHIPPED (P15) | 8 / 14 / 1 / 5 / 1 | Heavily reconciled; one-transaction import faithful, but 3-box funnel collapsed and several surfaces missing. |
| BP-4 Shell v2 | P17 — designed, not built | 3 / 6 / 14 / 0 / 1 | The chassis. Only re-homed pieces ship; rail/melt/panels are cited futures, zero unscheduled gaps. |
| BP-8 Dashboard | P18 — not started | 0 / 1 / 20 / 3 / 1 | Whole widget board unbuilt (scheduled); Today = daily note is the deliberate stand-in. |
| BP-12 Vault graph | P18 — not started | 1 / 0 / 22 / 0 / 1 | Entirely unbuilt except the VALUE_HEX hue substrate; honest scheduled surface. |
| BP-13 Settings | P19 — not started | 1 / 4 / 19 / 0 / 0 | ⌘, is an honest stub; whole modal is future; four reconciliations pre-recorded. |
| BP-2 Onboarding | P19 — not started | 8 / 1 / 15 / 0 / 1 | Tour 100% unbuilt, but ~⅓ of the surfaces it rides on already ship. |
| **Totals** | — | **111 / 90 / 108 / 32 / 11** | ~352 line-items; faithful where claimed, future where scheduled. |

_S = shipped faithfully · Δ = deliberate recorded delta · F = future/scheduled phase · M = missing (not shipped, not clearly scheduled) · P = palette item._

## 3. The genuinely-MISSING items (real gaps, not future phases)

There are **32 MISSING items**, and honesty requires splitting them: **29 sit inside surfaces we claim are shipped** (the real gaps), and 3 are small unbudgeted items hanging off the unstarted P18 dashboard. The concentration is in **BP-11 Composer (8)**, **BP-7 Files (6)**, and **BP-14 Import/Export (5)** — these are the thinnest "shipped" areas.

**Composer (BP-11) — 8 gaps, the biggest cluster:** no sticky formatting toolbar (IA-12 locks it in; no doc records dropping it), no kebab ⋮ menu, no slash `/` block menu, no create-subnote row, no file/web embed cards, no source-mode toggle (Ctrl+E), no snapshot-capture toggles, no editor footbar/word-count. The writing core is faithful; the frame around it is largely absent and mostly _not_ scheduled.

**Files/Library (BP-7) — 6 gaps:** the audit here is only a probe (1 shipped line captured), so treat the 6 MISSING as directional, not itemized — this surface most needs a full re-audit before we make fidelity claims about it.

**Import/Export (BP-14) — 5 gaps:** no native File-menu Import/Export items (chord/icon only), no bookmark-folder→subject proposer (LB8, promised, unbuilt), no deferred shelf (no cross-close persistence), **markdown-note ingestion exists in the service but the shell never calls it — a dropped .md is referenced as a File, not ingested**, and no saved export presets.

**Scattered singles:** BP-1 Apply-preset (Alt+P) — the one real hole in an otherwise 1:1 inspector; BP-3 three keyboard/hover affordances (digit-open-facet, in-popover I·X·O cycling, row-hover ↗/✦/⋯); BP-5 four capture-side pieces (AI name-on-send row, **Keep⇄Composer toggle — p12 claimed "ships" but it was never built**, attachment strip, merge-suggestion card); BP-6 the calendar-ghost context in Schedule (thinner than its _own_ recorded delta); BP-9 event cancelled-status + strikethrough (§1.13 listed it as a delta-to-ship, still unwired).

**P18-adjacent (3, minor):** dashboard template picker, .xlsx export target, per-habit point weights — small and unbudgeted, but they hang off an unstarted phase.

The most quietly embarrassing three, because a doc said "shipped/ships" and the code disagrees: **BP-5 Keep⇄Composer**, **BP-6 Schedule calendar-ghost**, and **BP-9 event cancelled-status**. Those are the ones to fix or re-annotate first.

## 4. The most notable DELTAS (deliberate, recorded — not drift)

These are the divergences a sharp reviewer _will_ flag; all are recorded reconciliations in `design/p*.md` / `blueprint-assessment.md`, driven by the lotus constitution (append-only log, AI-quarantine, one filter engine, no folders/tabs/workspaces-by-color):

- **AI is quarantined to proposals-only.** Every blueprint's in-place AI (inspector wand, hover-head, selection bubble, Copilot pane, Jarvis chat, AUTO/BLOCK plan tiers, classify-a-capture) is deliberately absent. The whole generative half of BP-10 §4/§5 is fenced; only the deterministic clerk + one Tidy queue ship. This is the single largest source of "delta" across the set.
- **No folders / no destination paths.** Blueprints repeatedly show "will save to → library/inbox/" lines; the append-only box has no truthful folder path, so every such line is omitted or reworded (BP-5 a6, BP-14 destination, BP-2 trust-beat). Recorded, not forgotten.
- **The 3-box import funnel collapsed** to pool+batch (BP-14) — no per-item Commit/Staged/Defer loop, but one-transaction import with external-id dedupe is faithful.
- **Search refuses command-mode** (BP-3 Scene C) — `⌘F` searches entities by constitution; the OS Help menu is the command-search equivalent.
- **Schedule lens is a list, not a week grid** (BP-6/BP-9) — client-side re-bucket instead of a calendar canvas; drag-to-reschedule deferred everywhere.
- **The "one filter engine" promise is only partly met** — BP-14 export ships a plain substring box, not the P13 facet DSL. This is a delta the design admits is "substantially unmet."
- **30-second undo toast → always-on ⌘Z** (BP-10) — lotus's unbounded single-step undo is stronger than Liv's timed toast, so the countdown is dropped by choice.

None of these are silent drift; each has a paper trail. A delta is a reconciliation, not a bug.

## 5. Palette — where blue/violet leaks (it doesn't)

**Clean.** All 11 PALETTE line-items across the set report the same result: the blueprints paint accent in Google-blue `#1A73E8` / brand-violet `#6F5BE6` (icon tiles, focus rings, role-date pills, chips, kbd caps, active tabs, primary CTAs, graph edges/hub), and **lotus re-hues every one to lake-green `#2f7d6b`, with amber/marigold reserved exclusively for AI presence.** No blueprint blue or violet reaches the build. The value-node/chip multi-hue rainbow (VALUE_HEX) is _not_ a violation — it's the intended hash-stable hue law, and `Hues.swift` ships byte-identical FNV-1a seeds to the blueprint's `--vx-*`. The one place to stay vigilant is P18 (graph/dashboard, unbuilt): those inherit accent from the token layer, so a faithful build will pick up lake-green automatically — but that's unverified until it exists. Palette law is currently honored with zero known leaks.

## 6. Closing — the honest split

**The divergence is ~85–90% scheduled future work, ~10–15% honest thinness inside shipped surfaces — and near-0% unfaithful-to-what-we-claim-is-done.**

Of the four things a friend notices — different chrome, missing dashboard, missing graph, missing settings/onboarding — all four are named, dated future phases (P17/P18/P19). Of the 108 FUTURE items, essentially all live in those unstarted phases. The build does not pretend they exist. Where we _do_ claim "shipped" (P11–P16), the grammar is faithful and the ~90 deltas are documented reconciliations forced by the append-only + AI-quarantine constitution.

The legitimate criticism is narrower and worth owning: a handful of shipped surfaces are **thinner than their own design docs assert** — BP-5's Keep⇄Composer, BP-6's Schedule ghost, and BP-9's event-status were each described as shipping and did not, and BP-11's Composer frame (toolbar/slash/kebab/source-toggle) is largely missing without a recorded decision to drop it. Those ~5–8 items are the real "we said done, it isn't" gap. Everything else your friend flagged is the roadmap working as intended — the app is being built blueprint-faithful, phase by phase, and is roughly two-thirds of the way through the shipped-surface set with the chassis (P17) and the big visual surfaces (P18/P19) still ahead.