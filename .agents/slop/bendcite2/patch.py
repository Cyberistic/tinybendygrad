#!/usr/bin/env python3
"""THE PATCH, AS A LIST OF (file, old, new) EXACT STRING EDITS.

TWO RULES, AND BOTH ARE MEASURED:

1. **LINE-COUNT NEUTRAL.** A `.bend` file's LINES are pointed at by OTHER files'
   `.bend` citations, so adding a line to a file moves every pointer INTO it. The
   `symbol=` form is what makes a pointer durable, but the pointers that are NOT
   yet durable are still line-based, and this patch must not move them. Every edit
   below replaces N LINES with N LINES, and `main()` CHECKS that.

2. **THE `symbol=` FORM.** The tree's own durable citation shape, and the one the
   `gates/bendcite-gate.py` census reads: `path.bend:NNN symbol=the_name`.

  .venv/bin/python .agents/slop/bendcite2/patch.py <root>
"""
import sys
from pathlib import Path

EDITS: list[tuple[str, str, str]] = []


def edit(rel: str, old: str, new: str) -> None:
  EDITS.append((rel, old, new))


# --------------------------------------------------------------------------- nn/argmax.bend
edit("tinybendygrad/nn/argmax.bend",
     "# SCRUTINISE A CALL (BEND'S RULE 1), AND `tinybendygrad/uop/ops.bend:8951` IS THE",
     "# SCRUTINISE A CALL (BEND'S RULE 1), AND `tinybendygrad/uop/ops.bend:8947 symbol=fs.pinfo.of` IS THE")

edit("tinybendygrad/nn/argmax.bend",
     "# PASS ON NOTHING.** THE READER BELOW ASKS `F.fold.shape` (uop/fold.bend:4764), WHICH",
     "# PASS ON NOTHING.** THE READER BELOW ASKS `F.fold.shape` (uop/fold.bend:4764 symbol=fold.shape), WHICH")

# --------------------------------------------------------------------------- nn/onnx.bend
edit("tinybendygrad/nn/onnx.bend",
     "# WALL(p3) onnx.py:543  contiguous_1 / :547 If / :564 Identity / :565 Constant / -- BLOCKED: needs x.contiguous (elementwise.bend:873) and Tensor.eye (NOT defs); If needs an OnnxRunner VALUE (:67-69) and ImageDecoder needs PIL (:72).",
     "# WALL(p3) onnx.py:543  contiguous_1 / :547 If / :564 Identity / :565 Constant / -- BLOCKED: needs x.contiguous, WHICH THE PORT'S `mixin/elementwise.bend` NO LONGER CARRIES -- upstream's `elementwise.py:59` is the record -- and Tensor.eye (NOT defs); If needs an OnnxRunner VALUE (:67-69) and ImageDecoder needs PIL (:72).")
edit("tinybendygrad/nn/onnx.bend",
     "#   :593 ConstantOfShape / :597 Size / :598 Shape",
     "#   :593 ConstantOfShape / :597 Size / :598 Shape, and the port's own pointer for `contiguous` is mixin/elementwise.bend:926 symbol=contiguous")
edit("tinybendygrad/nn/onnx.bend",
     "# WALL(p3) onnx.py:601  Not / Clip / IsInf -- BLOCKED: needs x.clip (elementwise.bend:880) and x.isinf (:832) (NOT defs); x.logical_not IS ported (ew_logical_not).",
     "# WALL(p3) onnx.py:601  Not / Clip / IsInf -- BLOCKED: needs x.clip, WHICH THE PORT'S `mixin/elementwise.bend` NO LONGER CARRIES -- upstream's `elementwise.py:586` is the record -- and x.isinf (:832) (NOT defs); x.logical_not IS ported (ew_logical_not).")
edit("tinybendygrad/nn/onnx.bend",
     "#   GATED, so only `x.max`/`x.min`/`x.sum`/`x.mean`/`x.argmax` are missing.",
     "#   GATED, so only `x.max`/`x.min`/`x.sum`/`x.mean`/`x.argmax` are missing, and the port's own pointer for `clamp` is mixin/elementwise.bend:933 symbol=clamp")

