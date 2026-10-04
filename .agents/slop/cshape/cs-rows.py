#!/usr/bin/env python3
"""cs-rows.py -- THE PY SIDE OF THE PATTERN-COMPILER IR, AT EACH WIDENING OF `cshape`.

`graphcmp.cshape` is monkeypatched IN THIS PROCESS ONLY, so the live `graphcmp.py` is
never edited by this unit. The patch is one `except` arm per widening, and the rows are
printed for EVERY widening side by side, because the danger is not "does it emit" but
"does the widening change any row that was already emitted".

    env -u PYTHONPATH LC_ALL=C DEV=CPU .venv/bin/python .agents/slop/cshape/cs-rows.py
"""
from __future__ import annotations

import os
import sys

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
sys.path.insert(0, REPO)
sys.path.insert(0, os.path.join(REPO, ".agents/slop"))
os.environ["DEV"] = "CPU"

import graphcmp as G  # noqa: E402

G.load_tinygrad()
G.COMM = G.commutative()

from tinygrad.uop.ops import UOp, UPat, Ops  # noqa: E402
from tinygrad.uop.upat import _get_clause  # noqa: E402
from tinygrad import dtypes  # noqa: E402

ORIG = G.cshape

WIDEN: list[tuple[str, tuple[type, ...]]] = [
    ("W0 RuntimeError (LIVE)", (RuntimeError,)),
    ("W1 +AssertionError", (RuntimeError, AssertionError)),
    ("W4 bare Exception", (Exception,)),
]


def patched(excs):
  def cshape(n: UOp) -> str:
    try:
      shp = n.shape
    except excs:
      return "R"
    if shp is None:
      G.SHAPE_NONE_HITS += 1
      return "N"
    return "(" + ",".join("U" if isinstance(d, UOp) else G.i64(d) for d in shp) + ")"
  return cshape


def main() -> int:
  # ---- upstream's own construction. `_get_clause` at upat.py:66, called the way
  # upstream's pattern matcher calls it. NOT hand-written.
  root = _get_clause(UPat(Ops.ADD), UOp(Ops.CUSTOMI, arg=("uop", dtypes.void)))
  nodes = root.toposort()
  print(f"# patir graph from `_get_clause(UPat(Ops.ADD), CUSTOMI('uop'))` -- "
        f"{len(nodes)} nodes, ops {' '.join(n.op.name for n in nodes)}")
  print("# node id mapping (toposort order, which is what `emit_py` numbers by):")
  for i, n in enumerate(nodes):
    print(f"#   {i+1:>2} {n.op.name:<12} nsrc={len(n.src)} arg={n.arg!r} "
          f"dtype={n.dtype!r} tag={n.tag!r}")
  base_rows = None
  for label, excs in WIDEN:
    G.cshape = patched(excs)
    # `emit_py` takes a GRAPH NAME, so the rows come from `row_of` over the same list.
    ix = {id(s): j + 1 for j, s in enumerate(nodes)}  # 1-based: `emit_py` numbers by i+1
    lines = []
    for i, n in enumerate(nodes):
      try:
        lines.append(G.row_of(n, i + 1, ix))
      except BaseException as e:  # noqa: BLE001 -- the emitter DYING is the measurement
        lines.append(f"!! EMITTER DIED: {type(e).__name__}: {' '.join(str(e).split())[:70]}")
    print(f"\n# ---- {label} ----")
    for ln in lines:
      print("  " + ln)
    if base_rows is None:
      base_rows = lines
    else:
      moved = [(a, b) for a, b in zip(base_rows, lines) if a != b]
      print(f"#   rows CHANGED vs W0: {len(moved)} of {len(lines)}")
      for a, b in moved:
        print(f"#     W0 {a}")
        print(f"#     {label.split()[0]} {b}")
  G.cshape = ORIG
  return 0


if __name__ == "__main__":
  sys.exit(main())
