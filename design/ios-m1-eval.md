# Liv iOS M1 vs ClickUp mobile vs Obsidian mobile — workflow-efficiency synthesis

**What this is.** Three agent-driven live sessions against the real Liv iOS M1 build in the simulator (every write cross-checked against the box via the CLI: entity cells, transaction history, absence-of-writes for drafts), judged against benchmark analyses of ClickUp mobile and Obsidian mobile compiled from verified documentation and community research. Liv numbers are **measured (M)**; competitor numbers are **estimates (E)** from research, not live devices. Read §6 (methodology) before quoting any number externally.

---

## 1. Scorecard — gestures-to-goal

A "gesture" = one tap/swipe or one text-entry session. Liv counts are the fastest *working* path observed, which in three scenarios is worse than the designed path because the designed path is broken (see §5).

| Scenario | Liv M1 | ClickUp | Obsidian |
|---|---|---|---|
| **Cold idea capture** | **4 (M)** — field not auto-focused (+1 tap); but zero decisions: no type, no location, no title | **5 (E)** — type menu (Task/Note/Doc/…) before any text field; List location pre-filled but mandatory; cold start widely reviewed as sluggish | **4 (E)** in-app / **3 (E)** via Shortcuts widget — cold start 1–8s is the real cost; the widget path skips the app but dumps into the daily note, deferring triage |
| **Serial capture (each additional idea)** | **5 (M)** — designed ~3 via "Another", which dead-ends (bug §5.3); each capture also permanently consumes a Desk tab | **2 (E)** — "Create and start another" keeps the sheet open with a cleared field; one-time +2 to enable the mode; persistence across sessions undocumented | **3 (E)** — never gets cheaper; the 1-gesture alternative co-locates thoughts in one daily note (triage debt) |
| **Task with due tomorrow** | **8 (M)** — "New task" verb opens on *Idea* mode (+2, bug §5.5); no due at capture time; due only via a 26pt chevron → row → picker (+3) | **6 (E)** — due is an optional field inside the create sheet; ±1 for an undocumented picker confirm; NL date typing ("tomorrow at 2pm") documented | **2 (E)** — but dishonest as a comparison: the checkbox is hand-typed markdown and "tomorrow" is inert prose — nothing surfaces, sorts, or notifies |
| **Complete a task from the day view** | **4 (M)** — 3 nav (features ^ → Today → day cell) + 1 status-ring tap; flip is instant and box-verified to use the `completes` status correctly | **2 (E)** — swipe-left + status pick on the agenda row, assuming the agenda is already on screen (+1–2 nav); picker tap is the safe assumption since statuses are List-specific | **1 (E)** — only if the note is on screen; no global task view exists, so finding it first costs +2–3 |
| **Reschedule to tomorrow by swipe** | **2 (M)** — leading swipe → "Tomorrow" on the Tasks row, works and box-verified; verb set is reduced vs spec (no Tonight/Pick) | **2 (E)** — swipe-right = reschedule on Today/Upcoming rows | **n/a** — no task system to reschedule |
| **Find and reopen** | **3 (M)** — magnifier auto-focuses, results live per keystroke, and opening a result *reuses* the already-open tab (no duplication) | **3 (E)** — search on Home is fused with the AI Command Bar; Recents covers the last 5 items in 1–2 | **3 (E)** — quick switcher, doubles as find-or-create |
| **Add one metadata value post-hoc** | **3 (M)** — the due picker itself is good; the entry point is a 26×26pt chevron (sub-HIG), and the status control is stone dead for scraps (bug §5.4) | **3 (E)** from an open task — each Details section is a fullscreen editor; ~6 end-to-end with search; unpinned custom fields +1 | **5 (E)** — name, type, value all hand-typed; 4 if the note already has properties |

Two texture notes the table can't hold:
- **Draft survival**: Liv passed the background/foreground interruption test live (draft intact, nothing written to the log — box-verified). Kill-and-cold-relaunch was not tested. Obsidian saves continuously by design; ClickUp is undocumented here.
- **Liv "as designed" vs "as measured"**: with the four capture-path bugs fixed, cold capture is 3, serial is 3, and task-with-due is ~5–6 (verb pre-selects Task mode, +Due chip after save). The measured numbers are a bug report as much as a design verdict.

---

## 2. Where Liv wins today — structurally

