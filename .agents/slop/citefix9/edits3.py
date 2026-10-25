#!/usr/bin/env python3
"""edits3.py -- THE THIRD EDIT SET: the rows the census still reports, and the AMBIENT
regressions the second set caused.

    .venv/bin/python .agents/slop/citefix9/edits3.py [--apply]

THE AMBIENT. `gates/header-census-gate.py`'s `declared_target` is THE FIRST
`tinygrad/...py` path in a header block, and EVERY bare `:N` in that block resolves
against it. So introducing a `tinygrad/...py` path can SILENTLY RE-aim every bare
citation in the file. The spelling `dir/name.py` (no `tinygrad/` prefix) resolves
uniquely in both instruments and moves NO ambient.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

EDITS: list[tuple[str, int, str, str]] = [
  # ---- llama.bend : `nn/optim.py` is unique AND does not become the declared target
  ("tinybendygrad/extra/models/llama.bend", 33,
   "`assign` at tinygrad/nn/optim.py:167,",
   "#                   `assign` at nn/optim.py:167, and nn/optim.bend:903 `op_vstep`"),
  ("tinybendygrad/extra/models/llama.bend", 34,
   "`assign` at tinygrad/nn/optim.py:168;",
   "#                   is upstream's `assign` at nn/optim.py:168; `op_mhat`/`op_vhat` are"),
  ("tinybendygrad/extra/models/llama.bend", 35,
   "`m_hat`/`v_hat` at tinygrad/nn/optim.py:169-170.",
   "#                   upstream's `m_hat`/`v_hat` at nn/optim.py:169-170. The optimizer"),

  # ---- transformer.bend : `mixin/rand.py` is unique AND does not become the target
  ("tinybendygrad/extra/models/transformer.bend", 52,
   "-- `tinygrad/mixin/rand.py:298`.",
   "-- `mixin/rand.py:298`."),

  # ---- rnnt.bend : `mixin/op.py` is unique AND does not become the target
  ("tinybendygrad/extra/models/rnnt.bend", 77,
   "(tinygrad/mixin/op.py:22)",
   "(mixin/op.py:22)"),
  ("tinybendygrad/extra/models/rnnt.bend", 78,
   "(tinygrad/mixin/op.py:20)",
   "(mixin/op.py:20)"),
  ("tinybendygrad/extra/models/rnnt.bend", 81,
   "#       at :45 with `numpy` and :46 and writes it into a fresh Tensor, so it cannot be a graph.",
   "#       at extra/models/rnnt.py:45 with `numpy` and extra/models/rnnt.py:46 and writes it into a fresh Tensor, so it cannot be a graph."),
  ("tinybendygrad/extra/models/rnnt.bend", 82,
   "#   (8) `unsqueeze` (:26,:38,:196,:197) --",
   "#   (8) `unsqueeze` (extra/models/rnnt.py:26, :38, :196, :197) --"),
  ("tinybendygrad/extra/models/rnnt.bend", 97,
   "# `Encoder` (:11) -- FOUR `Linear`s and two `LSTM`s -- before it reaches `Prediction`,",
   "# `Encoder` (extra/models/rnnt.py:11) -- FOUR `Linear`s and two `LSTM`s -- before it reaches `Prediction`,"),

  # ---- vit.bend : `nn/__init__.py` is unique AND does not become the target
  ("tinybendygrad/extra/models/vit.bend", 67,
   "# tinygrad/nn/__init__.py:56 `self.running_mean.assign(...)`",
   "# nn/__init__.py:56 `self.running_mean.assign(...)`"),

  # ---- nn/layers.bend : `mixin/op.py` is unique AND does not become the target
  ("tinybendygrad/nn/layers.bend", 13,
   "(tinygrad/mixin/op.py:1254)",
   "(mixin/op.py:1254)"),
  ("tinybendygrad/nn/layers.bend", 15,
   "(tinygrad/mixin/op.py:367)",
   "(mixin/op.py:367)"),

  # ---- engine/jit.bend : the claim must name the construct upstream HAS at the pin
  ("tinybendygrad/engine/jit.bend", 35,
   "#   jit.py:67 symbol=_jit_bufs   UPSTREAM AT THE PIN: `_written_uops` IS GONE -- upstream",
   "#   jit.py:67 symbol=_jit_bufs   `_jit_bufs` IS UPSTREAM AT THE PIN: `_written_uops` IS GONE"),

  # ---- mixin/creation.bend : `const_like` reads `self._shape` at ops.py:581-583
  ("tinybendygrad/mixin/creation.bend", 62,
   "#        (ops.py:605) directly and never goes through `_broadcast_to`.",
   "#        (tinygrad/uop/ops.py:581-583) directly and never goes through `_broadcast_to`."),

  # ---- nn/optim.bend : `sqrt` must be a CLAIM TOKEN of the `sqrt` citation
  ("tinybendygrad/nn/optim.bend", 59,
   "#   * `sqrt` -- tinygrad/mixin/elementwise.py:479 symbol=sqrt (`Ops.SQRT`), optim.py:113, :114, :173, :174.",
   "#   * `sqrt` -- tinygrad/mixin/elementwise.py:479 symbol=sqrt (`sqrt`, `Ops.SQRT`), optim.py:113, :114, :173, :174."),

  # ---- renderer/llvmir.bend : the fp8/fp16 VALUES are in the TOP-LEVEL dtype.py
  ("tinybendygrad/renderer/llvmir.bend", 188,
   "#     `float_to_fp8` (tinygrad/dtype.py:238) and `truncate` (tinygrad/dtype.py:289), so they are",
   "#     (tinygrad/dtype.py:238) `float_to_fp8` and `truncate` (tinygrad/dtype.py:289), so they are"),

  # ---- renderer/isa/x86.bend : the two markers name the constructs they cite
  ("tinybendygrad/renderer/isa/x86.bend", 156,
   "#   MINTS a `Register` with `itertools.count()`. `TODO(p3) x86.py:293 symbol=alloc_vregs`.",
   "#   MINTS a `Register` with `itertools.count()`. `alloc_vregs` -- `TODO(p3) x86.py:293 symbol=alloc_vregs`."),
  ("tinybendygrad/renderer/isa/x86.bend", 158,
   "#   `lock` / `stack_allocated` / `stack_size` state above. `TODO(p3) x86.py:681 symbol=X86LinearContext`.",
   "#   `lock` / `stack_allocated` / `stack_size` state above -- `X86LinearContext`. `TODO(p3) x86.py:681-707 symbol=X86LinearContext`."),

  # ---- tensor.bend : `new_buffer` must be a CLAIM TOKEN of the `new_buffer` citation
  ("tinybendygrad/tensor.bend", 29,
   "#      (tinygrad/uop/ops.py:835 symbol=new_buffer) and `_frompy`",
   "#      (tinygrad/uop/ops.py:835 symbol=new_buffer) `new_buffer` and `_frompy`"),

  # ---- renderer/ptx.bend : `to_function_name` is at tinygrad/helpers.py:157
  ("tinybendygrad/renderer/ptx.bend", 31,
   "(tinygrad/helpers.py:158)",
   "(tinygrad/helpers.py:157)"),

  # ---- renderer/llvmir.bend : the ORACLE is a PORT file, so it is named, not cited
  ("tinybendygrad/renderer/llvmir.bend", 67,
   "# and `llvmir-oracle.py:647-648` each list the tuple `(1, dtypes.f32, True)` twice in the",
   "# and the PORT'S OWN ORACLE (`llvmir-oracle.py`, lines 647-648) each list the tuple"),
  ("tinybendygrad/renderer/llvmir.bend", 68,
   "# same `lt` count/ptr table, so the fourth entry is the first again. This is the",
   "# `(1, dtypes.f32, True)` twice in the same `lt` count/ptr table, so the fourth entry is"),
  ("tinybendygrad/renderer/llvmir.bend", 69,
   "# `nv_query_litter` shape agent-core.md records -- wrong in the PORT and in the ORACLE, so",
   "# the first again. This is the `nv_query_litter` shape agent-core.md records -- wrong in"),
  ("tinybendygrad/renderer/llvmir.bend", 70,
   "# the differ reports 0 disagreements over a mistake made twice. Deleting the repeat costs no",
   "# the PORT and in the ORACLE, so the differ reports 0 disagreements over a mistake made"),
  ("tinybendygrad/renderer/llvmir.bend", 71,
   "# coverage (the claim is identical); GUESSING what the fourth entry was meant to be would",
   "# twice. Deleting the repeat costs no coverage (the claim is identical); GUESSING what the"),
  ("tinybendygrad/renderer/llvmir.bend", 72,
   "# invent a row, so it is REPORTED. `llvmir-gate.py --drop-dup` shows what the lane reads like",
   "# fourth entry was meant to be would invent a row, so it is REPORTED. `llvmir-gate.py --drop-dup`"),
  ("tinybendygrad/renderer/llvmir.bend", 73,
   "# without it: 470 rows, 470 names, AGREE, rc=0.",
   "# shows what the lane reads like without it: 470 rows, 470 names, AGREE, rc=0."),

  # ---- nn/onnx.bend : the RUNNERS, one pair per line, the names in the middle
  ("tinybendygrad/nn/onnx.bend", 37,
   "#     `_init_from_graph` onnx.py:298 symbol=_init_from_graph, `_from_subgraph`",
   "#     onnx.py:298 symbol=_init_from_graph, `_init_from_graph` `_from_subgraph`"),
  ("tinybendygrad/nn/onnx.bend", 38,
   "#     onnx.py:313 symbol=_from_subgraph, `_parse_input` onnx.py:318 symbol=_parse_input, `to` onnx.py:345 symbol=to,",
   "#     onnx.py:313 symbol=_from_subgraph, `_parse_input` `_to` onnx.py:318 symbol=_parse_input, onnx.py:345 symbol=to,"),
  ("tinybendygrad/nn/onnx.bend", 39,
   "#     `_get_python_const` onnx.py:352 symbol=_get_python_const, `__call__` onnx.py:361 symbol=__call__) and the protobuf layer they stand on.",
   "#     `_get_python_const` `__call__` onnx.py:352 symbol=_get_python_const, onnx.py:361 symbol=__call__) and the protobuf layer they stand on."),
]


def main() -> int:
  apply = "--apply" in sys.argv
  bad = 0
  by_file: dict[str, list[tuple[int, str, str]]] = {}
  for rel, at, old_tail, new in EDITS:
    by_file.setdefault(rel, []).append((at, old_tail, new))
  for rel, edits in by_file.items():
    path = ROOT / rel
    src = path.read_text().splitlines()
    n_before = len(src)
    for at, old_tail, new in sorted(edits, reverse=True):
      if at < 1 or at > len(src):
        print(f"FAIL {rel}:{at} is outside the file")
        bad += 1
        continue
      cur = src[at - 1]
      if cur == new:
        continue
      if old_tail not in cur:
        print(f"FAIL {rel}:{at} does not carry {old_tail!r}\n     it is: {cur!r}")
        bad += 1
        continue
      src[at - 1] = new
    if len(src) != n_before:
      print(f"FAIL {rel}: the line count moved")
      bad += 1
    if apply and bad == 0:
      path.write_text("\n".join(src) + "\n", encoding="utf-8")
  print(f"{len(EDITS)} edits over {len(by_file)} files; {bad} problem(s)")
  return 1 if bad else 0


if __name__ == "__main__":
  raise SystemExit(main())
