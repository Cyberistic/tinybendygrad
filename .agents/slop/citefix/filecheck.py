#!/usr/bin/env python3
"""filecheck.py -- EVERY UPSTREAM CITATION IN A HEADER, AND WHETHER IT HOLDS.

    .venv/bin/python .agents/slop/citefix/filecheck.py FILE [FILE ...]

`gates/pin-cite-gate.py`'s own `holds()` and `window_tokens()`, imported BY PATH, over the
file's own HEADER BLOCK (the citations `gates/header-census-gate.py` reads), against the
upstream corpus at the pin.

Prints one line per citation: HOLDS, FALSE, or UNCHECKABLE. UNCHECKABLE is NOT a pass: it
is a citation no instrument can hold, which is the class this whole exercise is about.
"""

from __future__ import annotations

import argparse
import importlib.util
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PIN = "5c2bf39d6c4b"


def load(name: str, path: Path):
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("files", nargs="+")
  args = ap.parse_args()
  pc = load("pincite", ROOT / "gates" / "pin-cite-gate.py")
  hc = load("hcensus", ROOT / "gates" / "header-census-gate.py")
  corpus = hc.Upstream(pc.UPSTREAM)
  cache: dict[str, list[str]] = {}

  def pin_lines(path: str) -> list[str]:
    if path not in cache:
      cache[path] = subprocess.run(
        ("git", "--no-optional-locks", "show", f"{PIN}:{path}"), cwd=ROOT,
        capture_output=True, text=True).stdout.splitlines()
    return cache[path]

  bad = 0
  for rel in args.files:
    src = (ROOT / rel).read_text(encoding="utf-8").splitlines()
    first, last, blk = hc.header_block(src)
    if not first:
      print(f"{rel}: NO HEADER BLOCK")
      continue
    tgt = hc.declared_target(blk)
    prefer = tgt.rsplit("/", 1)[0] if "/" in tgt else ""
    cites = hc.citation_claims(blk, first, rel, tgt)
    by_line: dict[int, list[dict]] = {}
    for c in cites:
      by_line.setdefault(c["at"], []).append(c)
    print(f"== {rel}  (target {tgt})")
    for at in sorted(by_line):
      group = by_line[at]
      spans = pc.line_spans(hc, src[at - 1])
      for i, c in enumerate(group):
        if c["kind"] != hc.SUBJECT_UPSTREAM:
          continue
        toks = pc.window_tokens(src[at - 1], spans, i) if i < len(spans) else []
        path, how = corpus.resolve(c["subject"], history=True, prefer_dir=prefer)
        if not path:
          print(f"  {at:5d} {c['subject']}:{c['lo']}-{c['hi']}  ABSENT FILE")
          bad += 1
          continue
        up = pin_lines(path)
        if not toks:
          print(f"  {at:5d} {c['subject']}:{c['lo']}-{c['hi']}  UNCHECKABLE (no token)")
          continue
        ok, why = pc.holds(up, c["lo"], c["hi"], toks)
        if not ok:
          bad += 1
        print(f"  {at:5d} {c['subject']}:{c['lo']}-{c['hi']}  {'HOLDS ' if ok else 'FALSE '} "
              f"{path} tokens={toks}")
  print(f"NOT-HOLDING: {bad}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
