#!/usr/bin/env python3
"""jsstage.py -- THE JS dtype lane, EXECUTED under `node`, against CPython.

Reproduce (from the repo root):
    .venv/bin/python .agents/slop/jstage/jsstage.py     # the stage: rc 0 / 1 / 3
    .venv/bin/python .agents/slop/jstage/jsstage.py --tree DIR   # read another tree

THE CLAIM, in one sentence, with its denominator:

    `node` runs `tinybendygrad/runtime/dtype.js` through `bend -o`, exits 0, prints
    ALL 20 rows this gate asks for, and agrees with CPython -- called, never
    transcribed -- on the 19 of them CPython can answer.

OF THOSE 20, **12 REACH `dtype.js` AND 8 DO NOT**, and the gate prints which is
which on its own line rather than letting a reader assume 20.  MEASURED
2026-10-05: `dtype.bend` had been rewritten so that `Dt.bf16`, `Dt.fp16` and
`Dt.fp8_to` are PURE defs, so the three CIDs `runtime/dtype.js` registers for them
are DEAD -- registered and never called -- and those rows measure `dtype.bend`'s
arithmetic.  The gate derives the split from the substrate's own declarations every
run, so a tree that moves back the other way is counted correctly without an edit.

WHAT IT DOES NOT CLAIM, stated here so the stage cannot be quoted as more:

  * IT IS NOT "EXECUTED IS BOUND".  A row that ran is not a row whose binding was
    shown to work.  The census that says so, with numbers, is a DIFFERENT lane's:
    `.agents/slop/CLANGFILL.md` §2 measured **320 executed, of which 256 ran with
    at least one NULL argument and 175 answered a refusal sentinel** -- and that
    census is `clangfill/gate.py`, which drives `cc` against `libclang`.  **IT IS
    NOT A JS CENSUS**: `clangshim/apply-port-lane.py:130` records that the libclang
    lane cannot be emitted to JS at all.  What this stage borrows is the SHAPE of
    that caution, and states its own limit in the terms it can measure -- every
    argument here is a bend literal, so there is no NULL-argument class to count.
  * `ceildiv(x, 0)` ANSWERS 0 IN BOTH LANES WHERE CPython RAISES (ABI-6).  That row
    is in NEITHER `pass` NOR `fail`: there is no CPython answer to agree with.

THE DENOMINATOR IS NOT `node`'s EXIT STATUS, for the reason this repo has paid for
twice (DTYPE-ABI.md ABI4-4: a dangling paren made `node` exit 1 with EMPTY stdout
and `abi4_gate.py` still reported 98/98, because `vs()` excludes absent rows from
`bad`).  So:

  * node's rc is READ, and a non-zero rc over a full row set is a FAIL; and
  * an ABSENT row is a FAIL, never a neutral -- `present == expected` is its own
    obligation, printed on its own line, not folded into the agreement count.

`bend -o` IS NOT A BUILD.  It EMITS JS; `node` is what runs it.  For the C lane the
build is `cc` -- a distinction this project has got wrong five times.

NOTHING IN THE LIVE TREE IS WRITTEN.  `tinybendygrad` is copied to `$TMPDIR` and
every arm, the plant and the disarm included, is built from the PRISTINE `dtype.js`
of the tree being measured and applied to the COPY.

`--tree DIR` measures `DIR/tinybendygrad` instead of the repo's.  It is a READER of
the substrate, not a way to plant one, and it exists because on 2026-10-05
`tinybendygrad/dtype.bend` was under concurrent edit and `bend -o` refused it --
which is the refusal this stage has to be able to report.  The report names the
tree it measured, so a number from a copy can never be quoted as a number about the
shipped tree.
"""
from __future__ import annotations

import argparse
import math
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
from tinygrad import dtype as td                              # noqa: E402
from tinygrad.helpers import cdiv, cmod, ceildiv, floordiv, floormod  # noqa: E402

BEND = REPO / "bin" / "bend"
JS_LANE = "tinybendygrad/runtime/dtype.js"
ROW = re.compile(r"^JS8 (\w+) = (.*)$")
U32 = 0xFFFFFFFF
INT64_MIN = -(1 << 63)

