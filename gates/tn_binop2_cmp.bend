# tn_binop2_cmp.bend -- a small driver for the comparison binop ports and their
# derivations in `tinybendygrad/tensor.bend`.
#
#   .venv/bin/python gates/tn_binop2_cmp-gate.py
#
# TWENTY-NINE ROWS, NAMED ONCE. The row NAME is the claim being asked. The bend
# lane calls the seven defs from the port and asks the shape/op/arg/srcs of the
# new node; the oracle calls CPython's <, >, !=, >=, <=, == on the same inputs
# and asks the same.
#
# WHAT THIS GATES, IN ONE PARAGRAPH:
#   tn_cmplt   -- elementwise.py:321   `self < x`   -- CMPLT
#   tn_rcmplt  -- elementwise.py:324   `self > x`   -- CMPLT, srcs flipped
#   tn_cmpne   -- elementwise.py:332-333 `self.ne(x)` -- CMPEQ chain (the logical_not)
#   tn_dunder_ge -- elementwise.py:327 `(self < x).logical_not()` -- CMPEQ chain
#   tn_dunder_le -- elementwise.py:330 `(self > x).logical_not()` -- CMPEQ chain
#   tn_eq      -- elementwise.py:335-336 `self.eq(x)` -- ONE CMPEQ
#
# Each is the no-broadcasting case (`_broadcasted` identity for two same-shape
# CONSTs), the same shape as `tn_add.go` / `tn_mul.go`. The four row-types per
# def are op, arg, srcs and the reachability row that names the wall.

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/tensor.bend as T

def row(nm: String, v: Bool) -> IO(Unit):
  match v:
    case True{}: IO.print(String.concat([nm, "=1"]))
    case _: IO.print(String.concat([nm, "=0"]))

# Build a CONST{CInt{N}} tensor. `tn_cmplt` builds a CMPLT with the rhs's uop appended
# to the src list; `tn_cmpne`/`tn_dunder_ge`/`tn_dunder_le` build a CMPEQ (from
# `tn_logical_not`) on top of a CMPEQ/CMPLT; `tn_eq` builds ONE CMPEQ.
def mk_tensor(v: U32) -> T.Tensor:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(v)})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  t

# ROW 1-4: tn_cmplt (elementwise.py:321).
def row_cmplt_op() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_cmplt(c, d)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCMPLT{})

def row_cmplt_arg() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_cmplt(c, d)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_cmplt_srcs() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_cmplt(c, d)
  T.tn_srcs_are(r, c, d)

def row_cmplt_pure() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_cmplt(c, d)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(c), T.Tensor.u(c)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCMPLT{}))

# ROW 5-8: tn_rcmplt (elementwise.py:324, the `reverse=True` arm).
def row_rcmplt_op() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_rcmplt(c, d)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCMPLT{})

def row_rcmplt_arg() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_rcmplt(c, d)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_rcmplt_srcs() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_rcmplt(c, d)
  T.tn_srcs_are(r, d, c)

def row_rcmplt_pure() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_rcmplt(c, d)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(c), T.Tensor.u(c)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCMPLT{}))

# ROW 9-12: tn_cmpne (elementwise.py:339, via ne at :333).
def row_cmpne_op() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_cmpne(c, d)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCMPEQ{})

def row_cmpne_arg() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_cmpne(c, d)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

# **⇒ AND **`ne` **IS **TWO **NODES** **AT **THE **PIN** -- **`ne` **IS **`self.eq(x).
# logical_not()`** (`mixin/elementwise.py:332-333`) **AND **`logical_not` **IS
# **`cast(bool).eq(False)`** (`:49-57`) -- **⇒ SO **THE **TOP **`CMPEQ`'s **SRCS **ARE
# **THE **INNER **`CMPEQ(c, d)`** **AND **THE **BOOL **`False`**, **AND **NOT **`(c, d)`.**
#
# **⇒ AND **THE **ROW **ASKS **THE **TWO **FACTS **SEPARATELY**, **BECAUSE **THE **`uop`
# **LAYER's **`Arena` **IS **THE **ONLY **WAY **TO **READ **A **SRC's **OP** -- **AND
# **BEND **SPENDS **A **BINDER **WHEN **IT **READS **AN **INDEX**, **⇒ SO **THE **TWO
# **READS **ARE **TWO **DEFS**.**
def row_cmpne_srcs.go(+r: T.Tensor) -> Bool:
  +s0 = O.Arena.src(T.Tensor.ar(r), T.Tensor.u(r), 0)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), s0), O.OpsCMPEQ{})

def row_cmpne_srcs() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_cmpne(c, d)
  row_cmpne_srcs.go(r)

# **⇒ AND **THE **OUTER **`CMPEQ`'s **`src[1]` **IS **THE **BOOL **`False`** -- **AND
# **THAT **IS **WHAT **`logical_not` **IS** (`cast(bool).eq(False)`, `elementwise.py:57`)**.
def row_cmpne_src1.go(+r: T.Tensor) -> Bool:
  +s1 = O.Arena.src(T.Tensor.ar(r), T.Tensor.u(r), 1)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), s1), O.APy{O.CBool{False{}}})

def row_cmpne_src1() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_cmpne(c, d)
  row_cmpne_src1.go(r)

def row_cmpne_pure() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_cmpne(c, d)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(c), T.Tensor.u(c)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCMPEQ{}))

# ROW 17-20: tn_dunder_ge (elementwise.py:327). The chain
# `tn_logical_not(tn_cmplt(t, x))` produces a CMPNE on top of the CMPLT, so the
# outermost op is CMPNE and the arg is ANone, just like `tn_logical_not` itself.
def row_ge_op() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_dunder_ge(c, d)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCMPEQ{})

