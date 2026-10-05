#!/usr/bin/env python3
"""canon.selftest.py -- the four rows that MOTIVATED the helper, plus the property
the helper's soundness rests on.

    python3 .agents/slop/norm/canon.selftest.py

WHY THIS IS NOT A UNIT TEST AFTER THE FACT.  Each of the four rows below is a
case a gate in this tree ACTUALLY MIS-JUDGED or WOULD HAVE MIS-JUDGED, and each
one is an assertion that cannot pass by accident:

  1. `1.1` in f16.  `jslane2/gen_f32_seam.py`'s `norm` was `repr(float(s))` with
     no round trip, and would have called this a LANE disagreement for a
     FORMATTING reason: `f32_show` prints the shortest f32-round-tripping
     `1.0996094` where CPython, holding a double, prints `1.099609375`.  The
     assertion is that the two spellings CANONICALISE EQUAL, so it fails on the
     old `norm` and passes on this one -- which is the whole claim.
  2. `1.0`.  `repr(ConstFloat(1.0))` is `ConstFloat(1.0)` and `F32.show(1.0)` is
     `1` (MEASURED: `comp.ts:788` shows the `.0` belongs to the diagnostic
     printer, not to `F32.show`, so JSL2-7's `448` vs `448.0` is real).  Bits on
     both sides are `0x3f800000`.
  3. `1.0 + 2**-40`.  `0x3ff0000000001000` at f64, EXACTLY `1.0` at f32
     (`e2e.sh:215` calls it "THE ROW f32 CANNOT HAVE"), and the assertion is that
     the WIDTH IS WHAT DECIDES -- so a normaliser with the width hard-coded
     fails here whichever width it chose.
  4. two NaNs differing only in payload.  `canon` REFUSES a spelling and
     `canon_bits` separates them; the assertion is that all three answers -- the
     refusal and the two patterns -- are DISTINCT STRINGS.

## THE PROPERTY, NOT JUST THE FOUR ROWS

`canon` parses a decimal spelling and re-rounds it, which is sound only because
`f32_show` prints a shortest form that READS BACK to the same f32
(`references/bend/bend2/bend.ts:1197`: the loop `for (p = 1; x === x && p <= 9 &&
f32_round(s) !== x; p += 1)` cannot exit until the round trip holds).  That is a
structural argument AND it is measured here, because four points do not establish
a property and an argument that is never run is how this class of defect gets
believed.

THE SWEEP IS A SAMPLE AND IS CALLED ONE.  2^32 patterns through `node` costs
hours.  What is swept is stratified and deterministic, and the count is printed
so a reader can see what was and was not covered:

  * every 2^14th pattern of the whole f32 space (262,144, uniform over sign,
    exponent, mantissa and the whole subnormal/normal boundary);
  * every 32nd pattern of the ENTIRE subnormal window (262,144);
  * every 2^14th pattern of the NaN bands only, and the four payload patterns
    `0x7fc00000`/`0x7fc00001`/`0xffc00001`/`0xffc00002` individually.

NaN patterns are EXCLUDED from the round-trip assertion and counted separately,
because `f32_show` answers `nan` for every one of them and there is nothing to
read back -- and counting them as a loss would be a row that fails for the right
reason and means nothing.
"""
from __future__ import annotations

import math
import os
import pathlib
import struct
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(REPO))

import canon  # noqa: E402
from tinygrad import dtype as td  # noqa: E402

BEND = REPO / "bin" / "bend"
F32 = 2 ** 32
#: `rows` RECURSES once per pattern, and node's stack is the limit: 65,536 of them
#: is `bend: memory fault (machine stack overflow?)`, MEASURED.  4,096 is the
#: chunk that runs, and `checks/gate_dtype.bend:8-13` measured the same shape of
#: cost for the same reason.
CHUNK = 4096

# (label, start, step, count) -- see the docstring.  Deterministic and printed.
SWEEPS = [
    ("whole f32 space, every 2^14th", 0, 1 << 14, F32 >> 14),
    ("the whole subnormal window, every 32nd", 1, 32, (1 << 23) >> 5),
    ("the NaN bands, every 2^14th", 0x7F800000, 1 << 14, (0xFF800000 - 0x7F800000) >> 14),
]
EXACT = [0x7FC00000, 0x7FC00001, 0xFFC00001, 0xFFC00002,
         0x3F800000, 0x3F800001, 0x7F7FFFFF, 0x00000001, 0x80000001]


