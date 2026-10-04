#!/bin/sh
# tensor.bend's gate, both lanes, and the diff.
#
#   sh .agents/slop/tensor-gate.sh
#
# Lanes: CPython builds the lazy graph and prints the SIGNATURE of each one; Bend builds
# the same graphs in the arena and prints the same strings. Nothing is executed, so the
# oracle needs no device.
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"

echo "--- check-only"
./bin/bend tinybendygrad/tensor.bend --check-only

echo "--- CPython lane"
.venv/bin/python .agents/slop/tensor-gate.py > /tmp/tensor-py.txt
cat /tmp/tensor-py.txt

echo "--- Bend lane (interpreted)"
./bin/bend tinybendygrad/tensor.bend > /tmp/tensor-bd.txt
cat /tmp/tensor-bd.txt

echo "--- Bend lane (native)"
./bin/bend tinybendygrad/tensor.bend -o /tmp/tensor-native >/dev/null 2>&1
/tmp/tensor-native > /tmp/tensor-bd-native.txt
if diff -q /tmp/tensor-bd.txt /tmp/tensor-bd-native.txt >/dev/null; then
  echo "interpreted == native: byte identical"
else
  echo "LANES DIFFER:"; diff /tmp/tensor-bd.txt /tmp/tensor-bd-native.txt
fi

echo "--- diff against CPython, SHARED rows only"
# `tn_rop_gap` is a DESIGNED disagreement (WALL 5) and `tn_arena`, `tn_param_old` and
# `tn_holds` have no CPython counterpart. All four are listed here rather than filtered
# silently, so the exclusion is visible on BOTH sides.
EXCL='-e ^tn_rop_gap= -e ^tn_arena= -e ^tn_param_old= -e ^tn_holds='
grep -v $EXCL /tmp/tensor-py.txt > /tmp/tensor-py-shared.txt
grep -v $EXCL /tmp/tensor-bd.txt > /tmp/tensor-bd-shared.txt
if diff /tmp/tensor-py-shared.txt /tmp/tensor-bd-shared.txt; then
  echo "SHARED ROWS IDENTICAL ($(wc -l < /tmp/tensor-bd-shared.txt | tr -d ' ') rows)"
fi

echo "--- the ONE designed disagreement, and the three Bend-only rows"
echo "py:"; grep $EXCL /tmp/tensor-py.txt
echo "bend:"; grep $EXCL /tmp/tensor-bd.txt
