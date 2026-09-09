#!/bin/zsh
# liv iOS — DRIVE THE APP AND ASSERT WHAT IS ON SCREEN.
#
# Written on 2026-08-24, after a day was lost to a harness that lied.
# A rework left the app updating `desk.state` correctly while the screen
# never repainted. Every check asked the model, and the model was right,
# so eight innocent modifiers were "ruled out" one by one on evidence
# that was worthless. Two things made it worthless:
#
#   1. A stray tap had switched the active workspace to All, so an empty
#      box read as "the surface did not change".
#   2. Taps were given as COORDINATES while the panel's row spacing was
#      being changed underneath them, so the same tap hit a different row
#      in every build.
#
# So this script refuses to report anything until its own preconditions
# hold, taps only by accessibility LABEL, and asserts what is RENDERED
# (Surface.swift's markers) rather than what the model believes.
#
#   ./drive.sh boot [where]      relaunch (optionally via -desk.boot <where>) and check
#   ./drive.sh grid              Notes' root is the LIST, and the box opens the switcher
#   ./drive.sh rows [view]       every row in that list is the SAME height
#   ./drive.sh routes           liv:// links land where they name, and nowhere else
#   ./drive.sh areas            Today counts the day by area of life under its date
#   ./drive.sh chrome [view]     the doors retire on a scroll and come back (all six by default)
#   ./drive.sh create            + makes what the place holds, in one tap
#   ./drive.sh desk              one desk of documents, the same in every view; a switcher pick lands
#   ./drive.sh lens              a saved filter actually narrows the app
#   ./drive.sh facets            search draws the core's counts, and chips cycle
#   ./drive.sh vault             the Vault card offers controls, or says why not
#   ./drive.sh surface           name the surface actually on screen
#   ./drive.sh tap <label>       tap by accessibility label, then re-read the surface
#   ./drive.sh goto <view>       open the panel, pick <view>, assert it rendered
#   ./drive.sh tour              every view in turn — the one that catches a dead repaint
#   ./drive.sh panel             the library panel, and the properties card
#   ./drive.sh bar               five keys, one row, disabled drawn as disabled
#   ./drive.sh workspace         the workspace card opens from the panel's foot, upward
#   ./drive.sh history           a note's ••• opens its version history as a card
#   ./drive.sh spool             a catch the share sheet left is in the Inbox at the next launch
#   ./drive.sh cycles            AttributeGraph cycles since boot
#   ./drive.sh quiet             opening a note adds NO AttributeGraph cycles
#
# Build first (`./build.sh`); `boot` installs what it finds and refuses
# to run against a bundle older than the sources.

set -u

# RUN FROM THIS DIRECTORY, WHEREVER INVOKED FROM. `build.sh` has always
# done this; this script did not, so `shell/ios/drive.sh routes` from
# the repo root looked for `build/Liv.app` under the root, found nothing,
# and said "run ./build.sh first" one line after build.sh had printed
# "built:" (2026-09-09). Every path below is relative to shell/ios.
cd "${0:A:h}"

# PIN THE PATH BEFORE ANYTHING ELSE.
#
# This machine has plan9port early on PATH, and its `ps`, `grep` and
# friends take different flags and quietly print something else instead
# of failing. `ps aux | grep Liv` returned nothing for a running app;
# `grep -o` returned a usage message that read, downstream, as "the
# screen shows none". The harness then failed all six hops of a perfectly
# healthy build.
#
# That is the same class of fault this whole file exists to prevent — an
# instrument reporting confidently about something it never measured — so
# the fix belongs here, once, rather than as a dodge at each call site.
# System tools first; homebrew after it, for `axe`.
path=(/usr/bin /bin /usr/sbin /sbin /opt/homebrew/bin $path)
UDID=${LIV_UDID:-8E699FF6-03A1-433B-A602-C51A30B14E87}
APP=app.liv.ios
# The App Group the box and the share spool live in (Catch.swift).
GROUP=group.liv.app
RUN=${TMPDIR:-/tmp}/liv-drive
mkdir -p "$RUN"
CONSOLE="$RUN/console.txt"
STATE="$RUN/state.txt"

# PLAIN TEXT, no colour. The first version used `print -P` with colour
# escapes and ate every `%` in its own output — it reported "cpu=14.0%f".
# A tool whose job is to be believed must not garble what it prints.
say()  { print -r -- "$1" }
# RETURNS, never exits. A `die` that calls `exit` cannot be caught by the
# tour, so the first failing hop killed the run before it could say which
# hop failed — a harness that reports nothing. The dispatcher at the
# bottom is the only place this script leaves.
# Prints and returns 1. It CANNOT return from its caller, so every call
# site must be `{ die "..."; return 1 }` — the version that just said
# `die "..."` reported the failure and then carried on to return 0, and
# the tour passed on a build that was visibly broken. A harness that
# prints FAIL and exits 0 is worse than no harness.
die()  { print -r -- "FAIL  $1"; return 1 }

# EVERY `axe` CALL IS BOUNDED. A HANG IS AS USELESS AS A LIE.
#
# `axe` talks to the simulator's accessibility server, and that server
# stalls: on 2026-08-31 a `describe-ui` that normally takes 1.7s blocked
# for over ten minutes while the app itself sat at 0% CPU with a healthy
# tree. Nothing in this file had a time limit, so one stalled call took
# the whole run with it and reported NOTHING — no pass, no fail, no
# clue. That is the same fault as a check that lies, wearing different
# clothes: the harness has to come back with an answer.
#
# `perl -e alarm` rather than `timeout`, which is not on a stock macOS
# and would make this file depend on a homebrew coreutils being present.
# Twenty seconds is far above the p100 of a healthy call and far below
# the patience of whoever is waiting.
axe() {
  perl -e 'alarm shift; exec @ARGV' 20 "$(whence -p axe)" "$@"
}

# AND `simctl`, FOR THE SAME REASON. `xcrun simctl io … screenshot` wedged
# on 2026-08-31 with the app at 0% CPU and a healthy tree — the simulator's
# own services, not ours, and only a restart cleared it. `axe` got its bound
# that day and these did not, which left the same hang available through a
# different door.
#
# 90s, not 20: a cold boot and an install of the whole bundle are slow by
# nature, where an accessibility read is not. Still far under the ten
# minutes a wedged call costs.
#
# NOT the backgrounded `launch --console-pty` (in `cmd_boot`): that one is
# MEANT to outlive the call, because it is what captures the console for
# the whole run. Bounding it would kill the log after 90 seconds.
sim() {
  perl -e 'alarm shift; exec @ARGV' 90 "$(whence -p xcrun)" simctl "$@"
}

container() { sim get_app_container "$UDID" "$APP" data 2>/dev/null }

# THE ACCESSIBILITY TREE, or nothing. Every reader below pipes through
# this, so a shut-down simulator or a dead app produces one clear line
# instead of six Python tracebacks — a harness that panics in public is
# hard to believe when it says something calm.
tree() { axe describe-ui --udid "$UDID" 2>/dev/null }

# Run a python snippet over the tree. `walk(n)` is called for every node;
# print whatever you want. $2 is a PREAMBLE (before the walk), $3 a
# POSTAMBLE (after it) — for readers that need the whole tree in hand
# before they can say anything, like "which rows sit between these two".
#
# A snippet that throws prints the traceback on stderr and returns
# nothing. It used to swallow the exception, which meant a typo in a
# reader was indistinguishable from an empty screen — the harness said
# "no saved filter in the panel" about a panel that had one (2026-08-27,
# a NameError from a preamble that was being appended AFTER the walk).
scan() {
  # BUILD THE PROGRAM IN A VARIABLE FIRST. Interpolating the snippet
  # straight into `python3 -c "..."` breaks the moment the snippet contains
  # a double quote — which every snippet does, because every one reads
  # n.get("AXLabel"). The shell closed the string early and python got a
  # fragment, so the reader returned nothing and the check reported "no
  # chips on screen" about a screen that was full of them.
  local prog
  prog="import json, sys, re
${2:-}
$1
d = json.load(sys.stdin)
walk(d if isinstance(d, dict) else d[0])
${3:-}"
  tree | python3 -c "$prog"
}
plist()     { echo "$(container)/Library/Preferences/$APP.plist" }

workspace() {
  local p="$(plist)"
  [[ -f "$p" ]] || { echo "?"; return }
  python3 - "$p" <<'PY'
import plistlib, sys
try: print(plistlib.load(open(sys.argv[1],'rb')).get("workspace.active", "?"))
except Exception: print("?")
PY
}

# NO GREP ANYWHERE IN THIS SCRIPT. `grep` here is whatever wins the PATH
# — on this machine plan9port's, which has no -o and does not match this
# pattern at all — and a harness whose readings depend on that is the
# thing this file exists to stop being.
cpu() {
  local pid; pid=$(pgrep -f "Liv.app/Liv" | head -1)
  [[ -n "$pid" ]] || return 0
  ps -o %cpu= -p "$pid" 2>/dev/null | tr -d ' '
}

# EVERY surface marker currently in the tree, one per line. More than one
# is the stuck-view bug: two surfaces mounted at once.
surfaces() {
  # PYTHON, NOT `grep -o`. `grep` inside this script is whatever wins the
  # PATH, and on this machine that is plan9port's, which has no -o: every
  # read came back a usage message, so the harness reported "the screen
  # shows none" for a perfectly healthy app and failed all six hops. A
  # tool that has to be believed cannot rest on which grep it got.
  axe describe-ui --udid "$UDID" 2>/dev/null | python3 -c '
import json, sys
out = []
def walk(n):
    u = n.get("AXUniqueId") or ""
    if u.startswith("liv.surface."): out.append(u[len("liv.surface."):])
    for c in n.get("children") or []: walk(c)
try:
    d = json.load(sys.stdin)
    walk(d if isinstance(d, dict) else d[0])
except Exception:
    pass
print("\n".join(sorted(out)))' 2>/dev/null
}

# A SPRINGBOARD ALERT, if one is covering the app.
#
# The one-surface rule reads markers the app draws (`liv.surface.` /
# `liv.overlay.`), so a system alert is invisible to it: on 2026-09-07 an
# erased simulator asked "Liv Would Like to Send You Notifications", and
# boot failed with "no surface marker appeared ... Check Surface.swift is
# in the build" — an accusation against an app that was running perfectly.
# A harness that names the wrong thing costs more than one that says
# nothing. A Sheet with no `liv.` marker anywhere under it is not ours.
#
# READ `type`, NOT `AXType`. The first draft of this asked for `AXType`
# and passed a synthetic test built with the same wrong key, then missed
# the real alert on screen — a check calibrated against fiction. `axe`
# spells it `type` (and `role` as `AXSheet`); only `AXUniqueId`, which
# `surfaces()` reads, carries the AX prefix.
system_alert() {
  axe describe-ui --udid "$UDID" 2>/dev/null | python3 -c 'import json, sys
hit = []
def kind(n):
    return str(n.get("type") or n.get("role") or "")
def ours(n):
    if str(n.get("AXUniqueId") or "").startswith("liv."): return True
    return any(ours(c) for c in n.get("children") or [])
def text(n, out):
    lab = n.get("AXLabel") or n.get("AXValue") or ""
    if lab: out.append(str(lab))
    for c in n.get("children") or []: text(c, out)
def walk(n):
    if kind(n) in ("Sheet", "AXSheet", "Alert", "AXAlert") and not ours(n):
        out = []
        text(n, out)
        if out: hit.append(out[0])
    for c in n.get("children") or []: walk(c)
try:
    d = json.load(sys.stdin)
    walk(d if isinstance(d, dict) else d[0])
except Exception:
    pass
print(hit[0] if hit else "")' 2>/dev/null
}

wait_for_surface() {
  local i
  for i in {1..40}; do
    [[ -n "$(surfaces)" ]] && return 0
    perl -e 'select(undef,undef,undef,0.25)'
  done
  return 1
}

