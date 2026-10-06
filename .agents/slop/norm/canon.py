#!/usr/bin/env python3
"""canon.py -- THE ONE canonical spelling of a float of a KNOWN WIDTH.

A normaliser that rounds differently on the two sides of a gate MANUFACTURES a
disagreement that is not one.  Three of them were found in this tree, in three
different units, in one day, and each printed a plausible line of output:

  * `jslane2/gen_f32_seam.py`'s `norm` was `repr(float(s))` with NO round trip,
    so it would have called `fp16(1.1)` a LANE disagreement for a FORMATTING
    reason -- `F32.show` prints the shortest f32-round-tripping decimal
    `1.0996094` where CPython, holding a double, prints `1.099609375`, and both
    are the SAME f32.  It escaped only because no `1.1` row was in its CASES.
  * `F32.show` PRINTS SEVEN-TO-NINE DIGITS (`references/bend/bend2/bend.ts:1197`
    `f32_show`, spliced into the JS runtime by `comp.ts:520`), so both sides
    must round through one width before they are compared.  MEASURED HERE:
    `f32_show(1.0)` is `1`, NOT `1.0` -- the `.0` at `bend.ts:1202` is applied
    only by the diagnostic printer at `comp.ts:788`, so JSL2-7's `448` vs
    `448.0` is real and the gate had to notice it.
  * the C/JS differ had a first float CONST that failed ON BOTH SIDES AT ONCE,
    `repr(ConstFloat(1.0))` against `F32.show(1.0)`, which is now IEEE-754 bits
    on both sides -- the only spelling that also separates two NaNs.

So the rule is ONE LINE and it is not about printing:

    A float is compared at the width OF THE SEAM THAT CARRIED IT, on BOTH
    sides, through THIS MODULE, and nowhere else.

## WHY THE WIDTH IS AN ARGUMENT AND NOT A CONSTANT

`1.0 + 2**-40` is the row that makes this unavoidable.  It is `0x3ff0000000001000`
in f64 and it rounds to EXACTLY `1.0` in f32 -- `e2e.sh:215` already says so and
calls it "THE ROW f32 CANNOT HAVE".  A normaliser that hard-codes one width
therefore answers one of two questions depending on which width it happens to
hard-code, and the reader cannot tell which from the output.  `canon(x, width)`
cannot be called without naming the width, so that failure is a type error
rather than a plausible row.

## WHY TWO ENTRY POINTS, AND IT IS NOT A CONVENTION

`canon` takes a VALUE (a Python float, or a decimal spelling off a lane).
`canon_bits` takes a PATTERN (the integer bits at `width`).  They are separate
because **NEITHER SIDE OF A GATE CAN HOLD A NaN PAYLOAD IN A FLOAT**:

  * CPython's `float` has no payload -- every NaN is one value, so the ORACLE
    side cannot even express `0x7FC00001` as a float.
  * JavaScript's `NaN` is one value too (`fu(0/0) == 0x7fc00000`, MEASURED).

**A NORMALISER THAT CLAIMS TO SEPARATE NaNs IS SEPARATING THEM ON ONE SIDE.**
`canon` therefore REFUSES: given a spelling that parses to NaN it answers
`<width>:?nan`, a string that is equal to NO pattern's canonical spelling, so a
gate cannot quietly call two different NaNs the same row.  `canon_bits` is the
only entry point that can separate them, and a gate that uses it must say what
it does when a lane has already lost the payload -- `gate_norm.py` prints that
outcome as its OWN THIRD VERDICT, never as a pass and never as a fail.

WHAT IS MEASURED ABOUT THE JS LANE'S NaN, because `tinybendygrad/base.bend:42`
CLAIMS OTHERWISE: on `node` v26.8.1 (darwin) `f32_bits(f32_from_bits(p)) == p`
for `p = 0x7fc00001, 0x7fc00000, 0xffc00001, 0xffc00002` -- the Float32Array
round trip KEEPS the payload -- while a NaN manufactured by JavaScript itself
(`0/0`) is `0x7fc00000`.  So the payload survives the TYPED-ARRAY path and does
not survive ARITHMETIC.  `base.bend` is not this unit's file; reported, not
edited.

## WHAT IT COSTS, STATED BECAUSE IT IS NOT FREE

This is a NINTH convention in a tree that already has EIGHT live ABI ones
(ABI-1 argument count, ABI-2 record field names, ABI-3 pair order, ABI-4 scalar
transport, ABI-5 `Term` is `u64` in C and `number` in node, ABI-6 zero divisor,
ABI-7 `dtype.js`'s return-style split, ABI-8 JS's `NaN` is a value not a
pattern).  The costs, measured rather than asserted:

  * ONE file, two functions, no language split -- because BOTH lanes are
    normalised in Python, from TEXT, after they have run.  The helper never has
    to exist in `.bend`, in C, or in JS.  That is the whole reason one helper
    is possible at all, and it is a property of the gates, not a happy accident.
  * a `.bend` gate that wants a BITS row must print `U32.show(F32.bits(v))` and
    not `F32.show(v)` -- one line in the emitter per gate, and `gate_norm.py`
    and `canon.selftest.py` carry both spellings side by side so the difference
    is measured instead of remembered.
  * `lint_norm.py` is what makes it stick.  A helper nobody is forced through is
    a helper that is bypassed the first time it is inconvenient, and the four
    instruments this tree has already been burned by each produced a plausible
    line and a wrong verdict.  The lint is the enforcement, not the helper.

## WHERE THE GATES ARE, AND THE ONES THAT ARE NOT ON IT YET

ON IT: `norm/gate_norm.py`, `norm/canon.selftest.py`, `jslane2/gen_f32_seam.py`
(its `norm`, which was the instance the brief names).

NOT ON IT, with the reason, so the next reader does not have to re-derive it:

  * `abi/abi_gate.py:118` -- EXPLICITLY DO-NOT-TOUCH, and it is already correct:
    `repr(struct.unpack("<f", struct.pack("<f", v))[0])` round-trips at f32.
  * `abi4/abi4_gate.py:235` -- EXPLICITLY DO-NOT-TOUCH, and already correct, the
    same expression.
  * `jstage/jsstage.py:300` -- another unit's tree, and already correct: an `f32`
    round trip plus `math.isnan` on both sides.  Its `:305` comment is the first
    written statement of the defect this module answers.
  * `mm-dt-gate.py:60` and `mm-walk-gate.py:44` -- another unit's tree, and
    **NOT CORRECT**: `"F" + (f"{v:g}" if v.is_integer() else repr(v))` fixes the
    `448` vs `448.0` half of the trap and leaves the `1.0996094` vs
    `1.099609375` half open.  See `census.txt`; reported, not edited.
  * `dc-oracle.py:131` -- another unit's tree, and **NOT CORRECT, AND THE AUTHOR
    KNEW**: the comment says "`%g` agrees with `H.f32_show` on 1.0 -- the only
    float CONST in this file -- and would NOT agree on a non-integral one."
    `f"{v:g}"` is SIX significant digits, so it is not merely a different
    shortest form: it can map two DIFFERENT f32 values to the same string.
  * `graphcmp.py:459` and `bend_e2e.py:71` -- DO-NOT-TOUCH.  `graphcmp.py` is
    already bits-based and is the fix the brief cites as instance 3.
"""
from __future__ import annotations

