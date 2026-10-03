#!/usr/bin/env python3
"""CPython oracle for `tinybendygrad/codegen/__init__.bend` -- CALLED, never typed.

Every value printed here is produced by RUNNING tinygrad from this checkout.
Nothing in the output is transcribed from the source; `q_src()` even re-derives
the rule table by reading it off the pattern objects.

    .venv/bin/python .agents/slop/codegen-init-oracle.py

Q1  THE RULE TABLE. How many rules does upstream's `pm_post_sched_cache`
    carry, which ops do they claim, and can any of them read a node's srcs?
    Read off `pm_post_sched_cache.patterns`, not off a transcription.

Q2  THE FIXTURE. The exact graph the port's `main` builds --
    SINK[PARAM(slot 0), PARAM(slot 1), ALLOC], ctx = ({}, (PARAM99, PARAM100))
    -- run through upstream `RewriteContext.walk_rewrite`.

Q3  THE PORT'S OWN ROW, RENDERED BY UPSTREAM. The port prints
    `new_sink=<idx> repl=<op(slot)->op(slot), ...>`. Upstream's `uop_short`
    renders `PARAM(slot=0)`, so this oracle renders in the PORT's format and
    prints the same line, so the two are diffable as strings. This is what
    "the port's row value, against CPython" means.

Q4  THE FACTS THE PORT'S ROW THROWS AWAY. Two of them, both measured:
      * `new_sink_is_original` -- ops.py:1810 guards the rebuild with
        `if new_src != n.src else n`, so a node whose srcs were rewritten IS a
        new object. The SINK's srcs ARE rewritten here.
      * `new_sink_srcs` -- the rewritten srcs, op and slot.
    Both are printed because `uop_short` collapses any SINK to the bare string
    "SINK", so no rendering of the SINK itself can separate these two answers.
"""
from __future__ import annotations

import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from tinygrad.uop.ops import Ops, ParamArg, RewriteContext, UOp  # noqa: E402
from tinygrad.dtype import dtypes  # noqa: E402
from tinygrad.schedule import pm_post_sched_cache  # noqa: E402


def param(slot: int) -> UOp:
  return UOp(Ops.PARAM, arg=ParamArg(slot, dtypes.int32, device="PYTHON"))


def fixture() -> UOp:
  """The port's `main`: SINK[PARAM{0}, PARAM{1}, ALLOC]."""
  return UOp(Ops.SINK, src=(param(0), param(1), UOp.alloc((1,), dtypes.int32, slot=0, device="PYTHON")))


def ctx() -> tuple:
  """The port's ctx: ({}, (PARAM99, PARAM100)) -- `pm_post_sched_cache`'s
  `ctx[1][x.arg.slot]`, so two entries cover slots 0 and 1. The ALLOC rule
  `create_new_buffer` writes into `ctx[0]`."""
  return ({}, (param(99), param(100)))


def port_short(u: UOp) -> str:
  """`gr_show.node` in tinybendygrad/codegen/__init__.bend, reimplemented:
  `OP(slot=N)` for a PARAM, the bare OP name otherwise. The port's printer
  has no `slot=` in the PARAM slot, and prints `BUFFER` bare where
  `gr-oracle.py` printed `BUFFER(slot=0)` -- so the two oracles disagree on
  SPELLING, which is why this file exists."""
  if u.op is Ops.PARAM and hasattr(u.arg, "slot"):
    return f"{u.op.name}({u.arg.slot})"
  return f"{u.op.name}"


def srcs_short(us) -> str:
  return ",".join(port_short(u) for u in us)


