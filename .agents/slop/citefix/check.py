#!/usr/bin/env python3
"""check.py -- WOULD EACH CITATION ON THESE LINES HOLD AT THE PIN?

    .venv/bin/python .agents/slop/citefix/check.py FILE LINE [LINE ...]

`gates/pin-cite-gate.py`'s own `holds()`, `window_tokens()` and `line_spans()`, imported BY
PATH, and the upstream corpus read at the pin. So the answer is the gate's answer, computed
without running the whole gate.

For each citation: the tokens the gate would attribute to it, and whether the cited line
holds the claim. A citation with no token is UNCHECKABLE -- which is not a pass, and is
printed as such.
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
  ap.add_argument("rel")
  ap.add_argument("lines", nargs="+", type=int)
  args = ap.parse_args()
  pc = load("pincite", ROOT / "gates" / "pin-cite-gate.py")
  hc = load("hcensus", ROOT / "gates" / "header-census-gate.py")
  src = (ROOT / args.rel).read_text(encoding="utf-8").splitlines()
  corpus = hc.Upstream(pc.UPSTREAM)
  cache: dict[str, list[str]] = {}

  def pin_lines(path: str) -> list[str]:
    if path not in cache:
      cache[path] = subprocess.run(
        ("git", "--no-optional-locks", "show", f"{PIN}:{path}"), cwd=ROOT,
        capture_output=True, text=True).stdout.splitlines()
    return cache[path]

  # THE HEADER'S DECLARED TARGET, which is the ambient the gate uses.
  _f, _l, blk = hc.header_block(src)
  tgt = hc.declared_target(blk)
  prefer = tgt.rsplit("/", 1)[0] if "/" in tgt else ""

  for at in args.lines:
    line = src[at - 1]
    spans = pc.line_spans(hc, line)
    print(f"{args.rel}:{at}")
    print(f"  {line}")
    for i, sp in enumerate(spans):
      subject = hc.CITE_RE.match(line[sp[0]:]).group(1) if hc.CITE_RE.match(line[sp[0]:]) else None
      if subject is None:
        # A BARE citation: the subject is the declared target.
        subject = tgt
      path, how = corpus.resolve(subject, history=True, prefer_dir=prefer)
      toks = pc.window_tokens(line, spans, i)
      if not toks:
        print(f"  citation {i} {line[sp[0]:sp[1]]!r} -> UNCHECKABLE (no token)")
        continue
      if not path:
        print(f"  citation {i} {line[sp[0]:sp[1]]!r} -> ABSENT FILE {subject}")
        continue
      lo = int(hc.CITE_RE.match(line[sp[0]:]).group(2)) if hc.CITE_RE.match(line[sp[0]:]) else 0
      hi = int(hc.CITE_RE.match(line[sp[0]:]).group(3) or lo) if hc.CITE_RE.match(line[sp[0]:]) else 0
      if not lo:
        # a bare `:N`
        import re
        m = re.search(r":(\d+)(?:-(\d+))?", line[sp[0]:sp[1]])
        lo = int(m.group(1))
        hi = int(m.group(2) or lo)
      up = pin_lines(path)
      ok, why = pc.holds(up, lo, hi, toks)
      print(f"  citation {i} {line[sp[0]:sp[1]]!r} -> {path}:{lo}-{hi} "
            f"{'HOLDS' if ok else 'FALSE'} tokens={toks} -- {why}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
