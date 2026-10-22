# `nn/argmax.bend` -- upstream's `Tensor.argmax` RECIPE, ported.
#
# WHAT UPSTREAM IS. `tinygrad/mixin/op.py:863-887`:
#
#     m   = self.eq(self.max(axis=axis, keepdim=True))
#     idx = m * type(self).arange(self.shape[axis], 0, -1).reshape(...)
#     return (self.shape[axis] - idx.max(axis=axis, keepdim=keepdim)).cast(dtypes.int32)
#
# `arange(n, 0, -1)` is `[n, n-1, ..., 1]`, so `idx[j]` is `n - j` where the value at
# `j` IS a maximum and `0` where it is not. `idx.max` therefore picks the LARGEST
# `n - j` among the maxima, which is the SMALLEST `j` among them -- THE FIRST
# OCCURRENCE. `n - idx.max` is that `j`. **SO THE TIE-BREAKING RULE IS A CONSEQUENCE OF
# THE FORMULA, NOT AN ASSERTION ABOUT IT** -- which is why the tie rows below can be
# checked rather than merely claimed.
#
# WHY A LIST AND NOT A TENSOR. THE PORT BUILDS UOp GRAPHS AND HAS NO EXECUTOR:
# `tinybendygrad/uop/fold.bend` answers dtype/shape/device/addr/base/ended and NOTHING
# ELSE -- THERE IS NO VALUE FOLD IN THE TREE. So a graph cannot be asked for its
# answer. What CAN be asked for an answer is the RECIPE, and upstream's recipe is a
# formula on the values along the axis.
#
# **AND THE GRAPH-LEVEL `argmax` IS REFUSED, WITH THE MEASUREMENT.** MEASURED
# 2026-10-22T07:5xZ ON THE COMMITTED TREE, `.agents/slop/nnargmax/probe.bend` ASKS FOUR
# QUESTIONS AND THE ANSWERS ARE:
#   Q1  does `nn_reduce` (nn/layers.bend) answer the keepdim MAX's shape?    **YES** (`1`)
#   Q2  does the comparison broadcast a `[4]` against a `[1]`?                **YES** (`4`)
#   Q3  does the bool dtype survive the comparison?                          **YES** (`bool`)
#   Q4  can the port produce an INDEX VECTOR along the axis -- the ONE THING
#       UPSTREAM'S RECIPE NEEDS?                                             **NO**
#   Q4 IS ASKED TWICE, ONCE THROUGH THE FOLD AND ONCE THROUGH THE MOVEMENT WALK,
#   BECAUSE `examples/beautiful_mnist.bend` RECORDS THAT THE TWO DISAGREE ON AN
#   `arange`-ROOTED NODE. **THEY AGREE HERE: BOTH READ EMPTY.** SO THE PORT CANNOT
#   PRODUCE AN `arange`, AND UPSTREAM'S GRAPH-LEVEL `argmax` IS NOT BUILDABLE UNTIL IT
#   CAN. **THE CAPABILITY THAT IS MISSING IS NAMED: A FOLD THAT ANSWERS THE SHAPE OF
#   AN INDEX VECTOR ALONG AN AXIS.** THIS FILE IS THE FORMULA, WHICH IS THE PART THAT
#   CAN BE BUILT AND CHECKED TODAY.
#
# `am_pick` IS THE MASK-TIMES-COUNTER (`idx[j]`), `am_max` IS `self.max`, AND `am_best`
# IS `idx.max`. `Bool.pick` AND NOT `match` ON A COMPUTED VALUE: `match` MAY NOT
# SCRUTINISE A CALL (BEND'S RULE 1), AND `tinybendygrad/uop/ops.bend:8951` IS THE
# TREE'S OWN COUNTER-EXAMPLE OF WHAT THAT COSTS -- A `match` ON A CALL THERE POISONED
# EVERY FILE THAT IMPORTS `uop/ops.bend`.
#
# THE ROWS. Every `want` IS UPSTREAM'S OWN ANSWER, READ OFF CPython
# (`tinygrad/mixin/op.py:863`) IN THIS REPO'S `.venv`, **NOT** OFF THIS FILE. THE
# ORCHESTRATOR RE-CHECKED ALL SIX AGAINST CPython INDEPENDENTLY: **0 DISAGREEMENTS OF
# 6** (`argmax_unique` 1, `argmax_tie3` 0, `argmax_tie2` 1, `argmax_tie_last` 0,
# `argmax_neg` 1, `argmax_zero` 2).
#
# SCOPE, STATED SO NOBODY INVENTS A WIDER CLAIM: THIS IS A 1-D F32 FORMULA. Upstream's
# `argmax` takes an AXIS and any dtype. A generalisation is a WIDENING OF THIS FILE,
# NOT A NEW IDEA, AND IT IS NOT DONE HERE.

