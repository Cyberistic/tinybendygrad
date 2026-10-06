#!/bin/sh
# Run `bend --check-only` on ONE file of the scratch tree, under BOTH bounds, one
# process at a time.  Two `bend` processes at once is how `sz.bend`'s 1,468 MB
# becomes an OOM, and three other units are live on this tree, so this WAITS for
# the tree to be free instead of joining them.  Prints ONE line: rc, the VERDICT
# TOKEN (never the exit code alone -- `rc=142` is somebody's own alarm), the first
# stdout line, and the EMPTINESS census of the tree afterwards, because
# `ALL PROOFS CHECK` is reported for a 0-byte file.
#
#   .agents/slop/opshapes/one.sh <label> <tree> <relpath-under-tinybendygrad>
set -u
LABEL=$1; TREE=$2; REL=$3
W=/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/opshapes
REPO=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad
OUT=$W/$LABEL
i=0
while [ "$i" -lt 60 ]; do
  N=$(ps -A -o args | grep -c '[b]end2/main.ts')
  [ "$N" -eq 0 ] && break
  sleep 20; i=$((i + 1))
done
N=$(ps -A -o args | grep -c '[b]end2/main.ts')
if [ "$N" -ne 0 ]; then echo "$LABEL SKIPPED: $N bend process(es) still running after 1200s"; exit 9; fi
"$REPO/.venv/bin/python" "$REPO/checks/bounded.py" --seconds 900 --mb 2048 -- \
  "$REPO/bin/bend" "$TREE/tinybendygrad/$REL" --check-only > "$OUT.out" 2> "$OUT.err"
RC=$?
TOK=$(grep -o 'WITHIN-LIMITS\|KILLED-ON-MEMORY\|TIMED-OUT\|NOT-STARTED\|NO-VERDICT' "$OUT.err" | head -1)
EMPTY=$(find "$TREE/tinybendygrad" -name '*.bend' -size -1c | wc -l | tr -d ' ')
HZ=$(wc -c < "$TREE/tinybendygrad/helpers.bend" | tr -d ' ')
printf '%s  rc=%s  %s  empty-bend=%s  helpers.bend=%s  | %s\n' \
  "$LABEL" "$RC" "${TOK:-NO-TOKEN}" "$EMPTY" "$HZ" "$(head -1 "$OUT.out")"
exit $RC