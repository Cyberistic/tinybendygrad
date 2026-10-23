#!/usr/bin/env python3
"""find.py -- WHERE DID THE CLAIMED CONSTRUCT MOVE TO?

    .venv/bin/python find.py ROWS.tsv [REL_FILTER]

For every false row in `ROWS.tsv`, print the upstream file's lines that mention the row's
CLAIM TOKENS at the pin, with the construct that encloses each. The claim tokens come from
the row, so the search is DISCOVERED, not typed.

The upstream file is the row's own subject, resolved by the GATE'S OWN resolver, and the
enclosing construct comes from the gate's own `enclosing()`/`declared_names()`, so a line
this script prints is a line the gate can judge.
"""

from __future__ import annotations

import csv
import importlib.util
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def load(name: str, path: Path):
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


def main(argv: list[str]) -> int:
  rows = list(csv.DictReader(open(argv[0], encoding="utf-8"), delimiter="\t"))
  only = argv[1] if len(argv) > 1 else ""
  gate = load("citefix_todo_cite", ROOT / "gates" / "todo-cite-gate.py")
  cor = gate.Corpus(pin="5c2bf39d6c4b")
  census = load("citefix_census", ROOT / "gates" / "header-census-gate.py")
  for r in rows:
    if only and only not in r["rel"]:
      continue
    subject = r["subject"]
    toks = [t for t in r["claim"].split(",") if t]
    # THE AMBIENT: the port file's own declared target directory.
    tgt = ""
    pf = ROOT / r["rel"]
    if pf.exists():
      blk = census.header_block(pf.read_text(errors="replace").splitlines())
      if blk[0]:
        t = census.declared_target(blk[2])
        tgt = t[len("tinygrad/"):] if t.startswith("tinygrad/") else t
    prefer = tgt.rsplit("/", 1)[0] if "/" in tgt else ""
    path, how = cor.resolve(subject, prefer_dir=prefer)
    print(f"== {r['rel']}:{r['at']}  {subject}:{r['lo']}{'-'+r['hi'] if r['hi']!=r['lo'] else ''} "
          f"[{r['class']}] toks={','.join(toks)}")
    if not path:
      print(f"   NO UPSTREAM FILE  ({how})")
      continue
    lines = cor.lines(path)
    print(f"   {path} ({len(lines)} lines) via {how}")
    seen = set()
    for t in toks:
      pat = re.compile(rf"\b{re.escape(t)}\b")
      for i, l in enumerate(lines, 1):
        if pat.search(l):
          if (t, i) in seen:
            continue
          seen.add((t, i))
          enc = gate.enclosing(lines, i)
          print(f"   {t:22s} :{i:<5d} {l.strip()[:90]}")
          if enc:
            print(f"   {'':22s}        enclosing: {enc[0]} (declared :{enc[1]})")
          if len(seen) > 60:
            break
    print()
  return 0


if __name__ == "__main__":
  raise SystemExit(main(sys.argv[1:]))
