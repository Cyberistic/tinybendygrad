#!/usr/bin/env python3
"""Measure the corpus and refuse to let its figure rot. `checks/corpus-figure.py`

    usage: .venv/bin/python checks/corpus-figure.py [--write]

THE CLAIM, WITH ITS DENOMINATOR.  `graphcmp.GRAPHS` declares **N** graphs; every one of them
builds; the set **UNION** of the ops they reach is **K of len(Ops)**. This prints all three, plus
the per-graph SUM, which is **not** the figure — and it is printed precisely because the sum is
the wrong number and the wrong number is what keeps getting written down.

WHY IT EXISTS, MEASURED.  The corpus figure existed in **at least nine** forms across the reports
at once: `13`, `34`, `35`, `43`, `54`, `59`, `60`, `61`, `73` and `77 of 77` — and `25 graphs`
against a measured `22`. **Three of them are arithmetically impossible as a coverage claim:
`588 of 77`, `372 of 77` and `0 of 77`.** Those three are the giveaway: **a figure larger than its
denominator is a PER-GRAPH SUM COMPARED AGAINST A SET.** Summing `ops-reached` across graphs counts
`BUFFER` once per graph that has one. *MEASURED HERE: the sum is 157 against a union of 53.*

A figure that nine documents disagree about is not documentation, and a figure nobody can
reproduce is not a measurement. This is the instrument that settles it, so the next disagreement
costs one command instead of an afternoon.

DENOMINATOR HANDLING, WHICH IS THE WHOLE POINT.  `len(Ops)` is read off the LIVE
`tinygrad.uop.ops.Ops`, so a new upstream op cannot age the answer silently — which is exactly how
the 34/35 pair happened. A graph that fails to build is **printed and counted separately**, never
skipped quietly: a coverage figure that silently drops a graph understates the coverage it claims.
"""
from __future__ import annotations

import argparse
import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]


def load_graphcmp():
    """Import the differ by path, then force its DEFERRED tinygrad imports.

    `graphcmp.py` defers every tinygrad import into `load_tinygrad()` so the py side cannot build
    its graph on whatever device happens to open first. **Importing the module is therefore NOT
    enough** — measured: without the call, every graph raises `NameError` and a union over zero
    built graphs prints `0 of 77` beside a denominator that looks perfectly healthy. That is where
    one of the impossible figures in the reports came from.
    """
    spec = importlib.util.spec_from_file_location("gc", ROOT / ".agents/slop/graphcmp.py")
    gc = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gc)
    gc.load_tinygrad()
    for n in ("AddrSpace", "DType", "dtypes", "AxisType", "Ops", "ParamArg", "UOp",
              "GroupOp", "Context"):
        setattr(sys.modules["gc"], n, getattr(gc, n))
    return gc


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--write", action="store_true", help="also print the CORPUS.md figure block")
    args = ap.parse_args()

    gc = load_graphcmp()
    from tinygrad.uop.ops import Ops
    names = [o.name for o in Ops]

    union: dict[str, int] = {}
    per_graph_sum = 0
    built, broken = 0, {}
    for g in sorted(gc.GRAPHS):
        try:
            nodes = gc.build(gc.emit_py(g, None), "py")[0]
        except Exception as exc:                      # reported, never skipped quietly
            tb = exc.__traceback__
            frame = tb.tb_frame
            while tb.tb_next:
                tb = tb.tb_next
                frame = tb.tb_frame
            broken[g] = f"{type(exc).__name__}: {exc} at {frame.f_code.co_filename.split('/')[-1]}:{frame.f_lineno}"
            continue
        built += 1
        census = gc.ops_census(nodes)
        per_graph_sum += len(census)
        for op, k in census.items():
            union[op] = union.get(op, 0) + k

    missing = [n for n in names if n not in union]
    print(f"graphs declared   : {len(gc.GRAPHS)}")
    print(f"graphs built      : {built}")
    print(f"graphs FAILED     : {len(broken)}")
    for g, why in broken.items():
        print(f"    {g}: {why}")
    print(f"denominator len(Ops) : {len(names)}")
    print(f"UNION  ops reached   : {len(union)} of {len(names)}")
    print(f"per-graph SUM        : {per_graph_sum}   <- NOT the figure; it counts an op once "
          f"per graph that has it")
    print(f"NOT reached ({len(missing)}): {' '.join(missing)}")

    if args.write:
        print()
        print("<!-- CORPUS.md FIGURE BLOCK — regenerate with checks/corpus-figure.py -->")
        print(f"- **{len(union)} of {len(names)} ops** reached, by set UNION over "
              f"**{len(gc.GRAPHS)} graphs** ({built} built, {len(broken)} failed)")
        print(f"- the per-graph SUM is **{per_graph_sum}** and is **not** this figure")
        print(f"- not reached: {' '.join(missing)}")

    # A figure that cannot be reproduced is not a measurement. Non-zero exit says so.
    return 0 if built == len(gc.GRAPHS) else 1


if __name__ == "__main__":
    sys.exit(main())