1. **Capture asks nothing, and the box proves it.** No type menu (ClickUp charges 1 gesture + 1 decision per capture), no mandatory location (ClickUp's Space>Folder>List taxonomy leaks into capture; its fastest surfaces — widgets — don't even respect the default List, a standing complaint), no title/folder (Obsidian shares this win but pays 1–8s cold start). CLI ground truth showed every capture is exactly `content` + `created`, one transaction, `:` stored literally — the no-token-grammar law held under live fire.
2. **Classification is deferred to a purpose-built surface, not skipped.** The Inbox Route lens turns a scrap into a task in 3 gestures *at triage time*, and the row leaves the lens on the same render. This is the structural inversion of ClickUp's capture-time type tax — same total work, moved to when the user has context.
3. **Search and the Desk tab model are already competitive with the mature apps.** Auto-focused field, live results, kind-grouped rows, and — notably — opening a result switches to the existing tab instead of duplicating it. Tab switcher is 2 gestures; back/forward over activation history works in both directions with correct enabled states. This matches Obsidian's best-in-class navigation and beats ClickUp's nav bar, which *disappears* inside task views.
4. **Real semantics with honest data.** "Tomorrow" resolved to the correct civil date; the status ring used the `completes` option; the swipe-reschedule wrote exactly one `set due` transaction. Obsidian's 2-gesture "task" is inert text; ClickUp's semantics come bundled with org-hierarchy overhead. Liv is the only one of the three whose cheap capture and real semantics live in the same object.
5. **Interruption-proof drafts** (background/resume verified) with nothing written to the log until commit — the append-only contract held across all three sessions.

---

## 3. Where Liv loses today

### (a) M1 gaps the roadmap already covers (design/ios.md §9)

- **No OS-level capture surfaces** — share extension (M1 remaining, blocked on a real Xcode project with App Group entitlements), lock-screen/home widgets and App Intents (M3), quick actions via the existing `liv://capture` deep links. This is the single biggest scoreboard gap: both competitors' *best* capture numbers (Obsidian's 3-gesture no-launch widget, ClickUp's widget-to-sheet) route around app launch entirely, and Liv currently has no route around it.
- **No sync** — the capture funnel (outbox projector, shipper, desktop drainer) is M2. Until then phone captures don't reach the desk, which caps the whole exercise at "local scratchpad".
- **No notifications, no Calendar surface** — M3. A due date that never fires is only half a due date; Obsidian is rightly punished for this in §1 and Liv currently shares the deficiency.
- **Minimal entity Detail / no CAS editor** — the §6 Desk-tab body (spans, Ref navigation, editor) is designed but M1 ships a stub.
- **The gesture-wiring bugs themselves** — §9 explicitly lists "hands-on QA of the gesture wiring (swipes, chips, camera) which headless simctl can't drive" as remaining M1 work. This evaluation effectively *was* that QA pass: the Another dead-end, the vanishing confirmation stage, the verb→mode mismatch, and the dead status control (§5) are implementation defects against a spec that is already right, not design risks.

### (b) Genuine design risks the roadmap does NOT cover

