#!/usr/bin/env python3
"""**THE **TABLE **BLOCKS' **SHAPE**, **SO **THE **MOVE **CAN **BE **DECIDED**.

**⇒⇒† AND **THE **POPULATION **IS **DISCOVERED** (DOCTRINE 1): **THE **SAME **WALK **AS
`table-census.py`, **⇒⇒† AND **THIS **REPORTS **FOR **EACH **NON-HEADER **BLOCK**:
  · **THE **EXACT **LINE **SPAN** (first/last line, 1-based, inclusive)
  · **THE **PIPE **RUN** -- **THE **CONTIGUOUS **SPAN **OF **`# |` **ROWS**, **⇒⇒† AND **THE **HEADER
    **ROW **AND **THE **SEPARATOR **ROW **ARE **IN **IT**
  · **WHETHER **THE **PIPE **RUN **IS **THE **WHOLE **BLOCK** (**⇒⇒† AND **THEN **IT **IS **A
    **`.rows` **FILE**) **OR **ONLY **A **PART** (**⇒⇒† AND **THEN **IT **IS **A **`.md` **FILE**
    **WITH **THE **PIPE **TABLE **INSIDE **IT**)
"""

import json
import os
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
PORT = ROOT / "tinybendygrad"

PIPE = re.compile(r"^\s*#\s*\|")
PROSE = re.compile(
  r"(NOT PORTED, one line each|THE INVENTORY:|THE WORK QUEUE|THE MUTATION LEDGER|"
  r"EVERY \w+ IS |THE TABLE:|THE LIST:|ONE LINE EACH|THE ROWS:)", re.I)


def blocks():
  for dp, _, fns in os.walk(PORT):
    for fn in sorted(fns):
      if not fn.endswith(".bend"):
        continue
      f = pathlib.Path(dp) / fn
      lines = f.read_text().split("\n")
      i = 0
      while i < len(lines):
        if lines[i].strip().startswith("#"):
          j = i
          while j < len(lines) and lines[j].strip().startswith("#"):
            j += 1
          yield f, i + 1, lines[i:j]
          i = j
        else:
          i += 1


def pipe_runs(blk):
  """**⇒⇒† AND **THE **CONTIGUOUS **SPANS **OF **`# |` **ROWS**."""
  runs = []
  start = None
  for k, l in enumerate(blk):
    if PIPE.match(l):
      if start is None:
        start = k
    else:
      if start is not None:
        runs.append((start, k - 1))
        start = None
  if start is not None:
    runs.append((start, len(blk) - 1))
  return runs


if __name__ == "__main__":
  lim = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 12
  out = []
  for f, ln, blk in blocks():
    if len(blk) < lim:
      continue
    text = " ".join(blk)
    pipe = sum(1 for l in blk if PIPE.match(l))
    if pipe >= max(3, len(blk) // 4):
      kind = "ROWS"
    elif PROSE.search(text):
      kind = "MD"
    else:
      continue
    is_header = ln <= 40
    if is_header:
      continue
    runs = pipe_runs(blk)
    best = max(runs, key=lambda r: r[1] - r[0]) if runs else None
    out.append({
      "path": str(f.relative_to(ROOT)),
      "line": ln,
      "lines": len(blk),
      "kind": kind,
      "pipe": pipe,
      "last": ln + len(blk) - 1,
      "pipe_run": [best[0], best[1]] if best else None,
      "pipe_run_len": (best[1] - best[0] + 1) if best else 0,
      "n_runs": len(runs),
    })
  out.sort(key=lambda r: -r["lines"])
  for r in out:
    print(f"{r['lines']:5d} {r['kind']:4s} pipe={r['pipe']:3d} "
          f"run={r['pipe_run_len']:4d}/{r['lines']:4d} nruns={r['n_runs']:2d} "
          f"{r['path']}:{r['line']}-{r['last']}")
  print(f"TOTAL non-header blocks: {len(out)}, lines: {sum(r['lines'] for r in out)}")
  if "--json" in sys.argv:
    pathlib.Path(sys.argv[sys.argv.index("--json") + 1]).write_text(json.dumps(out, indent=1))
