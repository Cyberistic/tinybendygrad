#!/usr/bin/env python3
"""classify.py -- everything needed to hand-classify the residual NEW FAILs:
anchor, needle, subject, resolved path, needle presence, and the FULL claiming line.

usage: .venv/bin/python .agents/slop/residual/classify.py
"""
import importlib.util
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("cc", ROOT / "checks/cites-census.py")
cc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cc)

IDX: dict[str, list[str]] = {}
for p in subprocess.run(["git", "ls-tree", "-r", "HEAD", "--name-only"], cwd=ROOT,
                        capture_output=True, text=True, check=True).stdout.splitlines():
  i = p.find("/")
  while i != -1:
    IDX.setdefault(p[i:], []).append(p)
    i = p.find("/", i + 1)

labels = {}
for line in (ROOT / ".agents/slop/failaudit/handlabels.rows").read_text().splitlines():
  f = line.split("\t")
  labels[f[2][1:] if f[2].startswith(".") else f[2]] = f[1]

n = 0
for line in (ROOT / ".agents/slop/residual/new-after.rows").read_text().splitlines():
  f = line.split("\t")
  if len(f) < 6 or f[2] != "suffix-index":
    continue
  n += 1
  anchor, subj, needle = f[3], f[4], f[5]
  path, _, ln = anchor.rpartition(":")
  src = ""
  try:
    src = (ROOT / path).read_text(errors="replace").splitlines()[int(ln) - 1].strip()
  except (OSError, IndexError, ValueError):
    pass
  hits = IDX.get("/" + subj, [])
  real = hits[0] if len(hits) == 1 else f"AMBIG({len(hits)}):{hits}"
  text = None
  try:
    text = (ROOT / real).read_text(errors="replace")
  except OSError:
    pass
  nd = needle[1:-1].replace("\\n", "\n").replace("\\t", "\t") if needle.startswith("'") else ""
  present = (nd in text) if (text is not None and nd) else None
  lab = labels.get(anchor[1:] if anchor.startswith(".") else anchor, "?")
  print(f"[{n:2d}] {anchor}  label={lab}")
  print(f"     subj={subj} -> {real}  needle={needle}  present={present}")
  print(f"     line: {src}")
