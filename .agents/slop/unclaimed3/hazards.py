"""A THROW-AWAY CHECKER for the two hazards the previous slice bought with a
measured fault:

  1. A PORT `symbol=` ON A LINE THAT ALSO CARRIES A `.py` CITATION binds to the
     `.py` one in `gates/todo-cite-gate.py` and goes WRONG-SYMBOL.
  2. TWO `.bend` CITATIONS ON ONE LINE make EVERY `symbol=` on that line a
     CANDIDATE for EVERY citation on it, so the wrong one can be chosen.

It prints every offending line in the files it is given.
"""
import re, sys
from pathlib import Path

BASE = Path(__file__).resolve().parents[3]
CITE = re.compile(r"([A-Za-z0-9_./-]*[A-Za-z0-9_]\.bend)\s*:\s*(\d+)(?:\s*-\s*(\d+))?")
PYCITE = re.compile(r"([A-Za-z0-9_./-]*[A-Za-z0-9_]\.py)\s*:\s*(\d+)(?:\s*-\s*(\d+))?")
SYMBOL = re.compile(r"\bsymbol\s*=\s*([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)?)")

bad = 0
for rel in sys.argv[1:]:
  p = BASE / rel
  for i, ln in enumerate(p.read_text(encoding="utf-8").split("\n"), 1):
    syms = SYMBOL.findall(ln)
    if not syms:
      continue
    # `gates/todo-cite-gate.py`'s SECOND POPULATION reads a COMMENT line that carries
    # the word `symbol` and binds every `symbol=` on it to the `.py` citation slot it
    # follows. A `D.refuse("...")` line is NOT a comment, so it is exempt.
    if not ln.lstrip().startswith("#"):
      continue
    py = PYCITE.findall(ln)
    bends = CITE.findall(ln)
    if py and bends:
      print(f"HAZARD-1 {rel}:{i}  a port symbol= shares a COMMENT line with a .py citation")
      print(f"    {ln.strip()[:160]}")
      bad += 1
    elif len(bends) > 1:
      print(f"HAZARD-2 {rel}:{i}  {len(bends)} .bend citations on one line and {len(syms)} symbol= field(s)")
      print(f"    {ln.strip()[:160]}")
      bad += 1
print("HAZARDS:", bad)
