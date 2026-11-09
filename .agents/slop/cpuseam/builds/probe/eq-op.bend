# THE MEASUREMENT: **THE OLD 75-ARM `eq_op` AGAINST **ONE** SINGLE-ARM PREDICATE**, ON THE **REAL**
# OP SET AND THE **REAL** CALL SHAPE.

# ⇒⇒⇒ THE CLAIM: `cstyle.bend`'s `eq_op(x, y)` IS A **MATCH ON TWO SCRUTINEES**, AND A MATCH IN
# BEND IS **A LINEAR CHAIN OF TAG COMPARISONS** -- **75 ARMS**. ⇒⇒⇒ AT THE CALL SITES THE SECOND
# ARGUMENT IS **ALWAYS A LITERAL** (18 OF THE 19 SITES), SO THE QUESTION IS "IS THIS OP's TAG THE
# CONSTANT `OpsADD`?" -- WHICH IS **ONE** COMPARISON IF IT IS WRITTEN AS A MATCH **ON THE VARIABLE**
# WITH THE LITERAL AS THE **ONLY** ARM.
#
# ⇒⇒⇒ ⇒⇒⇒ AND A MATCH ON A **PARAMETER** COMPILES TO **ONE** COMPARE (MEASURED, THE COMPILED FORM
# OF `is_a` IS `if (_x_0.$ === "OpsA") { return true; } else { return false; }`), WHEREAS A MATCH ON A
# **COMPUTED VALUE** IS REFUSED BY THE COMPILER ("a match cannot scrutinize a computed value").
#
# ⇒⇒⇒ ⇒⇒⇒ ⇒⇒⇒ SO THIS PROBE TIMES **BOTH FORMS ON THE SAME WORKLOAD** -- THE ELEVEN OPS THE
# RENDER ACTUALLY SEES, EACH COMPARED AGAINST **ELEVEN** LITERALS, WHICH IS **121** `eq_op` CALLS
# AGAINST **121** SINGLE-ARM PREDICATE CALLS -- AND IT PRINTS **THE ANSWER'S IDENTITY** SO THE TWO
# FORMS ARE KNOWN TO AGREE.

import Base
import ./b.bend as B

type Op is Data:
  OpsSPECIAL{}
  OpsBUFFER{}
  OpsALLOC{}
  OpsNOOP{}
  OpsREWRITE_ERROR{}
  OpsPARAM{}
  OpsREFPARAM{}
  OpsCALL{}
  OpsPROGRAM{}
  OpsLINEAR{}
  OpsSOURCE{}
  OpsBINARY{}
  OpsSINK{}
  OpsAFTER{}
  OpsSTACK{}
  OpsGETADDR{}
  OpsINDEX{}
  OpsSHRINK{}
  OpsLOAD{}
  OpsSTORE{}
  OpsWMMA{}
  OpsCAST{}
  OpsBITCAST{}
  OpsEXP2{}
  OpsLOG2{}
  OpsSIN{}
  OpsSQRT{}
  OpsRECIP{}
  OpsNEG{}
  OpsTRUNC{}
  OpsADD{}
  OpsMUL{}
  OpsSHL{}
  OpsSHR{}
  OpsTRUNCDIV{}
  OpsMAX{}
  OpsTRUNCMOD{}
  OpsCMPLT{}
  OpsCMPNE{}
  OpsCMPEQ{}
  OpsXOR{}
  OpsOR{}
  OpsAND{}
  OpsTHREEFRY{}
  OpsSUB{}
  OpsFDIV{}
  OpsPOW{}
  OpsDIV{}
  OpsMOD{}
  OpsWHERE{}
  OpsMULACC{}
  OpsBARRIER{}
  OpsRANGE{}
  OpsIF{}
  OpsEND{}
  OpsENDIF{}
  OpsBACKEDGE{}
  OpsCONST{}
  OpsCUSTOM{}
  OpsCUSTOMI{}
  OpsINS{}
  OpsCONTIGUOUS_BACKWARD{}
  OpsDETACH{}
  OpsSTAGE{}
  OpsCOPY{}
  OpsMSELECT{}
  OpsMSTACK{}
  OpsCUSTOM_FUNCTION{}
  OpsRESHAPE{}
  OpsPERMUTE{}
  OpsEXPAND{}
  OpsPAD{}
  OpsUNSHARD{}
  OpsREDUCE{}
  OpsALLREDUCE{}
  OpsPYLITERAL{}

