/* The one C seam between a native shell and the engine.
   A shell calls these verbs to change the box and to ask it what each
   screen shows; it never sees a byte of the log. Every verb answers
   LIV_OK or a negative code, and JSON through an out-pointer.

   The core-era verbs that used to open this file — capture/set/trash
   `_at`, `liv_snapshot`, triage by fingerprint — went with `core/` in
   stage 5 of design/rust-owns-the-mechanisms.md (2026-09-29). Nothing
   called them: the app moved onto the verbs below at slice 5b. */

#ifndef LIV_H
#define LIV_H

#include <stdbool.h>
#include <stdint.h>

/* Free a string a verb handed back through its out-pointer. */
void liv_string_free(char *s);


/* ====================================================================
   THE SEAM: one verb per screen, over the engine.

   A screen asks for itself and gets itself. The core-era ABI handed the
   shell the WHOLE BOX as one `liv_snapshot` document — 3.5 MB and 39 ms
   at 6,400 notes, rebuilt on every refresh — and the shell searched it to
   work out what Today is. Measured over one 2,000-task box: one day here
   is 2,268 bytes against the box's 448,891, and the ratio grows with the
   box rather than the screen. The deciding happens in `liv-surface`,
   where `cargo test` reaches it.

   Three things the seam is built on:

   1. A REAL ERROR CHANNEL. Every verb returns LIV_OK or a negative code,
      and the answer comes back through an out-pointer. The old ABI's `0`
      meant both "no id" and "it broke", so a shell could not tell an
      empty box from an unreadable one. Here an empty box is LIV_OK and an
      empty array.
   2. SIXTEEN-BYTE IDS, as 32 lowercase hex characters. An engine id is a
      UUID and a JSON number is not one.
   3. THE CONNECTION IS HELD. The engine is a database, so opening is
      0.3 ms and flat and SQLite does its own locking in WAL mode; there
      is no open-replay-close per call.

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

/* The Today screen. `now_ms` is the real instant and `offset_min` the
   phone's distance from UTC; "today" is the day on the phone's clock,
   and a due, which is a wall-clock time, is compared with now on that
   clock.

   {"days":[{"day":N, "all_day":[row…], "passed":[…], "ahead":[…],
             "done":[…], "areas":[{"name","count"}…], "unfiled":N}…],
    "late":[row…], "what_next":[row…], "captured":N}

   `days` is the date strip: today and the six days after it, so picking
   a day redraws without asking again. Only today has `passed`. `areas`
   and `unfiled` count what is late, open or all-day on that day, by
   area. `what_next` is up to five open tasks with no date, last touched
   first. `captured` counts the scraps (no kind yet) caught today.

   CHANGED IN PLACE 2026-09-30 (owner's word), like liv_view_tasks: the
   app had never called it, and it had fallen behind the screen.

   A row is
   {"id","title","untitled","kind"?,"due_ms"?,"all_day","status"?,"done","late",
    "area"?,"created_ms","touched_ms","has_file","has_body",
    "kind_word"?,"status_word"?,"area_word"?,"archived","trashed"}
   — already titled, already sorted, and `done` already resolved against
   which statuses complete.

   has_body ADDED 2026-09-15, purely additive: does the thing hold any
   words (whitespace does not count). Four shell surfaces ask it and on
   core/ it was answered by the body's compare-and-swap print being
   non-zero — which the engine hands back per body from liv_read_body,
   not per row, so all four quietly answered "no" and the Inbox listed
   nothing to route while the panel counted eight captures. It is NOT a
   fingerprint: "did MY base move" is a different question. */
int32_t liv_view_today(const char *path, int64_t now_ms, int32_t offset_min,
                       const char *lens, char **out);

