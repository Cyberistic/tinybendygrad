#!/usr/bin/env python3
"""edits2.py -- THE SECOND EDIT SET: the lines whose GEOMETRY (more than one citation on a
line, and the port's own vocabulary as the claim) needs the prose rewritten.

    .venv/bin/python .agents/slop/citefix9/edits2.py [--apply]

Same rules as edits.py: COMMENT-ONLY, and the file's LINE COUNT is unchanged, because a
`.bend` file's line numbers are an INTERFACE.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

EDITS: list[tuple[str, int, str, str]] = [
  # ---- engine/jit.bend : upstream DELETED `_written_uops` in `a26c50b01`
  ("tinybendygrad/engine/jit.bend", 35,
   "jit.py:62-64   _written_uops           PORTED, via realize.bend's `get_call_written_bufs`",
   "#   jit.py:67 symbol=_jit_bufs   UPSTREAM AT THE PIN: `_written_uops` IS GONE -- upstream"),
  ("tinybendygrad/engine/jit.bend", 36,
   "jit.py:71-73   _symbolic_ret           the comprehension; `get_parameters` is a seam",
   "#   jit.py:70-73   `_symbolic_ret`         DELETED it AND realize.py's `get_call_written_bufs`"),
  ("tinybendygrad/engine/jit.bend", 37,
   "jit.py:70-75   CapturedJit.__call__    the `concrete` fold, the `jit execs` threshold,",
   "#   jit.py:73-78   CapturedJit.__call__    in `a26c50b01`), so the PORT's copy of the"),
  ("tinybendygrad/engine/jit.bend", 38,
   "#                                           the var rebind",
   "#                                           latter has NO upstream counterpart at the pin"),

  # ---- examples/train_resnet.bend : the census is of examples/train_resnet.py, NOT extra/training.py
  ("tinybendygrad/examples/train_resnet.bend", 69,
   "#   `numpy` (:2, used :24,:26,:36,:37,:38)  MISSING. No n-d array library: the",
   "#   `numpy` (examples/train_resnet.py:2), used at :24 (`.astype`), :25 (`.astype`), :36 (`np.stack`) and :38 (`np.tile`). MISSING. No n-d array library: the"),

  # ---- extra/models/llama.bend
  ("tinybendygrad/extra/models/llama.bend", 28,
   "MISSING SYMBOL of the file: llama.py:53 `self.q_norm",
   "#   `nn.RMSNorm`    MISSING. (:53,:54,:137,:138,:200)  FIVE sites, and this is THE FIRST MISSING SYMBOL of the file: extra/models/llama.py:53 `self.q_norm"),
  ("tinybendygrad/extra/models/llama.bend", 32,
   "#                   `(self.b1 * self.m[i] + (1.0 - self.b1) * g).cast(...)` -- optim.py:167,",
   "#                   `(self.b1 * self.m[i] + (1.0 - self.b1) * g).cast(...)` -- verbatim, upstream's"),
  ("tinybendygrad/extra/models/llama.bend", 33,
   "#                   verbatim -- and :903 `op_vstep` is optim.py:168, and `op_mhat`/`op_vhat`",
   "#                   `assign` at tinygrad/nn/optim.py:167, and nn/optim.bend:903 `op_vstep`"),
  ("tinybendygrad/extra/models/llama.bend", 34,
   "#                   are optim.py:169,:170. The optimizer llama.py would train with is",
   "#                   is upstream's `assign` at tinygrad/nn/optim.py:168; `op_mhat`/`op_vhat` are"),
  ("tinybendygrad/extra/models/llama.bend", 35,
   "#                   ALREADY PORTED. llama.py only INFERENCES, and inference needs no adam.",
   "#                   upstream's `m_hat`/`v_hat` at tinygrad/nn/optim.py:169-170. The optimizer"),
  ("tinybendygrad/extra/models/llama.bend", 36,
   "#                   THAT IS THE ANSWER TO \"DOES A TRAINING LOOP NEED SOMETHING NEW\":",
   "#                   llama.py would train with is ALREADY PORTED; llama.py only INFERENCES."),
  ("tinybendygrad/extra/models/llama.bend", 37,
   "#                   NO. The adam half of this slice is DONE; what a training loop would",
   "#                   THAT IS THE ANSWER TO \"DOES A TRAINING LOOP NEED SOMETHING NEW\": NO. The"),
  ("tinybendygrad/extra/models/llama.bend", 38,
   "#                   add is a loss (`binary_crossentropy_logits`, bert.py:61, MISSING).",
   "#                   adam half is DONE; a training loop would add a loss (`binary_crossentropy_logits`, extra/models/bert.py:61, MISSING)."),
  ("tinybendygrad/extra/models/llama.bend", 59,
   "#   (2) `Tensor.erf`   MISSING. bert.py:236 needs it too.",
   "#   (2) `Tensor.erf`   MISSING. extra/models/bert.py:236 needs it too."),
  ("tinybendygrad/extra/models/llama.bend", 78,
   "# FIRST MISSING SYMBOL: `nn.RMSNorm(dim, qk_norm)` at llama.py:53, which the `if` at",
   "# FIRST MISSING SYMBOL: `nn.RMSNorm(dim, qk_norm)` at extra/models/llama.py:53, which the `if` at"),
  ("tinybendygrad/extra/models/llama.bend", 81,
   "# every configuration llama.py actually builds (`Transformer.__init__` :202 passes",
   "# every configuration llama.py actually builds -- `Transformer.__init__` at extra/models/llama.py:195-196"),
  ("tinybendygrad/extra/models/llama.bend", 82,
   "# `qk_norm` through, and every public config in meta's llama sets it).",
   "# passes `qk_norm` through at :199, and every public config in meta's llama sets it)."),

  # ---- extra/models/rnnt.bend : the bare `:NN` cites are extra/models/rnnt.py's lines
  ("tinybendygrad/extra/models/rnnt.bend", 77,
   "#       `mixin/op.bend:87-89` already names it -- \"`item` (op.py:22) and `data`",
   "#       `mixin/op.bend:87-89` already names it -- \"`item` (tinygrad/mixin/op.py:22) and `data`"),
  ("tinybendygrad/extra/models/rnnt.bend", 78,
   "#       (op.py:20) are NOT WALLS and are not ports: `data` is a",
   "#       (tinygrad/mixin/op.py:20) are NOT WALLS and are not ports: `data` is a"),
  ("tinybendygrad/extra/models/rnnt.bend", 80,
   "#       through it\". `_greedy_decode` reads a TENSOR BACK to the host at :45 and",
   "#       through it\". `_greedy_decode` (extra/models/rnnt.py:32) reads a TENSOR BACK to the host"),
  ("tinybendygrad/extra/models/rnnt.bend", 81,
   "#       :46 and writes it into a fresh Tensor, so it cannot be a graph.",
   "#       at :45 with `numpy` and :46 and writes it into a fresh Tensor, so it cannot be a graph."),
  ("tinybendygrad/extra/models/rnnt.bend", 82,
   "#   (8) `unsqueeze` (:26,:38,:195,:196,:197) -- `grep -rnE \"^def (mo|tn|ew)_unsqueeze\"` = 0.",
   "#   (8) `unsqueeze` (:26,:38,:196,:197) -- `grep -rnE \"^def (mo|tn|ew)_unsqueeze\"` = 0."),

  # ---- extra/models/transformer.bend
  ("tinybendygrad/extra/models/transformer.bend", 23,
   "# `Tensor.scaled_dot_product_attention` (transformer.py:27, :60) is MISSING, and",
   "# `Tensor.scaled_dot_product_attention` (extra/models/transformer.py:27) is MISSING, and"),
  ("tinybendygrad/extra/models/transformer.bend", 52,
   "#   (1) `Tensor.scaled_dot_product_attention` -- transform.py's `op.py:1177`. It is",
   "#   (1) `Tensor.scaled_dot_product_attention` -- `tinygrad/mixin/rand.py:298`. It is"),
  ("tinybendygrad/extra/models/transformer.bend", 59,
   "#       `TransformerBlock.__call__` (:32, :36, :38) and nothing else in this file",
   "#       `TransformerBlock.__call__`'s `x.layernorm()` (extra/models/transformer.py:32, :36, :38) and nothing else in this file"),

  # ---- function.bend : `param_like`'s BODY holds the `UOp` the claim names
  ("tinybendygrad/function.bend", 42,
   "#   `UOp.param_like`  ops.py:1228 symbol=param_like       `UOp.substitute`  ops.py:514 symbol=substitute",
   "#   `UOp.param_like`  ops.py:1228-1234 symbol=param_like  `UOp.substitute`  ops.py:514 symbol=substitute"),

  # ---- mixin/op.bend : `log_softmax` and `_softmax` get one citation each
  ("tinybendygrad/mixin/op.bend", 195,
   "# `log_softmax` (op.py:686 symbol=log_softmax) are TWO defs that both call `_softmax` (op.py:657 symbol=_softmax), so",
   "# `log_softmax` (op.py:686 symbol=log_softmax) are TWO defs that both call `_softmax`, so"),
  ("tinybendygrad/mixin/op.bend", 196,
   "# the thirteen nodes `_softmax` builds are interned ONCE. `softmax` prints 15 and",
   "# the thirteen nodes `_softmax` (op.py:657 symbol=_softmax) builds are interned ONCE."),

  # ---- nn/onnx.bend : the RUNNERS, one citation per line
  ("tinybendygrad/nn/onnx.bend", 37,
   "#     `_init_from_graph` onnx.py:298 symbol=_init_from_graph, `_from_subgraph` onnx.py:313 symbol=_from_subgraph, `_parse_input`",
   "#     `_init_from_graph` onnx.py:298 symbol=_init_from_graph, `_from_subgraph`"),
  ("tinybendygrad/nn/onnx.bend", 38,
   "#     onnx.py:318 symbol=_parse_input, `to` onnx.py:345 symbol=to, `_get_python_const` onnx.py:352 symbol=_get_python_const, `__call__` onnx.py:361 symbol=__call__)",
   "#     onnx.py:313 symbol=_from_subgraph, `_parse_input` onnx.py:318 symbol=_parse_input, `to` onnx.py:345 symbol=to,"),
  ("tinybendygrad/nn/onnx.bend", 39,
   "#     and the protobuf layer they stand on. THE WALL IS NAMED PER ARM below.",
   "#     `_get_python_const` onnx.py:352 symbol=_get_python_const, `__call__` onnx.py:361 symbol=__call__) and the protobuf layer they stand on."),

  # ---- nn/optim.bend : `sqrt` is at tinygrad/mixin/elementwise.py:479
  ("tinybendygrad/nn/optim.bend", 59,
   "#   * `sqrt` -- elementwise.py:479 symbol=sqrt (`Ops.SQRT`), optim.py:113, :114, :173, :174.",
   "#   * `sqrt` -- tinygrad/mixin/elementwise.py:479 symbol=sqrt (`Ops.SQRT`), optim.py:113, :114, :173, :174."),

  # ---- renderer/isa/x86.bend : the two TODO(p3) markers name their constructs
  ("tinybendygrad/renderer/isa/x86.bend", 155,
   "# * `alloc_vregs` (py:293-307) -- reads `ctx.reg_n`, calls `ctx.vreg`, which",
   "# * `alloc_vregs` (py:293-307) -- reads `ctx.reg_n`, calls `ctx.vreg`, which"),
  ("tinybendygrad/renderer/isa/x86.bend", 156,
   "#   MINTS a `Register` with `itertools.count()`. `TODO(p3) x86.py:293 symbol=alloc_vregs`.",
   "#   MINTS a `Register` with `itertools.count()`. `TODO(p3) x86.py:293 symbol=alloc_vregs`."),
  ("tinybendygrad/renderer/isa/x86.bend", 158,
   "#   `lock` / `stack_allocated` / `stack_size` state above. `TODO(p3) x86.py:681 symbol=X86LinearContext`.",
   "#   `lock` / `stack_allocated` / `stack_size` state above. `TODO(p3) x86.py:681 symbol=X86LinearContext`."),

  # ---- renderer/wgsl.bend : the two TODO(p3) markers name their constructs
  ("tinybendygrad/renderer/wgsl.bend", 14,
   "#   TODO(p3) wgsl.py:15  packed_store -- ditto, plus `.load`/`.store`",
   "#   TODO(p3) wgsl.py:15  `packed_store` -- ditto, plus `.load`/`.store`"),
  ("tinybendygrad/renderer/wgsl.bend", 15,
   "#   TODO(p3) wgsl.py:24  packed_load  -- ditto, plus `.index`",
   "#   TODO(p3) wgsl.py:24  `packed_load`  -- ditto, plus `.index`"),

  # ---- tensor.bend : `new_buffer` is at tinygrad/uop/ops.py:835
  ("tinybendygrad/tensor.bend", 29,
   "#      (ops.py:835 symbol=new_buffer) and `_frompy` (ops.py:855 symbol=_frompy) build a BUFFER node PLUS an opaque",
   "#      (tinygrad/uop/ops.py:835 symbol=new_buffer) and `_frompy` (tinygrad/uop/ops.py:855 symbol=_frompy) build a BUFFER node PLUS an opaque"),

  # ---- renderer/llvmir.bend : the fp8/fp16 VALUES live in the TOP-LEVEL dtype.py
  ("tinybendygrad/renderer/llvmir.bend", 188,
   "#     `float_to_fp8` (dtype.py:244) and `truncate` (dtype.py:295), so they are",
   "#     `float_to_fp8` (tinygrad/dtype.py:238) and `truncate` (tinygrad/dtype.py:289), so they are"),
  ("tinybendygrad/renderer/llvmir.bend", 192,
   "#   * `float_to_fp8`'s `_fp8_cfg` (dtype.py:236-241) is dtype.py's.",
   "#   * `float_to_fp8`'s `_fp8_cfg` (tinygrad/dtype.py:231-236) is dtype.py's."),

  # ---- schedule/multi.bend : fold.bend names the OLD upstream line; the pin's is 1094
  ("tinybendygrad/schedule/multi.bend", 16,
   "# `copy_multi`. `fold.bend` names it `ops.py:1104` in its own PROSE and carries it as",
   "# `copy_multi`. `fold.bend:5081` names it at 1104 in its own PROSE and carries it as"),

  # ---- uop/render.bend : upstream DELETED the pyrender round-trip
  ("tinybendygrad/uop/render.bend", 69,
   "# `tinygrad/uop/spec.py:293` does `exec(code, pyrender_globals(), lcls)` on the",
   "# `tinygrad/uop/spec.py` HAS NO `exec` AT THE PIN: upstream DELETED the whole"),
  ("tinybendygrad/uop/render.bend", 70,
   "# string `pyrender` produced and reads back `lcls['ast']`. That is not a missing",
   "# `pyrender` round-trip in `81157efb0` (\"use render_uir instead of pyrender\"), and"),
  ("tinybendygrad/uop/render.bend", 71,
   "# primitive; it is a missing language. The generated text names `UOp`, `Ops`,",
   "# `tinygrad/uop/spec.py:41` now PRINTS `render_uir(lst)` under `DEBUG >= 3` instead of"),
  ("tinybendygrad/uop/render.bend", 72,
   "# `dtypes`, `KernelInfo`, `ParamArg` and a dozen other CPython objects as GLOBALS",
   "# EXECUTING a rendered string. `render_uir` is `tinygrad/uop/render.py:65"),
  ("tinybendygrad/uop/render.bend", 73,
   "# in a namespace built by a Python `import`. Bend has no `exec`, no globals dict",
   "# symbol=render_uir` and a METHOD on `UOp` (`tinygrad/uop/ops.py:1181"),
  ("tinybendygrad/uop/render.bend", 74,
   "# and no value that knows its own type's name, so the round trip has no",
   "# symbol=render_uir`). So there is NO upstream round trip to port, and"),
  ("tinybendygrad/uop/render.bend", 75,
   "# representation at all -- not a hard one, not a deferred one.",
   "# `test_pyrender` IS GONE UPSTREAM TOO: that is not a missing primitive, it is a"),
  ("tinybendygrad/uop/render.bend", 76,
   "#",
   "# missing language. The generated text names `UOp`, `Ops`, `dtypes`, `KernelInfo`,"),
  ("tinybendygrad/uop/render.bend", 77,
   "# `upat.bend` already settled the precedent for this repo: the pattern COMPILER",
   "# `ParamArg` and a dozen other CPython objects as GLOBALS in a namespace built by"),
  ("tinybendygrad/uop/render.bend", 78,
   "# EMITS PYTHON TEXT and the Bend side is a hand-written dispatch instead. So the",
   "# a Python `import`. Bend has no `exec`, no globals dict and no value that knows"),
  ("tinybendygrad/uop/render.bend", 79,
   "# correct port of `pyrender` is to emit the text and NOT round-trip it, and",
   "# its own type's name, so the round trip has no representation at all."),
  ("tinybendygrad/uop/render.bend", 80,
   "# `test_pyrender` (`spec.py:296`) becomes the string-diff gate at the foot of",
   "# `upat.bend` settled the precedent: the pattern COMPILER EMITS PYTHON TEXT and the"),
  ("tinybendygrad/uop/render.bend", 81,
   "# this file instead of an `exec`. Recording it, not engineering around it.",
   "# Bend side is a hand-written dispatch; the string-diff gate at the foot of this file"),
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
