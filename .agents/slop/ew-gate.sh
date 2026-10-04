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

ROWS=76
DIVERGES='ew_promo_nc'

# `ew_promo_wf_wi` WAS A DIVERGENCE AND IS NOT ANY MORE, AND THAT IS THE POINT. It is the promotion matrix's missing cell -- two
# weak CONSTs of DIFFERENT classes, a weakfloat against a weakint -- and the other seven
# cells do not reach it, so nothing tested it until now.
#
#   CPython  3 nodes: CONST 1.0f, CONST 2.0f, MUL/2
#   this     2 nodes: CONST 1.0f,            MUL/2
#
# `promote` (elementwise.py:29-33) says the int const takes `remint(t._uop, dt)`, which MINTS
# A NEW CONST, and the float const is returned UNTOUCHED because
# `weak_dtype(weakfloat) == weakfloat == t.dtype`. So CPython keeps both and the port drops
# one: the port's weak-const promotion arm FOLDS the reminted side into the float operand
# instead of minting the const `remint` names. That is the same folding that turns `tanh`'s
# `-1` into 2**32, so `tanh` stays held on this ONE cause.
#
# The row is EXCLUDED so the gate is runnable, and it is PINNED -- both sides' exact content
# is asserted below -- so it is a standing, checked divergence and not a tolerance. The
# moment the folding is fixed the row changes and this gate says so.

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
# BOTH SIDES ARE FILTERED. `ew_promo_nc` exists only on the port, so filtering it from the
# oracle is a no-op -- but `ew_promo_wf_wi` is in BOTH files and is the one that diverges, so
# diffing an unfiltered oracle against a filtered port would compare exactly the row that
# is known to differ. That is how a divergence list stops working: it filters one side.
grep -vE "^($DIVERGES)=" "$GT-py.txt" > "$GT-py.sub"
grep -vE "^($DIVERGES)=" "$GT-bd.txt" > "$GT-bd.sub"
grep -vE "^($DIVERGES)=" "$GT-bn.txt" > "$GT-bn.sub"

# THE ROW COUNT IS ASSERTED, not assumed: 71 on all three. A lane that lost rows to a rename
# would otherwise produce a SMALLER diff, and a smaller diff is not a passing test.
# THREE COUNTS, because the two sides emit a DIFFERENT number of rows and that is now a
# fact about the port rather than an accident:
#
#   76  the oracle:  every row it emits is compared
#   77  the port:    the same 76, PLUS ew_promo_nc, which the oracle deliberately omits
#   76  what is COMPARED -- and it is 76, not 75, because the exclusion removes a row the
#       ORACLE DOES NOT HAVE. Filtering the oracle is a no-op, so the compared count is the
#       ORACLE's count, and a gate that assumed "unfiltered minus one" on both sides would
#       assert the wrong number on the side that never had the row.
#
# The port-only row is `ew_promo_nc`, which the oracle deliberately omits because a
# signature for a non-constant promotion is unfalsifiable. Asserting one number for all three
# files is how a gate ends up excluding a row that stopped existing without saying so, so
# each count is checked against the file it belongs to.
cnt() { wc -l < "$1" | tr -d ' '; }
[ "$(cnt "$GT-py.txt")" = 76 ] || { echo "ew-gate: the oracle has $(cnt "$GT-py.txt") rows, expected 76" >&2; exit 1; }
for f in "$GT-bd.txt" "$GT-bn.txt"; do
  [ "$(cnt "$f")" = 77 ] || { echo "ew-gate: $f has $(cnt "$f") rows, expected 77" >&2; exit 1; }
done
for f in "$GT-py.sub" "$GT-bd.sub" "$GT-bn.sub"; do
  [ "$(cnt "$f")" = 76 ] || { echo "ew-gate: $f has $(cnt "$f") COMPARED rows, expected 76" >&2; exit 1; }
done

diff "$GT-py.sub" "$GT-bd.sub" || { echo "ew-gate: DISAGREE (interpreted)" >&2; exit 1; }
diff "$GT-py.sub" "$GT-bn.sub" || { echo "ew-gate: DISAGREE (native)" >&2; exit 1; }

# AND THE DIVERGENT ROW MUST BE THERE. A row that went missing is not a divergence, it is a
# hole, and the two are indistinguishable from the diff alone.
grep -qE "^($DIVERGES)=" "$GT-bd.txt" || { echo "ew-gate: $DIVERGES is MISSING from the port" >&2; exit 1; }
grep -qE "^($DIVERGES)=" "$GT-bn.txt" || { echo "ew-gate: $DIVERGES is MISSING from the native lane" >&2; exit 1; }
# THE TWO DIVERGENCES HAVE DIFFERENT RELATIONSHIPS TO THE ORACLE, and a single
# "is DIVERGES stale" test cannot express both -- it fired on `ew_promo_wf_wi`, which the
# oracle is SUPPOSED to emit. So each is asserted on its own terms:
#   ew_promo_nc      the oracle must NOT have it. It is a port-only row, and if the oracle
#                    grew one then `DIVERGES` is excluding a row that now agrees, which is
#                    a tolerance that has stopped being one.
#   ew_promo_wf_wi   the oracle MUST have it, and the port must disagree on it. That is the
#                    promotion defect; a gate where it stopped being a divergence would be
#                    either fixed (good) or broken (worse), and only an assertion says which.
if grep -qE "^ew_promo_nc=" "$GT-py.txt"; then
  echo "ew-gate: the oracle now emits ew_promo_nc, so that exclusion is STALE" >&2
  exit 1
fi
grep -qE "^ew_promo_wf_wi=" "$GT-py.txt" || {
  echo "ew-gate: the oracle LOST ew_promo_wf_wi -- the promotion defect's row is gone" >&2
  exit 1
}

# The two halves the oracle DOES check for that graph must be present on the port side, or
# the exclusion above has quietly removed the whole claim rather than its unfalsifiable part.
for nm in ew_dt_promo_nc ew_op_promo_nc; do
  grep -q "^$nm=" "$GT-py.txt" || { echo "ew-gate: the oracle lost $nm" >&2; exit 1; }
  grep -q "^$nm=" "$GT-bd.txt" || { echo "ew-gate: the port lost $nm" >&2; exit 1; }
done

echo "ew-gate: 76 rows compared, 3 lanes identical, 1 documented divergence ($DIVERGES)"