/* The Tasks screen. `project` is a hex id or NULL; it narrows the groups
   and nothing else.

   {"groups":[{"status":"<hex>"?, "name", "completes", "hue":N?,
               "late":N, "rows":[row…]}…],
    "open":N, "late":N,
    "in_notes":[{"note":"<hex>","source","line","text","depth"}…],
    "projects":[{"id":"<hex>","name"}…]}

   Groups come in the status picker's order (liv_options on `status`), so
   a status segment picks its group by name without asking again. An
   empty group is not returned. `open` and `late` are the whole screen's
   counts inside the lens — the project filter does not move them — and
   `open` includes the open lines in notes. `projects` is what the
   Project menu offers: the six most used, commonest first.

   CHANGED IN PLACE 2026-09-30 (owner's word): the app had never called
   this verb, and it had fallen behind the screen. Rows gained "late"
   (open task, day passed) on every surface; it is set by the three told
   what day it is — Today, Tasks and the library — and false on the rest.

   CHANGED IN PLACE 2026-10-01 (owner's word), with liv_view_day,
   liv_view_search and liv_view_trash: `offset_min` is the phone's clock
   against UTC (as liv_view_today). A row with no name and no body is
   titled by its kind and when it was made — "Task · 1 Oct 06:07" — and
   that time is read on the phone's clock; it was UTC. */
int32_t liv_view_tasks(const char *path, const char *project,
                       int32_t today, int32_t offset_min, const char *lens,
                       char **out);

/* The library, in one pass over the box: every live row, the Notes and
   Unsorted lists as ids into it, and the count beside each view in the
   library panel. ADDED 2026-09-30, replacing liv_view_everything as the
   read a shell makes after every write.

   {"all":[row…], "notes":["<hex>"…], "unsorted":["<hex>"…],
    "counts":{"today","unsorted","notes","tasks","events"}}

   `all` is newest first and never lensed: it is what a shell looks a
   thing up in by id. `notes` is what opens as a page, in the lens, last
   touched first. `unsorted` is what a person files with no area, newest
   first, and NEVER lensed — a thing made under the wrong workspace must
   not vanish. Each count is the number of rows its view shows; `today`
   is open things that can be ticked, due today or earlier. `now_ms` and
   `offset_min` as liv_view_today. */
int32_t liv_view_library(const char *path, int64_t now_ms, int32_t offset_min,
                         const char *lens, char **out);

/* The reminders still to come, soonest first. ADDED 2026-10-01.

   {"soonest":[row…], "total":N}

   What rings: an event, or a task still open (a status makes a thing a
   task), at its clock time — a bare date never rings — after now on the
   phone's clock (`now_ms`, `offset_min` as liv_view_today), in every
   workspace, never from the trash or the archive. `soonest` is the first
   `limit`; `total` counts them all, so a shell with a cap on pending
   alarms can say how many did not fit. */
int32_t liv_view_reminders(const char *path, int64_t now_ms, int32_t offset_min,
                           uint32_t limit, char **out);

/* The calendar: every day from `from_day` to `to_day` (days since the
   epoch, both included) that has anything on it, in order.

   [{"day":N, "all_day":[row…], "timed":[row…]}…]

   Which things fall on which day, and nothing about where they are
   drawn: the shell lays out the hour grid itself, because it must do so
   again on every frame of a drag.

   CHANGED IN PLACE 2026-09-30 (owner's word): it answered one day with
   its blocks already laid out, the app had never called it, and the
   calendar needs a range — the month card's dots — more than a layout.
   `offset_min` as liv_view_tasks (2026-10-01). */
int32_t liv_view_day(const char *path, int32_t from_day, int32_t to_day,
                     int32_t offset_min, const char *lens, char **out);

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
   phantom entity with a hash of nothing.

   A file INSIDE THE BOX'S FOLDER is remembered relative to it, so a
   moved box or a reinstalled app still finds it — which is why the phone
   puts what it is handed in <box folder>/files/<uuid>/<name> first. A
   file anywhere else is remembered by its whole path. */
int32_t liv_add_file(const char *path, const char *file, uint64_t now_ms,
                     char **out);

