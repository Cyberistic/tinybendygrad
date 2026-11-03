"""The CPython half of probe-316.bend: build `x*-1 < c` with the VENDORED tinygrad at HEAD and ask
its own `symbolic.sym` for the answer, so the two renders are answers to the same question.

    .venv/bin/python .agents/slop/sym92/probe-316.py
"""
from tinygrad.uop.ops import UOp, Ops
from tinygrad import dtypes
from tinygrad.uop.symbolic import sym

x = UOp.variable("x", -1000, 1000, dtype=dtypes.int32)
mul = x * -1
for name, node in (("x_mul_neg1_lt_c3", mul < 3), ("x_mul_neg1_lt_cm1", mul < -1),
                   ("x_mul_neg1_lt_cmin", mul < -2147483648)):
  print("%s=%r" % (name, sym.rewrite(node)))
