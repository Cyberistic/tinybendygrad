#!/bin/zsh
# THE STAMPED LATE GATE. `late-gate.sh` alone cannot be trusted right now: three
# other agents are editing `uop/ops.bend`, `codegen/decomp/dtype.bend` and
# `codegen/__init__.bend`, and the gate went 0-rows/128-rows/0-rows inside one
# session -- which is indistinguishable from "not started" (bend 2.0.34
# stack-overflows about one run in twenty, per agent-core).
#
# So: hash the SUBSTRATE before, wait for a green run, hash it after, and print
# SUBSTRATE MOVED (and discard the verdict) if anything moved underneath.
#
#   .agents/slop/order-late-gate.sh [tries]
set -e
cd "$(dirname "$0")/../.."
TRIES=${1:-12}
SUB="tinybendygrad/uop/ops.bend tinybendygrad/uop/fold.bend tinybendygrad/uop/movement.bend tinybendygrad/uop/symbolic.bend tinybendygrad/codegen/decomp/dtype.bend tinybendygrad/codegen/__init__.bend tinybendygrad/dtype.bend tinybendygrad/helpers.bend"
sub_md5() { for f in ${=SUB}; do md5 -q "$f"; done | tr '\n' ' '; }
BEFORE=$(sub_md5)
echo "SUBSTRATE BEFORE  $BEFORE"
OK=0
for i in $(seq 1 "$TRIES"); do
  OUT=$(.agents/slop/late-gate.sh 2>&1 || true)
  N=$(printf '%s' "$OUT" | grep -o 'union: [0-9]*' | grep -o '[0-9]*' | head -1)
  if printf '%s' "$OUT" | grep -q 'MATCHES the CPython oracle'; then
    echo "$OUT" | tail -4
    OK=1
    echo "GREEN on attempt $i, $N rows"
    break
  fi
  echo "  attempt $i: union=$N rows, not green; substrate $(sub_md5 | cut -c1-8).."
  sleep 20
done
AFTER=$(sub_md5)
if [ "$BEFORE" != "$AFTER" ]; then
  echo "SUBSTRATE MOVED -- THESE NUMBERS ARE ABOUT A TREE THAT NO LONGER EXISTS"
  echo "  before $BEFORE"
  echo "  after  $AFTER"
  [ "$OK" = 1 ] && echo "  (the green run was AFTER the last move; re-run to stamp it)"
else
  echo "SUBSTRATE UNCHANGED  $AFTER"
fi
[ "$OK" = 1 ]
