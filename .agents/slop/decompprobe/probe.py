#!/usr/bin/env python3
"""probe -- WHAT are the 11 PROMOTION rows' extra CAST/1?  For each declared row, rebuild
the census's `deleted()` witness in-process from the PINS FILE (both sides' token strings
are already there) against CPython's LIVE node objects, and print for every deleted node
its op, the op+dtypes of its source and its CAST target.  So the class gets a MECHANISM
instead of a name.

    .venv/bin/python .agents/slop/decompprobe/probe.py
"""
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "gates"))

from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp, Ops, ParamArg, AddrSpace
from tinygrad.codegen.decomp import dtype as DT

POOL = [dtypes.uint8, dtypes.uint16, dtypes.uint32, dtypes.uint64]
for _ in range(5): POOL.append(dtypes.int32)
for _ in range(5): POOL.append(dtypes.uint32)
for _ in range(5): POOL.append(dtypes.bool)
for _ in range(5): POOL.append(dtypes.float32)
PAR = [UOp(Ops.PARAM, src=(), arg=ParamArg(0, dt, None, name="%s%d" % (chr(119 + (i < 4)), i),
                                            addrspace=AddrSpace.ALU, device=None))
       for i, dt in enumerate(POOL)]


def ws(base, nw):
  return PAR[base:base + nw]


def cone(roots):
  out, seen = [], set()
  def go(v):
    if id(v) in seen: return
    seen.add(id(v)); out.append(v)
    for s in v.src: go(s)
  for r in roots: go(r)
  return out


def ns(u):
  return "%s/%d" % (u.op.name, len(u.src))


def witness(nodes, pt):
  """`deleted()`, but the witness is the deleted NODES, not the deleted TOKENS."""
  ct = [ns(n) for n in nodes]
  out, dele, i, j = [], [], 0, 0
  while i < len(ct):
    if j < len(pt) and ct[i] == pt[j]:
      out.append(ct[i]); j += 1
    else:
      dele.append(nodes[i])
    i += 1
  return dele if j == len(pt) and out == pt else None


def pins():
  p = {}
  for ln in (ROOT / "gates" / "decomp_graph_census-pins.rows").read_text().splitlines():
    if not ln.strip() or ln.startswith("#"): continue
    row, cpy, bd = ln.split("\t")
    p[row] = (cpy.split("=", 1)[1].split(","), bd.split("=", 1)[1].split(","))
  return p


def roots_of(r):
  return list(r) if isinstance(r, tuple) else [r]


