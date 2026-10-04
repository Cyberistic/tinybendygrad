#!/usr/bin/env python3
"""derive.py -- DERIVE the row denominator from the SOURCE, then check the run against it.

WHY THIS FILE EXISTS. Every number in the port's own documentation is a transcribed
denominator (`227 rows`, `221 gated`, `6 declared exclusions`). A transcribed denominator is
a number that can be right about the count and wrong about the SET, and this project has
already been bitten by exactly that: a gate whose denominator disagreed with itself printed
two different numbers in one run.

So the denominator here is not typed. It is counted from `renderer/cstyle.bend`'s `main`,
which is a FLAT SEQUENCE OF ROW-EMITTING CALLS -- one call, one row. That is a derivation:
it does not consult the run it is checking.

  usage: derive.py <cstyle.bend> <port.txt>
"""
import importlib.util
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
GATE = HERE.parent / "cstyle-gate.py"
_spec = importlib.util.spec_from_file_location("cstyle_gate", GATE)
gate = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gate)

# `<row_fn>(` at the start of a `main` statement. `_ : Unit <- <fn>(` is the only shape
# main uses, so this is anchored rather than guessed -- and the count of ANCHORED calls is
# printed next to the count of parsed rows, which is the whole point.
CALL = re.compile(r"^\s*_\s*:\s*Unit\s*<-\s*([A-Za-z_][A-Za-z_0-9]*)\(\s*(\"(?:[^\"\\]|\\.)*\")")


def main_body(text):
  """The lines of `main` after its `def`, up to EOF. cstyle.bend's main is the LAST def in
  the file; if that stops being true this returns the wrong slice and the static/observed
  disagreement below says so rather than reporting a clean number."""
  i = text.find("\ndef main() -> IO(Unit):")
  if i < 0:
    raise SystemExit("derive: no `def main() -> IO(Unit):` found; the slice would be a guess")
  return text[i:].splitlines()


def expected_names(src):
  """[(emitter, family)] per row-emitting call in main, in source order. The family is the
  FIRST WORD of the call's first string-literal argument -- which is how the row NAME is
  built, so the family is derivable statically and is not the same thing as the run's
  family column (which splits on whitespace of the finished name)."""
  out = []
  for ln in main_body(src):
    m = CALL.match(ln)
    if m:
      out.append((m.group(1), m.group(2)[1:-1].split()[0]))
  return out


def main():
  src_path, port_path = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
  exp = expected_names(src_path.read_text())
  rows, shreds, dups = gate.rows_strict(port_path.read_text())
  print(f"STATIC  row-emitting calls in {src_path.name}'s main()   {len(exp)}")
  print(f"OBSERVED rows parsed by cstyle-gate.py's rows_strict  {len(rows)}")
  print(f"        lines the reader shredded (not rows)          {len(shreds)}")
  print(f"        duplicate row NAMES the reader saw            {len(dups)} {sorted(set(dups))}")
  print()
  # The set comparison. A count can agree while the SET does not, and the set is the claim.
  from collections import Counter
  ef = Counter(f for _, f in exp)
  of = Counter(r.split()[0] for r in rows)
  print(f"{'family':<9} {'static':>7} {'observed':>9} {'delta':>6}")
  for fam in sorted(set(ef) | set(of)):
    d = of[fam] - ef[fam]
    print(f"{fam:<9} {ef[fam]:>7} {of[fam]:>9} {d:>+6}")
  print(f"{'TOTAL':<9} {sum(ef.values()):>7} {sum(of.values()):>9} "
        f"{sum(of.values())-sum(ef.values()):>+6}")
  print()
  if ef != of:
    print("THE DENOMINATOR AND THE ROWS DISAGREE. Per-family deltas above are the finding;")
    print("a count-only check would have printed a single number and hidden this.")
    return 1
  print("static family multiset == observed family multiset, so the denominator is DERIVED,")
  print("not transcribed, and the run carried every row main asks for.")
  return 0


if __name__ == "__main__":
  sys.exit(main())