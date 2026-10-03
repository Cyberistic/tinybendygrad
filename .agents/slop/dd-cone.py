#!/usr/bin/env python3
"""dd-cone.py -- CPython's OWN cone for one `l2i` fixture, as a readable tree.

Every line is read out of the UOp CPython built; nothing is transcribed. The
`dfs pre-order` numbering is the oracle's `*sig` order, so the tree and the gate row
can be lined up against each other.

  .venv/bin/python .agents/slop/dd-cone.py lg9 lga lgb lge lgf lgm
"""
import sys

sys.path.insert(0, '.')
from tinygrad.dtype import dtypes
from tinygrad.uop.ops import UOp, Ops, UOpMetaClass, GroupOp
from tinygrad.codegen.decomp import dtype as DD

ORDER = []
_CALL = UOpMetaClass.__call__


def _call(cls, op, src=(), arg=None, tag=None, metadata=None):
  r = _CALL(cls, op, tuple(s._uop for s in src), arg, tag, metadata)
  if id(r) not in _seen:
    _seen.add(id(r))
    ORDER.append(r)
  return r


_seen = set()
UOpMetaClass.__call__ = _call

WPOOL = {dt: tuple(UOp.variable(f"{dt.name}{i}", 0, 0, dt) for i in range(5))
         for dt in (dtypes.i32, dtypes.u32, dtypes.bool, dtypes.f32)}

TABLE = {
    "lg1": (Ops.NEG, dtypes.int, dtypes.u32, 2), "lg2": (Ops.CAST, dtypes.long, dtypes.i32, 2),
    "lg3": (Ops.CAST, dtypes.long, dtypes.u32, 2), "lg4": (Ops.CAST, dtypes.long, dtypes.bool, 2),
    "lg5": (Ops.CAST, dtypes.long, dtypes.f32, 2), "lg6": (Ops.CAST, dtypes.ulong, dtypes.i32, 2),
    "lg7": (Ops.CAST, dtypes.int, dtypes.u32, 2), "lg8": (Ops.BITCAST, dtypes.long, dtypes.u32, 2),
    "lg9": (Ops.SHL, dtypes.int, dtypes.u32, 3), "lga": (Ops.SHR, dtypes.int, dtypes.u32, 3),
    "lgb": (Ops.SHR, dtypes.uint, dtypes.u32, 3), "lgc": (Ops.ADD, dtypes.int, dtypes.u32, 4),
    "lgd": (Ops.SUB, dtypes.int, dtypes.u32, 4), "lge": (Ops.MUL, dtypes.int, dtypes.u32, 4),
    "lgf": (Ops.CMPLT, dtypes.int, dtypes.u32, 4), "lgg": (Ops.CMPEQ, dtypes.int, dtypes.u32, 4),
    "lgh": (Ops.CMPNE, dtypes.int, dtypes.u32, 4), "lgi": (Ops.XOR, dtypes.int, dtypes.u32, 4),
    "lgj": (Ops.OR, dtypes.int, dtypes.u32, 4), "lgk": (Ops.AND, dtypes.int, dtypes.u32, 4),
    "lgl": (Ops.WHERE, dtypes.int, dtypes.u32, 5), "lgm": (Ops.MAX, dtypes.int, dtypes.u32, 4),
    "lgn": (Ops.FLOORDIV, dtypes.int, dtypes.u32, 4), "lgo": (Ops.CAST, dtypes.long, dtypes.u32, 1),
    "lgq": (Ops.CDIV, dtypes.int, dtypes.u32, 4), "lgr": (Ops.CMOD, dtypes.int, dtypes.u32, 4),
    "lgs": (Ops.CDIV, dtypes.uint, dtypes.u32, 4), "lgt": (Ops.CMOD, dtypes.uint, dtypes.u32, 4),
}


def walk(v, d, idx, out):
  v = v._uop if hasattr(v, "_uop") else v
  if id(v) in idx:
    out.append(f"{'  ' * d}#{idx[id(v)]} SHARED-> {v.op.name}")
    return
  idx[id(v)] = len(idx)
  arg = ""
  if v.op is Ops.CONST:
    arg = f" arg={v.arg!r}"
  elif v.op is Ops.PARAM:
    arg = f" name={v.arg.name}"
  out.append(f"{'  ' * d}#{idx[id(v)]} {v.op.name} dt={v.dtype}{arg}")
  for s in v.src:
    walk(s, d + 1, idx, out)


for nm in sys.argv[1:]:
  op, dt, xdt, n = TABLE[nm]
  ORDER.clear()
  _seen.clear()
  r = DD.l2i(op, dt, *WPOOL[xdt][:n])
  roots = list(r) if isinstance(r, tuple) else [r]
  print(f"=== {nm}  {op.name} dt={dt.name} xdt={xdt.name} nwords={n}  roots={len(roots)}")
  out, idx = [], {}
  for i, rt in enumerate(roots):
    out.append(f"-- root{i}")
    walk(rt, 1, idx, out)
  print("\n".join(out))
  print(f"   arena slots minted: {len(ORDER)}")
  print()