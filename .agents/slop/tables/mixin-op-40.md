<!-- FROM: tinybendygrad/mixin/op.bend:40 -->
# BLOCK:
# THE EIGHT WALLS, each named at its Python line.
# (The prose of this block was cut in the source; the LIST is here.)
#
# THE EIGHT WALLS, each named at its Python line. All eight are missing SUBSTRATE;
# W9 below is a different animal, a measured DEFECT in substrate that is present.
#
#   W1 mixin/op.py:74 `_getitem` -- the index is Python's
#      `int|slice|Tensor|None|list|tuple|Ellipsis`, a SEVEN-WAY sum type of
#      heterogeneous payloads (movement.py:86 `_parse_view_index` matches on the
#      Python TYPE), and the body then threads a list of FIVE-FIELD DICTS
#      (op.py:38). Bend's sum types hold one value per arm, so the `Ellipsis`
#      sentinel and the slice triple have no spelling, and `raise IndexError` has
#      no form.
#   W2 mixin/op.py:413 `einsum` -- a STRING FORMULA. `formula.split("->")`,
#      `"".join(sorted(...))`, `s.index(c)`, `s.count(c)`, `s.replace(c, "", 2)`
#      and `string.ascii_letters` are five distinct string algebras over the
#      formula, plus `dict.fromkeys` and `merge_dicts` over letter->size. Bend's
#      `String.split` takes a Char separator, so `split("->")` and `split(",")` do
#      not exist, and this is a whole PARSER.
#   W3 mixin/op.py:450 `gradient` -- `compute_gradient` is `mixin/gradient.py:114 symbol=compute_gradient`,
#      which `mixin/gradient.bend` records as `TODO(p3)` ITSELF: the shaped-edge
#      reduce needs `broadcast_axes` (ops.py:89) which reads `resolve` on a `Sint`,
#      and `uop/symbolic.py`'s `resolve` is not ported. A wall whose own port
#      names it is the cheapest kind of wall to accept.
#   W4 mixin/op.py:752 `_cumalu` -> mixin/movement.py:614 symbol=_pool `_pool` -- `_pool` is
#      TWELVE lines of shape arithmetic (`ceildiv`, `smax`, `flatten`, `repeat`,
#      `shrink_to`, four reshapes, a permute) and `fold.bend`'s `dt_shape`
#      (fold.bend:1608-1611) leaves PERMUTE, EXPAND, PAD, SHRINK and FLIP
#      un-answered, because their `marg` needs `ssimplify`. So `_pool` is
#      BUILDABLE but not CHECKABLE, and everything that reaches it through
#      `arange` (op.py:166) inherits it: `cumsum` (:770), `cumprod` (:784),
#      `cummax` (:798), `cummin` (:816), `logcumsumexp` (:830), `eye` (:215),
#      `_tri` (:233), `triu` (:236), `tril` (:259), and `sort`'s index count
#      (:958).
#   W5 mixin/op.py:913 `sort` -> `.contiguous()` (elementwise.py:59) is
#      `graph_rewrite` (ops.py:1886 symbol=graph_rewrite), which is P3 and lives in another module.
#      The bitonic loop is four nested `for` loops over stage counts, which Bend
#      spells as a fuel-carrying self-call; that part is mechanical, which is why
#      the wall is named at `contiguous` and not at the loop.
#   W6 mixin/op.py:731 `cat` -- `stack`/`flatten` are ops over a VARIADIC
#      `*args` tuple, `_pad_constant` needs `identity_element` (ops.py:58 symbol=identity_element, and
#      `identity_element` is not in ops.bend), and the shape arithmetic is
#      `itertools.accumulate` over `t.shape[dim]`.
#   W7 mixin/op.py:609 `normalize` -- see the PARITY row below. `sign`
#      (elementwise.py:907) needs `const_like` (creation.py) plus `_broadcast_to`
#      (movement.py:128), and `_broadcast_to` calls `broadcast_axes` (ops.py:89),
#      which is `resolve` on a `Sint` -- W3's wall, reached a second time. The
#      `p == 0` arm needs nothing but `ne`, so `mo_norm0` IS ported and gated;
#      the `p != 0` arm is `W7`.
#   W8 mixin/op.py:394 `matmul` / mixin/op.py:367 `dot` -- a WMMA lowering over
#      `UOp(Ops.WMMA, ...)` with a device-specific arg, and `dot`'s `permute +
#      reshape` contraction needs `resolve` (W3) to decide which `N` the WMMA
#      gets.
#
