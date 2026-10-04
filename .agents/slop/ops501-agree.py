#!/usr/bin/env python3
"""ops501-agree.py -- AGREE / DISAGREE over three lane files, by WHOLE `name=value` LINE.

    .venv/bin/python .agents/slop/ops501-agree.py py.txt bd.txt bn.txt

agent-core.md: "Your harness must diff whole `name=value` lines, not row NAMES. A
name-comparing harness reported 0 for all 30 mutations in one unit and 0 for all 68 in
another." So this compares the producer's OWN answer for a shared name, and it NAMES
the row on every disagreement -- a gate that says DISAGREE without saying which row is
a gate that has to be read by hand to be useful.

It reads with rebase-gate.py's rows(), the one row reader in this repo, and it reports
the DENOMINATOR on each side. A count is not a coverage statement.
"""
import importlib.util
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("rebase_gate", HERE / "rebase-gate.py")
rg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rg)

lanes = [pathlib.Path(p) for p in sys.argv[1:]]
parsed = [rg.rows(p.read_text()) for p in lanes]
py, others = parsed[0], parsed[1:]

den = " | ".join(f"{p.name}={len(r)}" for p, r in zip(lanes, parsed))
print(f"denominators: {den}")

ok = True
for p, other in zip(lanes[1:], others):
  only_py = sorted(set(py) - set(other))
  only_other = sorted(set(other) - set(py))
  shared = sorted(set(py) & set(other))
  bad = [(n, py[n], other[n]) for n in shared if py[n] != other[n]]
  if not (only_py or only_other or bad):
    print(f"AGREE {p.name}: {len(shared)} shared names, 0 disagreements")
    continue
  ok = False
  print(f"DISAGREE {p.name}: shared={len(shared)} py-only={len(only_py)} "
        f"{p.name}-only={len(only_other)} value-disagreements={len(bad)}")
  for n, a, b in bad:
    print(f"  ROW DISAGREE {n}: cpython={a} {p.name}={b}")
  for n in only_py:
    print(f"  ROW MISSING FROM {p.name}: {n} (cpython={py[n]})")
  for n in only_other:
    print(f"  ROW ONLY IN {p.name}: {n}={other[n]}")
sys.exit(0 if ok else 1)