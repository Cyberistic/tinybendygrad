#!/usr/bin/env python3
"""jsfix_gate.py -- the dtype seam's JS lane, executed, checked, and planted.

Reproduce (from the repo root):
    python3 .agents/slop/jsfix/jsfix_gate.py

WHAT THIS IS FOR.  `runtime/dtype.js` shipped reading `p.fst`/`p.snd` on a record
whose Bend fields are `hi`/`lo`, and answering with `io_tup(...)` =
`Tuple{fst,snd}` where generated code reads `{hi, lo}`.  Both halves were `undefined`
on the way in and a wrong shape on the way out, and `undefined >>> 0 === 0` made the
inbound read TOTAL rather than loud: the identity seam `Dt.i64_trunc` answered 0.
Node disagreed with CPython on 9 of 12 rows of `abi/abi_gate.py` and on 0 of 30
rows of `jslane2/gen_js_seam.py`.

The declaration is `.agents/slop/abi/abi.json`; this file cites it by id and does
not restate it.  What it adds over that gate is three things:
  1. the shipped tree is the MEASUREMENT -- the repair is IN the tree, so the
     evidence that it used to be broken is a PLANT, not a $TMPDIR diagnosis;
  2. a 30-row set that includes `int64.min`, which the 12-row set does not;
  3. an OUTBOUND-only plant.  Both lanes were broken; the inbound plant cannot see
     the outbound half, so a gate that only re-plants `p.fst` would report green on
     a lane that still builds `Tuple{fst,snd}`.

NO GATE ON BEND'S EXIT.  `dtype.bend` is COLD (its own 14 unfilled laws), so bend's
exit status answers "does this file stand alone", which is not the question.  This
gate requires that bend EMIT the backend and that `node` PRINT the rows, and it
reports bend's return code beside the verdict instead of failing on it.  This is the
`rebase-gate.py` discipline.

THE LIVE TREE IS NEVER WRITTEN.  Every arm patches a `$TMPDIR` copy.
"""
from __future__ import annotations

import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]
BEND = REPO / "bin" / "bend"
JS_LANE = REPO / "tinybendygrad" / "runtime" / "dtype.js"

U32 = 0xFFFFFFFF
MASK64 = (1 << 64) - 1
INT64_MIN = -(1 << 63)

DEFS = ["trunc", "floor_div", "floor_mod", "cdiv", "cmod", "ceildiv"]
# (a, b).  Every a and b has hi != lo except `floor_mod|-8|4`'s operands (hi/lo are
# the operand's words, -8 is 4294967295:4294967288), and `trunc` is single-operand.
# `int64.min` is the row no double can hold without the BigInt step.
FIXTURES = [(7, 4), (-7, 4), (-8, 4), (7, -4), (INT64_MIN, 3)]

# ---------------------------------------------------------------- the anchors.
# The SHIPPED text, verbatim, after the repair.  Every arm's base is this file, and
# `patch` re-reads the live tree and states how many sites it expects to change, so
# a lane that moves under us aborts the run instead of silently patching nothing.
JS_I64_OF_SHIPPED = """function i64_of(p) {
  return BigInt.asIntN(64, (BigInt(p.hi >>> 0) << 32n) | BigInt(p.lo >>> 0));
}"""
JS_PACK_SHIPPED = """function pack64(v) {
  const u = BigInt.asUintN(64, v);
  return {$: "tinybendygrad/helpers.I64", hi: Number((u >> 32n) & 0xffffffffn),
          lo: Number(u & 0xffffffffn)};
}"""

