#!/usr/bin/env python3
"""decl.py -- WHERE A `.bend` CONSTRUCT IS DECLARED, RIGHT NOW.

    .venv/bin/python .agents/slop/unv3/decl.py <port-file-relative-to-tinybendygrad> <name>

THE PORT'S OWN `.bend` DECLARATIONS. THE RULE IS THE GATE'S OWN, `gates/bendcite-gate.py`'s
`BEND_DECL`: `def X`, `def Owner.member`, `type X is Data:`, `law X:` at column 0, plus
the ADT VARIANTS. THE RULE IS COPIED HERE BECAUSE THE GATE MODULE DOES NOT IMPORT
STANDALONE (it reads a census module by path at RUN time), and a second copy of a
carve-out is a contract with no generator -- SO THE GATE'S OWN TEXT IS THE SOURCE OF
TRUTH AND THIS FILE SAYS WHICH LINE IT COPIED.
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
#: `gates/bendcite-gate.py`'s `BEND_DECL`, verbatim.
BEND_DECL = re.compile(r"^(?:def|type|law)\s+([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)")
#: `gates/bendcite-gate.py`'s `BEND_VARIANT`, verbatim.
BEND_VARIANT = re.compile(r"^\s+([A-Z][A-Za-z0-9_]*)\{")


def decls(path: pathlib.Path) -> list[tuple[str, int]]:
  out: list[tuple[str, int]] = []
  for i, raw in enumerate(path.read_text().splitlines(), 1):
    m = BEND_DECL.match(raw)
    if m:
      out.append((m.group(1), i))
      continue
    m = BEND_VARIANT.match(raw)
    if m:
      out.append((m.group(1), i))
  return out


def main() -> int:
  rel, name = sys.argv[1], sys.argv[2]
  p = ROOT / "tinybendygrad" / rel
  hits = [(nm, line) for nm, line in decls(p) if nm == name]
  if not hits:
    print(f"{rel}: NO DECLARATION OF `{name}`")
    return 1
  for nm, line in hits:
    print(f"{rel}: {nm} declared at :{line}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