# --------------------------------------------------------------------------- nn/state.bend
edit("tinybendygrad/nn/state.bend",
     "#     IS PORTED at `ops.bend:2849`, gate `gates/replace-gate.py` rc=0 8/8 rows) and",
     "#     IS PORTED at `ops.bend:2939 symbol=UOp.replace`, gate `gates/replace-gate.py` rc=0 8/8 rows) and")

edit("tinybendygrad/nn/state.bend",
     "#   `ops.bend:2849`, gate `gates/replace-gate.py` rc=0 8/8 rows), but `v.realize` (:162, WALL 4)",
     "#   `ops.bend:2939 symbol=UOp.replace`, gate `gates/replace-gate.py` rc=0 8/8 rows), but `v.realize` (:162, WALL 4)")

# --------------------------------------------------------------------------- codegen/gpudims.bend
edit("tinybendygrad/codegen/gpudims.bend",
     "# at `ops.bend:2849`, gate `gates/replace-gate.py` rc=0 8/8 rows). The TAG rides",
     "# at `ops.bend:2939 symbol=UOp.replace`, gate `gates/replace-gate.py` rc=0 8/8 rows). The TAG rides")

# --------------------------------------------------------------------------- mixin/dtype.bend
edit("tinybendygrad/mixin/dtype.bend",
     "# missing `CWeakFloat`; ops.bend:1318-1337 now has all seven arms, so the workaround is",
     "# missing `CWeakFloat`; the port's `uop/ops.bend` now has all seven arms, so the workaround is")

# --------------------------------------------------------------------------- mixin/reduce.bend
edit("tinybendygrad/mixin/reduce.bend",
     "# `Op` is `Data` (ops.bend:101), so the op RIDES in the record rather than a",
     "# `Op` is `Data` (uop/ops.bend:169 symbol=Op), so the op RIDES in the record rather than a")
edit("tinybendygrad/mixin/reduce.bend",
     "# THE ROW. `mo_shape`'s shape string (op.bend:1555 symbol=mo_shape) and `mo_sig`'s signature\n"
     "# (op.bend:1143) are REUSED -- they are defs in another file and Bend has no",
     "# THE ROW. `mo_shape`'s shape string (mixin/op.bend:1556 symbol=mo_shape) and `mo_sig`'s signature\n"
     "# (mixin/op.bend:1276 symbol=mo_sig) are REUSED -- they are defs in another file and Bend has no")

# --------------------------------------------------------------------------- codegen/decomp/op.bend
edit("tinybendygrad/codegen/decomp/op.bend",
     "#   * Any other op needs the recursive `_min_max`, which is P3 and recorded at\n"
     "#     `fold.bend:2176`. `dc_end` answers `False` there, which makes the guard\n"
     "#     fail and sends the rule down the GENERAL path. That is Python's answer\n"
     "#     whenever the guard is false, so the divergence is SOUND. It is\n"
     "#     DIVERGENCE D and the alternative -- answering `True` -- would be a wrong\n"
     "#     answer, not a conservative one.",
     "#   * Any other op needs the recursive `_min_max`, which is P3 and the port's\n"
     "#     `uop/fold.bend:5175 symbol=UOp.min_max` is the reader that would answer it.\n"
     "#     `dc_end` answers `False` for those ops, which makes the guard fail and sends\n"
     "#     the rule down the GENERAL path. That is Python's answer whenever the guard is\n"
     "#     false, so the divergence is SOUND. It is DIVERGENCE D and the alternative --\n"
     "#     answering `True` -- would be a wrong answer, not a conservative one.")

# --------------------------------------------------------------------------- nn/__init__.bend
edit("tinybendygrad/nn/__init__.bend",
     "#     (`mixin/elementwise.bend:358`) -> 1, `is_invalid` -> 81, `dtypes.weaks` -> 63, and",
     "#     (`mixin/elementwise.bend:325 symbol=ew_remint`) -> 1, `is_invalid` -> 81, `dtypes.weaks` -> 63, and")

# --------------------------------------------------------------------------- schedule/prepare.bend
edit("tinybendygrad/schedule/prepare.bend",
     "# `S.Dt`'s fourth field is the NAME (`LAWS/spec.bend:78`, `Dt{pri, bits, cls, nm}`)",
     "# `S.Dt`'s fourth field is the NAME (`LAWS/spec.bend:76 symbol=Dt`, `Dt{pri, bits, cls, nm}`)")

