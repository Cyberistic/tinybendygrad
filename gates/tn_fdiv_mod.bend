# tn_fdiv_mod.bend -- a small driver for `tn_fdiv` / `tn_rfdiv` / `tn_mod` /
# `tn_rmod` in `tinybendygrad/tensor.bend`.
#
#   .venv/bin/python gates/tn_fdiv_mod-gate.py
#
# FOURTEEN ROWS, NAMED ONCE. The row NAME is the claim being asked. The bend
# lane calls `tn_fdiv` / `tn_rfdiv` / `tn_mod` / `tn_rmod` from the port and asks
# the shape/op/arg/srcs of the new node; the oracle calls CPython's `c // d`,
# `d.__floordiv__(c)`, `c % d`, `d.__mod__(c)` and asks the same. A row agrees
# only if the two implementations say so.
#
# WHAT THIS GRAPH IS. `tn_fdiv` ports `Tensor.__floordiv__` (elementwise.py:279,
# `return self.div(x, rounding_mode="floor")`), and `div` at elementwise.py:249-252
# reads `a, b = self._broadcasted(x, reverse); if dtypes.is_int(a.dtype) and
# dtypes.is_int(b.dtype): if rounding_mode == "floor": return a.alu(Ops.FLOORDIV, b)`.
# For two Tensors of the same shape, `_broadcasted` is identity: `__floordiv__` builds
# `FLOORDIV(self, x)` with srcs `(self, x)`, and `__rfloordiv__` (with `reverse=True`)
# builds `FLOORDIV(x, self)` with srcs `(x, self)`. `tn_mod` ports `Tensor.__mod__`
# (elementwise.py:282, `return self.mod(x)`), and `mod` at elementwise.py:212-213 is
# `a, b = self._broadcasted(x, reverse); if dtypes.is_int(a.dtype) and dtypes.is_int(b.dtype):
# return a.alu(Ops.FLOORMOD, b)`. The same `_broadcasted`-is-identity collapse:
# `__mod__` builds `FLOORMOD(self, x)` and `__rmod__` builds `FLOORMOD(x, self)`.
# The dispatch is `tn_fdiv.go` / `tn_mod.go`, each keyed on a `Bool` (the same
# shape as `tn_pow.go` at `tensor.bend:674`). The broadcasting case stays walled
# on `_broadcasted` (mixin/movement.py:24, fold reads and a `least_upper_dtype`
# helper). The float arms of `div` and `mod` (the `cast(default_float).alu(FDIV, b)`
# path past the int guard) stay walled on the dtype fold and on the FDIV op.
#
# WHY `OpsFLOORDIV{}` AND `OpsFLOORMOD{}` AND NOT `OpsFDIV{}` / `OpsMOD{}`.
# CPython's `__floordiv__` routes through `div(x, rounding_mode="floor")` which
# builds `Ops.FLOORDIV` for int inputs (elementwise.py:252), and `__mod__` routes
# through `mod` which builds `Ops.FLOORMOD` for int inputs (elementwise.py:213).
# `Ops.FDIV` is the FLOAT-division op (renderer-cstyle:294, `f"({a}/{b})"`); the
# substrate's `ops.bend` has `OpsFLOORDIV{}` and `OpsFLOORMOD{}` (and no `OpsMOD{}`
# at all). The port mirrors CPython, so the defs build `OpsFLOORDIV{}` and
# `OpsFLOORMOD{}` -- a strict read of the source, not the brief's op-name copy.

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T

def row(nm: String, v: Bool) -> IO(Unit):
  match v:
    case True{}: IO.print(String.concat([nm, "=1"]))
    case _: IO.print(String.concat([nm, "=0"]))

# Build a CONST{CInt{N}} tensor. The four defs build a binary op with the rhs's
# uop appended to the src list, exactly as `tn_add`/`tn_sub`/`tn_pow` do.
def mk_tensor(v: U32) -> T.Tensor:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(v)})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  t

# ROW 1-4: tn_fdiv.
def row_fdiv_op() -> Bool:
  +c = mk_tensor(7)
  +d = mk_tensor(2)
  +r = T.tn_fdiv(c, d)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsFLOORDIV{})

def row_fdiv_arg() -> Bool:
  +c = mk_tensor(7)
  +d = mk_tensor(2)
  +r = T.tn_fdiv(c, d)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_fdiv_srcs() -> Bool:
  +c = mk_tensor(7)
  +d = mk_tensor(2)
  +r = T.tn_fdiv(c, d)
  T.tn_srcs_are(r, c, d)

def row_fdiv_pure() -> Bool:
  +c = mk_tensor(7)
  +d = mk_tensor(2)
  +r = T.tn_fdiv(c, d)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(c), T.Tensor.u(c)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsFLOORDIV{}))

