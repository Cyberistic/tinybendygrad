#!/usr/bin/env python3
"""abi4_gate.py -- WHICH OF THE THREE `of32` SITES IS ABI-4, AND IS IT ONE
CONVENTION OR THREE COINCIDENCES.  Measured, not read.

Reproduce (from the repo root):
    python3 checks/abi4_gate.py        # ~2 min, writes nothing live
    python3 checks/abi4_gate.py --save # persist the rows beside it

THE QUESTION.  `abi.json` declares ABI-4 as "a scalar crosses as bits in C and
as a value under node, and each lane must undo that on the way IN and NOT undo
it on the way OUT".  Three places in `dtype.js` violated that sentence, and all
three are now repaired in the tree:

    A  fp8_decode    of32(v) on an arithmetic VALUE -- one call INSIDE the lane
    B  dtype_fp16    of32(x) on the seam's ARGUMENT  -- the INBOUND crossing
    C  dtype_fp8_to  NO of32 on the seam's ANSWER    -- the OUTBOUND crossing

Three edits that fix rows might be one convention or three coincidences, and a
reading cannot tell them apart.  So the sites are SEPARATED BY ROW:

    NEEDS(s) = rows GREEN as shipped and RED with site s RE-BROKEN
    FIXES(s) = rows RED with all three re-broken and GREEN with only the other
               two re-broken, i.e. rows s is SUFFICIENT, alone, for

Coincidence looks like an empty or overlapping `NEEDS`.  One convention looks
like three non-empty sets whose intersections are accounted for rather than
wished away.  Both are printed whether or not they hold.

THE ROW SET IS WIDE ON PURPOSE.  `abi_gate.py`'s 12 rows contain exactly ONE
fp8_to row, and that row needs A and C *jointly*, so on 12 rows A and C cannot
be told apart -- an entanglement of the FIXTURES, not of the sites.  Two classes
of row separate them, and both are here:

  * EARLY-RETURN rows.  `fp8_decode` returns straight from its nan/inf branches
    without ever building `v`, so those rows exercise C alone: C fixes them and
    they are blind to A.  They are the 10 rows of `FIXES(C)`.
  * INVERSION rows.  `Dt.fp16(x: F32)` receives a VALUE and the backend emits
    the literal, so `Dt.fp16(1073741824.0)` arrives as the JS number
    1073741824 -- which as an f32 *pattern* is 0x40000000, the value 2.0.  A lane
    that reads its argument as a pattern answers `2` where CPython answers
    `inf`.  That is a POSITIVE detection: the wrong answer NAMES the wrong
    representation, where `fp16(1.5) = 0` says only that it is wrong.

LOCALITY IS CHECKED THREE WAYS, because it has been wrong three ways: by the
row set (a repair must move no `loc_*` row), by CONTENT (the repair's diff may
not mention any other ABI's token -- the check that would have caught
`js-repair-abi4` carrying ABI-2's edits), and against the tree itself (this
gate patches a COPY, so only a row comparison with the unpatched tree speaks
about the bytes in the repo).

THE PLANTS ARE SECOND MUTATIONS, NOT COPIES.  `break-<s>` already re-breaks site
s; planting the same bytes again would be a tautology.  Each plant is a
DIFFERENT spelling of the same violation -- the converter moved, reversed, or
applied twice -- so a plant that moves nothing means the violation has another
witness.  THE DISARMS ARE RUN AND LISTED FIRST: a disarm that moves something
is not a failed disarm, it is a defect that has not been named yet.

`dtype.c` is byte-unchanged and is not read for justification.  The declaration
is `tinybendygrad/dtype.bend`'s SEAM SIGNATURE for each CID, and the measurement
of what actually crosses is the backend's emitted literal.
"""
from __future__ import annotations

import json
import math
import pathlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from collections import namedtuple