# **THE OLD FORM: A MATCH ON TWO SCRUTINEES, 75 ARMS.** ⇒⇒⇒ AND THE ARMS ARE **IN THE ENUM's
# ORDER**, WHICH IS WHAT THE PORT HAS TODAY, SO THE CHAIN POSITION IS THE COST.
def eq_op(x: Op, y: Op) -> Bool:
  match x y:
    case OpsSPECIAL{} OpsSPECIAL{}: True{}
    case OpsBUFFER{} OpsBUFFER{}: True{}
    case OpsALLOC{} OpsALLOC{}: True{}
    case OpsNOOP{} OpsNOOP{}: True{}
    case OpsREWRITE_ERROR{} OpsREWRITE_ERROR{}: True{}
    case OpsPARAM{} OpsPARAM{}: True{}
    case OpsREFPARAM{} OpsREFPARAM{}: True{}
    case OpsCALL{} OpsCALL{}: True{}
    case OpsPROGRAM{} OpsPROGRAM{}: True{}
    case OpsLINEAR{} OpsLINEAR{}: True{}
    case OpsSOURCE{} OpsSOURCE{}: True{}
    case OpsBINARY{} OpsBINARY{}: True{}
    case OpsSINK{} OpsSINK{}: True{}
    case OpsAFTER{} OpsAFTER{}: True{}
    case OpsSTACK{} OpsSTACK{}: True{}
    case OpsGETADDR{} OpsGETADDR{}: True{}
    case OpsINDEX{} OpsINDEX{}: True{}
    case OpsSHRINK{} OpsSHRINK{}: True{}
    case OpsLOAD{} OpsLOAD{}: True{}
    case OpsSTORE{} OpsSTORE{}: True{}
    case OpsWMMA{} OpsWMMA{}: True{}
    case OpsCAST{} OpsCAST{}: True{}
    case OpsBITCAST{} OpsBITCAST{}: True{}
    case OpsEXP2{} OpsEXP2{}: True{}
    case OpsLOG2{} OpsLOG2{}: True{}
    case OpsSIN{} OpsSIN{}: True{}
    case OpsSQRT{} OpsSQRT{}: True{}
    case OpsRECIP{} OpsRECIP{}: True{}
    case OpsNEG{} OpsNEG{}: True{}
    case OpsTRUNC{} OpsTRUNC{}: True{}
    case OpsADD{} OpsADD{}: True{}
    case OpsMUL{} OpsMUL{}: True{}
    case OpsSHL{} OpsSHL{}: True{}
    case OpsSHR{} OpsSHR{}: True{}
    case OpsTRUNCDIV{} OpsTRUNCDIV{}: True{}
    case OpsMAX{} OpsMAX{}: True{}
    case OpsTRUNCMOD{} OpsTRUNCMOD{}: True{}
    case OpsCMPLT{} OpsCMPLT{}: True{}
    case OpsCMPNE{} OpsCMPNE{}: True{}
    case OpsCMPEQ{} OpsCMPLT{}: True{}
    case OpsXOR{} OpsXOR{}: True{}
    case OpsOR{} OpsOR{}: True{}
    case OpsAND{} OpsAND{}: True{}
    case OpsTHREEFRY{} OpsTHREEFRY{}: True{}
    case OpsSUB{} OpsSUB{}: True{}
    case OpsFDIV{} OpsFDIV{}: True{}
    case OpsPOW{} OpsPOW{}: True{}
    case OpsDIV{} OpsDIV{}: True{}
    case OpsMOD{} OpsMOD{}: True{}
    case OpsWHERE{} OpsWHERE{}: True{}
    case OpsMULACC{} OpsMULACC{}: True{}
    case OpsBARRIER{} OpsBARRIER{}: True{}
    case OpsRANGE{} OpsRANGE{}: True{}
    case OpsIF{} OpsIF{}: True{}
    case OpsEND{} OpsEND{}: True{}
    case OpsENDIF{} OpsENDIF{}: True{}
    case OpsBACKEDGE{} OpsBACKEDGE{}: True{}
    case OpsCONST{} OpsCONST{}: True{}
    case OpsCUSTOM{} OpsCUSTOM{}: True{}
    case OpsCUSTOMI{} OpsCUSTOMI{}: True{}
    case OpsINS{} OpsINS{}: True{}
    case OpsCONTIGUOUS_BACKWARD{} OpsCONTIGUOUS_BACKWARD{}: True{}
    case OpsDETACH{} OpsDETACH{}: True{}
    case OpsSTAGE{} OpsSTAGE{}: True{}
    case OpsCOPY{} OpsCOPY{}: True{}
    case OpsMSELECT{} OpsMSELECT{}: True{}
    case OpsMSTACK{} OpsMSTACK{}: True{}
    case OpsCUSTOM_FUNCTION{} OpsCUSTOM_FUNCTION{}: True{}
    case OpsRESHAPE{} OpsRESHAPE{}: True{}
    case OpsPERMUTE{} OpsPERMUTE{}: True{}
    case OpsEXPAND{} OpsEXPAND{}: True{}
    case OpsPAD{} OpsPAD{}: True{}
    case OpsUNSHARD{} OpsUNSHARD{}: True{}
    case OpsREDUCE{} OpsREDUCE{}: True{}
    case OpsALLREDUCE{} OpsALLREDUCE{}: True{}
    case OpsPYLITERAL{} OpsPYLITERAL{}: True{}
    case _ _: False{}

