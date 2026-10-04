#!/usr/bin/env python3
"""multi-raw-oracle.py -- CPython's RAW answers for the fixtures behind multi.bend's
BOOLEAN rows.

WHY. `multi.bend` prints `eq(a, b)`, i.e. 1 or 0. `multi-rows.py` prints the VALUE CPython
returned. So a name both sides spell the same way cannot be compared until we know what the
port's `1` is a statement ABOUT. `bx_none` is "count == 0" on the port and "()" here -- not a
disagreement, two encodings of one fact. `pm_rev` is "index == 2" on the port and `2` here.
This file emits the VALUE, so the probe on the Bend side can be compared to it directly and a
BOOLEAN that disagrees with its own value becomes visible.

Nothing here is restated: every row is the result of CALLING the function named in the
comment, at the line cited, on the same fixture multi.bend's row uses. Run it twice.

    .venv/bin/python .agents/slop/multi-raw-oracle.py
"""
import sys
sys.path.insert(0, '.')
from tinygrad.uop.ops import broadcast_axes, _broadcast_shape, sint_to_uop, ssimplify, Ops  # noqa: F401
from tinygrad.helpers import prod


def fmt(t):
  return "(" + ", ".join(str(x) for x in t) + ("," if len(t) == 1 else "") + ")"


def main():
  out = []

  # ---- broadcast_axes, ops.py:87. The whole tuple, every element.
  BX = [("none", (2, 3), (2, 3)), ("pad", (3,), (2, 3)), ("exp", (1, 3), (2, 3)),
        ("both", (1,), (2, 3)), ("noop", (2,), (2, 3)), ("scalar", (), (2, 3)),
        ("1out", (2,), (1, 2)), ("11", (1,), (1,)), ("1_2", (1,), (2,)),
        ("rank1", (3,), (3,))]
  for nm, s, o in BX:
    out.append((f"pbx {nm}", fmt(broadcast_axes(s, o))))
  # the refusal: nleft < 0 raises RuntimeError at ops.py:88
  try:
    broadcast_axes((2, 3), (3,))
    out.append(("pbx neg", "NO-RAISE"))
  except RuntimeError:
    out.append(("pbx neg", "-"))

  # ---- tuple.index, the whole of permute_multi's `root.marg.index(ax)` (multi.py:155).
  PM = [("ppm2 id", (0, 1), 0), ("ppm2 id1", (0, 1), 1), ("ppm2 sw", (1, 0), 0),
        ("ppm2 sw1", (1, 0), 1), ("ppm3 cyc", (2, 0, 1), 1), ("ppm3 cyc0", (2, 0, 1), 0),
        ("ppm3 rev", (2, 1, 0), 2), ("ppm3 mid", (0, 2, 1), 2)]
  for nm, m, ax in PM:
    out.append((nm, str(m.index(ax))))
  # a miss is Python's ValueError from tuple.index
  try:
    (0, 1).index(7)
    out.append(("ppm2 miss", "NO-RAISE"))
  except ValueError:
    out.append(("ppm2 miss", "-"))
  try:
    tuple().index(0)
    out.append(("ppm0 empty", "NO-RAISE"))
  except ValueError:
    out.append(("ppm0 empty", "-"))

  # ---- reduce_multi, multi.py:107-123. red = ax < num_axes, rem = ax >= num_axes,
  #      off = ax - num_axes over the remaining half. Both lists IN FULL.
  RD = [("all", [(0, 0), (1, 0)], 1), ("some", [(1, 0), (2, 0)], 1),
        ("none", [(2, 0), (3, 0)], 1), ("two", [(0, 0), (1, 0)], 2),
        ("mix", [(1, 0), (4, 0)], 3), ("zero", [(0, 0), (1, 0)], 0)]
  for nm, sh, na in RD:
    red = tuple(ax for ax, _ in sh if ax < na)
    rem = tuple(ax for ax, _ in sh if ax >= na)
    off = tuple(ax - na for ax in rem)
    out.append((f"prd {nm}", f"red={fmt(red)} rem={fmt(rem)} off={fmt(off)}"))

  # ---- reshape_multi, multi.py:125-140. arg_acc starts at 1 and appends EVERY running
  #      product, so it has len(new_shape)+1 entries (ops.py:127 reads arg_acc[::-1]).
  RS = [("prs2 same", (4, 6), 4, 2), ("prs2 mid", (2, 12), 4, 2), ("prs1 tail", (24,), 4, 2),
        ("prs1 head", (24,), 1, 2), ("prs2 bad", (5, 5), 4, 2),
        ("prs3 thr", (2, 3, 4), 4, 2), ("prs3 thr1", (2, 3, 4), 24, 2)]
  for nm, new, target, cnt in RS:
    arg_acc = [1]
    for s in new:
      arg_acc.append(arg_acc[-1] * s)
    # new_ax = len(arg_acc) - arg_acc[::-1].index(target) - 1, multi.py:132
    ok = target in arg_acc
    new_ax = (len(arg_acc) - arg_acc[::-1].index(target) - 1) if ok else 0
    out.append((nm, f"acc={fmt(tuple(arg_acc))} ok={int(ok)} ax={new_ax}"))

  w = max(len(r[0]) for r in out)
  for n, v in out:
    print(f"{n.ljust(w)}  {v}")


if __name__ == "__main__":
  main()
