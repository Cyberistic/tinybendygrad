#!/bin/zsh
# classify.sh <sandbox-root-relative-to-tinybendygrad>
# For every file in a mutation sandbox, decide against the LIVE tree + git blob history:
#   IDENTICAL : byte-identical to the live file right now        (clean duplicate)
#   STALE     : differs, but its content == some COMMITTED revision of that live path
#   PLANT     : differs, and its content appears at NO revision of that path (unique)
#   NOREF     : no live file at that path at all
# A PLANT is a deliberately-mutated copy still sitting in the tree. That is the thing
# that must not be reachable by accident, because a greping reader cannot tell it from
# the real file without this ledger.
set -u
# ROOT: one level up from `checks/`, and ASSERTED. `../../..` was written when this file
# lived at `.agents/slop/<unit>/` and left behind at the shallower depth, so it landed two
# levels ABOVE the repo -- and then every `tinybendygrad/$f` lookup missed and all 3476
# files were reported NOREF with exit 0. See `.agents/slop/shells/README.md`.
_d=${0%/*}; case $_d in "$0") _d=.;; esac
cd "$_d/.." || exit 1
[ -f pyproject.toml ] && [ -d tinybendygrad ] || { echo "$0: not at the repo root (pwd $PWD)" >&2; exit 3; }
ROOT="$1"
H=.agents/slop/mutledger/BLOBHIST.tsv
for f in $(cd "$ROOT" && find . -type f | sed 's|^\./||' | sort); do
  live="tinybendygrad/$f"
  if [ ! -e "$live" ]; then printf 'NOREF\t%s\n' "$f"; continue; fi
  if cmp -s "$ROOT/$f" "$live"; then printf 'IDENTICAL\t%s\n' "$f"; continue; fi
  b=$(git hash-object "$ROOT/$f")
  if grep -q "^$live	$b\$" "$H"; then printf 'STALE\t%s\n' "$f"
  else printf 'PLANT\t%s\n' "$f"; fi
done