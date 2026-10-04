#!/usr/bin/env python3
"""multi-namelane.py -- the 26-collision triage for schedule/multi.bend vs multi-rows.py.

READS BOTH LANES THROUGH `rebase-gate.py`'s OWN `rows()`. It does not define a row rule:
agent-core.md and rebase-gate.py both record that a second reader is how two instruments
end up measuring different quantities. `rows()` is imported, not copied.

It answers FOUR questions and prints a denominator for each:

  1 how many row NAMES does each lane print, and how many do they share as printed
  2 which SIDE owns each name, if the `t_` prefix is set aside -- and for every name that
    then collides, whether the two VALUES agree
  3 for a disagreement, what each side is actually MEASURING (count vs tuple vs bool vs
    membership), because "disagree" does not say which side is wrong
  4 nothing. This file changes no file.

Run: .venv/bin/python .agents/slop/multi-namelane.py <port.txt> <oracle.txt>
"""
import importlib.util
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
# `rebase-gate.py` has a dash, so it is loaded by PATH -- the file itself, not a copy of it.
_spec = importlib.util.spec_from_file_location("rebase_gate", HERE / "rebase-gate.py")
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
rows = _mod.rows


def main():
  port_txt = pathlib.Path(sys.argv[1]).read_text()
  orc_txt = pathlib.Path(sys.argv[2]).read_text()
  p, o = rows(port_txt), rows(orc_txt)

  print(f"port   rows={len(p)}")
  print(f"oracle rows={len(o)}")
  shared_as_printed = sorted(set(p) & set(o))
  print(f"shared as printed = {len(shared_as_printed)}  of {min(len(p), len(o))} "
        f"(min side; port-only={len(set(p)-set(o))} oracle-only={len(set(o)-set(p))})")

  # The prefix question, MEASURED rather than assumed: does EVERY port name carry `t_`?
  prefixed = [k for k in p if k.startswith("t_")]
  print(f"\nport names starting `t_`: {len(prefixed)} of {len(p)}")
  print(f"port names NOT starting `t_`: {sorted(set(p) - set(prefixed))}")

  pn = {k[2:] if k.startswith("t_") else k: v for k, v in p.items()}
  on = dict(o)
  coll = sorted(set(pn) & set(on))
  print(f"\ncollisions after setting the prefix aside: {len(coll)} "
        f"of {len(on)} oracle names ({len(set(pn)-set(on))} port names collide with nothing)")

  dis = [(c, pn[c], on[c]) for c in coll if pn[c] != on[c]]
  print(f"  agreeing:   {len(coll)-len(dis)}")
  print(f"  DISAGREEING: {len(dis)}")
  print()
  print(f"{'name':<22} {'port':<34} oracle")
  for c, pv, ov in dis:
    print(f"  {c:<20} {pv:<32} {ov}")


if __name__ == "__main__":
  main()
