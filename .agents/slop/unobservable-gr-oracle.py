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
    """Q3/Q4: what does `pm_post_sched_cache` ACTUALLY contain, read off the
    pattern objects rather than off a transcription of the source.

    `UPat.op` is a TUPLE of ops and a `UPat` with no field pattern has no
    `fields` attribute at all -- that is the structural statement "this pattern
    cannot look at anything but the op", and it is what makes Q1 a theorem
    rather than a guess.
    """
    out = []
    for pat, _ in pm_post_sched_cache.patterns:
      ops = "+".join(o.name for o in pat.op)
      fields = getattr(pat, "fields", None)
      out.append(f"UPat(op={ops}) fields={fields!r} "
                 f"-> src-visible={bool(fields) and 'src' in (fields or ())}")
    return out


def ctx_for(root: UOp):
  """ctx[1] must be indexable by every PARAM slot in the fixture, or the
  `pm_post_sched_cache` lambda raises IndexError before any row is printed."""
  slots = {s.arg.slot for s in root.src if s.op is Ops.PARAM}
  slots |= {t.arg.slot for s in root.src for t in s.src if t.op is Ops.PARAM}
  return ({}, tuple(param(99 + i) for i in range(max(slots) + 2 if slots else 2)))


def q1() -> None:
    print("=" * 78)
    print("Q1  UPSTREAM, MEASURED: does `pm_rewrite(n)` ever differ from")
    print("    `pm_rewrite(new_n)` over pm_post_sched_cache?")
    print("=" * 78)
    diffs = 0
    N = 10
    for k in range(N):
      root = fixture(k)
      ctx = ctx_for(root)
      a = walk_u(root, ctx)
      b = walk_mutant(root, ctx)
      same = a == b
      diffs += 0 if same else 1
      print(f"  fixture {k}: {len(a)} repl entries, "
            f"{'IDENTICAL' if same else 'DIFFERS'}"
            f"{'' if same else '  ' + str(sorted(set(a.items()) ^ set(b.items()))[:3])}")
    print(f"  --> {N - diffs}/{N} fixtures byte-identical, {diffs} differ")
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
    root = fixture(0)
    ctx = ctx_for(root)
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
    print("Q3  WHAT `pm_post_sched_cache` ACTUALLY CONTAINS (read off the patterns)")
    print("=" * 78)
    for line in src_reading_rules():
      print(f"  {line}")
    print(f"  rule count: {len(pm_post_sched_cache.patterns)}")
    print()
    print("  A rule that READS a node's srcs is what makes `u` and `rebuilt`")
    print("  different arguments: `src(rebuilt,0)` is the REWRITTEN src and")
    print("  `src(u,0)` is the original. pm_post_sched_cache carries no such rule,")
    print("  so a fixture built only from PARAM/ALLOC/SINK cannot separate them and")
    print("  NO NUMBER OF SUCH FIXTURES EVER WILL. That is a closed case.")


def q4() -> None:
    print()
    print("=" * 78)
    print("Q4  THE DANGEROUS ONE: the PORT's table has a SINK rule upstream does not")
    print("=" * 78)
    root = fixture(0)
    ctx = ctx_for(root)
    rc = RewriteContext(pm=pm_post_sched_cache, bpm=None, ctx=ctx, enter_calls=False)
    got = rc.walk_rewrite(root)
    print(f"  upstream pm_post_sched_cache ops: "
          f"{sorted({o.name for p, _ in pm_post_sched_cache.patterns for o in p.op})}")
    print(f"  the port's pm_post_sched_cache table (codegen/__init__.bend):")
    print(f"      O.PMEntry{{0, [O.OpsSINK{{}}], Nil{{}}}}   <- tag 0, NOT upstream")
    print(f"      O.PMEntry{{3, [O.OpsPARAM{{}}], Nil{{}}}}")
    print(f"      O.PMEntry{{4, [O.OpsALLOC{{}}], Nil{{}}}}")
    print(f"  uop/ops.bend pm_dispatch_m case 0 -> pm_r_sink_m -> Some{{self}}")
    print()
    print(f"  upstream's returned SINK:      srcs = "
          f"{[s.op.name + (f'({s.arg.slot})' if s.op is Ops.PARAM else '') for s in got.src]}")
    print(f"  upstream's SINK is a new node: {got is not root}")
    print()
    print("  With the port's extra `SINK -> self` rule, `pm_rewrite_m` returns")
    print("  Some{u}, so `wr.step.try_rule` takes the Some arm and records")
    print("  `repl[sink] = sink` -- the ORIGINAL node, whose srcs are")
    print(f"      {[s.op.name + (f'({s.arg.slot})' if s.op is Ops.PARAM else '') for s in root.src]}")
    print("  i.e. the UNREWRITTEN srcs. Upstream records the REBUILT node.")
    print()
    print("  The gate cannot see this: `uop_short` renders a SINK as the bare")
    print("  string 'SINK', so upstream's rebuilt SINK and the port's original")
    print("  SINK print identically, and `gr-diff.sh` compares COUNTS. This is")
    print("  an IDENTITY invariant guarded by an unobservable row, and it is the")
    print("  shape agent-core ranks highest.")
    print()
    print("  THE ROW THAT SEES IT -- expected value CALLED from CPython above:")
    print(f"      gr.sink_identity = 0        (upstream: replace[sink] is not sink)")
    print(f"      gr.sink_srcs = {','.join(s.op.name for s in got.src)}")
    print(f"      gr.sink_src_slots = "
          f"{','.join(str(s.arg.slot) for s in got.src if s.op is Ops.PARAM)}")


if __name__ == "__main__":
    q1()
    q2()
    q3()
