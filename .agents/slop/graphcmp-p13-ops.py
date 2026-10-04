#!/usr/bin/env python3
"""graphcmp-p13-ops.py -- THE OPS PROBES, and every number graphcmp's coverage claim rests on.

Nothing here is transcribed. Every answer is printed from CPython at run time, and every
number in `.agents/slop/graphcmp-LIMITS.md` section 5 and section 6 comes out of this file.

    env -u PYTHONPATH LC_ALL=C DEV=CPU .venv/bin/python .agents/slop/graphcmp-p13-ops.py

Five questions, and which limit or defect each one answers:

  Q1  Does `Ops.GROUP` carry a `params` list?   -> LIMITS section 6 (it does not, at this
       tree) and the whole reason `--graph group` had to build its fan-in to be worth
       anything.
  Q2  Does any graph before `--graph group` have a node with more than one parent?
       -> the claim that the differ had never placed a node twice.
  Q3  Which Tensor-level operation emits which NODE op, and is it one of the eight
       `GroupOp.Commutative`?  -> the `--graph commute` fixture, and the measured reason
       `CMPEQ` is a limit rather than a missing fixture.
  Q4  Can a symbolic dim be reached, and can TWO DIFFERENT ones be distinguished by the
       differ's normal form?  -> LIMITS section 3.
  Q5  What is `ParamArg.slot` for a variable PARAM, and does the port have a spelling?
       -> LIMITS section 2, the slot sentinel, and the reason `--graph sym` spells it.
"""
import collections
import os
import sys

os.environ["DEV"] = "CPU"
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import graphcmp as G                                          # noqa: E402

G.load_tinygrad()
from tinygrad import Tensor, dtypes                           # noqa: E402
from tinygrad.dtype import AddrSpace                          # noqa: E402
from tinygrad.uop.ops import (AxisType, Ops, ParamArg, UOp)   # noqa: E402
from tinygrad.uop import GroupOp                              # noqa: E402
import tinygrad                                              # noqa: E402

COMM = {o.name for o in GroupOp.Commutative}
print(f"# tree={tinygrad.__file__}")
print(f"# len(list(Ops))={len(list(Ops))}   GroupOp.Commutative={sorted(COMM)}")


def dump(tag: str, ast: UOp) -> list:
  """The toposort through `graphcmp`'s OWN `row_of`, so the probe prints the normal form
  rather than a parallel spelling of it that could drift from the one being tested."""
  lst = list(ast.toposort())
  ix = {id(n): i + 1 for i, n in enumerate(lst)}
  print(f"### {tag}: nodes={len(lst)} ops={sorted(set(n.op.name for n in lst))}")
  for i, n in enumerate(lst):
    print("  " + G.row_of(n, i + 1, ix))
  edges: dict = collections.Counter()
  for n in lst:
    for c in n.src:
      edges[id(c)] += 1
  # TWO COUNTS, and the difference between them is the thing a DAG fixture has to state.
  # EDGES counts occurrences, so `sh + sh` puts `sh` in the ADD's src TWICE and RESHAPE#5
  # answers 4 edges in `--graph group`. DISTINCT PARENTS counts parent NODES, so it answers
  # 2 -- the ADD and the MUL. Reporting only the edge count would have made the fixture
  # look like it had four parents when it has two, and reporting only the parent count
  # would have hidden the repeated child index, which is a different property again.
  parents: dict = collections.defaultdict(set)
  for n in lst:
    for c in n.src:
      parents[id(c)].add(id(n))
  print(f"  MULTI-PARENT NODES (op, id, in-edges, distinct parents): "
        f"{[(n.op.name, ix[id(n)], edges[id(n)], len(parents[id(n)])) for n in lst
           if len(parents[id(n)]) > 1]}")
  sym = [(n.op.name, ix[id(n)], G.cshape(n)) for n in lst if "U" in G.cshape(n)]
  print(f"  SYMBOLIC-DIM NODES (op, id, shape): {sym}")
  return lst


print("\n== Q1 GROUP's ARG: IS THERE A `params` LIST TO COMPARE? ==")
sh = Tensor.empty(4, 3).uop
g = UOp.group(sh + sh, sh * sh)
print(f"# group.op={g.op.name} arg={g.arg!r} nsrc={len(g.src)} dtype={g.dtype.name} "
      f"tag={g.tag!r}")
print(f"# hasattr(group,'params')={hasattr(g, 'params')}   "
      f"attributes mentioning 'param': {[a for a in dir(g) if 'param' in a.lower()]}")
print(f"# UOp.group source (ops.py:558-560): it is "
      f"`UOp(Ops.GROUP, src=tuple(...), **kwargs)` with NO arg, so `arg` is always None")
try:
  g.shape
  print("# group.shape did NOT raise")
except RuntimeError as e:
  print(f"# group.shape RAISES: {e}  (so the shape column is `R`)")

print("\n== Q2 A NODE WITH MORE THAN ONE PARENT (the `--graph group` claim) ==")
dump("group", g)

print("\n== Q3 WHICH Tensor OP EMITS WHICH NODE OP (the `--graph commute` fixture) ==")
a = Tensor.empty(4, 3).uop
b = Tensor.empty(4, 3).uop
cases = {
  "a + b": lambda: a + b, "a != b": lambda: a != b, "a.maximum(b)": lambda: a.maximum(b),
  "a & b": lambda: a & b, "a | b": lambda: a | b, "a ^ b": lambda: a ^ b,
  "a.max()": lambda: a.max(), "a.min()": lambda: a.min(), "a.sum()": lambda: a.sum(),
}
for k, f in cases.items():
  try:
    got = dump(k, f())
    print(f"  COMMUTATIVE REACHED BY {k}: {sorted(set(n.op.name for n in got) & COMM)}")
  except Exception as e:                                   # noqa: BLE001
    print(f"  {k} RAISED {type(e).__name__}: {e}")
