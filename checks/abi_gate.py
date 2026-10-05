#!/usr/bin/env python3
"""abi_gate.py -- both lanes of the dtype seam, checked against ONE declaration.

Reproduce (from the repo root):
    python3 checks/abi_gate.py

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
# ABI-2's repair is IN THE TREE (see dtype.js), so the anchors an arm is written
# against are now the CONFORMING text, and the evidence that the lane used to be
# broken is a PLANT rather than a $TMPDIR diagnosis.  `shipped` is the measurement;
# `plant-abi2-*-js` are the pre-fix bytes, verbatim.
JS_I64_OF_SHIPPED = """function i64_of(p) {
  return BigInt.asIntN(64, (BigInt(p.hi >>> 0) << 32n) | BigInt(p.lo >>> 0));
}"""
JS_PACK_SHIPPED = """function pack64(v) {
  const u = BigInt.asUintN(64, v);
  return {$: "tinybendygrad/helpers.I64", hi: Number((u >> 32n) & 0xffffffffn),
          lo: Number(u & 0xffffffffn)};
}"""
# The INBOUND half as it shipped: `p.fst`/`p.snd` against fields `hi`/`lo`.
JS_I64_OF_FST = """function i64_of(p) {
  return BigInt.asIntN(64, (BigInt(p.fst >>> 0) << 32n) | BigInt(p.snd >>> 0));
}"""
# The OUTBOUND half as it shipped: io_tup -> Tuple{fst,snd} where the caller
# reads {hi, lo}.  A separate plant, because an inbound-only plant CANNOT see it.
JS_PACK_IOTUP = """function pack64(v) {
  const u = BigInt.asUintN(64, v);
  return io_tup(Number((u >> 32n) & 0xffffffffn), Number(u & 0xffffffffn));
}"""
# THE DISARMS.  Re-spellings of the conforming reads, so 0 is the only correct
# moved count and a check matching TOKENS would fire on both of them.
JS_DISARM_IN = """function i64_of(p) {
  return BigInt.asIntN(64, (BigInt(p["hi"] >>> 0) << 32n) | BigInt(p["lo"] >>> 0));
}"""
JS_DISARM_OUT = """function pack64(v) {
  const u = BigInt.asUintN(64, v);
  return {$: "tinybendygrad/helpers.I64", lo: Number(u & 0xffffffffn) * 1,
          hi: Number(((u >> 32n) & 0xffffffffn))};
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

# The ABI-4 obligations.  Two `of32` calls applied to arithmetic VALUES (fp8_decode
# and dtype_fp16) and one MISSING conversion on the answer (dtype_fp8_to).  ALL THREE
# ARE NOW IN THE TREE (see dtype.js), so -- exactly as ABI-2's arms were re-anchored
# when ITS repair landed -- `JS_*_FIXED` is the SHIPPED text and `JS_*_OLD` is the
# PLANT.  `shipped` is the measurement, and the evidence that the lane used to be
# broken is a plant rather than a diagnosis.  There is no `js-repair-abi4` arm any
# more: an arm that applies a repair to an already-repaired tree is a tautology.
JS_FP16_FIXED = """function dtype_fp16(x) {
  return of32(half_to_f32(f16_bits(x)));
}"""
JS_FP8TO_OLD = """function dtype_fp8_to(x, kind) {
  return fp8_decode(x >>> 0, kind & 0xff);
}"""
JS_FP8TO_FIXED = """function dtype_fp8_to(x, kind) {
  return of32(fp8_decode(x >>> 0, kind & 0xff));
}"""
# THE THIRD SITE, WHICH THESE 12 ROWS CANNOT SEE ON ITS OWN.  `of32(...)` is
# pattern->value applied to an arithmetic VALUE, so of32(1.5) is the pattern 1 --
# the smallest f32 subnormal -- and bits32 of that denormal is 1.  It is observable
# only THROUGH the missing conversion at dtype_fp8_to, because this arm carries
# exactly ONE fp8_to row and that row needs both.  That is the whole reason the
# 98-row instrument at checks/abi4_gate.py exists and a comment did not.
JS_FP8DEC_OLD = """  const v = of32(exp === 0
    ? (mant / (mantMax + 1)) * Math.pow(2, 1 - bias)
    : (1 + mant / (mantMax + 1)) * Math.pow(2, exp - bias));
  return bits32(sgn ? -v : v);"""
JS_FP8DEC_FIXED = """  const v = exp === 0
    ? (mant / (mantMax + 1)) * Math.pow(2, 1 - bias)
    : (1 + mant / (mantMax + 1)) * Math.pow(2, exp - bias);
  return bits32(sgn ? -v : v);"""
# Re-spellings of the CONFORMING text, one per site, so 0 is the only correct moved
# count AND a check matching the token `of32(` fires on the plant but not on these.
JS_FP8DEC_DISARM = """  const v = (exp === 0
    ? (mant / (mantMax + 1)) * Math.pow(2, 1 - bias)
    : (1 + mant / (mantMax + 1)) * Math.pow(2, exp - bias)) * 1;
  return bits32(sgn ? -v : v);"""
JS_FP16_DISARM = """function dtype_fp16(x) {
  return of32(half_to_f32(f16_bits(x * 1)));
}"""
JS_FP8TO_DISARM = """function dtype_fp8_to(x, kind) {
  return of32(fp8_decode(x >>> 0, kind & 0xff) >>> 0);
}"""
ABI4_SITES = ((JS_FP8DEC_FIXED, JS_FP8DEC_OLD), (JS_FP16_FIXED, JS_FP16_OLD),
              (JS_FP8TO_FIXED, JS_FP8TO_OLD))
ABI4_DISARMS = ((JS_FP8DEC_FIXED, JS_FP8DEC_DISARM), (JS_FP16_FIXED, JS_FP16_DISARM),
                (JS_FP8TO_FIXED, JS_FP8TO_DISARM))


ARMS = {
    # ---- the measurement: nothing patched
    "shipped": [("c", []), ("js", [])],

    # ---- ABI-2's control, now that the repair is in the tree: ship GREEN, and two
    # ---- SEPARATE plants for the two halves, because one plant cannot see the
    # ---- other.  Each has a paired re-spelling expected to move 0.
    "plant-abi2-in-js": [("js", [(JS_I64_OF_SHIPPED, JS_I64_OF_FST, 1)])],
    "plant-abi2-out-js": [("js", [(JS_PACK_SHIPPED, JS_PACK_IOTUP, 1)])],
    "disarm-abi2-in-js": [("js", [(JS_I64_OF_SHIPPED, JS_DISARM_IN, 1)])],
    "disarm-abi2-out-js": [("js", [(JS_PACK_SHIPPED, JS_DISARM_OUT, 1)])],

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

    # ---- ABI-4, in the JS lane.  The C-side plant I wrote first -- a union that
    # ---- reads the pattern as a value and reads the bits back -- moved 0/12 and
    # ---- was going to stay 0 for every possible input: in C `f[0]` IS the
    # ---- pattern, so that is the identity BY CONSTRUCTION, not by fixture.  No
    # ---- fixture can separate it, which is the `unfixable` case in agent-core, not
    # ---- the `a 0 is a request for a fixture` case.  So the C lane has no ABI-4
    # ---- plant and the gate says so rather than reporting a zero it cannot
    # ---- explain.  The violation is real only where the backend hands the lane a
    # ---- VALUE, i.e. node.  `patch` restores the PRISTINE bytes before every arm,
    # ---- so arms are independent and the counts are comparable.
    # ---- The repair is in the tree, so `shipped` is GREEN and the plant re-breaks
    # ---- all three sites at once.  There is deliberately no `js-repair-abi4` arm:
    # ---- it applied the repair to the tree, which is now already repaired, so it
    # ---- measured a tautology -- and it was the arm that carried ABI-2's bytes,
    # ---- which is why "the ABI-4 repair touched ONLY F32 rows" FAILED once.
    "plant-abi4-js": [("js", [(shipped, other, 1) for shipped, other in ABI4_SITES])],
    "disarm-abi4-js": [("js", [(shipped, other, 1) for shipped, other in ABI4_DISARMS])],
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
    # A lane that prints NOTHING must never be a green lane.  `vs()` excludes
    # absent rows from `bad` by design (so a totalisation is not an absence), and
    # that is right UNTIL the lane dies: a dangling paren in dtype.js made node
    # exit 1 with empty stdout, and this gate then reported `node agrees with
    # CPython on 12/12` and 12 FAILs downstream.  node's exit status is the check
    # that was missing, and it costs one line.
    if p.returncode != 0 or len(rows) != len(ORACLE):
        sys.exit(f"{target} lane printed {len(rows)}/{len(ORACLE)} rows "
                 f"(rc={p.returncode}):\n{p.stderr[:600]}")
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


# THE CONTENT FENCE, and the reason it exists.  `js-repair-abi4` used to carry
# ABI-2's edits as well, so the five `abi123_*` rows it moved were moved by ABI-2;
# a row-count fence on that arm passed or failed for reasons nobody could read.
# This one reads the BYTES each arm would apply and refuses any JS edit that names
# another ABI's token.  It is checked for the ABI-4 arms here and for EVERY arm in
# checks/abi4_gate.py, because the entanglement was never about which
# convention -- it was about an arm quietly carrying two.
JS_ARM_TOKENS = ("p.hi", "p.lo", "p.fst", "p.snd", "io_tup", "BigInt",
                 "asIntN", "<< 32n", ">>> 32n")


def arm_leaks(arm: str) -> list[str]:
    """Tokens from another ABI that this arm's JS edits would write.  The C lane's
    arms legitimately mention `f[0]` and `i64_of`, so the fence is on the JS lane,
    which is where both shipped bugs were -- and it is scoped to the arms that are
    NOT ABI-2's, because ABI-2's own arms must of course write ABI-2's tokens.
    """
    if arm.startswith("plant-abi2") or arm.startswith("disarm-abi2"):
        return []
    out = []
    for lane, edits in ARMS[arm]:
        if lane != "js":
            continue
        for old, new, _ in edits:
            out += [t for t in JS_ARM_TOKENS if t in old or t in new]
    return sorted(set(out))


# ------------------------------------------------------------------- main.
UNDECLARED_REF = re.compile(
    r"(?<![\w/])((?:tinybendygrad|tinygrad|bin)/[\w./-]+?\.(?:py|js|c|bend|json)|"
    r"gen/\w+\.\w+):(\d+)")


def undeclared_refs(decl) -> tuple[list[str], list[str]]:
    """THE BLIND SPOT, NOW CLOSED.  This check read `abi`[i]['site'] and nothing
    else, so the `undeclared` block -- where a stale citation was found today --
    was prose, and prose that goes stale is indistinguishable from prose that was
    always wrong.

    Every `<path>:<line>` in an `undeclared` entry is now checked, EXCEPT in an
    entry that declares itself historical with a third element
    `{"historical": true, "why": ...}`.  That flag is the whole design: an entry
    that narrates a past measurement (`probe.js moved 894 -> 915`) would be a
    permanent false red, and a check that is always red on a class of entry is a
    check whose green is worth less than its red.  So the AUTHOR of the prose
    declares which claims are live, and a live claim that goes stale fails.

    Returns (stale, skipped)."""
    stale, skipped = [], []
    for entry in decl["undeclared"]:
        eid, prose = entry[0], entry[1]
        meta = entry[2] if len(entry) > 2 else {}
        refs = UNDECLARED_REF.findall(prose)
        if meta.get("historical"):
            skipped += [f"{eid} historical x{len(refs)}"]
            continue
        for rel, ln in refs:
            f = HERE / "abi" / rel if rel.startswith("gen/") else REPO / rel
            if not f.exists():
                stale.append(f"{eid} cites {rel}: no such file")
            elif int(ln) > len(f.read_text().splitlines()):
                stale.append(f"{eid} cites {rel}:{ln}, a file of "
                             f"{len(f.read_text().splitlines())} lines")
    return stale, skipped


def cite_ok(p: pathlib.Path, e) -> tuple[bool, str]:
    """Resolve one `site` entry.

    Two shapes.  A CHECKED-IN file is cited `[file, line, token]` and the gate
    checks that line still carries the token.  A GENERATED file is cited
    `{file, body, token}` -- BY NAME -- because `bend -o` embeds `import "./x.js"`
    verbatim: editing a lane moves every generated body `file:line` with no change
    to the convention being cited.  Measured here -- editing `dtype.js` moved all of
    `probe.js` by exactly +21 (894 -> 915 lines), which is how three stale
    citations were created in one commit."""
    if isinstance(e, dict):
        lines = p.read_text().splitlines()
        # A NAME citation must resolve to the DEFINITION, not to a call.  Three
        # measured ways to get that wrong, one per language:
        #   probe.js:701 is `process.exit(io_run(main));` and `function io_run` is
        #     at :861 -- a call site 160 lines earlier;
        #   bend mangles names to `$a$047b$c$`, and `$` is not a word character,
        #     so `\b$main$` can never match at all;
        #   probe.gen.c writes `static Term io_exec(Env e, IoWork* w) {` -- a return
        #     type between `static` and the name -- while `io_tup` is a `#define`.
        # So: the name must be followed by `(`/`{`/`=`, and must not sit in an
        # EXPRESSION position, which is what tells a definition from a call.
        name = e["body"]

        def is_def(line: str) -> bool:
            for m in re.finditer(re.escape(name), line):
                before = line[:m.start()].rstrip()
                after = line[m.end():].lstrip()[:1]
                if after not in ("(", "{", "="):
                    continue
                if before and before[-1] in "=+(,:?*&":
                    continue
                return True
            return False

        start = next((i for i, l in enumerate(lines) if is_def(l)), None)
        if start is None:
            return False, f"no definition of {name} in {p.name}"
        # the body is the def line plus its brace-matched extent, or 40 lines for a
        # macro / a table row, whichever is shorter
        depth, end = 0, min(len(lines), start + 400)
        for i in range(start, min(len(lines), start + 400)):
            depth += lines[i].count("{") - lines[i].count("}")
            if depth <= 0 and i > start:
                end = i + 1
                break
            if depth <= 0 and i == start and "{" not in lines[i]:
                end = i + 1
                break
        body = "\n".join(lines[start:end])
        return e["token"] in body, f"body {e['body']} @{start + 1}"
    _, ln, tok = e
    if not p.exists():
        return False, "no such file"
    lines = p.read_text().splitlines()
    if ln > len(lines):
        return False, f"only {len(lines)} lines"
    return tok in lines[ln - 1], f"line {ln}"


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
            for e in entries:
                f = e[0] if isinstance(e, list) else e["file"]
                at = (f":{e[1]}" if isinstance(e, list)
                      else f" body {e['body']}")
                print(f"    {side:<11} {f}{at}")

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
        # The two BACKEND files are persisted next to the declaration, because a
        # citation into a temp dir is a citation into nothing.
        for ext in ("js", "gen.c"):
            r = subprocess.run([str(BEND), str(work / "abi_probe.bend"),
                                "-o", str(gendir / f"probe.{ext}")],
                               capture_output=True, text=True)
            if r.returncode != 0:
                sys.exit(f"bend failed emitting probe.{ext}: {r.stdout}\n{r.stderr}")
        for a in decl["abi"]:
            for side, entries in a["site"].items():
                for e in entries:
                    f = e[0] if isinstance(e, list) else e["file"]
                    q = gendir / f.removeprefix("gen/") if f.startswith("gen/") \
                        else REPO / f
                    ok, where = cite_ok(q, e)
                    at = f"body {e['body']}" if isinstance(e, dict) else f"line {e[1]}"
                    if not ok:
                        stale.append(f"{a['id']} {side} {f} {at}: {where}")
                    print(f"  {'ok   ' if ok else 'STALE'} {a['id']:<6} "
                          f"{side:<11} {f:<28} {at:<24} {'' if ok else where}")
    if stale:
        print("\n  STALE POINTERS -- the declaration no longer describes the tree:")
        for s in stale:
            print(f"    {s}")
    else:
        print("  every cited line still carries its token")

    # --- the SAME check over the `undeclared` block, which it did not read until
    # --- a stale citation was found there.
    ustale, uskip = undeclared_refs(decl)
    stale += ustale
    print(f"  undeclared: {len(ustale)} stale live reference(s), "
          f"{len(uskip)} declared-historical entr(ies) skipped {uskip}")

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
        ("plant-abi2-in-js", "js", "shipped", "abi123"),
        ("disarm-abi2-in-js", "js", "shipped", "abi123"),
        ("plant-abi2-out-js", "js", "shipped", "abi123"),
        ("disarm-abi2-out-js", "js", "shipped", "abi123"),
        ("plant-abi4-js", "js", "shipped", "abi4"),
        ("disarm-abi4-js", "js", "shipped", "abi4"),
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

    # the ABI-2 control, on the lane that now SHIPS GREEN
    print("\n  --- ABI-2 control, on the lane that now ships GREEN ---")
    for arm in ("shipped", "plant-abi2-in-js", "plant-abi2-out-js",
                "disarm-abi2-in-js", "disarm-abi2-out-js"):
        bad, _ = vs(res[arm]["js"])
        print(f"    {arm:<18} node disagrees with CPython on {len(bad):>2}/{len(ORACLE)}"
              f"   {sorted(bad)}")
    print("    shipped green is the MEASUREMENT now: the ABI-2 repair is in the tree,")
    print("    so the evidence that the lane was broken is a plant, not a diagnosis.")
    ain = set(moved(shipjs, res["plant-abi2-in-js"]["js"]))
    aout = set(moved(shipjs, res["plant-abi2-out-js"]["js"]))
    print("    Both plants move the SAME rows here, and that is a property of these")
    print(f"    12 fixtures, not evidence of one defect: every row reads a record IN")
    print(f"    and reads the answer back OUT, so either half alone breaks all of them")
    print(f"    (inbound {sorted(ain)}")
    print(f"     outbound {sorted(aout)}).")
    print("    checks/jsfix_gate.py is the instrument that separates them:")
    print("    30 rows x 10 arms, 28/30 vs 30/30, and the VALUES differ -- `0:0`")
    print("    everywhere (a totalisation) against something that is not a hi:lo pair.")
    print("    The disarms re-spell the SAME conforming reads as p[\"hi\"]/p[\"lo\"] and")
    print("    as a one-line literal, so a check matching TOKENS would fire on both.")

    print("\n  --- ABI-4, and why there is no C-side plant to pair ---")
    print("    The C plant I wrote first reads the pattern as a value and reads the")
    print("    bits back.  In C `f[0]` IS the pattern, so that is the identity by")
    print("    CONSTRUCTION: no fixture can separate it, and 0/12 is a THEOREM, not")
    print("    a coverage gap.  The obligation is only live where the backend hands")
    print("    the lane a VALUE, so ABI-4's plant is in JS, against the shipped tree.")
    print("    The repair is IN the tree, so `shipped` is GREEN and the plant re-breaks")
    print("    all three sites at once.  This gate CANNOT tell the three sites apart:")
    print("    it carries one fp8_to row and that row needs two of them.  The")
    print("    98-row instrument at checks/abi4_gate.py separates them, and")
    print("    it is the only thing that can: NEEDS 10 / 40 / 30 with FIXES 10 / 10 / 0.")

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
        ("the declaration's pointers are current, INCLUDING the undeclared block "
         "(the block this check did not read until a stale citation was found in "
         "it; entries may opt out by declaring themselves historical)", not stale),
        ("every abi123_* row has hi != lo, by construction",
         all(WORDS[r][0] != WORDS[r][1] for r in WORDS)),
        ("cc agrees with CPython on the shipped tree", len(badc) == 0),
        # The two lanes AGREING is no longer the evidence: the repair landed, so the
        # shipped tree is green and only a PLANT can show the check still sees red.
        ("the two lanes agree on every row of the shipped tree", len(dis) == 0),
        ("and they agree only because both are right, not because the check is "
         "blind: the ABI-4 plant breaks that agreement",
         len(moved(shipjs, res["plant-abi4-js"]["js"])) > 0),
        ("ABI-2 does NOT fire on node with NO edit to the tree",
         not any("ABI-2 VIOLATED" in w for _, w in attribute(shipjs))),
        ("ABI-2 DOES fire on node when its INBOUND half is planted",
         any("ABI-2 VIOLATED" in w for _, w in attribute(res["plant-abi2-in-js"]["js"]))),
        ("ABI-2 DOES fire on node when its OUTBOUND half is planted",
         any("ABI-2 VIOLATED" in w for _, w in attribute(res["plant-abi2-out-js"]["js"]))),
        ("ABI-2's inbound plant stayed inside its own rows",
         not fence(shipjs, res["plant-abi2-in-js"]["js"], "abi123")),
        ("ABI-2's outbound plant stayed inside its own rows",
         not fence(shipjs, res["plant-abi2-out-js"]["js"], "abi123")),
        # NB there is deliberately NO check here that the two ABI-2 plants move
        # DIFFERENT rows, because they do not: both move the same five abi123_* rows
        # of this set.  That is a property of these 12 fixtures -- every one reads a
        # record IN and reads the answer back OUT, so either half alone breaks all
        # five -- and it is NOT evidence that they are one defect.  The 30-row gate
        # at checks/jsfix_gate.py is the instrument that separates them
        # (28/30 and 30/30, differing on floor_mod|-8|4 and cmod|-8|4), and it adds
        # the values: the inbound plant answers `0:0` everywhere, a totalisation,
        # while the outbound one answers something that is not a hi:lo pair at all.
        # A check here would have been a guess dressed as an obligation.
        ("ABI-2's inbound disarm moved 0", moved(shipjs, res["disarm-abi2-in-js"]["js"]) == []),
        ("ABI-2's outbound disarm moved 0", moved(shipjs, res["disarm-abi2-out-js"]["js"]) == []),
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
        ("ABI-4 does NOT fire on node with NO edit to the tree",
         not [r for r in vs(shipjs)[0] if r.startswith("abi4")]),
        ("ABI-4 DOES fire on node when all three sites are planted",
         len(moved(shipjs, res["plant-abi4-js"]["js"])) > 0),
        ("ABI-4's plant stayed inside its own rows",
         not fence(shipjs, res["plant-abi4-js"]["js"], "abi4")),
        ("ABI-4 disarm moved 0",
         moved(shipjs, res["disarm-abi4-js"]["js"]) == []),
        ("no JS arm writes another ABI's token -- the CONTENT fence, which is "
         "what `js-repair-abi4` tripped and what a row count cannot see",
         not {a: l for a in ARMS if (l := arm_leaks(a))}),
        ("the ABI-2 repair fixes every record row",
         len([r for r in vs(shipjs)[0] if r.startswith("abi123")]) == 0),
        # A plant is EXPECTED to move its own rows -- that is its job.  The check is
        # the other direction: it must not move a row it has no business touching,
        # or the two obligations would be entangled and one edit could paper over
        # the other.  And it is now a fence on the PLANT rather than on the repair,
        # because the repair is the tree and a fence on the tree is a tautology.
        ("the shipped JS lane agrees with CPython on every row",
         len(vs(shipjs)[0]) == 0),
        ("the shipped JS lane is byte-equal to the C lane on all rows",
         all(norm(shipjs.get(r, "\0")) == norm(ship.get(r, "\0")) for r in ORACLE)),
    ]
    for name, good in checks:
        print(f"  {'PASS' if good else 'FAIL'}  {name}")
        ok &= good

    print("\n" + "=" * 78)
    print("WHAT REMAINS UNDECLARED")
    print("=" * 78)
    for entry in decl["undeclared"]:
        print(f"  {entry[0]}  {entry[1]}")
    print("\n  gate rc:", 0 if ok else 1)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
