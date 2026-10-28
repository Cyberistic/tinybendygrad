#!/usr/bin/env python3
"""show.py -- THE SLICE'S OWN REMAINING ROWS, WITH THE PORT LINE THEY COME FROM.

    .venv/bin/python .agents/slop/unv3/show.py <pin.rows> [bend.rows]

The rows file names the port file and the port line; this prints the PORT'S OWN
TEXT for that line, because the gate's row names the CLAIM and the claim is what
has to be rewritten.
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


def show(rows_path: str, want: set[str]) -> None:
  with open(rows_path) as f:
    rows = list(csv.reader(f, delimiter="\t"))
  hdr, body = rows[0], rows[1:]
  ci = {n: i for i, n in enumerate(hdr)}
  for r in body:
    rel = r[ci["rel"]]
    if rel not in slice_files():
      continue
    cls = r[ci.get("class", ci.get("verdict"))]
    if want and cls not in want:
      continue
    at = int(r[ci["at"]])
    src = ROOT / rel
    lines = src.read_text().splitlines() if src.is_file() else []
    text = lines[at - 1] if 0 < at <= len(lines) else "(no such line)"
    print(f"--- {rel}:{at}  [{cls}] subject={r[ci['subject']]} lo={r[ci['lo']]} hi={r[ci['hi']]} claim={r[ci.get('claim') or ci.get('decl')]}")
    print(f"    {text}")


if __name__ == "__main__":
  want = set(sys.argv[3:]) if len(sys.argv) > 3 else {"unverifiable"}
  show(sys.argv[1], want)
