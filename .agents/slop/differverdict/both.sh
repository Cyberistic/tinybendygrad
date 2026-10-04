#!/bin/sh
# THE COMPARISON, DONE HONESTLY: both drivers start from an EMPTY `runs/graphcmp/D`, because
# "which artifacts did each produce" is the claim, and a leftover file from HEAD's committed
# `runs/graphcmp/D/` would answer it with the archive instead of with the driver.
#
# `git archive HEAD` ships `runs/graphcmp/D/` (154 files). Left in place, the Python driver
# appears to write `D6-srcswap-*.txt` -- files it NEVER produces -- purely because the archive
# left them there. That is the exact shape of the "A directory carrying a PASS-shaped file no
# command produces" defect the oracle's own step 14 exists to prevent.
set -u
cd "$(dirname "$0")/root" || exit 2
snap() { rm -rf "../$1"; mkdir -p "../$1"; cp runs/graphcmp/D/* "../$1"/ 2>/dev/null; }
wipe() { rm -rf runs/graphcmp/D; mkdir -p runs/graphcmp/D; }

echo "### ORACLE from an EMPTY D/"
wipe
GCMP_REPO="$PWD" sh .agents/slop/diffpy/oracle-run.sh > /dev/null 2>&1
snap oracle-D
echo "oracle wrote $(ls ../oracle-D | wc -l | tr -d ' ') files"

echo "### PYTHON from an EMPTY D/"
wipe
env -u PYTHONPATH .venv/bin/python checks/differ.py run > /dev/null 2>&1
snap python-D
echo "python wrote $(ls ../python-D | wc -l | tr -d ' ') files"