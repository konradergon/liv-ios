/* The one C seam between the macOS shell and the core.
   The shell never sees an entity or a byte of the log — it captures,
   reads one JSON snapshot, and triages by (entity, ordinal, fingerprint).
   Every call opens the box and closes it; the shell never holds it. */

#ifndef LOTUS_H
#define LOTUS_H

#include <stdint.h>

/* Capture one scrap into the box at path (created and seeded if fresh).
   Returns the new entity id, or 0 on failure. */
uint64_t lotus_capture_at(const char *path, const char *text);

/* Everything the window renders, as one JSON document.
   NULL on failure (probe to learn why). Free with lotus_string_free. */
char *lotus_snapshot(const char *path);

/* The same snapshot over a caller-chosen occurrence window: `dated` is
   unchanged (the full set; the shell buckets by day), but the recurrence
   `occurrences` are expanded over [from_civil, to_civil] (civil YYYYMMDDHHMM)
   instead of the current month. The engine caps the window at a year.
   NULL on failure. Free with lotus_string_free. */
char *lotus_snapshot_window_at(const char *path, int64_t from_civil, int64_t to_civil);
void lotus_string_free(char *s);

/* Accept / decline a proposal. The fingerprint comes from the snapshot
   and must still match — a consent is to a proposal, never a position.
   Return 1 on success, 0 when busy or when the queue shifted. */
int lotus_accept_at(const char *path, uint64_t entity, uint32_t ordinal,
                    uint64_t fingerprint);
int lotus_reject_at(const char *path, uint64_t entity, uint32_t ordinal,
                    uint64_t fingerprint);

/* Undo the last committed transaction. 1 on success. */
int lotus_undo_at(const char *path);

/* Why the box would not open: {"code","message"} JSON, or NULL when it
   opens fine. Codes: locked | corrupt | version | io. */
char *lotus_probe(const char *path);

/* One entity's content, fresh from the box:
   {"id":7,"name":"…"|null,"trashed":false,"missing":false,
    "fingerprint":1234,"spans":[{"Text":"…"},{"Ref":9},…]}
   Spans are the log's own serde encoding of Span, verbatim. Legacy
   plain-text content reads as one Text span (fingerprint still over the
   stored value); fingerprint is 0 when no content cell exists. Redirects
   resolve before reading. A box that opened fine but holds no such
   entity answers missing:true; NULL means only that the box itself is
   unavailable (probe to learn why). Free with lotus_string_free. */
char *lotus_content_at(const char *path, uint64_t id);

/* Replace the entity's whole content in one transaction (the editor's
   save). Empty spans remove content. base_fingerprint must still match
   the stored content — a save is to a value, never a moment. There is no
   force flag: overwrite is re-read then save. On success
   *fresh_fingerprint receives the new content's fingerprint.
   Returns 1 saved, -1 stale, 0 busy or invalid. */
int32_t lotus_set_content_at(const char *path, uint64_t id,
                             const char *spans_json,
                             uint64_t base_fingerprint,
                             uint64_t *fresh_fingerprint);

/* Set one property by name: the CLI's `set` through the seam — value
   parsed by the property's declared kind, replace-the-cell, one
   transaction. Serves the checkbox ("status","done"), rename ("name",…)
   and the inspector to come. 1 ok, 0 busy/parse failure/no entity. */
int32_t lotus_set_at(const char *path, uint64_t id,
                     const char *property, const char *value);

/* Ranked hits + facet counts for one raw DSL query, as JSON:
   {"hits":[{"id":7,"score":100.0,"field":"name"},…],
    "facets":[{"property":2,"label":"Type","values":[
       {"value":{"Reference":41},"label":"Task","count":12,"active":false},…]}]}
   Search is navigation: its own seam, not the cached snapshot. hits are
   bare ids (the shell already holds each title/cells) in rank order.
   Free with lotus_string_free. NULL when the box is unavailable. */
char *lotus_search_at(const char *path, const char *raw_query);

/* Every past version of an entity's content, NEWEST first:
   [{"seq":N,"time":..,"author":"..","label":"..","spans":[..]}]
   The log is the history — each entry is a whole content value.
   Restore one with lotus_set_content_at of its spans. NULL when the box
   is unavailable. Free with lotus_string_free. */
char *lotus_content_history_at(const char *path, uint64_t id);

/* Birth of a note: Create + type:note + created, one transaction.
   Returns the id, 0 on failure. Caller drops straight into renaming. */
uint64_t lotus_create_note_at(const char *path);

/* Get-or-create the daily note for a day (any packed civil in it) and
   workspace (0 = none). Returns the note id, 0 on failure. Idempotent per
   (date, workspace) — the one place find-then-create is atomic. */
uint64_t lotus_open_daily_note_at(const char *path, int64_t date_civil,
                                  uint64_t workspace);

/* Stamp an entity's TYPE by name (P12 12d Inbox Route commit). 1 ok, 0 on
   refusal (unknown type name / no entity). */
int32_t lotus_set_type_at(const char *path, uint64_t id, const char *type_name);

/* Create a task by hand (Tasks quick-add): Create + type:task +
   status:todo + created, one transaction. Returns the id, 0 on failure.
   Distinct from capture, which quarantines an untyped scrap. */
uint64_t lotus_create_task_at(const char *path);

/* Create an event by hand (the "+ Event" button, or double-click a day/hour).
   One transaction: type:event + due (from due_civil, all-day when date_only)
   + created. Returns the id, 0 on failure. Distinct from capture. */
uint64_t lotus_create_event_at(const char *path, int64_t due_civil, int32_t date_only);

