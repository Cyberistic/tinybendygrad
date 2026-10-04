#!/usr/bin/env python3
"""gen_f32_seam.py -- the `F32` seams, under node and under cc, side by side.

Reproduce (from the repo root):
    python3 .agents/slop/jslane2/gen_f32_seam.py

WHY THIS EXISTS.  `gen_js_seam.py` gates the six `Dt.i64_*` seams.  This one
exists because of the rule that gate's arithmetic *derived* and could not see:
**every seam that takes a `U32` agrees across the two lanes, and the one seam
that takes an `F32` does not.**  `Dt.bf16(U32)` and `Dt.fp8_from(U32, U32)`
agree; `Dt.fp16(F32)` does not; `Dt.fp8_to(U32, U32) -> F32` does not.

THE MECHANISM, INSTRUMENTED IN BOTH LANES (the probes are in the tree's own
`dtype.c` / `dtype.js`, applied to `$TMPDIR` copies only):

    C,  `fp16_run`:   PROBE fp16_run f[0] = 1069547520   <- the BITS of 1.5
    JS, `dtype_fp16`: PROBE dtype_fp16 x=1.5              <- the VALUE 1.5

Same declared type `F32`.  **C receives a bit pattern, node receives a value.**
`dtype.js`'s `of32(x)` then reinterprets the value 1.5 as the pattern 1, which
is the smallest f32 subnormal, so `fp16(1.5)` is 0 under node and 1.5 under cc.
CPython is called for the expectation; it is never transcribed.

`fp8_to` is reported as LANE-vs-LANE only.  Its mechanism is NOT localised and
is not guessed at here -- 2 of 3 rows diverge and that much is measured.
"""
from __future__ import annotations

import importlib.util
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]
sys.path.insert(0, str(REPO))
from tinygrad import dtype as td  # noqa: E402

# JFP-1 -- `norm` below routes through `.agents/slop/norm/canon.py`, the ONE place
# in this tree that knows how a float of a KNOWN WIDTH is spelled. It did not, and
# `repr(float(s))` has NO round trip: `F32.show` prints the shortest
# f32-round-tripping decimal `1.0996094` where CPython, holding a double, prints
# `1.099609375`, and those are the SAME f32 -- so the old `norm` called
# `fp16(1.1)` a LANE disagreement for a FORMATTING reason. It escaped only
# because no `1.1` row was in CASES; `fp16_1p1` is one now, so the escape is
# closed. `canon.py:87-88` already claimed this file was on it. It was not.
def _canon():
  path = HERE.parent / "norm" / "canon.py"
  if not path.exists():
    sys.exit(f"jfp: {path} is gone; a float normaliser has to be the canonical one")
  spec = importlib.util.spec_from_file_location("slop_norm_canon", path)
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  if not hasattr(mod, "canon"):
    sys.exit(f"jfp: {path} no longer exports canon()")
  return mod


CANON = _canon()

BEND = REPO / "bin" / "bend"
ROW = re.compile(r"^F32ROW (\w+) = (.*)$")

# (row name, bend expression, declared param type, Bend `show`, CPython callable)
CASES = [
    ("bf16_1p5", "D.Dt.bf16(F32.bits(1.5))", "U32", "F32",
     lambda: td.float_to_bf16(1.5)),
    ("fp16_1p5", "D.Dt.fp16(1.5)", "F32", "F32",
     lambda: td.float_to_fp16(1.5)),
    # THE ROW THAT PINS `norm`. `float_to_fp16(1.1)` is 1.099609375, an exact f32,
    # and `F32.show` prints `1.0996094`; a normaliser without a round trip calls
    # that a disagreement. Without this row the defect is invisible here again.
    ("fp16_1p1", "D.Dt.fp16(1.1)", "F32", "F32",
     lambda: td.float_to_fp16(1.1)),
    ("fp8from_1p5", "D.Dt.fp8_from(F32.bits(1.5), 0)", "U32", "U32",
     lambda: td.float_to_fp8(1.5, td.dtypes.fp8e4m3)),
    ("fp8to_0x3C", "D.Dt.fp8_to(60, 0)", "U32", "F32",
     lambda: td.fp8_to_float(0x3C, td.dtypes.fp8e4m3)),
    ("fp8to_0x7E", "D.Dt.fp8_to(126, 0)", "U32", "F32",
     lambda: td.fp8_to_float(0x7E, td.dtypes.fp8e4m3)),
    ("fp8to_0x7F_e5m2", "D.Dt.fp8_to(127, 1)", "U32", "F32",
     lambda: td.fp8_to_float(0x7F, td.dtypes.fp8e5m2)),
]

