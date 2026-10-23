#!/usr/bin/env python3
"""commentproof.py -- EVERY FILE I TOUCHED STRIPS TO THE SAME CODE AS `HEAD`.

    .venv/bin/python .agents/slop/citefix/commentproof.py --files FILE...

`checks/port-compile-gate.py`'s own `strip_comments()`, imported BY PATH, so the proof is
the tree's proof. The comparison is against `HEAD`, read with `git show HEAD:<path>` -- NOT
the working copy and NOT the index, because this tree's index is armed.

A file that FAILS the proof is reported and the exit status is 1: a citation fix that
changes a line of code is not a citation fix.
"""

from __future__ import annotations

import argparse
import importlib.util
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
  p = subprocess.run(("git", "--no-optional-locks",) + args, cwd=ROOT,
                     capture_output=True, text=True)
  return p.stdout


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("files", nargs="+")
  ap.add_argument("--rev", default="HEAD")
  args = ap.parse_args()
  strip = load("port_compile_gate", ROOT / "checks" / "port-compile-gate.py").strip_comments
  bad = 0
  for rel in args.files:
    live = (ROOT / rel).read_text(encoding="utf-8")
    head = git("show", f"{args.rev}:{rel}")
    if not head:
      print(f"FAIL {rel}: {args.rev} has no such path")
      bad += 1
      continue
    same = strip(head) == strip(live)
    nl_head = len(head.split("\n"))
    nl_live = len(live.split("\n"))
    if not same:
      print(f"FAIL {rel}: the code differs from {args.rev}")
      bad += 1
    elif nl_head != nl_live:
      print(f"FAIL {rel}: the line count moved {nl_head} -> {nl_live}")
      bad += 1
    else:
      print(f"ok   {rel}: comment-only, {nl_live} lines unchanged")
  if bad:
    print(f"{bad} file(s) FAILED the comment-only proof")
    return 1
  print(f"COMMENT-ONLY PROOF: {len(args.files)} file(s) pass")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
