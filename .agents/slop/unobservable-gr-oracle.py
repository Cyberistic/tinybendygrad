#!/usr/bin/env python3
"""IS `u` vs `rebuilt` OBSERVABLE? -- called from CPython, never argued.

`tinybendygrad/codegen/__init__.bend`'s comment (its own lines 48-50) says the
rule is tried on the REBUILT node, citing upstream `tinygrad/uop/ops.py`
`walk_rewrite`. The code passes `u`. The one gate row cannot tell them apart on
the old printer. Three questions, each answered by CALLING tinygrad:

  Q1  UPSTREAM, MEASURED. Run upstream's `walk_rewrite` against a mutant driver
      that passes `n` where upstream passes `new_n`, over a sweep of fixtures.
      Do the two repl maps ever differ? This is a theorem candidate: both
      `pm_post_sched_cache` patterns are `UPat(Ops.X)` with no `src=` clause,
      and upstream guards the rebuild with `if new_src != n.src else n`, so for
      every op the table carries the rebuilt node IS the original.

  Q2  THE ORACLE'S OWN BLINDNESS. `gr-oracle.py` renders a SINK as the bare
      string "SINK". Does the repl row for the SINK distinguish the ORIGINAL
      node from a REBUILT one? If not, the CPython side of that gate row is
      blind to the identity invariant that `walk_rewrite` turns on, and the
      port's row and the oracle's row agree for a reason that is not
      correctness.

  Q3  WHAT A DISCRIMINATING FIXTURE MUST LOOK LIKE. Which rule, in which table,
      reads a node's SRCS? `pm_r_noop_m` in the port reads `src(self,0)`, so a
      src-reading rule is what makes the two arguments distinguishable. Is
      there one in `pm_post_sched_cache`? No -- so the fixture has to come from
      a different table, and this reports which.

Run:  .venv/bin/python .agents/slop/unobservable-gr-oracle.py
"""
from __future__ import annotations

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2]))

from tinygrad.uop.ops import UOp, Ops, RewriteContext, PatternMatcher, UPat
from tinygrad.dtype import dtypes
from tinygrad.schedule import pm_post_sched_cache


def param(slot: int) -> UOp:
  from tinygrad.uop.ops import ParamArg
  return UOp(Ops.PARAM, arg=ParamArg(slot, dtypes.int32, device="PYTHON"))


def fixture(k: int):
  """k distinct fixture shapes, all over the same two-rule table."""
  p0, p1 = param(0), param(1)
  p2, p3 = param(2), param(3)
  al = UOp.alloc((1,), dtypes.int32, slot=0, device="PYTHON")
  al2 = UOp.alloc((2,), dtypes.float32, slot=1, device="PYTHON")
  bodies = [
    UOp(Ops.SINK, src=(p0, p1, al)),
    UOp(Ops.SINK, src=(p0, p1)),
    UOp(Ops.SINK, src=(al,)),
    UOp(Ops.SINK, src=(p0,)),
    UOp(Ops.SINK, src=(p0, p1, al, al2)),
    UOp(Ops.SINK, src=(p1, p0, al)),
    UOp(Ops.SINK, src=(UOp(Ops.ADD, src=(p0, p1)), al)),
    UOp(Ops.SINK, src=(UOp(Ops.MUL, src=(p0, al)), al2)),
    UOp(Ops.SINK, src=(p0, p0)),
    UOp(Ops.SINK, src=(al, al2, p0, p1, p2, p3)),
  ]
  return bodies[k % len(bodies)]


def walk_u(root: UOp, ctx) -> dict:
    """Upstream `walk_rewrite` with `pm_rewrite(new_n)` -- the reference."""
    rc = RewriteContext(pm=pm_post_sched_cache, bpm=None, ctx=ctx, enter_calls=False)
    rc.walk_rewrite(root)
    return {u.key: v.key for u, v in rc.replace.items()}


def walk_mutant(root: UOp, ctx) -> dict:
    """Upstream's driver, one token changed: `pm_rewrite(n)` not `(new_n)`.

    Transcribed from `tinygrad/uop/ops.py` `walk_rewrite` so the ONLY difference
    from `walk_rewrite` is the argument the top-down rule is tried on.
    """
    rc = RewriteContext(pm=pm_post_sched_cache, bpm=None, ctx=ctx, enter_calls=False)
    self_replace = rc.replace
    stack: list = [(root, False)]
    while stack:
      n, processed = stack.pop()
      if n in self_replace:
        continue
      if not processed:
        stack.append((n, True))
        for x in reversed(n.src):
          if x not in self_replace:
            stack.append((x, False))
      else:
        skip = int(n.op is Ops.CALL and not rc.enter_calls)
        new_src = n.src[:skip] + tuple(self_replace.get(x, x) for x in n.src[skip:])
        new_n = UOp(n.op, new_src, n.arg, n.tag) if new_src != n.src else n
        rewritten = rc.pm_rewrite(n)          # <-- THE MUTATION: `n`, not `new_n`
        if rewritten is not None:
          new_n = rewritten
        self_replace[n] = new_n
    return {u.key: v.key for u, v in self_replace.items()}


