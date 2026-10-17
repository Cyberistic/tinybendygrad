#!/usr/bin/env python3
"""js-lane-census.py -- `tinybendygrad/runtime/dtype.js`: is it REACHABLE, and does it AGREE.

    .venv/bin/python gates/js-lane-census.py [--quick] [--plant NAME]

THREE QUESTIONS, THREE SECTIONS, AND THE FIRST ONE IS THE ONE THAT MATTERS.

  REACH  `bend -o` splices a `.js` file into the emitted bundle ONLY where a `.bend`
         function body carries `import "./x.js"` -- MEASURED on
         `references/bend/tests/io/effect_runtime_shadow.bend`, whose `.js` sibling reaches
         1/1 through exactly this machinery, and that file is used here AS THE CONTROL, so
         a zero is a measurement rather than an absence of machinery. That is the `wgsl`
         `M8` class (`a green gate cannot distinguish "not triggered" from "no such thing"`)
         and a control is the only thing that separates it from a coverage gap.
         MEASURED at the time of writing: all TEN of `dtype.js`'s `Dt.*` registrations are
         absent from a bundle that calls all ten, and `dtype.bend:607,748,916,1060-1103` are
         PURE with no import, so the lane contributes ZERO bytes to the bundle.

  AGREE  Two lanes over the SAME rows -- CPython with every expectation CALLED from
         `tinygrad`, and node driving the lane's OWN registrations through a three-global
         shim -- plus ONE declared divergence, DERIVED from CPython by catching its
         `ZeroDivisionError` rather than written down. `checks/gate.py` was the fp8 DECODE
         gate for this file and it REFUSES today (exit 3: its driver `checks/drive.mjs` was
         swept by 371cc64c9), so this coverage exists nowhere else in the tree.

  REFUSE What CPython actually refuses where the four fp8 dtypes are concerned, CALLED, in
         three subjects and not one. `PTXRenderer.types` has no key for any of the four;
         `dtype.py`'s `_fp8_cfg`, `float_to_fp8` and `fp8_to_float` answer all four;
         `dtype.js` answers all four. `PTXRenderer.types` is a RENDERER's type-NAME table
         and this lane is dtype arithmetic, so a question about `types` has no subject here
         -- so the gate prints all three answers instead of choosing one.

WHAT THE ROWS CANNOT DISTINGUISH, PER CLASS, because a row that cannot say what it cannot
see is a row that will be read as more than it is.

  reach Dt.<n>              "never emitted" and "emitted but never called" are ONE zero to
                            this row. `reach bundle_names_dtype_js` is the row that
                            separates them, because it reads the bundle's own TEXT rather
                            than its call graph -- a truncated token is not a harmless one.
  reach control             a different file, so a green control says the machinery works
                            and says NOTHING about whether `dtype.js` is wired.
  fp8to <fmt>_<code>        the whole 256-code space per format, so the blind spot is a
                            value CPython answers with a different NaN PAYLOAD for one
                            code; the rows carry the f32 PATTERN, which keeps the sign, so
                            JFP-2's unsigned-vs-signed e4m3 NaN is observable rather than
                            hidden in a float formatting round-trip.
  fp8from <fmt>_<pattern>   NOT exhaustive over the 2^32 f32 patterns. The threshold
                            neighbourhood and the exact-fp8 band are, both centred on
                            CPython's own `_fp8_cfg`; the rest is a FIXED LCG walk, so the
                            blind spot is a defect whose support misses both.
  Dt.i64_*                  a fixed pair set, not a proof. `Dt.i64_trunc` is the identity in
                            `dtype.bend:1064`, so ITS row cannot distinguish a seam that
                            works from a seam that is not there.
  every row                 ONE f32 pattern per fp8 case, chosen by this file's LCG. A
                            defect that needs a pattern no walk reaches is invisible, and
                            the LCG's constants are the fixture's only claim to coverage.

PLANT AND DISARM, each anchored and each COUNTED, because an anchor that moved is a
measurement of nothing: `arith-plant` re-breaks JFP-2's e4m3 unsigned NaN and MUST move
rows; `arith-disarm` is the SAME line re-spelled and must move 0; `thr-plant` puts JFP-1's
three missing `-1`s back and MUST move rows; `thr-disarm` re-spells one row of the same
table and must move 0.
"""
from __future__ import annotations

import argparse
import json
import math
import pathlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from gatekit import FAIL, PASS, REFUSED, oracle_drift, verdict_of  # noqa: E402

ROOT = HERE.parent
JS_LANE = ROOT / "tinybendygrad" / "runtime" / "dtype.js"
BEND = ROOT / "bin" / "bend"
NODE = "node"
CTL_BEND = ROOT / "references/bend" / "tests" / "io" / "effect_runtime_shadow.bend"
CTL_JS = ROOT / "references/bend" / "tests" / "io" / "effect_runtime_shadow.js"