/* Space-cycles a date row's role: one transaction moving the value (civil +
   date_only intact) from `property` to the next role in the ring
   due -> date -> valid-until -> occurred -> purchased-on -> due. Returns the
   NEW property name (free with lotus_string_free), NULL on busy/refusal. */
char *lotus_cycle_date_role_at(const char *path, uint64_t id, const char *property);

/* Writes a date/span cell as ONE command (the mirror contract: inspector
   row, calendar drag, and span-grip drag are all this write). end_civil = 0
   means no end (a plain date); an end not strictly after the start is
   refused. date_only applies to both ends. Returns 1, or 0 on busy/refusal. */
int32_t lotus_set_span_at(const char *path, uint64_t id, const char *property,
                          int64_t start_civil, int64_t end_civil, int32_t date_only);

/* The status vocabulary OFFERED to a kind, sorted by board order: JSON
   [{id,name,order,hue,completes}]. Options with no carriers included (an
   empty column keeps its header). NULL on busy/unknown kind. Free with
   lotus_string_free. */
char *lotus_status_options_at(const char *path, const char *kind);

/* A new status option for a kind (column-add / "Edit vocabulary..."): one
   commit, ordered last. hue < 0 means none. Returns the option id, or 0. */
uint64_t lotus_add_status_option_at(const char *path, const char *kind,
                                    const char *name, double hue);

/* Layer 1 of the value pool: a property's distinct live values with usage
   counts, JSON [{value, count}], deterministic order (count desc, then
   display). NULL on busy/unknown property. Free with lotus_string_free. */
char *lotus_distinct_values_at(const char *path, const char *property);

// Birth a property definition (P11.5g add-property create leg). Returns
// the new definition id, 0 on refusal (empty/duplicate name, unknown kind).
uint64_t lotus_add_property_at(const char *path, const char *name,
                               const char *kind);

/* Birth of a list: Create + type:list + name + created, one transaction.
   Named at birth (unlike a note). Returns the id, 0 on failure. */
uint64_t lotus_create_list_at(const char *path, const char *name);

/* Add / remove ONE cell of a multi-valued property — list membership
   (property "related", value "#<member-id>"). Unlike lotus_set_at
   (replace-all) and lotus_unset_at (remove-all), these touch exactly one
   cell, and never delete the referenced entity. A no-op (already/not a
   member) still returns 1. 1 ok, 0 on busy/parse/no-entity. */
int32_t lotus_add_cell_at(const char *path, uint64_t id,
                          const char *property, const char *value);
int32_t lotus_remove_cell_at(const char *path, uint64_t id,
                             const char *property, const char *value);

/* Add a file by reference — the librarian: hash the file's bytes, create
   an entity with a file cell (path + hash), format, and name, one
   transaction. NEVER moves, copies, or renames the file. Returns the new
   id, 0 on failure (unreadable path, busy box). */
uint64_t lotus_add_file_at(const char *path, const char *file_path);

/* Import a batch (P15). items_json is a JSON array of tagged items
   ({"kind":"link","url":...,"title":...} / {"kind":"file","path":...} /
   {"kind":"note","frontmatter":[[k,v]...],"body":...,"source_id":...} /
   {"kind":"scrap","text":...}); stamps_json is [[property,target]...] reference
   cells stamped on every committed entity (the funnel's inherited project/area).
   ONE transaction, one undo; external-id / file-hash dedupe skips re-imports.
   Returns the count committed (deduped items skipped), -1 on a parse/box error. */
int64_t lotus_import_batch_at(const char *path, const char *items_json,
                              const char *stamps_json);

/* Export (P15). ids_json is [id...] (the shell-resolved matched-minus-unchecked
   set); group_props_json is [property...] group-by properties (<=2 used); dest a
   folder OUTSIDE the box. Copy-only, a projection — the log is untouched.
   Returns the count written, -1 on a parse/IO error. */
int64_t lotus_export_at(const char *path, const char *ids_json,
                        const char *group_props_json, const char *dest);

/* Re-hash a file entity's referenced path; if the bytes changed, replace
   the file cell (one transaction — a changed hash is the integration).
   1 changed & rewritten, 0 unchanged, -1 the path no longer resolves
   (broken reference). Called when a file is opened, never on a timer. */
int32_t lotus_resync_file_at(const char *path, uint64_t id);

/* A file entity's extracted plain text (the read-only preview), from the
   hash-keyed cache (extracting on a miss; the cache is rebuildable, never
   part of the log). Empty when there's no extractable text or the file is
   broken. Free with lotus_string_free; NULL only when the box is
   unavailable. */
char *lotus_extracted_text_at(const char *path, uint64_t id);

/* Birth of a workspace: Create + type + name (+ parent reference and a
   trailing order), one transaction. parent 0 = top level. Returns the
   id, 0 on failure. */
uint64_t lotus_create_workspace_at(const char *path, const char *name,
                                   uint64_t parent);

/* Trash one workspace — and only that one. Deletion never cascades:
   the children keep their dangling `parent` and the shell re-roots
   them. 1 on success, 0 on failure. */
int32_t lotus_trash_workspace_at(const char *path, uint64_t id);

/* Trash one entity — the inspector's Trash action. Soft, reversible,
   never cascades. 1 on success, 0 on failure. */
int32_t lotus_trash_at(const char *path, uint64_t id);

/* Remove every cell of one property — the inverse of lotus_set_at's
   replace. Missing property on the entity is success. 1 ok, 0 on
   busy/no entity/no property definition. */
int32_t lotus_unset_at(const char *path, uint64_t id, const char *property);

#endif