/* Re-hash what a file points at on this device.
   {"state":"unchanged"|"changed"|"broken", "path":…|null, "bytes":N|null}

   A changed hash IS the integration — it is how Liv learns Word saved
   the file. A vanished path is "broken" and LEAVES THE STORED HASH
   ALONE: a file on an unplugged drive is not a file whose contents
   changed.

   THIS IS WHERE A SHELL LEARNS WHERE A FILE IS. `path` is always whole,
   joined to the box's folder as it is now, so it is the path to open; it
   is null for a file that arrived by sync and has no copy here, and a
   broken file still names where it looked. `bytes` is the file's size,
   null when broken. */
int32_t liv_resync_file(const char *path, const char *id, uint64_t now_ms,
                        char **out);

/* The words in a file, and what a note made of it is called:
   {"name":"<name without its extension>", "text":"…"|null}

   NO BOX — it reads one file and writes nothing. `text` is null when the
   file does not hold text, and that is the engine's call, not the
   shell's: UTF-8, no NUL byte, at most half a megabyte, and not another
   app's markup (rtf, csv, svg, html, xml, ics, vcf, eml…). An empty file
   is text only when its name says so (.txt, .md, none). A byte order mark
   is dropped and every line ending reads as \n. `name` loses only a real
   extension: "Dr. Who quotes" stays whole. A path that will not read is
   LIV_ERR_REFUSED. */
int32_t liv_file_text(const char *file, char **out);

/* Make a note with its name and its words in ONE action. {"id":"<hex>"}

   What a text file handed to the phone becomes: liv_make then
   liv_write_body would be two actions, and one undo would leave an empty
   note behind. `name` may be NULL, and a blank one writes no name; empty
   spans write no body. LIV_ERR_ARG for spans that are not span JSON;
   LIV_ERR_REFUSED for a link to nothing, with nothing written. */
int32_t liv_make_note(const char *path, const char *name, const char *spans,
                      uint64_t now_ms, char **out);

/* Turn a file the box holds into a note of these spans, in ONE action.

   It keeps its id, so its links and cells stay; it loses its hash, its
   format, and that format's extension off the end of its name — nothing
   else of a name someone typed. A file becomes a note; a task or an event
   that carries a file stays what it is. The file on disk is never
   written, and one liv_undo makes it the file it was. LIV_ERR_REFUSED,
   with nothing written, for something that is not a file, a file in the
   trash, or a link to nothing. */
int32_t liv_file_into_note(const char *path, const char *id, const char *spans,
                           uint64_t now_ms);

/* What the clerk would suggest, as the inbox reads it.
   [{"entity":"<hex>", "print":N, "proposer", "reason"}…]

   A PROPOSAL IS NAMED BY THE THING IT IS ABOUT AND ITS FINGERPRINT, NEVER
   ITS POSITION. The sweep is a pure function of the box and is recomputed
   in every process, so an index would mean something different by the
   time the user tapped it.

   A proposal with no ops proposes nothing and is left out, so `entity` is
   always there: a row the shell is shown must be a row it can act on. */
int32_t liv_sweep(const char *path, char **out);

/* What the clerk would suggest about ONE thing: liv_sweep's rows for it,
   the same JSON. The whole-box sweep is Unsorted's and runs only while
   Unsorted is open; a thing's own card asks this instead, and it costs the
   thing rather than the box (2026-09-30, additive). */
int32_t liv_sweep_one(const char *path, const char *entity, char **out);

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

/* Put several back as ONE action, so one undo throws them all out again.
   `ids` is a JSON array of hex ids; {"restored":N} counts what came back.
   One not in the trash is passed over. A list that does not parse, or
   holds anything that is not an id, is LIV_ERR_ARG and writes nothing. */
int32_t liv_restore_many(const char *path, const char *ids, uint64_t now_ms,
                         char **out);

