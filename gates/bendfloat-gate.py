#!/usr/bin/env python3
"""bendfloat-gate.py -- the BEND lane's f16 rule, against CPython's own codec.

    .venv/bin/python gates/bendfloat-gate.py [--plant NAME]

WHY THIS FILE EXISTS.  `tinybendygrad/dtype.bend` implements the f16 rule in a FOURTH
place -- the tree has three lanes for it and this file is the gate for the one that had
none.  `gates/subnormal-flush-gate.py` drives the C (`runtime/dtype.c`) and the JS
(`runtime/dtype.js`) against CPython, and `gates/float-halfclass-gate.py` holds the two
half CLASSES for the same two lanes; both of them say in their own headers that the BEND
is not theirs.  MEASURED before this file existed, on the bend2 EMITTER's own output for
the live `tinybendygrad/dtype.bend`:

    BEND half->f32 (fp16_f32, white-box), 2046 half subnormals: 2046 disagree with CPython
        h2f_1: oracle=33800000 bend=43000000        <- 128.0 where the answer is 2**-24
    BEND f32->half (fp16_encode, white-box), 77 band patterns: 0 disagree
    BEND f32->half (Dt.fp16, THE SEAM), 77 band patterns: 75 disagree
    BEND Dt.fp16 over 64 f32 NaN patterns (32 low, 32 high): 32 disagree

so the Bend's ENCODE side agreed with CPython, its DECODE side did not, and its SEAM -- the
composition of the two -- inherited the decode side's answer.  The cause was one token:
`dtype.bend`'s exponent read `31 - U32.log2(m)`, and bend2's `U32.log2` is `floor(log2 n)`
and NOT the C's `__builtin_clz`, which is `31 - floor(log2 n)`.

THE LANE IS THE TREE'S OWN BYTES.  The subject is `tinybendygrad/dtype.bend`, and it is
COMPILED: `bin/bend` (the tree's shim onto `references/bend/bend2`) emits an ES module, and
`node` calls the module's exported defs.  Nothing about the rule is transcribed here: the
three defs the driver calls are one-line wrappers around `dtype.bend`'s own `fp16_f32`,
`fp16_encode` and `Dt.fp16`, and the probe that wraps them is WRITTEN BY THIS FILE into a
temporary copy of the tree, so the armed arms below can perturb the tree's own file and
recompile it.

THE POPULATION IS DISCOVERED, NEVER LISTED, and every class is a rule of the FORMAT:

    h2f    the half SUBNORMALS: exponent field 0, mantissa not 0, BOTH SIGNS.  2046.
    h2n    the half NaNs: exponent field 0x1f, mantissa not 0, BOTH SIGNS.  2046.
    h2i    the half INFINITIES: exponent field 0x1f, mantissa 0, BOTH SIGNS.  2.
    f16b   the f32 -> half SUBNORMAL BAND, from `gates/subnormal-flush-gate.py`'s own
           `f32_subnormal_band()`, both signs.  154.
    f16n   the f32 NaN CLASS: exponent field 0xff, mantissa not 0, BOTH SIGNS.  16777214.
           THE WHOLE CLASS, not a prefix of it and not a sample of it: the class is
           2^23 - 1 mantissas per sign, and a lane's answer on it is a FUNCTION of the
           payload, so a prefix of the class cannot say what the class does.
    seam_n the f32 NaN class through the SEAM, over the class's per-sign SPREAD -- the
           mantissas `k << 13 | 1` for k = 1..1023 -- which is neither a prefix nor a
           suffix of the class and which carries the low 13 bits too.

THE ORACLE IS CPython's OWN CODEC, CALLED.  `struct.pack('e')` / `struct.unpack('e')`,
which is what `tinygrad/dtype.py:220` calls, and `tinygrad/dtype.py` is PINNED BY BYTES
(the same pin `gates/subnormal-flush-gate.py` uses) so a re-vendor moves the pin or moves
the rows, not both.  No expected value is written down in this file: every number below is
COUNTED from the two lanes' own output.

THE FIVE VERDICTS ARE THE TREE'S.  `gatekit`'s: PASS 0, FAIL 1, REFUSED 3, SKIP 4, DEAD 5.
A SKIP IS NOT A PASS: this gate needs `bin/bend` (and `bun` and `node`), and when one of
them is absent it says REFUSED and exits 3 -- it does not exit 0 having measured nothing.

THE ARMS, each anchored, each COUNTED, each applied to a COPY of the lane it perturbs --
the live tree is never a base.  A plant that cannot fail is a comment, and a control that
moves rows is an instrument reading a TOKEN instead of a VALUE.  The anchors are the
tree's own FIXED text, so an arm whose anchor is gone REFUSES -- and that refusal is the
fix landing, not a broken gate.

    k-plant      the exponent is given the `31 -` back.  MUST take the h2f disagreement
                 count ABOVE zero and move the h2f values.
    k-disarm     the SAME line, re-spelled.  MUST move every count by ZERO.
    nan-plant    the NaN arms are given the PAYLOAD back, in both directions.  MUST take
                 the h2n and f16n disagreement counts ABOVE zero and the h2n and f16n
                 distinct counts ABOVE the oracle's.
    nan-disarm   the SAME two lines, re-spelled.  MUST move every count by ZERO.

WHY THE JS's `norm-plant` DOES NOT COVER THIS LANE.  `gates/float-halfclass-gate.py`'s
`norm-plant` gives the JS lane's `m << 14` back, and it holds the JS lane's rule.  The
BEND's rule is a different spelling of the same idea -- `U32.log2` where the JS has
`Math.clz32` -- in a different file, in a different language, compiled by a different
compiler.  A plant that perturbs the JS cannot move the Bend's rows, and a gate whose
plant does not move its own lane's rows is a gate that cannot SEE its own lane fail: the
lane it does not cover can regress silently, which is the whole reason this file exists.
So the Bend needs its OWN plant, and this file has one.

WHAT THIS FILE CANNOT SEE, because a row that cannot say what it cannot see is a row that
will be read as more than it is:

    the half NORMALS, the f32 -> half direction outside the band and outside the NaN
    class, the fp8 and bf16 rules, and every pattern class the fixture does not contain.
    The JS and C lanes are `gates/subnormal-flush-gate.py`'s and
    `gates/float-halfclass-gate.py`'s subject, not this file's.
"""
from __future__ import annotations

