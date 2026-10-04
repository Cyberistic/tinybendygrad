#!/bin/sh
# wk-cd-gate.sh -- the CPython gate for `wk_commit_dtype`, the NODE-LEVEL reader that nine
# of uop/weak.bend's markers said was missing.
#
#   sh .agents/slop/wk-cd-gate.sh
#
# 7 rows, THREE LANES -- CPython, bend interpreted, bend compiled -- 6 IDENTICAL and ONE
# DOCUMENTED DIVERGENCE (`cd_none`).
#
# WHAT IS UNDER TEST. `tinygrad/mixin/dtype.py:16` is three lines:
#     commit_int(self._uop.vmin, self._uop.vmax, default_int) if weakint else self.dtype
# The port had the ARITHMETIC (`D.commit_dtype`, `mixin/dtype.bend`) and the BOUNDS
# (`UOp.vmin`/`UOp.vmax`, `uop/fold.bend`). What was missing is the ONE call that joins
# them -- and it could not be written next to the arithmetic, because `mixin/dtype.bend` does
# not import `uop/weak.bend` and `wk_dt` lives there. So the wall those nine markers describe
# was never a language limit: it was an IMPORT TOPOLOGY. MEASURED, the edge this adds
# (`weak.bend -> mixin/dtype.bend`) closes no cycle -- ops.bend, fold.bend and spec.bend all
# do not import weak.bend.
#
# THE FIXTURE MUST BE A weakint PARAM, and that is the first thing this gate taught. A PARAM
# with dtype int32 answers `i32` on EVERY row -- the weakint branch is not taken and
# `commit_dtype` returns `self.dtype` -- so the first version of the oracle had seven rows
# of `i32` and proved nothing. The rows that discriminate are the ranges int32 cannot hold,
# because `commit_int`'s ladder starts at `default_int` and its first rung swallows every
# range inside int32. A gate without `cd_big_2p40` and `cd_one_2p40` would pass a reader
# that always answered `i32`.
#
# THE DIVERGENCE, `cd_none`, IS NAMED AND PINNED. CPython answers `i64`; the port answers
# nothing, because a PARAM with no `vmin_vmax` gives the bounds sweep no interval to
# report. `wk_commit_dtype` is FAITHFUL here -- it reports exactly what `UOp.vmin`/`UOp.vmax`
# gave it -- so the gap is the sweep's PARAM-with-no-bounds arm, not the reader. Both sides'
# content is asserted below, so the divergence cannot change unnoticed in either direction.
set -e
cd "$(dirname "$0")/../.."
GT=.agents/slop/wk-cd-gate
mkdir -p "$GT"

ROWS=7
COMPARED=6
NAME=wk-cd.bend
DIVERGES='cd_none'

check_line=$(./bin/bend ".agents/slop/$NAME" --check-only | head -1)
if [ "$check_line" != "ALL PROOFS CHECK" ]; then
  echo "wk-cd-gate: --check-only says '$check_line'" >&2
  exit 1
fi

run_lane() {  # $1 = output file, rest = the bend invocation
  out=$1; shift
  tries=0
  while [ "$tries" -lt 25 ]; do
    tries=$((tries + 1))
    if "$@" > "$out.tmp" 2> "$out.err" && [ "$(wc -l < "$out.tmp" | tr -d ' ')" = "$ROWS" ]; then
      mv "$out.tmp" "$out"
      return 0
    fi
  done
  echo "wk-cd-gate: lane did not produce $ROWS rows after $tries tries:" >&2
  cat "$out.err" >&2
  return 1
}

.venv/bin/python .agents/slop/wk-cd-oracle.py > "$GT-py.txt"
run_lane "$GT-bd.txt" ./bin/bend ".agents/slop/$NAME"
./bin/bend ".agents/slop/$NAME" -o "$GT.bin"
run_lane "$GT-bn.txt" "$GT.bin"

# BOTH SIDES ARE FILTERED, and the oracle side is not a no-op here: `cd_none` is in BOTH
# files and is the one that differs, so diffing an unfiltered oracle against a filtered port
# would compare exactly the row known to differ. That is how a divergence list stops working.
grep -vE "^($DIVERGES)=" "$GT-py.txt" > "$GT-py.sub"
grep -vE "^($DIVERGES)=" "$GT-bd.txt" > "$GT-bd.sub"
grep -vE "^($DIVERGES)=" "$GT-bn.txt" > "$GT-bn.sub"

for f in "$GT-py.txt" "$GT-bd.txt" "$GT-bn.txt"; do
  n=$(wc -l < "$f" | tr -d ' ')
  [ "$n" = "$ROWS" ] || { echo "wk-cd-gate: $f has $n rows, expected $ROWS" >&2; exit 1; }
done
for f in "$GT-py.sub" "$GT-bd.sub" "$GT-bn.sub"; do
  n=$(wc -l < "$f" | tr -d ' ')
  [ "$n" = "$COMPARED" ] || { echo "wk-cd-gate: $f has $n COMPARED rows, expected $COMPARED" >&2; exit 1; }
done

diff "$GT-py.sub" "$GT-bd.sub" || { echo "wk-cd-gate: DISAGREE (interpreted)" >&2; exit 1; }
diff "$GT-py.sub" "$GT-bn.sub" || { echo "wk-cd-gate: DISAGREE (native)" >&2; exit 1; }

# THE DIVERGENT ROW IS PINNED ON BOTH SIDES. A divergence nobody checks is a tolerance.
grep -q "^cd_none=i64$"   "$GT-py.txt" || { echo "wk-cd-gate: CPython's cd_none CHANGED" >&2; exit 1; }
grep -q "^cd_none=None$" "$GT-bd.txt" || { echo "wk-cd-gate: the port's cd_none CHANGED -- is the sweep's PARAM arm fixed? then drop this" >&2; exit 1; }
grep -q "^cd_none=None$" "$GT-bn.txt" || { echo "wk-cd-gate: the native lane's cd_none CHANGED" >&2; exit 1; }
# AND `DIVERGES` MUST STILL BE EXCLUDING EXACTLY ONE ROW PER LANE, or the list is stale. A
# first draft of this check used `<( ... )` -- the SAME bash-ism that made five gate
# harnesses in this tree unparseable under `sh` -- and compared a filtered file with itself,
# which is always equal and therefore always passes. It is now a COUNT, which is what the
# claim actually is: the exclusion removes one row and the rest are compared.
for f in "$GT-py.txt" "$GT-bd.txt" "$GT-bn.txt"; do
  kept=$(grep -cE "^($DIVERGES)=" "$f" || true)
  [ "$kept" = 1 ] || { echo "wk-cd-gate: $f has $kept '$DIVERGES' rows, expected exactly 1" >&2; exit 1; }
done

echo "wk-cd-gate: 6 rows identical, 3 lanes, 1 documented divergence ($DIVERGES)"