edit("tinybendygrad/schedule/prepare.bend",
     "# through `ops.bend:697`. A BUFFER's `src` is EMPTY in Python",
     "# through `uop/ops.bend:697 symbol=AxisType.lt`. A BUFFER's `src` is EMPTY in Python")

# --------------------------------------------------------------------------- renderer/kuconv.bend
edit("tinybendygrad/renderer/kuconv.bend",
     "#   | `dtype`     | `u.dtype` (ops.py:247)          | `F.fold.dt(ar, tb, i)` (fold.bend:4770) |",
     "#   | `dtype`     | `u.dtype` (ops.py:247)          | `F.fold.dt(ar, tb, i)` (uop/fold.bend:4770) |")
edit("tinybendygrad/renderer/kuconv.bend",
     "#   | `srcs`      | `u.src`  (ops.py:253)           | `O.Arena.srcs(ar, i)` (ops.bend:1394), RE-INDEXED |\n"
     "#",
     "#   | `srcs`      | `u.src`  (ops.py:253)           | `O.Arena.srcs(ar, i)` (ops.bend:1394), RE-INDEXED |\n"
     "#   the durable pointer for the `dtype` row is uop/fold.bend:4770 symbol=fold.dt")

# --------------------------------------------------------------------------- renderer/llvmir.bend
edit("tinybendygrad/renderer/llvmir.bend",
     "# (`uop/fold.bend:2798` says so), so `struct.pack(\"d\", x)` is not expressible --",
     "# (`uop/fold.bend:3565 symbol=bnd_f` says so), so `struct.pack(\"d\", x)` is not expressible --")

# --------------------------------------------------------------------------- runtime/support/elf.bend
edit("tinybendygrad/runtime/support/elf.bend",
     "#      THE ORDER ITS ARGUMENTS WERE WRITTEN IN. helpers.bend:1029 and\n"
     "#      ops_amd.bend:626 both put the accumulator FIRST for exactly this reason.",
     "#      THE ORDER ITS ARGUMENTS WERE WRITTEN IN. helpers.bend:1366 symbol=pool_pads_dup.go\n"
     "#      and ops_amd.bend:624 symbol=sig.step both put the accumulator FIRST for this.")

edit("tinybendygrad/runtime/support/elf.bend",
     "#   2. THE FUEL IS THE LIST, NOT A NUMBER. `sig.go` (ops_amd.bend:626) descends",
     "#   2. THE FUEL IS THE LIST, NOT A NUMBER. `sig.go` (ops_amd.bend:627 symbol=sig.go) descends")

edit("tinybendygrad/runtime/support/elf.bend",
     "# (engine/jit.bend:348) is the template: APPEND the rendered cell onto `acc` with",
     "# (engine/jit.bend:358 symbol=JName.reprs.go) is the template: APPEND the rendered cell onto `acc` with")

# --------------------------------------------------------------------------- runtime/support/autogen.bend
edit("tinybendygrad/runtime/support/autogen.bend",
     "# the shape `helpers.bend:1368` uses for the same reason.",
     "# the shape `helpers.bend:1366 symbol=pool_pads_dup.go` uses for the same reason.")

edit("tinybendygrad/runtime/support/autogen.bend",
     "#          shape `helpers.bend:1368` uses for the same reason) and a `Bool`",
     "#          shape `helpers.bend:1366 symbol=pool_pads_dup.go` uses for the same reason) and a `Bool`")

# --------------------------------------------------------------------------- runtime/ops_python.bend
edit("tinybendygrad/runtime/ops_python.bend",
     "# comment on the lane, restated at symbolic.bend:822).",
     "# comment on the lane, restated at uop/symbolic.bend:825 symbol=f32_pow).")

# --------------------------------------------------------------------------- runtime/ops_dsp.bend
edit("tinybendygrad/runtime/ops_dsp.bend",
     "# TODO(p3) LAWS/spec.bend:76  Dt.nm -- the name reader this file matches on.",
     "# TODO(p3) LAWS/spec.bend:76 symbol=Dt  Dt.nm -- the name reader this file matches on.")

# --------------------------------------------------------------------------- runtime/device.bend
edit("tinybendygrad/runtime/device.bend",
     "# (`runtime/support/compiler_cpu.bend:268 ClangCompiler.compile_argv`), and it is",
     "# (`runtime/support/compiler_cpu.bend:268 symbol=ClangCompiler.compile_argv`), and it is")

