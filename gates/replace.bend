# replace.bend -- a small driver for `O.UOp.replace`, used by the gate to confirm
# the port matches CPython's behaviour. Touches only finished substrate: the empty
# arena, `UOp.const`, and `UOp.replace` itself.
#
#   .venv/bin/python gates/replace-gate.py
#
# ROWS, NAMED ONCE. Each name is a claim about WHICH PROPERTY of `UOp.replace` is being
# asked, so the same name appears on the bend lane and the oracle, and a row renamed
# on one lane only is a gate that stopped asking its question without saying so.

import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O

def row(nm: String, v: Bool) -> IO(Unit):
  match v:
    case True{}: IO.print(String.concat([nm, "=1"]))
    case _: IO.print(String.concat([nm, "=0"]))

# `c0`: a CONST{CInt{7}} at index 1 in an empty arena. The simplest non-bottom node.
def c0() -> O.Found:
  O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(7)})

# `c1`: a CONST{CInt{3}} built on top of `c0`'s arena, at index 2.
def c1() -> O.Found:
  +c = c0()
  O.UOp.const(O.Found.ar(c), O.CInt{H.i64_of_i32(3)})

# An ALU{ADD} node with two srcs, built on top of c1's arena, at index 3.
def alu_add() -> O.Found:
  +a = c0()
  +b = c1()
  O.UOp.alu(O.Found.ar(b), O.OpsADD{}, [O.Found.i(a), O.Found.i(b)])

# ROW 1: replace with all None{} returns the SAME Found (identity).
# ROW 2: replace(op=Some{ADD}, ...) on a CONST node returns a node whose op IS OpsADD{}.
# ROW 3: replace(src=Some{[c]}, ...) on a CONST returns a node whose srcs ARE [c] (in the
#         same arena, since [c] is an index).
# ROW 4: replace(arg=Some{ADt{int32}}, ...) on a CONST returns a node whose arg IS ADt{int32}.
# ROW 5: replace(tag=Some{TBool{True}}, ...) on a CONST returns a node whose tag IS TBool{True}.
# ROW 6: replace(src=Some{[c2, c1]}, ...) on an ALU{ADD} returns a node whose srcs ARE [c2, c1]
#         (reversed order).
# ROW 7: replace(op=Some{ADD}, ...) on a CONST does NOT match the original (op changes).
# ROW 8: replace(arg=Some{ANone{}}, ...) on a CONST with arg=CInt returns a node with arg=ANone.

def row_same() -> Bool:
  +c = c0()
  +r = O.UOp.replace(O.Found.ar(c), O.Found.i(c), None{}, None{}, None{}, None{})
  U32.is_eq(O.Found.i(c), O.Found.i(r))

def row_op_changed() -> Bool:
  +c = c0()
  +r = O.UOp.replace(O.Found.ar(c), O.Found.i(c), Some{O.OpsADD{}}, None{}, None{}, None{})
  O.eq_op(O.Arena.op(O.Found.ar(r), O.Found.i(r)), O.OpsADD{})

def row_src_set() -> Bool:
  +c = c0()
  +a = c1()
  +r = O.UOp.replace(O.Found.ar(a), O.Found.i(a), None{}, Some{[O.Found.i(c)]}, None{}, None{})
  O.eq_u32(O.Arena.srcs(O.Found.ar(r), O.Found.i(r)), [O.Found.i(c)])

def row_arg_set() -> Bool:
  +c = c0()
  +r = O.UOp.replace(O.Found.ar(c), O.Found.i(c), None{}, None{}, Some{O.ADt{S.int32()}}, None{})
  O.eq_arg(O.Arena.arg(O.Found.ar(r), O.Found.i(r)), O.ADt{S.int32()})

def row_tag_set() -> Bool:
  +c = c0()
  +r = O.UOp.replace(O.Found.ar(c), O.Found.i(c), None{}, None{}, None{}, Some{O.TBool{True{}}})
  O.eq_tag(O.Arena.tag(O.Found.ar(r), O.Found.i(r)), O.TBool{True{}})

def row_src_reversed() -> Bool:
  +a = c0()
  +b = c1()
  +al = alu_add()
  +r = O.UOp.replace(O.Found.ar(al), O.Found.i(al), None{}, Some{[O.Found.i(b), O.Found.i(a)]}, None{}, None{})
  O.eq_u32(O.Arena.srcs(O.Found.ar(r), O.Found.i(r)), [O.Found.i(b), O.Found.i(a)])

def row_op_is_change() -> Bool:
  +c = c0()
  +r = O.UOp.replace(O.Found.ar(c), O.Found.i(c), Some{O.OpsADD{}}, None{}, None{}, None{})
  Bool.not(O.eq_op(O.Arena.op(O.Found.ar(r), O.Found.i(r)), O.Arena.op(O.Found.ar(c), O.Found.i(c))))

def row_arg_to_anone() -> Bool:
  +c = c0()
  +r = O.UOp.replace(O.Found.ar(c), O.Found.i(c), None{}, None{}, Some{O.ANone{}}, None{})
  O.eq_arg(O.Arena.arg(O.Found.ar(r), O.Found.i(r)), O.ANone{})

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("identity_returns_self", row_same())
    b : Unit <- row("replace_op_sets_op", row_op_changed())
    c : Unit <- row("replace_src_sets_srcs", row_src_set())
    d : Unit <- row("replace_arg_sets_arg", row_arg_set())
    e : Unit <- row("replace_tag_sets_tag", row_tag_set())
    f : Unit <- row("replace_src_two_elements", row_src_reversed())
    g : Unit <- row("replace_op_actually_changes_op", row_op_is_change())
    h : Unit <- row("replace_arg_to_anone", row_arg_to_anone())
    return Unit{}
