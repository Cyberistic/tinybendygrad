#!/usr/bin/env python3
"""Lane-D prices from `verdicts.rows` ALONE -- no census, no `read()`, no git.

Both rules are read off the CITING LINE at the row's own `file:at` anchor, so both are
UPPER BOUNDS on the equivalent gap rule (the gap is a substring of the line), and are
labelled as bounds rather than as the rule itself.

usage: shapesD.py <verdicts.rows>
"""
import importlib.util
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("cites", ROOT / "checks/cites-census.py")
cc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cc)

NUM = re.compile(r"has (\d+) lines, claim says (\d+)")
rows = [l.rstrip("\n").split("\t") for l in Path(sys.argv[1]).read_text().splitlines()]
D = [f for f in rows if f[0] == "D"]
cache: dict[tuple[str, int], str] = {}


def line(f: list[str]) -> str:
  path, _, at = f[3].rpartition(":")
  if not path or not at.isdigit():
    return ""
  k = (path, int(at))
  if k not in cache:
    try:
      cache[k] = (ROOT / path).read_text(errors="replace").splitlines()[int(at) - 1]
    except (OSError, IndexError, ValueError):
      cache[k] = ""
  return cache[k]


print(f"lane D rows in {sys.argv[1]}: {len(D)}  "
      f"{dict(Counter(f[2] for f in D))}")
for name, pred in (("the citing LINE carries OUTPUT (-> or rc=) -- a RUN's stdout", lambda s: cc.OUTPUT.search(s)),
                   ("the claiming line is a markdown table row", lambda s: s.lstrip().startswith("|")),
                   ("the claiming line quotes the number inside a backtick span", lambda s: f"`{NUM.search(s).group(2)}`" in s if NUM.search(s) else False)):
  n = sum(1 for f in D if f[2] == "FAIL" and pred(line(f)))
  m = sum(1 for f in D if f[2] == "PASS" and pred(line(f)))
  r = sum(1 for f in D if f[2] == "REFUSED" and pred(line(f)))
  print(f"  {name:<62} N={n:<4} M={m:<4} already-REFUSED={r}")

wc = [f for f in D if f[2] == "FAIL" and (m := NUM.search(f[6])) and int(m.group(1)) == int(m.group(2)) + 1]
print(f"\nD FAIL rows whose measured splitlines() is claim+1 (the `wc -l` shape): "
      f"{len(wc)}/{sum(1 for f in D if f[2] == 'FAIL')}")
for f in wc:
  print(f"    {f[3]}  {f[4]}  {f[6]}")
unparsed = [f for f in D if f[2] == "FAIL" and not NUM.search(f[6])]
print(f"D FAIL rows whose evidence carries no 'has N lines, claim says M': {len(unparsed)}")
for f in unparsed:
  print(f"    {f[3]}  {f[4]}  {f[6][:90]}")