# --------------------------------------------------------------------------- renderer/amd/elf.bend
edit("tinybendygrad/renderer/amd/elf.bend",
     "#               BLOCKER: `u.addrspace` is `ops.py:896`, still\n"
     "#               `TODO(p3)` in `uop/ops.bend:3773`. `u.dtype.itemsize` is",
     "#               BLOCKER: `u.addrspace` is `ops.py:896` and IS PORTED -- the port's\n"
     "#               `uop/fold.bend:4755 symbol=UOp.addrspace` is it. `u.dtype.itemsize` is")

# --------------------------------------------------------------------------- renderer/amd/generate.bend
edit("tinybendygrad/renderer/amd/generate.bend",
     "# calls `tag | line`.  The fix `cstyle.bend:1760` writes down for this --\n"
     "# `esc_row`, a newline turned into a backslash and an `n` -- FAILS TWICE OVER",
     "# calls `tag | line`.  The fix `renderer/cstyle.bend` NO LONGER CARRIES -- an `esc_row` is\n"
     "# not a construct there -- is a newline INSIDE the record, at renderer/amd/generate.bend:2599 symbol=fx_ps -- FAILS TWICE OVER")

# --------------------------------------------------------------------------- codegen/opt/heuristic.bend
edit("tinybendygrad/codegen/opt/heuristic.bend",
     "# which `codegen/rewriter.bend:52` already reports as ported with the env opt as a\n"
     "# PARAMETER -- so that half is available once that file is in the tree.",
     "# which `codegen/late/coalesce.bend:72 symbol=image_valid_dims` already reports as\n"
     "# ported with the env opt as a PARAMETER -- so that half is available once it lands.")

# --------------------------------------------------------------------------- extra/datasets/*.bend  (the `fetch` seam)
edit("tinybendygrad/extra/datasets/__init__.bend",
     "#   (1) `fetch` ITSELF. `tinybendygrad/helpers.bend:3193` records the whole HTTP",
     "#   (1) `fetch` ITSELF. `tinybendygrad/helpers.bend:3194` records the whole HTTP")

edit("tinybendygrad/extra/datasets/kits19.bend",
     "#   MISSING: `fetch` (upstream:24, the `helpers.bend:3193` HTTP seam) which",
     "#   MISSING: `fetch` (upstream:24, the `helpers.bend:3194` HTTP seam) which")

edit("tinybendygrad/extra/datasets/openimages.bend",
     "#     (upstream:108); `fetch` for the three CSVs (the `helpers.bend:3193` HTTP seam);",
     "#     (upstream:108); `fetch` for the three CSVs (the `helpers.bend:3194` HTTP seam);")

edit("tinybendygrad/extra/datasets/squad.bend",
     "#   MISSING: `fetch` (the `helpers.bend:3193` HTTP seam, upstream:11); a JSON reader",
     "#   MISSING: `fetch` (the `helpers.bend:3194` HTTP seam, upstream:11); a JSON reader")

# --------------------------------------------------------------------------- function.bend
edit("tinybendygrad/function.bend",
     "# subterm the decrease check looks for. The spelling is `helpers.bend:401`'s.",
     "# subterm the decrease check looks for. The spelling is `helpers.bend:401 symbol=CV`'s.")

# --------------------------------------------------------------------------- base.bend
edit("tinybendygrad/base.bend",
     "# `runtime/ops_python.bend:274-278` had already measured this (`w32`/`f32_of`)\n"
     "# and had no way to hand it to `dtype.bend`.",
     "# `runtime/ops_python.bend:299` had already measured this (`w32`/`f32_of`); that pair\n"
     "# is now a duplicate retired in favour of `F.F32.from_bits`, and it had no way to hand it to `dtype.bend`.")

# --------------------------------------------------------------------------- engine/realize.bend
edit("tinybendygrad/engine/realize.bend",
     "# BUFFER, and for those the fold's PARAM arm IS `arg.device` (fold.bend:1045), so",
     "# BUFFER, and for those the fold's PARAM arm IS `arg.device` (uop/fold.bend:2222 symbol=device_of.param), so")

