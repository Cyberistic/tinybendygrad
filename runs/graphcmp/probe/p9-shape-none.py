import os
os.environ["DEV"]="CPU"
import tinygrad
from tinygrad import dtypes
from tinygrad.uop.ops import UOp, Ops
print("tree:", tinygrad.__file__)
NO_SHAPE = [Ops.IF, Ops.BARRIER, Ops.SINK, Ops.REWRITE_ERROR, Ops.ENDIF, Ops.BACKEDGE,
            Ops.GROUP, Ops.LINEAR, Ops.PROGRAM, Ops.SOURCE]
c4 = UOp.const(4)
src = (c4,)
rows=[]
for op in NO_SHAPE:
  try:
    u = UOp(op, src, None)
  except Exception as e:
    rows.append((op.name, f"ctor {type(e).__name__}", "-", "-")); continue
  _sh = None
  try: _sh = u._shape
  except Exception as e: _sh = f"raised {type(e).__name__}"
  try: sh = u.shape; raised = "NO"
  except Exception as e: sh = f"{type(e).__name__}"; raised = "YES"
  rows.append((op.name, "built", repr(_sh), f"shape {sh} (raises={raised})"))
for r in rows: print("  %-15s %-8s _shape=%-8s %s" % r)
print()
print("INS void:")
u = UOp(Ops.INS, (), ("cuda", dtypes.void))
print("  _shape:", u._shape, "shape raises:", end=" ")
try: print("NO", u.shape)
except Exception as e: print("YES", type(e).__name__)
u2 = UOp(Ops.INS, (), ("cuda", dtypes.half))
print("  INS half _shape:", u2._shape, "shape:", u2.shape)
print()
print("=== IS `_shape is None` THE SAME SET AS `shape` RAISES? over a sweep ===")
import itertools
sweep = list(NO_SHAPE) + [Ops.INS, Ops.CONST, Ops.CAST, Ops.RANGE, Ops.STACK, Ops.RESHAPE, Ops.PERMUTE,
                          Ops.ADD, Ops.MUL, Ops.REDUCE, Ops.LOAD, Ops.STORE, Ops.INDEX, Ops.PARAM,
                          Ops.ALLOC, Ops.BUFFER, Ops.BINARY, Ops.PYLITERAL, Ops.MSELECT, Ops.CALL,
                          Ops.PROGRAM, Ops.SPECIAL, Ops.CUSTOM, Ops.COPY, Ops.NOOP]
mism=[]
for op in sweep:
  try: u = UOp(op, src, ("x", None) if op is Ops.PYLITERAL else None)
  except Exception: continue
  try: _ = u._shape; a = None
  except Exception: a = "raised"
  try: _ = u.shape; b = None
  except Exception: b = "raised"
  if (a is None) != (b is None): mism.append((op.name, a, b))
print("  ops where _shape-is-None differs from shape-raises:", mism or "NONE -- the two are the same set")