# PLANT A -- the inbound half, verbatim from the shipped-before-repair file.
JS_I64_OF_FST = """function i64_of(p) {
  return BigInt.asIntN(64, (BigInt(p.fst >>> 0) << 32n) | BigInt(p.snd >>> 0));
}"""
# PLANT B -- the OUTBOUND half alone.  Inbound stays conforming, so this plant can
# only be seen by a row that reads the answer back.
JS_PACK_IOTUP = """function pack64(v) {
  const u = BigInt.asUintN(64, v);
  return io_tup(Number((u >> 32n) & 0xffffffffn), Number(u & 0xffffffffn));
}"""
# PLANT C -- both halves, i.e. the file exactly as it shipped.
# PLANT D -- ABI-3: the words exchanged on the way in.  Nothing but the declaration
# forbids it, which is the point.
JS_I64_OF_SWAPPED = """function i64_of(p) {
  return BigInt.asIntN(64, (BigInt(p.lo >>> 0) << 32n) | BigInt(p.hi >>> 0));
}"""
# PLANT E -- ABI-3, the way OUT.  Independent of D: a lane can order the halves
# correctly inbound and wrongly outbound.
JS_PACK_SWAPPED = """function pack64(v) {
  const u = BigInt.asUintN(64, v);
  return {$: "tinybendygrad/helpers.I64", hi: Number(u & 0xffffffffn),
          lo: Number((u >> 32n) & 0xffffffffn)};
}"""
# PLANT F -- a SECOND PLANT, kept because it was mistaken for a disarm: ABI-5's
# Number-arithmetic hazard.  A double has 53 mantissa bits, so `hi * 2**32` is exact
# only when hi == 0, hi < 2**21, or hi is a power of two.
JS_I64_OF_NUMPROD = """function i64_of(p) {
  return BigInt.asIntN(64, BigInt((p.hi >>> 0) * 4294967296 + (p.lo >>> 0)));
}"""

# THE DISARMS.  A disarm is a SYNTACTIC RE-SPELLING of the conforming code, so the
# only correct moved-set is the empty one, and a check matching tokens would fire
# on every one of them.
#   in : p.hi -> p["hi"], p.lo -> p["lo"]
#   out: a one-line literal instead of a two-line one, same object
#   abs: `* 1n` on a BigInt is the identity, and `(u >> 32n) & 0xffffffffn` spelled
#        through `* 1n` is still the high word
JS_DISARM_IN = """function i64_of(p) {
  return BigInt.asIntN(64, (BigInt(p["hi"] >>> 0) << 32n) | BigInt(p["lo"] >>> 0));
}"""
JS_DISARM_OUT = """function pack64(v) {
  const u = BigInt.asUintN(64, v);
  return {$: "tinybendygrad/helpers.I64", lo: Number(u & 0xffffffffn) * 1,
          hi: Number(((u >> 32n) & 0xffffffffn))};
}"""

# Each arm is a list of (old, new, expected-sites) applied to the JS lane, which is
# the only lane this unit owns.  dtype.c is byte-unchanged and is not touched here.
ARMS = {
    # ---- the measurement: nothing patched
    "shipped": [],
    # ---- PLANT A: inbound only.  Must move rows; the outbound half still works.
    "plant-abi2-in-js": [(JS_I64_OF_SHIPPED, JS_I64_OF_FST, 1)],
    # ---- PLANT B: OUTBOUND only.  Inbound still works.  This is the half no
    # ---- inbound-only plant can see, and the reason it exists.
    "plant-abi2-out-js": [(JS_PACK_SHIPPED, JS_PACK_IOTUP, 1)],
    # ---- PLANT C: the file as it shipped, both halves.
    "plant-abi2-both-js": [(JS_I64_OF_SHIPPED, JS_I64_OF_FST, 1),
                           (JS_PACK_SHIPPED, JS_PACK_IOTUP, 1)],
    # ---- PLANT D / E: the pair order, each direction separately.
    "plant-abi3-in-js": [(JS_I64_OF_SHIPPED, JS_I64_OF_SWAPPED, 1)],
    "plant-abi3-out-js": [(JS_PACK_SHIPPED, JS_PACK_SWAPPED, 1)],
    # ---- PLANT F: ABI-5, Number arithmetic.  Not a disarm.
    "plant-abi5-js": [(JS_I64_OF_SHIPPED, JS_I64_OF_NUMPROD, 1)],
    # ---- THE DISARMS.  Re-spellings of the two conforming helpers.
    "disarm-abi2-in-js": [(JS_I64_OF_SHIPPED, JS_DISARM_IN, 1)],
    "disarm-abi2-out-js": [(JS_PACK_SHIPPED, JS_DISARM_OUT, 1)],
    "disarm-both-js": [(JS_I64_OF_SHIPPED, JS_DISARM_IN, 1),
                       (JS_PACK_SHIPPED, JS_DISARM_OUT, 1)],
}

