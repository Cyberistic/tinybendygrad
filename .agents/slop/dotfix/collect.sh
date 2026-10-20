#!/bin/sh
# THE COLLECTOR. IT RUNS THE THREE INSTRUMENTS AND WRITES `cases.rows`.
#
#   1. `.venv/bin/python cpython_oracle.py` -- CPython's ANSWERS.
#   2. `./bin/bend probe.bend`      -- THE PORT BEFORE THE FIX.
#   3. `./bin/bend probe_fix.bend`  -- THE PORT AFTER THE FIX.
#
# AND THE PORT'S OWN ROWS (`scratch/nn/layers.bend` and `scratchfix/nn/layers.bend`),
# WHICH ARE THE FILE'S OWN `nn_row_dot` / `nn_row_linear` ASSERTIONS.
#
# NOTHING IS TRANSCRIBED BY HAND. EVERY CELL OF `cases.rows` IS A LINE THIS
# SCRIPT SAW. RUN FROM THE REPO ROOT:  sh .agents/slop/dotfix/collect.sh

set -e
D=.agents/slop/dotfix
R=$D/cases.rows

.venv/bin/python $D/cpython_oracle.py > $D/cpython.out 2>&1
./bin/bend $D/probe.bend > $D/port_before.out 2>&1
./bin/bend $D/probe_fix.bend > $D/port_after.out 2>&1
./bin/bend $D/scratch/nn/layers.bend > $D/rows_before.out 2>&1
./bin/bend $D/scratchfix/nn/layers.bend > $D/rows_after.out 2>&1

.venv/bin/python $D/mkrows.py $R

echo "WROTE $R"
