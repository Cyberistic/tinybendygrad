#!/usr/bin/env python3
"""try.py -- TEST A CANDIDATE LINE: ITS CITATIONS, THEIR TOKENS, AND WHETHER THEY HOLD.

    .venv/bin/python .agents/slop/citefix9/try.py "the line text" [prefer_dir]

A one-line probe, so the prose can be iterated without a gate run. The machinery is
pin-cite-gate's own.
"""

from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def load(name: str, path: Path):
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


def git(*args: str) -> str:
  p = subprocess.run(("git", "--no-optional-locks") + args, cwd=ROOT, capture_output=True, text=True)
  return p.stdout


def main() -> int:
  line = sys.argv[1]
  prefer = sys.argv[2] if len(sys.argv) > 2 else ""
  pc = load("pincite", ROOT / "gates" / "pin-cite-gate.py")
  hc = load("hcensus", ROOT / "gates" / "header-census-gate.py")
  corpus = hc.Upstream(pc.UPSTREAM)
  pin = git("log", "-1", "--format=%H", "refs/remotes/upstream/master", "--", "tinygrad/").strip()
  claims = hc.citation_claims([line], 1, "x", "")
  spans = pc.line_spans(hc, line)
  for i, c in enumerate(claims):
    toks = pc.window_tokens(c["line"], spans, i) if i < len(spans) else []
    if not c["subject"].endswith(".py"):
      print(f"  [{i}] PORT  {c['subject']}:{c['lo']}  toks={toks}")
      continue
    path, how = corpus.resolve(c["subject"], history=True, prefer_dir=prefer)
    if not path:
      print(f"  [{i}] UNRESOLVED {c['subject']}:{c['lo']} ({how}) toks={toks}")
      continue
    lines = git("show", f"{pin}:{path}").splitlines()
    ok, why = pc.holds(lines, c["lo"], c["hi"], toks)
    print(f"  [{i}] {'HOLDS ' if ok else 'FALSE '} {path}:{c['lo']}-{c['hi']} toks={toks}")
    if not ok:
      print(f"        {why}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
