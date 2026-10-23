#!/usr/bin/env python3
"""apply.py -- APPLY A TABLE OF COMMENT EDITS, AND PROVE THEY ARE COMMENT-ONLY.

    .venv/bin/python .agents/slop/citefix/apply.py --edits EDITS.rows

The edits table is TSV: `rel`, `at` (1-based line), `old` (the text to replace), `new`
(the text to put in its place). `old` must occur EXACTLY ONCE on that line, so an edit that
does not apply is a refusal and not a silent no-op.

THE TWO PROOFS, AND THEY ARE THE POINT OF THE FILE:
  LINE COUNT UNCHANGED -- a `.bend` file's line numbers are an INTERFACE: other files
                          cite them, so an edit that adds or removes a line breaks a
                          citation somewhere else.
  COMMENT-ONLY         -- `checks/port-compile-gate.py`'s own `strip_comments()`, imported
                          BY PATH, so the proof is the tree's proof and not a second
                          implementation of it.
"""

from __future__ import annotations

import argparse
import csv
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def load(name: str, path: Path):
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--edits", required=True)
  ap.add_argument("--dry", action="store_true")
  args = ap.parse_args()

  strip = load("port_compile_gate", ROOT / "checks" / "port-compile-gate.py").strip_comments

  rows = list(csv.DictReader(open(args.edits, encoding="utf-8"), delimiter="\t"))
  by_file: dict[str, list[dict]] = {}
  for r in rows:
    by_file.setdefault(r["rel"], []).append(r)

  bad: list[str] = []
  changed: list[str] = []
  # ALL OR NOTHING. A file is written only when every edit for it applied, and NO file is
  # written when any edit failed: a partial write is a tree that is neither the old one nor
  # the new one, and a citation table is the last place to have one.
  staged: list[tuple[Path, str]] = []
  for rel, edits in sorted(by_file.items()):
    path = ROOT / rel
    text = path.read_text(encoding="utf-8")
    lines = text.split("\n")
    n_before = len(lines)
    file_bad = 0
    for e in sorted(edits, key=lambda e: -int(e["at"])):
      at = int(e["at"])
      if at < 1 or at > len(lines):
        bad.append(f"{rel}:{at} is outside the file")
        file_bad += 1
        continue
      line = lines[at - 1]
      n = line.count(e["old"])
      # `count=all` says EVERY occurrence is the same edit -- the gate's row names the
      # LINE and the text, and two citations on one line can carry the same text.
      if e.get("count") == "all":
        if n == 0:
          bad.append(f"{rel}:{at} `old` occurs 0 times: {e['old']!r}")
          file_bad += 1
          continue
        lines[at - 1] = line.replace(e["old"], e["new"])
        continue
      if n != 1:
        bad.append(f"{rel}:{at} `old` occurs {n} times: {e['old']!r}")
        file_bad += 1
        continue
      lines[at - 1] = line.replace(e["old"], e["new"], 1)
    new_text = "\n".join(lines)
    if len(lines) != n_before:
      bad.append(f"{rel}: the line count moved {n_before} -> {len(lines)}")
      file_bad += 1
    if strip(text) != strip(new_text):
      bad.append(f"{rel}: the edit is NOT comment-only")
      file_bad += 1
    if file_bad:
      continue
    if new_text != text:
      changed.append(rel)
      staged.append((path, new_text))

  for b in bad:
    print(f"REFUSED: {b}")
  if bad:
    return 1
  if not args.dry:
    for path, new_text in staged:
      path.write_text(new_text, encoding="utf-8")
  print(f"applied {len(rows)} edits to {len(changed)} file(s)")
  for c in changed:
    print(f"  {c}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
