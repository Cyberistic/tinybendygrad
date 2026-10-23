#!/usr/bin/env python3
"""apply.py -- APPLY A TABLE OF COMMENT-LINE REPLACEMENTS, BY LINE NUMBER.

    .venv/bin/python apply.py PATCH.tsv

The patch table is a TSV with a header and four columns: `rel`, `at`, `old`, `new`.
`at` is the 1-based line number, `old` is a SUBSTRING that the line must contain, and
`new` is the line's whole new text. The substring is the guard: a line that does not
contain it is REFUSED, so a patch that was written against a stale tree does not land on
the wrong line.

Every replacement must be COMMENT-ONLY: the script refuses a pair whose `old` and `new`
differ outside a comment. It refuses a non-comment line outright, and it refuses a `new`
that is not a comment when `old` was one.

The script is idempotent: a pair whose line already IS `new` is a no-op, and a pair whose
guard is absent from a line that already IS `new` is reported as ALREADY-APPLIED.
"""

from __future__ import annotations

import csv
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def main(argv: list[str]) -> int:
  if len(argv) != 1:
    print(__doc__)
    return 2
  rows = list(csv.DictReader(open(argv[0], encoding="utf-8"), delimiter="\t"))
  by_rel: dict[str, list[dict]] = {}
  for r in rows:
    by_rel.setdefault(r["rel"], []).append(r)
  bad = 0
  for rel, items in sorted(by_rel.items()):
    path = ROOT / rel
    lines = path.read_text(encoding="utf-8").split("\n")
    for r in items:
      at, old, new = int(r["at"]), r["old"], r["new"]
      if at < 1 or at > len(lines):
        print(f"REFUSED (line {at} is outside the file)  {rel}")
        bad += 1
        continue
      cur = lines[at - 1]
      if cur == new:
        print(f"NO-OP       {rel}:{at}")
        continue
      if old not in cur:
        print(f"REFUSED (guard absent)  {rel}:{at}: {cur[:80]}")
        bad += 1
        continue
      if not cur.lstrip().startswith("#") or not new.lstrip().startswith("#"):
        print(f"REFUSED (not a comment)  {rel}:{at}")
        bad += 1
        continue
      lines[at - 1] = new
    path.write_text("\n".join(lines), encoding="utf-8")
  print(f"APPLIED {len(rows)} pair(s); {bad} refused")
  return 1 if bad else 0


if __name__ == "__main__":
  raise SystemExit(main(sys.argv[1:]))
