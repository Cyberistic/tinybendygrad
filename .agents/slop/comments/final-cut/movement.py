import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from cut import apply

F = "tinybendygrad/mixin/movement.bend"

EDITS = [
  # ---- THE HEADER (101 lines) -> 66. THE NOT-PORTED INVENTORY (33 lines) IS DATA AND MOVES
  # TO A TABLE FILE; THE PORTED LIST STAYS, THE `ssimplify` FACT STAYS, THE INTERFACE STAYS AND
  # THE MEASURED `ceildiv_u32` FACT STAYS.
  (1, 101, """# mixin/movement.bend -- tinygrad/mixin/movement.py (640 lines). PORTED HALF: the shape
# arithmetic and the `marg` reader.
#
# THE SPLIT IN THIS FILE IS PYTHON'S. `mixin/movement.py` is a `MovementMixin` over `Tensor` AND
# over `UOp` (ops.py:233 symbol=UOp), and the two halves are not the same.
#
# WHAT IS PORTED HERE, gated against CPython:
#   1. `_pool` in full as SHAPE ARITHMETIC (movement.py:614-632 symbol=_pool): `noop`, `i_`, `o_`
#      (movement.py:618), `f_` (movement.py:622), the dilation window `k*(i*f+d)`
#      (movement.py:624-626), the permute order (movement.py:632).
#   2. `marg` (ops.py:792 symbol=marg) in all THREE arms, and `as_shape` on its CONCRETE arm
#      (`as_shape`, ops.py:786 symbol=as_shape). This is the W1/W2 answer.
#   3. `_shape`'s movement arms (ops.py:395-414 symbol=_shape) for RESHAPE, EXPAND, PERMUTE, PAD,
#      SHRINK and FLIP -- FIVE arms upstream: `Ops.FLIP` is NOT IN upstream at this pin.
#   4. The `PERMUTE` validity check (ops.py:402-404 symbol=_shape), as `mxm_perm_lt` + `mxm_dup`.
#   5. The WRITE half (Section I): `reshape` (:164), `permute` (:214), `pad` (:186), `shrink`
#      (:192), `flip` (:233), plus `mxw_dims_of` (the shape of ANY node, the merge point that
#      makes the identity test answerable) and `mxw_sig` (node count + root op + src count + SRC
#      OP SEQUENCE).
#
# NOT PORTED, each with the reason, IS IN `.agents/slop/tables/mixin-movement-1.md`. THE THREE
# FACTS THAT ARE NOT A LIST STAY HERE: `_broadcast_to` (:128) / `expand` (:149) are DONE FOR A
# CONCRETE SHAPE -- `mxw_bcast` at the END of this file is `_broadcast_to` with `broadcast_axes`'s
# `resolve` dropped, and the SYMBOLIC shape is still the WALL, because `broadcast_axes`
# (ops.py:89) needs `resolve` on a `Sint`. `stack` (movement.py:270 symbol=stack) is a WALL in
# `tensor.bend`: `_mop`'s `case Ops.STACK` (ops.py:809-812 symbol=_mop) needs `dtype_from_uop`
# and `ccast`, and `MopArg` has no STACK constructor.
#
# the wall this file exists to answer. `examples/beautiful_mnist.bend` names two walls, W1 (conv2d,
# `mixin/op.py:1562`) and W2 (max_pool2d, `mixin/op.py:1333`), and both bottom out in `_pool`
# (movement.py:614 symbol=_pool), both recorded there as "BUILDABLE, NOT CHECKABLE" because
# `fold.bend:1606-1612` answers `None{}` for PERMUTE, EXPAND, PAD, SHRINK and FLIP and gives the
# reason: `marg` -> `as_shape` -> `ssimplify`.
#
# `ssimplify` is the whole wall, and for a concrete shape it is the identity. Two CPython facts
# (`.agents/slop/notes/mxm-oracle.py`): (1) `ssimplify` (ops.py:94) is `uop.ssimplify() if
# isinstance(uop, UOp) else uop`, so an `int` comes back UNCHANGED; (2) `UOp.simplify`
# (ops.py:495 symbol=simplify) opens with `if self.op is Ops.CONST: return self`, and a shape arg
# is built by `shape_to_shape_arg` (ops.py:106) as `UOp.const(x)`. So for an INTEGER shape every
# element of `marg` is either a Python int or a CONST and the whole `as_shape` walk is an UNWRAP
# of `STACK -> CONST`. The oracle confirms it directly: for pad, shrink, reshape, permute, flip,
# `_pool`, the `_pool` inside `max_pool2d` and inside conv2d's own `_pad_constant`, `every
# concrete marg elem is a plain int: True`.
#
# so `mxm_marg` and `mxm_shape` are the port of the `ssimplify` arms `fold.bend` is missing, and
# they close W1 and W2 for every shape `examples/beautiful_mnist.bend` builds. `fold.bend` is
# READ-ONLY here, so the arms are SUPPLIED as a function the consumer calls rather than installed
# in the fold; that is the one structural cost of this answer. and the arm that does not close is
# named, not hidden: a symbolic shape puts a `UOp(PARAM)` in the marg and `ssimplify(PARAM)` is
# `graph_rewrite(PARAM, symbolic)` (`graph_rewrite`, ops.py:501 symbol=simplify), so `mxm_marg`
# answers `None{}` and the row is `mxm_sym_NONE`. That is a WALL in `uop/symbolic.py`, another
# unit.
#
# THE EXACT INTERFACE `examples/beautiful_mnist.bend` SHOULD CALL -- three defs, and nothing else
# in this file is on the path:
#   import ../tinybendygrad/mixin/movement.bend as MX
#   MX.mxm_shape(MX.mxm_marg(ar, i), src_shape) -> List<&2, U32>   # the SHAPE of a movement
#       node, given the source's shape: the `fold.bend:1606-1612` replacement
#   MX.mx_pool_shape(shp, k, stride, dilation) -> List<&2, U32>   # `_pool`'s OUTPUT shape.
#       This is W1/W2 and it needs no arena at all -- it is pure integer arithmetic
#   MX.mx_pool_perm(nn: U32, ni: U32)                             # `_pool`'s PERMUTE order.
#       EXISTS AND IS GATED (four rows against CPython), with BOTH arguments already
#       `U32`-converted: `nn` is `U32.from_nat(ndim - len(k))` and `ni` is
#       `U32.from_nat(List.length(&2, U32, k))`. It answers the ORDER, not a node: building the
#       PERMUTE is `mxw_permute(t, MX.mx_pool_perm(nn, ni))`, which is the gate row `pool_perm`,
#       NOT written.
# `mxm_marg` needs `+ar: O.Arena` and a node index.
#
# what is measured rather than assumed in the arithmetic. `H.ceildiv_u32` is overflow-free but
# TRUNCATES toward zero, and `o*s - d` on movement.py:606 CAN BE NEGATIVE. CPython, measured:
# `k=3, d=2, i=5, s=1` gives `o*s-d == -1`, where `H.ceildiv_u32` answers 858993459. So the sign
# is carried as a `Bool` and there are two arms, `mx_ceildiv_s`, and `H.ceildiv_i32` is NOT used
# anywhere in this file -- `H.floordiv_i32` is known-broken (it ignores the sign) and `ceildiv_i32`
# is built on it. `mx_pool_*` are the three places that decision is load-bearing."""),
]

apply(F, EDITS)
