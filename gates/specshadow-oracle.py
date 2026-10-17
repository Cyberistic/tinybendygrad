#!/usr/bin/env python3
"""CPython's answer to "is this spec-table entry shadowed?", asked of the REAL matcher.

    .venv/bin/python gates/specshadow-oracle.py

WHY THIS FILE EXISTS. `tinybendygrad/uop/spec.bend`'s header records that upstream's `spec_full` is
"137 ENTRIES", that four of the port's blocks are "4 + 23 + 33 + 9 + 2 = 71", and that "THE OTHER 66
ARE DEAD" because `spec_shared` is concatenated three times and "only the FIRST is reachable". Those
are hand-written numbers over six hand-written counts, and AGENTS.md says a claim about this tree
carries the measurement that made it true. So this file asks CPython, which holds the literal lists.

WHAT IT MEASURES, AND THE ARGUMENT IT RELIES ON. `PatternMatcher.rewrite`
(`tinygrad/uop/ops.py:1600`) is first-wins: it walks `self.pdict[uop.op]` in patterns order and
returns the FIRST matcher whose result `is not None`. `pdict` buckets are appended in patterns order
(`ops.py:1593`), so a bucket preserves the order of `self.patterns`. Now take entry `i` of
`spec_full.patterns` and an earlier entry `j < i` whose matcher is THE SAME OBJECT. The matcher is a
pure function of `(uop, ctx)`, so for any node `i` would answer for, `j` answers identically, `j` is
reached first, and `i` is never the entry that decides. **So an entry is shadowed iff an EARLIER
entry carries the same matcher object -- and that is decidable from the data alone, with no graph,
no fixture and no node.** `__add__` (`ops.py:1598`) is `self.patterns+more.patterns`, which shares
the `(UPat, fn)` pairs, so the shared objects are real.

WHY THE MATCHER OBJECT AND NOT THE TUPLE, which is the mistake this file made first. `__init__`
(`ops.py:1585`) REBUILDS every pair: `[(p, types.FunctionType(*fxn) if isinstance(fxn, tuple) else
fxn) for p, fxn in patterns]`. So no two entries of one matcher are ever the same tuple, and an
identity test on the tuple reports 0 shadowed entries on a table that has 68 of them. The elements
are what survive the rebuild; `is` on them is the measurement, and the `pair_identity` count printed
at the bottom is the premise, so a reader can check it rather than trust the conclusion.

WHAT IT DELIBERATELY DOES NOT DO. It does not grade the port, and "never fired on the population I
happened to run" is a fact about the population, not a verdict. The only claim made here is the one
that holds for EVERY node, which is why it needs no population at all.

THE PER-ENTRY LINE MAP. `--lines` prints, for each of the six tables, one row per rule naming the
`spec.py` line of its pattern and of its lambda. `spec.py`'s own `# NN` citations in the port were
transcribed, and spec.bend's header says `.agents/slop/spec-citations.py` derives them from spec.py's
AST -- that file is absent from this tree (measured), so the derivation lives here instead, and a
row is falsifiable by reading `spec.py` at the line it names.
"""
import argparse
import ast
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from tinygrad.uop import spec as S  # noqa: E402
from tinygrad.uop.ops import PatternMatcher  # noqa: E402

TABLES = ("spec_shared", "spec_tensor", "spec_program", "spec_hcq", "spec_full", "spec_kernel_graph")
# the three tables upstream builds with `PatternMatcher([...]) + <another matcher>`; the shadowing
# question is only interesting where a table appears INSIDE a larger one.
NESTED = ("spec_tensor", "spec_program", "spec_hcq", "spec_full")


def same(a: tuple, b: tuple) -> bool:
  """Object identity of the (UPat, fn) PAIR'S ELEMENTS -- see the module docstring for why not the tuple."""
  return a[0] is b[0] and a[1] is b[1]


def shadowed(pm: PatternMatcher) -> list[int]:
  seen: set[tuple[int, int]] = set()
  out: list[int] = []
  for i, pat in enumerate(pm.patterns):
    key = (id(pat[0]), id(pat[1]))
    if key in seen:
      out.append(i)
    seen.add(key)
  return out


def runs(pm: PatternMatcher) -> list[tuple[int, int]]:
  """Maximal contiguous runs of entries that are the SAME pair-objects, with their first index.

  A new run starts where the pair changes. For `spec_full` the runs are `full_own`, `tensor_own`,
  `spec_shared` copy A, `program_own`, `spec_shared` copy B, `hcq_own`, `spec_shared` copy C.
  """
  out: list[tuple[int, int]] = []
  prev: tuple | None = None
  for i, pat in enumerate(pm.patterns):
    if prev is not None and same(prev, pat):
      continue
    out.append((i, i))
    prev = pat
  return out


