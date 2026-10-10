#!/usr/bin/env python3
"""fold_graph_census-gate.py -- A VALUE CENSUS of the FOLD PROPERTIES.

    .venv/bin/python gates/fold_graph_census-gate.py

28 ROWS, THREE LANES, TWO DECLARED DIVERGENCES. The seven censuses beside it print OP
SEQUENCES (a graph); this one prints the VALUE a fold property answers, so it is the
read half those seven cannot see.

THE POPULATION. `tinygrad/uop/ops.py` names SEVEN fold properties -- `dtype` (:247),
`is_invalid` (:267), `shape` (:454), `const_like` (:600), `base` (:782), `vmin`
(:1102), `vmax` (:1104) -- and the port answers SIX of them:
`UOp.dtype`/`fold.dt`, `is_invalid`, `UOp.shape`/`fold.shape`, `UOp.base`/`fold.base`,
`UOp.vmin`, `UOp.vmax`. `const_like` is NOT ported: it is a named WALL in
`schedule/rangeify.bend` ("needs `DType.const` and `_mop(EXPAND)`"), and
`grep '^def .*const_like' tinybendygrad/uop/fold.bend` is EMPTY. So the census covers
six of the seven, and the seventh is the FINDING.

THE ROWS VARY THE OP, THE DTYPE AND THE SRC SHAPES, because a fold property's answer
depends on the NODE. The arg-only pair is the point: `fold_c_int3` and `fold_c_int4`
are the same op and dtype with a different CONST arg, so every field but
`vmin`/`vmax` is identical -- the `Rng.sig`-does-not-print-an-arg failure made
visible.

THE TWO DIVERGENCES, BOTH DOCUMENTED IN `fold.bend`, PINNED ON BOTH SIDES:

  `fold_expand_sym` -- the port REFUSES where CPython answers. The marg's SPECIAL has
    an END OF ZERO, so its interval is `[0, -1]`, EMPTY; `sym_dim` refuses it because
    ops.py:408's `all(x >= 0)` is then DECIDABLE and the fold cannot decide it. CPython's
    `ssimplify` is the identity here, so it answers `(2, U(Ops.SPECIAL:N), 4)`. This is
    the `mv_expsym` class (`fold.bend` header, lines 53-59), and it is ONE input class
    rather than "every symbolic marg".

  `fold_reshbare_w` -- the port ANSWERS where CPython RAISES. `w` over `[0, 3]` and
    `prod(ps) = 4` are DISJOINT, so `resolve(..., False)` is decidable and True and
    CPython raises `bad reshape`; this fold answers `(U(Ops.PARAM:w))` because it cannot
    multiply intervals. This is the `mv_reshbare_dis` residual (fold.bend:2053-2059).

  BOTH ARE CARVE-OUTS OF A NAMED INPUT CLASS, not defects: the port's refusal
  convention is documented ("a rule it cannot run is not a rule that passed"), and the
  two are the exact two `fold.bend` names in its own header.

WHAT A VALUE CENSUS CANNOT SEE, and it is named rather than hidden. An IDENTITY CAST is a graph
difference, not a fold-property difference -- both lanes read the same property off the SAME node --
so this census is structurally blind to it. But THE FIRST VERSION OF THIS PARAGRAPH NAMED THE WRONG
SUBJECT AND SAID "IT BELONGS TO THE `md_graph_census` LANE", AND BOTH WERE WRONG.

  * CPython folds it: `tinygrad/mixin/dtype.py:36` is
    `return self if self.dtype == (dt:=to_dtype(dtype)) else self._wrap_uop(...)` (body of the
    `cast` def at `:19`).
  * THE PORT FOLDS IT TOO. `tinybendygrad/mixin/dtype.bend:342` `cast_at.of` is the two-arm match and
    its `True` arm answers `O.Found{md_ar(fx), self}` -- the src, un-minted. `cast_at` was NEVER the
    offender. THE OFFENDER IS `UOp.cast` at `tinybendygrad/uop/ops.bend:2919`, whose body is
    `UOp.new(ar, OpsCAST{}, [self], ADt{dt}, TNone{})` -- it always mints, and its own comment says
    the full check "would need a FOLD CONTEXT, which is what `cast_at` ... IS".
  * SO IT DOES NOT BELONG TO `md_graph_census`: that gate's `cast_same_weakint` pin is
    `1 Ops.CONST/0` on BOTH sides, i.e. evidence that the port DOES fold an identity cast.
  * THE REAL BLAST RADIUS IS ONE FILE, AND IT IS NARROWER THAN "THREE SITES". `grep -rn "UOp\.cast("`
    outside `uop/ops.bend` answers EXACTLY ONE LINE -- `tensor.bend:514` -- and
    `grep -c "wk_cast_at\|cast_at" tinybendygrad/tensor.bend` answers **0**, so `tensor.bend` is the
    ONLY layer that never reaches the folding spelling; every other one goes through
    `W.wk_cast_at(F.folded(ar), ...)`. THAT ALONE IS WHY `ew_graph_census` carries one pin and
    `tn_graph_census` carries six. `tensor.bend` also hand-mints the CAST TWICE more, at `:485` and
    `:1264`, with `O.UOp.new(..., OpsCAST{}, ...)` rather than through the helper -- those are the
    sites to check next, and they are hand-written rather than reached by a broken helper.
    (A tree-wide `OpsCAST{}` grep is NOT the census: most of its ~100 hits are PATTERN-MATCHER
    arms and rewrites whose dtype genuinely differs, where an identity fold would be WRONG. The
    census is of the ones whose target dtype may already be the source's.)

A BLIND SPOT THAT IS NOT BLIND AFTER ALL, which is worth saying: the instrument cannot see it, but a
SIBLING INSTRUMENT CAN, so "this census cannot see X" is not a reason for no gate to see X.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, gate

ROWS = (
    "fold_c_int3",
    "fold_c_int4",
    "fold_c_float",
    "fold_c_bool_t",
    "fold_c_bool_f",
    "fold_c_invalid",
    "fold_buf_i32",
    "fold_buf_i64",
    "fold_add_ii",
    "fold_sub_ii",
    "fold_mul_ii",
    "fold_cast_i32",
    "fold_stack2",
    "fold_reshape22",
    "fold_resh_resh",
    "fold_expand",
    "fold_detach_resh",
    "fold_range5",
    "fold_special4",
    "fold_threefry",
    "fold_noop_buf",
    "fold_store_buf",
    "fold_pad_param",
    "fold_param_neg",
    "fold_expand_sym_pos",
    "fold_expand_sym",
    "fold_reshbare_n",
    "fold_reshbare_w",
)

# (CPython's line, the port's line), pinned on both sides. Both are the two documented
# input classes, not defects; if either is fixed, drop it from DIVERGES.
DIVERGES = {
    "fold_expand_sym": (
        "fold_expand_sym=n=6 op=Ops.EXPAND nsrc=2 srcops=Ops.BUFFER|Ops.STACK dtype=i32 "
        "shape=(2,U(Ops.SPECIAL:N),4) base=Ops.BUFFER self=0 invalid=0 "
        "vmin=-0:2147483648 vmax=+0:2147483647",
        "fold_expand_sym=n=6 op=Ops.EXPAND nsrc=2 srcops=Ops.BUFFER|Ops.STACK dtype=ABSENT "
        "shape=ABSENT base=ABSENT self=- invalid=0 vmin=ABSENT vmax=ABSENT",
    ),
    "fold_reshbare_w": (
        "fold_reshbare_w=n=3 op=Ops.RESHAPE nsrc=2 srcops=Ops.BUFFER|Ops.PARAM dtype=i32 "
        "shape=raise base=Ops.BUFFER self=0 invalid=0 "
        "vmin=-0:2147483648 vmax=+0:2147483647",
        "fold_reshbare_w=n=3 op=Ops.RESHAPE nsrc=2 srcops=Ops.BUFFER|Ops.PARAM dtype=i32 "
        "shape=(U(Ops.PARAM:w)) base=Ops.BUFFER self=0 invalid=0 "
        "vmin=-0:2147483648 vmax=+0:2147483647",
    ),
}

GATE = Gate(
    "fold_graph_census-gate",
    bend="fold_graph_census.bend",
    oracle="fold_graph_census-oracle.py",
    rows=len(ROWS),
    compared=len(ROWS) - len(DIVERGES),
    diverges=DIVERGES,
    pins=[(lane, r) for lane in ("py", "bd", "bn") for r in ROWS],
)

if __name__ == "__main__":
    sys.exit(gate(GATE, "fold_graph_census-gate: 28 rows, 3 lanes, 2 DECLARED divergences -- "
                       "the six ported fold properties (dtype, shape, base, is_invalid, vmin, "
                       "vmax) agree on 26 fixtures byte-for-byte; `const_like` is UNPORTED (a "
                       "rangeify wall); fold_expand_sym is the empty-interval refusal and "
                       "fold_reshbare_w is the disjoint-products residual"))
