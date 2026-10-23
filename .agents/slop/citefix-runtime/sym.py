#!/usr/bin/env python3
"""sym.py -- WHERE IS AN UPSTREAM CONSTRUCT AT THE PIN?

    .venv/bin/python sym.py SYM SUBJECT NAME [NAME...]      where is NAME declared?
    .venv/bin/python sym.py AT SUBJECT LO [HI]               what is at those lines?
    .venv/bin/python sym.py FIND SUBJECT TOKEN                which lines hold TOKEN?

`SUBJECT` is the citation's own subject, exactly as the port writes it (`ops_amd.py`,
`tinygrad/runtime/ops_amd.py`). The subject is resolved by the GATE'S OWN resolver, so a
line this script prints is a line the gate can judge.

The DECLARATION lines and the BODY SPANS come from the gate's own `decls_of()` and
`body_spans()`, loaded BY PATH, so this script and the gate cannot disagree about what a
symbol is or where it is declared.

A symbol that upstream does not declare is reported as ABSENT, with the NEAREST names, so
a re-point never lands on a plausible-looking line.
"""

from __future__ import annotations

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


def corpus():
  gate = load("citefix_todo_cite", ROOT / "gates" / "todo-cite-gate.py")
  return gate, gate.Corpus(pin="5c2bf39d6c4b")


def resolve(cor, subject: str, prefer: str) -> tuple[str, str]:
  path, how = cor.resolve(subject, prefer_dir=prefer)
  return path, how


def main(argv: list[str]) -> int:
  if len(argv) < 3:
    print(__doc__)
    return 2
  mode, subject = argv[0], argv[1]
  args = argv[2:]
  prefer = ""
  if "--prefer-dir" in args:
    i = args.index("--prefer-dir")
    prefer = args[i + 1]
    del args[i:i + 2]
  gate, cor = corpus()
  path, how = resolve(cor, subject, prefer)
  print(f"SUBJECT {subject} -> {path}  ({how})")
  if not path:
    return 1
  lines = cor.lines(path)
  declared = gate.decls_of(lines)
  spans = gate.body_spans(lines)
  print(f"LINES {len(lines)}")
  if mode == "AT":
    lo = int(args[0])
    hi = int(args[1]) if len(args) > 1 else lo
    for i in range(lo, min(hi, len(lines)) + 1):
      print(f"  :{i}\t{lines[i - 1]}")
    return 0
  if mode == "FIND":
    tok = args[0]
    pat = re.compile(rf"\b{re.escape(tok)}\b")
    for i, l in enumerate(lines, 1):
      if pat.search(l):
        print(f"  :{i}\t{l}")
    return 0
  if mode == "SYM":
    for name in args:
      bare = name.split(".")[-1]
      hits = [(n, d) for n, d in declared.items() if n == bare or n == name]
      if not hits:
        hits = [(n, d) for n, d in declared.items() if bare in n]
      if not hits:
        print(f"  {name}: ABSENT -- upstream declares no such name")
        near = sorted(n for n in declared if len(bare) >= 4 and bare[:4] in n)[:14]
        if near:
          print(f"      near: {', '.join(near)}")
        continue
      for n, d in hits:
        print(f"  {name}: declared at :{d}  (name={n})")
        for decl, first, last, kind in spans.get(n, []):
          print(f"      span {kind} :{first}-{last} (decl :{decl})")
    return 0
  if mode == "FIX":
    # WHAT A RE-POINT NEEDS: the upstream lines at the cited range, the construct that
    # ENCLOSES them, and where each claim token is declared.
    lo = int(args[0])
    hi = int(args[1]) if len(args) > 1 else lo
    toks = args[2:]
    print("  -- the cited lines at the pin --")
    for i in range(lo, min(hi, len(lines)) + 1):
      print(f"    :{i}\t{lines[i - 1]}")
    print("  -- the construct that encloses them --")
    for name, d in sorted(declared.items(), key=lambda kv: kv[1]):
      if lo <= d <= max(hi, lo):
        print(f"    {name} declared at :{d}")
    enclosing = [n for n, d in declared.items() if d <= lo]
    if enclosing:
      best = max(enclosing, key=lambda n: declared[n])
      print(f"    enclosing: {best} (declared at :{declared[best]})")
    print("  -- where each claim token is declared --")
    for t in toks:
      bare = t.split(".")[-1]
      hits = sorted((d, n) for n, d in declared.items() if n == bare or bare in n)
      if hits:
        print(f"    {t}: " + ", ".join(f"{n}@{d}" for d, n in hits[:8]))
      else:
        near = sorted(n for n in declared if len(bare) >= 4 and bare[:4] in n)[:8]
        print(f"    {t}: ABSENT" + (f"  near: {', '.join(near)}" if near else ""))
    return 0
  print(f"UNKNOWN MODE {mode}")
  return 2


if __name__ == "__main__":
  raise SystemExit(main(sys.argv[1:]))
