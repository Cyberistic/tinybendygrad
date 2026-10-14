#!/usr/bin/env python3
"""dtinert -- THE DECISIVE READING for the 11 PROMOTION rows.  For every node the port KEEPS
is its DERIVED dtype the same as the CPython node it stands for?  The port's tree is rebuilt
by replacing each deleted CAST with its own src, then every node's dtype is read off.

    .venv/bin/python .agents/slop/decompprobe/dtinert.py lg1 lg5 lga lgc lgd lge q5

Small rows only by default; the 2000+ node rows are minutes each and are run one at a time.
"""
import sys
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


def wit(nodes, pt):
  ct = [ns(n) for n in nodes]
  out, dele, imap, i, j = [], [], [], 0, 0
  while i < len(ct):
    if j < len(pt) and ct[i] == pt[j]: out.append(ct[i]); imap.append(i); j += 1
    else: dele.append(nodes[i])
    i += 1
  return (dele, imap) if j == len(pt) and out == pt else (None, None)


L = {"lg1": (Ops.NEG, dtypes.int32, dtypes.uint32, 9, 2),
     "lg5": (Ops.CAST, dtypes.int64, dtypes.float32, 19, 2),
     "lga": (Ops.SHR, dtypes.int32, dtypes.uint32, 9, 3),
     "lgc": (Ops.ADD, dtypes.int32, dtypes.uint32, 9, 4),
     "lgd": (Ops.SUB, dtypes.int32, dtypes.uint32, 9, 4),
     "lge": (Ops.MUL, dtypes.int32, dtypes.uint32, 9, 4),
     "lgq": (Ops.CDIV, dtypes.int32, dtypes.uint32, 9, 4),
     "lgr": (Ops.CMOD, dtypes.int32, dtypes.uint32, 9, 4),
     "lgs": (Ops.CDIV, dtypes.uint32, dtypes.uint32, 9, 4),
     "lgt": (Ops.CMOD, dtypes.uint32, dtypes.uint32, 9, 4)}
F = {"q5": (dtypes.float32, dtypes.fp8e5m2fnuz)}


def roots_of(row):
  if row in L:
    op, dt, _x, b, n = L[row]
    return list(DT.l2i(op, dt, *PAR[b:b + n]))
  fr, to = F[row]
  v = UOp(Ops.PARAM, src=(), arg=ParamArg(0, DT.f2f_dt[fr], None, name=row,
                                          addrspace=AddrSpace.ALU, device=None))
  return [DT.f2f(v, fr, to, True)]


for row in (sys.argv[1:] or ["lg1", "lg5", "lga", "lgc", "lgd", "lge", "q5"]):
  roots = roots_of(row)
  nodes = cone(roots)
  dele, imap = wit(nodes, P[row][1])
  if dele is None:
    print("== %-4s NOT A DELETION" % row); continue
  ids = {id(n) for n in dele}
  def rd(v, _ids=ids):
    if id(v) in _ids: return rd(v.src[0])
    return v.replace(src=tuple(rd(s) for s in v.src)) if v.src else v
  port = cone([rd(x) for x in roots])
  assert len(port) == len(imap), (row, len(port), len(imap))
  diff = [(p, nodes[c].dtype, port[p].dtype, ns(port[p])) for p, c in enumerate(imap)
          if nodes[c].dtype != port[p].dtype]
  print("== %-4s %4d deleted, %4d kept -- %s" % (
    row, len(dele), len(imap),
    "EVERY KEPT NODE HAS THE SAME DERIVED DTYPE" if not diff else "%d DIFFER" % len(diff)))
  for p, a, b, o in diff[:8]:
    print("      port#%-4d cpy %-16s port %-16s  %s" % (p, a, b, o))