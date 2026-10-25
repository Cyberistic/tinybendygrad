#!/usr/bin/env python3
"""edits4.py -- THE FOURTH EDIT SET: the last rows the census reports.

    .venv/bin/python .agents/slop/citefix9/edits4.py [--apply]
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

EDITS: list[tuple[str, int, str, str]] = [
  # ---- mixin/creation.bend : `const_like` is at tinygrad/uop/ops.py:581-583
  ("tinybendygrad/mixin/creation.bend", 62,
   "#        (tinygrad/uop/ops.py:581-583) directly and never goes through `_broadcast_to`.",
   "#        (`const_like`, tinygrad/uop/ops.py:581-583) directly and never goes through `_broadcast_to`."),

  # ---- nn/onnx.bend : the RUNNERS, one pair per line
  ("tinybendygrad/nn/onnx.bend", 37,
   "#     onnx.py:298 symbol=_init_from_graph, `_init_from_graph` `_from_subgraph`",
   "#     onnx.py:298 symbol=_init_from_graph, `_from_subgraph` `_init_from_graph` onnx.py:313 symbol=_from_subgraph,"),
  ("tinybendygrad/nn/onnx.bend", 38,
   "#     onnx.py:313 symbol=_from_subgraph, `_parse_input` `_to` onnx.py:318 symbol=_parse_input, onnx.py:345 symbol=to,",
   "#     onnx.py:318 symbol=_parse_input, `_parse_input` `to(device)` onnx.py:345 symbol=to,"),
  ("tinybendygrad/nn/onnx.bend", 39,
   "#     `_get_python_const` `__call__` onnx.py:352 symbol=_get_python_const, onnx.py:361 symbol=__call__) and the protobuf layer they stand on.",
   "#     onnx.py:352 symbol=_get_python_const, `__call__` `_get_python_const` onnx.py:361 symbol=__call__) and the protobuf layer they stand on."),
  ("tinybendygrad/nn/onnx.bend", 67,
   "#   * `If`'s branch runner (onnx.py:468 symbol=run_branch) and `Gradient` (onnx.py:1216 symbol=Gradient) need an",
   "#   * `If`'s `run_branch` (onnx.py:468 symbol=run_branch) and `Gradient` need an"),
  ("tinybendygrad/nn/onnx.bend", 68,
   "#     `OnnxRunner` VALUE -- this file's own class -- and `Gradient` also needs",
   "#     `OnnxRunner` VALUE -- this file's own class -- and `Gradient` (onnx.py:1216 symbol=Gradient) also needs"),
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
