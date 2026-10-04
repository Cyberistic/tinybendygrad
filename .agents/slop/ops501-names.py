#!/usr/bin/env python3
"""ops501-names.py -- WHICH SIDE HAS WHICH ROW, and the DENOMINATOR for each.

    .venv/bin/python .agents/slop/ops501-names.py <oracle.txt> <port.txt>

WHY A SCRIPT AND NOT `comm`. A count difference is not a coverage statement. This prints,
per side: the denominator (rows the side produced), the SHARED-name count, and the two
one-sided sets by name -- so "101 vs 82" is replaced by "101 | 101 | 82 | 82 shared, and
these 19 names are on the oracle's side only".

IT CALLS `rebase-gate.py`'s `rows()`, the one row reader in this repo. Do not write a
second reader: a name-comparing harness reported 0 for all 30 mutations in one unit.
"""
import importlib.util
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("rebase_gate", HERE / "rebase-gate.py")
rg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rg)

oracle_txt, port_txt = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
o, p = rg.rows(oracle_txt.read_text()), rg.rows(port_txt.read_text())

shared = sorted(set(o) & set(p))
only_o = sorted(set(o) - set(p))
only_p = sorted(set(p) - set(o))
disagree = [(n, o[n], p[n]) for n in shared if o[n] != p[n]]

print(f"oracle rows (denominator)  = {len(o)}")
print(f"port   rows (denominator)  = {len(p)}")
print(f"SHARED names              = {len(shared)}")
print(f"oracle-only names          = {len(only_o)}")
print(f"port-only names            = {len(only_p)}")
print(f"disagreements on shared    = {len(disagree)}")
for n, a, b in disagree:
  print(f"  DISAGREE {n}: oracle={a} port={b}")
for n in only_o:
  print(f"  ORACLE-ONLY {n}={o[n]}")
for n in only_p:
  print(f"  PORT-ONLY   {n}={p[n]}")