I64, F32T, U32T = "H.I64", "F32", "U32"


def hi_lo(v: int) -> str:
    """`H.i64_of_hi_lo(hi, lo)` carrying `v` as its 64-bit TWO'S-COMPLEMENT words.

    WRITTEN BY THIS FUNCTION AND NOT BY HAND, and the reason is a measured one.
    MEASURED 2026-10-05: a hand-typed `-8` as `i64_of_hi_lo(0, 4294967288)` is
    `+4294967288`, not `-8` -- `BigInt.asIntN(64, x)` leaves a 32-bit value alone,
    because the sign lives in the HIGH word.  Both lanes answered `+4294967288`
    correctly and four rows were red against a fixture that was wrong.  A fixture
    literal is a TYPED CONSTANT, and agent-core.md's table already has five units
    that shipped one.
    """
    u = v & ((1 << 64) - 1)
    return f"H.i64_of_hi_lo({u >> 32}, {u & U32})"


# (name, bind type, bend expr, how the row prints itself, CPython callable)
# `show=None` is a BIND-ONLY fixture step and is NOT in the denominator; `None` for
# the callable is a row CPython REFUSES, counted `diverge`, never `pass`.
CASES = [
    # -- the I64 RECORD seam: a record crosses by NAME (ABI-2), hi first (ABI-3),
    #    and the two words become BigInt before they are combined (ABI-5).
    ("trunc_0_7",      I64, f"D.Dt.i64_trunc({hi_lo(7)})", "H.i64_text", lambda: 7),
    ("trunc_min",      I64, f"D.Dt.i64_trunc({hi_lo(INT64_MIN)})", "H.i64_text",
     lambda: INT64_MIN),
    # `hi == lo == 0xFFFFFFFF`, so this row is what a pair-ORDER plant cannot see.
    ("trunc_hi_eq_lo", I64, f"D.Dt.i64_trunc({hi_lo(-1)})", "H.i64_text", lambda: -1),
    # `hi == 2097153 == 2**21 + 1`: past 2**21 and not a power of two, so
    # `hi * 4294967296` is INEXACT in a double.  This is the row ABI-5 is for.
    ("trunc_inexact_hi", I64, "D.Dt.i64_trunc(H.i64_of_hi_lo(2097153, 4294967295))",
     "H.i64_text", lambda: (2097153 << 32 | U32) - (1 << 64)),
    ("floordiv_neg",   I64, f"D.Dt.i64_floor_div({hi_lo(-8)}, {hi_lo(4)})", "H.i64_text",
     lambda: floordiv(-8, 4)),
    ("floormod_neg",   I64, f"D.Dt.i64_floor_mod({hi_lo(-8)}, {hi_lo(4)})", "H.i64_text",
     lambda: floormod(-8, 4)),
    ("cdiv_neg",       I64, f"D.Dt.i64_cdiv({hi_lo(-7)}, {hi_lo(4)})", "H.i64_text",
     lambda: cdiv(-7, 4)),
    ("cmod_neg",       I64, f"D.Dt.i64_cmod({hi_lo(-7)}, {hi_lo(4)})", "H.i64_text",
     lambda: cmod(-7, 4)),
    ("ceildiv_pos",    I64, f"D.Dt.i64_ceildiv({hi_lo(7)}, {hi_lo(4)})", "H.i64_text",
     lambda: ceildiv(7, 4)),
    # ABI-6: ONLY `ceildiv` raises upstream.  `cdiv`/`floordiv` guard with
    # `if y != 0 else 0`, so `cdiv_by0` is an AGREEMENT row and this one is not.
    ("cdiv_by0",       I64, f"D.Dt.i64_cdiv({hi_lo(7)}, {hi_lo(0)})", "H.i64_text",
     lambda: cdiv(7, 0)),
    ("ceildiv_by0",    I64, f"D.Dt.i64_ceildiv({hi_lo(7)}, {hi_lo(0)})", "H.i64_text",
     None),
    # -- the F32 SCALAR seam: a scalar crosses as BITS in C and as a VALUE in node
    #    (ABI-4), so `of32` belongs on an ANSWER and `bits32` on an ARGUMENT.
    ("bf16_1p5",    F32T, "D.Dt.bf16(F32.bits(1.5))", "F32.show",
     lambda: td.float_to_bf16(1.5)),
    ("fp16_1p5",    F32T, "D.Dt.fp16(1.5)", "F32.show", lambda: td.float_to_fp16(1.5)),
    # 1.1 is the row the `norm` of `jslane2/gen_f32_seam.py` would have called a
    # lane disagreement for a FORMATTING reason; it is here so this gate cannot.
    ("fp16_1p1",    F32T, "D.Dt.fp16(1.1)", "F32.show", lambda: td.float_to_fp16(1.1)),
    ("fp16_m2p25",  F32T, "D.Dt.fp16(2.25)", "F32.show", lambda: td.float_to_fp16(2.25)),
    # the INVERSION row: `Dt.fp16` takes a VALUE, so 1073741824 arrives as the
    # number 1073741824, whose own f32 PATTERN is `0x40000000` = 2.0.  A lane that
    # reads its argument as a pattern answers 2 where CPython answers inf.  This is
    # a POSITIVE detection: the wrong answer NAMES the wrong representation.
    ("fp16_inv",    F32T, "D.Dt.fp16(1073741824.0)", "F32.show",
     lambda: td.float_to_fp16(float("inf"))),
    ("fp8from_1p5", U32T, "D.Dt.fp8_from(F32.bits(1.5), 0)", "U32.show",
     lambda: td.float_to_fp8(1.5, td.dtypes.fp8e4m3)),
    ("fp8to_0x3C",  F32T, "D.Dt.fp8_to(60, 0)", "F32.show",
     lambda: td.fp8_to_float(0x3C, td.dtypes.fp8e4m3)),
    ("fp8to_0x7E",  F32T, "D.Dt.fp8_to(126, 0)", "F32.show",
     lambda: td.fp8_to_float(0x7E, td.dtypes.fp8e4m3)),
    ("fp8to_nan",   F32T, "D.Dt.fp8_to(127, 1)", "F32.show",
     lambda: td.fp8_to_float(0x7F, td.dtypes.fp8e5m2)),
]

