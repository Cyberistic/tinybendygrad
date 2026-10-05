#!/bin/sh
# mixin-op-gate.sh -- run BOTH lanes of tinybendygrad/mixin/op.bend and diff them against
# the CPython oracle. Every step is `set -e`, so the script fails loudly.
#
#   sh .agents/slop/mixin-op-gate.sh
#
# THREE LANES and they must agree byte for byte:
#
#   py    CPython, .venv/bin/python .agents/slop/mixin-op-gate.py
#   bend  the interpreted lane, ./bin/bend tinybendygrad/mixin/op.bend
#   bn    the NATIVE lane, compiled with -o and then run
#
# `--check-only` is run first: it is the fastest way to find a proof failure and it
# needs no device either.
#
# FOUR ROWS ARE BEND-ONLY -- `rop_gap`, `exp_cast`, `commit_weak`, `bin_promote` -- and
# they are filtered BY NAME. They name a refusal or a defect rather than a graph, so
# CPython cannot be asked for them; filtering by name rather than by position is what
# keeps a row that MOVES from being silently dropped.
set -e
cd "$(dirname "$0")/../.."

FOLD=/tmp/mop
BEND_ONLY='rop_gap|exp_cast|commit_weak|bin_promote'

./bin/bend tinybendygrad/mixin/op.bend --check-only

.venv/bin/python .agents/slop/mixin-op-gate.py | grep -vE "^($BEND_ONLY)=" > $FOLD.py
./bin/bend tinybendygrad/mixin/op.bend | grep -vE "^($BEND_ONLY)=" > $FOLD.bd
./bin/bend tinybendygrad/mixin/op.bend -o $FOLD.bin
$FOLD.bin | grep -vE "^($BEND_ONLY)=" > $FOLD.bn

diff $FOLD.py $FOLD.bd
diff $FOLD.py $FOLD.bn
echo "mixin-op-gate: $(wc -l < $FOLD.py | tr -d ' ') shared rows, 3 lanes identical"