def patterns() -> list[int]:
    out: list[int] = []
    for _, lo, step, n in SWEEPS:
        out += [lo + step * i for i in range(n)]
    return out + EXACT


def spellings(work: pathlib.Path, pats: list[int]) -> dict[int, str]:
    """The REAL `f32_show`, from the REAL emitted JS -- called, never transcribed.

    `JSL2-5` records the cost of assuming a re-spelling is one: `h * 2**32 + l`
    "looked like a re-spelling and moved 15 of 30 rows".
    """
    js = work / "f32show.js"
    r = subprocess.run([str(BEND), str(HERE / "f32show.bend"), "-o", str(js)],
                       capture_output=True, text=True, timeout=600)
    if not js.exists():
        sys.exit(f"bend -o emitted nothing for f32show.bend:\n{r.stdout}\n{r.stderr}")
    got: dict[int, str] = {}
    for i in range(0, len(pats), CHUNK):
        chunk = pats[i:i + CHUNK]
        env = dict(os.environ, NS_LO=str(chunk[0]), NS_STEP="0", NS_COUNT=str(len(chunk)))
        p = subprocess.run(["node", str(js)], env=env, capture_output=True, text=True,
                           timeout=600)
        toks = p.stdout.split()
        if len(toks) != 2 * len(chunk):
            sys.exit(f"f32show answered {len(toks)} tokens for {len(chunk)} patterns:\n"
                     f"{p.stdout[-400:]}\n{p.stderr[-400:]}")
        got.update({int(toks[2 * k]): toks[2 * k + 1] for k in range(len(chunk))})
    return got


def four_rows(bad: list[str]) -> list[str]:
    """The four motivating rows, each as its own line, each a proposition."""
    lines = []
    a = canon.canon("1.0996094", "f32")
    b = canon.canon(repr(td.float_to_fp16(1.1)), "f32")
    lines.append(f"1  `1.1` in f16, f32_show says `1.0996094` -> {a} | "
                 f"CPython says {td.float_to_fp16(1.1)!r} -> {b} | "
                 f"{'AGREE' if a == b else 'DISAGREE'}")
    if a != b:
        bad.append("1: a FORMATTING difference is being reported as a VALUE one")
    if repr(td.float_to_fp16(1.1)) == "1.0996094":
        bad.append("1: `repr(float_to_fp16(1.1))` is now `1.0996094`, so this row no "
                   "longer exercises the trap and must be REPLACED, not kept")

    a = canon.canon("1", "f32")
    b = canon.canon_bits(0x3F800000, "f32")
    lines.append(f"2  `1.0`: `F32.show` says `1` -> {a} | its bits say {b} | "
                 f"{'AGREE' if a == b else 'DISAGREE'}")
    if a != b:
        bad.append("2: `F32.show(1.0)` is `1` and its bits are `0x3f800000`, and those "
                   "two canonical spellings differ")
    if canon.canon("ConstFloat(1.0)", "f32") == a:
        bad.append("2: `ConstFloat(1.0)` canonicalised to a float, so `canon` is parsing "
                   "a Python repr as a value and would compare two PROGRAMS")

    v = 1.0 + 2.0 ** -40
    f64, f32 = canon.canon(repr(v), "f64"), canon.canon(repr(v), "f32")
    lines.append(f"3  `1.0 + 2**-40`: f64 -> {f64} | f32 -> {f32} | "
                 f"{'WIDTH DECIDES' if f64 != f32 else 'WIDTH IGNORED'}")
    if f64 == f32:
        bad.append(f"3: `1.0 + 2**-40` canonicalises the same at f64 and f32 ({f64})")
    if f32 != canon.canon(1.0, "f32"):
        bad.append(f"3: at f32 it is {f32}, which is not `1.0`'s {canon.canon(1.0, 'f32')}")
    if f64 != "f64:3ff0000000001000":
        bad.append(f"3: the f64 spelling is {f64}, not `f64:3ff0000000001000`, so the value "
                   "moved and this is no longer the row it was written for")

    three = [canon.canon("nan", "f32"), canon.canon_bits(0x7FC00001, "f32"),
             canon.canon_bits(0x7FC00000, "f32")]
    lines.append(f"4  two NaNs: `{three[1]}` vs `{three[2]}` vs a bare spelling "
                 f"`{three[0]}` | {'ALL THREE DISTINCT' if len(set(three)) == 3 else 'COLLAPSED'}")
    if len(set(three)) != 3:
        bad.append("4: a spelling and two payloads collapse to fewer than three answers, "
                   "so a NaN difference is being reported as an agreement")

    lines.append(f"J  JSL2-7's `448` vs `448.0`: {canon.canon('448', 'f32')} vs "
                 f"{canon.canon('448.0', 'f32')} | "
                 f"{'AGREE' if canon.canon('448', 'f32') == canon.canon('448.0', 'f32') else 'DISAGREE'}")
    if canon.canon("448", "f32") != canon.canon("448.0", "f32"):
        bad.append("JSL2-7: `448` and `448.0` canonicalise differently")
    return lines