# ---- dtype.js anchors. Each must occur EXACTLY ONCE or this refuses: an anchor
# ---- that has moved means the tree changed under us and every number here would
# ---- be stale, which is worse than a wrong number because it is a confident one.
I64_OF_SHIPPED = """function i64_of(p) {
  return BigInt.asIntN(64, (BigInt(p.hi >>> 0) << 32n) | BigInt(p.lo >>> 0));
}"""
# THE PLANT: ABI-2 exactly as it shipped.  `p.fst`/`p.snd` against fields `hi`/`lo`
# is not a wrong reading, it is a read of two fields that DO NOT EXIST -- and
# `undefined >>> 0 === 0`, so the seam answers 0 for EVERY input and still prints a
# plausible row.  Re-breaking it must move rows or this stage cannot fail.
I64_OF_PLANT = """function i64_of(p) {
  return BigInt.asIntN(64, (BigInt(p.fst >>> 0) << 32n) | BigInt(p.snd >>> 0));
}"""
# THE DISARM: a DIFFERENT EXPRESSION for the same value.  Over h, l in [0, 2**32)
# `(h << 32) | l` and `h * 2**32 + l` are the same function and it stays in BigInt,
# so 0 is the ONLY correct moved-set.  A disarm is only a disarm after it has moved
# 0 IN FACT: JSL2-5 records `h * 2**32 + l` in NUMBER arithmetic being mistaken for
# one and moving 15 of 30 rows, so that spelling is run here as a SECOND PLANT.
I64_OF_DISARM = """function i64_of(p) {
  return BigInt.asIntN(64, BigInt(p.hi >>> 0) * 4294967296n + BigInt(p.lo >>> 0));
}"""
I64_OF_NUMPROD = """function i64_of(p) {
  return BigInt.asIntN(64, BigInt((p.hi >>> 0) * 4294967296 + (p.lo >>> 0)));
}"""