L2I = {"lg1": (Ops.NEG, dtypes.int32, dtypes.uint32, 9, 2), "lg2": (Ops.CAST, dtypes.int64, dtypes.int32, 4, 2),
       "lg3": (Ops.CAST, dtypes.int64, dtypes.uint32, 9, 2), "lg4": (Ops.CAST, dtypes.int64, dtypes.bool, 14, 2),
       "lg5": (Ops.CAST, dtypes.int64, dtypes.float32, 19, 2), "lg6": (Ops.CAST, dtypes.uint64, dtypes.int32, 4, 2),
       "lg7": (Ops.CAST, dtypes.int32, dtypes.uint32, 9, 2), "lg8": (Ops.BITCAST, dtypes.int64, dtypes.uint32, 9, 2),
       "lg9": (Ops.SHL, dtypes.int32, dtypes.uint32, 9, 3), "lga": (Ops.SHR, dtypes.int32, dtypes.uint32, 9, 3),
       "lgb": (Ops.SHR, dtypes.uint32, dtypes.uint32, 9, 3), "lgc": (Ops.ADD, dtypes.int32, dtypes.uint32, 9, 4),
       "lgd": (Ops.SUB, dtypes.int32, dtypes.uint32, 9, 4), "lge": (Ops.MUL, dtypes.int32, dtypes.uint32, 9, 4),
       "lgf": (Ops.CMPLT, dtypes.int32, dtypes.uint32, 9, 4), "lgg": (Ops.CMPEQ, dtypes.int32, dtypes.uint32, 9, 4),
       "lgh": (Ops.CMPNE, dtypes.int32, dtypes.uint32, 9, 4), "lgi": (Ops.XOR, dtypes.int32, dtypes.uint32, 9, 4),
       "lgj": (Ops.OR, dtypes.int32, dtypes.uint32, 9, 4), "lgk": (Ops.AND, dtypes.int32, dtypes.uint32, 9, 4),
       "lgl": (Ops.WHERE, dtypes.int32, dtypes.uint32, 9, 5), "lgm": (Ops.MAX, dtypes.int32, dtypes.uint32, 9, 4),
       "lgn": (Ops.FLOORDIV, dtypes.int32, dtypes.uint32, 9, 4), "lgo": (Ops.CAST, dtypes.int64, dtypes.uint32, 9, 1),
       "lgq": (Ops.CDIV, dtypes.int32, dtypes.uint32, 9, 4), "lgr": (Ops.CMOD, dtypes.int32, dtypes.uint32, 9, 4),
       "lgs": (Ops.CDIV, dtypes.uint32, dtypes.uint32, 9, 4), "lgt": (Ops.CMOD, dtypes.uint32, dtypes.uint32, 9, 4),
       "lgu": (Ops.CAST, dtypes.float32, dtypes.float32, 19, 2), "lgy": (Ops.CAST, dtypes.int32, dtypes.int32, 4, 2)}

F2F = {"q1": (dtypes.fp8e4m3, dtypes.float32), "q2": (dtypes.float32, dtypes.fp8e4m3),
       "q3": (dtypes.float32, dtypes.fp8e5m2), "q4": (dtypes.fp8e4m3fnuz, dtypes.float32),
       "q5": (dtypes.float32, dtypes.fp8e5m2fnuz), "q6": (dtypes.half, dtypes.bfloat16),
       "q7": (dtypes.float32, dtypes.float64)}


def live(row):
  if row in L2I:
    _op, _dt, _xdt, _b, _n = L2I[row]
    return DT.l2i(_op, _dt, *ws(_b, _n))
  if row == "up":
    return DT.unpack32(PAR[9])
  fr, to = F2F[row]
  v = UOp(Ops.PARAM, src=(), arg=ParamArg(0, DT.f2f_dt[fr], None, name=row, addrspace=AddrSpace.ALU, device=None))
  return DT.f2f(v, fr, to, True)


P = pins()
print("PINS: %d declared divergences" % len(P))
for row in sorted(P, key=lambda r: (len(P[r][0]), r)):
  cpy_toks, bd_toks = P[row]
  if cpy_toks[0].startswith("raise=") or bd_toks[0].startswith("refused"):
    print("== %-4s  %s | %s  (a refusal, no cone)" % (row, cpy_toks[0], bd_toks[0])); continue
  try:
    r = live(row)
  except Exception as e:  # noqa: BLE001 -- a raise IS this row's answer
    print("== %-4s  cpy raises %s | port %s" % (row, type(e).__name__, bd_toks[0])); continue
  nodes = cone(roots_of(r))
  dele = witness(nodes, bd_toks)
  print("== %-4s  cpy %d nodes, port %d nodes" % (row, len(nodes), len(bd_toks)))
  if dele is None:
    print("   NOT A DELETION -- the residue is in a different order"); continue
  print("   deleted ops: %s" % dict(Counter(n.op.name for n in dele)))
  kinds = Counter()
  for n in dele:
    s = n.src[0]
    kinds["CAST %s -> %s over %s(%s)" % (s.dtype, getattr(n, "arg", "?"), ns(s), s.dtype)] += 1
  for k, c in sorted(kinds.items(), key=lambda kv: -kv[1]):
    print("     x%-4d %s" % (c, k))