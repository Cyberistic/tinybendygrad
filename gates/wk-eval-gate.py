#!/usr/bin/env python3
"""wk-eval-gate.py -- `_eval` and the three dunders, ops.py:521-529.

    .venv/bin/python gates/wk-eval-gate.py

16 rows, THREE LANES -- CPython, bend interpreted, bend compiled -- 15 identical and ONE
documented divergence.

WHY THESE FOUR MARKERS MOVED OUT OF `ops.bend`. The marker for `_eval` sat in `ops.bend`'s
NOT-PORTED block and it CANNOT be written there: `_eval` needs the node's dtype AND its two
bounds, and `ops.bend` imports only `Base`, `helpers` and `LAWS/spec` -- while `UOp.vmin`/`vmax`
are in `fold.bend` and the node-level dtype reader is in `weak.bend`, and BOTH of those import
`ops.bend`. The def sits downstream of the file that wanted it. That is the same relocation
`wk_commit_dtype` already got and the same shape of finding: an import edge, not a language
limit. Measured rather than inferred -- `ops.bend` cannot name `wk_eval_int` at all.

THE THREE CHECKS, AND WHY EVERY REFUSAL PAIRED WITH A `_dt` ROW. `_eval` refuses on the FIRST of
three checks in a fixed order, so a row printing only the outcome could not say which one refused:

    val=none, dt=0   the dtype is not in the caller's set
    val=none, dt=1   the dtype is fine and the bounds differ

All three refusals print `none`, so the `_dt` row beside each is the only thing separating them,
and the two halves have DISJOINT values -- which is what stops a reader that refuses for the wrong
reason from looking identical to one that refuses for the right one.

THE DIVERGENCE IS `simplify`, AND IT IS THE WHOLE OF ops.bend's NEXT WALL.
`int_weakint` asks for `int(UOp.const(7, dtypes.weakint))`, and CPython answers `7`. The port
answers `none`, because CPython's `_eval` reads `self.simplify()._min_max` and the port has no
`simplify`: a CONST carrying an explicit dtype is a CAST node, `min_max` cannot fold it, so the
bounds come back as a RANGE and check 2 refuses. The reader is faithful to the port's substrate;
the substrate is missing the arm. **The 15 identical rows are what make that claim checkable
rather than asserted** -- every other row here reads a value through the same sweep and answers
it, so a reader broken in general would show up everywhere rather than at one row.

WHAT IS PORTED: `wk_bnd_f32` (`BndFlt{v}` -- the half of `Bnd` that `wk_bnd_i64` could not read),
`wk_same` / `wk_same_f` (the "is it a SINGLE number" test, as a two-scrutinee match because the
value cannot be held across its own comparison), the three readers, and `dt_is_bool` /
`dt_is_int` / `dt_is_float` in `mixin/dtype.bend` -- the three `_eval` dtype sets, each a match on
`Cls`, which is why that file models seven classes rather than a signedness flag.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, main

ROWS = (
    "int_weakint_val", "float_weakfloat_val", "bool_true_val", "bool_false_val",
    "int_i32_val", "int_on_range_val", "bool_on_i32_val", "float_on_i32_val",
    "int_weakint_dt", "float_weakfloat_dt", "bool_true_dt", "int_i32_dt",
    "int_on_range_dt", "bool_on_i32_dt", "float_on_i32_dt",
    # `param_noshape`, TWO rows per fixture, and the second is a DIFFERENT question rather than a
    # restatement: a weak dtype must be refused AND must not have allocated a node to be refused
    # about. A reader that built the node and then refused passes `_built=none` and fails `_alloc`.
    "bool_false_dt",
    "param_i32_built", "param_i32_alloc", "param_weakint_built", "param_weakint_alloc",
    "param_weakfloat_built", "param_weakfloat_alloc",
)

GATE = Gate(
    "wk-eval-gate",
    bend="wk-eval.bend",
    oracle="wk-eval-oracle.py",
    rows=len(ROWS),
    # A divergence is a PAIR: where the two sides DIFFER. `int(UOp.const(7, weakint))` is `7` in
    # CPython and `none` here, and one string could only ever have described half of that.
    diverges={"int_weakint_val": ("int_weakint_val=0:7", "int_weakint_val=none")},
    compared=len(ROWS) - 1,
    # Row NAMES are the question, pinned on both lanes; the VALUES are the answer, and pinning
    # them here as well would pin the answer twice over.
    pins=[(lane, row) for lane in ("py", "bd") for row in ROWS],
)

if __name__ == "__main__":
    sys.exit(main(GATE, "wk-eval-gate: 22 rows, 3 lanes -- _eval's dtype set and single-number check, and "
                        "param_noshape's weaks guard -- agree with CPython; 1 divergence "
                        "(int_weakint, which needs simplify)"))