import Base

# `idx[j]` -- `n - j` where `v[j]` is a maximum, `0` where it is not.
def nn_argmax.pick(eq: Bool, j: U32, n: U32) -> U32: Bool.pick(U32, eq, U32.sub(n, j), 0)

# `self.max(axis=axis)` -- the running maximum. THE ACCUMULATOR IS THE SECOND
# PARAMETER and the list is the first, because Bend's termination check reads the
# arguments LEFT TO RIGHT and stops at the first one that is a smaller part of its
# parameter; the ones after it are free.
def nn_argmax.max.go(vals: List<&2, F32>, +acc: F32) -> F32:
  match vals:
    case Nil{}: acc
    case +v <> t: nn_argmax.max.go(t, Bool.pick(F32, F32.is_gt(v, acc), v, acc))

# `self.max(axis=axis)` -- seeded from the head, so no `-inf` constant is needed and an
# all-`-inf` list still answers the head.
def nn_argmax.head_max(vals: List<&2, F32>) -> F32:
  match vals:
    case Nil{}: 0.0
    case +v <> t: nn_argmax.max.go(t, v)

# `idx.max(axis=axis)` -- the running maximum of the masked counter. `j` IS THE
# POSITION, carried as an accumulator, because upstream's `arange` is exactly that
# counter and the port has no `arange` to borrow.
def nn_argmax.best(vals: List<&2, F32>, +mx: F32, +j: U32, +n: U32, +acc: U32) -> U32:
  match vals:
    case Nil{}: acc
    case +v <> t:
      nn_argmax.best(t, mx, U32.add(j, 1), n,
        Bool.pick(U32, U32.is_gt(acc, nn_argmax.pick(F32.is_eq(v, mx), j, n)), acc,
          nn_argmax.pick(F32.is_eq(v, mx), j, n)))

# `Tensor.argmax(axis=0)` on a 1-D tensor -- `mixin/op.py:863`.
def nn_argmax(+vals: List<&2, F32>) -> U32:
  +n = U32.from_nat(List.length(&2, F32, vals))
  +best = nn_argmax.best(vals, nn_argmax.head_max(vals), 0, n, 0)
  U32.sub(n, best)

# THE ROWS. The `want` IS UPSTREAM'S OWN ANSWER, NOT THIS FILE'S OUTPUT.
def nn_argmax.row(nm: String, vals: List<&2, F32>, want: U32) -> IO(Unit):
  IO.print(String.concat([nm, " got=", U32.show(nn_argmax(vals)), " want=", U32.show(want)]))

def main() -> IO(Unit):
  do IO<Unit>:
    nn_argmax.row("argmax_unique", [1.0, 7.0, 3.0, 2.0], 1)
    nn_argmax.row("argmax_tie3", [5.0, 5.0, 5.0], 0)
    nn_argmax.row("argmax_tie2", [1.0, 9.0, 9.0, 2.0], 1)
    nn_argmax.row("argmax_tie_last", [9.0, 1.0, 9.0], 0)
    nn_argmax.row("argmax_neg", [F32.sub(0.0, 3.0), F32.sub(0.0, 1.0), F32.sub(0.0, 7.0)], 1)
    nn_argmax.row("argmax_zero", [0.0, 0.0, 1.0, 0.0], 2)
