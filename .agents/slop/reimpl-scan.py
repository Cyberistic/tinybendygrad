#!/usr/bin/env python3
"""reimpl-scan.py -- ORACLES THAT RE-IMPLEMENT THE SUBJECT THEY MEASURE.

THE DEFECT. A row whose expected value is a CALL is only a test if the call
reaches the thing under test. `row("nv_bpt_0", _bpt(0, 48, 4))` is a call, and
`_bpt` is defined in the same oracle as

    def _bpt(slm, mws, nsm):
      return round_up(round_up(slm * 32, 0x200) * mws * nsm, 0x8000)

which is `tinygrad/runtime/ops_nv.py:693` with the attribute names replaced by
parameters. That is the same formula, character for character. Every `nv_bpt_*`
row is DERIVED in the only sense that matters to a regex and is a TRANSCRIPTION
in the only sense that matters to a reader -- and it is worse than a literal,
because a literal announces itself.

MEASURED, NOT GUESSED. A local def is a candidate when its body's CANONICAL FORM
-- every identifier and attribute name collapsed to `N`, keeping literals,
operators and helper call names -- appears in the upstream `.py` it claims to
oracle. Matching on the canonical form rather than the text is what lets
`slm` line up with `self.slm_per_thread`.

This is a CANDIDATE GENERATOR and it says so: every hit prints the oracle line,
the upstream file:line, and both canonical forms, so a reader can check it. It
never asserts a verdict, because a canonical match is a strong signal and not a
proof -- `round_up(x, 0x200)` is a one-liner that occurs in many places.

    .venv/bin/python .agents/slop/reimpl-scan.py                 # every oracle
    .venv/bin/python .agents/slop/reimpl-scan.py --oracle nv      # one file
    .venv/bin/python .agents/slop/reimpl-scan.py --min-len 20
"""
from __future__ import annotations

import argparse
import ast
import pathlib
import sys
from collections import defaultdict

ROOT = pathlib.Path(__file__).resolve().parents[2]
SLOP = ROOT / ".agents" / "slop"
sys.path.insert(0, str(SLOP))
from importlib import import_module  # noqa: E402

audit = import_module("handtyped-audit")

HELPERS = {"round_up", "data64", "len", "int", "str", "min", "max", "prod",
           "math", "list", "tuple", "set", "sorted", "abs", "divmod", "pow"}


def canon(node: ast.AST) -> str:
  """Identifier-free rendering: literals, operators, and HELPER names survive."""
  if isinstance(node, ast.Constant):
    return repr(node.value)
  if isinstance(node, ast.Name):
    return "N" if node.id not in HELPERS else node.id
  if isinstance(node, ast.Attribute):
    base = canon(node.value)
    return f"{base}.{node.attr}" if base in HELPERS else "N"
  if isinstance(node, ast.Call):
    f = node.func
    fname = f.id if isinstance(f, ast.Name) else (f.attr if isinstance(f, ast.Attribute) else "N")
    fname = fname if fname in HELPERS else "N"
    return f"{fname}({','.join(canon(a) for a in node.args)})"
  if isinstance(node, ast.BinOp):
    return f"({canon(node.left)}{type(node.op).__name__}{canon(node.right)})"
  if isinstance(node, ast.UnaryOp):
    return f"({type(node.op).__name__}{canon(node.operand)})"
  if isinstance(node, ast.Compare):
    ops = "".join(type(o).__name__ for o in node.ops)
    return f"({canon(node.left)}{ops}{','.join(canon(c) for c in node.comparators)})"
  if isinstance(node, ast.IfExp):
    return f"(ite({canon(node.test)},{canon(node.body)},{canon(node.orelse)}))"
  if isinstance(node, (ast.List, ast.Tuple)):
    return "[" + ",".join(canon(e) for e in node.elts) + "]"
  if isinstance(node, ast.Dict):
    return "{" + ",".join(canon(v) for v in node.values) + "}"
  if isinstance(node, ast.Subscript):
    return f"{canon(node.value)}[...]"
  return "?"


def exprs_of(path: pathlib.Path) -> dict[str, list[tuple[int, str]]]:
  """canonical form -> [(lineno, source)] for every expression in a .py file."""
  try:
    tree = ast.parse(path.read_text(errors="replace"))
  except (SyntaxError, OSError):
    return {}
  lines = path.read_text(errors="replace").splitlines()
  out: dict[str, list[tuple[int, str]]] = defaultdict(list)
  for n in ast.walk(tree):
    if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
      for st in ast.walk(n):
        if isinstance(st, ast.expr):
          c = canon(st)
          if len(c) >= 12:
            out[c].append((st.lineno, lines[st.lineno - 1].strip()))
  return out


def upstream_for(oracle: pathlib.Path) -> list[pathlib.Path]:
  """Which upstream `.py` an oracle touches, from its OWN IMPORTS.

  Not from its docstring. `nv-oracle.py`'s docstring names
  `tinybendygrad/runtime/ops_nv.bend` -- the PORT -- and its imports are the
  only place `tinygrad/runtime/ops_nv.py` appears, in dotted form
  (`from tinygrad.runtime.ops_nv import ...`). A slash-path regex over the
  header found ZERO upstream files for `nv-oracle.py` and therefore reported
  none of its re-implementations, which is the worst possible direction for a
  detector to fail in: `nv-oracle.py` holds the `_bpt` case.
  """
  import re as _re
  out: list[pathlib.Path] = []
  try:
    tree = ast.parse(oracle.read_text(errors="replace"))
  except SyntaxError:
    return out
  mods: set[str] = set()
  for n in ast.walk(tree):
    if isinstance(n, ast.Import):
      mods |= {a.name for a in n.names if a.name.startswith("tinygrad")}
    elif isinstance(n, ast.ImportFrom) and (n.module or "").startswith("tinygrad"):
      mods.add(n.module)
  head = oracle.read_text(errors="replace")[:4000]
  mods |= {m.group(1) for m in _re.finditer(r"\b([a-z_][a-z0-9_/]*\.py)\b", head)}
  for m in mods:
    rel = m[:-3].replace(".", "/") + ".py" if m.endswith(".py") else m.replace(".", "/")
    for cand in (ROOT / "tinygrad" / f"{rel}.py", ROOT / "tinygrad" / rel,
                 ROOT / rel):
      if cand.exists() and cand.is_file() and cand not in out:
        out.append(cand)
  return out


