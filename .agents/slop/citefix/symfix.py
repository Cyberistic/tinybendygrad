#!/usr/bin/env python3
"""symfix.py -- THE TODO-CITE GATE'S OWN VERDICT, TURNED INTO EDITS.

    .venv/bin/python .agents/slop/citefix/symfix.py --rows todo.rows --out EDITS.rows

The gate says three things that are EDITS:

  WRONG-LINE    the symbol is RIGHT and the LINE is wrong. The gate's own `decl_line` is
                where the symbol is declared, so the citation moves there.
  WRONG-SYMBOL  the symbol names something the cited file does not declare. The field is
                REMOVED: a citation with no `symbol=` is not measured by that gate, and a
                field that names a construct upstream does not have is a false claim.
  UNRESOLVABLE  with `how=no-file` the SUBJECT names no file the gate can resolve -- a
                file outside `tinygrad/`, or an ambiguous basename. The field is removed
                for the same reason.

Nothing else is touched: the gate's PASS rows are left exactly as they are.
"""

from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--rows", required=True)
  ap.add_argument("--out", required=True)
  ap.add_argument("--skip", default="tinybendygrad/runtime/")
  args = ap.parse_args()
  rows = list(csv.DictReader(open(args.rows, encoding="utf-8"), delimiter="\t"))
  edits: list[dict] = []
  for r in rows:
    rel = r["rel"]
    if rel.startswith(args.skip):
      continue
    verdict, how = r["verdict"], r["how"]
    line = r["line"]
    if verdict == "WRONG-LINE":
      decl = int(r["decl_line"])
      lo, hi = int(r["lo"]), int(r["hi"])
      width = hi - lo
      new = f"{r['subject']}:{decl}" + (f"-{decl + width}" if width else "")
      old = re.search(rf"{re.escape(r['subject'])}:\d+(?:-\d+)?", line)
      if not old:
        continue
      edits.append({"rel": rel, "at": int(r["at"]), "old": old.group(0), "new": new, "count": ""})
    elif verdict == "WRONG-SYMBOL" or (verdict == "UNRESOLVABLE" and how == "no-file"):
      m = re.search(r"symbol=[A-Za-z_][A-Za-z0-9_.]*", line)
      if not m:
        continue
      edits.append({"rel": rel, "at": int(r["at"]), "old": m.group(0), "new": "", "count": "all"})
  with open(args.out, "w", encoding="utf-8", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=["rel", "at", "old", "new", "count"], delimiter="\t",
                       lineterminator="\n")
    w.writeheader()
    w.writerows(edits)
  print(f"{len(edits)} edits -> {args.out}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
