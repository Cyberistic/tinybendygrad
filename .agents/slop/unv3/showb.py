#!/usr/bin/env python3
"""showb.py -- THE SLICE'S STALE `.bend` POINTERS, WITH THE PORT TEXT AND THE REAL LINE.

    .venv/bin/python .agents/slop/unv3/showb.py <bend.rows>

For each row it prints: the port file and line, the port's OWN text, the subject
and the cited range, the construct the gate says IS at the cited line, and the
construct the row CLAIMS -- so a rewrite can name the construct and not a number.
"""
import csv, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
SLICE = pathlib.Path("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/slices/unv3.rows")


def slice_files() -> set[str]:
  out = set()
  for row in csv.reader(SLICE.open(), delimiter="\t"):
    if row and row[0].endswith(".bend"):
      out.add(row[0])
  return out


def main() -> int:
  with open(sys.argv[1]) as f:
    rows = list(csv.reader(f, delimiter="\t"))
  hdr, body = rows[0], rows[1:]
  ci = {n: i for i, n in enumerate(hdr)}
  mine = slice_files()
  for r in body:
    rel = r[ci["rel"]]
    if rel not in mine:
      continue
    if r[ci["verdict"]] not in ("WRONG-LINE", "DANGLING-LINE"):
      continue
    at = int(r[ci["at"]])
    src = ROOT / rel
    lines = src.read_text().splitlines() if src.is_file() else []
    lo = max(0, at - 1)
    hi = min(len(lines), at + 1)
    print(f"=== {rel}:{at}  ->  {r[ci['subject']]}:{r[ci['lo']]}-{r[ci['hi']]}")
    print(f"    claimed={r[ci['claim']]!r}  tier={r[ci['tier']]!r}")
    print(f"    decl-at-cited-line={r[ci['decl']]!r}  at_line={r[ci['at_line']]!r} delta={r[ci['delta']]!r}")
    for i in range(lo, hi):
      print(f"    {i+1}: {lines[i]}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
