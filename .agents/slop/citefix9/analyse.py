#!/usr/bin/env python3
"""analyse.py -- FOR EACH QUEUE ROW: WHICH UPSTREAM FILE, AND DOES THE CLAIM HOLD THERE?

    .venv/bin/python .agents/slop/citefix9/analyse.py

The port tree's own header declares an upstream target, and the census resolves a bare
basename with that directory as the AMBIENT. A row whose subject is AMBIGUOUS names no
file, so nothing was ever tested against a file -- this asks the question the census
could not: for each candidate upstream file that carries the basename, DOES THE CLAIM
HOLD AT THE PIN?

THE PIN IS THE PIN, read out of the same place the gate reads it.
"""

from __future__ import annotations

import csv
import importlib.util
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def load(name: str, path: Path):
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


def git(*args: str) -> str:
  p = subprocess.run(("git", "--no-optional-locks") + args, cwd=ROOT, capture_output=True, text=True)
  return p.stdout


def main() -> int:
  pin = git("log", "-1", "--format=%H", "refs/remotes/upstream/master", "--", "tinygrad/").strip()
  pc = load("pincite", ROOT / "gates" / "pin-cite-gate.py")
  hc = load("hcensus", ROOT / "gates" / "header-census-gate.py")
  corpus = hc.Upstream(pc.UPSTREAM)

  with (ROOT / ".agents/slop/citefix/left-tok9.rows").open(encoding="utf-8") as fh:
    rows = list(csv.DictReader(fh, delimiter="\t"))
  cache: dict[str, list[str]] = {}

  def up_lines(path: str) -> list[str]:
    if path not in cache:
      cache[path] = git("show", f"{pin}:{path}").splitlines()
    return cache[path]

  for r in rows:
    rel, at = r["rel"], int(r["at"])
    toks = [t for t in r["tokens"].split(",") if t]
    hits = corpus.files().get(r["subject"], [])
    if r["subject"].endswith(".py") and "/" in r["subject"]:
      hits = [r["subject"]] if corpus.resolve(r["subject"], history=True)[0] else []
    print("=" * 110)
    print(f"{rel}:{at}   subject={r['subject']}  cited={r['lo']}-{r['hi']}  class={r['class']}")
    print(f"   tokens: {toks}")
    for cand in hits:
      lines = up_lines(cand)
      lo, hi = int(r["lo"]), int(r["hi"])
      if hi > len(lines):
        print(f"   {cand}: only {len(lines)} lines -- cited :{hi} is OUT OF RANGE")
        continue
      ok, why = pc.holds(lines, lo, hi, toks)
      present = [t for t in toks if t in "\n".join(lines)]
      print(f"   {cand}: holds={ok}  {why}")
      print(f"        tokens present in file: {present}")
      if not ok:
        print(f"        line {lo}: {lines[lo-1].strip()[:100]!r}")
    if not hits:
      print("   NO UPSTREAM FILE WITH THAT BASENAME")
      ever = corpus.ever().get(r["subject"], [])
      print(f"   ever existed: {ever}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