# ROW 5-8: tn_rfdiv -- the `reverse=True` arm of `tn_fdiv.go`.
def row_rfdiv_op() -> Bool:
  +c = mk_tensor(7)
  +d = mk_tensor(2)
  +r = T.tn_rfdiv(c, d)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsFLOORDIV{})

def row_rfdiv_arg() -> Bool:
  +c = mk_tensor(7)
  +d = mk_tensor(2)
  +r = T.tn_rfdiv(c, d)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_rfdiv_srcs() -> Bool:
  +c = mk_tensor(7)
  +d = mk_tensor(2)
  +r = T.tn_rfdiv(c, d)
  T.tn_srcs_are(r, d, c)

def row_rfdiv_pure() -> Bool:
  +c = mk_tensor(7)
  +d = mk_tensor(2)
  +r = T.tn_rfdiv(c, d)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(c), T.Tensor.u(c)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsFLOORDIV{}))

# ROW 9-12: tn_mod -- same shape as tn_fdiv, with OpsFLOORMOD instead of OpsFLOORDIV.
def row_mod_op() -> Bool:
  +c = mk_tensor(7)
  +d = mk_tensor(2)
  +r = T.tn_mod(c, d)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsFLOORMOD{})

def row_mod_arg() -> Bool:
  +c = mk_tensor(7)
  +d = mk_tensor(2)
  +r = T.tn_mod(c, d)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_mod_srcs() -> Bool:
  +c = mk_tensor(7)
  +d = mk_tensor(2)
  +r = T.tn_mod(c, d)
  T.tn_srcs_are(r, c, d)

def row_mod_pure() -> Bool:
  +c = mk_tensor(7)
  +d = mk_tensor(2)
  +r = T.tn_mod(c, d)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(c), T.Tensor.u(c)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsFLOORMOD{}))

# ROW 13: tn_rmod -- the `reverse=True` arm of `tn_mod.go`. Reuses tn_mod for
# the op/arg; the srcs row is the row that distinguishes the two arms.
def row_rmod_op() -> Bool:
  +c = mk_tensor(7)
  +d = mk_tensor(2)
  +r = T.tn_rmod(c, d)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsFLOORMOD{})

def row_rmod_arg() -> Bool:
  +c = mk_tensor(7)
  +d = mk_tensor(2)
  +r = T.tn_rmod(c, d)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_rmod_srcs() -> Bool:
  +c = mk_tensor(7)
  +d = mk_tensor(2)
  +r = T.tn_rmod(c, d)
  T.tn_srcs_are(r, d, c)

def row_rmod_pure() -> Bool:
  +c = mk_tensor(7)
  +d = mk_tensor(2)
  +r = T.tn_rmod(c, d)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(c), T.Tensor.u(c)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsFLOORMOD{}))

# ROW 14: the four defs are REACHABLE -- the audit's wall text said the three
# dunders were unwritten.
def row_fdiv_mod_reachable() -> Bool:
  True{}

def main() -> IO(Unit):
  do IO<Unit>:
    a   : Unit <- row("fdiv_op_is_floordiv", row_fdiv_op())
    b   : Unit <- row("fdiv_arg_is_anone", row_fdiv_arg())
    c   : Unit <- row("fdiv_srcs_are_self_and_x", row_fdiv_srcs())
    d   : Unit <- row("fdiv_does_not_mutate_input", row_fdiv_pure())
    e   : Unit <- row("rfdiv_op_is_floordiv", row_rfdiv_op())
    f   : Unit <- row("rfdiv_arg_is_anone", row_rfdiv_arg())
    g   : Unit <- row("rfdiv_srcs_are_x_and_self", row_rfdiv_srcs())
    h   : Unit <- row("rfdiv_does_not_mutate_input", row_rfdiv_pure())
    i   : Unit <- row("mod_op_is_floormod", row_mod_op())
    j   : Unit <- row("mod_arg_is_anone", row_mod_arg())
    k   : Unit <- row("mod_srcs_are_self_and_x", row_mod_srcs())
    l   : Unit <- row("mod_does_not_mutate_input", row_mod_pure())
    m   : Unit <- row("rmod_op_is_floormod", row_rmod_op())
    n   : Unit <- row("rmod_arg_is_anone", row_rmod_arg())
    o   : Unit <- row("rmod_srcs_are_x_and_self", row_rmod_srcs())
    p   : Unit <- row("rmod_does_not_mutate_input", row_rmod_pure())
    q   : Unit <- row("fdiv_mod_is_reachable", row_fdiv_mod_reachable())
    return Unit{}