def injective(bad: list[str]) -> str:
    """`canon` must be INJECTIVE on the f32 value space, or two different values get
    one answer and a gate calls them a match.  Deterministic sweep, count printed."""
    seen: dict[str, int] = {}
    collided = 0
    for p in range(0, F32, 4096):
        x = struct.unpack(">f", struct.pack(">I", p))[0]
        if math.isnan(x):
            continue
        k = canon.canon(x, "f32")
        if seen.setdefault(k, p) != p:
            collided += 1
    if collided:
        bad.append(f"injectivity: {collided} distinct f32 patterns share one spelling")
    return f"injectivity over {len(seen)} non-NaN f32 patterns: {collided} collisions"


def round_trip(spell: dict[int, str], bad: list[str]) -> str:
    """`float(f32_show(p))` must round back to `p`, or `canon` is lossy for `p`."""
    lost, skipped, seen = 0, 0, 0
    for p, s in spell.items():
        x = struct.unpack(">f", struct.pack(">I", p))[0]
        if math.isnan(x):
            skipped += 1
            continue
        seen += 1
        if canon.bits(float(s), "f32") != p:
            lost += 1
            if lost == 1:
                bad.append(f"round trip: f32_show's spelling for {p:#010x} is `{s}`, "
                           f"which reads back as {canon.bits(float(s), 'f32'):#010x}")
    return (f"f32_show round trip over {seen} patterns: {lost} lost "
            f"({skipped} NaN patterns skipped -- `f32_show` answers `nan` for every "
            "one of them and there is nothing to read back)")


