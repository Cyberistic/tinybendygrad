#!/bin/sh
# wk-f32-gate.sh -- the CPython gate for the I64 -> F32 conversion, `wk_i64_to_f32`.
#
#   sh .agents/slop/wk-f32-gate.sh
#
# 18 rows, THREE LANES -- CPython, bend interpreted, bend compiled -- all byte-identical.
# CPython's answer is `float(int)`, which is CORRECTLY ROUNDED, and the port's is a
# 24-bit-chunk Horner. Comparing bit patterns and not decimals is not a preference here:
# the difference between the two implementations is entirely in the last mantissa bit.
#
# `wk_dt_const.fpure` (uop/weak.bend) is the conversion's only caller, so it is the
# `weakint -> weakfloat` promotion in `elementwise.bend`, and `tanh` is held behind it.
# **This primitive had NO GATE AT ALL before this one**, which is how a conversion can be
# wrong for every negative value in the signed range and still be described in the tree as
# a rounding detail nobody had checked.
#
# THE TABLE IS WRITTEN ONCE, in `wk-f32-rows.py`, which generates BOTH the oracle's
# expectations and the Bend driver's fixtures. Every value is a (hi, lo) WORD PAIR, so
# nothing is re-spelled as a decimal on the Bend side -- and a value above 2**31 needs no
# negative literal, which is not a term in Bend.
#
# THE VALUES THAT REFUTE THE OLD FORMULA, and they are all NEGATIVE, which is the whole
# shape of the bug: `neg1` (-1), `neg2` (-2) and `negm32` (-2**32). The old two-term sum
# needed `hi` exactly, f32 has 24 mantissa bits, so `U32.to_f32(0xFFFFFFFF)` is 2**32 and
# the high term collapsed to zero. It made -1 and -2 IDENTICAL, and the oracle's two rows
# are different numbers, so no single-row fixture could have caught it.
set -e
cd "$(dirname "$0")/../.."
GT=.agents/slop/wk-f32-gate
mkdir -p "$GT"

ROWS=18
NAME=wk-f32.bend

check_line=$(./bin/bend ".agents/slop/$NAME" --check-only | head -1)
if [ "$check_line" != "ALL PROOFS CHECK" ]; then
  echo "wk-f32-gate: --check-only says '$check_line'" >&2
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
  echo "wk-f32-gate: lane did not produce $ROWS rows after $tries tries:" >&2
  cat "$out.err" >&2
  return 1
}

# THE TABLE IS REGENERATED, not read from a snapshot, so the fixture and the expectation
# cannot drift apart in the repo. `wk-f32-rows.py` writes the oracle's rows to stdout and
# the driver to `.agents/slop/wk-f32.bend`.
.venv/bin/python .agents/slop/wk-f32-rows.py > "$GT-py.txt"
run_lane "$GT-bd.txt" ./bin/bend ".agents/slop/$NAME"
./bin/bend ".agents/slop/$NAME" -o "$GT.bin"
run_lane "$GT-bn.txt" "$GT.bin"

diff "$GT-py.txt" "$GT-bd.txt" || { echo "wk-f32-gate: DISAGREE (interpreted)" >&2; exit 1; }
diff "$GT-py.txt" "$GT-bn.txt" || { echo "wk-f32-gate: DISAGREE (native)" >&2; exit 1; }

# The three rows that refute the old formula are PINNED BY NAME, so a regression that
# breaks only the negative half cannot hide behind the fifteen rows that always passed.
for nm in neg1 neg2 negm32 i64min; do
  grep -q "^$nm=" "$GT-py.txt" || { echo "wk-f32-gate: $nm is MISSING from the table" >&2; exit 1; }
done
# and they must be DISTINCT: the old formula made neg1 and neg2 identical, so a table that
# let them collapse would not have noticed. Two rows that must differ, asserted to differ.
a=$(grep '^neg1=' "$GT-py.txt" | cut -d= -f2)
b=$(grep '^neg2=' "$GT-py.txt" | cut -d= -f2)
[ "$a" != "$b" ] || { echo "wk-f32-gate: neg1 and neg2 have the SAME f32 -- the table is wrong" >&2; exit 1; }

echo "wk-f32-gate: 18 rows, 3 lanes byte-identical"
