"""CPython answers for the rules re-ported in this session, in the port's own canonical form.

    .venv/bin/python .agents/slop/sym92/probe-swap.py

The port's half is probe-swap.bend. Every case here is a rule whose BODY changed because the
`ne`/`eq` primitives swapped at the re-vendor, so the pair is what says the re-port is real.
"""
from tinygrad.uop.ops import UOp, Ops
from tinygrad import dtypes
from tinygrad.uop.symbolic import sym


def sh(u):
  """The port's canonical form: lowercase op, `c<N>` consts, params by name, `bt`/`bf`/`bad`."""
  if u.op is Ops.CONST:
    a = u.arg
    if a is None and u.dtype is dtypes.bool: return "bf"
    if a is True: return "bt"
    if a is False: return "bf"
    if a is None: return "bad"
    return ("n%d" % -a) if a < 0 else ("c%d" % a)
  if u.op is Ops.PARAM: return u.arg.name
  parts = " ".join(sh(s) for s in u.src)
  return "(%s %s)" % (u.op.name.lower(), parts)


xb = UOp.variable("xb", 0, 1, dtype=dtypes.bool)
xi = UOp.variable("xi", 0, 100, dtype=dtypes.int32)
g = UOp.variable("g", 0, 1, dtype=dtypes.bool)
a = UOp.variable("a", 0, 1, dtype=dtypes.bool)
b = UOp.variable("b", 0, 1, dtype=dtypes.bool)
c = UOp.variable("c", 0, 100, dtype=dtypes.int32)
d = UOp.variable("d", 0, 100, dtype=dtypes.int32)

cases = {
  "x_eq_true": xb.eq(True),                                     # :138
  "not_not": xb.logical_not().logical_not(),                    # :140
  "cast_eq_0": xb.cast(dtypes.i32).eq(0),                        # :144
  "cast_eq_1": xb.cast(dtypes.i32).eq(1),
  "cast_eq_2": xb.cast(dtypes.i32).eq(2),
  "x_eq_x": xi.eq(xi),                                           # :155
  "gate_where_ne_0": g.where(xi, 0).ne(0),                       # :271
  "where_where_same_else": a.where(b.where(c, d), d),            # :273
}
for k, v in cases.items():
  print("%s=%s" % (k, sh(sym.rewrite(v))))
