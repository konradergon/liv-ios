/* The one C seam between a native shell and the core.
   The shell never sees an entity or a byte of the log — it captures,
   reads one JSON snapshot, and triages by (entity, ordinal, fingerprint).
   Every call opens the box and closes it; the shell never holds it. */

#ifndef LIV_H
#define LIV_H

#include <stdbool.h>
#include <stdint.h>

/* Capture one scrap into the box at path (created and seeded if fresh).
   Returns the new entity id, or 0 on failure. */
uint64_t liv_capture_at(const char *path, const char *text);

/* Everything the window renders, as one JSON document.
   NULL on failure (probe to learn why). Free with liv_string_free.

   Among its keys, `note_tasks` is a PROJECTION (phase 3): the OPEN
   checkbox lines inside live notes,
     [{"entity":7,"line":1,"text":"call the surveyor","indent":0}, …]
   derived on read and stored nowhere — no entity is created, no cell is
   written. `line` is the line index in the shell's own buffer numbering
   (a paragraph break is a newline; a leading break is not one), so a
   shell can toggle the line through liv_set_content_at without a second
   scan. Trashed, archived and TEMPLATE notes are excluded, as are
   task/event-typed entities (their own body lines would double-count in
   the view that already lists them). Both authored forms are seen: the
   core's structural Block::Task and a literal "- [ ] " prefix in a Body
   paragraph.

   Each entity row carries `recency`: the seq of the newest transaction
   that touched it — a MONOTONIC key, 0 if none. It is what "the thing I
   was working on earlier" means, and it is the same signal search
   tiebreaks with, so a recents list and a search agree. Wall-clock
   modification time ties across rapid edits and cannot order recents.
   (Additive, 2026-08-18.)

   Each entity row's `title` is its DISPLAY NAME: its name cell, else the
   first non-empty line of its content with the block marker taken off,
   else "#<id>". Changed 2026-08-07 (owner) — it used to be a whole-body
   summary, so a multi-paragraph note reached every list as one run-on
   string. Test: services/tests/tasks.rs
   display_name_is_the_first_line_not_the_whole_body. */
char *liv_snapshot(const char *path);

/* The same snapshot over a caller-chosen occurrence window: `dated` is
   unchanged (the full set; the shell buckets by day), but the recurrence
   `occurrences` are expanded over [from_civil, to_civil] (civil YYYYMMDDHHMM)
   instead of the current month. The engine caps the window at a year.
   NULL on failure. Free with liv_string_free. */
char *liv_snapshot_window_at(const char *path, int64_t from_civil, int64_t to_civil);
void liv_string_free(char *s);

/* Accept / decline a proposal. The fingerprint comes from the snapshot
   and must still match — a consent is to a proposal, never a position.
   Return 1 on success, 0 when busy or when the queue shifted. */
int liv_accept_at(const char *path, uint64_t entity, uint32_t ordinal,
                    uint64_t fingerprint);
int liv_reject_at(const char *path, uint64_t entity, uint32_t ordinal,
                    uint64_t fingerprint);

/* Accept a GROUP of pending proposals as ONE transaction, one undo (P16).
   fingerprints_json is [u64,...] — the group's members by their displayed
   fingerprints. All-or-nothing: any stale member refuses the whole group
   untouched. 1 on success, 0 on busy / a stale group / a bad payload. */
int liv_accept_group_at(const char *path, const char *fingerprints_json);

/* Undo the last committed transaction. 1 on success. */
int liv_undo_at(const char *path);

/* Why the box would not open: {"code","message"} JSON, or NULL when it
   opens fine. Codes: locked | corrupt | version | io. */
char *liv_probe(const char *path);

/* One entity's content, fresh from the box:
   {"id":7,"name":"…"|null,"trashed":false,"missing":false,
    "fingerprint":1234,"spans":[{"Text":"…"},{"Ref":9},…]}
   Spans are the log's own serde encoding of Span, verbatim. Legacy
   plain-text content reads as one Text span (fingerprint still over the
   stored value); fingerprint is 0 when no content cell exists. Redirects
   resolve before reading. A box that opened fine but holds no such
   entity answers missing:true; NULL means only that the box itself is
   unavailable (probe to learn why). Free with liv_string_free. */
char *liv_content_at(const char *path, uint64_t id);

/* Replace the entity's whole content in one transaction (the editor's
   save). Empty spans remove content. base_fingerprint must still match
   the stored content — a save is to a value, never a moment. There is no
   force flag: overwrite is re-read then save. On success
   *fresh_fingerprint receives the new content's fingerprint.
   Returns 1 saved, -1 stale, 0 busy or invalid. */
int32_t liv_set_content_at(const char *path, uint64_t id,
                             const char *spans_json,
                             uint64_t base_fingerprint,
                             uint64_t *fresh_fingerprint);

/* Set one property by name: the CLI's `set` through the seam — value
   parsed by the property's declared kind, replace-the-cell, one
   transaction. Serves the checkbox ("status","done"), rename ("name",…)
   and the inspector to come. 1 ok, 0 busy/parse failure/no entity. */
int32_t liv_set_at(const char *path, uint64_t id,
                     const char *property, const char *value);

/* Ranked hits + facet counts for one raw DSL query, as JSON:
   {"hits":[{"id":7,"score":100.0,"field":"name"},…],
    "facets":[{"property":2,"label":"Type","values":[
       {"value":{"Reference":41},"label":"Task","count":12,"active":false},…]}]}
   Search is navigation: its own seam, not the cached snapshot. hits are
   bare ids (the shell already holds each title/cells) in rank order.
   Free with liv_string_free. NULL when the box is unavailable. */
