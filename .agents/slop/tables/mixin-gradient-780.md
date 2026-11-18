<!-- FROM: tinybendygrad/mixin/gradient.bend:780 -->
# BLOCK:
# --- 21. PERMUTE -- gradient.py:89. `(ctx.permute(argsort(ret.marg)),)`
#
# the rule, in three pieces, and every piece is upstream's own:
#
#   1. `ret.marg` for a PERMUTE is `self.arg` (ops.py:792) -- an `ATuple{ys}` here.
#   2. `argsort` (helpers.py:28) SORTS BY VALUE AND RETURNS INDICES, and
#      `helpers.bend`'s `argsort_u32` IS that function: it pairs each value with its
#      index (`Ix{i, v}`), sorts by `(value, index)` -- Python's `sorted` is stable, so
#      the INDEX breaks the ties -- and projects the INDEX back out.  - IT IS NOT
#      "a sort of arena indices": the sort key is the value and the projection is
#      THE INDEX.  MEASURED against upstream's own `argsort` on six inputs, in the
#      `pm_argsort_*` rows.
#   3. `ctx.permute(order)` (movement.py:214-231) has THREE observable behaviours:
#      a. `_resolve_dim` (movement.py:81-84) is PURE INTEGER ARITHMETIC over
#         `self.ndim` -- `total = self.ndim + extra`, a range test, and
#         `dim + total if dim < 0 else dim` -- and it NEVER calls `resolve`.  -
#         THERE IS NO `resolve` WALL AT `gr_21`.
#      b. THE IDENTITY EARLY-RETURN: `return self._mop(Ops.PERMUTE, arg=order_arg)
#         if order_arg != tuple(range(self.ndim)) else self` (movement.py:231).  For
#         the IDENTITY order the answer is `ctx` ITSELF and NO PERMUTE NODE IS BUILT.
#      c. THE VALIDITY RAISE: `if sorted(order_arg) != list(range(self.ndim)):
#         raise RuntimeError(...)` (movement.py:230).
#
# (a) and (c) both read `ctx.ndim`, and the port has no `ndim`: `ops.bend` has no
# `as_shape` and no `shape`, so a node's DIMENSION COUNT is not available here.  -
# (c) is not reproduced.  that is a named divergence and it is bounded by a
# MEASUREMENT, NOT BY AN ARGUMENT: upstream's `compute_gradient` guarantees
# `ctx.ndim == len(ret.marg)`, because the gradient flowing into a node is reshaped
# to THAT NODE'S SHAPE by the shaped-edge reduce at gradient.py:131-133 -- so the two
# agree BY CONSTRUCTION and (c) is UNREACHABLE from `compute_gradient`.  The
# `pm_raise_*` rows MEASURE both of upstream's raises on the fixtures that DO reach
# them, and the report names the one case where the port and upstream differ.
#
# (b) is reproduced, and it is the one that matters: the identity order is reachable
# in a hand-built graph, and upstream's answer for it is `ctx` itself -- a rule that
# builds a PERMUTE node for it would produce a DIFFERENT GRAPH.
#
# WHAT THE PORT USES INSTEAD OF `ctx.ndim`: `len(ret.marg)`, which is the length of
# the ATuple.  It is `ret.ndim` by upstream's own construction (`permute()` validates
# `sorted(order_arg) == list(range(self.ndim))`, so the arg's length IS the ndim), and
# `ctx.ndim == ret.ndim` by the shaped-edge reduce.  - THE TWO NUMBERS ARE EQUAL
# on every reachable fixture, and the port's is the one it can read.
# THE MARGIN, READ OFF THE NODE'S `src[1]`, AND THAT IS THE PIN'S SPELLING.
# At the pin `ops.py:772` reads `case Ops.PERMUTE: return self.src[1].as_shape`:
# the ORDER is the SECOND SOURCE and the node's ARG is None.  MEASURED
# 2026-11-11: this def read the node's ARG, which is None at the pin, so
# `gr_21_marg` answered an EMPTY list; `argsort` of an empty list is empty; and
# the IDENTITY TEST on an empty list is TRUE -- so `gr_21` took the identity
# early-return and answered the CTX for a PERMUTE whose order is (1,2,0).
# The oracle says the answer is a PERMUTE node: `oracle_pm_rule_len=2` and
# `oracle_pm_rule_tok=PERMUTE/2 [STACK/2 STACK/3]`.
#
# The order is a STACK of CONSTs (upstream's `shape_to_shape_arg`, ops.py:105-109),
# so the reader takes `src[1]`'s CHILDREN -- the STACK's own srcs -- and each
# child's CONST value.  A length-1 order is a BARE CONST and has no children --
# and that is the IDENTITY case, which upstream's `permute()` answers with the ctx
# itself.
#
# MEASURED 2026-11-11: the first version of this reader took the PERMUTE's own
# srcs (`Arena.srcs(ar, self)`) instead of `src[1]`'s, so it read the DATA node and
# the ORDER node, and the row did not move.
# END BLOCK

