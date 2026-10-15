#!/usr/bin/env python
"""CPython oracle for gates/symcases.rows. Same graphs, `sym.rewrite` ONCE, printed
as the SAME s-expr the port's `fz_render` prints, so the two diff as strings."""
import sys
sys.path.insert(0, "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
from tinygrad.uop.ops import UOp, Ops
from tinygrad import dtypes
from tinygrad.uop.symbolic import sym

def var(nm, dt): return UOp.variable(nm, 0, 100, dt)

def sh(u):
  if u.op is Ops.CONST:
    v = u.arg
    return ("c%d" % v) if isinstance(v, int) and v >= 0 else ("n%d" % -v if isinstance(v, int) else str(v))
  if u.op is Ops.PARAM: return u.arg.name
  return "(" + u.op.name + " " + " ".join(sh(s) for s in u.src) + ")"

def run(name, u):
  r = sym.rewrite(u)
  print("%s= sym=%s" % (name, sh(r) if r is not None else "norewrite"))

X, Y, Z = var("x", dtypes.weakint), var("y", dtypes.weakint), var("z", dtypes.weakint)
c = lambda n: UOp.const(n, dtypes.weakint)
run("t_add",   UOp(Ops.ADD, (c(7), c(0))))
run("t_xor",   UOp(Ops.XOR, (UOp(Ops.XOR, (X, c(5))), c(5))))
run("t_xor0",  UOp(Ops.XOR, (UOp(Ops.XOR, (X, c(5))), Y)))
run("t_group", UOp(Ops.GROUP, (X,)))
run("t_sink",  UOp(Ops.SINK, (UOp(Ops.GROUP, (X,)), c(2))))
# THE NEGATIVE AND THE SINGLE-SRC SIBLING, ADDED BY THE CALLER 2026-10-16. `t_sink0` IS THE SHAPE
# `M20` PROVED NO FIXTURE CAN MOVE: WITH NO SINK-LIKE SRC THE REBUILD IS BYTE-IDENTICAL AND
# `sy_novel`'s `ret is not uop` SWALLOWS IT -- **AND CPYTHON'S OWN `else None` IS REDUNDANT THE SAME
# WAY.** IT IS STILL WORTH A ROW: IT PINS THE *DECISION* (NO REWRITE) RATHER THAN THE REBUILD.
run("t_sink0", UOp(Ops.SINK, (X, c(2))))
run("t_sink1", UOp(Ops.SINK, (UOp(Ops.GROUP, (X,)),)))
run("t_mod",   UOp(Ops.FLOORMOD, (UOp(Ops.FLOORMOD, (X, Y)), Y)))
run("t_mod0",  UOp(Ops.FLOORMOD, (UOp(Ops.FLOORMOD, (X, Y)), Z)))
run("t_fdiv",  UOp(Ops.FLOORDIV, (UOp(Ops.FLOORDIV, (X, Y)), Y)))
run("t_fdiv0", UOp(Ops.FLOORDIV, (UOp(Ops.FLOORDIV, (X, Y)), Z)))
run("t_addx",  UOp(Ops.ADD, (UOp(Ops.MUL, (X, c(2))), c(0))))