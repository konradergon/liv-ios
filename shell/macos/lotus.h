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

#endif
