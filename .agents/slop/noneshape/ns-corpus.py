#!/usr/bin/env python3
"""ns-corpus.py -- THE CORPUS BEFORE AND AFTER, AGAINST 77, BOTH SIDES, WITH THE SPLIT,
AND THE VERDICT.

Three measurements, in this order, because the verdict has to be able to falsify the
reach count rather than decorate it:

  1. BLAST RADIUS. Every row of every graph in the LIVE corpus, before and after
     `uop/fold.bend`'s CUSTOM/CUSTOMI arm changed, diffed BY WHOLE `name=value` LINE.
     A harness that diffs row NAMES reported 0 for all 30 mutations in one unit and 0 for
     all 68 in another. The before-set is read from `.agents/slop/noneshape/base.py`, and
     that file is written by `--writebase`.

  2. THE SPLIT. `py-only` and `bend-only` over the union of live ops, plus the `NEITHER`
     list. Denominator `len(list(Ops))`, measured, not transcribed.

  3. THE VERDICT ON THE PATTERN IR, field by field, with the AssertionError widening the
     corpus needs in order to EMIT at all. The widening is an in-process monkeypatch and
     nothing on disk carries it, so it is re-derived here from the CSHAPE recipe and
     pinned by md5. NOTE WHAT IT BUYS: three MORE OPS REACHED and a VERDICT THAT IS STILL
     NOT `AGREE`, because the `Arg` spelling is the differ's, not the port's. The reach
     count is a count of something; the verdict is the answer.

    env -u PYTHONPATH LC_ALL=C DEV=CPU .venv/bin/python .agents/slop/noneshape/ns-corpus.py
    env -u PYTHONPATH LC_ALL=C DEV=CPU .venv/bin/python .agents/slop/noneshape/ns-corpus.py --writebase
"""
from __future__ import annotations

import hashlib
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
G.COMM = G.commutative()

from tinygrad.uop.ops import UOp, UPat, Ops  # noqa: E402
from tinygrad.uop.upat import _get_clause  # noqa: E402
from tinygrad import dtypes  # noqa: E402

BEND_ROWS = os.path.join(HERE, "patir-run1.txt")
BASE = os.path.join(HERE, "base.py")
LEDGER = ("z", "y", "u", "q", "X!", "BAD", "E", "?", "R")


def md5(path: str) -> str:
  return hashlib.md5(open(path, "rb").read()).hexdigest()


def census() -> dict[str, list[str]]:
  d = {}
  for g in sorted(G.GRAPHS):
    d[g] = G.emit_py(g, None) + G.emit_bend("CPU", g, tries=3)[0]
  return d


def bend_rows(path: str | None = None) -> list[str]:
  return [ln for ln in open(path or BEND_ROWS).read().splitlines()
          if ln and not ln.startswith("#") and "available" not in ln]


def verdict(py: list[str], bd: list[str], tag: str) -> tuple[int, int]:
  cmp_bad, agree = 0, 0
  print(f"  -- {tag}")
  for i in range(max(len(py), len(bd))):
    pf = G.unchunks(py[i]) if i < len(py) else ["?", "?", "?", "?", "?", "?", "?", "?"]
    bf = G.unchunks(bd[i]) if i < len(bd) else ["?", "?", "?", "?", "?", "?", "?", "?"]
    diffs = [(k, pf[j + 2], bf[j + 2]) for j, k in enumerate(G.FIELDS) if pf[j + 2] != bf[j + 2]]
    print(f"  node {i + 1} {pf[1]:<10} {'AGREE' if not diffs else 'MISMATCH ' + ', '.join(k for k, _, _ in diffs)}")
    for k, x, y in diffs:
      print(f"#       {k:<6} py={x}   bend={y}")
    cmp_bad += len(diffs)
    agree += 6 - len(diffs)
  print(f"# VERDICT {tag}: {'AGREE' if cmp_bad == 0 else f'DISAGREE -- {cmp_bad} field mismatches'} "
        f"(of {6 * max(len(py), len(bd))} field-records; {agree} agree)")
  return cmp_bad, agree


def ledger(lines) -> dict:
  out = {m: 0 for m in LEDGER}
  for ln in lines:
    f = G.unchunks(ln)
    for m, fis, _, _ in G.LEDGER:
      if any(G.at_value(f[fi], m) for fi in fis):
        out[m] += 1
    if f[3] == "R":
      out["R"] += 1
  return out


def widen(g):
  """The CSHAPE W1s recipe: `except RuntimeError` plus ops.py:444's AssertionError and
  NOTHING ELSE. ops.py:438/137/141 are wrong FIXTURES, not shapeless ops."""
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


