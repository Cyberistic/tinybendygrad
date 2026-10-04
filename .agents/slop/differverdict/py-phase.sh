#!/bin/sh
# Phase 2 only: the PYTHON side, into an isolated snapshot. Wipe D first so no shell-era
# file can be counted as produced by the side being measured.
set -u
cd "$(dirname "$0")/../../.." || exit 2
OUT=.agents/slop/differverdict
PY=.venv/bin/python
rm -rf runs/graphcmp/D; mkdir -p runs/graphcmp/D
env -u PYTHONPATH $PY checks/differ.py run > "$OUT/py-stdout.txt" 2> "$OUT/py-stderr.txt"
echo "python rc=$?  artifacts=$(find runs/graphcmp/D -type f | wc -l | tr -d ' ')"
rm -rf "$OUT/py-D"; cp -R runs/graphcmp/D "$OUT/py-D"
echo "== COMPARE =="
$PY "$OUT/cmp.py" "$OUT/shell-D" "$OUT/py-D" > "$OUT/CMP.txt" 2>&1
echo "cmp rc=$?"