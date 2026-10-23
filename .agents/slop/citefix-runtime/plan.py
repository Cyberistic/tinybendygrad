#!/usr/bin/env python3
"""plan.py -- A MECHANICAL RE-POINT FOR EVERY FALSE ROW, FOR REVIEW.

    .venv/bin/python plan.py ROWS.tsv > PLAN.tsv

For each false row, the row's cited line is MOVED to the upstream line that holds the
claim, and the row's citation is rewritten to carry `symbol=`. The upstream file is the
row's own subject, resolved by the GATE'S OWN resolver, and the declared names come from
the gate's own `decls_of()`, so a line this script picks is a line the gate can judge.

THE PLAN IS A PLAN: it is printed for a human to read, not applied. A row whose construct
is GONE at the pin is printed with `GONE` and a human decides what to write.
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
  rows = list(csv.DictReader(open(argv[0], encoding="utf-8"), delimiter="\t"))
  tc = load("plan_todo_cite", ROOT / "gates" / "todo-cite-gate.py")
  hc = load("plan_census", ROOT / "gates" / "header-census-gate.py")
  cor = tc.Corpus(pin="5c2bf39d6c4b")
  out = []
  for r in rows:
    toks = [t for t in r["claim"].split(",") if t]
    pf = ROOT / r["rel"]
    blk = hc.header_block(pf.read_text(errors="replace").splitlines())
    tgt = hc.declared_target(blk[2]) if blk[0] else ""
    rtgt = tgt[len("tinygrad/"):] if tgt.startswith("tinygrad/") else tgt
    prefer = rtgt.rsplit("/", 1)[0] if "/" in rtgt else ""
    path, how = cor.resolve(r["subject"], prefer_dir=prefer)
    if not path:
      out.append((r, "NOFILE", "", "", how))
      continue
    lines = cor.lines(path)
    declared = tc.decls_of(lines)
    old = int(r["lo"])
    # THE CANDIDATE LINES: the lines that NAME one of the claim tokens.
    cand = []
    for i, l in enumerate(lines, 1):
      for t in toks:
        if re.search(rf"\b{re.escape(t)}\b", l):
          cand.append((abs(i - old), i, t))
          break
    cand.sort()
    # THE DECLARED NAME AT THE BEST CANDIDATE, if any.
    best = cand[0] if cand else None
    sym = ""
    if best is not None:
      i = best[1]
      names = sorted(n for n, d in declared.items() if d == i)
      if names:
        # A CLAIM TOKEN that is itself a declared name wins.
        sym = next((n for n in names if n in toks), names[0])
      else:
        # else the CONSTRUCT THAT ENCLOSES the line: the gate's own `body_spans`.
        spans = tc.body_spans(lines)
        owners = []
        for nm, ss in spans.items():
          for decl, first, last, kind in ss:
            if first <= i <= last:
              owners.append((first, nm))
        if owners:
          sym = sorted(owners)[-1][1]
    out.append((r, path, (best[1] if best else 0), sym, how))
  w = csv.writer(sys.stdout, delimiter="\t", lineterminator="\n")
  w.writerow(["rel", "at", "subject", "lo", "hi", "new_path", "new_line", "symbol", "how", "line"])
  for r, path, nl, sym, how in out:
    w.writerow([r["rel"], r["at"], r["subject"], r["lo"], r["hi"], path, nl, sym, how, r["line"]])
  return 0


if __name__ == "__main__":
  raise SystemExit(main(sys.argv[1:]))
