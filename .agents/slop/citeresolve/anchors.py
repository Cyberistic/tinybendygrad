#!/usr/bin/env python3
"""Re-measure `cites2`'s 16 IMMUNE anchors: is each anchor still UNIQUE in its file?

cites2 §5 proposed the `(path, must_contain)` shape for 22 of 31 cites collapsing
to 16 distinct anchors.  An anchor that occurs exactly once makes the line number
redundant -- the anchor IS the pin.  Re-measured at the current HEAD, so the
IMMUNE/NEEDS-NUMBER verdicts carry a fresh moment.
"""
from __future__ import annotations

import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

# (relpath, anchor, the cites2 label)
ANCHORS = [
    ("tinybendygrad/dtype.bend", "def Dt.i64_trunc", "the port's i64 trunc"),
    ("tinybendygrad/uop/ops.bend", "ATuple{ys: List<&2, U32>}", "PERMUTE/FLIP's one arg type"),
    ("tinybendygrad/uop/ops.bend", "def UOp.mselect", "mselect's AInt arm"),
    ("tinybendygrad/uop/ops.bend", "#   dtype: DType = dtypes.void", "CallInfo's dtype field"),
    ("tinybendygrad/helpers.bend", 'getenv_int("DEBUG", 0)', "the DEBUG reader"),
    ("tinybendygrad/base.bend", "0x7FC00000", "the JS NaN collapse"),
    ("tinybendygrad/renderer/nir_llvmir.bend", 'String.concat([nm, " = ["', "the nl row shape"),
    ("tinybendygrad/runtime/support/nv/ip.bend", "import Base", "package-relative import"),
    ("tinybendygrad/LAWS/spec.bend", "import Base", "package-relative import"),
    ("tinybendygrad/runtime/support/nv/nvdev.bend", "def emit(xs: List<&2, String>)", "the nv emit"),
    ("tinybendygrad/uop/render.bend", "def py_row(", "the row shape"),
    ("tinybendygrad/uop/render.bend", "def rnd_row(", "the rnd rows"),
    ("tinybendygrad/uop/render.bend", "def pu_line(", "the pu line"),
    ("tinybendygrad/renderer/cstyle.bend", "`Ops.SHRINK` HAS NO DTYPE", "the SHRINK wall"),
    ("tinybendygrad/mixin/elementwise.bend", "def ew_add", "the ew dispatch"),
    (".agents/slop/ag-emit.bend", "bend2-constraints.md", "the quoted path"),
]


def head() -> str:
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()


def main() -> int:
    print("path\tanchor\thits\tfirst_line\tverdict\tlabel")
    immune = needs = gone = 0
    for rel, anchor, label in ANCHORS:
        try:
            blob = open(os.path.join(ROOT, rel), encoding="utf-8", errors="replace").read()
        except OSError:
            print(f"{rel}\t{anchor}\t-\t-\tGONE\t{label}")
            gone += 1
            continue
        lines = blob.splitlines()
        hits = [i for i, line in enumerate(lines, 1) if anchor in line]
        if not hits:
            print(f"{rel}\t{anchor}\t0\t-\tGONE\t{label}")
            gone += 1
        elif len(hits) == 1:
            print(f"{rel}\t{anchor}\t1\t{hits[0]}\tIMMUNE\t{label}")
            immune += 1
        else:
            print(f"{rel}\t{anchor}\t{len(hits)}\t{hits[0]}\tNEEDS-NUMBER\t{label}")
            needs += 1
    print(f"# HEAD={head()} immune={immune} needs_number={needs} gone={gone}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
