#!/bin/zsh
# THE PAIRED DISARM. A red with no paired green proves nothing: three controls in this
# project were found already disarmed, one of them leaving six lanes green. So the
# off-switch is exercised, not asserted.
#
# THE OFF-SWITCH IS `git add`. That is the WHOLE POINT of choosing index membership as
# the criterion: the alarm cannot be quieted by configuration, by a name, or by memory --
# only by putting the file in the index, which is committing it, which is a visible act
# by a named author. So the disarm here is the real one, not a simulation.
#
# ⚠ THE INDEX IS SHARED. `probe_f32lit.bend` is ALREADY STAGED by a live unit, so this
# script records the exact index state first and PROVES it restored at the end. It uses
# `git update-index` (index-only, never touches the worktree) rather than `git add`/`rm`,
# so no worktree file of another unit can be disturbed. It COMMITS NOTHING.
# ROOT: one level up from `checks/`, and ASSERTED. See `.agents/slop/shells/README.md`.
_d=${0%/*}; case $_d in "$0") _d=.;; esac
cd "$_d/.." || exit 2
[ -f pyproject.toml ] && [ -d tinybendygrad ] || { echo "$0: not at the repo root (pwd $PWD)" >&2; exit 3; }
PROBE=tinybendygrad/runtime/PROBE-DISARM.bend
say() { print -r -- "$1"; }
# BOTH READINGS, because they disagreed once and I would rather over-record: with jj
# co-committing, `git diff --cached --name-only` printed EMPTY while `git status
# --porcelain` showed seven staged entries (`A`/`M`/`D` in column 1). Recording only the
# first would have made the restore check compare "" with "" and prove nothing about a
# file this script never staged.
state() { { git diff --cached --name-only; git status --porcelain | cut -c1-2; } | sort | uniq; }
alarm() { .agents/slop/substrate-check.sh "$PROBE" tinybendygrad/runtime/zzread.bend 2>&1 \
            | grep -E '^(ROUTE|PROVENANCE|PORT ALARM|DENOMINATOR)'; }

say "### INDEX STATE BEFORE (recorded so it can be PROVEN restored)"
before=$(state); print -r -- "$before"
say ""
say "### 1. ARMED -- a probe in tinybendygrad/, nothing staged, nothing remembered"
printf 'import Base\n\ndef main() -> IO(Unit):\n  IO.print("probe")\n' > "$PROBE"
alarm
say ""
say '### 2. DISARMED -- the ONLY change is `git update-index --add`, i.e. OWN IT'
git update-index --add -- "$PROBE" || say "update-index FAILED"
alarm
say ""
say "### 3. BACK TO ARMED -- released from the index, same file still on disk"
git update-index --force-remove -- "$PROBE"
alarm
say ""
say "### 4. RESTORE"
rm -f "$PROBE"
after=$(state)
if [ "$before" = "$after" ]; then
  say "INDEX RESTORED: identical to the recorded state ($(print -r -- "$after" | grep -c '' ) entr(y/ies))."
else
  say "INDEX **NOT** RESTORED -- was:"; print -r -- "$before"; say "now:"; print -r -- "$after"
fi
print -r -- "PROBE-DISARM.bend on disk? $([ -e "$PROBE" ] && echo YES-LEFTOVER || echo no)"
print -r -- "staged copies of it? $(git diff --cached --name-only -- "$PROBE" | grep -c '')"