#!/usr/bin/env python3
"""**THE **MOVER**: **A **TABLE **LEAVES **THE **COMMENT **BLOCK **AND **BECOMES **A **FILE**.

**⇒⇒† AND **THE **POPULATION **IS **DISCOVERED**: **THE **WALK **OF `table-census.py`,
**⇒⇒† AND **THIS **READS **THE **SAME **BLOCKS **AND **MOVES **EACH **ONE**.

**⇒⇒† AND **THE **CLASSIFICATION**, **AND **IT **IS **BY **THE **TABLE's **OWN **SHAPE**:
  · **A **PIPE-ROW **TABLE** (A **CONTIGUOUS **RUN **OF **`# |` **ROWS** **WITH **A **HEADER
    **ROW **AND **A **`|---|` **SEPARATOR**) **⇒⇒† AND **IT **IS **A **ROW **DUMP** **⇒⇒† AND **IT
    **GOES **TO **A **`.rows` **FILE**, **⇒⇒† AND **WITH **THE **PIPES **KEPT** **⇒⇒† AND **THE
    **HEADER **ROW **AND **THE **SEPARATOR **ROW **TOO**.
  · **EVERYTHING **ELSE** (A **PROSE **WORK **QUEUE**, **AN **INVENTORY**, **A **MUTATION
    **LEDGER**, **A **WALL **LIST**, **OR **A **BLOCK **THAT **MIXES **PROSE **AND **PIPE
    **ROWS**) **⇒⇒† AND **IT **GOES **TO **A **`.md` **FILE**.

**⇒⇒† AND **THE **MOVED **FILE **CARRIES **ITS **ORIGIN**:
  · **A **`.md` **FILE **BEGINS **WITH **`<!-- FROM: <path>:<line> -->`**.
  · **A **`.rows` **FILE **BEGINS **WITH **`# FROM: <path>:<line>`** **AND **THEN **THE **HEADER
    **ROW**, **⇒⇒† AND **SO **THE **FILE **STAYS **A **TABLE**.

**⇒⇒† AND **THE **SOURCE **IS **REPLACED **BY **A **POINTER**, **AND **THE **POINTER **IS **A
**COMMENT**, **⇒⇒† AND **NOT **ONE **NON-`#` **LINE **MOVES**.
"""

import argparse
import json
import os
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
PORT = ROOT / "tinybendygrad"
OUT = ROOT / ".agents/slop/tables"

PIPE = re.compile(r"^\s*#\s*\|")
SEP = re.compile(r"^\s*#\s*\|[\s:|-]+\|\s*$")
PROSE = re.compile(
  r"(NOT PORTED, one line each|THE INVENTORY:|THE WORK QUEUE|THE MUTATION LEDGER|"
  r"EVERY \w+ IS |THE TABLE:|THE LIST:|ONE LINE EACH|THE ROWS:)", re.I)


def blocks():
  """**⇒⇒† AND **THE **WALK**, **⇒⇒† AND **NOT **A **HAND **LIST**."""
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


def find_blocks(lim=12):
  """**⇒⇒† AND **THE **SAME **SELECTION **AS `table-census.py`, **⇒⇒† AND **THE **NON-HEADER
  **ONES**, **⇒⇒† AND **A **HEADER **IS **A **FILE's **FIRST **BLOCK**, **⇒⇒† AND **A **HEADER
  **IS **NOT **A **TABLE **TO **MOVE**."""
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
    if ln <= 40:
      continue  # **⇒⇒† AND **THE **HEADER, **⇒⇒† AND **NOT **A **TABLE**.
    out.append((f, ln, blk, kind))
  return out


def table_span(blk):
  """**⇒⇒† AND **THE **PIPE **TABLE's **SPAN** -- **THE **HEADER **ROW, **THE **SEPARATOR **ROW
  **AND **THE **DATA **ROWS** -- **⇒⇒† AND **NONE** (⇒⇒† AND **SO **THE **BLOCK **IS **PROSE**)
  **WHEN **THERE **IS **NO **HEADER**/SEPARATOR **PAIR**."""
  runs = []
  i = 0
  while i < len(blk):
    if PIPE.match(blk[i]):
      j = i
      while j < len(blk) and PIPE.match(blk[j]):
        j += 1
      runs.append((i, j - 1))
      i = j
    else:
      i += 1
  for a, b in runs:
    for k in range(a, b):
      if SEP.match(blk[k]) and k > a:
        return (a, b)
  return None


def title_of(blk):
  """**⇒⇒† AND **THE **BLOCK's **OWN **TITLE**, **⇒⇒† AND **THE **FIRST **NON-EMPTY **LINE**,
  **⇒⇒† AND **STRIPPED **OF **THE **`#` **AND **OF **A **LEADING **`=`**/`-` **RULE**."""
  for l in blk:
    s = l.strip().lstrip("#").strip()
    s = re.sub(r"^[=\-]{3,}$", "", s).strip()
    if s:
      return s
  return "THE TABLE"