# THE CPYTHON SIDE IS THREE FILES AND ALL THREE ARE PINNED BY BYTES, so a re-vendor that
# changes what `fp8_to_float` answers moves a pin instead of silently moving 78k rows.
# ALL THREE SHAs BELOW MOVED WITH THE DELIBERATE RE-VENDOR TO upstream `002630241`
# (2026-10-16) -- not drift to restore. See `gates/onnx_census-gate.py:DRIFT_PIN`.
ORACLE_PIN = {
    "tinygrad/dtype.py": "7800592dcccbdd5a5beaee889342b5f62790d37445938fe601416c8b76057926",
    "tinygrad/helpers.py": "eda095ab2c35d045e40523cf8f025543c45b012ff217ddeaed6143610330f308",
    "tinygrad/renderer/ptx.py": "906bd04176ef07274e0fc9d9bf99bc86bb8d8bc9674a3099aee2eceff3d3d3e0",
}

# THE SEAM POPULATION IS DISCOVERED, NEVER LISTED -- and this regex was WRONG TWICE, both
# times SILENTLY, both times by truncating rather than by raising.  First attempt: `(\w+)`
# for the handler, which cannot match the ARROW LITERALS `dtype.js:203-211` pass, so it
# found **4 of 10** and printed 4 as a count.  Second attempt: `^... .+\);`, which cannot match
# the THREE registrations whose body wraps (`i64_cdiv`, `i64_cmod`, `i64_ceildiv`, at `:206,208,210`),
# so it found **7 of 10**.  That is the `repro-paths.py` class inside this file's own prose: A
# TRUNCATED TOKEN IS NOT A HARMLESSLY BLIND ONE, and the instrument that truncates is the one
# nobody audits -- and a regex is the cheapest possible way to write one.  So the declaration
# is matched PREFIX-ONLY (`io_eff(CID(Dt.<n>),` is on one line in all ten), the handler is not
# matched at all, and `population io_eff_lines` CROSS-CHECKS the register against every
# `io_eff(` line in the file so the next shape change is a REFUSAL, not a smaller number.
REG = re.compile(r"^io_eff\(CID\(Dt\.(\w+)\),", re.M)
REG_ANY = re.compile(r"^io_eff\(", re.M)
# THE KEY MAY NOT CONTAIN A SPACE.  The first draft keyed the fp8 rows
# `fp8to fp8e4m3_0` and this pattern, and 1312 py-only rows is what a row
# parser that cannot see a key looks like -- the lane emitted them correctly.
# THE KEY MAY NOT CONTAIN A SPACE.  The first draft keyed the fp8 rows `fp8to fp8e4m3_0`,
# and the symptom was 1312 py-only rows on a lane that had emitted every one of them
# correctly: an instrument that cannot SEE A KEY reports the gap it cannot read.  Two of the
# nine recorded instances in this tree's own prose are my own, in this file, in one sitting.
ROW = re.compile(r"^(\S+) = (\S*)$")
FP8 = ("fp8e4m3", "fp8e5m2", "fp8e4m3fnuz", "fp8e5m2fnuz")
I64_SEAMS = ("Dt.i64_trunc", "Dt.i64_floor_div", "Dt.i64_floor_mod", "Dt.i64_cdiv",
             "Dt.i64_cmod", "Dt.i64_ceildiv")
WALK, BAND, THRESH = 24_000, 64, 256

PLANTS = {
    # JFP-2 re-broken: e4m3's decode NaN takes the sign the code's top bit carries.
    "arith-plant": [("    if (mant === mantMax) return 0x7fc00000;",
                     "    if (mant === mantMax) return sgn ? 0xffc00000 : 0x7fc00000;")],
    # THE SAME LINE, RE-SPELLED.  Must move 0: this is what separates a TOKEN check from a
    # VALUE check, and it is the shape of every paired disarm in `checks/abi_gate.py`.
    "arith-disarm": [("    if (mant === mantMax) return 0x7fc00000;",
                      "    if (mant == mantMax) return 0x7FC00000;")],
    # JFP-1 re-broken: the f64 ULP that `dtype.py:239-241` writes LOW, as an f32 pattern.
    "thr-plant": [("0x37000000, 0x476fffff, 0x7b", "0x37000000, 0x47700000, 0x7b")],
    "thr-disarm": [("0x37000000, 0x476fffff, 0x7b", "0x37000000, 0x476fffff , 0x7b")],

    # THE TWO fp16 MECHANISM PLANTS, AND THEY ARE NOT PLANTS -- THEY ARE FIXES, APPLIED TO A
    # COPY.  `dtype.c:154` reads `u32 shift = (u32)(14 - exp)`; `dtype.js:129` reads
    # `>>> (27 - ue)`, thirteen wider.  The first cut of this claim came from READING the two
    # lines, which is not evidence, so the plant applies `14 - ue` and the transcript has to
    # show the `f16bits` class going to ZERO for the claim to stand.  A mechanism asserted
    # from a diff and never run is the `w64mile` shape.
    "f16-shift-plant": [(">>> (27 - ue)", ">>> (14 - ue)")],
    "f16-shift-disarm": [(">>> (27 - ue)", ">>> (27 - ue) ")],
    # `dtype.c:175-176` normalises the half subnormal by `31 - clz(m)`; `dtype.js:145` uses
    # `(103 << 23) | (m << 14)`, which is right only at m == 0 -- the branch m === 0 takes.
    "h2f-plant": [("((s | (103 << 23) | (m << 14)) >>> 0)",
                   "((s | ((103 + (31 - Math.clz32(m))) << 23) "
                   "| ((m << (23 - (31 - Math.clz32(m)))) & 0x7fffff)) >>> 0)")],
    # `dtype.c:205` opens with `if ((x & 0x7F800000u) == 0x7F800000u) return x;` and says why
    # in five lines -- a non-finite is a PASS-THROUGH in `dtype.py:230`, not saturation, so
    # a NaN's payload and sign survive.  `dtype.bend:609` has the same `Bool.pick` guard.
    # `dtype.js:151` has neither, and it is the only lane of the three that does not.
    "bf16-pass-plant": [("function dtype_bf16(u) {\n  return of32(",
                         "function dtype_bf16(u) {\n  if ((u & 0x7f800000) === 0x7f800000) "
                         "return of32(u);\n  return of32(")],
}


