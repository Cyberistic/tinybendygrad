#!/usr/bin/env python3
"""blob-rows.py -- run every importer of `tinybendygrad/uop/ops.bend` and record its ROWS.

HARNESS CONTRACT, from `.agents/slop/agent-core.md`: this diffs WHOLE `name=value`
LINES, not row names. A name-comparing harness reported 0 for all 30 mutations in one
unit and 0 for all 68 in another.

It snapshots into `.agents/slop/blobrows/<tag>/<path>.txt`, so `before` and `after` are
two independent directories and the diff is `diff -r`. Nothing is patched in place: the
harness only READS `ops.bend` and every other file, so it cannot perturb the tree it is
measuring.

    .venv/bin/python .agents/slop/blob-rows.py before

A 0-row result is indistinguishable from "not started" here -- bend stack-overflows ~1
run in 20 -- so every run prints a per-file row count and a `ZERO` list, and any file
that reads 0 is re-run once before the snapshot is accepted.
"""
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BEND = os.path.join(REPO, 'bin/bend')
OPS = 'tinybendygrad/uop/ops.bend'
# bend's own "bend 2.0.35 is available" line is not a row of the file under test, and it
# changes whenever the toolchain is updated -- so it is filtered, and it is the ONLY
# thing filtered. Everything else on stdout is a row, INCLUDING lines that are not
# `name=value`: `uop/fold.bend` prints `bl_dt_w127_signed lo=NInf hi=PInf` and an earlier
# `^[a-z_]*=` matcher silently read that file as 0 rows.
BANNER = re.compile(r'^bend \d+\.\d+')


def importers() -> list[str]:
  """Every .bend file whose source names `ops.bend`, plus `ops.bend` itself.

  Sorted, so the snapshot directory listing is stable. The needle is the bare path
  segment: most importers write `import ./../uop/ops.bend`, so a lookbehind that
  excludes a preceding `/` drops 15 of the 72.
  """
  found = set()
  for root, _dirs, files in os.walk(os.path.join(REPO, 'tinybendygrad')):
    for f in files:
      if not f.endswith('.bend'):
        continue
      p = os.path.join(root, f)
      with open(p, encoding='utf-8', errors='replace') as fh:
        if f == 'ops.bend' or 'ops.bend' in fh.read():
          found.add(os.path.relpath(p, REPO))
  return sorted(found)


def rows_of(path: str, tries: int = 2) -> tuple[list[str], str]:
  """Every stdout line one importer prints, retried once if it printed none.

  The retry is the point: a bend stack overflow also prints no rows, and accepting the
  first empty answer would record a 0-row baseline that later reads as a delta. A file
  that legitimately prints nothing is reported as `no-main`, not as `empty`.
  """
  for attempt in range(tries):
    r = subprocess.run([BEND, path], cwd=REPO, capture_output=True, text=True, timeout=1200)
    out = [ln for ln in r.stdout.splitlines() if ln.strip() and not BANNER.match(ln)]
    if out:
      return out, 'ok' if attempt == 0 else f'ok-after-retry({attempt + 1})'
    return [], 'no-main' if 'no main' in (r.stderr + r.stdout) else f'empty(rc={r.returncode})'
  return [], 'unreachable'


def main() -> None:
  tag = sys.argv[1]
  dest = os.path.join(REPO, '.agents/slop/blobrows', tag)
  os.makedirs(dest, exist_ok=True)
  files = importers()
  print(f"blob-rows: {len(files)} files import {OPS} (including itself)")
  counts, zero = {}, []
  for rel in files:
    rows, status = rows_of(rel)
    name = rel.replace('/', '__') + '.txt'
    with open(os.path.join(dest, name), 'w', encoding='utf-8') as fh:
      fh.write('\n'.join(rows) + ('\n' if rows else ''))
    counts[rel] = len(rows)
    if not rows:
      zero.append(f"{rel} ({status})")
    print(f"  {len(rows):6d}  {rel}  {status}")
  total = sum(counts.values())
  with open(os.path.join(dest, '_counts.tsv'), 'w', encoding='utf-8') as fh:
    for rel in files:
      fh.write(f"{counts[rel]}\t{rel}\n")
    fh.write(f"TOTAL\t{total}\n")
  print(f"blob-rows: tag={tag} TOTAL_ROWS={total} FILES={len(files)}")
  print(f"blob-rows: ZERO-ROW FILES ({len(zero)}): {zero if zero else 'none'}")


if __name__ == '__main__':
  main()