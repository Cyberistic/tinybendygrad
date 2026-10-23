#!/usr/bin/env python3
"""commentonly.py -- THE COMMENT-ONLY PROOF, FOR EVERY FILE THE UNIT TOUCHED.

    .venv/bin/python .agents/slop/citefix-runtime/commentonly.py [FILES...]

`strip_comments()` is `checks/port-compile-gate.py`'s OWN, loaded BY PATH, so the proof
uses the INSTRUMENT'S definition of a comment and not a second one. The two texts are
compared with BLANK LINES DROPPED, because a comment-only edit that reflows a paragraph
changes the blank lines and nothing else.

A file that FAILS the proof is printed with the first differing line, and the exit status
is 1.
"""

from __future__ import annotations

import importlib.util
import subprocess
import sys
import warnings
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def load(name: str, path: Path):
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    spec.loader.exec_module(mod)
  return mod


def code(text: str) -> list[str]:
  gate = load("commentonly_gate", ROOT / "checks" / "port-compile-gate.py")
  return [ln for ln in gate.strip_comments(text).split("\n") if ln.strip()]


def main(argv: list[str]) -> int:
  files = argv[1:]
  if not files:
    files = subprocess.run(["git", "diff", "--name-only", "--", "tinybendygrad/runtime/"],
                           cwd=ROOT, capture_output=True, text=True).stdout.split()
  bad = 0
  for f in files:
    p = ROOT / f
    head = subprocess.run(["git", "show", f"HEAD:{f}"], cwd=ROOT, capture_output=True, text=True)
    if head.returncode:
      print(f"SKIP (not in HEAD): {f}")
      continue
    a, b = code(head.stdout), code(p.read_text(encoding="utf-8"))
    if a == b:
      print(f"COMMENT-ONLY  {f}  ({len(a)} code line(s))")
      continue
    bad += 1
    print(f"FAILED        {f}  (HEAD {len(a)} code line(s), NOW {len(b)})")
    for i in range(max(len(a), len(b))):
      x = a[i] if i < len(a) else "<none>"
      y = b[i] if i < len(b) else "<none>"
      if x != y:
        print(f"   first difference at code line {i + 1}:")
        print(f"     HEAD {x[:120]}")
        print(f"     NOW  {y[:120]}")
        break
  print(f"{len(files)} file(s) checked; {bad} FAILED")
  return 1 if bad else 0


if __name__ == "__main__":
  raise SystemExit(main(sys.argv[1:]))