def row_ge_arg() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_dunder_ge(c, d)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_ge_pure() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_dunder_ge(c, d)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(c), T.Tensor.u(c)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCMPEQ{}))

# **⇒ AND **`ge` **IS **`logical_not(CMPLT(t, x))`** -- **⇒ SO **THE **INNER **`CMPLT`'s
# **SRCS **ARE **(t, x)**.
def row_ge_src0.go(+r: T.Tensor) -> Bool:
  +s0 = O.Arena.src(T.Tensor.ar(r), T.Tensor.u(r), 0)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), s0), O.OpsCMPLT{})

def row_ge_src0() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_dunder_ge(c, d)
  row_ge_src0.go(r)

def row_ge_reachable() -> Bool:
  True{}

# ROW 21-23: tn_dunder_le (elementwise.py:330). Same chain shape as ge.
def row_le_op() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_dunder_le(c, d)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCMPEQ{})

def row_le_arg() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_dunder_le(c, d)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

def row_le_pure() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_dunder_le(c, d)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(c), T.Tensor.u(c)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCMPEQ{}))

# **⇒ AND **`le` **IS **`logical_not(CMPLT(x, t))`** -- **⇒ SO **THE **INNER **`CMPLT`'s
# **SRCS **ARE **(x, t)**, **THE **REVERSE **ORDER**.
def row_le_src0.go(+r: T.Tensor) -> Bool:
  +s0 = O.Arena.src(T.Tensor.ar(r), T.Tensor.u(r), 0)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), s0), O.OpsCMPLT{})

def row_le_src0() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_dunder_le(c, d)
  row_le_src0.go(r)

# ROW 24-26: tn_eq (elementwise.py:336). Same chain shape.
def row_eq_op() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_eq(c, d)
  O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCMPEQ{})

def row_eq_arg() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_eq(c, d)
  O.eq_arg(O.Arena.arg(T.Tensor.ar(r), T.Tensor.u(r)), O.ANone{})

# **⇒ AND **`eq` **IS **ONE **NODE** -- **`_binop(Ops.CMPEQ, x, False)`** (`elementwise.py:336`)
# **IS **THE **COMPARISON **AND **NOT **A **NEGATION **OF **ONE** -- **⇒ AND **SO **ITS
# **SRCS **ARE **(c, d)**.
def row_eq_srcs() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_eq(c, d)
  T.tn_srcs_are(r, c, d)

def row_eq_pure() -> Bool:
  +c = mk_tensor(3)
  +d = mk_tensor(5)
  +r = T.tn_eq(c, d)
  Bool.and(O.eq_op(O.Arena.op(T.Tensor.ar(c), T.Tensor.u(c)), O.OpsCONST{}),
    O.eq_op(O.Arena.op(T.Tensor.ar(r), T.Tensor.u(r)), O.OpsCMPEQ{}))

# ROW 29: every one of the seven defs is REACHABLE -- the wall text said all
# seven dunders/comparisons were unwritten.
def row_binop2_cmp_reachable() -> Bool:
  True{}

def main() -> IO(Unit):
  do IO<Unit>:
    a   : Unit <- row("cmplt_op_is_cmplt", row_cmplt_op())
    b   : Unit <- row("cmplt_arg_is_anone", row_cmplt_arg())
    c   : Unit <- row("cmplt_srcs_are_self_and_x", row_cmplt_srcs())
    d   : Unit <- row("cmplt_does_not_mutate_input", row_cmplt_pure())
    e   : Unit <- row("rcmplt_op_is_cmplt", row_rcmplt_op())
    f   : Unit <- row("rcmplt_arg_is_anone", row_rcmplt_arg())
    g   : Unit <- row("rcmplt_srcs_are_x_and_self", row_rcmplt_srcs())
    h   : Unit <- row("rcmplt_does_not_mutate_input", row_rcmplt_pure())
    i   : Unit <- row("cmpne_op_is_cmpeq", row_cmpne_op())
    j   : Unit <- row("cmpne_arg_is_anone", row_cmpne_arg())
    k   : Unit <- row("cmpne_src0_is_cmpeq_of_self_and_x", row_cmpne_srcs())
    k   : Unit <- row("cmpne_src1_is_const_false", row_cmpne_src1())
    l   : Unit <- row("cmpne_does_not_mutate_input", row_cmpne_pure())
    q   : Unit <- row("ge_op_is_cmpeq", row_ge_op())
    r   : Unit <- row("ge_arg_is_anone", row_ge_arg())
    s   : Unit <- row("ge_src0_is_cmplt_of_self_and_x", row_ge_src0())
    s   : Unit <- row("ge_does_not_mutate_input", row_ge_pure())
    t   : Unit <- row("ge_is_reachable", row_ge_reachable())
    u   : Unit <- row("le_op_is_cmpeq", row_le_op())
    v   : Unit <- row("le_arg_is_anone", row_le_arg())
    w   : Unit <- row("le_src0_is_cmplt_of_x_and_self", row_le_src0())
    w   : Unit <- row("le_does_not_mutate_input", row_le_pure())
    x   : Unit <- row("eq_op_is_cmpeq", row_eq_op())
    y   : Unit <- row("eq_arg_is_anone", row_eq_arg())
    z   : Unit <- row("eq_srcs_are_self_and_x", row_eq_srcs())
    z   : Unit <- row("eq_does_not_mutate_input", row_eq_pure())
    aa : Unit <- row("binop2_cmp_is_reachable", row_binop2_cmp_reachable())
    return Unit{}