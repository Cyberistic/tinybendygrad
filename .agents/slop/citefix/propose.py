#!/usr/bin/env python3
"""propose.py -- A TABLE OF RE-POINTS, ONE ROW PER FALSE CITATION.

    .venv/bin/python .agents/slop/citefix/propose.py --rows SUGGEST.rows --out ROWS

For every false citation, the claim tokens and, for each token, the line at the pin where
upstream DECLARES it. The proposal is NOT applied: it is the QUEUE, and a queue that is a
second copy of a list is a contract with no generator, so it is written BY this script from
the census rows and the pin.

THE TOKEN ORDER MATTERS. The port writes `NAME (file.py:N)`, so the FIRST claim token of a
citation is the construct it is about, and the proposal leads with that token's
declaration.
"""

from __future__ import annotations

import argparse
import csv
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PIN = "5c2bf39d6c4b"


def git(*args: str) -> str:
  return subprocess.run(("git", "--no-optional-locks",) + args, cwd=ROOT,
                        capture_output=True, text=True).stdout


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--rows", required=True)
  ap.add_argument("--out", required=True)
  args = ap.parse_args()

  rows = list(csv.DictReader(open(args.rows, encoding="utf-8"), delimiter="\t"))
  cache: dict[str, list[str]] = {}

  def lines_of(path: str) -> list[str]:
    if path not in cache:
      cache[path] = git("show", f"{PIN}:{path}").splitlines()
    return cache[path]

  out: list[dict] = []
  for r in rows:
    toks = [t for t in r["tokens"].split(",") if t]
    found: list[str] = []
    if r["up"] and toks:
      lines = lines_of(r["up"])
      for t in toks:
        hits = []
        for i, raw in enumerate(lines, 1):
          s = raw.strip()
          if not s or s.startswith("#"):
            continue
          m = re.match(r"(?:async\s+)?(?:def|class)\s+([A-Za-z_]\w*)", s)
          if m and m.group(1) == t:
            hits.append(i)
            continue
          m = re.match(r"([A-Za-z_]\w*)\s*(?::[^=]+)?=", s)
          if m and m.group(1) == t and not raw.startswith(" " * 8):
            hits.append(i)
        if hits:
          found.append(f"{t}={','.join(str(h) for h in hits[:6])}")
    rec = {**r, "decl_map": " ".join(found)}
    out.append(rec)

  with open(args.out, "w", encoding="utf-8", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=list(out[0].keys()), delimiter="\t", lineterminator="\n")
    w.writeheader()
    w.writerows(out)
  print(f"{len(out)} rows -> {args.out}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
