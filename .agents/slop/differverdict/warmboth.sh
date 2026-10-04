#!/bin/sh
# THE SAME COMPARISON, ON A WARM SUBSTRATE, so the VERDICT and DENOMINATOR lines are real
# reports rather than two identical `rc=1` failures. Same from-empty discipline as both.sh.
set -u
W=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/.agents/slop/differverdict/warm
S=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/.agents/slop/differverdict
cd "$W" || exit 2
snap() { rm -rf "../warm-$1"; mkdir -p "../warm-$1"; cp runs/graphcmp/D/* "../warm-$1"/ 2>/dev/null; }
wipe() { rm -rf runs/graphcmp/D; mkdir -p runs/graphcmp/D; }

echo "### ORACLE, warm, from an EMPTY D/"
wipe
GCMP_REPO="$PWD" sh .agents/slop/diffpy/oracle-run.sh > /dev/null 2>&1
snap oracle
echo "oracle wrote $(ls ../warm-oracle | wc -l | tr -d ' ') files"

echo "### PYTHON, warm, from an EMPTY D/"
wipe
env -u PYTHONPATH .venv/bin/python checks/differ.py run > /dev/null 2>&1
snap python
echo "python wrote $(ls ../warm-python | wc -l | tr -d ' ') files"