char *liv_search_at(const char *path, const char *raw_query);

/* Lex a query into terms — no box, no lock. Free with liv_string_free. */
char *liv_lex(const char *raw_query);

/* The ids a LENS admits, plus the query's lexed terms:
   {"ids":[…],"terms":[{"op","key","value","raw"},…]}.
   `is:archived` RESTRICTS here where it WIDENS in search. Free with
   liv_string_free; NULL on a busy box. */
char *liv_query_ids_at(const char *path, const char *raw_query);

/* Every past version of an entity's content, NEWEST first:
   [{"seq":N,"time":..,"author":"..","label":"..","spans":[..]}]
   The log is the history — each entry is a whole content value.
   Restore one with liv_set_content_at of its spans. NULL when the box
   is unavailable. Free with liv_string_free. */
char *liv_content_history_at(const char *path, uint64_t id);

/* Both directions of an entity's links, as one JSON object:
   {"out":[{"id":N,"name":"..","kinds":["note"],"property":"related",
            "from_body":false}, ..],
    "in":[..]}
   One mechanism, two doors: a [[ ]] typed in a body (from_body true) and
   a link picked in properties (a `related` cell) are the same edge.
   Filing and backstage furniture are not links. An unknown id answers
   with two empty lists. NULL when the box is unavailable. Free with
   liv_string_free. */
char *liv_links_at(const char *path, uint64_t id);

/* Birth of a note: Create + type:note + created, one transaction.
   Returns the id, 0 on failure. Caller drops straight into renaming. */
uint64_t liv_create_note_at(const char *path);

/* Get-or-create the daily note for a day (any packed civil in it) and
   workspace (0 = none). Returns the note id, 0 on failure. Idempotent per
   (date, workspace) — the one place find-then-create is atomic. */
uint64_t liv_open_daily_note_at(const char *path, int64_t date_civil,
                                  uint64_t workspace);

/* Stamp an entity's TYPE by name (P12 12d Inbox Route commit). 1 ok, 0 on
   refusal (unknown type name / no entity). */
int32_t liv_set_type_at(const char *path, uint64_t id, const char *type_name);

/* Create a task by hand (Tasks quick-add): Create + type:task +
   status:todo + created, one transaction. Returns the id, 0 on failure.
   Distinct from capture, which quarantines an untyped scrap. */
uint64_t liv_create_task_at(const char *path);

/* Create an event by hand (the "+ Event" button, or double-click a day/hour).
   One transaction: type:event + due (from due_civil, all-day when date_only)
   + created. Returns the id, 0 on failure. Distinct from capture. */
uint64_t liv_create_event_at(const char *path, int64_t due_civil, int32_t date_only);

/* Space-cycles a date row's role: one transaction moving the value (civil +
   date_only intact) from `property` to the next role in the ring
   due -> date -> valid-until -> occurred -> purchased-on -> due. Returns the
   NEW property name (free with liv_string_free), NULL on busy/refusal. */
char *liv_cycle_date_role_at(const char *path, uint64_t id, const char *property);

/* Writes a date/span cell as ONE command (the mirror contract: inspector
   row, calendar drag, and span-grip drag are all this write). end_civil = 0
   means no end (a plain date); an end not strictly after the start is
   refused. date_only applies to both ends. Returns 1, or 0 on busy/refusal. */
int32_t liv_set_span_at(const char *path, uint64_t id, const char *property,
                          int64_t start_civil, int64_t end_civil, int32_t date_only);

/* The status vocabulary OFFERED to a kind, sorted by board order: JSON
   [{id,name,order,hue,completes}]. Options with no carriers included (an
   empty column keeps its header). NULL on busy/unknown kind. Free with
   liv_string_free. */
char *liv_status_options_at(const char *path, const char *kind);

/* A new status option for a kind (column-add / "Edit vocabulary..."): one
   commit, ordered last. hue < 0 means none. Returns the option id, or 0. */
uint64_t liv_add_status_option_at(const char *path, const char *kind,
                                    const char *name, double hue);

/* Layer 1 of the value pool: a property's distinct live values with usage
   counts, JSON [{value, count}], deterministic order (count desc, then
   display). NULL on busy/unknown property. Free with liv_string_free. */
char *liv_distinct_values_at(const char *path, const char *property);

// Birth a property definition (P11.5g add-property create leg). Returns
// the new definition id, 0 on refusal (empty/duplicate name, unknown kind).
uint64_t liv_add_property_at(const char *path, const char *name,
                               const char *kind);

/* Birth of a list: Create + type:list + name + created, one transaction.
   Named at birth (unlike a note). Returns the id, 0 on failure. */
uint64_t liv_create_list_at(const char *path, const char *name);

/* Add / remove ONE cell of a multi-valued property — list membership
   (property "related", value "#<member-id>"). Unlike liv_set_at
   (replace-all) and liv_unset_at (remove-all), these touch exactly one
   cell, and never delete the referenced entity. A no-op (already/not a
   member) still returns 1. 1 ok, 0 on busy/parse/no-entity. */
int32_t liv_add_cell_at(const char *path, uint64_t id,
                          const char *property, const char *value);
int32_t liv_remove_cell_at(const char *path, uint64_t id,
                             const char *property, const char *value);

/* Add a file by reference — the librarian: hash the file's bytes, create
   an entity with a file cell (path + hash), format, and name, one
   transaction. NEVER moves, copies, or renames the file. Returns the new
   id, 0 on failure (unreadable path, busy box). */
