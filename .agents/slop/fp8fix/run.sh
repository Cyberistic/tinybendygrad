#!/bin/sh
# FX-7 -- base, disarms, plants, fix, sweep. IN THAT ORDER: a disarm runs BEFORE the
# plant it belongs to, so a disarm cannot be "passing" because the plant already moved
# things. Everything happens under $TMPDIR; the live tree is READ, never planted in.
#
#   sh run.sh gate     the 82,978-row gate over all ten trees          (~1 minute)
#   sh run.sh sweep    the exhaustive subnormal sweep, FIX and BASE    (~25 min, both
#                      trees concurrently -- one sweep is 234,830,338 CPython calls)
#   sh run.sh          both
set -e
REPO=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$REPO"
HERE=.agents/slop/fp8fix
WHAT=${1:-all}

T=$(mktemp -d "${TMPDIR:-/tmp}/fp8fix.XXXXXX")
echo "TREE $T   live md5 $(md5 -q tinybendygrad/runtime/dtype.c)"
BASE_CODE_MD5=$(python3 -c 'import sys;sys.path.insert(0,"'"$HERE"'");import plants;print(plants.BASE_CODE_MD5)')

# --- BASE: the file as it was, reverse-applied, and PROVEN by md5 --------------------
mkdir -p "$T/BASE"
python3 "$HERE/plants.py" BASE "$T/BASE" >/dev/null || { echo "BASE RECONSTRUCTION FAILED"; exit 1; }
echo "BASE whole-file md5 $(md5 -q "$T/BASE/dtype.c")  code md5 VERIFIED against $BASE_CODE_MD5"

# --- the FIX tree is the live file, COPIED so nothing under $TMPDIR writes to the repo
mkdir -p "$T/FIX"
cp tinybendygrad/runtime/dtype.c "$T/FIX/dtype.c"

for v in A-plant A-plant-ge A-disarm C-plant C-disarm D-plant D-disarm B-plant; do
  mkdir -p "$T/$v"
  python3 "$HERE/plants.py" "$v" "$T/$v" >/dev/null
done

for v in BASE FIX A-plant A-plant-ge A-disarm C-plant C-disarm D-plant D-disarm B-plant; do
  python3 "$HERE/build.py" "$T/$v" --src "$T/$v/dtype.c" >/dev/null || exit 1
  echo "built $v"
done
echo "$T" > "${TMPDIR:-/tmp}/fp8fix.last.tree"

# --- THE PREDICTIONS, BEFORE ANY PLANT RUNS -----------------------------------------
python3 "$HERE/gate.py" --predict

if [ "$WHAT" = gate ] || [ "$WHAT" = all ]; then
  # FIX FIRST: the brief's question is "what did the fix move", and every plant and
  # disarm is then compared against the fixed file too.
  python3 "$HERE/gate.py" "$T/FIX" "$T/BASE" "$T/A-plant" "$T/A-plant-ge" "$T/A-disarm" \
      "$T/C-plant" "$T/C-disarm" "$T/D-plant" "$T/D-disarm" "$T/B-plant" \
      --no-sweep --derived
fi

if [ "$WHAT" = sweep ] || [ "$WHAT" = all ]; then
  echo ""
  echo "=== SWEEP: exhaustive over each format's subnormal window, BOTH signs ==="
  python3 "$HERE/gate.py" "$T/FIX" --no-sweep >/dev/null 2>&1 || true
  python3 "$HERE/gate.py" "$T/FIX" > "$T/sweep-fix.txt" 2>&1 &
  P1=$!
  python3 "$HERE/gate.py" "$T/BASE" > "$T/sweep-base.txt" 2>&1 &
  P2=$!
  wait $P1 $P2
  grep -E '^(==|  S\[)' "$T/sweep-base.txt" | sed 's/^/BASE /'
  grep -E '^(==|  S\[)' "$T/sweep-fix.txt"  | sed 's/^/FIX  /'
fi
echo "TREE $T"