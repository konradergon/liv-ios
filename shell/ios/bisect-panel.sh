#!/bin/sh
# liv iOS — WHICH HALF OF THE REDESIGN STOPPED THE LIBRARY DOOR.
#
# Four builds, four runs of `drive.sh library`, one table. It exists
# because the same question was asked five times by hand over
# 2026-09-16, each answer taking a round trip, and two of those answers
# were worthless: one measured a binary whose build had failed, and one
# died in the harness before it ever reached the app.
#
# WHAT IT COMPARES. The redesign is two independent halves, and either
# could be the fault:
#
#   PANEL  Panel.swift + Chrome.swift — the workspace head at the top of
#          the library, the fade's `solid:`, the foot and the mask gone.
#   REST   the rename — the view drawn as Notes, its icon, the row order,
#          the lens that no longer exists, a launch flag, a route alias.
#
# They are paired that way because they must compile: Panel.swift asks
# the scrim for its reach and the two revisions spell that differently,
# and Everything.swift switches over the lens Positions.swift declares.
# Split them any further and half the builds fail for reasons that say
# nothing.
#
# WHAT IT LEAVES BEHIND: nothing. `Sources` is restored to the commit you
# started on, on the way out and on a Ctrl-C. It refuses to start if you
# have uncommitted work there, because it would overwrite it.
#
# The four rows read as a truth table. base OPENS and head does not is
# the run that means anything; whichever single half fails alone is the
# one carrying the fault, and if both fail alone it is in the pairing.

set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT" || exit 1

# The last build the owner opened the panel in (2026-09-16). Override to
# bisect a different pair: BISECT_GOOD=<ref> ./shell/ios/bisect-panel.sh
GOOD=${BISECT_GOOD:-389baec}

PANEL="shell/ios/Sources/Panel.swift shell/ios/Sources/Chrome.swift"
REST="shell/ios/Sources/App.swift shell/ios/Sources/Desk.swift \
shell/ios/Sources/Everything.swift shell/ios/Sources/Navigate.swift \
shell/ios/Sources/Positions.swift shell/ios/Sources/Routes.swift \
shell/ios/Sources/Surface.swift shell/ios/Sources/Tabs.swift"

NOW=$(git rev-parse HEAD) || exit 1
LOG=${TMPDIR:-/tmp}/liv-bisect
mkdir -p "$LOG"

if [ -n "$(git status --porcelain -- shell/ios/Sources)" ]; then
    echo "shell/ios/Sources has uncommitted changes, and this script" >&2
    echo "overwrites every file in it. Commit or stash them first." >&2
    exit 1
fi

git rev-parse --verify "$GOOD^{commit}" >/dev/null 2>&1 || {
    echo "no such commit: $GOOD" >&2
    exit 1
}

restore() { git checkout "$NOW" -- shell/ios/Sources 2>/dev/null; }
trap 'restore' EXIT
trap 'restore; exit 130' INT TERM

echo "good = $GOOD   head = $(git rev-parse --short "$NOW")"
echo

try() {
    name=$1
    panel_ref=$2
    rest_ref=$3
    slug=$(echo "$name" | tr ' ' '-')

    git checkout "$panel_ref" -- $PANEL || return 1
    git checkout "$rest_ref" -- $REST || return 1

    printf '  %-18s ' "$name"

    if ! ./shell/ios/build.sh >"$LOG/$slug.build.txt" 2>&1; then
        echo "BUILD FAILED    $LOG/$slug.build.txt"
        return 0
    fi
    if ./shell/ios/drive.sh library >"$LOG/$slug.run.txt" 2>&1; then
        echo "panel OPENS"
    else
        echo "panel does NOT open   $LOG/$slug.run.txt"
    fi
}

echo "  candidate          result"
echo "  ------------------ ----------------------------------------"
try "base"        "$GOOD" "$GOOD"
try "panel only"  "$NOW"  "$GOOD"
try "rename only" "$GOOD" "$NOW"
try "head"        "$NOW"  "$NOW"

echo
echo "Sources restored to $(git rev-parse --short "$NOW")."
