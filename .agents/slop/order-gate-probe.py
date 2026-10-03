#!/usr/bin/env python3
"""D5 -- WHY `gt_ops0..5` CANNOT DISTINGUISH, AND WHAT CAN.

`gt_ops{k}` prints `pat.op` -- the ROOT op of the k-th pattern of
`pm_move_gates_from_index`. Measured: LOAD STORE LOAD STORE WHERE WHERE, so
three sibling pairs tie. The census called this DANGEROUS and its report asked
for "the two WHERE rows to have different content, or to be folded into one row
so the blindness is declared rather than implied."

BEFORE choosing, MEASURE whether the pairs are distinguishable AT ALL, and by
which part of the pattern. `UPat`'s `src` is not a flat list: `x.load(a, b)`
stores `(x, (a,), (b,))`, so it is a TUPLE OF GROUPS, a group is a TUPLE of
UPats or a plain NAME string for `UPat.var()`, and `None` is `allow_any_len`.
That shape is what makes the discrimination possible, and the first version of
this probe assumed a flat list and measured "nothing distinguishes anything",
which would have been a false zero.

    DEV=NULL .venv/bin/python .agents/slop/order-gate-probe.py
"""
import sys

sys.path.insert(0, '.')

from tinygrad.uop.ops import UPat
from tinygrad.codegen.late.gater import pm_move_gates_from_index


def ops_of(op):
  if isinstance(op, tuple):
    return "|".join(sorted(o.name for o in op))
  return "*" if op is None else op.name


def walk(p, out):
  """ONE canonical, order-bearing rendering of a whole pattern.

  Every difference the six patterns actually have is a difference in this
  string: the op SET at each node (`|`-joined, so `{INDEX, SHRINK}` is one
  token and not two), the NAME of a `UPat.var()` slot versus the op set of a
  structural slot, and the POSITION of every slot.
  """
  if isinstance(p, str):
    out.append("var:" + p)
    return
  if isinstance(p, UPat):
    out.append("op:" + ops_of(p.op))
    if p.name:
      out[-1] += "/named:" + p.name
    walk(p.src, out)
    return
  if p is None:
    out.append("any")
    return
  for g in p:
    out.append("grp")
    walk(g, out)


def shape(p):
  out = []
  walk(p, out)
  return " ".join(out)


print("=== the six, as the census's `gt_ops` prints them")
for k, (pat, _fn) in enumerate(pm_move_gates_from_index.patterns):
  print(f"  gt_ops{k}={ops_of(pat.op)}")

print()
print("=== the six, as `gt_shape` would print them")
shapes = {}
for k, (pat, _fn) in enumerate(pm_move_gates_from_index.patterns):
  s = shape(pat)
  shapes[k] = s
  print(f"  gt_shape{k}={s}")

print()
pairs = [(0, 2), (1, 3), (4, 5)]
print("=== the three sibling pairs the census flagged")
for i, j in pairs:
  print(f"  ({i},{j}): gt_ops {'TIE' if ops_of(pm_move_gates_from_index.patterns[i][0].op) == ops_of(pm_move_gates_from_index.patterns[j][0].op) else 'differ'}"
        f"   gt_shape {'TIE' if shapes[i] == shapes[j] else 'DIFFER'}")
  if shapes[i] != shapes[j]:
    a, b = shapes[i].split(" "), shapes[j].split(" ")
    d = [(x, y) for x, y in zip(a, b) if x != y]
    print(f"      first difference at token {d[0][0] == '' and 0 or [n for n,(x,y) in enumerate(zip(a,b)) if x!=y][0]}: "
          f"{[ (n, a[n], b[n]) for n in range(min(len(a),len(b))) if a[n]!=b[n] ][:2]}")

print()
allv = list(shapes.values())
print(f"distinct gt_ops values : {len({ops_of(p[0].op) for p in pm_move_gates_from_index.patterns})} of 6")
print(f"distinct gt_shape values: {len(set(allv))} of 6")
# blind_swaps on the shape string, by the census's own definition.
import re
from collections import defaultdict
for k, s in shapes.items():
  t = [x for x in re.split(r"[,\s|]+", s) if x]
  n = defaultdict(int)
  for x in t:
    n[x] += 1
  b = sum(c * (c - 1) // 2 for c in n.values())
  print(f"  blind_swaps(gt_shape{k}) = {b}")
