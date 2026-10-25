#!/usr/bin/env python3
"""check.py -- FOR EVERY CITATION ON A GIVEN LINE: THE SUBJECT, THE TOKENS, AND WHETHER
THE CLAIM HOLDS AT THE PIN.

    .venv/bin/python .agents/slop/citefix9/check.py FILE [FILE...]

This is pin-cite-gate's own machinery (its parser, its token window, its `holds`), run on
ONE line at a time so the prose can be iterated without a 90-second gate run.
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
  pc = load("pincite", ROOT / "gates" / "pin-cite-gate.py")
  hc = load("hcensus", ROOT / "gates" / "header-census-gate.py")
  corpus = hc.Upstream(pc.UPSTREAM)
  pin = git("log", "-1", "--format=%H", "refs/remotes/upstream/master", "--", "tinygrad/").strip()
  cache: dict[str, list[str]] = {}

  def up_lines(path: str) -> list[str]:
    if path not in cache:
      cache[path] = git("show", f"{pin}:{path}").splitlines()
    return cache[path]

  for rel in sys.argv[1:]:
    src = (ROOT / rel).read_text().splitlines()
    first, last, blk = hc.header_block(src)
    tgt = hc.declared_target(blk)
    claims = hc.citation_claims(blk, first, rel, tgt)
    by_line: dict[int, list[dict]] = {}
    for c in claims:
      by_line.setdefault(c["at"], []).append(c)
    print("=" * 110)
    print(f"{rel}   header {first}..{last}  target={tgt!r}")
    for at in sorted(by_line):
      line = src[at - 1]
      spans = pc.line_spans(hc, line)
      print(f"  --- line {at}: {line}")
      for i, c in enumerate(by_line[at]):
        toks = pc.window_tokens(c["line"], spans, i) if i < len(spans) else []
        if not c["subject"].endswith(".py"):
          print(f"      [{i}] PORT  {c['subject']}:{c['lo']}  toks={toks}")
          continue
        path, how = corpus.resolve(c["subject"], history=True,
                                   prefer_dir=tgt.rsplit("/", 1)[0] if "/" in (tgt or "") else "")
        if not path:
          print(f"      [{i}] UNRESOLVED {c['subject']}:{c['lo']}  ({how})  toks={toks}")
          continue
        lines = up_lines(path)
        if c["lo"] > len(lines):
          print(f"      [{i}] OUT-OF-RANGE {path}:{c['lo']}  toks={toks}")
          continue
        ok, why = pc.holds(lines, c["lo"], c["hi"], toks)
        print(f"      [{i}] {'HOLDS ' if ok else 'FALSE '} {path}:{c['lo']}-{c['hi']}  "
              f"toks={toks}")
        if not ok:
          print(f"            {why}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
