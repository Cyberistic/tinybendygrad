#!/bin/sh
# The gate for the rule-body unit. THREE LANES, and the comparison is on whole
# `name=value` LINES -- never on row NAMES (agent-core.md: a name-comparing
# harness reported 0 for all 30 mutations in one unit and 0 for all 68 in
# another).
#
#   lane bd   ./bin/bend tinybendygrad/schedule/__init__.bend
#   lane bn   the native build, if the tree has one
#   lane py   python3 .agents/slop/schedule-bodies/sb-oracle.py
#
# The BASE lane is the 81 rows the previous unit left, and they must be
# BYTE-IDENTICAL. `--plant` / `--disarm` make a throw-away COPY of the tree --
# never the live one -- because a $TMPDIR scratch copy cannot resolve a relative
# import, which produced 22 phantom blind spots in one unit.
set -eu
cd "$(dirname "$0")/../../.."
D=.agents/slop/schedule-bodies
PORT=tinybendygrad/schedule/__init__.bend
BASE=$D/BEFORE-rows.txt

substrate() {
  h=$(sha256sum tinybendygrad/helpers.bend | cut -d' ' -f1)
  o=$(sha256sum tinybendygrad/uop/ops.bend  | cut -d' ' -f1)
  echo "helpers=$h ops=$o"
}

if [ "${1:-}" = "--substrate" ]; then substrate; exit 0; fi

./bin/bend $PORT > $D/rows-bd.txt 2> $D/rows-bd.err || true
echo "== substrate: $(substrate)"
echo "== bend stderr:"; cat $D/rows-bd.err
if [ ! -s $D/rows-bd.txt ]; then
  echo "== VERDICT INCONCLUSIVE: the port emitted NO ROWS. A bend that dies on a"
  echo "   def it does not own produces no line to count, so a row census cannot"
  echo "   report it -- this is the dead-arm instrument gap."
  exit 3
fi

# 1. the regression floor: the 81 rows the previous unit left
if [ -f $BASE ]; then
  if grep -F -x -f $BASE $D/rows-bd.txt > /dev/null 2>&1; then
    echo "== BASE 81 rows: byte-identical (all present)"
  else
    echo "== BASE 81 rows: *** NOT ALL PRESENT ***"
    grep -F -x -v -f $BASE $D/rows-bd.txt | head -20
  fi
  echo "== base rows: $(wc -l < $BASE)   port rows: $(wc -l < $D/rows-bd.txt)"
fi

# 2. the new rows against CPython, on whole lines
PYTHONPATH=. python3 $D/sb-oracle.py > $D/sb-oracle.txt 2>$D/sb-oracle.err || {
  echo "== VERDICT INCONCLUSIVE: the CPython lane failed"; cat $D/sb-oracle.err; exit 3; }
python3 $D/sb-diff.py $D/sb-oracle.txt $D/rows-bd.txt