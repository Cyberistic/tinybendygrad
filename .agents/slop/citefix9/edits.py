#!/usr/bin/env python3
"""edits.py -- THE EDIT SET: (file, line, the OLD line's tail, the NEW line).

    .venv/bin/python .agents/slop/citefix9/edits.py [--apply]

Every edit is COMMENT-ONLY and keeps the file's LINE COUNT, because a `.bend` file's
line numbers are an INTERFACE: other files cite them.

The OLD text is given as a TAIL to match on, so an edit cannot land on the wrong line
after an earlier edit moved the text around.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

# (rel, lineno, old_tail, new_line)
EDITS: list[tuple[str, int, str, str]] = [
  # ---- codegen/decomp/dtype.bend : the three fp conversions are in the TOP-LEVEL dtype.py
  ("tinybendygrad/codegen/decomp/dtype.bend", 99,
   "(`dtype.py:225/229/244`,",
   "# `float_to_fp16` / `float_to_bf16` / `float_to_fp8` (`tinygrad/dtype.py:219/223/238`,"),

  # ---- codegen/decomp/transcendental.bend : polyN is tinygrad/helpers.py:154
  ("tinybendygrad/codegen/decomp/transcendental.bend", 93,
   "`polyN` (helpers.py:153)",
   "# 6. `polyN` (tinygrad/helpers.py:154) IS SEEDED WITH THE PYTHON FLOAT `0.0`, so its"),

  # ---- examples/test_pkl_imagenet.bend : `hit += y == t` is examples/test_pkl_imagenet.py:18
  ("tinybendygrad/examples/test_pkl_imagenet.bend", 123,
   "`hit += y == t`       (:18)",
   "#     `hit += y == t`       (examples/test_pkl_imagenet.py:18)  host integer arithmetic over a REALIZED"),

  # ---- extra/datasets/preprocess_imagenet.bend : three `def iterate` sites, one per line
  ("tinybendygrad/extra/datasets/preprocess_imagenet.bend", 10,
   "is `kits19.py:73`, `squad.py:133` and",
   "# `def iterate` under `extra/datasets/` is `datasets/kits19.py:73`,"),
  ("tinybendygrad/extra/datasets/preprocess_imagenet.bend", 11,
   "# `librispeech.py:67`;",
   "# `squad.py:133` and `librispeech.py:67`; `grep -n iterate extra/datasets/imagenet.py` is empty. So this"),

  # ---- extra/models/bert.bend
  ("tinybendygrad/extra/models/bert.bend", 59,
   "MISSING (bert.py:61, bert.py:72).",
   "#   (6) `Tensor.binary_crossentropy_logits` MISSING (extra/models/bert.py:61, extra/models/bert.py:72)."),
  ("tinybendygrad/extra/models/bert.bend", 66,
   "at bert.py:182, where",
   "# FIRST MISSING SYMBOL: `Embedding(vocab_size, hidden_size)` at extra/models/bert.py:182, where"),
  ("tinybendygrad/extra/models/bert.bend", 67,
   "alias at bert.py:9 and",
   "# `Embedding = nn.Embedding` is the module-level alias at extra/models/bert.py:9 and there is no `def Embedding`"),
  ("tinybendygrad/extra/models/bert.bend", 77,
   "bert.py:78-124 reads",
   "# TREATED AS ONE. extra/models/bert.py:78-124 reads a TENSORFLOW checkpoint through"),
  ("tinybendygrad/extra/models/bert.bend", 78,
   "# `tf.train.list_variables`, and bert.py:24-31 reads a TORCH checkpoint through",
   "# `tf.train.list_variables` (extra/models/bert.py:85), and the TORCH loader is"),
  ("tinybendygrad/extra/models/bert.bend", 79,
   "# `torch.load`. `helpers.bend:3193` already records the whole weight-download",
   "# `extra/models/bert.py:24-31`, whose `torch.load` is at extra/models/bert.py:26. `helpers.bend:3193`"),
  ("tinybendygrad/extra/models/bert.bend", 80,
   "# seam as unported I/O, and neither framework has a counterpart. Named here so no",
   "# already records the whole weight-download seam as unported I/O, and neither framework"),
  ("tinybendygrad/extra/models/bert.bend", 81,
   "# reader counts them as arithmetic left undone.",
   "# has a counterpart. Named here so no reader counts them as arithmetic left undone."),

  # ---- extra/models/clip.bend : `.cos`/`.sin` are extra/models/llama.py:10
  ("tinybendygrad/extra/models/clip.bend", 63,
   "(llama.py:10 needs",
   "#   `x.sin`/`x.cos`  NOT NAMED BY clip.py. (extra/models/llama.py:10 needs `.cos` and there is"),

  # ---- extra/models/convnext.bend : `self.running_mean.assign(...)` is tinygrad/nn/__init__.py:56
  ("tinybendygrad/extra/models/convnext.bend", 69,
   "# (\"`Tensor.assign` -- op.py:56-57 `self.running_mean.assign(...)`\", and",
   "# (\"`Tensor.assign` -- tinygrad/nn/__init__.py:56 `self.running_mean.assign(...)`\", and"),

  # ---- extra/models/mask_rcnn.bend
  ("tinybendygrad/extra/models/mask_rcnn.bend", 66,
   "#     and llama.py:10 needs `.cos` too -- `mixin/elementwise.bend:550` has",
   "#     and extra/models/llama.py:10 needs `.cos` too -- `mixin/elementwise.bend:550` has"),

  # ---- extra/models/retinanet.bend : one_hot at retinanet.py:151, bert.py:164, transformer.py:54
  ("tinybendygrad/extra/models/retinanet.bend", 48,
   "#   `Tensor.one_hot`   MISSING (:151) -- new to this slice, and shared with bert.py",
   "#   `Tensor.one_hot`   MISSING (extra/models/retinanet.py:151) -- new to this slice, and"),
  ("tinybendygrad/extra/models/retinanet.bend", 49,
   "#                 (:164) and transformer.py (:54).",
   "#                 shared with bert.py's `onehot` (extra/models/bert.py:164) and `one_hot` (extra/models/transformer.py:54)."),

  # ---- extra/models/vit.bend : the same `self.running_mean.assign(...)`
  ("tinybendygrad/extra/models/vit.bend", 67,
   "# op.py:56-57 `self.running_mean.assign(...)`\", and `tensor.bend:2539` states the",
   "# tinygrad/nn/__init__.py:56 `self.running_mean.assign(...)`\", and `tensor.bend:2539` states the"),

  # ---- nn/__init__.bend : `arange` is tinygrad/mixin/op.py:166
  ("tinybendygrad/nn/__init__.bend", 93,
   "`arange` is op.py:166.",
   "#     mixin/reduce.py, `arange` is tinygrad/mixin/op.py:166. NONE is mine and none is built, so"),

  # ---- nn/layers.bend : `linear` and `dot` are tinygrad/mixin/op.py
  ("tinybendygrad/nn/layers.bend", 13,
   "#     `Tensor.linear` (op.py:1254) is",
   "#     `Tensor.linear` (tinygrad/mixin/op.py:1254) is"),
  ("tinybendygrad/nn/layers.bend", 15,
   "#     `dot` (op.py:367) is",
   "#     `dot` (tinygrad/mixin/op.py:367) is"),

  # ---- renderer/ptx.bend : `to_function_name` is tinygrad/helpers.py:158
  ("tinybendygrad/renderer/ptx.bend", 31,
   "`ansistrip` (helpers.py:157)",
   "#   * `to_function_name`'s `ansistrip` (tinygrad/helpers.py:158) -- a regex ANSI strip."),

  # ---- renderer/tc_ptx.bend : `strong_dtype` is tinygrad/dtype.py:169
  ("tinybendygrad/renderer/tc_ptx.bend", 56,
   "# `strong_dtype(dtype)`'s PTX type (`dtype.py:169-170`), so `types[strong_dtype",
   "# `strong_dtype(dtype)`'s PTX type (`tinygrad/dtype.py:169-170`), so `types[strong_dtype"),

  # ---- uop/symbolic.bend : `floordiv` is tinygrad/helpers.py:77, `truncate` is tinygrad/dtype.py:289
  ("tinybendygrad/uop/symbolic.bend", 75,
   "is given by helpers.py:76.",
   "#    `U32.div(a,0) = 0` is the number Python's `floordiv` is given by tinygrad/helpers.py:77."),
  ("tinybendygrad/uop/symbolic.bend", 85,
   "#      b. `truncate` (dtype.py:297) is",
   "#      b. `truncate` (tinygrad/dtype.py:289) is"),

  # ---- uop/weak.bend : `DType.const` is tinygrad/dtype.py:79
  ("tinybendygrad/uop/weak.bend", 35,
   "# THE SECOND WALL is `DType.const` (dtype.py:79-84) for",
   "# THE SECOND WALL is `DType.const` (tinygrad/dtype.py:79-84) for"),

  # ---- mixin/creation.bend : `argfix` is tinygrad/helpers.py:22
  ("tinybendygrad/mixin/creation.bend", 120,
   "#   6. `argfix(*shape)` (helpers.py:24) COLLAPSES",
   "#   6. `argfix(*shape)` (tinygrad/helpers.py:22) COLLAPSES"),
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
