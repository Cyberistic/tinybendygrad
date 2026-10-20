#!/usr/bin/env python3
"""THROWAWAY: the half NaN class, which is in NEITHER gate's population.

`gates/subnormal-flush-gate.py` drives the half SUBNORMALS and the f32->half SUBNORMAL
band.  `gates/js-lane-census.py` drives `range(0x402)`.  So the half NaNs (0x7c01..0x7fff
and 0xfc01..0xffff) are driven by NOTHING, and the three lanes spell that class three
ways: `dtype.c:172` keeps only the quiet bit, `dtype.js:164` and `dtype.bend:736` keep
the whole payload.  This measures it, in both directions, against CPython's own codec.
"""
import importlib.util
import pathlib
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("sfg", ROOT / "gates" / "subnormal-flush-gate.py")
sfg = importlib.util.module_from_spec(spec)
sys.path.insert(0, str(ROOT / "gates"))
spec.loader.exec_module(sfg)

# THE CLASS, DISCOVERED BY THE FORMAT'S OWN RULE: a half NaN is exponent 0x1f with a
# non-zero mantissa, BOTH SIGNS.
nan_half = [h for h in range(0x10000) if (h & 0x7C00) == 0x7C00 and (h & 0x3FF) != 0]
# THE OTHER DIRECTION: the f32 patterns whose f16 value is a NaN, i.e. exponent field
# 0xff, BOTH SIGNS -- discovered, not listed.
nan_f32 = [p for p in range(0x7F800000, 0x7F800000 + 0x800000)
           if p & 0x7FFFFF] + [p | 0x80000000 for p in range(0x7F800000, 0x7F800000 + 0x800000)
                               if p & 0x7FFFFF]
nan_f32 = nan_f32[:64] + nan_f32[-64:]   # a fixed sample of each end; the class is huge

print(f"half NaN class: {len(nan_half)} patterns (both signs)")
print(f"f32 NaN class: {len(nan_f32)} patterns sampled from the two ends")

with tempfile.TemporaryDirectory() as tmp:
    work = pathlib.Path(tmp)
    jsrc = (ROOT / "tinybendygrad" / "runtime" / "dtype.js").read_text()
    csrc = (ROOT / "tinybendygrad" / "runtime" / "dtype.c").read_text()

    # DIRECTION 1: half -> f32.  The JS/C lanes answer an f32 PATTERN; the oracle
    # answers the f32 pattern of CPython's own half value.
    js = sfg.js_lane(work, jsrc, nan_half, [])
    c = sfg.c_lane(work, csrc, nan_half, [])
    orc = sfg.oracle_rows(nan_half, [])
    d_js = sum(1 for h in nan_half if js[f"h2f_{h:x}"] != orc[f"h2f_{h:x}"])
    d_c = sum(1 for h in nan_half if c[f"h2f_{h:x}"] != orc[f"h2f_{h:x}"])
    d_jc = sum(1 for h in nan_half if js[f"h2f_{h:x}"] != c[f"h2f_{h:x}"])
    print(f"  half->f32 : js-vs-oracle {d_js}/{len(nan_half)} | c-vs-oracle "
          f"{d_c}/{len(nan_half)} | js-vs-c {d_jc}/{len(nan_half)}")
    for h in (0x7c01, 0x7e00, 0x7fff, 0xfc01):
        k = f"h2f_{h:x}"
        print(f"    {k}: oracle={orc[k]} js={js[k]} c={c[k]}")

    # DIRECTION 2: f32 -> half.  The lanes answer a half PATTERN.
    js2 = sfg.js_lane(work, jsrc, [], nan_f32)
    c2 = sfg.c_lane(work, csrc, [], nan_f32)
    orc2 = sfg.oracle_rows([], nan_f32)
    e_js = sum(1 for p in nan_f32 if js2[f"f16b_{p:x}"] != orc2[f"f16b_{p:x}"])
    e_c = sum(1 for p in nan_f32 if c2[f"f16b_{p:x}"] != orc2[f"f16b_{p:x}"])
    e_jc = sum(1 for p in nan_f32 if js2[f"f16b_{p:x}"] != c2[f"f16b_{p:x}"])
    print(f"  f32->half : js-vs-oracle {e_js}/{len(nan_f32)} | c-vs-oracle "
          f"{e_c}/{len(nan_f32)} | js-vs-c {e_jc}/{len(nan_f32)}")
    for p in (0x7F800001, 0x7FFFFFFF, 0xFFC00000, 0xFFFFFFFF):
        k = f"f16b_{p:x}"
        if k in orc2:
            print(f"    {k}: oracle={orc2[k]} js={js2[k]} c={c2[k]}")
