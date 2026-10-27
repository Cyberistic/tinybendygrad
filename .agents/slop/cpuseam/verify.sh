#!/bin/sh
# verify.sh -- THE WHOLE MEASUREMENT, IN ONE COMMAND, REPEATABLE.
#
#   sh .agents/slop/cpuseam/verify.sh
#
# IT RUNS, IN ORDER:
#   1. `./bin/bend <file> --check-only` ON THE PORT's TWO FILES.
#   2. THE THREE JS-LANE BUILDS (THE PORT's RENDERER, THE PORT's RELOCATOR AND
#      THE PORT's OWN DEVICE LANE).
#   3. `pipeline.py`, WHICH RUNS THE PORT's RENDERER, `cc`s IT WITH UPSTREAM's
#      OWN ARGV, RUNS THE PORT's OWN `jit_loader`, MMAPS AND CALLS, AND COMPARES
#      WITH CPython's OWN CPU DEVICE -- AND THEN RUNS THE SAME FOUR STAGES WITH
#      THE PLANT.
#
# ⇒ THE PLANT'S ROWS MUST BE RED. A PLANT THAT IS GREEN IS A FAILED MEASUREMENT
# AND THIS SCRIPT SAYS SO.
#
# ⇒ WHY THE JS LANE: THE NATIVE LANE'S BINARY CANNOT EXEC ON THIS MACHINE --
# EVERY LOCALLY-BUILT BINARY IS KILLED BY THE KERNEL's `AppleSystemPolicy`
# ("Security policy would not allow process"), AND `DevToolsSecurity -status`
# SAYS "Developer mode is currently disabled". THE REPORT HAS THE EVIDENCE.
# THE PORT's BEND CODE IS THE SAME CODE IN BOTH LANES.
set -e
HERE=$(dirname "$0")
ROOT=$(cd "$HERE/../../.." && pwd)
BUN=${BUN:-/Users/cyberistic/.bun/bin/bun}

cd "$ROOT"

echo "== 1. the port's files =="
./bin/bend tinybendygrad/renderer/cstyle.bend --check-only || exit 1
# `ops_cpu.bend` EXITS 1 WITH ONE LINE: ITS TWO EFFECTS ARE FOREIGN CODE. THAT
# IS THE SAME SHAPE AS `tinybendygrad/sz.bend`, AND IT IS NOT A FAILURE.
./bin/bend tinybendygrad/runtime/ops_cpu.bend --check-only 2>&1 | grep -q "2 defs rely on unsafe or foreign code" \
  || { echo "ops_cpu.bend: the foreign-code line is gone"; exit 1; }
echo "ops_cpu.bend: 2 foreign-code effects, as expected"

echo "== 2. the js-lane builds =="
./bin/bend "$HERE/render.bend" -o /tmp/render.js
./bin/bend "$HERE/relocate.bend" -o /tmp/relocate.js
./bin/bend "$HERE/launch.bend" -o /tmp/launch.js
./bin/bend "$HERE/launch.bend" -o /tmp/launch

echo "== 3. the measurement, and the plant =="
.venv/bin/python "$HERE/pipeline.py"
