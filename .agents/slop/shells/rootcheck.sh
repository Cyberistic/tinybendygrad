#!/bin/sh
# rootcheck.sh -- RUN every checks/*.sh in a given tree, from a foreign CWD, and record what
# each one did. `verdicts.py` reads the evidence this leaves and names the verdicts.
#
#   sh rootcheck.sh <tree> <seconds> <outdir>
#
#   <tree>    the checkout to run the scripts FROM -- the live repo, or a `git worktree`
#             copy elsewhere. Root-finding is the ONLY variable under test, so the caller
#             links in the gitignored prerequisites a script needs (`.venv/`,
#             `references/`, `bin/bend`, `runs/`). `runs/` must be a real COPY, not a
#             symlink: six of these scripts write into it and it belongs to another unit.
#   <seconds> per-script alarm. rc=142 IS THIS HARNESS'S OWN ALARM; `verdicts.py` reports
#             it as ALARM and never as a pass.
#
# WHY IT EXECUTES INSTEAD OF READING. The defect is "this script resolved a path against a
# directory that is not the repo root", and the cheapest sound test of that is to RUN the
# script somewhere that is not the repo root and see whether it found anything. A harness
# that hunted for `cd` in the source would share its own assumption with whatever it found --
# and this repo has already paid for exactly that: one tokenizer ate a full stop
# (`[A-Za-z0-9_.-]*`) and a second belt that shared the assumption missed the very thing it
# was hunting. So this file contains no pattern for a shell construct at all.
#
# SKIP, in $SKIP, is for a script that must not be executed here (`mutate.sh` wrote to the
# LIVE tree through a hardcoded absolute path, which is the defect, so running it to
# demonstrate the defect would have demonstrated it destructively). SKIP is never a pass.
set -u
TREE=${1:?tree}
SECS=${2:-20}
OUT=${3:?outdir}
FOREIGN_CWD=${FOREIGN_CWD:-/}
SKIP=${SKIP:-}
mkdir -p "$OUT"
cd "$TREE" || exit 2

# $0 has no slash -> sh. Otherwise take the interpreter off the shebang: eight of the
# eighteen are zsh and their `print` is not sh's `echo`.
interp () { sed -n '1s|^#!*/bin/\([a-z]*\).*|\1|p' "$1"; }

# The arguments a script needs before its root step is even reachable: a script that dies on
# `set -u` and a missing argument never gets to the line under test.
args_for () {
  case $1 in
    classify.sh) printf '%s' "$TREE" ;;
    plant.sh)    printf 'REPO=%s W=%s' "$TREE" "$OUT/plant" ;;
    *)           printf '' ;;
  esac
}

for s in "$TREE"/checks/*.sh; do
  name=${s##*/}
  case " $SKIP " in *" $name "*) echo "SKIP $name (listed in SKIP)"; continue ;; esac
  sh_=$(interp "$s"); [ -n "$sh_" ] || sh_=sh
  a=$(args_for "$name")
  # shellcheck disable=SC2086
  ( cd "$FOREIGN_CWD" && perl -e 'alarm shift; exec @ARGV' "$SECS" "$sh_" "$s" $a ) \
    > "$OUT/$name.out" 2> "$OUT/$name.err"
  echo $? > "$OUT/$name.rc"
done
echo "evidence in $OUT; classify it with:"
echo "  .venv/bin/python .agents/slop/shells/verdicts.py $TREE $OUT"