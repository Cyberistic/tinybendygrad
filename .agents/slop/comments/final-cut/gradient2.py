import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cut import apply

F = "tinybendygrad/mixin/gradient.bend"

EDITS = [
  # rule 29 -- THE IDENTITY CHECK paragraph repeats the FIRST paragraph's fact.
  (855, 877, """# --- 29. AFTER, clone/assign -- gradient.py:101. `(None, ctx)`
#
# * THE NAME REBIND. * `dest` is bound at `AFTER.src[0]` AND at `AFTER.src[1].src[0]`. The
# rule fires ONLY when those are the SAME node, and the compiled form states that as an
# explicit `is` (upat.py:100-105). Without the check the rule claims every
# `AFTER(_, STORE(_,_))` -- including the ordering-only shape of tag 28 and the partial-store
# shape of tag 30 -- and it still typechecks.
#
# `gr_28` is therefore SPLIT: the identity test is a separate def, `gr_29_same`, and the rule
# answers `GSkip{}` when it fails. That is the honest port -- not "the rule claims and then
# declines", but "the pattern does not match", because in the compiled form the `is` is part of
# the MATCH. The two-sided gate is `rebind` (same node -> fires) and `rebind_off` (different
# node -> does not), and the mutation is `gr_29_same`'s `U32.is_eq` replaced by `True{}`.
# `U32.is_eq` on two arena indices IS `store.setdefault(...).same`, which is what the
# interpreter does (notes, "THE NAME-REBIND QUESTION, SETTLED")."""),

  # rule 30 -- the WALL paragraph and the UPSTREAM WHY are the facts.
  (905, 934, """# --- 30. AFTER, partial store -- gradient.py:100-101. `partial_store_gradient(ctx, dest, view)`
#
# the helper is a `while` LOOP plus a re-entry into the matcher, and both halves are walls
# here. `gradient.py:54-58` walks `base` up through `{RESHAPE, SHRINK, PERMUTE, PAD}`
# accumulating a `path`, and returns `None` if it never reaches `dest`; `gradient.py:61` then
# calls `compute_gradient`, whose own `pm_gradient.rewrite` (gradient.py:124) is THE MATCHER
# CALLING ITSELF. That is mutual recursion between `gr_29` and `gr_rewrite`, and Bend refuses
# mutual recursion outright (notes, "There is no mutual recursion"). The loop itself is a
# `while` with a mutable list, which Bend expresses as a self-call on the tail, but it cannot
# be entered FROM the rewrite.
# TODO(p3) mixin/gradient.py:52  partial_store_gradient -- the body RE-ENTERS
#   `pm_gradient.rewrite` (gradient.py:124, reached through `compute_gradient` at
#   gradient.py:61), so `gr_29` and `gr_rewrite` would be mutually
#   recursive and Bend refuses that. It also needs `mop.replace(src=(grad,)+mop.src[1:])`
#   (a src rewrite with an `Arg` preserved) and `grad.const_like(1)`.
#
# THE UPSTREAM WHY ON THIS HELPER, and it is the ONE place the rule answers with something
# other than `ctx`:
#   gradient.py:53 -- "A write through a non-overlapping view replaces only that region of
#   the returned state." The rule's answer is a PAIR -- a MASK and a GRADIENT -- and the mask
#   is the part that is not a gradient at all: it is `mask.cast(dtypes.bool).where(0, ctx)`,
#   which ZEROES the gradient everywhere OUTSIDE the written region and leaves it alone inside.
#   So the returned state keeps its old values where the write did not land. That is why the
#   helper is named "partial_store" and not "store": the write is partial and the state is
#   MERGED, not replaced. `compute_gradient(view, grad.const_like(1), {dest})` is what produces
#   the mask -- the mask is the gradient of a CONSTANT 1 over the view, which is 1 on the view
#   and 0 outside it."""),

  # THE WALK -- the THREE PORTED PIECES are a table, and the TWO WALLS are the facts.
  (1088, 1123, """# THE WALK -- `compute_gradient` (gradient.py:116-145) and `_deepwalk` (:109-114).
#
# THREE of upstream's five pieces ported:
#
#   (a) `_deepwalk`'s `in_target_path` LATTICE (:112) -- ported as a forward pass over
#       `O.UOp.toposort`, which is sound for the reason `fold.bend`'s Kahn is: a node's flag
#       reads only its SRCS' flags, and a src is always EARLIER in a toposort, so one pass in
#       post-order IS the fixpoint. `topovisit`'s VISITOR is a Python lambda and Bend has no
#       closures in a datatype field, so the lambda becomes the fold and the dict becomes a
#       `Data` pair of parallel lists (notes, T-6).
#   (b) THE WALK (:114) -- `[node for node in in_target_path if node.op is not Ops.DETACH and
#       in_target_path[node]]`, i.e. a FILTER over the same pair. PORTED.
#   (c) `grads` AND THE ACCUMULATION (:118, :129-139) -- a `Data` pair of parallel lists with
#       an IN-PLACE update, which is what makes it dict-shaped: append is last-wins, and
#       Python's `grads[k] = grads[k] + v` overwrites while keeping `k`'s INSERTION position.
#
# TWO THINGS DID NOT LAND, and both are the walls already recorded in the header of this file:
#   * the SHAPED-EDGE REDUCE (:132-133), which needs `broadcast_axes` and `sum_acc_dtype`. It
#     is not merely deferred here -- MEASURED, it is a place where CPython ITSELF raises:
#     `oracle-cg.py`'s second fixture drives `compute_gradient` into `RuntimeError: cannot
#     broadcast ... into ()` at gradient.py:133, so the fixture cannot gate a port of that
#     line either. The walk is gated on the fixture that does NOT reach it, and every node in
#     that fixture is a SCALAR -- the leaves are `BUFFER(STACK())`, whose `_shape` is `()`
#     (ops.py:359, :789) -- so the guard `k._shape is not None and v._shape is not None and
#     k._shape != v._shape` is FALSE throughout -- the port omits a branch that is not taken,
#     which is stated rather than hidden.
#   * the BACKWARD-METADATA pass (:140-144), which reads `all_metadata` (ops.py's module-level
#     dict). It has no observable effect on `grads`, so omitting it changes no row in this
#     gate; that is a NAMED OMISSION, not a silent one.
# `call_gradient` (:20-50) stays a wall under `grad_30`'s block and is NOT called here: a CALL
# in the walk is the one node shape whose gradient this port cannot produce, and `cg_run` states
# that rather than pretending."""),

  # THE INNER LOOP -- the LAST paragraph is the substrate rule and the SHAPE is the fact.
  (1425, 1450, """# THE INNER LOOP, gradient.py:129-139: `for k, v in zip(t0.src, lgrads)`. ONE
# self-recursive def and the two lists shrink together.
#
# THE UPSTREAM WHY-S ON THIS LOOP, and the loop's shape is not obvious from its body:
#   gradient.py:129 -- "a shaped edge's gradient is summed to its source's shape". The
#     gradient of an edge whose SHAPE differs from its source's shape is not the gradient
#     itself but a REDUCE of it, back down to the source's shape. Without this, a broadcast
#     edge's gradient would carry the broadcast's shape and the next node up would be summing
#     against a mismatched shape. The condition is `k._shape is not None and v._shape is not
#     None and k._shape != v._shape` -- TWO `is not None` conjuncts, so a node with an UNKNOWN
#     shape is left alone rather than reduced. That is the third clause and it is the one the
#     port's gate exercises: the whole fixture is SCALAR (`_shape` is `()`), so the branch is
#     never taken.
#   gradient.py:130 -- `if v is None: continue`. A HOLE in the rule's answer is not a zero
#     gradient; it is "this rule says nothing about this src", and the walk must leave the
#     existing gradient alone rather than overwrite it. `gs` HOLES are index 0, which is the
#     arena's bottom node and therefore tinygrad's own `None` (see this file's header).
#
# the shape is the point and it cost four edges to find. The obvious spelling -- `cg_puts`
# calls a `cg_hole` that calls `cg_puts` back -- is a MUTUAL RECURSION and this compiler
# refuses the pair with "expected : a filled definition". Lifting the recursion OUT of the
# branch is what works: `step` answers the state after ONE (k, v) pair and `go` owns the
# descent over the tails. `fold.bend`'s `Kahn.gather.go` is the same arrangement."""),

  # THE WALK, a FILTER -- the LAST paragraph is a RESTATEMENT of (a) and (b) above.
  (1221, 1237, """# THE WALK, a FILTER over the pair. `_ _` is the cover and it covers BOTH ragged arms
# (notes, rule 4 at position 1260) -- a `Nil` on one side with a `h <> t` on the other is a
# ragged list, which `flags` can never be because `dw_flags` pushes both together.
#
# THE TWO UPSTREAM WHY-S, and the FILTER is not a simplification of the walk -- it is the
# second half of it:
#   gradient.py:108 -- "compute the target path (top down)". The path is computed TOP DOWN,
#     from the root, and `in_target_path[x]` is TRUE when x is a target OR when any of x's srcs
#     is on the path. That is the closure of "reaches a target", and computing it top-down is
#     what makes it one pass: a node's flag reads only its SRCS' flags, and a src is always
#     EARLIER in a toposort.
#   gradient.py:111 -- "don't flow through DETACH or anything not in target path". TWO
#     exclusions, and the DETACH one is a semantic choice rather than a bookkeeping one: a
#     DETACH is a gradient STOP, so a gradient must not flow THROUGH one."""),
]

apply(F, EDITS)
