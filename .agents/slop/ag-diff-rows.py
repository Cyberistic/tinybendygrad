#!/usr/bin/env python
"""Compare a Bend gate's stdout against a CPython oracle's stdout, by WHOLE `name=value`
LINE.  Not by row name -- agent-core.md records a name-comparing harness reporting 0 for
all 30 mutations in one unit and 0 for all 68 in another, because a name set that agrees
on every value can never move.

  usage: python .agents/slop/ag-diff-rows.py PORT.txt ORACLE.txt [LABEL] [IGNORE.txt]

EXIT 0 when the two agree on every non-ignored row, 1 when they differ, 2 when either
side is EMPTY -- an empty side is a failed run, never a pass, because bend 2.0.34's stack
overflow prints zero rows roughly one run in twenty and is indistinguishable from "not
started".

IGNORE.txt names rows that are deliberately NOT CPython facts, so the residual is
provably empty rather than "empty apart from the ones I expected". Every ignored name
must be present on exactly one side, or the ignore list is hiding a real agreement.
"""
import sys


def read(path):
  out = {}
  order = []
  with open(path) as f:
    for line in f:
      line = line.rstrip("\n")
      if not line or line.startswith("#") or "=" not in line:
        continue
      name, _, val = line.partition("=")
      out.setdefault(name, []).append(val)
      order.append(name)
  return out, order


def main():
  if len(sys.argv) < 3:
    print(__doc__, file=sys.stderr)
    return 2
  port_p, oracle_p = sys.argv[1], sys.argv[2]
  label = sys.argv[3] if len(sys.argv) > 3 else ""
  ignore = set()
  if len(sys.argv) > 4:
    with open(sys.argv[4]) as f:
      ignore = {ln.strip() for ln in f if ln.strip() and not ln.startswith("#")}
  port, _ = read(port_p)
  oracle, _ = read(oracle_p)

  if not port:
    print(f"{label} PORT EMITTED ZERO ROWS -- failed run, not a pass", file=sys.stderr)
    return 2
  if not oracle:
    print(f"{label} ORACLE EMITTED ZERO ROWS -- failed run, not a pass", file=sys.stderr)
    return 2

  reds = []
  skipped = []
  for name in sorted(set(port) | set(oracle)):
    if name in ignore:
      if (name in port) == (name in oracle):
        print(f"IGNORE LIST IS WRONG: {name} is on "
              f"{'both' if name in port and name in oracle else 'neither'} side")
        return 2
      skipped.append(name)
      continue
    if port.get(name) != oracle.get(name):
      reds.append((name, port.get(name), oracle.get(name)))
  for name, p, o in reds:
    pv = ",".join(p) if p is not None else "<absent>"
    ov = ",".join(o) if o is not None else "<absent>"
    print(f"RED {name}: port={pv} oracle={ov}")
  print(f"{label} compared={len(set(port) | set(oracle)) - len(skipped)} "
        f"ignored={len(skipped)} reds={len(reds)}")
  if skipped:
    print(f"{label} ignored: {' '.join(skipped)}")
  return 1 if reds else 0


if __name__ == "__main__":
  sys.exit(main())