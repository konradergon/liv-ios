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

/* Create a task by hand (Tasks quick-add): Create + type:task +
   status:todo + created, one transaction. Returns the id, 0 on failure.
   Distinct from capture, which quarantines an untyped scrap. */
uint64_t lotus_create_task_at(const char *path);

/* Add a file by reference — the librarian: hash the file's bytes, create
   an entity with a file cell (path + hash), format, and name, one
   transaction. NEVER moves, copies, or renames the file. Returns the new
   id, 0 on failure (unreadable path, busy box). */
uint64_t lotus_add_file_at(const char *path, const char *file_path);

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
