<!-- FROM: tinybendygrad/mixin/movement.bend:1255 -->
# BLOCK:
# SECTION I -- THE WRITE HALF. `mixin/movement.py`'s WRAPPERS, in Python's order.
#
# Sections A-H are the READ half: `_pool`'s shape arithmetic and the `ssimplify`-on-
# CONCRETE arm (`mxm_marg`, `mxm_shape`) that close W1/W2. This section is the twenty-
# four wrappers that call `_mop`, and the reason it is a separate section is the
# IDENTITY TEST: every one of them ends `return self if ret.shape == self.shape else
# ret` (movement.py:185, :190, :194, :231, :254), so the wrapper needs the shape of the
# node it JUST BUILT -- and `uop/fold.bend:1670 symbol=sym_dim.end` does not answer that for PAD, SHRINK,
# EXPAND, FLIP or PERMUTE.
#
# THE MERGE POINT, and it is the reason this section is buildable at all. The
# wrappers use `MX.mxm_shape(MX.mxm_marg(ar, made), src_shape)` for that test rather
# than `mixin/op.bend`'s `mo_reshape`/`mo_permute`, whose `mo_sints` comparison is the
# one that has to work around the gap. `op.bend` is READ-ONLY here, so the gap is
# ROUTED AROUND rather than fixed, and the routing is one function: `mxw_same`.
#
# EVERY WRAPPER IS GATED ON FOUR NUMBERS, not one: node count, root op, src count, and
# the SRC OP SEQUENCE. The sequence is the one that matters and it is the one this
# project has been bitten by -- a movement that swaps two srcs has the right count and
# the wrong graph. `mxw_sig` prints all four as one string so no row can quietly drop
# one of them.
# --- THE GRAPH INSPECTOR -----------------------------------------------------
# THE PARAM ARG, in `ops.bend`'s field order. It is a COPY and not a call into
# `op.bend` because `mo_buf4` hard-codes `size = 4` and the fixtures here need several
# sizes; `mn_buf1` in `examples/beautiful_mnist.bend` is the same copy and the reason
# is the same, which is a duplication three files now carry and which a shared
# `ops.bend` builder would delete.
# END BLOCK

# SECTION I -- THE WRITE HALF. `mixin/movement.py`'s WRAPPERS, in Python's order.
#
# Sections A-H are the READ half: `_pool`'s shape arithmetic and the `ssimplify`-on-
# CONCRETE arm (`mxm_marg`, `mxm_shape`) that close W1/W2. This section is the twenty-
# four wrappers that call `_mop`, and the reason it is a separate section is the
# IDENTITY TEST: every one of them ends `return self if ret.shape == self.shape else
# ret` (movement.py:185, :190, :194, :231, :254), so the wrapper needs the shape of the
# node it JUST BUILT -- and `uop/fold.bend:1670 symbol=sym_dim.end` does not answer that for PAD, SHRINK,
# EXPAND, FLIP or PERMUTE.
#
# THE MERGE POINT, and it is the reason this section is buildable at all. The
# wrappers use `MX.mxm_shape(MX.mxm_marg(ar, made), src_shape)` for that test rather
# than `mixin/op.bend`'s `mo_reshape`/`mo_permute`, whose `mo_sints` comparison is the
# one that has to work around the gap. `op.bend` is READ-ONLY here, so the gap is
# ROUTED AROUND rather than fixed, and the routing is one function: `mxw_same`.
#
# EVERY WRAPPER IS GATED ON FOUR NUMBERS, not one: node count, root op, src count, and
# the SRC OP SEQUENCE. The sequence is the one that matters and it is the one this
# project has been bitten by -- a movement that swaps two srcs has the right count and
# the wrong graph. `mxw_sig` prints all four as one string so no row can quietly drop
# one of them.
# --- THE GRAPH INSPECTOR -----------------------------------------------------
# THE PARAM ARG, in `ops.bend`'s field order. It is a COPY and not a call into
# `op.bend` because `mo_buf4` hard-codes `size = 4` and the fixtures here need several
# sizes; `mn_buf1` in `examples/beautiful_mnist.bend` is the same copy and the reason
# is the same, which is a duplication three files now carry and which a shared
# `ops.bend` builder would delete.
