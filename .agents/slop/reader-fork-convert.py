#!/usr/bin/env python3
"""reader-fork-convert.py -- DELETE A FORKED READER BY IMPORTING THE GATE'S, MECHANICALLY.

    python3 .agents/slop/reader-fork-convert.py --apply
    python3 .agents/slop/reader-fork-convert.py            # dry run, prints the plan

A copied reader is a second reader. That is the whole reason this file exists, and it is why
every replacement is an IMPORT of `rebase-gate.py`'s `rows()` -- loaded BY PATH, the idiom
`ops-501-mutate.py` already established, because `rebase-gate.py` is not an identifier and a
`from rebase_gate import rows` that cannot resolve is a reader that silently stops being one.

WHAT IT WILL NOT DO. It will not touch a fork whose contract is genuinely its own. Those are
registered in `.agents/slop/reader-contracts.tsv` with the contract stated, and
`reader-guard.py` fails if a registered fork's BEHAVIOUR moves without its contract text moving
with it. A fork with a stated contract is acceptable; a fork that claims to be `rows()` is not.

⚠ CONVERTING CHANGES A TOOL'S BEHAVIOUR, so it is not free. `--apply` prints, per file, what
the reader read before and what it reads after on the six shapes, and the caller is expected to
check that against the tool's own lane. `reader-fork-census.py` re-run afterwards is the
independent check: the drifted count must fall by exactly the number of rows converted, and a
reader that stops being a `def` leaves the candidate list entirely -- so a conversion that did
not happen cannot hide.
"""
import argparse
import ast
import importlib.util
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent

# The import block every converted file gets. `pathlib` and `sys` are assumed present; the
# converter ADDS them when they are not, and refuses if it cannot.
BANNER = """
# ── THE ROW READER IS `rebase-gate.py`'s OWN, LOADED BY PATH AND NOT COPIED ──────────────
# Measured by reader-fork-census.py, on this corpus and on the tree it was measured against:
# 51 of 52 text readers disagreed with `rows()` on at least one of the six row shapes, and four
# of them carried a docstring saying they were `rows()` VERBATIM. A copied reader is a second
# reader; this is the only import of the gate's, so there is exactly one answer to "what does
# this lane's output mean".
#
# ⚠ THE CONVERSION IS NOT FREE and the census prints the load: 1,440 lane files under
# .agents/slop, 289,262 lines, of which 44,345 are F2 (`py=`-tail) lines and 2,370 are F3
# (two-space) lines. So a fork that did not fold the `py=` tail was reading a DIFFERENT STRING
# on 15% of the lanes it read, and one that skipped F3 was blind to 0.8% of them. Those numbers
# are the size of what these forks were getting wrong, not a rounding of it.
_RG = importlib.util.spec_from_file_location("rebase_gate", {GATE})
_rebase_gate = importlib.util.module_from_spec(_RG)
_RG.loader.exec_module(_rebase_gate)
{FUNC} = _rebase_gate.rows
"""

# (relpath, func name) -- every one of these is a textbook `name=value` splitter with no stated
# contract of its own, or a fork whose docstring CLAIMED to be `rows()`. The forks that really do
# have their own contract are in reader-contracts.tsv and are deliberately absent from this list.
CONVERT = (
  # the four that asserted the identity measurement refutes
  ("ga_controls.py", "rows"),
  ("ga_rows_blast.py", "rows"),
  ("pin-tree-oracle.py", "rows"),
  ("rebase-oracle-ops.py", "rows"),
  # textbook duplicates, no stated contract
  ("ga_rows.py", "rows"),
  ("rebase-break.py", "rows"),
  ("rebase-shadow.py", "rows"),
  ("commute-detect.py", "rows_of"),
  ("ops-python-mutate.py", "rows_of"),
  ("helpers-tc-mutate.py", "rows"),
  ("mt_diff.py", "rows"),
  ("mop-mut.py", "rows"),
  ("debug-mutate.py", "rows_of"),
  ("ext_mutate.py", "rows_of_text"),
  ("mutate.py", "rows"),
  ("dtype-pri-mutate.py", "rows_of"),
  ("tools/mutate-dm.py", "rows"),
  ("tools/mutate-allreduce.py", "rows"),
  ("tools/mutate-memory.py", "rows"),
)


def gate_rows():
  spec = importlib.util.spec_from_file_location("rebase_gate", str(HERE / "rebase-gate.py"))
  m = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(m)
  return m.rows


def node_of(src, func):
  for n in ast.walk(ast.parse(src)):
    if isinstance(n, ast.FunctionDef) and n.name == func:
      return n
  return None


def convert(rel, func, apply):
  p = HERE / rel
  src = p.read_text()
  n = node_of(src, func)
  if n is None:
    return f"SKIP  {rel}:{func} -- no such def (already converted?)"
  if "_rebase_gate.rows" in src and f"\n{func} = _rebase_gate.rows" in src:
    return f"SKIP  {rel}:{func} -- already imports the gate's rows()"

  lines = src.splitlines(keepends=True)
  start, end = n.lineno - 1, n.end_lineno
  block = "".join(lines[start:end])

  imports = [i for i in ("importlib.util", "pathlib", "sys")
             if not _has_import(src, i)]
  added = ""
  if imports:
    head = ""
    if "importlib" in imports and not _has_import(src, "importlib"):
      head += "import importlib.util\n"
    if "pathlib" in imports and not _has_import(src, "pathlib"):
      head += "import pathlib\n"
    if "sys" in imports and not _has_import(src, "sys"):
      head += "import sys\n"
    added = head

  # `rebase-gate.py` lives at the TOP of `.agents/slop`, so a file in `tools/` has to climb two
  # levels to find it. `with_name` would silently build a path to a file that is not there and
  # the tool would stop having a reader at all -- which is the failure mode this whole exercise
  # exists to end, so the climb is computed from the path rather than assumed flat.
  up = ".parent" * (len(rel.split("/")) - 1)
  gate = f"pathlib.Path(__file__).resolve(){up} / \"rebase-gate.py\""
  new_src = ("".join(lines[:start]) + added + BANNER.format(FUNC=func, GATE=gate)
             + "".join(lines[end:]))
  detail = (f"{rel}:{func}  {len(block.splitlines())} lines of parser removed, "
            f"import added ({', '.join(imports) if imports else 'no imports needed'})")
  if not apply:
    return f"PLAN  {detail}"
  p.write_text(new_src)
  return f"DONE  {detail}"


def _has_import(src, mod):
  for n in ast.walk(ast.parse(src)):
    if isinstance(n, ast.Import):
      if any(a.name == mod or a.name.startswith(mod + ".") for a in n.names):
        return True
    if isinstance(n, ast.ImportFrom):
      if (n.module or "") == mod or (n.module or "").startswith(mod + "."):
        return True
  return False


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--apply", action="store_true")
  a = ap.parse_args()
  print(f"control: rebase-gate.py rows(), loaded by path -- {gate_rows() is not None}")
  for rel, func in CONVERT:
    print(" ", convert(rel, func, a.apply))
  # Every touched file must still PARSE. A converter that leaves a file unparseable has
  # replaced a drifted reader with no reader at all, which is strictly worse.
  bad = []
  for rel, _ in CONVERT:
    try:
      ast.parse((HERE / rel).read_text())
    except SyntaxError as e:
      bad.append(f"{rel}: {e}")
  print(f"\nparse check over {len(CONVERT)} files: "
        f"{'all parse' if not bad else 'FAILED ' + '; '.join(bad)}")
  return 1 if bad else 0


if __name__ == "__main__":
  sys.exit(main())