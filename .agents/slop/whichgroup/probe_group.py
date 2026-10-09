#!/usr/bin/env python
"""probe_group.py -- DOES `UOp.group` OF ONE SRC MAKE A GROUP?

Every answer below is printed with the file and line it came from, so no reader has to
trust this file's prose. Q1/Q2 answer from UPSTREAM SOURCE; Q3 answers from CPython.
Nothing here reads the bend lane, and nothing here writes outside this unit's directory.
"""
import os, pathlib, sys, collections
os.environ["DEV"] = "CPU"
REPO = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / ".agents" / "slop"))
import graphcmp as G
G.load_tinygrad()
from tinygrad import Tensor, dtypes
from tinygrad.uop.ops import UOp, Ops

src = (REPO / "tinygrad" / "uop" / "ops.py").read_text().splitlines()
print("Q1 UPSTREAM SOURCE -- tinygrad/uop/ops.py:558-560")
for i in (557, 558, 559):
  print(f"  {i+1}: {src[i]}")

a = Tensor.empty(4, 3, dtype=dtypes.float)
flip = a.flip(0).uop
g = UOp.group(flip)
print()
print("Q2 CPython -- what graphcmp.py:1386 `UOp.group(a.flip(0).uop)` RETURNS")
print("  group(...) is the FLIP itself? =", g is flip)
print("  g.op                         =", g.op, "| FLIP =", Ops.FLIP)
print("  Ops.GROUP node created?      =", g.op is Ops.GROUP)

rows = G.emit_py("flip", None)
census = collections.Counter(G.unchunks(r)[1] for r in rows)
print()
print(f"Q3 G.emit_py('flip', None) -> {len(rows)} rows")
print("  op census                    =", dict(sorted(census.items())))
print("  GROUP rows                   =", [r for r in rows if ":GROUP " in r] or "NONE")
print()
print("Q4 THE OTHER 11 GROUPS IN graphcmp.bend -- src-count of each hand-built OpsGROUP")
bend = (REPO / ".agents" / "slop" / "graphcmp.bend").read_text().splitlines()
import re
for i, ln in enumerate(bend, 1):
  if "OpsGROUP{}" in ln:
    m = re.search(r"\[([^\]]*)\]", ln)
    srcs = [s for s in re.findall(r"O\.Found\.i\(", m.group(1))] if m else []
    print(f"  :{i:<5} srcs on this line = {len(srcs)}  {'<== ONE: upstream makes NO GROUP' if len(srcs)==1 else ''}")