BEND_SRC = """import ./tinybendygrad/dtype.bend as D
import ./tinybendygrad/helpers.bend as H

def main() -> IO(Unit):
  do IO<Unit>:
{body}"""

STEP = {nm: (ty, ex, show, cp) for nm, ty, ex, show, cp in CASES}
ROW_NAMES = [c[0] for c in CASES if c[3] is not None]


def call_of(ex: str) -> str:
    return ex.split(".", 2)[2].split("(")[0]


def emit(seams: dict[str, bool]) -> str:
    """ONE `.bend`, ONE emit, ONE node run -- so node's rc belongs to the WHOLE row
    set.  Twenty emits would give twenty rcs, and a short twentieth one could be
    reported as a twentieth failure of the wrong thing.

    `seams[name]` says whether `Dt.<name>` is declared `-> IO(_)` in the tree's own
    `dtype.bend`.  That is read from the DECLARATION rather than assumed, because
    the two shapes need two different spellings inside a `do IO<Unit>` block -- an
    `IO` value binds with `<-` and a pure one does not, it must be lifted with
    `IO.pure`.  `dtype.bend` is mid-refactor (measured 2026-10-05: `Dt.bf16`,
    `Dt.fp16` and `Dt.fp8_to` had become pure defs, leaving seven live CIDs, and
    the same three had been `IO` laws the day before), so a hard-coded shape is a
    stage that refuses on whichever side of that change the tree happens to be on.
    `agent-core.md`'s own rule applies: which of the two a helper answers is the
    DECLARATION's business, not the caller's guess.
    """
    out = []
    for nm, ty, ex, show, _ in CASES:
        rhs = ex if seams[call_of(ex)] else f"IO.pure({ty}, {ex})"
        out.append(f"    {nm} : {ty} <- {rhs}")
        if show is not None:
            out.append(f'    IO.print("JS8 {nm} = " ++ {show}({nm}))')
    return BEND_SRC.format(body="\n".join(out) + "\n")


SEAM_DECL = re.compile(r"^def Dt\.(\w+)\(.*?\)\s*->\s*(IO\(|[A-Z])", re.M)


def seams_of(dtype_bend: pathlib.Path) -> dict[str, bool]:
    """`{name: is-an-IO-law}` for every `Dt.*` the substrate declares.  A name this
    gate drives and the declaration does not carry is a FAIL, not a default: it
    means the fixture is asking for a seam the tree has moved."""
    found = {m[0]: m[1] == "IO(" for m in SEAM_DECL.findall(dtype_bend.read_text())}
    want_names = {call_of(c[2]) for c in CASES}
    gone = sorted(want_names - set(found))
    if gone:
        raise ArmError("`dtype.bend` declares no %s -- the seam this gate drives has "
                       "moved, so every number below would be about a lane that no "
                       "longer exists" % ", ".join(gone))
    return found


class ArmError(Exception):
    """The tree's `dtype.js` no longer carries the anchor the controls are built
    from.  THAT IS A FAILURE, NOT A REFUSAL, and the distinction is the whole point:
    a `dtype.js` that has reverted to `p.fst`/`p.snd` is the ABI-2 BUG SHIPPING
    AGAIN, and reporting that as SKIP would launder a live defect into 'this stage
    could not run'.  SKIP is for a substrate that will not compile, where nothing
    was measured at all."""


def arm(substrate: pathlib.Path, work: pathlib.Path, read: str) -> None:
    """Write ONE arm's `dtype.js` into the copy.  Every arm is built from the
    PRISTINE file of the tree being measured, never from another arm, so an arm
    cannot inherit an edit even by accident (ABI4-6)."""
    src = (substrate / JS_LANE).read_text()
    if read == I64_OF_SHIPPED:
        (work / JS_LANE).write_text(src)
        return
    if src.count(I64_OF_SHIPPED) != 1:
        raise ArmError("the `i64_of` anchor occurs %dx in %s -- it moved, so this gate "
                       "can neither read the lane it was written to attest nor build "
                       "the control that proves the lane can fail"
                       % (src.count(I64_OF_SHIPPED), JS_LANE))
    (work / JS_LANE).write_text(src.replace(I64_OF_SHIPPED, read))