# --- 21. PERMUTE -- gradient.py:89. `(ctx.permute(argsort(ret.marg)),)`
#
# the rule, in three pieces, and every piece is upstream's own:
#
#   1. `ret.marg` for a PERMUTE is `self.arg` (ops.py:792) -- an `ATuple{ys}` here.
#   2. `argsort` (helpers.py:28) SORTS BY VALUE AND RETURNS INDICES, and
#      `helpers.bend`'s `argsort_u32` IS that function: it pairs each value with its
#      index (`Ix{i, v}`), sorts by `(value, index)` -- Python's `sorted` is stable, so
#      the INDEX breaks the ties -- and projects the INDEX back out.  - IT IS NOT
#      "a sort of arena indices": the sort key is the value and the projection is
#      THE INDEX.  MEASURED against upstream's own `argsort` on six inputs, in the
#      `pm_argsort_*` rows.
#   3. `ctx.permute(order)` (movement.py:214-231) has THREE observable behaviours:
#      a. `_resolve_dim` (movement.py:81-84) is PURE INTEGER ARITHMETIC over
#         `self.ndim` -- `total = self.ndim + extra`, a range test, and
#         `dim + total if dim < 0 else dim` -- and it NEVER calls `resolve`.  -
#         THERE IS NO `resolve` WALL AT `gr_21`.
#      b. THE IDENTITY EARLY-RETURN: `return self._mop(Ops.PERMUTE, arg=order_arg)
#         if order_arg != tuple(range(self.ndim)) else self` (movement.py:231).  For
#         the IDENTITY order the answer is `ctx` ITSELF and NO PERMUTE NODE IS BUILT.
#      c. THE VALIDITY RAISE: `if sorted(order_arg) != list(range(self.ndim)):
#         raise RuntimeError(...)` (movement.py:230).
#
# (a) and (c) both read `ctx.ndim`, and the port has no `ndim`: `ops.bend` has no
# `as_shape` and no `shape`, so a node's DIMENSION COUNT is not available here.  -
# (c) is not reproduced.  that is a named divergence and it is bounded by a
# MEASUREMENT, NOT BY AN ARGUMENT: upstream's `compute_gradient` guarantees
# `ctx.ndim == len(ret.marg)`, because the gradient flowing into a node is reshaped
# to THAT NODE'S SHAPE by the shaped-edge reduce at gradient.py:131-133 -- so the two
# agree BY CONSTRUCTION and (c) is UNREACHABLE from `compute_gradient`.  The
# `pm_raise_*` rows MEASURE both of upstream's raises on the fixtures that DO reach
# them, and the report names the one case where the port and upstream differ.
#
# (b) is reproduced, and it is the one that matters: the identity order is reachable
# in a hand-built graph, and upstream's answer for it is `ctx` itself -- a rule that
# builds a PERMUTE node for it would produce a DIFFERENT GRAPH.
#
# WHAT THE PORT USES INSTEAD OF `ctx.ndim`: `len(ret.marg)`, which is the length of
# the ATuple.  It is `ret.ndim` by upstream's own construction (`permute()` validates
# `sorted(order_arg) == list(range(self.ndim))`, so the arg's length IS the ndim), and
# `ctx.ndim == ret.ndim` by the shaped-edge reduce.  - THE TWO NUMBERS ARE EQUAL
# on every reachable fixture, and the port's is the one it can read.
# THE MARGIN, READ OFF THE NODE'S `src[1]`, AND THAT IS THE PIN'S SPELLING.
# At the pin `ops.py:772` reads `case Ops.PERMUTE: return self.src[1].as_shape`:
# the ORDER is the SECOND SOURCE and the node's ARG is None.  MEASURED
# 2026-11-11: this def read the node's ARG, which is None at the pin, so
# `gr_21_marg` answered an EMPTY list; `argsort` of an empty list is empty; and
# the IDENTITY TEST on an empty list is TRUE -- so `gr_21` took the identity
# early-return and answered the CTX for a PERMUTE whose order is (1,2,0).
# The oracle says the answer is a PERMUTE node: `oracle_pm_rule_len=2` and
# `oracle_pm_rule_tok=PERMUTE/2 [STACK/2 STACK/3]`.
#
# The order is a STACK of CONSTs (upstream's `shape_to_shape_arg`, ops.py:105-109),
# so the reader takes `src[1]`'s CHILDREN -- the STACK's own srcs -- and each
# child's CONST value.  A length-1 order is a BARE CONST and has no children --
# and that is the IDENTITY case, which upstream's `permute()` answers with the ctx
# itself.
#
# MEASURED 2026-11-11: the first version of this reader took the PERMUTE's own
# srcs (`Arena.srcs(ar, self)`) instead of `src[1]`'s, so it read the DATA node and
# the ORDER node, and the row did not move.