import argparse
import array
import importlib.util
import itertools
import json
import pathlib
import shutil
import struct
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from gatekit import FAIL, PASS, REFUSED, verdict_of  # noqa: E402

ROOT = HERE.parent
BEND = ROOT / "bin" / "bend"
PORT = ROOT / "tinybendygrad"
DTYPE = PORT / "dtype.bend"
NODE, BUN = "node", "bun"

# THE SIBLING GATE, BY PATH.  `float-halfclass-gate.py` holds the two half CLASSES and
# imports `subnormal-flush-gate.py` by path itself, so this file takes the SECOND one
# through the FIRST and there is exactly one copy of each module in this process.
_spec = importlib.util.spec_from_file_location(
    "float_halfclass_gate", HERE / "float-halfclass-gate.py")
fhc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fhc)
sfg = fhc.sfg

# THE ORACLE PIN, the same bytes `gates/subnormal-flush-gate.py` pins, so the two gates
# cannot drift apart on what the oracle IS.
ORACLE_PIN = sfg.ORACLE_PIN

# THE PROBE.  Three one-line wrappers around the tree's own defs, and nothing else: the
# rule under test is `dtype.bend`'s, and this file adds no arithmetic of its own.
PROBE = """import Base
import ./tinybendygrad/dtype.bend as D

def bf_h2f(h: U32) -> U32:
  D.fp16_f32(h)

def bf_enc(s: U32, e: U32, m: U32) -> U32:
  D.fp16_encode(s, e, m)

def bf_seam(x: F32) -> F32:
  D.Dt.fp16(x)
"""