def plants(bad: list[str]) -> list[str]:
    """THE THREE HISTORICAL NORMALISERS, RUN AGAINST THE FOUR ROWS.

    A row that no instrument can get wrong is not a row.  `agent-core.md` asks for
    plants by name and for a `0` to be called a theorem rather than a gap, so each
    normaliser below is asked WHICH rows it gets wrong -- and the answer is not the
    one I expected, which is the point of asking rather than asserting.

    MEASURED, AND IT CORRECTS THE BRIEF'S OWN STORY IN ONE PLACE:

      * `repr(float(s))` -- `jslane2/gen_f32_seam.py`'s `norm` -- gets the f16
        `1.1` row WRONG (`1.0996094` against `1.099609375`) and gets `1.0`,
        `448` and `nan` RIGHT.  **So it fixes HALF the trap, exactly as
        `mm-dt-gate.py:60` does**: `repr(float(s))` re-formats an integral float as
        `448.0`, which is what JSL2-7 needed, and it cannot touch the shortest-form
        half.  The trap is not one trap; it is two, and the three instances of this
        class each fixed one of them.

      * `f"{v:g}"` -- `dc-oracle.py:131` -- gets the f16 `1.1` row RIGHT (both
        spellings truncate to `1.09961`) and is WRONG IN A WAY NO ROW PAIR CAN SEE:
        six significant digits maps `1.0000001`, `1.0000002` and `1.0000003` -- three
        DISTINCT f32 values -- onto the single spelling `1`.  **The fixture that
        exposes it is not a lane/oracle disagreement at all; it is two DIFFERENT
        values inside one side.**  That is a new kind of row and no gate in this
        tree has one.  `cstyle-live/cstyle-numbers.py:5` states the same reason for
        printing hex instead, and had it in prose rather than as a row.
    """
    f16_11 = repr(td.float_to_fp16(1.1))
    loopy = repr(1.0 + 2.0 ** -40)
    # (a) `jslane2/gen_f32_seam.py`'s `norm`, VERBATIM.  No round trip.
    a = lambda s: repr(float(s))  # noqa: E731
    # (b) `dc-oracle.py:131` / `mm-dt-gate.py:60`'s integral half.  SIX digits.
    b = lambda s: f"{float(s):g}"  # noqa: E731

    rows = [("1  `1.1` in f16", "1.0996094", f16_11),
            ("2  `1.0`", "1", "1.0"),
            ("3  `1.0 + 2**-40` at f64", loopy, "1.0"),
            ("J  `448`", "448", "448.0"),
            ("N  `nan`", "nan", "nan")]
    out, evidence = [], {}
    for name, plant in (("repr(float(s))", a), ("f\"{v:g}\"", b)):
        wrong = [n for n, lane, oracle in rows if plant(lane) != plant(oracle)]
        out.append(f"  plant({name}) gets WRONG, of the five lane/oracle rows: "
                   f"{wrong or 'NONE'}")
        evidence[name] = wrong
    one_ulp = ("1.0000001", "1.0000002", "1.0000003")
    spells = [b(s) for s in one_ulp]
    out.append(f"  plant(f\"{{v:g}}\") on THREE DISTINCT f32 values one ULP apart "
               f"{one_ulp} -> {spells}: {len(set(spells))} spelling(s)")
    if len(set(spells)) == 1:
        evidence['f"{v:g}"'] = ["the 1-ULP collision"]
    elif len(set(spells)) == 3:
        bad.append("plants: `%g` no longer collides three 1-ULP-apart f32 values, so the "
                   "fixture that exposes `dc-oracle.py:131` needs replacing")
    if len({canon.canon(s, 'f32') for s in one_ulp}) != 3:
        bad.append("plants: the helper does NOT separate the three 1-ULP-apart f32 "
                   "values, so the collision is not one `canon` introduces")
    out.append(f"  the helper on the same three: "
               f"{[canon.canon(s, 'f32') for s in one_ulp]} -- 3 distinct, no collision")
    out.append(f"  plant(repr(float(s))) at f64 on `1.0 + 2**-40`: {a(loopy)} vs {a('1.0')}"
               f" -> DISAGREE; the helper at f32 says {canon.canon(1.0 + 2.0 ** -40, 'f32')}"
               ", which is `1.0`'s own spelling")
    for name, seen in evidence.items():
        if not seen:
            bad.append(f"plants: NO row in this file gets `{name}` wrong, so nothing here "
                       "distinguishes it from the helper")
    out.append(f"  every plant is distinguished by at least one row: "
               f"{ {k: len(v) for k, v in evidence.items()} }")
    return out


def main() -> int:
    bad: list[str] = []
    print("THE FOUR MOTIVATING ROWS")
    for line in four_rows(bad):
        print("  " + line)
    print("\nTHE PROPERTIES THE HELPER STANDS ON")
    print("  " + injective(bad))
    work = pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / "normwork"
    work.mkdir(parents=True, exist_ok=True)
    pats = patterns()
    print(f"  sweep size {len(pats)} of 2^32, stratified: "
          + "; ".join(f"{n} {lo:#x}+{st}x{c}" for n, lo, st, c in SWEEPS)
          + f"; plus {len(EXACT)} exact")
    print("  " + round_trip(spellings(work, pats), bad))
    print("\nTHE PLANTS, so each row is shown able to FAIL")
    for line in plants(bad):
        print(line)
    print()
    for b in bad:
        print("  FAIL " + b)
    print(f"\n{len(bad)} failure(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())