uint64_t liv_add_file_at(const char *path, const char *file_path);

/* Import a batch (P15). items_json is a JSON array of tagged items
   ({"kind":"link","url":...,"title":...} / {"kind":"file","path":...} /
   {"kind":"note","frontmatter":[[k,v]...],"body":...,"source_id":...} /
   {"kind":"scrap","text":...}); stamps_json is [[property,target]...] reference
   cells stamped on every committed entity (the funnel's inherited project/area).
   ONE transaction, one undo; external-id / file-hash dedupe skips re-imports.
   Returns the count committed (deduped items skipped), -1 on a parse/box error. */
int64_t liv_import_batch_at(const char *path, const char *items_json,
                              const char *stamps_json);

/* Export (P15). ids_json is [id...] (the shell-resolved matched-minus-unchecked
   set); group_props_json is [property...] group-by properties (<=2 used); dest a
   folder OUTSIDE the box. Copy-only, a projection — the log is untouched.
   Returns the count written, -1 on a parse/IO error. */
int64_t liv_export_at(const char *path, const char *ids_json,
                        const char *group_props_json, const char *dest);

/* Re-hash a file entity's referenced path; if the bytes changed, replace
   the file cell (one transaction — a changed hash is the integration).
   1 changed & rewritten, 0 unchanged, -1 the path no longer resolves
   (broken reference). Called when a file is opened, never on a timer. */
int32_t liv_resync_file_at(const char *path, uint64_t id);

/* A file entity's extracted plain text (the read-only preview), from the
   hash-keyed cache (extracting on a miss; the cache is rebuildable, never
   part of the log). Empty when there's no extractable text or the file is
   broken. Free with liv_string_free; NULL only when the box is
   unavailable. */
char *liv_extracted_text_at(const char *path, uint64_t id);

/* Birth of a workspace: Create + type + name (+ parent reference and a
   trailing order), one transaction. parent 0 = top level. Returns the
   id, 0 on failure. */
uint64_t liv_create_workspace_at(const char *path, const char *name,
                                   uint64_t parent);

/* Trash one workspace — and only that one. Deletion never cascades:
   the children keep their dangling `parent` and the shell re-roots
   them. 1 on success, 0 on failure. */
int32_t liv_trash_workspace_at(const char *path, uint64_t id);

/* Pin an object to the Favourites shelf (P17g): one transaction, lands
   after the last pin, idempotent (re-pin returns the existing pin's id).
   Returns the pin id, 0 on failure. */
uint64_t liv_pin_at(const char *path, uint64_t target);

/* Unpin a target: trash its live pin (soft). 1 when a pin was removed,
   0 when the target had none. */
int32_t liv_unpin_at(const char *path, uint64_t target);

/* Rename one VALUE everywhere it is carried (P19b): one grouped
   transaction, one undo. Text cells rewrite; select/status renames the
   option or merges into an existing one. Returns the carrier count,
   -1 on refusal. */
int64_t liv_rename_value_at(const char *path, const char *property,
                              const char *old_value, const char *new_value);

/* Mint an option for a select/status property - idempotent. Returns the
   option id, 0 on failure. */
uint64_t liv_add_option_at(const char *path, uint64_t property, const char *name);

/* Toggle one kind's reference on a definition's display-attribute property
   ("hide-on-kind" / "core-on-kind") — additive per kind (P19 review).
   Returns 1 changed, 0 no-op, -1 refused. */
int32_t liv_kind_flag_at(const char *path, uint64_t def, const char *property,
                           uint64_t kind, int32_t on);

/* Import a batch of messages (P20g): JSON [{external_id, from, source,
   sent?, body}]. One transaction; external-id upserts feed-owned cells
   only. Returns created+updated, -1 on failure. */
int64_t liv_import_messages_at(const char *path, const char *json);

/* Drain the vault's self-defense notices (P20j.4): JSON array of strings
   (length regression / in-place replacement / conflicted-copy siblings).
   Read-and-clear. Free with liv_string_free. */
char *liv_vault_alerts_at(const char *path);

/* The vault verbs (P20j.5). status: {"mode","root","files"} — cheap, no
   scan. sync: one scan -> tier-A ingest (ONE undoable txn) -> re-project;
   {"edited","created","surfaced"}. rebuild: full re-materialize from an
   empty manifest; returns the file count. Free strings with
   liv_string_free. */
char *liv_vault_status_at(const char *path);
char *liv_vault_sync_at(const char *path);
int64_t liv_vault_rebuild_at(const char *path);

/* Divergence findings + resolution (P20j.7). findings: read-only scan,
   JSON [{kind,id?,path?,count?}]; all=1 expands a mass burst. resolve:
   verdict "take-disk"|"keep-app"|"trash"; returns 1/0. Free the findings
   string with liv_string_free. */
char *liv_vault_findings_at(const char *path, int32_t all);
int32_t liv_vault_resolve_at(const char *path, uint64_t id,
                               const char *rel_path, const char *verdict);

/* Log one closed time interval (P18d): full civil stamps YYYYMMDDHHMM.
   Start writes nothing anywhere - the running timer is shell state. */
uint64_t liv_log_time_at(const char *path, uint64_t target, int64_t start_civil,
                           int64_t end_civil);

/* Save a view (P18d): a named query - the filter engine's bookmark. */
uint64_t liv_create_view_at(const char *path, const char *name, const char *query);

/* Add a board widget (P18d): kind + workspace scope (0 = Home) + span
   (<= 0 default). Config edits ride liv_set_at; removal liv_trash_at. */
