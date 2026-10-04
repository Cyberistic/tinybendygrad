#!/bin/sh
# Drive both sides into isolated snapshot dirs, then compare. Shell out to .venv/bin/python.
set -u
cd "$(dirname "$0")/../../.." || exit 2
OUT=.agents/slop/differverdict
PY=.venv/bin/python
mkdir -p "$OUT"

# The real runs/graphcmp/D is the one shared output dir both drivers write. Snapshot whatever
# is there first so nothing is lost, and WIPE it between the two sides so a stale file from
# the other driver cannot be counted as produced by the side being measured.
if [ -d runs/graphcmp/D ]; then
  (cd runs/graphcmp/D && find . -type f | sort | xargs -I{} sh -c 'mkdir -p "$0/$(dirname {})" && cp "{}" "$0/{}"' "$OUT/pre-existing-D") 2>/dev/null
fi

echo "== ORACLE (shell) =="
rm -rf runs/graphcmp/D; mkdir -p runs/graphcmp/D
GCMP_REPO="$PWD" sh .agents/slop/diffpy/oracle-run.sh > "$OUT/shell-stdout.txt" 2> "$OUT/shell-stderr.txt"
echo "oracle rc=$?  artifacts=$(find runs/graphcmp/D -type f | wc -l | tr -d ' ')"
rm -rf "$OUT/shell-D"; cp -R runs/graphcmp/D "$OUT/shell-D"

echo "== PYTHON =="
rm -rf runs/graphcmp/D; mkdir -p runs/graphcmp/D
env -u PYTHONPATH $PY checks/differ.py run > "$OUT/py-stdout.txt" 2> "$OUT/py-stderr.txt"
echo "python rc=$?  artifacts=$(find runs/graphcmp/D -type f | wc -l | tr -d ' ')"
rm -rf "$OUT/py-D"; cp -R runs/graphcmp/D "$OUT/py-D"

echo "== COMPARE =="
$PY "$OUT/cmp.py" "$OUT/shell-D" "$OUT/py-D"
echo "cmp rc=$?"