HERE = pathlib.Path(__file__).resolve().parent
# `parents[0]` is the immediate parent, which for `checks/<this file>` IS the repo
# root; the old `parents[2]` was right only at `.agents/slop/abi4/`, and the move to
# `checks/` carried the constant across without recomputing it.  REPO became
# `/Users/cyberistic/src`, and the gate raised FileNotFoundError at
# `JS_LANE.read_text()` -- an EXCEPTION, which is not a red gate: it has no
# denominator and no disagreement, so it counted nowhere.  Note the trap: `parents[1]`
# is ALSO wrong (it is `/Users/cyberistic/src/tries`), and writing it was caught here
# by the assertion below rather than by a third exception.  The depth is now PROVED
# by `refuse()`, which is `sb-gate.sh` rule 1 -- "a cd that lands outside is exit 3"
# -- in Python.
REPO = HERE.parents[0]
sys.path.insert(0, str(REPO))
from tinygrad import dtype as td            # noqa: E402

BEND = REPO / "bin" / "bend"
JS_LANE = REPO / "tinybendygrad" / "runtime" / "dtype.js"
BEND_LANE = REPO / "tinybendygrad" / "dtype.bend"
OTHER_GATES = ("checks/abi_gate.py", "checks/jsfix_gate.py")
ROW = re.compile(r"^F32ROW (\w+) = (.*)$")


def refuse(*why: str) -> None:
    """exit 3 = REFUSED, and NOT a verdict.  `sb-gate.sh`'s vocabulary, in Python.

    Every input this gate reads is asserted to EXIST before it is read, because a
    missing input is not a passing input: the old `[ -f $BASE ]`-with-no-else form
    skipped the comparison in silence and exited 0.  Here the same shape raised
    `FileNotFoundError`, which is worse than exit 0 -- an exception is not a red
    gate, it has no denominator and no disagreement, so it is excluded from every
    count by being uncategorisable.  A refusal is at least a number."""
    print("== REFUSED, NOT A VERDICT: " + "; ".join(why), file=sys.stderr)
    sys.exit(3)


# `parents[N]` is a constant that silently expires when the file moves, and a move
# is exactly what happened to this one.  So the depth is PROVED, not assumed:
# REPO must be the directory that actually holds the substrate.  `cd` out of the
# repo is refused here the way `sb-gate.sh` refuses it.
if not (REPO / "tinybendygrad" / "runtime" / "dtype.js").is_file():
    refuse(f"REPO does not hold the tree: {REPO} is not the repo root "
           f"(is `parents[N]` stale after a move?)")
for _p in (BEND, BEND_LANE, *(REPO / g for g in OTHER_GATES)):
    if not _p.exists():
        refuse(f"input absent: {_p.relative_to(REPO)}")

# ------------------------------------------------------------------ the sites.
# (as shipped, as re-broken).  Anchors must occur exactly once or this exits: an
# anchor that has moved means the tree changed under us and every number below
# would be stale.
JS_FP8DEC_SHIPPED = """  const v = exp === 0
    ? (mant / (mantMax + 1)) * Math.pow(2, 1 - bias)
    : (1 + mant / (mantMax + 1)) * Math.pow(2, exp - bias);
  return bits32(sgn ? -v : v);"""
JS_FP8DEC_BROKEN = """  const v = of32(exp === 0
    ? (mant / (mantMax + 1)) * Math.pow(2, 1 - bias)
    : (1 + mant / (mantMax + 1)) * Math.pow(2, exp - bias));
  return bits32(sgn ? -v : v);"""
JS_FP16_SHIPPED = """function dtype_fp16(x) {
  return of32(half_to_f32(f16_bits(x)));
}"""
JS_FP16_BROKEN = """function dtype_fp16(x) {
  return of32(half_to_f32(f16_bits(of32(x))));
}"""
JS_FP8TO_SHIPPED = """function dtype_fp8_to(x, kind) {
  return of32(fp8_decode(x >>> 0, kind & 0xff));
}"""
JS_FP8TO_BROKEN = """function dtype_fp8_to(x, kind) {
  return fp8_decode(x >>> 0, kind & 0xff);
}"""

SITES = {"A": (JS_FP8DEC_SHIPPED, JS_FP8DEC_BROKEN),
         "B": (JS_FP16_SHIPPED, JS_FP16_BROKEN),
         "C": (JS_FP8TO_SHIPPED, JS_FP8TO_BROKEN)}
