#!/usr/bin/env python3
"""gate_dtype.py -- diff the SIX retired laws in dtype.bend against CPython.

WHAT IS DIFFED: whole `name=value` lines, NEVER row names. agent-core records a
name-comparing harness that reported 0 for all 68 mutations in one unit, so a
name comparison here would be the instrument that already failed.

THE ORACLE IS A CALL. `expect.py`'s sibling `gen_dtype.py` imports
`float_to_bf16`, `float_to_fp16` and `fp8_to_float` from `tinygrad/dtype.py`
and applies them; the f32 PATTERN of each answer is read out with `struct`. So no
expectation here is typed, and a mistake in `runtime/dtype.c` cannot be copied
into it -- the whole point of the gate is that the port and the C are two
readings of dtype.py and neither is the oracle.

THE JS-LANE EXCLUSION. A row whose expected ANSWER is a NaN pattern cannot be
checked in the JS lane at all: `F32.bits` there collapses every NaN onto
0x7FC00000 (comp.ts:539 `f32_from_bits`), so a CORRECT port reads back a
different pattern and the row is a false red. Those rows are decided from the
ORACLE's answer and skipped in JS only; the skipped count is printed and the
C lane runs all of them. `from_bits` itself is gated separately by `run.py`,
which measures the NaN collapse rather than skipping around it.
"""
import argparse
import os
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, ROOT)
from tinygrad.dtype import (fp8_to_float, float_to_bf16,  # noqa: E402
                            float_to_fp16)
from tinygrad import dtypes  # noqa: E402

FP8S = [dtypes.fp8e4m3, dtypes.fp8e5m2, dtypes.fp8e4m3fnuz,
        dtypes.fp8e5m2fnuz]


def f32_of(p):
    return struct.unpack(">f", struct.pack(">I", p))[0]


def pat_of(x):
    return struct.unpack(">I", struct.pack(">f", x))[0]


def is_nan_pat(p):
    return (p & 0x7F800000) == 0x7F800000 and (p & 0x007FFFFF) != 0


def expected(start, count):
    """Every row the driver will print, as `name=value`, from upstream."""
    out = {}
    for p in range(start, start + count):
        x = f32_of(p)
        out[f"bf16_{p}"] = pat_of(float_to_bf16(x))
        out[f"fp16_{p}"] = pat_of(float_to_fp16(x))
        c = p & 255
        for k, d in enumerate(FP8S):
            out[f"fp8_{k}_{c}"] = pat_of(fp8_to_float(c, d))
    return out


def ranges():
    """The sweep blocks. Every one is named after what it is FOR, not chosen by
    hand-picked values:
      all_codes      0..255            every fp8 code, all four formats
      zero_boundary  the +-0 / subnormal / min-normal / 1.0 neighbourhood
      norm_top       the max-normal -> inf boundary
      inf_nan        the first 256 positive NaN payloads, bit by bit
      nan_neg        the same with the sign bit set
      seed_N         deterministic pseudo-random blocks over the whole space
    The seeds are printed by `--ranges` so the set is reproducible."""
    out = [("all_codes", 0, 256),
           ("zero_boundary", 0, 1024),
           ("just_below_one", 1065353216 - 512, 1024),
           ("subnormal_top", 8388608 - 1024, 2048),
           ("norm_top", 2139095039 - 1024, 2048),
           ("inf_nan", 2139095040, 4096),
           ("nan_neg", 4286578688, 4096),
           ("hi_block", 4294967295 - 4096, 4096)]
    s = 12345
    for i in range(24):
        s = (s * 1103515245 + 12345) % (2 ** 32)
        out.append((f"seed_{i}", s % (2 ** 32 - 8192), 8192))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lane", choices=["js", "c"], required=True)
    ap.add_argument("--bend")
    ap.add_argument("--binary")
    ap.add_argument("--ranges", action="store_true")
    args = ap.parse_args()

    if args.ranges:
        for n, s, c in ranges():
            print(f"{n} {s} {c}")
        return 0

    cmd = [args.bend, os.path.join(HERE, "gate_dtype.bend")] \
        if args.lane == "js" else [args.binary]
    moved, rows, skipped = [], 0, 0
    for name, start, count in ranges():
        env = dict(os.environ, FB_START=str(start), FB_COUNT=str(count))
        r = subprocess.run(cmd, env=env, capture_output=True, text=True)
        if not r.stdout.strip():
            raise SystemExit(f"{name}: no rows\n{r.stderr}")
        got = dict(t.split("=", 1) for t in r.stdout.split())
        exp = expected(start, count)
        missing = set(exp) - set(got)
        extra = set(got) - set(exp)
        if missing or extra:
            moved.append(f"{name}: rows missing={len(missing)} "
                         f"extra={len(extra)}")
        for k in exp:
            rows += 1
            if args.lane == "js" and is_nan_pat(int(exp[k])):
                skipped += 1
                continue
            if got.get(k) != str(exp[k]):
                moved.append(f"{name} {k} got={got.get(k)} want={exp[k]}")
    print(f"lane={args.lane} rows={rows} skipped_js_only={skipped} "
          f"moved={len(moved)}")
    for m in moved[:40]:
        print("  " + m)
    if len(moved) > 40:
        print(f"  ... {len(moved) - 40} more")
    return 1 if moved else 0


if __name__ == "__main__":
    sys.exit(main())