import math
import struct

#: the widths a seam in this tree can carry, in BYTES.  `bf16` is 2 and its
#: canonical spelling is 8 hex digits because a bf16 value IS an f32 with its
#: low 16 bits zero -- `struct` has no bf16 format and inventing one would be a
#: second rounding.  There is NO `f8` for the same reason as no `bf16` format:
#: an fp8 code is 8 BITS WIDE, so `fp8_to_float` yields an f32 and the row is
#: canonicalised at f32.  That is a fact about the carrier, not a missing entry.
WIDTHS: dict[str, int] = {"f64": 8, "f32": 4, "f16": 2, "bf16": 4}

#: BIG ENDIAN on both sides of every pack, so a canonical spelling reads in the
#: SAME order `F32.bits` and `U32.show` print it: `1.0` is `f32:3f800000`, not
#: `f32:0000803f`.  Rounding is byte-order-independent; only the reading is not.
_FMT = {"f64": ">d", "f32": ">f", "f16": ">e", "bf16": ">f"}
_UFMT = {"f64": ">Q", "f32": ">I", "f16": ">H", "bf16": ">I"}

BF16_ROUND = 0x7FFF  # `float_to_bf16`'s own bias, and the half that rounds up


def round_to(x: float, width: str) -> float:
    """`x` rounded ONCE to `width`.  ONE, and `struct` does the single rounding.

    NOT `round(f32(x), f16(x))`: that is double rounding, and
    `beautiful-mnist-gate.py:45-51` records a live instance of it in the OTHER
    direction (CPython rounds once at the store, a port that rounds per
    operation differs by one ULP on `1/sqrt(32*9)`).  `bf16` is the one width
    `struct` cannot do, so it is `f32` then the high half's own
    round-half-to-even, which is `tinygrad/dtype.py:229-232`'s step verbatim.
    """
    _check(width)
    if width == "bf16":
        u = struct.unpack(_UFMT["bf16"], struct.pack(_FMT["bf16"], x))[0]
        u = (u + BF16_ROUND + ((u >> 16) & 1)) & 0xFFFF0000
        return struct.unpack(_FMT["bf16"], struct.pack(_UFMT["bf16"], u))[0]
    return struct.unpack(_FMT[width], struct.pack(_FMT[width], x))[0]