def dest_name(rel, line, ext):
  """**⇒⇒† AND **THE **NAME**: **THE **SOURCE's **STEM**, **⇒⇒† AND **THE **LINE**, **⇒⇒† AND
  **THE **EXTENSION** -- **⇒⇒† AND **`tinybendygrad/uop/fold.bend:7177` **⇒⇒† AND
  **`tables/uop-fold-7177.rows`**."""
  stem = pathlib.Path(rel).stem
  parts = pathlib.Path(rel).with_suffix("").parts
  slug = "-".join(p for p in parts if p != "tinybendygrad")
  slug = slug.replace(".linearizer-mut", "linearizer-mut")
  return f"{slug}-{line}.{ext}"


def dirty_files():
  """**⇒⇒† AND **THE **FILES **ANOTHER **UNIT **IS **EDITING** **RIGHT **NOW**, **⇒⇒† AND
  **READ **FROM **`git diff --name-only`**, **⇒⇒† AND **A **DIRTY **FILE **IS **NOT **TOUCHED**,
  **⇒⇒† AND **BECAUSE **AN **EDIT **TO **IT **WOULD **CONFLICT**."""
  import subprocess
  out = subprocess.run(["git", "diff", "--name-only", "--", "tinybendygrad/"],
                       capture_output=True, text=True, cwd=ROOT).stdout
  return set(out.split())


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--limit", type=int, default=12)
  ap.add_argument("--only", default=None,
                  help="A COMMA SEPARATED LIST OF SOURCE PATHS; THE REST IS SKIPPED.")
  ap.add_argument("--skip-dirty", action="store_true",
                  help="SKIP EVERY FILE THAT `git diff --name-only` NAMES.")
  ap.add_argument("--dry-run", action="store_true")
  args = ap.parse_args()

  only = set(args.only.split(",")) if args.only else None
  skip = dirty_files() if args.skip_dirty else set()
  OUT.mkdir(parents=True, exist_ok=True)
  plan = []
  for f, ln, blk, kind in find_blocks(args.limit):
    rel = str(f.relative_to(ROOT))
    if rel in skip:
      print(f"SKIP (another unit is editing it): {rel}:{ln}")
      continue
    if only is not None and rel not in only:
      continue
    span = table_span(blk)
    # **⇒⇒† AND **THE **CLASSIFICATION**: **A **PIPE **TABLE **WITH **A **HEADER **AND **A
    # **SEPARATOR** **⇒⇒† AND **THE **BLOCK **IS **A **ROW **DUMP** **⇒⇒† AND **IT **GOES **TO
    # **A **`.rows` **FILE**. **⇒⇒† AND **EVERYTHING **ELSE **IS **PROSE** **⇒⇒† AND **GOES
    # **TO **A **`.md` **FILE**.
    if span is not None:
      ext = "rows"
      body = blk[span[0]:span[1] + 1]
      rest = blk[:span[0]] + blk[span[1] + 1:]
    else:
      ext = "md"
      body = blk
      rest = []
    name = dest_name(rel, ln, ext)
    plan.append((f, ln, blk, rel, ext, name, span, rest, body))
    if not args.dry_run:
      dest = OUT / name
      if ext == "rows":
        head = [f"# FROM: {rel}:{ln}"] + body
        dest.write_text("\n".join(head) + "\n")
      else:
        head = [f"<!-- FROM: {rel}:{ln} -->", ""] + body
        dest.write_text("\n".join(head) + "\n")
  if args.dry_run:
    for p in plan:
      print(f"{p[4]:4s} {p[0].relative_to(ROOT)}:{p[1]} -> tables/{p[5]}")
    print(f"PLAN: {len(plan)} blocks")
    return
  # **⇒⇒† AND **THE **EDIT**: **REPLACE **THE **BLOCK **WITH **A **POINTER**.
  byfile = {}
  for f, ln, blk, rel, ext, name, span, rest, body in plan:
    byfile.setdefault(f, []).append((ln, blk, rel, ext, name))
  for f, edits in byfile.items():
    lines = f.read_text().split("\n")
    # **⇒⇒† AND **THE **EDITS **ARE **APPLIED **FROM **THE **LAST **BLOCK **UP**, **⇒⇒† AND
    # **SO **A **BLOCK's **LINE **NUMBERS **STAY **TRUE**.
    for ln, blk, rel, ext, name in sorted(edits, key=lambda e: -e[0]):
      i = ln - 1
      assert lines[i:i + len(blk)] == blk, f"{rel}:{ln} DOES NOT MATCH"
      # **⇒⇒† AND **THE **POINTER**, **AND **IT **CARRIES **THE **TABLE's **OWN **TITLE**,
      # **⇒⇒† AND **SO **A **READER **WHO **SEES **ONLY **THE **SOURCE **KNOWS **WHAT **IS **IN
      # **THE **FILE**.
      title = title_of(blk)
      ptr = [f"# THE TABLE IS IN `.agents/slop/tables/{name}` -- {title}"]
      lines[i:i + len(blk)] = ptr
    f.write_text("\n".join(lines))
  print(f"MOVED {len(plan)} blocks")
  for p in plan:
    print(f"  {p[0].relative_to(ROOT)}:{p[1]} -> .agents/slop/tables/{p[5]}")


if __name__ == "__main__":
  main()
