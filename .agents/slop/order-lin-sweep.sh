#!/bin/zsh
# THE ORDER-SWAP SWEEP FOR codegen/late/linearizer.
#
# For each src-swap of the CPython fixture graph, print every row that MOVED
# against the unswapped baseline. An empty diff is a PROVEN-INVISIBLE swap: the
# whole 128-row gate cannot distinguish the two graphs, so no fixture ever could.
#
#   .agents/slop/order-lin-sweep.sh
set -e
cd "$(dirname "$0")/../.."
OUT=".agents/slop/order-lin"
mkdir -p "$OUT"
PY=.venv/bin/python
BASE=""
$PY .agents/slop/order-lin-probe.py > "$OUT/base.txt"
BASE=$(wc -l < "$OUT/base.txt" | tr -d ' ')
echo "baseline: $BASE rows"
# SANITY: the probe's unswapped rows must equal the committed oracle, or the diff
# below measures the probe's own transcription rather than the swap.
if diff -q .agents/slop/late-oracle.txt "$OUT/base.txt" > /dev/null; then
  echo "probe baseline == committed late-oracle.txt  (good)"
else
  echo "!! PROBE DISAGREES WITH THE COMMITTED ORACLE -- diff:"
  diff .agents/slop/late-oracle.txt "$OUT/base.txt" | head -30
fi
echo
for s in add add2 end range sink0 sinkend sinkrev; do
  ORDER_LIN_SWAP=$s $PY .agents/slop/order-lin-probe.py > "$OUT/$s.txt" 2>"$OUT/$s.err" || true
  if [ ! -s "$OUT/$s.txt" ]; then echo "--- swap=$s  CRASHED"; head -5 "$OUT/$s.err"; continue; fi
  n=$(diff "$OUT/base.txt" "$OUT/$s.txt" | grep -c '^>' || true)
  m=$(diff "$OUT/base.txt" "$OUT/$s.txt" | grep -c '^<' || true)
  echo "--- swap=$s  rows changed: $m value-lines, $n value-lines moved"
  if [ "$m" = "0" ]; then
    echo "    *** PROVEN INVISIBLE: 0 of $BASE rows can see this swap"
  else
    diff "$OUT/base.txt" "$OUT/$s.txt" | grep '^<' | sed 's/^< /      - /' | head -12
    diff "$OUT/base.txt" "$OUT/$s.txt" | grep '^>' | sed 's/^> /      + /' | head -12
  fi
done