cmd_boot() {
  # A NAMED PLACE, ALWAYS. With no argument this used to launch and let
  # the app restore wherever it was left, which meant "boot" landed
  # somewhere different on every run: after a check that ended in an open
  # document it came up IN that document, where the bar is hidden on
  # purpose, and the next check failed with "the bar never drew"
  # (2026-08-29). A ready state that depends on the previous run is not a
  # ready state. `today` is a list view with the whole chrome up.
  local where="${1:-today}"
  # INSTALL WHAT WAS JUST BUILT. `./build.sh` with no argument compiles
  # and stops; without this, every assertion below is made against
  # whatever build happened to be on the simulator. Caught on 2026-08-27
  # when a deliberately broken assertion still reported PASS. Same guard
  # as suites.sh, and for the same reason.
  [[ -d build/Liv.app ]] || { die "no build/Liv.app — run ./build.sh first"; return 1 }
  local stale
  stale=$(find Sources -name '*.swift' -newer build/Liv.app/Liv 2>/dev/null | head -1)
  [[ -z "$stale" ]] || { die "build/Liv.app is older than $stale — run ./build.sh"; return 1 }
  sim boot "$UDID" >/dev/null 2>&1   # already-booted is fine
  sim install "$UDID" build/Liv.app >/dev/null 2>&1 \
    || { die "install failed — the checks would have driven the OLD app"; return 1 }
  sim terminate "$UDID" "$APP" >/dev/null 2>&1
  # Let the terminate land. Running this straight after `suites.sh`
  # otherwise races its own last terminate and boots into nothing.
  perl -e 'select(undef,undef,undef,0.6)'
  : > "$CONSOLE"
  # `boot <flag>` starts the app somewhere specific using the app's OWN
  # rehearsal flags (`-desk.boot`, documented in App.swift). Driving the
  # UI to reach a place is a test of the driving; a check that wants to
  # assert what a place LOOKS like should be put there.
  local args=()
  [[ -n "$where" ]] && args=(-desk.boot "$where")
  ( xcrun simctl launch --console-pty "$UDID" "$APP" $args > "$CONSOLE" 2>&1 & echo $! > "$RUN/pid" )
  if ! wait_for_surface; then
    local alert; alert="$(system_alert)"
    if [[ -n "$alert" ]]; then
      die "the system is covering the app with: $alert
      That is a springboard alert, not the app — dismiss it once
      (\`axe tap --udid $UDID --label Allow\`) and pre-grant the rest with
      \`xcrun simctl privacy $UDID grant all $APP\`. An erased or new
      simulator asks these on first launch."
      return 1
    fi
    die "no surface marker appeared in 10s.
      Either the app did not start, or nothing on screen calls
      \`.livSurface()\` — and a harness that cannot see the surface
      cannot tell you anything. Check Surface.swift is in the build."
    return 1
  fi
  # SETTLE before saying ready. A surface marker appears while the app is
  # still decoding its first snapshot and burning a core; a tour started
  # in that window taps into a UI that is still moving and fails at
  # random. `boot` returning must mean READY, or every caller has to
  # invent its own wait — and one of them will get it wrong.
  local i
  for i in {1..24}; do
    local c="$(cpu)"
    [[ -n "$c" && ${c%%.*} -lt 40 ]] && break
    perl -e 'select(undef,undef,undef,0.25)'
  done
  # AND WAIT FOR THE CHROME. A surface marker means the body is up; the
  # bar and the Library button paint a beat later. Returning between the
  # two handed the next check a screen with "0 keys" and no Library
  # button — a build that was fine, failing at random depending on how
  # busy the machine was (2026-08-27). "Ready" has to mean the whole
  # screen, or every caller invents its own wait and one gets it wrong.
  for i in {1..24}; do
    (( $(bar_count) >= 5 )) && break
    perl -e 'select(undef,undef,undef,0.25)'
  done
  (( $(bar_count) >= 5 )) || { die "the bar never drew after boot.
      The body rendered but the chrome did not — look at Bar.swift and at
      whether the surface is drawing over it."; return 1 }

  # AND WAIT FOR THE PLACE IT WAS ASKED FOR.
  #
  # `-desk.boot <where>` is applied on the FIRST DECODED SNAPSHOT, which
  # is well after the first paint. Until then the app has already
  # restored wherever it was left — and if that was an open note, the
  # document surface is up, with the editor mounted and the keyboard
  # rising, while this function is deciding it is ready. A check that
  # read the note list in that window got the rows, tapped one a beat
  # later, and was told there was no such row (seen 2026-08-30, and it
  # is why `panel` failed once and passed on a re-run).
  #
  # Only the six feature views are checked: the other flags name an
  # overlay (`library`, `search`, `switcher`) or a document (`desk`,
  # `open`), and those do not name a surface this can compare against.
  case "$where" in
    today|tasks|inbox|calendar|everything|notes)
      local want="$where"
      for i in {1..24}; do
        [[ "$(surfaces)" == "$want" ]] && break
        perl -e 'select(undef,undef,undef,0.25)'
      done
      [[ "$(surfaces)" == "$want" ]] || {
        die "asked to boot into '$where' and the screen shows '$(surfaces)'.
      The boot flag is applied on the first decoded snapshot; if the app
      is still showing what it restored, everything measured after this
      is being measured on the wrong surface."; return 1 }
      ;;
  esac

  # NOTHING OVER THE SURFACE. A fresh launch has no panel and no sheet;
  # if one is on screen, this is not the launch it claims to be — and
  # every measurement below is being taken through it.
  local over
  over=$(overlays | tr '\n' ' ')
  [[ -z "${over// /}" ]] || { die "booted with an overlay still up: $over
      The app did not actually restart, or something restores it."; return 1 }

  local ws="$(workspace)"
  echo "$ws" > "$STATE"
  # The baseline. This app boots with two AttributeGraph cycles and has
  # for as long as anyone has looked; reporting the TOTAL just teaches
  # you to ignore the warning. What matters is whether YOUR change added
  # any, so the count at boot is remembered and only growth is news.
  count_cycles > "$RUN/cycles.base"
  cmd_check
}

# The preconditions. Nothing this script says means anything unless these
# hold, so they are checked before every assertion, not once at the top.
cmd_check() {
  local booted
  booted=$(sim list devices 2>/dev/null | python3 -c "
import sys
print(1 if any('$UDID' in l and 'Booted' in l for l in sys.stdin) else 0)" 2>/dev/null)
  [[ "$booted" == "1" ]] || {
    die "simulator $UDID is not booted.
      Boot it: xcrun simctl bootstatus $UDID -b"
    return 1
  }
  local c="$(cpu)"
  [[ -n "$c" ]] || { die "the app is not running."; return 1 }
  # A wedged render loop pins a core, and that is what a "the screen
  # never changed" bug looks like from outside. But a freshly launched
  # app legitimately burns a core decoding its first snapshot, so ONE
  # sample cannot tell the two apart — the first version of this check
  # failed the whole run whenever it was called right after a launch.
  # Spinning means SUSTAINED.
  if [[ ${c%%.*} -gt 80 ]]; then
    perl -e 'select(undef,undef,undef,1.5)'
    local c2="$(cpu)"
    if [[ ${c2%%.*} -gt 80 ]]; then
      die "the app is spinning: ${c}% then ${c2}% CPU, a second and a half
      apart. It is not idle, so nothing below can be trusted.
      Sample it: sample \$(pgrep -f Liv.app/Liv) 3"
      return 1
    fi
    c="$c2"
  fi
  local n base grew
  n=$(count_cycles)
  base=$(cat "$RUN/cycles.base" 2>/dev/null || echo 0)
  grew=$(( n - base ))
  if [[ $grew -gt 0 ]]; then
    say "WARN  $grew NEW AttributeGraph cycle(s) since boot ($n total, $base at launch)."
    say "      A cycle wedges the update loop for that subtree: bodies keep"
    say "      evaluating with the right values while the pixels stop moving."
    say "      Most often a .safeAreaInset whose height reads the safe area."
  fi
  local s; s=(${(f)"$(surfaces)"})
  (( $#s == 1 )) || { die "expected ONE surface on screen, found $#s: ${s[*]:-none}.
      Two at once is the stuck-view bug: the outgoing view never left."; return 1 }
  local ws="$(workspace)"
  if [[ -f "$STATE" && "$ws" != "$(cat $STATE)" ]]; then
    die "the workspace changed under the test: $(cat $STATE) -> $ws.
      A stray tap moved it. Every reading since is against a different
      box — this is the exact failure that cost 2026-08-23."
    return 1
  fi
  say "ok    surface=${s[1]}  workspace=$ws  cpu=${c}%"
}

cmd_surface() { local s=(${(f)"$(surfaces)"}); echo "${s[*]:-none}" }

cmd_tap() {
  local label="$1" i
  # RETRY FOR THREE SECONDS BEFORE CALLING IT ABSENT.
  #
  # "Not on screen yet" and "not on screen" are different answers, and a
  # single attempt cannot tell them apart. The first launch after an
  # install paints the surface a beat before the chrome, so a one-shot tap
  # on a bar button failed the whole tour on a build that was fine
  # (2026-08-27). Retrying costs nothing when the button is there — the
  # first attempt wins — and removes the only source of flake the harness
  # had left. Still label-only: never coordinates.
  for i in {1..12}; do
    if axe tap --udid "$UDID" --label "$label" >/dev/null 2>&1; then
      perl -e 'select(undef,undef,undef,1.2)'
      return 0
    fi
    perl -e 'select(undef,undef,undef,0.25)'
  done
  die "no element labelled '$label' on screen after 3s.
      Run: axe describe-ui --udid $UDID
      Never fall back to coordinates — that is how the same tap starts
      hitting a different row in every build."
  return 1
}

# What a view is ALLOWED to render. Notes is the one that is not itself:
# its root is the tab GRID, and a tab in it holds a document. Spelling that
# out here beats a check that quietly passes on the wrong screen.
# WHICH SURFACES COUNT AS "you are in this view".
#
# Notes has two, and that is not slack: its root is the LIST, and it
# resumes the DOCUMENT you had open. The desk keeps its active tab, so
# arriving at Notes with something open lands you back in it — which is
# what a tab is for. `tabs` was the third, until the grid stopped being
# Notes' root and became the switcher (2026-08-28).
# WHAT LANDING ON A VIEW MAY LOOK LIKE. Every view answers with its own
# marker and nothing else.
#
# `notes` used to also allow `document`, because arriving at Notes from
# another view restored whatever was open — so this check could not tell
# a working navigation from the bug the owner hit on 2026-09-09
# ("sometimes… it gets you to an open note instead of showing the
# list"). One tap, one meaning, one allowed surface.
allowed() { echo "$1" }

# Is the library panel open? One sample; waiting out the animation is
# wait_panel's job.
panel_open() {
  # THE PANEL'S OWN MARKER, not a word that happens to be on it.
  #
  # This used to look for the label "Trash". The settings sheet carries
  # that word too, so any check that left settings open told every later
  # check the library panel was up — and the tour then failed on a build
  # that was fine (2026-08-27). Same lesson as Surface.swift: ask the
  # structure, never the content.
  # No `grep`: this file pins PATH precisely because the wrong one wins,
  # and zsh answers this without leaving the shell. `(r)` is an exact
  # match, so "librarian" would not count.
  local o=(${(f)"$(overlays)"})
  (( ${o[(I)library]} ))
}

# Which overlays are on screen, one per line.
overlays() {
  scan 'def walk(n):
    i = n.get("AXUniqueId") or n.get("identifier") or ""
    if i.startswith("liv.overlay."): print(i[len("liv.overlay."):])
    for c in n.get("children") or []: walk(c)'
}

# The panel is closed only if it STAYS closed. One sample during the
# closing animation still finds the overlay marker, so poll before
# believing it.
panel_closed() {
  local i
  for i in {1..12}; do
    panel_open || return 0
    perl -e 'select(undef,undef,undef,0.25)'
  done
  return 1
}

cmd_goto() {
  local want="$1"
  local title="$(python3 -c "print('$want'.capitalize())")"
  # NORMALISE FIRST. Every hop must start from the same screen or a hop
  # is testing whatever the hop before it left behind — the second way
  # the old harness lied.
  if ! panel_open; then
    cmd_tap "Library" || return 1
  fi
  # WAIT for it, do not sample once. Tapping a row while the panel is
  # still sliding lands on a moving target: the tap SUCCEEDS, hits
  # nothing, and the failure surfaces one line later as "picked X but the
  # panel is still open" — about a build that was fine. This was the last
  # flake left in the tour (2026-08-27); it only ever showed on the first
  # run after an install, which is exactly when the animation is slowest.
  wait_panel open || { die "the library panel did not open."; return 1 }
  cmd_tap "$title" || return 1
  panel_closed || { die "picked '$title' but the panel is still open."; return 1 }
  local got=(${(f)"$(surfaces)"})
  local ok=(${=$(allowed $want)})
  if [[ -z "${got[1]:-}" || ${ok[(Ie)${got[1]}]} -eq 0 ]]; then
    die "picked '$title' but the screen shows '${got[*]:-none}', not ${ok[*]}.
      The model may well have moved — that is not the question. The
      question is what is RENDERED, and it did not change."
    return 1
  fi
  cmd_check
}

# THE ONE THAT CATCHES A DEAD REPAINT. Every view in turn, each asserted
# on screen. A body that stops repainting fails on the first hop.
cmd_tour() {
  cmd_boot >/dev/null 2>&1 || { die "could not boot before the tour."; return 1 }
  local views=(today notes inbox calendar tasks everything)
  local v why failed=0
  for v in $views; do
    print -n "  -> $v  "
    if why=$(cmd_goto "$v" 2>&1); then
      say "rendered"
    else
      say "DID NOT RENDER"
      print -r -- "$why" | sed 's/^/        /'
      failed=1
    fi
  done
  (( failed )) && { die "the tour did not complete. See above."; return 1 }
  say "ok    tour: all six views rendered"
  cmd_check
}

# THE PANEL IS NOT FULL SCREEN (owner, 2026-08-23: "Panel should not be
# full screen!"), and the sliver it leaves is LIVE.
#
# Asserted geometrically rather than by eye: the library toggle lives on
# the desk, so when the panel opens it must travel right by the panel's
# width and still be on screen. If the panel ever goes full-width again,
# or the desk stops travelling with it, this fails.
# THE PANEL, AND THE CARD THAT USED TO BE ONE.
#
# This was one body run twice, mirrored, while the note's properties
# stood on the trailing edge as the library's twin. They are not twins
# any more (owner, 2026-08-29: "maybe card everywhere. start with one"):
# the properties come up as a sheet from the note's ••• menu, the way a
# record's card already worked here and the way Anytype reaches its own.
#
# So the first half checks the one panel that is still a panel, and the
# second checks that the card has a door, comes up, and does NOT shove
# the desk — because a card that pushes is a panel in a sheet's clothes.
#
# Everything asserted is GEOMETRY or a marker on screen, never whether a
# view is mounted. A closed panel stays mounted and simply moves off
# screen, so "is its marker in the tree" answers a different question
# than the one being asked (learned the hard way, 2026-08-28).
cmd_panel() {
  check_library || return 1
  check_properties_card || return 1
  say "ok    panel: the library stands short of the edge and comes back from a tap and a drag; the properties card opens from the ••• and leaves the desk where it was"
  cmd_check
}

# The library: opens from its own button and pushes the desk RIGHT.
check_library() {
  local which=library probe=Library dir=1 rest open_x screen_w mid_x
  screen_w=$(screen_width)
  (( screen_w > 0 )) || { die "could not read the screen width."; return 1 }

  # The library door itself is the probe: it travels with the desk and it
  # is the chrome that stays in the sliver.
  cmd_boot >/dev/null 2>&1 || { die "could not boot before the library check."; return 1 }

  rest=$(button_x "$probe") || {
    die "no '$probe' on screen, so there is nothing to measure the desk by."
    return 1
  }
  open_side "$which" || return 1
  open_x=$(button_x "$probe") || {
    die "the '$probe' door vanished when the $which panel opened.
      The panel is covering the desk, so it is full screen — and there is
      then no sliver to tap and no way back but a drag."
    return 1
  }

  # IT MOVED, AND IT MOVED THE RIGHT WAY.
  local travelled=$(( (open_x - rest) * dir ))
  (( travelled >= 40 )) || {
    die "the $which panel barely moved the desk: '$probe' went ${rest} -> ${open_x}
      (expected to travel $([[ $dir == 1 ]] && echo right || echo left) by more than 40).
      Either it is not pushing the desk aside, or it is pushing it the
      wrong way."
    return 1
  }
  # AND IT LEFT A SLIVER. A panel that takes the whole screen has no way
  # back but a drag, which is the thing the owner rejected outright
  # (2026-08-23: "Panel should not be full screen!").
  (( open_x + 40 <= screen_w )) || {
    die "the desk was pushed off screen: '$probe' is at ${open_x} of ${screen_w}.
      That is a full-screen panel with extra steps."; return 1 }

  # THE SLIVER TAKES THE TOUCHES, and its one job is to bring the desk
  # back. You could work the desk through the gap while a panel was open
  # — scroll a list, tick a task — behind something that says it has your
  # attention (owner, 2026-08-24).
  #
  # A COORDINATE tap, deliberately, and the only ones in this file: the
  # target is a REGION, not a control. The desk is hidden from the
  # accessibility tree behind a panel precisely so nothing in it can be
  # reached, so there is no label to aim at — which is the point. The x
  # is DERIVED from the probe's own centre rather than guessed, and y is
  # well below the chrome row so the tap lands on bare desk.
  mid_x=$(button_cx "$probe") || { die "could not centre on '$probe'."; return 1 }
  axe tap --udid "$UDID" -x "$mid_x" -y 400 >/dev/null 2>&1 || {
    die "could not tap the $which sliver at x=${mid_x}."; return 1 }
  perl -e 'select(undef,undef,undef,1.4)'
  back_at_rest "$probe" "$rest" || {
    die "tapping the $which sliver at x=${mid_x} left the panel open.
      The gap has to put the panel away — otherwise it is either dead
      (no way back) or live (the desk is workable behind a panel)."
    return 1
  }

  # AND THE DRAG STILL STARTS THERE. The panel is dragged open and shut
  # from anywhere (owner, 2026-08-08); the layer that swallows touches in
  # the sliver takes that drag too, so it has to carry it.
  open_side "$which" || return 1
  mid_x=$(button_cx "$probe") || { die "could not centre on '$probe'."; return 1 }
  local end_x=$(( dir == 1 ? 120 : screen_w - 120 ))
  axe swipe --udid "$UDID" --start-x "$mid_x" --start-y 500 \
    --end-x "$end_x" --end-y 500 --duration 0.4 >/dev/null 2>&1
  perl -e 'select(undef,undef,undef,1.6)'
  back_at_rest "$probe" "$rest" || {
    die "a drag from the $which sliver at x=${mid_x} left the panel open.
      The gesture opens and closes from anywhere; the sliver's own layer
      swallows the touch, so that layer has to carry the drag."
    return 1
  }
}

# THE PROPERTIES CARD. It has its own key on the top row as of
# 2026-09-07 — one tap, not a menu — and it is a sheet, so the desk must
# NOT travel when it opens. The trailing edge drag that used to summon a
# panel is gone with the panel.
#
# This tapped "Note actions" then "Properties" until the key existed,
# and its die text said the ••• "is the only way in since the trailing
# panel was retired". That was true for nine days. The ••• is still read
# here, but only as the POSITION PROBE for the desk — the assertion
# below needs a landmark that survives the sheet.
check_properties_card() {
  cmd_boot notes >/dev/null 2>&1 || { die "could not boot into Notes."; return 1 }
  local rest after moved
  open_first_note || return 1

  # The ••• is the probe for the desk's position, not the door.
  rest=$(button_x "Note actions") || {
    die "no ••• on an open note, so there is no landmark to measure the
      desk's travel against."
    return 1
  }
  cmd_tap "Properties" || {
    die "no Properties key on an open note's top row. It is a key of its
      own since 2026-09-07 — it was an item in the ••• menu before that,
      and it must not be in both (standing rule 4)."
    return 1
  }
  perl -e 'select(undef,undef,undef,1.6)'

  [[ -n "$(overlays | grep -x properties)" ]] || {
    die "tapped Properties and no card came up (overlays: $(overlays | tr '\n' ' '))."
    return 1
  }

  # A CARD LIES OVER THE DESK; ONLY A PANEL PUSHES IT. If the chrome
  # travelled, the sheet is still shoving the desk aside and the change
  # is cosmetic. The ••• is behind the sheet at the medium detent, so
  # read it from the tree, not from a screenshot.
  after=$(button_x "Note actions") || after="$rest"
  moved=$(( after > rest ? after - rest : rest - after ))
  (( moved < 40 )) || {
    die "the desk travelled ${moved}pt when the properties opened.
      A card lies over the desk; only a panel pushes it."
    return 1
  }
}

# Open the library by its own door. (The properties had one of these
# too, an edge drag, until they became a card on 2026-08-29 — see
# check_properties_card. They have a KEY of their own again as of
# 2026-09-07, which is a door, not the drag: a card over the desk, not a
# panel pushing it.)
open_side() {
  local i
  for i in {1..3}; do
    cmd_tap "Library" >/dev/null 2>&1
    perl -e 'select(undef,undef,undef,1.4)'
    [[ -n "$(overlays | grep -x "$1")" ]] && return 0
  done
  die "the $1 panel did not open."
  return 1
}

# Has the desk come home? Geometry, not mounting: a closed panel is still
# in the view tree, just parked off screen.
back_at_rest() {
  local probe="$1" rest="$2" now i
  for i in {1..8}; do
    now=$(button_x "$probe") && (( now > rest - 8 && now < rest + 8 )) && return 0
    perl -e 'select(undef,undef,undef,0.3)'
  done
  return 1
}


screen_width() {
  axe describe-ui --udid "$UDID" 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
d = d if isinstance(d, dict) else d[0]
print(int((d.get('frame') or {}).get('width', 0)))"
}

# The CENTRE x of a button's frame — what a region tap aims at when the
# region is defined by the control sitting in it.
button_cx() {
  axe describe-ui --udid "$UDID" 2>/dev/null | python3 -c "
import json, sys
want = sys.argv[1]
d = json.load(sys.stdin)
def w(n):
    f = n.get('frame') or {}
    if (n.get('AXLabel') or '') == want and f.get('width'):
        print(int(f['x'] + f['width'] / 2)); raise SystemExit
    for c in n.get('children') or []: w(c)
w(d if isinstance(d, dict) else d[0])
raise SystemExit(1)" "$1"
}

# The x of a button's frame, by label.
button_x() {
  axe describe-ui --udid "$UDID" 2>/dev/null | python3 -c "
import json,sys
want=sys.argv[1]
d=json.load(sys.stdin)
def w(n):
    if (n.get('AXLabel') or '')==want and (n.get('frame') or {}).get('width'):
        print(int(n['frame']['x'])); raise SystemExit
    for c in n.get('children') or []: w(c)
w(d if isinstance(d,dict) else d[0])
raise SystemExit(1)" "$1"
}

# THE BAR: five keys, one row, and disabled drawn as disabled.
#
# Owner, 2026-08-23: the same button set you would expect in a browser or
# Obsidian, literally. The reference's own rule for a dead key is that it
# stays exactly where it is and only its ink changes — so the geometry
# must never move as navigation state does, and that is what "one row,
# five keys, always" checks.
cmd_bar() {
  cmd_boot >/dev/null 2>&1 || { die "could not boot before the bar check."; return 1 }
  # 1. THE SHAPE. Five keys, in order, on one row — one capsule, not two.
  local shape
  shape=$(bar_keys | python3 -c '
import json, sys
ks = json.load(sys.stdin)
want = ["Back", "Forward", "Search", "New", "open"]
if len(ks) != 5:
    print("COUNT %d" % len(ks)); raise SystemExit
for k, w in zip(ks, want):
    if not k["label"].endswith(w):
        print("ORDER %s != %s" % (k["label"], w)); raise SystemExit
if len({k["y"] for k in ks}) != 1:
    print("ROWS %s" % sorted({k["y"] for k in ks})); raise SystemExit
print("OK %d %d %d" % tuple(int(ks[n]["enabled"]) for n in (0, 1, 4)))')
  case "$shape" in
    COUNT*) die "the bar has ${shape#COUNT } keys, not five: back, forward, search, new, tabs."; return 1 ;;
    ORDER*) die "the bar's keys are out of order: ${shape#ORDER }."; return 1 ;;
    ROWS*)  die "the bar's keys sit on ${shape#ROWS } different rows. It is one capsule, not two."; return 1 ;;
    OK*)    ;;
    *)      die "could not read the bar. Is a keyboard up? It retires under one."; return 1 ;;
  esac

  # 2. DEAD KEYS ARE DRAWN DEAD, not removed. At rest there is nothing
  #    behind you and nothing ahead, so both history keys are dim; the
  #    numbered box is live, because the grid is elsewhere.
  local parts=(${=shape})
  (( parts[2] == 0 )) || { die "Back is live at rest, with nothing behind you."; return 1 }
  (( parts[3] == 0 )) || { die "Forward is live at rest, with nothing ahead of you."; return 1 }
  (( parts[4] == 1 )) || { die "the numbered box is dead away from the grid; nothing else opens the tabs."; return 1 }

  # 3. ONE DOOR PER ROOM. A labelled "< Notes" used to sit top-left inside
  #    a document, beside a bar that already carries back and a way up to
  #    the grid. It is gone (owner, 2026-08-24) and must stay gone.
  #    (The (i) properties door went on 2026-08-14 for the same rule —
  #    which is history, not a prohibition on the Properties KEY added
  #    2026-09-07. That key REPLACED the ••• menu's item; the room still
  #    has one door.)
  labelled_back && {
    die "a labelled back is on screen beside the bar's own back key.
      Two doors to one room — the same standing rule 4 that retired the
      (i) properties door on 2026-08-14."
    return 1
  }

  # WHAT THE GRID DOES TO THIS KEY is `drive.sh grid`'s to say — it
  # boots straight into Notes rather than driving there, because a note
  # left open puts a keyboard up and the bar retires under one.
  say "ok    bar: five keys, one row, dead keys drawn dead, one door per room"
  cmd_check
}

# WAIT for the panel to be open (or shut), rather than sampling once.
# Checking immediately after a tap races a 0.22s animation, and the race
# is not even: it usually wins, so the failure looks intermittent and
# unrelated to whatever you are actually testing.
wait_panel() {
  local want="$1" i
  for i in {1..12}; do
    if [[ "$want" == open ]]; then panel_open && return 0
    else panel_open || return 0; fi
    perl -e 'select(undef,undef,undef,0.3)'
  done
  return 1
}

# The first tab card in the grid, by its accessibility label.
first_card() {
  local l
  l=$(axe describe-ui --udid "$UDID" 2>/dev/null | python3 -c '
import json, sys
cards = []
def walk(n):
    lab = n.get("AXLabel") or ""
    f = n.get("frame") or {}
    # A card is a tall button in the body, not a bar key and not a row —
    # and not the New-note card, which is a door out, not a tab.
    #
    # AND IT HAS TO BE ON SCREEN. The grid scrolls, and it now starts at
    # the BOTTOM (rev 40), so with enough tabs open the earliest cards sit
    # at a NEGATIVE y — off the top of the viewport. This walk sorted by y
    # and picked the topmost, so `axe tap` aimed at an activation point
    # nobody could reach and the check failed on a build that was fine.
    # Found 2026-09-06 with thirteen tabs open; the first card was at
    # y=-296.
    y = f.get("y", 0)
    if (n.get("type") == "Button" and lab and f.get("height", 0) > 100
            and lab != "New note" and y >= 0 and y + f.get("height", 0) <= 912):
        cards.append(((y, f["x"]), lab))
    for c in n.get("children") or []: walk(c)
try:
    d = json.load(sys.stdin)
    walk(d if isinstance(d, dict) else d[0])
except Exception:
    pass
# A label that appears TWICE cannot be tapped by label — axe refuses an
# ambiguous match, and rightly. Only a UNIQUE label is an answer here.
#
# The old fallback returned cards[0] when none was unique, which handed
# the caller a label `axe tap` would refuse and reported it as "no element
# on screen after 3s" — a harness failure that reads exactly like a broken
# app. Two nameless notes made in the same MINUTE share a card label
# ("Note, created · 2026-09-07 15:01, note"), so the collision is ordinary
# rather than rare; the caller falls back to the frame centre, the same
# exception `open_first_note` already takes.
from collections import Counter
seen = Counter(lab for _, lab in cards)
cards.sort()
uniq = [lab for _, lab in cards if seen[lab] == 1]
print(uniq[0] if uniq else "")' 2>/dev/null)
  [[ -n "$l" ]] || return 1
  print -r -- "$l"
}

# Is a labelled back ("Back to Notes") on screen? The bare `<` in the bar
# is labelled just "Back", so this cannot catch it by mistake.
labelled_back() {
  local hit
  hit=$(axe describe-ui --udid "$UDID" 2>/dev/null | python3 -c '
import json, sys
found = [0]
def walk(n):
    if (n.get("AXLabel") or "").startswith("Back to "): found[0] = 1
    for c in n.get("children") or []: walk(c)
try:
    d = json.load(sys.stdin)
    walk(d if isinstance(d, dict) else d[0])
except Exception:
    pass
print(found[0])' 2>/dev/null)
  [[ "$hit" == "1" ]]
}

# How many keys the bar is drawing. `bar_keys` prints ONE line of JSON,
# so counting its LINES gives 1 for a full bar and 1 for an empty one.
bar_count() {
  bar_keys | python3 -c 'import json, sys
try: print(len(json.load(sys.stdin)))
except Exception: print(0)'
}

# The bar's five keys as JSON, in x order.
# THE NUMBERED BOX IS SPOKEN AS "3 documents open" (2026-09-05; it was
# "Desk. 3 documents open" while the grid called itself the Desk). No
# fixed prefix, so it is matched by shape wherever a check reads it.
bar_keys() {
  axe describe-ui --udid "$UDID" 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin); out=[]
def tab_key(l): return l.endswith(' open') and l.split(' ')[0].isdigit()
def w(n):
    l=n.get('AXLabel') or ''
    f=n.get('frame') or {}
    if n.get('type')=='Button' and f.get('y',0) > 700 and (
        l in ('Back','Forward','Search','New') or tab_key(l)):
        out.append({'label': l, 'x': f.get('x',0), 'y': f.get('y',0),
                    'enabled': bool(n.get('enabled'))})
    for c in n.get('children') or []: w(c)
w(d if isinstance(d,dict) else d[0])
print(json.dumps(sorted(out, key=lambda k: k['x'])))"
}

# THE CHROME LEAVES, AND TAKES ITS ROOM WITH IT.
#
# Added 2026-09-07. `livHidesChrome` has slid the doors off screen since
# 2026-08-20 and no check has ever asserted it — the "what's left" audit
# named that gap by name ("the harness has no scroll-retire check on any
# view"). The owner then photographed the other half of it: the buttons
# went, and the 52pt band reserved for them stayed, leaving a hole between
# the clock and the day's title.
#
# So this asserts BOTH halves on one flick: the door goes above the top of
# the screen, and the content rises into the band it vacated.
#
# AN ORDINARY SWIPE IS ENOUGH, and that is the point. Until 2026-09-07 it
# was not: `DeskModel.scrolled` measured its threshold from an anchor that
# was re-clamped to within 44pt of the live offset on every sample, so
# `y > anchor + 44` was false by construction on a smooth scroll and only a
# sample that happened to jump the whole threshold at once could trip it.
# Calendar never tripped at all. The threshold measures from the last
# direction CHANGE now, so this check drives it the way a thumb does.
cmd_chrome() {
  # EVERY SURFACE THAT HIDES ITS CHROME, unless one is named. All six
  # call `livHidesChrome`, and Calendar is the one that silently did not
  # work — a check that only ever ran on Today would have stayed green
  # through the whole of 2026-09-07.
  if (( $# == 0 )); then
    local v
    for v in today calendar inbox tasks everything notes; do
      cmd_chrome "$v" || return 1
    done
    return 0
  fi
  local view="$1"
  cmd_boot "$view" >/dev/null 2>&1 || { die "could not boot into $view."; return 1 }
  # LET THE SURFACE SETTLE. Calendar scrolls itself to the current hour on
  # appear (`openAtTheDay`); a swipe that lands during that animation is
  # absorbed by it and the check reports a chrome that never moved.
  perl -e 'select(undef,undef,undef,2.5)'
  local before after
  before=$(door_y)
  [[ -n "$before" ]] || {
    die "no library door on '$view' at rest, so there is nothing to retire."
    return 1
  }
  (( before > 0 )) || {
    die "the library door starts at ${before}, already off screen."
    return 1
  }

  axe swipe --udid "$UDID" --start-x 210 --start-y 700 --end-x 210 --end-y 300 \
    --duration 0.3 >/dev/null 2>&1
  perl -e 'select(undef,undef,undef,2.0)'

  after=$(door_y)
  if [[ -n "$after" ]] && (( after >= 0 )); then
    die "flicked '$view' and the library door is still at ${after}.
      The chrome retires on scroll (livHidesChrome). If this view never
      retires it, say so in its own comment rather than leaving the
      check green."
    return 1
  fi

  # THE DOOR'S TRAVEL IS THE ASSERTION. It leaves by exactly the band it
  # owns, `LivRow.topInset` — which is also the band `LivTopScrim`
  # reserves and now gives back, so one number pins both halves.
  #
  # WHAT THIS CANNOT ASSERT, and why: "the content rose" is not readable
  # from the tree on a scrolling surface, because the content moved for
  # two reasons at once — the flick and the band. The first version
  # compared the topmost label before and after and reported 138 -> 498,
  # which is the list having scrolled, not the band having stayed. The
  # band's own collapse was measured directly instead (Calendar's pinned
  # title, 137 -> 85 with the band forced closed) and is recorded in
  # design/ios.md rather than asserted here.
  local travelled=$(( before - after ))
  (( travelled >= 100 )) || {
    die "the door only travelled ${travelled}pt (${before} -> ${after}).
      It leaves by its whole band, about 114pt on a notched phone."
    return 1
  }
  # AND THEY COME BACK. Scrolling the other way is how you get the
  # furniture, so a check that only proved they leave would pass on a
  # surface that had lost them for good.
  axe swipe --udid "$UDID" --start-x 210 --start-y 300 --end-x 210 --end-y 720 \
    --duration 0.3 >/dev/null 2>&1
  perl -e 'select(undef,undef,undef,2.0)'
  local home=$(door_y)
  [[ -n "$home" ]] && (( home >= 0 )) || {
    die "scrolled back up on '$view' and the doors did not return (y=${home:-absent})."
    return 1
  }
  say "ok    chrome: on $view the doors retire (${before} -> ${after}, ${travelled}pt) and come back on the way up"
  cmd_check
}

# Where the library door sits, or nothing when it is not in the tree.
door_y() {
  scan 'def walk(n):
    if (n.get("AXLabel") or "") == "Library":
        print(int((n.get("frame") or {}).get("y", 0)))
    for c in n.get("children") or []: walk(c)' | head -1
}

# THE LINE ONLY LIV CAN PRINT. Today counts the day by area of life under
# its date — "Work 3 · Home 1 · 2 unfiled" — since 2026-09-06 (direction A,
# "the furniture shows"). It draws only when the day holds something, so
# the check boots into Today, confirms the late pile is there, and asserts
# that a StaticText carrying "unfiled" or a shipped area name sits between
# the date and the day strip.
cmd_areas() {
  cmd_boot today >/dev/null 2>&1 || { die "could not boot into Today."; return 1 }
  local line
  line=$(axe describe-ui --udid "$UDID" 2>/dev/null | python3 -c "
import json, sys
areas = ('Work', 'Health', 'Money', 'Home', 'Family & Friends', 'Learning')
hits = []
def walk(n):
    l = n.get('AXLabel') or ''
    f = n.get('frame') or {}
    if n.get('type') == 'StaticText' and 60 < f.get('y', 0) < 260 and (
        'unfiled' in l or any(l.startswith(a + ' ') for a in areas)):
        hits.append((round(f.get('y', 0)), f.get('x', 0), l))
    for c in n.get('children') or []: walk(c)
d = json.load(sys.stdin); walk(d if isinstance(d, dict) else d[0])
# SCREEN ORDER, left to right: the app puts the shipped areas first and
# the unfiled count last, and the report should read the way the line does.
hits.sort(); print(' · '.join(l for _, _, l in hits))")
  [[ -n "$line" ]] || {
    die "Today shows no area line under its date. With a late pile on
      screen it must count the day by area, or say how much is unfiled."
    return 1
  }
  say "ok    areas: Today counts the day by area — $line"
  cmd_check
}

# THE `liv://` DOOR — the only way into this app from another one.
#
# Added 2026-09-05 with the scheme itself. `design/what-liv-is-for.md`
# ranks catching things from other apps above any new feature, and the
# links had been "designed, unbuilt" since 2026-08-10.
#
# SIMCTL OPENURL RAISES A SYSTEM ALERT ("Open in Liv?") because the URL
# has no source app. That alert is a separate window, so `surfaces`
# reports nothing at all while it is up — the first run of this check
# read "none" three times and looked like a dead handler when the
# handler was fine. Tap Open, then read.
open_url() {
  local url="$1"
  xcrun simctl openurl "$UDID" "$url" >/dev/null 2>&1 || {
    die "simctl refused to open $url."
    return 1
  }
  perl -e 'select(undef,undef,undef,1.0)'
  # The alert appears for a URL with no source app. It is the system's,
  # not ours, and a person following a link from Mail sees the same one.
  axe tap --udid "$UDID" --label "Open" >/dev/null 2>&1
  perl -e 'select(undef,undef,undef,1.6)'
}

cmd_routes() {
  cmd_boot today >/dev/null 2>&1 || { die "could not boot before the route check."; return 1 }

  # 1. A VIEW BY NAME. `liv://inbox` is the one the spec names; the other
  #    five come free from the same `Feature` enum.
  open_url "liv://inbox" || return 1
  [[ "$(cmd_surface)" == "inbox" ]] || {
    die "liv://inbox landed on '$(cmd_surface)', not the Inbox."
    return 1
  }
  open_url "liv://tasks" || return 1
  [[ "$(cmd_surface)" == "tasks" ]] || {
    die "liv://tasks landed on '$(cmd_surface)', not Tasks."
    return 1
  }

  # 2. AN UNKNOWN HOST CHANGES NOTHING. A link from another app must not
  #    get to guess where you land, so an unparseable one is dropped in
  #    silence rather than falling back to a default surface.
  open_url "liv://nonsense" || return 1
  [[ "$(cmd_surface)" == "tasks" ]] || {
    die "liv://nonsense moved the app to '$(cmd_surface)'. An unknown route
      must do nothing at all."
    return 1
  }

  # 3. CAPTURE MAKES A NOTE AND PUTS THE CARET IN IT — the same door `+`
  #    opens, so what it makes is an Inbox capture.
  #
  #    The count is read BEFORE, from Tasks: once the note is open the
  #    caret is in it, the keyboard is up, and the bar retires under a
  #    keyboard by design — so there is no numbered box to read after,
  #    and the first draft of this check failed on that rather than on
  #    anything being wrong.
  local before keys=5
  before=$(tab_count) || { die "no tab count before the capture route."; return 1 }
  open_url "liv://capture" || return 1
  [[ "$(cmd_surface)" == "document" ]] || {
    die "liv://capture landed on '$(cmd_surface)', not a document."
    return 1
  }
  #    THE RETIRED BAR IS THE ASSERTION. A capture whose caret is not in
  #    it is a note you have to tap before you can type, which is the
  #    thing this route exists to skip.
  #
  #    WAIT FOR IT, do not sample once. The keyboard animates in after
  #    the document paints, so a single read a beat too early sees five
  #    keys and reports a broken route about a working one — the same
  #    flake `cmd_tap` was given a retry loop for (2026-08-27). Caught
  #    here on the first deliberate break of this check.
  local i
  for i in {1..10}; do
    keys=$(bar_keys | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')
    [[ "$keys" == "0" ]] && break
    perl -e 'select(undef,undef,undef,0.4)'
  done
  (( keys == 0 )) || {
    die "liv://capture opened a document with the bar still up (${keys} keys),
      so no keyboard came with it — the caret is not in the note."
    return 1
  }

  # 4. A CATCH WITH SOMETHING IN IT. `liv://capture?text=…` is how
  #    another app HANDS Liv a sentence rather than opening it to a
  #    blank — the half of the thesis's "catching things from other apps"
  #    a URL scheme can do without a share extension (2026-09-09). The
  #    text must be on screen: it is saved first and then shown.
  open_url "liv://capture?text=caught%20from%20outside" || return 1
  [[ "$(cmd_surface)" == "document" ]] || {
    die "liv://capture?text= landed on '$(cmd_surface)', not a document."
    return 1
  }
  tree | grep -q "caught from outside" || {
    die "liv://capture?text=… opened a document without the text in it.
      A catch is saved first and then shown; this one arrived empty."
    return 1
  }

  say "ok    routes: liv://inbox and liv://tasks land, liv://capture opens a note with the caret in it (desk held ${before} first), liv://capture?text= lands with the text in it, an unknown host does nothing"
  cmd_check
}

# EVERY ROW IN A LIST IS THE SAME HEIGHT — the thing twenty green checks
# could not see.
#
# Added 2026-09-05, after the row-height unification shipped with a hole
# in it: Tasks kept a leftover `.padding(.vertical, 4)` OUTSIDE the frame
# that sets the height, so it padded the content first, the 56 floor
# never bound, and a row carrying a chip drew 58 while its neighbours
# drew 56. Nothing here measured a row, so the harness reported ten
# PASSes over an uneven list. This check was watched failing at
# "56pt x11, 58pt x1" before the padding came off.
#
# WHAT IT CAN AND CANNOT DO. It finds rows by geometry — wide, and in the
# row band — because the accessibility tree offers nothing better. An
# `.accessibilityIdentifier` on each row recipe was tried the same day
# and reverted: SwiftUI hangs the identifier on a row's LEAVES (the ring
# at 24, the glyph at 19, the title at 15), never on the row, so it
# named everything except the thing being measured.
#
# Geometry alone cannot tell a row from the chrome above it. Measured on
# Today: a screen title's block is 50.3, the day strip 58, the "Late"
# collapse heading 60 — and the broken Tasks row was 58, between the two.
# So the sweep runs this on NOTES and TASKS, whose columns hold rows and
# nothing else in the band, and the other four are callable by hand and
# will name their own chrome as an outlier. A check that is honest about
# where it bites beats one that cries wolf on four screens.
row_heights() {
  axe describe-ui --udid "$UDID" 2>/dev/null | python3 -c "
import json, sys
from collections import Counter
# BY POSITION, NOT BY NODE. A row is five or six nested groups sharing
# one frame, so counting nodes counts the nesting; a (y, height) pair
# counts the row.
seen = set()
def walk(n):
    f = n.get('frame') or {}
    h, w = f.get('height', 0), f.get('width', 0)
    # LivRow.height is 56 and LivRow.band is 44, so 52 is the gap
    # between a row and the tallest chrome. The ceiling keeps a card
    # (150) and a whole section group out.
    if w > 250 and 52 <= h <= 100:
        seen.add((round(f.get('y', 0), 1), round(h, 1)))
    for c in n.get('children') or []: walk(c)
try:
    d = json.load(sys.stdin)
    walk(d if isinstance(d, dict) else d[0])
except Exception:
    pass
hs = Counter(h for _, h in seen)
print(json.dumps(sorted(hs.items(), key=lambda kv: -kv[1])))"
}

cmd_rows() {
  local view="${1:-tasks}"
  cmd_boot "$view" >/dev/null 2>&1 || { die "could not boot into $view."; return 1 }
  # NORMALISE FIRST, the way `cmd_goto` does. Tasks remembers its filter
  # across launches, so a run that left it on "Move" hands the next one
  # an empty list and the check reports "no rows" about a build that is
  # fine. "All" is the only slice guaranteed to hold something.
  [[ "$view" == "tasks" ]] && { cmd_tap "All" >/dev/null 2>&1 || true }
  local seen verdict
  seen=$(row_heights) || { die "could not read $view's rows."; return 1 }
  verdict=$(print -r -- "$seen" | python3 -c "
import json, sys
rows = json.load(sys.stdin)
# EVERY ROW COUNTS, including one of a kind. An earlier draft ignored a
# height seen once, to skip headers — and that is the exact shape of the
# bug it was written for: ONE task carried a chip and drew 58 while ten
# drew 56.
if not rows:
    print('NONE'); raise SystemExit
if len(rows) > 1:
    print('SPLIT ' + ', '.join('%spt x%d' % (h, n) for h, n in rows)); raise SystemExit
h, n = rows[0]
if float(h) != 56:
    print('WRONG %spt x%d' % (h, n)); raise SystemExit
print('OK %spt x%d' % (h, n))")
  case "$verdict" in
    NONE)   die "no rows on '$view' to measure. Is the list empty?"; return 1 ;;
    WRONG*) die "'$view' draws its rows at ${verdict#WRONG }, not LivRow.height (56).
      Every content list shares one row height."
            return 1 ;;
    SPLIT*) die "'$view' draws its rows at more than one height: ${verdict#SPLIT }.
      One list, one beat (owner, 2026-09-05: 'make row height more consistent').
      If one is a few points TALLER, look for a padding applied OUTSIDE the
      frame that sets LivRow.height: it wraps the content first, so the 56
      floor never binds."
            return 1 ;;
    OK*)    ;;
    *)      die "could not read '$view' rows: $verdict"; return 1 ;;
  esac
  say "ok    rows: $view draws every row at ${verdict#OK }"
  cmd_check
}

