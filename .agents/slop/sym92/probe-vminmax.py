"""CPython answers for `UOp._min_max`, in the port's canonical form.

    .venv/bin/python .agents/slop/sym92/probe-vminmax.py

The port's half is probe-vminmax.bend.

THIS IS ONE OF THE THREE WALLS THE `divandmod.bend` TODO BLOCK NAMES. THE OTHERS ARE `divides`
(MEASURED: THE PORT'S ANSWERS THE SAME AS UPSTREAM'S, SO THAT WALL IS STALE) AND
`const_factor` (THE PORT HAS A FULL GCD FOLD AT `ops.bend:7855`). THE `_min_max` WALL IS THE ONE
THAT GATES `fold_divmod_congruence`, `nest_by_factor` AND `factor_remainder`.
"""
from tinygrad.uop.ops import UOp, Ops
from tinygrad import dtypes

x = UOp.variable("x", 0, 10, dtype=dtypes.weakint)
y = UOp.variable("y", -5, 5, dtype=dtypes.weakint)
for nm, e in [("x", x), ("y", y), ("x*4", x * 4), ("x+y", x + y), ("x*4+8", x * 4 + 8)]:
  print("%s=[%s..%s]" % (nm, e.vmin, e.vmax))
