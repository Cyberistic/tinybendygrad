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
import struct
import sys

import math

from tinygrad import Tensor, dtypes


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
    # `exp` IS BUILT FROM ITS SOURCE EXPRESSION AND NOT BY CALLING THE METHOD, and that
    # is the whole difference between 5 nodes and 7.
    #
    #     Tensor.exp()  ->  7  CONST CAST CAST CONST MUL EXP2 CAST
    #     the SOURCE    ->  5  CONST CAST     CONST MUL EXP2
    #
    # The port implements the SOURCE, so the oracle has to measure the source. The two extra
    # nodes are in CPython's `Tensor.exp()` WRAPPER, which this port does not have and is
    # not asked to have. MEASURED, both ways, in the same process.
    #
    # THAT IS THE THIRD TIME A FIXTURE MISMATCH HAS BITTEN THIS GATE, and the three are
    # worth listing because they are all the same mistake -- comparing the two sides on
    # different QUESTIONS:
    #   int32 fixture vs CPython's weakint  (wk-cd-gate: seven rows of i32, proving nothing)
    #   a weakfloat CONST choosing the lattice vs CPython's strong float32  (ew_exp: 4 vs 7)
    #   the METHOD WRAPPER vs the SOURCE EXPRESSION                            (ew_exp: 7 vs 5)
    # In every case the port was right and the ORACLE was asking a different question.
    sig((t.cast(dtypes.float32) * (1 / math.log(2))).exp2()._uop, "ew_exp")
    print(f"# fixture dtype = {t.dtype}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