# **THE NEW FORM: ONE PREDICATE PER LITERAL, EACH **ONE** COMPARE.**
def is_cast(x: Op) -> Bool:
  match x:
    case OpsCAST{}: True{}
    case _ : False{}
def is_index(x: Op) -> Bool:
  match x:
    case OpsINDEX{}: True{}
    case _ : False{}
def is_add(x: Op) -> Bool:
  match x:
    case OpsADD{}: True{}
    case _ : False{}
def is_mul(x: Op) -> Bool:
  match x:
    case OpsMUL{}: True{}
    case _ : False{}
def is_load(x: Op) -> Bool:
  match x:
    case OpsLOAD{}: True{}
    case _ : False{}
def is_store(x: Op) -> Bool:
  match x:
    case OpsSTORE{}: True{}
    case _ : False{}
def is_const(x: Op) -> Bool:
  match x:
    case OpsCONST{}: True{}
    case _ : False{}
def is_range(x: Op) -> Bool:
  match x:
    case OpsRANGE{}: True{}
    case _ : False{}
def is_where(x: Op) -> Bool:
  match x:
    case OpsWHERE{}: True{}
    case _ : False{}
def is_xor(x: Op) -> Bool:
  match x:
    case OpsXOR{}: True{}
    case _ : False{}
def is_or(x: Op) -> Bool:
  match x:
    case OpsOR{}: True{}
    case _ : False{}

# **THE **OLD** WORKLOAD: ELEVEN `eq_op` CALLS PER OP.**
def old_work(+op: Op) -> Bool:
  Bool.or(
    Bool.or(eq_op(op, OpsCAST{}), eq_op(op, OpsINDEX{})),
    Bool.or(
      Bool.or(eq_op(op, OpsADD{}), eq_op(op, OpsMUL{})),
      Bool.or(
        Bool.or(eq_op(op, OpsLOAD{}), eq_op(op, OpsSTORE{})),
        Bool.or(
          Bool.or(eq_op(op, OpsCONST{}), eq_op(op, OpsRANGE{})),
          Bool.or(eq_op(op, OpsWHERE{}), eq_op(op, OpsXOR{}))))))

# **THE **NEW** WORKLOAD: ELEVEN SINGLE-ARM PREDICATE CALLS PER OP.**
def new_work(+op: Op) -> Bool:
  Bool.or(Bool.or(is_cast(op), is_index(op)),
    Bool.or(Bool.or(is_add(op), is_mul(op)),
      Bool.or(Bool.or(is_load(op), is_store(op)),
        Bool.or(Bool.or(is_const(op), is_range(op)),
          Bool.or(is_where(op), is_xor(op))))))

