#!/usr/bin/env python3
"""tn_minimum-oracle.py -- CPython's `Ops`, the interpreter-side witness.

    .venv/bin/python gates/tn_minimum-oracle.py

THE BRIEF SAID `Tensor.minimum` IS WALLED ON A MISSING `OpsMIN{}`. IT IS NOT:
CPython's `Ops` has NO `MIN` member -- `minimum` (mixin/elementwise.py:393) is
built from `Ops.MAX` (float arm `-(-t).alu(Ops.MAX, -x)`; int arm
`(t ^ k).alu(Ops.MAX, x ^ k) ^ k`). This oracle emits CPython's enum BY
DISCOVERY (`list(Ops)`, never a hand list) so the gate can compare it against
the port's constructors, which are read from `tinybendygrad/uop/ops.bend`.

`cpython_ops` is the sorted member list joined by `,`; `min_in_cpython` asks the
interpreter directly rather than trusting a grep.
"""

from tinygrad.uop.ops import Ops

names = sorted(o.name for o in Ops)
print(f"cpython_ops_count={len(names)}")
print(f"min_in_cpython={int('MIN' in Ops.__members__)}")
print("cpython_ops=" + ",".join(names))
