#!/bin/sh
# .agents/slop/lane-load-sweep.sh -- the rows-against-load curve, one cell at a time.
#
# THE CELLS, and why cell B exists:
#   A  nice 0,  0 filler   -- the reference: what an uncontended lane looks like if the machine
#                              ever gives one back
#   B  nice 19, 0 filler   -- THE NICE CONTROL. B vs A prices `nice` itself. Without it, the
#                              A..F slope is confounded and cannot be attributed to load.
#   C..F                   -- nice 19 with 2/4/8/16 runnable fillers. Load is the only variable.
#
# EVERY CELL TIMES OUT rather than hanging, and the timeout is COUNTED (partial rows are kept),
# because a starved lane's whole signature is that it is still running when you stop looking.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
LANE=${LANE:-tinybendygrad/runtime/support/nv/nvdev.bend}
REPS=${REPS:-3}
TMO=${TMO:-75}
OUT=${OUT:-.agents/slop/lane-load-measurements.tsv}
PY="$ROOT/.venv/bin/python"

run () {  # run <fillers> <lanenice> <label> [extra flags]
  f=$1; n=$2; l=$3; shift 3
  echo "" >> "$ROOT/$OUT"
  "$PY" "$ROOT/.agents/slop/lane-load.py" --lane "$LANE" --fillers "$f" \
      --fillernice 19 --lanenice "$n" --reps "$REPS" --timeout "$TMO" \
      --label "$l" --out "$OUT" "$@"
}

run 0  0  "A_nice0_f0"
run 0  19 "B_nice19_f0"
run 2  19 "C_nice19_f2"
run 4  19 "D_nice19_f4"
run 8  19 "E_nice19_f8"
run 16 19 "F_nice19_f16"
# THE TYPE-CHECKER CONTROL. NV7 claims `--check-only` stayed at 0.37 s under 19 bends, i.e. that
# the interpreter and not the type checker degrades. That is the load-bearing half of NV7 and it
# has never been measured as a function of load either, so it is measured here at the deepest
# cell. If rows degrade and check-only does not, the degradation is in EVALUATION.
run 16 19 "G_checkonly_f16" --check-only
echo "SWEEP DONE"
