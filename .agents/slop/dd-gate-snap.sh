#!/bin/sh
# dd-gate-snap.sh -- run dtype.bend's GATE against the PINNED $TMPDIR snapshot with one
# file overlaid from the live tree.
#
# WHY THIS EXISTS. `uop/fold.bend` is another unit's and was mid-edit for this run:
# `./bin/bend tinybendygrad/codegen/decomp/dtype.bend` refused with
#     Error: - expected : m  - observed : m (consumed more than once)
#     Location: reshape_ok      (uop/fold.bend:1792)
# `reshape_ok` is not in `dtype.bend`, so the failure is in the SUBSTRATE -- exactly the
# case agent-core.md names. The fix is to measure on a pinned substrate, not to edit
# theirs. THIS IS A WORKAROUND, NOT A DESIGN: it is only sound while the snapshot's
# md5s are printed on every run, because a substrate change moves rows and a stale
# snapshot hides it.
#
#   dd-gate-snap.sh OUT [SRCFILE]
set -u
S=/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode
SNAP=$S/f2f-snap
OUT="$1"
SRC="${2:-tinybendygrad/codegen/decomp/dtype.bend}"
W=$S/f2f-gatework
rm -rf "$W"
mkdir -p "$W"
cp -R "$SNAP/tinybendygrad" "$W/tinybendygrad"
cp "$SRC" "$W/tinybendygrad/codegen/decomp/dtype.bend"

for f in codegen/decomp/dtype.bend uop/ops.bend uop/fold.bend; do
  printf 'SUBSTRATE %-26s snap=%s live=%s\n' "$f" \
    "$(md5 -q "$SNAP/tinybendygrad/$f")" "$(md5 -q "tinybendygrad/$f")"
done

i=0
while [ "$i" -lt 10 ]; do
  i=$((i + 1))
  perl -e 'alarm 2400; exec @ARGV' ./bin/bend "$W/tinybendygrad/codegen/decomp/dtype.bend" \
    > "$OUT" 2> "$OUT.err"
  got=$(grep -c '^lg' "$OUT" 2>/dev/null | head -1)
  got=${got:-0}
  if [ "$got" -ge 152 ]; then
    echo "ok attempt $i ($got l2i rows) -> $OUT"
    rm -f "$OUT.err"
    exit 0
  fi
  sleep 8
done
echo "FAILED: only $got l2i rows after $i attempts" >&2
head -20 "$OUT.err" >&2
exit 1