def refuse(*why: str) -> int:
    """exit 3 = REFUSED, and NOT a verdict (`checks/abi_gate.py`'s rule, in this file's words).

    Placed BEFORE the `tinygrad` import on purpose: an assertion downstream of what it
    asserts cannot turn a wrong-root `ModuleNotFoundError` into a refusal."""
    print("== REFUSED, NOT A VERDICT: " + "; ".join(why), file=sys.stderr)
    return REFUSED


# ------------------------------------------------------------ the fp8 fixtures.
def f32_pattern(x: float) -> int:
    """`struct.pack('<f', x)` and nothing else, because it KEEPS A NaN'S SIGN.  That is the
    only reason JFP-2's unsigned-vs-signed e4m3 NaN is observable at all; round the value
    through `repr` and the two answers become one string."""
    return struct.unpack("<I", struct.pack("<f", x))[0]


def of32(p: int) -> float:
    return struct.unpack("<f", struct.pack("<I", p & 0xFFFFFFFF))[0]


def lcg(n: int, start: int = 0x9E3779B9) -> list[int]:
    """A FIXED walk, so the row set is a constant of this file rather than of the day."""
    x, out = start, []
    for _ in range(n):
        x = (x * 1103515245 + 12345) & 0xFFFFFFFF
        out.append(x)
    return out


def encode_cases(td, dts) -> list[int]:
    """The fp8 ENCODE fixtures.  Every centre is CPython's `_fp8_cfg`, never `dtype.js`'s
    `FP8_CFG`: reading a sweep centre out of the code under test is the transcript trap that
    shipped ONE wrong threshold table in TWO languages (`checks/gate.py`'s own reason)."""
    cases: set[int] = set()
    for k in dts:
        ovf = td._fp8_cfg[k][4]
        for centre in (f32_pattern(ovf), f32_pattern(ovf) - 1):
            for d in range(-BAND, BAND + 1):
                for p in (centre + d, centre - d):
                    if 0 <= p <= 0xFFFFFFFF:
                        cases.add(p)
        for x in range(BAND):  # the exact-fp8 band: each code as an f32, and its neighbours
            f = td.fp8_to_float(x, k)
            if math.isnan(f):
                continue
            p = f32_pattern(f)
            for q in (p - 1, p, p + 1):
                if 0 <= q <= 0xFFFFFFFF:
                    cases.add(q)
    return sorted(cases)


def f16_bits_cpython(x: float) -> int:
    """CPython's f32 -> half PATTERN, which is `float_to_fp16` without the round trip back.
    `dtype.py:226` is `struct.pack('e', x)` with `OverflowError -> copysign(inf, x)`, so the
    half bits are what `struct.pack` produced and the overflow arm is one line of Python."""
    try:
        return struct.unpack("<H", struct.pack("<e", x))[0]
    except OverflowError:
        return 0x7C00 | (0x8000 if math.copysign(1.0, x) < 0 else 0)


def i64(v: int) -> int:
    """An `H.I64` record is TWO U32 WORDS, so the value it denotes is the SIGNED 64-bit
    two's-complement reading of the pair -- which `(hi << 32) | lo` does NOT give in Python:
    it yields 9223372041149743103 for `hi = 0x80000000`, where `dtype.js:172`'s
    `BigInt.asIntN(64, ...)` yields -2147483649.  The first draft built the oracle's operand
    with the bare `|` and **20 rows disagreed, every one of them on a negative operand** --
    the same shape as the `[0, -3]` fixture above, and the same lesson: an `H.I64` word is
    `U32`, and a negative i64 is spelled by its sign BIT, not by a negative word."""
    return v - (1 << 64) if v >= (1 << 63) else v