/* Everything a reference property may point at, named and in the order a
   picker should show them:
   [{"id":"<hex>","name":…,"completes":bool,"hue":N|null}…]

   completes AND hue ADDED 2026-09-15, purely additive. A status
   vocabulary without them is three words with nothing to choose between:
   the iOS ring writes "whichever option completes", found none, wrote
   nothing, and a task could not be ticked at all. The engine has held
   prop::COMPLETES all along and a row's own "done" flag already read it
   — only the picker was left guessing.

   completes is ALWAYS present, never omitted for a false: a missing key
   and a false decode the same in Swift and only one of them is an
   answer. hue is null when the option has not got one. Both mean
   something only for a status; every other vocabulary says false and
   null, and a picker that does not care does not look.

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

/* The id of a kind by its name, THE BACKSTAGE ONES INCLUDED — "view",
   "workspace", "note". {"id":"<hex>"} LIV_ERR_ARG when nothing is
   called that. Added 2026-09-15, purely additive.

   liv_kinds above is the CREATE MENU's list and deliberately omits
   Workspace and View: a person never picks one from a list. But the app
   MAKES both — a saved filter is a View, a workspace is a Workspace —
   and that list was the shell's only way to name a kind. So saving a
   new filter looked for "view" among the six, did not find it, and
   wrote nothing: no filter, and no error anyone could see.

   This is the door liv_property_named is, for the reason written there.
   It does NOT widen the picker; liv_kinds still answers the six.
   Matched case-insensitively against the one place these words live. */
int32_t liv_kind_named(const char *path, const char *name, char **out);

/* ====================================================================
   FINDING THINGS

   TWO JOBS, ONE GRAMMAR. The same text means two different things
   depending on where it is typed, and the parser is told which:

     - a SEARCH BOX WIDENS. `is:archived` means "look in the archive
       too", because someone hunting for a thing wants it found.
     - a LENS RESTRICTS. The same `is:archived` in a workspace filter
       means "only archived things", because a filter is a boundary.

   liv_view_search is the first, liv_lens the second. Separate verbs rather
   than a flag, because the answers are shaped differently: a search is
   ranked hits with facets, a lens is a flat set of ids.

   A USER NEVER TYPES THIS. The text grammar is the storage format and
   an advanced escape hatch, not the interface. liv_terms is how a
   stored filter becomes chips a person edits by tapping.
   ==================================================================== */

/* The Search screen. ADDED 2026-09-30, replacing liv_search.

   {"hits":[row…], "total":N, "exact":bool,
    "facets":[{"property":"<hex>","label",
               "values":[{"label","count","active","excluded"}…]}…]}

   The hits the workspace `lens` admits, as rows in rank order, cut to
   `limit` (0 is no limit) — the lens applied BEFORE counting and cutting,
   so `total` is about the same list. `exact` is true when a hit is
   titled like the query's free words, whatever the case; a query of
   only qualifiers is never exact.

   `limit` BOUNDS THE HITS AND NEVER THE FACETS. A facet count is over
   everything the query matches inside the lens, words included: a row
   saying "Work 12" when the list shows 10 is telling the truth, and a
   count that changed with how far the user had scrolled would be useless
   for pivoting. A facet count also excludes its OWN property's
   constraints, or a facet you have already picked shows its own count
   and nothing else; a picked value keeps its chip even at zero.
   `offset_min` as liv_view_tasks (2026-10-01). */
int32_t liv_view_search(const char *path, const char *query, uint32_t limit,
                        int32_t offset_min, const char *lens, char **out);

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
   a shell edit a filter as chips and write the result back as text. */
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

/* The workspace tree:
   [{"id":"<hex>","name","query", …}…]

   A WORKSPACE IS AN ORDINARY ENTITY, so there is no verb here that
   makes one — liv_make with the workspace kind and liv_set of its cells
   already do, which is the whole point of the primitives existing.
   This only reads.

   liv_workspaces adds emoji, favorite, archived, builtin, parent and
   order. An ARCHIVED workspace is included WITH ITS FLAG: the switcher
   shows them behind a disclosure, and filtering them out here would
   take that choice away from the shell. A trashed one is gone, which is
   a different thing. */
int32_t liv_workspaces(const char *path, char **out);

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
   they are trying to get back. Archived is NOT trashed and is not here.
   `offset_min` as liv_view_tasks (2026-10-01). */
int32_t liv_view_trash(const char *path, int32_t offset_min, char **out);

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

#endif
