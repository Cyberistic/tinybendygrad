#!/usr/bin/env python3
"""show.py -- UPSTREAM AT THE PIN, WITH LINE NUMBERS.

    .venv/bin/python .agents/slop/citefix/show.py tinygrad/mixin/movement.py 610-640
    .venv/bin/python .agents/slop/citefix/show.py tinygrad/mixin/movement.py 610-640 --decls

THE PIN IS THE VENDORED TREE's COMMIT, read from git, so a hand edit to the vendored copy
cannot make a false citation look true.
"""

from __future__ import annotations

import argparse
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PIN = "5c2bf39d6c4b"


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("path")
  ap.add_argument("span", nargs="?", default="")
  ap.add_argument("--decls", action="store_true", help="list every def/class in the file")
  ap.add_argument("--grep", default="", help="print the lines matching this regex")
  args = ap.parse_args()
  txt = subprocess.run(["git", "--no-optional-locks", "show", f"{PIN}:{args.path}"],
                       cwd=ROOT, capture_output=True, text=True)
  if txt.returncode:
    print(f"ABSENT: {args.path} is not at the pin")
    return 1
  lines = txt.stdout.splitlines()
  print(f"# {args.path} at {PIN}: {len(lines)} lines")
  if args.decls:
    for i, raw in enumerate(lines, 1):
      m = re.match(r"^(\s*)(?:async\s+)?(?:def|class)\s+([A-Za-z_]\w*)", raw)
      if m:
        print(f"{i:6d}  {m.group(2)}")
    return 0
  if args.grep:
    for i, raw in enumerate(lines, 1):
      if re.search(args.grep, raw):
        print(f"{i:6d}  {raw}")
    return 0
  if args.span:
    a, _s, b = args.span.partition("-")
    lo, hi = int(a), int(b or a)
    for i in range(lo, min(hi, len(lines)) + 1):
      print(f"{i:6d}  {lines[i - 1]}")
    return 0
  for i, raw in enumerate(lines, 1):
    print(f"{i:6d}  {raw}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
