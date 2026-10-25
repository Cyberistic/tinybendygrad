"""PROBE -- what upstream's CONST, STACK and BUFFER look like, and whether a
2-D node can be built WITHOUT a RESHAPE.

THE QUESTION THIS SETTLES.  upstream's `_shape` for a BUFFER reads
`self.src[0].as_shape` (ops.py:359) and ASSERTS `len(self.src[0].as_shape) <= 1`,
so a BUFFER is at most 1-D.  A 2-D node therefore has to come from somewhere else,
and the candidates are:

  * `Ops.STACK`: `_shape` is `(len(self.src),) + self.src[0].shape` (ops.py:352-354),
    so a STACK of two 1-D nodes is 2-D.  **NO RESHAPE NEEDED.**
  * `Ops.RESHAPE`: `_shape` is `self.src[1].as_shape` -- needs gr_17 on the port side.

The probe answers: which of these actually works, what the nodes look like, and
whether the two sides can be built identically.
"""
import struct

from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad.dtype import dtypes


def f32bits(v) -> int:
  return struct.unpack('<I', struct.pack('<f', float(v)))[0]


def show(name, u):
  print("%-22s op=%-9s nsrc=%d arg=%r shape=%r dtype=%s" %
        (name, u.op.name, len(u.src), u.arg, u.shape, u.dtype))


def main():
  # --- the CONST spellings -------------------------------------------------
  for label, c in [("UOp(Ops.CONST, arg=2)", UOp(Ops.CONST, arg=2)),
                   ("UOp.const(2)", UOp.const(2)),
                   ("UOp.const(2, int32)", UOp.const(2, dtypes.int32))]:
    try:
      show(label, c)
      print("      val=%r op_is_CONST=%s" % (getattr(c, "val", "<none>"), c.op is Ops.CONST))
    except Exception as e:
      print("%-22s RAISED %s: %s" % (label, type(e).__name__, e))

  # --- the BUFFER's shape src ----------------------------------------------
  print()
  for label, sh in [("STACK()", UOp(Ops.STACK, src=())),
                    ("STACK(CONST 2)", UOp(Ops.STACK, src=(UOp(Ops.CONST, arg=2),))),
                    ("STACK(const(2))", UOp(Ops.STACK, src=(UOp.const(2),)))]:
    try:
      print("%-22s as_shape=%r" % (label, sh.as_shape))
    except Exception as e:
      print("%-22s RAISED %s: %s" % (label, type(e).__name__, e))

  print()
  b = UOp(Ops.BUFFER, src=(UOp(Ops.STACK, src=(UOp(Ops.CONST, arg=2),)),), arg=ParamArg(0, dtypes.float32))
  show("BUFFER(STACK(CONST 2))", b)

  # --- a 2-D node with NO RESHAPE ------------------------------------------
  print()
  x = UOp(Ops.BUFFER, src=(UOp(Ops.STACK, src=(UOp(Ops.CONST, arg=2),)),), arg=ParamArg(0, dtypes.float32))
  y = UOp(Ops.BUFFER, src=(UOp(Ops.STACK, src=(UOp(Ops.CONST, arg=2),)),), arg=ParamArg(1, dtypes.float32))
  st = UOp(Ops.STACK, src=(x, y))
  show("STACK(x, y)", st)
  print("      ndim=%d shape=%r" % (st.ndim, st.shape))

  # --- the PERMUTE ----------------------------------------------------------
  print()
  per = UOp(Ops.PERMUTE, src=(st,), arg=(1, 0))
  show("PERMUTE(st, (1,0))", per)
  print("      marg=%r ndim=%d shape=%r" % (per.marg, per.ndim, per.shape))

  # --- upstream's OWN permute(), to see what it raises on what -------------
  print()
  for label, node in [("st (2-D)", st), ("x (1-D)", x)]:
    try:
      r = node.permute(1, 0)
      show("st.permute(1,0)" if node is st else "x.permute(1,0)", r)
    except Exception as e:
      print("%-22s RAISED %s: %s" % ("%s.permute(1,0)" % label, type(e).__name__, e))

  # --- the ctx candidates --------------------------------------------------
  print()
  p = UOp(Ops.BUFFER, src=(UOp(Ops.STACK, src=(UOp(Ops.CONST, arg=2),)),), arg=ParamArg(2, dtypes.float32))
  q = UOp(Ops.BUFFER, src=(UOp(Ops.STACK, src=(UOp(Ops.CONST, arg=2),)),), arg=ParamArg(3, dtypes.float32))
  ctx = UOp(Ops.STACK, src=(p, q))
  show("ctx = STACK(p, q)", ctx)
  print("      ndim=%d shape=%r" % (ctx.ndim, ctx.shape))
  print("      ctx.permute((1,0)) ->")
  r = ctx.permute((1, 0))
  show("ctx.permute((1,0))", r)
  print("      ndim=%d shape=%r" % (r.ndim, r.shape))


main()