def bits(x: float, width: str) -> int:
    """`x`, rounded to `width`, as that width's IEEE-754 bit pattern.

    THE ONLY SPELLING THAT DOES NOT ROUND AT ALL, so it is the only one a row
    that claims to be about a VALUE may compare.  `f32_bits` and `F32.bits` are
    the same function on both lanes: `struct.unpack("<I", struct.pack("<f", 1.0))`
    and `F32.bits(1.0)` are both `1065353216` (MEASURED, `graphcmp.py:2816`).
    """
    _check(width)
    return struct.unpack(_UFMT[width], struct.pack(_FMT[width], round_to(x, width)))[0]


def canon(value: float | str, width: str) -> str:
    """THE canonical spelling of a float VALUE, at `width`.

    `value` is a Python float OR a decimal spelling off a lane (`F32.show`, or
    `repr()` of CPython's answer).  A string that is not a float at all comes
    back UNCHANGED, so this can sit in a generic row comparer without knowing
    which of its rows are floats.

    THE NaN REFUSAL IS THE POINT.  A spelling parses to a float, and a NaN
    parsed from `"nan"` would then be PACKED as `0x7fc00000` -- a payload the
    text never carried.  That is a one-mistake-copied answer, so this returns
    `"<width>:?nan"` instead: a string equal to no pattern's spelling, which
    forces a gate to notice that it is comparing a NaN it cannot resolve.
    """
    _check(width)
    if isinstance(value, str):
        try:
            x = float(value)
        except ValueError:
            return value
    else:
        x = float(value)
    if math.isnan(x):
        return f"{width}:?nan"
    return f"{width}:{bits(x, width):0{_hexdigits(width)}x}"


def canon_bits(pattern: int, width: str) -> str:
    """THE canonical spelling of an IEEE-754 PATTERN at `width`, and the ONLY
    entry point that separates two NaNs.

    `pattern` is the integer bits AT `width`, so there is nothing to round and
    `0x7fc00001` and `0x7fc00000` get different answers.  CPython's `float`
    cannot express either of them and JavaScript's `NaN` is one value, so a gate
    that needs this MUST know what its lane did with the payload -- see
    `gate_norm.py`'s `JS-NAN-LOSS` verdict.
    """
    _check(width)
    return f"{width}:{pattern & ((1 << 8 * WIDTHS[width]) - 1):0{_hexdigits(width)}x}"


def _check(width: str) -> None:
    if width not in WIDTHS:
        raise ValueError(f"width {width!r} is not one of {sorted(WIDTHS)}")


def _hexdigits(width: str) -> int:
    return WIDTHS[width] * 2


def spells_differ(left: object, right: object, width: str) -> bool:
    """`left` and `right` are DIFFERENT VALUES at `width`, by whatever spelling
    each arrived in.  This is the ONE comparison a gate should make, because it
    is the only one that cannot forget the width or the NaN refusal.
    """
    return canon(left, width) != canon(right, width)