def scan(oracle: pathlib.Path) -> list[dict]:
  tree = ast.parse(oracle.read_text(errors="replace"))
  ups = upstream_for(oracle)
  if not ups:
    return []
  idx = {u: exprs_of(u) for u in ups}
  lines = oracle.read_text(errors="replace").splitlines()
  hits = []
  for n in ast.walk(tree):
    if not isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
      continue
    if n.name in audit.ROW_FUNCS:
      continue
    for st in ast.walk(n):
      if not isinstance(st, ast.expr):
        continue
      c = canon(st)
      for u in ups:
        for (ul, usrc) in idx[u].get(c, []):
          hits.append({"name": n.name, "lineno": n.lineno, "expr_line": st.lineno,
                       "canon": c, "up": u, "up_line": ul, "up_src": usrc,
                       "oracle_src": lines[st.lineno - 1].strip()})
  # Keep the LONGEST canonical match per (def, oracle expr line, upstream file).
  # ast.walk yields every sub-expression, so an unfiltered list reports the same
  # copied line once per nesting level and a count of "10 candidates" turns out
  # to be one. Both lines are printed for each survivor, so the reader can check.
  best: dict[tuple, dict] = {}
  for h in hits:
    k = (h["name"], h["expr_line"], h["up"], h["up_line"])
    if k not in best or len(h["canon"]) > len(best[k]["canon"]):
      best[k] = h
  return sorted(best.values(), key=lambda h: (h["name"], h["expr_line"]))


def callers(oracle: pathlib.Path, fname: str, depth: int = 0) -> list[ast.expr]:
  """Row-value expressions that (transitively) call `fname`.

  A re-implementation matters in proportion to how many expected values lean on
  it. `_bpt` in `nv-oracle.py` is one copied line; if thirty `nv_bpt_*` rows call
  it then thirty rows are beliefs, and the honest denominator is thirty and not
  one.
  """
  if depth > 3:
    return []
  tree = ast.parse(oracle.read_text(errors="replace"))
  out = []
  for n in ast.walk(tree):
    if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and \
       n.func.id == fname:
      out.append(n)
  for g, ldef in ((n.name, n) for n in ast.walk(tree)
                  if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))):
    if g == fname:
      continue
    for c in ast.walk(ldef):
      if isinstance(c, ast.Call) and isinstance(c.func, ast.Name) and \
         c.func.id == fname:
        out.append(c)
  return out


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--oracle", default=None)
  ap.add_argument("--min-len", type=int, default=24)
  a = ap.parse_args()
  targets = [p for p in audit.oracles()
             if "MUTANT" not in p.name and
             (a.oracle is None or a.oracle in str(p))]
  print("=" * 100)
  print("ORACLES THAT RE-IMPLEMENT THE SUBJECT -- canonical-form match of a local")
  print("def's body against the upstream .py. CANDIDATES, each with both lines.")
  print("=" * 100)
  total = 0
  per = []
  for o in targets:
    hits = [h for h in scan(o) if len(h["canon"]) >= a.min_len]
    if not hits:
      continue
    per.append((len(hits), o))
    total += len(hits)
  print()
  print(f"{'oracle':32} {'reimpl exprs':>13} {'defs':>6} {'rows leaning on a copy':>24}")
  tot_rows = 0
  for n, o in sorted(per, key=lambda kv: -kv[0]):
    hits = [h for h in scan(o) if len(h["canon"]) >= a.min_len]
    defs = sorted({h["name"] for h in hits})
    nr = 0
    for d in defs:
      nr += len(callers(o, d))
    tot_rows += nr
    print(f"  {str(o.relative_to(SLOP))[:31]:32} {n:>13} {len(defs):>6} {nr:>24}")
  print(f"  {'TOTAL':32} {total:>13} {'':>6} {tot_rows:>24}")
  print()
  print("  `rows leaning on a copy` COUNTS CALL SITES that transitively call a")
  print("  re-implemented def, so a def used inside a loop counts once and the")
  print("  runtime row count is higher. It is an UPPER BOUND ON IMPACT per site")
  print("  only if no site is in a loop -- treat it as a site count, always.")
  print()
  for o in targets:
    hits = [h for h in scan(o) if len(h["canon"]) >= a.min_len]
    if not hits:
      continue
    print(f"--- {o.relative_to(SLOP)}   {len(hits)} candidate expression(s)")
    for h in hits:
      try:
        rel = h["up"].relative_to(ROOT)
      except ValueError:
        rel = h["up"]
      print(f"    def {h['name']} (:{h['lineno']})  expr at :{h['expr_line']}")
      print(f"      oracle   : {h['oracle_src'][:86]}")
      print(f"      {str(rel)}:{h['up_line']}")
      print(f"      upstream : {h['up_src'][:86]}")
  print("-" * 100)
  print(f"TOTAL candidate re-implementations: {total}")
  print("A canonical match is a SIGNAL, not a verdict. Read both lines.")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())