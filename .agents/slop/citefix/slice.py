#!/usr/bin/env python3
"""slice.py -- MY SLICE of the census: the false citations OUTSIDE the `TODO(pN)`
population, in the files THIS UNIT owns.

    .venv/bin/python .agents/slop/citefix/slice.py --pin ROWS --todo ROWS --out ROWS

THE CENSUS LOGIC IS NOT COPIED. `.agents/slop/citeclass/census.py` IS IMPORTED BY PATH and
its `ROOT` is pointed at the tree being measured, so the classification -- which row is
FALSE, and which row is inside the marker population -- is the census's own, and this
file only SELECTS.

THE SLICE IS A PATH RULE, NOT A LIST. `tinybendygrad/runtime/**` belongs to another unit,
so every row whose `rel` starts with that prefix is not mine. The prefix is the tree's
own layout, not a population of files.

THE FREEZE. `--tree DIR` measures a COPY of the port tree, so a before/after reading
compares two trees and not two moments. `--tree` defaults to the live tree.
"""

from __future__ import annotations

import argparse
import collections
import csv
import importlib.util
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent.parent
CENSUS_PATH = ROOT / ".agents" / "slop" / "citeclass" / "census.py"

#: THE OTHER UNIT's TERRITORY. A path rule, so a file that moves is still excluded.
NOT_MINE = "tinybendygrad/runtime/"


def load_census(tree_root: Path):
  spec = importlib.util.spec_from_file_location("citeclass_census", CENSUS_PATH)
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  mod.ROOT = tree_root
  return mod


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--pin", required=True)
  ap.add_argument("--todo", required=True)
  ap.add_argument("--out", required=True)
  ap.add_argument("--tree", default=str(ROOT), help="the tree root that holds tinybendygrad/")
  ap.add_argument("--all", action="store_true", help="also print the rows that are not false")
  args = ap.parse_args()

  tree_root = Path(args.tree).resolve()
  census = load_census(tree_root)
  pin_rows = census.read_rows(Path(args.pin))
  todo_rows = census.read_rows(Path(args.todo))
  gate_pop = {(r["rel"], r["subject"], r["lo"]) for r in todo_rows}

  lines_by_rel: dict[str, list[str]] = {}
  for p in census.walk_bend(tree_root / census.PORT_REL):
    rel = str(p.relative_to(tree_root))
    lines_by_rel[rel] = p.read_text(encoding="utf-8", errors="replace").splitlines()

  out_rows: list[dict] = []
  for r in pin_rows:
    rel, at = r["rel"], int(r["at"])
    src = lines_by_rel.get(rel)
    if src is None:
      continue
    line = src[at - 1]
    by_line = bool(census.MARKER.search(line))
    by_gate = (rel, r["subject"], r["lo"]) in gate_pop
    cls = r["class"]
    if cls == "at_pin":
      false = "no"
    elif cls == "uncheckable_no_claim_token":
      false = "unverifiable-no-claim-token"
    elif cls == "unverifiable":
      false = "unverifiable-no-claim-about-the-file"
    else:
      false = "yes"
    mine = not rel.startswith(NOT_MINE)
    out_rows.append({
      "rel": rel, "at": at, "subject": r["subject"], "lo": r["lo"], "hi": r["hi"],
      "class": cls, "at_pin": r["at_pin"], "false_at_pin": false,
      "tagged_by_line": int(by_line), "tagged_by_gate": int(by_gate),
      "marker": (census.MARKER.search(line).group(1) if by_line else ""),
      "mine": int(mine), "claim": r["claim"], "line": line,
    })

  outp = Path(args.out)
  outp.parent.mkdir(parents=True, exist_ok=True)
  with outp.open("w", encoding="utf-8", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=list(out_rows[0].keys()), delimiter="\t",
                       lineterminator="\n")
    w.writeheader()
    w.writerows(out_rows)

  def false_rows(rows):
    return [r for r in rows if r["false_at_pin"] == "yes"]

  mine_all = [r for r in out_rows if r["mine"]]
  mine_false = false_rows(mine_all)
  mine_false_unmeasured = [r for r in mine_false if not r["tagged_by_gate"]]
  theirs_false = false_rows([r for r in out_rows if not r["mine"]])

  print(f"tree        : {tree_root}")
  print(f"citations   : {len(out_rows)}")
  print(f"MY SLICE    : {len(mine_all)} citations, {len(mine_false)} FALSE at the pin")
  print(f"  of those  : {len(mine_false_unmeasured)} not measured by todo-cite-gate.py")
  print(f"THEIR SLICE : {len(theirs_false)} FALSE at the pin (not mine)")
  print()
  print("MY FALSE ROWS, BY FILE:")
  per = collections.defaultdict(lambda: [0, 0])
  for r in mine_false:
    per[r["rel"]][0] += 1
    per[r["rel"]][1] += 1
    if not r["tagged_by_gate"]:
      per[r["rel"]][1] += 0
  for rel, (nf, _n) in sorted(per.items(), key=lambda kv: (-kv[1][0], kv[0])):
    print(f"  {nf:5d}  {rel}")
  print()
  print("MY FALSE ROWS, BY CLASS:")
  c = collections.Counter(r["class"] for r in mine_false)
  for cls, n in c.most_common():
    print(f"  {n:5d}  {cls}")
  if args.all:
    print()
    for r in mine_false:
      print(f"{r['rel']}:{r['at']}  {r['subject']}:{r['lo']}-{r['hi']}  {r['class']}  "
            f"claim={r['claim']}")
      print(f"    {r['line']}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
