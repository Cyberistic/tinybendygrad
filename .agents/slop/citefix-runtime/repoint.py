#!/usr/bin/env python3
"""repoint.py -- RE-POINT EVERY FALSE ROW, MECHANICALLY, AND PRINT THE PATCH.

    .venv/bin/python repoint.py ROWS.tsv PLAN.tsv OUT.tsv [--skip FILE,FILE]

For each row, the port's line is rewritten: the citation that the row names is replaced
by the SAME citation at the line the PLAN chose, plus `symbol=` when the gate's own
`resolve_symbol` says the symbol resolves there. A symbol that does NOT resolve is
DROPPED, because a `symbol=` the gate cannot resolve is a WRONG-SYMBOL row -- a red gate.

The rewrite is a CITATION SUBSTITUTION and nothing else: the prose around the citation
is untouched, so the port's sentence keeps its shape.

A row whose construct is GONE at the pin has no PLAN line and is printed as `SKIP` for a
human to write by hand.
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
  plan = {(r["rel"], r["at"], r["subject"], r["lo"]): r for r in csv.DictReader(open(argv[1], encoding="utf-8"), delimiter="\t")}
  skip = set()
  if len(argv) > 3 and argv[3].startswith("--skip="):
    skip = set(argv[3][len("--skip="):].split(","))
  tc = load("repoint_todo_cite", ROOT / "gates" / "todo-cite-gate.py")
  cor = tc.Corpus(pin="5c2bf39d6c4b")
  # THE EDITS, GROUPED BY LINE: a line with several citations is rewritten once.
  per_line: dict[tuple[str, int], list[dict]] = {}
  skipped = []
  for r in rows:
    key = (r["rel"], r["at"])
    if r["rel"] in skip:
      continue
    p = plan.get((r["rel"], r["at"], r["subject"], r["lo"]))
    if p is None or not p["new_line"] or p["new_line"] == "0":
      skipped.append(r)
      continue
    per_line.setdefault(key, []).append((r, p))
  out = []
  for (rel, at), items in sorted(per_line.items()):
    path = ROOT / rel
    lines = path.read_text(encoding="utf-8").split("\n")
    cur = lines[int(at) - 1]
    new = cur
    for r, p in items:
      lo, hi = int(r["lo"]), int(r["hi"])
      subject, nlo = r["subject"], int(p["new_line"])
      # THE CITATION OCCURRENCE: the explicit one first, then the bare one.
      pat = re.compile(rf"{re.escape(subject)}:{lo}(?:-{hi})?") if re.search(rf"{re.escape(subject)}:{lo}", new) \
        else re.compile(rf"(?<![\w./-]):{lo}(?:-{hi})?(?![\w:])")
      m = pat.search(new)
      if not m:
        continue
      # THE SYMBOL, IF THE GATE CAN RESOLVE IT AT THE NEW LINE.
      sym = p["symbol"]
      up = p["new_path"]
      ulines = cor.lines(up)
      declared = tc.decls_of(ulines)
      spans = tc.body_spans(ulines)
      if sym:
        got, decl, n = tc.resolve_symbol(ulines, spans, declared, sym, nlo)
        if not got:
          sym = ""
        else:
          inside = any(f <= nlo <= l for _d, f, l, _k in spans.get(got.split(".")[-1], []))
          if decl != nlo and not inside:
            sym = ""
      base = subject.rsplit("/", 1)[-1]
      rep = f"{base}:{nlo}" + (f" symbol={sym}" if sym else "")
      new = new[:m.start()] + rep + new[m.end():]
    if new != cur:
      out.append((rel, at, cur, new))
  w = csv.writer(open(argv[2], "w", encoding="utf-8", newline=""), delimiter="\t", lineterminator="\n")
  w.writerow(["rel", "at", "old", "new"])
  for rel, at, cur, new in out:
    w.writerow([rel, at, cur, new])
  print(f"WROTE {len(out)} line edit(s) -> {argv[2]}; {len(skipped)} row(s) SKIPPED (no plan line)")
  for r in skipped:
    print(f"  SKIP {r['rel']}:{r['at']} {r['subject']}:{r['lo']} toks={r['claim']}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main(sys.argv[1:]))
