#!/usr/bin/env python3
"""CPython oracle for elementwise's `log`, `log10` and `exp`. GRAPH SIGNATURES.

    .venv/bin/python .agents/slop/ew-explog-oracle.py

    ew_log     = self.log2() * math.log(2)                    (elementwise.py:840)
    ew_log10   = self.log2() * math.log10(2)                  (elementwise.py:852)
    ew_exp     = elementwise.py:511-522, THREE casts:
                 self.cast(least_upper_float(self.dtype)) then
                 self.cast(least_upper_dtype(self.dtype, float32)).mul(1/math.log(2)).exp2().cast(self.dtype)

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
import struct
import sys

from tinygrad import Tensor


def sig(u, nm):
    """`op/n`, and a FLOAT const carries its f32 BITS -- the same convention the port's
    `ew_sig` uses, so the two lanes are comparable as written.

    This is the stronger of the two available claims. A shape-only row would pass an
    implementation that put the WRONG CONSTANT in the right place, and a constant is exactly
    what these three methods are about -- `log` and `log10` differ only in which one they
    multiply by. An int const prints no bits on either side, because the port only resolves
    bits for a float payload."""
    def tok(x):
        if x.op.name == "CONST" and isinstance(x.arg, float):
            return f"CONST/{len(x.src)}={struct.unpack('I', struct.pack('f', x.arg))[0]}"
        return f"{x.op.name}/{len(x.src)}"
    ts = list(u.toposort())
    print(f"{nm}={len(ts)} " + " ".join(tok(x) for x in ts) + " ")


def main():
    t = Tensor(5)
    sig(t.uop.log(), "ew_log")
    sig(t.uop.log10(), "ew_log10")
    # `exp` IS THE METHOD, elementwise.py:511-522, and the port now implements ALL THREE of
    # its casts -- `ew_exp` used to build only the middle one, which is why this gate used to
    # measure the SOURCE expression instead.
    #
    #     Tensor.exp()  ->  7  CONST CAST CAST CONST MUL EXP2 CAST
    #     the SOURCE    ->  5  CONST CAST     CONST MUL EXP2
    #
    # The two extra nodes are cast 1 (`least_upper_float`) and cast 3 (the cast-back), both
    # outside the source expression. `ew_exp` now has them, so the oracle calls the METHOD and
    # the two sides are asked the SAME question again. MEASURED, both:
    # `7 CONST/0 CAST/1 CAST/1 CONST/0=1069066811 MUL/2 EXP2/1 CAST/1 `.
    #
    # THE THREE FIXTURE MISMATCHES THIS GATE'S HISTORY NAMES, kept because the third is what
    # this fix resolves -- comparing the two sides on different QUESTIONS:
    #   int32 fixture      vs CPython's weakint    (wk-cd-gate: seven rows of i32, proving nothing)
    #   a weakfloat CONST  vs CPython's strong f32
    #   the method wrapper vs the source expression    -- FIXED IN THE PORT, so now the METHOD
    sig(t.exp()._uop, "ew_exp")
    print(f"# fixture dtype = {t.dtype}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
