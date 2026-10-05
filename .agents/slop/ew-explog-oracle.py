#!/usr/bin/env python3
"""CPython oracle for elementwise's `log`, `log10` and `exp`. GRAPH SIGNATURES.

    .venv/bin/python .agents/slop/ew-explog-oracle.py

    ew_log     = self.log2() * math.log(2)                    (elementwise.py:840)
    ew_log10   = self.log2() * math.log10(2)                  (elementwise.py:852)
    ew_exp     = self.cast(least_upper_dtype(self.dtype, float32)).mul(1/math.log(2)).exp2()

THESE ARE THE FIRST THREE METHODS THE CONSTANT WALL UNBLOCKED, and the wall is the one
`ew-consts-gate.py` refuted: the constants are available and bit-exact. Each of these is TWO
NODES of new arithmetic over `ew_log2` / `ew_exp2` and the `ew_k` constants.

THE FIXTURE IS `Tensor(5)` AND ITS DTYPE IS **weakint**, which is not what the name
suggests and is the whole difficulty in `ew_exp`: a weakint operand makes CPython's promotion
mint THREE `CAST` nodes, where an int32 operand would make fewer. The port's fixture
`g_i32()` is an int32 const, so if the two sides disagree the FIXTURE is what to change and
never the claim -- which is why the first thing to check is `exp`'s cast count and not its
multiply.

A GRAPH AND NOT A VALUE, because these are methods and the question is whether the PORT
BUILDS THE SAME GRAPH. `log` is `CONST LOG2 CONST MUL` and any value gate would pass an
implementation that got the right number out of the wrong ops.
"""
import sys

from tinygrad import Tensor


def sig(u, nm):
    ts = list(u.toposort())
    print(f"{nm}={len(ts)} " + " ".join(f"{x.op.name}/{len(x.src)}" for x in ts) + " ")


def main():
    t = Tensor(5)
    sig(t.uop.log(), "ew_log")
    sig(t.uop.log10(), "ew_log10")
    sig(t.uop.exp(), "ew_exp")
    print(f"# fixture dtype = {t.dtype}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
