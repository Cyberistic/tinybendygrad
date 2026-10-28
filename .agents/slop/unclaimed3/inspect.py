"""A THROW-AWAY INSPECTOR for the UNCLAIMED slice. It loads the gate BY PATH and
answers three questions: WHAT is at a cited line, WHAT does the file DECLARE, and
WHICH claim token could a `symbol=` name."""
import sys, importlib.util
from pathlib import Path

BASE = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("bc", BASE / "gates" / "bendcite-gate.py")
bc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bc)
C = bc.Corpus(BASE)
J = bc.Judge(C)


def constructs(rel):
  return C.constructs[rel]


def at(rel, line):
  return C.construct_at(rel, line)


def declares(rel, name):
  return C.declares(rel, name)


if __name__ == "__main__":
  rel = sys.argv[1]
  lo = int(sys.argv[2]) if len(sys.argv) > 2 else 0
  hi = int(sys.argv[3]) if len(sys.argv) > 3 else 0
  print("== CONSTRUCTS in", rel)
  for n, d, s, e in constructs(rel):
    print(f"  {n:40s} decl={d:6d} span={s}-{e}")
  if lo:
    print(f"== AT {rel}:{lo}" + (f"-{hi}" if hi else ""))
    body = C.bodies[rel]
    for i in range(max(1, lo - 3), min(len(body), hi + 3) + 1):
      print(f"  {i:6d}| {body[i-1]}")
