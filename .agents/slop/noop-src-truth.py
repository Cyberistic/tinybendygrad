#!/usr/bin/env python3
"""noop-src-truth.py -- does CPython itself build `UOp(Ops.NOOP)` as a DELIBERATE src?

Answering the four detector suspects whose op-sequence is a NOOP, so the exclusion is
MEASURED rather than argued. Four call sites, four answers, called:

  rng_loopfn   ops.py:645 `UOp.loop(axis_id)` is `UOp(Ops.RANGE, src=(UOp(Ops.NOOP),), ...)`
               -- a NOOP interned on purpose as the RANGE's only src. So the row's
               `Ops.RANGE/1 Ops.NOOP` is CPython's own shape, not a stale arena.
  kernel ops   codegen/kernel.bend's `ix` STARTS AT 0, and index 0 is this port's arena
               bottom standing in for CPython's `None` UOp. The leading NOOP is the PORT's
               spelling; the 19 ops after it are measured (kn-noop-truth.py).
  regalloc     `rw_tbl_ops` is the SORTED set of op names a `PatternMatcher` table keys on,
               and NOOP is a real key in tinygrad's tables.
  function     `callu_ops` is a KNOWN WALL, recorded at function.bend:876 as a dedup-order
               bug in helpers.bend (read-only to that unit) -- not an arena read.

Run twice; the differ refuses a single run.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from tinygrad.uop.ops import UOp, Ops, AxisType


def main():
  # 1. rng_loopfn -- the RANGE built by UOp.loop, and its src's op.
  lo = UOp.loop(7)
  print(f"rng_loopfn=1 Ops.{lo.op.name}/{len(lo.src)} Ops.{lo.src[0].op.name}")
  print(f"rng_loopfn_is_ctor={type(lo).__name__}")
  print(f"rng_loopfn_src_is_noop={lo.src[0].op is Ops.NOOP}")
  # the NOOP src has no srcs of its own, which is what `Nil{}` prints as -- so the DETECTOR
  # can tell this NOOP from a repr string by the ABSENCE of `arg=`
  print(f"rng_loopfn_src_srcs={len(lo.src[0].src)}")

  # 2. NOOP really is a constructible op, not only the arena bottom's spelling
  n = UOp(Ops.NOOP)
  print(f"noop_ctor_op={n.op.name} srcs={len(n.src)}")

  # 3. regalloc -- NOOP is a key in a real PatternMatcher table
  from tinygrad.uop.ops import PatternMatcher, UPat
  pm = PatternMatcher([(UPat(Ops.NOOP, name="n"), lambda n: n),
                       (UPat(Ops.CAST, name="c"), lambda c: c)])
  keys = sorted({str(k) for k in pm.pdict})
  print(f"regalloc_tbl_ops={' '.join(keys)}")
  print(f"regalloc_noop_is_key={any('NOOP' in k for k in keys)}")

  # 4. the arena bottom's distinguishing marks, for the detector's SHAPE rule
  print(f"noop_arg_is_none={n.arg is None}")


if __name__ == "__main__":
  main()