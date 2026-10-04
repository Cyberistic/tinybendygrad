#!/bin/sh
# surface2's as_param mutation harness. Three one-token edits, each applied, run, reverted.
#
#   sh .agents/slop/surface2/asparam-mutate.sh
#
# THE POINT is that `tn_asparam` alone cannot fail on a slot bug, so the table has to show
# WHICH of the three facts each mutation moves. A harness that diffed whole `name=value`
# lines and reported "0 disagreements" for these would be the failure mode agent-core
# warns about, so this one greps for the row NAME and prints the moved FACT.
set -e
ROOT=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad
cd "$ROOT"
F=tinybendygrad/tensor.bend
W=${TMPDIR:-/tmp}/surface2-mut
mkdir -p "$W"
cp "$F" "$W/pristine.bend"

BASE=$(./bin/bend "$F" 2>/dev/null | grep '^tn_asparam=')
echo "BASE $BASE"
echo

run () { # $1 = arm name, $2 = from, $3 = to
  cp "$W/pristine.bend" "$F"
  .venv/bin/python - "$F" "$2" "$3" <<'PY'
import sys
p, a, b = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
assert s.count(a) == 1, "MUST-EDIT-FOUND-%d: %r" % (s.count(a), a)
open(p, "w").write(s.replace(a, b))
PY
  OUT=$(./bin/bend "$F" 2>/dev/null | grep '^tn_asparam=' || echo "tn_asparam=<did not print>")
  echo "$1"
  echo "  $OUT"
  if [ "$OUT" = "$BASE" ]; then echo "  VERDICT: NOTHING MOVED"; else echo "  VERDICT: MOVED"; fi
  echo
}

# A21: drop the slot -- `tn_asparam_slot` must move and the SIGNATURE must NOT.
run A21-drop-slot 'O.ParamArg{slot, O.ParamArg.dtype(src)' 'O.ParamArg{0, O.ParamArg.dtype(src)'

# A22: forward the SOURCE's slot -- the signature still prints `1 PARAM/0` and only
# `tn_asparam_ne` moves, because a signature cannot see an ARG. This is the arm that
# proves the boolean exists.
run A22-forward-src-slot 'O.ParamArg{slot, O.ParamArg.dtype(src)' 'O.ParamArg{O.ParamArg.slot(src), O.ParamArg.dtype(src)'

# A23: the wrong OP -- the signature moves and the ARG rows do not.
run A23-wrong-op 'O.UOp.new(ar, O.OpsPARAM{}, Nil{},' 'O.UOp.new(ar, O.OpsBUFFER{}, Nil{},'

# A24: a CONTROL -- a no-op edit, reported so the table has a row that CANNOT move.
run A24-control 'S.AGlobal{}, O.ParamArg.device(src)' 'S.AGlobal{}, O.ParamArg.device(src)'

cp "$W/pristine.bend" "$F"
echo "restored: $(diff -q "$W/pristine.bend" "$F" && echo yes)"
echo "final  : $(./bin/bend "$F" 2>/dev/null | grep '^tn_asparam=')"