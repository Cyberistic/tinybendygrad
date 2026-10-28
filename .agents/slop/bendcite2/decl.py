#!/usr/bin/env python3
"""Find where a `.bend` symbol is DECLARED, using the gate's OWN rule (loaded BY PATH).

  .venv/bin/python .agents/slop/bendcite2/decl.py <file.bend> <name> [<name> ...]
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "gates"))
import importlib.util

spec = importlib.util.spec_from_file_location("bendcite", ROOT / "gates" / "bendcite-gate.py")
bc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bc)


def decls(path: Path, name: str) -> list[tuple[int, int, int]]:
  body = path.read_text(encoding="utf-8").splitlines()
  return bc.bend_constructs(body)


def main() -> int:
  path = Path(sys.argv[1])
  body = path.read_text(encoding="utf-8").splitlines()
  cs = bc.bend_constructs(body)
  for name in sys.argv[2:]:
    hits = [(d, s, e) for (n, d, s, e) in cs if n == name]
    if not hits:
      last = name.rsplit(".", 1)[-1]
      hits = [(d, s, e) for (n, d, s, e) in cs if n == last]
    if hits:
      for d, s, e in hits:
        print(f"{path}:{d} {name}  (span {s}-{e})  :: {body[d-1].strip()[:100]}")
    else:
      print(f"{path}: NOT FOUND {name}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
