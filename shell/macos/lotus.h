/* The one C seam between the macOS shell and the core.
   One function; the shell never sees an entity or a byte of the log. */

#ifndef LOTUS_H
#define LOTUS_H

#include <stdint.h>

/* Capture one scrap into the box at path (created and seeded if fresh).
   Opens, writes, closes: the shell never holds the box.
   Returns the new entity id, or 0 on failure. */
uint64_t lotus_capture_at(const char *path, const char *text);

#endif