ROW = re.compile(r"^SEAM (\w+) #(\d+) = (.*)$")
md5 = lambda b: hashlib.md5(b).hexdigest()


def upstream(name: str, a: int, b: int) -> int:
    """CPython, by CALLING tinygrad's own helper.  Never transcribed."""
    from tinygrad.helpers import cdiv, cmod, ceildiv, floordiv, floormod
    return {"trunc": lambda: a, "floor_div": lambda: floordiv(a, b),
            "floor_mod": lambda: floormod(a, b), "cdiv": lambda: cdiv(a, b),
            "cmod": lambda: cmod(a, b), "ceildiv": lambda: ceildiv(a, b)}[name]()


def pattern(v: int) -> str:
    """`H.i64_text` prints hi:lo, so the oracle prints hi:lo.  A decimal would be a
    different string from the lane's and would make a correct lane look wrong."""
    u = v & MASK64
    return f"{u >> 32}:{u & U32}"


def inexact(hi: int) -> bool:
    """Is `hi * 2**32` exact in a double?  53 mantissa bits."""
    return hi != 0 and (hi >= (1 << 21)) and (hi & (hi - 1)) != 0


def patch(text: str, edits) -> str:
    for old, new, expect in edits:
        got = text.count(old)
        if got != expect:
            sys.exit(f"anchor: expected {expect} site(s), found {got}: "
                     f"{old.splitlines()[0][:70]!r}")
        text = text.replace(old, new)
    return text


# --------------------------------------------------- exact models of the arms.
# A count that cannot explain its own unmoved rows is a coverage gap pretending to
# be a measurement, so every arm here is MODELLED in Python and compared row for
# row.  A model that matched only the moved rows would explain nothing.
def swap_words(u: int) -> int:
    return (((u & U32) << 32) | ((u >> 32) & U32)) & MASK64


def signed(u: int) -> int:
    """The int64 the seam's arithmetic takes.  Getting this wrong made the model
    answer `1073741823:4294967294` for floordiv(-7, 4), which is neither the lane's
    answer nor tinygrad's."""
    u &= MASK64
    return u - (1 << 64) if u >> 63 else u


def numprod(u: int) -> int:
    """What `(hi >>> 0) * 4294967296 + (lo >>> 0)` is, in a double, then through
    `BigInt(...)` (which truncates toward zero) and `BigInt.asIntN(64, .)`.  The sum
    always rounds to a whole double, because `hi * 2**32` is a multiple of 2**32 and
    the spacing above 2**52 is coarser than 1."""
    return (int(float(u >> 32) * 4294967296.0 + float(u & U32))) & MASK64


# What `i64_of` returns for a record whose UNSIGNED 64-bit pattern is `u`, under
# each inbound plant.  Every entry takes and returns a PATTERN; `signed()` below
# turns one into the int64 the seam's arithmetic takes.
CIN = {
    "identity": lambda u: u,
    # `p.fst`/`p.snd` on a record whose fields are hi/lo: both undefined, and
    # `undefined >>> 0 === 0`, so the read is a TOTALISATION, not a misread.
    "fst": lambda u: 0,
    # `BigInt(p.lo >>> 0) << 32n | BigInt(p.hi >>> 0)`.
    "swap": swap_words,
    # `BigInt((p.hi >>> 0) * 4294967296 + (p.lo >>> 0))` in Number arithmetic.
    "numprod": numprod,
}