# --------------------------------------------------------------------------- codegen/late/linearizer.bend
edit("tinybendygrad/codegen/late/linearizer.bend",
     "# BINARY one `graph_rewrite` at a time (kernel.bend:466-472), and whose stage",
     "# BINARY one `graph_rewrite` at a time (codegen/kernel.bend:816 symbol=pm_to_program), and whose stage")

# --------------------------------------------------------------------------- codegen/kernel.bend
edit("tinybendygrad/codegen/kernel.bend",
     "# B1's own RE-PORT -- `ad117c928` lists `kernel.bend:353` by name -- and folding",
     "# B1's own RE-PORT -- `ad117c928` lists `kernel.bend`'s line 353 by name -- and folding")
edit("tinybendygrad/codegen/kernel.bend",
     "# that a three-row move owes. `uop/ops.bend` already keeps `AXIS_UNROLL` for",
     "# that a three-row move owes. `ad117c928` names that line -- the `build_range_map` doc-comment -- and the port carries it at codegen/kernel.bend:367 symbol=kn_unroll.ax. `uop/ops.bend` already keeps `AXIS_UNROLL` for")
# --------------------------------------------------------------------------- codegen/opt/search.bend
edit("tinybendygrad/codegen/opt/search.bend",
     "# which is the `device.bend` `sig=0 4 5` shape; `postrange.bend:772-778` still quotes the\n"
     "# OLD set and is not this file's to fix.",
     "# which is the `device.bend` `sig=0 4 5` shape; `codegen/opt/postrange.bend:721-731\n"
     "# symbol=get_kernel_actions` still quotes the OLD set and is not this file's to fix.")

# --------------------------------------------------------------------------- renderer/amd/dsl.bend
edit("tinybendygrad/renderer/amd/dsl.bend",
     "# `F32{data: Word(32n)}` and `Word` is not exported -- the identical wall\n"
     "# `tinybendygrad/tensor.bend:308` and `tinybendygrad/renderer/wgsl.bend:59`\n"
     "# record, for the identical reason.",
     "# `F32{data: Word(32n)}` and `Word` is not exported -- the identical wall\n"
     "# `tinybendygrad/tensor.bend:1214 symbol=tn_const` and\n"
     "# `tinybendygrad/renderer/wgsl.bend:340 symbol=nan_thr` record, for the identical reason.")

# --------------------------------------------------------------------------- uop/fold.bend  (CONTESTED -- see the report)
edit("tinybendygrad/uop/fold.bend",
     "    #     mapped to the INS arg at :910) IS that pair, and `uop/spec.bend:1043-1047`\n"
     "    #     already gates CUSTOM and CUSTOMI on it: \"`AInk` IS that pair, and it is the\n"
     "    #     only constructor that is\".",
     "    #     mapped to the INS arg at :910) IS that pair, and `uop/spec.bend:1082\n"
     "    #     symbol=sh_21` already gates CUSTOM and CUSTOMI on it: \"`AInk` IS that pair,\n"
     "    #     and it is the only constructor that is\".")

# --------------------------------------------------------------------------- uop/validate.bend (CONTESTED -- see the report)
edit("tinybendygrad/uop/validate.bend",
     "# by `uop/fold.bend` (fold.bend:2482, \"the wall is arithmetic, not the fold\").",
     "# by `uop/fold.bend` (uop/fold.bend:5175 symbol=UOp.min_max is the reader, and the walk behind it is that file's P3 work queue).")


def main() -> int:
  root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
  bad = 0
  counts: dict[str, tuple[int, int]] = {}
  for rel, old, new in EDITS:
    p = root / rel
    s = p.read_text(encoding="utf-8")
    n = s.count(old)
    if n != 1:
      print(f"SKIP (count={n}) {rel}: {old[:70]!r}")
      bad += 1
      continue
    before = len(s.splitlines())
    after = len(s.replace(old, new).splitlines())
    counts[rel] = (counts.get(rel, (0, 0))[0] + before - after,
                   counts.get(rel, (0, 0))[1])
    p.write_text(s.replace(old, new), encoding="utf-8")
  print(f"APPLIED {len(EDITS) - bad} of {len(EDITS)}")
  print("LINE-COUNT DELTA PER FILE (must be 0 for every file others cite by line):")
  for rel, (d, _) in sorted(counts.items()):
    mark = "OK " if d == 0 else "!! "
    print(f"  {mark}{rel}: {d:+d}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
