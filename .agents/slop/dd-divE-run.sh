#!/bin/sh
# dd-divE-run.sh -- run the dtype.bend gate until the run is HEALTHY, not merely
# non-empty. dd-run.sh's guard is `grep -c '^lg'` and that is NOT enough: a
# stack-overflowed run prints EVERY row and comes back with EMPTY cone walks
# (measured: lgrsig=, lgssig=, lgtsig=, lgvsig=, lgwsig=, lgxsig=, upsig=, with
# 148 ^lg rows present). So the guard is dd-divE-check.py --degenerate, which
# fails on any empty `sig`/`k` and on a missing `c{i}`.
#
#   dd-divE-run.sh [TREE_DIR] [OUT] [TRIES]
set -u
TREE="${1:-tinybendygrad}"
OUT="${2:-.agents/slop/dd-gate.txt}"
TRIES="${3:-8}"
i=0
while [ "$i" -lt "$TRIES" ]; do
  i=$((i + 1))
  ./bin/bend "$TREE/codegen/decomp/dtype.bend" > "$OUT.tmp" 2> "$OUT.err"
  if python3 .agents/slop/dd-divE-check.py "$OUT.tmp" .agents/slop/dd-oracle.txt \
       --degenerate > "$OUT.health" 2>&1; then
    mv "$OUT.tmp" "$OUT"
    rm -f "$OUT.err"
    cat "$OUT.health"
    echo "ok: healthy run on attempt $i -> $OUT"
    exit 0
  fi
  echo "attempt $i degenerate: $(cat "$OUT.health")" >&2
done
echo "FAILED: $TRIES runs, none healthy" >&2
exit 1