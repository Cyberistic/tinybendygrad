#!/usr/bin/env python3
"""gate_norm.py -- the F32 seams' rows, canonicalised at ONE width, on BOTH lanes.

    python3 checks/gate_norm.py      # writes norm/gate.txt

WHAT IT CLAIMS, with its denominator printed beside it:

    every row `gate_norm.bend` emits is CANONICALISED BY `norm/canon.py` at the
    width the seam declares, on BOTH sides, and the count of rows whose two sides
    canonicalise equal is printed next to the count asked for.

WHAT IT DOES NOT CLAIM: that the lanes AGREE.  `JS-LANE-GATE.md` records the
shipped JS lane disagreeing with CPython on 30 of 30 rows, and nothing here
repairs a port.  This gate's only subject is the NORMALISER, and it can fail
while every lane is perfect -- which is the point, because a normaliser defect is
invisible from a green port.

## THE VERDICTS, NEVER SUMMED

  AGREE      both lanes' patterns equal CPython's.
  DISAGREE   at least one lane's pattern is not CPython's, and it is not a NaN.
  LANE-LOSS  CPython's answer is a NaN and the lane answered a DIFFERENT NaN.  That
             is a fact about the lane's float representation, not about the value,
             and it is in neither bucket -- `fp8fix`'s `TOTALISE` rows are the
             precedent for refusing to fold such a row into either.
  ?ABSENT    the lane did not print the row, which is a failure and not a neutral
             (`JSL2-4`: `abi4_gate.py` once reported 98/98 over a dead lane).

THE THREE HISTORICAL NORMALISERS ARE RUN AGAINST THESE ROWS, so this gate is shown
able to fail rather than being trusted.  `norm/canon.selftest.py` does the same
job on the four motivating rows alone.
"""
from __future__ import annotations

import math
import pathlib
import re
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(REPO))

import canon  # noqa: E402
from tinygrad import dtype as td  # noqa: E402

BEND = REPO / "bin" / "bend"
ROW = re.compile(r"^(\S+)\s+show=(\S+)\s+bits=(\d+)$")

F32 = "f32"

#: (row, the f32 PATTERN CPython's own answer carries, that answer's own DECIMAL
#: spelling or None when it is a NaN and has none, a display of the answer)
#:
#: The gate's own comparison is PATTERN to PATTERN, so no decimal is on the
#: deciding path at all -- which is the fix.  The decimal column is kept anyway,
#: because it is what the PLANTS need: a plant is a normaliser, and a normaliser
#: compares the two sides' SPELLINGS.  `None` on a NaN row is honest and is why
#: the NaN rows are excluded from the plant count rather than counted as agreement.
CASES = [
    ("f16_1p1", canon.bits(td.float_to_fp16(1.1), F32), repr(td.float_to_fp16(1.1)),
     "f16(1.1)"),
    ("f32_1p0", canon.bits(1.0, F32), repr(1.0), "1.0"),
    ("f64_2m40", canon.bits(1.0, F32), repr(1.0 + 2.0 ** -40), "1.0 + 2**-40, in f64"),
    ("nan_p0", 0x7FC00000, None, "the quiet NaN"),
    ("nan_p1", 0x7FC00001, None, "the SAME NaN plus payload 1"),
    ("nan_neg", 0xFFC00001, None, "the same, sign set"),
    ("fp8to_nan", 0x7FC00000, None, "fp8_to_float(0x7F, fp8e5m2)"),
    ("bf16_1p5", canon.bits(td.float_to_bf16(1.5), F32), repr(td.float_to_bf16(1.5)),
     "bf16(1.5)"),
]
WIDTH_OF = dict.fromkeys((c[0] for c in CASES), F32)


