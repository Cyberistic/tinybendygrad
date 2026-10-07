#!/usr/bin/env python3
"""norm_check.py -- prove `jslane2/gen_f32_seam.py`'s `norm` round-trips, or does not.

    python3 checks/norm_check.py

`gen_f32_seam.py` itself no longer reaches `bend`: `Dt.bf16` and `Dt.fp16` became
SEAMS in `dtype.bend` (a file another unit owns and is editing), so its `SRC`
template's `v : F32 <- D.Dt.bf16(...)` is a type error. VERIFIED PRE-EXISTING:
the committed copy fails with the identical message and the identical line, so
this is `dtype.bend` moving under the gate and not this unit's edits. Reported,
not worked around by editing their file.

So the normaliser is checked here, on its own, against the EXACT pair the defect
names -- and a `norm` that returns a constant would also "pass", so the negative
case is part of the gate, not an afterthought.

  1. `norm("1.0996094") == norm("1.099609375")`   one f32, two spellings
  2. `norm("1.0996094") != norm("1.0996093")`     the neighbouring f32 still differs
  3. `norm("<absent>") == "<absent>"`             a non-float passes through
  4. `norm("nan") == norm("-nan")`                NaN matches NaN
"""
from __future__ import annotations

import importlib.util
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent


def refuse(*why: str) -> None:
  """exit 3 = REFUSED, and NOT a verdict.  `checks/abi_gate.py` rule, in this file's idiom.

  Placed BEFORE `load()`, because the stale depth made `load()` raise
  `FileNotFoundError` FIRST, and an assertion DOWNSTREAM of what it asserts cannot turn an
  exception into a refusal."""
  print("== REFUSED, NOT A VERDICT: " + "; ".join(why), file=sys.stderr)
  sys.exit(3)


# `parents[0]`, NOT `HERE.parent`.  `3f0e70ff1` MOVED this file from `.agents/slop/jslane2/` to
# `checks/`, ONE level shallower, and carried the constant across: `HERE.parent` became the
# REPO ROOT, so `JSL2` looked for `<root>/jslane2/gen_f32_seam.py` while the file sat at
# `.agents/slop/jslane2/gen_f32_seam.py`, PRESENT AND IMPORTABLE.  MEASURED, and this is the
# FIFTH spelling of this class -- the instrument's rule finds an instance by a `parents[N]`
# regex, and this one spells the same depth as `HERE.parent / "jslane2"`, so it was invisible.
# The depth is PROVED by `refuse()` below, not assumed.
REPO = HERE.parents[0]
if not (REPO / "pyproject.toml").is_file() or not (REPO / "tinybendygrad").is_dir():
  refuse(f"REPO does not hold the tree: {REPO} is not the repo root "
         f"(is `parents[N]` stale after a move?)")
JSL2 = REPO / ".agents" / "slop" / "jslane2" / "gen_f32_seam.py"
if not JSL2.is_file():
  refuse(f"input absent: {JSL2}  (the normaliser under test; recoverable from git at "
         "371cc64c9^:.agents/slop/jslane2/gen_f32_seam.py.  This gate cannot produce a "
         "denominator without it.)")

# What the OLD `norm` was. This is the PLANT: a re-spelling of the defect, run
# against the same gate, because a fix to a normaliser that nothing can fail is a
# fix to nothing.
OLD = "repr(float(s)) with no round trip"


def load(name: str, path: pathlib.Path):
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  sys.modules[name] = mod
  spec.loader.exec_module(mod)
  return mod


def cases(norm) -> list[tuple[str, bool]]:
  return [
    (f"one f32, two spellings agree        (the defect's pair)",
     norm("1.0996094") == norm("1.099609375")),
    (f"the neighbouring f32 still differs (a constant would pass)",
     norm("1.0996094") != norm("1.0996093")),
    ("a non-float passes through unchanged", norm("<absent>") == "<absent>"),
    ("NaN matches NaN", norm("nan") == norm("-nan")),
    ("an integral f32 is not a different value", norm("448") == norm("448.0")),
  ]


def main() -> None:
  g = load("jfp_gen_f32_seam", JSL2)
  rows = cases(g.norm)

  def old(s: str) -> str:
    try:
      return repr(float(s))
    except ValueError:
      return s

  plant = cases(old)

  # `relative_to(REPO)`, not `relative_to(HERE.parents[1])`: `parents[1]` is the repo's PARENT,
  # so it rendered the subject as `2026-09-30-tinybendygrad/jslane2/gen_f32_seam.py` -- the same
  # off-by-one, one line down, and it did not raise because `parents[1]` still encloses the path.
  print(f"gate under test: {JSL2.relative_to(REPO)}  norm -> {g.norm.__module__}")
  print(f"                  CANON.canon(s, \"f32\"), not {OLD}\n")
  bad = 0
  for (label, got), (_, planted) in zip(rows, plant):
    bad += not got
    print(f"  {'ok  ' if got else 'FAIL'}  {label:<52} the old norm: "
          f"{'passes' if planted else 'FAILS'}")
  if not all(got for _, got in rows):
    bad += 1
  print(f"\nFIXED {sum(1 for _, g in rows if g)}/{len(rows)} assertions hold"
        f"   PLANT ({OLD}) {sum(1 for _, p in plant if p)}/{len(plant)}")
  if not any(not p for _, p in plant):
    print("*** the plant passes every assertion: this gate cannot fail ***")
    bad += 1
  sys.exit(1 if bad else 0)


# THE VERDICT SURFACE, DECLARED. `gates/gate-surface.py` reads these by AST -- never by import,
# because import RUNS a gate. At rest the normaliser check runs and answers `0`.
VERDICTS = {0: "PASS", 1: "FAIL", 3: "REFUSED"}
PLANTS = {0: []}


if __name__ == "__main__":
  main()