/* The one C seam between the macOS shell and the core.
   Three functions; the shell never sees an entity or a byte of the log. */

#ifndef LOTUS_H
#define LOTUS_H

#include <stdint.h>

typedef struct LotusSession LotusSession;

/* Open (or create) the box at path, seeded if fresh. NULL on failure. */
LotusSession *lotus_open(const char *path);

/* Capture one scrap. Returns the new entity id, or 0 on failure. */
uint64_t lotus_capture(LotusSession *session, const char *text);

/* Close the session. NULL is a no-op. Do not use the pointer again. */
void lotus_close(LotusSession *session);

#endif