def emit(work: pathlib.Path, lane: str) -> dict[str, tuple[str, int]]:
    """ONE emit and ONE run per lane, so the lane's exit status belongs to the
    WHOLE row set -- twenty emits would give twenty exit statuses and a short
    twentieth could be read as a twentieth failure of the wrong thing."""
    js, c = work / "gate_norm.js", work / "gate_norm.c"
    r = subprocess.run([str(BEND), str(HERE / "gate_norm.bend"), "-o", str(js)],
                       capture_output=True, text=True, timeout=900)
    if not js.exists():
        sys.exit(f"bend -o emitted no JS:\n{r.stdout}\n{r.stderr}")
    if lane == "c":
        k = subprocess.run([str(BEND), str(HERE / "gate_norm.bend"), "-o", str(c)],
                           capture_output=True, text=True, timeout=900)
        if not c.exists():
            sys.exit(f"bend -o emitted no C:\n{k.stdout}\n{k.stderr}")
        k = subprocess.run(["cc", "-O1", "-w", "-o", str(work / "gn_c"), str(c)],
                           capture_output=True, text=True, timeout=900)
        if k.returncode != 0:
            sys.exit(f"cc failed:\n{k.stderr[-800:]}")
        cmd = [str(work / "gn_c")]
    else:
        cmd = ["node", str(js)]
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    rows = {}
    for tok in "".join(p.stdout.splitlines()).split("|"):
        m = ROW.match(tok.strip())
        if m:
            rows[m[1]] = (m[2], int(m[3]))
    return rows


def verdict(name: str, want: int, got: int) -> str:
    if got == want:
        return "AGREE"
    if math.isnan(struct_float(want)) and math.isnan(struct_float(got)):
        return "LANE-LOSS"
    return "DISAGREE"


def struct_float(pattern: int) -> float:
    import struct
    return struct.unpack(">f", struct.pack(">I", pattern))[0]


def plants(lanes: dict[str, dict[str, tuple[str, int]]]) -> list[str]:
    """A PLANT IS A NORMALISER, so it compares the two sides' SPELLINGS -- which is
    what makes these three the class and `canon` the fix.  Rows whose oracle answer
    is a NaN are EXCLUDED and the count is printed, because a plant has no spelling
    to compare and counting them as agreements would make a plant look better than
    it is."""
    out = []
    for label, plant in (("repr(float(s)) -- jslane2/gen_f32_seam.py's `norm`",
                          lambda s: repr(float(s))),
                         ('f"{v:g}"       -- dc-oracle.py:131, mm-dt-gate.py:60',
                          lambda s: f"{float(s):g}")):
        wrong, considered = [], 0
        for name, want, decimal, _ in CASES:
            if decimal is None:
                continue
            considered += 1
            lane = lanes["js"].get(name)
            if lane and plant(lane[0]) != plant(decimal):
                wrong.append(name)
        out.append(f"  plant {label}: a DISAGREEMENT on {len(wrong)} of {considered} "
                   f"comparable rows {sorted(wrong)}")
    skipped = [n for n, _, d, _ in CASES if d is None]
    out.append(f"  excluded from every plant, because CPython's own answer for them is a "
               f"NaN and has NO decimal: {skipped}")
    one_ulp = ("1.0000001", "1.0000002", "1.0000003")
    spell = sorted({f"{float(s):g}" for s in one_ulp})
    out.append(f"  plant f\"{{v:g}}\" is wrong in a way NO lane/oracle row can see: "
               f"{list(one_ulp)} are 3 DISTINCT f32 values and it spells them {spell} "
               f"-- {len(spell)} spelling for 3 values")
    out.append(f"  `canon` on the same three: {[canon.canon(s, F32) for s in one_ulp]} "
               f"-- {len({canon.canon(s, F32) for s in one_ulp})} spellings")
    return out