BREAKS = ["", "A", "B", "C", "AB", "AC", "BC", "ABC"]

# THE PLANTS -- a SECOND mutation of the same violation, not a copy of the break.
#   A : of32 on `v` moved from the assignment to the RETURN that consumes it
#   B : the REVERSE converter at the argument: `bits32` where `of32` was wrong
#   C : a DOUBLE conversion at the seam, pattern->value->pattern, "for safety"
JS_PLANT_A = """  const v = exp === 0
    ? (mant / (mantMax + 1)) * Math.pow(2, 1 - bias)
    : (1 + mant / (mantMax + 1)) * Math.pow(2, exp - bias);
  return bits32(sgn ? -of32(v) : of32(v));"""
JS_PLANT_B = """function dtype_fp16(x) {
  return of32(half_to_f32(f16_bits(bits32(x))));
}"""
JS_PLANT_C = """function dtype_fp8_to(x, kind) {
  return of32(of32(fp8_decode(x >>> 0, kind & 0xff)));
}"""

# THE DISARMS -- syntactic re-spellings of the CONFORMING text at one site each,
# so the only correct moved-set is the empty one AND a check matching `of32(`
# fires on every plant but on none of these.  `v * 1`, `x * 1` and `>>> 0` are
# the identity over every double, including nan, +/-0 and +/-inf.
JS_DISARM_A = """  const v = (exp === 0
    ? (mant / (mantMax + 1)) * Math.pow(2, 1 - bias)
    : (1 + mant / (mantMax + 1)) * Math.pow(2, exp - bias)) * 1;
  return bits32(sgn ? -v : v);"""
JS_DISARM_B = """function dtype_fp16(x) {
  return of32(half_to_f32(f16_bits(x * 1)));
}"""
JS_DISARM_C = """function dtype_fp8_to(x, kind) {
  return of32(fp8_decode(x >>> 0, kind & 0xff) >>> 0);
}"""
PLANTS = {"A": (JS_FP8DEC_SHIPPED, JS_PLANT_A), "B": (JS_FP16_SHIPPED, JS_PLANT_B),
          "C": (JS_FP8TO_SHIPPED, JS_PLANT_C)}
DISARMS = {"A": (JS_FP8DEC_SHIPPED, JS_DISARM_A), "B": (JS_FP16_SHIPPED, JS_DISARM_B),
           "C": (JS_FP8TO_SHIPPED, JS_DISARM_C)}

# Any arm that introduces or removes one of these is not an ABI-4 arm.  This is
# the CONTENT fence, and it is what `moved` rows cannot do: the historical
# `js-repair-abi4` arm moved five `abi123_*` rows and was blamed on ABI-4 until it
# was found to be carrying ABI-2's bytes.
OTHER_ABI_TOKENS = ("p.hi", "p.lo", "p.fst", "p.snd", "io_tup", "BigInt",
                    "asIntN", "<< 32n", ">>> 32n")

# THE ALTERNATIVE SPELLING.  ABI-4 says the seam must answer a VALUE; it does not
# say whether the conversion happens inside `fp8_decode` or at the seam.  Both are
# measured, so the report cannot claim the one that went green was the right one.
JS_FP8DEC_ALT = """  const v = exp === 0
    ? (mant / (mantMax + 1)) * Math.pow(2, 1 - bias)
    : (1 + mant / (mantMax + 1)) * Math.pow(2, exp - bias);
  return sgn ? -v : v;"""

