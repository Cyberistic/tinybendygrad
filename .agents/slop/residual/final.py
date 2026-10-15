#!/usr/bin/env python3
"""final.py -- the landed guard's price, measured as a DIFFERENTIAL on one snapshot.

usage: .venv/bin/python .agents/slop/residual/final.py <out.rows>
"""
import importlib.util
import re
import subprocess
import warnings
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("cc", ROOT / "checks/cites-census.py")
cc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cc)

FIXED = cc.quoted_spans
REV = re.compile(r"^[0-9a-f]{7,40}\^?:")
TRACKED = subprocess.run(["git", "ls-tree", "-r", "HEAD", "--name-only"], cwd=ROOT,
                         capture_output=True, text=True, check=True).stdout.splitlines()
IDX: dict[str, list[str]] = {}
for _p in TRACKED:
  _i = _p.find("/")
  while _i != -1:
    IDX.setdefault(_p[_i:], []).append(_p)
    _i = _p.find("/", _i + 1)


def how(s):
  if REV.match(s):
    return "rev"
  if (ROOT / s).is_file():
    return "ROOT-exact"
  h = IDX.get("/" + s)
  return "absent" if h is None else ("suffix-index" if len(h) == 1 else f"AMBIG-{len(h)}")


def key(c):
  return (c.get("lane"), c.get("file"), c.get("at"), c.get("subject"),
          c.get("needle") if c.get("needle") is not None else f"#{c.get('num')}")


def run():
  with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    return [cc.judge(c) for c in cc.census(cc.committed())[0]]


def spans_reverted(text):
  out, i = [], 0
  while True:
    a = text.find("`", i)
    if a < 0:
      break
    b = text.find("`", a + 1)
    if b < 0:
      break
    out.append((a, b + 1, text[a + 1:b]))
    i = b + 1
  for m in re.finditer(r"\"([^\"]{4,})\"|'([^']{4,})'", text):
    out.append((m.start(), m.end(), next(g for g in m.groups() if g)))
  return sorted(out)


after = run()
cc.quoted_spans = spans_reverted
before = run()
cc.quoted_spans = FIXED

bp, ap = Counter(c["verdict"] for c in before), Counter(c["verdict"] for c in after)
print(f"ROWS before={len(before)} after={len(after)}")
print(f"BEFORE  PASS={bp[cc.PASS]} FAIL={bp[cc.FAIL]} REFUSED={bp[cc.REFUSED]} SKIP={bp[cc.SKIP]}")
print(f"AFTER   PASS={ap[cc.PASS]} FAIL={ap[cc.FAIL]} REFUSED={ap[cc.REFUSED]} SKIP={ap[cc.SKIP]}")
b, a = defaultdict(Counter), defaultdict(Counter)
for c in before:
  b[key(c)][c["verdict"]] += 1
for c in after:
  a[key(c)][c["verdict"]] += 1
keys = set(b) | set(a)
retired = [k for k in keys if b[k][cc.FAIL] > a[k][cc.FAIL]]
silenced = [k for k in keys if b[k][cc.PASS] > a[k][cc.PASS]]
newfail = [k for k in keys if a[k][cc.FAIL] > b[k][cc.FAIL]]
newpass = [k for k in keys if a[k][cc.PASS] > b[k][cc.PASS]]
print(f"N (FAIL retired)  = {sum(b[k][cc.FAIL] - a[k][cc.FAIL] for k in retired)}")
print(f"M (PASS silenced) = {sum(b[k][cc.PASS] - a[k][cc.PASS] for k in silenced)}")
print(f"FAIL->PASS recovered = {len(newpass)}   new FAIL keys = {len(newfail)}")
print(f"NEW-only N = {sum(1 for k in retired if k[3] and how(k[3]) == 'suffix-index')}"
      f"  NEW-only M = {sum(1 for k in silenced if k[3] and how(k[3]) == 'suffix-index')}")
out = Path(__file__).resolve().parent / "final.rows"
with out.open("w") as fh:
  for k, tag in ([(k, "RETIRED-FAIL") for k in retired] + [(k, "SILENCED-PASS") for k in silenced]
                 + [(k, "NEW-FAIL") for k in newfail] + [(k, "RECOVERED-PASS") for k in newpass]):
    fh.write(f"{tag}\t" + "\t".join(str(x) for x in k) + f"\t{how(k[3])}\n")
print(f"-> {out}")