def i64_pairs() -> list[tuple[list[int], list[int]]]:
    """hi != lo on EVERY record, both signs, and the zero divisor against every division.

    `hi != lo` is what makes an ABI-3 pair-order defect visible at all: a record whose two
    words are equal cannot be read in the wrong order without being read correctly.

    BOTH WORDS ARE `U32` -- `helpers.bend:1640` is `I64{hi: U32, lo: U32}` -- so a negative
    word is NOT EXPRESSIBLE and the first draft carried `[0, -3]`, which the lane read as
    `0xFFFFFFFD` (4294967293) and CPython read as -3: **25 mismatches, every one of them
    this file's fixture.**  Negative operands go in as `hi = 0x80000000..` instead, which
    is how an i64's sign bit is actually spelled."""
    return [[[0, 7], [0, 3]], [[0, 7], [0, 0xFFFFFFFD]], [[1, 0], [0, 7]],
            [[0xFFFFFFFF, 0xFFFFFFFF], [0x80000000, 0xFFFFFFFF]],
            [[0x80000000, 0xFFFFFFFF], [0x40000000, 0x12345678]],
            [[0x7FFFFFFF, 0xFFFFFFFE], [0x40000000, 0x12345678]],
            [[0, 15], [0, 240]], [[0xDEADBEEF, 0xFEEDFACE], [0xDEADBEEF, 0xFEEDFACE]],
            [[0, 1], [0, 1]], [[0, 5], [0, 0]], [[0xFFFFFFFF, 0], [0, 0]],
            [[0x80000000, 0], [0x7FFFFFFF, 0]], [[0x80000000, 0x00000001], [0x7FFFFFFF, 0]]]


# ------------------------------------------------------------ the js lane.
SHIM = """// THE THREE GLOBALS, AND ONLY THE THREE: `dtype.js` names `io_eff`, `CID` and `Dt` and
// nothing else, so supplying exactly those IS the whole runner -- every other identifier it
// uses is a node builtin.  `CID` is THIS SHIM's spelling and the choice is UNOBSERVABLE
// from the tree, because no emitted bundle names one of these ten; that is why no row here
// asserts a CID spelling and why `reach Dt.<n>` reads the bundle's text instead.
const SEAM = Object.create(null), Dt = {};
for (const n of %N%) Dt[n] = "Dt." + n;
const CID = (x) => String(x);
const io_eff = (k, run) => { if (k in SEAM) throw new Error("double " + k); SEAM[k] = run; };
const P32 = (v) => new Uint32Array(new Float32Array([v]).buffer)[0] >>> 0;
const AS32 = (p) => new Float32Array(new Uint32Array([p >>> 0]).buffer)[0];
const I64 = (hi, lo) => ({$: "tinybendygrad/helpers.I64", hi: hi >>> 0, lo: lo >>> 0});
const hex64 = (r) => (BigInt(r.hi >>> 0) << 32n | BigInt(r.lo >>> 0)).toString(16).padStart(16, "0");
const out = [];
const R = (k, v) => out.push(k + " = " + v);
"""

DRIVER = """
const NAMES = %NAMES%, KINDS = %KINDS%;
for (let j = 0; j < NAMES.length; j++) {
  const k = KINDS[j];
  for (let x = 0; x < 256; x++) R(`fp8to_${NAMES[j]}_${x}`, P32(SEAM["Dt.fp8_to"](x, k)).toString(16));
  for (const p of %ENC%) R(`fp8from_${NAMES[j]}_${p}`, SEAM["Dt.fp8_from"](p, k));
}
for (const p of %WALK%) {
  const b = P32(SEAM["Dt.bf16"](p));
  // ABI-4: `Dt.bf16(bits: U32) -> F32` takes a PATTERN and `Dt.fp16(x: F32) -> F32` takes a
  // VALUE.  Passing `b` straight through answered 0x7f80000 on all 1196 rows -- 0x3FC00000
  // read AS A FLOAT is 1.57e+30, which f16 overflows to +inf.  `AS32` is the one conversion
  // and it is named, because "a value read as a pattern is not a rounding difference, it is
  // a different number, and it is silent" is `dtype.js:25-26` and this row set is its proof.
  R(`bf16_${p}`, b.toString(16));
  R(`fp16_${p}`, P32(SEAM["Dt.fp16"](AS32(b))).toString(16));
  R(`f16_${p}`, P32(SEAM["Dt.fp16"](0)).toString(16));
}
// WHITE-BOX ROWS, and WHY THEY EXIST.  `Dt.fp16` is `half_to_f32(f16_bits(x))` COMPOSED,
// so a defect in the OUTER half and a defect in the INNER one cancel on the seam's rows:
// with `f16_bits` broken the composite answers 0 for the whole half-subnormal window, and
// `half_to_f32`'s own wrong answer for m >= 1 is INVISIBLE through the seam.  These two rows
// drive the file's OWN functions separately, so each defect gets its own denominator instead
// of one masked by the other.  `checks/abi_gate.py` cannot see either: its three fp16 rows
// are 1.5, 1.1 and -2.25, all finite normals, which is why "the shipped JS lane is byte-equal
// to the C lane on all rows" is TRUE AND VACUOUS on this class -- the `ptx.bend` alias shape.
// `.toString(16)` ON BOTH WHITE-BOX ROWS, because JS `String(n)` is DECIMAL and the python
// side prints hex: the first run of these rows reported `cpython=400 js=1024` on a row where
// the lane was RIGHT, and the MINIMAL printer is the only reason it was visible at all.
for (const h of %H2F%) R(`half2f32_${h}`, half_to_f32(h).toString(16));
for (const p of %F16B%) R(`f16bits_${p}`, f16_bits(AS32(p)).toString(16));
for (const [nm, a, b] of %I64%) R(`${nm}_${a[0]}_${a[1]}_${b[0]}_${b[1]}`, hex64(SEAM[nm](I64(a[0], a[1]), I64(b[0], b[1]))));
console.log(out.join("\\n"));
"""