def run(substrate: pathlib.Path, work: pathlib.Path, read: str) -> tuple[int, dict[str, str], str]:
    """-> (node's rc, rows, node's stderr tail).  The rc belongs to the STAGE, not to
    the emit: `bend -o` is not a build and its rc says only that JS was emitted.
    rc 3 = the substrate refused to compile (SKIP); rc 4 = the lane is unreadable
    (FAIL); anything else is node's own status."""
    try:
        arm(substrate, work, read)
        body = emit(seams_of(substrate / "tinybendygrad" / "dtype.bend"))
    except ArmError as e:
        return 4, {}, str(e)
    bend, js = work / "jsstage.bend", work / "jsstage.js"
    bend.write_text(body)
    r = subprocess.run([str(BEND), str(bend), "-o", str(js)], capture_output=True, text=True)
    if r.returncode != 0 or not js.exists():
        # A substrate that will not compile is a REFUSAL, not a verdict: nothing was
        # measured.  `run-f64.sh` exits 3 for exactly this and stage 7 maps it to
        # SKIP; stage 8 must do the same or a cold tree would be reported green.
        return 3, {}, "bend rc=%d\n%s" % (r.returncode, (r.stdout + r.stderr)[-1200:])
    p = subprocess.run(["node", str(js)], capture_output=True, text=True, timeout=300)
    rows = {}
    for line in p.stdout.splitlines():
        m = ROW.match(line)
        if m:
            rows[m[1]] = m[2].strip()
    return p.returncode, rows, p.stderr[-1200:]


def pattern(v: int) -> str:
    """`hi:lo`, the form `H.i64_text` prints, so the comparison is on the SEAM's own
    representation rather than on a rendering this file guessed.  MASKED, because
    Python's `>>` on a negative int is arithmetic: `pattern(-1)` is `4294967295:
    4294967295` and not `-1:4294967295`."""
    u = v & ((1 << 64) - 1)
    return f"{u >> 32}:{u & U32}"


def f32(x: float) -> float:
    """Round a double to the nearest f32.  `F32.show` prints SEVEN significant
    digits -- `1.0996094` where CPython prints `1.099609375` -- so comparing the two
    as floats still misses on a formatting difference, and a count containing both
    kinds of miss is a count that means two things at once (JSL2-7).
    `jslane2/gen_f32_seam.py`'s own `norm` is `repr(float(s))` with NO round-trip and
    would call `fp16(1.1)` a lane disagreement for that reason; the row is here so
    that this gate cannot."""
    return struct.unpack("<f", struct.pack("<f", x))[0]


def want(nm: str) -> str | None:
    """CPython, CALLED, never transcribed.  `None` = CPython refuses and there is
    nothing to agree with."""
    ty, _, _, cp = STEP[nm]
    return None if cp is None else (pattern(cp()) if ty == I64 else repr(float(cp())))