# THE DRIVER.  It reads the fixture the gate wrote, calls the tree's own defs, and writes
# the answers back as one u32 per pattern.  It computes NO expected value and prints NO
# verdict: the comparison is the gate's, in Python, over the two lanes' own bytes.
DRIVER = """import fs from "node:fs";
import mod from "./probe.mjs";

const here = new URL(".", import.meta.url);
const hdr = JSON.parse(fs.readFileSync(new URL("fixture.json", here), "utf8"));
const bin = fs.readFileSync(new URL("fixture.bin", here));
const pats = new Uint32Array(bin.buffer, bin.byteOffset, bin.length / 4);
const ans = new Uint32Array(pats.length);
const fb = new ArrayBuffer(4);
const f32 = new Float32Array(fb);
const u32 = new Uint32Array(fb);
let i = 0;
for (const s of hdr.sections) {
  for (let k = 0; k < s.count; k++, i++) {
    const p = pats[i];
    let v;
    if (s.kind === "h2f") {
      v = mod.bf_h2f(p) >>> 0;
    } else if (s.kind === "enc") {
      v = mod.bf_enc((p >>> 16) & 0x8000, (p >>> 23) & 0xff, p & 0x7fffff) >>> 0;
    } else {
      u32[0] = p;
      v = mod.bf_seam(f32[0]);
      f32[0] = v;
      v = u32[0] >>> 0;
    }
    ans[i] = v;
  }
}
fs.writeFileSync(new URL("answers.bin", here), Buffer.from(ans.buffer));
"""

# THE ARMS.  The anchors are the tree's own FIXED text, each one a single site.
K_FIXED = "U32.shln(U32.add(U32.from_nat(U32.log2(m)), 103), 23n)"
K_BROKEN = "U32.shln(U32.add(U32.sub(31, U32.from_nat(U32.log2(m))), 103), 23n)"
ENC_FIXED = "U32.or(31744, 512)"
ENC_PAYLOAD = "U32.or(31744, U32.or(512, U32.shrn(m, 13n)))"
DEC_FIXED = "U32.or(2139095040, 4194304)"
DEC_PAYLOAD = "U32.or(2139095040, U32.shln(m, 13n))"

ARMS: dict[str, tuple[list[tuple[str, str]], dict[str, str]]] = {
    # THE `31 -` GIVEN BACK.  The rule whose exponent is `31 - floor(log2 m) + 103`.
    "k-plant": ([(K_FIXED, K_BROKEN)],
                {"h2f/disagree": "above", "h2n/disagree": "same",
                 "f16b/disagree": "same", "f16n/disagree": "same"}),
    # THE SAME LINE, RE-SPELLED.  Must move nothing: this is what separates a TOKEN
    # check from a VALUE check.
    "k-disarm": ([(K_FIXED, K_FIXED.replace("(m), 103)", "(m) , 103)"))],
                 {"h2f/disagree": "same", "h2n/disagree": "same",
                  "f16b/disagree": "same", "f16n/disagree": "same"}),
    # THE PAYLOAD CARRIED INSTEAD OF CANONICALISED, IN BOTH DIRECTIONS.
    "nan-plant": ([(ENC_FIXED, ENC_PAYLOAD), (DEC_FIXED, DEC_PAYLOAD)],
                  {"h2n/disagree": "above", "h2n/distinct": "above",
                   "f16n/disagree": "above", "f16n/distinct": "above"}),
    # THE SAME TWO LINES, RE-SPELLED.
    "nan-disarm": ([(ENC_FIXED, ENC_FIXED.replace("(31744, 512)", "(31744,  512)")),
                    (DEC_FIXED, DEC_FIXED.replace("(2139095040,", "( 2139095040,"))],
                   {"h2n/disagree": "same", "f16n/disagree": "same",
                    "h2n/distinct": "same", "f16n/distinct": "same"}),
}


def refuse(*why: str) -> int:
    print("== REFUSED, NOT A VERDICT: " + "; ".join(why), file=sys.stderr)
    return REFUSED


# ------------------------------------------------------------ the populations.
def half_subnormals() -> list[int]:
    """The half SUBNORMALS: exponent field 0, mantissa not 0, both signs."""
    return sfg.half_subnormals()


def half_nans() -> list[int]:
    """The half NaNs: exponent field 0x1f, mantissa not 0, both signs."""
    return fhc.half_classes()[1]


def half_infinities() -> list[int]:
    """The half INFINITIES: exponent field 0x1f, mantissa 0, both signs.

    NOT in `half_classes()`: that function's two classes are the subnormals and the NaNs,
    and the infinities are a third class with a THIRD property -- the map must send them
    to an INFINITY and not to a NaN, which is a distinction no count of NaN rows can see.
    """
    return [h for h in range(0x10000) if (h & 0x7C00) == 0x7C00 and (h & 0x3FF) == 0]


