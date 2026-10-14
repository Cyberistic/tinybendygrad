#!/usr/bin/env python3
"""shapes -- THE FOUR src->target SHAPES of the 11 PROMOTION rows, aggregated, and the
per-row breakdown that produces them.  Run from the pins so the numbers are the pins'.

    .venv/bin/python .agents/slop/decompprobe/shapes.py
"""
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "gates"))

from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp, Ops, ParamArg, AddrSpace
from tinygrad.codegen.decomp import dtype as DT

P = {}
for ln in (ROOT / "gates" / "decomp_graph_census-pins.rows").read_text().splitlines():
  if not ln.strip() or ln.startswith("#"): continue
  _r, _c, _b = ln.split("\t")
  P[_r] = (_c.split("=", 1)[1].split(","), _b.split("=", 1)[1].split(","))

POOL = [dtypes.uint8, dtypes.uint16, dtypes.uint32, dtypes.uint64]
for _ in range(5): POOL.append(dtypes.int32)
for _ in range(5): POOL.append(dtypes.uint32)
for _ in range(5): POOL.append(dtypes.bool)
for _ in range(5): POOL.append(dtypes.float32)
PAR = [UOp(Ops.PARAM, src=(), arg=ParamArg(0, dt, None, name="%s%d" % (chr(119 + (i < 4)), i),
                                            addrspace=AddrSpace.ALU, device=None)) for i, dt in enumerate(POOL)]

L = {"lg1": (Ops.NEG, dtypes.int32, dtypes.uint32, 9, 2), "lg5": (Ops.CAST, dtypes.int64, dtypes.float32, 19, 2),
     "lga": (Ops.SHR, dtypes.int32, dtypes.uint32, 9, 3), "lgc": (Ops.ADD, dtypes.int32, dtypes.uint32, 9, 4),
     "lgd": (Ops.SUB, dtypes.int32, dtypes.uint32, 9, 4), "lge": (Ops.MUL, dtypes.int32, dtypes.uint32, 9, 4),
     "lgq": (Ops.CDIV, dtypes.int32, dtypes.uint32, 9, 4), "lgr": (Ops.CMOD, dtypes.int32, dtypes.uint32, 9, 4),
     "lgs": (Ops.CDIV, dtypes.uint32, dtypes.uint32, 9, 4), "lgt": (Ops.CMOD, dtypes.uint32, dtypes.uint32, 9, 4)}
F = {"q5": (dtypes.float32, dtypes.fp8e5m2fnuz)}


def cone(roots):
  out, seen = [], set()
  def go(v):
    if id(v) in seen: return
    seen.add(id(v)); out.append(v)
    for s in v.src: go(s)
  for x in roots: go(x)
  return out


def ns(u):
  return "%s/%d" % (u.op.name, len(u.src))


def greedy(nodes, pt):
  ct = [ns(n) for n in nodes]
  d, i, j = [], 0, 0
  while i < len(ct):
    if j < len(pt) and ct[i] == pt[j]: j += 1
    else: d.append(nodes[i])
    i += 1
  return d if j == len(pt) else None


tot = Counter()
print(f"{'row':5} {'want':>5} {'got':>4}   shapes (src -> CAST target, over)")
for r in sorted(P, key=lambda k: len(P[k][1])):
  cpy, pt = P[r]
  if cpy[0].startswith("raise=") or pt[0].startswith("refused"):
    continue
  if r in L:
    op, dt, _x, b, n = L[r]
    roots = list(DT.l2i(op, dt, *PAR[b:b + n]))
  elif r in F:
    fr, to = F[r]
    v = UOp(Ops.PARAM, src=(), arg=ParamArg(0, DT.f2f_dt[fr], None, name=r,
                                            addrspace=AddrSpace.ALU, device=None))
    roots = [DT.f2f(v, fr, to, True)]
  else:
    continue        # q2/q3 are the two FINDINGS: not deletions, so there is no set to shape
  nodes = cone(roots)
  dele = greedy(nodes, pt)
  if dele is None:
    print(f"{r:5} {'-':>5} {'-':>4}   NOT A DELETION"); continue
  k = Counter("%s -> %s over %s" % (n.src[0].dtype, n.arg, ns(n.src[0])) for n in dele)
  tot += k
  want = len(cpy) - len(pt)
  assert want == len(dele), (r, want, len(dele))
  print(f"{r:5} {want:5d} {len(dele):4d}   " + "; ".join(f"{a} x{c}" for a, c in k.most_common()))
print()
print("AGGREGATE, %d entries in %d shapes:" % (sum(tot.values()), len(tot)))
for a, c in tot.most_common():
  print("  %5d  %s" % (c, a))
print()
pairs = Counter(t.split(" over ")[0] for t in tot.elements())
print("BY src->target ALONE (%d distinct pairs):" % len(pairs))
for a, c in pairs.most_common():
  print("  %5d  %s" % (c, a))