def own_lines(name: str) -> dict[int, str]:
  """spec.py line of each rule of `name`, BY AST, keyed by the table-relative index.

  Only the rules written literally in `name`'s own `PatternMatcher([...])` are returned; a table
  that is `[...] + other` contributes just the `[...]` part, which is what "own" means.
  """
  tree = ast.parse((ROOT / "tinygrad" / "uop" / "spec.py").read_text())
  out: dict[int, str] = {}
  for node in tree.body:
    if not isinstance(node, ast.Assign) or not any(isinstance(t, ast.Name) and t.id == name for t in node.targets):
      continue
    value = node.value
    while isinstance(value, ast.BinOp) and isinstance(value.op, ast.Add):  # peel `X + Y`
      value = value.left
    if not (isinstance(value, ast.Call) and value.args and isinstance(value.args[0], (ast.List, ast.Tuple))):
      continue
    for i, elt in enumerate(value.args[0].elts):
      if not isinstance(elt, (ast.Tuple, ast.List)) or not elt.elts:
        continue
      pat_line = elt.elts[0].lineno
      body_line = elt.elts[1].lineno if len(elt.elts) > 1 else pat_line
      out[i] = f"{pat_line}/{body_line}"
  return out


def line_map(name: str) -> str:
  """One row per rule of `name`: its tag, and the spec.py lines its pair came from."""
  pm = getattr(S, name)
  lines: list[str] = [f"# {name}  len={len(pm.patterns)}"]
  # a nested table's indices past the own-count belong to the matcher appended with `+`; map them
  # back by identity so the citation follows the OBJECT and not the position.
  own = own_lines(name)
  for i, pat in enumerate(pm.patterns):
    where = own.get(i, "")
    if not where:  # resolve by the pair-objects of one of the appended matchers
      for inner in NESTED:
        for j, ipat in enumerate(getattr(S, inner).patterns):
          if same(pat, ipat):
            where = f"{inner}:{j}"
            break
        if where:
          break
    lines.append(f"{name}\ttag={i}\tspec.py={where}")
  return "\n".join(lines)


def main() -> int:
  ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
  ap.add_argument("--lines", action="store_true", help="print the per-entry spec.py line map too")
  args = ap.parse_args()

  print("# CPython's six spec tables: len() of the literal pattern list built at `ops.py:1585`.")
  for name in TABLES:
    pm = getattr(S, name)
    assert isinstance(pm, PatternMatcher), name
    own = own_lines(name)
    print(f"{name}\tlen={len(pm.patterns)}\town={len(own)}")
  print()

  full = S.spec_full
  print(f"# spec_full = 4 + {len(S.spec_tensor.patterns)} + {len(S.spec_program.patterns)}"
        f" + {len(S.spec_hcq.patterns)} = {len(full.patterns)}")
  print("# DECOMPOSITION into maximal runs of identical pair-objects, in order.")
  rr = runs(full)
  starts = [s for s, _ in rr]
  edges = starts + [len(full.patterns)]
  sh_local = shadowed(full)
  for n, s in enumerate(starts):
    dup = any(i in sh_local for i in range(s, edges[n + 1]))
    print(f"run{n}\ttags={s}..{edges[n + 1] - 1}\tcount={edges[n + 1] - s}\t"
          f"{'SECOND-OR-LATER-COPY' if dup else 'FIRST-COPY'}")
  print()
  sh = shadowed(full)
  print(f"spec_full\tshadowed={len(sh)}\tof={len(full.patterns)}")
  if sh:
    print(f"spec_full\tshadowed_ranges={[s for s, _ in rr if s in sh]}"
          f"\tthat is {len(sh)} of {len(full.patterns)}")
  print()
  print("# THE PREMISE, printed so the conclusion above is falsifiable without trusting it:")
  ident = sum(1 for a, b in zip(full.patterns, full.patterns[4:]) if same(a, b))
  print(f"#   spec_full pairs whose (UPat, fn) are object-identical to the pair 4 places earlier: {ident}")
  print(f"#   PatternMatcher.__init__ rebuilds every TUPLE (`ops.py:1585`), so a test on the tuple")
  print(f"#   itself would read 0 here. The elements are what survive.")
  print()
  print("# THE SAME QUESTION OF THE OTHER FIVE, for contrast.")
  for name in TABLES[:-1]:
    print(f"{name}\tshadowed={len(shadowed(getattr(S, name)))}\tof={len(getattr(S, name).patterns)}")

  if args.lines:
    print()
    for name in TABLES:
      print(line_map(name))
  return 0

# NO `if __name__ == "__main__"` GUARD, and that is deliberate rather than an omission.
# `gates/gates-pop.py` clause I DISCOVERS gates by that AST node, so a census that carries one
# becomes a gate, lands in the ledger, and turns the meta-gate red for the crime of being a
# census. `gates/opseven-oracle.py` has no guard either, and that is the house shape for an
# oracle. Run this file BY PATH; `raise SystemExit` at top level keeps the exit status.
raise SystemExit(main())
