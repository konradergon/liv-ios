#!/bin/zsh
# liv iOS — RUN THE LAUNCH-FLAG SELF-CHECKS.
#
#   ./suites.sh                 all ten
#   ./suites.sh planes tabs     just these
#
# These are the app's own unit tests: each is a function that returns a
# list of failures, reached by a launch flag. `cargo test` does not run
# them — they live in the shell.
#
# WHY THIS IS A SCRIPT AND NOT ONE LINE. The app does not exit after a
# suite, so `xcrun simctl launch --console-pty …` never returns and any
# `grep` downstream never sees EOF. Bounding it with SIGALRM does not
# work either: `xcrun` forks `simctl`, so the alarm kills `xcrun` while
# `simctl` holds the pipe open. What works is below — background the
# launch into a file, poll the file for the verdict, then kill the pty
# owner, which takes the app with it.
#
# Do NOT run two of these at once: each one's kill would take the
# other's launches with it.

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
ALL=(spans workspace calendar share places tabs planes glyph palette editor)

suites=("$@")
(( $# )) || suites=($ALL)

# A misspelled name would otherwise launch a flag nothing reads, and the
# app would sit there printing no verdict — which reads as a failing
# suite rather than as a typo.
for f in $suites; do
  (( $ALL[(I)$f] )) || { print -r -- "no such suite: $f (have: $ALL)"; exit 1 }
done

# INSTALL WHAT WAS JUST BUILT, EVERY TIME.
#
# `./build.sh` with no argument only compiles — it does not install. So
# this script used to launch WHATEVER WAS ON THE SIMULATOR, which could be
# any older build. It reported ten PASSes for a suite whose assertions had
# been deliberately broken (2026-08-27), because the broken code was never
# on the device.
#
# A green suite that never ran the code under test is the one failure this
# harness cannot be allowed to have. So: install first, and refuse to run
# at all if there is nothing to install.
if [[ ! -d build/Liv.app ]]; then
  print -r -- "no build/Liv.app — run ./build.sh first"
  exit 1
fi
stale=$(find Sources -name '*.swift' -newer build/Liv.app/Liv 2>/dev/null | head -1)
if [[ -n "$stale" ]]; then
  print -r -- "build/Liv.app is older than $stale — run ./build.sh first"
  exit 1
fi
xcrun simctl boot "$UDID" >/dev/null 2>&1   # already-booted is fine
if ! xcrun simctl install "$UDID" build/Liv.app 2>&1; then
  print -r -- "install failed — suites would have tested the OLD app"
  exit 1
fi

OUT=$(mktemp -d)
fail=0
for f in $suites; do
  xcrun simctl terminate "$UDID" "$APP" >/dev/null 2>&1
  xcrun simctl launch --console-pty "$UDID" "$APP" -$f.selfcheck 1 > "$OUT/$f" 2>&1 &
  pid=$!
  for i in {1..60}; do
    grep -q "SELFCHECK" "$OUT/$f" 2>/dev/null && break
    perl -e 'select(undef,undef,undef,0.5)'
  done
  kill $pid 2>/dev/null; wait $pid 2>/dev/null
  if grep -q "SELFCHECK PASS" "$OUT/$f" 2>/dev/null; then
    print -r -- "PASS  $f"
  else
    fail=1
    print -r -- "FAIL  $f"
    # The suite prints one line per failed assertion. Show them; a bare
    # "FAIL" tells you nothing you can act on.
    #
    # NOT `grep … || print`: the pipeline's status is `sed`'s, which
    # succeeds on empty input, so the fallback never ran and the one case
    # it exists for — the suite not running at all — printed a bare FAIL.
    lines=$(grep "SELFCHECK" "$OUT/$f" 2>/dev/null)
    if [[ -n "$lines" ]]; then
      print -r -- "$lines" | sed 's/^/      /'
    else
      print -r -- "      (no verdict — the suite did not run at all)"
      print -r -- "      raw output: $OUT/$f"
    fi
  fi
done
xcrun simctl terminate "$UDID" "$APP" >/dev/null 2>&1
exit $fail
