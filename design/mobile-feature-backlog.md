# Mobile feature backlog — from Viktor's blueprint corpus

> 2026-07-26. Source: `origin/viktor/wp1-property-types` docs on the
> lovable-notes-hub remote (DECISIONS D01–D31, IA-1–12, BP-1–14, WP1–10)
> + `viktor/fixes` CONTINUE-HERE. The owner's ruling: these desktop
> concepts eventually land in the phone app. Desktop UI itself is
> Viktor/Viggo territory — this file only maps their concepts to
> `shell/ios`. Notable: the corpus contains almost no explicit mobile
> thinking (one unanswered owner question, "What if its on my phone?",
> 2026-06-09) — this backlog is that answer.

Ranked by how directly the corpus's own logic lands on a phone:

1. **Capture contract (D07/D08, BP-5)** — capture never blocks, never asks
   a name; AI may suggest ONLY the name, visibly and editably; metadata
   pre-filled as editable chips (workspace/area stamp). Mobile already
   implements the ask-nothing half; the visible AI-name row and the
   workspace stamp chip are additions (AI part waits for assist/M-later).
2. **Inbox = one cleanup home, Route | Tidy (IA-3)** — already the mobile
   design; the corpus adds the commit bar + guilt-free "Later" grammar.
3. **Three-layer pickers + seeded vocabulary (D17) and suggest-with-
   alternatives (D09)** — mobile's pickers already do used→create-new;
   add the curated seed layer when the core exposes it; alternatives-in-
   cards is the Tidy-lens accept UI.
4. **Universal `status` + role-typed dates (D31 spine)** — already in the
   core and mobile. Keep parity as the corpus's WP1 property types land.
5. **Chip budgets per density (D31/BP-7)** — the corpus defines exactly
   which chips survive at small sizes (list row = ONE anchor chip; tiles
   never show status). Adopt as the phone's density law — mobile currently
   improvises this.
6. **Tier-1 "keep in sight" + the daily note as Today's anchor** — the
   corpus's answer to a phone home surface; mobile's Today should grow a
   pinned/tier-1 strip and the daily-note door (M2+).
7. **Task quick-add lenses (BP-6, ClickUp logic)** — status columns from
   the user's own vocabulary; mobile's Tasks groups already match; the
   write-down batch mode is a good future phone surface.
8. **One filter grammar (D21/D22)** — phone search facets should mirror
   the desktop facet grammar (include→exclude→off cycling) rather than
   invent new filter UI.
9. **People-chips / peek cards (BP-9)** — contact-centric capture
   ("@Steven owes me 300 kr") is a canonical phone scenario in the corpus.
10. **AI suggester-never-editor (D08/D09)** — matches the liv constitution;
    any future mobile AI is visible-suggestion-only.

Explicitly NOT for the phone (desktop-only by the corpus's own logic):
tab-melt/canvas chrome, three-pane shell, vault graph overlay, Jarvis
agent write-loop, department scripts / .docx production.

Dependency note: items 1 (AI name), 3 (seed layer), and the Tidy lens all
gate on assist arriving in the mobile shell (M2+ per design/ios.md §9).
