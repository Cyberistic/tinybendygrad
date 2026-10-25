# THE ALU LANE PROBE. IT ASKS `symbolic.bend`'s OWN INT LANE WHAT IT ANSWERS
# FOR `Ops.MAX`, AND COMPARES IT WITH WHAT CPython's `python_alu` ANSWERS.
#
#     ./bin/bend .agents/slop/execfix/alu.bend
#
# THE POINT: THE PACKETS FOR THE FAILING `max` CASES AND THE PASSING FLOAT `max`
# CASES ARE BYTE-IDENTICAL APART FROM THE DTYPE, SO THE DIFFERENCE IS THE LANE.
# THIS PROBE SAYS WHICH HALF OF THE LANE IS WRONG.

import ../../../tinybendygrad/helpers.bend as H
import ../../../tinybendygrad/uop/ops.bend as O
import ../../../tinybendygrad/uop/symbolic.bend as SY

def show(c: Maybe<&1, O.Const>) -> String:
  match c:
    case Some{v}:
      match v:
        case O.CInt{i}: String.concat(["CInt(", H.i64_text(i), ")"])
        case O.CFloat{f}: String.concat(["CFloat(bits=", U32.show(F32.bits(f)), ")"])
        case O.CBool{b}: String.concat(["CBool(", U32.show(Bool.to_u32(b)), ")"])
        case _: "Cother"
    case None{}: "None"

def p(nm: String, c: Maybe<&1, O.Const>) -> IO(Unit):
  IO.print(String.concat([nm, " = ", show(c)]))

def pi(nm: String, +b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, " = ", U32.show(Bool.to_u32(b))]))

def pu(nm: String, +v: U32) -> IO(Unit):
  IO.print(String.concat([nm, " = ", U32.show(v)]))

def main() -> IO(Unit):
  do IO<Unit>:
    # CPython's `python_alu[Ops.MAX]` is `max`, so max(3,7) = 7 and max(7,3) = 7.
    p("i32 MAX(3,7)", SY.exec_alu_i32(False{}, O.OpsMAX{}, SY.I3{2, 3, 7, 0}))
    p("i32 MAX(7,3)", SY.exec_alu_i32(False{}, O.OpsMAX{}, SY.I3{2, 7, 3, 0}))
    p("u32 MAX(3,7)", SY.exec_alu_i32(True{}, O.OpsMAX{}, SY.I3{2, 3, 7, 0}))
    p("i32 ADD(3,7)", SY.exec_alu_i32(False{}, O.OpsADD{}, SY.I3{2, 3, 7, 0}))
    p("i32 CMPLT(3,7)", SY.exec_alu_i32(False{}, O.OpsCMPLT{}, SY.I3{2, 3, 7, 0}))
    p("i32 CMPLT(7,3)", SY.exec_alu_i32(False{}, O.OpsCMPLT{}, SY.I3{2, 7, 3, 0}))
    p("f32 MAX(3,7)", SY.exec_alu_f32(O.OpsMAX{}, 2, 3.0, 7.0, 0.0))
    # THE COMPARISON PRIMITIVE THE INT LANE'S `max` IS BUILT ON.
    pi("i32_lt(3,7)", SY.i32_lt(False{}, 3, 7))
    pi("i32_lt(7,3)", SY.i32_lt(False{}, 7, 3))
    pu("i32_max(3,7)", SY.i32_max(False{}, 3, 7))
    pu("i32_max(7,3)", SY.i32_max(False{}, 7, 3))
    pu("u32_max(3,7)", SY.i32_max(True{}, 3, 7))
    # AND THE RAW COMPARISON, TO SEPARATE `i64_cmp` FROM `Cmp.is_lt`.
    pi("cmp_lt(3,7)", Cmp.is_lt(H.i64_cmp(H.i64_of_i32(3), H.i64_of_i32(7))))
    pi("cmp_lt(7,3)", Cmp.is_lt(H.i64_cmp(H.i64_of_i32(7), H.i64_of_i32(3))))
    pi("i64_neg(0)", H.i32_is_neg(0))
    pi("i64_neg(7)", H.i32_is_neg(7))