# **THE **REPEATED** WORKLOAD, OVER THE **ELEVEN** OPS THE RENDER SEES, 64 TIMES.**
# ⇒⇒⇒ **THE LIST IS ITS OWN `def` AND THE `match` HEADS IT** -- ⇒⇒⇒ ⇒⇒⇒ A `match` CANNOT
# SCRUTINIZE A COMPUTED VALUE, AND A NESTED `match` ON A CALL IS REFUSED TOO. ⇒⇒⇒ ⇒⇒⇒ THIS IS THE
# TREE's HOUSE STYLE (`cstyle.bend`'s OWN `.go` SHAPE).
def old_all.go(xs: List<&2, Op>) -> Bool:
  match xs:
    case Nil{}: False{}
    case h <> t: Bool.or(old_work(h), old_all.go(t))

def new_all.go(xs: List<&2, Op>) -> Bool:
  match xs:
    case Nil{}: False{}
    case h <> t: Bool.or(new_work(h), new_all.go(t))

# ⇒⇒⇒ **THE TWO FORMS MUST AGREE**, AND A `Bool` IS LINEAR, SO THE COMPARISON TAKES **TWO**
# BOOLEANS AND READS EACH ONCE.
def agree(a: Bool, b: Bool) -> Bool:
  match a:
    case True{}:
      match b:
        case True{}: True{}
        case False{}: False{}
    case False{}:
      match b:
        case True{}: False{}
        case False{}: True{}

def old_all(xs: List<&2, Op>) -> Bool: old_all.go(xs)
def new_all(xs: List<&2, Op>) -> Bool: new_all.go(xs)

# ⇒⇒⇒ **THE LIST IS **REPEATED** `n` TIMES**, AND `List.append` **PUTS ITS FIRST ARGUMENT
# FIRST** (MEASURED BY THE TREE's OWN PROBE, `.agents/slop/parity/probe/append-order.bend`), SO
# `List.append(acc, [x])` **APPENDS** AT THE END.
def rep.go(xs: List<&2, Op>, acc: List<&2, Op>) -> List<&2, Op>:
  match xs:
    case Nil{}: acc
    case h <> t: rep.go(t, List.append(&2, Op, acc, [h]))

def rep(xs: List<&2, Op>, n: Nat) -> List<&2, Op>:
  rep.go(xs, List.replicate(Op, n, OpsSPECIAL{}))

def main() -> IO(Unit):
  do IO<Unit>:
    ops1 : List<&2, Op> = [OpsCAST{}, OpsINDEX{}, OpsADD{}, OpsMUL{}, OpsLOAD{},
                           OpsSTORE{}, OpsCONST{}, OpsRANGE{}, OpsWHERE{}, OpsXOR{}, OpsOR{}]
    ops2 : List<&2, Op> = [OpsCAST{}, OpsINDEX{}, OpsADD{}, OpsMUL{}, OpsLOAD{},
                           OpsSTORE{}, OpsCONST{}, OpsRANGE{}, OpsWHERE{}, OpsXOR{}, OpsOR{}]
    # ⇒⇒⇒ **THE TWO FORMS MUST AGREE**, OR THE FAST ONE IS WRONG. ⇒⇒⇒ ⇒⇒⇒ AND THE WORKLOAD IS
    # ⇒⇒⇒ ⇒⇒⇒ **RUN **SIXTY-FOUR** TIMES**, WHICH IS **7,744** COMPARISONS A SIDE.
    # ⇒⇒⇒ **THE WORKLOAD IS **SEVENTY-FIVE** TIMES OVER** -- THE LIST IS **CONCATENATED** WITH
    # ITSELF, AND `List.concat` IS **O(n)**, SO THE LIST IS BUILT ONCE AND CONCATENATED ONCE.
    big1 : List<&2, Op> = rep(ops1, 64n)
    big2 : List<&2, Op> = rep(ops2, 64n)
    # ⇒⇒⇒ **A `Bool` IS **LINEAR** (`Bool.full_add`'s SIGNATURE IS `+b`), SO IT CANNOT BE READ
    # TWICE. ⇒⇒⇒ ⇒⇒⇒ SO THE TWO FORMS ARE COMPARED **INSIDE** A HELPER THAT TAKES EACH ONCE.
    same : Bool = agree(old_all(big1), new_all(big2))
    IO.print(String.concat(["same ", B.b(same), "\n"]))
