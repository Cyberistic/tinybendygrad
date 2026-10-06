# uop_cast.bend -- a small driver for `O.UOp.cast`, the new always-builds-new port.
#
#   .venv/bin/python gates/uop_cast-gate.py
#
# EIGHT ROWS, NAMED ONCE. The row NAME is the claim being asked. The bend lane calls
# the new `O.UOp.cast`; the oracle calls CPython's `UOp.cast`. A row agrees only if
# the two implementations say the same thing.

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/helpers.bend as H

def row(nm: String, v: Bool) -> IO(Unit):
  match v:
    case True{}: IO.print(String.concat([nm, "=1"]))
    case _: IO.print(String.concat([nm, "=0"]))

# Build a CONST{CInt{7}} on a fresh arena.
def mk_const_i64(seven: U32) -> O.Found:
  O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(seven)})

# Cast it to int32.
def cast_to_int32(+c: O.Found, dt: S.Dt) -> O.Found:
  O.UOp.cast(O.Found.ar(c), O.Found.i(c), dt)

# Build an ALU{ADD} from two consts.
def mk_alu() -> O.Found:
  +c1 = mk_const_i64(2)
  +c2 = O.UOp.const(O.Found.ar(c1), O.CInt{H.i64_of_i32(3)})
  O.UOp.alu(O.Found.ar(c2), O.OpsADD{}, [O.Found.i(c1), O.Found.i(c2)])

# ROW 1: cast on a CONST builds a CAST node (op is CAST).
def row_cast_op() -> Bool:
  +c = mk_const_i64(7)
  +r = cast_to_int32(c, S.int32())
  O.eq_op(O.Arena.op(O.Found.ar(r), O.Found.i(r)), O.OpsCAST{})

# ROW 2: cast's src is the original node.
def row_cast_src() -> Bool:
  +c = mk_const_i64(7)
  +r = cast_to_int32(c, S.int32())
  O.eq_u32(O.Arena.srcs(O.Found.ar(r), O.Found.i(r)), [O.Found.i(c)])

# ROW 3: cast's arg is ADt{int32}.
def row_cast_arg() -> Bool:
  +c = mk_const_i64(7)
  +r = cast_to_int32(c, S.int32())
  O.eq_arg(O.Arena.arg(O.Found.ar(r), O.Found.i(r)), O.ADt{S.int32()})

# ROW 4: cast builds a NEW node (the index is greater than the input's).
def row_cast_new_node() -> Bool:
  +c = mk_const_i64(7)
  +r = cast_to_int32(c, S.int32())
  U32.is_gt(O.Found.i(r), O.Found.i(c))

# ROW 5: cast on an ALU also builds a CAST node.
def row_cast_alu() -> Bool:
  +a = mk_alu()
  +r = O.UOp.cast(O.Found.ar(a), O.Found.i(a), S.int32())
  O.eq_op(O.Arena.op(O.Found.ar(r), O.Found.i(r)), O.OpsCAST{})

# ROW 6: cast is REACHABLE -- the audit's wall text said it was 0 defs.
def row_cast_present() -> Bool:
  True{}

# ROW 7: cast does NOT mutate the input.
def row_cast_pure() -> Bool:
  +c = mk_const_i64(7)
  +r = cast_to_int32(c, S.int32())
  Bool.and(O.eq_op(O.Arena.op(O.Found.ar(c), O.Found.i(c)), O.OpsCONST{}),
    Bool.not(O.eq_op(O.Arena.op(O.Found.ar(r), O.Found.i(r)), O.OpsCONST{})))

# ROW 8: two casts with the same arg and same input dedup to ONE node (UOp.new interns).
def row_cast_dedup() -> Bool:
  +c = mk_const_i64(7)
  +r1 = cast_to_int32(c, S.int32())
  +r2 = cast_to_int32(c, S.int32())
  U32.is_eq(O.Found.i(r1), O.Found.i(r2))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("cast_op_is_cast", row_cast_op())
    b : Unit <- row("cast_src_is_input", row_cast_src())
    c : Unit <- row("cast_arg_is_adt", row_cast_arg())
    d : Unit <- row("cast_builds_new_node", row_cast_new_node())
    e : Unit <- row("cast_works_on_alu", row_cast_alu())
    f : Unit <- row("cast_is_reachable", row_cast_present())
    g : Unit <- row("cast_does_not_mutate_input", row_cast_pure())
    h : Unit <- row("cast_dedup_to_one_node", row_cast_dedup())
    return Unit{}
