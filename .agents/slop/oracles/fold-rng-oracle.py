#!/usr/bin/env python
# fold-rng-oracle.py -- the CPython oracle for the RANGES rows of
# tinybendygrad/uop/fold.bend (`UOp._ranges`, ops.py:483, and `UOp.ranges`, ops.py:497).
#
# THE CONTRACT. One row per fixture:
#
#     rg_<tag> ranges=[R(0),R(1)]
#
# `R(<axis>)` is one live RANGE, printed by the ints of its innermost `axis_id` and NOT
# by an arena index: CPython's UOps are numbered by a different interning order, so a
# number neither lane means the same thing by. A fixture therefore gives every RANGE its
# own axis, which is what real tinygrad does, and a row is a SET CHECKED FOR ORDER --
# `dict` insertion order, which is the fold's list order.
#
# `axis_id` is `arg[1:]` (ops.py:502), so CPython's is `((0,),)` for a flat arg and the
# arena's `ARange{ids}` is `[0]`: the NESTING is `Arena.depth` and is ops.bend's recorded
# wall, so the label reads the innermost tuple on one side and the ids on the other. Both
# print `0` for the same range and the row is about the SET, not about the depth.
#
# `ABSENT` is the fold's "this fold cannot answer this node" (see the file's header),
# and it is where CPython and the fold DISAGREE by design: `ended_ranges` is a `Derived`
# field, so a node the dtype/shape ladder does not answer (UNSHARD, STAGE, CUSTOM,
# CUSTOMI) has no `ended` list to subtract with. Every such node is named below.
#
#     .venv/bin/python .agents/slop/oracles/fold-rng-oracle.py > $OUT/py.txt
#     ./bin/bend tinybendygrad/uop/fold.bend                    > $OUT/bend.txt
#     diff <(grep '^rg_' $OUT/py.txt) <(grep '^rg_' $OUT/bend.txt)
import sys
sys.path.insert(0, '.')
from tinygrad.uop.ops import UOp, Ops  # noqa: E402
from tinygrad.uop.spec import AxisType  # noqa: E402
from tinygrad import dtypes  # noqa: E402

DIV = {}


def lab(r):
  return "R(" + ",".join(str(x) for x in r.axis_id[-1]) + ")"


def row(tag, u):
  print(f"rg_{tag} ranges=[{','.join(lab(r) for r in u.ranges)}]")
  return u


def no(tag, u, why):
  DIV[tag] = why
  print(f"rg_{tag} ranges=ABSENT")


def rng(end, axis):
  return UOp.range(end, (axis,), AxisType.LOOP)


def cst(n):
  return UOp.const(n)


def st(*xs):
  return UOp(Ops.STACK, xs)


# 1. NO RANGE ANYWHERE. `ranges` is empty, and the fold's empty is the same empty the
#    `Range <~> None` arms produce -- this row says the fold is not answering `Nil`
#    for everything.
row("none", cst(4))

# 2. A RANGE ASKS FOR ITSELF. `if self.op is Ops.RANGE: return {self:None} | _ranges`
#    is a PREPEND, and the only way to see a prepend is a root that IS a RANGE.
row("self", rng(4, 0))

r0, r1, r2 = rng(4, 0), rng(4, 1), rng(8, 2)

# 3/4. THE UNION, IN BOTH SRC ORDERS. `for s in self.src: ret.update(s.ranges)` is an
#      ORDER-SENSITIVE union -- `dict.update` keeps a key's first position -- so the
#      same two ranges in two orders are two different rows and one of them moving is
#      the whole test. A SET that forgets its order cannot tell them apart.
row("two", st(r0, r1))
row("rev", st(r1, r0))

# 5. THE SAME RANGE TWICE. `ADD(r0, r0)` names it twice, so a multiset answer prints it
#    twice and CPython's `dict` prints it once. This is the "membership where the count
#    is wanted" family from bend2-constraints.md, on the SET side.
row("dup", UOp(Ops.ADD, (r0, r0)))

# 6. `END`'s OWN ARM, and it is NOT `range_start[END]`: `tuple(r for r in src[1:] if
#    r.op is Ops.RANGE)`. Two of the three ranges end, one survives, and the survivor
#    is the one at src[0] -- so a row that pops src[0] as well answers `[]`.
row("end", UOp(Ops.END, (r0, r1, r2)))

# 7. `AFTER`'s ARM IS THE FLATTEN, not `src[1:]`: `tuple(flatten([x.ended_ranges for x
#    in self.src[1:]]))`. The END it names is at src[1], so its `r1` ends here -- and a
#    reading of `src[1:]` as the delete list would end `r1` twice and `r0` not at all.
row("after", UOp(Ops.AFTER, (cst(4), UOp(Ops.END, (r0, r1)))))

# 8. `BARRIER` FLATTENS OVER *ALL* ITS SRCS, so a range that arrives twice (once under
#    the END and once on its own) is popped once and the OTHER survivor stays -- and it
#    stays in union order. The partial pop is the row.
row("barrier", UOp(Ops.BARRIER, (UOp(Ops.END, (r0, r1)), r2)))

# 9. THE `else` BRANCH OF THE POP, and the one that needs `er.ranges`. `BACKEDGE`'s
#    ended list is `src[1:2]`, so the STACK at src[1] is the `er` -- and `er` is NOT a
#    RANGE, so the delete set is `STACK(r1).ranges` = {R(1)}, not {STACK}. `r0` at
#    src[0] is the `self`, and it does NOT end: this row is also the `src[1:2]`
#    off-by-one that bend2-constraints.md already flagged for `ended_ranges`.
row("er", UOp(Ops.BACKEDGE, (r0, st(r1), cst(4))))

# 10/11. `CALL`'s ONE CONDITIONAL. `if self.op is Ops.CALL and self.body.op is
#       Ops.CUSTOM_FUNCTION: return ()`, else `src[1:]`. Two rows one condition apart:
#       the CUSTOM_FUNCTION body ends nothing, a CONST body ends both ranges.
#       The CallInfo dtype is NON-VOID on purpose: `call_ds.go` is
#       `some_if(not dt is void, ...)`, so a void CALL is a node the dtype/shape ladder
#       does not answer and its `ended` list is not in the table. Measured on both
#       lanes: with a void arg both rows read ABSENT here, and the point of the two rows
#       is `ended_of.call`'s conditional rather than that refusal.
cf = UOp(Ops.CUSTOM_FUNCTION, (), ("myext", dtypes.void))
row("call_cf", UOp(Ops.CALL, (cf, r0, r1), (None, False, False, dtypes.int32)))
row("call_c", UOp(Ops.CALL, (cst(4), r0, r1), (None, False, False, dtypes.int32)))

# 12. THE REFUSAL. `STAGE` is one of the four ops `dt_shape` does not answer, so its
#     `ended` list is not in the fold's table and the whole set is not answered.
#     CPython has no such limit -- it answers `[R(0)]` -- and the disagreement is
#     recorded here rather than smoothed into an agreeing row.
no("absent", UOp(Ops.STAGE, (cst(4), st(r0))),
   "`STAGE` is a DEFERRED op in `dt_shape`, so `ended_ranges` is not in the table; "
   "CPython answers [R(0)]")

print()
print("== WHAT CPython ANSWERS WHERE THE FOLD REFUSES ==")
for tag, why in DIV.items():
  print(f"  rg_{tag}: {why}")
