#!/usr/bin/env python3
"""geom.py -- WHICH BACKTICKED NAME IS A TOKEN OF WHICH CITATION, ON ONE LINE.

    .venv/bin/python .agents/slop/citefix/geom.py tinybendygrad/mixin/movement.bend 20

`gates/pin-cite-gate.py`'s `window_tokens()`, imported BY PATH, so the GEOMETRY IS THE
GATE's GEOMETRY and not a re-derivation of it.

THE RULE, AND IT IS THE WHOLE TRICK. A backticked name is a claim token of a citation
only if it is within `_NEAREST` (40) CHARACTERS of every OTHER citation on the line. So on
a line with two citations eighty characters apart, the name next to the first citation is
a token of the SECOND one, and the name next to the second is a token of the FIRST.

Prints, per citation: the token list, the claim, and the verdict the pin-cite gate would
give it.
"""

from __future__ import annotations

import argparse
import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def load(name: str, path: Path):
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("rel")
  ap.add_argument("at", type=int)
  args = ap.parse_args()
  pc = load("pincite", ROOT / "gates" / "pin-cite-gate.py")
  hc = load("hcensus", ROOT / "gates" / "header-census-gate.py")
  lines = (ROOT / args.rel).read_text(encoding="utf-8").splitlines()
  line = lines[args.at - 1]
  spans = pc.line_spans(hc, line)
  print(f"{args.rel}:{args.at}")
  print(f"  {line}")
  print("  spans:", spans)
  for i, sp in enumerate(spans):
    toks = pc.window_tokens(line, spans, i)
    print(f"  citation {i}: span={sp} text={line[sp[0]:sp[1]]!r} tokens={toks}")
  # WHERE EVERY BACKTICK IS, so a reader can see the geometry.
  for m in pc.BACKTICK.finditer(line):
    print(f"  backtick @{m.start()}-{m.end()}: {m.group(1)!r}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
