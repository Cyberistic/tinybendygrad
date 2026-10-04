#!/usr/bin/env python3
"""CPython oracle for elementwise.bend's F32 constants. BIT PATTERNS.

    .venv/bin/python .agents/slop/ew-consts-oracle.py

THE ROWS ARE BIT PATTERNS AND NOT DECIMALS. A gate that compared `0.044715` against
`0.044715` would pass on a transcription that is wrong in the ninth decimal place and still
rounds to the right f32 -- which is the whole failure mode of the thing being gated. The
port has no `F64` at all (`rg '^type F64' tinybendygrad/` is zero hits), so the only place
two sides can MEET is the 32 bits.

CPython's answer is `struct.unpack('I', struct.pack('f', x))[0]`: pack the double into the
nearest f32, then read those 32 bits back. One correctly-rounded step, which is the only
definition of "the f32 of this constant" worth gating.

WHAT THIS GATE DOES **NOT** CLAIM, and the first draft of it did, wrongly: it does not
compare DECIMALS. Two reasons, and the first one was my own error. The draft printed
CPython's original DOUBLE against the port's `H.f32_show` of the f32 -- two different
quantities -- so all 21 rows differed and the diff said nothing. Underneath that error
there is a real difference worth naming: `H.f32_show` is a SIX-DECIMAL-PLACE formatter and
CPython's `repr` is a SHORTEST-ROUND-TRIP one, so f32(log 2) is `0.693147` here and
`0.6931471824645996` there. That is a claim about the PRINTER, not about the constants, and
it is a separate unit. A gate that asserted it would be asserting something this unit did
not measure, and a gate that quietly dropped it would be hiding a known divergence.

THE THREE ROWS THAT ARE NOT OBVIOUS, because each one MEASURED a wrong first attempt:

  k_log10_2        `0.30102999` -- eight decimals, more precise on paper -- rounds to
                   0x3E9A209A. CPython's f32(log10 2) is 0x3E9A209B. FIVE decimals,
                   `0.30103`, is CORRECT. **More digits is not more accurate in f32**, and
                   the intuition that it is cost one round.
  k_selu_gamma     same shape: `1.0507009` is wrong and `1.050701` is right.
  k_sqrt_2_over_pi  a COMPOSITE, `F32.sqrt(F32.div(2.0, F32.pi()))`, is one ulp off,
                   because it rounds twice -- once for the quotient and once for the sqrt --
                   where CPython rounds once at the end. **A literal cannot double-round**,
                   so this constant is a literal and not an expression. That is the
                   general rule this table exists to record.

  k_pi             `F32.pi()` is spelled `3.14159265` in base.bend -- a TRUNCATION -- and
                   it still equals CPython's f32(pi) = 0x40490FDB, because the truncation
                   is under half an ulp. Asserted rather than assumed, since "obviously
                   fine" is how a truncated constant survives a review.
"""
import math
import struct
import sys

ROWS = [
    # the eight NAMED transcriptions: the typo surface, one def each
    ("k_log2", lambda: math.log(2)),
    ("k_log10_2", lambda: math.log10(2)),
    ("k_inv_log2", lambda: 1 / math.log(2)),
    ("k_sqrt_2", lambda: math.sqrt(2)),
    ("k_sqrt_2_over_pi", lambda: math.sqrt(2 / math.pi)),
    ("k_gelu", lambda: 0.044715),
    ("k_quick_gelu", lambda: 1.702),
    ("k_selu_alpha", lambda: 1.6732631926242618),
    ("k_selu_gamma", lambda: 1.0507009873554805),
    # and the constants the marker block claimed were impossible at all
    ("k_pi", lambda: math.pi),
    ("k_pi_2", lambda: math.pi / 2),
    ("k_sixth", lambda: 1 / 6),
    ("k_half", lambda: 0.5),
    ("k_one", lambda: 1.0),
    ("k_two", lambda: 2.0),
    ("k_neg_one", lambda: -1.0),
    ("k_leak", lambda: 0.01),
    ("k_rtol", lambda: 1e-05),
    ("k_atol", lambda: 1e-08),
    ("k_e", lambda: math.e),
    ("k_two_pi", lambda: math.pi * 2),
]


def f32_bits(x):
    return struct.unpack('I', struct.pack('f', x))[0]


def main():
    for nm, f in ROWS:
        print(f"{nm}={f32_bits(f())}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
