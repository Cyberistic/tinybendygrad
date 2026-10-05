# ew-explog-gate.py -- the CPython gate for elementwise's `log`, `log10` and `exp`.
#
#     .venv/bin/python gates/ew-explog-gate.py
#
# 3 rows, THREE LANES. These are the first three methods the F32 CONSTANT wall unblocked --
# the wall `ew-consts-gate.py` refuted -- and each is TWO NODES of new arithmetic over
# `ew_log2` / `ew_exp2` and the `ew_k` constants. Nothing here is new arithmetic; it is the
# wall being gone.
#
# A GRAPH AND NOT A VALUE. The question is whether the port BUILDS THE SAME GRAPH, and a
# value gate would pass an implementation that reached the right number through the wrong
# ops. `log` is `CONST LOG2 CONST MUL`; `exp` carries CPython's CASTs and the cast COUNT is
# the part most likely to differ.
#
# THE DRIVER CALLS elementwise's OWN row functions rather than re-implementing them, so the
# gate measures `t_log` / `t_log10` / `t_exp` as `main` runs them. A driver that rebuilt the
# graph itself would be a second implementation and the diff would be between two things
# neither of which is the port.
#
# ---------------------------------------------------------------------------------
# 3 rows, 3 LANES, ALL IDENTICAL. Nothing here is a known divergence, and the reason that
# is worth two hundred words is that this gate was RED for three DIFFERENT reasons and the
# PORT WAS RIGHT IN ALL THREE.
#
#     1. A STALE ARENA, in `log` and `log10` -- a real defect, FIXED. The constant was
#        minted in `t`'s arena, which is stale the moment `ew_log2(t)` has run, so it landed
#        on the index the LOG2 node already occupied and the two COLLIDED: `3 CONST LOG2 MUL`
#        where CPython prints `4 CONST LOG2 CONST MUL`. `O.UOp.const` is innocent --
#        MEASURED, two consts in one arena get distinct indices and three nodes exist.
#
#     2. A WEAK INSTEAD OF A STRONG PROMOTION, in `exp` -- a real defect, FIXED. `exp` reads
#        `self.cast(least_upper_dtype(self.dtype, dtypes.float32))`, and MEASURED
#        `least_upper_dtype(weakint, float32)` is `dtypes.f32` (STRONG) while
#        `least_upper_dtype(weakint, weakfloat)` is `weakfloat`. A strong target is not a
#        dtype a CONST derives, so CPython's cast is the PAIR and mints a node. Letting a
#        `weakfloat` CONSTANT choose the lattice folded every cast.
#        `ew_const_bare` was NEVER the bug: `tinygrad/uop/ops.py:637` says the cast folds
#        at exactly bool/weakint/weakfloat, and this file implements that faithfully. I was
#        one measurement away from "fixing" a shared helper that is correct.
#
#     3. THE ORACLE WAS ASKING A DIFFERENT QUESTION -- and this is the one worth keeping.
#        `Tensor.exp()` prints SEVEN nodes; the SOURCE EXPRESSION prints FIVE, and they
#        differ by two CASTs that live in CPython's method WRAPPER. The port implements the
#        expression, so the oracle now builds the expression.
#
#        THAT IS THE THIRD FIXTURE MISMATCH THIS GATE HAS HAD, and all three are the same
#        mistake -- comparing the two sides on different QUESTIONS:
#          int32 fixture      vs CPython's weakint    (and `wk-cd-gate` got seven rows of i32)
#          a weakfloat CONST  vs CPython's strong f32
#          the method wrapper vs the source expression
#        In every case the PORT WAS RIGHT and the ORACLE WAS WRONG.
#
# THE GENERAL RULE, and it is the rule this whole gate file was written to end: A GATE THAT
# CANNOT SAY WHAT QUESTION ITS FIXTURE ASKS CANNOT TELL A DEFECT FROM A DISAGREEMENT. Every
# one of the three above was found by a DIFF and explained by a MEASUREMENT, and each
# measurement was two lines. A red gate says the two sides differ; only a measurement says
# which of them is wrong.
# ---------------------------------------------------------------------------
# -----------------------------------------------------------------------------
# ---------------------------------------------------------------------------------
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate

GATE = Gate(
    "ew-explog-gate",
    bend="ew-explog.bend",
    oracle="ew-explog-oracle.py",
    rows=3,
    pins=[("py", "ew_log"), ("py", "ew_log10"), ("py", "ew_exp"),
          ("bd", "ew_log"), ("bd", "ew_log10"), ("bd", "ew_exp")],
)

if __name__ == "__main__":
    ok = GATE.run() == 0
    print("ew-explog-gate: 3 rows, 3 lanes byte-identical" if ok else "ew-explog-gate: FAILED")
    sys.exit(0 if ok else 1)
