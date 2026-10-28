#!/usr/bin/env python3
"""THE HAZARD AUDIT: a `symbol=` on a line that ALSO carries a `.py` citation binds to
the `.py` one in `gates/todo-cite-gate.py`, and FAILS.

  .venv/bin/python .agents/slop/bendcite2/audit.py <root>
"""
import re
import sys
from pathlib import Path

PYCITE = re.compile(r"([A-Za-z0-9_.\-/]*[A-Za-z0-9_]\.(?:py|bend))\s*:\s*(\d+)(?:\s*-\s*(\d+))?")
SYMBOL = re.compile(r"\bsymbol\s*=\s*([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)?)")
MARKER = re.compile(r"TODO\((p\d+)\)")


def main() -> int:
  root = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
  bad = 0
  for rel in sys.argv[2:]:
    p = root / rel
    for i, ln in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
      syms = SYMBOL.findall(ln)
      if not syms:
        continue
      pys = [m.group(1) for m in PYCITE.finditer(ln) if m.group(1).endswith(".py")]
      marker = bool(MARKER.search(ln))
      if pys or marker:
        bad += 1
        print(f"HAZARD {rel}:{i}  symbol={syms}  py-cites={pys}  marker={marker}")
        print(f"    {ln.strip()[:160]}")
  print(f"HAZARDS: {bad}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