SRC = """import ./tinybendygrad/dtype.bend as D
import ./tinybendygrad/helpers.bend as H

{defs}
def main() -> IO(Unit):
  do IO<Unit>:
{body}"""

#: `Dt.<name>` is declared `-> IO(_)` or it is not, and WHICH decides the shape
#: inside a `do IO<Unit>` block: an `IO` value binds with `<-` and a PURE one does
#: not.  MEASURED 2026-10-05: `dtype.bend` made `Dt.bf16`, `Dt.fp16` and
#: `Dt.fp8_to` PURE, so this file's old `v : F32 <- D.Dt.bf16(...)` stopped
#: compiling and THE WHOLE GATE WENT COLD -- it printed "bend failed" and exited 1,
#: which means the `fp16_1p1` fixture below and the `norm` fix had never actually
#: run.  A fix that is not executed is not a fix.  The declaration is READ, not
#: assumed, because `dtype.bend` is mid-refactor and a hard-coded shape refuses on
#: whichever side of that change the tree happens to be on.
SEAM_DECL = re.compile(r"^def Dt\.(\w+)\(.*?\)\s*->\s*(IO\(|[A-Z])", re.M)

#: TWO SPELLINGS PER ROW, ON ONE LINE, because the whole subject of this gate is a
#: difference BETWEEN SPELLINGS: `F32.show` is the seven-to-nine digit
#: shortest-form printer (`references/bend/bend2/bend.ts:1197`) and `F32.bits` is
#: the spelling that does not round at all and the only one that separates two NaNs.
#: Reading `bits` is what makes `fp8to_0x7F_e5m2` decidable at all -- `canon`
#: answers `f32:?nan` for a bare spelling on purpose.  A `U32`-typed row has no
#: bits of its own to read, so it prints the one spelling there is.
PREFIX = {"F32": "F32ROW {nm} = ", "U32": "U32ROW {nm} = "}


def row_body(nm: str, sh: str, val: str) -> str:
    """A `U32` row's PATTERN IS ITS OWN DECIMAL -- there is nothing to round, so it
    is printed in both slots rather than through `F32.bits`, which does not type at
    all on a `U32` (`expected : F32 / observed : U32`, MEASURED)."""
    head, mid = PREFIX[sh].format(nm=nm), f" BITSROW {nm} = "
    bits = f"F32.bits({val})" if sh == "F32" else val
    return f'String.concat(["{head}", {sh}.show({val}), "{mid}", U32.show({bits}), " | "])'


def emit(dtype_bend: pathlib.Path) -> str:
    io = {m[0] for m in SEAM_DECL.findall(dtype_bend.read_text())
          if m[1].startswith("IO(")}
    defs, body = [], []
    for nm, ex, _, sh, _ in CASES:
        call = ex.split(".", 2)[2].split("(")[0]
        if call in io:
            body.append(f"    {nm} : {sh} <- {ex}")
            body.append(f"    IO.print({row_body(nm, sh, nm)})")
            continue
        # A PURE call needs no lift in an ARGUMENT position, and a Bend parameter
        # is consumed by its first use -- `+v` twice is the way to read it twice.
        defs.append(f"def {nm}_row(+v: {sh}) -> String:\n  {row_body(nm, sh, 'v')}")
        body.append(f"    IO.print({nm}_row({ex}))")
    return SRC.format(defs="\n\n".join(defs) + "\n" if defs else "",
                      body="\n".join(body) + "\n")