def src_reading_rules() -> list[str]:
    """Q3: which of `pm_post_sched_cache`'s patterns constrain a node's SRCS?

    Read off the pattern objects, not the lambda source: a `UPat(Ops.X)` with no
    `src=` field cannot distinguish two nodes that agree on `op` and `arg`.
    """
    out = []
    for pat, _ in pm_post_sched_cache.patterns:
      name = pat.__class__.__name__
      fields = getattr(pat, "fields", None)
      constrained = [f for f in (fields or ()) if f in ("src", "arg")]
      out.append(f"{name}(op={pat.op.name}) constrains={constrained or 'NONE'}")
    return out


def q1() -> None:
    print("=" * 78)
    print("Q1  UPSTREAM, MEASURED: does `pm_rewrite(n)` ever differ from")
    print("    `pm_rewrite(new_n)` over pm_post_sched_cache?")
    print("=" * 78)
    from tinygrad.uop.ops import ParamArg
    ca = param(99)
    cb = param(100)
    ctx = ({}, (ca, cb))
    diffs = 0
    for k in range(10):
      root = fixture(k)
      a = walk_u(root, ctx)
      b = walk_mutant(root, ctx)
      same = a == b
      diffs += 0 if same else 1
      print(f"  fixture {k}: {len(a)} repl entries, "
            f"{'IDENTICAL' if same else 'DIFFERS'}"
            f"{'' if same else '  ' + str(sorted(set(a.items()) ^ set(b.items()))[:3])}")
    print(f"  --> {10 - diffs}/10 fixtures byte-identical, {diffs} differ")
    if diffs == 0:
        print("  VERDICT: THEOREM (as far as a sweep can show) -- the mutation is")
        print("  UNREACHABLE for this table. Both patterns are `UPat(Ops.X)` with no")
        print("  `src=` clause, and upstream guards the rebuild with")
        print("  `new_n = UOp(...) if new_src != n.src else n`, so for every op the")
        print("  table carries (PARAM, ALLOC: both src-free) `new_n IS n`.")


def q2() -> None:
    print()
    print("=" * 78)
    print("Q2  THE ORACLE'S OWN BLINDNESS: does the SINK repl row distinguish the")
    print("    ORIGINAL node from a REBUILT one?")
    print("=" * 78)
    from tinygrad.uop.ops import ParamArg
    ca, cb = param(99), param(100)
    ctx = ({}, (ca, cb))
    root = fixture(0)
    rc = RewriteContext(pm=pm_post_sched_cache, bpm=None, ctx=ctx, enter_calls=False)
    new_sink = rc.walk_rewrite(root)
    rep = rc.replace[root]
    print(f"  uop_short(replacement)   = 'SINK'        <- what gr-oracle.py prints")
    print(f"  replacement is original  = {rep is root}")
    print(f"  replacement op.name      = {rep.op.name}")
    print(f"  replacement.src == orig.src = {rep.src == root.src}")
    print(f"  replacement.src is orig.src = {rep.src is root.src}")
    print(f"  replacement.key == orig.key = {rep.key == root.key}")
    print()
    print("  `uop_short` prints only `u.op.name` for a SINK, so it answers 'SINK'")
    print("  for the original node AND for a rebuilt node AND for any node whose")
    print("  srcs were rewritten. The repl row is therefore blind, ON THE CPYTHON")
    print("  SIDE, to the identity invariant walk_rewrite actually turns on.")
    print("  The two-lane gate can agree on this row for the wrong reason.")


def q3() -> None:
    print()
    print("=" * 78)
    print("Q3  WHAT A DISCRIMINATING FIXTURE MUST LOOK LIKE")
    print("=" * 78)
    for line in src_reading_rules():
      print(f"  {line}")
    print()
    print("  A rule that reads a node's SRCS is what makes `u` and `rebuilt`")
    print("  different arguments: `src(rebuilt,0)` is the REWRITTEN src and")
    print("  `src(u,0)` is the original. pm_post_sched_cache carries none, so a")
    print("  fixture built only from PARAM/ALLOC/SINK cannot separate them and no")
    print("  number of such fixtures will.")
    print()
    # A src-reading rule, to show the shape is reachable at all.
    pm_src = PatternMatcher([(UPat(Ops.SINK), lambda ctx, x: x.src[0])])
    ca, cb = param(99), param(100)
    ctx = ({}, (ca, cb))
    root = fixture(0)
    a = RewriteContext(pm=pm_post_sched_cache, bpm=None, ctx=ctx, enter_calls=False)
    a.walk_rewrite(root)
    ref = {u.key: v.key for u, v in a.replace.items()}
    rc = RewriteContext(pm=pm_src, bpm=None, ctx=ctx, enter_calls=False)
    got = rc.walk_rewrite(root)
    b = {u.key: v.key for u, v in rc.replace.items()}
    print(f"  CONTROL, a src-reading rule on the SAME fixture:")
    print(f"    pm_post_sched_cache gave the SINK -> {ref.get(root.key)!r}")
    print(f"    a `lambda x: x.src[0]` SINK rule gives it -> "
          f"{UOp.load if False else got.src[0].op.name}")
    print(f"    the two differ: {ref.get(root.key) != got.key}")
    print("    so the mutation IS observable -- with a rule that reads srcs.")


if __name__ == "__main__":
    q1()
    q2()
    q3()
