#!/usr/bin/env python3
"""al-verdict.py -- THE TWO-SIDED VERDICT ON THE PATTERN-COMPILER IR, WITH THE
DENOMINATOR PRINTED, AND WITH NO MONKEYPATCH: whatever `carg` says is what is ON DISK.

`noneshape/ns-argplant.py` printed P0 (no arm) against P1 (a monkeypatched arm). Now the
arm IS on disk, so there is nothing to patch and a P0/P1 pair would be two identical
numbers. This instrument takes the bend-side rows from a FILE instead, so the BEFORE
(`noneshape/patir-run1.txt`, `AReduce`-spelled) and the AFTER
(`arglit/patir-AFTER.txt`, `AOpLit`-spelled) are compared by the same code against the
same py rows.

    env -u PYTHONPATH LC_ALL=C DEV=CPU .venv/bin/python .agents/slop/arglit/al-verdict.py \
        .agents/slop/noneshape/patir-run1.txt BEFORE
    env -u PYTHONPATH LC_ALL=C DEV=CPU .venv/bin/python .agents/slop/arglit/al-verdict.py \
        .agents/slop/arglit/patir-AFTER.txt AFTER

THE `AssertionError` WIDENING IS INHERITED FROM `ns-argplant.py` and is NOT PART OF ANY
FIX: upstream's `ops.py:444` assert FIRES on the AND node, so without the widening the py
rows cannot be emitted at all and this instrument would report nothing. It catches
`RuntimeError`, and `AssertionError` ONLY when the message starts
`"None input shape not supported for "` -- so `ops.py:438`/`:137`/`:141`, which are WRONG
FIXTURES, still refuse. It is a monkeypatch and NOTHING ON DISK CARRIES IT.
"""
from __future__ import annotations

import os
import sys

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
SLOP = os.path.join(REPO, ".agents/slop")
sys.path.insert(0, REPO)
sys.path.insert(0, SLOP)
os.environ["DEV"] = "CPU"

import graphcmp as G  # noqa: E402

G.load_tinygrad()

from tinygrad.uop.ops import UOp, UPat, Ops  # noqa: E402
from tinygrad.uop.upat import _get_clause  # noqa: E402
from tinygrad import dtypes  # noqa: E402


def widen() -> None:
  """The AND node's shape has no answer on either side. `R` on the py side is the
  widening; the port's `all_shapes` refuses and prints `?`. NOT A FIX."""
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


def py_rows() -> list[str]:
  root = _get_clause(UPat(Ops.ADD), UOp(Ops.CUSTOMI, arg=("uop", dtypes.void)))
  lst = list(root.toposort())
  ix = {id(n): i + 1 for i, n in enumerate(lst)}
  return [G.row_of(n, i + 1, ix) for i, n in enumerate(lst)]


def bend_rows(path: str) -> list[str]:
  rows = []
  for ln in open(path).read().splitlines():
    if ln and not ln.startswith("#") and "available" not in ln:
      rows.append(ln)
  if not rows:
    raise SystemExit(f"{path}: 0 rows -- an instrument that produced nothing is not a pass")
  # A row is `i:iN nsrc:NS op:NAME dtype:X shape:X src:N ARG`, so it always carries at
  # least four colons and a `src:` field. A `.bend` SOURCE file passes the emptiness test
  # above and then dies inside `unchunks` with `substring not found` -- MEASURED, and it
  # did: this check exists because the plant script once passed the PROBE where the probe's
  # OUTPUT was meant, got rc 0 from a crash-free-looking run, and reported "moved 0".
  # A row's SIX fields are six `k:v` chunks separated by single spaces, so it has FIVE
  # colons and its fifth chunk is the src list. `src:` appears only inside the arg text
  # (`n(i1,i2)`, `rg(i0,...)`), never as a field -- MEASURED on the row below, which has 5
  # colons and no `src:` field, so asking for `src:` rejected a perfect row and my first
  # draft of this check was wrong for the same reason the FLIP check was: it tested for
  # something other than the claim.
  # ASK THE SAME FUNCTION THE COMPARISON ASKS. A row is 8 unchunks: index, op, and one per
  # `G.FIELDS`. There is no cheap textual proxy for that and I tried two: chunk-count
  # rejects a PERFECT row whose arg text contains a space (`in(s{0}.op is {1},Dvoid)`), and
  # `count(":")` is fooled both ways. `G.unchunks` IS the parser, so a row is a row exactly
  # when it parses to the right arity -- and a `.bend` source line does not, MEASURED.
  bad = []
  for r in rows:
    try:
      if len(G.unchunks(r)) != len(G.FIELDS) + 2:
        bad.append(r)
    except Exception:
      bad.append(r)
  if bad:
    raise SystemExit(f"{path}: {len(bad)} of {len(rows)} line(s) are not rows, first: {bad[0][:70]!r}"
                     f" -- pass the probe's OUTPUT, not the probe.")
  return rows


def no_carg_arm() -> None:
  """The PRE-FIX py side, MEASURED rather than recalled: the landed arm is removed by
  flipping one predicate, so this cell differs from the AFTER cell by exactly the arm.
  `ns-argplant.py`'s `ORIG_CARG` was this function before the arm was added; here the
  arm is skipped on the SAME function object, so there is no second copy to drift."""
  import graphcmp as g
  landed = g.carg
  armed = (Ops.CUSTOM, Ops.CUSTOMI)

  def pre(op, x) -> str:
    if op in armed:
      return g._carg(x)  # what it did before: the generic tuple grammar, `n(`
    return landed(op, x)

  g.carg = pre


def main() -> int:
  if len(sys.argv) not in (3, 4):
    print(__doc__)
    return 2
  path, tag = sys.argv[1], sys.argv[2]
  pre_arm = len(sys.argv) == 4 and sys.argv[3] == "pre-arm"
  widen()
  if pre_arm:
    no_carg_arm()
    print("# (py side: the `carg` CUSTOM/CUSTOMI arm DISABLED -- the pre-fix cell)")
  py = py_rows()
  bd = bend_rows(path)
  blank = ["?", "?", "?", "?", "?", "?", "?", "?"]
  bad = agree = 0
  print(f"# VERDICT {tag}  ({os.path.basename(path)})")
  print(f"#   denominator: {len(py)} py rows x {len(G.FIELDS)} fields = {len(py) * len(G.FIELDS)}"
        f" field-records; {len(bd)} bend rows")
  for i in range(max(len(py), len(bd))):
    pf = G.unchunks(py[i]) if i < len(py) else blank
    bf = G.unchunks(bd[i]) if i < len(bd) else blank
    d = [(k, pf[j + 2], bf[j + 2]) for j, k in enumerate(G.FIELDS) if pf[j + 2] != bf[j + 2]]
    print(f"  node {i + 1} {pf[1]:<10} {'AGREE' if not d else 'MISMATCH ' + ', '.join(k for k, _, _ in d)}")
    for k, x, y in d:
      print(f"#       {k:<6} py={x}   bend={y}")
    bad += len(d)
    agree += len(G.FIELDS) - len(d)
  print(f"# VERDICT {tag}: {'AGREE' if bad == 0 else f'DISAGREE -- {bad} field mismatches'}"
        f" of {len(G.FIELDS) * max(len(py), len(bd))}; {agree} agree")
  return 0


if __name__ == "__main__":
  sys.exit(main())