uint64_t liv_widget_add_at(const char *path, const char *kind, uint64_t workspace,
                             double span);

/* Create a habit (P18b): points <= 0 means none (reads as 1); cadence may
   be NULL. */
uint64_t liv_create_habit_at(const char *path, const char *name, double points,
                               const char *cadence);

/* Check a habit in on a civil day (YYYYMMDD; 0 = today). Idempotent per
   (habit, day); uncheck = liv_trash_at on the returned row. */
uint64_t liv_check_in_at(const char *path, uint64_t habit, int64_t day);

/* Save a layout layer (P17i): one transaction — name + workspace scope
   (0 = Home) + ordered member ids ("[u64,...]"). Returns the layer id,
   0 on failure. Restore is pure shell; rename/delete ride set/trash. */
uint64_t liv_layer_save_at(const char *path, const char *name, uint64_t workspace,
                             const char *members_json);

/* Trash one entity — the inspector's Trash action. Soft, reversible,
   never cascades. 1 on success, 0 on failure. */
int32_t liv_trash_at(const char *path, uint64_t id);

/* Put a trashed thing back — the inverse of liv_trash_at, and the verb
   that was missing until 2026-08-20. Without it, undo-right-after was the
   only recovery, and only while the trash was still the last transaction.
   1 restored, 0 busy / no such entity / not trashed. Never cascades. */
int32_t liv_restore_at(const char *path, uint64_t id);

/* Remove every cell of one property — the inverse of liv_set_at's
   replace. Missing property on the entity is success. 1 ok, 0 on
   busy/no entity/no property definition. */
int32_t liv_unset_at(const char *path, uint64_t id, const char *property);


/* ====================================================================
   THE NEW SEAM: one verb per screen, over the engine.

   Everything above this line reads `core/` and hands the shell the WHOLE
   BOX as one `liv_snapshot` document — 3.5 MB and 39 ms at 6,400 notes,
   rebuilt on every refresh, linear in the box and independent of what is
   on screen. The shell then searches it to work out what Today is.

   Below, a screen asks for itself and gets itself. Measured over the same
   2,000-task box: one day is 2,268 bytes against the box's 448,891 — a
   factor of 198, and the ratio grows with the box rather than the screen.
   The deciding happens in `liv-surface`, where `cargo test` reaches it.

   THE TWO SEAMS ARE INDEPENDENT AND BOTH WORK. Nothing above changes
   until the shell has moved off it, one surface at a time
   (design/rust-owns-the-mechanisms.md §5, stages 3 and 4).

   Three things are deliberately different from the ABI above:

   1. A REAL ERROR CHANNEL. Every verb returns LIV_OK or a negative code,
      and the answer comes back through an out-pointer. Above, `0` means
      both "no id" and "it broke", which is why a shell cannot tell an
      empty box from an unreadable one. Here an empty box is LIV_OK and an
      empty array.
   2. SIXTEEN-BYTE IDS, as 32 lowercase hex characters. An engine id is a
      UUID and a JSON number is not one.
   3. NO `with_box`. That pattern exists because opening a core box
      replays its whole log; the engine is a database, so opening is
      0.3 ms and flat, SQLite does its own locking in WAL mode, and the
      connection is simply held.

   Every out-string is freed with liv_string_free. A failing call writes
   nothing through `out`.
   ==================================================================== */

#define LIV_OK          0
#define LIV_ERR_PATH   -1   /* path was null or not UTF-8 */
#define LIV_ERR_OPEN   -2   /* no such box, no permission, or too new */
#define LIV_ERR_ARG    -3   /* a parameter did not parse */
#define LIV_ERR_READ   -4   /* the box opened and refused the read */
#define LIV_ERR_ENCODE -5   /* the answer would not encode (a bug here) */

/* The three below belong to the WRITE verbs, which can fail in ways a
   read cannot. They are codes and not LIV_ERR_READ because a shell has a
   different thing to do about each. */
#define LIV_ERR_STALE   -6  /* the stored body moved; re-read and decide */
#define LIV_ERR_REFUSED -7  /* the box will not take this write */
#define LIV_ERR_NOTHING -8  /* there was nothing there to do */

/* `lens` is a JSON array of hex ids the workspace admits, or NULL for no
   workspace. NULL IS NOT "[]": a workspace whose query matches nothing
   admits nothing, and that is a real state — passing NULL to mean it
   would turn a filtered-to-empty screen into an unfiltered one. */

/* Today, for the day `day` (days since the epoch), knowing the real
   `today` and the clock. They differ whenever the date strip has moved,
   and several rules turn on whether they are the same.

   {"late":[row…], "passed":[…], "ahead":[…], "all_day":[…], "done":[…],
    "next":"<hex id>"?, "captured":N}

   A row is
   {"id","title","untitled","kind"?,"due_ms"?,"all_day","status"?,"done",
    "area"?,"created_ms","touched_ms","has_file"} — already titled, already
   sorted, and `done` already resolved against which statuses complete. */
int32_t liv_view_today(const char *path, int32_t day, int32_t today,
                       int64_t now_ms, const char *lens, char **out);

/* Tasks, grouped by status. filter: 0 all, 1 status, 2 project;
   filter_id is the hex id it names and is ignored when filter is 0.

   [{"status":"<hex>"?, "name", "completes", "late":N, "rows":[row…]}…]

   `late` is the GROUP's count, not a flag per row: on a real box every
   task is overdue, and a colour on every row distinguishes nothing.
   An empty group is not returned. */
