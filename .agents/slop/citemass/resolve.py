#!/usr/bin/env python3
"""Re-measure every `.bend:<N>` cite: is its CLAIM-TOKEN on the cited line?

Population by DISCOVERY (os.walk over checks/, .bend/py/sh), then each cite's
claim-token resolved in the target file. A cite that resolves is checked against
the line(s) it names. The token is the anchor; the number is only a coordinate.

Verdicts (AGENTS.md five):
  HOLD      anchor is on a line the cite names
  DRIFT     anchor is in the file at a different line   (restorable, number edit)
  DELETED   anchor is in NO line, and git says it once existed in the file
  NARR      anchor is in NO line, and git says it never existed  (narrative)
  AMBIG     ref basename maps to >1 file
  GONE      ref basename maps to no file

Emits TSV. Also prints git evidence for DELETED/NARR.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
CHECKS = os.path.join(ROOT, "checks")

CITE = re.compile(r"(?P<ref>[A-Za-z0-9_./-]+\.bend):(?P<num>\d+)(?:-(?P<end>\d+))?")

# The anchor: (check_relpath, cite_line, ref, N, end, anchor).  Anchor is a literal
# substring that MUST be on the cited line.  Chosen from the citing comment itself.
A = [
    ("checks/abi_gate.py", 94, "dtype.bend", 1064, None, "def Dt.i64_trunc"),
    ("checks/differ.py", 149, "ops.bend", 1066, None, "ATuple{ys: List<&2, U32>}"),
    ("checks/differ.py", 177, "ops.bend", 4554, None, "WALL(p3)"),
    ("checks/differ.py", 177, "ops.bend", 4560, None, "ABlob"),
    ("checks/disagree-gate.py", 103, "ops.bend", 1057, None, "dtype: S.Dt"),
    ("checks/e2e.py", 55, "renderer/cstyle.bend", 2984, 3015, "rd_row"),
    ("checks/e2e.sh", 228, "renderer/cstyle.bend", 2984, 3015, "rd_row"),
    ("checks/env-precond.py", 48, "helpers.bend", 308, None, 'getenv_int("DEBUG"'),
    ("checks/env-precond.py", 48, "helpers.bend", 342, 345, "NO_COLOR"),
    ("checks/gate_norm.py", 242, "base.bend", 42, None, "0xFFC00001"),
    ("checks/nl-gate.py", 16, "nir_llvmir.bend", 125, None, 'String.concat([nm, " = ["'),
    ("checks/nl-gate.py", 39, "ops.bend", 7837, None, "vd_text"),
    ("checks/nl-gate.py", 40, "ops.bend", 7874, None, "vd_dbg"),
    ("checks/nl-gate.py", 91, "nir_llvmir.bend", 125, None, 'String.concat([nm, " = ["'),
    ("checks/nl-gate.py", 477, "ops.bend", 7837, None, "vd_text"),
    ("checks/nl-gate.py", 477, "ops.bend", 7874, None, "vd_dbg"),
    ("checks/nvrows-deadrow-gate.py", 95, "ip.bend", 371, None, "import Base"),
    ("checks/nvrows-deadrow-gate.py", 96, "LAWS/spec.bend", 48, None, "import Base"),
    ("checks/nvrows-deadrow-gate.py", 213, "nvdev.bend", 1770, None, "def emit(xs: List<&2, String>)"),
    ("checks/rn-gate.py", 10, "render.bend", 2148, None, "py_row"),
    ("checks/rn-gate.py", 26, "render.bend", 2148, None, "py_row"),
    ("checks/rn-gate.py", 40, "render.bend", 2809, 2819, "IO.print"),
    ("checks/rn-gate.py", 51, "render.bend", 2693, 2703, "rnd_"),
    ("checks/rn-gate.py", 98, "render.bend", 2148, None, "py_row"),
    ("checks/rn-gate.py", 133, "render.bend", 2809, 2819, "IO.print"),
    ("checks/rn-gate.py", 164, "render.bend", 2763, None, "pu_line"),
    ("checks/rn-gate.py", 171, "render.bend", 2148, None, "py_row"),
    ("checks/rn-gate.py", 172, "render.bend", 2693, 2703, "rnd_"),
    ("checks/rn-gate.py", 250, "render.bend", 2148, None, "py_row"),
    ("checks/rn-gate.py", 251, "render.bend", 2809, 2819, "IO.print"),
    ("checks/rn-gate.py", 399, "render.bend", 2809, 2819, "IO.print"),
    ("checks/run-f64.sh", 411, "cstyle.bend", 1879, None, "def g_kernel"),
    ("checks/run-port-mm.sh", 27, "cstyle.bend", 49, None, "Ops.SHRINK"),
    ("checks/run-port-mm.sh", 29, "cstyle.bend", 1879, None, "def g_kernel"),
    ("checks/run-port-mm.sh", 87, "helpers.bend", 2551, None, "GlobalCounters.reset"),
    ("checks/stage1-census.py", 204, "mixin/elementwise.bend", 542, 543, "ew_add"),
    ("checks/unowned.py", 66, "ag-emit.bend", 32, None, "bend2-constraints.md"),
]


def index() -> dict[str, list[str]]:
    idx: dict[str, list[str]] = {}
    for base in (os.path.join(ROOT, "tinybendygrad"), CHECKS, os.path.join(ROOT, ".agents/slop")):
        for dp, _d, fn in os.walk(base):
            for f in fn:
                if f.endswith(".bend"):
                    rel = os.path.relpath(os.path.join(dp, f), ROOT)
                    idx.setdefault(f, []).append(rel)
    return idx


def find(needle: str, path: str) -> list[int]:
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return []
    return [i for i, l in enumerate(lines, 1) if needle in l]


def ever(needle: str, path: str) -> bool:
    r = subprocess.run(["git", "log", "--all", "-S", needle, "--format=%h", "--", path],
                       cwd=ROOT, capture_output=True, text=True)
    return bool(r.stdout.strip())


def main() -> int:
    idx = index()
    print("check\tline\tref\tN\tend\tanchor\ttarget\tverdict\tactual")
    verdicts: dict[str, int] = {}
    for ck, ln, ref, n, end, anchor in A:
        cands = idx.get(os.path.basename(ref), [])
        if not cands:
            v, target, actual = "GONE", "", ""
        else:
            # prefer exact suffix match
            exact = [c for c in cands if c.endswith(ref)] or cands
            target = sorted(exact, key=len)[0]
            hits = find(anchor, os.path.join(ROOT, target))
            if not hits:
                v = "DELETED" if ever(anchor, target) else "NARR"
                actual = ""
            elif any(n <= h <= (end or n) for h in hits):
                v = "HOLD"
                actual = ",".join(map(str, hits))
            else:
                v = "DRIFT"
                actual = ",".join(map(str, hits))
        verdicts[v] = verdicts.get(v, 0) + 1
        print(f"{ck}\t{ln}\t{ref}\t{n}\t{end or ''}\t{anchor!r}\t{target}\t{v}\t{actual}")
    print("# " + " ".join(f"{k}={verdicts[k]}" for k in sorted(verdicts)), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