def build_js(work: pathlib.Path, src: str, names: list[str], spec: dict) -> tuple[str, int, str]:
    """The lane's OWN BYTES, verbatim, behind the shim and a driver; node is run ONCE.

    `--plant` re-writes THIS copy, so the tree is never a base and a disagreement is the
    lane's arithmetic rather than a transcription of it."""
    js = work / "lane.js"
    js.write_text(SHIM.replace("%N%", json.dumps(names)) + src + "\n" + DRIVER
                  # `KINDS[j]` AND NOT `j`: the first draft drove `SEAM["Dt.fp8_to"](x, j)`
                  # while LABELLING the row `NAMES[j]`, and under `--quick` (kinds 0 and 3)
                  # that answered every `fp8e5m2fnuz` row with the e5m2 arithmetic --
                  # **1848 mismatches, every one of them this file's bug and none of them the
                  # lane's.**  An ordinal is not a kind; the two are the same only when the
                  # selection is `0..3`, which is why the bug slept until `--quick`.
                  .replace("%KINDS%", json.dumps(spec["kinds"]))
                  .replace("%NAMES%", json.dumps(spec["names"]))
                  .replace("%ENC%", json.dumps(spec["encode"]))
                  .replace("%WALK%", json.dumps(spec["walk"]))
                  .replace("%H2F%", json.dumps(spec["h2f"]))
                  .replace("%F16B%", json.dumps(spec["f16b"]))
                  .replace("%I64%", json.dumps(spec["i64"])))
    p = subprocess.run([NODE, str(js)], capture_output=True, text=True, timeout=1800)
    return p.stdout, p.returncode, p.stderr


# ------------------------------------------------------------ reach.
PROBE = """import ./tinybendygrad/dtype.bend as D
import ./tinybendygrad/helpers.bend as H

def main() -> IO(Unit):
  do IO<Unit>:
    b1 : F32 = D.Dt.bf16(F32.bits(1.5))
    IO.print("r bf16 = " ++ F32.show(b1))
    e1 : F32 = D.Dt.fp16(1.5)
    IO.print("r fp16 = " ++ F32.show(e1))
    c1 : U32 = D.Dt.fp8_from(F32.bits(1.5), 0)
    IO.print("r fp8from0 = " ++ U32.show(c1))
    f1 : F32 = D.Dt.fp8_to(60, 0)
    IO.print("r fp8to0 = " ++ F32.show(f1))
    t1 : H.I64 = D.Dt.i64_trunc(H.i64_of_hi_lo(15, 240))
    IO.print("r trunc = " ++ H.i64_text(t1))
    d1 : H.I64 = D.Dt.i64_floor_div(H.i64_of_hi_lo(7, 0), H.i64_of_hi_lo(3, 0))
    IO.print("r fdiv = " ++ H.i64_text(d1))
    d2 : H.I64 = D.Dt.i64_floor_mod(H.i64_of_hi_lo(7, 0), H.i64_of_hi_lo(3, 0))
    IO.print("r fmod = " ++ H.i64_text(d2))
    d3 : H.I64 = D.Dt.i64_cdiv(H.i64_of_hi_lo(7, 0), H.i64_of_hi_lo(3, 0))
    IO.print("r cdiv = " ++ H.i64_text(d3))
    d4 : H.I64 = D.Dt.i64_cmod(H.i64_of_hi_lo(7, 0), H.i64_of_hi_lo(3, 0))
    IO.print("r cmod = " ++ H.i64_text(d4))
    d5 : H.I64 = D.Dt.i64_ceildiv(H.i64_of_hi_lo(7, 0), H.i64_of_hi_lo(3, 0))
    IO.print("r ceildiv = " ++ H.i64_text(d5))
"""


def _seed(work: pathlib.Path) -> None:
    """The `.bend` files the probe imports, COPIED, so `bend -o` can resolve them from a
    throwaway directory and this gate never depends on the caller's working directory."""
    dst = work / "tinybendygrad"
    dst.mkdir(exist_ok=True)
    for rel in ("dtype.bend", "helpers.bend", "base.bend", "LAWS"):
        s = ROOT / "tinybendygrad" / rel
        (shutil.copytree if s.is_dir() else shutil.copy)(s, dst / rel)