# NOTES REACHES NOTES, and the grid is the switcher over it.
#
# This replaces the 2026-08-24 check that asserted the opposite — that
# Notes' root WAS the grid and the numbered box was dead on it. That
# arrangement was measured on 2026-08-28 and it hid the box: the grid
# draws `desk.liveTabs`, so Notes showed 8 of the 134 notes in the box
# and offered no route to the other 126.
#
# The load-bearing assertion here is the second one. A view named after a
# thing has to contain it, and the only way to see that a list is showing
# you MORE than what you left open is to compare it against the count the
# bar is already reporting.
cmd_grid() {
  cmd_boot notes >/dev/null 2>&1 || { die "could not boot into Notes."; return 1 }
  [[ "$(cmd_surface)" == "notes" ]] || {
    die "Notes' root draws '$(cmd_surface)', not the list of notes.
      The grid is the tab SWITCHER; the root is the shelf."
    return 1
  }

  # NOTHING OPEN IS A REAL STATE, and the one this check cannot run from:
  # its last step opens "the first card", and with nothing open the only
  # card is New note — a label the footer's + shares, and `axe` rightly
  # refuses an ambiguous one. Found 2026-09-05; the check had been green
  # only because the box always had tabs open when it ran. So open one
  # note, and come back to the root, which is one tap away (rev 40).
  if [[ "$(tab_count)" == "0" ]]; then
    open_first_note || return 1
    cmd_goto notes >/dev/null 2>&1 || { die "opened a note, but could not get back to Notes' root."; return 1 }
    [[ "$(cmd_surface)" == "notes" ]] || {
      die "picked Notes with a note open and it drew '$(cmd_surface)', not the list.
      Tapping the view you are in goes to its root (rev 40)."
      return 1
    }
  fi

  # THE HOLE THIS CHECK EXISTS FOR. The list must reach past the open
  # tabs — if the two numbers ever match again, the root has gone back to
  # drawing `liveTabs` and 126 notes have quietly become unreachable.
  local open rows
  open=$(tab_count) || { die "the bar reports no tab count to compare against."; return 1 }
  rows=$(note_rows)
  (( rows > open )) || {
    die "Notes lists ${rows} rows while ${open} tabs are open.
      The root is showing you what you left open, not what you have. That
      is the 8-of-134 hole (2026-08-28) coming back."
    return 1
  }

  # AND THE NUMBERED BOX IS ALIVE HERE. It was dead for as long as the
  # grid was the root — you cannot open the grid on top of itself. With a
  # list underneath, the switcher is always a different surface.
  local live
  live=$(bar_keys | python3 -c '
import json, sys
ks = json.load(sys.stdin)
print(int(ks[4]["enabled"]) if len(ks) > 4 else "?")')
  [[ "$live" == "1" ]] || {
    die "the numbered box reads '$live' on Notes' root; it must be live.
      Its one reason to be dead was the grid being the root, and it is not."
    return 1
  }
  cmd_tap "$(bar_tab_label)" || return 1
  # The grid is an OVERLAY now, not a surface: it covers Notes rather
  # than replacing it, so the surface underneath stays `notes` and the
  # thing to look for is the cover's own marker.
  [[ -n "$(overlays | grep -x tabs)" ]] || {
    die "tapped the numbered box and no tab grid came up (overlays: $(overlays | tr '\n' ' ')).
      The box is the only door to the switcher."
    return 1
  }
  labelled_back && { die "a labelled back is on the grid."; return 1 }

  # AND INSIDE A DOCUMENT, where the labelled back used to live. Opening
  # one from the grid is the only way to assert it is really gone — on
  # any other surface there was never one to find.
  local card
  card=$(first_card) || card=""
  if [[ -n "$card" ]]; then
    cmd_tap "$card" || return 1
  else
    # EVERY CARD SHARES ITS LABEL WITH ANOTHER — two nameless notes made
    # in the same minute. Tap the first card's frame centre instead: the
    # same exception `open_first_note` documents, and not a guess, since
    # the frame is what the tree just reported.
    local xy
    xy=$(axe describe-ui --udid "$UDID" 2>/dev/null | python3 -c "
import json, sys
best = None
def walk(n):
    global best
    f = n.get('frame') or {}
    if (n.get('type') == 'Button' and (n.get('AXLabel') or '')
            and f.get('height', 0) > 100 and f.get('y', 0) >= 0
            and f.get('y', 0) + f.get('height', 0) <= 912
            and (n.get('AXLabel') or '') != 'New note'):
        key = (f.get('y', 0), f.get('x', 0))
        if best is None or key < best[0]:
            best = (key, int(f['x'] + f['width'] / 2), int(f['y'] + f['height'] / 2))
    for c in n.get('children') or []: walk(c)
d = json.load(sys.stdin); walk(d if isinstance(d, dict) else d[0])
print(f'{best[1]} {best[2]}' if best else '')")
    [[ -n "$xy" ]] || { die "no tab card on the grid to open."; return 1 }
    axe tap --udid "$UDID" -x ${xy%% *} -y ${xy##* } >/dev/null 2>&1
    perl -e 'select(undef,undef,undef,1.2)'
    card="the first card"
  fi
  [[ "$(cmd_surface)" == "document" ]] || {
    die "tapped the card '$card' and the screen shows '$(cmd_surface)', not a document."
    return 1
  }
  labelled_back && {
    die "the labelled back is still drawn inside a document.
      It is gone (owner, 2026-08-24) and the bar carries both its jobs:
      the back key, and the numbered box for the way up to the grid."
    return 1
  }
  say "ok    grid: Notes lists ${rows} notes against ${open} open, the box opens the switcher, no labelled back in a document"
  cmd_check
}

# How many tabs the bar says are open.
tab_count() {
  bar_tab_label | python3 -c "
import re, sys
m = re.search(r'([0-9]+)', sys.stdin.read())
print(m.group(1) if m else '')" | grep -E '^[0-9]+$'
}

bar_tab_label() {
  scan 'def walk(n):
    l = n.get("AXLabel") or ""
    if l.endswith(" open") and l.split(" ")[0].isdigit(): print(l)
    for c in n.get("children") or []: walk(c)' | head -1
}

# The first row in Notes' list, by label — the door into a document now
# that the root is a list rather than a grid of cards.
# OPEN THE FIRST NOTE IN THE LIST, and do not report a failure that is
# really a race.
#
# Two checks did this as `row=$(first_note)` then `cmd_tap "$row"`, and
# the pair failed intermittently (seen twice: 2026-08-30 and 2026-08-31,
# both times passing on a re-run). The label is read from one snapshot of
# the tree and used against another: in between, the list can still be
# settling after an install, and the unnamed rows in this box all read
# alike — "Note, <date>" since 2026-09-06, "Untitled, <date>" before it
# — so a stale read finds nothing to match.
#
# Re-reading is the fix, not a longer sleep — a sleep long enough to be
# safe on a busy machine is wasted on every healthy run. The success
# condition is what the caller actually wants: a document on screen.
open_first_note() {
  # BY ITS OWN FRAME, not by its label — and that is not the ban being
  # broken, it is the same exception the library sliver already takes.
  #
  # The unnamed notes in this box all read "Note, <date>" (the kind
  # word, from `livRowTitle` since 2026-09-06 — it was "Untitled"
  # before), and the create check adds one per run, so three notes now
  # share today's date. `axe
  # tap --label` REFUSES a label that matches more than one element
  # ("Multiple (3) accessibility elements matched… none expose
  # AXUniqueId"), which is the correct thing for it to do and leaves this
  # with nothing to aim at.
  #
  # The rule at the top of this file bans GUESSED coordinates — "that is
  # how the same tap starts hitting a different row in every build" —
  # and the centre of the frame the tree just reported is not a guess.
  # It is the same information the label lookup would have used, read at
  # the same instant. Every attempt is checked by the only thing that
  # matters: a document on screen.
  local i x y
  for i in {1..3}; do
    read x y <<< "$(first_note_point)"
    if [[ -n "${x:-}" ]]; then
      axe tap --udid "$UDID" -x "$x" -y "$y" >/dev/null 2>&1
      perl -e 'select(undef,undef,undef,1.1)'
      [[ "$(cmd_surface)" == "document" ]] && return 0
    fi
    perl -e 'select(undef,undef,undef,0.6)'
  done
  die "could not open a note from the list after three tries.
      The rows are there but tapping one did not land on a document."
  return 1
}

# The centre of the first note row, as `x y`, straight from the tree.
first_note_point() {
  scan 'def walk(n):
    l = n.get("AXLabel") or ""
    f = n.get("frame") or {}
    if (n.get("type") == "Button" and l and f.get("width", 0) > 200
            and 40 < f.get("height", 0) < 90
            and not l.startswith(SKIP)):
        ROWS.append((f.get("y", 0), f))
    for c in n.get("children") or []: walk(c)' \
    'ROWS = []
SKIP = ("Library", "Note actions", "Back", "Forward", "Search", "New")' \
    'ROWS.sort(key=lambda r: r[0])
if ROWS:
    f = ROWS[0][1]
    print(int(f["x"] + f["width"] / 2), int(f["y"] + f["height"] / 2))'
}

first_note() {
  scan 'def walk(n):
    l = n.get("AXLabel") or ""
    f = n.get("frame") or {}
    if (n.get("type") == "Button" and l and f.get("width", 0) > 200
            and 40 < f.get("height", 0) < 90
            and not l.startswith(SKIP)):
        ROWS.append((f.get("y", 0), l))
    for c in n.get("children") or []: walk(c)' \
    'ROWS = []
SKIP = ("Library", "Note actions", "Back", "Forward", "Search", "New")' \
    'ROWS.sort()
print(ROWS[0][1] if ROWS else "")' | grep .
}

# Rows in Notes' list: full-width buttons of row height, minus the chrome
# that happens to share those bounds.
note_rows() {
  scan 'def walk(n):
    l = n.get("AXLabel") or ""
    f = n.get("frame") or {}
    if (n.get("type") == "Button" and l and f.get("width", 0) > 200
            and 40 < f.get("height", 0) < 90
            and not l.startswith(SKIP)):
        SEEN.append(l)
    for c in n.get("children") or []: walk(c)' \
    'SEEN = []
SKIP = ("Library", "Note actions", "Back", "Forward", "Search", "New")' \
    'print(len(SEEN))'
}

# ONE TAP MAKES THE THING THIS PLACE HOLDS.
#
# `+` used to open a five-item menu everywhere, so making a note — the
# thing you do most — cost two taps by every route (owner, 2026-08-28).
# It now creates what the surface in front of you holds, and the menu
# moved to a long press.
#
# The long press is NOT checked here, and that is a tooling limit rather
# than a choice: `axe` cannot generate one. A known-good shipping
# gesture (Calendar's day cell, `.onLongPressGesture`) does not fire
# through `axe swipe` or `axe touch` either. It IS reachable through the
# simulator MCP's `touch_path` with two points and a dt, which is how it
# was verified by hand on 2026-08-28 — the full menu came up and the tap
# did not fire.
cmd_create() {
  # A DOCUMENT PLACE makes a document, in one tap and with no menu.
  cmd_boot notes >/dev/null 2>&1 || { die "could not boot into Notes."; return 1 }
  cmd_tap "New" || return 1
  perl -e 'select(undef,undef,undef,1.8)'
  no_create_menu || {
    die "+ in Notes opened the create menu. It is meant to make a note and
      leave the menu to a long press."
    return 1
  }
  [[ "$(cmd_surface)" == "document" ]] || {
    die "+ in Notes left the screen on '$(cmd_surface)', not a document.
      A note is a document and opens as one."
    return 1
  }

  # A RECORD PLACE makes a record, which opens as a card over where you
  # stand rather than as a document — so the surface must NOT change.
  cmd_boot tasks >/dev/null 2>&1 || { die "could not boot into Tasks."; return 1 }
  cmd_tap "New" || return 1
  perl -e 'select(undef,undef,undef,1.8)'
  no_create_menu || { die "+ in Tasks opened the create menu."; return 1 }
  [[ "$(cmd_surface)" == "tasks" ]] || {
    die "+ in Tasks left the screen on '$(cmd_surface)'.
      A task is a record: it opens as a card over Tasks, not as a document."
    return 1
  }
  say "ok    create: one tap makes a note in Notes and a task in Tasks, no menu in either"
  cmd_check
}

# True when the five-item create menu is NOT on screen.
no_create_menu() {
  local hit
  hit=$(scan 'def walk(n):
    if (n.get("AXLabel") or "") == "Scan text": print("yes")
    for c in n.get("children") or []: walk(c)' | head -1)
  [[ -z "$hit" ]]
}

# ONE DESK, AND IT FOLLOWS YOU.
#
# Until 2026-08-28 every view had its own plane of tabs, so `[n]` counted
# "tabs open in Calendar" — a number about a place there is one of, and
# the switcher over Today really did show two Todays. The desk is
# app-wide now: the documents you have open are the same set wherever you
# stand.
#
# This asserts the property neither `cargo test` nor the suites can see —
# that the COUNT ON THE BAR does not move when you walk between views.
# It does not open anything: opening a note raises the keyboard, and the
# bar retires under one, so there would be no count to read.
cmd_desk() {
  cmd_boot notes >/dev/null 2>&1 || { die "could not boot into Notes."; return 1 }
  local first n v
  first=$(tab_count) || { die "the bar reports no tab count in Notes."; return 1 }
  (( first > 0 )) || {
    die "the desk is empty, so this check would pass on anything.
      Open a note or two on the simulator first."
    return 1
  }

  for v in today calendar tasks inbox everything; do
    cmd_goto "$v" >/dev/null 2>&1 || { die "could not reach $v."; return 1 }
    n=$(tab_count) || { die "no tab count in $v — the bar should carry one everywhere."; return 1 }
    (( n == first )) || {
      die "the desk changed size on the way to ${v}: ${first} in Notes, ${n} here.
        There is one desk. A count that moves when you walk is a count of
        that view's own plane, which is the thing that went away."
      return 1
    }
  done
  say "ok    desk: ${first} documents, the same set in all six views"

  # AND A PICK FROM THE SWITCHER, STANDING SOMEWHERE ELSE, SHOWS THE NOTE.
  #
  # Until 2026-09-09 the switcher's card called `focus`, which made the
  # tab active and changed no view — so from Today the grid closed and
  # Today kept drawing. Every model check passed: the tab WAS active. Only
  # the screen could say nothing had happened, so the assertion is the
  # rendered surface. The card is found by its frame (the grid's cards
  # are the only 150pt buttons on screen), for the reason `open_first_note`
  # gives: two unnamed notes share one label.
  cmd_goto today >/dev/null 2>&1 || { die "could not reach Today for the switcher pick."; return 1 }
  cmd_tap "$(bar_tab_label)" || return 1
  local x y
  read x y <<< "$(first_card_point)"
  [[ -n "${x:-}" ]] || { die "the switcher opened from Today but shows no card to pick."; return 1 }
  axe tap --udid "$UDID" -x "$x" -y "$y" >/dev/null 2>&1
  perl -e 'select(undef,undef,undef,1.2)'
  [[ "$(cmd_surface)" == "document" ]] || {
    die "picked a card from the switcher while in Today and the screen shows
      '$(cmd_surface)', not the document. The tab is probably active and
      the view never changed — see DeskModel.show."
    return 1
  }
  say "ok    desk: a switcher pick from Today lands on the document"
  cmd_check
}

# The first card in the switcher's grid, by frame — see `first_note_point`
# for why a frame the tree just reported is not a guessed coordinate.
first_card_point() {
  scan 'def walk(n):
    l = n.get("AXLabel") or ""
    f = n.get("frame") or {}
    if (n.get("type") == "Button" and l and 140 < f.get("height", 0) < 160
            and l != "New note"):
        CARDS.append((f.get("y", 0), f.get("x", 0), f))
    for c in n.get("children") or []: walk(c)' \
    'CARDS = []' \
    'CARDS.sort(key=lambda r: (r[0], r[1]))
if CARDS:
    f = CARDS[0][2]
    print(int(f["x"] + f["width"] / 2), int(f["y"] + f["height"] / 2))'
}

cmd_lens() {
  # DOES A SAVED FILTER ACTUALLY NARROW THE APP?
  #
  # The query parser moved from Swift to the core on 2026-08-27. `cargo
  # test` proves the core answers correctly; it cannot see whether the
  # shell asks, or whether it does anything with the answer. Between the
  # two sits `Workspace.admits`, and a lens that quietly admits everything
  # looks exactly like no lens at all.
  #
  # So: read the count the panel prints, turn a saved filter on, read it
  # again. The number has to move.
  cmd_boot everything >/dev/null 2>&1 || { die "could not boot before the lens check."; return 1 }
  cmd_tap "Library" || return 1
  local before after name
  before=$(panel_count Everything)
  [[ -n "$before" ]] || { die "the panel prints no count for Everything, so
      there is nothing to compare. Check the panel still draws counts."; return 1 }

  # The saved filters are the buttons the panel lists between the last view
  # row and "New filter". Positional rather than a name list: the check has
  # to work on any box's furniture, and a filter can be called anything at
  # all — including "Settings".
  name=$(scan 'def walk(n):
    l = n.get("AXLabel") or ""
    if n.get("type") == "Button" and l: SEEN.append(l)
    for c in n.get("children") or []: walk(c)' \
    'SEEN = []' \
    'lo = max((i for i, l in enumerate(SEEN) if re.match(r"^Everything, [0-9]+$", l)), default=-1)
hi = next((i for i, l in enumerate(SEEN) if l == "New filter"), -1)
if lo >= 0 and hi > lo:
    print(chr(10).join(SEEN[lo + 1:hi]))' | head -1)
  [[ -n "$name" ]] || { die "no saved filter listed in the library panel, so
      there is nothing to switch on. Make one in the app first."; return 1 }

  cmd_tap "$name" || return 1
  perl -e 'select(undef,undef,undef,1.5)'
  cmd_tap "Library" || return 1
  after=$(panel_count Everything)
  [[ -n "$after" ]] || { die "the Everything row left the panel once the
      filter '$name' was on."; return 1 }
  (( after != before )) || {
    die "the filter '$name' changed nothing: $before items before, $after after.
      Either the lens is never asked for, or every row is being admitted.
      Look at Workspace.refreshLens and Workspace.admits."
    return 1
  }

  # PUT IT BACK. This check turns a filter on, and the filter is
  # remembered; leaving it on would hand every later check a narrowed app
  # and no clue why.
  cmd_tap "$name" >/dev/null 2>&1 || true
  say "ok    lens: '$name' took Everything from $before to $after"
  cmd_check
}

# THE FACET ROW: the counts the core has always computed, finally drawn.
#
# `services::search::facet` runs a probe query per candidate value on every
# search and returns how many results each value would leave, plus whether
# the query already includes or excludes it. Nothing decoded it until
# 2026-08-26. This check is here because that is exactly the kind of thing
# that goes quiet again without anyone noticing.
cmd_facets() {
  # BOOT FIRST. Run after `grid` this lands in a document with the keyboard
  # up, and the bar retires under a keyboard — so the Search key is not on
  # screen and the check fails about the wrong thing. Every check that needs
  # the bar starts from a known launch.
  cmd_boot >/dev/null 2>&1 || { die "could not boot before the facet check."; return 1 }
  cmd_tap "Search" || return 1
  # WAIT for the field, do not assume the sheet is up. Typing into a sheet
  # that has not arrived types into whatever has focus, and the check then
  # reports "no facet chips" about a screen that was never search.
  wait_field || { die "the search sheet did not open."; return 1 }
  axe type "note" --udid "$UDID" >/dev/null 2>&1 || { die "could not type into search."; return 1 }
  perl -e 'select(undef,undef,undef,2.5)'
  local chips
  chips=$(facet_chips)
  (( $(print -r -- "$chips" | wc -l) >= 2 )) || {
    die "no facet chips on screen for the query 'note'.
      The core sends counts for every select property on every search; if
      none are drawn, the shell is throwing them away again."
    return 1
  }
  # Every chip must carry a count, or it is a filter you cannot judge.
  print -r -- "$chips" | python3 -c '
import sys, re
bad = [l.strip() for l in sys.stdin if l.strip() and not re.search(", [0-9]+", l)]
raise SystemExit(1 if bad else 0)' || {
    die "a facet chip has no count. The count is the point — it is what
      says whether narrowing by that value leaves anything."
    return 1
  }

  # THE PROPERTY NAMES ARE ON SCREEN. Until 2026-09-07 the band was one
  # horizontal scroller holding every property side by side, so only the
  # first was visible and the screen never said what you could narrow by
  # (owner: "it isn't obvious how"). One row per property now, the name at
  # the margin — so at least two names must be fully inside the screen.
  local named
  named=$(axe describe-ui --udid "$UDID" 2>/dev/null | python3 -c "
import json, sys
w = 0
names = []
def walk(n):
    global w
    f = n.get('frame') or {}
    if n.get('type') == 'Application':
        w = max(w, f.get('width', 0))
    l = n.get('AXLabel') or ''
    if (n.get('type') == 'StaticText' and l and l[:1].isupper() and ' ' not in l
            and 100 < f.get('y', 0) < 460 and f.get('x', 0) < 40):
        names.append((l, f.get('x', 0) + f.get('width', 0)))
    for c in n.get('children') or []: walk(c)
d = json.load(sys.stdin); walk(d if isinstance(d, dict) else d[0])
if not w: w = 440
print(len([1 for _, right in names if right <= w]))")
  (( named >= 2 )) || {
    die "only ${named:-0} property name(s) are fully on screen in the facet band.
      Every property gets its own row with its name at the margin; if they
      are off the right edge again, the band is one scroller once more."
    return 1
  }

  # ONE TAP INCLUDES, AND THE FIELD STAYS THE PERSON'S WORDS.
  #
  # This is the assertion the check exists for now, and it is the exact
  # inverse of the one it carried until 2026-09-07: that one required the
  # query text to CONTAIN a colon after a tap, which pinned the leak open
  # (owner: "clunky things like 'type:foo' appearing in search bar").
  local first=$(print -r -- "$chips" | head -1)
  cmd_tap "$first" || return 1
  local q=$(query_text)
  [[ "$q" == "note" ]] || {
    die "tapping '$first' changed the search field to '$q'.
      The field holds what the PERSON typed; a picked constraint is a chip
      under it. Grammar in the field is standing rule 5 breaking."
    return 1
  }
  local lit=$(facet_chips | python3 -c '
import sys
print(next((l.strip() for l in sys.stdin if "included" in l), ""))')
  [[ -n "$lit" ]] || { die "tapped a chip and none reads as included."; return 1 }
  # And the choice is VISIBLE as its own chip, which is the way back.
  local line=$(constraint_chips)
  [[ -n "$line" ]] || {
    die "included a value and no constraint chip appeared under the field.
      What you chose has to be on screen, or there is nothing to undo."
    return 1
  }

  # EXCLUDE IS A NAMED VERB, not a second tap. Tap the constraint chip,
  # take the middle row.
  cmd_tap "$line" || return 1
  local value=$(print -r -- "$line" | sed 's/^[a-z][a-z ]* //; s/,.*//')
  cmd_tap "Hide $value" || {
    die "the facet menu has no 'Hide $value' row. Exclusion is a verb in
      words now, not a hidden third state of a tap."
    return 1
  }
  q=$(query_text)
  [[ "$q" == "note" ]] || {
    die "hiding a value put '$q' in the search field. The '-type:x' spelling
      is the storage format and must never be shown."
    return 1
  }
  local struck=$(facet_chips | python3 -c '
import sys
print(next((l.strip() for l in sys.stdin if "excluded" in l), ""))')
  [[ -n "$struck" ]] || { die "chose Hide and no chip reads as excluded."; return 1 }

  # AND THE WAY OUT. Removing the constraint clears both marks.
  cmd_tap "Remove $value" || return 1
  [[ -z "$(constraint_chips)" ]] || {
    die "removed the constraint and its chip is still under the field."
    return 1
  }
  say "ok    facets: property names on screen, one tap includes, Hide excludes, and the field stays your words"
  cmd_tap "Close search" >/dev/null 2>&1 || true
  cmd_check
}

# THE CHIPS UNDER THE FIELD — what you chose, as opposed to what is on
# offer in the band. Their labels end in ", only. Change" or ", hidden.
# Change", which no facet chip can match (those end in a count).
constraint_chips() {
  scan 'def walk(n):
    l = n.get("AXLabel") or ""
    if n.get("type") == "Button" and l.endswith(". Change"): print(l)
    for c in n.get("children") or []: walk(c)'
}

# WAIT for the search sheet's field, rather than assuming the sheet is up.
# Same reason as wait_panel: typing into a sheet that has not arrived types
# into whatever has focus, and the check then reports about a screen that
# was never search.
wait_field() {
  local i
  for i in {1..12}; do
    # `has_field` alone. A field with text in it is still a field, so the
    # `query_text` half could never be true without this one already
    # being true — it only cost a second UI dump per poll.
    [[ -n "$(has_field)" ]] && return 0
    perl -e 'select(undef,undef,undef,0.35)'
  done
  return 1
}

has_field() {
  scan 'def walk(n):
    if n.get("type") == "TextField": print("yes")
    for c in n.get("children") or []: walk(c)'
}

# The count the panel prints next to a view — "Everything, 246".
#
# A view holding NOTHING prints no number at all ("a count which is always
# there stops being read", owner 2026-08-18), so a bare row reads as 0.
# Prints nothing only when the row is not on screen — which means the
# panel is shut, and that is a different answer from "empty".
# THE PANEL'S COUNT FOR ONE VIEW — from the panel's own ROW, which is a
# Button.
#
# It matched any element with the right label, and on 2026-08-31 the
# screens gained titles: `Text("Everything")` is a StaticText labelled
# exactly "Everything", it appears in the tree before the panel's row,
# and this read it, found no count on it and reported 0. The `lens` check
# then said a filter had changed nothing — about a filter that works.
#
# Third label collision in two days (the others: 48 buttons called
# "Today", three notes sharing a date). The lesson each time is the same:
# a reader that asks only "what is this called" will eventually be
# answered by the wrong thing. Asking for the TYPE as well costs one
# clause and rules out every label that is merely text on a screen.
panel_count() {
  scan 'def walk(n):
    l = n.get("AXLabel") or ""
    m = re.match(r"^" + VIEW + r"(, ([0-9]+))?$", l)
    if m and n.get("type") == "Button": print(m.group(2) or "0")
    for c in n.get("children") or []: walk(c)' "VIEW = \"$1\"" | head -1
}

facet_chips() {
  scan 'def walk(n):
    l = n.get("AXLabel") or ""
    if n.get("type") == "Button" and re.match(r"^[a-z][a-z ]* .+, [0-9]+", l): print(l)
    for c in n.get("children") or []: walk(c)'
}

query_text() {
  scan 'def walk(n):
    if n.get("type") == "TextField": print(n.get("AXValue") or "")
    for c in n.get("children") or []: walk(c)' ''
}

# THE VAULT CARD: the folder promise, and whether it says anything at all.
#
# Five liv_vault_* verbs backed this in Rust and no client called any of
# them, so "your work sits in an ordinary folder" had nothing behind it on
# the phone. This does not test the projection itself (that needs a vault
# fixture and LIV_BOX_PATH); it asserts the card exists and is HONEST in
# whichever mode the box is in — either it offers the controls, or it says
# plainly why there are none. A card that renders empty is the failure.
cmd_vault() {
  cmd_boot >/dev/null 2>&1 || { die "could not boot before the vault check."; return 1 }
  cmd_tap "Library" || return 1
  cmd_tap "Settings" || return 1
  perl -e 'select(undef,undef,undef,1.5)'
  local said
  said=$(settings_text)
  print -r -- "$said" | python3 -c '
import sys
t = sys.stdin.read()
vault = all(k in t for k in ("Folder", "Files", "Sync now", "Rebuild"))
legacy = "not inside a vault folder" in t
raise SystemExit(0 if (vault or legacy) else 1)' || {
    die "the Vault card says neither the controls nor the reason there are none.
      Either it offers Folder/Files/Sync/Rebuild, or it explains that this box
      is not inside a vault folder. Rendering nothing is the failure."
    return 1
  }
  local verdict
  if print -r -- "$said" | python3 -c 'import sys; raise SystemExit(0 if "not inside a vault folder" in sys.stdin.read() else 1)'; then
    verdict="legacy box, and the card says so rather than showing dead controls"
  else
    verdict="folder, file count, Sync and Rebuild all on screen"
  fi
  # PUT THE SCREEN BACK. A check that opens a sheet and walks away hands
  # the next one a screen it did not ask for; that is how a passing build
  # produced three failures in a row here. Terminating is the only close
  # that always works — there is no Done button on this sheet, and a swipe
  # on a detent sheet is not reliably reproducible.
  sim terminate "$UDID" "$APP" >/dev/null 2>&1
  say "ok    vault: $verdict"
}

settings_text() {
  scan 'def walk(n):
    for k in ("AXLabel", "AXValue"):
        v = n.get(k)
        if isinstance(v, str) and v: print(v)
    for c in n.get("children") or []: walk(c)' ''
}

cmd_cycles() {
  python3 -c '
import sys
try: ls = sorted({l.strip() for l in open(sys.argv[1], errors="ignore") if "cycle detected" in l})
except Exception: ls = []
print("\n".join(ls) if ls else "(none since boot)")' "$CONSOLE"
}

count_cycles() {
  python3 -c '
import sys
try: print(sum("cycle detected" in l for l in open(sys.argv[1], errors="ignore")))
except Exception: print(0)' "$CONSOLE"
}

# OPENING A NOTE ADDS NO ATTRIBUTEGRAPH CYCLES.
#
# It added 57 until 2026-08-30, every one of them through a single line:
# `updateUIView` took first responder synchronously, so UIKit called
# SwiftUI back into a transaction that was still running and the graph
# was asked for a value it was already computing (EditorText.swift, and
# the comment there has the whole chain). A cycle wedges that subtree's
# update loop — bodies keep evaluating with the right values while the
# pixels stop moving — which is the failure this harness was written for
# in the first place, and the third time this app has hit it.
#
# So it gets a CHECK, not a warning. `cmd_check` warns about growth
# since boot, and a warning is a thing you learn to scroll past. This
# fails.
#
# The number is measured across ONE action, deliberately: the app boots
# with two cycles of its own and has for as long as anyone has looked,
# and asserting the total would make this check about that instead.
cmd_quiet() {
  cmd_boot notes >/dev/null 2>&1 || { die "could not boot into Notes."; return 1 }
  local before after row
  before=$(count_cycles)
  open_first_note || return 1
  perl -e 'select(undef,undef,undef,1.6)'
  after=$(count_cycles)
  local new=$(( after - before ))
  (( new == 0 )) || {
    die "opening a note fired $new AttributeGraph cycle(s).
      Something took first responder, or otherwise re-entered SwiftUI,
      from inside an update pass. Run it again under a debugger:
        SIMCTL_CHILD_AG_PRINT_CYCLES=3 ./drive.sh boot notes
      then read the digraph the graph prints for each one — and see
      MarkdownEditor.updateUIView, which is where the last 57 came from."
    return 1
  }
  say "ok    quiet: opening a note adds no AttributeGraph cycles (${before} at boot, ${after} after)"
  cmd_check
}

# THE WORKSPACE CARD, AND WHAT IT HANGS OVER.
#
# Added 2026-09-08, after the card spent a week with the bottom bar
# painted across it (owner: "when opening workspaces from the panel, the
# bar is above that card"). Nothing here could see it: the card had no
# `LivOverlay` marker, so no check could assert it was even up, and the
# door that opens it had no accessibility label — its label was DERIVED
# from the active workspace's name, so it changed with the box.
#
# WHAT THIS CANNOT ASSERT, and it is the very thing that was broken:
# WHICH OF THE TWO IS ON TOP. Z-order is paint, and the accessibility
# tree has none of it. Worse, the bar is `accessibilityHidden` while a
# panel is out — in the broken build AND the fixed one, for different
# reasons — so "is the bar in the tree" answers a different question and
# would have read green throughout. Catching the paint needs a pixel
# sampled off a screenshot, and `simctl io … screenshot` is the one call
# that wedged this harness (see `sim` above); it is not worth that door
# for one assertion. So this guards the FLOW and the GEOMETRY, and the
# layering stays an eyes-on check.
cmd_workspace() {
  cmd_boot >/dev/null 2>&1 || { die "could not boot before the workspace check."; return 1 }
  open_side library || return 1

  cmd_tap "Switch workspace" || {
    die "no 'Switch workspace' door at the foot of the library panel.
      It is the only way to the workspace card."
    return 1
  }
  perl -e 'select(undef,undef,undef,1.4)'

  [[ -n "$(overlays | grep -x workspace)" ]] || {
    die "tapped the workspace door and no card came up (overlays: $(overlays | tr '\n' ' '))."
    return 1
  }

  # IT RISES FROM THE EDGE ITS BUTTON IS ON. The door is at the FOOT of
  # the panel, so the card comes from the bottom — it fell from the top
  # for nine days after the button moved and the direction stayed behind
  # (owner, 2026-08-31: "some menus are popping up top down when the
  # button is not at the top"). Its title is the highest thing in it, so
  # the title's own y is where the card begins.
  local top
  top=$(scan 'def walk(n):
    if (n.get("AXLabel") or "") == "Workspace":
        f = n.get("frame") or {}
        print(int(f.get("y", 0)))
    for c in n.get("children") or []: walk(c)' | head -1)
  [[ -n "$top" ]] || {
    die "the card is up but draws no 'Workspace' title, so nothing on it
      says what it is."
    return 1
  }
  (( top > 400 )) || {
    die "the workspace card begins at y=${top} — it is falling from the
      TOP. It hangs from the panel's foot and must rise from the bottom."
    return 1
  }

  # AND IT OFFERS THE ONE VERB THAT IS ONLY HERE.
  #
  # `grep -q`, not `grep -c`: a count always prints a number, so a `-n`
  # test on it is true even at zero — an assertion that cannot fail.
  # Written that way first, and caught by reading it rather than by
  # running it.
  tree | grep -q "New workspace" || {
    die "the card is up but offers no 'New workspace' row."
    return 1
  }

  say "ok    workspace: the card rises from the panel's foot (title at y=${top}),"
  say "      and carries its own New workspace row. WHICH IS ON TOP — it or the"
  say "      bar — is paint, and no check here can see it: look with your eyes."
}

# THE HISTORY CARD. Every version of a note, from its ••• menu, as a card.
#
# Added 2026-09-09 with the card itself. The verb it reads has been in
# the ABI since the history was built and nothing in the shell called it,
# so the thesis's "read what you wrote three weeks ago, put it back" was
# core-only; this asserts the door exists, opens, is marked, and names
# itself. RESTORE is not driven here: it is a write to the box, and the
# ffi tests already prove a restore appends a version and never rewrites
# the log. What a driver can add is that the card is reachable at all.
cmd_history() {
  cmd_boot notes >/dev/null 2>&1 || { die "could not boot into Notes."; return 1 }
  open_first_note || return 1

  cmd_tap "Note actions" || return 1
  perl -e 'select(undef,undef,undef,1.0)'
  cmd_tap "History" || {
    die "the note's ••• menu offers no History. A note's versions are the
      thesis's own promise; the door to them is this menu."
    return 1
  }
  perl -e 'select(undef,undef,undef,1.6)'

  [[ -n "$(overlays | grep -x history)" ]] || {
    die "tapped History and no card came up (overlays: $(overlays | tr '\n' ' '))."
    return 1
  }

  # IT LISTS AT LEAST THE CURRENT VERSION. A note you could open has
  # content, so its history is never empty; an empty card here means the
  # read failed and the card is hiding it.
  tree | grep -q '"current"' || {
    die "the History card is up but shows no current version. The read
      of liv_content_history_at came back empty for a note that has words."
    return 1
  }

  say "ok    history: the note's ••• menu opens its version history as a card, marked, with the current version listed"
}

# A CATCH THE SHARE SHEET LEFT IS IN THE INBOX AT THE NEXT LAUNCH
# (2026-09-09). The extension itself runs inside ANOTHER app's share
# sheet, which this harness cannot reach by label with any confidence.
# What it can do is leave a file exactly where the extension leaves one
# (Catch.swift: <group>/liv/spool/*.txt) and watch the app pick it up —
# the half of the seam that lives in this tree, and the half that would
# fail silently: an extension that saved to a folder nobody reads would
# say "Saved to Liv" and be lying.
cmd_spool() {
  # Install first, so the group container exists to write into.
  cmd_boot inbox >/dev/null 2>&1 || { die "could not boot into the Inbox."; return 1 }
  local group
  group=$(sim get_app_container "$UDID" "$APP" "$GROUP" 2>/dev/null)
  [[ -n "$group" && -d "$group" ]] || {
    die "no App Group container for $GROUP.
      The box and the spool both live there (Catch.swift, LivGroup.id);
      if simctl cannot name it the entitlement did not reach the bundle."
    return 1
  }
  mkdir -p "$group/liv/spool"
  local words="spooled from the share sheet $(date +%H%M%S)"
  local file="$group/liv/spool/drive-$$.txt"
  print -r -- "$words" > "$file"

  # The drain runs at launch, so relaunch — the file was written after
  # the first one.
  cmd_boot inbox >/dev/null 2>&1 || { die "could not relaunch into the Inbox."; return 1 }
  local i
  for i in {1..10}; do
    tree | grep -q "$words" && break
    perl -e 'select(undef,undef,undef,0.5)'
  done
  tree | grep -q "$words" || {
    die "a file in the spool did not become a capture: '$words' is not in the Inbox.
      RootView.drainSpool reads <group>/liv/spool at launch and on every
      foreground; check that it ran, and that Spool.dir resolves the same
      container simctl just named ($group)."
    return 1
  }
  [[ ! -e "$file" ]] || {
    die "the catch is in the Inbox but its spool file is still there — it
      will be caught AGAIN at the next foreground. Item.done() removes the
      file once the box answers with an id."
    return 1
  }
  say "ok    spool: a file left in the App Group spool is an Inbox capture at the next launch, and the file is gone"
  cmd_check
}

# The ONE place this script exits, so every command can fail by
# returning and still be caught by the command above it.
case "${1:-}" in
  boot)    cmd_boot "${2:-}" || exit 1 ;;
  check)   cmd_check   || exit 1 ;;
  surface) cmd_surface || exit 1 ;;
  tap)     cmd_tap "${2:?usage: drive.sh tap <label>}" && cmd_check || exit 1 ;;
  goto)    cmd_goto "${2:?usage: drive.sh goto <view>}" || exit 1 ;;
  tour)    cmd_tour    || exit 1 ;;
  panel)   cmd_panel   || exit 1 ;;
  bar)     cmd_bar     || exit 1 ;;
  workspace) cmd_workspace || exit 1 ;;
  history) cmd_history   || exit 1 ;;
  spool)   cmd_spool   || exit 1 ;;
  grid)    cmd_grid    || exit 1 ;;
  rows)    cmd_rows "${2:-tasks}" || exit 1 ;;
  routes)  cmd_routes  || exit 1 ;;
  areas)   cmd_areas   || exit 1 ;;
  chrome)  cmd_chrome ${2:+"$2"} || exit 1 ;;
  create)  cmd_create  || exit 1 ;;
  desk)    cmd_desk    || exit 1 ;;
  lens)    cmd_lens    || exit 1 ;;
  facets)  cmd_facets  || exit 1 ;;
  vault)   cmd_vault   || exit 1 ;;
  cycles)  cmd_cycles  || exit 1 ;;
  quiet)   cmd_quiet   || exit 1 ;;
  *) sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
