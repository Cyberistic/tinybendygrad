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
# THIS GATE IS CURRENTLY **RED**, and the cause is a REAL DEFECT IN `ew_log` / `ew_log10`
# -- not a fixture mismatch, which is what this header first claimed.
#
#   THE FIXTURE IS FINE, and that took a measurement to establish. `g_i32()` is named for
#   int32 and is actually **weakint**: `uop/fold.bend:1949` types a bare `O.CInt` const as
#   `S.weakint()`. So the port's fixture and CPython's `Tensor(5)` -- also weakint -- ARE the
#   same dtype, and the two shapes to compare are CPython's weakint ones:
#
#       CPython  ew_log = 4  CONST LOG2 CONST MUL
#       this              3  CONST LOG2 MUL
#       CPython  ew_exp = 7  CONST CAST CAST CONST MUL EXP2 CAST
#       this              4  CONST CONST MUL EXP2
#
#   SO THE MISSING NODE IS THE FLOAT CONSTANT. `ew_log` is
#   `ew_mul2(ew_log2(t), ew_ct(ew_cf(T.Tensor.ar(t), ew_k.log2())), False{})` and the
#   constant is not appearing in the MUL's srcs at all -- the MUL's two srcs are the input
#   const and the LOG2. `ew_exp` has the same defect with the opposite sign: its constants
#   ARE nodes (both print with f32 bits) but it mints no CASTs, and CPython's does because
#   `least_upper_dtype(weakint, float32)` is not the weakint's own dtype.
#
#   The next unit is therefore NOT a fixture change. It is: why does a const TENSOR built
#   by `ew_ct(ew_cf(...))` in the tensor's own arena stop being a distinct node, and where
#   the promotion is supposed to put the CASTs. Both are questions about `ew_mul2` and the
#   weak arm of `ew_promote`, and both are answerable with a row rather than by reasoning.
# ---------------------------------------------------------------------------------
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate

GATE = Gate(
    "ew-explog-gate",
    bend=".agents/slop/ew-explog.bend",
    oracle=".agents/slop/ew-explog-oracle.py",
    rows=3,
    pins=[("py", "ew_log"), ("py", "ew_log10"), ("py", "ew_exp"),
          ("bd", "ew_log"), ("bd", "ew_log10"), ("bd", "ew_exp")],
)

if __name__ == "__main__":
    ok = GATE.run() == 0
    print("ew-explog-gate: 3 rows, 3 lanes byte-identical" if ok else "ew-explog-gate: FAILED")
    sys.exit(0 if ok else 1)
