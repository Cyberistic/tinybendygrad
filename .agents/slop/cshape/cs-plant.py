#!/usr/bin/env python3
"""cs-plant.py -- THE PLANT AND THE DISARM, DISARM FIRST, AND THE TWO-SIDED VERDICT.

Order matters and the order is the point.

  1. DISARM FIRST. This unit made NO edit to `graphcmp.py`, so the disarm is "remove this
     unit's probes" and it must move NOTHING. MEASURED: the live file's md5 before and
     after, and the 25-graph row census run TWICE with a byte comparison. A disarm that
     moves a row is not a disarm; one control in this tree moved 15 rows and would have
     shipped a false theorem, and another "removed the fix" while actually being a SECOND
     mutation. So the disarm is measured before the plant exists, not after.

  2. THE WIDENING'S BLAST RADIUS ON THE EXISTING CORPUS. One widening applied, then the
     whole 25-graph row set diffed against the baseline BY WHOLE `name=value` LINE -- a
     harness that diffs row NAMES reported 0 for all 30 mutations in one unit and 0 for all
     68 in another, so this one diffs text.

  3. THE PLANTS. Each asks `cshape` DIRECTLY, because that is the arm under test and
     `row_of` reaches other instruments first: the NEG plant's `.dtype` dies in
     `promo_dtype(())` at ops.py BEFORE `cshape` is called, so a plant driven through
     `row_of` measures the wrong def. One edit per arm, so each is an attribution.
       PLANT-A  ops.py:438 `unary ops must have 1 src` -- a WRONG FIXTURE, not a shapeless
                op. Separates the unscoped arm from the ops.py:444-scoped arm.
       PLANT-B  ops.py:444 `None input shape not supported for ADD` -- a graph upstream
                calls INVALID, and the same fact the pattern compiler's AND produces.
       PLANT-C  the pattern-compiler IR itself, both sides, with the ledger and a VERDICT.

    env -u PYTHONPATH LC_ALL=C DEV=CPU .venv/bin/python .agents/slop/cshape/cs-plant.py
"""
from __future__ import annotations

import hashlib
import os
import sys

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
SLOP = os.path.join(REPO, ".agents/slop")
sys.path.insert(0, REPO)
sys.path.insert(0, SLOP)
os.environ["DEV"] = "CPU"

import graphcmp as G  # noqa: E402

G.load_tinygrad()
G.COMM = G.commutative()

from tinygrad.uop.ops import UOp, UPat, Ops  # noqa: E402
from tinygrad.uop.upat import _get_clause  # noqa: E402
from tinygrad import dtypes  # noqa: E402

ORIG_CSHAPE = G.cshape
LEDGER = ("z", "y", "u", "q", "X!", "BAD", "E", "?")
BEND_ROWS = os.path.join(SLOP, "cshape", "patir-bend.txt")


def md5(path: str) -> str:
  return hashlib.md5(open(path, "rb").read()).hexdigest()


def census() -> dict[str, list[str]]:
  """Every py-side row of every graph, by graph name. The corpus, as TEXT."""
  return {g: G.emit_py(g, None) for g in sorted(G.GRAPHS)}


def ledger(rows: list[str]) -> dict[str, int]:
  """Per-ROW counts of the live markers, by the DIFFER'S OWN test -- `G.LEDGER` says which
  marker goes at which field and `G.at_value` says a value position -- the same pair
  `.agents/slop/graphcmp-oracle.py` uses. A first version scanned every field for the
  marker's TEXT and reported all zeros on a corpus the differ's own census reports as
  carrying `z y q E ?`."""
  out = {m: 0 for m in LEDGER}
  for r in rows:
    f = G.unchunks(r)
    for m, fis, _, _ in G.LEDGER:
      if any(G.at_value(f[fi], m) for fi in fis):
        out[m] += 1
  return out


def make_cshape(excs, scoped: bool = False):
  """The one arm under test. `scoped` narrows ONLY the AssertionError, so the two arms
  differ by ONE predicate and the RuntimeError half behaves identically in both."""
  def cshape(n: UOp) -> str:
    try:
      shp = n.shape
    except excs as e:
      if scoped and isinstance(e, AssertionError) and not str(e).startswith(
          "None input shape not supported for "):
        raise
      return "R"
    if shp is None:
      G.SHAPE_NONE_HITS += 1
      return "N"
    return "(" + ",".join("U" if isinstance(d, UOp) else G.i64(d) for d in shp) + ")"
  return cshape


