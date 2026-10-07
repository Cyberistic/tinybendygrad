#!/usr/bin/env python
"""CENSUS BY DISCOVERY: which committed Python reads the INDEX rather than the TREE.

The population is DISCOVERED by `os.walk` over a named set of roots, not listed. A census from a
hand list is the fault this project removes every night (AGENTS.md doctrine 1).
"""
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent.parent

# THE ROOTS OF THE WALK. Every one is a directory whose OWN `.py` files are the population.
ROOTS = ("checks", "gates", ".agents/slop")

# INDEX-READING SHAPES: id -> (regex, one-line description).
SHAPES = {
  "ls-files": (re.compile(r"\bls-files\b"),
    "lists the INDEX: the staging area, which a reset empties"),
  "cached": (re.compile(r"--cached|\bdiff-index\b"),
    "diff --cached is index-vs-HEAD; a reset index makes it EMPTY"),
  "read-tree": (re.compile(r"\bread-tree\b"),
    "WRITES the index -- the operation that CAUSED destructions 2 and 3"),
  "add": (re.compile(r"(?:git|['\"]git['\"]|['\"]-C['\"])(?:\s*\([^)]{0,80}\))*\s*,?\s*['\"]add['\"]"
                     r"|\bgit\s+(-C\s+\S+\s+)*add\b|git\.add\b|\badd\s+-[A-Za-z]*A\b"),
    "`git add` stages; `git add -A` is what committed the .txt violations"),
  "porcelain": (re.compile(r"--porcelain"),
    "porcelain status reads index+worktree, not the tree"),
}

# TREE-READING (SAFE) SHAPES: id -> regex.
SAFE = {
  "ls-tree":  re.compile(r"\bls-tree\b"),
  "diff-tree":re.compile(r"\bdiff-tree\b"),
  "cat-file": re.compile(r"\bcat-file\b"),
  "git-grep": re.compile(r"\bgit\b[^\n]{0,30}\bgrep\b"),
  "rev-parse":re.compile(r"\brev-parse\b"),
}

SKIP_DIRS = {".git", "__pycache__", ".venv", "node_modules", "references", ".jj"}


def walk_population(roots):
  """DISCOVERY, not a list. Yields every .py under each root dir."""
  for r in roots:
    base = ROOT / r
    if not base.is_dir():
      continue
    for dirpath, dirnames, filenames in os.walk(base):
      dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
      for fn in filenames:
        if fn.endswith(".py"):
          yield Path(dirpath) / fn


def committed(path):
  """COMMITTED FILES ONLY -- read from the TREE, never the index."""
  rel = str(path.relative_to(ROOT))
  r = subprocess.run(["git", "cat-file", "-e", f"HEAD:{rel}"],
                     cwd=ROOT, capture_output=True)
  return r.returncode == 0


def scan(path):
  try:
    src = path.read_text(encoding="utf-8", errors="replace")
  except OSError:
    return None
  lines = src.splitlines()
  idx_hits, safe_hits = [], []
  for n, line in enumerate(lines, 1):
    s = line.strip()
    if s.startswith("#"):
      continue
    for name, pat in SAFE.items():
      if pat.search(line):
        safe_hits.append((name, n, s[:140]))
    for name, (pat, _desc) in SHAPES.items():
      if pat.search(line):
        idx_hits.append((name, n, s[:140]))
  return {"path": str(path.relative_to(ROOT)), "index": idx_hits,
          "safe": sorted({h[0] for h in safe_hits})}


def main():
  rows = []
  for p in walk_population(ROOTS):
    r = scan(p)
    if r and r["index"]:
      r["committed"] = committed(p)
      rows.append(r)
  rows.sort(key=lambda r: r["path"])
  out = Path(__file__).resolve().parent / "census.rows"
  with out.open("w", encoding="utf-8") as fh:
    for r in rows:
      kinds = ",".join(sorted({h[0] for h in r["index"]}))
      fh.write(f"{r['path']}\t{kinds}\tcommitted={r['committed']}\tsafe={','.join(r['safe'])}\n")
  n = len(rows)
  ncommit = sum(1 for r in rows if r["committed"])
  print(f"WALK SCOPE: roots={ROOTS} pruned={sorted(SKIP_DIRS)}")
  total = sum(1 for _ in walk_population(ROOTS))
  print(f"POPULATION (all .py discovered): {total}")
  print(f"INDEX-READING: {n}  (committed: {ncommit}, uncommitted: {n - ncommit})")
  kinds = {}
  for r in rows:
    for h in r["index"]:
      kinds[h[0]] = kinds.get(h[0], 0) + 1
  for k, v in sorted(kinds.items(), key=lambda kv: -kv[1]):
    print(f"  {k:12s} {v}")
  print(f"SAFE-ONLY (no index shape at all): {total - n}")
  print(f"ROWS -> {out}")
  return 0


if __name__ == "__main__":
  sys.exit(main())