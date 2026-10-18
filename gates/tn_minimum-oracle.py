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

`cpython_ops_decl` is the SAME enum in DECLARATION order, and it exists because
`tinygrad/uop/__init__.py:12` says, verbatim and in upstream's own file:

    # the order of these Ops controls the order of the toposort

A sorted list cannot carry that claim, so a gate reading only `cpython_ops` prints
PASS on a reordered enum. MEASURED 2026-10-18T18:01:55Z, `git grep -e 'for [a-z_]* in
Ops\\b' -e 'list(Ops)' -e 'Ops.__members__' refs/remotes/upstream/HEAD -- tinygrad`
returns rc=1, ZERO hits: **no upstream code path reads the enum's order.** So this row
HONOURS AN UPSTREAM CLAIM MADE IN A COMMENT; it does not measure an upstream behaviour,
and the gate says so in its own output rather than leaving it to this file's docstring.

`cpython_ops` is left byte-identical -- including the `sorted(...)` spelling, which
`gates/gapcensus.py:214` reads as a literal out of THIS FILE's source.
"""

from tinygrad.uop.ops import Ops

names = sorted(o.name for o in Ops)
decl = [o.name for o in Ops]
print(f"cpython_ops_count={len(names)}")
print(f"min_in_cpython={int('MIN' in Ops.__members__)}")
print("cpython_ops=" + ",".join(names))
print("cpython_ops_decl=" + ",".join(decl))
