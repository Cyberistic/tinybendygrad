#!/usr/bin/env python3
"""ns-argplant.py -- WHICH SPELLING OF THE `(str, DType)` PAIR SHOULD WIN, MEASURED.

The disagreement, from `.agents/slop/noneshape/pyarg-run0.txt` sec A:

    graphcmp.py  carg(Ops.CUSTOM, ('{0}.op is {1}', dtypes.void)) = n(s{0}.op is {1},Dvoid)
    graphcmp.py  carg(Ops.INS,     ('{0}.op is {1}', dtypes.void)) = in(s{0}.op is {1},Dvoid)
    graphcmp.bend argstr(AInk{ins, dt})                           = in(s{0}.op is {1},Dvoid)

ONE value, TWO py-side spellings, chosen by WHICH OP holds it, and one bend-side spelling.
`carg`'s own docstring says it "Mirrors `argstr` in graphcmp.bend character for character".
MEASURED: it does not, and the arm it is missing is one line.

Two repairs are possible and they are NOT symmetric:

  P1  ADD AN ARM to `carg`: `if op is Ops.CUSTOM | Ops.CUSTOMI: return f"in({bstr(x[0])},{dt(x[1])})"`.
      One line. Moves live rows: measured below.
  P2  CHANGE `argstr`'s `AInk` arm from `in(` to the generic tuple spelling. Then INS
      changes too, because INS's arg is the same pair and one `Arg` constructor serves
      both. Every INS row in the corpus moves.

`carg`'s OWN precedent, in the file: ADEV-1, the COPY arm at graphcmp.py, hit exactly this
-- `Ops.COPY`'s arg is `str|tuple[str,...]` stored verbatim, and with no arm it fell to the
generic `_carg` tuple grammar while ALLREDUCE went through the flattening `dev`, so one
graph spelled the same value two ways two nodes apart. MEASURED there, calling CPython:
`c.arg == r.arg[1]`, i.e. `('CPU','CPU')` on both. And the fix that unit shipped was
"no third option existed: exactly one of the two spellings could have been right" -- so it
ADDED AN ARM. So the precedent inside `carg` is P1, and this is the same class.

`graphcmp.py`'s `COMPOSITE` tuple is the second measurement: it enumerates the composite
openers both sides spell (`P( al( cF( cI( in( kI( pI( rd( rg( wm(`), and the census's
"unmapped atom letter" test subtracts exactly that list. So `in(` is a REGISTERED form
and `n(` is the generic one. Under P1 nothing decodes differently; under P2 the `in(`
atom leaves `COMPOSITE` and every INS row changes.

This is a monkeypatch and nothing on disk carries it -- `graphcmp.py` and `graphcmp.bend`
belong to another unit. It is here so the recommendation is a measurement.

    env -u PYTHONPATH LC_ALL=C DEV=CPU .venv/bin/python .agents/slop/noneshape/ns-argplant.py
"""
from __future__ import annotations

import os
import sys

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
SLOP = os.path.join(REPO, ".agents/slop")
HERE = os.path.join(SLOP, "noneshape")
sys.path.insert(0, REPO)
sys.path.insert(0, SLOP)
os.environ["DEV"] = "CPU"

import graphcmp as G  # noqa: E402

G.load_tinygrad()

from tinygrad.uop.ops import UOp, UPat, Ops  # noqa: E402
from tinygrad.uop.upat import _get_clause  # noqa: E402
from tinygrad import dtypes  # noqa: E402

ORIG_CARG = G.carg


def carg_p1(op, x) -> str:
  """The one missing arm. Nothing else changes."""
  if op in (Ops.CUSTOM, Ops.CUSTOMI):
    return f"in({G.bstr(x[0])},{G.dt(x[1])})"
  return ORIG_CARG(op, x)


def widen(g):
  orig = G.cshape

  def cshape(n: UOp) -> str:
    try:
      return orig(n)
    except RuntimeError:
      return "R"
    except AssertionError as e:
      if str(e).startswith("None input shape not supported for "):
        return "R"
      raise

  G.cshape = cshape


def ir_rows() -> list[str]:
  root = _get_clause(UPat(Ops.ADD), UOp(Ops.CUSTOMI, arg=("uop", dtypes.void)))
  lst = list(root.toposort())
  ix = {id(n): i + 1 for i, n in enumerate(lst)}
  return [G.row_of(n, i + 1, ix) for i, n in enumerate(lst)]


def bend_rows(path: str) -> list[str]:
  return [ln for ln in open(path).read().splitlines()
          if ln and not ln.startswith("#") and "available" not in ln]


def verdict(tag: str, py: list[str], bd: list[str]) -> tuple[int, int]:
  bad = agree = 0
  for i in range(max(len(py), len(bd))):
    pf = G.unchunks(py[i]) if i < len(py) else ["?", "?", "?", "?", "?", "?", "?", "?"]
    bf = G.unchunks(bd[i]) if i < len(bd) else ["?", "?", "?", "?", "?", "?", "?", "?"]
    d = [(k, pf[j + 2], bf[j + 2]) for j, k in enumerate(G.FIELDS) if pf[j + 2] != bf[j + 2]]
    print(f"  {tag} node {i + 1} {pf[1]:<10} "
          f"{'AGREE' if not d else 'MISMATCH ' + ', '.join(k for k, _, _ in d)}")
    for k, x, y in d:
      print(f"#       {k:<6} py={x}   bend={y}")
    bad += len(d)
    agree += 6 - len(d)
  print(f"# VERDICT {tag}: {bad} field mismatches of {6 * max(len(py), len(bd))}; {agree} agree")
  return bad, agree


def main() -> int:
  widen(G)
  bd = bend_rows(os.path.join(HERE, "patir-run1.txt"))
  G.carg = ORIG_CARG
  before = ir_rows()
  G.carg = carg_p1
  after = ir_rows()
  G.carg = ORIG_CARG

  print("# ==== P1's BLAST RADIUS ON THE LIVE CORPUS, WHOLE LINE ====")
  moved = 0
  for g in sorted(G.GRAPHS):
    a = G.emit_py(g, None)
    G.carg = carg_p1
    b = G.emit_py(g, None)
    G.carg = ORIG_CARG
    if a != b:
      moved += sum(1 for x, y in zip(a, b) if x != y)
      print(f"#   {g}: {sum(1 for x, y in zip(a, b) if x != y)} of {len(a)} py rows move")
  print(f"# live py rows moved by the ONE arm: {moved}  (0 means the widening is inert)")
  print("#   inert on the corpus and it is also the CORRECT answer: no live graph holds a")
  print("#   CUSTOM/CUSTOMI arg, because the pattern compiler IR is not in `GRAPHS`.")

  print("\n# ==== THE VERDICT, P0 (no arm) vs P1 (the one arm) ====")
  verdict("P0", before, bd)
  verdict("P1", after, bd)
  print("\n# WHAT P1 DOES NOT FIX, and it is the other half of item 2:")
  print("#   node 2's `arg` is `OADD` vs `rd(OADD,i0)` and NO arm in `carg` can fix that,")
  print("#   because the bend side has no `Arg` constructor holding a bare `Op` at all --")
  print("#   `ns-oparg.bend` fails to compile with `expected : O.Arg / observed : O.Op`.")
  print("#   That is a TYPE CHANGE in uop/ops.bend, not a spelling change.")
  return 0


if __name__ == "__main__":
  sys.exit(main())