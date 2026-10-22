#!/bin/sh
# THE BEND LOCK. One bend at a time, and a lock that CANNOT OUTLIVE ITS OWNER.
#
# WHY THIS EXISTS, AND IT IS NOT A TASTE.  `AGENTS.md`'s rule is that the SUM of
# concurrently running files' measured peak RSS must be under 60% of `hw.memsize` -- a rule
# about a SUM, not about a COUNT.  But a machine that had 14 units running at once measured
# `loadavg 193.85` ON 12 CORES, and one unit's `--plant` waited **289 s** for the compiler.
# So the bend runs are SERIALISED, and a serialisation needs a lock that a DEAD PROCESS
# cannot keep.
#
# THE HAZARD THIS FIXES, MEASURED 2026-10-22: a plain `mkdir` lock was found **HELD FOR
# MINUTES WITH NO COMPILER ALIVE BEHIND IT**, and every unit waited on it.  A lock whose
# owner is gone must be reclaimable -- and the reclamation must NOT steal a LIVE owner's
# lock, or two compilers run at once and the memory precondition is what breaks.
#
# THE OWNER IS A PID, AND THE COMPILER IS CHECKED TOO.  The compiler is `bun`, not the
# shell that invoked it, so "is the owner alive" is necessary but NOT sufficient: a shell
# can be alive while its `bun` child is gone.  Hence the second check.
#
#   usage:  checks/bendlock.sh -- <command> [args...]
#   env:    BEND_LOCK_DIR       where the lock lives (default: see below)
#           BEND_LOCK_STALE_S   how old a DEAD owner's lock may be before reclaim (default 300)
#
# THE DEFAULT LOCK PATH IS THE ONE THE UNITS WERE TOLD TO USE, AND THAT IS DELIBERATE.
# MEASURED 2026-10-22: a script with a repo-named lock and an ad-hoc `mkdir` recipe with
# a different path are **TWO LOCKS**, AND TWO LOCKS DO NOT EXCLUDE EACH OTHER -- the recipe
# would hold one while this script held the other, and two compilers would run at once,
# which is the exact thing the lock is for.  **A LOCK IS ONLY A LOCK IF EVERY FORM SHARES
# IT.**  When the ad-hoc recipe is retired, change this default and the recipe together.
#
# AN UNOWNED LOCK IS RECLAIMED FASTER THAN A DEAD-OWNED ONE.  A lock with no `owner` file
# has nobody who can prove they own it, so waiting the full stale window for it is waiting
# for nothing.  A lock whose owner PID is ALIVE is NEVER reclaimed.
#
# THE COMPILER IS `bin/bend`, NOT bare `bend`: `command -v bend` FAILS in this tree.
#
# WHAT IT DOES NOT DO: it does not bound the child's memory.  For that, use
# `checks/bounded.py --mb 2048 -- <command>` -- and READ THE VERDICT TOKEN ON ITS
# `[bounded]` LINE (`WITHIN-LIMITS` / `KILLED-ON-MEMORY` / `TIMED-OUT`), NOT THE EXIT
# CODE.  `AGENTS.md` records a unit that lost 425 rows by believing the status.

set -eu

if [ "$1" = "--" ]; then shift; fi
if [ $# -lt 1 ]; then
  echo "bendlock: usage: checks/bendlock.sh -- <command> [args...]" >&2
  exit 2
fi

LOCKDIR="${BEND_LOCK_DIR:-${TMPDIR:-/tmp}/opencode/bend.lock}"
STALE_S="${BEND_LOCK_STALE_S:-300}"
UNOWNED_S="${BEND_LOCK_UNOWNED_S:-30}"

# A COMPILER IS ALIVE?  `bun .../main.ts` is the compiler; a bare `bend` does not exist.
compiler_alive() {
  pgrep -f 'main\.ts' >/dev/null 2>&1
}

# THE OWNER IS ALIVE?  `kill -0` asks the kernel, so it is true for a live process and
# false for a dead one.  A PID that is not ours is still ours to test.
owner_alive() {
  [ "${1:-0}" -gt 0 ] 2>/dev/null || return 1
  kill -0 "$1" 2>/dev/null
}

acquire() {
  while :; do
    if mkdir "$LOCKDIR" 2>/dev/null; then
      echo $$ > "$LOCKDIR/owner"
      return 0
    fi
    # THE LOCK IS HELD.  Take it only if its owner is GONE and it is OLD -- and an
    # UNOWNED lock (no `owner` file) is reclaimed on the shorter window, because nobody
    # can prove they own it.
    op=$(cat "$LOCKDIR/owner" 2>/dev/null || echo 0)
    if [ "$op" -gt 0 ] 2>/dev/null; then
      owner_dead=0
      owner_alive "$op" || owner_dead=1
      limit=$STALE_S
    else
      owner_dead=1
      limit=$UNOWNED_S
    fi
    if [ "$owner_dead" = 1 ] && ! compiler_alive; then
      age=$(( $(date +%s) - $(stat -f %m "$LOCKDIR" 2>/dev/null || echo 0) ))
      if [ "$age" -gt "$limit" ]; then
        rm -f "$LOCKDIR/owner" 2>/dev/null || true
        rmdir "$LOCKDIR" 2>/dev/null || true
        continue
      fi
    fi
    sleep 2
  done
}

release() {
  rm -f "$LOCKDIR/owner" 2>/dev/null || true
  rmdir "$LOCKDIR" 2>/dev/null || true
}

acquire
trap release EXIT INT TERM
"$@"
