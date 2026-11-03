"""CPython half of probe-253.bend: `(x*c0)+(x*c1) -> x*(c0+c1)` fires only when `c0+c1` fits `x`'s
dtype. Two cases, one that must FIRE and one that must DECLINE.

    .venv/bin/python .agents/slop/sym92/probe-253.py
"""
from tinygrad.uop.ops import UOp, Ops
from tinygrad import dtypes
from tinygrad.uop.symbolic import sym


def sh(u):
  if u.op is Ops.CONST:
    a = u.arg
    if a is True: return "bt"
    if a is False: return "bf"
    return ("n%d" % -a) if a < 0 else ("c%d" % a)
  if u.op is Ops.PARAM: return u.arg.name
  return "(%s %s)" % (u.op.name.lower(), " ".join(sh(s) for s in u.src))


def mulc(x, c): return UOp(Ops.MUL, src=(x, UOp.const(c, x.dtype)))

# int8 holds [-128, 127]: 1+2 fits, 127+127 does not.
x8 = UOp.variable("x", -128, 127, dtype=dtypes.int8)
print("fits=%s" % sh(sym.rewrite(UOp(Ops.ADD, src=(mulc(x8, 1), mulc(x8, 2))))))
print("overflow=%s" % sh(sym.rewrite(UOp(Ops.ADD, src=(mulc(x8, 127), mulc(x8, 127))))))