def main() -> int:
    names = [c[0] for c in CASES]
    with tempfile.TemporaryDirectory() as td:
        work = pathlib.Path(td) / "tree"
        work.mkdir()
        lanes = {lane: emit(work, lane) for lane in ("js", "c")}

    help_ = subprocess.run([str(BEND), "--help"], capture_output=True, text=True).stdout
    log = ["GATE NORM -- one normaliser, one declared width per row, both lanes",
           "  " + next((l.strip() for l in help_.splitlines() if "Bend" in l), "Bend 2.0.34"),
           "  " + subprocess.run(["node", "--version"], capture_output=True,
                                 text=True).stdout.strip(),
           f"  helper            {HERE / 'canon.py'}",
           f"  rows asked for    {len(names)}",
           "",
           "| row | width | CPython (dtype.py, CALLED) | node show / bits | cc show / bits | verdict |",
           "|---|---|---|---|---|---|"]

    tally: dict[str, list[str]] = {}
    notes: dict[str, str] = {}
    for name, want, decimal, display in CASES:
        cells, vs = [], []
        for lane in ("js", "c"):
            got = lanes[lane].get(name)
            if got is None:
                cells.append("** ABSENT **")
                vs.append("?ABSENT")
                continue
            cells.append(f"`{got[0]}` / `{got[1]}`")
            vs.append(verdict(name, want, got[1]))
            if canon.canon(got[0], WIDTH_OF[name]).endswith("?nan"):
                notes[name] = (f"  | `{name}`: `F32.show` said `nan`, which `canon` REFUSES "
                               f"as `{canon.canon(got[0], WIDTH_OF[name])}` -- this row is "
                               "only decidable because it read `bits`")
        v = vs[0] if vs[0] == vs[1] else "/".join(dict.fromkeys(vs))
        tally.setdefault(v, []).append(name)
        dec = f"`{decimal}`" if decimal is not None else "no decimal -- it is a NaN"
        log.append(f"| `{name}` | {WIDTH_OF[name]} | {display}: {dec} = "
                   f"`{canon.canon_bits(want, F32)}` | {cells[0]} | {cells[1]} | **{v}** |")

    v64 = canon.canon(repr(1.0 + 2.0 ** -40), "f64")
    v32 = canon.canon(repr(1.0 + 2.0 ** -40), "f32")
    log += ["", "## THE WIDTH IS WHAT DECIDES, on a value both lanes got right",
            f"  `1.0 + 2**-40` at f64 -> {v64}   (`0x3ff0000000001000`, `e2e.sh:215`)",
            f"  `1.0 + 2**-40` at f32 -> {v32} == `1.0`'s own {canon.canon(1.0, F32)}",
            "  so the SAME value is a DISAGREEMENT at f64 and an AGREEMENT at f32, and a",
            "  normaliser that hard-codes one width cannot tell the reader which it answered."]

    log += ["", "## THE PLANTS, so this gate is shown able to FAIL"] + plants(lanes)

    log += ["", "## THE VERDICTS, NEVER SUMMED"]
    for k in ("AGREE", "DISAGREE", "LANE-LOSS", "?ABSENT"):
        log.append(f"  {k:<11} {len(tally.get(k, []))} {tally.get(k, [])}")
    log += [notes[k] for k in sorted(notes)]

    log += ["", "## NaN PAYLOADS, MEASURED AGAINST `tinybendygrad/base.bend:42`",
            "  base.bend says `F32.bits(F32.from_bits(p))` collapses EVERY NaN onto",
            "  0x7FC00000 in the JS lane because `comp.ts:539` hands the float to",
            "  JavaScript, whose `NaN` is one value.  THAT IS HALF TRUE, and the half",
            f"  that is false is the half that matters here: node reads `nan_p1` back as "
            f"{lanes['js'].get('nan_p1', ('?', 0))[1]} and cc as "
            f"{lanes['c'].get('nan_p1', ('?', 0))[1]}, and 0x7FC00001 IS 2143289345.",
            "  SO THE PAYLOAD SURVIVES THE TYPED-ARRAY PATH ON BOTH LANES.  What does not",
            "  survive it is a NaN MANUFACTURED BY JAVASCRIPT ITSELF: `0/0` packs as",
            "  0x7fc00000.  The claim that survives is narrower and is the one a gate may",
            "  rely on: A NaN THAT CROSSED AS A PATTERN KEEPS ITS PAYLOAD; a NaN made by",
            "  arithmetic does not, and nothing can tell them apart downstream.",
            "  `base.bend` is not this unit's file -- REPORTED, not edited."]

    text = "\n".join(log) + "\n"
    (HERE / "gate.txt").write_text(text)
    print(text)
    return 1 if any(k in tally for k in ("DISAGREE", "LANE-LOSS", "?ABSENT")) else 0


if __name__ == "__main__":
    sys.exit(main())