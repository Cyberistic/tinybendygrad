#!/bin/sh
# helpers-gap-gate.sh -- THE DIFFERENTIAL GATE for the `helpers.bend` defs that
# NO OTHER GATE COVERS.
#
#   sh .agents/slop/helpers-device-shrink/helpers-gap-gate.sh
#
# TWO LANES AND A DIFF:
#
#   py   CPython, `.agents/slop/helpers-device-shrink/helpers-gap-oracle.py`
#        -> $GT.rows, the EXPECTED VALUES.
#   bd   Bend, `./bin/bend .agents/slop/helpers-device-shrink/helpers-gap.bend`
#        -> $GT.bd
#
# **AND THE DIFF IS THE TEST.** Every expectation is CPython's OWN arithmetic or
# CPython's OWN `math.gcd`, and NO row is typed from memory. The 64-bit rows
# compare against CPython's UNBOUNDED integers taken modulo 2**64 -- because the
# port's PAIR IS 64 BITS WIDE and the wrap is the WIDTH rather than a choice.
#
# **AND WHAT IS ALREADY COVERED, SO THIS DOES NOT DUPLICATE IT:**
#   `.agents/slop/helpers-tc-gate.sh` -- 237 shared rows (`trange`,
#     `GlobalCounters`, `Context`, `i64_or`, `i64_and`, `i64_shl`, `i64_div`,
#     `i64_mod`, `i64_add`, `i64_sub`, `i64_dec`).
#   `gates/i64-shl-gate.py` -- 151 rows.
#   `gates/i64-shr-gate.py` -- 301 rows.
# **THE GAPS THIS FILLS ARE:** `i64_mul`, `gcd`, `u64_divmod`, `i64_abs`,
# `i64_not`, `i64_neg`, `cdiv_i64`, `cmod_i64`, `floordiv_i32`, `floormod_i32`,
# `cdiv_i32`, `cmod_i32`, `ceildiv_i32`, `round_up_i32`, `round_down_i32` and
# `next_power2`.
#
# **AND THE BEND LANE'S IMPORT IS REBASED BY HAND** -- the driver lives under
# `.agents/slop/helpers-device-shrink/` and reaches the port at
# `./../../../tinybendygrad/helpers.bend`.
set -e
cd "$(dirname "$0")/../../.."
GT=.agents/slop/helpers-device-shrink/gap

# **`bend`'s machine stack overflows on ~1 run in 20 and then prints ZERO rows,
# which is indistinguishable from "did not start", so the lane is retried while
# its row count is 0.** A lane that is genuinely empty would loop forever, and
# that is the intended failure: a non-empty row set is the gate.
run_lane() {  # $1 = output file, rest = the bend invocation
  out=$1; shift
  tries=0
  while [ "$tries" -lt 25 ]; do
    tries=$((tries + 1))
    if "$@" > "$out.tmp" 2>"$out.err" && [ -s "$out.tmp" ]; then
      mv "$out.tmp" "$out"
      return 0
    fi
  done
  echo "helpers-gap-gate: lane produced 0 rows after $tries tries:" >&2
  cat "$out.err" >&2
  return 1
}

.venv/bin/python .agents/slop/helpers-device-shrink/helpers-gap-oracle.py > "$GT.rows"
run_lane "$GT.bd" ./bin/bend .agents/slop/helpers-device-shrink/helpers-gap.bend

# **THE ROWS ARE COMPARED AS SETS OF `name=value` LINES, SORTED**, so the
# comparison is order-INDEPENDENT and a row that moved is a DIFF. **AND THE SORT
# GOES THROUGH FILES, NOT PROCESS SUBSTITUTION** -- `sh` ON macOS IS BASH 3.2
# WITHOUT `<( )`, AND A GATE THAT DOES NOT RUN ON THE MACHINE IS NOT A GATE.
sort "$GT.rows" > "$GT.rows.sorted"
sort "$GT.bd" > "$GT.bd.sorted"
if diff "$GT.rows.sorted" "$GT.bd.sorted" > "$GT.diff"; then
  echo "helpers-gap-gate: $(wc -l < "$GT.rows" | tr -d ' ') shared rows, the port and CPython agree"
  exit 0
fi
echo "helpers-gap-gate: FAIL -- the port and CPython disagree:" >&2
cat "$GT.diff" >&2
exit 1
