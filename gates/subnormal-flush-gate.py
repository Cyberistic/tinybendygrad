#!/usr/bin/env python3
"""subnormal-flush-gate.py -- the f16 SUBNORMAL class, and WHICH of the port's rules is odd.

    .venv/bin/python gates/subnormal-flush-gate.py [--plant NAME]

WHY THIS FILE EXISTS, and it is not "the census is red".  `gates/js-lane-census.py` asks
ONE question -- does `tinybendygrad/runtime/dtype.js` agree with the CPython oracle -- and
it answers NO on 1194 of 7008 rows.  That is a measurement, and it does NOT say WHICH side
is wrong: the census has two lanes and the oracle is one of them.  So this file asks the
SECOND question, the one a red census cannot answer by itself:

    the port implements the f16 rule in THREE places -- `dtype.bend` (the Bend path),
    `runtime/dtype.c` (the compiled seam) and `runtime/dtype.js` (the interpreted seam).
    Two of them can be RUN here and the oracle is the third, so "which side is wrong" is
    a MEASUREMENT and not an inference.

THE THREE LANES, and how each one is obtained:

  ORACLE  CPython's `struct.pack('e')`, CALLED.  `tinygrad/dtype.py` is PINNED by bytes
          (`ORACLE_PIN`, the same pin `gates/js-lane-census.py` uses), because a re-vendor
          that changes what the oracle answers must MOVE THE PIN rather than move rows.

  C       `tinybendygrad/runtime/dtype.c`'s own `fp16_encode` and `fp16_f32`, EXTRACTED
          MECHANICALLY from the live file -- the text between `static u32 fp16_encode(u32
          x) {` and the closing brace in column zero -- and COMPILED with `cc`.  Not
          transcribed: a transcription is a second copy of the rule and the second copy is
          exactly the thing that rots.  The extracted text is hashed into a ROW, so a
          reader can re-extract it and compare the hash.

  JS      `tinybendygrad/runtime/dtype.js`'s own `half_to_f32` and `f16_bits`, driven by
          `node` behind a three-global shim (`Dt`, `CID`, `io_eff` -- the only identifiers
          the file names), with the fixture spliced into the driver.  The file's own bytes.

THE POPULATION IS DISCOVERED, NEVER LISTED.  Two directions, two rules, and both rules are
selected by a RULE and not by a hand-written set of patterns:

  h2f   the half SUBNORMALS: every half pattern whose exponent field is 0 and whose
        mantissa is not 0, BOTH SIGNS.  Found by walking the half pattern space and
        applying the format's own rule -- a half's exponent is bits 10..14, so
        `h & 0x7c00 == 0` is `exp == 0` and `h & 0x3ff` is the mantissa.
  f16b  the f32 patterns whose f16 exponent `ue = e - 127 + 15` lies in `[-10, 0]`: the
        band where the f16 value is SUBNORMAL and still representable, BOTH SIGNS.  The
        band is spelled from the lane's own bias rather than written down, and `ue < -10`
        is excluded because BOTH lanes flush there and so it cannot be a disagreement.

WHAT THE ROWS CANNOT DISTINGUISH, per class, because a row that cannot say what it cannot
see is a row that will be read as more than it is.

  h2f   the half subnormals are DISCRETE, so this class is EXHAUSTIVE over the half
        format's subnormal space, both signs.  It says nothing about the NORMAL half
        values, which this file does not drive.
  f16b  the band is exhaustive over the f16 subnormal band of the f32 EXPONENT space, but
        the f32 MANTISSAS inside it are a fixed set (seven per exponent field), so a defect
        that needs a mantissa no set reaches is invisible.
  both  the fixture is a SET OF PATTERNS, so it says nothing about a defect that only
        appears for a PATTERN CLASS the fixture does not contain.

THE ARMS, each anchored, each COUNTED, and each applied to a COPY of the lane it
perturbs -- the live tree is never a base.  A plant that cannot fail is a comment, and a
control that moves rows is an instrument reading a TOKEN instead of a VALUE.  Each arm
states what it MUST do, and the gate checks the STATEMENT against the run:

  js-plant        the JS lane's half-subnormal arm is given the C lane's normalization.
                  MUST take the js/h2f count to ZERO and leave js/f16b UNCHANGED.
  js-disarm       the SAME line, re-spelled.  MUST move every count by ZERO.
  js-plant-all    the C lane's normalization AND the C lane's f16 subnormal shift AND
                  round-half-to-even, all three moved into the JS lane.  MUST take BOTH
                  js counts to ZERO: this is the falsifier for "these are all of it".
  js-all-disarm   the SAME three lines, re-spelled.  MUST move every count by ZERO.
  c-plant         the C lane's `k = 31 - clz(m)` is made one wider.  MUST take the c/h2f
                  count from ZERO to a NON-ZERO number: a lane that cannot be broken
                  cannot be trusted to agree, and a green C lane that is green because
                  the instrument cannot see it is the `wgsl` `M8` shape.
  c-disarm        the SAME line, re-spelled.  MUST move every count by ZERO.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
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
C_LANE = ROOT / "tinybendygrad" / "runtime" / "dtype.c"
NODE, CC = "node", "cc"

# THE SAME BYTES `gates/js-lane-census.py` PINS, so the two gates cannot drift apart on
# what the oracle IS: a re-vendor moves this pin or it moves the census's, and one of the
# two moving alone is a disagreement between two gates about the same oracle.
ORACLE_PIN = {
    "tinygrad/dtype.py": "7800592dcccbdd5a5beaee889342b5f62790d37445938fe601416c8b76057926",
}

# THE C LANE'S NORMALIZATION, as the C lane writes it (`dtype.c:175-176`):
# `k = 31 - __builtin_clz(m)`, then `(k + 103) << 23 | (m << (23 - k)) & 0x7fffff`.
# `31 - clz(m)` is `floor(log2 m)`, so `k` is the position of the mantissa's leading bit
# and the fraction is shifted LEFT by `23 - k` into place.  The JS lane's arm is a FIXED
# `m << 14`, which assumes the mantissa is already normalised -- true for `m >= 512` and
# false for every other subnormal.
C_NORMALISE = ("((s | ((103 + (31 - Math.clz32(m))) << 23) "
                "| ((m << (23 - (31 - Math.clz32(m)))) & 0x7fffff)) >>> 0)")
JS_ARM = "((s | (103 << 23) | (m << 14)) >>> 0)"
JS_SHIFT = ">>> (27 - ue)"
C_K = "u32 k = 31u - (u32)__builtin_clz(m);"

ARMS: dict[str, tuple[list[tuple[str, str]], dict]] = {
    "js-plant": ([(JS_ARM, C_NORMALISE)], {"js/h2f": 0, "js/f16b": "unchanged"}),
    "js-disarm": ([(JS_ARM, JS_ARM.replace("(m <<", "(m  <<"))], {"*": "unchanged"}),
    "js-plant-all": ([(JS_ARM, C_NORMALISE),
                      (JS_SHIFT, ">>> (14 - ue)"),
                      ("    return s | ((m | 0x800000) >>> (14 - ue));",
                       "    const big = m | 0x800000, sh = 14 - ue;\n"
                       "    let hm = big >>> sh;\n"
                       "    const rem = big & ((1 << sh) - 1), halfway = 1 << (sh - 1);\n"
                       "    if (rem > halfway || (rem === halfway && (hm & 1))) hm += 1;\n"
                       "    return s | hm;")],
                     {"js/h2f": 0, "js/f16b": 0}),
    "js-all-disarm": ([(JS_ARM, JS_ARM.replace("(m <<", "(m  <<")),
                        ("    return s | ((m | 0x800000) >>> (27 - ue));",
                         "    return s | ((m | 0x800000) >>> (27 - ue) );"),
                        (JS_SHIFT, ">>> (27 - ue )")],
                       {"*": "unchanged"}),
    "c-plant": ([(C_K, C_K.replace("31u -", "32u -"))], {"c/h2f": "nonzero"}),
    "c-disarm": ([(C_K, C_K.replace("__builtin_clz(m)", "__builtin_clz( m )"))],
                 {"*": "unchanged"}),
}


def refuse(*why: str) -> int:
    print("== REFUSED, NOT A VERDICT: " + "; ".join(why), file=sys.stderr)
    return REFUSED


# ------------------------------------------------------------ the fixtures.
def half_subnormals() -> list[int]:
    """Every half pattern whose EXPONENT FIELD is 0 and whose mantissa is not 0.

    DISCOVERED by walking the half pattern space and applying the format's own rule, so
    a hand-written list of 1023 patterns would not be a list that notices the format
    changing under it.  BOTH SIGNS: the negative subnormals are as much of the class as
    the positive ones, and the census drives only `0..0x401`.
    """
    return [h for h in range(0x10000) if (h & 0x7C00) == 0 and (h & 0x3FF) != 0]


def f32_subnormal_band() -> list[int]:
    """The f32 patterns whose f16 value is a SUBNORMAL and is still representable.

    `ue = e - 127 + 15` is the lane's own exponent (both lanes compute it that way), so
    the band is `ue` in `[-10, 0]`: `ue < -10` is flushed to zero by BOTH lanes and is
    therefore not a disagreement, and `ue > 0` is a half NORMAL and is not this class.
    Inverting the lane's own formula, `e = ue + 127 - 15`, so `e` is 102..112.
    The seven mantissas are the interesting ones: zero, one, two, the two round-to-even
    ties, the carry, and the largest.
    """
    lo, hi = -10 + 127 - 15, 0 + 127 - 15
    mants = (0, 1, 2, 0x200000, 0x3FFFFF, 0x400000, 0x7FFFFF)
    return sorted([e << 23 | m for e in range(lo, hi + 1) for m in mants]
                  + [(e << 23 | m) | 0x80000000 for e in range(lo, hi + 1) for m in mants])


def of32(p: int) -> float:
    return struct.unpack("<f", struct.pack("<I", p & 0xFFFFFFFF))[0]


def f32_pattern(x: float) -> int:
    return struct.unpack("<I", struct.pack("<f", x))[0]


# ------------------------------------------------------------ the lanes.
SHIM = """// THE THREE GLOBALS AND ONLY THE THREE: `dtype.js` names `io_eff`, `CID` and `Dt`
// and nothing else, so supplying exactly those IS the whole runner.  `Dt` is a Proxy so
// the shim does not have to KNOW the registered names -- a shim that lists them is a
// second copy of the register, and the register is discoverable.
const SEAM = Object.create(null);
const Dt = new Proxy({}, {get: (_, k) => "Dt." + String(k)});
const CID = (x) => String(x);
const io_eff = (k, run) => { SEAM[k] = run; };
"""

DRIVER = """
// FIXED-WIDTH HEX ON BOTH ROWS.  JS `String(n)` is DECIMAL and `.toString(16)` is
// MINIMAL, so the lane printed `0` where the oracle prints `0000`: the values agreed and
// the strings did not, and 77 rows were reported as disagreements that were not one.  It
// is the same class `gates/js-lane-census.py` records for its own white-box rows.
for (const h of %H2F%)
  out.push(`h2f_${h.toString(16)} = ${half_to_f32(h).toString(16).padStart(8, "0")}`);
