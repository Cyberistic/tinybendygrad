<!-- FROM: tinybendygrad/tensor.bend:1615 -->
# BLOCK:
# THE MOVEMENT DISPATCH. `_mop` (tensor.py:499) is
# `self._apply_uop(UOp._mop, op=op, arg=arg)` and `_rop` (tensor.py:500) is
# `self._apply_uop(UOp._rop, op=op, axis=axis)`: ONE LINE each, and the node
# construction they forward to is `UOp._mop` (ops.py:799) and `UOp._rop` (ops.py:633).
#
# HOISTED, WITH A NOTICE, and the notice is fold.bend's: ops.bend is READ-ONLY to
# this file and carries both as `TODO(p3) ops.py:799  symbol=_mop` and `:633  symbol=_rop`. A
# one-line def whose callee does not exist cannot be gated at all, and the movement
# dispatch is the largest share of this file that builds a graph, so the body is
# written here. When ops.bend lands it, `tn_mop` and `tn_rop` become the one-liners
# Python has and nothing else in this file changes.
#
# PORTED: the two early NOOPs (ops.py:823-826), the `src_args` split (:827-830),
# `shape_to_shape_arg` (ops.py:106), and the final
# `UOp(op, src=(self,)+UOp.sink(*usrcs).simplify().src)` (:835).
#
# THE `.simplify()` IS A WALL: it is `graph_rewrite` (P3). MEASURED for the six
# movement args this file gates, it is the IDENTITY -- `UOp.sink(x).simplify().src` is
# `(x,)`, `UOp.sink(x, y).simplify().src` is `(x, y)`, and `UOp.sink(c).simplify()` is
# still a SINK -- so the port builds the SINK and reads its srcs. `tn_sink1` and
# `tn_sink2` are the rows that would move if a rewrite ever did reach a shape arg.
#
# THE `Ops.STACK` ARM (ops.py:831-834) needs `dtype_from_uop` and `ccast`, both P3, so
# `MopArg` has no `Ops.STACK` case and a STACK arg is a `TODO(p3)`.
# `arg` is one of three shapes and `op` says which, which is exactly what
# ops.py:827-830 decides after Python has already made `arg` a heterogeneous tuple.
# `APairs` is the TRANSPOSE Python computes with `list(zip(*arg))`: `arg` is a tuple
# of (lo, hi) pairs, one per dim, and the transpose is the list of los and the list of
# his.
# END BLOCK

# THE MOVEMENT DISPATCH. `_mop` (tensor.py:499) is
# `self._apply_uop(UOp._mop, op=op, arg=arg)` and `_rop` (tensor.py:500) is
# `self._apply_uop(UOp._rop, op=op, axis=axis)`: ONE LINE each, and the node
# construction they forward to is `UOp._mop` (ops.py:799) and `UOp._rop` (ops.py:633).
#
# HOISTED, WITH A NOTICE, and the notice is fold.bend's: ops.bend is READ-ONLY to
# this file and carries both as `TODO(p3) ops.py:799  symbol=_mop` and `:633  symbol=_rop`. A
# one-line def whose callee does not exist cannot be gated at all, and the movement
# dispatch is the largest share of this file that builds a graph, so the body is
# written here. When ops.bend lands it, `tn_mop` and `tn_rop` become the one-liners
# Python has and nothing else in this file changes.
#
# PORTED: the two early NOOPs (ops.py:823-826), the `src_args` split (:827-830),
# `shape_to_shape_arg` (ops.py:106), and the final
# `UOp(op, src=(self,)+UOp.sink(*usrcs).simplify().src)` (:835).
#
# THE `.simplify()` IS A WALL: it is `graph_rewrite` (P3). MEASURED for the six
# movement args this file gates, it is the IDENTITY -- `UOp.sink(x).simplify().src` is
# `(x,)`, `UOp.sink(x, y).simplify().src` is `(x, y)`, and `UOp.sink(c).simplify()` is
# still a SINK -- so the port builds the SINK and reads its srcs. `tn_sink1` and
# `tn_sink2` are the rows that would move if a rewrite ever did reach a shape arg.
#
# THE `Ops.STACK` ARM (ops.py:831-834) needs `dtype_from_uop` and `ccast`, both P3, so
# `MopArg` has no `Ops.STACK` case and a STACK arg is a `TODO(p3)`.
# `arg` is one of three shapes and `op` says which, which is exactly what
# ops.py:827-830 decides after Python has already made `arg` a heterogeneous tuple.
# `APairs` is the TRANSPOSE Python computes with `list(zip(*arg))`: `arg` is a tuple
# of (lo, hi) pairs, one per dim, and the transpose is the list of los and the list of
# his.
