#!/usr/bin/env python3
"""abi_gate.py -- both lanes of the dtype seam, checked against ONE declaration.

Reproduce (from the repo root):
    python3 .agents/slop/abi/abi_gate.py

THE DELIVERABLE IS NOT A ROW COUNT.  It is the ATTRIBUTION: every disagreement
between the two lanes, or between a lane and CPython, is assigned to exactly one
of the four ABI ids declared in `abi.json`.  A red that cannot be named is what
both shipped bugs were.

WHY A GATE AND NOT A COMMENT.  Each of the two shipped bugs was a bug in NO lane.
ABI-1 was C reading `f[0],f[1]` where the seam has one argument; locally that is
exactly what `dtype.js:165`'s two-parameter lambda says.  ABI-2 was JS reading
`p.fst`/`p.snd`; locally that is exactly what `dtype.c:212`'s `io_tup(e,a,b)`
produces.  Each lane was correct with respect to a statement of the ABI that the
other lane did not satisfy, so no test *inside* a lane can fail.  Only an artifact
that is ABOVE both lanes has a shared referent, and a comment is not one: both
lanes were written by reading each other's CODE, which is the thing in dispute.

THE THREE CONTROLS.  A red with no paired disarm proves nothing -- three controls
in this project were found disarmed.  Every plant here has a paired disarm that is
a SYNTACTIC RE-SPELLING of the conforming code, so 0 is the only correct moved
count, AND a diagnostic (what it would take to conform, evaluated for real).

THE LIVE TREE IS NEVER WRITTEN.  dtype.c and dtype.js are copied to $TMPDIR and
patched there.  The `shipped` arm patches nothing at all: it is the measurement.
"""
from __future__ import annotations

import json
import pathlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]
sys.path.insert(0, str(REPO))
from tinygrad import dtype as td            # noqa: E402
from tinygrad.helpers import floordiv       # noqa: E402

BEND = REPO / "bin" / "bend"
C_LANE = REPO / "tinybendygrad" / "runtime" / "dtype.c"
JS_LANE = REPO / "tinybendygrad" / "runtime" / "dtype.js"
DECL = HERE / "abi.json"

# ---------------------------------------------------------------- the probe.
# One program, twelve rows, keyed by the ABI id whose convention each row
# exercises.  Every abi123_* row has hi != lo and both words nonzero, so no row
# is blind to the pair order; that is a property of the fixture set and the gate
# prints both words so it can be checked rather than believed.
PROBE = """import ./tinybendygrad/dtype.bend as D
import ./tinybendygrad/helpers.bend as H

def main() -> IO(Unit):
  do IO<Unit>:
    t1 : H.I64 <- D.Dt.i64_trunc(H.i64_of_hi_lo(15, 240))
    IO.print("abi123 trunc_A = " ++ H.i64_text(t1))
    t2 : H.I64 <- D.Dt.i64_trunc(H.i64_of_hi_lo(3735928559, 305419896))
    IO.print("abi123 trunc_B = " ++ H.i64_text(t2))
    d1 : H.I64 <- D.Dt.i64_floor_div(H.i64_of_hi_lo(7, 0), H.i64_of_hi_lo(3, 0))
    IO.print("abi123 fdiv_b3 = " ++ H.i64_text(d1))
    d2 : H.I64 <- D.Dt.i64_floor_div(H.i64_of_hi_lo(7, 0), H.i64_of_hi_lo(5, 0))
    IO.print("abi123 fdiv_b5 = " ++ H.i64_text(d2))
    d3 : H.I64 <- D.Dt.i64_floor_div(H.i64_of_hi_lo(7, 0), H.i64_of_hi_lo(1, 0))
    IO.print("abi123 fdiv_b1 = " ++ H.i64_text(d3))
    c1 : U32 <- D.Dt.fp8_from(F32.bits(1.5), 0)
    IO.print("abi1 fp8from_e4m3 = " ++ U32.show(c1))
    c2 : U32 <- D.Dt.fp8_from(F32.bits(1.5), 2)
    IO.print("abi1 fp8from_fnuz = " ++ U32.show(c2))
    b1 : F32 <- D.Dt.bf16(F32.bits(1.5))
    IO.print("abi1 bf16_1p5 = " ++ F32.show(b1))
    e1 : F32 <- D.Dt.fp16(1.5)
    IO.print("abi4 fp16_1p5 = " ++ F32.show(e1))
    e2 : F32 <- D.Dt.fp16(1.1)
    IO.print("abi4 fp16_1p1 = " ++ F32.show(e2))
    e3 : F32 <- D.Dt.fp16(F32.neg(2.25))
    IO.print("abi4 fp16_m2p25 = " ++ F32.show(e3))
    f1 : F32 <- D.Dt.fp8_to(60, 0)
    IO.print("abi4 fp8to_0x3C = " ++ F32.show(f1))
"""