1. **Tab accumulation from capture.** Every capture permanently consumes a persistent Desk tab (badge climbed 1→2→3 in one short session). The design says tabs persist per device and the capture door *is* a tab; a capture-heavy phone user accumulates dozens of stale scrap tabs with no observed bulk-close. Nothing in §6–§9 addresses tab hygiene. Fix candidates: serial captures reuse one tab; "Done" closes the capture tab; or a "close all scrap tabs" verb in the switcher.
2. **The post-save metadata path is architecturally fragile.** The chip row lives only on a *transient* confirmation stage; once the user leaves it, the sole path to due/status is a 26×26pt chevron — sub-HIG and the least discoverable control on the screen. Even fully debugged, the design hangs the most common task attribute (due) off the most missable affordance. Consider: chip row rendered persistently on the saved entity body (the spec's "the saved entity becomes this tab's content" arguably already implies this), and a ≥44pt metadata affordance.
3. **Due vocabulary gaps.** No plain "Today" option (reachable only because Pick-a-date defaults to today); "Tonight" hardcodes 20:00; on Fridays "Tomorrow" and "Weekend" are visually duplicate options in both the picker and the swipe verbs. Small, but this is the picker on the hot path.
4. **Empty-vocabulary scoping is undesigned.** The dead status control's likely root cause — status options scoped out for untyped scraps rendering as an enabled, silent no-op — is a design hole, not just a bug: §6 promises one-editor-everywhere but doesn't say what a property row does when its vocabulary is empty. Rule needed: hide, disable-with-explainer, or seed defaults — never render a live-looking dead control.
5. **Capture-verbatim vs iOS defaults.** Auto-capitalization mutated stored content ("probe two" → "Probe two"). For a product whose law is that typed text stays literal, this is a spec-adjacent default that should be decided (`autocapitalization(.never)`) or documented, and it's nowhere in §8.
6. **Stale drafts can be committed by accident.** The surviving draft silently reappears on the *next* capture open; one tap saves week-old text. "Draft survives every interruption" needs an aging/visibility rule ("draft restored" affordance or per-tab scoping).

---

## 4. Competitors' best ideas Liv has not yet absorbed, by gesture-economics payoff

1. **Context-inheriting inline creation (ClickUp).** ClickUp's agenda "New" row inherits that day's due date; board columns inherit column properties. Liv's Tasks spec already has inline quick-add into the active *status* group — extending the same idiom to the Today day strip (quick-add under a day = due inherited) collapses the worst measured number: task-with-due goes from 8 gestures to ~3, and removes the chevron→row→picker chain for the dominant case. Biggest single payoff available.
2. **Persistent serial-capture sheet (ClickUp's "Create and start another").** Save clears the field and keeps the sheet, with the confirmation collapsed to a tappable toast. Takes serial capture from 5 (measured) / 3 (designed) to a true 2 per idea, and — if serial captures share one tab — simultaneously solves the tab-accumulation risk in §3(b)1. This is a strictly stronger version of "Another" and could replace it rather than coexist.
3. **Find-or-create in the search overlay (Obsidian's quick switcher).** Typing a name with no match offers creation in place. Merges retrieval and capture into one 3-gesture surface reachable from anywhere via the always-present magnifier — a second capture door that costs zero new chrome. (Honorable mention, same family: a type-a-date field *inside* the due picker, ClickUp-style NL dates. The no-token-grammar law fences the capture field, not the picker; "next fri" typed into a dedicated date control is arguably compatible. Owner call.)

Not listed because already absorbed or roadmapped: swipe verbs without opening the item (shipped), tappable created-toast reopen (the entity *is* the tab), widgets/share-sheet/quick actions (§9 M1/M3), Recents (covered by the switcher + search).

---

## 5. Bugs and friction found live, ranked by severity

1. **Silent text loss in the capture sheet.** Field visibly focused, keyboard up; focus dropped spontaneously ~2–4s later; a full typed sentence produced zero characters and no feedback. Directly violates "draft survives every interruption" — the draft never existed. *Fix: make the field first-responder synchronously at presentation; remove the delayed detent-settle/auto-focus logic that steals and releases first responder.*
2. **Post-save confirmation stage appears only for the session's first capture** (reproduced; captures 2 and 3 jumped Save → bare entity tab). Kills both the chip row and "Another" from the second capture onward — the two designed affordances of the capture flow. *Fix: present the confirmation stage unconditionally after every capture commit, regardless of how the New tab was created.*
3. **"Another" dead-ends** — dismisses the whole flow to the entity tab, indistinguishable from "Done" (observed once; unretestable because of bug 2). *Fix: reset the sheet to an empty field in the same mode instead of dismissing; likely shares a root cause with bug 2.*
4. **Dead status control in the metadata editor for scraps.** Enabled-looking popup, six input methods, zero response, zero writes (box-verified); adjacent due row works instantly. Likely empty status vocabulary for untyped scraps → SwiftUI Menu with zero items = silent no-op. *Fix: hide or disable-with-explainer when the scoped vocabulary is empty; never render a live dead control.*
5. **Verb→mode mismatch: "New task" opens on Idea mode** (3/3), making the verb identical to "Capture an idea" and risking task names saved as idea scraps; the mode switch also dismisses the keyboard (+2 gestures per task). *Fix: pass the verb's mode into the sheet's initial selection and keep first responder across mode changes.*
6. **No after-save chip row on the saved entity body** — the spec's `+Tag +Project +Person +Due +Type` surface is absent from the tab body (verified by full accessibility dump); only the 26pt chevron remains. *Fix: render the DETAILS chip row persistently on the saved entity body, not only on the transient confirmation.*
7. **Capture field not auto-focused on open** — one wasted tap on every single capture, against the P1 goal. *Fix: focus on appear (same change as bug 1).*
8. **Capture sheet detent instability** — presents at medium, auto-expands on a delay (sometimes >2s, sometimes never), moving the mode tabs ~330pt mid-interaction; mistimed taps hit the dimmed background and dismiss the sheet. *Fix: present at the final detent with focus, no animated re-layout on the hot path.*
9. **Metadata chevron is 26×26pt** — sole gateway to due/status, under the 44pt HIG minimum; the status value's own hit target measured ~11×13pt. *Fix: full-width row buttons (the due row already is one) and a ≥44pt chevron.*
10. **Stale draft silently restored on next capture open** — one tap can commit abandoned text. *Fix: visible "draft restored" chip with a clear affordance, or scope drafts to the tab.*
11. **Minor, batched:** auto-capitalization mutates content (*set `.never` or document*); "UPCOMING 7D" tile stale after in-window completion (*recompute on snapshot change*); Today tile 4 reads "CAPTURED" where spec says "Pinned" (*align or amend spec*); Tasks-row swipe carries only Tomorrow/Weekend vs the spec's Tonight/Tomorrow/Weekend/Pick (*complete the verb set*); Friday "Tomorrow"/"Weekend" duplication and no plain "Today" in the due picker (*vocabulary fix, §3(b)3*); Route-lens conversion skips the designed in-place chip phase and writes no default status (*spec question*); metadata-expand transition ghosting (*cosmetic*); one unconfirmed instance of feature-grid Capture creating a tab without presenting the sheet (*low confidence, check presentation timing*).

**Owner action item (environment, not the app):** the iOS-simulator MCP tool is unusable on this machine — it reports "Xcode is installed but not selected" despite a correct `xcode-select -p`. Run `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`. All three sessions fell back to axe HID / AppleScript-AX + `simctl` screenshots.

---

## 6. Methodology caveats — read before trusting any number

- **Simulator, not device.** Touch was injected HID/AX events on a Mac; real-thumb ergonomics (the 26pt chevron, detent timing, keyboard behavior) may differ in both directions. One session suffered macOS display sleep and key-focus races from three parallel agents sharing a desktop; affected events were documented and excluded from gesture counts, but the focus-loss bug (§5.1) carries a residual chance of environment contribution — it should be re-verified on device.
- **Agent-driven, not human.** Gesture counts are robust (each tap deliberate and logged with coordinates); wall-clock times are not — the input tooling stalled and replayed keystrokes at ~1 char/s and screenshots lagged the UI, so all `seconds_approx` figures are clean estimates, and measured wall clocks (up to ~8 min for a 15-second flow) measure the harness, not the app.
- **M1 skeleton vs mature apps.** Liv is a pre-QA milestone build explicitly missing its roadmapped capture surfaces (share extension, widgets, sync, notifications); ClickUp and Obsidian are years-polished products. The fair reading of §1 is "Liv's floor vs competitors' ceiling."
- **Competitor numbers are research estimates**, from official help docs, release notes, and community sources — not live-device measurements. Documented uncertainties are carried in the cells (ClickUp's undocumented picker confirm and mode persistence; Obsidian's configurable toolbar and first-use share-sheet placement). Treat cross-app deltas under ±1 gesture as noise.
- **Small N, some one-shot observations.** The "Another" dead-end was seen once and could not be retested because the confirmation stage never reappeared; draft survival was validated for background/resume only, not process kill; a sub-second confirmation flash in one run cannot be fully excluded (a clean-input run behaved identically).
- **What is solid:** every Liv write and non-write was verified against the box via the CLI — cell values, civil-date resolution, one-transaction-per-verb, and the absence of writes from drafts and dead controls. The append-only contract held throughout all three sessions.

Screenshot evidence: `/private/tmp/claude-501/-Users-k-src-liv/f40c56c4-dde2-4118-b7c7-19bc68ef9f75/scratchpad/eval/{capture,tasks,find}`. Design references: `/Users/k/src/liv/design/ios.md` §6 (IA and capture spec), §9 (build order used for the §3 roadmap classification).
