#!/usr/bin/env python3
"""jsfix_e2e.py -- ONE row set, run against the LIVE `runtime/dtype.js`.

Reproduce (from the repo root):
    python3 .agents/slop/jsfix/jsfix_e2e.py        # rc 0 iff the lane is correct

`jsfix_gate.py` proves the lane by planting mutations of it.  This proves it by
running the file as it sits in the tree and writing down what it answered, so the
claim has a repeatable artefact behind it rather than only a count.

It is a SEPARATE program from the gate on purpose.  A gate that both plants and
reports can report green off a mis-placed arm; this one imports nothing from the
gate, reads `runtime/dtype.js` unmodified, and emits the table below.
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
BEND = REPO / "bin" / "bend"
LANE = REPO / "tinybendygrad" / "runtime" / "dtype.js"

U32 = 0xFFFFFFFF
MASK64 = (1 << 64) - 1
INT64_MIN = -(1 << 63)
DEFS = ["trunc", "floor_div", "floor_mod", "cdiv", "cmod", "ceildiv"]
FIXTURES = [(7, 4), (-7, 4), (-8, 4), (7, -4), (INT64_MIN, 3)]
ROW = re.compile(r"^ROW (\w+) (\S+) = (.*)$")


def pattern(v: int) -> str:
    u = v & MASK64
    return f"{u >> 32}:{u & U32}"


def main() -> None:
    sys.path.insert(0, str(REPO))
    from tinygrad.helpers import cdiv, cmod, ceildiv, floordiv, floormod

    cpy = {"trunc": lambda a, b: a, "floor_div": floordiv, "floor_mod": floormod,
           "cdiv": cdiv, "cmod": cmod, "ceildiv": ceildiv}

    body = ["import ./tinybendygrad/dtype.bend as D",
            "import ./tinybendygrad/helpers.bend as H", "",
            "def main() -> IO(Unit):", "  do IO<Unit>:"]
    for d in DEFS:
        for (a, b) in FIXTURES:
            ha, la = divmod(a & MASK64, 1 << 32)
            hb, lb = divmod(b & MASK64, 1 << 32)
            call = (f"D.Dt.i64_trunc(H.i64_of_hi_lo({ha}, {la}))" if d == "trunc" else
                    f"D.Dt.i64_{d}(H.i64_of_hi_lo({ha}, {la}), "
                    f"H.i64_of_hi_lo({hb}, {lb}))")
            body.append(f"    r : H.I64 <- {call}")
            body.append(f'    IO.print("ROW {d} {a},{b} = " ++ H.i64_text(r))')
    probe = "\n".join(body) + "\n"

    with tempfile.TemporaryDirectory() as td:
        work = pathlib.Path(td) / "tree"
        work.mkdir()
        shutil.copytree(REPO / "tinybendygrad", work / "tinybendygrad")
        assert (work / "tinybendygrad/runtime/dtype.js").read_bytes() == LANE.read_bytes()
        (work / "probe.bend").write_text(probe)
        out = work / "probe.js"
        r = subprocess.run([str(BEND), str(work / "probe.bend"), "-o", str(out)],
                           capture_output=True, text=True)
        # Gated on node's stdout, never on bend's exit: dtype.bend is COLD and the
        # two questions ("does it stand alone", "can it be built and run") are not
        # the other's.
        if not out.exists():
            sys.exit(f"no backend emitted: rc={r.returncode}\n{r.stdout}\n{r.stderr}")
        p = subprocess.run(["node", str(out)], capture_output=True, text=True,
                           timeout=300)

    got = {}
    for line in p.stdout.splitlines():
        m = ROW.match(line)
        if m:
            got[(m[1], m[2])] = m[3]

    print(f"dtype.js, byte-for-byte as it sits in the tree.  bend -o rc={r.returncode}"
          f" (reported, not gated on).  node answered {len(got)} rows.\n")
    print("| seam | a | b | CPython | node | |")
    print("|---|---|---|---|---|---|")
    bad = 0
    for d in DEFS:
        for (a, b) in FIXTURES:
            want = pattern(cpy[d](a, b))
            have = got.get((d, f"{a},{b}"), "<absent>")
            ok = have == want
            bad += not ok
            print(f"| `{d}` | `{a}` | `{b}` | `{want}` | `{have}` |"
                  f" {'ok' if ok else '** WRONG **'} |")
    print(f"\n  {len(got) - bad}/{len(got)} rows agree with tinygrad.helpers, called.")
    sys.exit(0 if not bad and len(got) == len(DEFS) * len(FIXTURES) else 1)


if __name__ == "__main__":
    main()