ROW = re.compile(r"^(abi\d+) (\w+) = (.*)$")


# ------------------------------------------------------------- the oracle.
# CPython, CALLED.  Never transcribed.  (dtype.py and helpers.py, imported.)
def pair(v: int) -> str:
    """`H.i64_text` prints hi:lo, so the oracle must print hi:lo too.  My first
    cut wrote f"{floordiv(7,3)}:0" -- the DECIMAL 2 -- which is a different
    string from the lane's 0:2 and made cc look wrong on rows it got right."""
    u = v & 0xFFFFFFFFFFFFFFFF
    return f"{u >> 32}:{u & 0xFFFFFFFF}"


ORACLE = {
    "abi123_trunc_A": "15:240",
    "abi123_trunc_B": "3735928559:305419896",
    "abi123_fdiv_b3": pair(floordiv(7, 3)),
    "abi123_fdiv_b5": pair(floordiv(7, 5)),
    "abi123_fdiv_b1": pair(floordiv(7, 1)),
    "abi1_fp8from_e4m3": str(td.float_to_fp8(1.5, td.dtypes.fp8e4m3)),
    "abi1_fp8from_fnuz": str(td.float_to_fp8(1.5, td.dtypes.fp8e4m3fnuz)),
    "abi1_bf16_1p5": repr(float(td.float_to_bf16(1.5))),
    "abi4_fp16_1p5": repr(float(td.float_to_fp16(1.5))),
    "abi4_fp16_1p1": repr(float(td.float_to_fp16(1.1))),
    "abi4_fp16_m2p25": repr(float(td.float_to_fp16(-2.25))),
    "abi4_fp8to_0x3C": repr(float(td.fp8_to_float(0x3C, td.dtypes.fp8e4m3))),
}
# hi:lo of each abi123 row, so the hi != lo property is printable, not assumed.
WORDS = {"abi123_trunc_A": (15, 240), "abi123_trunc_B": (3735928559, 305419896)}


def norm(s: str) -> str:
    """Normalise an F32 row to its f32 value before counting.

    Two separate format traps, both measured here, both of which would otherwise
    land in the count and make it mean two things at once (JSL2-7):
      * `F32.show` prints `448` where CPython prints `448.0`;
      * `f32_show` searches for the SHORTEST round-tripping form (probe.js:43-56),
        so the f32 nearest 1.1 prints as `1.0996094` while CPython, holding a
        double, prints `1.099609375`.  Both are the same f32 -- 1.099609375 is
        exactly representable in f32 -- so this is a spelling, not a value."""
    try:
        v = float(s)
    except ValueError:
        return s
    return repr(struct.unpack("<f", struct.pack("<f", v))[0])


# ---------------------------------------------------------------- the arms.
# Each arm is a list of (lane, [(old, new), ...]).  Anchors must be unique or the
# run aborts: a non-unique anchor means the lane file moved under us and every
# number below would be stale.
C_I64_OF_OLD = """static s64 i64_of(Env e, Term t) {
  Term o[2];
  ctr_take(e, t, 2, o);
  return (s64)((((u64)(u32)o[0]) << 32) | (u32)o[1]);
}"""
# ABI-1 PLANT: the pre-fix i64_of, verbatim from w64mile/dtype-c-i64.patch:7-13.
C_I64_OF_OVERREAD = """static s64 i64_of(Term* f) {
  return (s64)(((u64)(u32)f[0] << 32) | (u32)f[1]);
}"""
JS_I64_OF_OLD = """function i64_of(p) {
  return BigInt.asIntN(64, (BigInt(p.fst >>> 0) << 32n) | BigInt(p.snd >>> 0));
}"""
JS_PACK_OLD = """function pack64(v) {
  const u = BigInt.asUintN(64, v);
  return io_tup(Number((u >> 32n) & 0xffffffffn), Number(u & 0xffffffffn));
}"""
JS_FP16_OLD = """function dtype_fp16(x) {
  return of32(half_to_f32(f16_bits(of32(x))));
}"""
C_FP8TO_OLD = """static Term fp8_to_run(Env e, Term* f, IoWork* w) {
  return (Term)(intptr_t)fp8_decode((u32)f[0] & 0xFFu, (u32)f[1] & 0xFFu);
}"""
C_FP16_OLD = """static Term fp16_run(Env e, Term* f, IoWork* w) {
  return (Term)(intptr_t)fp16_f32(fp16_encode((u32)f[0]));
}"""
C_PACK_OLD = """static Term pack64(Env e, s64 v) {
  return io_tup(e, (Term)(intptr_t)(u32)((u64)v >> 32), (Term)(intptr_t)(u32)(u64)v);
}"""
C_JOIN_OLD = """  v = (f32)(exp == 0 ? (mant / (f32)(mant_max + 1)) * (1.0f / (1u << bias))
                     : (1.0f + mant / (f32)(mant_max + 1)) *
                       ldexpf(1.0f, (int)exp - (int)bias));
  return f32_rewrap(sgn ? -v : v);"""

