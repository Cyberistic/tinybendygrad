#!/usr/bin/env python3
"""handtyped-rank.py -- RANK THE HAND-TYPED ROWS BY CONSEQUENCE, NOT BY COUNT.

`order-verdicts.py` ranked by how many `BELIEF?` rows an oracle had, which is
ranking by SIZE. `nv-oracle.py` is the largest block at 102 sites and its most
consequential rows are twenty lines in the middle of it; `cs_oracle.py` has 63
and half of them are LLVM triple strings where a wrong literal is a cosmetic
mismatch. Size is not consequence and this file does not use it.

FOUR SIGNALS, all computed, none guessed.

  LIES    a row whose literal makes the gate ASSERT something rather than
          DESCRIBE something: a `True`/`False` that decides a control path, an
          error or refusal MESSAGE, a branch decided by `if/else` over
          constants, or a name emitted TWICE in one oracle (where the gate's
          one-value-per-name reader makes one of the pair unobservable no
          matter what it says). This is the class that turns a wrong port into
          a green gate instead of a red one.
  REIMPL  a row whose subject leans on a def that is a transcription of the
          upstream formula -- `reimpl-scan.py`'s measurement. A call into a
          copy of the subject is worse than a literal, because it looks derived.
  MAGIC   a bare number with no provenance: hex, binary, or a decimal >= 100.
          Every hex constant in every oracle was invisible to the old detector,
          and the two worst hand-typed incidents this project paid for were both
          hex (BNXT_VENDOR 5356 vs 5348, and ~0x6996 written as 24425).
  DEAD    a literal no run of the oracle ever produced.

  rank = 3*LIES + 2*REIMPL + MAGIC + 2*DEAD, per ORACLE, over DEFECT sites only.

    .venv/bin/python .agents/slop/handtyped-rank.py
"""
from __future__ import annotations

import ast
import pathlib
import re
import sys
from collections import Counter, defaultdict

ROOT = pathlib.Path(__file__).resolve().parents[2]
SLOP = ROOT / ".agents" / "slop"
sys.path.insert(0, str(SLOP))
from importlib import import_module  # noqa: E402

audit = import_module("handtyped-audit")
reimpl = import_module("reimpl-scan")

MSG = re.compile(r"(?:raise|refus|cannot|can not|must |invalid|unknown|not "
                 r"supported|unsupported|is empty|out of |required|no device|"
                 r"failed|error)", re.I)
NAMED = re.compile(r"(?:_ok|_refus|_msg|_message|_raises|_raises|_bad|_fail|"
                   r"_err|_none|_miss)", re.I)
HEX = re.compile(r"0[xXbBoO]")
MAGIC_DEC = re.compile(r"^\d{3,}$")


class _Arm(ast.NodeVisitor):
  """Tag every `row` site with the try/except ARM it sits in.

  A duplicate row NAME is only a shadow when both sites can EXECUTE. Two sites
  in opposite arms of one `try`/`except` share a name by construction -- the
  `ok` row and the `refused` row -- and exactly one of them runs, so the gate's
  one-value-per-name reader is not hiding anything. Counting those as shadows put
  seven of `elf_oracle.py`'s "duplicates" in the LIES column and would have made
  it rank second for the wrong reason.

  TERMINAL BLOCKS MATTER TOO. `prepare-oracle.py`'s `sr_{nm}_ret` has three
  sites at :401 (the `except` arm), :404 (`if ret is None: row(...); return`) and
  :405, and the two latter are mutually exclusive because the `if` body RETURNS.
  Modelling only `try`/`except` called all three shadows and put
  `prepare-oracle.py` third on the list for thirteen names that hide nothing.
  """

  def __init__(self):
    self.stack: list[tuple[int, str]] = []
    self.arm: dict[int, tuple] = {}

  def _block(self, tid: int, label: str, body):
    self.stack.append((tid, label))
    for s in body:
      self.visit(s)
    self.stack.append((tid, label + "$end"))

  def visit_Try(self, node: ast.Try):
    tid = id(node)
    self._block(tid, "try", node.body)
    self._block(tid, "else", node.orelse)
    self._block(tid, "fin", node.finalbody)
    for h in node.handlers:
      self._block(tid, "exc", h.body)
    # NO `self.generic_visit(node)` HERE. It re-walks every statement in the
    # try with an EMPTY stack and `visit_Call` overwrites `arm[lineno]`, so every
    # tagged row ends up untagged and every try/except pair looks like a shadow.

  def visit_If(self, node: ast.If):
    tid = id(node)
    self.visit(node.test)
    # a block that ends in return/raise/continue/break cannot fall through, so
    # whatever follows it is in a different execution path
    self._block(tid, "thenT" if _terminal(node.body) else "then",
                node.body)
    self._block(tid, "elseT" if _terminal(node.orelse) else "elseF",
                node.orelse)

  def visit_Call(self, node: ast.Call):
    fn = node.func
    fname = fn.attr if isinstance(fn, ast.Attribute) else (
      fn.id if isinstance(fn, ast.Name) else None)
    if fname in audit.ROW_FUNCS:
      self.arm[node.lineno] = tuple(self.stack)
    self.generic_visit(node)


def _terminal(body) -> bool:
  if not body:
    return False
  last = body[-1]
  return isinstance(last, (ast.Return, ast.Raise, ast.Continue, ast.Break))