for (const p of %F16B%)
  out.push(`f16b_${p.toString(16)} = ${f16_bits(of32(p)).toString(16).padStart(4, "0")}`);
console.log(out.join("\\n"));
"""


def _rows(text: str) -> dict[str, str]:
    rows = {}
    for line in text.splitlines():
        k, sep, v = line.partition(" = ")
        if k and sep and v:
            rows[k] = v.strip()
    return rows


def js_lane(work: pathlib.Path, src: str, h2f: list[int], f16b: list[int]) -> dict[str, str]:
    """The lane's OWN BYTES, verbatim, behind the shim and a driver; node is run ONCE."""
    js = work / "lane.js"
    js.write_text(SHIM + src + "\nconst out = [];\n" + DRIVER
                  .replace("%H2F%", json.dumps(h2f))
                  .replace("%F16B%", json.dumps(f16b)))
    p = subprocess.run([NODE, str(js)], capture_output=True, text=True, timeout=600)
    if p.returncode != 0:
        raise RuntimeError(f"node exited {p.returncode}: {p.stderr[:400]}")
    return _rows(p.stdout)


def extract_c(text: str, name: str) -> str:
    """The C lane's own function body, EXTRACTED from the live file.

    The extent is `static u32 <name>(...) {` up to the closing brace in column zero, which
    is how this file writes every function.  A hand-transcribed copy of the rule would be
    a second copy of the rule, and the second copy is the thing that rots.
    """
    start = text.index(f"static u32 {name}(")
    return text[start:text.index("\n}\n", start) + 3]


