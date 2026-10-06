#!/bin/sh
# The LIVE INSTRUMENT: run `graphcmp.bend`'s own `main` on ONE graph, in the
# SCRATCH tree, and print the rows to stdout.  `main` takes the graph name as
# argv[1] (`fz_name`, graphcmp.bend:1344) and `IO.print`s every canonical row --
# it does NOT write `runs/graphcmp/D`, so this cannot perturb the shared run.
#
#   .agents/slop/opshapes/rows.sh <label> <tree> <graph>
#
# One bend process at a time, and the VERDICT TOKEN is parsed rather than the exit
# code (`rc=142` would be somebody's own alarm).  Emptiness is checked AFTER the
# run, because `ALL PROOFS CHECK` is reported for a 0-byte file.
set -u
LABEL=$1; TREE=$2; G=$3
W=/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/opshapes
REPO=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad
OUT=$W/$LABEL
i=0
while [ "$i" -lt 90 ]; do
  N=$(ps -A -o args | grep -c '[b]end2/main.ts')
  [ "$N" -eq 0 ] && break
  sleep 20; i=$((i + 1))
done
N=$(ps -A -o args | grep -c '[b]end2/main.ts')
if [ "$N" -ne 0 ]; then echo "$LABEL SKIPPED: $N bend process(es) still running after 1800s"; exit 9; fi
"$REPO/.venv/bin/python" "$REPO/checks/bounded.py" --seconds 900 --mb 2048 -- \
  "$REPO/bin/bend" "$TREE/.agents/slop/graphcmp.bend" "$G" > "$OUT.out" 2> "$OUT.err"
RC=$?
TOK=$(grep -o 'WITHIN-LIMITS\|KILLED-ON-MEMORY\|TIMED-OUT\|NOT-STARTED\|NO-VERDICT' "$OUT.err" | head -1)
EMPTY=$(find "$TREE/tinybendygrad" -name '*.bend' -size -1c | wc -l | tr -d ' ')
HZ=$(wc -c < "$TREE/tinybendygrad/helpers.bend" | tr -d ' ')
ROWS=$(grep -c ' ' "$OUT.out" 2>/dev/null || echo 0)
printf '%s graph=%s rc=%s %s rows=%s empty-bend=%s helpers.bend=%s\n' \
  "$LABEL" "$G" "$RC" "${TOK:-NO-TOKEN}" "$ROWS" "$EMPTY" "$HZ"
exit $RC