int32_t liv_view_tasks(const char *path, int32_t filter,
                       const char *filter_id, int32_t today,
                       const char *lens, char **out);

/* Everything, in one slice: 0 all, 1 notes, 2 upcoming, 3 unfiled.
   Returns [row…], already ordered — newest first, except notes, which is
   most-recently-touched first, and upcoming, which reads forward. */
int32_t liv_view_everything(const char *path, int32_t slice, int32_t today,
                            const char *lens, char **out);

/* The calendar's day: the all-day strip, and the timeline's blocks with
   their overlap already resolved.

   {"all_day":[row…],
    "blocks":[{"row":row,"start_min","minutes","column","columns"}…]}

   `start_min` is minutes from midnight — the shell multiplies by its own
   points-per-hour. `minutes` is never zero, so a thing with no duration
   stays tappable. `column`/`columns` are a CLUSTER's, not a pair's: two
   blocks that miss each other can both hit a third, and all three share
   the width. */
int32_t liv_view_day(const char *path, int32_t day, const char *lens,
                     char **out);

/* Drop every held connection. Call before moving or replacing a box file.
   Not thread-safe against a liv_view_* call in flight. */
void liv_view_close_all(void);

/* ====================================================================
   THE ENGINE'S WRITE VERBS

   Everything above this line reads. Until these existed the engine had
   set, add, remove, trash, restore, undo, set_content, rename_value,
   add_file and the clerk's queue, all tested, and no shell could reach
   any of them — so a shell on the engine could look and never touch.

   A BODY CROSSES IN THE SHELL'S OWN SPAN JSON, deliberately. It is what
   Editor.swift's SpanJSON already encodes and decodes — {"Text":"words"},
   {"Break":"Body"}, {"Break":{"Heading":3}} — because a second span
   encoding would be two grammars for one user-facing shape. The one
   difference is that a Ref is 32 hex characters rather than a JSON
   number, and the shell's id decoder was built to accept both.

   A span this build does not understand is REFUSED (LIV_ERR_ARG), never
   dropped: flattening a block a newer build wrote is a decision about
   someone's writing that a wire decoder should not be making. The save
   fails and the editor still holds the text.
   ==================================================================== */

/* One body and the fingerprint to save it against.
   {"spans":[…], "print":N}

   ZERO IS NEVER A REAL FINGERPRINT — it is what "no body yet" reads as,
   so a first save needs no special case. */
int32_t liv_read_body(const char *path, const char *id, char **out);

/* Replace a body, compare-and-swap on `base`. {"print":N}

   LIV_ERR_STALE means the stored body moved since `base` was read:
   RE-READ, NEVER OVERWRITE. There is no force flag, by design. Empty
   spans clear the body. LIV_ERR_REFUSED is the model saying no — a Ref
   to nothing, most often. */
int32_t liv_write_body(const char *path, const char *id, const char *spans,
                       uint64_t base, uint64_t now_ms, char **out);

/* Every past version of one body, NEWEST FIRST.
   [{"device","seq","at_ms","author","spans"}…]

   Restoring one is an ordinary liv_write_body of its spans over a freshly
   read base. The log is never rewritten, so a restore is itself a
   version. `author` is "user" or the proposer's name. */
int32_t liv_body_history(const char *path, const char *id, char **out);

/* Both directions of one thing's links: {"out":[hex…], "in":[hex…]}

   A [[ ]] typed in a body is the same edge as a link picked in
   properties — the fold indexes both — so this is the only reader either
   list needs. */
int32_t liv_links(const char *path, const char *id, char **out);

/* What undo and redo would take, without taking it:
   {"undo":bool, "redo":bool} — what a toolbar needs to know whether its
   buttons are live. */
int32_t liv_undo_state(const char *path, char **out);

/* Take back this device's last action, and put it back. LIV_ERR_NOTHING
   when there is none, which is an ANSWER and not a failure: a shell
   asking on a fresh box is not a shell doing anything wrong, and the ABI
   above this line has one zero for both. */
int32_t liv_undo(const char *path, uint64_t now_ms);
int32_t liv_redo(const char *path, uint64_t now_ms);

/* Rename one value of a property, everywhere it is carried.
   {"carriers":N}

   `carriers` is how many things change ON SCREEN, which for a select is
   not the number of writes: one write to the option's name re-renders
   every carrier. Zero is a success, not a refusal.

   LIV_ERR_REFUSED for an empty or unchanged name, a value nothing is
   called, a property that does not rename, or an AMBIGUOUS rename —
   which refuses rather than guessing, because two kinds sharing an
   option name is the designed state of `status`. */
int32_t liv_rename_value(const char *path, const char *property,
                         const char *old_name, const char *new_name,
                         uint64_t now_ms, char **out);

/* Take a file into the box BY REFERENCE. {"id":"<hex>"}

   Never copies or moves it — the file is read to hash it and left where
   the user put it. An unreadable path is LIV_ERR_REFUSED, never a
   phantom entity with a hash of nothing. */
int32_t liv_add_file(const char *path, const char *file, uint64_t now_ms,
                     char **out);

/* Re-hash what a file points at on this device.
   {"state":"unchanged"|"changed"|"broken", "path":…|null}

   A changed hash IS the integration — it is how Liv learns Word saved
   the file. A vanished path is "broken" and LEAVES THE STORED HASH
   ALONE: a file on an unplugged drive is not a file whose contents
   changed. `path` is null for a file that arrived by sync and has no
   copy here, which is the honest answer to "where were you looking". */