def c_lane(work: pathlib.Path, csrc: str, h2f: list[int], f16b: list[int]) -> dict[str, str]:
    """The C lane's own bytes, compiled, and run over the same fixture."""
    body = extract_c(csrc, "fp16_encode") + "\n" + extract_c(csrc, "fp16_f32")
    drv = work / "lane.c"
    drv.write_text(
        "#include <stdio.h>\n#include <stdint.h>\ntypedef uint32_t u32;\n"
        + body
        + "\nint main(void) {\n"
        + "".join(f'  printf("h2f_{h:x} = %08x\\n", fp16_f32({h}u));\n' for h in h2f)
        + "".join(f'  printf("f16b_{p:x} = %04x\\n", fp16_encode({p}u));\n' for p in f16b)
        + "  return 0;\n}\n")
    exe = work / "lane"
    k = subprocess.run([CC, "-O1", "-w", "-o", str(exe), str(drv)],
                       capture_output=True, text=True, timeout=600)
    if k.returncode != 0:
        raise RuntimeError(f"cc exited {k.returncode}: {k.stderr[-400:]}")
    p = subprocess.run([str(exe)], capture_output=True, text=True, timeout=600)
    if p.returncode != 0:
        raise RuntimeError(f"the C lane exited {p.returncode}: {p.stderr[:400]}")
    return _rows(p.stdout)


