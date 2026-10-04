#!/usr/bin/env python3
"""graphcmp-oracle.py -- THE COVERAGE DENOMINATOR, TABULATED. Nothing here is typed.

Answers the question a verdict line cannot: for each `--graph`, how many NODES, how many
distinct OPS, how many distinct `arg` ATOM LETTERS, how many distinct SHAPE texts, and
which of the eight ledger markers are LIVE. `AGREE` on 18 nodes over 7 distinct ops with 6
atom letters is a different claim from `AGREE` on 2 nodes over 2 ops with 3 letters, and
the two must not be reported in the same way.

It emits BOTH sides and tabulates the union, so a port op or atom the py side never
produces shows up as a per-side difference rather than being absorbed into an AGREE.

    env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/graphcmp-oracle.py
"""
from __future__ import annotations

import collections
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import graphcmp as G  # noqa: E402


def atoms(arg: str) -> set:
  """The ATOM LETTERS in an arg. Two conditions, and the first version had only the first
  and was visibly wrong on screen -- MEASURED, it reported `34DNPSbils` for a `ParamArg`
  and `)` for a `KernelInfo`, because it counted the SECOND character of every atom and
  the `)` of the `n()` empty-list spelling:
    * the letter sits where a VALUE starts -- offset 0, or right after `( , : =` -- so
      the `D` inside `sDefault` is not an atom; and
    * the letter is a LETTER and is followed by alnum/underscore or by nothing, and the
      scan then SKIPS the rest of the token, so `i0` contributes `i` and `Df32`
      contributes `D`. That also stops `n()` contributing its `n` or its `)`."""
  out, i = set(), 0
  while i < len(arg):
    c = arg[i]
    if c.isalpha() and (i == 0 or arg[i - 1] in "(,:=") and (
        i + 1 == len(arg) or arg[i + 1].isalnum() or arg[i + 1] == "_"):
      out.add(c)
      while i + 1 < len(arg) and (arg[i + 1].isalnum() or arg[i + 1] == "_"):
        i += 1
    i += 1
  return out


def census(lines: list[str]) -> dict:
  ops, res, shapes, depths, atom = set(), set(), set(), set(), set()
  per_op: collections.Counter = collections.Counter()
  for ln in lines:
    f = G.unchunks(ln)
    ops.add(f[1])
    per_op[f[1]] += 1
    shapes.add(f[3])
    depths.add(f[4])
    atom |= atoms(f[6])
    for m, fis, _, _ in G.LEDGER:
      if any(G.at_value(f[fi], m) for fi in fis):
        res.add(m)
  return {"nodes": len(lines), "ops": ops, "residual": res, "shapes": shapes,
          "depths": depths, "atoms": atom, "symdims": symdim_rows(lines),
          "per_op": per_op}


def symdim_rows(lines: list[str]) -> list[str]:
  """The ids of the nodes whose `shape` column carries a symbolic dim. `symdims` counts
  over built `Node`s, which needs the whole differ; this reads the same `U` at a dim
  position straight off the wire so the census has no dependency on `build`."""
  return [G.unchunks(ln)[0][1:] for ln in lines
          if G.unchunks(ln)[3].startswith("(") and "U" in G.split_top(G.unchunks(ln)[3][1:-1])]