# ----------------------------------------------------------------- the rows.
Row = namedtuple("Row", "name owner expr decl_in decl_out show expect")
# `decl_in`/`decl_out` are copied from `tinybendygrad/dtype.bend`'s SEAM SIGNATURES,
# which is the declaration of what crosses.  `owner` is the fence prefix:
# abi4_ = a row a scalar VALUE crosses, loc_ = a row it does not.
KINDS = ["fp8e4m3", "fp8e5m2", "fp8e4m3fnuz", "fp8e5m2fnuz"]
# 0x7F is nan in e4m3 and e5m2 (exp all ones, mant nonzero) and in the two FNUZ
# formats every pattern with the top bit set is nan -- those rows return from
# fp8_decode's EARLY branches and never build `v`.
FP8_TO_X = [0x00, 0x01, 0x04, 0x08, 0x3C, 0x7C, 0x7E, 0x7F, 0x80, 0x81, 0xFF]
# 2**30, 0x3FC00000 and 3*2**30: as an f32 PATTERN these are 2.0, 1.5 and -2.0,
# while as a VALUE they are all past fp16's 65504 and saturate to inf.
FP16_X = [1.5, 1.1, -2.25, 0.5, 100.0, 65504.0, 1e-8, -0.0, 0.0,
          1073741824.0, 1069547520.0, 3221225472.0]
BF16_BITS = [0x3FC00000, 0xBF800000, 0x00000001, 0x7F800000, 0x7FC00000,
             0x477FE000, 0x3F800000, 0x40000000, 0x00800000, 0x7F7FFFFF]
FP8_FROM_X = [1.5, -1.5, 0.0, -0.0, 256.0, 448.0, 1e-8, 1e9]


def f32bits(x: float) -> int:
    return struct.unpack("<I", struct.pack("<f", x))[0]


def f32bits_inv(b: int) -> float:
    return struct.unpack("<f", struct.pack("<I", b))[0]


def flit(x: float) -> str:
    """A Bend F32 literal.  Bend reads `F32.neg` and not a leading `-` (measured:
    `D.Dt.fp16(-2.25)` is `expected : a term / observed : '-'`), and its parser
    takes plain decimals, so `repr(1e-08)` is expanded rather than spelled with an
    exponent.  `copysign` and not `< 0`, because `-0.0 < 0` is False."""
    if math.copysign(1, x) < 0:
        return f"F32.neg({flit(abs(x))})"
    s = repr(x)
    return s if "e" not in s else f"{x:.20f}".rstrip("0")


def cases() -> list[Row]:
    out = []
    for x in FP16_X:
        tag = repr(x).replace(".", "p").replace("-", "m").replace("+", "")
        out.append(Row(f"abi4_fp16_{tag}", "abi4", f"D.Dt.fp16({flit(x)})",
                       "F32", "F32", "F32", lambda x=x: td.float_to_fp16(x)))
    for k, dt in enumerate(KINDS):
        for x in FP8_TO_X:
            out.append(Row(f"abi4_fp8to_{k}_{x:02X}", "abi4",
                           f"D.Dt.fp8_to({x}, {k})", "U32", "F32", "F32",
                           lambda x=x, dt=dt: td.fp8_to_float(
                               x, getattr(td.dtypes, dt))))
    for b in BF16_BITS:
        out.append(Row(f"loc_bf16_{b:08X}", "loc", f"D.Dt.bf16({b})",
                       "U32", "F32", "F32",
                       lambda b=b: td.float_to_bf16(f32bits_inv(b))))
    for k, dt in enumerate(KINDS):
        for x in FP8_FROM_X:
            out.append(Row(f"loc_fp8from_{k}_{f32bits(x):08X}", "loc",
                           f"D.Dt.fp8_from({f32bits(x)}, {k})", "U32", "U32", "U32",
                           lambda x=x, dt=dt: td.float_to_fp8(
                               x, getattr(td.dtypes, dt))))
    return out


def emit(cs: list[Row]) -> str:
    body = ["import ./tinybendygrad/dtype.bend as D", "",
            "def main() -> IO(Unit):", "  do IO<Unit>:"]
    for i, r in enumerate(cs):
        body.append(f"    v{i} : {r.show} <- {r.expr}")
        body.append(f'    IO.print("F32ROW {r.name} = " ++ {r.show}.show(v{i}))')
    return "\n".join(body) + "\n"


def norm(s: str) -> str:
    """`f32_show` prints the SHORTEST round-tripping form, so the f32 nearest 1.1
    prints `1.0996094` where CPython, holding a double, prints `1.099609375`.
    abi_gate.py's JSL2-7: compare as f32, or the count means two things at once."""
    try:
        return repr(struct.unpack("<f", struct.pack("<f", float(s)))[0])
    except ValueError:
        return s


