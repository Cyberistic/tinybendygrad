#!/bin/sh
# dd-cone-run.sh -- run the gate on a MIRROR tree, never the live file, and keep a
# byte-stable capture.
#
# Same stack-overflow guard as dd-run.sh: bend's machine stack overflows on ~1 run
# in 20 and sometimes prints ZERO rows, which is indistinguishable from "not
# started", so this LOOPS until a run prints at least MIN_ROWS `lg` rows.
# Never gate on the exit code: --check-only exits 1 on a clean file.
#
#   dd-cone-run.sh WORKDIR OUT [MIN_ROWS]
# WORKDIR is a tree directory that must be the PARENT of codegen/.
set -u
TREE="${1:?tree dir}"
OUT="${2:?out file}"
ROWS="${3:-140}"
i=0
while [ "$i" -lt 12 ]; do
  i=$((i + 1))
  ./bin/bend "$TREE/codegen/decomp/dtype.bend" > "$OUT.tmp" 2> "$OUT.err"
  got=$(grep -c '^lg' "$OUT.tmp" 2>/dev/null | head -1)
  got=${got:-0}
  if [ "$got" -ge "$ROWS" ]; then
    mv "$OUT.tmp" "$OUT"
    rm -f "$OUT.err"
    echo "ok: $got l2i rows on attempt $i"
    exit 0
  fi
done
echo "FAILED: only $got l2i rows after $i attempts (need >= $ROWS)" >&2
head -5 "$OUT.err" >&2
exit 1