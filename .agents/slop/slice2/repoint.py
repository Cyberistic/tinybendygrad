#!/usr/bin/env python3
"""RE-POINT the stale `.bend`-to-`.bend` line citations in MY 26 files.

THE FIX IS THE `symbol=` FORM: "A CITATION THAT NAMES THE CONSTRUCT DOES NOT ROT
WHEN THE LINES MOVE." So `file.bend:<stale>` becomes `file.bend:<the line the
construct is AT NOW> symbol=<the construct's name>`.

THE NEW LINE IS NOT GUESSED: it is the DECLARATION LINE the gate itself reports in
its `decl` column, and the NAME is the claim token the gate reports. Where the
gate's `decl` is a NEAREST-OF-N, the row says so and the plan below names the
member that is the one the claim is about.

Every edit is a TEXT EDIT, and the gate is run afterwards to check it.
"""
import csv, re, sys
from pathlib import Path

ROOT = Path("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
SL = Path("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/slice2")

# (rel, port line, the OLD citation text as it appears, the NEW citation text)
PLAN = [
  # ---- codegen/decomp/op.bend
  ("tinybendygrad/codegen/decomp/op.bend", 1023,
   "`H.i64_cmp` (helpers.bend:1696)",
   "`H.i64_cmp` (helpers.bend:1697 symbol=i64_cmp)"),
  # ---- codegen/opt/heuristic.bend
  ("tinybendygrad/codegen/opt/heuristic.bend", 9,
   "`uop/fold.bend:2431`",
   "`uop/fold.bend:5055 symbol=UOp.ranges`"),
  # ---- codegen/rewriter.bend
  ("tinybendygrad/codegen/rewriter.bend", 82,
   "fold.bend:4819-4823",
   "fold.bend:5055 symbol=UOp.ranges"),
  # ---- examples/test_pkl_imagenet.bend
  ("tinybendygrad/examples/test_pkl_imagenet.bend", 53,
   "jit.bend:38-41",
   "jit.bend:401 symbol=ii_vars"),
  ("tinybendygrad/examples/test_pkl_imagenet.bend", 167,
   "helpers.bend:306 `getenv_int`",
   "helpers.bend:307 symbol=getenv_int `getenv_int`"),
  # ---- extra/models/convnext.bend
  ("tinybendygrad/extra/models/convnext.bend", 22,
   "nn/layers.bend:756 `nn_conv2d`",
   "nn/layers.bend:937 symbol=nn_conv2d `nn_conv2d`"),
  ("tinybendygrad/extra/models/convnext.bend", 24,
   "nn/layers.bend:427 `nn_linear`",
   "nn/layers.bend:530 symbol=nn_linear `nn_linear`"),
  ("tinybendygrad/extra/models/convnext.bend", 25,
   "nn/layers.bend:262 `nn_relu`",
   "nn/layers.bend:299 symbol=nn_relu `nn_relu`"),
  ("tinybendygrad/extra/models/convnext.bend", 40,
   "nn/layers.bend:756",
   "nn/layers.bend:937 symbol=nn_conv2d"),
  ("tinybendygrad/extra/models/convnext.bend", 55,
   "`mixin/elementwise.bend:1217` is `ew_quick_gelu`",
   "`mixin/elementwise.bend:1227 symbol=ew_quick_gelu` is `ew_quick_gelu`"),
  ("tinybendygrad/extra/models/convnext.bend", 85,
   "nn/state.bend:227's shape",
   "nn/state.bend:838 symbol=main's shape"),
  # ---- extra/models/resnet.bend
  ("tinybendygrad/extra/models/resnet.bend", 29,
   "`extra/models/vit.bend:153` and `:157`",
   "`extra/models/vit.bend:153` and `extra/models/vit.bend:157` (upstream's `vt_layernorm`)"),
  ("tinybendygrad/extra/models/resnet.bend", 59,
   "dtype.bend:518 `to_dtype`",
   "dtype.bend:557 symbol=to_dtype `to_dtype`"),
  ("tinybendygrad/extra/models/resnet.bend", 65,
   "mixin/op.bend:891 `mo_mean`",
   "mixin/op.bend:953 symbol=mo_mean `mo_mean`"),
  ("tinybendygrad/extra/models/resnet.bend", 74,
   "`mo_reshape` mixin/op.bend:664",
   "`mo_reshape` mixin/op.bend:704 symbol=mo_reshape"),
  ("tinybendygrad/extra/models/resnet.bend", 79,
   "`mx_pool_f` mixin/movement.bend:297",
   "`mx_pool_f` mixin/movement.bend:300 symbol=mx_pool_f"),
  ("tinybendygrad/extra/models/resnet.bend", 170,
   "nn/state.bend:227's shape",
   "nn/state.bend:838 symbol=main's shape"),
  # ---- extra/models/unet.bend
  ("tinybendygrad/extra/models/unet.bend", 30,
   "`cr_full` (mixin/creation.bend:417)",
   "`cr_full` (mixin/creation.bend:489 symbol=cr_full)"),
  ("tinybendygrad/extra/models/unet.bend", 32,
   "`ew_exp`, mixin/elementwise.bend:1286",
   "`ew_exp`, mixin/elementwise.bend:1312 symbol=ew_exp"),
  ("tinybendygrad/extra/models/unet.bend", 63,
   "`ew_silu`, mixin/elementwise.bend:1209",
   "`ew_silu`, mixin/elementwise.bend:1219 symbol=ew_silu"),
  ("tinybendygrad/extra/models/unet.bend", 65,
   "`cr_expand`, mixin/creation.bend:271",
   "`cr_expand`, mixin/creation.bend:343 symbol=cr_expand"),
  ("tinybendygrad/extra/models/unet.bend", 66,
   "(`nn_conv2d`, nn/layers.bend:756)",
   "(`nn_conv2d`, nn/layers.bend:937 symbol=nn_conv2d)"),
  # ---- mixin/reduce.bend
  ("tinybendygrad/mixin/reduce.bend", 84,
   "`mo_ax` (op.bend:752)",
   "`mo_ax` (op.bend:794 symbol=mo_ax)"),
  ("tinybendygrad/mixin/reduce.bend", 167,
   "`T.tn_rop` (tensor.bend:867)",
   "`T.tn_rop` (tensor.bend:1843 symbol=tn_rop)"),
  ("tinybendygrad/mixin/reduce.bend", 230,
   "`mo_shape`'s shape string (op.bend:1395)",
   "`mo_shape`'s shape string (op.bend:1555 symbol=mo_shape)"),
  ("tinybendygrad/mixin/reduce.bend", 259,
   "`M.mo_axis0` (op.bend:745)",
   "`M.mo_axis0` (op.bend:787 symbol=mo_axis0)"),
  # ---- runtime/ops_cpu.bend
  ("tinybendygrad/runtime/ops_cpu.bend", 135,
   "`device.bend:869-871` ports `TinyELF.iter_sig`",
   "`device.bend:988 symbol=TinyELF.iter_sig` ports `TinyELF.iter_sig`"),
  # ---- uop/ops.bend
  ("tinybendygrad/uop/ops.bend", 1486,
   "`Arena.empty` spends arena index 0 on the bottom (ops.bend:1166)",
   "`Arena.empty` spends arena index 0 on the bottom (ops.bend:1356 symbol=Arena.empty)"),
  ("tinybendygrad/uop/ops.bend", 2742,
   "(`ops.bend:1255`)",
   "(`ops.bend:1293 symbol=Arena`)"),
  ("tinybendygrad/uop/ops.bend", 2968,
   "`cast_at` in `mixin/dtype.bend:335`",
   "`cast_at` in `mixin/dtype.bend:350 symbol=cast_at`"),
  ("tinybendygrad/uop/ops.bend", 3054,
   "(`ops.bend:1255`)",
   "(`ops.bend:1293 symbol=Arena`)"),
  ("tinybendygrad/uop/ops.bend", 4426,
   "`ops.bend:6649`'s inline `replace`",
   "`ops.bend:895 symbol=TNone`'s inline `replace`"),
  ("tinybendygrad/uop/ops.bend", 5131,
   "`Ranged` / `UOp.ranges` (fold.bend:4372)",
   "`Ranged` / `UOp.ranges` (fold.bend:5055 symbol=UOp.ranges)"),
  ("tinybendygrad/uop/ops.bend", 5138,
   "`schedule/rangeify.bend:189`, whose `rf_in_ranges`",
   "`schedule/rangeify.bend:205 symbol=rf_in_ranges`, whose `rf_in_ranges`"),
  ("tinybendygrad/uop/ops.bend", 5234,
   "`tensor.bend`'s `tn_rop` (tensor.bend:868)",
   "`tensor.bend`'s `tn_rop` (tensor.bend:1843 symbol=tn_rop)"),
  ("tinybendygrad/uop/ops.bend", 5326,
   "`tensor.bend`'s `tn_mop` (tensor.bend:729)",
   "`tensor.bend`'s `tn_mop` (tensor.bend:1704 symbol=tn_mop)"),
  ("tinybendygrad/uop/ops.bend", 8559,
   "`render.bend:1878`'s `render_with_splits`",
   "`render.bend:1718 symbol=render_with_splits`'s `render_with_splits`"),
  ("tinybendygrad/uop/ops.bend", 8748,
   "the `ax_names_str` shape (ops.bend:5793)",
   "the `ax_names_str` shape (ops.bend:6514 symbol=ax_names_str)"),
  ("tinybendygrad/uop/ops.bend", 8770,
   "`ax_names_str` at ops.bend:5792",
   "`ax_names_str` at ops.bend:6514 symbol=ax_names_str"),
  ("tinybendygrad/uop/ops.bend", 9526,
   "`Rng.srcops.seeded` (ops.bend:5127)",
   "`Rng.srcops.seeded` (ops.bend:6060)"),
  # ---- uop/render.bend
  ("tinybendygrad/uop/render.bend", 628,
   "(ops.bend:2330-2345)",
   "(ops.bend:1228 symbol=ARange)"),
  ("tinybendygrad/uop/render.bend", 2122,
   "(ops.bend:1011-1018:",
   "(ops.bend:1145 symbol=CallInfo:"),
]

fail = 0
for rel, at, old, new in PLAN:
  p = ROOT / rel
  lines = p.read_text(errors="replace").splitlines(keepends=True)
  if at > len(lines):
    print(f"OUT-OF-RANGE {rel}:{at}  (the file has {len(lines)} lines)")
    fail += 1
    continue
  line = lines[at - 1]
  if old not in line:
    print(f"NO-MATCH {rel}:{at}  wanted {old!r}")
    print(f"    got {line.rstrip()!r}")
    fail += 1
    continue
  lines[at - 1] = line.replace(old, new, 1)
  p.write_text("".join(lines))
  print(f"OK {rel}:{at}  {old!r} -> {new!r}")
print(f"\n{len(PLAN) - fail} of {len(PLAN)} re-pointed, {fail} failed.")