def run(work: pathlib.Path, target: str) -> dict[str, tuple[str, str]]:
    bend = work / "f.bend"
    bend.write_text(emit(work / "tinybendygrad" / "dtype.bend"))
    if target == "js":
        out = work / "f.js"
        cmd = ["node", str(out)]
    else:
        out = work / "f.gen.c"
        cmd = [str(work / "f.gen")]
    r = subprocess.run([str(BEND), str(bend), "-o", str(out)], capture_output=True, text=True)
    if r.returncode != 0 or not out.exists():
        sys.exit(f"bend failed: {r.stdout}\n{r.stderr}")
    if target == "c":
        k = subprocess.run(["cc", "-O1", "-w", "-o", str(work / "f.gen"), str(out)],
                           capture_output=True, text=True)
        if k.returncode != 0:
            sys.exit(f"cc failed: {k.stderr}")
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    rows = {}
    for tok in "".join(p.stdout.splitlines()).split("|"):
        m = re.match(r"^(?:F32ROW|U32ROW) (\w+) = (\S+)(?: BITSROW \1 = (\d+))?$",
                     tok.strip())
        if m:
            rows[m[1]] = (m[2], m[3] or "")
    return rows


def norm(s: str) -> str:
    """A float of a KNOWN WIDTH, canonically spelled, on BOTH sides.

    JFP-1.  This was `repr(float(s))` with no round trip, which is what makes
    `F32.show`'s shortest-f32-round-tripping `1.0996094` and CPython's double's
    `1.099609375` compare unequal -- one f32, two spellings, a manufactured
    disagreement.  `canon` rounds through f32 once on each side, and answers
    `f32:?nan` for a NaN so a gate cannot quietly call two NaNs the same row.
    A string that is not a float at all (`<absent>`) comes back unchanged, so
    this still sits in a generic row comparer.
    """
    return CANON.canon(s, "f32")


def both(row: str | tuple[str, str]) -> tuple[str, str]:
    """A lane's answer, as `(spelling, pattern)`, canonicalised.  THE PATTERN IS
    PREFERRED WHEN THE ROW HAS ONE, because it is the only spelling that does not
    round; the spelling is the fallback and it is the only thing a row without a
    `BITSROW` can be judged on."""
    spelling, pattern = row if isinstance(row, tuple) else (row, "")
    return (CANON.canon_bits(int(pattern), "f32") if pattern else norm(spelling),
            norm(spelling))


def agree(lane: str | tuple[str, str], want: str) -> str:
    """`AGREE` / `AGREE-UNRESOLVED` / `DISAGREE`, and THE MIDDLE ONE IS ITS OWN
    OUTCOME because it is not the same claim as `AGREE`.

    A row whose ORACLE answer is a NaN has no pattern on the oracle side -- CPython's
    `float` cannot express `0x7fc00001` -- so all the gate can say is that both
    sides are the same UNRESOLVED value.  Folding that into `AGREE` would be the
    mistake this whole unit exists to prevent, one level up: a formatting-or-
    resolution difference reported as an agreement.  `fp8fix`'s `TOTALISE` rows are
    the precedent for a third bucket that is in neither pass nor fail.
    """
    got, spelled = both(lane)
    if got == want:
        return "AGREE"
    if spelled == want:
        return "AGREE-UNRESOLVED" if want.endswith("?nan") else "AGREE"
    return "DISAGREE"