def oracle_rows(h2f: list[int], f16b: list[int]) -> dict[str, str]:
    """CPython's OWN codec, CALLED.  `struct.pack('e', x)` is `dtype.py:226`."""
    rows = {}
    for h in h2f:
        rows[f"h2f_{h:x}"] = f"{f32_pattern(struct.unpack('<e', struct.pack('<H', h))[0]):08x}"
    for p in f16b:
        rows[f"f16b_{p:x}"] = f"{struct.unpack('<H', struct.pack('<e', of32(p)))[0]:04x}"
    return rows


# ------------------------------------------------------------ the gate.
def lanes(work: pathlib.Path, jsrc: str, csrc: str, h2f: list[int],
          f16b: list[int]) -> tuple[dict[str, str], dict[str, str]]:
    try:
        return (js_lane(work, jsrc, h2f, f16b), c_lane(work, csrc, h2f, f16b))
    except RuntimeError as exc:
        raise _Refused(str(exc)) from None


class _Refused(Exception):
    pass


def counts(py: dict[str, str], lane: dict[str, str]) -> dict[str, int]:
    """Disagreements against the oracle, SPLIT BY DIRECTION.

    The split is not decoration: the two directions have DIFFERENT defects, and a single
    number over both is a number that cannot say which one is present.
    """
    out = {}
    for d, pre in (("h2f", "h2f_"), ("f16b", "f16b_")):
        out[d] = sum(1 for k in py if k.startswith(pre) and lane.get(k) != py[k])
    out["all"] = sum(1 for k in py if lane.get(k) != py[k])
    return out


