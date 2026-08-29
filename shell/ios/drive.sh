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
#   ./drive.sh grid              Notes' root is the tab grid, and unopenable on itself
#   ./drive.sh create            + makes what the place holds, in one tap
#   ./drive.sh desk              one desk of documents, the same in every view
#   ./drive.sh lens              a saved filter actually narrows the app
#   ./drive.sh facets            search draws the core's counts, and chips cycle
#   ./drive.sh vault             the Vault card offers controls, or says why not
#   ./drive.sh surface           name the surface actually on screen
#   ./drive.sh tap <label>       tap by accessibility label, then re-read the surface
#   ./drive.sh goto <view>       open the panel, pick <view>, assert it rendered
#   ./drive.sh tour              every view in turn — the one that catches a dead repaint
#   ./drive.sh panel             BOTH panels: not full screen, sliver live
#   ./drive.sh bar               five keys, one row, disabled drawn as disabled
#   ./drive.sh cycles            AttributeGraph cycles since boot
#
# Build first (`./build.sh`); `boot` installs what it finds and refuses
# to run against a bundle older than the sources.

set -u

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

container() { xcrun simctl get_app_container "$UDID" "$APP" data 2>/dev/null }

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

wait_for_surface() {
  local i
  for i in {1..40}; do
    [[ -n "$(surfaces)" ]] && return 0
    perl -e 'select(undef,undef,undef,0.25)'
  done
  return 1
}

