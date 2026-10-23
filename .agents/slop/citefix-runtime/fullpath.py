#!/usr/bin/env python3
"""fullpath.py -- RE-POINT EVERY CITATION ON A TOUCHED LINE AT ITS FULL UPSTREAM PATH.

    .venv/bin/python fullpath.py OUT.tsv

The pin-cite census resolves a BARE BASENAME with its OWN resolver, and that resolver
REFUSES an ambiguous basename: `helpers.py` is seven upstream files, so a citation written
`helpers.py:161` names NO file at all and the census cannot judge it -- it lands in the
`at_no_revision` class, which is FALSE. The todo-cite gate's resolver CAN disambiguate it
(the port file's own declared target directory is the ambient), so the two instruments
disagree about the same citation.

THE FIX IS THE FULL PATH: `tinygrad/helpers.py:161` names ONE file in BOTH resolvers.
This script rewrites every citation on every line the unit touched to that form, and it
refuses a subject it cannot resolve -- so a citation is never silently dropped.

The port's own `.bend` citations are NOT touched: they are not upstream citations.
"""

from __future__ import annotations

import csv
import importlib.util
import re
import sys
import warnings
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def load(name: str, path: Path):
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    spec.loader.exec_module(mod)
  return mod


def main(argv: list[str]) -> int:
  tc = load("fullpath_todo_cite", ROOT / "gates" / "todo-cite-gate.py")
  hc = load("fullpath_census", ROOT / "gates" / "header-census-gate.py")
  cor = tc.Corpus(pin="5c2bf39d6c4b")
  BACKTICK = re.compile(r"`[^`]*`")
  # THE LINES THE UNIT TOUCHED: every patch table this unit wrote.
  lines_by_rel: dict[str, set[int]] = {}
  for t in sorted((ROOT / ".agents" / "slop" / "citefix-runtime").glob("patch-*.tsv")):
    for r in csv.DictReader(open(t, encoding="utf-8"), delimiter="\t"):
      lines_by_rel.setdefault(r["rel"], set()).add(int(r["at"]))
  out = []
  argv = sys.argv[1:]
  for rel, ats in sorted(lines_by_rel.items()):
    p = ROOT / rel
    src = p.read_text(encoding="utf-8").split("\n")
    blk = hc.header_block(src)
    tgt = hc.declared_target(blk[2]) if blk[0] else ""
    rtgt = tgt[len("tinygrad/"):] if tgt.startswith("tinygrad/") else tgt
    prefer = rtgt.rsplit("/", 1)[0] if "/" in rtgt else ""
    for at in sorted(ats):
      line = src[at - 1]
      new = line
      # THE EXPLICIT CITATIONS: `subject.py:N`.
      def fix_explicit(m):
        subject = m.group(1)
        if not subject.endswith(".py"):
          return m.group(0)
        path, _how = cor.resolve(subject, prefer_dir=prefer)
        if not path:
          return m.group(0)
        full = "tinygrad/" + path
        return f"{full}:{m.group(2)}" + (f"-{m.group(3)}" if m.group(3) else "")
      new = re.sub(r"([A-Za-z0-9_.\-/]*\.py):(\d+)(?:-(\d+))?", fix_explicit, new)
      # THE BARE CITATIONS: `:N` -- the port's own declared target. A `:N` INSIDE A
      # BACKTICK SPAN is NOT a citation: `dims[:3]` is a slice, and rewriting it would
      # change the code's meaning, not its comment's.
      def fix_bare(m):
        quoted = any(sp.start() <= m.start() < sp.end() for sp in BACKTICK.finditer(new))
        if quoted:
          return m.group(0)
        # A SLICE IS NOT A CITATION: `dims[:3]` is a slice, and the port writes it that way.
        if m.start() and new[m.start() - 1] == "[":
          return m.group(0)
        path, _how = cor.resolve(rtgt, prefer_dir=prefer) if rtgt else ("", "")
        if not path:
          return m.group(0)
        full = "tinygrad/" + path
        return f"{full}:{m.group(1)}" + (f"-{m.group(2)}" if m.group(2) else "")
      new = re.sub(r"(?<![\w./\-]):(\d+)(?:-(\d+))?(?![\w:])", fix_bare, new)
      if new != line:
        out.append((rel, at, line, new))
  w = csv.writer(open(argv[0], "w", encoding="utf-8", newline=""), delimiter="\t", lineterminator="\n")
  w.writerow(["rel", "at", "old", "new"])
  for rel, at, old, new in out:
    w.writerow([rel, at, old, new])
  print(f"WROTE {len(out)} line edit(s) -> {argv[0]}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main(sys.argv[1:]))
