#!/usr/bin/env python3
"""censusnow.py -- ONE census, with the totals, the NEW/PRE split, and the FAIL rows.

usage: .venv/bin/python .agents/slop/residual/censusnow.py <out.rows>
"""
import importlib.util
import re
import subprocess
import sys
import warnings
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("cc", ROOT / "checks/cites-census.py")
cc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cc)

REV = re.compile(r"^[0-9a-f]{7,40}\^?:")
IDX: dict[str, list[str]] = {}
for p in subprocess.run(["git", "ls-tree", "-r", "HEAD", "--name-only"], cwd=ROOT,
                        capture_output=True, text=True, check=True).stdout.splitlines():
  i = p.find("/")
  while i != -1:
    IDX.setdefault(p[i:], []).append(p)
    i = p.find("/", i + 1)


def how(s: str) -> str:
  if REV.match(s):
    return "rev"
  if (ROOT / s).is_file():
    return "ROOT-exact"
  h = IDX.get("/" + s)
  return "absent" if h is None else ("suffix-index" if len(h) == 1 else f"AMBIG-{len(h)}")


paths = cc.committed()
with warnings.catch_warnings():
  warnings.simplefilter("ignore")
  judged = [cc.judge(c) for c in cc.census(paths)[0]]
t = Counter(c["verdict"] for c in judged)
fails = [c for c in judged if c["verdict"] == cc.FAIL]
pre = sum(1 for c in fails if how(c.get("subject", "")) == "ROOT-exact")
new = sum(1 for c in fails if how(c.get("subject", "")) == "suffix-index")
head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True,
                      text=True).stdout.strip()
print(f"HEAD {head[:12]}  files={len(paths)}  rows={len(judged)}")
print(f"PASS={t[cc.PASS]} FAIL={t[cc.FAIL]} REFUSED={t[cc.REFUSED]} SKIP={t[cc.SKIP]} DEAD={t[cc.DEAD]}")
print(f"FAIL split: PRE(ROOT-exact)={pre}  NEW(suffix-index)={new}")
out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / ".agents/slop/residual/fails-now.rows"
with out.open("w") as f:
  for c in fails:
    needle = (c.get("needle") or "").replace("\n", "\\n").replace("\t", "\\t")
    f.write("\t".join([c["lane"], c["file"] + ":" + str(c.get("at", "")),
                       str(c.get("subject", "")), repr(needle), how(c.get("subject", "")),
                       c.get("evidence", "").replace("\t", " ")]) + "\n")
print(f"-> {out}")