def signals(path: pathlib.Path) -> dict:
  scan = audit.scan(path)
  rows = [r for r in scan["rows"] if r["defect"]]
  arms = _Arm()
  arms.visit(ast.parse(path.read_text(errors="replace")))
  # a name is SHADOWED when two of its sites share an arm path, i.e. both can run
  byname: dict[str, list[dict]] = {}
  for r in scan["rows"]:
    byname.setdefault(r["name"], []).append(r)
  dup = set()
  for nm, rs in byname.items():
    if len(rs) < 2:
      continue
    seen = Counter()
    for r in rs:
      seen[arms.arm.get(r["lineno"], ())] += 1
    if any(c > 1 for c in seen.values()):
      dup.add(nm)
  allnames = Counter(r["name"] for r in scan["rows"])

  def lies(r) -> bool:
    v = r["value_src"]
    if r["name"] in dup:
      return True
    if v.strip("\"'") in ("True", "False"):
      return True
    if v[:1] == v[-1:] and v[:1] in "\"'" and (MSG.search(v) or NAMED.search(r["name"])):
      return True
    if re.search(r"\bif\b|\belse\b|ite\(", v):
      return True
    return False

  def magic(r) -> bool:
    return bool(HEX.search(r["value_src"])) or bool(MAGIC_DEC.match(r["value_src"].strip()))

  # REIMPL IS COUNTED OVER *EVERY* SITE, NOT OVER THE DEFECT ONES, and that is
  # not a detail. A row whose value calls a def that copies the upstream formula
  # is classified DERIVED by `handtyped-audit` -- it is a call, and a call is not
  # hand-typed -- so the two sets are DISJOINT BY CONSTRUCTION. Scoring REIMPL
  # inside the DEFECT set reads 0 for every oracle in the corpus, and a column
  # that is 0 everywhere because of how the filter is built is not a
  # measurement. `nv-oracle.py`'s `_bpt` / `_smem_cfg` / `_max_threads` /
  # `_top` / `_unk_size` all live on the DERIVED side, and 22 of its row sites
  # lean on one of them.
  rhits = [h for h in reimpl.scan(path) if len(h["canon"]) >= 24]
  rdefs = {h["name"] for h in rhits}

  def leans(r) -> bool:
    v = r["value_src"]
    return any(re.search(r"\b" + re.escape(d) + r"\s*\(", v) for d in rdefs)

  allrows = scan["rows"]
  return {
    "path": path,
    "n": len(rows),
    "sites": len(allrows),
    "lies": sum(1 for r in rows if lies(r)),
    "magic": sum(1 for r in rows if magic(r)),
    "reimpl": sum(1 for r in allrows if leans(r)),
    "dupnames": len(dup),
    "rdefs": len(rdefs),
    "rows": rows,
  }


def main() -> int:
  print("=" * 104)
  print("HAND-TYPED ROWS RANKED BY CONSEQUENCE -- DEFECT sites only, LITERAL+LOCAL")
  print("=" * 104)
  out = []
  for f in audit.oracles():
    if "MUTANT" in f.name:
      continue
    s = signals(f)
    if not s["n"]:
      continue
    score = 3 * s["lies"] + 2 * s["reimpl"] + s["magic"]
    out.append((score, s))
  out.sort(key=lambda kv: -kv[0])
  print(f"{'rank':>4} {'oracle':30} {'score':>6} {'DEFECT':>7} {'LIES':>5} "
        f"{'MAGIC':>6} {'REIMPL':>7} {'reimpl-defs':>12} {'dup names':>10}")
  for i, (sc, s) in enumerate(out, 1):
    print(f"{i:>4} {str(s['path'].relative_to(SLOP))[:29]:30} {sc:>6} {s['n']:>7} "
          f"{s['lies']:>5} {s['magic']:>6} {s['reimpl']:>7} {s['rdefs']:>12} "
          f"{s['dupnames']:>10}")
  tot = [0, 0, 0, 0]
  for _, s in out:
    tot = [a + b for a, b in zip(tot, [s["n"], s["lies"], s["magic"], s["reimpl"]])]
  print("-" * 104)
  print(f"{'':4} {'TOTAL':30} {'':6} {tot[0]:>7} {tot[1]:>5} {tot[2]:>6} {tot[3]:>7}")
  print()
  print("LIES  = the row asserts a control decision, a message, or a SHADOWED name.")
  print("        A name is shadowed when two of its sites share a try/except ARM,")
  print("        i.e. both can run; opposite arms cannot, and counting those put")
  print("        elf_oracle's seven ok/refused pairs in as shadows.")
  print("MAGIC = hex/binary, or a bare decimal >= 100 with no provenance.")
  print("REIMPL= the row's value comes from a def that copies the upstream formula.")
  print()
  print("THE ORDER IS NOT THE COUNT ORDER, and here is the whole difference:")
  bycount = sorted(out, key=lambda kv: -kv[1]["n"])[:6]
  print(f"  {'by COUNT':30} " + " ".join(str(s['path'].name)[:9] for _, s in bycount))
  print(f"  {'by SCORE':30} " + " ".join(str(s['path'].name)[:9] for _, s in out[:6]))
  return 0


if __name__ == "__main__":
  raise SystemExit(main())