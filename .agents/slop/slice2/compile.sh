#!/bin/zsh
# COMPILE every one of MY 26 files, ONE bend at a time, and READ THE VERDICT TOKEN.
# The exit code is NOT the answer: `checks/bounded.py`'s own header records a unit that
# lost 425 rows by believing the status. The token is `WITHIN-LIMITS` /
# `KILLED-ON-MEMORY` / `TIMED-OUT`.
ROOT=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad
SL=/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/slice2
FILES=(
  codegen/decomp/dtype.bend codegen/decomp/op.bend codegen/decomp/transcendental_f32.bend
  codegen/opt/heuristic.bend codegen/rewriter.bend device.bend examples/test_pkl_imagenet.bend
  extra/models/convnext.bend extra/models/resnet.bend extra/models/unet.bend helpers.bend
  mixin/dtype.bend mixin/reduce.bend nn/optim.bend renderer/amd/generate.bend
  renderer/isa/x86.bend runtime/ops_cpu.bend runtime/ops_npy.bend runtime/support/c.bend
  runtime/support/compiler_amd.bend runtime/support/compiler_mesa.bend runtime/support/nv/ip.bend
  runtime/support/system.bend schedule/memory.bend uop/ops.bend uop/render.bend
)
cd "$ROOT"
for f in $FILES; do
  out=$(.venv/bin/python checks/bounded.py --mb 2048 -- ./bin/bend "tinybendygrad/$f" 2>&1)
  token=$(print -r -- "$out" | grep -oE "WITHIN-LIMITS|KILLED-ON-MEMORY|TIMED-OUT" | tail -1)
  if [ -z "$token" ]; then token="NO-TOKEN"; fi
  printf "%-12s %s\n" "$token" "tinybendygrad/$f"
  print -r -- "$out" > "$SL/compile-$(echo $f | tr '/' '_').out"
done
