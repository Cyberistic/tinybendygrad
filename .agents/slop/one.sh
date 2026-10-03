#!/bin/sh
# one.sh <file.bend> <outdir> -- check and run exactly ONE bend file.
#
# NEVER read bend's exit status. `--check-only` EXITS 1 ON A CLEAN FILE: dtype.bend
# has 14 permanently unfilled laws and one agent lost a 10-minute retry loop to it.
# The verdict is bend's FIRST DIAGNOSTIC LINE, and WHICH STREAM IT ARRIVES ON DEPENDS ON
# THE VERDICT ITSELF (measured): success prints to STDOUT, failure to STDERR. So the
# verdict is read from `check.err` and falls back to `check.out`. That same split is what
# makes `rows` countable: the error block is on stderr, so everything on stdout is a
# proof row except bend's own two success messages, which are subtracted explicitly.
#
# WHY THE RETRY LOOP: a 0-ROW RESULT IS INDISTINGUISHABLE FROM "NOT STARTED". bend's
# machine stack overflows on ~1 run in 20 and can then print nothing at all, so
# "both check streams silent" and "stack overflow" are retried up to $ONE_ATTEMPTS (6)
# before the caller may conclude anything. 0 rows is NOT a retry trigger on its own --
# a library prints 0 rows forever -- it is reported after the cap and the caller decides
# `no-main` vs `no-rows` from the source, which is a static fact the run cannot supply.
#
# Prints one TAB-separated record:  rows <TAB> attempts <TAB> first-diagnostic-line
# Artifacts land in $outdir, never in the tree: nothing here is opened for writing under
# tinybendygrad/ or tinygrad/.
set -u
cd "$(dirname "$0")/../.."

f="$1"; d="$2"; A="${ONE_ATTEMPTS:-6}"
mkdir -p "$d"

n=0
while [ "$n" -lt "$A" ]; do
  n=$((n + 1))
  ./bin/bend "$f" --check-only >"$d/check.out" 2>"$d/check.err"
  ./bin/bend "$f"              >"$d/run.out"   2>"$d/run.err"
  # Both check streams silent means bend died; a stack overflow means the run was void.
  if { [ -s "$d/check.err" ] || [ -s "$d/check.out" ]; } &&
     ! grep -q 'machine stack overflowed' "$d/run.err"; then
    break
  fi
done

rows=$(grep -vc -e '^$' \
             -e '^ALL PROOFS CHECK$' \
             -e '^Use --verdict for mathematical validity\.$' "$d/run.out")
printf '%s\t%s\t%s\n' "$rows" "$n" \
  "$(cat "$d/check.err" "$d/check.out" | grep -m1 . | tr -d '\r')"