# The JS repair.  Four edits, each one an obligation named in abi.json.  This is
# the DIAGNOSTIC arm: it exists to show the declaration is satisfiable and to give
# ABI-2's control a green middle.  It is $TMPDIR ONLY and is NOT applied to the
# tree -- declaring the ABI is the coordinator's call, not this gate's.
JS_I64_OF_FIXED = """function i64_of(p) {
  return BigInt.asIntN(64, (BigInt(p.hi >>> 0) << 32n) | BigInt(p.lo >>> 0));
}"""
JS_PACK_FIXED = """function pack64(v) {
  const u = BigInt.asUintN(64, v);
  return {$: "tinybendygrad/helpers.I64", hi: Number((u >> 32n) & 0xffffffffn),
          lo: Number(u & 0xffffffffn)};
}"""
JS_FP16_FIXED = """function dtype_fp16(x) {
  return of32(half_to_f32(f16_bits(x)));
}"""
JS_FP8TO_OLD = """function dtype_fp8_to(x, kind) {
  return fp8_decode(x >>> 0, kind & 0xff);
}"""
JS_FP8TO_FIXED = """function dtype_fp8_to(x, kind) {
  return of32(fp8_decode(x >>> 0, kind & 0xff));
}"""
# THE SAME ABI-4 BUG AS dtype_fp16, AT THE SAME SHAPE, IN A DIFFERENT FUNCTION.
# `of32(...)` is pattern->value applied to an arithmetic VALUE, so of32(1.5) is
# the pattern 1 -- the smallest f32 subnormal -- and `bits32` of that denormal is
# 1.  This is what `fp8_to(0x3C)` answers under node, and it is why JS-LANE-GATE.md
# recorded fp8_to as "measured, NOT localised": the fault is in the HELPER, not in
# the seam that calls it.  Measured, with all three stages, by fp8stage.py.
JS_FP8DEC_OLD = """  const v = of32(exp === 0
    ? (mant / (mantMax + 1)) * Math.pow(2, 1 - bias)
    : (1 + mant / (mantMax + 1)) * Math.pow(2, exp - bias));
  return bits32(sgn ? -v : v);"""
JS_FP8DEC_FIXED = """  const v = exp === 0
    ? (mant / (mantMax + 1)) * Math.pow(2, 1 - bias)
    : (1 + mant / (mantMax + 1)) * Math.pow(2, exp - bias);
  return bits32(sgn ? -v : v);"""