def main() -> int:
  os.environ.setdefault("DEV", "CPU")
  G.load_tinygrad()
  G.COMM = G.commutative()
  import tinygrad
  print(f"# tree={tinygrad.__file__}")
  print(f"# {'graph':<10} {'nodes':>5} {'cnt':>4} {'ops':>4} {'arg-atoms':>9} "
        f"{'shapes':>6} {'depths':>6} {'sym':>5}  live-ledger")
  tot_nodes = 0
  tot_ops: set[str] = set()
  tot_atoms: set[str] = set()
  tot_comm: set[str] = set()
  tot_sym = 0
  tal: collections.Counter = collections.Counter()
  graphs_of: collections.Counter = collections.Counter()
  all_res: collections.Counter = collections.Counter()
  for g in sorted(G.GRAPHS):
    py = census(G.emit_py(g, None))
    bd = census(G.emit_bend("CPU", g)[0])
    tot_nodes += py["nodes"]
    tot_ops |= py["ops"] | bd["ops"]
    tot_atoms |= py["atoms"] | bd["atoms"]
    tot_comm |= py["ops"] & G.COMM
    tot_sym += len(py["symdims"])
    tal.update(py["per_op"])
    graphs_of.update(py["ops"])
    for m in py["residual"] | bd["residual"]:
      all_res[m] += 1
    same = "same" if py["ops"] == bd["ops"] else f"PY-BEND OPs DIFFER: {py['ops'] ^ bd['ops']}"
    print(f"  {g:<10} {py['nodes']:>2}/{bd['nodes']:<2} {'ok' if py['nodes'] == bd['nodes'] else 'BAD':>4} "
          f"{len(py['ops']):>4} {''.join(sorted(py['atoms'])) or '-':>9} "
          f"{len(py['shapes']):>6} {len(py['depths']):>6} "
          f"{len(py['symdims']):>2}/{len(bd['symdims']):<2} "
          f"{','.join(sorted(py['residual'] | bd['residual'])) or '-'}  [{same}]")
  print(f"# TOTAL: {len(G.GRAPHS)} graphs, {tot_nodes} nodes per side, "
        f"{len(tot_ops)} distinct ops: {' '.join(sorted(tot_ops))}")
  print(f"# FIELDS COMPARED PER NODE: {len(G.WIRE)} on the wire, {len(G.FIELDS)} in the "
        f"equality decision ({', '.join(G.FIELDS)}); `id` is reporting-only by R1")
  comp = set(c[0] for c in G.COMPOSITE)
  unknown = tot_atoms - set(G.ATOMS.values()) - comp
  print(f"# COMPOSITE ARG FORMS SPELLED BY BOTH SIDES: {list(G.COMPOSITE)}")
  print(f"# DISTINCT ARG ATOM LETTERS REACHED: {''.join(sorted(tot_atoms))} "
      f"({len(tot_atoms)} distinct = {len(tot_atoms - comp)} atom letters + "
      f"{len(tot_atoms & comp)} composite-form prefixes; a letter that is NEITHER an atom "
      f"nor a composite prefix would be an unmapped value: {''.join(sorted(unknown)) or 'none'})")
  print(f"# LEDGER MARKERS LIVE ON AT LEAST ONE GRAPH: "
        f"{dict(sorted(all_res.items())) or 'none'} of {len(G.LEDGER)} markers")
  print("#   ^ SORTED, and that is DEFECT 20 (2026-10-04, found by the two-run byte check "
        "and by nothing else). `all_res` is a `Counter` whose insertion order is the order "
        "the markers were first seen, and it is fed by `py['residual'] | bd['residual']` -- "
        "a SET UNION, whose iteration order over STRINGS follows the per-process string hash "
        "and is therefore randomized by `PYTHONHASHSEED`. MEASURED: three consecutive runs "
        "of this oracle gave three answers, "
        "`{'y': 1, 'z': 1, 'q': 1, 'E': 1, '?': 2}` against "
        "`{'y': 1, 'z': 1, 'E': 1, 'q': 1, '?': 2}` against the first again, and the "
        "two-run sha256 check over `runs/graphcmp/D` caught it on `D0-coverage-census.txt` "
        "as the ONLY differing file out of 158.\n"
        "#   It is the exact class the brief names: a COUNT that is right and an ORDER that "
        "is not, printed where a reader will read it as one line of fact. Every OTHER "
        "iteration of a set in this file is already `sorted(...)` -- which is why 157 of "
        "158 files were stable and this one was not.")
  print(f"# LEDGER MARKERS NEVER LIVE ON ANY GRAPH: "
        f"{[m for m, _, _, _ in G.LEDGER if m not in all_res] or 'none'}")
  print(f"# COMMUTATIVE OPS (read from CPython): {sorted(G.COMM)}")
  print(f"# COMMUTATIVE OPS REACHED BY A NODE: {len(tot_comm)}/{len(G.COMM)} "
        f"{sorted(tot_comm)}; NOT REACHED {sorted(G.COMM - tot_comm)} "
        f"(--equiv is MEASURED on {len(tot_comm)} of {len(G.COMM)})")
  print(f"# SYMBOLIC-DIM NODES: {tot_sym} of {tot_nodes} py-side nodes carry a `U` dim "
        f"(MEASURED off the shape column of every graph above)")
  print(f"# FIELD-RECORDS PER SIDE: {tot_nodes} nodes x {len(G.FIELDS)} compared fields = "
        f"{tot_nodes * len(G.FIELDS)}")
  print("# PER-OP NODE COUNTS ACROSS THE CORPUS -- the denominator for every op claim:")
  print("#   " + "  ".join(f"{op} {tal[op]}/{graphs_of[op]}" for op in sorted(tal))
          + "   (nodes/graphs)")
  print(f"# NOT REACHED ({len(list(G.Ops)) - len(tal)} of {len(list(G.Ops))}): "
        + " ".join(o.name for o in G.Ops if o.name not in tal))
  return 0


if __name__ == "__main__":
  sys.exit(main())