#!/usr/bin/env python
"""Merge the two `oracle-search.py` runs -- base config first, BEAM_PADTO=1 second --
into the single row set the gate is compared against.

  usage: python .agents/slop/merge-oracle.py BASE.txt PADTO.txt OUT.txt

REFUSES to emit when the two runs define one name with two different values. That is the
whole job: `actions` is built at module import time from `getenv("BEAM_PADTO", 0)`, so no
single process can see both tables, and a merge that silently took the second file's
value would report a padto disagreement as a port red. It also refuses an empty input --
a 0-row side is a failed run, never a pass.
"""
import sys


def read(path):
  out = {}
  with open(path) as f:
    for line in f:
      line = line.rstrip("\n")
      if not line or line.startswith("#") or "=" not in line:
        continue
      name, _, val = line.partition("=")
      out.setdefault(name, set()).add(val)
  return out


def main():
  base, padto, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
  b, p = read(base), read(padto)
  for label, d in (("base", b), ("padto", p)):
    if not d:
      print(f"{label} side is EMPTY -- failed run, not a pass", file=sys.stderr)
      return 2
  merged = dict(b)
  for name, vals in p.items():
    if name in merged:
      clash = merged[name] - vals
      if clash:
        print(f"CONFLICT {name}: base={sorted(merged[name])} padto={sorted(vals)}",
              file=sys.stderr)
        return 1
    merged[name] = vals
  with open(out_path, "w") as f:
    for name in sorted(merged):
      assert len(merged[name]) == 1, f"{name} has {merged[name]}"
      f.write(f"{name}={next(iter(merged[name]))}\n")
  print(f"merged {len(merged)} rows -> {out_path}", file=sys.stderr)
  return 0


if __name__ == "__main__":
  sys.exit(main())