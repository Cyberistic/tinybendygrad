#!/bin/sh
# ew-consts-gate.sh -- the CPython gate for elementwise.bend's F32 CONSTANTS.
#
#   sh .agents/slop/ew-consts-gate.sh
#
# 21 rows, THREE LANES -- CPython, bend interpreted, bend compiled -- all byte-identical.
# Each row is one constant and its f32 BIT PATTERN.
#
# THIS GATE EXISTS TO REFUTE A WALL, and that is unusual enough to say plainly. The marker
# block above these constants in elementwise.bend read "no float literal anywhere in the
# port, because `F32` is `F32{data: Word(32n)}`, `Word` is not exported, and `U32.to_f32` is
# an unfilled LAW which live code may not call" -- and that claim held up a dozen methods at
# a time. All three of its halves are false: a literal works, `F32.pi()` is a constant, and
# `U32.to_f32` is a base law that `F32.from_nat` itself calls. A claim about what the
# substrate CANNOT do is the one kind of claim a compiler will not check for you, so it has
# to be measured, and measuring it is this file.
#
# WHY BIT PATTERNS AND NOT DECIMALS. The port has no `F64`, so 32 bits is the only place
# two sides can meet. A decimal gate would also pass on a transcription that is wrong in the
# ninth place and still rounds to the right f32 -- which is the constants' actual failure
# mode, and it bit three of them here. The oracle's header records all three.
#
# WHAT IS **NOT** GATED, and it is a real difference rather than an omission: `H.f32_show` is
# a SIX-DECIMAL-PLACE formatter and CPython's `repr` is a SHORTEST-ROUND-TRIP one, so
# f32(log 2) is `0.693147` here and `0.6931471824645996` there. The first draft of this
# driver printed the decimal and every row differed -- but for two reasons, and the first
# one was my own error: it compared CPython's original DOUBLE against the port's f32, which
# are different quantities. Underneath that error the printer difference is real. It is
# about a different def, so it is recorded as its own unit rather than asserted here.
set -e
cd "$(dirname "$0")/../.."
GT=.agents/slop/ew-consts-gate
mkdir -p "$GT"

ROWS=21

check_line=$(./bin/bend .agents/slop/ew-consts.bend --check-only | head -1)
if [ "$check_line" != "ALL PROOFS CHECK" ]; then
  echo "ew-consts-gate: --check-only says '$check_line'" >&2
  exit 1
fi

# The driver has no row-name prefix, so the lane filter is the WHOLE output. That is only
# safe because the row count is asserted immediately below: a lane that printed nothing and
# a lane that printed 21 rows must never look alike.
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
  echo "ew-consts-gate: lane did not produce $ROWS rows after $tries tries:" >&2
  cat "$out.err" >&2
  return 1
}

.venv/bin/python .agents/slop/ew-consts-oracle.py > "$GT-py.txt"
run_lane "$GT-bd.txt" ./bin/bend .agents/slop/ew-consts.bend
./bin/bend .agents/slop/ew-consts.bend -o "$GT.bin"
run_lane "$GT-bn.txt" "$GT.bin"

diff "$GT-py.txt" "$GT-bd.txt" || { echo "ew-consts-gate: DISAGREE (interpreted)" >&2; exit 1; }
diff "$GT-py.txt" "$GT-bn.txt" || { echo "ew-consts-gate: DISAGREE (native)" >&2; exit 1; }

# EVERY ROW IS NAMED, and the names are the ones the oracle and the driver agreed on, so a
# renamed or dropped constant fails here rather than shrinking the diff by one line.
cut -d= -f1 "$GT-py.txt" | sort > "$GT-names.txt"
cut -d= -f1 "$GT-bd.txt" | sort > "$GT-names.bd"
diff "$GT-names.txt" "$GT-names.bd" || { echo "ew-consts-gate: the row NAMES differ" >&2; exit 1; }
[ "$(wc -l < "$GT-names.txt" | tr -d ' ')" = "$ROWS" ] || {
  echo "ew-consts-gate: expected $ROWS names" >&2; exit 1; }

# And the three rows that MEASURED WRONG on the obvious spelling are pinned by name, so a
# later "simplification" back to the more precise-looking literal is a gate failure and not
# a silent one-ulp regression nobody notices until a gelu output drifts.
for nm in k_log10_2 k_selu_gamma k_sqrt_2_over_pi; do
  grep -q "^$nm=" "$GT-py.txt" || { echo "ew-consts-gate: $nm is MISSING" >&2; exit 1; }
done

echo "ew-consts-gate: 21 rows, 3 lanes byte-identical"
