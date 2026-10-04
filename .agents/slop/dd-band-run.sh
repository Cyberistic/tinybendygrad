#!/bin/sh
# dd-band-run.sh -- run a dd-band probe against the FROZEN dtype.bend/ops.bend snapshot.
#
# WHY NOT THE LIVE TREE. `tinybendygrad/uop/ops.bend` is another unit's and was observed
# THREE states inside forty minutes (md5 baff197566ce -> 3cd6e0dffc -> b3dab8582a), and the
# third does not compile: it declares `type Arg` twice, at its lines 1110 and 1349, so both
# this unit's probe AND the pre-existing `.agents/slop/dd-slotprobe.bend` die with
# "duplicate declaration: Arg". A probe that reads a substrate another agent is editing
# measures their keystrokes. So the tree is a snapshot taken once and the digest is asserted.
#
# LAYOUT. The probe carries `./../../tinybendygrad/...` imports, which is the house form and
# resolves from `.agents/slop/`, so the work tree is REPO-SHAPED: a root holding both
# `tinybendygrad/` and `.agents/slop/`. A flat mirror cannot resolve it -- agent-core.md
# records a $TMPDIR scratch copy that could not, and it manufactured 22 phantom blind spots.
#
# usage: dd-band-run.sh PROBE.bend [OUT] [WORKDIR]
set -u
SCRATCH=/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode
SNAP=$SCRATCH/dd-band-snap
PROBE="$1"
OUT="${2:-$SCRATCH/dd-band-run.out}"
WORK="${3:-$SCRATCH/dd-band-work}"
NAME=$(basename "$PROBE")

# RULE I: the snapshot must be the snapshot.
for f in tinybendygrad/codegen/decomp/dtype.bend tinybendygrad/uop/ops.bend; do
  printf '%s  %s\n' "$(md5 -q "$SNAP/$f")" "$f" || exit 2
done

rm -rf "$WORK"
mkdir -p "$WORK/repo/.agents/slop"
cp -R "$SNAP/tinybendygrad" "$WORK/repo/tinybendygrad"
cp "$PROBE" "$WORK/repo/.agents/slop/$NAME"

# RULE E/H: bend prints NOTHING on a stack overflow (~1 run in 20) and that is
# byte-identical to "never started", so a run with no rows is retried, and the exit
# status is never the verdict.
i=0
while [ "$i" -lt 12 ]; do
  i=$((i + 1))
  perl -e 'alarm 1800; exec @ARGV' ./bin/bend "$WORK/repo/.agents/slop/$NAME" \
    > "$OUT" 2> "$OUT.err"
  if grep -q '=' "$OUT"; then
    echo "ok on attempt $i -> $OUT"
    exit 0
  fi
  sleep 8
done
echo "FAILED: $NAME printed no rows in $i attempts" >&2
head -8 "$OUT.err" >&2
exit 1