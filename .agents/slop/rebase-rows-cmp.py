#!/usr/bin/env python3
"""Compare a port's rows against its CPython oracle BY NAME, with no baseline.

rebase-gate.py cannot say UNCHANGED or BROKEN for `codegen/opt/search.bend`: it has no
recorded baseline, so verdict() short-circuits to NOT-STARTED before guard 1 runs. But the
rows are all producible right now, so the comparison the baseline would have made can be
made directly, and for THIS port it does not come out clean.

Uses rebase-gate.py's own row extractor and its own oracle registry, so this is not a
second opinion from a different instrument.
"""
import importlib.util, pathlib, subprocess as sp, sys
REPO = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("rg", REPO / ".agents/slop/rebase-gate.py")
rg = importlib.util.module_from_spec(spec); spec.loader.exec_module(rg)

BEND = sys.argv[1]
ORACLE = sys.argv[2:]
_, bend_rows = rg.run_port(pathlib.Path(REPO / BEND), ORACLE, native=False)
lane = next(k for k in bend_rows if k.startswith("cpython:"))
bend, py = bend_rows["interpreted"], bend_rows[lane]
print(f"  port  {BEND}   interpreted {len(bend)} rows")
print(f"  oracle {lane}   {len(py)} rows")
shared = sorted(set(bend) & set(py))
print(f"  shared row names: {len(shared)}   (0 shared is GUARD 3: nothing was compared)\n")
bad = [(k, bend[k], py[k]) for k in shared if bend[k] != py[k]]
for k, b, p in bad:
  print(f"  RED {k}:  port={b}   cpython={p}")
print(f"\n  {len(shared)-len(bad)}/{len(shared)} shared rows agree, {len(bad)} disagree")
