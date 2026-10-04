#!/usr/bin/env python
"""DENOM yield -- which of the 18 does each candidate graph ADD, against the MEASURED
reached-59, and is the construction upstream's own.

This is the decision table for step 3. For each candidate:
  graph   the upstream entry point, cited
  nodes   size of the emitted graph
  NEW     ops it adds to the corpus, i.e. `NEW = census - reached59`
  of-18   how many of the brief's 18 those are

`reached59` is READ FROM THE CENSUS ROWS ON DISK (`.agents/slop/denom/rows-*-py.txt`),
not transcribed, so it cannot drift from the corpus.
"""
import sys, os, pathlib, collections
sys.path.insert(0, "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
sys.path.insert(0, "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/.agents/slop")
os.environ["DEV"] = "CPU"
import graphcmp as G
G.load_tinygrad()
G.COMM = G.commutative()

HERE = pathlib.Path("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/.agents/slop/denom")
REACHED = set()
for p in sorted(HERE.glob("rows-*-py.txt")):
  for ln in p.read_text().splitlines():
    if ln.strip(): RECHED = None
  rows = [l for l in p.read_text().splitlines() if l.strip()]
  RECHED = None
  for r in rows:
    recs = {r[1:]: G.unchunks(r) for r in rows}
    break
  RECHED = None
  d = {r[1:]: G.unchunks(r) for r in rows}
  REACHED |= {f[1] for f in d.values()}

from tinygrad.uop.ops import UOp, UPat, Ops
from tinygrad.uop.upat import _get_clause
from tinygrad.codegen.decomp.op import get_late_rewrite_patterns
from tinygrad.codegen import to_program
from tinygrad import Tensor, dtypes
from tinygrad.device import Device
from tinygrad.helpers import DISABLE_FAST_IDIV

F32, I32 = dtypes.float, dtypes.int
f = lambda: Tensor.empty(4, 3, dtype=F32)
i = lambda: Tensor.empty(4, 3, dtype=I32)

def _kernel_ast():
  out = Tensor.empty(4, 5).realize()
  out.assign(Tensor.empty(4, 3) @ Tensor.empty(3, 5))
  return [si.src[0] for si in out.schedule_linear().src if si.src[0].op is Ops.SINK][0]

def _mulacc():
  """codegen/decomp/op.py:118-121 -- the ONLY MULACC site, and it is a REWRITE. Same shape
  as `g_late`: an eager graph run through upstream's OWN late patterns."""
  a, b, c = f(), f(), f()
  eager = UOp.group((a * b).uop, (a * b + c).uop, (a << 3).uop + c)
  pm = get_late_rewrite_patterns(tuple(Device.default.renderer.code_for_op.keys()),
                                 bool(DISABLE_FAST_IDIV))
  return graph_rewrite(eager, pm, name="arith/mulacc")

from tinygrad.uop.ops import graph_rewrite

CANDS = [
 ("patir",  "upat.py:17/163 _get_clause (base CUSTOMI) -- the PATTERN COMPILER IR",
  lambda: _get_clause(UPat(Ops.ADD), UOp(Ops.CUSTOMI, arg=("uop", dtypes.void)))),
 ("mulacc", "codegen/decomp/op.py:119 via get_late_rewrite_patterns",
  _mulacc),
 ("stage",  "ops.py:676 UOp.bufferize", lambda: f().uop.bufferize()),
 ("copy",   "ops.py:765 UOp.copy_to_device", lambda: f().uop.copy_to_device("CPU")),
 ("getaddr","ops.py:844 UOp.getaddr", lambda: UOp.new_buffer("CPU", 16, F32).getaddr("CPU")),
 ("customfn","ops.py:1258 UOp.custom_function",
  lambda: UOp.custom_function("f", UOp.variable("v", 0, 4).unbound(), dtype=F32)),
 ("ins",    "ops.py:622 UOp.ins", lambda: UOp(Ops.NOOP).ins("nop", dtype=dtypes.void)),
 ("rwrerr", "viz/serve.py:197 UOp(Ops.REWRITE_ERROR, arg=traceback)",
  lambda: UOp(Ops.REWRITE_ERROR, arg="boom")),
 ("threefry","mixin/elementwise.py:458 Tensor.threefry",
  lambda: i().threefry(i().cast(dtypes.uint64)).uop),
 ("wmma",   "ops.py:651 UOp.wmma",
  lambda: UOp.wmma(*(Tensor.ones(16, 16).uop,)*3, dims=(16,16,16), threads=32)),
 ("mstack", "ops.py:770 UOp.mstack", lambda: f().uop.mstack(f().uop)),
 ("mselect","ops.py:769 UOp.mselect", lambda: f().uop.copy_to_device(("CPU","CPU")).mselect(0)),
 ("unshard","ops.py:701 UOp.unshard", lambda: f().uop.unshard(0, UOp.range(2, 0))),
 ("allred", "ops.py:679 UOp.allreduce",
  lambda: f().uop.copy_to_device(("CPU","CPU")).allreduce(Ops.ADD, ("CPU","CPU"))),
 ("program","codegen/__init__.py:518 to_program", lambda: to_program(_kernel_ast(), Device.default.renderer)),
]

EIGHTEEN = set("""ALLREDUCE COPY CUSTOM CUSTOMI CUSTOM_FUNCTION GETADDR INS MSELECT MSTACK
MULACC PROGRAM PYLITERAL REWRITE_ERROR SOURCE STAGE THREEFRY UNSHARD WMMA""".split())

print(f"# reached(baseline) = {len(REACHED)}  of {len(list(Ops))}")
print(f"{'cand':<9} {'nodes':<6} {'NEW':<4} {'of18':<5} new-ops")
for name, cite, build in CANDS:
  try:
    root = build()
    cen = collections.Counter(u.op.name for u in root.toposort())
  except Exception as e:
    print(f"{name:<9} ERR    -    -    {type(e).__name__}: {' '.join(str(e).split())[:60]}")
    continue
  new = sorted(set(cen) - REACHED)
  n18 = [o for o in new if o in EIGHTEEN]
  print(f"{name:<9} {sum(cen.values()):<6} {len(new):<4} {len(n18):<5} {' '.join(new)}")

union = set()
for name, cite, build in CANDS:
  try:
    union |= set(u.op.name for u in build().toposort())
  except Exception: pass
print()
print(f"# UNION of ALL 14 candidates reaches {len(union | REACHED)} of {len(list(Ops))}")
print(f"# of the 18 reached by the union: {len(EIGHTEEN & union)} of 18 -> {' '.join(sorted(EIGHTEEN - union))} STILL UNREACHED")