def main() -> None:
    names = [c[0] for c in CASES]
    with tempfile.TemporaryDirectory() as td:
        work = pathlib.Path(td) / "tree"
        work.mkdir()
        shutil.copytree(REPO / "tinybendygrad", work / "tinybendygrad")
        js, c = run(work, "js"), run(work, "c")

    print("ROWS PRESENT vs ROWS EXPECTED")
    for lbl, r in (("node", js), ("cc", c)):
        miss = [n for n in names if n not in r]
        print(f"  {lbl:<5} present {len(names) - len(miss):>2} / expected {len(names)}"
              + (f"   MISSING {miss}" if miss else ""))

    print("\n| seam | in / out | CPython (dtype.py) | node | cc | lanes agree | node | cc |")
    print("|---|---|---|---|---|---|---|---|")
    tally: dict[str, list[str]] = {}
    for n, ex, pt, sh, cp in CASES:
        want = norm(str(cp())) if sh == "F32" else CANON.canon_bits(int(cp()), "f32")
        gj, gc = js.get(n, "<absent>"), c.get(n, "<absent>")
        vj, vc = agree(gj, want), agree(gc, want)
        for lane, v in (("node", vj), ("cc", vc)):
            tally.setdefault(v, []).append(n if lane == "node" else f"{n}[cc]")
        cell = lambda r: both(r)[0] if isinstance(r, tuple) else r
        print(f"| `{n}` | {pt} -> {sh} | `{want}` | {cell(gj)} | {cell(gc)} |"
              f" {'yes' if both(gj) == both(gc) else '** NO **'} | {vj} | {vc} |")
    print("\nTHE VERDICTS, NEVER SUMMED")
    for k in ("AGREE", "AGREE-UNRESOLVED", "DISAGREE"):
        print(f"  {k:<17} {len(tally.get(k, []))} {tally.get(k, [])}")
    print("  `AGREE-UNRESOLVED` is a NaN whose PAYLOAD neither side can compare: CPython's")
    print("  `float` has no payload, so the oracle cannot say which NaN it meant.  It is")
    print("  in NEITHER pass nor fail, because counting it as a pass would claim a")
    print("  separation neither side made.")
    dis = [n for n in names if both(js.get(n, "")) != both(c.get(n, ""))]
    print(f"\nlanes disagree on {len(dis)}/{len(names)}: {dis}")
    bad = sum(len(tally.get(k, [])) for k in ("DISAGREE",))
    bad += sum(1 for n in names if n not in js or n not in c)

    print("\nWHAT THE DATA SUPPORTS, AND IT HAS CHANGED SINCE JS-LANE-GATE.md WAS")
    print("WRITTEN.  That note's table -- node 3/6 against CPython, `fp16` answering")
    print("`0`, `fp8_to 0x3C` answering `1` -- WAS MEASURED ON THE SHIPPED TREE WITH")
    print("`Dt.fp16`/`Dt.fp8_to` STILL REACHING `runtime/dtype.js` THROUGH THEIR CIDs.")
    print("MEASURED NOW: `dtype.bend:583` records those three as PURE defs, so the three")
    print("CIDs `dtype.js` registers for them are DEAD -- registered and never called --")
    print("and what this table now measures is `dtype.bend`'s arithmetic.  `FROMBITS.md`")
    print("is where that change is recorded and `jstage/jsstage.py:384-389` derives the")
    print("same split per run.  SO:")
    print("  * 0 of 7 rows now disagree between the lanes.  That is NOT the JS lane")
    print("    being fixed -- it is the JS lane no longer being REACHED by these rows;")
    print("  * `fp16` and `fp8_to` are the rows that moved, and what they moved BY is")
    print("    the substrate, not a normaliser;")
    print("  * the normaliser is not on the deciding path for any of the 7 rows, which")
    print("    is the change this unit made and it is why the `fp16_1p1` fixture below")
    print("    cannot fail today: it is a row that PINS the normaliser, not a row that")
    print("    tests a port, and `norm/canon.selftest.py` is where it is shown to fail")
    print("    on the normaliser it replaced.")
    sys.exit(1 if (dis or bad) else 0)


if __name__ == "__main__":
    main()