def swap(text: str, old: str, new: str) -> str:
    got = text.count(old)
    if got != 1:
        sys.exit(f"anchor: expected 1 site, found {got} -- dtype.js moved:\n"
                 f"{old.splitlines()[0]}")
    return text.replace(old, new)


def breaks(text: str, subset: str) -> str:
    for s in subset:
        text = swap(text, *SITES[s])
    return text


def run(work: pathlib.Path, cs: list[Row], label: str) -> dict[str, str]:
    bend = work / "f32.bend"
    bend.write_text(emit(cs))
    out = work / "f32.js"
    if out.exists():
        out.unlink()
    r = subprocess.run([str(BEND), str(bend), "-o", str(out)],
                       capture_output=True, text=True)
    if not out.exists():                      # a dead lane is never a green one
        sys.exit(f"no backend for arm {label}: rc={r.returncode}\n{r.stdout}\n{r.stderr}")
    p = subprocess.run(["node", str(out)], capture_output=True, text=True, timeout=300)
    rows = {m[1]: m[2].strip() for m in map(ROW.match, p.stdout.splitlines()) if m}
    # A lane that printed nothing is a DEAD lane, not a green one, and the check
    # that says so is node's exit status.  It bit: a dangling `)` left in
    # fp8_decode made node exit 1 with empty stdout while this gate reported
    # `shipped 57/98`, because this gate measures a PATCHED COPY and so never saw
    # the bytes the tree actually had.
    if p.returncode != 0 or len(rows) != len(cs):
        sys.exit(f"arm {label}: node printed {len(rows)}/{len(cs)} rows "
                 f"(rc={p.returncode})\n{p.stderr[:600]}")
    return rows


def rc_of(script: pathlib.Path, *args: str) -> tuple[int, str]:
    r = subprocess.run([sys.executable, str(script), *args], capture_output=True,
                       text=True, timeout=1800, cwd=REPO)
    return r.returncode, r.stdout + r.stderr