def f32_band() -> list[int]:
    """The f32 -> half SUBNORMAL BAND, both signs, from the sibling gate's own rule."""
    return sfg.f32_subnormal_band()


def f32_nan_patterns() -> array.array:
    """THE f32 NaN CLASS, BOTH SIGNS: exponent field 0xff, mantissa not 0.

    THE WHOLE CLASS: 2^23 - 1 mantissas per sign.  It is an `array` and not a list because
    a list of 16.7 million Python ints is a gigabyte of pointers and this class is a
    PATTERN, not a fact about the lane.
    """
    a = array.array("I", (0x7F800000 | m for m in range(1, 0x800000)))
    a.extend(0xFF800000 | m for m in range(1, 0x800000))
    return a


def f32_nan_spread() -> list[int]:
    """THE f32 NaN CLASS'S SPREAD, for the seam: the mantissas `k << 13 | 1`, both signs.

    Neither a prefix nor a suffix of the class: `k` spans every 13-bit truncation the
    class has, and the `| 1` carries the low 13 bits, so a defect that reads either the
    high bits or the low bits of the payload is in the fixture.
    """
    return ([0x7F800000 | (k << 13) | 1 for k in range(1, 1024)]
            + [0xFF800000 | (k << 13) | 1 for k in range(1, 1024)])


# ------------------------------------------------------------ the oracle.
def oracle_h2f(patterns) -> array.array:
    """CPython's own half -> f32 codec, CALLED: `struct.unpack('e', ...)`, then the f32
    pattern of the value it answers."""
    out = array.array("I")
    for h in patterns:
        v = struct.unpack("<e", struct.pack("<H", h))[0]
        out.append(struct.unpack("<I", struct.pack("<f", v))[0])
    return out


def oracle_enc(patterns) -> array.array:
    """CPython's own f32 -> half codec, CALLED: the half BITS of `struct.pack('e', x)`.

    BULK, in chunks: the class is 16.7 million patterns and a per-pattern call would make
    the gate's own oracle the slow part of it.
    """
    out = array.array("I")
    step = 1 << 20
    it = iter(patterns)
    while chunk := list(itertools.islice(it, step)):
        raw = b"".join(struct.pack("<I", p) for p in chunk)
        floats = struct.unpack(f"<{len(chunk)}f", raw)
        out.extend(struct.unpack(f"<{len(chunk)}H", struct.pack(f"<{len(chunk)}e", *floats)))
    return out


def oracle_seam(patterns) -> array.array:
    """CPython's own codec, TWICE: the f32 pattern of the value a half round trip
    answers.  This is the oracle of the SEAM, and it is a COMPOSITION of the two calls
    above -- not a transcription of either."""
    halves = oracle_enc(patterns)
    out = array.array("I")
    step = 1 << 20
    for i in range(0, len(halves), step):
        chunk = halves[i:i + step]
        raw = b"".join(struct.pack("<H", h) for h in chunk)
        floats = struct.unpack(f"<{len(chunk)}e", raw)
        out.extend(struct.unpack(f"<{len(chunk)}I", struct.pack(f"<{len(chunk)}f", *floats)))
    return out


# ------------------------------------------------------------ the lane.
def bend_lane(work: pathlib.Path, dtype_text: str, sections: list[dict],
              pats: list[array.array]) -> array.array:
    """THE TREE'S OWN BYTES, COMPILED AND CALLED.

    The tree is COPIED, `dtype.bend` in the copy is the text given, the probe is written
    beside it, `bin/bend` emits an ES module and `node` calls it.  Nothing of the rule is
    transcribed: the text given IS `dtype.bend`.
    """
    tree = work / "tree"
    tree.mkdir(parents=True)
    shutil.copytree(PORT, tree / "tinybendygrad")
    (tree / "tinybendygrad" / "dtype.bend").write_text(dtype_text)
    (tree / "probe.bend").write_text(PROBE)
    r = subprocess.run([str(BEND), str(tree / "probe.bend"), "-o", str(work / "probe.mjs")],
                       capture_output=True, text=True, timeout=1800)
    if r.returncode != 0:
        raise RuntimeError(f"bend failed: {(r.stderr or '').strip()[:300]}")
    meta, offset = [], 0
    with (work / "fixture.bin").open("wb") as fh:
        for s, ps in zip(sections, pats):
            meta.append({"name": s["name"], "kind": s["kind"], "count": len(ps),
                         "offset": offset})
            raw = array.array("I", ps)
            if sys.byteorder != "little":
                raw.byteswap()
            fh.write(raw.tobytes())
            offset += len(ps)
    (work / "fixture.json").write_text(json.dumps({"sections": meta}))
    (work / "driver.mjs").write_text(DRIVER)
    n = subprocess.run([NODE, str(work / "driver.mjs")], capture_output=True, text=True,
                       timeout=3600)
    if n.returncode != 0:
        raise RuntimeError(f"node failed: {(n.stderr or '').strip()[:300]}")
    raw = (work / "answers.bin").read_bytes()
    ans = array.array("I")
    ans.frombytes(raw)
    if sys.byteorder != "little":
        ans.byteswap()
    return ans


