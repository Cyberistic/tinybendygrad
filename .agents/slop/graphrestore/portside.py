#!/usr/bin/env python3
"""DOES THE PORT BUILD THESE GRAPHS? `.agents/slop/graphrestore/portside.py`

    usage: .venv/bin/python .agents/slop/graphrestore/portside.py [--dev CPU] [--tries 1]

**ONE `bend` AT A TIME, ALWAYS.**  `sz.bend` peaks at 1,468 MB and three other units are live,
so this script never parallelises and never shells out to two emitters at once.  `--tries 1`
because `graphcmp.emit_bend`'s own default is 5 and five identical failures of a COMPILE ERROR
are not five measurements; they are one measurement five times, and the cost is 5x.

WHAT IT ANSWERS, AND WHY IT IS NOT THE COVERAGE FIGURE.  `checks/corpus-figure.py` measures
`gc.build(gc.emit_py(g, None), "py")` -- **CPython's** side.  This measures
`gc.emit_bend(dev, g)` -- **the port's**.  A graph can be reachable in CPython and unbuildable in
the port, and when one instrument is named "coverage" and prints the other side's number, that is
how a figure becomes a lie with a fresh number.  Both are printed here, together, so they cannot
be confused.
"""
from __future__ import annotations

import argparse
import importlib.util
import os
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
HERE = pathlib.Path(__file__).resolve().parent


def load_graphcmp(dev: str | None):
    """`DEV` is pinned BEFORE `load_tinygrad()`, because the deferred imports are what resolve
    the device (`graphcmp.py:283`)."""
    if dev:
        os.environ["DEV"] = dev
    spec = importlib.util.spec_from_file_location("gc", ROOT / ".agents/slop/graphcmp.py")
    gc = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gc)
    gc.load_tinygrad()
    return gc


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dev", default="CPU", help="the device the differ pins (default CPU)")
    ap.add_argument("--tries", type=int, default=1, help="emit_bend attempts per graph")
    args = ap.parse_args()

    gc = load_graphcmp(args.dev)
    from tinygrad.device import Device
    from tinygrad.uop.ops import Ops
    denom = [o.name for o in Ops]

    py_ops: set[str] = set()
    port_ops: set[str] = set()
    ns = gc.__dict__
    exec(compile((HERE / "restored.py").read_text(), str(HERE / "restored.py"), "exec"), ns)
    for n in ("allred", "cdiv", "late"):
        gc.GRAPHS[n] = ns[f"g_{n}"]
    names = sorted(gc.GRAPHS)
    print(f"dev = {args.dev}   renderer = {type(Device.default.renderer).__name__}   "
          f"denominator len(Ops) = {len(denom)}\n")
    print(f"{'GRAPH':<11}{'py rows':>9}{'BEND rows':>11}   port verdict")
    print("-" * 78)
    for g in names:
        try:
            pys = gc.emit_py(g, None)
            py_nodes = gc.build(pys, "py")[0]
            py_ops |= set(gc.ops_census(py_nodes))
            pyn = len(pys)
        except BaseException as exc:
            pyn = 0
            print(f"{g:<11}{'ERR':>9}{'-':>11}   py: {type(exc).__name__}: {str(exc)[:60]}")
        try:
            rows, _ = gc.emit_bend(args.dev, g, tries=args.tries)
            port_ops |= {gc.unchunks(r)[1] for r in rows}
            bn, verdict = len(rows), "OK"
        except BaseException as exc:
            bn = 0
            verdict = f"**NO ROWS** {type(exc).__name__}"
            if (tail := notes_line(exc)):
                verdict += f" :: {tail}"
        print(f"{g:<11}{pyn:>9}{bn:>11}   {verdict}"[:210])

    print("-" * 78)
    missing = [n for n in denom if n not in port_ops]
    print(f"PORT-SIDE UNION over {len(names)} graphs : {len(port_ops)} of {len(denom)}")
    print(f"CPYTHON-SIDE UNION over the same       : {len(py_ops)} of {len(denom)}")
    print(f"NOT reached on the PORT side ({len(missing)}): {' '.join(missing)}")
    return 0


def notes_line(exc: BaseException) -> str:
    """`emit_bend`'s SystemExit carries the per-attempt stderr tail; that is the reason."""
    return " | ".join(str(exc).split("\n  ")[1:2])[:150]


if __name__ == "__main__":
    sys.exit(main())