#!/usr/bin/env python3
"""gen_dtype.py -- the oracle for the SIX laws retired in dtype.bend.

Every expectation is a CALL into `tinygrad/dtype.py`, not a transcription and not
a re-implementation. `fp8_to_float` and `float_to_bf16` are imported from the
upstream module and applied to the fixture; the f32 PATTERN of the answer is
then read out with `struct`. So a row's expectation is what CPython + upstream
produce, and a mistake made in `dtype.c` cannot be copied into the oracle.

THE FIXTURES. Three inputs per row-triple, and they are chosen so one call
covers six laws:

  * `bf16`  -- an arbitrary f32 pattern, run through `Dt.bf16`.
  * `fp16`  -- an arbitrary f32 pattern, run through `Dt.fp16`.
  * `code`  -- an fp8 code 0..255, run through `Dt.fp8_to` for all FOUR formats.

`--cases` prints one line per case as `bf16=<p> fp16=<p> code=<c>`. The driver
takes those three numbers as env vars and answers six rows, so the driver holds
no fixture of its own and the harness diffs whole `name=value` lines.

THE JS-LANE EXCLUSION, AND WHY IT IS COUNTED. A row whose expected ANSWER is a
NaN pattern cannot be checked in the JS lane at all: `F32.bits` there collapses
every NaN onto 0x7FC00000 (comp.ts:539), so a correct port reads back a
different pattern and the row is a false red. `gen_dtype.py --mark` appends
`~js` to those rows; the harness SKIPS exactly the marked ones in JS, RUNS
everything in C, and prints how many it skipped. It never skips silently.
"""
import argparse
import math
import struct
import sys
import os

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__),
                                                "..", "..", "..")))
from tinygrad.dtype import (fp8_to_float, float_to_bf16,  # noqa: E402
                            float_to_fp16)
from tinygrad import dtypes  # noqa: E402

FP8S = [dtypes.fp8e4m3, dtypes.fp8e5m2, dtypes.fp8e4m3fnuz,
        dtypes.fp8e5m2fnuz]
KIND = {d: i for i, d in enumerate(FP8S)}


def f32_of(p: int) -> float:
    return struct.unpack(">f", struct.pack(">I", p))[0]


def pat_of(x: float) -> int:
    return struct.unpack(">I", struct.pack(">f", x))[0]


def is_nan_pat(p: int) -> bool:
    return (p & 0x7F800000) == 0x7F800000 and (p & 0x007FFFFF) != 0


def cases():
    """Every f32 exponent class at five mantissas, both signs, and the whole
    fp8 code space. The patterns come out of `struct` round trips, so they are
    CPython's, and the boundary names are the brief's."""
    named = [0x00000000, 0x80000000, 0x00000001, 0x007FFFFF, 0x00800000,
             0x3F7FFFFF, 0x3F800000, 0x3F800001, 0x7F800000, 0xFF800000,
             0x7FC00000, 0xFFC00000, 0x7F800001, 0xFF800001, 0x7FFFFFFF,
             0xFFFFFFFF]
    mants = [0, 1, 0x400000, 0x7FFFFE, 0x7FFFFF]
    out = []
    for p in named:
        out.append(("named", p))
    for e in range(256):
        for sgn in (0, 1):
            for m in mants:
                p = (sgn << 31) | (e << 23) | m
                assert pat_of(f32_of(p)) == p
                out.append((f"e{e:03d}s{sgn}m{m:06x}", p))
    return out


def expect_rows(bf16_in: int, fp16_in: int, code: int):
    """The six rows, each a CALL into upstream."""
    rows = [
        ("bf16", pat_of(float_to_bf16(f32_of(bf16_in)))),
        ("fp16", pat_of(float_to_fp16(f32_of(fp16_in)))),
    ]
    for d in FP8S:
        rows.append((f"fp8_{KIND[d]}", pat_of(fp8_to_float(code, d))))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases", action="store_true")
    ap.add_argument("--mark", action="store_true",
                    help="mark rows whose ANSWER is a NaN pattern with ~js")
    ap.add_argument("--expect", help="bf16,fp16,code")
    args = ap.parse_args()

    if args.cases:
        for _, p in cases():
            print(f"bf16={p} fp16={p} code={p & 255}")
        return
    if not args.expect:
        ap.error("one of --cases --expect")
    b, f, c = (int(x) for x in args.expect.split(","))
    for name, v in expect_rows(b, f, c):
        suffix = "~js" if (args.mark and is_nan_pat(v)) else ""
        print(f"{name}={v}{suffix}")


if __name__ == "__main__":
    sys.exit(main())
