"""CPython answers for `UOp.divides`, in the port's canonical form.

    .venv/bin/python .agents/slop/sym92/probe-divides.py

The port's half is probe-divides.bend.

THIS IS THE MEASUREMENT THAT THE `divandmod.bend` TODO BLOCK NEEDS. IT SAYS THE WALL FOR
`nested_div` AND `remove_nested_mod` IS "`divides` NEEDS `gcd` NEEDS A `Counter` FOLD", BUT THE
PORT's `UOp.divides` (`ops.bend:7972`) IS A RECURSION OVER ADD/MUL/CONST THAT CARRIES A `Dv`
RECORD -- SO IF IT ANSWERS THE SAME AS UPSTREAM, THAT WALL IS STALE.
"""
from tinygrad.uop.ops import UOp, Ops
from tinygrad import dtypes


def sh(u):
  if u is None: return "none"
  if u.op is Ops.CONST:
    a = u.arg
    if a is True: return "bt"
    if a is False: return "bf"
    if a is None: return "bad"
    return ("n%d" % -a) if a < 0 else ("c%d" % a)
  if u.op is Ops.PARAM: return u.arg.name or "?"
  return "(%s %s)" % (u.op.name.lower(), " ".join(sh(s) for s in u.src))


x = UOp.variable("x", 0, 10, dtype=dtypes.weakint)
print("x*4.divides(4)=%s" % sh((x * 4).divides(4)))
print("x*4+8.divides(4)=%s" % sh((x * 4 + 8).divides(4)))
print("x*6.divides(4)=%s" % sh((x * 6).divides(4)))
print("x.divides(4)=%s" % sh(x.divides(4)))
