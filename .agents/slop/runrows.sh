#!/bin/sh
# runrows.sh <bend-file> <out-file>
# Runs a bend file's main and writes its rows, RETRYING A ZERO-ROW RESULT.
#
# WHY THE RETRY: bend's machine stack overflows on ~1 run in 20, printing
#   "Error: the machine stack overflowed"
# and sometimes ZERO rows. A 0-row result is INDISTINGUISHABLE from "never
# started", so it is re-run rather than believed.
#
# WHY THE LOOP CAP: a file whose main prints nothing prints 0 rows FOREVER
#   (`codegen/rewriter.bend`, `codegen/opt/postrange.bend` are the two known).
# So the cap exits non-zero with EXPLICIT text, never a silent 0.
set -u
BEND="$1"; OUT="$2"; N=0
while [ "$N" -lt 8 ]; do
  N=$((N+1))
  ./bin/bend "$BEND" > "$OUT.tmp" 2> "$OUT.err"
  if grep -q 'machine stack overflowed' "$OUT.tmp" "$OUT.err"; then
    echo "  [$N] STACK OVERFLOW -- re-running" >&2
    continue
  fi
  R=$(grep -c . "$OUT.tmp")
  if [ "$R" -eq 0 ]; then
    echo "  [$N] ZERO ROWS -- re-running" >&2
    continue
  fi
  mv "$OUT.tmp" "$OUT"; echo "  rows=$R attempts=$N" >&2; exit 0
done
echo "NO ROWS after $N attempts -- this file may have no main" >&2
exit 1