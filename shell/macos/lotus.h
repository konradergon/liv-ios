/* The one C seam between the macOS shell and the core.
   The shell never sees an entity or a byte of the log — it captures,
   reads one JSON snapshot, and triages by (entity, ordinal). Every call
   opens the box and closes it; the shell never holds it. */

#ifndef LOTUS_H
#define LOTUS_H

#include <stdint.h>

/* Capture one scrap into the box at path (created and seeded if fresh).
   Returns the new entity id, or 0 on failure. */
uint64_t lotus_capture_at(const char *path, const char *text);

/* Everything the window renders, as one JSON document.
   NULL on failure (including the box being open elsewhere).
   Free the result with lotus_string_free. */
char *lotus_snapshot(const char *path);
void lotus_string_free(char *s);

/* Accept / decline the proposal addressed by (entity, ordinal) — the
   1-based ordinal the snapshot reports; 0 means "the only one".
   Declines are remembered forever. Return 1 on success. */
int lotus_accept_at(const char *path, uint64_t entity, uint32_t ordinal);
int lotus_reject_at(const char *path, uint64_t entity, uint32_t ordinal);

#endif
