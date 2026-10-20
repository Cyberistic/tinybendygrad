#!/bin/sh
# COLLECT EVERY MEASUREMENT OF THIS UNIT, IN ORDER, AND REBUILD `cases.rows`.
#
#   1. `.venv/bin/python cpython_oracle.py`  -> cpython.out     (CPython's ANSWERS)
#   2. `.venv/bin/python mkvariants.py`      -> THE FOUR ABLATION TREES
#   3. `./bin/bend probe*.bend`              -> port_*.out      (THE PORT'S ANSWERS)
#   4. `./bin/bend scratch*/nn/layers.bend`  -> rows_*.out      (THE FILE'S OWN ROWS)
#   5. `.venv/bin/python mkrows.py`          -> cases.rows
#
# EVERY COMMAND IS SEQUENTIAL, CHEAP, AND UNDER 20 s. NOTHING HERE RUNS A GATE,
# AND NOTHING HERE TOUCHES THE REAL TREE.
#
# RUN FROM THE REPO ROOT:  sh .agents/slop/dw3/collect.sh

set -e
HERE=.agents/slop/dw3

.venv/bin/python $HERE/cpython_oracle.py > $HERE/cpython.out 2>&1
echo "cpython: rc=$?"

.venv/bin/python $HERE/mkvariants.py > $HERE/variants.out 2>&1
echo "variants: rc=$?"

for v in "" _g _gw _gwo _fix; do
  ./bin/bend $HERE/probe$v.bend > $HERE/port$v.out 2>&1
  echo "probe$v: rc=$?"
done

for v in scratch scratchg scratchgw scratchgwo scratchfix; do
  ./bin/bend $HERE/$v/nn/layers.bend > $HERE/rows_$v.out 2>&1
  echo "rows_$v: rc=$?"
done

.venv/bin/python $HERE/mkrows.py $HERE/cases.rows
echo "cases.rows: rc=$?"