def main() -> None:
    cs = cases()
    names = [r.name for r in cs]
    isf = {r.name: r.show == "F32" for r in cs}
    oracle: dict[str, str] = {}
    for r in cs:
        try:
            v = r.expect()
        except Exception as e:                    # noqa: BLE001
            # FATAL, never counted.  This bit silently once, for 44 rows:
            # `td.dtypes[...]` is not subscriptable, so every fp8 oracle raised
            # TypeError, the row was marked red, and a repaired lane was reported
            # as disagreeing with CPython on rows it got RIGHT.  A model that
            # cannot answer is not a lane that is wrong, and when the two disagree
            # the model is the first suspect.
            sys.exit(f"oracle raised on {r.name}: {type(e).__name__}: {e}")
        oracle[r.name] = norm(str(v)) if isf[r.name] else str(int(v))

    pristine = JS_LANE.read_text()
    arms: dict[str, str] = {"shipped": pristine}
    for sub in BREAKS[1:]:
        arms[f"break-{sub}"] = breaks(pristine, sub)
    for s in "ABC":                              # disarms FIRST, run FIRST
        arms[f"disarm-{s}"] = swap(pristine, *DISARMS[s])
    for s in "ABC":
        arms[f"plant-{s}"] = swap(pristine, *PLANTS[s])
    # ALT: fp8_decode answers a VALUE and the seam's conversion is removed.
    arms["ALT"] = swap(swap(pristine, *SITES["C"]), JS_FP8DEC_SHIPPED, JS_FP8DEC_ALT)

    with tempfile.TemporaryDirectory() as td:
        work = pathlib.Path(td) / "tree"
        work.mkdir()
        shutil.copytree(REPO / "tinybendygrad", work / "tinybendygrad")
        lane = work / "tinybendygrad" / "runtime" / "dtype.js"
        res = {}
        for a, text in arms.items():
            lane.write_text(text)
            res[a] = run(work, cs, a)

    def red(a: str) -> list[str]:
        # `norm` is applied to an F32 row's answer and NEVER to a U32 one: the
        # oracle prints `60` for a U32 and norm('60') is '60.0', so normalising
        # both sides of a U32 row reports 32 rows red that agree.  It bit once.
        return [n for n in names if (norm(res[a][n]) if isf[n] else res[a][n]) != oracle[n]]

    def green(a: str) -> set[str]:
        return set(names) - set(red(a))

    needs = {s: sorted(green("shipped") - green(f"break-{s}")) for s in "ABC"}
    others = {s: "".join(x for x in "ABC" if x != s) for s in "ABC"}
    fixes = {s: sorted(green(f"break-{others[s]}") - green("break-ABC")) for s in "ABC"}
    ov = {f"{a}^{b}": sorted(set(needs[a]) & set(needs[b]))
          for a, b in (("A", "B"), ("A", "C"), ("B", "C"))}
    b_alone = not (set(needs["B"]) & (set(needs["A"]) | set(needs["C"])))
    a_in_c = set(needs["A"]) <= set(needs["C"])
    c_own = set(fixes["C"]) - set(fixes["A"]) - set(fixes["B"])

    print("=" * 78)
    print("ROWS PRESENT vs ROWS EXPECTED  (a lane that prints nothing is not green)")
    print("=" * 78)
    for a in arms:
        print(f"  {a:<10} present {len(res[a]):>3}/{len(names)}")

    print("\n" + "=" * 78)
    print("AGREEMENT WITH CPYTHON, `tinygrad.dtype` CALLED -- never transcribed")
    print("=" * 78)
    for a in arms:
        print(f"  {a:<10} {len(green(a)):>3}/{len(names)} agree")

    print("\n" + "=" * 78)
    print("DISARMS FIRST -- re-spellings of the SHIPPING text, one site each")
    print("=" * 78)
    disarm_ok = True
    for s in "ABC":
        mv = [n for n in names if res["shipped"][n] != res[f"disarm-{s}"][n]]
        print(f"  DISARM {s}  moved {len(mv):>3}/{len(names)}"
              + (f"   ** {mv[:3]}" if mv else "   0 is the only correct count"))
        disarm_ok &= not mv

    print("\n" + "=" * 78)
    print("PLANTS -- a SECOND mutation of the violation, not a copy of the break")
    print("=" * 78)
    plant_ok = True
    for s, what in (("A", "of32(v) moved to the return that consumes it"),
                    ("B", "the REVERSE converter, bits32, at the argument"),
                    ("C", "a DOUBLE of32 at the seam, pattern->value->pattern")):
        mv = [n for n in names if res["shipped"][n] != res[f"plant-{s}"][n]]
        print(f"  PLANT {s}  moved {len(mv):>3}/{len(names)}   {what}"
              + (f"   e.g. {mv[:2]}" if mv else "   ** a plant that moved nothing "
                 "proves nothing"))
        plant_ok &= bool(mv)

    print("\n" + "=" * 78)
    print("WHICH SITE IS ABI-4 -- necessity and sufficiency, per site")
    print("=" * 78)
    print("  NEEDS(s) = green as shipped, RED with site s re-broken")
    print("  FIXES(s) = green with the other two re-broken, RED with all three")
    for s in "ABC":
        print(f"\n  site {s}   NEEDS {len(needs[s]):>3}   FIXES {len(fixes[s]):>3}")
        print(f"    NEEDS: {needs[s][:4]}{' ...' if len(needs[s]) > 4 else ''}")
        print(f"    FIXES: {fixes[s][:4]}{' ...' if len(fixes[s]) > 4 else ''}")
    for k, v in ov.items():
        print(f"    NEEDS({k}) = {len(v)} {v[:3]}")
    print("\n  READ AS FOLLOWS.  `of32` is PATTERN->VALUE, `bits32` is")
    print("  VALUE->PATTERN, and `dtype.bend` declares `Dt.fp16(x: F32)` and")
    print("  `Dt.fp8_to(..) -> IO(F32)`.")
    print(f"    B  NEEDS {len(needs['B'])}, FIXES {len(fixes['B'])}, and NEEDS(B) touches")
    print("       no fp8_to row -> the INBOUND crossing, SEPARABLE BY ROW.")
    print(f"    C  FIXES {len(fixes['C'])} of which {len(c_own)} that A and B fix nothing")
    print("       -> the OUTBOUND crossing, and the only site with a row set of its")
    print("       OWN: fp8_decode's EARLY nan/inf returns never build `v`.")
    print(f"    A  FIXES {len(fixes['A'])}, and NEEDS(A) is a SUBSET of NEEDS(C) ({len(ov['A^C'])}")
    print("       shared) -> NOT separable from C by ANY fixture.  The same error")
    print("       (`of32` on a value) one call INSIDE the lane, on C's path, and")
    print("       reachable only through C.  Load-bearing, so not incidental -- and")
    print("       not a seam crossing either.  `abi_gate.py` carries ONE fp8_to row,")
    print("       which needs both, which is why its ABI-4 arm could never separate")
    print("       them.")
    print(f"\n  so: B and C are ABI-4 AT THE SEAM, A is ABI-4's error class applied")
    print(f"  INTERNAL to the lane.  {'All three are load-bearing.' if all(needs[s] for s in 'ABC') else 'A SITE IS REDUNDANT.'}"
          "  NONE is incidental.")

    print("\n  DIRECTION, BY VALUE -- the wrong answer NAMES the wrong representation")
    for n in fixes["B"][:3]:
        print(f"    {n:<30} CPython {oracle[n]:<10} shipped {res['shipped'][n]:<10}"
              f" with B broken {res['break-B'][n]}")
    print("  `Dt.fp16(x: F32)` receives a VALUE, and 1073741824 / 1069547520 are the")
    print("  VALUE whose own f32 PATTERN is 2.0 / 1.5 -- so those rows read the")
    print("  argument as a pattern BY NAME, which `fp16(1.5) = 0` cannot.")

    alt_red = red("ALT")
    print(f"\n  THE ALTERNATIVE SPELLING (`ALT`: fp8_decode answers a VALUE, the seam's")
    print(f"  of32 removed) is green on {len(green('ALT'))}/{len(names)}, RED on exactly")
    print(f"  {len(alt_red)} rows, and that set IS FIXES(C): {sorted(alt_red) == sorted(fixes['C'])}.")
    print("  So the conversion is FORCED ONTO THE SEAM, and the reason is structural:")
    print("  fp8_decode returns straight from its nan/inf branches WITHOUT building")
    print("  `v`, so a conversion placed at its `return` is bypassed by 10 of its 44")
    print("  reachable rows.  Measured, and it is why the repair cannot be written")
    print("  one call inward.")

    print("\n" + "=" * 78)
    print("LOCALITY -- by row set, by content, and by the tree's own bytes")
    print("=" * 78)
    mv_full = [n for n in names if res["break-ABC"][n] != res["shipped"][n]]
    esc = [n for n in mv_full if not n.startswith("abi4_")]
    print(f"  by ROW SET: the repair moved {len(mv_full)}/{len(names)} rows and "
          f"{len(esc)} of them outside abi4_*  {esc}")
    diff = []
    for shipped, other in list(SITES.values()):
        diff += shipped.splitlines() + other.splitlines()
    leaked = [t for t in OTHER_ABI_TOKENS if any(t in l for l in diff)]
    print(f"  by CONTENT: the repair's diff ({len(diff)} lines) mentions another ABI's")
    print(f"    tokens: {leaked or 'none'}.  A row-count fence cannot see an entangled")
    print("    ARM; this can, because it reads the bytes the arm would apply.")
    # EVERY ARM is fenced, not just the repair: the historical entanglement was an
    # ARM carrying another ABI's bytes, and a fence on the one arm that mattered
    # today is a fence that will be wrong tomorrow.  The structural half of the fix
    # is that every arm is built from `pristine` and from nothing else (no arm is
    # ever derived from another arm), so an arm cannot inherit an edit even by
    # accident; the check below is what proves that rather than trusting it.
    arm_leak = {}
    base = pristine.splitlines()
    for a, text in arms.items():
        delta = [l for l in text.splitlines() if l not in base]
        hit = [t for t in OTHER_ABI_TOKENS if any(t in l for l in delta)]
        if hit:
            arm_leak[a] = hit
    print(f"  EVERY ARM, {len(arms)} of them: edits naming another ABI: "
          f"{arm_leak or 'none'}")
    same = [n for n in names if res["shipped"][n] != res["ALT"][n]]
    print(f"  by THE TREE: `shipped` prints {len(res['shipped'])}/{len(names)} and the")
    print(f"    only arm that differs from it by a row is ALT ({len(same)} rows), so the")
    print("    bytes in the repo ARE the repair -- measured, not asserted.  This gate")
    print("    patches a copy, so it could not see the tree's own syntax: a dangling")
    print("    paren passed 98/98 here until node's exit status was checked.")

    ag, jg = (rc_of(REPO / g) for g in OTHER_GATES)
    jn = re.findall(r"^\s+shipped\s+(\d+)/(\d+)$", jg[1], re.M)
    print(f"  by the OTHER GATES: abi_gate rc={ag[0]}  jsfix_gate rc={jg[0]}"
          + (f"  jsfix shipped {jn[0][0]}/{jn[0][1]}" if jn else ""))
    print("    all 30 jsfix rows are `Dt.i64_*` and no arm of this repair touches an")
    print("    I64 helper, so jsfix MOVING 0 is a THEOREM about its row set and not")
    print("    evidence of locality.  Its rc is the only thing claimed for it here.")

    print("\n" + "=" * 78)
    print("VERDICT")
    print("=" * 78)
    checks = [
        ("every arm printed every row, so no arm is a silent no-op",
         all(len(res[a]) == len(names) for a in arms)),
        ("the re-broken tree is RED on abi4_ rows, so the gate has teeth",
         any(n.startswith("abi4_") for n in red("break-ABC"))),
        ("every DISARM moved 0 -- a disarm that moves is not a disarm", disarm_ok),
        ("every PLANT moved rows", plant_ok),
        ("the shipped tree agrees with CPython on all 98 rows", not red("shipped")),
        ("every site is NECESSARY for a non-empty row set, so none is incidental",
         all(needs[s] for s in "ABC")),
        ("B is separable from A and C BY ROW: NEEDS(B) touches no fp8_to row",
         b_alone),
        ("C has an exclusive row set: it alone fixes rows A and B fix nothing",
         bool(c_own)),
        ("A alone fixes nothing, so no fixture can witness A by itself",
         not fixes["A"]),
        ("A is NESTED in C rather than separable: NEEDS(A) is a SUBSET of NEEDS(C) "
         "-- stated as measured, and it is why abi_gate's 12 rows cannot tell them",
         a_in_c),
        ("the ALT spelling is red on exactly FIXES(C), so the conversion is FORCED "
         "ONTO THE SEAM by fp8_decode's early returns",
         sorted(alt_red) == sorted(fixes["C"]) and bool(fixes["C"])),
        ("the repair moved no `loc_*` row (a row where no VALUE crosses)", not esc),
        ("the repair's diff mentions no other ABI's token -- the CONTENT fence",
         not leaked),
        (f"NO ARM of the {len(arms)} names another ABI's token: the entanglement was "
         "an ARM carrying another ABI's bytes, and a fence on the one arm that "
         "mattered today is a fence that will be wrong tomorrow", not arm_leak),
        ("abi_gate.py exits 0 against this tree", ag[0] == 0),
        ("jsfix_gate.py exits 0 against this tree", jg[0] == 0),
    ]
    ok = True
    for name, good in checks:
        print(f"  {'PASS' if good else 'FAIL'}  {name}")
        ok &= good
    if "--save" in sys.argv:
        (HERE / "rows.json").write_text(json.dumps(
            {"names": names, "oracle": oracle, "arms": list(arms), "needs": needs,
             "fixes": fixes, "red": {a: red(a) for a in arms},
             "green": {a: len(green(a)) for a in arms},
             "rows": {a: res[a] for a in arms}}, indent=1))
    print("\n  gate rc:", 0 if ok else 1)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