def main() -> int:
  before = census()
  if "--writebase" in sys.argv:
    # ONE ROW PER LINE and NO in-row separator, because a row's own text contains commas:
    # `P(i0,Df32,i12,...)` and `rg(i0,XDEVICE,n(i0))` both do. A first version joined with
    # "," and read back with split(","), which shredded 2230 rows into 611 fragments and
    # reported EVERY graph's row COUNT as moved -- a blast radius of 611 that was pure
    # separator arithmetic. THAT is the CSH-6 failure in a new costume: a harness that
    # cannot parse its own baseline will report a huge diff and it will look like a plant.
    with open(BASE, "w") as f:
      f.write("\n".join(f"{g}\t{r}" for g in sorted(before) for r in before[g]) + "\n")
    print(f"# wrote {BASE}: {sum(len(v) for v in before.values())} rows")
    return 0

  print("# ==== 0. PINS ====")
  for name, p in (("graphcmp.py", os.path.join(SLOP, "graphcmp.py")),
                  ("graphcmp.bend", os.path.join(SLOP, "graphcmp.bend")),
                  ("tinybendygrad/uop/fold.bend", os.path.join(REPO, "tinybendygrad/uop/fold.bend"))):
    print(f"# md5 {name:<32} {md5(p)}")

  print("\n# ==== 1. BLAST RADIUS ON THE LIVE CORPUS, WHOLE `name=value` LINE ====")
  if not os.path.exists(BASE):
    print("# NO BASELINE FILE -- run --writebase FIRST. An absent instrument is not a pass.")
    return 1
  base: dict[str, list[str]] = {}
  for ln in open(BASE):
    g, _, r = ln.rstrip("\n").partition("\t")
    base.setdefault(g, []).append(r)
  now = before
  moved = [(g, a, b) for g in sorted(set(base) | set(now))
           for a, b in zip(base.get(g, []), now.get(g, [])) if a != b]
  len_moved = [g for g in sorted(set(base) | set(now)) if len(base.get(g, [])) != len(now.get(g, []))]
  print(f"# graphs {len(now)}   rows now {sum(len(v) for v in now.values())}   "
        f"rows base {sum(len(v) for v in base.values())}")
  print(f"# rows whose TEXT moved: {len(moved)}   graphs whose row COUNT moved: {len(len_moved)}")
  for g, a, b in moved[:20]:
    print(f"#   {g}: {a}  ->  {b}")
  if len_moved:
    print(f"#   count-moved graphs: {len_moved}")

  print("\n# ==== 2. THE SPLIT, AGAINST 77 ====")
  den = len(list(Ops))
  live_py = {G.unchunks(r)[1] for rows in now.values() for r in rows}
  live_bd = {G.unchunks(r)[1] for g in sorted(now) for r in G.emit_bend("CPU", g, tries=3)[0]}
  pat_py = {G.unchunks(r)[1] for r in py_ir()}
  pat_bd = {G.unchunks(r)[1] for r in bend_rows()}
  print(f"# denominator (measured len(list(Ops)))        : {den}")
  print(f"# graphs (live)                                 : {len(now)}   (+1 patir, ceiling)")
  print(f"# reached PY        live {len(live_py)}   +patir {len(pat_py)}   "
        f"union {len(live_py | pat_py)}")
  print(f"# reached BEND      live {len(live_bd)}   +patir {len(pat_bd)}   "
        f"union {len(live_bd | pat_bd)}")
  print(f"# reached BOTH      live {len(live_py & live_bd)}   "
        f"+patir {len((live_py | pat_py) & (live_bd | pat_bd))}")
  print(f"# py-only           live {sorted(live_py - live_bd)}   "
        f"+patir {sorted((live_py | pat_py) - (live_bd | pat_bd))}")
  print(f"# bend-only         live {sorted(live_bd - live_py)}   "
        f"+patir {sorted((live_bd | pat_bd) - (live_py | pat_py))}")
  after = (live_py | pat_py) | (live_bd | pat_bd)
  never = sorted(o.name for o in Ops if o.name not in after)
  print(f"# NEITHER (either side)  live {den - len(live_py | live_bd)}   "
        f"+patir {den - len(after)}   {never}")
  print(f"# ledger live  PY   {ledger([r for rows in now.values() for r in rows])}")
  print(f"# ledger live  BEND {ledger([r for g in sorted(now) for r in G.emit_bend('CPU', g, tries=3)[0]])}")

  print("\n# ==== 3. THE VERDICT ON THE PATTERN IR -- THE HEADLINE ====")
  widen(G)
  py = emit_ir(ir_root())
  if not py:
    print("# py side emitted NOTHING. That is a CRASH, not an agreement.")
    return 1
  run0 = os.path.join(HERE, "patir-run0.txt")
  print("\n# BEFORE -- the SAME py rows against `fold.bend` at the pin e372ca22, same probe,")
  print("# so the two verdicts differ by `fold.bend` and by nothing else:")
  verdict(py, bend_rows(run0) if os.path.exists(run0) else [], "BEFORE")
  print("\n# AFTER -- the same py rows against `fold.bend` at 310c3975:")
  cmp_bad, agree = verdict(py, bend_rows(), "AFTER")
  print(f"\n# ledger py   {ledger(py)}")
  print(f"# ledger bend {ledger(bend_rows())}")
  print("# py rows as emitted:")
  for ln in py:
    print(f"#   {ln}")
  print("# py rows, bend side, AFTER:")
  for ln in bend_rows():
    print(f"#   {ln}")
  print("# NOTE the `arg` column: it disagrees on `n(` vs `in(` and on `OADD` vs")
  print("# `rd(OADD,i0)`, and BOTH halves of that are the DIFFER's, not the port's --")
  print("# see .agents/slop/NONSHAPE.md sec 3. The dtype and shape columns AGREE on every")
  print("# node this unit's arm covers, which is what `fold.bend` was for; the AND's")
  print("# `?` is the port refusing upstream's assert at ops.py:444, which is upstream's")
  print("# own answer and is NOT widened here.")
  return 0


def ir_root() -> UOp:
  return _get_clause(UPat(Ops.ADD), UOp(Ops.CUSTOMI, arg=("uop", dtypes.void)))


def emit_ir(root: UOp) -> list[str]:
  """`emit_py`'s tail, on a UOp that is not a `base()` graph name: the toposort and the
  `ix` map are the whole of it."""
  lst = list(root.toposort())
  ix = {id(n): i + 1 for i, n in enumerate(lst)}
  return [G.row_of(n, i + 1, ix) for i, n in enumerate(lst)]


def py_ir() -> list[str]:
  orig = G.cshape
  try:
    widen(G)
    return emit_ir(ir_root())
  finally:
    G.cshape = orig


if __name__ == "__main__":
  sys.exit(main())