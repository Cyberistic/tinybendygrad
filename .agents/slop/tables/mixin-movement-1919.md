<!-- FROM: tinybendygrad/mixin/movement.bend:1919 -->
# BLOCK:
# THE MEASURED MUTATION TABLE. Twenty-seven mutations: sixteen on the READ half
# (Sections A-H) and eleven on the WRITE half (Section I). Driver:
# `.agents/slop/notes/mxm-mutate.py`. the COPY it mutates must live beside this file
# because the imports are relative -- a copy in /tmp cannot resolve `./../helpers.bend`
# and every mutation reads REFUSED, which is itself a measured fact. The full 27-row table
# with row sets is appended to `.agents/slop/notes/bend2-constraints.md`.
#
# no mutation moves nothing, and four blind spots were found and closed (M5, M8, M12,
# and W7, whose `case _ False{}` arm -- the one that answers a NON-movement op from the
# fold -- had no fixture at all, because every node in the rows was a movement op and the
# one non-movement node they reached is a node `fold.bend` does not answer, so the arm's
# answer was the empty list EITHER WAY). The four rows that closed them are `f_neg`,
# `add_tag`, `pool_wide` and `add_shape`. A rule no mutation can reach is not gated.
#
# M11 and W10 are the gate's two LOAD-bearing weaknesses, and they are the same kind of
# WEAKNESS. M11 is the printer's own append direction and it moves 25 of 70 rows; W10
# replaces the toposort count with `1` and it moves all 15 `n=` rows. Together they say
# that a 70-row gate here is NOT seventy independent witnesses: the printer is one shared
# component and the `n=` field is one shared component. A mutation in EITHER invalidates a
# quarter of the suite, and neither is a rule under test.
#
# W2 is the row this project needed and did not have. Swapping a pad's two shape args --
# `self|a|b` to `self|b|a` -- leaves the ROOT OP, the SRC COUNT and (mostly) the NODE COUNT
# alone, and it moves only `pad_noop` and `shrink_noop`, the two rows where the identity
# test fires. A gate carrying `op` and `nsrc` but not the src OP SEQUENCE would be
# completely blind to it. That is the "right count, wrong graph" hole the brief names,
# MEASURED in this file, and `mxw_sig` prints all four facts in one string precisely so a
# fixture cannot drop one of them.
#
# W11 IS THE ALIASING RULE'S THIRD SYMPTOM, and it is the quietest one. The identity
# test reading the BASE's arena with the MADE node's index returned False for a no-op
# reshape, so `resh_noop` built a RESHAPE where CPython returns `self`. The usual symptom of
# the rule is a WRONG node; this one is a MISSING node, because `Arena.node` answers the
# BOTTOM for an index past the end. One row (`resh_noop`) sees it and nothing else would.
#
# W4 and M16 are compile errors and that is the finding -- inverting `mxw_permute`'s
# order test and reading src[0]'s arg in `mxm_ys` are both refused before they run, so the
# two are the only rules in this file the type checker defends rather than the gate.
#
# what the table still does not cover, and it is most of the write half. Every row is a
# node signature or a shape. Nothing here builds `_pool`'s CHAIN, so nothing sees the seven
# `shrink_to`/`reshape` calls, the `repeat`, or the permute that closes it. Nor does
# anything here build a whole conv2d: `examples/beautiful_mnist.bend` is the consumer and its
# W1/W2 rows are the ones that would catch it.
# `_broadcast_to` (movement.py:128-146) -- THE CONCRETE HALF.
#
# The file's own header lists this as NOT PORTED: "`_broadcast_to` (:128) /
# `expand` (:149) -- WALL: `broadcast_axes` (ops.py:89) needs `resolve` on a
# `Sint` ...; portable for a concrete shape and not done." this is that half.
#
# CPython's rule, quoted (movement.py:134-146):
#
#   # EXPAND only adds dims on the left. squeeze 1s that need expanding, EXPAND
#   # on left, permute back.
#   n_left = len(new_shape) - len(self.shape)
#   expand_at = tuple(i-n_left for i in broadcast_axes(self.shape, new_shape) if i >= n_left)
#   kept = tuple(i for i in range(len(self.shape)) if i not in expand_at)
#   squeezed = self.reshape(tuple(self.shape[i] for i in kept))
#   expanded = squeezed._mop(Ops.EXPAND, arg=new_shape[:n_left] + tuple(new_shape[n_left+i] for i in expand_at))
#   perm = tuple(range(n_left)) + tuple(
#     n_left + (expand_at.index(i) if i in expand_at else len(expand_at) + kept.index(i)) for i in range(len(self.shape)))
#   return expanded.permute(perm)
#
# the marg is not the target. It is the left-added dims (`new_shape[:n_left]`)
# and THEN the dims of the SOURCE axes that were 1 and became BIGGER
# (`new_shape[n_left+i] for i in expand_at`). THE SQUEEZE AND THE PERMUTE are what
# make the result's shape the target's, and a marg that is the whole target is
# the shape `tuple(self.marg) + ps` (ops.py:397) reads as -- THE WHOLE TARGET
# CONCATENATED WITH THE SOURCE.
#
# `broadcast_axes` (ops.py:93-97) is `resolve`d, so the SYMBOLIC shape is the wall;
# a CONCRETE one is not, and every caller of `mxw_bcast` has one.
# THE PREDICATE -- `self.shape[i] == 1 and new_shape[n_left+i] != 1`. This is
# `broadcast_axes` (ops.py:93-97) with the `resolve` dropped, which is the whole
# of the difference between the symbolic shape and a concrete one.
# END BLOCK