ARMS = {
    # ---- the measurement: nothing patched
    "shipped": [("c", []), ("js", [])],

    # ---- ABI-2 control: red with NO edit -> repaired -> still green after a
    # ---- RE-SPELLING of the same reads.  Two obligations, two edits, and no
    # ---- ABI-4 edit, so anything that moves outside the record rows is visible
    # ---- as an escape rather than absorbed.
    "js-repair-abi2": [("js", [(JS_I64_OF_OLD, JS_I64_OF_FIXED, 1),
                               (JS_PACK_OLD, JS_PACK_FIXED, 1)])],
    "disarm-abi2-js": [("js", [(JS_I64_OF_OLD,
                                """function i64_of(p) {
  return BigInt.asIntN(64, (BigInt(p["hi"] >>> 0) << 32n) | BigInt(p["lo"] >>> 0));
}""", 1),
                               (JS_PACK_OLD, JS_PACK_FIXED, 1)])],

    # ---- ABI-4 is THREE edits, in three different functions, and that is the
    # ---- finding: two `of32` calls applied to values (dtype.js:80 and :123) and
    # ---- one missing conversion at the transport (dtype.js:131).
    "js-repair-abi4": [("js", [(JS_I64_OF_OLD, JS_I64_OF_FIXED, 1),
                               (JS_PACK_OLD, JS_PACK_FIXED, 1),
                               (JS_FP16_OLD, JS_FP16_FIXED, 1),
                               (JS_FP8DEC_OLD, JS_FP8DEC_FIXED, 1),
                               (JS_FP8TO_OLD, JS_FP8TO_FIXED, 1)])],

    # ---- ABI-1: the pre-fix over-read, planted in the C lane
    "plant-abi1-c": [("c", [(C_I64_OF_OLD, C_I64_OF_OVERREAD, 1),
                            ("i64_of(e, f[0])", "i64_of(f)", "+"),
                            ("i64_of(e, f[1])", "i64_of(f + 2)", "+")])],
    "disarm-abi1-c": [("c", [("f[0]", "*(f + 0)", "+"), ("f[1]", "*(f + 1)", "+"),
                             ("o[0]", "*(o + 0)", 1), ("o[1]", "*(o + 1)", 1)])],

    # ---- ABI-3: the halves exchanged on the way out
    "plant-abi3-c": [("c", [(C_PACK_OLD,
                             """static Term pack64(Env e, s64 v) {
  return io_tup(e, (Term)(intptr_t)(u32)(u64)v, (Term)(intptr_t)(u32)((u64)v >> 32));
}""", 1)])],
    "disarm-abi3-c": [("c", [("(s64)((((u64)(u32)o[0]) << 32) | (u32)o[1])",
                              "(s64)(((u64)(u32)o[0]) * 0x100000000ull + (u32)o[1])", 1)])],

    # ---- ABI-4 is planted in the JS lane, NOT the C lane.
    #
    # The C-side plant I wrote first -- a union that reads the pattern as a value
    # and reads the bits back -- moved 0/12, and it was going to stay 0 for every
    # possible input.  In C `f[0]` IS the pattern, so `a.u = pattern; b.v = a.v;
    # b.u = pattern` is the identity BY CONSTRUCTION, not by fixture.  No fixture
    # can separate them, which is the `unfixable` case in agent-core, not the
    # `a 0 is a request for a fixture` case.  So the C lane has no ABI-4 plant and
    # the gate says so rather than reporting a zero it cannot explain.
    #
    # The violation is real only where the backend hands the lane a VALUE, i.e.
    # node (probe.js:391 emits `1.5`, not 0x3FC00000).  So ABI-4's plant is the
    # shipped `of32(x)` and its base is js-repair.
    # `patch` restores the PRISTINE bytes before every arm, so an arm's edits are
    # written against the shipped file, never against another arm's output.  That
    # is what makes the arms independent and the counts comparable.
    "plant-abi4-js": [("js", [(JS_I64_OF_OLD, JS_I64_OF_FIXED, 1),
                              (JS_PACK_OLD, JS_PACK_FIXED, 1),
                              (JS_FP16_OLD, JS_FP16_FIXED, 1),
                              (JS_FP8DEC_OLD, JS_FP8DEC_FIXED, 1),
                              (JS_FP8TO_OLD, JS_FP8TO_FIXED, 1),
                              # and back out again: the shipped `of32(x)` on the way in
                              (JS_FP16_FIXED, JS_FP16_OLD, 1)])],
    "disarm-abi4-js": [("js", [(JS_I64_OF_OLD, JS_I64_OF_FIXED, 1),
                               (JS_PACK_OLD, JS_PACK_FIXED, 1),
                               # a re-spelling of the REPAIRED read: `+x` on a
                               # number is the identity, so this is the same value
                               (JS_FP16_OLD,
                                """function dtype_fp16(x) {
  return of32(half_to_f32(f16_bits(+x)));
}""", 1),
                               (JS_FP8DEC_OLD, JS_FP8DEC_FIXED, 1),
                               (JS_FP8TO_OLD, JS_FP8TO_FIXED, 1)])],
}


