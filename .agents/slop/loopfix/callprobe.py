#!/usr/bin/env python3
"""loopfix/callprobe.py -- DOES `CallInfo.dtype` CHANGE ANY ANSWER, ON EITHER SIDE?

    .venv/bin/python .agents/slop/loopfix/callprobe.py

THE QUESTION. `fold.bend`'s `rg_call` carried a NON-VOID `CallInfo` and its comment said
why: `call_ds.go` was `some_if(not dt is void, ...)`, so a void CALL was a node the ladder
did not answer and the row read ABSENT. That reason is GONE as of 2026-10-06. The only
honest things left to say about the field are (a) is it load-bearing, and (b) what does
CPYTHON do with it -- and CPython's answer is the surprise, because upstream reads a
CALL's dtype off `src[0].dtype` (ops.py:130) and NOT off `CallInfo` at all.

So this prints, per fixture and per arg dtype, the four things a row can depend on: the
dtype CPython computes, whether `CallInfo`'s own dtype field moved anything, and the
`_shape` and `ranges` the differ compares. A fixture field that moves none of them is
DECORATION, and decoration that is load-bearing for the right reason has to be named --
which is the whole of the `rg_call` decision.
"""
import sys

sys.path.insert(0, '.')
from tinygrad.uop.ops import UOp, Ops  # noqa: E402
from tinygrad.uop.spec import AxisType  # noqa: E402
from tinygrad import dtypes  # noqa: E402


def rng(end, axis):
    # `UOp.range(end, (axis,), AxisType.LOOP)` -- the oracle's own helper, verbatim
    # (`oracles/fold-rng-oracle.py:51`), because `UOp(Ops.RANGE, ...)` by hand builds an
    # arg the property does not expect.
    return UOp.range(end, (axis,), AxisType.LOOP)


def rngs(u) -> str:
    return "[" + ",".join(str(r.axis_id[-1][0]) for r in u.ranges) + "]"


def report(tag, u) -> None:
    try:
        dt = u.dtype
    except Exception as exc:                      # noqa: BLE001 -- the ANSWER is the finding
        dt = f"!! {type(exc).__name__}: {exc}"
    try:
        sh = u._shape
    except Exception as exc:                      # noqa: BLE001
        sh = f"!! {type(exc).__name__}"
    print(f"{tag:<26} dtype={dt!s:<52} _shape={sh!s:<10} ranges={rngs(u)}")


c4 = UOp(Ops.CONST, (), 4)
cf = UOp(Ops.CUSTOM_FUNCTION, (), ("myext", dtypes.void))
r0, r1 = rng(c4, 0), rng(c4, 1)

print("== THE TWO `rg_call` FIXTURES, AND THE SAME TWO WITH A VOID CallInfo ARG")
for name, body in (("call_cf", cf), ("call_c", c4)):
    for dt in (dtypes.int32, dtypes.void):
        report(f"{name} arg={dt}", UOp(Ops.CALL, (body, r0, r1), (None, False, False, dt)))

print()
print("== WHAT `src[0].dtype` IS FOR EACH BODY -- THE FIELD ops.py:130 ACTUALLY READS")
report("CUSTOM_FUNCTION body", cf)
report("CONST body", c4)

print()
print("== SO: `CallInfo.dtype` IS NOT AN UPSTREAM FIELD AT ALL.")
print(f"   `repr` of the fixture's arg: {UOp(Ops.CALL, (cf, r0, r1), (None, False, False, dtypes.int32)).arg!r}")
print("   upstream's CallInfo is `CallInfo(grad_fxn, name, precompile, precompile_backward, aux)`,")
print("   so the fixture's 4-tuple IS upstream's arg and its third element is `precompile`.")