def compare(lane: array.array, oracle: array.array) -> tuple[int, list]:
    """(disagreements, first four) -- COUNTED from the two lanes' own bytes.

    The EQUAL case is a memcmp: the class is 16.7 million rows and a Python loop over it
    would make the gate's own bookkeeping the slow part of the measurement.  The UNEQUAL
    case counts every one of them and keeps four.
    """
    if lane.tobytes() == oracle.tobytes():
        return 0, []
    n, first = 0, []
    for i in range(len(oracle)):
        if lane[i] != oracle[i]:
            n += 1
            if len(first) < 4:
                first.append((i, lane[i], oracle[i]))
    return n, first


def run(*, arm: str | None) -> int:
    if not (ROOT / "pyproject.toml").is_file() or not PORT.is_dir():
        return refuse(f"ROOT is not the repo root: {ROOT}")
    if not DTYPE.is_file():
        return refuse(f"input absent: {DTYPE}")
    if arm is not None and arm not in ARMS:
        return refuse(f"unknown arm {arm!r}; one of {sorted(ARMS)}")
    if bad := sfg.oracle_drift(ORACLE_PIN):
        return refuse("the CPython side drifted: " + "; ".join(bad))
    for tool in (NODE, BUN):
        if not shutil.which(tool):
            return refuse(f"{tool} is not on PATH")
    if not BEND.is_file():
        return refuse(f"the compiler shim is absent: {BEND}")

    # THE ARM'S EDIT IS MADE ON A COPY OF THE LANE, BEFORE ANY LANE RUNS, and the anchor
    # must be found EXACTLY ONCE: an anchor that moved is a measurement of nothing.
    src = DTYPE.read_text()
    armed = src
    for old, new in (ARMS.get(arm) or [[]])[0]:
        n = armed.count(old)
        if n != 1:
            return refuse(f"arm {arm}: anchor {old.strip()[:56]!r} found {n} site(s), "
                          f"expected 1 -- dtype.bend moved")
        armed = armed.replace(old, new)

    h2f, h2n, h2i = half_subnormals(), half_nans(), half_infinities()
    f16b, f16n, seam_n = f32_band(), f32_nan_patterns(), f32_nan_spread()
    sections = [
        {"name": "h2f", "kind": "h2f"}, {"name": "h2n", "kind": "h2f"},
        {"name": "h2i", "kind": "h2f"}, {"name": "f16b", "kind": "enc"},
        {"name": "seam_b", "kind": "seam"}, {"name": "f16n", "kind": "enc"},
        {"name": "seam_n", "kind": "seam"},
    ]
    pats = [array.array("I", h2f), array.array("I", h2n), array.array("I", h2i),
            array.array("I", f16b), array.array("I", f16b), f16n,
            array.array("I", seam_n)]
    oracle = {
        "h2f": oracle_h2f(h2f), "h2n": oracle_h2f(h2n), "h2i": oracle_h2f(h2i),
        "f16b": oracle_enc(f16b), "seam_b": oracle_seam(f16b),
        "f16n": oracle_enc(f16n), "seam_n": oracle_seam(seam_n),
    }

    try:
        with tempfile.TemporaryDirectory() as tmp:
            base = bend_lane(pathlib.Path(tmp) / "base", src, sections, pats)
            armed_ans = base
            if arm is not None:
                armed_ans = bend_lane(pathlib.Path(tmp) / "armed", armed, sections, pats)
    except RuntimeError as exc:
        return refuse(str(exc))

    # THE ANSWERS FILE'S LENGTH IS THE CONTRACT, and it is checked rather than assumed.
    want = sum(len(p) for p in pats)
    if len(base) != want:
        return refuse(f"the lane answered {len(base)} rows, expected {want}")
    if arm is not None and len(armed_ans) != want:
        return refuse(f"the armed lane answered {len(armed_ans)} rows, expected {want}")

    counts: dict[str, dict[str, int]] = {}
    rows_by_name: dict[str, array.array] = {}
    off = 0
    for s, ps in zip(sections, pats):
        n = len(ps)
        rows = base[off:off + n]
        arows = armed_ans[off:off + n]
        off += n
        rows_by_name[s["name"]] = rows
        d, bad = compare(rows, oracle[s["name"]])
        da, bada = compare(arows, oracle[s["name"]])
        counts[s["name"]] = {
            "rows": n, "disagree": d, "arm_disagree": da,
            "distinct": len(set(rows)), "arm_distinct": len(set(arows)),
            "oracle_distinct": len(set(oracle[s["name"]])),
        }
        for i, got, wantv in bad:
            print(f"  {s['name']} row {i}: oracle={wantv:08x} bend={got:08x}")
        for i, got, wantv in bada:
            if not bad:
                print(f"  {s['name']} ARM row {i}: oracle={wantv:08x} arm={got:08x}")

    print(f"bendfloat-gate: {want} rows over {len(sections)} classes, 2 lanes "
          f"(ORACLE / the compiled tinybendygrad/dtype.bend)")
    for s in sections:
        c = counts[s["name"]]
        print(f"  {s['name']:<7} {c['rows']:>9} rows | disagree {c['disagree']:>9} "
              f"| distinct {c['distinct']:>6} (oracle {c['oracle_distinct']})")
    # THE INJECTIVITY OF THE POSITIVE CLASS, COUNTED and not asserted: the sign bit
    # cannot collide with itself, so the positive class is where injectivity is a
    # question at all.  A rule can be injective and WRONG, so this row is not a verdict
    # on its own -- it is the shape `gates/float-halfclass-gate.py` holds for the JS
    # and the C, and it is here for the Bend.
    pos_rows = {rows_by_name["h2f"][i] for i, h in enumerate(h2f) if h < 0x8000}
    pos_bad = sum(1 for i, h in enumerate(h2f) if h < 0x8000
                  and rows_by_name["h2f"][i] != oracle["h2f"][i])
    h2f_pos = [h for h in h2f if h < 0x8000]
    print(f"  h2f positive class: {len(h2f_pos)} inputs, {len(pos_rows)} distinct f32 "
          f"patterns (the map must be INJECTIVE), {pos_bad} disagree")
    print(f"  RULE bend (dtype.bend): {K_FIXED!r}")

    if arm is None:
        bad = [name for name, c in counts.items() if c["disagree"]]
        if bad:
            print(f"bendfloat-gate: {verdict_of(FAIL)} -- the bend lane disagrees with the "
                  f"oracle on {', '.join(bad)}")
            return FAIL
        print(f"bendfloat-gate: {verdict_of(PASS)} -- the bend lane agrees with the oracle "
              f"on all {want} rows")
        return PASS

    print("  ARM " + arm + ": " + " | ".join(
        f"{name} disagree {counts[name]['disagree']} -> {counts[name]['arm_disagree']}"
        for name in counts))
    for old, new in ARMS[arm][0]:
        print(f"    {old.strip()[:58]!r} -> {new.strip()[:58]!r}")
    for key, rel in ARMS[arm][1].items():
        name, field = key.split("/")
        base_v = counts[name][field]
        arm_v = counts[name]["arm_" + field]
        ok = {"same": arm_v == base_v, "above": arm_v > base_v,
              "below": arm_v < base_v}.get(rel, False)
        if not ok:
            print(f"  ARM {arm} VIOLATED: {key} is {arm_v}, and the arm says {rel} of {base_v}")
            return FAIL
    print(f"bendfloat-gate: {verdict_of(PASS)} -- arm {arm} did what it says")
    return PASS


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="the bend lane's f16 rule, against CPython")
    ap.add_argument("--plant", choices=sorted(ARMS))
    ns = ap.parse_args()
    sys.exit(run(arm=ns.plant))