def rows_of(root: UOp) -> list[str]:
  """`root.toposort()`, numbered the way `emit_py` numbers. Numbering the WHOLE toposort
  matters: an earlier version mapped only the node it was asked about, so a node with a
  src read `ix[id(src)]` off a dict that did not hold it and died with
  `KeyError: <UOp.unique_num>` -- a crash in the PLANT that read like a crash in the
  instrument."""
  nodes = root.toposort()
  ix = {id(s): j + 1 for j, s in enumerate(nodes)}
  out = []
  for i, n in enumerate(nodes):
    try:
      out.append(G.row_of(n, i + 1, ix))
    except BaseException as e:  # noqa: BLE001 -- the emitter DYING is the measurement
      out.append(f"!! DIED {type(e).__name__}: {' '.join(str(e).split())[:64]}")
  return out


ARMS = (("W0  except RuntimeError            (LIVE)", (RuntimeError,), False),
        ("W1  + AssertionError, UNSCOPED", (RuntimeError, AssertionError), False),
        ("W1s + AssertionError, ops.py:444 only", (RuntimeError, AssertionError), True),
        ("W4  bare except Exception", (Exception,), False))


def ask_arm(label, node: UOp) -> str:
  """`cshape(node)` and nothing else."""
  G.cshape = make_cshape(*dict((a[0], (a[1], a[2])) for a in ARMS)[label][1:2] if False else
                         next((a[1:] for a in ARMS if a[0] == label)))
  try:
    return "R" if G.cshape(node) == "R" else f"dims={G.cshape(node)}"
  except BaseException as e:  # noqa: BLE001
    return f"!! DIED {type(e).__name__}: {' '.join(str(e).split())[:52]}"
  finally:
    G.cshape = ORIG_CSHAPE


