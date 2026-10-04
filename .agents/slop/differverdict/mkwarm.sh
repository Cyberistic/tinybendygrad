#!/bin/sh
# A WARM substrate, so the comparison measures VERDICTS and not two identical failures.
#
# MEASURED: the substrate went cold at `a9491a5c26bb` ("arglit"), which added the 20th `Arg`
# constructor `AOpLit{op: Op}` to `tinybendygrad/uop/ops.bend` and did NOT add the
# corresponding arm to `argstr` in `.agents/slop/graphcmp.bend`. `--check-only` then reads
# `expected : cases for ../../tinybendygrad/uop/ops.AOpLit` and every `emit --side bend` is
# 0 rows. Its PARENT `3a68607fb198` has neither half of the change, so it is warm.
#
# THE LIVE TREE IS COLD IN THE OPPOSITE DIRECTION: `graphcmp.bend:398` HAS the
# `case O.AOpLit{aop}: opx(aop)` arm and live `ops.bend` has LOST the variant. Two units,
# opposite halves of the same edit. So neither the live tree nor HEAD can measure anything.
#
# NOTHING IN THE REPO IS EDITED. This is a scratch tree under my own slop directory.
set -eu
SRC=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad
DST=$SRC/.agents/slop/differverdict/warm
rm -rf "$DST"
mkdir -p "$DST"
cd "$SRC"
jj file list -r 3a68607fb198 2>/dev/null | wc -l | xargs -I{} echo "files at 3a68607fb198: {}"
jj archive -r 3a68607fb198 "$DST" 2>/dev/null || git archive 3a68607fb198 | tar -x -C "$DST"
ln -sfn "$SRC/.venv" "$DST/.venv"
mkdir -p "$DST/bin"
ln -sfn "$SRC/bin/bend" "$DST/bin/bend"
echo "warm root: $DST"