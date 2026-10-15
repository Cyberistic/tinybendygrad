#!/usr/bin/env python3
"""newrows.py -- the residual NEW FAILs, with the claiming line, for hand classification.

usage: .venv/bin/python .agents/slop/residual/newrows.py <fails.rows> <out.rows>
"""
import importlib.util
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("cc", ROOT / "checks/cites-census.py")
cc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cc)
REV = re.compile(r"^[0-9a-f]{7,40}\^?:")
IDX: dict[str, list[str]] = {}
for _p in subprocess.run(["git", "ls-tree", "-r", "HEAD", "--name-only"], cwd=ROOT,
                         capture_output=True, text=True, check=True).stdout.splitlines():
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


rows = Path(sys.argv[1]).read_text().splitlines()
out = Path(sys.argv[2]).open("w")
n_new = n_pre = 0
for i, line in enumerate(rows):
  f = line.split("\t")
  if len(f) < 6:
    continue
  lane, anchor, subj, needle, ev = f[0], f[1], f[2], f[3], f[4]
  h = how(subj)
  n_new += h == "suffix-index"
  n_pre += h == "ROOT-exact"
  path, _, ln = anchor.rpartition(":")
  try:
    src = (ROOT / path).read_text(errors="replace").splitlines()[int(ln) - 1]
  except (OSError, IndexError, ValueError):
    src = "<no such line>"
  out.write("\t".join([f"{i+1}", lane, h, anchor, subj, needle,
                       src.strip()[:170]]) + "\n")
out.close()
print(f"NEW (suffix-index) = {n_new}")
print(f"PRE (ROOT-exact)   = {n_pre}")
print(f"-> {sys.argv[2]}")
