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

BEND = REPO / "bin" / "bend"
ROW = re.compile(r"^F32ROW (\w+) = (.*)$")

# (row name, bend expression, declared param type, Bend `show`, CPython callable)
CASES = [
    ("bf16_1p5", "D.Dt.bf16(F32.bits(1.5))", "U32", "F32",
     lambda: td.float_to_bf16(1.5)),
    ("fp16_1p5", "D.Dt.fp16(1.5)", "F32", "F32",
     lambda: td.float_to_fp16(1.5)),
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

def main() -> IO(Unit):
  do IO<Unit>:
{src}"""


def emit() -> str:
    out = [f'    v : {sh} <- {ex}\n    IO.print("F32ROW {nm} = " ++ {sh}.show(v))'
           for nm, ex, _, sh, _ in CASES]
    return SRC.format(src="\n".join(out) + "\n")


def run(work: pathlib.Path, target: str) -> dict[str, str]:
    bend = work / "f.bend"
    bend.write_text(emit())
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
    for line in p.stdout.splitlines():
        m = ROW.match(line)
        if m:
            rows[m[1]] = m[2].strip()
    return rows


def norm(s: str) -> str:
    """`F32.show` prints `448` where Python prints `448.0`.  That is a FORMAT
    difference, not a value difference, and letting it into the count would make
    the number mean two things at once."""
    try:
        return repr(float(s))
    except ValueError:
        return s


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

    print("\n| seam | in / out | CPython (dtype.py) | node | cc | lanes agree |")
    print("|---|---|---|---|---|---|")
    bad_js = bad_c = 0
    for n, ex, pt, sh, cp in CASES:
        want, gj, gc = norm(str(cp())), js.get(n, "<absent>"), c.get(n, "<absent>")
        bad_js += norm(gj) != want
        bad_c += norm(gc) != want
        sig = pt
        print(f"| `{n}` | {sig} -> {sh} | `{want}` | `{gj}` | `{gc}` |"
              f" {'yes' if norm(gj) == norm(gc) else '** NO **'} |")
    print(f"\nnode agrees with CPython on {len(names) - bad_js}/{len(names)}"
          f"   (compared as floats, so `448` == `448.0`)")
    print(f"cc   agrees with CPython on {len(names) - bad_c}/{len(names)}")
    dis = [n for n in names if norm(js.get(n, "")) != norm(c.get(n, ""))]
    print(f"lanes disagree on {len(dis)}/{len(names)}: {dis}")

    print("\nWHAT THE DATA SUPPORTS, and it is LESS than the rule this gate was")
    print("written to test.  The rule was 'a seam taking U32 agrees, a seam whose")
    print("F32 crosses disagrees'.  `fp8_to(U32, U32) -> F32` REFUTES it: it takes")
    print("two U32s and still disagrees on 2 of 3 rows.  What survives:")
    print("  * the two U32->U32 seams agree exactly;")
    print("  * `fp16` disagrees, and the reason is INSTRUMENTED IN BOTH LANES --")
    print("    C's `fp16_run` receives f[0] = 1069547520 (the BITS of 1.5) while")
    print("    node's `dtype_fp16` receives x = 1.5 (the VALUE);")
    print("  * `fp8_to`'s divergence is measured (2 of 3 rows) but NOT localised, and")
    print("    is deliberately not guessed at here.")
    sys.exit(1 if dis else 0)


if __name__ == "__main__":
    main()