#!/bin/sh
# dd-run.sh -- run the dtype.bend gate and keep a byte-stable capture.
#
# bend's machine stack overflows on ~1 run in 20 and sometimes prints ZERO rows,
# which is indistinguishable from "not started" -- so this LOOPS until a run
# prints at least one `l2i`-named row.  Never gate on the exit code: --check-only
# exits 1 on a clean file (14 unfilled dtype.bend laws).
#
#   dd-run.sh [TREE_DIR] [OUT] [MIN_ROWS]
# TREE_DIR defaults to tinybendygrad and must be the PARENT of codegen/.
set -u
TREE="${1:-tinybendygrad}"
OUT="${2:-.agents/slop/dd-gate.txt}"
ROWS="${3:-28}"
i=0
while [ "$i" -lt 8 ]; do
  i=$((i + 1))
  ./bin/bend "$TREE/codegen/decomp/dtype.bend" > "$OUT.tmp" 2> "$OUT.err"
  got=$(grep -c '^lg' "$OUT.tmp" 2>/dev/null | head -1)
  got=${got:-0}
  if [ "$got" -ge "$((ROWS * 4))" ]; then
    mv "$OUT.tmp" "$OUT"
    rm -f "$OUT.err"
    echo "ok: $got l2i rows on attempt $i"
    exit 0
  fi
done
echo "FAILED: only $got l2i rows after $i attempts (need $((ROWS * 4)))" >&2
head -5 "$OUT.err" >&2
exit 1