<!-- FROM: tinybendygrad/tensor.bend:1648 -->
# BLOCK:
# THE `__i*__` TWELVE AND `__eq__` -- tensor.py:536-549. Twelve methods, each
# `return self.assign(self.<op>(x))`, and the reason they are not here is NOT operator
# overloading -- BEND HAS IT (`bend guide:630`: inside `(.. : T)` the operators call `T.add`
# through `T.mod`). It is the ASSIGNMENT half: `self.assign(...)` MUTATES, and Bend is affine.
#
#   tensor.py:534  __iadd__        assign + elementwise.py:101 (Ops.ADD)
#   tensor.py:535  __isub__        assign + elementwise.py sub (Ops.SUB)
#   tensor.py:536  __imul__        assign + elementwise.py:143 (Ops.MUL)
#   tensor.py:537  __itruediv__    assign + elementwise.py div (Ops.FDIV)
#   tensor.py:538  __ifloordiv__   assign + elementwise.py floordiv
#   tensor.py:539  __ipow__        assign + elementwise.py pow (Ops.POW)
#   tensor.py:540  __iand__        assign + elementwise.py:171 (Ops.AND)
#   tensor.py:541  __ior__         assign + elementwise.py:185 (Ops.OR)
#   tensor.py:542  __ixor__        assign + elementwise.py:200 (Ops.XOR)
#   tensor.py:543  __ilshift__     assign + elementwise.py:353 (Ops.SHL)
#   tensor.py:544  __irshift__     assign + elementwise.py:364 (Ops.SHR)
#   tensor.py:545  __imatmul__     assign + mixin/op.py:394 -- a WMMA, not an alu
#   tensor.py:549  __eq__          elementwise.py eq (Ops.CMPEQ)
#
# AND THE TWELVE TODOS, one per row:
#
# TODO(p3) tensor.py:534  __iadd__        assign + elementwise.py:101 (Ops.ADD) -- the `__i*__` blocker.
# TODO(p3) tensor.py:535  __isub__        assign + elementwise.py sub (Ops.SUB) -- the `__i*__` blocker.
# TODO(p3) tensor.py:536  __imul__        assign + elementwise.py:143 (Ops.MUL) -- the `__i*__` blocker.
# TODO(p3) tensor.py:537  __itruediv__    assign + elementwise.py div (Ops.FDIV) -- the `__i*__` blocker.
# TODO(p3) tensor.py:538  __ifloordiv__   assign + elementwise.py floordiv -- the `__i*__` blocker.
# TODO(p3) tensor.py:539  __ipow__        assign + elementwise.py pow (Ops.POW) -- the `__i*__` blocker.
# TODO(p3) tensor.py:540  __iand__        assign + elementwise.py:171 (Ops.AND) -- the `__i*__` blocker.
# TODO(p3) tensor.py:541  __ior__         assign + elementwise.py:185 (Ops.OR) -- the `__i*__` blocker.
# TODO(p3) tensor.py:542  __ixor__        assign + elementwise.py:200 (Ops.XOR) -- the `__i*__` blocker.
# TODO(p3) tensor.py:543  __ilshift__     assign + elementwise.py:353 (Ops.SHL) -- the `__i*__` blocker.
# TODO(p3) tensor.py:544  __irshift__     assign + elementwise.py:364 (Ops.SHR) -- the `__i*__` blocker.
# TODO(p3) tensor.py:545  __imatmul__     assign + mixin/op.py:394 -- a WMMA, not an alu
# TODO(p3) tensor.py:549  __eq__          elementwise.py eq (Ops.CMPEQ)
#
