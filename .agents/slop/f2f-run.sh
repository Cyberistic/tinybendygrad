#!/bin/sh
# f2f-run.sh -- run a `f2f` probe against a FROZEN snapshot of the live tree.
#
# SAME SUBSTRATE RULE AS dd-band-run.sh. `uop/ops.bend` is another unit's and has been
# observed in four states; a probe that reads a substrate someone else is editing measures
# their keystrokes. So the substrate is a snapshot under $TMPDIR and `md5 -q` is asserted
# on BOTH files. `md5 -q` on macOS takes exactly ONE file: two prints nothing and reads
# as a silent pass.
#
# THE WORK TREE IS REPO-SHAPED (a root holding both `tinybendygrad/` and `.agents/slop/`),
# because the probes carry `./../../tinybendygrad/...` imports.
#
# RULE E/H: bend prints NOTHING on a stack overflow (~1 run in 20) and that is
# byte-identical to "never started", so a run with no rows is retried and the exit status
# is never the verdict.
#
# usage: f2f-run.sh PROBE.bend OUT [SRCFILE] [MINROWS]
set -u
S=/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode
SNAP=$S/f2f-snap
PROBE="$1"
OUT="$2"
SRC="${3:-$SNAP/tinybendygrad/codegen/decomp/dtype.bend}"
MINROWS="${4:-3}"
NAME=$(basename "$PROBE")

for f in codegen/decomp/dtype.bend uop/ops.bend; do
  a=$(md5 -q "$SNAP/tinybendygrad/$f")
  b=$(md5 -q "tinybendygrad/$f")
  printf '%s snap=%s live=%s\n' "$f" "$a" "$b"
done

W=$S/f2f-work/repo
rm -rf "$S/f2f-work"
mkdir -p "$W/.agents/slop"
cp -R "$SNAP/tinybendygrad" "$W/tinybendygrad"
cp "$SRC" "$W/tinybendygrad/codegen/decomp/dtype.bend"
cp "$PROBE" "$W/.agents/slop/$NAME"

i=0
while [ "$i" -lt 14 ]; do
  i=$((i + 1))
  perl -e 'alarm 2400; exec @ARGV' ./bin/bend "$W/.agents/slop/$NAME" > "$OUT" 2> "$OUT.err"
  got=$(grep -c '^[A-Za-z0-9_]' "$OUT" 2>/dev/null | head -1)
  got=${got:-0}
  if [ "$got" -ge "$MINROWS" ]; then
    echo "ok attempt $i ($got rows) -> $OUT"
    exit 0
  fi
  sleep 8
done
echo "FAILED: $NAME printed $got rows in $i attempts" >&2
head -8 "$OUT.err" >&2
exit 1