# THE MEASURED MUTATION TABLE. Twenty-seven mutations: sixteen on the READ half
# (Sections A-H) and eleven on the WRITE half (Section I). Driver:
# `.agents/slop/notes/mxm-mutate.py`. the COPY it mutates must live beside this file
# because the imports are relative -- a copy in /tmp cannot resolve `./../helpers.bend`
# and every mutation reads REFUSED, which is itself a measured fact. The full 27-row table
# with row sets is appended to `.agents/slop/notes/bend2-constraints.md`.
#
# no mutation moves nothing, and four blind spots were found and closed (M5, M8, M12,
# and W7, whose `case _ False{}` arm -- the one that answers a NON-movement op from the
# fold -- had no fixture at all, because every node in the rows was a movement op and the
# one non-movement node they reached is a node `fold.bend` does not answer, so the arm's
# answer was the empty list EITHER WAY). The four rows that closed them are `f_neg`,
# `add_tag`, `pool_wide` and `add_shape`. A rule no mutation can reach is not gated.
#
# M11 and W10 are the gate's two LOAD-bearing weaknesses, and they are the same kind of
# WEAKNESS. M11 is the printer's own append direction and it moves 25 of 70 rows; W10
# replaces the toposort count with `1` and it moves all 15 `n=` rows. Together they say
# that a 70-row gate here is NOT seventy independent witnesses: the printer is one shared
# component and the `n=` field is one shared component. A mutation in EITHER invalidates a
# quarter of the suite, and neither is a rule under test.
#
# W2 is the row this project needed and did not have. Swapping a pad's two shape args --
# `self|a|b` to `self|b|a` -- leaves the ROOT OP, the SRC COUNT and (mostly) the NODE COUNT
# alone, and it moves only `pad_noop` and `shrink_noop`, the two rows where the identity
# test fires. A gate carrying `op` and `nsrc` but not the src OP SEQUENCE would be
# completely blind to it. That is the "right count, wrong graph" hole the brief names,
# MEASURED in this file, and `mxw_sig` prints all four facts in one string precisely so a
# fixture cannot drop one of them.
#
# W11 IS THE ALIASING RULE'S THIRD SYMPTOM, and it is the quietest one. The identity
# test reading the BASE's arena with the MADE node's index returned False for a no-op
# reshape, so `resh_noop` built a RESHAPE where CPython returns `self`. The usual symptom of
# the rule is a WRONG node; this one is a MISSING node, because `Arena.node` answers the
# BOTTOM for an index past the end. One row (`resh_noop`) sees it and nothing else would.
#
# W4 and M16 are compile errors and that is the finding -- inverting `mxw_permute`'s
# order test and reading src[0]'s arg in `mxm_ys` are both refused before they run, so the
# two are the only rules in this file the type checker defends rather than the gate.
#
# what the table still does not cover, and it is most of the write half. Every row is a
# node signature or a shape. Nothing here builds `_pool`'s CHAIN, so nothing sees the seven
# `shrink_to`/`reshape` calls, the `repeat`, or the permute that closes it. Nor does
# anything here build a whole conv2d: `examples/beautiful_mnist.bend` is the consumer and its
# W1/W2 rows are the ones that would catch it.
# `_broadcast_to` (movement.py:128-146) -- THE CONCRETE HALF.
#
# The file's own header lists this as NOT PORTED: "`_broadcast_to` (:128) /
# `expand` (:149) -- WALL: `broadcast_axes` (ops.py:89) needs `resolve` on a
# `Sint` ...; portable for a concrete shape and not done." this is that half.
#
# CPython's rule, quoted (movement.py:134-146):
#
#   # EXPAND only adds dims on the left. squeeze 1s that need expanding, EXPAND
#   # on left, permute back.
#   n_left = len(new_shape) - len(self.shape)
#   expand_at = tuple(i-n_left for i in broadcast_axes(self.shape, new_shape) if i >= n_left)
#   kept = tuple(i for i in range(len(self.shape)) if i not in expand_at)
#   squeezed = self.reshape(tuple(self.shape[i] for i in kept))
#   expanded = squeezed._mop(Ops.EXPAND, arg=new_shape[:n_left] + tuple(new_shape[n_left+i] for i in expand_at))
#   perm = tuple(range(n_left)) + tuple(
#     n_left + (expand_at.index(i) if i in expand_at else len(expand_at) + kept.index(i)) for i in range(len(self.shape)))
#   return expanded.permute(perm)
#
# the marg is not the target. It is the left-added dims (`new_shape[:n_left]`)
# and THEN the dims of the SOURCE axes that were 1 and became BIGGER
# (`new_shape[n_left+i] for i in expand_at`). THE SQUEEZE AND THE PERMUTE are what
# make the result's shape the target's, and a marg that is the whole target is
# the shape `tuple(self.marg) + ps` (ops.py:397) reads as -- THE WHOLE TARGET
# CONCATENATED WITH THE SOURCE.
#
# `broadcast_axes` (ops.py:93-97) is `resolve`d, so the SYMBOLIC shape is the wall;
# a CONCRETE one is not, and every caller of `mxw_bcast` has one.
# THE PREDICATE -- `self.shape[i] == 1 and new_shape[n_left+i] != 1`. This is
# `broadcast_axes` (ops.py:93-97) with the `resolve` dropped, which is the whole
# of the difference between the symbolic shape and a concrete one.