def run(*, arm: str | None) -> int:
    if not (ROOT / "pyproject.toml").is_file() or not (ROOT / "tinybendygrad").is_dir():
        return refuse(f"ROOT is not the repo root: {ROOT}")
    for p in (JS_LANE, C_LANE):
        if not p.exists():
            return refuse(f"input absent: {p}")
    if arm is not None and arm not in ARMS:
        return refuse(f"unknown arm {arm!r}; one of {sorted(ARMS)}")
    if bad := oracle_drift(ORACLE_PIN):
        return refuse("the CPython side drifted: " + "; ".join(bad))
    for tool in (NODE, CC):
        if not shutil.which(tool):
            return refuse(f"{tool} is not on PATH")

    jsrc, csrc = JS_LANE.read_text(), C_LANE.read_text()
    h2f, f16b = half_subnormals(), f32_subnormal_band()
    py = oracle_rows(h2f, f16b)
    want = len(h2f) + len(f16b)

    try:
        with tempfile.TemporaryDirectory() as tmp:
            work = pathlib.Path(tmp)
            base_js, base_c = lanes(work, jsrc, csrc, h2f, f16b)
            j2, c2 = jsrc, csrc
            for old, new in (ARMS.get(arm) or [[]])[0]:
                n = j2.count(old) + c2.count(old)
                if n != 1:
                    raise _Refused(f"arm {arm}: anchor {old.strip()[:56]!r} found {n} site(s)")
                if old in j2:
                    j2 = j2.replace(old, new)
                else:
                    c2 = c2.replace(old, new)
            arm_js, arm_c = lanes(work, j2, c2, h2f, f16b)
    except _Refused as exc:
        return refuse(str(exc))

    for name, lane in (("js", base_js), ("c", base_c), ("js-arm", arm_js), ("c-arm", arm_c)):
        if len(lane) != want:
            return refuse(f"the {name} lane emitted {len(lane)} rows, expected {want}")
    for name, lane in (("js", base_js), ("c", base_c), ("js-arm", arm_js), ("c-arm", arm_c)):
        missing = sorted(set(py) - set(lane))
        if missing:
            return refuse(f"the {name} lane is missing {len(missing)} oracle rows: {missing[:3]}")

    cb = {"js": counts(py, base_js), "c": counts(py, base_c)}
    ca = {"js": counts(py, arm_js), "c": counts(py, arm_c)}
    print(f"subnormal-flush-gate: {len(py)} rows, 3 lanes (ORACLE / dtype.c / dtype.js), "
          f"{len(h2f)} half subnormals (both signs), {len(f16b)} f32->half band patterns")
    print(f"  RULE f32->half subnormal band: f32 exponent fields "
          f"{(f32_subnormal_band()[0] >> 23) & 0xff}.."
          f"{(f32_subnormal_band()[-1] >> 23) & 0xff}, "
          f"ue = e - 127 + 15, ue in [-10, 0]")
    print(f"  DISAGREE js-vs-oracle {cb['js']['all']}/{len(py)} "
          f"(h2f {cb['js']['h2f']}, f16b {cb['js']['f16b']}) | "
          f"c-vs-oracle {cb['c']['all']}/{len(py)} "
          f"(h2f {cb['c']['h2f']}, f16b {cb['c']['f16b']}) | "
          f"js-vs-c {sum(1 for k in py if base_js.get(k) != base_c.get(k))}/{len(py)}")
    for k in sorted(k for k in py if base_js.get(k) != py[k])[:3]:
        print(f"  JS  {k}: oracle={py[k]} js={base_js[k]}")
    for k in sorted(k for k in py if base_c.get(k) != py[k])[:3]:
        print(f"  C   {k}: oracle={py[k]} c={base_c[k]}")
    js_rule = [l.strip() for l in jsrc.splitlines() if "103 << 23" in l]
    c_rule = [l.strip() for l in csrc.splitlines() if "__builtin_clz" in l]
    print(f"  RULE js (dtype.js:145): {js_rule[0] if js_rule else 'NOT FOUND'}")
    print(f"  RULE c  (dtype.c:176):  {c_rule[0] if c_rule else 'NOT FOUND'}")
    print(f"  RULE c extracted sha256={hashlib.sha256(extract_c(csrc, 'fp16_f32').encode()).hexdigest()[:16]}"
          f" bytes={len(extract_c(csrc, 'fp16_f32'))}")

    if arm is None:
        if cb["js"]["all"] or cb["c"]["all"]:
            print(f"subnormal-flush-gate: {verdict_of(FAIL)} -- the js lane disagrees with the "
                  f"oracle on {cb['js']['all']} rows; the c lane on {cb['c']['all']}")
            return FAIL
        print(f"subnormal-flush-gate: {verdict_of(PASS)} -- all three lanes agree on {len(py)} rows")
        return PASS

    # THE ARM'S STATEMENT, CHECKED AGAINST THE RUN.  An arm that does not do what it says
    # is a FAIL: an arm that cannot fail is a comment.
    print(f"  ARM {arm}: baseline js {cb['js']} / c {cb['c']} -> "
          f"armed js {ca['js']} / c {ca['c']}")
    for old, new in ARMS[arm][0]:
        print(f"    {old.strip()[:58]!r} -> {new.strip()[:58]!r}")
    for key, want_val in ARMS[arm][1].items():
        if key == "*":
            for lane, base, armed in (("js", cb["js"], ca["js"]), ("c", cb["c"], ca["c"])):
                for d in ("h2f", "f16b", "all"):
                    if armed[d] != base[d]:
                        print(f"  ARM {arm} VIOLATED: {lane}/{d} moved "
                              f"{base[d]} -> {armed[d]}; a control that moves rows is an "
                              f"instrument reading a TOKEN instead of a VALUE")
                        return FAIL
            continue
        lane, d = key.split("/")
        got = ca[lane][d]
        base = cb[lane][d]
        if want_val == "unchanged":
            ok = got == base
        elif want_val == "nonzero":
            ok = got != 0
        else:
            ok = got == want_val
        if not ok:
            print(f"  ARM {arm} VIOLATED: {key} is {got}, and the arm says {want_val} "
                  f"(the baseline was {base})")
            return FAIL
    print(f"subnormal-flush-gate: {verdict_of(PASS)} -- arm {arm} did what it says")
    return PASS


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="the f16 subnormal class, three lanes")
    ap.add_argument("--plant", choices=sorted(ARMS))
    ns = ap.parse_args()
    sys.exit(run(arm=ns.plant))
