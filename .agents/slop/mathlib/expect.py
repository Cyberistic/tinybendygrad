#!/usr/bin/env python3
"""Generate the F32 bit-pattern expectations for `lit_probe.bend` BY CALLING CPython.

agent-core.md: "Generate every `py=` expectation BY CALLING CPYTHON. Never type
one." and the sharper version -- "Agreement between a port and a hand-typed
oracle is not corroboration; it is one mistake copied." So these come from
CPython's own `struct`, and the f32 rounding is done by `struct.pack`/`unpack`,
not by me.

The values under test are the constants that the 37-mention `math.inf` / `math.pi`
/ `math.log(2)` cluster NAMES, plus the 3 special values. CPython's `math` module
supplies them; this script prints what an f32 CONTAINING them must look like.

Writes `.agents/slop/mathlib/expect.txt`. Run twice and diff -- agent-core.md's
"write the expected values down and run twice".
"""
import math
import pathlib
import struct

HERE = pathlib.Path(__file__).resolve().parent


def f32(x: float) -> str:
    """The 8 hex digits of the f32 nearest `x`. CPython does the rounding."""
    (bits,) = struct.unpack(">I", struct.pack(">f", x))
    return f"{bits:08x}"


def main() -> int:
    rows = [
        ("inf", math.inf),
        ("ninf", -math.inf),
        ("nan", math.nan),
        ("pi", math.pi),
        ("log2", math.log(2)),
        ("log10_2", math.log10(2)),
        ("sqrt2", math.sqrt(2)),
        ("invlog2", 1 / math.log(2)),
        ("2pi", 2 * math.pi),
        ("0.5", 0.5),
    ]
    lines = []
    for name, val in rows:
        # `0.5` and friends are exact; the rest are the f32-rounded decimal. Round
        # through f32 FIRST so the printed constant is the one a port must write.
        lines.append(f"{name:<8} {f32(val)}")
    text = "\n".join(lines) + "\n"
    (HERE / "expect.txt").write_text(text)
    print(text, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())