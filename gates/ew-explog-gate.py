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
# `ew_log` AND `ew_log10` ARE GREEN. `ew_exp` IS RED, AND IT IS A PROMOTION-COUNT QUESTION
# RATHER THAN A DTYPE ONE:
#
#     CPython  ew_exp = 7  CONST CAST CAST CONST MUL EXP2 CAST
#     this              5  CONST CAST     CONST MUL EXP2
#
# TWO DEFECTS WERE FOUND HERE, and both are recorded because one of them was a WRONG
# SUSPICION that a measurement killed.
#
# 1. A **STALE ARENA**, in `log` and `log10` -- FIXED. The constant was minted in `t`'s
#    arena, which is stale the moment `ew_log2(t)` has run, so it landed on the index the
#    LOG2 node already occupied and the two COLLIDED: `3 CONST LOG2 MUL` where CPython
#    prints `4 CONST LOG2 CONST MUL`. `O.UOp.const` is innocent -- MEASURED, two consts in
#    one arena get distinct indices and three nodes exist. Both now mint through one helper
#    that takes the RESULT's arena.
#
# 2. A **WEAK INSTEAD OF A STRONG PROMOTION**, in `exp` -- FIXED. `exp` is
#    `self.cast(least_upper_dtype(self.dtype, dtypes.float32)).mul(1/log(2)).exp2()` and the
#    `float32` is the whole point: MEASURED, `least_upper_dtype(weakint, float32)` is
#    `dtypes.f32` -- STRONG -- while `least_upper_dtype(weakint, weakfloat)` is `weakfloat`.
#    A strong target is not a dtype a CONST derives, so CPython's cast is the PAIR and
#    mints a node; a weak target folds. Letting a `weakfloat` CONSTANT decide the lattice
#    folded every cast and printed 4 nodes.
#
# `ew_const_bare` WAS NEVER THE BUG, and that is the part worth keeping:
# `tinygrad/uop/ops.py:637` says the cast folds at exactly bool/weakint/weakfloat, and
# `elementwise.bend:305` implements that faithfully. **I was one measurement away from
# "fixing" a shared helper that is correct**, and the gate is what stopped me -- a value
# gate would have passed the fold and a shape gate would have said only "4 != 7".
#
# WHAT IS LEFT IS THE COUNT. CPython mints THREE casts -- two on the input, one on the
# result -- and the port mints ONE, so its promotion is not minting the pair for a STRONG
# promotion the way `ew_const_bare`'s own comment says it should. That is in SHARED
# promotion code, and a patch there changes every gated row that promotes across a strong
# dtype. It is recorded rather than applied: a blast radius that wide is a decision.
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
