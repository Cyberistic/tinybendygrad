# THE ALU LANE PROBE, FOR THE VSLANE FAMILY.

#     ./bin/bend .agents/slop/vslane/alu.bend
#
# IT ASKS `symbolic.bend`'s OWN TWO LANES WHAT THEY ANSWER, FOR THE OPS THE
# DIVERGING FIXTURES USE. THE TEMPLATE IS `.agents/slop/execfix/alu.bend`.

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

def main() -> IO(Unit):
  do IO<Unit>:
    # ---- THE SQRT CHAIN, EXACTLY AS THE PACKET SPELLS IT -------------------
    # f32.sqrt.0: INDEX(1.0) -> CMPLT -> CMPNE -> WHERE -> WHERE -> MUL -> SQRT
    p("f32 CMPLT(1.0,0.0)", SY.exec_alu_f32(O.OpsCMPLT{}, 2, 1.0, 0.0, 0.0))
    p("f32 CMPNE(1.0,0.0)", SY.exec_alu_f32(O.OpsCMPNE{}, 2, 1.0, 0.0, 0.0))
    p("f32 WHERE(0.0,-1.0,1.0)", SY.exec_alu_f32(O.OpsWHERE{}, 3, 0.0, F32.neg(1.0), 1.0))
    p("f32 WHERE(1.0,1.0,0.0)", SY.exec_alu_f32(O.OpsWHERE{}, 3, 1.0, 1.0, 0.0))
    p("f32 MUL(1.0,1.0)", SY.exec_alu_f32(O.OpsMUL{}, 2, 1.0, 1.0, 0.0))
    p("f32 SQRT(1.0)", SY.exec_alu_f32(O.OpsSQRT{}, 1, 1.0, 0.0, 0.0))
    p("f32 SQRT(2.0)", SY.exec_alu_f32(O.OpsSQRT{}, 1, 2.0, 0.0, 0.0))
    p("f32 SQRT(4.0)", SY.exec_alu_f32(O.OpsSQRT{}, 1, 4.0, 0.0, 0.0))
    # ---- THE OTHER MATHY OPS ----------------------------------------------
    p("f32 LOG2(2.0)", SY.exec_alu_f32(O.OpsLOG2{}, 1, 2.0, 0.0, 0.0))
    p("f32 EXP2(2.0)", SY.exec_alu_f32(O.OpsEXP2{}, 1, 2.0, 0.0, 0.0))
    p("f32 RECIPROCAL(2.0)", SY.exec_alu_f32(O.OpsRECIPROCAL{}, 1, 2.0, 0.0, 0.0))
    # ---- THE INTEGER LANE --------------------------------------------------
    p("i32 CMPNE(0,1)", SY.exec_alu_i32(False{}, O.OpsCMPNE{}, SY.I3{2, 0, 1, 0}))
    p("i32 CMPEQ(0,1)", SY.exec_alu_i32(False{}, O.OpsCMPEQ{}, SY.I3{2, 0, 1, 0}))
    p("i32 CMPLT(0,1)", SY.exec_alu_i32(False{}, O.OpsCMPLT{}, SY.I3{2, 0, 1, 0}))
    p("i32 SHL(1,2)", SY.exec_alu_i32(False{}, O.OpsSHL{}, SY.I3{2, 1, 2, 0}))
    p("i32 SHR(4,2)", SY.exec_alu_i32(False{}, O.OpsSHR{}, SY.I3{2, 4, 2, 0}))
    p("i32 CMOD(7,3)", SY.exec_alu_i32(False{}, O.OpsCMOD{}, SY.I3{2, 7, 3, 0}))
    p("i32 MUL(3,7)", SY.exec_alu_i32(False{}, O.OpsMUL{}, SY.I3{2, 3, 7, 0}))
    p("i32 ADD(3,7)", SY.exec_alu_i32(False{}, O.OpsADD{}, SY.I3{2, 3, 7, 0}))
    p("i32 NEG(3)", SY.exec_alu_i32(False{}, O.OpsNEG{}, SY.I3{1, 3, 0, 0}))