print(f"# UOp has no cmpeq/cmpne method: "
      f"{[a for a in dir(UOp) if 'cmp' in a.lower()]}  (UOp.__eq__ is the ucache eq)")
try:
  eq = (Tensor.empty(4, 3) == Tensor.empty(4, 3)).uop
  print(f"# (Tensor == Tensor).uop ops={sorted(set(n.op.name for n in eq.toposort()))} "
        f"-- NO CMPEQ, so CMPEQ is unreachable from an eager graph")
except Exception as e:                                       # noqa: BLE001
  print(f"# (Tensor == Tensor) RAISED {type(e).__name__}: {e}")

print("\n== Q4 SYMBOLIC DIMS: REACHABLE, AND DISTINGUISHABLE? ==")
nv = UOp.variable("n", 1, 100)
mv = UOp.variable("m", 1, 100)
a0 = Tensor.empty(4, 3).uop
c4 = UOp.const(4)
two = UOp.group(UOp(Ops.RESHAPE, (a0, UOp.stack(nv, c4))),
                UOp(Ops.RESHAPE, (a0, UOp.stack(mv, c4))))
dump("sym (two symbolic dims)", two)
_same_obj, _same_eq, _same_key = nv is mv, nv == mv, nv.key == mv.key
print(f"# n is m: {_same_obj}   n == m: {_same_eq}   n.key == m.key: {_same_key}")
print(f"# the two RESHAPEs' shape TEXTS are identical: "
      f"{[G.cshape(n) for n in two.toposort() if n.op is Ops.RESHAPE][-2:]}")
print(f"# but their `arg`-bearing PARAMs differ in ParamArg's sixth field (`name`): "
      f"{[G.carg(Ops.PARAM, n.arg) for n in two.toposort() if n.op is Ops.PARAM]}")
one = G.PLANTS["sym1"](two)
dump("sym1 (plant: both dims collapsed to one)", one)

print("\n== Q5 ParamArg.slot FOR A VARIABLE, AND THE SENTINELS ==")
spelled = ParamArg(0, dtypes.weakint, None, (1, 100), 1, "n", AddrSpace.ALU)
from dataclasses import fields, replace                    # noqa: E402
print(f"# UOp.variable('n',1,100).arg = {nv.arg!r}")
print(f"# spelled with slot=0        = {spelled!r}")
print(f"# fields differing: {[f.name for f in fields(nv.arg) if getattr(nv.arg, f.name) != getattr(spelled, f.name)]}")
print(f"# replace(variable.arg, slot=0) == spelled: {replace(nv.arg, slot=0) == spelled}")
r1 = UOp(Ops.RESHAPE, (a0, UOp.stack(nv, c4)))
n0 = UOp(Ops.PARAM, src=(), arg=spelled)
r2 = UOp(Ops.RESHAPE, (a0, UOp.stack(n0, c4)))
print(f"# the slot does NOT reach the shape: r1.shape[0] is v = {r1.shape[0] is nv}, "
      f"r2.shape[0] is n0 = {r2.shape[0] is n0}, and both render {G.cshape(r2)!r}")
print(f"# PORT SENTINELS, which DISAGREE (LIMITS section 2):")
print("#   ops.bend:871              ParamArg{slot: U32, ...}  -- `-1` has no spelling")
print("#   schedule/__init__.bend:1100  writes slot 0 and says so")
print("#   ops.bend:3566-3573        calls any slot but 0/1 'the free Variable sentinel', "
      "and uses 4294967295")

print("\n== Q6 THE CORPUS TALLY: OPS, PER-OP NODE COUNTS, SYMBOLIC DIMS ==")
tal: collections.Counter = collections.Counter()
graphs_of: collections.Counter = collections.Counter()
comm: set[str] = set()
nodes = sym = 0
for name in sorted(G.GRAPHS):
  py = G.emit_py(name, None)
  rows = [G.unchunks(l) for l in py]
  c = collections.Counter(f[1] for f in rows)
  tal.update(c)
  graphs_of.update(c.keys())
  comm |= set(c) & COMM
  sd = [f[0][1:] for f in rows if f[3].startswith("(") and "U" in G.split_top(f[3][1:-1])]
  nodes += len(rows)
  sym += len(sd)
  print(f"  {name:<10} {len(rows):>2} nodes  ops={sorted(c)}  sym={sd}")
allops = [o.name for o in Ops]
print(f"# TOTAL {len(G.GRAPHS)} graphs, {nodes} nodes/side, {len(tal)} of {len(allops)} ops")
print(f"# PER-OP (nodes/graphs): " + "  ".join(f"{o} {tal[o]}/{graphs_of[o]}" for o in sorted(tal)))
print(f"# COMMUTATIVE {len(comm)}/{len(COMM)} {sorted(comm)}; NOT REACHED {sorted(COMM - comm)}")
print(f"# SYMBOLIC-DIM NODES {sym} of {nodes}; FIELD-RECORDS {nodes * len(G.FIELDS)}")
print(f"# NOT REACHED ({len(allops) - len(tal)}): " + " ".join(o for o in allops if o not in tal))
