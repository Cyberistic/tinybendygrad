#!/usr/bin/env python3
"""CPython oracle for `resolve_returned_after` (tinygrad/uop/ops.py:1899).

    .venv/bin/python .agents/slop/ops-rra-oracle.py

Eight rows over one arena. Every node is built with the real `UOp` constructor and
every row CALLS the real `resolve_returned_after`, so the diff against the port is a
comparison of two implementations rather than two readings of the same comment.

THE ARENA ORDER IS THE CONTRACT, and the port's copy of it says why in the same
words: CPython's test is `st.src[0].unsharded_base is r.unsharded_base`, so a store
only matches when its TARGET peels to `r`, and every target must therefore be
declared before the store that writes it. An arena that violates that answers `None`
for every row -- on both sides, which is how a gate can be green and meaningless.

The first draft of the port's arena put the AFTERs after the stores and got `none` on
all seven. The filter was right and the FIXTURE was wrong. That is worth a row per
conjunct rather than one row per def: seven of these eight rows exist so that no
single conjunct can be dropped without one of them moving.
"""
import sys

from tinygrad.uop.ops import Ops, UOp, resolve_returned_after
from tinygrad.uop.spec import AxisType  # noqa: F401  (parity with the port's imports)

# 1 CONST 7 | 2 CONST 9 | 3 BUFFER | 4 AFTER[3] | 5 PARAM | 6 STORE[4,1]
# 7 SINK[6] | 8 STORE[4,2] | 9 SINK[6,8] | 10 SINK[1] | 11 SINK[] | 12 SINK[6,1]
# 13 STORE[5,1] | 14 SINK[13] | 15 UNSHARD[3] | 16 STORE[3,1] | 17 SINK[16]
C7 = UOp(Ops.CONST, (), 7, AxisType.LOOP)
C9 = UOp(Ops.CONST, (), 9, AxisType.LOOP)
BUF = UOp(Ops.BUFFER, ())
R_VAL = UOp(Ops.AFTER, (BUF,))
R_PARAM = UOp(Ops.PARAM, ())
STORE_VAL = UOp(Ops.STORE, (R_VAL, C7))
SINK_ONE = UOp(Ops.SINK, (STORE_VAL,))
STORE_OTHER = UOp(Ops.STORE, (R_VAL, C9))
SINK_TWO = UOp(Ops.SINK, (STORE_VAL, STORE_OTHER))
SINK_NONSTORE = UOp(Ops.SINK, (C7,))
SINK_EMPTY = UOp(Ops.SINK, ())
SINK_MIXED = UOp(Ops.SINK, (STORE_VAL, C7))
STORE_PARAM = UOp(Ops.STORE, (R_PARAM, C7))
SINK_PARAM = UOp(Ops.SINK, (STORE_PARAM,))
R_UNSHARD = UOp(Ops.UNSHARD, (BUF,), ((0,),))
STORE_UNSHARD = UOp(Ops.STORE, (BUF, C7))
SINK_UNSHARD = UOp(Ops.SINK, (STORE_UNSHARD,))
# 18 RESHAPE[3] -- NOT a STORE, and its base IS r_unshard's base, because RESHAPE is
# in GroupOp.movement so unsharded_base(RESHAPE(BUF)) == BUF.
# 19 SINK[16,18] -- the store AND that reshape: the only sink where the op test and the
# base test disagree, and therefore the only row that can see `op is Ops.STORE`.
RESHAPE_BUF = UOp(Ops.RESHAPE, (BUF,))
SINK_SAMEBASE = UOp(Ops.SINK, (STORE_UNSHARD, RESHAPE_BUF))

NODES = 19


def show(x):
  """`some:Ops.NAME` or a bare `none`.

  A bare `none`, not `none:AttributeError`: this def's `None` is CPython's own
  `return None` for `len(stores) != 1`, which is a VALUE and not a raise. The
  `none:<ExceptionName>` spelling is for arms where CPython raises, and using it here
  would make a row satisfiable by a port that invented a refusal.
  """
  return "none" if x is None else f"some:Ops.{x.op.name}"


def row(nm, value):
  print(f"{nm}={value}")


def count(r, t):
  """The arena size AFTER the call, which is how many nodes the answer minted.

  `UOp.new` appends, so `len(ucache)` grows by one per mint. `resolve_returned_after`
  mints in exactly one of its two arms -- the PARAM one builds `r.after(store)` -- so
  this is the row that says the mint HAPPENED. A def that returned the store's src
  instead, or skipped the AFTER, answers the other seven rows identically.
  """
  from tinygrad.uop.ops import UOpMetaClass
  before = len(UOpMetaClass.ucache)
  out = resolve_returned_after(r, t)
  return f"{len(UOpMetaClass.ucache) - before}" if out is not None else "none"


def main():
  # rra_val: one match, r's base is an AFTER -> the `stores[0].src[1]` arm.
  row("rra_val", show(resolve_returned_after(R_VAL, SINK_ONE)))
  # rra_param: one match, r IS a PARAM -> the `r.after(stores[0])` arm, which MINTS.
  # It is the ONLY row whose answer op is AFTER, so it is the only row that can see
  # which of the two arms ran.
  row("rra_param", show(resolve_returned_after(R_PARAM, SINK_PARAM)))
  # rra_unshard: `r` is an UNSHARD, and UNSHARD is the one op where `base` and
  # `unsharded_base` differ. The store's target is the BUFFER, which peels to r's
  # base. A def that used `UOp.base` instead finds no match and answers `none`.
  row("rra_unshard", show(resolve_returned_after(R_UNSHARD, SINK_UNSHARD)))
  # rra_none_zero: the sink's only src is a CONST, so the `op is Ops.STORE` filter
  # drops it. A def with no op test would count it and answer `some:Ops.CONST`.
  row("rra_none_zero", show(resolve_returned_after(R_VAL, SINK_NONSTORE)))
  # rra_none_two: two stores to the SAME r, so both pass the filter and `!= 1`
  # refuses. A def that returned the first match answers `some:Ops.CONST` here and
  # passes every other row, because in all of them there is exactly one match.
  row("rra_none_two", show(resolve_returned_after(R_VAL, SINK_TWO)))
  # rra_none_empty: the sink has no srcs at all -- the ONLY row that reaches the
  # filter's `Nil{}` arm, so a filter written without it is invisible elsewhere.
  row("rra_none_empty", show(resolve_returned_after(R_VAL, SINK_EMPTY)))
  # rra_mixed: one store AND a CONST. Same sink shape as rra_none_two but the second
  # src is filtered out, so the answer is `some` where rra_none_two is `none`. The
  # pair is what says the STORE test is load-bearing: without it both are `none`.
  row("rra_mixed", show(resolve_returned_after(R_VAL, SINK_MIXED)))
  # rra_samebase: two candidates whose bases are EQUAL, so only the op test separates
  # them. Without this row the op-test mutation moves NOTHING, which is what the
  # mutation table measured on the first draft.
  row("rra_samebase", show(resolve_returned_after(R_UNSHARD, SINK_SAMEBASE)))
  row("rra_arena", count(R_PARAM, SINK_PARAM))
  assert NODES == 19, "the arena grew; every index above is a comment that moved"
  return 0


if __name__ == "__main__":
  sys.exit(main())