def agree(nm: str, got: str) -> bool:
    """An `H.I64` row compares as the exact `hi:lo` string, because a 64-bit value
    does not survive a float round-trip.  A float row compares through `f32()` and
    NaN matches NaN, so a formatting difference is not counted as a disagreement."""
    w = want(nm)
    if w is None:
        return True
    if STEP[nm][0] == I64:
        return got == w
    try:
        g, e = f32(float(got)), f32(float(w))
    except (OverflowError, ValueError):
        return got == w
    return g == e or (math.isnan(g) and math.isnan(e))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--tree", default=str(REPO), metavar="DIR",
                    help="measure DIR/tinybendygrad instead of the repo's (default: the repo)")
    substrate = pathlib.Path(ap.parse_args().tree).resolve()
    # A TREE THAT IS NOT THERE is a refusal, not a crash.  MEASURED: `--tree` pointed
    # at a directory without a `tinybendygrad` under it and the gate died on a
    # `FileNotFoundError` from `copytree`, which the stage then had to read as FAIL --
    # and a FAIL is a claim that the LANE is wrong, which is not what happened.
    for needed in ("tinybendygrad", JS_LANE, "tinybendygrad/dtype.bend"):
        if not (substrate / needed).exists():
            print("REFUSED -- %s has no `%s`, so there is nothing to measure. rc 3 = SKIP."
                  % (substrate, needed))
            return 3
    diverge = [n for n in ROW_NAMES if want(n) is None]
    comparable = [n for n in ROW_NAMES if want(n) is not None]

    with tempfile.TemporaryDirectory() as td:
        work = pathlib.Path(td) / "tree"
        work.mkdir()
        shutil.copytree(substrate / "tinybendygrad", work / "tinybendygrad")
        try:
            seams = seams_of(substrate / "tinybendygrad" / "dtype.bend")
        except ArmError as e:
            print("REFUSED -- %s" % e)
            return 3
        rc, rows, err = run(substrate, work, I64_OF_SHIPPED)
        if rc == 3:
            print("SUBSTRATE MEASURED: %s" % (substrate / JS_LANE))
            print("REFUSED -- the substrate will not compile, so NOTHING BELOW IS A VERDICT.")
            print("       rc 3, which e2e.sh stage 8 maps to SKIP and NOT to PASS: a stage")
            print("       that could not run has measured nothing.")
            print(err)
            return 3
        plant_rc, plant, plant_err = run(substrate, work, I64_OF_PLANT)
        disarm_rc, disarm, disarm_err = run(substrate, work, I64_OF_DISARM)
        numprod_rc, numprod, numprod_err = run(substrate, work, I64_OF_NUMPROD)
        unreadable = [e for c, e in ((plant_rc, plant_err), (disarm_rc, disarm_err),
                                     (numprod_rc, numprod_err)) if c == 4]

    missing = [n for n in ROW_NAMES if n not in rows]
    # AN ABSENT ROW IS A FAILURE, not a neutral.  `wrong` is the disagreement list;
    # `missing` is reported on its own line and `fails` carries it, so the two are
    # never collapsed into one number that could come out empty for having nothing
    # to look at (ABI4-4).
    wrong = [n for n in comparable if not agree(n, rows[n])]

    print("THE CLAIM, with its denominator")
    print("  substrate measured             %s" % (substrate / JS_LANE))
    print("  rows asked for                 %d" % len(ROW_NAMES))
    # THE DENOMINATOR SPLIT, AND IT IS THE HONEST PART.  A row only reaches
    # `runtime/dtype.js` if `dtype.bend` still declares its `Dt.*` as `-> IO(_)`.
    # MEASURED 2026-10-05: `Dt.bf16`, `Dt.fp16` and `Dt.fp8_to` had been rewritten
    # as PURE defs in `dtype.bend`, so the CIDs `dtype.js` registers for them are
    # DEAD -- registered and never called -- and those rows now measure
    # `dtype.bend`'s arithmetic instead of the JS lane's.  Counting them as JS rows
    # would overstate this stage by exactly the number it prints here.
    lane_rows = [n for n in ROW_NAMES if seams[call_of(STEP[n][1])]]
    pure_rows = [n for n in ROW_NAMES if n not in lane_rows]
    dead = sorted(cid for cid in re.findall(r"io_eff\(CID\(Dt\.(\w+)\)", (substrate / JS_LANE).read_text())
                  if not seams.get(cid))
    print("  rows that REACH `dtype.js`      %d   %s" % (len(lane_rows), ", ".join(lane_rows)))
    print("  rows that are pure `dtype.bend` %d   %s"
          % (len(pure_rows), "(NOT the JS lane)" if pure_rows else ""))
    print("  CIDs `dtype.js` registers that `dtype.bend` no longer calls  %d  %s"
          % (len(dead), ", ".join(dead) if dead else "-"))
    print("  rows CPython can answer        %d   (%d diverge: CPython raises, so there "
          "is no answer -- %s)" % (len(comparable), len(diverge), ", ".join(diverge)))
    print("  `node` exit status             %d" % rc)
    print("  ROWS PRESENT == ROWS EXPECTED  %s   (%d/%d)"
          % ("yes" if not missing else "NO -- MISSING " + str(missing),
             len(ROW_NAMES) - len(missing), len(ROW_NAMES)))
    print("  node agrees with CPython on    %d/%d"
          % (len(comparable) - len(wrong), len(comparable)))

    print("\n| row | CPython (called) | node | |")
    print("|---|---|---|---|")
    for n in ROW_NAMES:
        w, got = want(n), rows.get(n, "<ABSENT>")
        mark = "" if w is None else (" ok" if agree(n, got) else " ** WRONG **")
        print("| `%s` | %s | `%s` |%s"
              % (n, "raises" if w is None else "`" + w + "`", got, mark))

    print("\nTHE CONTROL THAT PROVES THIS STAGE CAN GO RED, AND THE ONE THAT PROVES")
    print("IT IS NOT RED BY CONSTRUCTION")
    moved = lambda r: [n for n in ROW_NAMES if r.get(n) != rows.get(n)]
    pmoved, dmoved, nmoved = moved(plant), moved(disarm), moved(numprod)
    print("  PLANT  `p.hi`/`p.lo` -> `p.fst`/`p.snd` (ABI-2 as shipped)   moved %d/%d"
          % (len(pmoved), len(ROW_NAMES)))
    print("    rows: %s" % ", ".join(pmoved))
    print("  DISARM `<<32n |` -> `* 2**32n +`, BigInt, same function     moved %d/%d   %s"
          % (len(dmoved), len(ROW_NAMES),
             "-- 0 is the only correct count" if not dmoved else "-- NOT A DISARM"))
    print("  PLANT  the same in NUMBER arithmetic (NOT a disarm)          moved %d/%d"
          % (len(nmoved), len(ROW_NAMES)))
    print("    rows: %s" % ", ".join(nmoved))
    # The plant's UNMOVED rows are attributed, not hand-waved.  Three classes, each
    # a theorem rather than luck: a row that never reaches `dtype.js`; a row that
    # reaches it by a seam the plant does not touch; and a row that goes through
    # `i64_of` but already answers `0:0`, which a planted seam answering 0 cannot
    # move.
    zero_lane = [n for n in lane_rows if n not in pmoved]
    uses_i64_of = lambda n: ".Dt.i64_" in STEP[n][1]
    bypass = [n for n in zero_lane if not uses_i64_of(n)]
    already = [n for n in zero_lane if uses_i64_of(n)]
    print("  the plant's %d unmoved rows, attributed -- and every class is a theorem:"
          % (len(ROW_NAMES) - len(pmoved)))
    print("    %d never reach `dtype.js` (pure `dtype.bend`): %s"
          % (len(pure_rows), ", ".join(pure_rows)))
    print("    %d reach `dtype.js` by a seam the plant does NOT touch (`i64_of` is "
          "one function of seven registered CIDs): %s" % (len(bypass), ", ".join(bypass)))
    print("    %d go through `i64_of` but already answer `0:0`, and a planted seam "
          "answering 0 cannot move a row that is already 0: %s  (answers %s)"
          % (len(already), ", ".join(already), ", ".join(rows.get(n, "?") for n in already)))

    if err.strip():
        print("\nnode stderr (last lines):\n" + err)

    fails = []
    fails += unreadable
    if rc != 0:
        fails.append("node exited %d" % rc)
    if missing:
        fails.append("rows absent: %s -- an absent row is a FAIL, not a neutral, so "
                     "%d of %d rows are unmeasured" % (missing, len(missing), len(ROW_NAMES)))
    if wrong:
        fails.append("rows disagreeing with CPython: %s" % wrong)
    if not pmoved:
        fails.append("the plant moved 0 rows, so this stage CANNOT fail on the bug it exists for")
    if dmoved:
        fails.append("the disarm moved %d rows, so it is a second plant, not a disarm" % len(dmoved))

    print("\n===== VERDICT: %s =====" % ("PASS" if not fails else "FAIL"))
    for f in fails:
        print("  FAIL %s" % f)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