def main() -> int:
  live = os.path.join(SLOP, "graphcmp.py")
  md5_0 = md5(live)

  # ---- 1. THE DISARM, FIRST ----------------------------------------------------------
  print("# ==== 1. DISARM FIRST: this unit's probes removed, corpus unchanged ====")
  print(f"# md5 .agents/slop/graphcmp.py at entry : {md5_0}")
  base1 = census()
  base2 = census()
  same = base1 == base2
  print(f"# census run twice, byte-equal          : {same}  "
        f"(sha1 {hashlib.sha1(repr(sorted(base1.items())).encode()).hexdigest()[:16]})")
  print(f"# graphs {len(base1)}   rows {sum(len(v) for v in base1.values())}   "
        f"SHAPE_NONE_HITS {G.SHAPE_NONE_HITS}")
  print(f"# md5 after two censuses                : {md5(live)}  "
        f"(unchanged={md5_0 == md5(live)})")
  print(f"# THE DISARM'S VERDICT: "
        f"{'PASS -- moved nothing' if same and md5_0 == md5(live) else 'FAIL -- it MOVED'}")
  print("# NOTE the baseline itself is NOT clean: `lin` and `loop` disagree ON PURPOSE, so")
  print("# 'moved nothing' is about the DIFFERENCE between two runs, not about agreement.")

  # ---- 2. THE WIDENING'S BLAST RADIUS ON THE EXISTING CORPUS ------------------------
  print("\n# ==== 2. DOES ANY WIDENING MOVE A ROW THAT WAS ALREADY EMITTED? ====")
  for label, excs, scoped in ARMS:
    G.cshape = make_cshape(excs, scoped)
    G.SHAPE_NONE_HITS = 0
    try:
      now = census()
      moved = [(g, a, b) for g in base1 for a, b in zip(base1[g], now.get(g, [])) if a != b]
      print(f"  {label:<44} graphs {len(now)}  rows {sum(len(v) for v in now.values())}  "
            f"rows CHANGED {len(moved)}  graphs LOST {len(base1) - len(now)}  "
            f"SHAPE_NONE_HITS {G.SHAPE_NONE_HITS}")
      for g, a, b in moved[:4]:
        print(f"#     {g}: {a}\n#     {' ' * len(g)}  {b}")
    except BaseException as e:  # noqa: BLE001
      print(f"  {label:<44} CENSUS DIED {type(e).__name__}: {' '.join(str(e).split())[:52]}")
  G.cshape = ORIG_CSHAPE
  G.SHAPE_NONE_HITS = 0

  # ---- 3. PLANT-A: ops.py:438, A WRONG FIXTURE --------------------------------------
  print("\n# ==== 3. PLANT-A -- ops.py:438 `unary ops must have 1 src`: a BAD FIXTURE ====")
  bad = UOp(Ops.NEG, src=())
  try:
    bad.shape
  except BaseException as e:  # noqa: BLE001
    print(f"#   upstream raises {type(e).__name__}: {' '.join(str(e).split())[:56]}")
  for label, _, _ in ARMS:
    print(f"  {label:<44} cshape -> {ask_arm(label, bad)}")
  print("#   THE ATTRIBUTION: W1 renders `R` for a graph upstream calls a BUG. W1s refuses.")
  print("#   Both arms differ by ONE predicate and the difference is exactly this row.")

  # ---- 3b. PLANT-B: ops.py:444, A SHAPELESS-SRC GRAPH --------------------------------
  print("\n# ==== 3b. PLANT-B -- ops.py:444 `None input shape not supported`: the AND case ====")
  invalid = UOp(Ops.ADD, src=(UOp(Ops.CUSTOMI, arg=("uop", dtypes.void)),))
  try:
    invalid.shape
  except BaseException as e:  # noqa: BLE001
    print(f"#   upstream raises {type(e).__name__}: {' '.join(str(e).split())[:56]}")
  for label, _, _ in ARMS:
    print(f"  {label:<44} cshape -> {ask_arm(label, invalid)}")

  # ---- 3c. PLANT-C: THE PATTERN-COMPILER IR, BOTH SIDES, WITH A VERDICT --------------
  print("\n# ==== 3c. PLANT-C -- the pattern IR, BOTH SIDES, LEDGER, AND THE VERDICT ====")
  pat = _get_clause(UPat(Ops.ADD), UOp(Ops.CUSTOMI, arg=("uop", dtypes.void)))
  # `bend` writes its upgrade notice to stdout too, and it parses as neither a comment nor
  # a row: `ValueError: invalid literal for int() with base 10: 'bend 2.0.35 is available'`.
  bend = [ln for ln in open(BEND_ROWS).read().splitlines()
          if ln.strip() and not ln.startswith("#") and not ln.startswith("bend ")]
  py_by_w = {}
  for label, excs, scoped in ARMS:
    G.cshape = make_cshape(excs, scoped)
    py_by_w[label] = rows_of(pat)
  G.cshape = ORIG_CSHAPE
  print(f"# py side, W0 (LIVE) -- {len(py_by_w[ARMS[0][0]])} of {len(pat.toposort())} nodes:")
  for ln in py_by_w[ARMS[0][0]]:
    print(f"  py {ln}")
  for label, _, _ in ARMS[1:]:
    print(f"# py side, {label} -- {len(py_by_w[label])} of {len(pat.toposort())} nodes:")
    for ln in py_by_w[label]:
      print(f"  py {ln}")
  print(f"# bend side, {BEND_ROWS} (cs-patir.bend, the DIFFER's own renderer):")
  for ln in bend:
    print(f"  bd {ln}")
  # ---- the field-by-field comparison, which is the VERDICT and not the ledger --------
  print(f"\n# ---- FIELD-BY-FIELD, py(W1) vs bend. 8 wire fields; 6 are compared "
        f"({', '.join(G.FIELDS)}) ----")
  p = [G.unchunks(r) for r in py_by_w[ARMS[1][0]]]
  b = [G.unchunks(r) for r in bend]
  cmp_bad = agree = 0
  for i in range(max(len(p), len(b))):
    pf = p[i] if i < len(p) else None
    bf = b[i] if i < len(b) else None
    if pf is None or bf is None:
      print(f"  node {i+1}: ONE-SIDED py={pf is not None} bend={bf is not None}")
      cmp_bad += 1
      continue
    # `unchunks` returns `[id, op, dtype, shape, depth, tag, arg, src]`, so `G.FIELDS`'s
    # six names start at index 2. A first version used `j + 1` and reported "shape
    # py=void" -- the DTYPE column under the SHAPE column's name, which is the exact
    # "field NAMES and never field counts" trap with the columns shifted by one.
    diffs = [(k, pf[j + 2], bf[j + 2]) for j, k in enumerate(G.FIELDS) if pf[j + 2] != bf[j + 2]]
    print(f"  node {i+1} {pf[1]:<10} {'AGREE' if not diffs else 'MISMATCH ' + ', '.join(k for k, _, _ in diffs)}")
    for k, x, y in diffs:
      print(f"#       {k:<6} py={x}   bend={y}")
    cmp_bad += len(diffs)
    agree += 6 - len(diffs)
  lpy, lbd = ledger(py_by_w[ARMS[1][0]]), ledger(bend)
  print(f"\n#   VERDICT: {'AGREE' if cmp_bad == 0 else f'DISAGREE -- {cmp_bad} field mismatches'} "
        f"(field-records compared {6 * max(len(p), len(b))}, agreeing {agree})")
  print(f"#   ledger py  {lpy}")
  print(f"#   ledger bend {lbd}")
  print(f"#   ?={lpy['?']}/{lbd['?']} -- THE HEADLINE IS THE VERDICT ABOVE, NOT THIS LINE:")
  print(f"#   `flip` read ?=0 on BOTH sides while DISAGREEing at 6/7, and reads ?=0 now that")
  print(f"#   it AGREEs. `?` measures omission, not agreement.")

  # ---- 4. THE LEDGER OVER THE LIVE CORPUS --------------------------------------------
  print("\n# ==== 4. LEDGER PER SIDE OVER THE LIVE 25-GRAPH CORPUS (no widening applied) ====")
  tot = {m: 0 for m in LEDGER}
  for g in sorted(base1):
    l = ledger(base1[g])
    for m in LEDGER:
      tot[m] += l[m]
    live_m = {m: c for m, c in l.items() if c}
    print(f"  {g:<10} {len(base1[g]):>3} rows  {','.join(sorted(live_m)) or '-':<12} {live_m or '-'}")
  print(f"  {'TOTAL py':<10} {sum(len(v) for v in base1.values()):>3} rows  {tot}")
  print(f"# SHAPE_NONE_HITS over the whole census: {G.SHAPE_NONE_HITS} "
        f"(the `N` arm -- measured dead, as `cshape`'s own docstring says)")

  # ---- 5. THE CORPUS AFTER, AGAINST 77, BOTH SIDES, WITH THE SPLIT -------------------
  print("\n# ==== 5. CORPUS BEFORE / AFTER, AGAINST 77, BOTH SIDES, WITH THE SPLIT ====")
  den = len(list(Ops))
  live_py = {G.unchunks(r)[1] for rows in base1.values() for r in rows}
  live_bd = {G.unchunks(r)[1] for g in sorted(base1)
             for r in G.emit_bend("CPU", g, tries=3)[0]}
  pat_ops_py = {G.unchunks(r)[1] for r in py_by_w[ARMS[1][0]]}
  pat_ops_bd = {G.unchunks(r)[1] for r in bend}
  print(f"# denominator                       : {den}   (measured len(list(Ops)))")
  print(f"# graphs                            : {len(base1)} -> {len(base1) + 1} (patir)")
  print(f"# reached PY                        : {len(live_py)} -> {len(live_py | pat_ops_py)}")
  print(f"# reached BEND                      : {len(live_bd)} -> {len(live_bd | pat_ops_bd)}")
  print(f"# reached BOTH                      : {len(live_py & live_bd)} -> "
        f"{len((live_py | pat_ops_py) & (live_bd | pat_ops_bd))}")
  print(f"# py-only                           : {sorted(live_py - live_bd)} -> "
        f"{sorted((live_py | pat_ops_py) - (live_bd | pat_ops_bd))}")
  print(f"# bend-only                         : {sorted(live_bd - live_py)} -> "
        f"{sorted((live_bd | pat_ops_bd) - (live_py | pat_ops_py))}")
  after = (live_py | pat_ops_py) | (live_bd | pat_ops_bd)
  never = sorted(o.name for o in Ops if o.name not in after)
  print(f"# NEVER reached, either side         : {den - len(live_py | live_bd)} -> "
        f"{den - len(after)}  {never}")
  print("#   AND `patir` is NOT a clean addition: it reports 64/64/64 with py-only=[] and")
  print("#   bend-only=[] -- a CLEAN-LOOKING NUMBER -- while the verdict on the very same")
  print("#   graph is DISAGREE at 9 field mismatches with ?=3 on the bend side. The op")
  print("#   census counts an op REACHED from the row's op column, which is printed even")
  print("#   when the row reads `?` in dtype AND shape. `?` measures omission, and a clean")
  print("#   reach count is not agreement. THIS is the `flip` pattern, and it is why the")
  print("#   verdict is the headline and the reach count is not.")
  print("# THE LIVE corpus is UNCHANGED at 61/77 both sides: `patir` CANNOT be added to it,")
  print("# because `graphcmp.py`/`graphcmp.bend` (the `GRAPHS` dict and the dispatch arm)")
  print("# belong to another unit and this unit is forbidden to edit them. The 64/64/64")
  print("# above is the CEILING, measured from this unit's own probe, NOT the live number --")
  print("# and per the paragraph above it is NOT a claim of agreement either.")
  return 0


if __name__ == "__main__":
  sys.exit(main())