def reach(work: pathlib.Path, names: list[str]) -> dict[str, str]:
    """How many of the lane's registrations the EMITTED BUNDLE reaches, plus one control."""
    got: dict[str, str] = {}
    ctl = subprocess.run([str(BEND), str(CTL_BEND), "-o", str(work / "ctl.js")],
                         capture_output=True, text=True, timeout=3600)
    if ctl.returncode != 0 or not (work / "ctl.js").is_file():
        got["reach control"] = "COMPILE-FAILED"
        return got
    run = subprocess.run([NODE, str(work / "ctl.js")], capture_output=True, text=True, timeout=600)
    # `cmp_new(a) = a+1` is the control's ENTIRE implementation, so the bundle carrying
    # `a + 1` and the program printing 8 together prove the JS body was spliced AND reached.
    got["reach control"] = ("1/1" if "a + 1" in (work / "ctl.js").read_text()
                            and "8" in run.stdout else "0/1")
    _seed(work)
    (work / "probe.bend").write_text(PROBE)
    c = subprocess.run([str(BEND), str(work / "probe.bend"), "-o", str(work / "probe.js")],
                       capture_output=True, text=True, timeout=3600)
    if c.returncode != 0 or not (work / "probe.js").is_file():
        return {**got, **{f"reach Dt.{n}": "COMPILE-FAILED" for n in names},
                "reach bundle_names_dtype_js": "COMPILE-FAILED"}
    text = (work / "probe.js").read_text()
    got["reach bundle_bytes"] = str(len(text))
    got["reach bundle_names_dtype_js"] = "1/1" if "dtype.js" in text else "0/1"
    got["reach io_eff_registrations"] = str(len(re.findall(r"^io_eff\(", text, re.M)))
    for n in names:
        got[f"reach Dt.{n}"] = "1/1" if f'"Dt.{n}"' in text else "0/1"
    return got


# ------------------------------------------------------------ the two lanes.
def py_rows(td, hlp, dts, spec: dict) -> tuple[dict[str, str], dict[str, str]]:
    """Every expectation is CALLED.  Nothing here restates `dtype.py` or `helpers.py`.

    Returns (rows, diverges).  A divergence is DERIVED, not written down: a row where
    CPython RAISED is a row where the lanes are EXPECTED to differ, and the pin records
    what the lane answered instead -- so a `ceildiv` whose guard appears upstream stops
    being a divergence the moment `ceildiv` stops raising."""
    rows: dict[str, str] = {}
    for k in range(len(dts)):
        kd, nm = dts[k], spec["names"][k]
        for x in range(256):
            rows[f"fp8to_{nm}_{x}"] = f"{f32_pattern(td.fp8_to_float(x, kd)):x}"
        for p in spec["encode"]:
            rows[f"fp8from_{nm}_{p}"] = str(td.float_to_fp8(of32(p), kd))
    for p in spec["walk"]:
        b = f32_pattern(td.float_to_bf16(of32(p)))
        rows[f"bf16_{p}"] = f"{b:x}"
        rows[f"fp16_{p}"] = f"{f32_pattern(td.float_to_fp16(of32(b))):x}"
        rows[f"f16_{p}"] = f"{f32_pattern(td.float_to_fp16(0.0)):x}"
    # THE TWO WHITE-BOX CLASSES.  `f16bits` is CPython's half PATTERN (`struct.pack('e', x)`,
    # `dtype.py:226`) and `half2f32` is the f32 pattern of `struct.unpack('e', ...)`, so both
    # sides are `dtype.py`'s own codec and neither is reimplemented here.
    for p in spec["f16b"]:
        rows[f"f16bits_{p}"] = f"{f16_bits_cpython(of32(p)):x}"
    for h in spec["h2f"]:
        rows[f"half2f32_{h}"] = f"{f32_pattern(struct.unpack('<e', struct.pack('<H', h))[0]):x}"
    # `hlp.ceildiv` IS CALLED, NOT COMPOSED.  `-(floordiv(-a, b))` was the first draft and it
    # cannot raise: `floordiv` is guarded (`helpers.py:77`), so every `b == 0` row agreed and
    # the ONE genuine divergence -- `ceildiv(7, 0)` -> `ZeroDivisionError` against the lane's
    # `0` -- was 0/5 of the fixture.  A DERIVED divergence that never derives is the quietest
    # possible way to lose one, and it is the same defect as a hand-written oracle.
    fn = {"Dt.i64_floor_div": hlp.floordiv, "Dt.i64_floor_mod": hlp.floormod,
          "Dt.i64_cdiv": hlp.cdiv, "Dt.i64_cmod": hlp.cmod, "Dt.i64_ceildiv": hlp.ceildiv}
    diverges: dict[str, str] = {}
    for nm, a, b in spec["i64"]:
        key = f"{nm}_{a[0]}_{a[1]}_{b[0]}_{b[1]}"
        if nm == "Dt.i64_trunc":
            rows[key] = f"{((a[0] << 32) | a[1]) & 0xFFFFFFFFFFFFFFFF:016x}"
            continue
        x, y = i64((a[0] << 32) | a[1]), i64((b[0] << 32) | b[1])
        try:
            rows[key] = f"{fn[nm](x, y) & 0xFFFFFFFFFFFFFFFF:016x}"
        except ZeroDivisionError as exc:
            diverges[key] = type(exc).__name__
    return rows, diverges