def lane(name: str, a: int, b: int) -> int:
    """THE LANE's arithmetic -- dtype.js's `floor_pair`/`cdiv_of` and their guards,
    not tinygrad's helpers.

    This is not a stylistic choice and the gate found the difference: a plant that
    totalises the INBOUND read sends `b` to `0n`, and then `ceildiv(0, 0)` raises
    ZeroDivisionError in tinygrad while dtype.js's ceildiv guard answers `0n`.
    Modelling the ORACLE instead of the lane made this instrument itself raise on
    ABI-6 -- which is ABI-6, arriving through the measuring apparatus."""
    if name == "trunc":
        return a
    if b == 0:                       # tinygrad's zero-divisor branch; ABI-6
        return a if name in ("floor_mod", "cmod") else 0
    if name in ("floor_div", "floor_mod"):
        return upstream(name, a, b)
    if name == "ceildiv":
        return -(a // -b)
    q = abs(a) // abs(b)              # cdiv truncates toward zero
    q = -q if (a < 0) != (b < 0) else q
    return q if name == "cdiv" else a - q * b


def model(arm: str, name: str, a: int, b: int) -> str | None:
    """The arm's predicted `hi:lo`, or None where the prediction is a SHAPE claim
    (`io_tup` builds a Tuple, so there is nothing to predict) rather than a value."""
    cin, cout = MODEL[arm]
    if cout == "io_tup":
        return None
    v = lane(name, signed(CIN[cin](a & MASK64)), signed(CIN[cin](b & MASK64)))
    return COUT[cout](pattern(v))


# What `pack64` returns, as the `hi:lo` string the caller will print, under each
# outbound plant.  `io_tup` is not modelled as a value: it is not an H.I64 at all,
# so it has no hi:lo to model, and the gate asserts the SHAPE instead.
COUT = {
    "identity": lambda s: s,
    "swap": lambda s: f"{s.split(':')[1]}:{s.split(':')[0]}",
}


MODEL = {
    "shipped": ("identity", "identity"),
    "plant-abi2-in-js": ("fst", "identity"),
    "plant-abi2-out-js": ("identity", "io_tup"),
    "plant-abi2-both-js": ("fst", "io_tup"),
    "plant-abi3-in-js": ("swap", "identity"),
    "plant-abi3-out-js": ("identity", "swap"),
    "plant-abi5-js": ("numprod", "identity"),
    "disarm-abi2-in-js": ("identity", "identity"),
    "disarm-abi2-out-js": ("identity", "identity"),
    "disarm-both-js": ("identity", "identity"),
}

# An H.I64 printed by `H.i64_text` is two decimal U32 words and nothing else.
HI_LO = re.compile(r"^\d+:\d+$")


def emit_rows(k: int, hi_a: int, lo_a: int, hi_b: int, lo_b: int) -> str:
    body = ["import ./tinybendygrad/dtype.bend as D",
            "import ./tinybendygrad/helpers.bend as H", "",
            "def main() -> IO(Unit):", "  do IO<Unit>:"]
    for d in DEFS:
        if d == "trunc":
            call = f"D.Dt.i64_trunc(H.i64_of_hi_lo({hi_a}, {lo_a}))"
        else:
            call = (f"D.Dt.i64_{d}(H.i64_of_hi_lo({hi_a}, {lo_a}), "
                    f"H.i64_of_hi_lo({hi_b}, {lo_b}))")
        body.append(f"    r : H.I64 <- {call}")
        body.append(f'    IO.print("SEAM {d} #{k} = " ++ H.i64_text(r))')
    return "\n".join(body) + "\n"


def emit_divergence_rows() -> str:
    """ABI-6's rows, kept OUT of the agreement set on purpose.

    A zero divisor is the one input on which tinygrad's helpers raise
    ZeroDivisionError and BOTH lanes answer a number.  So an oracle that called
    `floordiv(7, 0)` would raise inside the gate and take the whole run with it --
    which is exactly what happened to this instrument before the arithmetic was
    modelled per lane.  These rows are therefore COUNTED and REPORTED as
    `diverge`, and never entered into any agreement count."""
    body = ["import ./tinybendygrad/dtype.bend as D",
            "import ./tinybendygrad/helpers.bend as H", "",
            "def main() -> IO(Unit):", "  do IO<Unit>:"]
    for d in DEFS:
        if d == "trunc":
            continue
        hi_a, lo_a = divmod(7 & MASK64, 1 << 32)
        call = (f"D.Dt.i64_{d}(H.i64_of_hi_lo({hi_a}, {lo_a}), "
                f"H.i64_of_hi_lo(0, 0))")
        body.append(f"    r : H.I64 <- {call}")
        body.append(f'    IO.print("DIV6 {d} = " ++ H.i64_text(r))')
    return "\n".join(body) + "\n"


DIV = re.compile(r"^DIV6 (\w+) = (.*)$")


def run_cc_divergence(work: pathlib.Path) -> dict[str, str]:
    """The SAME ABI-6 rows under the C lane, compiled with cc.

    `abi.json` says 'BOTH lanes answer 0'.  Asserting that would be a citation
    where a measurement belongs, and the C lane is the one with the fixed commit, so
    it is run rather than believed.  dtype.c is byte-unchanged by this script."""
    (work / "div.bend").write_text(emit_divergence_rows())
    out = work / "div.gen.c"
    r = subprocess.run([str(BEND), str(work / "div.bend"), "-o", str(out)],
                       capture_output=True, text=True)
    if not out.exists():
        sys.exit(f"no backend emitted for the C ABI-6 rows: rc={r.returncode}\n"
                 f"{r.stdout}\n{r.stderr}")
    k = subprocess.run(["cc", "-O1", "-w", "-o", str(work / "div.gen"), str(out)],
                       capture_output=True, text=True)
    if k.returncode != 0:
        sys.exit(f"cc failed for the ABI-6 rows: {k.stderr}")
    p = subprocess.run([str(work / "div.gen")], capture_output=True, text=True,
                       timeout=300)
    return {m[1]: m[2] for m in map(DIV.match, p.stdout.splitlines()) if m}


def run(arm: str, work: pathlib.Path) -> tuple[dict[str, str], dict[str, str], int | None]:
    """Patch, compile with node's backend, run node, read stdout rows.

    Returns (rows, divergence_rows, bend_rc).  bend_rc is REPORTED, never acted on:
    dtype.bend is cold, and the two questions -- 'does this file stand alone' and
    'can the lane be built and run' -- are not the other's."""
    (work / "tinybendygrad" / "runtime" / "dtype.js").write_text(
        patch(JS_LANE.read_text(), ARMS[arm]))
    bend = work / "seam.bend"
    rows: dict[str, str] = {}
    div: dict[str, str] = {}
    brc: int | None = None
    for k, (a, b) in enumerate(FIXTURES):
        ha, la = divmod(a & MASK64, 1 << 32)
        hb, lb = divmod(b & MASK64, 1 << 32)
        bend.write_text(emit_rows(k, ha, la, hb, lb))
        out = work / "seam.js"
        if out.exists():
            out.unlink()
        r = subprocess.run([str(BEND), str(bend), "-o", str(out)],
                           capture_output=True, text=True)
        brc = r.returncode
        # The gate is on the ROWS.  No backend and no rows is a dead lane, never a
        # green one, and bend's rc on its own decides nothing.
        if not out.exists():
            sys.exit(f"no backend emitted ({arm}): rc={brc}\n{r.stdout}\n{r.stderr}")
        p = subprocess.run(["node", str(out)], capture_output=True, text=True,
                           timeout=300)
        for line in p.stdout.splitlines():
            m = ROW.match(line)
            if m:
                rows[f"{m[1]}|{a}|{b}"] = m[3]
    bend.write_text(emit_divergence_rows())
    out = work / "div.bend.js"
    if out.exists():
        out.unlink()
    subprocess.run([str(BEND), str(bend), "-o", str(out)], capture_output=True,
                   text=True)
    if not out.exists():
        sys.exit(f"no backend emitted for the ABI-6 rows ({arm})")
    p = subprocess.run(["node", str(out)], capture_output=True, text=True, timeout=300)
    for line in p.stdout.splitlines():
        m = DIV.match(line)
        if m:
            div[m[1]] = m[2]
    return rows, div, brc


# ------------------------------------------------------------------- main.
DUMP = HERE / "rows.json"


def main() -> None:
    sys.path.insert(0, str(REPO))
    keys = [f"{d}|{a}|{b}" for (a, b) in FIXTURES for d in DEFS]
    cpy = {k: pattern(upstream(k.split("|")[0],
                               *[int(x) for x in k.split("|")[1:]])) for k in keys}

    # The rows are persisted NEXT TO THIS FILE, not in $TMPDIR: an oracle in a temp
    # dir is gone before the commit, so its CPython comparison is unreproducible.
    # They are also what lets the checks below be re-derived without re-running bend.
    reuse = "--reuse" in sys.argv
    if reuse and DUMP.exists():
        saved = json.loads(DUMP.read_text())
        res, brc, div = saved["rows"], saved["bend_rc"], saved["div"]
        div["cc"] = saved["div"]["cc"]
        print(f"  reused {DUMP.name} -- bend was NOT re-run")
    else:
        res, brc, div = {}, {}, {}
        with tempfile.TemporaryDirectory() as td:
            work = pathlib.Path(td) / "tree"
            work.mkdir()
            shutil.copytree(REPO / "tinybendygrad", work / "tinybendygrad")
            for arm in ARMS:
                print(f"  --- arm {arm} ---")
                res[arm], div[arm], brc[arm] = run(arm, work)
            div["cc"] = run_cc_divergence(work)
        DUMP.write_text(json.dumps({"arms": list(ARMS), "bend_rc": brc,
                                    "lane_md5": md5(JS_LANE.read_bytes()),
                                    "rows": res, "div": div}, indent=1))

    def bad(r: dict[str, str]) -> list[str]:
        return [k for k in keys if r.get(k) != cpy[k]]

    def moved(a: str, b: str) -> list[str]:
        """Whole `name=value` lines, not row NAMES.  A name-comparing harness
        reported 0 for all 30 mutations in another unit."""
        return [k for k in keys if res[a].get(k, "\0") != res[b].get(k, "\0")]

    def modelled(arm: str) -> list[str]:
        """Rows where the arm disagrees with the arm's own exact Python model.
        Empty means EVERY row -- moved and unmoved -- is explained."""
        out = []
        for k in keys:
            d, a, b = k.split("|")
            want = model(arm, d, int(a), int(b))
            got = res[arm].get(k)
            if want is None:      # io_tup: a shape claim, checked separately
                if got is not None and HI_LO.match(got):
                    out.append(f"{k}: answered {got!r}, which IS a valid hi:lo")
            elif got != want:
                out.append(f"{k}: arm {got!r}, model {want!r}")
        return out

    print("\n" + "=" * 78)
    print("ROWS PRESENT vs ROWS EXPECTED")
    print("=" * 78)
    for arm in ARMS:
        miss = [k for k in keys if k not in res[arm]]
        print(f"  {arm:<18} present {len(keys) - len(miss):>2}/{len(keys)}"
              + (f"   MISSING {miss}" if miss else ""))

    print("\n" + "=" * 78)
    print("AGREEMENT WITH CPYTHON -- `tinygrad.helpers` CALLED, never transcribed")
    print("=" * 78)
    for arm in ARMS:
        print(f"  {arm:<18} {len(keys) - len(bad(res[arm])):>2}/{len(keys)}")

    print("\n" + "=" * 78)
    print("EXACT MODEL -- every row explained, moved AND unmoved")
    print("=" * 78)
    print("  A plant that fires on some rows and is silent on others is only a")
    print("  measurement if the silence is accounted for.  Each arm is modelled in")
    print("  Python and compared on all 30, so an unexplained 0 cannot survive.")
    for arm in ARMS:
        cin, cout = MODEL[arm]
        mm = modelled(arm)
        print(f"  {arm:<18} in={cin:<9} out={cout:<9} unexplained {len(mm)}/30")
        for m in mm[:4]:
            print(f"      {m}")
        if len(mm) > 4:
            print(f"      ... and {len(mm) - 4} more")

    print("\n" + "=" * 78)
    print("BEND'S EXIT STATUS -- reported, NOT gated on (dtype.bend is COLD)")
    print("=" * 78)
    print("  'does this file stand alone' and 'can the lane be built and run' are")
    print("  two questions and neither is the other.  The gate is on node's rows.")
    for arm in ARMS:
        print(f"  {arm:<18} bend -o rc={brc[arm]}   node rows={len(res[arm])}")

    print("\n" + "=" * 78)
    print("PLANT AND DISARM -- the DISARMS are run and listed FIRST")
    print("=" * 78)
    order = [a for a in ARMS if a.startswith("disarm")] + \
            [a for a in ARMS if a.startswith("plant")]
    for arm in order:
        kind = "DISARM" if arm.startswith("disarm") else "PLANT "
        mv = moved("shipped", arm)
        why = {
            "disarm-abi2-in-js": "p.hi -> p[\"hi\"], p.lo -> p[\"lo\"]",
            "disarm-abi2-out-js": "the same object, one line, field order swapped",
            "disarm-both-js": "both re-spellings at once",
            "plant-abi2-in-js": "p.fst/p.snd, the inbound half as it shipped",
            "plant-abi2-out-js": "io_tup, the OUTBOUND half as it shipped",
            "plant-abi2-both-js": "both halves: the file exactly as it shipped",
            "plant-abi3-in-js": "the words exchanged inbound",
            "plant-abi3-out-js": "the words exchanged OUTBOUND",
            "plant-abi5-js": "(hi * 2**32 + lo) in Number arithmetic",
        }[arm]
        print(f"\n  {kind} {arm:<18} moved {len(mv):>2}/30   {why}")
        for k in mv[:4]:
            print(f"      {k:<34} CPython {cpy[k]:<22} this arm {res[arm][k]!r}")
        if len(mv) > 4:
            print(f"      ... and {len(mv) - 4} more")
        if kind == "DISARM" and mv:
            print("      ** A DISARM THAT MOVED SOMETHING IS NOT A DISARM.")
        if kind == "PLANT" and not mv:
            print("      ** a plant that moved nothing proves nothing.")

    # The two ABI-2 halves are the finding, so state what separates them precisely.
    a, b = set(moved("shipped", "plant-abi2-in-js")), set(moved("shipped", "plant-abi2-out-js"))
    print("\n  THE TWO HALVES ARE NOT THE SAME DEFECT, and here is what separates them:")
    print(f"    inbound-only plant  moves {len(a)}/30 and answers {res['plant-abi2-in-js'][keys[0]]!r}"
          f" on row 0 -- a TOTALISATION (i64_of is 0 for every input)")
    print(f"    outbound-only plant moves {len(b)}/30 and answers {res['plant-abi2-out-js'][keys[0]]!r}"
          f" on row 0 -- not a hi:lo pair at all (io_tup built a Tuple)")
    print(f"    rows only the outbound plant moves: {sorted(b - a)}")
    print(f"    rows only the inbound plant moves:  {sorted(a - b)}")
    print("    So a gate whose only plant re-reads p.fst would report this lane green")
    print("    while pack64 still built the wrong shape.  That is why PLANT B exists.")

    npx = moved("shipped", "plant-abi5-js")
    print("\n  ABI-5's plant, attributed per OPERAND (a double has 53 mantissa bits):")
    for k in keys:
        d, a_, b_ = k.split("|")
        ops = [("a", a_)] if d == "trunc" else [("a", a_), ("b", b_)]
        badops = [nm for nm, v in ops if inexact((int(v) & MASK64) >> 32)]
        hit = "MOVED" if k in npx else "     "
        print(f"    {hit} {k:<34} inexact hi half on {','.join(badops) or '-'}")
    print("    The model above already predicts all 30 exactly, so the moved set is")
    print("    not a coincidence list -- it is a consequence.")

    print("\n" + "=" * 78)
    print("ABI-6 -- CLASSIFIED, NOT COUNTED BLIND")
    print("=" * 78)
    print("  `abi.json` states ABI-6 as 'both lanes answer 0 where tinygrad's helpers")
    print("  raise ZeroDivisionError'.  That is TRUE OF `ceildiv` AND FALSE OF THE")
    print("  OTHER FOUR: tinygrad/helpers.py:74 and :77 guard `cdiv` and `floordiv`")
    print("  with an explicit `if y != 0 else 0`, so only `ceildiv` ever raises.")
    print("  A block that reported 5 divergences here would have counted 4 agreements")
    print("  as divergences, which is JSL2-7 with the sign flipped.")
    div6_rows, agree6_rows = [], []
    for d in DEFS:
        if d == "trunc":
            continue
        try:
            want = pattern(upstream(d, 7, 0))
            kind = "agree"
            agree6_rows.append(d)
        except ZeroDivisionError as e:
            want = f"ZeroDivisionError: {e}"
            kind = "DIVERGE"
            div6_rows.append(d)
        got = div["shipped"].get(d, "<absent>")
        gotc = div["cc"].get(d, "<absent>")
        print(f"  {d:<10} tinygrad -> {want:<38} node {got:<10} cc {gotc:<10} {kind}")
    print(f"\n  {len(div6_rows)} diverge ({', '.join(div6_rows)}), "
          f"{len(agree6_rows)} agree.  Counted `diverge`, never `pass`: the lanes")
    print("  AGREE on the zero divisor, so no lane-against-lane check can see this,")
    print("  and an oracle that called floordiv(7, 0) would raise inside this gate.")
    div6 = div6_rows == ["ceildiv"] and all(
        div["shipped"].get(d) == div["cc"].get(d) for d in DEFS if d != "trunc")

    print("\n" + "=" * 78)
    print("VERDICT")
    print("=" * 78)
    checks = [
        ("the shipped JS lane agrees with CPython on all 30 rows",
         not bad(res["shipped"])),
        ("the shipped JS lane PRINTED all 30 rows, so none is absent",
         len(res["shipped"]) == len(keys)),
        ("every arm printed all 30 rows, so no arm is a silent no-op",
         all(len(res[a]) == len(keys) for a in ARMS)),
        ("every arm matches its exact model on all 30 rows, so no 0 is unexplained",
         all(not modelled(a) for a in ARMS)),
        ("PLANT A: the inbound half alone moves rows (it used to ship)",
         len(moved("shipped", "plant-abi2-in-js")) > 0),
        ("PLANT A is a TOTALISATION, not a misread: it answers 0:0 on every row",
         all(res["plant-abi2-in-js"][k] == "0:0" for k in keys)),
        ("every row PLANT A does NOT move has the totalised answer as its true answer",
         all(cpy[k] == "0:0" for k in keys if k not in a)),
        ("PLANT B: the OUTBOUND half alone moves rows -- no inbound plant sees this",
         len(moved("shipped", "plant-abi2-out-js")) > 0),
        ("PLANT B answers nothing that is a valid hi:lo pair on any row",
         all(not HI_LO.match(res["plant-abi2-out-js"][k]) for k in keys)),
        ("PLANT C: the file as it shipped moves at least as many rows as either half",
         len(moved("shipped", "plant-abi2-both-js")) >= max(len(a), len(b))),
        ("PLANT D: the words exchanged inbound move rows",
         len(moved("shipped", "plant-abi3-in-js")) > 0),
        ("PLANT E: the words exchanged OUTBOUND move rows",
         len(moved("shipped", "plant-abi3-out-js")) > 0),
        ("PLANT F: Number arithmetic moves rows (BigInt is load-bearing, ABI-5)",
         len(npx) > 0),
        ("DISARM inbound moved 0", moved("shipped", "disarm-abi2-in-js") == []),
        ("DISARM outbound moved 0", moved("shipped", "disarm-abi2-out-js") == []),
        ("DISARM both moved 0", moved("shipped", "disarm-both-js") == []),
        ("ABI-6: exactly ONE zero-divisor seam diverges from upstream, and it is "
         "ceildiv (the 4 others are agreements, not divergences)",
         div6_rows == ["ceildiv"]),
        ("ABI-6: node and cc answer IDENTICALLY on all five zero-divisor rows, so no "
         "lane-agreement check can see the divergence",
         all(div["shipped"].get(d) == div["cc"].get(d) for d in DEFS if d != "trunc") and div6),
    ]
    ok = True
    for name, good in checks:
        print(f"  {'PASS' if good else 'FAIL'}  {name}")
        ok &= good

    print("\n" + "=" * 78)
    print("WHAT THIS GATE STILL CANNOT SEE")
    print("=" * 78)
    print("  The 12 F32 rows of abi/abi_gate.py (bf16, fp16, fp8_from, fp8_to).")
    print("  fp16(1.5) and fp8_to(0x3C) are ABI-4, a DIFFERENT convention in a")
    print("  DIFFERENT half of the same file, and all 30 rows here are I64.")
    print("  ABI-6 (both lanes answer 0 where tinygrad's helpers raise")
    print("  ZeroDivisionError) is a divergence from UPSTREAM, not between lanes, so")
    print("  no lane-agreement check can see it.  Counted diverge, never pass.")
    print("\n  gate rc:", 0 if ok else 1)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