int32_t liv_resync_file(const char *path, const char *id, uint64_t now_ms,
                        char **out);

/* What the clerk would suggest, as the inbox reads it.
   [{"entity":"<hex>", "print":N, "proposer", "reason"}…]

   A PROPOSAL IS NAMED BY THE THING IT IS ABOUT AND ITS FINGERPRINT, NEVER
   ITS POSITION. The sweep is a pure function of the box and is recomputed
   in every process, so an index would mean something different by the
   time the user tapped it.

   A proposal with no ops proposes nothing and is left out, so `entity` is
   always there: a row the shell is shown must be a row it can act on. */
int32_t liv_sweep(const char *path, char **out);

/* Say yes / say no, passing back the two things the row named. The
   proposal is RE-DERIVED from the box rather than taken on trust: one the
   box no longer makes is one the user already acted on, and
   LIV_ERR_NOTHING says so rather than writing something stale.

   `entity` is what makes that affordable. Re-deriving the WHOLE box to
   find one proposal cost 120 ms in a 500-note box — every tap in the
   inbox re-reading everything — against 3 ms for the one thing, and the
   guarantee is identical: sweeping one thing is sweeping everything,
   narrowed, and a test compares the two entity by entity.

   DECLINING IS NOT FORGETTING — a refusal persists and the clerk does
   not ask again. */
int32_t liv_accept(const char *path, const char *entity, uint64_t print,
                   uint64_t now_ms);
int32_t liv_decline(const char *path, const char *entity, uint64_t print,
                    uint64_t now_ms);

/* ====================================================================
   THE VERBS EVERY TAP USES

   The block above is the EDITOR's doors — bodies, undo, files, renames,
   the clerk. These are the app's: capture a scrap, make a thing, tick a
   checkbox, file it under Work, throw it away. Without them a shell on
   the engine can read and never touch.

   A VALUE CROSSES AS TEXT, and the property says what it means. The
   shell sends "yes", "3", "2026-09-13", "Work"; whether that is a bool,
   a number, a date or an option is a fact about the property, which the
   box already knows. The alternative — the shell declaring the type of
   everything it sends — puts the model in two places and makes every new
   field a Swift change. LIV_ERR_REFUSED comes back, with nothing
   written, when the text does not read.

   A PROPERTY IS NAMED BY ITS ID, not its name. The old ABI's liv_set_at
   takes a name and looks it up, which quietly makes renaming a field
   break every caller that spelled it. Use liv_property_named once to
   turn a frozen name into an id, then pass the id.
   ==================================================================== */

/* Make one thing of a kind, optionally named. {"id":"<hex>"}
   `name` may be NULL for something born untitled, which is the common
   case and not an error. */
int32_t liv_make(const char *path, const char *kind, const char *name,
                 uint64_t now_ms, char **out);

/* Capture a scrap: one UNTYPED thing whose body is this text, in one
   action. {"id":"<hex>"}

   Untyped is the point. A capture is a thought, not a decision about
   what kind of thing it is — the clerk's promotion proposer is what
   offers to make it a task later, and it can only offer that because
   nothing here decided first. One action, so one undo takes the whole
   capture back rather than leaving an empty note behind. */
int32_t liv_capture(const char *path, const char *text, uint64_t now_ms,
                    char **out);

/* Set a register; add a member to a set; take one out.

   liv_remove is ADD-WINS: a member added concurrently on another device
   survives it, which is why a tag added on the phone is not lost by a
   removal on the laptop. */
int32_t liv_set(const char *path, const char *entity, const char *property,
                const char *value, uint64_t now_ms);
int32_t liv_add(const char *path, const char *entity, const char *property,
                const char *value, uint64_t now_ms);
int32_t liv_remove(const char *path, const char *entity, const char *property,
                   const char *value, uint64_t now_ms);

/* Empty a cell. NOT the same as setting it to nothing — an unset cell
   has no value at all, which is what a picker's "None" means and what a
   due date cleared off a task means.

   Emptying an empty cell writes nothing, so a picker set to None twice
   is one undo rather than two. */
int32_t liv_unset(const char *path, const char *entity, const char *property,
                  uint64_t now_ms);

/* Into the trash, and back out. TRASHING IS A CELL, not a deletion:
   nothing leaves the log, which is what makes restore a write rather
   than a resurrection — and what lets an undone create stay readable in
   the Trash, where a person goes to get it back. */
int32_t liv_trash(const char *path, const char *entity, uint64_t now_ms);
int32_t liv_restore(const char *path, const char *entity, uint64_t now_ms);

/* Everything a reference property may point at, named and in the order a
   picker should show them: [{"id":"<hex>","name":…}…]

   THE WORDS COME FROM THE BOX, NEVER FROM THE SHELL. The current tree
   keeps the six area names as a Swift constant, which one-core.md §4
   records as a mistake: a shell carrying its own copy of the furniture
   drifts from the box that stores it, and the drift is invisible until
   someone renames something.

   Compiled-in furniture and a user's own come back in ONE list, because
   that is what the cell accepts — a picker that separated them would be
   inventing a distinction the model does not have. Empty for a property
   that holds no references, which is an answer and not a failure. */
int32_t liv_options(const char *path, const char *property, char **out);

/* One thing's cells, as the inspector reads them:
   [{"property":"<hex>","name","holds","many","value","ref":"<hex>"?,
     "contended":bool}…]

   `value` is ALWAYS a display string, so a shell renders a row without
   knowing the kind; `ref` carries the target when there is one, for a row
   that is tappable.

   `contended` is not decoration. Two devices can leave a register holding
   two values, and the model's rule is that nothing silently wins, so the
   shell has to be able to show the choice rather than pick one. */