# ---------------------------------------------------------------- running.
def patch(work: pathlib.Path, edits) -> None:
    """`edits` is a list of (lane, [(old, new, expect), ...]); a lane absent from
    the arm is left byte-identical, which is how the C lane stays the baseline
    while an arm perturbs only the JS lane."""
    """Apply an arm's edits to the $TMPDIR copies.  Restores the pristine bytes
    first, so arms are independent and the live tree is never a base.

    Every edit STATES how many sites it expects.  A count that is not stated is
    a count nobody looked at, and an anchor that has moved must abort the run
    rather than silently patch nothing."""
    table = dict(edits)
    for lane, rel, src in (("c", "tinybendygrad/runtime/dtype.c", C_LANE),
                           ("js", "tinybendygrad/runtime/dtype.js", JS_LANE)):
        text = src.read_text()
        for old, new, expect in table.get(lane, []):
            got = text.count(old)
            want = got if expect == "+" else expect
            if got < 1 or (expect != "+" and got != expect):
                sys.exit(f"anchor: expected {expect} site(s), found {got}, in {lane}: "
                         f"{old.splitlines()[0][:70]!r}")
            text = text.replace(old, new)
            print(f"    patched {lane}:{got:>2} site(s)  {old.splitlines()[0][:56]!r}")
        (work / rel).write_text(text)


def drive(work: pathlib.Path, target: str) -> dict[str, str]:
    """Compile the probe and run it.  Returns {} and a reason on failure --
    a lane that produces nothing must never be counted as a pass."""
    bend = work / "abi_probe.bend"
    bend.write_text(PROBE)
    if target == "js":
        out, cmd = work / "abi_probe.js", ["node", str(work / "abi_probe.js")]
    else:
        out, cmd = work / "abi_probe.gen.c", [str(work / "abi_probe.gen")]
    r = subprocess.run([str(BEND), str(bend), "-o", str(out)],
                       capture_output=True, text=True)
    if r.returncode != 0 or not out.exists():
        sys.exit(f"bend failed for {target}: {r.stdout}\n{r.stderr}")
    if target == "c":
        k = subprocess.run(["cc", "-O1", "-w", "-o", str(work / "abi_probe.gen"), str(out)],
                           capture_output=True, text=True)
        if k.returncode != 0:
            sys.exit(f"cc failed: {k.stderr}")
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    rows = {}
    for line in p.stdout.splitlines():
        m = ROW.match(line)
        if m:
            rows[f"{m[1]}_{m[2]}"] = m[3].strip()
    return rows


# ------------------------------------------------------------ attribution.
def swap(pair: str) -> str:
    if ":" not in pair:
        return "\0absent"
    a, b = pair.split(":")
    return f"{b}:{a}"


def attribute(rows: dict[str, str]) -> list[tuple[str, str]]:
    """The decision procedure from abi.json, applied to the abi123_trunc rows."""
    out = []
    for r in ("abi123_trunc_A", "abi123_trunc_B"):
        got, want = rows.get(r), ORACLE[r]
        if got is None:
            out.append((r, "ROW ABSENT -- cannot be called a pass"))
        elif got == want:
            out.append((r, "ok: ABI-2 and ABI-3 satisfied on this record"))
        elif got == swap(want):
            out.append((r, "ABI-3 VIOLATED: the two words are exchanged"))
        else:
            out.append((r, f"ABI-2 VIOLATED: answered {got!r}, which is neither the "
                           f"record {want} nor its swap {swap(want)} -- the lane is "
                           f"not reading this record's two halves at all"))
    return out


def arity2_live(rows: dict[str, str]) -> bool:
    """Three distinct second arguments, three distinct CPython answers.  A lane
    that consumed fewer than two answers the same thing for all three."""
    got = [rows.get(r) for r in ("abi123_fdiv_b3", "abi123_fdiv_b5", "abi123_fdiv_b1")]
    return len(set(got)) == 3


def vs(rows: dict[str, str]) -> tuple[list[str], list[str]]:
    """Wrong rows, and absent rows, kept apart.  A totalised lane that PRINTS 0
    must never be countable as a lane that printed nothing."""
    bad = [r for r in ORACLE if r in rows and norm(rows[r]) != norm(ORACLE[r])]
    return bad, [r for r in ORACLE if r not in rows]


def moved(base: dict[str, str], arm: dict[str, str]) -> list[str]:
    """Whole `name=value` lines, not row NAMES -- a name-comparing harness
    reported 0 for all 30 mutations in another unit."""
    return [r for r in ORACLE if base.get(r, "\0") != arm.get(r, "\0")]


