#!/bin/sh
# ew-gate.sh -- the CPython gate for mixin/elementwise.bend's METHOD SURFACE.
#
#   sh .agents/slop/ew-gate.sh
#
# 75 rows, THREE LANES -- CPython, bend interpreted, bend compiled -- all byte-identical.
#
# THE ORACLE AND THE EMITTER BOTH EXISTED AND NO GATE DID. That is the same gap
# prepare.bend had, and it is a gap with a cost: a file whose surface is UNMEASURED
# accumulates reasons that nobody checked. This one had a wall -- "no float literal
# anywhere in the port" -- holding up a dozen methods, and all three of its halves were
# false (see ew-consts-gate.sh, which refuted it). Four of the last five walls in this
# port were an untested premise rather than a substrate limit, so the fix is not more care:
# it is that a claim gets a GATE before it gets believed. This file is that gate.
#
# THE ROWS ARE GRAPH SIGNATURES and not values: `ew_add=3 CONST/0 CONST/0 ADD/2` is the
# node count, then each node's `OP/n` with its src count, in arena order. Comparing the
# graph rather than a number is the stronger claim of the two -- a promotion that produces
# the right dtype by the wrong ops is a different method, and a value gate would pass it.
#
# ONE ROW DIVERGES, BY NAME, and it is the only one. `ew_promo_nc` is the port's signature
# for a non-constant promotion, and the oracle DELIBERATELY does not emit it: a signature
# there is unfalsifiable, because CPython's promotion of a non-constant has no fixed arity to
# compare against. The oracle gates the two halves it CAN check -- `ew_dt_promo_nc` and
# `ew_op_promo_nc` -- and the port emits those too. So the divergence is excluded rather than
# tolerated silently, it must be PRESENT, and a gate that quietly dropped it would be a gate
# that cannot tell a documented divergence from a hole.
#
# A GATE THAT DIFFS LINES AND NOT FIELDS. The rows end in a space (the signature joiner), and
# a field map would not notice if one side stopped emitting it.
#
# WHAT THIS GATE DOES NOT CLAIM, and a mutation table must not pretend otherwise: it claims
# the SHAPES. `0.30103 -> 0.30102999` leaves this gate GREEN, and that is the correct answer
# rather than a blind spot -- no method row calls `ew_k.log10_2()` yet, because the methods
# are unmigrated, so changing a constant cannot change a signature. The CONSTANTS are gated
# by ew-consts-gate.sh, which is a bit-pattern gate and turns red on exactly that mutation.
# Two gates, two claims: shapes here, values there. A single gate that claimed both would
# have to be green on the constant until a method used it, which is the same
# untested-premise shape this file exists to end.
set -e
cd "$(dirname "$0")/../.."
GT=.agents/slop/ew-gate
mkdir -p "$GT"

ROWS=75
DIVERGES='ew_promo_nc'

check_line=$(./bin/bend tinybendygrad/mixin/elementwise.bend --check-only | head -1)
if [ "$check_line" != "ALL PROOFS CHECK" ]; then
  echo "ew-gate: --check-only says '$check_line'" >&2
  exit 1
fi

run_lane() {  # $1 = output file, rest = the bend invocation
  out=$1; shift
  tries=0
  while [ "$tries" -lt 25 ]; do
    tries=$((tries + 1))
    if "$@" 2> "$out.err" | grep '^ew_' > "$out.tmp" && [ -s "$out.tmp" ]; then
      mv "$out.tmp" "$out"
      return 0
    fi
  done
  echo "ew-gate: lane produced 0 ew_ rows after $tries tries:" >&2
  cat "$out.err" >&2
  return 1
}

.venv/bin/python .agents/slop/ew-gate.py > "$GT-py.txt"

run_lane "$GT-bd.txt" ./bin/bend tinybendygrad/mixin/elementwise.bend
./bin/bend tinybendygrad/mixin/elementwise.bend -o "$GT.bin"
run_lane "$GT-bn.txt" "$GT.bin"

# A REGEX ALTERNATION and not a comma list, for the reason ops-rnd-gate.sh records:
# `grep -v "^a,b="` matches nothing and the gate then diffs a row it meant to drop.
grep -vE "^($DIVERGES)=" "$GT-bd.txt" > "$GT-bd.sub"
grep -vE "^($DIVERGES)=" "$GT-bn.txt" > "$GT-bn.sub"

# THE ROW COUNT IS ASSERTED, not assumed: 71 on all three. A lane that lost rows to a rename
# would otherwise produce a SMALLER diff, and a smaller diff is not a passing test.
n=$(wc -l < "$GT-py.txt" | tr -d ' ')
[ "$n" = "$ROWS" ] || { echo "ew-gate: the oracle has $n rows, expected $ROWS" >&2; exit 1; }
for f in "$GT-py.txt" "$GT-bd.sub" "$GT-bn.sub"; do
  m=$(wc -l < "$f" | tr -d ' ')
  [ "$m" = "$ROWS" ] || { echo "ew-gate: $f has $m rows, expected $ROWS" >&2; exit 1; }
done

diff "$GT-py.txt" "$GT-bd.sub" || { echo "ew-gate: DISAGREE (interpreted)" >&2; exit 1; }
diff "$GT-py.txt" "$GT-bn.sub" || { echo "ew-gate: DISAGREE (native)" >&2; exit 1; }

# AND THE DIVERGENT ROW MUST BE THERE. A row that went missing is not a divergence, it is a
# hole, and the two are indistinguishable from the diff alone.
grep -qE "^($DIVERGES)=" "$GT-bd.txt" || { echo "ew-gate: $DIVERGES is MISSING from the port" >&2; exit 1; }
grep -qE "^($DIVERGES)=" "$GT-bn.txt" || { echo "ew-gate: $DIVERGES is MISSING from the native lane" >&2; exit 1; }
# and the oracle must NOT have grown a second one, or `DIVERGES` is stale and the exclusion
# is excluding nothing while claiming to exclude something.
if grep -qE "^($DIVERGES)=" "$GT-py.txt"; then
  echo "ew-gate: the oracle now emits $DIVERGES, so DIVERGES is STALE" >&2
  exit 1
fi

# The two halves the oracle DOES check for that graph must be present on the port side, or
# the exclusion above has quietly removed the whole claim rather than its unfalsifiable part.
for nm in ew_dt_promo_nc ew_op_promo_nc; do
  grep -q "^$nm=" "$GT-py.txt" || { echo "ew-gate: the oracle lost $nm" >&2; exit 1; }
  grep -q "^$nm=" "$GT-bd.txt" || { echo "ew-gate: the port lost $nm" >&2; exit 1; }
done

echo "ew-gate: 75 rows, 3 lanes identical, 1 documented divergence ($DIVERGES)"