cmd_boot() {
  local where="${1:-}"
  # INSTALL WHAT WAS JUST BUILT. `./build.sh` with no argument compiles
  # and stops; without this, every assertion below is made against
  # whatever build happened to be on the simulator. Caught on 2026-08-27
  # when a deliberately broken assertion still reported PASS. Same guard
  # as suites.sh, and for the same reason.
  [[ -d build/Liv.app ]] || { die "no build/Liv.app — run ./build.sh first"; return 1 }
  local stale
  stale=$(find Sources -name '*.swift' -newer build/Liv.app/Liv 2>/dev/null | head -1)
  [[ -z "$stale" ]] || { die "build/Liv.app is older than $stale — run ./build.sh"; return 1 }
  xcrun simctl boot "$UDID" >/dev/null 2>&1   # already-booted is fine
  xcrun simctl install "$UDID" build/Liv.app >/dev/null 2>&1 \
    || { die "install failed — the checks would have driven the OLD app"; return 1 }
  xcrun simctl terminate "$UDID" "$APP" >/dev/null 2>&1
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
  wait_for_surface || { die "no surface marker appeared in 10s.
      Either the app did not start, or nothing on screen calls
      \`.livSurface()\` — and a harness that cannot see the surface
      cannot tell you anything. Check Surface.swift is in the build."; return 1 }
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
  booted=$(xcrun simctl list devices 2>/dev/null | python3 -c "
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
allowed() {
  case "$1" in
    notes) echo "notes document" ;;
    *)     echo "$1" ;;
  esac
}

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
# BOTH PANELS, ONE CHECK.
#
# The library and the note's properties panel became the SAME panel on
# 2026-08-28 — one `SidePanel`, one travel distance, one wash, differing
# in nothing but which edge they stand on. A check that covered only the
# library would leave half of that untested, and the half that is newer.
#
# So this runs one body twice, mirrored. Everything it asserts is
# GEOMETRY — where the desk's own chrome ended up — never whether a view
# is mounted. A closed panel stays mounted and simply moves off screen,
# so "is its marker in the tree" answers a different question than the
# one being asked (learned the hard way, 2026-08-28).
cmd_panel() {
  cmd_boot >/dev/null 2>&1 || { die "could not boot before the panel check."; return 1 }
  check_side library || return 1
  check_side properties || return 1
  say "ok    panels: both stand short of the far edge, push the desk the right way, and come back from a tap and a drag in the sliver"
  cmd_check
}

# One panel, by name. `library` opens from its own button and pushes the
# desk RIGHT; `properties` opens with a drag in from the trailing edge
# and pulls it LEFT.
check_side() {
  local which="$1" probe dir rest open_x screen_w mid_x
  screen_w=$(screen_width)
  (( screen_w > 0 )) || { die "could not read the screen width."; return 1 }

  if [[ "$which" == library ]]; then
    # The library door itself is the probe: it travels with the desk and
    # it is the chrome that stays in the sliver on that side.
    probe=Library; dir=1
    cmd_boot >/dev/null 2>&1 || { die "could not boot before the library check."; return 1 }
  else
    # The properties panel only exists over an open document, and the
    # ••• is the chrome that stays in ITS sliver.
    probe="Note actions"; dir=-1
    cmd_boot notes >/dev/null 2>&1 || { die "could not boot into Notes."; return 1 }
    local row
    row=$(first_note) || { die "no note in the list to open."; return 1 }
    cmd_tap "$row" || return 1
    perl -e 'select(undef,undef,undef,1.2)'
  fi

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
  # back but a drag, which is the thing the owner rejected outright.
  if [[ "$which" == library ]]; then
    (( open_x + 40 <= screen_w )) || {
      die "the desk was pushed off screen: '$probe' is at ${open_x} of ${screen_w}.
        That is a full-screen panel with extra steps."; return 1 }
  else
    (( open_x >= 0 )) || {
      die "the desk was pulled off screen: '$probe' is at ${open_x}.
        That is a full-screen panel with extra steps."; return 1 }
    # AND THE PANEL ITSELF STOPS SHORT. Measured from the panel's own
    # marker, which sits at its content's leading edge: on this side that
    # edge is IN the screen, so there is a number to read. (On the
    # library's side the panel's leading edge is the screen's own, at 0,
    # and the sliver is measured by the desk instead — above.)
    local edge
    edge=$(overlay_x properties) || {
      die "the properties panel drew no marker to measure."; return 1 }
    (( edge >= 40 )) || {
      die "the properties panel starts at x=${edge}: it is full screen.
        It has to stop short and leave a sliver of the desk, the same way
        the library does (owner, 2026-08-23: 'Panel should not be full
        screen!')."
      return 1
    }
  fi

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

# Open one panel by its own door: a button for the library, an edge drag
# for the properties panel, which has no button by design.
open_side() {
  local i
  for i in {1..3}; do
    if [[ "$1" == library ]]; then
      cmd_tap "Library" >/dev/null 2>&1
    else
      axe swipe --udid "$UDID" --start-x $(( $(screen_width) - 5 )) --start-y 420 \
        --end-x 120 --end-y 420 --duration 0.35 >/dev/null 2>&1
    fi
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

# The leading x of a panel's own marker — where the panel actually
# starts, as opposed to where its full-width layout frame does.
overlay_x() {
  axe describe-ui --udid "$UDID" 2>/dev/null | python3 -c "
import json, sys
want = 'liv.overlay.' + sys.argv[1]
d = json.load(sys.stdin)
def w(n):
    i = n.get('AXUniqueId') or n.get('identifier') or ''
    f = n.get('frame') or {}
    if i == want and f:
        print(int(f.get('x', 0))); raise SystemExit
    for c in n.get('children') or []: w(c)
w(d if isinstance(d, dict) else d[0])
raise SystemExit(1)" "$1"
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
want = ["Back", "Forward", "Search", "New", "Tabs"]
if len(ks) != 5:
    print("COUNT %d" % len(ks)); raise SystemExit
for k, w in zip(ks, want):
    if not k["label"].startswith(w):
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
  labelled_back && {
    die "a labelled back is on screen beside the bar's own back key.
      Two doors to one room — the reason the (i) properties door went on
      2026-08-14, and standing rule 4."
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
    # A card is a tall button in the body, not a bar key and not a row.
    if n.get("type") == "Button" and lab and f.get("height", 0) > 100:
        cards.append(((f["y"], f["x"]), lab))
    for c in n.get("children") or []: walk(c)
try:
    d = json.load(sys.stdin)
    walk(d if isinstance(d, dict) else d[0])
except Exception:
    pass
# A label that appears TWICE cannot be tapped by label — axe refuses an
# ambiguous match, and rightly. Prefer one that is unique on screen.
from collections import Counter
seen = Counter(lab for _, lab in cards)
cards.sort()
uniq = [lab for _, lab in cards if seen[lab] == 1]
print(uniq[0] if uniq else (cards[0][1] if cards else ""))' 2>/dev/null)
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
bar_keys() {
  axe describe-ui --udid "$UDID" 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin); out=[]
def w(n):
    l=n.get('AXLabel') or ''
    f=n.get('frame') or {}
    if n.get('type')=='Button' and f.get('y',0) > 700 and (
        l in ('Back','Forward','Search','New') or l.startswith('Tabs')):
        out.append({'label': l, 'x': f.get('x',0), 'y': f.get('y',0),
                    'enabled': bool(n.get('enabled'))})
    for c in n.get('children') or []: w(c)
w(d if isinstance(d,dict) else d[0])
print(json.dumps(sorted(out, key=lambda k: k['x'])))"
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
  card=$(first_card) || { die "no tab card on the grid to open."; return 1 }
  cmd_tap "$card" || return 1
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
    if l.startswith("Tabs."): print(l)
    for c in n.get("children") or []: walk(c)' | head -1
}

# The first row in Notes' list, by label — the door into a document now
# that the root is a list rather than a grid of cards.
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
SKIP = ("Tabs.", "Library", "Note actions", "Back", "Forward", "Search", "New")' \
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
SKIP = ("Tabs.", "Library", "Note actions", "Back", "Forward", "Search", "New")' \
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
  cmd_check
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
  # include -> exclude -> off, and the query text follows.
  local first=$(print -r -- "$chips" | head -1)
  cmd_tap "$first" || return 1
  local q=$(query_text)
  [[ "$q" == *":"* ]] || { die "tapping '$first' did not add a term; query is '$q'."; return 1 }
  local lit=$(facet_chips | python3 -c '
import sys
print(next((l.strip() for l in sys.stdin if "included" in l), ""))')
  [[ -n "$lit" ]] || { die "tapped a chip and none reads as included."; return 1 }
  cmd_tap "$lit" || return 1
  q=$(query_text)
  [[ "$q" == *"-"* ]] || { die "second tap did not exclude; query is '$q'."; return 1 }
  local struck=$(facet_chips | python3 -c '
import sys
print(next((l.strip() for l in sys.stdin if "excluded" in l), ""))')
  [[ -n "$struck" ]] || { die "excluded chip does not say so."; return 1 }
  cmd_tap "$struck" || return 1
  q=$(query_text)
  [[ "$q" != *":"* ]] || { die "third tap did not clear the term; query is '$q'."; return 1 }
  say "ok    facets: chips with counts, and include-exclude-off follows the query text"
  cmd_tap "Close search" >/dev/null 2>&1 || true
  cmd_check
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
panel_count() {
  scan 'def walk(n):
    l = n.get("AXLabel") or ""
    m = re.match(r"^" + VIEW + r"(, ([0-9]+))?$", l)
    if m: print(m.group(2) or "0")
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
  xcrun simctl terminate "$UDID" "$APP" >/dev/null 2>&1
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
  grid)    cmd_grid    || exit 1 ;;
  create)  cmd_create  || exit 1 ;;
  desk)    cmd_desk    || exit 1 ;;
  lens)    cmd_lens    || exit 1 ;;
  facets)  cmd_facets  || exit 1 ;;
  vault)   cmd_vault   || exit 1 ;;
  cycles)  cmd_cycles  || exit 1 ;;
  *) sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