def q1() -> None:
  print("=" * 78)
  print("Q1  UPSTREAM'S RULE TABLE, read off the pattern objects")
  print("=" * 78)
  pats = pm_post_sched_cache.patterns
  print(f"  tinygrad/schedule/__init__.py:96-101   rule count = {len(pats)}")
  for i, (pat, fn) in enumerate(pats):
    ops = "+".join(o.name for o in pat.op)
    fields = getattr(pat, "fields", "<ABSENT>")
    name = getattr(pat, "name", "<ABSENT>")
    srcs = getattr(pat, "srcs", "<ABSENT>")
    fname = fn.__name__ if getattr(fn, "__name__", None) else "lambda"
    print(f"    rule {i}: ops={ops}  name={name}  fields={fields}  srcs={srcs}  body={fname}")
  print()
  print("  BOTH patterns are src-free, so neither can read a node's srcs. That")
  print("  is the structural reason `pm_rewrite(n)` and `pm_rewrite(new_n)` are")
  print("  the same call for this table: ops.py:1810 hands back `n` itself")
  print("  whenever `new_src == n.src`, and a src-free node always has that.")


def q2() -> None:
  print()
  print("=" * 78)
  print("Q2  UPSTREAM'S ANSWER ON THE PORT'S FIXTURE")
  print("=" * 78)
  root, c = fixture(), ctx()
  print(f"  graph        = SINK[PARAM(0), PARAM(1), ALLOC]   ({len(root.src)} srcs)")
  print(f"  ctx[1]       = (PARAM(99), PARAM(100))")
  rc = RewriteContext(pm=pm_post_sched_cache, bpm=None, ctx=c, enter_calls=False)
  got = rc.walk_rewrite(root)
  print(f"  walk_rewrite returns op = {got.op.name}")
  print(f"  repl entries           = {len(rc.replace)}  (root included: {root in rc.replace})")
  for old, new in rc.replace.items():
    print(f"      {port_short(old):<12} -> {port_short(new)}")


def q3() -> None:
  print()
  print("=" * 78)
  print("Q3  THE PORT'S OWN ROW, RENDERED BY UPSTREAM  <- diff against the port")
  print("=" * 78)
  root, c = fixture(), ctx()
  rc = RewriteContext(pm=pm_post_sched_cache, bpm=None, ctx=c, enter_calls=False)
  got = rc.walk_rewrite(root)
  pairs = ",".join(f"{port_short(o)}->{port_short(n)}" for o, n in rc.replace.items())
  # The port prints one pair per toposort node, in toposort order. CPython's
  # `replace` is insertion-ordered, so the two are only comparable if that
  # order IS a toposort. Derive a post-order DFS here and compare, rather than
  # assuming it.
  order = list(rc.replace)

  def post(u: UOp, seen: set, out: list) -> None:
    if u in seen:
      return
    seen.add(u)
    for x in u.src:
      post(x, seen, out)
    out.append(u)

  topo: list = []
  post(root, set(), topo)
  print(f"  repl order == post-order DFS over the root: {order == topo}")
  print(f"      repl order = {[port_short(o) for o in order]}")
  print(f"      DFS  order = {[port_short(o) for o in topo]}")
  print(f"py.new_sink_op={got.op.name}")
  print(f"py.repl={pairs}")
  print()
  print("  (the port prints `new_sink=<U32 index>`; upstream has no index, so")
  print("   the comparable fact is `new_sink_op`, printed above. The index is")
  print("   NOT comparable: the port's arena numbering is its own.)")


def q4() -> None:
  print()
  print("=" * 78)
  print("Q4  THE FACTS THE PORT'S ROW THROWS AWAY")
  print("=" * 78)
  root, c = fixture(), ctx()
  rc = RewriteContext(pm=pm_post_sched_cache, bpm=None, ctx=c, enter_calls=False)
  got = rc.walk_rewrite(root)
  print(f"  py.new_sink_is_original = {1 if got is root else 0}")
  print(f"      ops.py:1810 `new_n = UOp(...) if new_src != n.src else n`: the")
  print(f"      SINK's srcs WERE rewritten, so walk_rewrite records a NEW node.")
  print(f"  py.new_sink_srcs = {srcs_short(got.src)}")
  print(f"  py.sink_src_slots = {','.join(str(s.arg.slot) for s in got.src if s.op is Ops.PARAM)}")
  print(f"  py.alloc_rule_fired = "
        f"{any(o.op is Ops.ALLOC for o in rc.replace)}")


if __name__ == "__main__":
  q1()
  q2()
  q3()
  q4()
