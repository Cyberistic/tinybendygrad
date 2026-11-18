import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cut import apply

F = "tinybendygrad/tensor.bend"

# **THE **FOURTH **PASS**: **THE **DUPLICATED **`__i*__` **TABLE** (⇒⇒† AND **THE **FIRST **COPY
# **ENDS **MID-SENTENCE**, **⇒⇒† AND **A **TRUNCATED **COMMENT **IS **NOT **A **CUT**), **⇒⇒† AND
# **THE **REMAINING **ESSAYS**.
EDITS = [
  # THE DUPLICATE -- the first copy's fragment is a DANGLING SENTENCE and the table it introduces
  # is the SECOND copy's, verbatim. Cut the fragment and the duplicate.
  (1677, 1688, """# THE `__i*__` TWELVE AND `__eq__` -- tensor.py:536-549. Twelve methods, each
# `return self.assign(self.<op>(x))`, and the reason they are not here is NOT operator
# overloading -- BEND HAS IT (`bend guide:630`: inside `(.. : T)` the operators call `T.add`
# through `T.mod`). It is the ASSIGNMENT half: `self.assign(...)` MUTATES, and Bend is affine."""),

  # `_rop` -- the SIX STEPS are upstream's own, and the HOIST paragraph says why the hoist is
  # load-bearing. The "ONE def and not a .go/.of split" paragraph is the SUBSTRATE RULE, which
  # the file's header used to carry and which every reader of the .bend rule already knows.
  (1342, 1372, """# `_rop` -- ops.py:655, hoisted. Six steps:
#   axis = tuple(sorted(axis))
#   reduce_axis = tuple(x for x in axis if resolve(self.shape[x] != 1))
#   if not len(reduce_axis): return self.reshape(kept)
#   perm = reduce_axis + tuple(i for i in range(len(self.shape)) if i not in reduce_axis)
#   ret = UOp(Ops.REDUCE, src=(self.permute(perm),), arg=(op, len(reduce_axis)))
#   return ret.reshape(kept) if axis != reduce_axis else ret
#
# HOISTED FROM mixin/movement.py, and the hoist is load-bearing rather than convenient:
# `permute` (:214) ends `return self._mop(Ops.PERMUTE, arg=order_arg) if order_arg !=
# tuple(range(self.ndim)) else self` and `reshape` (:185) ends `return self if ret.shape ==
# self.shape else ret`. Without those two identity tests `_rop` builds a PERMUTE where Python
# returns `self` and a RESHAPE where Python returns `self`, and every fixture disagrees. They
# are movement.py's lines and they move back with movement.bend.
#
# `resolve` (ops.py:445) is symbolic and a concrete dim is already resolved, so the `!= 1` test
# is `fold.bend`'s `bcast_dim.is_uop_or_ne_1`, which is the same predicate with the same two
# cases.
#
# WHAT IS NOT PORTED, and `tn_rop_gap` reports it: the `reduce_axis` filter reads
# `self.shape[x]`, and for a source that is a RESHAPE the fold has no answer (fold.bend's
# `t_gap_ok`). So `tn_rop.ne1` answers `None` there, `tn_rop.reduce` reads that as "the filter
# could not run" and falls back to the empty arm, and the multi-dimensional `_rop` fixtures --
# which Python builds over a RESHAPE, because `Tensor([[1,2],[3,4]])` IS one -- are on the wall
# list rather than in the gate. The 1-D fixtures are BUFFER-rooted and their shape folds, so they
# are in."""),

  # tn_rop.ne1 -- the FIRST paragraph is the fact, the SECOND is a four-rule essay about the
  # parameter order, and the THIRD and FOURTH are the substrate rules again.
  (1403, 1423, """# `tuple(x for x in axis if resolve(self.shape[x] != 1))`, and `None` when the fold
# cannot answer the shape at all.
#
# the order of the parameters is the whole trick. A def may only call defs declared above it, a
# `.go`/`.step` pair would be MUTUAL RECURSION (refused), a def body is ONE EXPRESSION, and a
# self-call must read LEFT TO RIGHT with the SHRINKING argument first. All four together mean the
# self-call must be the arm's entire expression, which means the `Bool.pick` that appends has to
# be an ARGUMENT of the self-call. So the list is the FIRST parameter -- `ne1(axis, acc, k)` -- the
# tail `t` is the self-call's first argument, and `acc` is the computed one.
#
# `Bool.pick` is strict, so BOTH branches are evaluated: the self-call runs whether or not `x` is
# kept. That is harmless here and it is what makes the walk terminate -- the tail is consumed
# exactly once per element."""),

  # `assign` -- the SPINE and the four upstream WHY-S. The four WHY-S are upstream's own
  # comments, and they are the reason each arm exists; they are the fact. The third arm's
  # upstream comment is the LONGEST and it says the one thing a reader needs: the AFTER must
  # go UNDER the view so the shape survives.
  (1474, 1523, """# `assign` -- tensor.py:236-274. NINE branches, and the SPINE is the only one that
# builds a graph without device state:
#
#   assign = self.uop.after(store := self.uop.store(x.uop))              -- :259
#   ib = self.uop
#   while ib.op in GroupOp.Movement|{Ops.BITCAST, Ops.DETACH} and not (ib.
#     has_buffer_identity() and _tensor_holds(ib)): ib = ib.src[0]        -- :261
#
# and the other eight arms all want a `Buffer` (WALL 2), `has_buffer_identity` (P3),
# `is_realized` (P3), `UOp.clone` (P3), `least_upper_dtype` on a weak dtype (P4's
# dtype.bend) or `substitute` (WALL 3). So the SPINE is ported and the rest is one
# `TODO(p3)`.
#
# THE UPSTREAM WHY-S OF THE ARMS AROUND THE SPINE, and the SPINE is the SIMPLE case and every
# other arm exists to avoid it:
#   tensor.py:253 -- "assigning to a pending value that views no other live tensor is
#   initialization, not a write: the whole tensor is overwritten, so the pending value is dead."
#   The parenthetical is the subtle half: a broadcast const like `const_like` is `EXPAND(CONST)`
#   and it LOOKS like a view but it views NOTHING, so it is not an "other live tensor" and the
#   arm still fires.
#   tensor.py:258 -- "STORE+AFTER: STORE is the write effect (void), AFTER wraps the view for
#   correct shape/ranging". The pair is not redundant: the STORE carries no shape -- it is a
#   void effect on a buffer -- and the AFTER is what carries the SHAPE and the RANGE.
#   tensor.py:261 -- "a partial write needs storage to land in: a pending value gets explicit
#   storage (a clone)". A PARTIAL write -- one into a view, not the whole tensor -- has to land
#   in a real buffer, so a pending target is given one by CLONING it.
#   tensor.py:264 -- "view assign: the base reads 'after the store into the view' (one AFTER
#   level). replace the node under the views (e.g. RESHAPE(BUFFER)) so @function's substitution
#   catches it". EVERY live tensor whose storage is the assigned one has its uop rewritten, and
#   the rewrite replaces the node UNDER the views -- so a `RESHAPE(BUFFER)` becomes
#   `RESHAPE(BUFFER.after(store))` and not `RESHAPE(BUFFER).after(store)`. The reason is the
#   shape: the AFTER has to be under the RESHAPE so the RESHAPE's shape is still the view's
#   shape, and so `@function`'s later substitution actually catches it.
#   tensor.py:269 -- "simple assign". The arm that needs none of the above: the target IS the
#   tensor, so the store and its AFTER are the whole story."""),

  # THE ZIP -- the FIRST paragraph is the fact (two facts, kept apart), the SECOND is the
  # measurement, and the THIRD is the FLOAT CONST wall, which is the same claim as the DEPS
  # header's and is repeated.
  (1583, 1613, """# THE ZIP -- tensor.py:490-494. `zip(tensors_need_grad, self.gradient(*tensors_need_grad,
# gradient=gradient))` is TWO facts and the row keeps them apart, because a row that cannot tell
# them apart cannot fail:
#
#   `mixin/op.py:471`  `[self._wrap_uop(grads[x] if x in grads else x.const_like(0))
#                        for x in target_uops]`  -- the ANSWER: one slot per target, in
#                        TARGET ORDER, and a target with no entry in `grads` gets the
#                        ZERO SUBSTITUTE rather than a hole. This is `Bwd.gs`.
#   `tensor.py:493`    `if t.grad is None: t.grad = g` -- the WRITE, and the number of
#                        writes is what `Bwd.ts` LENGTHS. This is `Tensor.grad_set`, which
#                        until now had no caller in the tree.
#
# WHY TWO INSTEAD OF ONE. `const_like(0)` is the substitute that makes the two halves DISJOINT:
# a port that skipped the target instead of substituting it produces the SAME `Bwd.gs` (the
# answer is unchanged) and ONE FEWER write, so a row that printed only the answer could not see
# it. And a port that walked the two lists in the other order produces the SAME COUNT and a
# PERMUTED answer. Neither half sees the other's bug; the row is the pair. Measured on the
# `t_bwd` fixture: see `.agents/slop/BACKWARD-WALK.md`.
#
# `G.gslot` IS the `x in grads` half and `G.GSlot.v_of` the `grads[x]` half, so the ONLY thing
# this def adds is the ELSE. `x.const_like(0)` (ops.py:600) is `CONST(0)._mop(EXPAND,
# x._shape)` and the CONST is a FLOAT literal, which is a WALL -- but a NAMED DIVERGENCE, not a
# missing type: a decimal literal IS an `F32` (MEASURED: `F32.bits(0.044715)` is CPython's f32
# of 0.044715), so `O.CFloat{0.044715}` is a legal constant and `nn/optim.bend` already
# constructs `CFloat{...}` NINE TIMES. What is missing is the ONE call in THIS file that
# interns a float literal into a CONST tensor. So the substitute is the arena's RESERVED INDEX
# 0 -- the same `None` convention `grad` already carries -- and the gate prints `ZERO` for that
# slot rather than printing a node that would claim to be a float."""),
]

apply(F, EDITS)