int32_t liv_cells(const char *path, const char *entity, char **out);

/* The kinds a create menu offers: [{"id":"<hex>","name":…}…]
   The six the product names, in product order, plus anything the user
   declared. Not every kind that exists — the rest is furniture the app
   draws with, and a person never picks one from a list. */
int32_t liv_kinds(const char *path, char **out);

/* The id of a compiled-in property by its stable name — "due", "status",
   "area". {"id":"<hex>"} LIV_ERR_ARG when nothing is called that.

   A shell needs SOME way in. Every other verb here names a property by
   id, which is right, but the first id has to come from somewhere and
   hard-coding 32 hex characters in Swift is worse than asking. These
   names are frozen (op-format.md's ordinals-on-disk-forever), so this is
   a lookup of something stable, not of a label a user can change. */
int32_t liv_property_named(const char *path, const char *name, char **out);

/* ====================================================================
   FINDING THINGS

   TWO JOBS, ONE GRAMMAR. The same text means two different things
   depending on where it is typed, and the parser is told which:

     - a SEARCH BOX WIDENS. `is:archived` means "look in the archive
       too", because someone hunting for a thing wants it found.
     - a LENS RESTRICTS. The same `is:archived` in a workspace filter
       means "only archived things", because a filter is a boundary.

   liv_search is the first, liv_lens the second. Separate verbs rather
   than a flag, because the answers are shaped differently: a search is
   ranked hits with facets, a lens is a flat set of ids.

   A USER NEVER TYPES THIS. The text grammar is the storage format and
   an advanced escape hatch, not the interface. liv_terms is how a
   stored filter becomes chips a person edits by tapping.
   ==================================================================== */

/* Ranked hits and the facet rows beside them.
   {"hits":[{"id":"<hex>","score":N,"field":…}…],
    "facets":[{"property":"<hex>","label",
               "values":[{"label","count","active","excluded"}…]}…]}

   `field` says WHERE the best match was — name | cell | filed | content,
   or "structured" for a pure-qualifier hit — so a row can hint why it is
   in the list rather than leaving the user to guess.

   `limit` BOUNDS THE HITS AND NEVER THE FACETS. A facet count is over
   everything the query matches: a row saying "Work 12" when the list
   shows 10 is telling the truth about the box, and a count that changed
   with how far the user had scrolled would be useless for pivoting,
   which is the one thing a facet row is for. 0 means no ceiling.

   A facet count also excludes its OWN property's constraints, or a facet
   you have already picked shows its own count and nothing else. */
int32_t liv_search(const char *path, const char *query, uint32_t limit,
                   char **out);

/* The ids a LENS admits: {"ids":["<hex>"…], "terms":[…]}

   The same grammar read the other way round. The lexed terms come back
   with the ids so a shell can draw the filter as chips in the same
   breath it applies it, without parsing the text itself. */
int32_t liv_lens(const char *path, const char *query, char **out);

/* Split a query into its terms. NO BOX, no lock, no opinion about
   whether a property exists — safe to call on every keystroke.
   [{"op","key","value","raw"}…]

   `raw` is the term respelled canonically, so joining a term list back
   together reproduces a query that lexes the same way. That is what lets
   a shell edit a filter as chips and write the result back as text.

   Named liv_terms, not liv_lex: the old ABI already exports a liv_lex
   over core/'s grammar, and every engine verb is purely additive. */
int32_t liv_terms(const char *query, char **out);

/* Every value this property is actually CARRYING, commonest first:
   [{"label","ref":"<hex>"?,"count":N}…]

   A different question from liv_options, which asks what a cell MAY
   hold. A free-text field has no options and still wants to offer what
   the user has typed before. Trashed things are left out: offering what
   the trash holds is offering someone their own deletions back. */
int32_t liv_values_in_use(const char *path, const char *property, char **out);

/* Every file reference this device cannot open:
   [{"id":"<hex>","name","path":…|null,"why":"absent"|"gone"}…]

   A HASH TRAVELS AND A PATH DOES NOT, which is why these are two
   answers and not one. A file added on the laptop reaches the phone as
   a real, valid reference with no local copy — "absent", and the answer
   is "find it for me". A path this device knows that no longer holds a
   file is "gone", and that one is broken.

   Neither touches the stored hash: a file on an unplugged drive is not
   a file whose contents changed. */
int32_t liv_file_alerts(const char *path, char **out);

/* The workspace tree, and the saved filters:
   [{"id":"<hex>","name","query", …}…]

   A WORKSPACE IS AN ORDINARY ENTITY, so there is no verb here that
   makes one — liv_make with the workspace kind and liv_set of its cells
   already do, which is the whole point of the primitives existing.
   These only read.

   liv_workspaces adds emoji, favorite, archived, builtin, parent and
   order. An ARCHIVED workspace is included WITH ITS FLAG: the switcher
   shows them behind a disclosure, and filtering them out here would
   take that choice away from the shell. A trashed one is gone, which is
   a different thing. */
int32_t liv_workspaces(const char *path, char **out);
int32_t liv_views(const char *path, char **out);

/* The clerk's consent switch: {"on":bool, "property":"<hex>"}

   ABSENT OR TRUE IS ON; only an explicit false silences it — an older
   box that never set it is not a box that said no. Turning it off is an
   ordinary liv_set of the property named here, which is why there is no
   writer for it. */
int32_t liv_assist(const char *path, char **out);