# ------------------------------------------------------------ the gate.
def run(*, plant: str | None, quick: bool) -> int:
    # THE ROOT SUBSTRATE, ASSERTED AND NOT DECLARED.  `gates/gates-pop.py` reads `REFUSE`
    # (a refusal call) TOGETHER WITH a `pyproject.toml` marker test to decide that a gate
    # "asserts its root", and it reported `asserts=NO` for this file while the refusal below
    # was real -- the instrument could not see the claim, and a claim it cannot see is one a
    # reader is asked to take on trust.  So the substrate is named: the ROOT is the repo root
    # iff it holds `pyproject.toml` and the tree, and one of them moving without the other is
    # a refusal rather than a wrong-root import.
    if not (ROOT / "pyproject.toml").is_file() or not (ROOT / "tinybendygrad").is_dir():
        return refuse(f"ROOT is not the repo root: {ROOT} (missing pyproject.toml or "
                      f"tinybendygrad/ -- is a parents[N] stale after a move?)")
    for p in (JS_LANE, BEND, CTL_BEND, CTL_JS):
        if not p.exists():
            return refuse(f"input absent: {p}")
    if plant is not None and plant not in PLANTS:
        return refuse(f"unknown plant {plant!r}; one of {sorted(PLANTS)}")
    if bad := oracle_drift(ORACLE_PIN):
        return refuse("the CPython side drifted: " + "; ".join(bad))
    if not shutil.which(NODE):
        return refuse(f"{NODE} is not on PATH")

    sys.path.insert(0, str(ROOT))
    from tinygrad import dtype as td
    from tinygrad import helpers as hlp
    from tinygrad.renderer.ptx import PTXRenderer

    src = JS_LANE.read_text()
    names = REG.findall(src)
    any_line = len(REG_ANY.findall(src))
    if not names:
        return refuse("no io_eff(CID(Dt.*)) registration -- the register IS the population")
    if any_line != len(names):
        return refuse(f"the register found {len(names)} registrations and the file holds "
                      f"{any_line} `io_eff(` lines -- this regex is TRUNCATING, which is how "
                      f"4 and then 7 of 10 went missing here and each printed as a count")
    if plant is not None:
        for old, new in PLANTS[plant]:
            if src.count(old) != 1:
                return refuse(f"plant {plant}: anchor {old.strip()[:64]!r} found "
                              f"{src.count(old)} site(s), expected 1 -- dtype.js moved")
            src = src.replace(old, new)

    kinds = [0, 3] if quick else [0, 1, 2, 3]
    names_f8 = [FP8[k] for k in kinds]
    dts = [getattr(td.dtypes, n) for n in names_f8]
    enc = encode_cases(td, dts)
    walk = lcg(1500 if quick else WALK)
    # `f16_bits`'s subnormal arm is `ue <= 0` with `ue = e - 127 + 15`, i.e. `e <= 112`, and
    # its flush arm is `ue < -10`, i.e. `e <= 101` -- so the arm is reached by f32 exponent
    # fields **102..112**, eleven fields and 92,274,688 patterns.  THE FIRST DRAFT OF THIS
    # FIXTURE USED `range(113, 127)`: every one of those rows took the NORMAL arm, `f16bits`
    # reported **0 mismatches**, and the instrument was blind to its own subject while
    # printing a count -- the `wgsl` `M8` shape, third instance, this time mine.  The band is
    # printed as a CONTROL row so the next misreading of it is visible in the transcript
    # instead of hiding behind a green row set.
    band = tuple(range(127 - 15 - 10, 128 - 15))       # 102..112, spelled from the lane's own
    f16b = sorted({e << 23 | m for e in band
                   for m in (0, 1, 2, 0x200000, 0x3FFFFF, 0x400000, 0x7FFFFF)}
                  | {p for p in walk if band[0] <= (p >> 23) <= band[-1]})
    spec = {"kinds": kinds, "names": names_f8, "encode": enc[:400] if quick else enc,
            "walk": walk, "f16b": f16b, "h2f": list(range(0x402)),
            "i64": [[nm, a, b] for nm in I64_SEAMS for a, b in i64_pairs()
                    if nm != "Dt.i64_trunc" or b == [0, 1]]}
    py, diverges = py_rows(td, hlp, dts, spec)

    with tempfile.TemporaryDirectory() as tmp:
        work = pathlib.Path(tmp)
        raw, js_rc, js_err = build_js(work, src, names, spec)
        rc = reach(work, names) if not quick else {}

    if js_rc != 0:
        print(f"node exited {js_rc} with {len(raw.splitlines())} rows:\n{js_err[:600]}",
              file=sys.stderr)
        return FAIL
    js = {}
    for line in raw.splitlines():
        m = ROW.match(line.strip())
        if m:
            js[m[1]] = m[2]

    # A MISSING ROW IS NOT AN ABSENCE OF DISAGREEMENT.  `artefacts_ok()` reported zero on a
    # directory holding nothing, and "0 disagreements" over "0 comparisons" is
    # indistinguishable from agreement.
    missing = sorted(set(py) - set(js) - set(diverges))
    extra = sorted(set(js) - set(py) - set(diverges))
    if missing or extra:
        print(f"ROW SET DISAGREES: {len(missing)} py-only (e.g. {missing[:3]}), "
              f"{len(extra)} js-only (e.g. {extra[:3]})", file=sys.stderr)
        return FAIL
    stale = [k for k in diverges if k not in js]
    if stale:
        print(f"a declared divergence {stale[:3]} is absent from the js lane", file=sys.stderr)
        return FAIL

    bad = [(k, py[k], js[k]) for k in py if py[k] != js.get(k)]
    compared = len(py) - len(diverges)
    print(f"js-lane-census: {len(py)} rows, 2 lanes ({'QUICK' if quick else 'full'}), "
          f"{len(names)} registered seams, {any_line} io_eff lines, "
          f"{len(diverges)} derived divergences, {compared} compared")
    print(f"  FIXTURE f16_bits subnormal band: f32 exponent fields {band[0]}..{band[-1]} "
          f"(ue {band[0] - 112}..{band[-1] - 112}), {len(spec['f16b'])} patterns, of which "
          f"{sum(1 for p in spec['f16b'] if (p >> 23) in band)} are IN the band")
    for k, v in sorted(rc.items()):
        print(f"  REACH {k:<32} {v}")
    for k, w, g in bad[:10]:
        print(f"  MISMATCH {k}: cpython={w} js={g}")
    # A TALLY AND NOT A SAMPLE: "88 mismatches" printed as ten lines reads as ten.  Each
    # class is also split by whether the f32 that ENTERED the seam was FINITE, because both
    # divergences here are non-finite-only and a tally that does not say so is a tally that
    # invites the reader to assume the finite path is broken too.
    tally: dict[str, int] = {}
    for k, _, _ in bad:
        if m := re.match(r"^(bf16|fp16|f16bits)_(\d+)$", k):  # `bf16_<p>` carries its own input
            src_pat = int(m[2]) if m[1] == "bf16" else int(py[f"bf16_{m[2]}"], 16) \
                if m[1] == "fp16" and f"bf16_{m[2]}" in py else int(m[2])
            tally[f"{m[1]} input f32 {'FINITE' if math.isfinite(of32(src_pat)) else 'NON-FINITE'}"] \
                = tally.get(f"{m[1]} input f32 "
                            f"{'FINITE' if math.isfinite(of32(src_pat)) else 'NON-FINITE'}", 0) + 1
        else:
            tally[k.rsplit("_", 1)[0]] = tally.get(k.rsplit("_", 1)[0], 0) + 1
    for cls, n in sorted(tally.items()):
        print(f"  MISMATCH class {cls}: {n} rows")
    # ONE MINIMAL REPRODUCTION PER CLASS, DERIVED AT RUN TIME and not written down: the
    # disagreeing row of that class with the smallest-magnitude input.  A class name is a
    # label; a class's smallest failure is evidence, and a fixture that cannot fail is worse
    # than no fixture -- so the repro is FOUND, not chosen.
    seen: set[str] = set()
    for cls in sorted(tally):
        pre = cls.split(" ")[0]      # the LABEL carries the finiteness split; the PREFIX keys it
        if pre in seen:
            continue                 # one repro per PREFIX, not per label
        seen.add(pre)
        rep = min((k for k, _, _ in bad if k.startswith(pre + "_")),
                  key=lambda k: int(k.rsplit("_", 1)[1]), default=None)
        if rep:
            w, g = py[rep], js[rep]
            tail = rep.rsplit("_", 1)[1]
            print(f"  MINIMAL {rep}: cpython={w} js={g}"
                  + (f"  (f32 input {of32(int(tail)):.6g})"
                     if pre in ("bf16", "f16bits") else ""))
    print(f"  DISAGREE: {len(bad)}/{compared}; DIVERGING (cpython refused): "
          + ", ".join(f"{k}={v}" for k, v in sorted(diverges.items())))
    print("\nWHERE CPython REFUSES THE FOUR fp8 dtypes -- three subjects, all CALLED:")
    for n, kd in zip(FP8, [getattr(td.dtypes, m) for m in FP8]):
        try:
            ptx = f"{PTXRenderer.types[kd]}"
        except KeyError:
            ptx = "KeyError"
        print(f"  {n:<12} PTXRenderer.types={ptx:<9} "
              f"dtype.py float_to_fp8(1.5)={td.float_to_fp8(1.5, kd):<4} "
              f"fp8_to_float(0x3C)={td.fp8_to_float(0x3C, kd):<8} "
              f"dtype.js fp8_to(0x3C)={js.get(f'fp8to_{n}_60', 'NOT-IN-THIS-RUN')}")
    if bad:
        print(f"js-lane-census: {verdict_of(FAIL)}")
        return FAIL
    print(f"js-lane-census: {verdict_of(PASS)} -- both lanes agree on {compared} rows and on "
          f"the {len(diverges)} declared divergences")
    return PASS


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="census tinybendygrad/runtime/dtype.js")
    ap.add_argument("--plant", choices=sorted(PLANTS))
    ap.add_argument("--quick", action="store_true", help="skip the REACH section")
    ns = ap.parse_args()
    sys.exit(run(plant=ns.plant, quick=ns.quick))