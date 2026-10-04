#!/usr/bin/env python
"""DENOM emittable -- for each of the 14 upstream-constructed candidate graphs, can the
DIFFER canonicalise it?

This is the sharpest question yet and it is NOT "does the op exist". It asks, node by node,
whether `graphcmp.cshape` (graphcmp.py:722) can render every node, because that function is
the differ's R4 SHAPE arm and it only catches `RuntimeError` (graphcmp.py:750).

MEASURED FINDING THAT PROMPTS THE INSTRUMENT: `graphcmp.py:750` is
    try: shp = n.shape
    except RuntimeError: return "R"
and `AssertionError` is NOT a subclass of `RuntimeError` (`issubclass` MEASURED False).
`ops.py:442` raises `AssertionError` ("None input shape not supported for {op}") for any
`GroupOp.Broadcastable` op -- AND and OR -- whose srcs have no shape. So the differ CANNOT
canonicalise a graph containing a shapeless AND, and `upat.py:66` makes EVERY pattern-
compiler IR AND-rooted by construction:
    return UOp(Ops.AND, src=tuple(and_clause)) if and_clause else UOp(Ops.CUSTOMI, arg=("True", dtypes.void))
so `CUSTOM`/`CUSTOMI`/`PYLITERAL` are reachable in tinygrad and un-emittable in the differ.

That is a wall in the INSTRUMENT, not a denominator error, and this file measures which
graphs hit it rather than asserting it.
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
  rows = [l for l in p.read_text().splitlines() if l.strip()]
  if rows:
    REACHED |= {f[1] for f in {r[1:]: G.unchunks(r) for r in rows}.values()}

from tinygrad.uop.ops import UOp, UPat, Ops, graph_rewrite
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

def _mulacc_null():
  """codegen/decomp/op.py:118-121. GATED on `Ops.MULACC in code_for_op`; only
  renderer/ptx.py:33 lists it, so this is 0 MULACC on CPU -- MEASURED, and the reason the
  union below reads 76 not 77."""
  a, b, c = f(), f(), f()
  eager = UOp.group((a * b + c).uop)
  pm = get_late_rewrite_patterns(tuple(Device.default.renderer.code_for_op.keys()),
                                 bool(DISABLE_FAST_IDIV))
  return graph_rewrite(eager, pm, name="arith/mulacc")

CANDS = [
 ("patir",  "upat.py:17/66 _get_clause -- PATTERN COMPILER IR",       lambda: _get_clause(UPat(Ops.ADD), UOp(Ops.CUSTOMI, arg=("uop", dtypes.void)))),
 ("mulacc", "op.py:119 via get_late_rewrite_patterns (PTX-gated)",    _mulacc_null),
 ("stage",  "ops.py:676 UOp.bufferize",                                lambda: f().uop.bufferize()),
 ("copy",   "ops.py:765 UOp.copy_to_device",                          lambda: f().uop.copy_to_device("CPU")),
 ("getaddr","ops.py:844 UOp.getaddr",                                 lambda: UOp.new_buffer("CPU", 16, F32).getaddr("CPU")),
 ("customfn","ops.py:1258 UOp.custom_function",                       lambda: UOp.custom_function("f", UOp.variable("v",0,4).unbound(), dtype=F32)),
 ("ins",    "ops.py:622 UOp.ins",                                     lambda: UOp(Ops.NOOP).ins("nop", dtype=dtypes.void)),
 ("rwrerr", "viz/serve.py:197 UOp(Ops.REWRITE_ERROR)",                lambda: UOp(Ops.REWRITE_ERROR, arg="boom")),
 ("threefry","mixin/elementwise.py:458 Tensor.threefry",              lambda: i().threefry(i().cast(dtypes.uint64)).uop),
 ("wmma",   "ops.py:651 UOp.wmma",                                    lambda: UOp.wmma(*(Tensor.ones(16,16).uop,)*3, dims=(16,16,16), threads=32)),
 ("mstack", "ops.py:770 UOp.mstack",                                  lambda: f().uop.mstack(f().uop)),
 ("mselect","ops.py:769 UOp.mselect",                                 lambda: f().uop.copy_to_device(("CPU","CPU")).mselect(0)),
 ("unshard","ops.py:701 UOp.unshard",                                 lambda: f().uop.unshard(0, UOp.range(2, 0))),
 ("allred", "ops.py:679 UOp.allreduce",                               lambda: f().uop.copy_to_device(("CPU","CPU")).allreduce(Ops.ADD, ("CPU","CPU"))),
 ("program","codegen/__init__.py:518 to_program",                     lambda: to_program(_kernel_ast(), Device.default.renderer)),
]

EIGHTEEN = set("""ALLREDUCE COPY CUSTOM CUSTOMI CUSTOM_FUNCTION GETADDR INS MSELECT MSTACK
MULACC PROGRAM PYLITERAL REWRITE_ERROR SOURCE STAGE THREEFRY UNSHARD WMMA""".split())

print(f"# reached(baseline corpus) = {len(REACHED)} of {len(list(Ops))}")
print(f"{'cand':<9} {'nodes':<6} {'emittable':<10} {'NEW':<4} {'of18':<5} blocker / new-ops")
emittable_union, blocked = set(), []
for name, cite, build in CANDS:
  try:
    root = build()
    nodes = list(root.toposort())
  except Exception as e:
    print(f"{name:<9} ERR    -           -    -    -    BUILD {type(e).__name__}: {' '.join(str(e).split())[:50]}")
    continue
  cen = collections.Counter(u.op.name for u in nodes)
  new = sorted(set(cen) - REACHED)
  n18 = [o for o in new if o in EIGHTEEN]
  bad = []
  for u in nodes:
    try: G.cshape(u)
    except Exception as e: bad.append(f"{u.op.name}:{type(e).__name__}")
  emittable = not bad
  if emittable: emittable_union |= set(cen)
  else: blocked.append((name, bad, sorted(n18)))
  print(f"{name:<9} {len(nodes):<6} {'YES' if emittable else 'NO':<10} {len(new):<4} {len(n18):<5} "
        f"{(';'.join(bad)) if bad else ' '.join(new)}")

print()
print(f"# EMITTABLE union reaches {len(REACHED | emittable_union)} of {len(list(Ops))}")
print(f"# of the 18 EMITTABLE: {len(EIGHTEEN & emittable_union)}  blocked: {' '.join(sorted(EIGHTEEN - emittable_union))}")
for name, bad, n18 in blocked:
  print(f"#   BLOCKED {name:<9} cshape-raises={' '.join(bad)}  would-have-added={' '.join(n18)}")