/* ---- the last three, found by mapping the old ABI verb by verb ---- */

/* Declare a field the app did not ship with — the product's "new kind of
   field behind a door in Settings". {"id":"<hex>"}

   `holds` is text | number | bool | datetime | reference | richtext |
   file; `many` makes it a set rather than a register. LIV_ERR_REFUSED
   for a shape the model does not have.

   It is an ordinary entity, MINTED ONCE on one device, which is what
   stops it drifting the way a seeded copy does: there is no second copy
   to disagree with. */
int32_t liv_declare_field(const char *path, const char *name,
                          const char *holds, bool many, uint64_t now_ms,
                          char **out);

/* Accept several suggestions as ONE action. {"taken":N}

   ALL OR NOTHING, AND ONE UNDO. Half a consent is worse than none: the
   user agreed to a set, and a set that half-landed is not what they
   agreed to.

   `entities` and `prints` are parallel arrays of `count` items, each
   proposal named the way liv_accept names one.

   A fingerprint the box no longer proposes is SKIPPED rather than
   failing the batch: "accept all" is a sweep of what is on screen, and
   one row the user already dealt with on another device is not a reason
   to refuse the other nine. Only what was actually passed is taken —
   never everything the entity happens to be offering. LIV_ERR_NOTHING
   when none of them landed. */
int32_t liv_accept_all(const char *path, const char *const *entities,
                       const uint64_t *prints, uint32_t count,
                       uint64_t now_ms, char **out);

/* Why the box will not open: {"code","message"}, code "ok" when it does.
   Codes: ok | version | corrupt | io.

   A SHELL THAT CANNOT OPEN THE BOX HAS NOTHING ELSE TO ASK. Every other
   verb answers LIV_ERR_OPEN, which says that it failed and not what to
   do about it, and the answers need different screens. "version" means
   the box was written by a newer build and the user should update —
   the one a wrong answer strands someone on. */
int32_t liv_probe_box(const char *path, char **out);

/* ---- the two surfaces the swap would otherwise take away ---- */

/* What is in the trash, newest first — the same row shape every other
   surface returns, so the Trash screen draws with the code every list
   already has.

   THE ONE SURFACE THAT WANTS THE ROWS THE OTHERS THROW AWAY, and it
   ignores the lens on purpose: the trash is the trash, and a workspace
   filter hiding some of it would leave someone unable to find the thing
   they are trying to get back. Archived is NOT trashed and is not here. */
int32_t liv_view_trash(const char *path, char **out);

/* Open `- [ ]` lines written inside notes:
   [{"note":"<hex>","source","line":N,"text","depth":N}…]

   A PROJECTION: nothing here is stored. No entity is created and no cell
   is written — a line in a note is a thought, not a task someone has to
   file. `line` is the block's index from the top of the body, which is
   the toggle's address, so a shell can tick it without a second scan.

   Notes only: something already typed as a task or an event is listed as
   itself, and its body lines would be the same work counted twice. */
int32_t liv_note_tasks(const char *path, char **out);

/* The properties a person can put on something:
   [{"id":"<hex>","name","holds","many"}…]

   The six the product names, then anything the user declared. NOT every
   property that exists — most are plumbing the app needs and never
   offers as a field to fill in, and a picker listing `trashed` beside
   `due` would be the model leaking through the interface. */
int32_t liv_properties(const char *path, char **out);

/* Turn the clerk on or off.

   THE BOX OWNS WHERE THE SWITCH LIVES. The clerk is off when any live
   thing carries an explicit no, so turning it off means writing one and
   turning it back on means taking it away — a rule about the model, not
   something a shell should have to know.

   Absent or true is ON, so turning it on REMOVES the cell rather than
   writing true: a box that never said anything and a box that said yes
   are the same box. */
int32_t liv_set_assist(const char *path, bool on, uint64_t now_ms);

/* Mint a new value for a property that points at things, and offer it.
   {"id":"<hex>"}

   THE KIND IS WHATEVER THE PROPERTY POINTS AT, not always an Option.
   `area` is RefTo(kind::AREA) and `status` is RefTo(kind::STATUS);
   minting an Option for either makes something the cell refuses — a new
   area that cannot be chosen.

   It joins the property's declared `options` only where the property
   keeps a list: a RefTo with none accepts anything of its kind, so a
   minted area is choosable the moment it exists.

   Minting is a DECISION, which is why it is its own verb and not
   something liv_set does when a name does not match. Typing a typo must
   not create a seventh area. Asking twice hands back the one that
   already exists, case-insensitively. LIV_ERR_REFUSED for a field with
   no vocabulary. */
int32_t liv_add_option(const char *path, const char *property,
                       const char *name, uint64_t now_ms, char **out);

/* THE ONE-WAY DOOR: build an engine box from a core box.

   Refuses if `to` already exists — "run it again" is the first thing
   anyone tries and a converter that allows it can double a box. To
   rebuild, delete the file first, which is also how a shell says "throw
   the conversion away and take the core box as truth again".

   It RESOLVES the core box's schema rather than copying it: a fresh box
   is 70 entities and almost all of it is 51 property definitions, a type
   per kind and an option per area and status, all of which the engine has
   compiled in. Copying them would put a second "due" and a second "Work"
   beside the frozen ones in every picker.

   The report:
   {"entities","cells","resolved","minted_vocabulary","flattened",
    "files_dropped","undeclared","unknown_kinds":[…],"clean"} */
int32_t liv_view_convert(const char *from, const char *to, char **out);

#endif
