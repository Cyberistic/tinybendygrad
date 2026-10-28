#!/usr/bin/env python3
"""mine.py -- COUNT THE SLICE'S ROWS IN A GATE'S ROWS FILE.

    .venv/bin/python .agents/slop/unv3/mine.py pin  <rows>   # unverifiable count
    .venv/bin/python .agents/slop/unv3/mine.py bend <rows>   # WRONG-LINE + DANGLING-LINE

THE POPULATION IS THE SLICE'S OWN FILE LIST, AND IT IS DISCOVERED FROM THE ROWS FILE
THE ORCHESTRATOR GAVE ME (`unv3.rows`), NOT NAMED TWICE: one copy of the list is a
contract with no generator.
"""
import csv, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
SLICE = pathlib.Path("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/slices/unv3.rows")


def slice_files() -> set[str]:
  out = set()
  with SLICE.open() as f:
    for row in csv.reader(f, delimiter="\t"):
      if row and row[0].endswith(".bend"):
        out.add(row[0])
  return out


def main() -> int:
  mode, rows_path = sys.argv[1], sys.argv[2]
  mine = slice_files()
  with open(rows_path) as f:
    rows = list(csv.reader(f, delimiter="\t"))
  hdr, body = rows[0], rows[1:]
  if mode == "pin":
    ci = {n: i for i, n in enumerate(hdr)}
    bad = [r for r in body if r[ci["rel"]] in mine and r[ci["class"]] == "unverifiable"]
    per: dict[str, int] = {}
    for r in bad:
      per[r[ci["rel"]]] = per.get(r[ci["rel"]], 0) + 1
    print(f"unverifiable in slice: {len(bad)}")
    for k in sorted(per):
      print(f"  {per[k]:3d}  {k}")
    return 0 if not bad else 1
  # bendcite
  ci = {n: i for i, n in enumerate(hdr)}
  bad = [r for r in body if r[ci["rel"]] in mine and r[ci["verdict"]] in ("WRONG-LINE", "DANGLING-LINE")]
  per: dict[str, int] = {}
  for r in bad:
    per[r[ci["rel"]]] = per.get(r[ci["rel"]], 0) + 1
  print(f"WRONG-LINE+DANGLING-LINE in slice: {len(bad)}")
  for k in sorted(per):
    print(f"  {per[k]:3d}  {k}")
  if "-v" in sys.argv:
    for r in bad:
      print("   ", r[ci["rel"]], r[ci["at"]], r[ci["subject"]], r[ci["verdict"]], r[ci["decl"]])
  return 0 if not bad else 1


if __name__ == "__main__":
  sys.exit(main())
