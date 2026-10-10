#!/usr/bin/env python
"""censusclaims.py -- EVERY census string in a fixture docstring, against the LIVE rows.

A fixture's docstring census is PROSE, not a declaration, and this file's first job is to
say so with a measurement rather than an assertion: MEASURED 0 docstring-read sites across
`checks/*.py`, `gates/*.py`, `.agents/slop/*.py` and `oracles/*.py` (AST: every
`Attribute(attr="__doc__")` and every `Name(id in {getdoc, cleandoc})`).  So a stale census
in a docstring breaks nothing mechanically -- which is exactly why it can rot: the bend half
of a pair corrected its own docstring and the py half did not, and the pair then disagreed
about what the census IS.

THE POPULATION of claims is `ast.get_docstring` over the `def g_*` functions of the fixture --
the fixture's own AST, not a grep for `GROUP=`, which would find the same token in prose,
in a comment, and in a code string alike.

THE ROWS are `isolate.emit(name, "py", dev)`: ONE FRESH PROCESS PER GRAPH.  Calling
`graphcmp.emit_py` in a loop does not work and does not merely cost time -- `UOp.unique_num`
is a module-level `itertools.count` that reaches the row stream through `ParamArg(next(...))`
and out through `graphcmp.py:708`'s `u(pa.slot)`, so graph N's rows carry a number no
published row set contains.  `.agents/slop/hermetic/isolate.py` exists for this."""
import ast, os, pathlib, re, sys, collections

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / ".agents" / "slop" / "hermetic"))
sys.path.insert(0, str(ROOT / ".agents" / "slop"))
os.environ["DEV"] = "CPU"
import graphcmp as G      # noqa: E402
import isolate           # noqa: E402

CENSUS = re.compile(r"`([A-Z][A-Z0-9_]*(?:=\d+(?: [^`]*?)?)(?: [A-Z][A-Z0-9_]*=\d+)*)`")
NAME = re.compile(r"g_(\w+)\Z")


def claims(path):
  """(graph, line, {op: count}) for every `OP=n ...` census string in a `g_*` docstring."""
  src = pathlib.Path(path).read_text()
  tree = ast.parse(src)
  out = []
  for n in ast.walk(tree):
    if not isinstance(n, ast.FunctionDef):
      continue
    doc = ast.get_docstring(n) or ""
    # The fixture names its builders `g_<graph>` and `GRAPHS` keys them by the BARE name.
    m = NAME.match(n.name)
    if not m:
      continue
    for c in CENSUS.finditer(doc):
      got = dict(re.findall(r"([A-Z][A-Z0-9_]*)=(\d+)", c.group(1)))
      if got:
        # `GRAPHS` is keyed by the BARE name -- "flip", not "g_flip" -- so the graph to ask
        # `isolate.emit` for is `m.group(1)` alone.  Two revisions printed `g_flip` here and
        # every one of the 18 came back `KeyError: 'g_flip'` from `graphcmp.py:1613`.
        out.append((m.group(1), n.lineno, {k: int(v) for k, v in got.items()}))
  return out


def measured(graph):
  rows = isolate.emit(graph, "py", "CPU")
  return collections.Counter(r.split()[1].split(":")[-1] for r in rows)


def main():
  # ONE file, and it is the Python one.  `graphcmp.bend` is NOT Python -- the bend half
  # keeps its censuses in `#` comments, so `ast.parse` raises SyntaxError on it and a
  # census claim there is not a docstring at all.  Its side is settled by the LIVE bend
  # emit and by its own corrected comments, both cited in the report.
  for path in (".agents/slop/graphcmp.py",):
    cl = claims(ROOT / path)
    print(f"\n{path} -- {len(cl)} docstring census claims, each checked against "
          f"isolate.emit(<g>, 'py', 'CPU')")
    for g, line, c in cl:
      try:
        m = measured(g)
      except SystemExit as e:
        print(f"  {g:<16} docstring line {line:<5} WALL: {e}")
        continue
      want = collections.Counter(c)
      ok = want == m
      print(f"  {'OK  ' if ok else 'WRONG'} {g:<16} docstring line {line:<5} "
            f"docstring={dict(sorted(c.items()))}")
      if not ok:
        only_doc = {k: v for k, v in want.items() if m.get(k, 0) != v}
        print(f"       live rows say  {dict(sorted(m.items()))}")
        print(f"       the disagreement: {only_doc}")
  return 0


if __name__ == "__main__":
  sys.exit(main())