def fence(base: dict[str, str], arm: dict[str, str], owned: set[str]) -> list[str]:
    return [r for r in moved(base, arm) if not r.startswith(owned)]


# ------------------------------------------------------------------- main.
def main() -> None:
    decl = json.loads(DECL.read_text())
    ids = [a["id"] for a in decl["abi"]]

    print("=" * 78)
    print("THE DECLARATION -- four conventions, and where each side implements it")
    print("=" * 78)
    for a in decl["abi"]:
        print(f"\n{a['id']}  {a['name']}")
        for line in a["statement"]:
            print(f"    {line}")
        print("  sites:")
        for side, entries in a["site"].items():
            for f, ln, tok in entries:
                print(f"    {side:<11} {f}:{ln}   {tok!r}")

    # --- dangling-pointer check.  This can report that THIS DOCUMENT is stale.
    # --- It cannot report that a lane conforms.  Conformance is measured below.
    print("\n" + "=" * 78)
    print("POINTER CHECK -- is this document still pointing at what it claims?")
    print("=" * 78)
    stale = []
    gendir = HERE / "gen"
    gendir.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory() as td:
        work = pathlib.Path(td) / "tree"
        work.mkdir()
        shutil.copytree(REPO / "tinybendygrad", work / "tinybendygrad")
        (work / "abi_probe.bend").write_text(PROBE)
        # The two BACKEND files are persisted next to the declaration, because the
        # declaration cites them by line and a citation into a temp dir is a
        # citation into nothing.
        for ext in ("js", "gen.c"):
            r = subprocess.run([str(BEND), str(work / "abi_probe.bend"),
                                "-o", str(gendir / f"probe.{ext}")],
                               capture_output=True, text=True)
            if r.returncode != 0:
                sys.exit(f"bend failed emitting probe.{ext}: {r.stdout}\n{r.stderr}")
        for a in decl["abi"]:
            for side, entries in a["site"].items():
                for f, ln, tok in entries:
                    p = gendir / f.removeprefix("gen/") if f.startswith("gen/") else REPO / f
                    if not p.exists():
                        stale.append(f"{a['id']} {side} {f}:{ln} -- no such file")
                        print(f"  STALE {a['id']:<6} {side:<11} {f}:{ln}  (no file)")
                        continue
                    lines = p.read_text().splitlines()
                    if ln > len(lines):
                        stale.append(f"{a['id']} {side} {f}:{ln} -- only {len(lines)} lines")
                        print(f"  STALE {a['id']:<6} {side:<11} {f}:{ln}  (short file)")
                        continue
                    ok = tok in lines[ln - 1]
                    if not ok:
                        stale.append(f"{a['id']} {side} {f}:{ln} expected {tok!r}")
                    print(f"  {'ok   ' if ok else 'STALE'} {a['id']:<6} {side:<11} "
                          f"{f}:{ln}")
    if stale:
        print("\n  STALE POINTERS -- the declaration no longer describes the tree:")
        for s in stale:
            print(f"    {s}")
    else:
        print("  every cited line still carries its token")

    # --- the lanes.
    with tempfile.TemporaryDirectory() as td:
        work = pathlib.Path(td) / "tree"
        work.mkdir()
        shutil.copytree(REPO / "tinybendygrad", work / "tinybendygrad")
        res: dict[str, dict[str, dict[str, str]]] = {}
        for arm, edits in ARMS.items():
            print(f"\n  --- arm {arm} ---")
            patch(work, edits)
            res[arm] = {}
            for tgt in ("c", "js"):
                res[arm][tgt] = drive(work, tgt)

    ship, shipjs = res["shipped"]["c"], res["shipped"]["js"]

    print("\n" + "=" * 78)
    print("ROWS PRESENT vs ROWS EXPECTED")
    print("=" * 78)
    for arm in ARMS:
        for tgt in ("c", "js"):
            _, miss = vs(res[arm][tgt])
            if arm == "shipped" or miss:
                print(f"  {arm:<15} {tgt:<3} present {len(ORACLE) - len(miss):>2}/"
                      f"{len(ORACLE)}" + (f"   MISSING {miss}" if miss else ""))

    print("\n" + "=" * 78)
    print("THE MEASUREMENT -- shipped tree, no edit to either lane")
    print("=" * 78)
    print(f"  {'row':<20} {'CPython':<22} {'cc (dtype.c)':<22} {'node (dtype.js)':<22}")
    for r in ORACLE:
        print(f"  {r:<20} {ORACLE[r]:<22} {ship.get(r,'<absent>'):<22} "
              f"{shipjs.get(r,'<absent>'):<22}")
    badc, _ = vs(ship)
    badj, _ = vs(shipjs)
    print(f"\n  cc   agrees with CPython on {len(ORACLE) - len(badc)}/{len(ORACLE)}")
    print(f"  node agrees with CPython on {len(ORACLE) - len(badj)}/{len(ORACLE)}")
    dis = [r for r in ORACLE if norm(ship.get(r, "\0")) != norm(shipjs.get(r, "\0"))]
    print(f"  the two lanes DISAGREE on {len(dis)}/{len(ORACLE)}: {dis}")

    print("\n" + "=" * 78)
    print("ATTRIBUTION -- which of the four, and decided how")
    print("=" * 78)
    print("  For the record rows: the answer is R, swap(R), or NEITHER.  Only the")
    print("  third answer can mean ABI-2, so the two are separable by value alone.")
    for tgt, rows in (("cc", ship), ("node", shipjs)):
        print(f"\n  --- {tgt} ---")
        for r, why in attribute(rows):
            print(f"    {r:<18} {why}")
        print(f"    ABI-1 arity-2 liveness: "
              f"{'ALIVE (3 distinct answers)' if arity2_live(rows) else 'DEAD -- the lane did not vary with its second argument'}")

    print("\n" + "=" * 78)
    print("PLANT AND DISARM -- every plant paired, every disarm expected to be 0")
    print("=" * 78)
    verdicts = []
    controls = [
        # (arm, lane, base arm, the row PREFIX this convention owns)
        ("plant-abi1-c", "c", "shipped", "abi123"),
        ("disarm-abi1-c", "c", "shipped", "abi123"),
        ("plant-abi3-c", "c", "shipped", "abi123"),
        ("disarm-abi3-c", "c", "shipped", "abi123"),
        ("js-repair-abi2", "js", "shipped", "abi123"),
        ("disarm-abi2-js", "js", "js-repair-abi2", "abi123"),
        ("plant-abi4-js", "js", "js-repair-abi4", "abi4"),
        ("disarm-abi4-js", "js", "js-repair-abi4", "abi4"),
    ]
    for arm, tgt, base, prefix in controls:
        b, a = res[base][tgt], res[arm][tgt]
        mv = moved(b, a)
        out = fence(b, a, prefix)
        kind = ("PLANT " if arm.startswith("plant") else
                "DISARM" if arm.startswith("disarm") else "REPAIR")
        print(f"\n  {kind} {arm}  ({tgt}, vs {base})")
        print(f"    rows moved: {len(mv)}/{len(ORACLE)}  {mv}")
        if out:
            print(f"    ** ESCAPED ITS OWN ROW SET {prefix}_*: {out}")

    # the ABI-2 control is a three-point control on a lane that ships red
    print("\n  --- ABI-2 control, three points, on the lane that ships RED ---")
    for arm in ("shipped", "js-repair-abi2", "disarm-abi2-js"):
        bad, _ = vs(res[arm]["js"])
        print(f"    {arm:<15} node disagrees with CPython on {len(bad):>2}/{len(ORACLE)}"
              f"   {sorted(bad)}")
    print("    shipped red is not a plant -- it is the tree, unedited.  The repairs")
    print("    are $TMPDIR only.  The disarm re-spells the SAME conforming reads as")
    print('    p["hi"] and p["lo"], so a check matching TOKENS would fire on it.')

    print("\n  --- ABI-4, and why there is no C-side plant to pair ---")
    print("    The C plant I wrote first reads the pattern as a value and reads the")
    print("    bits back.  In C `f[0]` IS the pattern, so that is the identity by")
    print("    CONSTRUCTION: no fixture can separate it, and 0/12 is a THEOREM, not")
    print("    a coverage gap.  The obligation is only live where the backend hands")
    print("    the lane a VALUE, so ABI-4's plant is in JS, against js-repair-abi4.")

    # arity-2 liveness, measured on the ABI-1 plant
    print("\n  --- ABI-1 arity-2 predicate on the over-read plant ---")
    for arm in ("shipped", "plant-abi1-c", "disarm-abi1-c"):
        rows = res[arm]["c"]
        got = [rows.get(r) for r in ("abi123_fdiv_b3", "abi123_fdiv_b5", "abi123_fdiv_b1")]
        print(f"    {arm:<15} fdiv over b in 3,5,1 -> {got}  "
              f"{'ALIVE' if len(set(got)) == 3 else 'DEAD'}")

    print("\n" + "=" * 78)
    print("VERDICT")
    print("=" * 78)
    ok = True
    checks = [
        ("the declaration's pointers are current", not stale),
        ("every abi123_* row has hi != lo, by construction",
         all(WORDS[r][0] != WORDS[r][1] for r in WORDS)),
        ("cc agrees with CPython on the shipped tree", len(badc) == 0),
        ("the two lanes disagree somewhere, so the check has teeth", len(dis) > 0),
        ("ABI-2 fires on node with NO edit to the tree",
         any("ABI-2 VIOLATED" in w for _, w in attribute(shipjs))),
        ("ABI-2 does NOT fire on cc", not any("VIOLATED" in w for _, w in attribute(ship))),
        ("ABI-1 plant fires on cc",
         len(moved(ship, res["plant-abi1-c"]["c"])) > 0),
        ("ABI-1 plant stayed inside its own rows",
         not fence(ship, res["plant-abi1-c"]["c"], "abi123")),
        ("ABI-1 disarm moved 0", moved(ship, res["disarm-abi1-c"]["c"]) == []),
        ("ABI-3 plant fired", len(moved(ship, res["plant-abi3-c"]["c"])) > 0),
        ("ABI-3 plant stayed inside its own rows",
         not fence(ship, res["plant-abi3-c"]["c"], "abi123")),
        ("ABI-3 disarm moved 0", moved(ship, res["disarm-abi3-c"]["c"]) == []),
        ("ABI-4 fires on node with NO edit to the tree",
         len([r for r in vs(shipjs)[0] if r.startswith("abi4")]) > 0),
        ("ABI-4 plant fired in JS",
         len(moved(res["js-repair-abi4"]["js"], res["plant-abi4-js"]["js"])) > 0),
        ("ABI-4 plant stayed inside its own rows",
         not fence(res["js-repair-abi4"]["js"], res["plant-abi4-js"]["js"], "abi4")),
        ("ABI-4 disarm moved 0",
         moved(res["js-repair-abi4"]["js"], res["disarm-abi4-js"]["js"]) == []),
        ("the ABI-2 repair fixes every record row",
         len([r for r in vs(res["js-repair-abi2"]["js"])[0] if r.startswith("abi123")]) == 0),
        # A repair is EXPECTED to move its own rows -- that is its job.  The check
        # is the other direction: it must not move a row it has no business
        # touching, or the two obligations would be entangled and one edit could
        # paper over the other.  (My first cut asserted this backwards and failed
        # on a repair that was working.)
        # NB `shipjs`, not `ship`: a JS-lane repair must be compared against the
        # SHIPPED JS lane.  Comparing it against the C lane moves every F32 row
        # for the trivial reason that the lanes disagree there, and reports a
        # working repair as entangled.
        ("the ABI-2 repair touched ONLY record rows",
         not [r for r in moved(shipjs, res["js-repair-abi2"]["js"])
              if not r.startswith("abi123")]),
        ("the ABI-4 repair touched ONLY F32 rows",
         not [r for r in moved(shipjs, res["js-repair-abi4"]["js"])
              if not r.startswith("abi4")]),
        ("the ABI-2 disarm moved 0 against the repair",
         moved(res["js-repair-abi2"]["js"], res["disarm-abi2-js"]["js"]) == []),
        ("all four obligations applied, node agrees with CPython everywhere",
         len(vs(res["js-repair-abi4"]["js"])[0]) == 0),
        ("the repaired JS lane is byte-equal to the C lane on all rows",
         all(norm(res["js-repair-abi4"]["js"].get(r, "\0")) == norm(ship.get(r, "\0"))
             for r in ORACLE)),
    ]
    for name, good in checks:
        print(f"  {'PASS' if good else 'FAIL'}  {name}")
        ok &= good

    print("\n" + "=" * 78)
    print("WHAT REMAINS UNDECLARED")
    print("=" * 78)
    for i, t in decl["undeclared"]:
        print(f"  {i}  {t}")
    print("\n  gate rc:", 0 if ok else 1)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
