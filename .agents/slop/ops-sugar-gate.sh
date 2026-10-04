#!/bin/sh
# ops-sugar-gate.sh -- the CPython lane for the sugar constructors of
# `tinybendygrad/uop/ops.bend` (ops.py:565-674): body, is_inline_call,
# has_unbound_outputs, index, store, ins, wmma, reduce, cconst, invalid, ufix.
#
#   sh .agents/slop/ops-sugar-gate.sh
#
# THREE LANES and they must agree byte for byte:
#
#   py    CPython, .venv/bin/python .agents/slop/ops-sugar-oracle.py
#   bd    the interpreted lane, ./bin/bend tinybendygrad/uop/ops.bend
#   bn    the NATIVE lane, compiled with -o and then run
#
# `--check-only` runs first and its FIRST LINE is read, never its status: it exits 1
# on a file with no unfilled laws too, so `set -e` is deliberately not applied to it
# and the failure is a first line that is not `ALL PROOFS CHECK`.
#
# `TG_TREE` picks the tree, so the same script diffs the port against the vendored
# pin and against upstream, and the two answers differ in exactly the rows upstream
# moved:
#
#   sh .agents/slop/ops-sugar-gate.sh
#   TG_TREE=. sh .agents/slop/ops-sugar-gate.sh
#
# THE FILTER IS BY PREFIX, NEVER BY POSITION. Every row of this unit starts `sg_`,
# so `grep '^sg_'` selects the block and nothing else. Filtering by position is what
# silently drops a row that MOVED, and a row that moved is the whole signal.
#
# WHY A SEPARATE SCRIPT AND NOT A BLOCK OF `ops-gate.sh`. `ops-gate.sh` diffs the
# whole file against `ops-oracle.py`, whose row ORDER is a contract for the axis
# unit. This unit is 39 rows of a different subject with a different fixture arena,
# and putting them in that oracle would make that file's order this unit's problem.
# `ops-oracle.py` lists this family as `#bend_only_sg` with the reason, so the
# shared gate filters it and the shared gate's own rows are untouched.
set -e
cd "$(dirname "$0")/../.."

F=.agents/slop/oracles/opssugar

check_line=$(./bin/bend tinybendygrad/uop/ops.bend --check-only | head -1)
if [ "$check_line" != "ALL PROOFS CHECK" ]; then
  echo "ops-sugar-gate: --check-only says '$check_line'" >&2
  exit 1
fi

.venv/bin/python .agents/slop/ops-sugar-oracle.py | grep '^sg_' > "$F-py.txt"
./bin/bend tinybendygrad/uop/ops.bend | grep '^sg_' > "$F-bd.txt"
./bin/bend tinybendygrad/uop/ops.bend -o "$F.bin"
"$F.bin" | grep '^sg_' > "$F-bn.txt"

# The row NAMES must agree before the values do, and separately: a row that exists
# on one side only is a different failure from a row whose value differs, and a
# value-only diff hides the first inside the second.
for lane in py bd; do
  sed 's/=.*//' "$F-$lane.txt" | sort > "$F-$lane.names"
done
if ! diff "$F-py.names" "$F-bd.names"; then
  echo "ops-sugar-gate: the two lanes disagree on WHICH ROWS exist" >&2
  exit 1
fi

if ! diff "$F-py.txt" "$F-bd.txt"; then
  echo "ops-sugar-gate: DISAGREE (interpreted)" >&2
  exit 1
fi
if ! diff "$F-py.txt" "$F-bn.txt"; then
  echo "ops-sugar-gate: DISAGREE (native)" >&2
  exit 1
fi

echo "ops-sugar-gate: $(wc -l < "$F-py.txt" | tr -d ' ') rows, 3 lanes identical"
