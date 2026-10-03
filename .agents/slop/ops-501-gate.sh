#!/bin/sh
# ops-501-gate.sh -- the CPython lane for the ops.py:501-1928 unit of
# `tinybendygrad/uop/ops.bend`: the base family, the movers, `split_uop`.
#
#   sh .agents/slop/ops-501-gate.sh
#
# THREE LANES and they must agree byte for byte:
#
#   py    CPython, .venv/bin/python .agents/slop/ops-501-oracle.py
#   bd    the interpreted lane, ./bin/bend tinybendygrad/uop/ops.bend
#   bn    the NATIVE lane, compiled with -o and then run
#
# `--check-only` runs first and its FIRST LINE is read, never its status: it exits
# 1 on a file with no unfilled laws too. `set -e` is deliberately not applied to
# it, and the failure is a first line that is not `ALL PROOFS CHECK`.
#
# `TG_TREE` picks the tree, so the same script diffs the port against the vendored
# pin and against upstream, and the two answers differ in exactly the rows upstream
# moved:
#
#   sh .agents/slop/ops-501-gate.sh
#   TG_TREE=. sh .agents/slop/ops-501-gate.sh
#
# THE FILTER IS BY PREFIX, NEVER BY POSITION. Every row of this unit starts `s5_`,
# so `grep '^s5_'` selects the block and nothing else. Filtering by position is
# what silently drops a row that MOVED, and a row that moved is the whole signal.
set -e
cd "$(dirname "$0")/../.."

F=.agents/slop/oracles/ops501

# Read the FIRST line. `SOME PROOFS FAIL` naming anything other than dtype.bend's
# fourteen unfilled laws is the failure.
check_line=$(./bin/bend tinybendygrad/uop/ops.bend --check-only | head -1)
if [ "$check_line" != "ALL PROOFS CHECK" ]; then
  echo "ops-501-gate: --check-only says '$check_line'" >&2
  exit 1
fi

.venv/bin/python .agents/slop/ops-501-oracle.py | grep '^s5_' > "$F-py.txt"
./bin/bend tinybendygrad/uop/ops.bend | grep '^s5_' > "$F-bd.txt"
./bin/bend tinybendygrad/uop/ops.bend -o "$F.bin"
"$F.bin" | grep '^s5_' > "$F-bn.txt"

# The row NAMES must agree before the values do, and separately: a row that exists
# on one side only is a different failure from a row whose value differs, and a
# value-only diff hides the first inside the second.
for lane in py bd; do
  sed 's/=.*//' "$F-$lane.txt" | sort > "$F-$lane.names"
done
if ! diff "$F-py.names" "$F-bd.names"; then
  echo "ops-501-gate: the two lanes disagree on WHICH ROWS exist" >&2
  exit 1
fi

if ! diff "$F-py.txt" "$F-bd.txt"; then
  echo "ops-501-gate: DISAGREE (interpreted)" >&2
  exit 1
fi
if ! diff "$F-py.txt" "$F-bn.txt"; then
  echo "ops-501-gate: DISAGREE (native)" >&2
  exit 1
fi

echo "ops-501-gate: $(wc -l < "$F-py.txt" | tr -d ' ') rows, 3 lanes identical"
