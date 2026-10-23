#!/usr/bin/env python3
"""review.py -- THE PROPOSED RE-POINTS, WITH THE UPSTREAM LINES THEY POINT AT.

    .venv/bin/python .agents/slop/citefix/review.py --edits EDITS.rows

Prints, for every proposed edit: the port's line, the upstream line the citation names
NOW, and the upstream line the proposal names. A proposal is only worth taking when the
upstream line it names HOLDS the claim -- and that is a judgement a reader makes here.
"""

from __future__ import annotations

import argparse
import csv
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PIN = "5c2bf39d6c4b"
CACHE: dict[str, list[str]] = {}


def up(path: str) -> list[str]:
  if path not in CACHE:
    CACHE[path] = subprocess.run(
      ("git", "--no-optional-locks", "show", f"{PIN}:{path}"), cwd=ROOT,
      capture_output=True, text=True).stdout.splitlines()
  return CACHE[path]


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--edits", required=True)
  ap.add_argument("--only", default="")
  args = ap.parse_args()
  rows = list(csv.DictReader(open(args.edits, encoding="utf-8"), delimiter="\t"))
  src: dict[str, list[str]] = {}
  for e in rows:
    rel = e["rel"]
    at = int(e["at"])
    if rel not in src:
      src[rel] = (ROOT / rel).read_text(encoding="utf-8").splitlines()
    if args.only and args.only not in rel:
      continue
    line = src[rel][at - 1]
    # THE UPSTREAM PATH, from the port file's own declared target and the subject.
    path = None
    for cand in (e["new"], e["old"]):
      m = re.match(r"([\w./-]+\.py):", cand)
      if m:
        p = m.group(1)
        if not p.startswith("tinygrad/"):
          p = "tinygrad/" + p
        path = p
        break
    def show(txt: str) -> str:
      m = re.search(r":(\d+)(?:-(\d+))?", txt)
      if not path or not m:
        return "?"
      n = int(m.group(1))
      lines = up(path)
      return lines[n - 1].strip()[:100] if 0 < n <= len(lines) else "?"
    print(f"{rel}:{at}")
    print(f"  PORT : {line.strip()[:150]}")
    print(f"  OLD  : {e['old']}  ->  {show(e['old'])}")
    print(f"  NEW  : {e['new']}  ->  {show(e['new'])}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
