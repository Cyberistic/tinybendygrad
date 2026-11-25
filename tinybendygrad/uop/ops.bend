# ops.bend -- tinygrad/uop/ops.py.
# THIS FILE IS THE GATE. .agents/TODO.md: "if the arena does not work here, the
#   A UOp is a U32 index into an append-only `List<Node>`, threaded through
# WHY AN INDEX AND NOT A TREE. tinygrad hash-conses UOps in
# WHAT THE ARENA COST. This is the list a reviewer should check first.
#   1. NO GLOBAL STATE. `Array<T>` masks its index (`Array.get` computes
# WHERE DEFS WERE REORDERED, and why. Bend has no forward references: a def may
# NOT PORTED, one line each, with the reason. The block at the bottom is the
# `./../dtype.bend` IS NOT IMPORTED, and that is worth a line. The gate says
# THE REBASE DEPENDENCY LIST -- what `78d482262` needs from the OTHER files.
# `78d482262` ("range AxisType is first / delete REDUCE/UNROLL") is 53 files and
# 16 of the 53 are under `tinygrad/`; one is this one. Of the other 15, ELEVEN read
#   #  file                     needs from ops.py                        lines
# `tinygrad/uop/__init__.py` (`Ops`, `GroupOp`) is NOT among the 53 at all, so
# three things the list says that a diff would not.
#   * `uop/spec.py`'s RANGE-arg predicate MOVED with the flip. Pin:
# THE REVERSE LIST -- who needs THIS file -- is the one that is not obvious, and

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../renderer/estimates.bend as E
type Op is Data:
  OpsSPECIAL{}
  OpsBUFFER{}
  OpsALLOC{}
  OpsNOOP{}
  OpsREWRITE_ERROR{}
  OpsPARAM{}
  # REFERENCE A PARAM -- upstream `codegen/__init__.py:426` builds one when a param's addrspace is not ALU,
  # and every generic predicate that lists PARAM lists it too (`uop/__init__.py:114`'s `Defines`,
  # `ops.py:169`, `ops.py:350`, `ops.py:873`, `render.py:40`).
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

def Ops.name.of(op: Op) -> String:
  match op:
    case OpsSPECIAL{}: "SPECIAL"
    case OpsBUFFER{}: "BUFFER"
    case OpsALLOC{}: "ALLOC"
    case OpsNOOP{}: "NOOP"
    case OpsREWRITE_ERROR{}: "REWRITE_ERROR"
    case OpsPARAM{}: "PARAM"
    case OpsREFPARAM{}: "REFPARAM"
    case OpsCALL{}: "CALL"
    case OpsPROGRAM{}: "PROGRAM"
    case OpsLINEAR{}: "LINEAR"
    case OpsSOURCE{}: "SOURCE"
    case OpsBINARY{}: "BINARY"
    case OpsSINK{}: "SINK"
    case OpsAFTER{}: "AFTER"
    case OpsSTACK{}: "STACK"
    case OpsGETADDR{}: "GETADDR"
    case OpsINDEX{}: "INDEX"
    case OpsSHRINK{}: "SHRINK"
    case OpsLOAD{}: "LOAD"
    case OpsSTORE{}: "STORE"
    case OpsWMMA{}: "WMMA"
    case OpsCAST{}: "CAST"
    case OpsBITCAST{}: "BITCAST"
    case OpsEXP2{}: "EXP2"
    case OpsLOG2{}: "LOG2"
    case OpsSIN{}: "SIN"
    case OpsSQRT{}: "SQRT"
    case OpsRECIP{}: "RECIP"
    case OpsNEG{}: "NEG"
    case OpsTRUNC{}: "TRUNC"
    case OpsADD{}: "ADD"
    case OpsMUL{}: "MUL"
    case OpsSHL{}: "SHL"
    case OpsSHR{}: "SHR"
    case OpsTRUNCDIV{}: "TRUNCDIV"
    case OpsMAX{}: "MAX"
    case OpsTRUNCMOD{}: "TRUNCMOD"
    case OpsCMPLT{}: "CMPLT"
    case OpsCMPNE{}: "CMPNE"
    case OpsCMPEQ{}: "CMPEQ"
    case OpsXOR{}: "XOR"
    case OpsOR{}: "OR"
    case OpsAND{}: "AND"
    case OpsTHREEFRY{}: "THREEFRY"
    case OpsSUB{}: "SUB"
    case OpsFDIV{}: "FDIV"
    case OpsPOW{}: "POW"
    case OpsDIV{}: "DIV"
    case OpsMOD{}: "MOD"
    case OpsWHERE{}: "WHERE"
    case OpsMULACC{}: "MULACC"
    case OpsBARRIER{}: "BARRIER"
    case OpsRANGE{}: "RANGE"
    case OpsIF{}: "IF"
    case OpsEND{}: "END"
    case OpsENDIF{}: "ENDIF"
    case OpsBACKEDGE{}: "BACKEDGE"
    case OpsCONST{}: "CONST"
    case OpsCUSTOM{}: "CUSTOM"
    case OpsCUSTOMI{}: "CUSTOMI"
    case OpsINS{}: "INS"
    case OpsCONTIGUOUS_BACKWARD{}: "CONTIGUOUS_BACKWARD"
    case OpsDETACH{}: "DETACH"
    case OpsSTAGE{}: "STAGE"
    case OpsCOPY{}: "COPY"
    case OpsMSELECT{}: "MSELECT"
    case OpsMSTACK{}: "MSTACK"
    case OpsCUSTOM_FUNCTION{}: "CUSTOM_FUNCTION"
    case OpsRESHAPE{}: "RESHAPE"
    case OpsPERMUTE{}: "PERMUTE"
    case OpsEXPAND{}: "EXPAND"
    case OpsPAD{}: "PAD"
    case OpsUNSHARD{}: "UNSHARD"
    case OpsREDUCE{}: "REDUCE"
    case OpsALLREDUCE{}: "ALLREDUCE"
    case OpsPYLITERAL{}: "PYLITERAL"

def Ops.name(op: Op) -> String:
  String.concat(["Ops.", Ops.name.of(op)])

def Ops.value(op: Op) -> U32:
  match op:
    case OpsSPECIAL{}: 1
    case OpsBUFFER{}: 2
    case OpsALLOC{}: 3
    case OpsNOOP{}: 4
    case OpsREWRITE_ERROR{}: 5
    case OpsPARAM{}: 6
    case OpsREFPARAM{}: 7
    case OpsCALL{}: 8
    case OpsPROGRAM{}: 9
    case OpsLINEAR{}: 10
    case OpsSOURCE{}: 11
    case OpsBINARY{}: 12
    case OpsSINK{}: 13
    case OpsAFTER{}: 14
    case OpsSTACK{}: 15
    case OpsGETADDR{}: 16
    case OpsINDEX{}: 17
    case OpsSHRINK{}: 18
    case OpsLOAD{}: 19
    case OpsSTORE{}: 20
    case OpsWMMA{}: 21
    case OpsCAST{}: 22
    case OpsBITCAST{}: 23
    case OpsEXP2{}: 24
    case OpsLOG2{}: 25
    case OpsSIN{}: 26
    case OpsSQRT{}: 27
    case OpsRECIP{}: 28
    case OpsNEG{}: 29
    case OpsTRUNC{}: 30
    case OpsADD{}: 31
    case OpsMUL{}: 32
    case OpsSHL{}: 33
    case OpsSHR{}: 34
    case OpsTRUNCDIV{}: 35
    case OpsMAX{}: 36
    case OpsTRUNCMOD{}: 37
    case OpsCMPLT{}: 38
    case OpsCMPNE{}: 39
    case OpsCMPEQ{}: 40
    case OpsXOR{}: 41
    case OpsOR{}: 42
    case OpsAND{}: 43
    case OpsTHREEFRY{}: 44
    case OpsSUB{}: 45
    case OpsFDIV{}: 46
    case OpsPOW{}: 47
    case OpsDIV{}: 48
    case OpsMOD{}: 49
    case OpsWHERE{}: 50
    case OpsMULACC{}: 51
    case OpsBARRIER{}: 52
    case OpsRANGE{}: 53
    case OpsIF{}: 54
    case OpsEND{}: 55
    case OpsENDIF{}: 56
    case OpsBACKEDGE{}: 57
    case OpsCONST{}: 58
    case OpsCUSTOM{}: 59
    case OpsCUSTOMI{}: 60
    case OpsINS{}: 61
    case OpsCONTIGUOUS_BACKWARD{}: 62
    case OpsDETACH{}: 63
    case OpsSTAGE{}: 64
    case OpsCOPY{}: 65
    case OpsMSELECT{}: 66
    case OpsMSTACK{}: 67
    case OpsCUSTOM_FUNCTION{}: 68
    case OpsRESHAPE{}: 69
    case OpsPERMUTE{}: 70
    case OpsEXPAND{}: 71
    case OpsPAD{}: 72
    case OpsUNSHARD{}: 73
    case OpsREDUCE{}: 74
    case OpsALLREDUCE{}: 75
    case OpsPYLITERAL{}: 76

# TRANSCRIPTION ROTTS: MEASURED, THE PORT'S `associative` WAS MISSING `XOR` AND
# WRITTEN AS THE UNION THEY ARE AND NOT AS A FOURTH TABLE, SO A DERIVED SET

def GroupOp.unary(op: Op) -> Bool:
  match op:
    case OpsEXP2{}: True{}
    case OpsLOG2{}: True{}
    case OpsSIN{}: True{}
    case OpsSQRT{}: True{}
    case OpsRECIP{}: True{}
    case OpsNEG{}: True{}
    case OpsTRUNC{}: True{}
    case _: False{}

def GroupOp.binary(op: Op) -> Bool:
  match op:
    case OpsADD{}: True{}
    case OpsMUL{}: True{}
    case OpsTRUNCDIV{}: True{}
    case OpsMAX{}: True{}
    case OpsTRUNCMOD{}: True{}
    case OpsCMPLT{}: True{}
    case OpsCMPNE{}: True{}
    case OpsCMPEQ{}: True{}
    case OpsXOR{}: True{}
    case OpsSHL{}: True{}
    case OpsSHR{}: True{}
    case OpsOR{}: True{}
    case OpsAND{}: True{}
    case OpsTHREEFRY{}: True{}
    case OpsSUB{}: True{}
    case OpsFDIV{}: True{}
    case OpsPOW{}: True{}
    case OpsDIV{}: True{}
    case OpsMOD{}: True{}
    case _: False{}

def GroupOp.ternary(op: Op) -> Bool:
  match op:
    case OpsWHERE{}: True{}
    case OpsMULACC{}: True{}
    case _: False{}

def GroupOp.defines(op: Op) -> Bool:
  match op:
    case OpsPARAM{}: True{}
    case OpsREFPARAM{}: True{}
    case OpsBUFFER{}: True{}
    case OpsALLOC{}: True{}
    case OpsBINARY{}: True{}
    case _: False{}

def GroupOp.irreducible(op: Op) -> Bool:
  match op:
    case OpsCONST{}: True{}
    case OpsSPECIAL{}: True{}
    case OpsRANGE{}: True{}
    case OpsPARAM{}: True{}
    case OpsGETADDR{}: True{}
    case _: False{}

def GroupOp.movement(op: Op) -> Bool:
  match op:
    case OpsRESHAPE{}: True{}
    case OpsEXPAND{}: True{}
    case OpsPERMUTE{}: True{}
    case OpsPAD{}: True{}
    case OpsSHRINK{}: True{}
    case _: False{}

def GroupOp.commutative(op: Op) -> Bool:
  match op:
    case OpsADD{}: True{}
    case OpsMUL{}: True{}
    case OpsMAX{}: True{}
    case OpsCMPNE{}: True{}
    case OpsCMPEQ{}: True{}
    case OpsXOR{}: True{}
    case OpsAND{}: True{}
    case OpsOR{}: True{}
    case _: False{}

def GroupOp.associative(op: Op) -> Bool:
  match op:
    case OpsADD{}: True{}
    case OpsMUL{}: True{}
    case OpsAND{}: True{}
    case OpsOR{}: True{}
    case OpsMAX{}: True{}
    case OpsXOR{}: True{}
    case _: False{}

def GroupOp.idempotent(op: Op) -> Bool:
  match op:
    case OpsOR{}: True{}
    case OpsAND{}: True{}
    case OpsMAX{}: True{}
    case _: False{}

def GroupOp.reduce(op: Op) -> Bool:
  match op:
    case OpsADD{}: True{}
    case OpsMUL{}: True{}
    case OpsMAX{}: True{}
    case _: False{}

def GroupOp.comparison(op: Op) -> Bool:
  match op:
    case OpsCMPLT{}: True{}
    case OpsCMPNE{}: True{}
    case OpsCMPEQ{}: True{}
    case _: False{}

def GroupOp.effect(op: Op) -> Bool:
  match op:
    case OpsSTORE{}: True{}
    case OpsCUSTOM{}: True{}
    case OpsCALL{}: True{}
    case OpsBARRIER{}: True{}
    case _: False{}

def GroupOp.alu(+op: Op) -> Bool:
  Bool.or(GroupOp.unary(op), Bool.or(GroupOp.binary(op), GroupOp.ternary(op)))

def GroupOp.broadcastable(+op: Op) -> Bool:
  Bool.or(GroupOp.binary(op), GroupOp.ternary(op))

def GroupOp.elementwise(op: Op) -> Bool:
  match op:
    case OpsCAST{}: True{}
    case OpsBITCAST{}: True{}
    case _: GroupOp.alu(op)


# AxisType -- tinygrad/uop/ops.py:17

type AxisType is Data:
  AXIS_DEVICE{}
  AXIS_GLOBAL{}
  AXIS_LOCAL{}
  AXIS_WARP{}
  AXIS_WEAK{}
  AXIS_LOOP{}
  AXIS_UPCAST{}
  AXIS_PLACEHOLDER{}
  AXIS_REDUCE{}
  AXIS_UNROLL{}

def AxisType.name.dead(a: AxisType) -> String:
  match a:
    case AXIS_REDUCE{}: "REDUCE"
    case _: "UNROLL"

def AxisType.name(a: AxisType) -> String:
  match a:
    case AXIS_DEVICE{}: "DEVICE"
    case AXIS_GLOBAL{}: "GLOBAL"
    case AXIS_LOCAL{}: "LOCAL"
    case AXIS_WARP{}: "WARP"
    case AXIS_WEAK{}: "WEAK"
    case AXIS_LOOP{}: "LOOP"
    case AXIS_UPCAST{}: "UPCAST"
    case AXIS_PLACEHOLDER{}: "PLACEHOLDER"
    case _: AxisType.name.dead(a)

def AxisType.all() -> List<&2, AxisType>:
  [AXIS_DEVICE{}, AXIS_GLOBAL{}, AXIS_LOCAL{}, AXIS_WARP{}, AXIS_WEAK{}, AXIS_LOOP{},
   AXIS_UPCAST{}, AXIS_PLACEHOLDER{}, AXIS_REDUCE{}, AXIS_UNROLL{}]

def AxisType.value(a: AxisType) -> U32:
  match a:
    case AXIS_DEVICE{}: 1
    case AXIS_GLOBAL{}: 2
    case AXIS_LOCAL{}: 3
    case AXIS_WARP{}: 4
    case AXIS_WEAK{}: 5
    case AXIS_LOOP{}: 6
    case AXIS_UPCAST{}: 7
    case AXIS_PLACEHOLDER{}: 8
    case AXIS_REDUCE{}: 9
    case _: 10

# `AxisType.__lt__` -- ops.py:19 upstream, ADDED by 78d482262. `self.value <
def AxisType.lt(x: AxisType, y: AxisType) -> Bool:
  U32.is_lt(AxisType.value(x), AxisType.value(y))

# axis_letters / axis_colors -- ops.py:51,53. Two dictionaries keyed by an Enum, two
def axis_letters(a: AxisType) -> String:
  match a:
    case AXIS_DEVICE{}: "d"
    case AXIS_GLOBAL{}: "g"
    case AXIS_LOCAL{}: "l"
    case AXIS_WARP{}: "w"
    case AXIS_WEAK{}: "L"
    case AXIS_LOOP{}: "L"
    case AXIS_UPCAST{}: "u"
    case _: "!KeyError"

def axis_colors(a: AxisType) -> String:
  match a:
    case AXIS_DEVICE{}: "green"
    case AXIS_GLOBAL{}: "blue"
    case AXIS_LOCAL{}: "cyan"
    case AXIS_WARP{}: "CYAN"
    case AXIS_WEAK{}: "red"
    case AXIS_LOOP{}: "red"
    case AXIS_UPCAST{}: "yellow"
    case _: "!KeyError"

# `axis_to_pos` IS GONE. ops.py:57 at the pin, deleted by 78d482262 and replaced by
# range_start -- ops.py:56. `range_start[self.op]` is a slice offset, so it is a
# DEAD CLAIM, MEASURED. This `U32` ladder has NO CALLER in the port -- `ended_ranges` is
def range_start(op: Op) -> U32:
  match op:
    case OpsSTAGE{}: 1
    case OpsREDUCE{}: 1
    case OpsEND{}: 1
    case OpsCALL{}: 1
    case OpsLINEAR{}: 0
    case _: 0

def range_start_str(op: Op) -> String:
  match op:
    case OpsSTAGE{}: "1"
    case OpsREDUCE{}: "1"
    case OpsEND{}: "1"
    case OpsCALL{}: "1"
    case OpsLINEAR{}: "0"
    case _: "!KeyError"


type Const is Data:
  CBool{b: Bool}
  CInt{i: H.I64}
  CFloat{f: F32}
  CInvalid{}

# `Sint` is ops.py:1888 symbol=sint -- `sint = int|UOp`, spelled out. It is the element type
type Sint is Data:
  SI{i: H.I64}
  SU{u: U32}

def SInt.of(i: H.I64) -> Sint: SI{i}
def SInt.uop(u: U32) -> Sint: SU{u}

def SInt.is_int(s: Sint) -> Bool:
  match s:
    case SI{i}: True{}
    case SU{u}: False{}

def SInt.uop_of(s: Sint) -> Maybe<&1, U32>:
  match s:
    case SI{i}: None{}
    case SU{u}: Some{u}

type PyRange is Data:
  PyRange{lo: H.I64, hi: H.I64}

type Img is Data:
  Img{h: U32, w: U32}

# ParamArg -- tinygrad/uop/ops.py:22
#     ...]|None` (`uop/ops.py:34`) and `device.py:29`'s table is string-keyed. See

type ParamArg is Data:
  ParamArg{slot: U32, dtype: S.Dt,
    vmin_vmax: Maybe<&2, PyRange>,
    multiple_of: Maybe<&2, U32>,
    name: Maybe<&2, String>,
    addrspace: S.Addr,
    device: Maybe<&2, S.Dev>,
    volatile: Bool,
    image: Maybe<&2, Img>,
    buffer: Maybe<&2, U32>,
    bind_on_realize: Bool,
    val: Maybe<&2, Const>}

# A tag tuple holds UOPS, so it holds their INDICES: ops.py:547 says "tags can
type Tag is Data:
  TNone{}
  TBool{b: Bool}
  TStr{s: String}
  TInt{i: U32}
  TTuple{xs: List<&2, U32>}

# The three arg payloads, moved UP from ops.py:1339-1404.
type OPTOPS is Data:
  OPS_TC{}
  OPS_SPLIT{}
  OPS_PADTO{}
  OPS_SWAP{}

def OPTOPS.value(o: OPTOPS) -> U32:
  match o:
    case OPS_TC{}: 1
    case OPS_SPLIT{}: 2
    case OPS_PADTO{}: 3
    case _: 4

# or a 3-tuple `(amt, target, top)` (`postrange.py:114` checks `len(opt.arg) in
type SPL is Data:
  SPL{amt: U32, t: AxisType, top: Maybe<&2, Bool>}

type TC is Data:
  TC{any: Bool, sel: U32, lvl: U32, use: U32}

type OPTARG is Data:
  OA_NONE{}
  OA_INT{i: U32}
  OA_SPLIT{a: SPL}
  OA_TC{a: TC}

type OPT is Data:
  OPT{op: OPTOPS, axis: U32, arg: OPTARG}

def OPT.op(x: OPT) -> OPTOPS:
  match x:
    case OPT{op, axis, arg}: op

def OPT.axis(x: OPT) -> U32:
  match x:
    case OPT{op, axis, arg}: axis

def OPT.arg(x: OPT) -> OPTARG:
  match x:
    case OPT{op, axis, arg}: arg

# The three arg payloads, moved UP from ops.py:1339-1404.
# KernelInfo -- ops.py:1339. six fields, upstream's six, in upstream's order:
# upstream's own `ops.py:26` imports it under `TYPE_CHECKING` and Bend REFUSES
# because `do_estimates` -- upstream's only writer, `codegen/__init__.py:446` --
# upstream's only writer is `runtime/support/hcq2.py:295` and the port's
# upstream's elements are `Opt` dataclasses (pin ops.py:1342,1343 `tuple`), and
# `--graph lin` carries one, MEASURED by calling the py side,
# which is `heuristic.py:109`'s own `Opt(OptOps.SPLIT, axis, (0, AxisType.UPCAST))`.
# and the CONTENT was unobservable -- MEASURED, changing a fixture's payload `0` to
type KernelInfo is Data:
  KernelInfo{name: String, applied_opts: List<&2, OPT>, opts_to_apply: Maybe<&2, List<&2, OPT>>,
    estimates: Maybe<&2, E.Estimates>, beam: U32, optimized: Bool}

def KernelInfo.of() -> KernelInfo:
  KernelInfo{"test", Nil{}, None{}, None{}, 0, False{}}

# `Target` -- tinygrad/helpers.py:198. `device, renderer, arch, interface, indices`,
# DIFFERENT identities are two types: a `H.Target.parse`d target could not go
# be typed at all. MEASURED, before this change: the round trip gate answered
# ProgramInfo -- ops.py:1343. SEVEN fields, and the SEVENTH is `target: Target`.
# (`ops.py:1358`) takes a `target` argument and there was no `from_sink`, so
type ProgramInfo is Data:
  ProgramInfo{global_size: List<&2, H.I64>, local_size: List<&2, H.I64>, params: List<&2, U32>, globals: List<&2, U32>, outs: List<&2, U32>, ins: List<&2, U32>, target: H.Target}

def ProgramInfo.of() -> ProgramInfo:
  ProgramInfo{[H.i64_of_i32(1), H.i64_of_i32(1), H.i64_of_i32(1)], [H.i64_of_i32(1), H.i64_of_i32(1), H.i64_of_i32(1)], Nil{}, Nil{}, Nil{}, Nil{}, H.Target.of()}

type VarVals is Data:
  VarVals{m: Map<&2, H.I64>}

def VarVals.new() -> VarVals:
  VarVals{Map.new(&2, H.I64)}

def GroupOp.opaque_call_bodies(op: Op) -> Bool:
  match op:
    case OpsSINK{}: True{}
    case OpsPROGRAM{}: True{}
    case OpsLINEAR{}: True{}
    case OpsSTORE{}: True{}
    case OpsCUSTOM_FUNCTION{}: True{}
    case _: False{}

# CustomFunction -- ops.py:1394-1397 upstream. NOT AT THE PIN: `git show
# pin a CUSTOM_FUNCTION's arg was a bare `str` (ops.py:1256,
# here because `uop/spec.py:110` now reads `isinstance(x.arg, CustomFunction)` and
#   name: str                    the external function's SYMBOL. `hcq2.py:84` writes
#                                `dtype_from_uop`'s CUSTOM_FUNCTION arm (ops.py:133)
type CustomFunction is Data:
  CustomFunction{name: String, dtype: S.Dt}

# (ops.py:1509) builds exactly this value -- `arg=CustomFunction(fn)`, dtype void.
def CustomFunction.of(name: String) -> CustomFunction:
  CustomFunction{name, S.void()}

# CallInfo -- ops.py:1391. TWO FIELDS DROPPED, and both for the same reason:
# FALSE and it names a function and a shape, which is why it looked like it confirmed
# THE FIELD. MEASURED:
#   * `tinygrad/uop/ops.py:130-132` is `case Ops.CALL:` / "a call has the dtype of its
#   * `tinygrad/uop/spec.py:112` at HEAD is `lambda x: isinstance(x.arg, CallInfo)` --
type CallInfo is Data:
  CallInfo{name: Maybe<&2, String>, precompile: Bool, precompile_backward: Bool, dtype: S.Dt}

#   CustomFunction          ACustom    CUSTOM_FUNCTION arg (ops.py:1394 upstream;
#   Ops                     AOpLit     PYLITERAL arg (`upat.py:26` passes `self.op[0]`,
#                                     a bare `Ops`; `__init__.py:101` says the literal is
#   tuple[int, ...]         ATuple     PERMUTE arg (`movement.py:231`), UNSHARD arg
#                                     (`ops.py:691`: "the tuple of sharded axes, sorted")
#   -- and this is the WRONG SPELLING FOR A FLIP, which is `tuple[bool, ...]`:
#      `ops.py:428` asserts `all(isinstance(x, bool) for x in self.marg)` and
#      MEASURED on a fresh src `UOp(Ops.FLIP, src, (1, 0))` RAISES
#   str                     AStr       SPECIAL name (`gpudims.py:104`), SOURCE text
#                                     (`codegen/__init__.py:455`)
#   (str, DType)            AInk       INS arg (`ops.py:622`), CUSTOM/CUSTOMI arg --
#                                     `ops.py:137` ASSERTS that pair: "CUSTOM/CUSTOMI arg
#                                     byte values. `ops.py:201`'s key holds the `bytes`
#   int                     AInt       MSELECT's shard index (`ops.py:772`), a bare int.
#                                     `runs/graphcmp/D/D1-graph-mselect.txt`): `ops.py:201`'s

type Arg is Data:
  ANone{}
  ADt{dt: S.Dt}
  APy{v: Const}
  AParam{pa: ParamArg}
  ACustom{cf: CustomFunction}
  ACall{ci: CallInfo}
  AKernel{ki: KernelInfo}
  AProgram{pi: ProgramInfo}
  ARange{ids: List<&2, U32>, at: AxisType}
  AReduce{rop: Op, num_axes: U32}
  # `upat.py:26`'s `UOp(Ops.PYLITERAL, arg=self.op[0])` -- and the compiler said so:
  AOpLit{op: Op}
  AWmma{dims: List<&2, U32>, dt: S.Dt, threads: U32, tc: Maybe<&2, List<&2, U32>>}
  ATuple{ys: List<&2, U32>}
  # guard `not all(isinstance(x, bool) for x in self.marg)` (ops.py:428) while PERMUTE
  # has none.  ONE upstream pattern (`upat`/`spec.py:166` asserts `isinstance(mv.arg,
  # this.  MEASURED on the corpus: CPython renders `a.flip(0).uop.arg` as
  ABoolList{bs: List<&2, Bool>}
  AStr{s: String}
  AInk{ins: String, dt: S.Dt}
  AAllred{rop: Op, dev: S.Dev}
  ADev{dev: S.Dev}
  ABlob{bs: List<&2, U32>}
# `CallInfo.__repr__` (ops.py:1401) is at the end of the equality block, because it
# The `Metadata` side table (`all_metadata`, ops.py:215) is NOT a second store.
  AInt{i: U32}
  AFloat{f: F32}
  ABad{}

def CallInfo.of() -> CallInfo:
  CallInfo{None{}, False{}, False{}, S.void()}

# THE TABLE IS IN `.agents/slop/tables/uop-ops-1294.md` -- `CallInfo.__repr__` (ops.py:1401) is at the end of the equality block, because it

type Node is Data:
  Node{op: Op, src: List<&2, U32>, arg: Arg, tag: Tag}

type Arena is Data:
  Arena{nodes: List<&2, Node>, shp: List<&2, U32>}


def Arena.nodes(x: Arena) -> List<&2, Node>:
  match x:
    case Arena{nodes, shp}: nodes

def Arena.shp(x: Arena) -> List<&2, U32>:
  match x:
    case Arena{nodes, shp}: shp

def Arena.depth.at(ss: List<&2, U32>, n: Nat) -> U32:
  match ss n:
    case Nil{} _: 0
    case h <> t 0n: h
    case _ <> t 1n+p: Arena.depth.at(t, p)

def Arena.depth(ar: Arena, i: U32) -> U32:
  Arena.depth.at(Arena.shp(ar), U32.to_nat(i))

def Node.op(x: Node) -> Op:
  match x:
    case Node{op, src, arg, tag}: op

def Node.src(x: Node) -> List<&2, U32>:
  match x:
    case Node{op, src, arg, tag}: src

def Node.arg(x: Node) -> Arg:
  match x:
    case Node{op, src, arg, tag}: arg

def Node.tag(x: Node) -> Tag:
  match x:
    case Node{op, src, arg, tag}: tag

def Arena.bottom() -> Node:
  Node{OpsNOOP{}, Nil{}, ABad{}, TNone{}}

def Arena.empty() -> Arena:
  Arena{[Arena.bottom()], [0]}

# ops.py:842 says must never be reset, and the arena's length IS that counter.
def Arena.next(ar: Arena) -> U32:
  U32.from_nat(List.length(&2, Node, Arena.nodes(ar)))

def UOp.is_none(u: U32) -> Bool:
  U32.is_zero(u)

def Arena.at.go(ns: List<&2, Node>, n: Nat) -> Maybe<&1, Node>:
  match ns n:
    case Nil{} _:
      None{}
    case k <> t 0n:
      Some{k}
    case k <> t 1n+p:
      Arena.at.go(t, p)

def Arena.at(ar: Arena, i: U32) -> Maybe<&1, Node>:
  Arena.at.go(Arena.nodes(ar), U32.to_nat(i))

def Arena.node(ar: Arena, i: U32) -> Node:
  Maybe.default(&1, Node, Arena.at(ar, i), Arena.bottom())

def Arena.op(ar: Arena, i: U32) -> Op:
  Node.op(Arena.node(ar, i))

def Arena.arg(ar: Arena, i: U32) -> Arg:
  Node.arg(Arena.node(ar, i))

def Arena.tag(ar: Arena, i: U32) -> Tag:
  Node.tag(Arena.node(ar, i))

def Arena.srcs(ar: Arena, i: U32) -> List<&2, U32>:
  Node.src(Arena.node(ar, i))

def Arena.src(ar: Arena, i: U32, n: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, Node.src(Arena.node(ar, i)), U32.to_nat(n)), 0)

def Arena.src0(ar: Arena, i: U32) -> U32:
  Arena.src(ar, i, 0)

def Arena.nsrc(ar: Arena, i: U32) -> U32:
  U32.from_nat(List.length(&2, U32, Node.src(Arena.node(ar, i))))

def Arena.src_from.go(xs: List<&2, U32>, k: Nat) -> List<&2, U32>:
  match xs k:
    case Nil{} 0n: Nil{}
    case Nil{} 1n+p: Nil{}
    case h <> t 0n: h <> t
    case h <> t 1n+p: Arena.src_from.go(t, p)

def Arena.src_from(ar: Arena, i: U32, k: U32) -> List<&2, U32>:
  Arena.src_from.go(Node.src(Arena.node(ar, i)), U32.to_nat(k))

def Arena.src_to.go(xs: List<&2, U32>, k: Nat) -> List<&2, U32>:
  match xs k:
    case Nil{} 0n: Nil{}
    case Nil{} 1n+p: Nil{}
    case h <> t 0n: Nil{}
    case h <> t 1n+p: h <> Arena.src_to.go(t, p)

def Arena.src_to(ar: Arena, i: U32, k: U32) -> List<&2, U32>:
  Arena.src_to.go(Node.src(Arena.node(ar, i)), U32.to_nat(k))

# `self.src_without_body` -- ops.py:1327. It is `self.src[1:]` for a CALL and
def Arena.src_without_body.op(op: Op, src: List<&2, U32>) -> List<&2, U32>:
  match op:
    case OpsCALL{}: Arena.src_from.go(src, 1n)
    case _: src

def Arena.src_without_body.node(nd: Node) -> List<&2, U32>:
  match nd:
    case Node{op, src, arg, tag}: Arena.src_without_body.op(op, src)

def Arena.src_without_body(ar: Arena, i: U32) -> List<&2, U32>:
  Arena.src_without_body.node(Arena.node(ar, i))


def SInt.i(x: Sint) -> H.I64:
  match x:
    case SI{i}: i
    case _: H.i64_of_i32(0)

def SInt.u(x: Sint) -> U32:
  match x:
    case SU{u}: u
    case _: 0

def VarVals.m(x: VarVals) -> Map<&2, H.I64>:
  match x:
    case VarVals{m}: m

def ParamArg.slot(x: ParamArg) -> U32:
  match x:
    case ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: slot

# because a Variable is bound by NAME (function.py:15-17), and `param_like` then
# `from_buffer` (ops.py:860) uses `-id(opaque)` for an unrelated reason -- and a
def ParamArg.no_slot() -> U32: 4294967295

def ParamArg.has_slot(x: ParamArg) -> Bool:
  Bool.not(U32.is_eq(ParamArg.slot(x), ParamArg.no_slot()))

def ParamArg.dtype(x: ParamArg) -> S.Dt:
  match x:
    case ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: dtype

def ParamArg.vmin_vmax(x: ParamArg) -> Maybe<&2, PyRange>:
  match x:
    case ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: vmin_vmax

def ParamArg.multiple_of(x: ParamArg) -> Maybe<&2, U32>:
  match x:
    case ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: multiple_of

def ParamArg.name(x: ParamArg) -> Maybe<&2, String>:
  match x:
    case ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: name

def ParamArg.addrspace(x: ParamArg) -> S.Addr:
  match x:
    case ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: addrspace

def ParamArg.device(x: ParamArg) -> Maybe<&2, S.Dev>:
  match x:
    case ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: device

def ParamArg.volatile(x: ParamArg) -> Bool:
  match x:
    case ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: volatile

def ParamArg.image(x: ParamArg) -> Maybe<&2, Img>:
  match x:
    case ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: image

def ParamArg.buffer(x: ParamArg) -> Maybe<&2, U32>:
  match x:
    case ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: buffer

def ParamArg.bind_on_realize(x: ParamArg) -> Bool:
  match x:
    case ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: bind_on_realize

def ParamArg.val(x: ParamArg) -> Maybe<&2, Const>:
  match x:
    case ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: val

# ParamArg -- ops.py:23's constructor with every default the dataclass declares.
def ParamArg.of(slot: U32, dtype: S.Dt) -> ParamArg:
  ParamArg{slot, dtype, None{}, None{}, None{}, S.AGlobal{}, None{}, False{}, None{}, None{}, False{}, None{}}

def KernelInfo.name(x: KernelInfo) -> String:
  match x:
    case KernelInfo{name, applied_opts, opts_to_apply, estimates, beam, optimized}: name

def KernelInfo.applied_opts(x: KernelInfo) -> List<&2, OPT>:
  match x:
    case KernelInfo{name, applied_opts, opts_to_apply, estimates, beam, optimized}: applied_opts

def KernelInfo.opts_to_apply(x: KernelInfo) -> Maybe<&2, List<&2, OPT>>:
  match x:
    case KernelInfo{name, applied_opts, opts_to_apply, estimates, beam, optimized}: opts_to_apply

def KernelInfo.estimates(x: KernelInfo) -> Maybe<&2, E.Estimates>:
  match x:
    case KernelInfo{name, applied_opts, opts_to_apply, estimates, beam, optimized}: estimates

def KernelInfo.beam(x: KernelInfo) -> U32:
  match x:
    case KernelInfo{name, applied_opts, opts_to_apply, estimates, beam, optimized}: beam

def KernelInfo.optimized(x: KernelInfo) -> Bool:
  match x:
    case KernelInfo{name, applied_opts, opts_to_apply, estimates, beam, optimized}: optimized

# helpers.py:156 is `''.join([c if c in (letters+digits+'_') else
# keeps Python's shape, and it sits HERE rather than at ops.py:1347 because it
def KernelInfo.function_name(x: KernelInfo) -> String:
  KernelInfo.name(x)

def ProgramInfo.global_size(x: ProgramInfo) -> List<&2, H.I64>:
  match x:
    case ProgramInfo{global_size, local_size, params, globals, outs, ins, target}: global_size

def ProgramInfo.local_size(x: ProgramInfo) -> List<&2, H.I64>:
  match x:
    case ProgramInfo{global_size, local_size, params, globals, outs, ins, target}: local_size

def ProgramInfo.params(x: ProgramInfo) -> List<&2, U32>:
  match x:
    case ProgramInfo{global_size, local_size, params, globals, outs, ins, target}: params

def ProgramInfo.globals(x: ProgramInfo) -> List<&2, U32>:
  match x:
    case ProgramInfo{global_size, local_size, params, globals, outs, ins, target}: globals

def ProgramInfo.outs(x: ProgramInfo) -> List<&2, U32>:
  match x:
    case ProgramInfo{global_size, local_size, params, globals, outs, ins, target}: outs

def ProgramInfo.ins(x: ProgramInfo) -> List<&2, U32>:
  match x:
    case ProgramInfo{global_size, local_size, params, globals, outs, ins, target}: ins

# `target: Target` -- ops.py:1349. The SEVENTH field, and the one that was
def ProgramInfo.target(x: ProgramInfo) -> H.Target:
  match x:
    case ProgramInfo{global_size, local_size, params, globals, outs, ins, target}: target

def CallInfo.name(x: CallInfo) -> Maybe<&2, String>:
  match x:
    case CallInfo{name, precompile, precompile_backward, dtype}: name

def CallInfo.precompile(x: CallInfo) -> Bool:
  match x:
    case CallInfo{name, precompile, precompile_backward, dtype}: precompile

def CallInfo.precompile_backward(x: CallInfo) -> Bool:
  match x:
    case CallInfo{name, precompile, precompile_backward, dtype}: precompile_backward

def CallInfo.dtype(x: CallInfo) -> S.Dt:
  match x:
    case CallInfo{name, precompile, precompile_backward, dtype}: dtype

def CustomFunction.name(x: CustomFunction) -> String:
  match x:
    case CustomFunction{name, dtype}: name

def CustomFunction.dtype(x: CustomFunction) -> S.Dt:
  match x:
    case CustomFunction{name, dtype}: dtype

def eq_bool(x: Bool, y: Bool) -> Bool:
  Bool.not(Bool.xor(x, y))

def eq_op(x: Op, y: Op) -> Bool:
  U32.is_eq(Ops.value(x), Ops.value(y))

def eq_u32(ys: List<&2, U32>, zs: List<&2, U32>) -> Bool:
  match ys zs:
    case Nil{} Nil{}: True{}
    case y <> t w <> u: Bool.and(U32.is_eq(y, w), eq_u32(t, u))
    case Nil{} _ <> _: False{}
    case _ <> _ Nil{}: False{}

def eq_i64(x: H.I64, y: H.I64) -> Bool:
  Cmp.is_eq(H.i64_cmp(x, y))

def eq_bool_list(ys: List<&2, Bool>, zs: List<&2, Bool>) -> Bool:
  match ys zs:
    case Nil{} Nil{}: True{}
    case y <> t w <> u: Bool.and(eq_bool(y, w), eq_bool_list(t, u))
    case Nil{} _ <> _: False{}
    case _ <> _ Nil{}: False{}

# `movement.py:253`'s `tuple([i in axis_arg for i in range(len(self.shape))])` --
def bools_of.go(+xs: List<&2, U32>) -> List<&2, Bool>:
  match xs:
    case Nil{}: Nil{}
    case h <> t: Bool.not(U32.is_zero(h)) <> bools_of.go(t)

def bools_of(+xs: List<&2, U32>) -> List<&2, Bool>: bools_of.go(xs)

def eq_i64s(xs: List<&2, H.I64>, ys: List<&2, H.I64>) -> Bool:
  match xs ys:
    case Nil{} Nil{}: True{}
    case x <> t y <> u: Bool.and(eq_i64(x, y), eq_i64s(t, u))
    case Nil{} _ <> _: False{}
    case _ <> _ Nil{}: False{}

def eq_opt_u32(x: Maybe<&2, U32>, y: Maybe<&2, U32>) -> Bool:
  match x y:
    case None{} None{}: True{}
    case Some{a} Some{b}: U32.is_eq(a, b)
    case None{} Some{b}: False{}
    case Some{a} None{}: False{}

def eq_opt_u32s(x: Maybe<&2, List<&2, U32>>, y: Maybe<&2, List<&2, U32>>) -> Bool:
  match x y:
    case None{} None{}: True{}
    case Some{a} Some{b}: eq_u32(a, b)
    case None{} Some{b}: False{}
    case Some{a} None{}: False{}

def eq_opt_str(x: Maybe<&2, String>, y: Maybe<&2, String>) -> Bool:
  match x y:
    case None{} None{}: True{}
    case Some{a} Some{b}: String.eq(a, b)
    case None{} Some{b}: False{}
    case Some{a} None{}: False{}

def eq_pyrange(x: PyRange, y: PyRange) -> Bool:
  match x y:
    case PyRange{lo, hi} PyRange{lo2, hi2}: Bool.and(eq_i64(lo, lo2), eq_i64(hi, hi2))

def eq_img(x: Img, y: Img) -> Bool:
  match x y:
    case Img{h, w} Img{h2, w2}: Bool.and(U32.is_eq(h, h2), U32.is_eq(w, w2))

def eq_opt_pyrange(x: Maybe<&2, PyRange>, y: Maybe<&2, PyRange>) -> Bool:
  match x y:
    case None{} None{}: True{}
    case Some{a} Some{b}: eq_pyrange(a, b)
    case None{} Some{b}: False{}
    case Some{a} None{}: False{}

def eq_opt_img(x: Maybe<&2, Img>, y: Maybe<&2, Img>) -> Bool:
  match x y:
    case None{} None{}: True{}
    case Some{a} Some{b}: eq_img(a, b)
    case None{} Some{b}: False{}
    case Some{a} None{}: False{}

def eq_dev.d1(y: S.Dev, +tag: U32) -> Bool:
  match y:
    case S.D1{t2}: U32.is_eq(tag, t2)
    case _: False{}

def eq_dev.n(y: S.Dev, +tags: List<&2, U32>) -> Bool:
  match y:
    case S.Dn{t2}: eq_u32(tags, t2)
    case _: False{}

def eq_dev.sel(x: S.Dev, y: S.Dev) -> Bool:
  match x:
    case S.D1{tag}: eq_dev.d1(y, tag)
    case S.Dn{tags}: eq_dev.n(y, tags)

def eq_dev(x: S.Dev, y: S.Dev) -> Bool:
  eq_dev.sel(x, y)

def eq_opt_dev(x: Maybe<&2, S.Dev>, y: Maybe<&2, S.Dev>) -> Bool:
  match x y:
    case None{} None{}: True{}
    case Some{a} Some{b}: eq_dev(a, b)
    case None{} Some{b}: False{}
    case Some{a} None{}: False{}

def eq_optops(x: OPTOPS, y: OPTOPS) -> Bool:
  U32.is_eq(OPTOPS.value(x), OPTOPS.value(y))

def eq_optbool(x: Maybe<&2, Bool>, y: Maybe<&2, Bool>) -> Bool:
  match x y:
    case None{} None{}: True{}
    case Some{a} Some{b}: eq_bool(a, b)
    case None{} Some{b}: False{}
    case Some{a} None{}: False{}

def eq_spl(x: SPL, y: SPL) -> Bool:
  match x y:
    case SPL{a, t, p} SPL{b, u, q}:
      Bool.and(U32.is_eq(a, b), Bool.and(U32.is_eq(AxisType.value(t), AxisType.value(u)), eq_optbool(p, q)))

def eq_tc(x: TC, y: TC) -> Bool:
  match x y:
    case TC{a, b, c, d} TC{e, f, g, h}:
      Bool.and(eq_bool(a, e), Bool.and(U32.is_eq(b, f), Bool.and(U32.is_eq(c, g), U32.is_eq(d, h))))

def eq_optarg(x: OPTARG, y: OPTARG) -> Bool:
  match x y:
    case OA_NONE{} OA_NONE{}: True{}
    case OA_INT{i} OA_INT{j}: U32.is_eq(i, j)
    case OA_SPLIT{a} OA_SPLIT{b}: eq_spl(a, b)
    case OA_TC{a} OA_TC{b}: eq_tc(a, b)
    case _ _: False{}

def eq_opt(x: OPT, y: OPT) -> Bool:
  match x y:
    case OPT{a, b, c} OPT{d, e, f}:
      Bool.and(eq_optops(a, d), Bool.and(U32.is_eq(b, e), eq_optarg(c, f)))

def eq_opts(xs: List<&2, OPT>, ys: List<&2, OPT>) -> Bool:
  match xs ys:
    case Nil{} Nil{}: True{}
    case x <> t y <> u: Bool.and(eq_opt(x, y), eq_opts(t, u))
    case Nil{} _ <> _: False{}
    case _ <> _ Nil{}: False{}

def KernelInfo.eq_opts(x: Maybe<&2, List<&2, OPT>>, y: Maybe<&2, List<&2, OPT>>) -> Bool:
  match x y:
    case None{} None{}: True{}
    case Some{a} Some{b}: eq_opts(a, b)
    case None{} Some{b}: False{}
    case Some{a} None{}: False{}

def eq_cls.CVoid(x: S.Cls, y: S.Cls) -> Bool:
  match y:
    case S.CVoid{}: True{}
    case _: False{}

def eq_cls.CWeakInt(x: S.Cls, y: S.Cls) -> Bool:
  match y:
    case S.CWeakInt{}: True{}
    case _: False{}

def eq_cls.CBool(x: S.Cls, y: S.Cls) -> Bool:
  match y:
    case S.CBool{}: True{}
    case _: False{}

def eq_cls.CUint(x: S.Cls, y: S.Cls) -> Bool:
  match y:
    case S.CUint{}: True{}
    case _: False{}

def eq_cls.CSint(x: S.Cls, y: S.Cls) -> Bool:
  match y:
    case S.CSint{}: True{}
    case _: False{}

def eq_cls.CFloat(x: S.Cls, y: S.Cls) -> Bool:
  match y:
    case S.CFloat{}: True{}
    case _: False{}

def eq_cls.CWeakFloat(x: S.Cls, y: S.Cls) -> Bool:
  match y:
    case S.CWeakFloat{}: True{}
    case _: False{}

# `eq_dt(weakfloat, weakfloat)` FALSE -- dtype.py's `DType` is `@dataclass(frozen=True,
def eq_cls.sel(x: S.Cls, y: S.Cls) -> Bool:
  match x:
    case S.CVoid{}: eq_cls.CVoid(x, y)
    case S.CWeakInt{}: eq_cls.CWeakInt(x, y)
    case S.CBool{}: eq_cls.CBool(x, y)
    case S.CUint{}: eq_cls.CUint(x, y)
    case S.CSint{}: eq_cls.CSint(x, y)
    case S.CFloat{}: eq_cls.CFloat(x, y)
    case _: eq_cls.CWeakFloat(x, y)

def eq_cls(x: S.Cls, y: S.Cls) -> Bool:
  eq_cls.sel(x, y)

# False and `eq_addr(Aalu, AReg)` True. dtype.py:51-54's `AddrSpace` is a plain
def eq_addr(x: S.Addr, y: S.Addr) -> Bool:
  match x:
    case S.AGlobal{}:
      match y:
        case S.AGlobal{}: True{}
        case _: False{}
    case S.ALocal{}:
      match y:
        case S.ALocal{}: True{}
        case _: False{}
    case S.AReg{}:
      match y:
        case S.AReg{}: True{}
        case _: False{}
    case _:
      match y:
        case S.Aalu{}: True{}
        case _: False{}

# IS THIS PARAM AN ALU ONE? `u.addrspace != AddrSpace.ALU` (ops.py:1365) IS
def pa.is_alu.of(a: Arg) -> Bool:
  match a:
    case AParam{pa}:
      match pa:
        case ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}:
          eq_addr(addrspace, S.Aalu{})
    case _: False{}

# MEASURED (`PARITY.md` §107): `Ops.eq_dt` accounts for 34,757 of the 39,478 `String.eq` calls in 1,500 turns,
def eq_dt_name(amb: Bool, +nm: String, +n2: String) -> Bool:
  match amb:
    case True{}: String.eq(nm, n2)
    case False{}: True{}

def eq_dt(x: S.Dt, y: S.Dt) -> Bool:
  match x y:
    case S.Dt{pri, bits, cls, nm} S.Dt{p2, b2, c2, n2}:
      +pr = pri
      Bool.and(U32.is_eq(pr, p2), Bool.and(U32.is_eq(bits, b2),
        Bool.and(eq_cls(cls, c2),
          eq_dt_name(Bool.or(U32.is_eq(pr, 10), U32.is_eq(pr, 11)), nm, n2))))


def eq_axis(x: AxisType, y: AxisType) -> Bool:
  U32.is_eq(AxisType.value(x), AxisType.value(y))

def eq_const.CBool(y: Const, +b: Bool) -> Bool:
  match y:
    case CBool{c}: eq_bool(b, c)
    case _: False{}

def eq_const.CInt(y: Const, +i: H.I64) -> Bool:
  match y:
    case CInt{j}: eq_i64(i, j)
    case _: False{}

def eq_const.CFloat(y: Const, +f: F32) -> Bool:
  match y:
    case CFloat{g}: U32.is_eq(F32.bits(f), F32.bits(g))
    case _: False{}

def eq_const.CInvalid(y: Const) -> Bool:
  match y:
    case CInvalid{}: True{}
    case _: False{}

def eq_const.sel(x: Const, y: Const) -> Bool:
  match x:
    case CBool{b}: eq_const.CBool(y, b)
    case CInt{i}: eq_const.CInt(y, i)
    case CFloat{f}: eq_const.CFloat(y, f)
    case _: eq_const.CInvalid(y)

def eq_const(x: Const, y: Const) -> Bool:
  eq_const.sel(x, y)

def eq_opt_const(x: Maybe<&2, Const>, y: Maybe<&2, Const>) -> Bool:
  match x y:
    case None{} None{}: True{}
    case Some{a} Some{b}: eq_const(a, b)
    case None{} Some{b}: False{}
    case Some{a} None{}: False{}

# `eq_pynest` -- the NESTED `PyConst`, which is a DIFFERENT COMPARATOR from `eq_const` and
# `ops.py:201`'s key is `(op, src, arg, tag, type(arg))`, so `type(arg)` disambiguates the
# (ops.py:42, `PyConst = float|int|bool` at dtype.py:38) NESTED inside `arg`, and there
# CPython-measured, `.agents/slop/ops-oracle.py`, and the fixture is a PAIR THAT DIFFERS
# `CFloat`: `ConstFloat.__hash__` is `hash(self.bits)` (dtype.py:21) and
def eq_pynest.CBool(y: Const, +b: Bool) -> Bool:
  match y:
    case CBool{y1}: eq_bool(b, y1)
    case CInt{y1}: eq_bool(Bool.not(Cmp.is_eq(H.i64_cmp(y1, H.i64_of_i32(0)))), b)
    case _: False{}

def eq_pynest.CInt(y: Const, +i: H.I64) -> Bool:
  match y:
    case CInt{y1}: eq_i64(i, y1)
    case _: False{}

def eq_pynest(y: Const, z: Const) -> Bool:
  match y:
    case CBool{b}: eq_pynest.CBool(z, b)
    case CInt{i}: eq_pynest.CInt(z, i)
    case _: eq_const(y, z)

def eq_opt_pynest(x: Maybe<&2, Const>, y: Maybe<&2, Const>) -> Bool:
  match x y:
    case None{} None{}: True{}
    case Some{a} Some{b}: eq_pynest(a, b)
    case None{} Some{b}: False{}
    case Some{a} None{}: False{}

# ParamArg -- the 12-field dataclass of ops.py:23 (13 before `72f98ffe0` moved `size`

def eq_paramarg(x: ParamArg, y: ParamArg) -> Bool:
  match x y:
    case ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val} ParamArg{s2, d2, v2, m2, n2, a2, dv2, vo2, i2, b2, br2, w2}:
      Bool.and(U32.is_eq(slot, s2), Bool.and(eq_dt(dtype, d2),
        Bool.and(eq_opt_pyrange(vmin_vmax, v2),
        Bool.and(eq_opt_u32(multiple_of, m2), Bool.and(eq_opt_str(name, n2),
        Bool.and(eq_addr(addrspace, a2), Bool.and(eq_opt_dev(device, dv2),
        Bool.and(eq_bool(volatile, vo2), Bool.and(eq_opt_img(image, i2),
        Bool.and(eq_opt_u32(buffer, b2), Bool.and(eq_bool(bind_on_realize, br2),
          eq_opt_pynest(val, w2))))))))))))

# FIELDS -- MEASURED, `KernelInfo() == KernelInfo(optimized=True)` is False and
def eq_estimates(x: E.Estimates, y: E.Estimates) -> Bool:
  match x y:
    case E.Estimates{o, l, m} E.Estimates{o2, l2, m2}:
      Bool.and(U32.is_eq(o, o2), Bool.and(U32.is_eq(l, l2), U32.is_eq(m, m2)))

def KernelInfo.eq_estimates(x: Maybe<&2, E.Estimates>, y: Maybe<&2, E.Estimates>) -> Bool:
  match x y:
    case None{} None{}: True{}
    case Some{a} Some{b}: eq_estimates(a, b)
    case None{} Some{b}: False{}
    case Some{a} None{}: False{}

def eq_kernelinfo(x: KernelInfo, y: KernelInfo) -> Bool:
  match x y:
    case KernelInfo{name, applied_opts, opts_to_apply, estimates, beam, optimized} KernelInfo{n2, o2, p2, e2, b2, op2}:
      Bool.and(String.eq(name, n2), Bool.and(eq_opts(applied_opts, o2),
        Bool.and(KernelInfo.eq_opts(opts_to_apply, p2), Bool.and(KernelInfo.eq_estimates(estimates, e2),
        Bool.and(U32.is_eq(beam, b2), eq_bool(optimized, op2))))))

def eq_target(x: H.Target, y: H.Target) -> Bool:
  match x y:
    case H.Target{device, renderer, arch, iface, indices} H.Target{d2, r2, a2, i2, n2}:
      Bool.and(String.eq(device, d2), Bool.and(String.eq(renderer, r2),
        Bool.and(String.eq(arch, a2), Bool.and(String.eq(iface, i2),
          String.eq(indices, n2)))))

def eq_programinfo(x: ProgramInfo, y: ProgramInfo) -> Bool:
  match x y:
    case ProgramInfo{global_size, local_size, params, globals, outs, ins, target} ProgramInfo{g2, l2, v2, b2, o2, i2, t2}:
      Bool.and(eq_i64s(global_size, g2), Bool.and(eq_i64s(local_size, l2),
        Bool.and(eq_u32(params, v2), Bool.and(eq_u32(globals, b2),
        Bool.and(eq_u32(outs, o2), Bool.and(eq_u32(ins, i2),
          eq_target(target, t2)))))))

def eq_callinfo(x: CallInfo, y: CallInfo) -> Bool:
  match x y:
    case CallInfo{name, precompile, precompile_backward, dtype} CallInfo{n2, p2, b2, d2}:
      Bool.and(eq_opt_str(name, n2), Bool.and(eq_bool(precompile, p2),
        Bool.and(eq_bool(precompile_backward, b2), eq_dt(dtype, d2))))

def eq_customfunction(x: CustomFunction, y: CustomFunction) -> Bool:
  match x y:
    case CustomFunction{name, dtype} CustomFunction{n2, d2}: Bool.and(String.eq(name, n2), eq_dt(dtype, d2))

def eq_arg.ANone(y: Arg) -> Bool:
  match y:
    case ANone{}: True{}
    case _: False{}

def eq_arg.ADt(y: Arg, +dt: S.Dt) -> Bool:
  match y:
    case ADt{y1}: eq_dt(dt, y1)
    case _: False{}

def eq_arg.APy(y: Arg, +v: Const) -> Bool:
  match y:
    case APy{y1}: eq_const(v, y1)
    case _: False{}

def eq_arg.AParam(y: Arg, +pa: ParamArg) -> Bool:
  match y:
    case AParam{y1}: eq_paramarg(pa, y1)
    case _: False{}

def eq_arg.ACustom(y: Arg, +cf: CustomFunction) -> Bool:
  match y:
    case ACustom{y1}: eq_customfunction(cf, y1)
    case _: False{}

def eq_arg.ACall(y: Arg, +ci: CallInfo) -> Bool:
  match y:
    case ACall{y1}: eq_callinfo(ci, y1)
    case _: False{}

def eq_arg.AKernel(y: Arg, +ki: KernelInfo) -> Bool:
  match y:
    case AKernel{y1}: eq_kernelinfo(ki, y1)
    case _: False{}

def eq_arg.AProgram(y: Arg, +pi: ProgramInfo) -> Bool:
  match y:
    case AProgram{y1}: eq_programinfo(pi, y1)
    case _: False{}

def eq_arg.ARange(y: Arg, +ids: List<&2, U32>, +at: AxisType) -> Bool:
  match y:
    case ARange{y1, y2}: Bool.and(eq_u32(ids, y1), eq_axis(at, y2))
    case _: False{}

def eq_arg.AReduce(y: Arg, +rop: Op, +num_axes: U32) -> Bool:
  match y:
    case AReduce{y1, y2}: Bool.and(U32.is_eq(Ops.value(rop), Ops.value(y1)), U32.is_eq(num_axes, y2))
    case _: False{}

def eq_arg.AOpLit(y: Arg, +op: Op) -> Bool:
  match y:
    case AOpLit{y1}: U32.is_eq(Ops.value(op), Ops.value(y1))
    case _: False{}

def eq_arg.AWmma(y: Arg, +dims: List<&2, U32>, +dt: S.Dt, +threads: U32, +tc: Maybe<&2, List<&2, U32>>) -> Bool:
  match y:
    case AWmma{y1, y2, y3, y4}: Bool.and(eq_u32(dims, y1), Bool.and(eq_dt(dt, y2), Bool.and(U32.is_eq(threads, y3), eq_opt_u32s(tc, y4))))
    case _: False{}

def eq_arg.ATuple(y: Arg, +ys: List<&2, U32>) -> Bool:
  match y:
    case ATuple{y1}: eq_u32(ys, y1)
    case _: False{}

def eq_arg.ABoolList(y: Arg, +bs: List<&2, Bool>) -> Bool:
  match y:
    case ABoolList{y1}: eq_bool_list(bs, y1)
    case _: False{}

def eq_arg.AStr(y: Arg, +s: String) -> Bool:
  match y:
    case AStr{y1}: String.eq(s, y1)
    case _: False{}

def eq_arg.AInk(y: Arg, +ins: String, +dt: S.Dt) -> Bool:
  match y:
    case AInk{y1, y2}: Bool.and(String.eq(ins, y1), eq_dt(dt, y2))
    case _: False{}

def eq_arg.AAllred(y: Arg, +rop: Op, +dev: S.Dev) -> Bool:
  match y:
    case AAllred{y1, y2}: Bool.and(U32.is_eq(Ops.value(rop), Ops.value(y1)), eq_dev(dev, y2))
    case _: False{}

def eq_arg.ADev(y: Arg, +dev: S.Dev) -> Bool:
  match y:
    case ADev{y1}: eq_dev(dev, y1)
    case _: False{}

# same ucache key: ONE node where `ops.py:201`'s key, which holds the `bytes` object
def eq_arg.ABlob(y: Arg, +bs: List<&2, U32>) -> Bool:
  match y:
    case ABlob{y1}: eq_u32(bs, y1)
    case _: False{}

def eq_arg.AInt(y: Arg, +i: U32) -> Bool:
  match y:
    case AInt{y1}: U32.is_eq(i, y1)
    case _: False{}

# same bug. It is the OPPOSITE bug, and the difference is the PYTHON CLASS of the
# element `ops.py:201`'s key holds -- the key is
#   * `dtype.py:8-23` `class ConstFloat(float)` says in its own docstring that it
# MEASURED, live, on both trees this gate can select, by CALLING
def eq_arg.AFloat(y: Arg, +f: F32) -> Bool:
  match y:
    case AFloat{y1}: F32.is_eq(f, y1)
    case _: False{}

def eq_arg.ABad(y: Arg) -> Bool:
  match y:
    case ABad{}: True{}
    case _: False{}

def eq_arg.sel(x: Arg, y: Arg) -> Bool:
  match x:
    case ANone{}: eq_arg.ANone(y)
    case ADt{dt}: eq_arg.ADt(y, dt)
    case APy{v}: eq_arg.APy(y, v)
    case AParam{pa}: eq_arg.AParam(y, pa)
    case ACustom{cf}: eq_arg.ACustom(y, cf)
    case ACall{ci}: eq_arg.ACall(y, ci)
    case AKernel{ki}: eq_arg.AKernel(y, ki)
    case AProgram{pi}: eq_arg.AProgram(y, pi)
    case ARange{ids, at}: eq_arg.ARange(y, ids, at)
    case AReduce{rop, num_axes}: eq_arg.AReduce(y, rop, num_axes)
    case AOpLit{op}: eq_arg.AOpLit(y, op)
    case AWmma{dims, dt, threads, tc}: eq_arg.AWmma(y, dims, dt, threads, tc)
    case ATuple{ys}: eq_arg.ATuple(y, ys)
    case ABoolList{bs}: eq_arg.ABoolList(y, bs)
    case AStr{s}: eq_arg.AStr(y, s)
    case AInk{ins, dt}: eq_arg.AInk(y, ins, dt)
    case AAllred{rop, dev}: eq_arg.AAllred(y, rop, dev)
    case ADev{dev}: eq_arg.ADev(y, dev)
    case ABlob{bs}: eq_arg.ABlob(y, bs)
    case AInt{i}: eq_arg.AInt(y, i)
    case AFloat{f}: eq_arg.AFloat(y, f)
    case ABad{}: eq_arg.ABad(y)

def eq_arg(x: Arg, y: Arg) -> Bool:
  eq_arg.sel(x, y)

def eq_tag.TNone(y: Tag) -> Bool:
  match y:
    case TNone{}: True{}
    case _: False{}

# `ops.py:201`'s key is `(op, src, arg, tag, type(arg))`. It carries `type(arg)` and NOT
# top-level split must be KEPT. `rtag(self, tag=True)` -- ops.py:258 -- is what makes
def eq_tag.TBool(y: Tag, +b: Bool) -> Bool:
  match y:
    case TBool{y1}: eq_bool(b, y1)
    case TInt{y1}: eq_bool(Bool.not(U32.is_zero(y1)), b)
    case _: False{}

def eq_tag.TStr(y: Tag, +s: String) -> Bool:
  match y:
    case TStr{y1}: String.eq(s, y1)
    case _: False{}

def eq_tag.TInt(y: Tag, +i: U32) -> Bool:
  match y:
    case TInt{y1}: U32.is_eq(i, y1)
    case TBool{y1}: eq_bool(Bool.not(U32.is_zero(i)), y1)
    case _: False{}

def eq_tag.TTuple(y: Tag, +xs: List<&2, U32>) -> Bool:
  match y:
    case TTuple{y1}: eq_u32(xs, y1)
    case _: False{}

def eq_tag.sel(x: Tag, y: Tag) -> Bool:
  match x:
    case TNone{}: eq_tag.TNone(y)
    case TBool{b}: eq_tag.TBool(y, b)
    case TStr{s}: eq_tag.TStr(y, s)
    case TInt{i}: eq_tag.TInt(y, i)
    case TTuple{xs}: eq_tag.TTuple(y, xs)

def eq_tag(x: Tag, y: Tag) -> Bool:
  eq_tag.sel(x, y)

def eq_node(x: Node, y: Node) -> Bool:
  match x y:
    case Node{op, src, arg, tag} Node{o2, s2, a2, t2}:
      Bool.and(U32.is_eq(Ops.value(op), Ops.value(o2)),
        Bool.and(eq_u32(src, s2), Bool.and(eq_arg(arg, a2), eq_tag(tag, t2))))

# THE SAME EQUALITY, WITH THE WANTED NODE's OP VALUE ALREADY IN HAND: THE OP IS FIXED FOR
# THE WHOLE INTERNING SCAN, AND `Ops.value` IS A SIXTY-ARM MATCH. MEASURED, IT IS CALLED
# 41,973,508 TIMES A TURN AND ITS ARMS ARE 1,684,550,390 TAG COMPARISONS
# (`.agents/slop/wgslperf/count-intern.py` COUNTS THE COMPILED FORM).
#
# AND THE SRCS, THE ARG AND THE TAG ARE COMPARED ONLY WHEN THE OP MATCHES: `Bool.and`
# EVALUATES BOTH OF ITS ARGUMENTS, SO THE OLD FORM PAID FOR THEM ON EVERY NODE.
def eq_node.ov.go(same_op: Bool, same_sh: Bool, x: Node, y: Node) -> Bool:
  match same_op:
    case True{}:
      match same_sh:
        case True{}:
          match x y:
            case Node{_, src, arg, tag} Node{_, s2, a2, t2}:
              Bool.and(eq_u32(src, s2), Bool.and(eq_arg(arg, a2), eq_tag(tag, t2)))
        case False{}: False{}
    case False{}: False{}

# UOpMetaClass.__call__ -- ops.py:193 symbol=UOpMetaClass.__call__. THE CONSTRUCTOR.
# THE KEY MUST SEPARATE DTYPES. ops.py:193 -- a CONST's dtype comes from the
type UpAlt is Data:
  UpFixed{ys: List<&2, U32>}
  UpRepeat{x: U32}

# variants because ops.py:1464 reads the difference: a tuple keeps its order, a
type SrcArg is Data:
  SNone{}
  SOne{x: U32}
  STuple{ys: List<&2, U32>}
  SList{ys: List<&2, U32>}

# ops.py:1448. `src_in` is `_in_src`, the RAW argument, which `named` and
type UPat is Data:
  UPat{
    op: Maybe<&2, List<&2, Op>>,
    match_dtype: Maybe<&2, List<&2, S.Dt>>,
    arg: Maybe<&2, Arg>,
    name: Maybe<&2, String>,
    src_in: SrcArg,
    src: List<&2, UpAlt>,
    is_any: Bool,
    strict_length: Bool,
    required_len: U32,
    early_reject: List<&2, Op>}

type Pat is Data:
  Pat{upats: List<&2, UPat>}

type PatFound is Data:
  PatFound{pat: Pat, i: U32}

def PatFound.pat(f: PatFound) -> Pat:
  match f:
    case PatFound{pat, _}: pat

def PatFound.i(f: PatFound) -> U32:
  match f:
    case PatFound{_, i}: i

def Pat.upats(pat: Pat) -> List<&2, UPat>:
  match pat:
    case Pat{upats}: upats

def UPat.op(u: UPat) -> Maybe<&2, List<&2, Op>>:
  match u:
    case UPat{op, _, _, _, _, _, _, _, _, _}: op

def UPat.match_dtype(u: UPat) -> Maybe<&2, List<&2, S.Dt>>:
  match u:
    case UPat{_, md, _, _, _, _, _, _, _, _}: md

def UPat.arg(u: UPat) -> Maybe<&2, Arg>:
  match u:
    case UPat{_, _, a, _, _, _, _, _, _, _}: a

def UPat.name(u: UPat) -> Maybe<&2, String>:
  match u:
    case UPat{_, _, _, n, _, _, _, _, _, _}: n

def UPat.src_in(u: UPat) -> SrcArg:
  match u:
    case UPat{_, _, _, _, si, _, _, _, _, _}: si

def UPat.src(u: UPat) -> List<&2, UpAlt>:
  match u:
    case UPat{_, _, _, _, _, s, _, _, _, _}: s

def UPat.is_any(u: UPat) -> Bool:
  match u:
    case UPat{_, _, _, _, _, _, b, _, _, _}: b

def UPat.strict_length(u: UPat) -> Bool:
  match u:
    case UPat{_, _, _, _, _, _, _, b, _, _}: b

def UPat.required_len(u: UPat) -> U32:
  match u:
    case UPat{_, _, _, _, _, _, _, _, n, _}: n

def UPat.early_reject(u: UPat) -> List<&2, Op>:
  match u:
    case UPat{_, _, _, _, _, _, _, _, _, er}: er

def intern.find.pick(hit: Bool, k: U32, +nxt: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match hit:
    case True{}: Some{k}
    case False{}: nxt

# THE SCAN IS THE WHOLE ARENA, AND THE COMPARISON IS THE COST. MEASURED, IT IS 20,818,516
# NODE COMPARISONS A TURN OVER 85,340 SCANS OF AN ARENA OF ~244 NODES.
#
# AND THE WANTED NODE's OP VALUE IS HOISTED OUT OF THE SCAN: THE OP DOES NOT CHANGE, AND
# `Ops.value` IS A SIXTY-ARM MATCH (THE COUNT IS IN `eq_node.ov.go`'s COMMENT).
def intern.find.same(ov: U32, +nd: Node, +want: Node, same_sh: Bool) -> Bool:
  eq_node.ov.go(U32.is_eq(Ops.value(Node.op(nd)), ov), same_sh, nd, want)

# (ops.py:201); both colliding args are tuples, so `type(arg)` does not split
def intern.find.go(ns: List<&2, Node>, ss: List<&2, U32>, +k: U32, +want: Node, +depth: U32, +ov: U32) -> Maybe<&2, U32>:
  match ns ss:
    case Nil{} Nil{}:
      None{}
    case Nil{} _ <> _:
      None{}
    case _ <> _ Nil{}:
      None{}
    case +nd <> t sh <> st:
      nxt = intern.find.go(t, st, U32.add(k, 1), want, depth, ov)
      intern.find.pick(intern.find.same(ov, nd, want, U32.is_eq(sh, depth)), k, nxt)

def intern.find(ns: List<&2, Node>, ss: List<&2, U32>, +k: U32, +want: Node, +depth: U32) -> Maybe<&2, U32>:
  intern.find.go(ns, ss, k, want, depth, Ops.value(Node.op(want)))


def intern.put.shp(+ar: Arena, +want: Node, depth: U32) -> Arena:
  Arena{List.append(&2, Node, Arena.nodes(ar), [want]), List.append(&2, U32, Arena.shp(ar), [depth])}

def intern.put(+ar: Arena, +want: Node) -> Arena:
  intern.put.shp(ar, want, 0)


def intern.get(ar: Arena, hit: Maybe<&2, U32>) -> Maybe<&2, U32>:
  hit


def UOp.make.intern.put(+ar: Arena, hit: Maybe<&2, U32>, +want: Node, depth: U32) -> Arena:
  match hit:
    case Some{i}: ar
    case None{}: intern.put.shp(ar, want, depth)


def UOp.make.intern(+ar: Arena, +want: Node, +depth: U32) -> Arena:
  UOp.make.intern.put(ar, intern.find(Arena.nodes(ar), Arena.shp(ar), 0, want, depth), want, depth)

def UOp.make.shp(+ar: Arena, +op: Op, +src: List<&2, U32>, +arg: Arg, +tag: Tag, depth: U32) -> Arena:
  UOp.make.intern(ar, Node{op, src, arg, tag}, depth)

def UOp.make(+ar: Arena, +op: Op, +src: List<&2, U32>, +arg: Arg, +tag: Tag) -> Arena:
  UOp.make.shp(ar, op, src, arg, tag, 0)

def UOp.of.intern.put(+ar: Arena, hit: Maybe<&2, U32>, +want: Node) -> U32:
  match hit:
    case Some{i}: i
    case None{}: U32.sub(Arena.next(ar), 1)

# `Metadata` is helpers.py:293's `(name, backward)` record, and ops.py is where
# property at ops.py:775.

def UOp.of.intern(+ar: Arena, +want: Node, depth: U32) -> U32:
  UOp.of.intern.put(ar, intern.find(Arena.nodes(ar), Arena.shp(ar), 0, want, depth), want)

def UOp.of.shp(+ar: Arena, +op: Op, +src: List<&2, U32>, +arg: Arg, +tag: Tag, depth: U32) -> U32:
  UOp.of.intern(ar, Node{op, src, arg, tag}, depth)

def UOp.of(+ar: Arena, +op: Op, +src: List<&2, U32>, +arg: Arg, +tag: Tag) -> U32:
  UOp.of.shp(ar, op, src, arg, tag, 0)


def eq_op_list(xs: List<&2, Op>, ys: List<&2, Op>) -> Bool:
  match xs:
    case Nil{}:
      match ys:
        case Nil{}: True{}
        case _ <> _: False{}
    case x <> t:
      match ys:
        case Nil{}: False{}
        case y <> u: Bool.and(eq_op(x, y), eq_op_list(t, u))

def eq_dt_list(xs: List<&2, S.Dt>, ys: List<&2, S.Dt>) -> Bool:
  match xs:
    case Nil{}:
      match ys:
        case Nil{}: True{}
        case _ <> _: False{}
    case x <> t:
      match ys:
        case Nil{}: False{}
        case y <> u: Bool.and(eq_dt(x, y), eq_dt_list(t, u))


def eq_opt_op(x: Maybe<&2, List<&2, Op>>, y: Maybe<&2, List<&2, Op>>) -> Bool:
  match x:
    case Some{a}:
      match y:
        case Some{b}: eq_op_list(a, b)
        case None{}: False{}
    case None{}:
      match y:
        case Some{_}: False{}
        case None{}: True{}

def eq_opt_dt(x: Maybe<&2, List<&2, S.Dt>>, y: Maybe<&2, List<&2, S.Dt>>) -> Bool:
  match x:
    case Some{a}:
      match y:
        case Some{b}: eq_dt_list(a, b)
        case None{}: False{}
    case None{}:
      match y:
        case Some{_}: False{}
        case None{}: True{}

def eq_opt_arg(x: Maybe<&2, Arg>, y: Maybe<&2, Arg>) -> Bool:
  match x:
    case Some{a}:
      match y:
        case Some{b}: eq_arg(a, b)
        case None{}: False{}
    case None{}:
      match y:
        case Some{_}: False{}
        case None{}: True{}

def eq_inalts(xs: List<&2, UpAlt>, ys: List<&2, UpAlt>) -> Bool:
  match xs:
    case Nil{}:
      match ys:
        case Nil{}: True{}
        case _ <> _: False{}
    case UpFixed{a} <> t:
      match ys:
        case Nil{}: False{}
        case UpFixed{b} <> u: Bool.and(eq_u32(a, b), eq_inalts(t, u))
        case UpRepeat{_} <> _: False{}
    case UpRepeat{a} <> t:
      match ys:
        case Nil{}: False{}
        case UpFixed{_} <> _: False{}
        case UpRepeat{b} <> u: Bool.and(U32.is_eq(a, b), eq_inalts(t, u))

def srcarg.tag(s: SrcArg) -> U32:
  match s:
    case SNone{}: 0
    case SOne{_}: 1
    case STuple{_}: 2
    case SList{_}: 3

def srcarg.ys(s: SrcArg) -> List<&2, U32>:
  match s:
    case SNone{}: Nil{}
    case SOne{x}: [x]
    case STuple{ys}: ys
    case SList{ys}: ys

def eq_in_src(+x: SrcArg, +y: SrcArg) -> Bool:
  Bool.and(U32.is_eq(srcarg.tag(x), srcarg.tag(y)), eq_u32(srcarg.ys(x), srcarg.ys(y)))

def eq_upat(x: UPat, y: UPat) -> Bool:
  match x y:
    case UPat{op1, md1, a1, n1, si1, s1, y1, l1, r1, e1} UPat{op2, md2, a2, n2, si2, s2, y2, l2, r2, e2}:
      Bool.and(eq_opt_op(op1, op2),
      Bool.and(eq_opt_dt(md1, md2),
      Bool.and(eq_opt_arg(a1, a2),
      Bool.and(eq_opt_str(n1, n2),
      Bool.and(eq_in_src(si1, si2),
      Bool.and(eq_inalts(s1, s2),
      Bool.and(eq_bool(y1, y2),
      Bool.and(eq_bool(l1, l2),
                U32.is_eq(r1, r2)))))))))


def pintern.find.pick(hit: Bool, k: U32, +nxt: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match hit:
    case True{}: Some{k}
    case False{}: nxt

def pintern.find(us: List<&2, UPat>, +k: U32, +want: UPat) -> Maybe<&2, U32>:
  match us:
    case Nil{}:
      None{}
    case u <> t:
      pintern.find.pick(eq_upat(u, want), k, pintern.find(t, U32.add(k, 1), want))

def pintern.put(+pat: Pat, +want: UPat) -> Pat:
  Pat{List.append(&2, UPat, Pat.upats(pat), [want])}

def pintern.of(pat: Pat, hit: Maybe<&2, U32>) -> U32:
  match hit:
    case Some{i}: i
    case None{}: U32.from_nat(List.length(&2, UPat, Pat.upats(pat)))

def Pat.of.put(pat: Pat, i: U32) -> PatFound:
  PatFound{pat, i}

type Metadata is Data:
  Metadata{name: String, backward: Bool}

# the `metadata` property, ops.py:775, which is the one getter. Python returns

def UOp.metadata(m: Maybe<&2, Metadata>) -> Maybe<&2, Metadata>:
  m

type Found is Data:
  Found{ar: Arena, i: U32}

def Found.of(p: Arena & U32) -> Found:
  (a, i) = p
  Found{a, i}

def Found.ar(f: Found) -> Arena:
  match f:
    case Found{ar, i}: ar

def Found.i(f: Found) -> U32:
  match f:
    case Found{ar, i}: i

def UOp.new.of(+ar: Arena, +made: Arena, +op: Op, +src: List<&2, U32>, +arg: Arg, +tag: Tag) -> Found:
  Found{made, UOp.of(made, op, src, arg, tag)}

def UOp.new(+ar: Arena, +op: Op, +src: List<&2, U32>, +arg: Arg, +tag: Tag) -> Found:
  UOp.new.of(ar, UOp.make(ar, op, src, arg, tag), op, src, arg, tag)


type Merge is Data:
  Merge{ar: Arena, map: List<&2, U32>}

def Merge.ar(x: Merge) -> Arena:
  match x:
    case Merge{ar, map}: ar

def Merge.map(x: Merge) -> List<&2, U32>:
  match x:
    case Merge{ar, map}: map

def Merge.remap.go(+map: List<&2, U32>, src: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match src:
    case Nil{}: acc
    case h <> t:
      Merge.remap.go(map, t, List.append(&2, U32, acc,
        [Maybe.default(&2, U32, List.get(&2, U32, map, U32.to_nat(h)), 0)]))

def Merge.remap(+map: List<&2, U32>, src: List<&2, U32>) -> List<&2, U32>:
  Merge.remap.go(map, src, Nil{})

def Merge.go(nodes: List<&2, Node>, +ar: Arena, +map: List<&2, U32>) -> Merge:
  match nodes:
    case Nil{}: Merge{ar, map}
    case h <> t:
      match h:
        case Node{op, src, arg, tag}:
          +f = UOp.new(ar, op, Merge.remap(map, src), arg, tag)
          Merge.go(t, Found.ar(f), List.append(&2, U32, map, [Found.i(f)]))

def Arena.merge(+base: Arena, +other: Arena) -> Merge:
  Merge.go(Arena.nodes(other), base, Nil{})

def Merge.at(+x: Merge, i: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, Merge.map(x), U32.to_nat(i)), 0)
def UOp.new.shp.of(+ar: Arena, +made: Arena, +op: Op, +src: List<&2, U32>, +arg: Arg, +tag: Tag, depth: U32) -> Found:
  Found{made, UOp.of.shp(made, op, src, arg, tag, depth)}

def UOp.new.shp(+ar: Arena, +op: Op, +src: List<&2, U32>, +arg: Arg, +tag: Tag, +depth: U32) -> Found:
  UOp.new.shp.of(ar, UOp.make.shp(ar, op, src, arg, tag, depth), op, src, arg, tag, depth)

# The syntactic sugar of ops.py:557-737, in Python's order, and only the part
# sink -- ops.py:559. `UOp(Ops.SINK, src=tuple([x for x in srcs if x is not None]), kwargs)`
def UOp.sink(ar: Arena, +srcs: List<&2, U32>) -> Found:
  UOp.new(ar, OpsSINK{}, srcs, ANone{}, TNone{})

# alu -- ops.py:630. `UOp(op, src=(self, *src), kwargs)`
def UOp.alu(ar: Arena, +op: Op, +srcs: List<&2, U32>) -> Found:
  UOp.new(ar, op, srcs, ANone{}, TNone{})

# `where` -- mixin/elementwise.py:426, `self.alu(Ops.WHERE, x, y)`, i.e.
def UOp.where(ar: Arena, +cond: U32, +x: U32, +y: U32) -> Found:
  UOp.new(ar, OpsWHERE{}, [cond, x, y], ANone{}, TNone{})

# `valid` -- ops.py:664. `cond.where(self, self.const_like(Invalid))`, and for the CONST case
def UOp.valid_of(ar: Arena, +self: U32, +inv: U32, +cond: U32) -> Found:
  UOp.where(ar, cond, self, inv)

# backedge -- ops.py:620. `UOp(Ops.BACKEDGE, src=(self, loop, cond))`
def UOp.backedge(ar: Arena, +self: U32, +loop: U32, +cond: U32) -> Found:
  UOp.new(ar, OpsBACKEDGE{}, [self, loop, cond], ANone{}, TNone{})

# after -- ops.py:621. `UOp(Ops.AFTER, src=(self,)+src, kwargs) if len(src) else self`
def UOp.after.go(srcs: List<&2, U32>, ar: Arena, self: U32, made: Found) -> Found:
  match srcs:
    case Nil{}: Found{ar, self}
    case _ <> _: made

def UOp.after(+ar: Arena, +self: U32, +srcs: List<&2, U32>) -> Found:
  UOp.after.go(srcs, ar, self, UOp.new(ar, OpsAFTER{}, List.append(&2, U32, [self], srcs), ANone{}, TNone{}))

# group -- ops.py:536-538, and upstream DELETED `Ops.GROUP` to get there:
def UOp.group.of(srcs: List<&2, U32>, ar: Arena, +stk: Found) -> Found:
  match srcs:
    case Nil{}: stk
    case s <> t:
      match t:
        case Nil{}: Found{ar, s}
        case _ <> _: UOp.after(Found.ar(stk), Found.i(stk), srcs)

def UOp.group(+ar: Arena, +srcs: List<&2, U32>) -> Found:
  UOp.group.of(srcs, ar, UOp.new(ar, OpsSTACK{}, Nil{}, ANone{}, TNone{}))

# end -- ops.py:619. `UOp(Ops.END, src=(self,)+src) if len(src) else self`
def UOp.end.go(srcs: List<&2, U32>, ar: Arena, self: U32, made: Found) -> Found:
  match srcs:
    case Nil{}: Found{ar, self}
    case _ <> _: made

def UOp.end(+ar: Arena, +self: U32, +srcs: List<&2, U32>) -> Found:
  UOp.end.go(srcs, ar, self, UOp.new(ar, OpsEND{}, List.append(&2, U32, [self], srcs), ANone{}, TNone{}))

# mstack -- ops.py:773. `UOp(Ops.MSTACK, src=(self,)+srcs) if len(srcs) else self`
def UOp.mstack.go(srcs: List<&2, U32>, ar: Arena, self: U32, made: Found) -> Found:
  match srcs:
    case Nil{}: Found{ar, self}
    case _ <> _: made

def UOp.mstack(+ar: Arena, +self: U32, +srcs: List<&2, U32>) -> Found:
  UOp.mstack.go(srcs, ar, self, UOp.new(ar, OpsMSTACK{}, List.append(&2, U32, [self], srcs), ANone{}, TNone{}))

# replace -- ops.py:253. `b.replace(op=..., src=..., arg=..., tag=...)` is a
# -- the field-by-field copy is what `pm_replace_buffers` (hcq2.py:103) and
# the bool LOAD/STORE rules (ptx.py:49/52) reach for.
def UOp.replace.go(same: Bool, +new_op: Op, +new_src: List<&2, U32>, +new_arg: Arg, +new_tag: Tag, ar: Arena, self: U32) -> Found:
  match same:
    case True{}: Found{ar, self}
    case False{}: UOp.new(ar, new_op, new_src, new_arg, new_tag)

def UOp.replace.same.cur.op(new_op: Op, cur_op: Op, new_src: List<&2, U32>, cur_src: List<&2, U32>, new_arg: Arg, cur_arg: Arg, new_tag: Tag, cur_tag: Tag) -> Bool:
  eq_op(new_op, cur_op)

def UOp.replace.same.cur.src(new_op: Op, cur_op: Op, new_src: List<&2, U32>, cur_src: List<&2, U32>, new_arg: Arg, cur_arg: Arg, new_tag: Tag, cur_tag: Tag) -> Bool:
  eq_u32(new_src, cur_src)

def UOp.replace.same.cur.arg(new_op: Op, cur_op: Op, new_src: List<&2, U32>, cur_src: List<&2, U32>, new_arg: Arg, cur_arg: Arg, new_tag: Tag, cur_tag: Tag) -> Bool:
  eq_arg(new_arg, cur_arg)

def UOp.replace.same.cur.tag(new_op: Op, cur_op: Op, new_src: List<&2, U32>, cur_src: List<&2, U32>, new_arg: Arg, cur_arg: Arg, new_tag: Tag, cur_tag: Tag) -> Bool:
  eq_tag(new_tag, cur_tag)

def UOp.replace.all_same(same_op: Bool, same_src: Bool, same_arg: Bool, same_tag: Bool) -> Bool:
  Bool.and(Bool.and(same_op, same_src), Bool.and(same_arg, same_tag))

def UOp.replace(+ar: Arena, +self: U32, +mop: Maybe<&2, Op>, +msrc: Maybe<&2, List<&2, U32>>, +marg: Maybe<&2, Arg>, +mtag: Maybe<&2, Tag>) -> Found:
  +cur_op = Arena.op(ar, self)
  +cur_src = Arena.srcs(ar, self)
  +cur_arg = Arena.arg(ar, self)
  +cur_tag = Arena.tag(ar, self)
  +new_op = Maybe.default(&2, Op, mop, cur_op)
  +new_src = Maybe.default(&2, List<&2, U32>, msrc, cur_src)
  +new_arg = Maybe.default(&2, Arg, marg, cur_arg)
  +new_tag = Maybe.default(&2, Tag, mtag, cur_tag)
  same_op = UOp.replace.same.cur.op(new_op, cur_op, new_src, cur_src, new_arg, cur_arg, new_tag, cur_tag)
  same_src = UOp.replace.same.cur.src(new_op, cur_op, new_src, cur_src, new_arg, cur_arg, new_tag, cur_tag)
  same_arg = UOp.replace.same.cur.arg(new_op, cur_op, new_src, cur_src, new_arg, cur_arg, new_tag, cur_tag)
  same_tag = UOp.replace.same.cur.tag(new_op, cur_op, new_src, cur_src, new_arg, cur_arg, new_tag, cur_tag)
  UOp.replace.go(UOp.replace.all_same(same_op, same_src, same_arg, same_tag), new_op, new_src, new_arg, new_tag, ar, self)

# cast -- mixin/dtype.py:19. `return self if self.dtype == dt else self.alu(Ops.CAST, arg=dt)`.
# FOLD property (`dtype_from_uop`, ops.py:247). A rule body that has no fold
def UOp.cast(ar: Arena, self: U32, dt: S.Dt) -> Found:
  UOp.new(ar, OpsCAST{}, [self], ADt{dt}, TNone{})

def UOp.replicate.go(+self: U32, n: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+p: UOp.replicate.go(self, p, List.append(&2, U32, acc, [self]))

def UOp.replicate(+self: U32, n: U32) -> List<&2, U32>:
  UOp.replicate.go(self, U32.to_nat(n), Nil{})

# broadcast -- ops.py:612. `if count == 1: return self`; else `UOp(Ops.STACK,
# THE STACK IS DELIBERATE, NOT A COLLAPSE. ops.py:604 -- a repeated value stays
def UOp.broadcast.go(isone: Bool, ar: Arena, +self: U32, made: Found) -> Found:
  match isone:
    case True{}: Found{ar, self}
    case False{}: made

def UOp.broadcast(+ar: Arena, +self: U32, +count: U32) -> Found:
  UOp.broadcast.go(U32.is_eq(count, 1), ar, self,
    UOp.new(ar, OpsSTACK{}, UOp.replicate(self, count), ANone{}, TNone{}))

# const -- ops.py:631. `UOp(Ops.CONST, arg=dtype.const(b), src=()).cast(dtype)`
# TODO(p3) ops.py:610  def const -- `UOp.const` needs `dtypes.from_py` (dtype.py:100, which also needs
# `commit_int` and `strong_dtype`) and `truncate` (dtype.py:289, half of which is
def UOp.const(ar: Arena, +v: Const) -> Found:
  UOp.new(ar, OpsCONST{}, Nil{}, APy{v}, TNone{})

# `shape_to_shape_arg` -- ops.py:103-107, NEW to this file. Upstream:
# THE INT CHECK IS THE POINT. ops.py:108 -- every element must have an integer
#     `as_shape` is `(self.val,)` (ops.py:783-786), so the shape is `(n,)`.
#     Ops.STACK),)` is upstream's own spelling at `ops.py:1002`.
# `IndexError`, and a scalar PARAM whose src is a CONST `1` is a DIFFERENT NODE from
# one whose src is an empty STACK. MEASURED on CPython, `Tensor.empty(1).uop.src` is a
def shape_to_shape_arg.of(+ar: Arena, +made: Arena, n: Maybe<&2, U32>) -> Found:
  match n:
    case Some{k}: UOp.const(made, CInt{H.i64_of_i32(k)})
    case None{}: UOp.new(made, OpsSTACK{}, Nil{}, ANone{}, TNone{})

def shape_to_shape_arg(+ar: Arena, n: Maybe<&2, U32>) -> U32:
  Found.i(shape_to_shape_arg.of(ar, ar, n))

# `src=(shape_to_shape_arg(...),)+UOp.device_range_src(device)` -- ops.py:829, :1187,
# UPSTREAM's `_mop` (`ops.py:790-791`) CALLS:
# AND IT LIVES HERE, AND NOT ONLY HERE -- THE PORT HAD THREE
# IT, AND THE DUPLICATION IS THE DEFECT AND NOT THE COPY.
# AND THE LENGTH-1 ARM IS A BARE CONST -- `ops.py:112`: `return src[0]
def shape_arg.const(+ar: Arena, v: U32) -> Found:
  UOp.const(ar, CInt{H.i64_of_i32(v)})

type ShapeArg is Data:
  ShapeArg{ar: Arena, acc: List<&2, U32>}

def ShapeArg.ar(+s: ShapeArg) -> Arena:
  match s:
    case ShapeArg{ar, acc}: ar

def ShapeArg.acc(+s: ShapeArg) -> List<&2, U32>:
  match s:
    case ShapeArg{ar, acc}: acc

def shape_arg.push(+ar: Arena, acc: List<&2, U32>, v: U32) -> ShapeArg:
  +c = shape_arg.const(ar, v)
  ShapeArg{Found.ar(c), List.append(&2, U32, acc, [Found.i(c)])}

def shape_arg.go(ys: List<&2, U32>, +s: ShapeArg) -> Found:
  match ys:
    case Nil{}:
      UOp.new(ShapeArg.ar(s), OpsSTACK{}, ShapeArg.acc(s), ANone{}, TNone{})
    case v <> t:
      shape_arg.go(t, shape_arg.push(ShapeArg.ar(s), ShapeArg.acc(s), v))

def shape_arg_found(ar: Arena, ys: List<&2, U32>) -> Found:
  match ys:
    case v <> Nil{}: shape_arg.const(ar, v)
    case _: shape_arg.go(ys, ShapeArg{ar, Nil{}})

def shape_arg(ar: Arena, ys: List<&2, U32>) -> U32:
  Found.i(shape_arg_found(ar, ys))

# `src=(shape_to_shape_arg(...),)+UOp.device_range_src(device)` -- ops.py:829, :1187,
# `src=(shape_to_shape_arg(...),)+UOp.device_range_src(device)` -- ops.py:829, :1187,
# UPSTREAM's `_mop` (`ops.py:790-791`) CALLS:
# AND IT LIVES HERE, AND NOT ONLY HERE -- THE PORT HAD THREE
# IT, AND THE DUPLICATION IS THE DEFECT AND NOT THE COPY.
# AND THE LENGTH-1 ARM IS A BARE CONST -- `ops.py:112`: `return src[0]
def param_src(+ar: Arena, n: Maybe<&2, U32>) -> List<&2, U32>:
  [shape_to_shape_arg(ar, n)]

# MEASURED, `gates/../sizetosrc/paramsrc_probe.bend` over both spellings on one BUFFER:
def UOp.new.param(+ar: Arena, +op: Op, n: Maybe<&2, U32>, arg: Arg, tag: Tag) -> Found:
  +f = shape_to_shape_arg.of(ar, ar, n)
  UOp.new(Found.ar(f), op, [Found.i(f)], arg, tag)

# `new_buffer` -- ops.py:809-815. THE NODE IS PORTED AND THE HOST ALLOCATION IS NOT:
# `Buffer(device, size * dtype.itemsize)` is CPython allocating, and the port's
# `ParamArg.buffer` is an allocator SLOT (`Maybe<U32>`, its own field at ops.bend:537), so a
# caller holding a device supplies the slot and this builds the node that refers to it.
#
# THE SLOT IS A PARAMETER AND NOT `next(UOp.unique_num)`. MEASURED: `grep -n "unique_num"
# tinybendygrad/uop/ops.bend` answers NOTHING -- the port has no mutable global counter,
# because an arena is threaded linearly. Upstream's `num=None` default is therefore not
# available here, and a caller that wants a fresh slot gets it from wherever it mints them.
#
# THE THREE UPSTREAM GUARDS ARE NOT SPELLED: a weak dtype, a non-storage dtype and a
# non-concrete size all `raise` upstream, and this file has no exceptions. A caller passes a
# concrete `size` and a storage `dtype`; `mxw_buf` in `mixin/movement.bend` is the f32/GLOBAL
# convenience the Tensor path uses.
def UOp.new_buffer.pa(+dev: S.Dev, size: U32, +dt: S.Dt, num: Maybe<&2, U32>) -> ParamArg:
  match num:
    case Some{n}: ParamArg{n, dt, None{}, None{}, None{}, S.AGlobal{}, Some{dev}, False{},
      None{}, None{}, False{}, None{}}
    case None{}:  ParamArg{0, dt, None{}, None{}, None{}, S.AGlobal{}, Some{dev}, False{},
      None{}, None{}, False{}, None{}}

def UOp.new_buffer(+ar: Arena, dev: S.Dev, +size: U32, dt: S.Dt, num: Maybe<&2, U32>) -> Found:
  UOp.new.param(ar, OpsBUFFER{}, Some{size}, AParam{UOp.new_buffer.pa(dev, size, dt, num)}, TNone{})

# THE READER, and the reason it takes the OWNER. `ops.py:353-357`:
# reason upstream's `size_of(owner)` takes a `UOp` (`.agents/slop/graphcmp.py:703`).
def ParamArg.size.const(arg: Arg) -> Maybe<&2, U32>:
  match arg:
    case APy{CInt{i}}: Some{H.lo32(i)}
    case _: None{}

def ParamArg.size.node(op: Op, arg: Arg) -> Maybe<&2, U32>:
  match op:
    case OpsCONST{}: ParamArg.size.const(arg)
    case _: None{}

# `max_numel()` AT THE PIN READS THROUGH A CAST: MEASURED on CPython,
# `UOp(Ops.PARAM, src=(UOp.const(4).cast(dtypes.int),)).max_numel()` is 4, and a committed
# const at this pin IS `CAST(CONST)` (a typed CONST is not one node). A reader that only
# looked at `src[0]`'s own arg answered `None` the moment `pm_cast_const` committed the
# shape arg -- MEASURED, every buffer rendered as `data0_` with no shape. One CAST level is
# what the population has; a deeper chain would need a fuel walk and is refused here.
def ParamArg.size.cast.op(op: Op, arg: Arg) -> Maybe<&2, U32>:
  match op:
    case OpsCONST{}: ParamArg.size.const(arg)
    case _: None{}

def ParamArg.size.cast(+ar: Arena, +n: U32) -> Maybe<&2, U32>:
  ParamArg.size.cast.op(Node.op(Arena.node(ar, Arena.src0(ar, n))), Arena.arg(ar, Arena.src0(ar, n)))

def ParamArg.size.alt(m: Maybe<&2, U32>, +ar: Arena, +n: U32) -> Maybe<&2, U32>:
  match m:
    case Some{k}: Some{k}
    case None{} : ParamArg.size.cast(ar, n)

def ParamArg.size.of(+ar: Arena, self: U32, +n: U32) -> Maybe<&2, U32>:
  ParamArg.size.alt(ParamArg.size.node(Node.op(Arena.node(ar, n)), Arena.arg(ar, n)), ar, n)

def ParamArg.size(+ar: Arena, +self: U32) -> Maybe<&2, U32>:
  ParamArg.size.of(ar, self, Arena.src0(ar, self))

# range -- ops.py:642. `UOp(Ops.RANGE, src=(sint_to_uop(end, dtype),)+src,
# which is `range_str`'s job and is P3 (`uop/render.py`), plus `hcq2.py:498`'s
# builds `(at, (0, 1))` (ops.py:643); a flat `arg=(at, 0, 1)` is a different
# ucache key (ops.py:201) with the same ints. `ARange` stores the ints only.
def UOp.range_shaped(ar: Arena, +end: U32, +ids: List<&2, U32>, at: AxisType, depth: U32) -> Found:
  UOp.new.shp(ar, OpsRANGE{}, [end], ARange{ids, at}, TNone{}, depth)

def UOp.range_end(ar: Arena, +end: U32, +ids: List<&2, U32>, at: AxisType) -> Found:
  UOp.range_shaped(ar, end, ids, at, 0)

# axis_id / axis_type -- ops.py:499-505 upstream, 502-508 at the pin. Both assert
# MEASURED 2026-10-03, CALLING CPython (`UOp.range(4, <axis_id>, AxisType.WEAK)`), which
# `pyrender` (render.py:101 is `repr(y) for y in x.arg`, not `axis_id`), and in
# `range_str` (ops.py:96 joins `str(x) for x in u.axis_id`) -- and this def can see
# are same-named defs of a DIFFERENT shape, `(ar, i)`, in `fold.bend`, `fold_mm_work.bend`
def UOp.axis_id(arg: Arg) -> Maybe<&2, List<&2, U32>>:
  match arg:
    case ARange{ids, at}: Some{ids}
    case _: None{}

def UOp.axis_type(arg: Arg) -> Maybe<&2, AxisType>:
  match arg:
    case ARange{ids, at}: Some{at}
    case _: None{}

# loop -- ops.py:644. `UOp(Ops.RANGE, src=(UOp(Ops.NOOP),), arg=(AxisType.WEAK, axis_id))`
def UOp.loop.go(+made: Found, +axis_id: U32) -> Found:
  UOp.range_end(Found.ar(made), Found.i(made), [axis_id], AXIS_WEAK{})

def UOp.loop(+ar: Arena, axis_id: U32) -> Found:
  UOp.loop.go(UOp.new(ar, OpsNOOP{}, Nil{}, ANone{}, TNone{}), axis_id)

# special -- ops.py:650. `UOp(Ops.SPECIAL, src=(sint_to_uop(end),), arg=name)`
def UOp.special(ar: Arena, +end: U32, nm: String) -> Found:
  UOp.new(ar, OpsSPECIAL{}, [end], AStr{nm}, TNone{})

# The graph walks. ops.py:295 and 309.

type Frame is Data:
  Frame{n: U32, visited: Bool}

type Topo is Data:
  Topo{cache: List<&2, U32>, stack: List<&2, Frame>, calls: Bool}

def Topo.empty() -> Topo:
  Topo{Nil{}, Nil{}, True{}}


def Topo.cache_add(n: U32, t: Topo) -> Topo:
  match t:
    case Topo{cache, stack, calls}: Topo{List.append(&2, U32, cache, [n]), stack, calls}


def Arena.push_srcs.go(srcs: List<&2, U32>, st: List<&2, Frame>) -> List<&2, Frame>:
  match srcs:
    case Nil{}: st
    case s <> t: Arena.push_srcs.go(t, Frame{s, False{}} <> st)


def Arena.push_srcs(+srcs: List<&2, U32>, st: List<&2, Frame>) -> List<&2, Frame>:
  Arena.push_srcs.go(List.reverse(&2, U32, srcs), st)


def Topo.srcs_of(ar: Arena, +n: U32, calls: Bool) -> List<&2, U32>:
  match calls:
    case True{}: Arena.srcs(ar, n)
    case False{}: Arena.src_without_body(ar, n)

def Topo.push.srcs(ar: Arena, +n: U32, t: Topo) -> List<&2, U32>:
  match t:
    case Topo{cache, stack, calls}: Topo.srcs_of(ar, n, calls)

def Topo.push(ar: Arena, +n: U32, +t: Topo) -> Topo:
  match t:
    case Topo{cache, stack, calls}: Topo{cache, Arena.push_srcs(Topo.push.srcs(ar, n, t), Frame{n, True{}} <> stack), calls}


def Topo.step.hit(ar: Arena, +n: U32, rest: List<&2, Frame>, seen: Bool, +cache: List<&2, U32>, calls: Bool) -> Topo:
  match seen:
    case True{}: Topo{cache, rest, calls}
    case False{}: Topo.push(ar, n, Topo{cache, rest, calls})


def Topo.step.fresh(ar: Arena, +n: U32, rest: List<&2, Frame>, +cache: List<&2, U32>, calls: Bool) -> Topo:
  Topo.step.hit(ar, n, rest, List.contains(U32, U32.is_eq, cache, n), cache, calls)

def Topo.step.vis(ar: Arena, +n: U32, visited: Bool, rest: List<&2, Frame>, cache: List<&2, U32>, calls: Bool) -> Topo:
  match visited:
    case True{}: Topo.cache_add(n, Topo{cache, rest, calls})
    case False{}: Topo.step.fresh(ar, n, rest, cache, calls)

def Topo.step(ar: Arena, t: Topo) -> Topo:
  match t:
    case Topo{cache, stack, calls}:
      match stack:
        case Nil{}: t
        case Frame{n, visited} <> rest:
          Topo.step.vis(ar, n, visited, rest, cache, calls)

def Topo.cache_of(t: Topo) -> List<&2, U32>:
  match t:
    case Topo{cache, stack, calls}: cache


def Arena.edges.f(e: U32, nd: Node) -> U32:
  U32.add(e, U32.from_nat(List.length(&2, U32, Node.src(nd))))

def Arena.edges(ar: Arena) -> U32:
  List.foldl(&2, Node, U32, Arena.edges.f, Arena.nodes(ar), 0)

def Arena.budget(+ar: Arena) -> Nat:
  U32.to_nat(U32.add(Arena.next(ar), Arena.edges(ar)))

def toposort(fuel: Nat, +ar: Arena, t: Topo) -> List<&2, U32>:
  match fuel:
    case 0n: Topo.cache_of(t)
    case 1n+p: toposort(p, ar, Topo.step(ar, t))


def UOp.toposort(fuel: Nat, +ar: Arena, self: U32) -> List<&2, U32>:
  toposort(fuel, ar, Topo.push(ar, self, Topo.empty()))


def UOp.topovisit(fuel: Nat, +ar: Arena, self: U32) -> List<&2, U32>:
  UOp.toposort(fuel, ar, self)

def UOp.toposort_nocalls(fuel: Nat, +ar: Arena, self: U32) -> List<&2, U32>:
  toposort(fuel, ar, Topo{Nil{}, List.append(&2, Frame, Nil{}, [Frame{self, False{}}]), False{}})

# the backward slice -- ops.py:280, :286, :289. three defs, one walk.
# WHY `nocalls` AND NOT `toposort`. `enter_calls=False` is the WHOLE of the
# from the front removes a different node. MEASURED on `chain`:
def bsl.go(+self: U32, xs: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case +h <> t: bsl.go(self, t, Bool.pick(List<&2, U32>, U32.is_eq(h, self), acc, List.append(&2, U32, acc, [h])))

def UOp.backward_slice(fuel: Nat, +ar: Arena, +self: U32) -> List<&2, U32>:
  bsl.go(self, UOp.toposort_nocalls(fuel, ar, self), Nil{})

def UOp.backward_slice_with_self(fuel: Nat, +ar: Arena, +self: U32) -> List<&2, U32>:
  List.append(&2, U32, [self], UOp.backward_slice(fuel, ar, self))

# topovisit -- ops.py:309. "NOTE: this shares a lot of code with toposort". It
# `src` normalisation -- ops.py:1456-1461, the `permutations` line:
# OR, XOR, all of them. Arity >= 3 is TODO(p3) ops.py:1409  def UPat.__init__ --
def all_same.from(+h: U32, t: List<&2, U32>) -> Bool:
  match t:
    case Nil{}: True{}
    case y <> u: Bool.and(U32.is_eq(h, y), all_same.from(h, u))

def all_same(ys: List<&2, U32>) -> Bool:
  match ys:
    case Nil{}: True{}
    case y <> t: all_same.from(y, t)

def perms.of(+a: U32, t: List<&2, U32>) -> List<&2, UpAlt>:
  match t:
    case Nil{}: [UpFixed{[a]}]
    case +b <> u:
      match u:
        case Nil{}: [UpFixed{[a, b]}, UpFixed{[b, a]}]
        case _ <> _w: Nil{}

def perms(ys: List<&2, U32>) -> List<&2, UpAlt>:
  match ys:
    case Nil{}: Nil{}
    case a <> t: perms.of(a, t)

def src_alts.of(same: Bool, +ys: List<&2, U32>) -> List<&2, UpAlt>:
  match same:
    case True{}: [UpFixed{ys}]
    case False{}: perms(ys)

def src_alts(+ys: List<&2, U32>) -> List<&2, UpAlt>:
  src_alts.of(all_same(ys), ys)

def alts_of(s: SrcArg) -> List<&2, UpAlt>:
  match s:
    case SNone{}: Nil{}
    case SOne{x}: [UpRepeat{x}]
    case STuple{ys}: [UpFixed{ys}]
    case SList{ys}: src_alts(ys)

# ops.py:1470. `not (allow_any_len or isinstance(src, UPat) or src is None)`

def strict_of(s: SrcArg, allow_any_len: Bool) -> Bool:
  match s:
    case SNone{}: False{}
    case SOne{_}: False{}
    case STuple{_}: Bool.not(allow_any_len)
    case SList{_}: Bool.not(allow_any_len)

# ops.py:1471. `0 if isinstance(src, UPat) or src is None else len(src)`

def required_of(s: SrcArg) -> U32:
  match s:
    case SNone{}: 0
    case SOne{_}: 0
    case STuple{ys}: U32.from_nat(List.length(&2, U32, ys))
    case SList{ys}: U32.from_nat(List.length(&2, U32, ys))

# `early_reject` -- ops.py:1476-1478. The comprehension is
def early.step.of(got: Maybe<&2, Op>, rest: List<&2, Op>) -> List<&2, Op>:
  match got:
    case Some{o}: List.append(&2, Op, rest, [o])
    case None{}: rest
def single_op.len(n: Nat, +os: List<&2, Op>) -> Maybe<&2, Op>:
  match n:
    case 1n: List.head(&2, Op, os)
    case _n: None{}

def single_op.of(o: Maybe<&2, List<&2, Op>>) -> Maybe<&2, Op>:
  match o:
    case Some{+os}: single_op.len(List.length(&2, Op, os), os)
    case None{}: None{}
def op_of.of(hit: Maybe<&2, UPat>) -> Maybe<&2, List<&2, Op>>:
  match hit:
    case Some{u}: UPat.op(u)
    case None{}: None{}

def op_of(+pat: Pat, k: U32) -> Maybe<&2, List<&2, Op>>:
  op_of.of(List.get(&2, UPat, Pat.upats(pat), U32.to_nat(k)))

def single_op(+pat: Pat, k: U32) -> Maybe<&2, Op>:
  single_op.of(op_of(pat, k))

def early.step(+pat: Pat, k: U32, rest: List<&2, Op>) -> List<&2, Op>:
  early.step.of(single_op(pat, k), rest)

def early.scan(+pat: Pat, ks: List<&2, U32>) -> List<&2, Op>:
  match ks:
    case Nil{}: Nil{}
    case k <> t: early.step(pat, k, early.scan(pat, t))

def early.alts(+pat: Pat, alts: List<&2, UpAlt>) -> List<&2, Op>:
  match alts:
    case Nil{}: Nil{}
    case UpFixed{ys} <> _: early.scan(pat, ys)
    case UpRepeat{_} <> _: Nil{}

# The constructor -- ops.py:1449. `UPat(Ops.CAST, dtype, (self,))` becomes
def early_scan(+pat: Pat, s: SrcArg, alts: List<&2, UpAlt>) -> List<&2, Op>:
  match s:
    case SNone{}: Nil{}
    case SOne{_}: Nil{}
    case STuple{_}: early.alts(pat, alts)
    case SList{_}: early.alts(pat, alts)

def early_of(+pat: Pat, s: SrcArg, custom: Maybe<&2, List<&2, Op>>, alts: List<&2, UpAlt>) -> List<&2, Op>:
  match custom:
    case Some{ers}: ers
    case None{}: early_scan(pat, s, alts)

# `dtype` -- ops.py:1480. `self.match_dtype[0] if ... else dtypes.void`.
def dt_head.of.head(h: Maybe<&2, S.Dt>) -> S.Dt:
  match h:
    case Some{d}: d
    case None{}: S.void()

def dt_head.of(md: Maybe<&2, List<&2, S.Dt>>) -> S.Dt:
  match md:
    case Some{ds}: dt_head.of.head(List.head(&2, S.Dt, ds))
    case None{}: S.void()

def UPat.dtype(u: UPat) -> S.Dt:
  dt_head.of(UPat.match_dtype(u))


def prepend(self: U32, src: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, [self], src)

# `named` -- ops.py:1485. Every field is carried across, and `not
def UPat.of.miss(+pat: Pat, want: UPat) -> PatFound:
  PatFound{pintern.put(pat, want), U32.from_nat(List.length(&2, UPat, Pat.upats(pat)))}

def UPat.of.hit(hit: Maybe<&2, U32>, +pat: Pat, +want: UPat) -> PatFound:
  match hit:
    case Some{i}: PatFound{pat, i}
    case None{}: UPat.of.miss(pat, want)

def UPat.of.put(+pat: Pat, +want: UPat) -> PatFound:
  UPat.of.hit(pintern.find(Pat.upats(pat), 0, want), pat, want)

def UPat.of(
  +pat: Pat,
  op: Maybe<&2, List<&2, Op>>,
  match_dtype: Maybe<&2, List<&2, S.Dt>>,
  +src: SrcArg,
  arg: Maybe<&2, Arg>,
  name: Maybe<&2, String>,
  allow_any_len: Bool,
  custom_early_reject: Maybe<&2, List<&2, Op>>,
  is_any: Bool) -> PatFound:

  u: UPat = UPat{op, match_dtype, arg, name, src, alts_of(src), is_any,
           strict_of(src, allow_any_len), required_of(src),
           early_of(pat, src, custom_early_reject, alts_of(src))}
  UPat.of.put(pat, u)

def UPat.named.put(u: UPat, name: String, pat: Pat) -> PatFound:
  match u:
    case UPat{op, md, arg, _, si, _, any, sl, _, _}: UPat.of(
      pat, op, md, si, arg, Some{name}, Bool.not(sl), None{}, any)
def opt_dts.one(dt: Maybe<&2, S.Dt>) -> Maybe<&2, List<&2, S.Dt>>:
  match dt:
    case Some{d}: Some{[d]}
    case None{}: None{}

def opt_dts(dt: Maybe<&2, S.Dt>) -> Maybe<&2, List<&2, S.Dt>>:
  opt_dts.one(dt)

def UPat.var(pat: Pat, name: Maybe<&2, String>, dt: Maybe<&2, S.Dt>) -> PatFound:
  UPat.of(pat, None{}, opt_dts(dt), SNone{}, None{}, name, False{}, None{}, False{})

def UPat.named.of(hit: Maybe<&2, UPat>, name: String, pat: Pat) -> PatFound:
  match hit:
    case Some{u}: UPat.named.put(u, name, pat)
    case None{}: UPat.var(pat, Some{name}, None{})

def UPat.named(+pat: Pat, k: U32, name: String) -> PatFound:
  UPat.named.of(List.get(&2, UPat, Pat.upats(pat), U32.to_nat(k)), name, pat)

# `any` / `or_casted` / `or_bitcasted` / `or_after` -- ops.py:1487-1493.

def UPat.any(pat: Pat, src: List<&2, U32>) -> PatFound:
  UPat.of(pat, None{}, None{}, STuple{src}, None{}, None{}, False{}, None{}, True{})
def UPat.or_any.pair(chosen: U32, +wrapped: PatFound) -> PatFound:
  UPat.any(PatFound.pat(wrapped), [chosen, PatFound.i(wrapped)])
def or_pick(pat: Pat, k: U32, name: Maybe<&2, String>) -> U32:
  match name:
    case None{}: k
    case Some{nm}: PatFound.i(UPat.named(pat, k, nm))
def UPat.or_any.wrap(pat: Pat, k: U32, name: Maybe<&2, String>, wrap: Op, any_len: Bool) -> PatFound:
  UPat.of(pat, Some{[wrap]}, None{}, STuple{[k]}, None{}, name, any_len, None{}, False{})

def UPat.or_any(+pat: Pat, +k: U32, +name: Maybe<&2, String>, wrap: Op, any_len: Bool) -> PatFound:
  UPat.or_any.pair(or_pick(pat, k, name), UPat.or_any.wrap(pat, k, name, wrap, any_len))

def UPat.or_casted(pat: Pat, k: U32, name: Maybe<&2, String>) -> PatFound:
  UPat.or_any(pat, k, name, OpsCAST{}, False{})

def UPat.or_bitcasted(pat: Pat, k: U32, name: Maybe<&2, String>) -> PatFound:
  UPat.or_any(pat, k, name, OpsBITCAST{}, False{})

def UPat.or_after(pat: Pat, k: U32, name: Maybe<&2, String>) -> PatFound:
  UPat.or_any(pat, k, name, OpsAFTER{}, True{})

# `var` / `cvar` / `const` -- ops.py:1495-1501. `@functools.cache` is the intern

def UPat.cvar(pat: Pat, name: Maybe<&2, String>, dt: Maybe<&2, S.Dt>, arg: Maybe<&2, Arg>) -> PatFound:
  UPat.of(pat, Some{[OpsCONST{}]}, opt_dts(dt), SNone{}, arg, name, False{}, None{}, False{})

def UPat.const(pat: Pat, b: Const, dt: Maybe<&2, S.Dt>) -> PatFound:
  UPat.of(pat, Some{[OpsCONST{}]}, opt_dts(dt), SNone{}, Some{APy{b}}, None{}, False{}, None{}, False{})

# The one-src sugar -- ops.py:1504-1522. Each is `UPat.of` with a fixed `op` and
# `sink` -- ops.py:1506. `tuple([x for x in srcs if x is not None])` filters Nones

def UPat.f(pat: Pat, k: U32, op: Op) -> PatFound:
  UPat.of(pat, Some{[op]}, None{}, STuple{[k]}, None{}, None{}, False{}, None{}, False{})

def UPat.sink(pat: Pat, srcs: List<&2, U32>) -> PatFound:
  UPat.of(pat, Some{[OpsSINK{}]}, None{}, STuple{srcs}, None{}, None{}, False{}, None{}, False{})

def UPat.index(pat: Pat, k: U32, srcs: List<&2, U32>) -> PatFound:
  UPat.of(pat, Some{[OpsINDEX{}]}, None{}, STuple{prepend(k, srcs)}, None{}, None{}, False{}, None{}, False{})

def UPat.load(pat: Pat, k: U32, srcs: List<&2, U32>) -> PatFound:
  UPat.of(pat, Some{[OpsLOAD{}]}, None{}, STuple{prepend(k, srcs)}, None{}, None{}, False{}, None{}, False{})

def UPat.store(pat: Pat, k: U32, srcs: List<&2, U32>) -> PatFound:
  UPat.of(pat, Some{[OpsSTORE{}]}, None{}, STuple{prepend(k, srcs)}, None{}, None{}, False{}, None{}, False{})

def UPat.end(pat: Pat, k: U32, srcs: List<&2, U32>) -> PatFound:
  UPat.of(pat, Some{[OpsEND{}]}, None{}, STuple{prepend(k, srcs)}, None{}, None{}, False{}, None{}, False{})

def UPat.backedge(pat: Pat, k: U32, loop: U32, cond: U32) -> PatFound:
  UPat.of(pat, Some{[OpsBACKEDGE{}]}, None{}, STuple{[k, loop, cond]}, None{}, None{}, False{}, None{}, False{})

# `reduce` -- ops.py:1516. `arg = kwargs.pop('arg', None); if isinstance(arg, Ops):
def UPat.reduce.md(u: UPat, arg: Maybe<&2, Arg>, k: U32, srcs: List<&2, U32>, pat: Pat) -> PatFound:
  match u:
    case UPat{_, md, _, _, _, _, _, _, _, _}: UPat.of(
      pat, Some{[OpsREDUCE{}]}, md, STuple{prepend(k, srcs)}, arg, None{}, False{}, None{}, False{})

def UPat.reduce.put(hit: Maybe<&2, UPat>, arg: Maybe<&2, Arg>, k: U32, srcs: List<&2, U32>, pat: Pat) -> PatFound:
  match hit:
    case Some{u}: UPat.reduce.md(u, arg, k, srcs, pat)
    case None{}: UPat.var(pat, None{}, None{})

def UPat.reduce.of(+pat: Pat, +k: U32, srcs: List<&2, U32>, arg: Maybe<&2, Arg>) -> PatFound:
  UPat.reduce.put(List.get(&2, UPat, Pat.upats(pat), U32.to_nat(k)), arg, k, srcs, pat)

def UPat.reduce(+pat: Pat, k: U32, srcs: List<&2, U32>, rop: Op, ax: U32) -> PatFound:
  UPat.reduce.of(pat, k, srcs, Some{AReduce{rop, ax}})

# `cast` -- ops.py:1510. The short-circuit `if dtype is not None and
def UPat.bitcast.put(pat: Pat, u: UPat, dt: Maybe<&2, S.Dt>, k: U32) -> PatFound:
  match u:
    case UPat{_, _, _, _, _, _, _, _, _, _}: UPat.of(
      pat, Some{[OpsBITCAST{}]}, opt_dts(dt), STuple{[k]}, None{}, None{}, False{}, None{}, False{})

def UPat.cast.same(same: Bool, +u: UPat, +dt: Maybe<&2, S.Dt>, k: U32, pat: Pat) -> PatFound:
  match same:
    case True{}: PatFound{pat, k}
    case False{}: UPat.bitcast.put(pat, u, dt, k)
def is_same_dt.of(want: Maybe<&2, List<&2, S.Dt>>, got: Maybe<&2, List<&2, S.Dt>>) -> Bool:
  match want:
    case Some{w}:
      match got:
        case Some{g}: eq_dt_list(w, g)
        case None{}: False{}
    case None{}: False{}

def is_same_dt(md: Maybe<&2, List<&2, S.Dt>>, +dt: Maybe<&2, S.Dt>) -> Bool:
  is_same_dt.of(opt_dts(dt), md)

def UPat.cast.md(+u: UPat, +dt: Maybe<&2, S.Dt>, k: U32, pat: Pat) -> PatFound:
  UPat.cast.same(is_same_dt(UPat.match_dtype(u), dt), u, dt, k, pat)

def UPat.cast.of(hit: Maybe<&2, UPat>, dt: Maybe<&2, S.Dt>, k: U32, pat: Pat) -> PatFound:
  match hit:
    case Some{u}: UPat.cast.md(u, dt, k, pat)
    case None{}: UPat.var(pat, None{}, None{})

def UPat.cast(+pat: Pat, +k: U32, dt: Maybe<&2, S.Dt>) -> PatFound:
  UPat.cast.of(List.get(&2, UPat, Pat.upats(pat), U32.to_nat(k)), dt, k, pat)

def UPat.bitcast.of(hit: Maybe<&2, UPat>, dt: Maybe<&2, S.Dt>, k: U32, pat: Pat) -> PatFound:
  match hit:
    case Some{u}: UPat.bitcast.put(pat, u, dt, k)
    case None{}: UPat.var(pat, None{}, None{})

def UPat.bitcast(+pat: Pat, +k: U32, dt: Maybe<&2, S.Dt>) -> PatFound:
  UPat.bitcast.of(List.get(&2, UPat, Pat.upats(pat), U32.to_nat(k)), dt, k, pat)

# `broadcast` -- ops.py:1519. `src=self` is a UPat, not a tuple, so this is the
def UPat.broadcast.put(pat: Pat, u: UPat, k: U32) -> PatFound:
  match u:
    case UPat{_, md, _, _, _, _, _, _, _, _}: UPat.of(
      pat, Some{[OpsSTACK{}]}, md, SOne{k}, None{}, None{}, False{}, None{}, False{})

def UPat.broadcast.of(hit: Maybe<&2, UPat>, +k: U32, pat: Pat) -> PatFound:
  match hit:
    case Some{u}: UPat.broadcast.put(pat, u, k)
    case None{}: UPat.var(pat, None{}, None{})

def UPat.broadcast(+pat: Pat, +k: U32) -> PatFound:
  UPat.broadcast.of(List.get(&2, UPat, Pat.upats(pat), U32.to_nat(k)), k, pat)

# `after` -- ops.py:1520
def UPat.after.put(pat: Pat, u: UPat, k: U32, srcs: List<&2, U32>) -> PatFound:
  match u:
    case UPat{_, md, _, _, _, _, _, _, _, _}: UPat.of(
      pat, Some{[OpsAFTER{}]}, md, STuple{prepend(k, srcs)}, None{}, None{}, False{}, None{}, False{})

def UPat.after.of(hit: Maybe<&2, UPat>, +k: U32, +srcs: List<&2, U32>, pat: Pat) -> PatFound:
  match hit:
    case Some{u}: UPat.after.put(pat, u, k, srcs)
    case None{}: UPat.var(pat, None{}, None{})

def UPat.after(+pat: Pat, +k: U32, srcs: List<&2, U32>) -> PatFound:
  UPat.after.of(List.get(&2, UPat, Pat.upats(pat), U32.to_nat(k)), k, srcs, pat)

# `alu` -- ops.py:1531.
def UPat.alu.src.of(pat: Pat, comm: Bool, op: Op, +k: U32, other: U32, md: Maybe<&2, List<&2, S.Dt>>) -> PatFound:
  match comm:
    case True{}: UPat.of(pat, Some{[op]}, md, SList{[k, other]}, None{}, None{}, False{}, None{}, False{})
    case False{}: UPat.of(pat, Some{[op]}, md, STuple{[k, other]}, None{}, None{}, False{}, None{}, False{})
def is_one_of(op: Op, want: Op) -> Bool:
  U32.is_eq(Ops.value(op), Ops.value(want))

def is_comm(+op: Op) -> Bool:
  Bool.or(is_one_of(op, OpsADD{}), Bool.or(is_one_of(op, OpsMUL{}),
  Bool.or(is_one_of(op, OpsMAX{}), Bool.or(is_one_of(op, OpsAND{}),
  Bool.or(is_one_of(op, OpsOR{}), Bool.or(is_one_of(op, OpsXOR{}),
  Bool.or(is_one_of(op, OpsCMPEQ{}), is_one_of(op, OpsCMPNE{}))))))))

def UPat.alu.src(+pat: Pat, md: Maybe<&2, List<&2, S.Dt>>, +op: Op, +k: U32, other: U32) -> PatFound:
  UPat.alu.src.of(pat, is_comm(op), op, k, other, md)
def last_md.of(hit: Maybe<&2, UPat>) -> Maybe<&2, List<&2, S.Dt>>:
  match hit:
    case Some{u}: UPat.match_dtype(u)
    case None{}: None{}

def last_md(pat: Pat, other: U32) -> Maybe<&2, List<&2, S.Dt>>:
  last_md.of(List.get(&2, UPat, Pat.upats(pat), U32.to_nat(other)))

def UPat.alu.dt.of(cmp: Bool, pat: Pat, other: U32) -> Maybe<&2, List<&2, S.Dt>>:
  match cmp:
    case True{}: Some{[S.boolean()]}
    case False{}: last_md(pat, other)
def is_cmp(+op: Op) -> Bool:
  Bool.or(U32.is_eq(Ops.value(op), Ops.value(OpsCMPLT{})),
          U32.is_eq(Ops.value(op), Ops.value(OpsCMPNE{})))

def UPat.alu.dt(+pat: Pat, +k: U32, other: U32, op: Op) -> Maybe<&2, List<&2, S.Dt>>:
  UPat.alu.dt.of(is_cmp(op), pat, other)

def UPat.alu.put(+pat: Pat, u: UPat, +op: Op, +k: U32, +other: U32) -> PatFound:
  match u:
    case UPat{_, _, _, _, _, _, _, _, _, _}: UPat.alu.src(
      pat, UPat.alu.dt(pat, k, other, op), op, k, other)

def UPat.alu.of(hit: Maybe<&2, UPat>, op: Op, +k: U32, +other: U32, pat: Pat) -> PatFound:
  match hit:
    case Some{u}: UPat.alu.put(pat, u, op, k, other)
    case None{}: UPat.var(pat, None{}, None{})

def UPat.alu(+pat: Pat, +k: U32, op: Op, other: U32) -> PatFound:
  UPat.alu.of(List.get(&2, UPat, Pat.upats(pat), U32.to_nat(k)), op, k, other, pat)

# ops.py:1474-1475: `custom_early_reject` overrides the computed set.
# `PatternMatcher` -- ops.py:1587, in its COMPILED form.
# This is not the interpreter. `ops.py:1588` is
type PMEntry is Data:
  PMEntry{tag: U32, ops: List<&2, Op>, rej: List<&2, Op>}

type PMEntrys is Data:
  PMEntrys{es: List<&2, PMEntry>}

def PMEntrys.es(ts: PMEntrys) -> List<&2, PMEntry>:
  match ts:
    case PMEntrys{es}: es

def PMEntry.tag(e: PMEntry) -> U32:
  match e:
    case PMEntry{tag, ops, rej}: tag

def PMEntry.ops(e: PMEntry) -> List<&2, Op>:
  match e:
    case PMEntry{tag, ops, rej}: ops

def PMEntry.rej(e: PMEntry) -> List<&2, Op>:
  match e:
    case PMEntry{tag, ops, rej}: rej

type Verdict is Data:
  VTrue{}
  VFalse{}
  VSkip{}

def pm_keep.take(v: Verdict) -> Verdict:
  match v:
    case VSkip{}: VSkip{}
    case VTrue{}: VTrue{}
    case VFalse{}: VFalse{}
def pm_keep.go(acc: Verdict, v: Verdict) -> Verdict:
  match acc:
    case VSkip{}: pm_keep.take(v)
    case VTrue{}: VTrue{}
    case VFalse{}: VFalse{}

def pm_keep(acc: Verdict, v: Verdict) -> Verdict:
  pm_keep.go(acc, v)

def pm_when.of(b: Bool, v: Verdict) -> Verdict:
  match b:
    case True{}: v
    case False{}: VSkip{}

def pm_when(b: Bool, v: Verdict) -> Verdict:
  pm_when.of(b, v)

def op_is(ar: Arena, self: U32, want: Op) -> Bool:
  eq_op(Arena.op(ar, self), want)

def pm_r_sink(ar: Arena, self: U32) -> Verdict:
  pm_when(op_is(ar, self, OpsSINK{}), VTrue{})
def pm_r_cast(+ar: Arena, +self: U32) -> Verdict:
  pm_when(Bool.or(op_is(ar, self, OpsCAST{}), op_is(ar, self, OpsBITCAST{})), VTrue{})
def pm_r_noop(ar: Arena, self: U32) -> Verdict:
  pm_when(op_is(ar, self, OpsNOOP{}), VTrue{})

def pm_dispatch.go(tag: U32, ar: Arena, self: U32) -> Verdict:
  match tag:
    case 0: pm_r_sink(ar, self)
    case 1: pm_r_noop(ar, self)
    case 2: pm_r_cast(ar, self)
    case _: VSkip{}

def pm_dispatch(tag: U32, ar: Arena, self: U32) -> Verdict:
  pm_dispatch.go(tag, ar, self)

def pm_try.go(ok: Bool, tag: U32, ar: Arena, self: U32) -> Verdict:
  match ok:
    case True{}: pm_dispatch(tag, ar, self)
    case False{}: VSkip{}

def pm_try.of(claimed: Bool, early: Bool, tag: U32, ar: Arena, self: U32) -> Verdict:
  pm_try.go(Bool.and(claimed, early), tag, ar, self)
def op_in(ops: List<&2, Op>, +want: Op) -> Bool:
  match ops:
    case Nil{}: False{}
    case x <> t: Bool.or(eq_op(x, want), op_in(t, want))

def pm_claimed(ops: List<&2, Op>, ar: Arena, self: U32) -> Bool:
  op_in(ops, Arena.op(ar, self))

# `any(x.op in ops for x in self.backward_slice)` -- ops.py:289. Python's comment
def op_in_bsl.go(+ar: Arena, +want: List<&2, Op>, xs: List<&2, U32>, acc: Bool) -> Bool:
  match xs:
    case Nil{}: acc
    case h <> t: op_in_bsl.go(ar, want, t, Bool.or(acc, op_in(want, Arena.op(ar, h))))

def UOp.op_in_backward_slice_with_self(fuel: Nat, +ar: Arena, +self: U32, +want: List<&2, Op>) -> Bool:
  Bool.or(op_in(want, Arena.op(ar, self)), op_in_bsl.go(ar, want, UOp.backward_slice(fuel, ar, self), False{}))

def pm_early.go(+have: List<&2, Op>, rej: List<&2, Op>) -> Bool:
  match rej:
    case Nil{}: True{}
    case o <> t: Bool.and(op_in(have, o), pm_early.go(have, t))
# `ler` is ops.py:1607's `{u.op for u in uop.src}`, so it is a FOLD OVER THE SRC
# by the spec.bend port: spec.py:201's reject set is FOUR ops, so under the pair
def pm_ler.put(x: List<&2, Op>) -> List<&2, Op>:
  x
def pm_ler.fold(ns: List<&2, Nat>, +ar: Arena, +self: U32, acc: List<&2, Op>) -> List<&2, Op>:
  match ns:
    case Nil{}: acc
    case n <> t: pm_ler.fold(t, ar, self,
      List.append(&2, Op, acc, [Arena.op(ar, Arena.src(ar, self, U32.from_nat(n)))]))

def pm_ler(+ar: Arena, +self: U32) -> List<&2, Op>:
  pm_ler.put(pm_ler.fold(List.range(U32.to_nat(Arena.nsrc(ar, self))), ar, self, Nil{}))

def pm_early(ts: PMEntrys, ar: Arena, self: U32, rej: List<&2, Op>) -> Bool:
  pm_early.go(pm_ler(ar, self), rej)

def pm_try(ts: PMEntrys, +ar: Arena, +self: U32, +e: PMEntry) -> Verdict:
  pm_try.of(pm_claimed(PMEntry.ops(e), ar, self), pm_early(ts, ar, self, PMEntry.rej(e)), PMEntry.tag(e), ar, self)

def pm_scan(+ts: PMEntrys, +ar: Arena, +self: U32, todo: List<&2, PMEntry>, acc: Verdict) -> Verdict:
  match todo:
    case Nil{}: acc
    case e <> t: pm_scan(ts, ar, self, t, pm_keep(acc, pm_try(ts, ar, self, e)))

def pm_rewrite(+ts: PMEntrys, ar: Arena, self: U32) -> Verdict:
  pm_scan(ts, ar, self, PMEntrys.es(ts), VSkip{})

# THE TABLE IS IN `.agents/slop/tables/uop-ops-4189.md` -- THE ENGINE FAMILY (`_m`). PARALLEL to the `pm_rewrite` family above; this

type Aa is Data:
  Aa{b: U32, v: U32}

type CallifyCtx is Data:
  CallifyCtx{replacements: List<&2, U32>, allocs: List<&2, Aa>, views: List<&2, U32>, stores: List<&2, U32>}

def CallifyCtx.of(replacements: List<&2, U32>, allocs: List<&2, Aa>, views: List<&2, U32>, stores: List<&2, U32>) -> CallifyCtx:
  CallifyCtx{replacements, allocs, views, stores}

def callify_ctx() -> CallifyCtx:
  CallifyCtx.of(Nil{}, Nil{}, Nil{}, Nil{})

def CallifyCtx.replacements(x: CallifyCtx) -> List<&2, U32>:
  match x:
    case CallifyCtx{replacements, allocs, views, stores}: replacements

def CallifyCtx.allocs(x: CallifyCtx) -> List<&2, Aa>:
  match x:
    case CallifyCtx{replacements, allocs, views, stores}: allocs

def CallifyCtx.views(x: CallifyCtx) -> List<&2, U32>:
  match x:
    case CallifyCtx{replacements, allocs, views, stores}: views

def CallifyCtx.stores(x: CallifyCtx) -> List<&2, U32>:
  match x:
    case CallifyCtx{replacements, allocs, views, stores}: stores

def Aa.b(x: Aa) -> U32:
  match x:
    case Aa{b, v}: b

def Aa.v(x: Aa) -> U32:
  match x:
    case Aa{b, v}: v

def ag_pick(hit: Bool, acc: Maybe<&2, U32>, v: U32) -> Maybe<&2, U32>:
  match hit:
    case True{} : Some{v}
    case False{}: acc

def ag_go(+as: List<&2, Aa>, +b: U32, acc: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match as:
    case Nil{}       : acc
    case Aa{j, v} <> t: ag_go(t, b, ag_pick(U32.is_eq(j, b), acc, v))

def aa_get(+c: CallifyCtx, +b: U32) -> Maybe<&2, U32>:
  ag_go(CallifyCtx.allocs(c), b, None{})

def ap_tail(found: Bool, +b: U32, +v: U32) -> List<&2, Aa>:
  match found:
    case True{} : Nil{}
    case False{}: [Aa{b, v}]

def ap_pick(hit: Bool, r: List<&2, Aa>, j: U32, old: U32, +v: U32) -> List<&2, Aa>:
  match hit:
    case True{} : List.append(&2, Aa, [Aa{j, v}], r)
    case False{}: List.append(&2, Aa, [Aa{j, old}], r)

def ap_go(+as: List<&2, Aa>, found: Bool, +b: U32, +v: U32) -> List<&2, Aa>:
  match as:
    case Nil{}        : ap_tail(found, b, v)
    case Aa{j, old} <> t:
      r = ap_go(t, Bool.or(found, U32.is_eq(j, b)), b, v)
      ap_pick(U32.is_eq(j, b), r, j, old, v)

def aa_put(+c: CallifyCtx, +b: U32, +v: U32) -> CallifyCtx:
  CallifyCtx.of(CallifyCtx.replacements(c),
    ap_go(CallifyCtx.allocs(c), False{}, b, v),
    CallifyCtx.views(c), CallifyCtx.stores(c))

def aa_has(+as: List<&2, Aa>, +b: U32) -> Bool:
  match as:
    case Nil{}       : False{}
    case Aa{j, _} <> t: Bool.or(U32.is_eq(j, b), aa_has(t, b))

# 3. `collect_stores` -- __init__.py:220-221. NEEDS ctx, and it is one of only
# that mutated the ctx and returned the node would be a DIFFERENT rule, so the
type CTX is Data:
  CArgs{xs: List<&2, U32>}
  CNodes{m: Map<&2, U32>}
  # `canonicalize_alloc`'s ctx. IT IS HERE AND NOT IN `schedule/` FOR A MEASURED
  CCallify{c: CallifyCtx}

def CTX.has_hit.m(r: Sigma<&1, &1, Map<&2, U32>, _ => Bool>) -> Bool:
  match r:
    case Tuple{m, v}: v

def CTX.get_v.m(r: Sigma<&1, &1, Map<&2, U32>, _ => U32>) -> U32:
  match r:
    case Tuple{m, v}: v

def CTX.at_node.of(hit: Bool, +m: Map<&2, U32>, +self: U32) -> Maybe<&2, U32>:
  match hit:
    case True{}: Some{CTX.get_v.m(Map.get(U32, 0, m, U32.show(self)))}
    case False{}: None{}

def CTX.at_node(+m: Map<&2, U32>, +self: U32) -> Maybe<&2, U32>:
  CTX.at_node.of(CTX.has_hit.m(Map.has(&2, U32, m, U32.show(self))), m, self)

def CTX.at(+ctx: CTX, n: Nat, +self: U32) -> Maybe<&2, U32>:
  match ctx:
    case CArgs{xs}: List.get(&2, U32, xs, n)
    case CNodes{m}: CTX.at_node(m, self)
    case CCallify{c}: None{}

def pm_r_sink_m(+ctx: CTX, ar: Arena, self: U32) -> Maybe<&2, U32>:
  Some{self}

def pm_r_cast_m(+ctx: CTX, +ar: Arena, +self: U32) -> Maybe<&2, U32>:
  Some{self}

def pm_r_noop_m(+ctx: CTX, ar: Arena, self: U32) -> Maybe<&2, U32>:
  Some{Arena.src(ar, self, 0)}

def pm_r_param_m.slot(arg: Arg) -> U32:
  match arg:
    case AParam{pa}: ParamArg.slot(pa)
    case _: 4294967295

def pm_r_param_m.go(slot: U32, +ctx: CTX) -> Maybe<&2, U32>:
  match slot ctx:
    case 0 CArgs{xs}: List.get(&2, U32, xs, U32.to_nat(0))
    case 1 CArgs{xs}: List.get(&2, U32, xs, U32.to_nat(1))
    case _ CArgs{xs}: None{}
    case _ CNodes{m}: None{}
    case _ CCallify{c}: None{}

def pm_r_param_m(+ctx: CTX, +ar: Arena, +self: U32) -> Maybe<&2, U32>:
  pm_r_param_m.go(pm_r_param_m.slot(Arena.arg(ar, self)), ctx)

def pm_r_alloc_m.at.go(xs: List<&2, U32>, n: Nat) -> Maybe<&2, U32>:
  match xs:
    case Nil{}: None{}
    case h <> t:
      match n:
        case 0n: Some{h}
        case 1n+p: pm_r_alloc_m.at.go(t, p)

def pm_r_alloc_m.at(+ctx: CTX, n: Nat) -> Maybe<&2, U32>:
  match ctx:
    case CArgs{xs}: pm_r_alloc_m.at.go(xs, n)
    case CNodes{m}: None{}
    case CCallify{c}: None{}

def pm_r_alloc_m(+ctx: CTX, +ar: Arena, +self: U32) -> Maybe<&2, U32>:
  pm_r_alloc_m.at(ctx, 2n)

# THE OPS.PY RULE TABLES -- ops.py:1863 symbol=_substitute,
# ops.py:1864 symbol=_pm_resolve_params, ops.py:1873 symbol=pm_drop_after, and
# tinygrad/uop/spec.py:207 symbol=spec_program. The FOURTH is NOT IN upstream's
# `ops.py:1591-1593` symbol=PatternMatcher.__init__ is where a `PMEntry` comes from, and it is three lines:
# SET, and it is `ops.py:1565` symbol=PatternMatcher.rewrite's
# shortcut. `ops.py:1469-1470` symbol=UPat.__init__ computes `upat_match` and
# `ops.py:1565` symbol=PatternMatcher.rewrite's `if not early_reject.issubset(ler): continue`
# `tuple(Ops)` -- the claim of ops.py:1863 symbol=_substitute's
# `UPat(tuple(Ops), name="x")` and of tinygrad/uop/spec.py:207 symbol=spec_program's
# (tinygrad/uop/__init__.py:137 symbol=GroupOp.All), measured by CPython:
def all_ops() -> List<&2, Op>:
  [OpsSPECIAL{} OpsBUFFER{} OpsALLOC{} OpsNOOP{} OpsREWRITE_ERROR{} OpsPARAM{} OpsREFPARAM{} OpsCALL{} OpsPROGRAM{} OpsLINEAR{} OpsSOURCE{} OpsBINARY{},
   OpsSINK{} OpsAFTER{} OpsSTACK{} OpsGETADDR{} OpsINDEX{} OpsSHRINK{} OpsLOAD{} OpsSTORE{} OpsWMMA{} OpsCAST{},
   OpsBITCAST{} OpsEXP2{} OpsLOG2{} OpsSIN{} OpsSQRT{} OpsRECIP{} OpsNEG{} OpsTRUNC{} OpsADD{} OpsMUL{} OpsSHL{},
   OpsSHR{} OpsTRUNCDIV{} OpsMAX{} OpsTRUNCMOD{} OpsCMPLT{} OpsCMPNE{} OpsCMPEQ{} OpsXOR{} OpsOR{} OpsAND{} OpsTHREEFRY{},
   OpsSUB{} OpsFDIV{} OpsPOW{} OpsDIV{} OpsMOD{} OpsWHERE{} OpsMULACC{} OpsBARRIER{} OpsRANGE{} OpsIF{} OpsEND{},
   OpsENDIF{} OpsBACKEDGE{} OpsCONST{} OpsCUSTOM{} OpsCUSTOMI{} OpsINS{} OpsCONTIGUOUS_BACKWARD{} OpsDETACH{} OpsSTAGE{} OpsCOPY{} OpsMSELECT{},
   OpsMSTACK{} OpsCUSTOM_FUNCTION{} OpsRESHAPE{} OpsPERMUTE{} OpsEXPAND{} OpsPAD{} OpsUNSHARD{} OpsREDUCE{} OpsALLREDUCE{} OpsPYLITERAL{}]

# which is NOT IN upstream's `ops.py` at this pin (upstream has NO `remove_all_tags`); the surviving upstream construct is tinygrad/uop/spec.py:207 symbol=spec_program's `UPat(GroupOp.All-{Ops.CONST}, dtypes.weaks)`. `Tag`'s bottom
def tag_is_none(t: Tag) -> Bool:
  match t:
    case TNone{}: True{}
    case _: False{}

# TAG 40 -- ops.py:1873 symbol=pm_drop_after. `pm_drop_after`:
def pm_r_drop_m(+ctx: CTX, +ar: Arena, +self: U32) -> Maybe<&2, U32>:
  Some{Arena.src(ar, self, 0)}

# TAG 42 -- ops.py:1864 symbol=_pm_resolve_params. `_pm_resolve_params`:
def pm_r_rp_m.slot(arg: Arg) -> U32:
  match arg:
    case AParam{pa}: ParamArg.slot(pa)
    case _: 4294967295

def pm_r_rp_m.at(+ctx: CTX, slot: U32) -> Maybe<&2, U32>:
  match ctx slot:
    case CArgs{xs} 4294967295: None{}
    case CArgs{xs} _: List.get(&2, U32, xs, U32.to_nat(slot))
    case CNodes{m} _: None{}
    case CCallify{c} _: None{}

def pm_r_rp_m(+ctx: CTX, +ar: Arena, +self: U32) -> Maybe<&2, U32>:
  pm_r_rp_m.at(ctx, pm_r_rp_m.slot(Arena.arg(ar, self)))

def pm_dispatch_m.go(tag: U32, ar: Arena, self: U32, +ctx: CTX) -> Maybe<&2, U32>:
  match tag:
    case 0: pm_r_sink_m(ctx, ar, self)
    case 1: pm_r_noop_m(ctx, ar, self)
    case 2: pm_r_cast_m(ctx, ar, self)
    case 3: pm_r_param_m(ctx, ar, self)
    case 4: pm_r_alloc_m(ctx, ar, self)
    case 40: pm_r_drop_m(ctx, ar, self)
    case 42: pm_r_rp_m(ctx, ar, self)
    case _: None{}

def pm_dispatch_m(tag: U32, ar: Arena, self: U32, ctx: CTX) -> Maybe<&2, U32>:
  pm_dispatch_m.go(tag, ar, self, ctx)

def pm_try_m.go(ok: Bool, tag: U32, ar: Arena, self: U32, +ctx: CTX) -> Maybe<&2, U32>:
  match ok:
    case True{}: pm_dispatch_m(tag, ar, self, ctx)
    case False{}: None{}

def pm_try_m.of(claimed: Bool, early: Bool, tag: U32, ar: Arena, self: U32, ctx: CTX) -> Maybe<&2, U32>:
  pm_try_m.go(Bool.and(claimed, early), tag, ar, self, ctx)

def pm_try_m(ts: PMEntrys, +ar: Arena, +self: U32, +e: PMEntry, +ctx: CTX) -> Maybe<&2, U32>:
  pm_try_m.of(pm_claimed(PMEntry.ops(e), ar, self), pm_early(ts, ar, self, PMEntry.rej(e)), PMEntry.tag(e), ar, self, ctx)

def pm_scan_m(+ts: PMEntrys, +ar: Arena, +self: U32, todo: List<&2, PMEntry>, acc: Maybe<&2, U32>, +ctx: CTX) -> Maybe<&2, U32>:
  match todo:
    case Nil{}: acc
    case e <> t:
      match acc:
        case Some{value}: acc
        case None{}: pm_scan_m(ts, ar, self, t, pm_try_m(ts, ar, self, e, ctx), ctx)

def pm_rewrite_m(+ts: PMEntrys, +ar: Arena, +self: U32, +ctx: CTX) -> Maybe<&2, U32>:
  pm_scan_m(ts, ar, self, PMEntrys.es(ts), None{}, ctx)

# linearity. `ops.py:1565` symbol=PatternMatcher.rewrite and `ops.py:1663` symbol=TrackedPatternMatcher.rewrite type the pass's `ctx` as `ctx=None`, and each lambda
# already paid for: `remove_all_tags` MINTS. `ops.py:245-249` symbol=UOp.replace returns
# TAG 41 -- tinygrad/uop/spec.py:207 symbol=spec_program. `remove_all_tags`:
# `ops.py:245-249` symbol=UOp.replace is what `replace(tag=None)` is:
# "every op" is tinygrad/uop/spec.py:207 symbol=spec_program. And the implementation
def pm_r_tag_m.of(untagged: Bool, made: Found) -> Maybe<&2, Found>:
  Bool.pick(Maybe<&2, Found>, untagged, None{}, Some{made})

def pm_r_tag_m(+ctx: CTX, +ar: Arena, +self: U32) -> Maybe<&2, Found>:
  pm_r_tag_m.of(tag_is_none(Arena.tag(ar, self)),
    UOp.new(ar, Arena.op(ar, self), Arena.srcs(ar, self), Arena.arg(ar, self), TNone{}))

# TAG 43 -- ops.py:1863 symbol=_substitute. `_substitute`:
# The ctx is `dvars: dict[UOp, UOp]` (`ops.py:506` symbol=UOp.substitute), so it is keyed by the NODE
def pm_sub_m.of(r: Sigma<&1, &1, Map<&2, U32>, _ => U32>, s: Sigma<&1, &1, Map<&2, U32>, _ => Bool>) -> Maybe<&2, U32>:
  match r, s:
    case Tuple{m, v}, Tuple{n, b}: Bool.pick(Maybe<&2, U32>, b, Some{v}, None{})

def pm_sub_m(+ctx: Map<&2, U32>, +ar: Arena, +self: U32) -> Maybe<&2, U32>:
  pm_sub_m.of(Map.get(U32, 0, ctx, U32.show(self)), Map.has(&2, U32, ctx, U32.show(self)))

# and each entry's three fields are `ops.py:1604`'s `[p, None, p.early_reject]`
# scan that reads a table and the dispatch that reads a tag live in DIFFERENT
def pm_substitute() -> PMEntrys:
  PMEntrys{[PMEntry{43, all_ops(), Nil{}}]}

def pm_resolve_params() -> PMEntrys:
  PMEntrys{[PMEntry{42, [OpsPARAM{}], Nil{}}]}

def pm_remove_all_tags() -> PMEntrys:
  PMEntrys{[PMEntry{41, all_ops(), Nil{}}]}

def pm_drop_after_table() -> PMEntrys:
  PMEntrys{[PMEntry{40, [OpsAFTER{}], Nil{}}]}

# `_f` IS THE `_m` FAMILY WITH A DIFFERENT ANSWER, so it is the same five defs in
# order (ops.py:1618's `return ret` on the first non-None).
def pm_try_f.go(ok: Bool, +ar: Arena, +self: U32, +ctx: CTX) -> Maybe<&2, Found>:
  match ok:
    case True{}: pm_r_tag_m(ctx, ar, self)
    case False{}: None{}

def pm_try_f.of(claimed: Bool, early: Bool, +ar: Arena, +self: U32, +ctx: CTX) -> Maybe<&2, Found>:
  pm_try_f.go(Bool.and(claimed, early), ar, self, ctx)

def pm_try_f(ts: PMEntrys, +ar: Arena, +self: U32, +e: PMEntry, +ctx: CTX) -> Maybe<&2, Found>:
  pm_try_f.of(pm_claimed(PMEntry.ops(e), ar, self), pm_early(ts, ar, self, PMEntry.rej(e)), ar, self, ctx)

def pm_scan_f(+ts: PMEntrys, +ar: Arena, +self: U32, todo: List<&2, PMEntry>, acc: Maybe<&2, Found>, +ctx: CTX) -> Maybe<&2, Found>:
  match todo:
    case Nil{}: acc
    case e <> t:
      match acc:
        case Some{value}: acc
        case None{}: pm_scan_f(ts, ar, self, t, pm_try_f(ts, ar, self, e, ctx), ctx)

def pm_rewrite_f(+ts: PMEntrys, +ar: Arena, +self: U32, +ctx: CTX) -> Maybe<&2, Found>:
  pm_scan_f(ts, ar, self, PMEntrys.es(ts), None{}, ctx)

# ops.py:1609 is `if not early_reject.issubset(ler): continue`, so the rule FIRES
def src_op(+ar: Arena, self: U32, n: U32, want: Op) -> Bool:
  op_is(ar, Arena.src(ar, self, n), want)

# `UPatCompileError` -- ops.py:1588 raises when a pattern's source cannot be read,
# `is_any` is a DISJUNCTION, which is what upat.py:18 compiles it to. The
# THE BASE FAMILY -- ops.py:785 `base`, :792 `unsharded_base`, :801
# `base` -- ops.py:785. `if self.op in GroupOp.Movement: return self.src[0].base;
def UOp.base.peel(+ar: Arena, +self: U32) -> Bool:
  Bool.or(GroupOp.movement(Arena.op(ar, self)), eq_op(Arena.op(ar, self), OpsDETACH{}))

def UOp.base(fuel: Nat, +ar: Arena, +self: U32) -> U32:
  match fuel:
    case 0n: self
    case 1n+p: UOp.base(p, ar, Bool.pick(U32, UOp.base.peel(ar, self), Arena.src(ar, self, 0), self))

# `unsharded_base` -- ops.py:792. Python's second and third arms are `self.src[0]
def UOp.unsharded_base.peel(+ar: Arena, +self: U32) -> Bool:
  Bool.or(UOp.base.peel(ar, self), eq_op(Arena.op(ar, self), OpsUNSHARD{}))

def UOp.unsharded_base(fuel: Nat, +ar: Arena, +self: U32) -> U32:
  match fuel:
    case 0n: self
    case 1n+p: UOp.unsharded_base(p, ar, Bool.pick(U32, UOp.unsharded_base.peel(ar, self), Arena.src(ar, self, 0), self))

# `storage_base` -- ops.py:801. Python is `b = self.unsharded_base; while b.op in
def UOp.storage_base.peel(+ar: Arena, +self: U32) -> Bool:
  Bool.or(UOp.unsharded_base.peel(ar, self),
    Bool.or(eq_op(Arena.op(ar, self), OpsBITCAST{}), eq_op(Arena.op(ar, self), OpsAFTER{})))

def UOp.storage_base(fuel: Nat, +ar: Arena, +self: U32) -> U32:
  match fuel:
    case 0n: self
    case 1n+p: UOp.storage_base(p, ar, Bool.pick(U32, UOp.storage_base.peel(ar, self), Arena.src(ar, self, 0), self))

# `without_after` -- ops.py:623. `self.src[0].without_after if self.op is Ops.AFTER
def UOp.without_after(fuel: Nat, +ar: Arena, +self: U32) -> U32:
  match fuel:
    case 0n: self
    case 1n+p: UOp.without_after(p, ar, Bool.pick(U32, eq_op(Arena.op(ar, self), OpsAFTER{}), Arena.src(ar, self, 0), self))

# `buf_uop` -- ops.py:925. NOT a peel: Python walks while `len(s.src) and s.op not
def UOp.buf_uop.cont(op: Op) -> Bool:
  match op:
    case OpsBUFFER{}: False{}
    case OpsALLOC{}: False{}
    case OpsPARAM{}: False{}
    case OpsREFPARAM{}: False{}
    case OpsSTAGE{}: False{}
    case OpsMSTACK{}: False{}
    case _: True{}

def UOp.buf_uop.walk(+ar: Arena, +self: U32) -> Bool:
  Bool.and((Arena.nsrc(ar, self) > 0 : U32), UOp.buf_uop.cont(Arena.op(ar, self)))

def UOp.buf_uop(fuel: Nat, +ar: Arena, +self: U32) -> U32:
  match fuel:
    case 0n: self
    case 1n+p: UOp.buf_uop(p, ar, Bool.pick(U32, UOp.buf_uop.walk(ar, self), Arena.src(ar, self, 0), self))

# `has_buffer_identity` -- ops.py:952. A `U32 -> Bool` walk, so the same shape
def op_in3(+op: Op) -> Bool:
  Bool.or(eq_op(op, OpsRESHAPE{}), Bool.or(eq_op(op, OpsUNSHARD{}), eq_op(op, OpsMSELECT{})))

def UOp.has_buffer_identity.walk(after_ok: Bool, +ar: Arena, +self: U32) -> Bool:
  Bool.or(op_in3(Arena.op(ar, self)), Bool.and(after_ok, eq_op(Arena.op(ar, self), OpsAFTER{})))

def UOp.has_buffer_identity.term(op: Op) -> Bool:
  match op:
    case OpsBUFFER{}: True{}
    case OpsALLOC{}: True{}
    case OpsPARAM{}: True{}
    case OpsREFPARAM{}: True{}
    case _: False{}

def UOp.has_buffer_identity(fuel: Nat, +after_ok: Bool, +ar: Arena, +self: U32) -> Bool:
  match fuel:
    case 0n: UOp.has_buffer_identity.term(Arena.op(ar, self))
    case 1n+p: Bool.pick(Bool, UOp.has_buffer_identity.walk(after_ok, ar, self),
      UOp.has_buffer_identity(p, after_ok, ar, Arena.src(ar, self, 0)),
      UOp.has_buffer_identity.term(Arena.op(ar, self)))

# THE MOVERS -- ops.py:624 `barrier`, :679 `bufferize`, :680 `allreduce`,
# ops.py:501-1928 is not.
# `bufferize` -- ops.py:679. `UOp(Ops.STAGE, src=(self,)+args, kwargs)`, and
def UOp.bufferize(ar: Arena, +self: U32, +args: List<&2, U32>) -> Found:
  UOp.new(ar, OpsSTAGE{}, List.append(&2, U32, [self], args), ABad{}, TNone{})

# `barrier` -- ops.py:624. `UOp(Ops.BARRIER, src=(self,)+src)`, self FIRST, the
def UOp.barrier(ar: Arena, +self: U32, +src: List<&2, U32>) -> Found:
  UOp.new(ar, OpsBARRIER{}, List.append(&2, U32, [self], src), ABad{}, TNone{})

# `allreduce` -- ops.py:680. `UOp(Ops.ALLREDUCE, src=(self,), arg=(op, device))`
def UOp.allreduce(ar: Arena, +self: U32, +rop: Op, +dev: S.Dev) -> Found:
  UOp.new(ar, OpsALLREDUCE{}, [self], AAllred{rop, dev}, TNone{})

# `mselect` -- ops.py:772. `UOp(Ops.MSELECT, src=(self,), arg=arg)` where `arg` is
# `ABlob` is BINARY's BYTES, not "a bare number in the arg": `ops.py:201`'s key holds
# `runs/graphcmp/D/D1-graph-mselect.txt`, VERDICT DISAGREE), which is the wall this
def UOp.mselect(ar: Arena, +self: U32, k: U32) -> Found:
  UOp.new(ar, OpsMSELECT{}, [self], AInt{k}, TNone{})

# `sharding` -- ops.py:707. `tuple(zip(self.arg, self.src[1:])) if self.op is
type Shard is Data: Shard{ax: U32, rng: U32}

def sharding.go(xs: List<&2, U32>, ys: List<&2, U32>, acc: List<&2, Shard>) -> List<&2, Shard>:
  match xs ys:
    case Nil{} _: acc
    case x <> xt Nil{}: acc
    case x <> xt y <> yt: sharding.go(xt, yt, List.append(&2, Shard, acc, [Shard{x, y}]))

def sharding.pair(arg: Arg, ar: Arena, self: U32) -> List<&2, Shard>:
  match arg:
    case ATuple{ys}: sharding.go(ys, Arena.src_from(ar, self, 1), Nil{})
    case _: Nil{}

def UOp.sharding(+ar: Arena, +self: U32) -> List<&2, Shard>:
  Bool.pick(List<&2, Shard>, eq_op(Arena.op(ar, self), OpsUNSHARD{}),
    sharding.pair(Arena.arg(ar, self), ar, self), Nil{})

# `split_uop` -- ops.py:685. `if self.op is sep: for s in self.src: yield from
# THE STEP IS A `Bool.pick` AND NOT A `match`, because `sep` is a PARAMETER and
type Wk is Data: Wk{work: List<&2, U32>, out: List<&2, U32>}

def Wk.out(w: Wk) -> List<&2, U32>:
  match w:
    case Wk{work, out}: out

# MEASURED, and this is the bug the shape exists to prevent: the first version had
type Nd is Data: Nd{go: Bool, srcs: List<&2, U32>, i: U32}

def UOp.split_uop.node(+ar: Arena, +sep: Op, +h: U32) -> Nd:
  Nd{op_is(ar, h, sep), Arena.srcs(ar, h), h}

def split_uop.step(nd: Nd, work: List<&2, U32>, out: List<&2, U32>) -> Wk:
  match nd:
    case Nd{go, srcs, i}:
      match go:
        # AND THE ORDER IS UPSTREAM's.  MEASURED 2026-11-24: ON `ADD(x, y)`
        # THE PORT YIELDS `x, y` AND UPSTREAM YIELDS `x, y`
        # (`for s in self.src: yield from s.split_uop(sep)`, ops.py:656), AND
        # THE PORT's `work` IS A STACK WHOSE SRCS GO ON THE FRONT AND WHOSE
        # HEAD IS POPPED -- SO THE TERMS COME OUT REVERSED AT ONE LEVEL AND
        # **THE `out` IS BUILT BY APPENDING**, WHICH RESTORES THEM AT EVERY
        # LEVEL, BECAUSE A NESTED SRC's OWN TERMS ARE REVERSED THE SAME WAY.
        # AND A FIRST DRAFT READ THE STACK AS A QUEUE AND "FIXED" IT WITH A
        # PREPEND, AND THAT MADE IT **WRONG** -- MEASURED, `3 2` INSTEAD OF
        # `2 3` -- SO THE ORDER IS RIGHT AND THE COMMENT IS WHAT WAS WRONG.
        case True{}: Wk{List.append(&2, U32, srcs, work), out}
        case False{}: Wk{work, List.append(&2, U32, out, [i])}


def UOp.split_uop.pop(fuel: Nat, +ar: Arena, +sep: Op, w: Wk) -> Wk:
  match fuel:
    case 0n: w
    case 1n+p:
      match w:
        case Wk{work, out}:
          match work:
            case Nil{}: w
            case h <> rest: UOp.split_uop.pop(p, ar, sep, split_uop.step(UOp.split_uop.node(ar, sep, h), rest, out))

def UOp.split_uop(fuel: Nat, +ar: Arena, self: U32, +sep: Op) -> List<&2, U32>:
  Wk.out(UOp.split_uop.pop(fuel, ar, sep, Wk{[self], Nil{}}))

# `sint_to_uop` -- ops.py:1860 symbol=sint_to_uop. `UOp.const(x, dtype=dtypes.weakint)`, and the
def UOp.sint_to_uop(ar: Arena, s: Sint) -> Found:
  match s:
    case SU{u}: Found{ar, u}
    case SI{i}: UOp.new(ar, OpsCONST{}, Nil{}, APy{CInt{i}}, TNone{})

# `gate_kernel_sink` -- ops.py:1880 symbol=gate_kernel_sink. Three arms, two of them NEGATIVE tests, and
def gate_kernel_sink.arg(arg: Arg) -> Bool:
  match arg:
    case AKernel{ki}: False{}
    case _: True{}

# ops.py:1-500. WHERE EACH NAME ACTUALLY LIVES NOW.
#     bsl.go, UOp.backward_slice (ops.py:280), UOp.backward_slice_with_self (:286)
#     ops.py:18  AxisType.__repr__   -> axis_repr        (render.bend:550)
#     ops.py:41  ParamArg.__repr__   -> paramarg_repr    (render.bend:501)
#     ops.py:269 UOp.__repr__        -> pretty_print, render.bend's `pyrender`
#     ops.py:329 UOp._shape        -> fold.shape.of / dt_shape  (fold.bend:882)
#     ops.py:456 UOp.shape         -> UOp.shape                (fold.bend:3994)
#     ops.py:470 UOp.ended_ranges  -> UOp.ended_ranges         (fold.bend:3969)
# TODO(p3) ops.py:75  def srender
# TODO(p3) ops.py:1135  def sym_infer
# WALL(p3) ops.py:212  def __init__ -- BLOCKED. STORE A FUNCTION IN A DATA FIELD -- `recursive_property.__init__` keeps `self.fxn`. The
#   `Data`, MEASURED. (A function as a PARAMETER is fine -- `bend guide:69` says functions may
# TODO(p3) ops.py:211  def __get__
# WALL(p3) ops.py:240  def __del__ -- BLOCKED. NO GARBAGE COLLECTOR TO CALL IT. `bend guide:646` -- "values are affine, a `match` frees
# WALL(p3) ops.py:244  def __reduce__ -- BLOCKED. THE PICKLE PROTOCOL. `return UOp, (op, src, arg, tag, metadata)` is a `__reduce__`: an
# TODO(p3) ops.py:254  def key
# wall(p3) ops.py:284  def _bool_slice -- blocked. needs `fold`'s walk and a dtype predicate, so it lives downstream of this file like
# TODO(p3) ops.py:279  def bool_slice
# wall(p3) ops.py:316  def tuplize -- blocked. the mechanism is replaced, not missing. `tuplize` builds `(op.value, repr(arg), dtype, *(src
#   consumers are outside ops.py anyway -- `codegen/late/linearizer.py:36` (a sort) and
#   `uop/symbolic.py:225` (a rewrite rule) -- and neither is ported.
# TODO(p3) ops.py:436  def shard_shape
# TODO(p3) ops.py:442  def max_shard_shape
# PORTED -- `ops.py:481 _ranges` and `ops.py:495 ranges` are `fold.bend`'s
# TODO(p3) ops.py:471  def ranges
# TODO(p3) ops.py:495  def simplify
# DONE(p3) ops.py:92 def ssimplify -- `ssimplify_of` and `UOp.ssimplify_val` /
#   documented wall in this file (`ops.py:511`, "* uop evaluation *") and 3,679 lines of
# done(p3) ops.py:521 def _eval -- and it was misfiled here, which is the finding. `_eval` needs
# TODO(p3) ops.py:503  def __bool__   -- DONE, same gate (`bool_true`, `bool_false`,
# TODO(p3) ops.py:504  def __int__    -- DONE, same gate (`int_weakint`, `int_i32`,
# TODO(p3) ops.py:505  def __float__  -- DONE, same gate (`float_weakfloat`,
# TODO(p3) ops.py:506  def substitute
# TODO(p3) ops.py:513  def __index__
# TODO(p3) ops.py:526  def trace_num
# WALL(p3) ops.py:563  def __getitem__ -- BLOCKED. PYTHON'S SLICE PROTOCOL. The body calls `super(UOp, self).__getitem__(idx)`,
# done(p3) ops.py:597 def _uop -- and the honest answer is that there is nothing to
#   names `Tensor.u` as `_uop -- tensor.py:118` and every graph-building method there
# done(p3) ops.py:599 def _wrap_uop -- same reason, and it is the stronger one.
# TODO(p3) ops.py:572  def const_like
# TODO(p3) ops.py:578  def ufix
# TODO(p3) ops.py:585  def store
# TODO(p3) ops.py:594  def ins
# TODO(p3) ops.py:595  def contract
# TODO(p3) ops.py:612  def cconst
#   ops.py:610 -- a FORCED CAST is needed for bool because the ordinary cast
# TODO(p3) ops.py:621  def wmma
#   ops.py:622 -- the input dtype lives in the arg, not in `src[0].dtype`,
# PORTED -- `ops.py:652 _rop` is `tensor.bend`'s `tn_rop`, which is
# TODO(p3) ops.py:635  def invalid
# DONE(p3) ops.py:664 def valid -- `UOp.where` and `UOp.valid_of` above, gated at
#   `gates/ops-core-gate.py` in FOUR rows. `where` is `mixin/elementwise.py:426`'s
#   finds a different node -- I read `ANone{}` out of three srcs that were there all along. MEASURED
# TODO(p3) ops.py:637  def get_idx
# TODO(p3) ops.py:643  def reduce
# TODO(p3) ops.py:652  def overflows
# WALL(p3) ops.py:670  def unshard -- BLOCKED. `def _shard` IS ABSENT -- checked as a definition, comments excluded. `unshard` builds a
#   ops.py:663-665 -- an UNSHARD carries one sharding RANGE per sharded axis;
# WALL(p3) ops.py:690  def bounds -- BLOCKED. `def max_numel` IS ABSENT, and `bounds` also reads `self.axis` and a device COUNT
# TODO(p3) ops.py:681  def axis
# TODO(p3) ops.py:713  def _shard
# WALL(p3) ops.py:734  def shard -- BLOCKED. `def _shard` IS ABSENT -- the same one `unshard` needs. `copy_to_device` IS present, so
# TODO(p3) ops.py:729  def store_call  -- BLOCKED, and is `self.param_like(0).store(...).call(self, src)`.
# TODO(p3) ops.py:736  def on_disk  -- BLOCKED, and is `device.startswith("DISK")`.
# TODO(p3) ops.py:737  def on_creation_device  -- BLOCKED, and is `device.startswith(...)`.
# PORTED -- `ops.py:818 _mop` is `tensor.bend`'s `tn_mop`, which is
# PORTED -- `ops.py:809-815 new_buffer` is `UOp.new_buffer` above. The node is thedef; the
# host `Buffer` it would allocate is CPython's, and the port's `ParamArg.buffer` is a slot.
# TODO(p3) ops.py:817  def from_buffer
#   ops.py:821 -- both the storage identity and the dtype interpretation are
# TODO(p3) ops.py:823  def empty_like  -- BLOCKED, and opens `canonicalize_device(...)`.
# TODO(p3) ops.py:841  def clone  -- BLOCKED, and opens `canonicalize_device(...)` then tests `is_disk_device`.
# TODO(p3) ops.py:829  def _frompy
# DONE(p3) ops.py:902 def is_virtual -- `wk_is_virtual` in `weak.bend`, `no_dev` beside it.
#   the claim that no DEF in the port sets it was FALSE. measured 2026-10-30:
# TODO(p3) ops.py:895  def contiguous_view
# TODO(p3) ops.py:916  def contiguous_view_offset  -- BLOCKED, and is `None if (view := self.contiguous_view()) is None`.
# TODO(p3) ops.py:926  def _buffer_view  -- BLOCKED, and raises on `self.contiguous_view() is None`.
# TODO(p3) ops.py:950  def _base_buffer_is_realized  -- BLOCKED, and walks the AFTER chain then reads `u.base.realized`.
# TODO(p3) ops.py:957  def realized  -- BLOCKED, and ANSWERS a Buffer.
# TODO(p3) ops.py:968  def is_realized  -- BLOCKED, and is `self.base.realized is not None`.
# TODO(p3) ops.py:738  def needs_storage  -- BLOCKED, and is `not is_virtual and (storage_base.op is ALLOC or base.realized)`.
# TODO(p3) ops.py:932  def buffer
# PORTED -- `ops.py:1015 UOp.variable` is `UOp.variable` (this file), four `vrn_*`
# `is_variable` (ops.py:1020) is STILL BLOCKED and this does not change that: its
#   ops.py:1020  def is_variable
#     A four-of-five port is not a partial port, it is a WRONG ANSWER: it returns
#   ops.py:1025  def is_bound_var
#   ops.py:1032  def bind
#     the range table) and `uval.divides(self.arg.multiple_of)` (ops.py:1069, not
#   ops.py:1039  def unbound
#   ops.py:1043  def unbind
#   ops.py:1046  def unbind_all
#     `bsl.go`'s shape and readable; `substitute` (ops.py:506 symbol=UOp.substitute) is not ported, and
#   ops.py:1049  def variables
# AND `const_factor` IS DONE -- MEASURED 2026-11-08: `def UOp.const_factor(fuel, ar, i) ->
# DONE(p3) ops.py:1048 def const_factor -- `UOp.const_factor` above, FLATTENED: the def and
# DONE(p3) ops.py:1082 def pop_const -- `UOp.pop_const_val` / `UOp.pop_const_hits` above, with
# TODO(p3) ops.py:1032  def gcd
# TODO(p3) ops.py:1038  def divide_exact
# TODO(p3) ops.py:1049  def vmin
# TODO(p3) ops.py:1051  def vmax
# TODO(p3) ops.py:1106  def _min_max
# TODO(p3) ops.py:1124  def _sym_fxn
# TODO(p3) ops.py:1135  def sym_infer
# TODO(p3) ops.py:1139  def render
# TODO(p3) ops.py:1147  def render_uir  -- upstream's `pyrender` was DELETED before this pin.
# TODO(p3) ops.py:1188  def alloc  -- BLOCKED, and ends `ret.view_as(shape)`.
# TODO(p3) ops.py:1160  def alloc_like  -- BLOCKED, and delegates to `alloc`.
# TODO(p3) ops.py:1163  def placeholder  -- BLOCKED, and ends `view_as`.
# TODO(p3) ops.py:1173  def placeholder_like  -- BLOCKED, and delegates to `placeholder`.
# PORTED -- `ops.py:1224 UOp.set` is `UOp.set` (this file). The def, its fixture,
#   THE STALE ARENA. The first draft was
# done(p3) ops.py:1229 def param -- the shape-less arm only, and it is in `weak.bend`. the third
# TODO(p3) ops.py:1193  def param_like
# TODO(p3) ops.py:1201  def view_as
# custom_function -- ops.py:1258 upstream. `UOp(Ops.CUSTOM_FUNCTION, src=src,
# arg=CustomFunction(name, dtype))`. The pin's spelling was ops.py:1256 and took no
def gate_kernel_sink.of(op: Op, +arg: Arg) -> Bool:
  match op:
    case OpsLINEAR{}: False{}
    case OpsSINK{}: gate_kernel_sink.arg(arg)
    case _: True{}

def gate_kernel_sink(+ar: Arena, +x: U32) -> Bool:
  gate_kernel_sink.of(Arena.op(ar, x), Arena.arg(ar, x))

# THE TABLE IS IN `.agents/slop/tables/uop-ops-5125.md` -- THE INVENTORY: every ops.py def that is NOT yet a Bend def, with the reason.
def UOp.custom_function(+ar: Arena, name: String, +srcs: List<&2, U32>, dt: S.Dt) -> Found:
  UOp.new(ar, OpsCUSTOM_FUNCTION{}, srcs, ACustom{CustomFunction{name, dt}}, TNone{})

# TODO(p3) ops.py:1212  def call
# WALL(p3) ops.py:1274  def call_with_outputs -- BLOCKED. ENDS IN THE `alloc` CHAIN: the body binds output ALLOCs through `mint` below, and `mint`
# WALL(p3) ops.py:1280  def mint -- BLOCKED. CALLS `UOp.alloc` ("`buf = UOp.alloc(...)`"), and `alloc` ends in `ret.view_as(shape)`
# WALL(p3) ops.py:1298  def call_with_output -- BLOCKED. IS `UOp.call_with_outputs((self,), *srcs)`, one line over the marker above it, so it is
# wall(p3) ops.py:1299  def custom_kernel -- blocked. builds its placeholders with `UOp.placeholder_like`, and `placeholder_like` delegates to
# TODO(p3) ops.py:1277  def to_elf
# TODO(p3) ops.py:1284  def uopfunc
# done(p3) ops.py:1229 def param -- the shape-less arm only, and it is in `weak.bend`. the third
# WALL(p3) ops.py:1323  def outlined -- BLOCKED. PYTHON INTROSPECTION OF A CALLABLE: `inspect.signature(fn).bind(*args, kwargs)`,
# DONE(p3) ops.py:1352 def launch_dims -- `ProgramInfo.launch_dims` is
# IDENTITY on the port's launch sizes, because `sym_infer` (ops.py:95) is the
#   ops.py:1366  def vals
# I GOT THIS BLOCKER WRONG TWICE before landing it, and both errors were the same

def g_const() -> Found:
  UOp.const(Arena.empty(), CInt{H.i64_of_i32(3)})

def g_rng() -> Found:
  +c0 = UOp.const(Arena.empty(), CInt{H.i64_of_i32(1)})
  UOp.range_end(Found.ar(c0), Found.i(c0), [1], AXIS_DEVICE{})

def g_special() -> Found:
  +r = g_rng()
  UOp.special(Found.ar(r), Found.i(r), "g")

def g_cycle() -> Found:
  +sp = g_special()
  +r = g_rng()
  UOp.backedge(Found.ar(sp), Found.i(sp), Found.i(r), Found.i(sp))

def g_chain() -> Found:
  +c0 = UOp.const(Arena.empty(), CInt{H.i64_of_i32(0)})
  +r0 = UOp.range_end(Found.ar(c0), Found.i(c0), [0], AXIS_LOOP{})
  +a0 = UOp.alu(Found.ar(r0), OpsADD{}, [Found.i(r0), Found.i(c0)])
  UOp.range_end(Found.ar(a0), Found.i(a0), [0], AXIS_GLOBAL{})

def t_hashcons() -> Bool:
  +f = g_const()
  +again = UOp.const(Found.ar(f), CInt{H.i64_of_i32(3)})
  Bool.and(U32.is_eq(Found.i(f), Found.i(again)),
    U32.is_eq(Arena.next(Found.ar(again)), U32.add(Found.i(f), 1)))

def t_dtype_key() -> Bool:
  +f = g_const()
  +b = UOp.const(Found.ar(f), CBool{True{}})
  Bool.not(U32.is_eq(Found.i(f), Found.i(b)))

def t_float_zeros_differ() -> Bool:
  +f = UOp.const(Arena.empty(), CFloat{0.0})
  +g = UOp.const(Found.ar(f), CFloat{F32.neg(0.0)})
  Bool.not(U32.is_eq(Found.i(f), Found.i(g)))

def t_float_nan_interns() -> Bool:
  +nan: F32 = F32.div(0.0, 0.0)
  +f = UOp.const(Arena.empty(), CFloat{nan})
  +g = UOp.const(Found.ar(f), CFloat{nan})
  U32.is_eq(Found.i(f), Found.i(g))

def t_cycle() -> Bool:
  +f = g_cycle()
  +ar = Found.ar(f)
  +sp = g_special()
  +s = Found.i(sp)
  +be = Found.i(f)
  Bool.and(Bool.and(Bool.and(U32.is_eq(Arena.src0(ar, be), s), U32.is_eq(Arena.src(ar, be, 1), Found.i(g_rng()))),
    eq_op(Arena.op(ar, s), OpsSPECIAL{})), eq_op(Arena.op(ar, Arena.src(ar, be, 1)), OpsRANGE{}))

# ops.py:621 `UOp.after` builds `src=(self,)+src`, so SELF IS src[0]. This row exists
# builds OpsRANGE, ops.py:660) and the supplied node is a CONST, so self-first means
def t_after_puts_self_first() -> Bool:
  +c = UOp.const(Arena.empty(), CInt{H.i64_of_i32(0)})
  +e = UOp.range_end(Found.ar(c), Found.i(c), [0], AXIS_GLOBAL{})
  +a = UOp.after(Found.ar(e), Found.i(e), [Found.i(c)])
  +ar = Found.ar(a)
  Bool.and(op_is(ar, Found.i(a), OpsAFTER{}),
  Bool.and(op_is(ar, Arena.src(ar, Found.i(a), 0), OpsRANGE{}),
           op_is(ar, Arena.src(ar, Found.i(a), 1), OpsCONST{})))

# the same for `UOp.end` (ops.py:619): self first, supplied node second.
def t_end_puts_self_first() -> Bool:
  +c = UOp.const(Arena.empty(), CInt{H.i64_of_i32(0)})
  +e = UOp.range_end(Found.ar(c), Found.i(c), [0], AXIS_GLOBAL{})
  +e2 = UOp.end(Found.ar(e), Found.i(e), [Found.i(c)])
  +ar = Found.ar(e2)
  Bool.and(op_is(ar, Found.i(e2), OpsEND{}),
  Bool.and(op_is(ar, Arena.src(ar, Found.i(e2), 0), OpsRANGE{}),
           op_is(ar, Arena.src(ar, Found.i(e2), 1), OpsCONST{})))

def t_toposort() -> Bool:
  +f = g_chain()
  +ar = Found.ar(f)
  o = UOp.toposort(Arena.budget(ar), ar, Found.i(f))
  Nat.is_eq(List.length(&2, U32, o), 4n)

def t_cycle_terminates() -> Bool:
  +f = g_cycle()
  +o = UOp.toposort(64n, Found.ar(f), Found.i(f))
  Bool.and(Bool.not(Nat.is_eq(List.length(&2, U32, o), 0n)), Nat.is_le(List.length(&2, U32, o), 8n))

def key_same(p: Node, q: Node) -> Bool: eq_node(p, q)

def t_key_eq() -> Bool:
  Bool.and(Bool.and(key_same(Node{OpsADD{}, [1, 2], ANone{}, TNone{}}, Node{OpsADD{}, [1, 2], ANone{}, TNone{}}),
    Bool.not(key_same(Node{OpsADD{}, [1, 2], ANone{}, TNone{}}, Node{OpsADD{}, [1, 3], ANone{}, TNone{}}))),
    Bool.not(key_same(Node{OpsADD{}, [1, 2], ANone{}, TNone{}}, Node{OpsADD{}, [1, 2], ANone{}, TStr{"t"}})))

# dtype.py:59-62 is the oracle and it is an IDENTITY: `DType` is
def t_eq_dt() -> Bool:
  Bool.and(Bool.and(eq_dt(S.void(), S.void()), eq_dt(S.weakint(), S.weakint())),
    Bool.and(Bool.and(eq_dt(S.boolean(), S.boolean()), eq_dt(S.uint32(), S.uint32())),
    Bool.and(Bool.and(eq_dt(S.int32(), S.int32()), eq_dt(S.half(), S.half())),
    Bool.and(eq_dt(S.single(), S.single()), eq_dt(S.weakfloat(), S.weakfloat())))))

def t_eq_dt_disjoint() -> Bool:
  Bool.and(Bool.and(Bool.not(eq_dt(S.weakfloat(), S.half())), Bool.not(eq_dt(S.half(), S.weakfloat()))),
    Bool.and(Bool.and(Bool.not(eq_dt(S.weakfloat(), S.weakint())), Bool.not(eq_dt(S.weakint(), S.weakfloat()))),
    Bool.and(Bool.not(eq_dt(S.half(), S.bfloat16())), Bool.not(eq_dt(S.void(), S.weakfloat())))))

def g_cast_twice(+dt: S.Dt) -> U32:
  +c = UOp.const(Arena.empty(), CInt{H.i64_of_i32(0)})
  +ar = Found.ar(c)
  +a = UOp.new(ar, OpsCAST{}, [Found.i(c)], ADt{dt}, TNone{})
  +b = UOp.new(Found.ar(a), OpsCAST{}, [Found.i(c)], ADt{dt}, TNone{})
  Arena.next(Found.ar(b))

def t_weakfloat_interns() -> Bool:
  Bool.and(U32.is_eq(g_cast_twice(S.weakfloat()), 3), U32.is_eq(g_cast_twice(S.half()), 3))

# dtype.py:51-54's `AddrSpace` is an `IntEnum` with four members and no
def t_eq_addr() -> Bool:
  Bool.and(Bool.and(Bool.and(Bool.and(eq_addr(S.AGlobal{}, S.AGlobal{}), Bool.not(eq_addr(S.AGlobal{}, S.ALocal{}))), Bool.and(Bool.not(eq_addr(S.AGlobal{}, S.AReg{})), Bool.not(eq_addr(S.AGlobal{}, S.Aalu{})))), Bool.and(Bool.and(Bool.not(eq_addr(S.ALocal{}, S.AGlobal{})), eq_addr(S.ALocal{}, S.ALocal{})), Bool.and(Bool.not(eq_addr(S.ALocal{}, S.AReg{})), Bool.not(eq_addr(S.ALocal{}, S.Aalu{}))))),
    Bool.and(Bool.and(Bool.and(Bool.not(eq_addr(S.AReg{}, S.AGlobal{})), Bool.not(eq_addr(S.AReg{}, S.ALocal{}))), Bool.and(eq_addr(S.AReg{}, S.AReg{}), Bool.not(eq_addr(S.AReg{}, S.Aalu{})))), Bool.and(Bool.and(Bool.not(eq_addr(S.Aalu{}, S.AGlobal{})), Bool.not(eq_addr(S.Aalu{}, S.ALocal{}))), Bool.and(Bool.not(eq_addr(S.Aalu{}, S.AReg{})), eq_addr(S.Aalu{}, S.Aalu{})))))

# `ParamArg.addrspace` is the seventh field and is a BARE `S.Addr` (ops.py:23-36
def g_param_addr(slot: U32, as: S.Addr) -> ParamArg:
  ParamArg{slot, S.uint32(), None{}, None{}, None{}, as, None{}, False{}, None{}, None{}, False{}, None{}}

def g_param_twice(+p1: ParamArg, +p2: ParamArg) -> U32:
  +c = UOp.const(Arena.empty(), CInt{H.i64_of_i32(0)})
  +ar = Found.ar(c)
  +a = UOp.new(ar, OpsPARAM{}, [Found.i(c)], AParam{p1}, TNone{})
  +b = UOp.new(Found.ar(a), OpsPARAM{}, [Found.i(c)], AParam{p2}, TNone{})
  Arena.next(Found.ar(b))

def t_addr_interns() -> Bool:
  Bool.and(U32.is_eq(g_param_twice(g_param_addr(0, S.Aalu{}), g_param_addr(0, S.Aalu{})), 3),
    U32.is_eq(g_param_twice(g_param_addr(0, S.Aalu{}), g_param_addr(0, S.AReg{})), 4))

def t_ops_name() -> Bool:
  Bool.and(Bool.and(String.eq(Ops.name(OpsSPECIAL{}), "Ops.SPECIAL"), String.eq(Ops.name(OpsADD{}), "Ops.ADD")),
    Bool.and(Bool.and(String.eq(Ops.name(OpsREDUCE{}), "Ops.REDUCE"), String.eq(Ops.name(OpsPYLITERAL{}), "Ops.PYLITERAL")),
      Bool.and(String.eq(Ops.name.of(OpsADD{}), "ADD"), String.eq(Ops.name.of(OpsCUSTOM_FUNCTION{}), "CUSTOM_FUNCTION"))))

def pat_base.of(f: PatFound) -> Pat:
  PatFound.pat(f)

def pat_base() -> Pat:
  pat_base.of(UPat.var(Pat{[]}, Some{"x"}, None{}))

def t_var_interns.y(+x1: PatFound, +x2: PatFound, y1: PatFound) -> Bool:
  Bool.and(U32.is_eq(PatFound.i(x1), PatFound.i(x2)),
           Bool.not(U32.is_eq(PatFound.i(x2), PatFound.i(y1))))

def t_var_interns.go(+x1: PatFound, +x2: PatFound) -> Bool:
  t_var_interns.y(x1, x2, UPat.var(PatFound.pat(x2), Some{"y"}, None{}))

def t_var_interns.of(+x1: PatFound) -> Bool:
  t_var_interns.go(x1, UPat.var(PatFound.pat(x1), Some{"x"}, None{}))

def t_var_interns() -> Bool:
  t_var_interns.of(UPat.var(Pat{[]}, Some{"x"}, None{}))

def t_broadcast_repeats.of(alts: List<&2, UpAlt>) -> Bool:
  match alts:
    case Nil{}: False{}
    case UpRepeat{x} <> _: U32.is_eq(x, 0)
    case UpFixed{_} <> _: False{}
def pat_nth.of(hit: Maybe<&2, UPat>) -> UPat:
  match hit:
    case Some{u}: u
    case None{}: UPat{None{}, None{}, None{}, None{}, SNone{}, Nil{}, False{}, False{}, 0, Nil{}}

def pat_nth(+f: PatFound, n: U32) -> UPat:
  pat_nth.of(List.get(&2, UPat, Pat.upats(PatFound.pat(f)), U32.to_nat(n)))

def t_broadcast_repeats.go(+f: PatFound) -> Bool:
  t_broadcast_repeats.of(UPat.src(pat_nth(f, PatFound.i(f))))

def t_broadcast_repeats() -> Bool:
  t_broadcast_repeats.go(UPat.broadcast(pat_base(), 0))

def t_required_len.of(rep: UPat, tup: UPat) -> Bool:
  Bool.and(U32.is_eq(UPat.required_len(rep), 0), U32.is_eq(UPat.required_len(tup), 1))

def t_required_len() -> Bool:
  t_required_len.of(pat_nth(UPat.broadcast(pat_base(), 0), 1),
                    pat_nth(UPat.f(pat_base(), 0, OpsADD{}), 1))

def n_alts_of(alts: List<&2, UpAlt>) -> U32:
  match alts:
    case Nil{}: 0
    case _ <> t: U32.add(1, n_alts_of(t))
def t_alu_permutes.n(+f: PatFound, want: U32) -> Bool:
  U32.is_eq(n_alts_of(UPat.src(pat_nth(f, PatFound.i(f)))), want)

def t_alu_permutes.of(+comm: PatFound, +plain: PatFound) -> Bool:
  Bool.and(t_alu_permutes.n(comm, 2), t_alu_permutes.n(plain, 1))

def t_alu_permutes() -> Bool:
  t_alu_permutes.of(UPat.alu(pat_base(), 0, OpsADD{}, 1),
                    UPat.alu(pat_base(), 0, OpsCAST{}, 1))

def t_early_reject.of(ers: List<&2, Op>) -> Bool:
  U32.is_eq(U32.from_nat(List.length(&2, Op, ers)), 1)

def pat_base_op.of(f: PatFound) -> Pat:
  PatFound.pat(f)

def pat_base_op() -> Pat:
  pat_base_op.of(UPat.cvar(Pat{[]}, Some{"c"}, None{}, None{}))

def t_early_reject() -> Bool:
  t_early_reject.of(UPat.early_reject(pat_nth(UPat.f(pat_base_op(), 0, OpsADD{}), 1)))

# matters, because spec.py:201's reject set is four ops and the broken version
def g_ler.put(+leaf: Arena, four: Arena) -> Found:
  Found{four, 1}

def g_ler() -> Found:
  g_ler.put(UOp.make(Arena.empty(), OpsCONST{}, Nil{}, ANone{}, TNone{}),
            UOp.make(UOp.make(Arena.empty(), OpsCONST{}, Nil{}, ANone{}, TNone{}),
              OpsADD{}, [0, 0, 0, 0], ANone{}, TNone{}))
def t_ler_len.go(have: List<&2, Op>, want: U32) -> Bool:
  U32.is_eq(U32.from_nat(List.length(&2, Op, have)), want)

def t_ler_len.of(+f: Found) -> Bool:
  t_ler_len.go(pm_ler(Found.ar(f), Found.i(f)), Arena.nsrc(Found.ar(f), Found.i(f)))

def t_ler_len() -> Bool:
  t_ler_len.of(g_ler())

def Rng.srcops.go(+ar: Arena, xs: List<&2, U32>, +acc: String, +first: Bool) -> String:
  match xs:
    case Nil{}: acc
    case +h <> t:
      Rng.srcops.go(ar, t, Bool.pick(String, first, acc ++ Ops.name(Arena.op(ar, h)),
        acc ++ " " ++ Ops.name(Arena.op(ar, h))), False{})

# `+first` starts FALSE and not TRUE, because `seeded` has ALREADY put the head's name
def Rng.srcops.seeded(+ar: Arena, xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}: "-"
    case +h <> t: Rng.srcops.go(ar, t, Ops.name(Arena.op(ar, h)), False{})

def Rng.srcops(+ar: Arena, self: U32) -> String:
  Rng.srcops.seeded(ar, Arena.srcs(ar, self))

def Rng.sig(+ar: Arena, +self: U32) -> String:
  String.concat([
    Nat.show(List.length(&2, U32, UOp.toposort(Arena.budget(ar), ar, self))), " ",
    Ops.name(Arena.op(ar, self)), "/", U32.show(Arena.nsrc(ar, self)), " ",
    Rng.srcops(ar, self)])

def row(nm: String, b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(b)]))

def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

def dt_name(d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, nm}: nm

# blob -- the intern key's bytes half. ops.py:201, spec.py:96, ops.py:365.
# so `eq_arg.ABlob` compared a summary. Two DIFFERENT blobs of the SAME length were
# `b"bbbb"` -- EQUAL LENGTH, UNEQUAL CONTENT. A fixture of DIFFERENT lengths is
def t_const_bool_vs_int_splits() -> Bool:
  +u = UOp.new(Arena.empty(), OpsCONST{}, Nil{}, APy{CBool{True{}}}, TNone{})
  +v = UOp.new(Found.ar(u), OpsCONST{}, Nil{}, APy{CInt{H.i64_of_i32(1)}}, TNone{})
  Bool.not(U32.is_eq(Found.i(u), Found.i(v)))

# `ParamArg.val` is a `PyConst` NESTED inside `arg` (ops.py:42, `PyConst = float|int|bool`
# at dtype.py:38), `type(arg)` is `ParamArg` on both sides, and the same two values are ONE
def pa_with(v: Maybe<&2, Const>) -> Arg:
  AParam{ParamArg{0, S.int32(), None{}, None{}, None{}, S.AGlobal{}, None{}, False{}, None{},
                  None{}, False{}, v}}

def pynest_same(v1: Maybe<&2, Const>, v2: Maybe<&2, Const>) -> Bool:
  +u = UOp.new(Arena.empty(), OpsPARAM{}, Nil{}, pa_with(v1), TNone{})
  +v = UOp.new(Found.ar(u), OpsPARAM{}, Nil{}, pa_with(v2), TNone{})
  U32.is_eq(Found.i(u), Found.i(v))

def t_pynest_bool_vs_int_interns() -> Bool: pynest_same(Some{CBool{True{}}}, Some{CInt{H.i64_of_i32(1)}})

def t_pynest_int_distinct_interns() -> Bool: pynest_same(Some{CInt{H.i64_of_i32(1)}}, Some{CInt{H.i64_of_i32(2)}})

def t_pynest_none_vs_zero_interns() -> Bool: pynest_same(None{}, Some{CInt{H.i64_of_i32(0)}})

# `ConstFloat.__hash__` is `hash(self.bits)` (dtype.py:21) and
# DIFFERENT dict buckets upstream and are never compared at all. This row reads FALSE and
def t_pynest_cfloat_vs_int_interns() -> Bool:
  pynest_same(Some{CFloat{1.0}}, Some{CInt{H.i64_of_i32(1)}})

def t_pynest_signed_zero_interns() -> Bool:
  pynest_same(Some{CFloat{F32.neg(0.0)}}, Some{CFloat{0.0}})


def ax_names_str.go(xs: List<&2, AxisType>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case a <> t: List.append(&2, String, [AxisType.name(a)], ax_names_str.go(t))

# THE GATE for the ops.py:501-1928 block above. The CPython lane is

def s5.pa(slot: U32) -> ParamArg: ParamArg.of(slot, S.int32())

type S5 is Data: S5{c: U32, b: U32, p: U32, a: U32, r1: U32, r2: U32, us: U32, bc: U32, af: U32}

def S5.c(f: S5) -> U32:
  match f:
    case S5{c, b, p, a, r1, r2, us, bc, af}: c

def S5.b(f: S5) -> U32:
  match f:
    case S5{c, b, p, a, r1, r2, us, bc, af}: b

def S5.p(f: S5) -> U32:
  match f:
    case S5{c, b, p, a, r1, r2, us, bc, af}: p

def S5.a(f: S5) -> U32:
  match f:
    case S5{c, b, p, a, r1, r2, us, bc, af}: a

def S5.r1(f: S5) -> U32:
  match f:
    case S5{c, b, p, a, r1, r2, us, bc, af}: r1

def S5.r2(f: S5) -> U32:
  match f:
    case S5{c, b, p, a, r1, r2, us, bc, af}: r2

def S5.us(f: S5) -> U32:
  match f:
    case S5{c, b, p, a, r1, r2, us, bc, af}: us

def S5.bc(f: S5) -> U32:
  match f:
    case S5{c, b, p, a, r1, r2, us, bc, af}: bc

def S5.af(f: S5) -> U32:
  match f:
    case S5{c, b, p, a, r1, r2, us, bc, af}: af

def s5.name(ar: Arena, i: U32) -> String: Ops.name(Arena.op(ar, i))

def s5.seps.go(+ar: Arena, xs: List<&2, U32>, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case +h <> t: s5.seps.go(ar, t, String.concat([acc, " ", s5.name(ar, h)]))

def s5.seps(+ar: Arena, xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}: ""
    case +h <> t: s5.seps.go(ar, t, s5.name(ar, h))

def s5.minted.of.go(+ar: Arena, +f: Found, srcs: List<&2, U32>) -> String:
  match srcs:
    case Nil{}: Ops.name(Arena.op(ar, Found.i(f)))
    case _ <> _: String.concat([Ops.name(Arena.op(ar, Found.i(f))), "/", s5.seps(ar, srcs)])

def s5.minted.of(+ar: Arena, +f: Found) -> String:
  s5.minted.of.go(ar, f, Arena.srcs(ar, Found.i(f)))

def s5.minted.go(ar: Arena, f: Found) -> String: s5.minted.of(ar, f)

type DRng is Data: DRng{ar: Arena, ys: List<&2, U32>}

def DRng.ar(+d: DRng) -> Arena:
  match d:
    case DRng{ar, ys}: ar

def DRng.ys(+d: DRng) -> List<&2, U32>:
  match d:
    case DRng{ar, ys}: ys

def DRng.of(+f: Found) -> DRng: DRng{Found.ar(f), [Found.i(f)]}

def s5.d1(k: U32) -> S.Dev: S.D1{k}

def s5.dn(n: U32) -> S.Dev: S.Dn{UOp.replicate(1, n)}

def s5.ga.arena() -> Arena:
  Arena{[
    Arena.bottom(),
    Node{OpsBUFFER{}, Nil{}, AParam{s5.pa(1)}, TNone{}},
    Node{OpsALLOC{}, Nil{}, AParam{s5.pa(2)}, TNone{}},
    Node{OpsPARAM{}, Nil{}, AParam{s5.pa(3)}, TNone{}},
    Node{OpsSHRINK{}, [1], ATuple{Nil{}}, TNone{}},
    Node{OpsBITCAST{}, [1], ADt{S.single()}, TNone{}},
    Node{OpsBINARY{}, [1], ANone{}, TNone{}},
    Node{OpsMSTACK{}, [1], ANone{}, TNone{}},
    Node{OpsMSELECT{}, [1, 2], AInt{0}, TNone{}},
    Node{OpsLINEAR{}, [1], ANone{}, TNone{}},
    Node{OpsCONST{}, Nil{}, APy{CInt{H.i64_of_i32(3)}}, TNone{}},
    Node{OpsRESHAPE{}, [1, 14], ATuple{[0]}, TNone{}},
    Node{OpsAFTER{}, [1], ANone{}, TNone{}},
    Node{OpsADD{}, [1, 1], ANone{}, TNone{}},
    Node{OpsSTACK{}, [10, 10], ANone{}, TNone{}}
  ], [0]}

type CLike is Data:
  CU{u: U32}
  CV{v: Const}

# `is_invalid` -- ops.py:267. `self.op is Ops.CONST and self.val is Invalid`. It is
def UOp.is_invalid.of(op: Op, arg: Arg) -> Bool:
  match op arg:
    case OpsCONST{} APy{CInvalid{}}: True{}
    case _ _: False{}

def UOp.is_invalid(+ar: Arena, +self: U32) -> Bool:
  UOp.is_invalid.of(Arena.op(ar, self), Arena.arg(ar, self))

# `invalid` -- ops.py:663. `UOp.const(Invalid)`: a CONST whose `APy` payload is the
def UOp.invalid(ar: Arena) -> Found:
  UOp.const(ar, CInvalid{})

# `reduce` -- ops.py:671. `arg = kwargs.pop('arg', None); if isinstance(arg, Ops):
def UOp.reduce.arg(rop: Maybe<&2, Op>) -> Arg:
  match rop:
    case Some{r}: AReduce{r, 0}
    case None{}: ANone{}

def UOp.reduce(ar: Arena, self: U32, srcs: List<&2, U32>, rop: Maybe<&2, Op>) -> Found:
  UOp.new(ar, OpsREDUCE{}, List.append(&2, U32, [self], srcs), UOp.reduce.arg(rop), TNone{})

# `cconst` -- ops.py:640. `UOp(Ops.CAST, src=(UOp.const(b),), arg=dtype)`. A FORCED
def UOp.cconst(+ar: Arena, v: Const, dt: S.Dt) -> Found:
  +c = UOp.const(ar, v)
  UOp.new(Found.ar(c), OpsCAST{}, [Found.i(c)], ADt{dt}, TNone{})

# `ssimplify` -- ops.py:92. TWO ARMS AND A CAST:
# a convenience. `simplify` is a documented wall in this file (`ops.py:511`, "* uop evaluation
def cval_arg(a: Arg) -> Maybe<&1, Const>:
  match a:
    case APy{CBool{b}}: Some{CBool{b}}
    case APy{CInt{i}}: Some{CInt{i}}
    case APy{CFloat{f}}: Some{CFloat{f}}
    case _: None{}

def ssimplify_of(op: Op, +ar: Arena, +i: U32) -> Maybe<&1, Const>:
  match op:
    case OpsCONST{}: cval_arg(Arena.arg(ar, i))
    case OpsCAST{}: cval_arg(Arena.arg(ar, Arena.src0(ar, i)))
    case _: None{}

def UOp.ssimplify_val(+ar: Arena, +i: U32) -> Maybe<&1, Const>:
  ssimplify_of(Arena.op(ar, i), ar, i)

def UOp.ssimplify_is_val(+ar: Arena, +i: U32) -> Bool:
  Bool.or(eq_op(Arena.op(ar, i), OpsCONST{}),
          Bool.and(eq_op(Arena.op(ar, i), OpsCAST{}),
                   eq_op(Arena.op(ar, Arena.src0(ar, i)), OpsCONST{})))

def UOp.pop_const_val(+ar: Arena, +i: U32, op: Op) -> Maybe<&1, Const>:
  Bool.pick(Maybe<&1, Const>,
            Bool.and(eq_op(Arena.op(ar, i), op),
                     eq_op(Arena.op(ar, Arena.src(ar, i, 1)), OpsCONST{})),
            cval_arg(Arena.arg(ar, Arena.src(ar, i, 1))),
            None{})

def UOp.pop_const_hits(+ar: Arena, +i: U32, op: Op) -> Bool:
  Bool.and(eq_op(Arena.op(ar, i), op),
           eq_op(Arena.op(ar, Arena.src(ar, i, 1)), OpsCONST{}))

# `UOp.const_factor` -- ops.py:1048, "largest known int that divides self".
# recursive. that is TRUE of the obvious spelling and FALSE of the arms: a stack or ADD node's
def cf.cv.c(c: Const) -> H.I64:
  match c:
    case CInt{i}: i
    case _       : H.i64_of_i32(1)

def cf.cv(m: Maybe<&1, Const>) -> H.I64:
  match m:
    case Some{+c}: cf.cv.c(c)
    case None{}  : H.i64_of_i32(1)

def cf.mul.val(+ar: Arena, i: U32, k: U32) -> H.I64:
  cf.cv(cval_arg(Arena.arg(ar, Arena.src(ar, i, k))))

def cf.mul.b(c1: Bool, +ar: Arena, i: U32) -> H.I64:
  match c1:
    case True{} : cf.mul.val(ar, i, 1)
    case False{}: H.i64_of_i32(1)

def cf.mul.a(c0: Bool, +ar: Arena, +i: U32, c1: Bool) -> H.I64:
  match c0:
    case True{} : cf.mul.val(ar, i, 0)
    case False{}: cf.mul.b(c1, ar, i)

def cf.mul(+ar: Arena, +i: U32) -> H.I64:
  cf.mul.a(eq_op(Arena.op(ar, Arena.src(ar, i, 0)), OpsCONST{}), ar, i,
           eq_op(Arena.op(ar, Arena.src(ar, i, 1)), OpsCONST{}))

def cf.defs(arg: Arg) -> H.I64:
  match arg:
    case AParam{pa}: H.i64_of_i32(Maybe.default(&2, U32, ParamArg.multiple_of(pa), 1))
    case _: H.i64_of_i32(1)

def cf.defs.op(+ar: Arena, +i: U32, d: Bool) -> H.I64:
  match d:
    case True{} : cf.defs(Arena.arg(ar, i))
    case False{}: H.i64_of_i32(1)

# `gcd(1, x)` is 1. MEASURED on the probe: `add_m6_m4` answered 1 for want of this arm, and 2 is
def cf.local.go(op: Op, arg: Arg, +ar: Arena, +i: U32) -> H.I64:
  match op:
    case OpsCONST{}: cf.cv(cval_arg(arg))
    case OpsMUL{}  : cf.mul(ar, i)
    case OpsSTACK{}: H.i64_of_i32(0)
    case OpsADD{}  : H.i64_of_i32(0)
    case _         : cf.defs.op(ar, i, GroupOp.defines(op))

def cf.local(+ar: Arena, +i: U32) -> H.I64:
  cf.local.go(Arena.op(ar, i), Arena.arg(ar, i), ar, i)

def cf.keep(op: Op) -> Bool:
  match op:
    case OpsSTACK{}: True{}
    case OpsADD{}  : True{}
    case _         : False{}

def cf.next(nxt: Bool, +rest: List<&2, U32>, +ar: Arena, +h: U32) -> List<&2, U32>:
  match nxt:
    case True{} : List.concat(&2, U32, [Arena.srcs(ar, h), rest])
    case False{}: rest

def cf.walk(fuel: Nat, +ar: Arena, todo: List<&2, U32>, out: List<&2, U32>) -> List<&2, U32>:
  match fuel todo:
    case 0n Nil{}: out
    case 1n+p Nil{}: out
    case 0n +h <> rest: out
    case 1n+p +h <> rest:
      cf.walk(p, ar, cf.next(cf.keep(Arena.op(ar, h)), rest, ar, h), List.append(&2, U32, out, [h]))
# ops.py:1073-1079 -- `UOp.gcd` and `UOp.divide_exact`.
# (`ops.py:219-220`: `__hash__ = tuple.__hash__` AND `__eq__` IS `self is other`). SO THE
#    CONVENTION AND NOT A NEW ONE.

def cf.sum(ns: List<&2, U32>, +ar: Arena, acc: H.I64) -> H.I64:
  match ns:
    case Nil{}: acc
    case n <> rest: cf.sum(rest, ar, H.gcd(acc, cf.local(ar, n)))

def cf.top(keep: Bool, fuel: Nat, +ar: Arena, i: U32) -> H.I64:
  match keep:
    case True{} : cf.sum(cf.walk(fuel, ar, [i], Nil{}), ar, H.i64_of_i32(0))
    case False{}: cf.local(ar, i)

def UOp.const_factor(fuel: Nat, +ar: Arena, +i: U32) -> H.I64:
  cf.top(cf.keep(Arena.op(ar, i)), fuel, ar, i)

# THE TABLE IS IN `.agents/slop/tables/uop-ops-6592.md` -- the counter -- `collections.Counter` over node lists, as a list of pairs.
type Ctr is Data:
  Ctr{k: U32, n: U32}

def Ctr.k(+c: Ctr) -> U32:
  match c:
    case Ctr{k, n}: k

def Ctr.n(+c: Ctr) -> U32:
  match c:
    case Ctr{k, n}: n

def ctr_find.pick(+same: Bool, +hit: U32, +acc: U32) -> U32:
  match same:
    case True{}: hit
    case False{}: acc

def ctr_find.hit(+c: Ctr, +k: U32, +acc: U32) -> U32:
  match c:
    case Ctr{k2, n2}: ctr_find.pick(U32.is_eq(k2, k), n2, acc)

def ctr_find.go(+l: List<&2, Ctr>, +k: U32, +acc: U32) -> U32:
  match l:
    case Nil{}: acc
    case c <> t: ctr_find.go(t, k, ctr_find.hit(c, k, acc))

def ctr_bump.same(+c: Ctr, +k: U32) -> Bool:
  match c:
    case Ctr{k2, n2}: U32.is_eq(k2, k)

def ctr_bump.hit2(+c: Ctr, +k: U32, +acc: List<&2, Ctr>) -> List<&2, Ctr>:
  match c:
    case Ctr{k2, n2}: List.append(&2, Ctr, acc, [Ctr{k2, U32.add(n2, 1)}])

def ctr_bump.found2(+same: Bool, +found: Bool) -> Bool:
  match same:
    case True{}: True{}
    case False{}: found

def ctr_bump.found(+c: Ctr, +k: U32, +found: Bool) -> Bool:
  ctr_bump.found2(ctr_bump.same(c, k), found)

def ctr_bump.pick(+same: Bool, +hit: List<&2, Ctr>, +miss: List<&2, Ctr>) -> List<&2, Ctr>:
  match same:
    case True{}: hit
    case False{}: miss

# NODES WERE COUNTED, AND `t_ctr_bump` READ `False`.
def ctr_bump.end(+found: Bool, +acc: List<&2, Ctr>, +k: U32) -> List<&2, Ctr>:
  ctr_bump.pick(found, acc, List.append(&2, Ctr, acc, [Ctr{k, 1}]))

def ctr_bump.hit(+c: Ctr, +k: U32, +acc: List<&2, Ctr>) -> List<&2, Ctr>:
  ctr_bump.pick(ctr_bump.same(c, k),
                ctr_bump.hit2(c, k, acc),
                List.append(&2, Ctr, acc, [c]))

def ctr_bump.go(+l: List<&2, Ctr>, +k: U32, +acc: List<&2, Ctr>, +found: Bool) -> List<&2, Ctr>:
  match l:
    case Nil{}: ctr_bump.end(found, acc, k)
    case c <> t: ctr_bump.go(t, k, ctr_bump.hit(c, k, acc), ctr_bump.found(c, k, found))

def ctr_bump(+l: List<&2, Ctr>, +k: U32, +acc: List<&2, Ctr>) -> List<&2, Ctr>: ctr_bump.go(l, k, acc, False{})

def ctr_of.go(+l: List<&2, U32>, +acc: List<&2, Ctr>) -> List<&2, Ctr>:
  match l:
    case Nil{}: acc
    case k <> t: ctr_of.go(t, ctr_bump(acc, k, Nil{}))

def ctr_of(+l: List<&2, U32>) -> List<&2, Ctr>: ctr_of.go(l, Nil{})

def ctr_find(+l: List<&2, Ctr>, +k: U32) -> U32: ctr_find.go(l, k, 0)

def ctr_min.pick(less: Bool, +m: U32, +n: U32) -> U32:
  match less:
    case True{}: m
    case False{}: n

def ctr_min(+m: U32, +n: U32) -> U32: ctr_min.pick(U32.is_lt(m, n), m, n)

def ctr_inter.min.hit4(+seen: Bool, +n: U32, +acc: U32) -> U32:
  match seen:
    case True{}: ctr_min(acc, n)
    case False{}: n

def ctr_inter.min.hit3(+missing: Bool, +n: U32, +acc: U32, +seen: Bool) -> U32:
  match missing:
    case True{}: 0
    case False{}: ctr_inter.min.hit4(seen, n, acc)

def ctr_inter.min.hit2(+n: U32, +k: U32, +acc: U32, +seen: Bool) -> U32:
  ctr_inter.min.hit3(U32.is_eq(n, 0), n, acc, seen)

def ctr_inter.min.hit(+l: List<&2, Ctr>, +k: U32, +acc: U32, +seen: Bool) -> U32:
  ctr_inter.min.hit2(ctr_find(l, k), k, acc, seen)

def ctr_inter.min.end(+seen: Bool, +acc: U32) -> U32:
  match seen:
    case True{}: acc
    case False{}: 0

def ctr_inter.min.go(+ls: List<&2, List<&2, Ctr>>, +k: U32, +acc: U32, +seen: Bool) -> U32:
  match ls:
    case Nil{}: ctr_inter.min.end(seen, acc)
    case l <> t: ctr_inter.min.go(t, k, ctr_inter.min.hit(l, k, acc, seen), True{})

def ctr_inter.add2(zero: Bool, +k: U32, +n: U32, +acc: List<&2, Ctr>) -> List<&2, Ctr>:
  match zero:
    case True{}: acc
    case False{}: List.append(&2, Ctr, acc, [Ctr{k, n}])

def ctr_inter.add(+k: U32, +n: U32, +acc: List<&2, Ctr>) -> List<&2, Ctr>:
  ctr_inter.add2(U32.is_eq(n, 0), k, n, acc)

def ctr_inter.put(+c: Ctr, +ls: List<&2, List<&2, Ctr>>, +acc: List<&2, Ctr>) -> List<&2, Ctr>:
  ctr_inter.add(Ctr.k(c), ctr_inter.min.go(ls, Ctr.k(c), 0, False{}), acc)

def ctr_inter.go(+first: List<&2, Ctr>, +ls: List<&2, List<&2, Ctr>>, +acc: List<&2, Ctr>) -> List<&2, Ctr>:
  match first:
    case Nil{}: acc
    case c <> t: ctr_inter.go(t, ls, ctr_inter.put(c, ls, acc))

# MEASURED 2026-11-08: "c (consumed more than once)".
def ctr_inter(+ls: List<&2, List<&2, Ctr>>) -> List<&2, Ctr>:
  match ls:
    case Nil{}: Nil{}
    case first <> t: ctr_inter.go(first, ls, Nil{})

#                  DISTINCT KEYS INSTEAD OF OCCURRENCES, which is the difference between a
def t_ctr_bump() -> Bool:
  +c = ctr_of([1, 2, 3, 2])
  Bool.and(U32.is_eq(ctr_find(c, 1), 1),
    Bool.and(U32.is_eq(ctr_find(c, 2), 2),
      U32.is_eq(ctr_find(c, 3), 1)))

def t_ctr_find() -> Bool:
  +c = ctr_of([7, 7, 9])
  Bool.and(U32.is_eq(ctr_find(c, 7), 2),
    Bool.and(U32.is_eq(ctr_find(c, 9), 1),
      U32.is_eq(ctr_find(c, 4), 0)))

def t_ctr_inter() -> Bool:
  +i = ctr_inter([ctr_of([1, 1, 2]), ctr_of([1, 2, 2])])
  Bool.and(U32.is_eq(ctr_find(i, 1), 1),
    Bool.and(U32.is_eq(ctr_find(i, 2), 1),
      U32.is_eq(ctr_find(i, 3), 0)))
# `UOp.divides` -- ops.py:1069, "self / v as the same shape, or None when it is not exact".
type Dv is Data:
  Dv{ok: Bool, f: Found, i: U32}

def Dv.ok(+d: Dv) -> Bool:
  match d:
    case Dv{ok, f, i}: ok

def Dv.f(+d: Dv) -> Found:
  match d:
    case Dv{ok, f, i}: f

def Dv.i(+d: Dv) -> U32:
  match d:
    case Dv{ok, f, i}: i

def dv.no(+f: Found) -> Dv: Dv{False{}, f, 0}

def dv.yes(+f: Found, +i: U32) -> Dv: Dv{True{}, f, i}

def dv.is1(+v: H.I64) -> Bool: Cmp.is_eq(H.i64_cmp(v, H.i64_of_i32(1)))

def dv.const2(+z: Bool, +f: Found, +val: H.I64, +v: H.I64) -> Dv:
  match z:
    case True{}:
      +c = UOp.const(Found.ar(f), CInt{H.i64_div(val, v)})
      dv.yes(c, Found.i(c))
    case False{}: dv.no(f)

def dv.add(ok: Bool, +da: Dv, +db: Dv) -> Dv:
  match ok:
    case True{}:
      +m = UOp.alu(Found.ar(Dv.f(db)), OpsADD{}, [Dv.i(da), Dv.i(db)])
      dv.yes(m, Found.i(m))
    case False{}: dv.no(Dv.f(db))

def dv.mul.b(ok1: Bool, +da: Dv, +db: Dv, +s0: U32) -> Dv:
  match ok1:
    case True{}:
      +m = UOp.alu(Found.ar(Dv.f(db)), OpsMUL{}, [s0, Dv.i(db)])
      dv.yes(m, Found.i(m))
    case False{}: dv.no(Dv.f(db))

def dv.mul.a(ok0: Bool, +da: Dv, +db: Dv, s0: U32, s1: U32) -> Dv:
  match ok0:
    case True{}:
      +m = UOp.alu(Found.ar(Dv.f(db)), OpsMUL{}, [Dv.i(da), s1])
      dv.yes(m, Found.i(m))
    case False{}: dv.mul.b(Dv.ok(db), da, db, s0)

def dv.defs3(z: Bool, +f: Found, +v: H.I64, +i: U32) -> Dv:
  match z:
    case True{}:
      +c = UOp.const(Found.ar(f), CInt{v})
      +q = UOp.alu(Found.ar(c), OpsDIV{}, [i, Found.i(c)])
      dv.yes(q, Found.i(q))
    case False{}: dv.no(f)

def dv.defs2(m: Maybe<&2, U32>, +f: Found, +v: H.I64, +i: U32) -> Dv:
  match m:
    case Some{k}: dv.defs3(H.i64_is_zero(H.i64_mod(H.i64_of_i32(k), v)), f, v, i)
    case None{}  : dv.no(f)

def dv.mo(arg: Arg) -> Maybe<&2, U32>:
  match arg:
    case AParam{pa}: ParamArg.multiple_of(pa)
    case _         : None{}

def dv.defs.op(+ar: Arena, +i: U32, d: Bool, +f: Found, +v: H.I64) -> Dv:
  match d:
    case True{} : dv.defs2(dv.mo(Arena.arg(ar, i)), f, v, i)
    case False{}: dv.no(f)

def dv.const1(+ar: Arena, +i: U32, +v: H.I64, +f: Found) -> Dv:
  +val = cf.cv(cval_arg(Arena.arg(ar, i)))
  dv.const2(H.i64_is_zero(H.i64_mod(val, v)), f, val, v)

def UOp.divides.op(+fuel: Nat, +op: Op, +ar: Arena, +v: H.I64, +i: U32) -> Dv:
  match fuel:
    case 0n: Dv{False{}, Found{ar, 0}, 0}
    case 1n++p:
      match op:
        case OpsCONST{}: dv.const1(ar, i, v, Dv.f(Dv{False{}, Found{ar, 0}, 0}))
        case OpsADD{}  :
          +da = UOp.divides.op(p, Arena.op(ar, Arena.src(ar, i, 0)), ar, v, Arena.src(ar, i, 0))
          +db = UOp.divides.op(p, Arena.op(ar, Arena.src(ar, i, 1)), Found.ar(Dv.f(da)), v, Arena.src(ar, i, 1))
          dv.add(Bool.and(Dv.ok(da), Dv.ok(db)), da, db)
        case OpsMUL{}  :
          +ma = UOp.divides.op(p, Arena.op(ar, Arena.src(ar, i, 0)), ar, v, Arena.src(ar, i, 0))
# `UOp.gcd` AND `UOp.divide_exact` -- ops.py:1073-1079.
# `UOp.gcd(*uops)` -- ops.py:1073:
#     (`ops.py:81`: `{Ops.ADD:0, Ops.MUL:1, Ops.MAX:dt.min}[op]`).
#   * `const_like` is not ported (`ops.py:581`, a bare `TODO(p3)` with no wall named),
          +mb = UOp.divides.op(p, Arena.op(ar, Arena.src(ar, i, 1)), Found.ar(Dv.f(ma)), v, Arena.src(ar, i, 1))
          dv.mul.a(Dv.ok(ma), ma, mb, Arena.src(ar, i, 0), Arena.src(ar, i, 1))
        case _         : dv.defs.op(ar, i, GroupOp.defines(op), Found{ar, 0}, v)

def UOp.divides.one(one: Bool, +fuel: Nat, +ar: Arena, +v: H.I64, +i: U32) -> Dv:
  match one:
    case True{} : Dv{True{}, Found{ar, i}, i}
    case False{}: UOp.divides.op(fuel, Arena.op(ar, i), ar, v, i)

def UOp.divides(fuel: Nat, +ar: Arena, +v: H.I64, +i: U32) -> Dv:
  UOp.divides.one(dv.is1(v), fuel, ar, v, i)

# `UOp.usum` -- mixin/elementwise.py:40.
#     `def usum(self, *uops) -> Self: return functools.reduce(operator.or_ if
#      self.dtype is dtypes.bool else operator.add, argfix(*uops), self)`
#
# AND IT LIVES HERE AND NOT IN `schedule/indexing.bend`, AND THE REASON IS THE
# IMPORT DIRECTION.  MEASURED 2026-11-24: `schedule/indexing.bend` IMPORTS
# `uop/ops.bend`, SO `uop/` CANNOT IMPORT `schedule/` -- AND `uop/divandmod.bend`
# NEEDS `usum` FOR THE `remove_nested_mod` ARM (`divandmod.py:33`).  SO IT IS
# HERE, WHERE BOTH CAN REACH IT, AND `schedule/indexing.bend`'s `rr_usum` IS
# THE SAME OPERATION AND IS REPLACED BY THIS.
#
# AND THE SHAPE IS A LIST AND NOT A VARARG, AND THE SEMANTICS ARE THE SAME:
# UPSTREAM'S `argfix(*uops)` UNWRAPS A SINGLE LIST ARGUMENT, SO `UOp.usum(a, b,
# c)` IS `reduce(add, (b, c), a)` -- THE FIRST IS THE RECEIVER AND THE REST ARE
# THE ARGUMENTS.  SO THE SUM IS OVER A LIST, LEFT-NESTED, AND AN EMPTY LIST IS
# THE IDENTITY `CONST 0` (`identity_element(Ops.ADD, dt)` IS `0`, ops.py:57).
#
# AND THE ASSOCIATION IS LEFT-NESTED BECAUSE UPSTREAM'S `reduce` IS, AND
# `schedule/indexing.bend`'s `rr_usum` IS **RIGHT**-NESTED (`x <> t => ADD(x,
# rr_usum(t))`) AND IS **NOT** CHANGED BY THIS.  THE REASON IS MEASURED: THE
# CORPUS COMPARES CANONICAL FORMS **BYTE-IDENTICALLY**, SO A DIFFERENT
# ASSOCIATION IN THE RESHAPE'S AXIS COMBINATION WOULD BE A CORPUS DIVERGENCE --
# AND THE DENOTATION IS THE SAME EITHER WAY, SO NOTHING WOULD BE WRONG AND THE
# BYTES WOULD DIFFER.  TWO CALL SITES, TWO MEASURED SHAPES, AND ONE OF THEM
# CHANGED.
def UOp.usum.pair(+f: Found, x: U32, +ar: Arena) -> Found:
  UOp.alu(Found.ar(f), OpsADD{}, [Found.i(f), x])

# AND THE FOLD IS LEFT-NESTED, AND `reduce(add, (b, c), a)` IS `((a+b)+c)`:
# SO THE ACCUMULATOR IS THE SUM SO FAR AND THE NEXT TERM IS ADDED **ON THE
# RIGHT** OF IT, AND THE LIST IS WALKED FROM THE FRONT.
def UOp.usum.go(xs: List<&2, U32>, +acc: Found, +ar: Arena) -> Found:
  match xs:
    case Nil{}: acc
    case x <> t: UOp.usum.go(t, UOp.usum.pair(acc, x, ar), ar)

def UOp.usum(+ar: Arena, +xs: List<&2, U32>) -> Found:
  match xs:
    case Nil{}: UOp.const(ar, CInt{H.i64_of_i32(0)})
    case x <> Nil{}: Found{ar, x}
    case x <> t: UOp.usum.go(t, Found{ar, x}, ar)

# THE TABLE IS IN `.agents/slop/tables/uop-ops-6972.md` -- `UOp.gcd` AND `UOp.divide_exact` -- ops.py:1073-1079.
def UOp.pop_const_node.isconst(+ar: Arena, +i: U32) -> Bool:
  eq_op(Arena.op(ar, Arena.src(ar, i, 1)), OpsCONST{})

def UOp.pop_const_node.ismul(+ar: Arena, +i: U32, +op: Op) -> Bool:
  eq_op(Arena.op(ar, i), op)

def UOp.pop_const_node.hit(+ar: Arena, +i: U32, +op: Op, +self: U32, isc: Bool) -> U32:
  match isc:
    case True{}: Arena.src(ar, i, 0)
    case False{}: self

def UOp.pop_const_node.hit2(+ar: Arena, +i: U32, +op: Op, +self: U32, ism: Bool) -> U32:
  match ism:
    case True{}: UOp.pop_const_node.hit(ar, i, op, self, UOp.pop_const_node.isconst(ar, i))
    case False{}: self

def UOp.pop_const_node.hit3(+ar: Arena, +i: U32, +op: Op, +self: U32, two: Bool) -> U32:
  match two:
    case True{}: UOp.pop_const_node.hit2(ar, i, op, self, UOp.pop_const_node.ismul(ar, i, op))
    case False{}: self

def UOp.pop_const_node(+ar: Arena, +i: U32, +op: Op) -> U32:
  UOp.pop_const_node.hit3(ar, i, op, i, U32.is_eq(Arena.nsrc(ar, i), 2))

def UOp.gcd.counter(+fuel: Nat, +ar: Arena, +i: U32) -> List<&2, Ctr>:
  ctr_of(UOp.split_uop(fuel, ar, i, OpsMUL{}))

def UOp.gcd.count.step(+ar: Arena, +h: U32, +acc: List<&2, List<&2, Ctr>>) -> List<&2, List<&2, Ctr>>:
  List.append(&2, List<&2, Ctr>, acc, [UOp.gcd.counter(Arena.budget(ar), ar, h)])

def UOp.gcd.count.go(+ar: Arena, +l: List<&2, U32>, +acc: List<&2, List<&2, Ctr>>) -> List<&2, List<&2, Ctr>>:
  match l:
    case Nil{}: acc
    case nh <> nt : UOp.gcd.count.go(ar, nt, UOp.gcd.count.step(ar, nh, acc))

def UOp.gcd.count(+ar: Arena, +uops: List<&2, U32>) -> List<&2, List<&2, Ctr>>:
  UOp.gcd.count.go(ar, uops, Nil{})

def UOp.gcd.terms.go(+ar: Arena, +uops: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match uops:
    case Nil{}: acc
    case h <> t: UOp.gcd.terms.go(ar, t, List.append(&2, U32, acc, [UOp.pop_const_node(ar, h, OpsMUL{})]))

def UOp.gcd.terms(+ar: Arena, +uops: List<&2, U32>) -> List<&2, U32>:
  UOp.gcd.terms.go(ar, uops, Nil{})

def UOp.gcd.isempty(+c: List<&2, Ctr>) -> Bool:
  match c:
    case Nil{}: True{}
    case _ <> _ : False{}

def UOp.gcd.cfactors.go(+fuel: Nat, +ar: Arena, +uops: List<&2, U32>, +acc: List<&2, H.I64>) -> List<&2, H.I64>:
  match uops:
    case Nil{}: acc
    case h <> t: UOp.gcd.cfactors.go(fuel, ar, t, List.append(&2, H.I64, acc, [UOp.const_factor(fuel, ar, h)]))

def UOp.gcd.cfactors(+fuel: Nat, +ar: Arena, +uops: List<&2, U32>) -> List<&2, H.I64>:
  UOp.gcd.cfactors.go(fuel, ar, uops, Nil{})

def UOp.gcd.gcd.go(+fs: List<&2, H.I64>, +acc: H.I64) -> H.I64:
  match fs:
    case Nil{}: acc
    case h <> t: UOp.gcd.gcd.go(t, H.gcd(acc, h))

def UOp.gcd.gcd(+fs: List<&2, H.I64>) -> H.I64:
  match fs:
    case Nil{}: H.i64_of_i32(1)
    case h <> t: UOp.gcd.gcd.go(t, h)

def UOp.gcd.prod.go(+c: List<&2, Ctr>, +acc: List<&2, U32>) -> List<&2, U32>:
  match c:
    case Nil{}: acc
    case x <> t: UOp.gcd.prod.go(t, List.concat(&2, U32, [acc, H.make_tuple_rep(Ctr.k(x), Ctr.n(x))]))

def UOp.gcd.prod(+c: List<&2, Ctr>) -> List<&2, U32>:
  UOp.gcd.prod.go(c, Nil{})

def UOp.gcd.const2(+ar: Arena, +uops: List<&2, U32>, g: H.I64) -> Found:
  match uops:
    case Nil{}: Found{ar, 0}
    case x <> _ : UOp.const(ar, CInt{g})

def UOp.gcd.const(+ar: Arena, +uops: List<&2, U32>) -> Found:
  UOp.gcd.const2(ar, uops, UOp.gcd.gcd(UOp.gcd.cfactors(Arena.budget(ar), ar, uops)))

def UOp.gcd.answer.mul2(+made: Found, +h: U32) -> Found:
  UOp.alu(Found.ar(made), OpsMUL{}, [Found.i(made), h])

# `UOp.divide_exact` -- ops.py:1038-1047.
# "WE AREN'T SURE" ANSWER AND NOT AN ERROR.
type Ds is Data:
  Ds{ok: Bool, es: List<&2, U32>}

def UOp.gcd.answer.mul(+es: List<&2, U32>, +made: Found) -> Found:
  match es:
    case Nil{}: made
    case h <> t: UOp.gcd.answer.mul(t, UOp.gcd.answer.mul2(made, h))

def Ds.ok(+d: Ds) -> Bool:
  match d:
    case Ds{ok, es}: ok

def Ds.es(+d: Ds) -> List<&2, U32>:
  match d:
    case Ds{ok, es}: es

# SINGLE CONSUMPTION -- MEASURED 2026-11-09: "expected : den / observed : den (consumed more
def UOp.divide_exact.ge1(+h: Ctr, +den: List<&2, Ctr>) -> Bool:
  Bool.not(U32.is_gt(ctr_find(den, Ctr.k(h)), Ctr.n(h)))

def UOp.divide_exact.diff(n: U32, +d: U32, gt: Bool) -> U32:
  match gt:
# MUST BE `Data` -- MEASURED 2026-11-08: "Note: +m can be used many times, so its type must be
# ANSWER TYPE AND NOT A NEW ONE.
    case True{}: 0
    case False{}: U32.sub(n, d)

# THE TABLE IS IN `.agents/slop/tables/uop-ops-7235.md` -- THE FOUR ARMS OF `divide_exact`, IN UPSTREAM's ORDER.
type Dq is Data:
  Dq{ok: Bool, f: Found}

def UOp.divide_exact.fold.elems(+h: Ctr, +den: List<&2, Ctr>) -> List<&2, U32>:
  H.make_tuple_rep(Ctr.k(h), UOp.divide_exact.diff(Ctr.n(h), ctr_find(den, Ctr.k(h)),
                                                  U32.is_gt(ctr_find(den, Ctr.k(h)), Ctr.n(h))))

def UOp.divide_exact.fold.add(+h: Ctr, +den: List<&2, Ctr>, +st: Ds) -> Ds:
  Ds{Bool.and(Ds.ok(st), UOp.divide_exact.ge1(h, den)),
     List.concat(&2, U32, [Ds.es(st), UOp.divide_exact.fold.elems(h, den)])}

def UOp.divide_exact.fold.go(+c: List<&2, Ctr>, +den: List<&2, Ctr>, +st: Ds) -> Ds:
  match c:
    case Nil{}: st
    case h <> t: UOp.divide_exact.fold.go(t, den, UOp.divide_exact.fold.add(h, den, st))

# AND THE **OTHER HALF** OF UPSTREAM's TEST, AND IT IS THE DENOMINATOR's SIDE:
# EVERY FACTOR OF THE DIVISOR MUST APPEAR IN THE NUMERATOR AT LEAST AS OFTEN,
# BECAUSE `Counter(num) - Counter(den)` GIVES A **NEGATIVE** COUNT FOR A
# FACTOR THAT IS IN THE DIVISOR AND NOT IN THE NUMERATOR AND UPSTREAM's TEST
# IS `all(v>=0 ...)` (ops.py:1046).
def UOp.divide_exact.den.ok(+h: Ctr, +num: List<&2, Ctr>) -> Bool:
  Bool.not(U32.is_gt(Ctr.n(h), ctr_find(num, Ctr.k(h))))

def UOp.divide_exact.den.go(+c: List<&2, Ctr>, +num: List<&2, Ctr>, ok: Bool) -> Bool:
  match c:
    case Nil{}: ok
    case h <> t: UOp.divide_exact.den.go(t, num, Bool.and(ok, UOp.divide_exact.den.ok(h, num)))

def UOp.divide_exact.den.all(+num: List<&2, Ctr>, +den: List<&2, Ctr>) -> Bool:
  UOp.divide_exact.den.go(den, num, True{})

def Dq.ok(+d: Dq) -> Bool:
  match d:
    case Dq{ok, f}: ok

def Dq.f(+d: Dq) -> Found:
  match d:
    case Dq{ok, f}: f

# and the "we aren't sure" answer: a `Dv`-shaped record with `ok` FALSE -- and the INDEX is
def Dq.no(+ar: Arena) -> Dq:
  Dq{False{}, Found{ar, 0}}

def UOp.divide_exact.add(+ar: Arena, +da: Dq, +db: Dq, +ok: Bool) -> Dq:
  match ok:
    case True{}: Dq{True{}, UOp.alu(Found.ar(Dq.f(db)), OpsADD{}, [Found.i(Dq.f(da)), Found.i(Dq.f(db))])}
    case False{}: Dq.no(ar)

# 1 (`ops.py:81`: `{Ops.ADD:0, Ops.MUL:1, Ops.MAX:dt.min}[op]`). -- MEASURED 2026-11-09:
def UOp.divide_exact.cval(+ar: Arena, +v: U32) -> H.I64:
  cf.cv(UOp.pop_const_val(ar, v, OpsMUL{}))

def UOp.divide_exact.constval(+ar: Arena, +v: U32) -> H.I64:
  cf.cv(cval_arg(Arena.arg(ar, v)))

def UOp.divide_exact.dv(+d: Dv, +ok: Bool) -> Dq:
  match ok:
    case True{}: Dq{True{}, Dv.f(d)}
    case False{}: Dq.no(Found.ar(Dv.f(d)))

def UOp.divide_exact.start(+ar: Arena, +self: U32, +v: U32) -> Found:
  UOp.const(ar, CInt{H.i64_div(UOp.divide_exact.cval(ar, self), UOp.divide_exact.cval(ar, v))})

def UOp.divide_exact.mod0(+c: H.I64, d: H.I64, zero: Bool) -> Bool:
  match zero:
    case True{}: False{}
    case False{}: H.i64_is_zero(H.i64_mod(c, d))

def UOp.divide_exact.ar(+m: Found) -> Arena:
  Found.ar(m)

def UOp.divide_exact.i(+m: Found) -> U32:
  Found.i(m)

def UOp.divide_exact.mul8(+m: Found, +nh: U32) -> Found:
  UOp.alu(UOp.divide_exact.ar(m), OpsMUL{}, [UOp.divide_exact.i(m), nh])

def UOp.divide_exact.mul7(+t: List<&2, U32>, +m: Found, +h: U32) -> Dq:
  match t:
    case Nil{}: Dq{True{}, UOp.divide_exact.mul8(m, h)}
    case nh <> nt :
      UOp.divide_exact.mul7(nt, UOp.divide_exact.mul8(m, h), nh)

# EACH, IN TWO DEFS -- MEASURED 2026-11-09: "expected : a call smaller than
def UOp.divide_exact.mul6(+ar: Arena, +start: Found, +es: List<&2, U32>) -> Dq:
  match es:
    case Nil{}: Dq{True{}, start}
    case h <> t: UOp.divide_exact.mul7(t, start, h)

def UOp.divide_exact.mul5(+ar: Arena, +self: U32, +v: U32, fac: U32, div_fac: U32, start: Found,
                          st: Ds) -> Dq:
  match st:
    case Ds{ok, es}:
      match ok:
        case True{}: UOp.divide_exact.mul6(ar, start, es)
        case False{}: Dq.no(ar)

def UOp.divide_exact.mul4(+ar: Arena, +self: U32, +v: U32, fac: U32, div_fac: U32, start: Found,
                          num: List<&2, Ctr>, den: List<&2, Ctr>) -> Dq:
  UOp.divide_exact.mul5(ar, self, v, fac, div_fac, start,
                        UOp.divide_exact.fold.go(num, den, Ds{True{}, Nil{}}))

# AND THE DENOMINATOR's SIDE OF THE TEST, AND IT IS **THE WHOLE** OF UPSTREAM's
# `all(v>=0 for v in new_count.values())` TOGETHER WITH `ge1`: `ge1` SAYS THE
# DIVISOR DOES NOT HAVE MORE OF A NUMERATOR FACTOR THAN THE NUMERATOR HAS, AND
# `den.all` SAYS THE NUMERATOR HAS AT LEAST AS MANY OF A DIVISOR FACTOR AS THE
# DIVISOR HAS.  MEASURED 2026-11-25: WITHOUT THE SECOND HALF THE PORT
# ANSWERED `divide_exact(6x, 4)` AS A QUOTIENT AND UPSTREAM ANSWERS `None`.
def UOp.divide_exact.mul4b(+ar: Arena, +self: U32, +v: U32, fac: U32, div_fac: U32, start: Found,
                           num: List<&2, Ctr>, den: List<&2, Ctr>, ok: Bool) -> Dq:
  match ok:
    case True{}: UOp.divide_exact.mul4(ar, self, v, fac, div_fac, start, num, den)
    case False{}: Dq.no(ar)

def UOp.divide_exact.mul3(+ar: Arena, +self: U32, +v: U32, +fac: U32, +div_fac: U32, +start: Found) -> Dq:
  +num = ctr_of(UOp.split_uop(Arena.budget(ar), ar, fac, OpsMUL{}))
  +den = ctr_of(UOp.split_uop(Arena.budget(ar), ar, div_fac, OpsMUL{}))
  UOp.divide_exact.mul4b(ar, self, v, fac, div_fac, start, num, den,
                         UOp.divide_exact.den.all(num, den))

def UOp.divide_exact.mul2(+ar: Arena, +self: U32, +v: U32, fac: U32, div_fac: U32, mod0: Bool,
                          start: Found) -> Dq:
  match mod0:
    case True{}: UOp.divide_exact.mul3(ar, self, v, fac, div_fac, start)
    case False{}: Dq.no(ar)

# UNSHAPED `UOp.const(b, dt)` -- MEASURED 2026-11-07 ON CPYTHON -- AND THE DIVISION IS
def UOp.divide_exact.mul(+ar: Arena, +self: U32, +v: U32) -> Dq:
  UOp.divide_exact.mul2(ar, self, v,
                        UOp.pop_const_node(ar, self, OpsMUL{}),
                        UOp.pop_const_node(ar, v, OpsMUL{}),
                        UOp.divide_exact.mod0(UOp.divide_exact.cval(ar, self), UOp.divide_exact.cval(ar, v),
                                              H.i64_is_zero(UOp.divide_exact.cval(ar, v))),
                        UOp.divide_exact.start(ar, self, v))

# COMPUTED VALUE -- MEASURED 2026-11-09: "a parameter or field scrutinee (a match cannot
def UOp.divide_exact.op(fuel: Nat, op: Op, +ar: Arena, +v: U32, +self: U32) -> Dq:
  match fuel:
    case 0n: Dq.no(ar)
    case 1n++p:
      match op:
        case OpsADD{}:
          +da = UOp.divide_exact.op(p, Arena.op(ar, Arena.src(ar, self, 0)), ar, v, Arena.src(ar, self, 0))
          +db = UOp.divide_exact.op(p, Arena.op(Found.ar(Dq.f(da)), Arena.src(ar, self, 1)),
                                    Found.ar(Dq.f(da)), v, Arena.src(ar, self, 1))
          UOp.divide_exact.add(ar, da, db, Bool.and(Dq.ok(da), Dq.ok(db)))
        case OpsMUL{}: UOp.divide_exact.mul(ar, self, v)
        case _: Dq.no(ar)

def UOp.divide_exact.cst(isconst: Bool, +ar: Arena, +self: U32, +v: U32) -> Dq:
  match isconst:
    case True{}:
      +dv = UOp.divides(Arena.budget(ar), ar, UOp.divide_exact.constval(ar, v), self)
      UOp.divide_exact.dv(dv, Dv.ok(dv))
    case False{}: UOp.divide_exact.op(Arena.budget(ar), Arena.op(ar, self), ar, v, self)

def UOp.divide_exact.one(same: Bool, +ar: Arena, +self: U32, +v: U32) -> Dq:
  match same:
    case True{}: Dq{True{}, UOp.const(ar, CInt{H.i64_of_i32(1)})}
    case False{}: UOp.divide_exact.cst(eq_op(Arena.op(ar, v), OpsCONST{}), ar, self, v)

def UOp.divide_exact(+ar: Arena, +self: U32, +v: U32) -> Dq:
  UOp.divide_exact.one(U32.is_eq(self, v), ar, self, v)

# `UOp.const(1, dt)`, MEASURED 2026-11-07 ON CPYTHON.
def UOp.gcd.prod.elems(+c: List<&2, Ctr>) -> List<&2, U32>:
  UOp.gcd.prod(c)

def UOp.gcd.answer(+ar: Arena, +uops: List<&2, U32>) -> Found:
  match uops:
    case Nil{}: Found{ar, 0}
    case x <> _ :
      +c = UOp.const(ar, CInt{UOp.gcd.gcd(UOp.gcd.cfactors(Arena.budget(ar), ar, uops))})
      UOp.gcd.answer.mul(UOp.gcd.prod.elems(ctr_inter(UOp.gcd.count(ar, UOp.gcd.terms(ar, uops)))), c)

# 'UOp.gcd.answer.mul3']` THREE TIMES, AND THE PORT's OWN `merge_dicts.go` is the shape
def UOp.gcd.mk2(+ar: Arena, +uops: List<&2, U32>, empty: Bool) -> Found:
  match empty:
    case True{}: UOp.gcd.const(ar, uops)
    case False{}: UOp.gcd.answer(ar, uops)

def UOp.gcd.mk(+ar: Arena, +uops: List<&2, U32>) -> Found:
  UOp.gcd.mk2(ar, uops, UOp.gcd.isempty(ctr_inter(UOp.gcd.count(ar, UOp.gcd.terms(ar, uops)))))

def UOp.gcd(+ar: Arena, +uops: List<&2, U32>) -> Found:
  match uops:
    case Nil{}: Found{ar, 0}
    case h <> t: UOp.gcd.mk(ar, uops)

# `index` -- ops.py:578. `UOp(Ops.INDEX, src=(self,)+tuple(new_srcs))`, and above it
def UOp.index.isconst(ar: Arena, k: U32) -> Bool:
  eq_op(Arena.op(ar, k), OpsCONST{})

def UOp.index.slot.go(arg: Arg) -> U32:
  match arg:
    case APy{CInt{i}}: H.lo32(i)
    case _: 0

def UOp.index.slot(+ar: Arena, self: U32, k: U32) -> U32:
  Arena.src(ar, self, UOp.index.slot.go(Arena.arg(ar, k)))

# THE PICK, and it is where the two answers have DIFFERENT ARENAS: the fast path
# SAME node. Here they are DIFFERENT nodes, so the `Bool` decides and one is built.
def UOp.index.pick(hit: Bool, +ar: Arena, self: U32, k: U32) -> Found:
  match hit:
    case True{}: Found{ar, UOp.index.slot(ar, self, k)}
    case False{}: UOp.new(ar, OpsINDEX{}, [self, k], ANone{}, TNone{})

def UOp.index.guard(+ar: Arena, self: U32, k: U32) -> Bool:
  Bool.and(eq_op(Arena.op(ar, self), OpsSTACK{}), UOp.index.isconst(ar, k))

def UOp.index.one(+ar: Arena, +self: U32, +k: U32) -> Found:
  UOp.index.pick(UOp.index.guard(ar, self, k), ar, self, k)

def UOp.index.rest(ar: Arena, self: U32, h: U32, t: List<&2, U32>) -> Found:
  match t:
    case Nil{}: UOp.index.one(ar, self, h)
    case _ <> _: UOp.new(ar, OpsINDEX{}, List.append(&2, U32, [self, h], t), ANone{}, TNone{})

def UOp.index.go(ar: Arena, self: U32, srcs: List<&2, U32>) -> Found:
  match srcs:
    case Nil{}: UOp.new(ar, OpsINDEX{}, [self], ANone{}, TNone{})
    case h <> t: UOp.index.rest(ar, self, h, t)

def UOp.index(ar: Arena, self: U32, srcs: List<&2, U32>) -> Found:
  UOp.index.go(ar, self, srcs)

# `store` -- ops.py:613. `srcs = (self, self.const_like(src) if not isinstance(src,
def UOp.store.srcs(+self: U32, +val: U32, gate: Maybe<&2, U32>) -> List<&2, U32>:
  match gate:
    case Some{g}: [self, val, g]
    case None{}: [self, val]

def UOp.store(ar: Arena, +self: U32, +val: U32, gate: Maybe<&2, U32>) -> Found:
  UOp.new(ar, OpsSTORE{}, UOp.store.srcs(self, val, gate), ANone{}, TNone{})

# `wmma` -- ops.py:649. `UOp(Ops.WMMA, src=(a, b, acc), arg=(dims, a.dtype,
def UOp.wmma(ar: Arena, a: U32, b: U32, acc: U32, dims: List<&2, U32>, dt: S.Dt, threads: U32, tc: Maybe<&2, List<&2, U32>>) -> Found:
  UOp.new(ar, OpsWMMA{}, [a, b, acc], AWmma{dims, dt, threads, tc}, TNone{})

def sg.tag(t: Tag) -> String:
  match t:
    case TNone{}: "none"
    case TBool{b}: Bool.show(b)
    case TStr{s}: s
    case TInt{i}: U32.show(i)
    case TTuple{xs}: "tuple"

def sg.ctor(arg: Arg) -> String:
  match arg:
    case ANone{}: "none"
    case ADt{dt}: String.concat(["dt:", dt_name(dt)])
    case APy{CBool{b}}: String.concat(["cbool:", Bool.show(b)])
    case APy{CInt{i}}: "cint"
    case APy{CFloat{f}}: "cfloat"
    case APy{CInvalid{}}: "cinvalid"
    case AInk{ins, dt}: String.concat(["ink:", ins, "/", dt_name(dt)])
    case AReduce{rop, num_axes}: String.concat(["reduce:", Ops.name(rop), "/", U32.show(num_axes)])
    case AWmma{dims, dt, threads, tc}: String.concat(["wmma:", U32.show(threads), "/", dt_name(dt)])
    case _: "other"

# `ufix` -- ops.py:606. THREE rows and the third is the one the def exists for:
def UOp.device_range_src.dn(ar: Arena, +tags: List<&2, U32>) -> DRng:
  +c = UOp.const(ar, CInt{H.i64_of_i32(U32.from_nat(List.length(&2, U32, tags)))})
  DRng.of(UOp.range_end(Found.ar(c), Found.i(c), [0], AXIS_DEVICE{}))

def UOp.device_range_src(ar: Arena, +dev: S.Dev) -> DRng:
  match dev:
    case S.D1{tag}: DRng{ar, Nil{}}
    case S.Dn{tags}: UOp.device_range_src.dn(ar, tags)

# `copy_to_device` -- ops.py:761. `inp = self if arg is None else MSELECT(self,
def UOp.copy_to_device.inp(ar: Arena, +self: U32, k: Maybe<&2, U32>) -> Found:
  match k:
    case None{}: Found{ar, self}
    case Some{j}: UOp.mselect(ar, self, j)

def UOp.copy_to_device(+ar: Arena, +self: U32, k: Maybe<&2, U32>, +dev: S.Dev) -> Found:
  +f = UOp.copy_to_device.inp(ar, self, k)
  +d = UOp.device_range_src(Found.ar(f), dev)
  UOp.new(DRng.ar(d), OpsCOPY{}, List.append(&2, U32, [Found.i(f)], DRng.ys(d)), ADev{dev}, TNone{})

# `getaddr` -- ops.py:844. `if self.without_after.op not in {BUFFER, ALLOC, SHRINK,
def UOp.getaddr.op(op: Op) -> Bool:
  match op:
    case OpsBUFFER{}: True{}
    case OpsALLOC{}: True{}
    case OpsSHRINK{}: True{}
    case OpsBITCAST{}: True{}
    case OpsBINARY{}: True{}
    case OpsMSTACK{}: True{}
    case OpsMSELECT{}: True{}
    case OpsPARAM{}: True{}
    case OpsLINEAR{}: True{}
    case _: False{}

def UOp.getaddr.peel(fuel: Nat, +ar: Arena, +self: U32) -> Bool:
  UOp.getaddr.op(Arena.op(ar, UOp.without_after(fuel, ar, self)))

def UOp.getaddr.go(peels: Bool, ar: Arena, +self: U32, made: Found) -> Found:
  match peels:
    case True{}: made
    case False{}: Found{ar, self}

def UOp.getaddr(fuel: Nat, +ar: Arena, +self: U32, +dev: S.Dev) -> Found:
  UOp.getaddr.go(UOp.getaddr.peel(fuel, ar, self), ar, self,
    UOp.new(ar, OpsGETADDR{}, [self], ADev{dev}, TNone{}))

# ==== ops.py:1030  `expr`, the one Variable-lattice def this arena can read ====
# `expr` -- ops.py:1030. `assert self.op in {Ops.PARAM, Ops.BUFFER}; return
def UOp.expr.go(arg: Arg) -> Maybe<&2, String>:
  match arg:
    case AParam{pa}:
      match pa:
        case ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: name
    case _: None{}

def UOp.expr(+ar: Arena, +self: U32) -> Maybe<&2, String>:
  UOp.expr.go(Arena.arg(ar, self))

# DONE(p3) ops.py:1048  def const_factor
#   be written that way, because its recursion is over a DIFFERENT node per step
#   DONE  ops.py:1069 `divides`   -- `UOp.divides.op` (:7951) and `UOp.divides` (:7972),
#   DONE  ops.py:1082 `pop_const` -- `UOp.pop_const_val` (:7738) / `UOp.pop_const_hits`
#   TODO  ops.py:1073 `gcd`
#   TODO  ops.py:1079 `divide_exact`
# TODO(p3) ops.py:1032  def gcd
# TODO(p3) ops.py:1038  def divide_exact
#   `__floordiv__`. `const_like` is ops.py:572 and is NOT ported (:5441): it is
# ==== ops.py:1015  `UOp.variable` =========================================
# three siblings had each invented one. MEASURED: `variable("i",0,10).arg.slot` is
def UOp.variable.pa.of(base: ParamArg, nm: String, r: PyRange, mo: U32) -> ParamArg:
  match base:
    case ParamArg{slot, dtype, vmin_vmax, multiple_of, _n, addrspace, device, volatile, image, buffer, bind_on_realize, val}:
      ParamArg{slot, dtype, Some{r}, Some{mo}, Some{nm}, S.Aalu{},
        device, volatile, image, buffer, bind_on_realize, val}

def UOp.variable.pa(nm: String, lo: H.I64, hi: H.I64, mo: U32, dt: S.Dt) -> ParamArg:
  UOp.variable.pa.of(ParamArg.of(ParamArg.no_slot(), dt), nm, PyRange{lo, hi}, mo)

def UOp.variable(+ar: Arena, nm: String, lo: H.I64, hi: H.I64, mo: U32, dt: S.Dt) -> Found:
  UOp.new(ar, OpsPARAM{}, Nil{}, AParam{UOp.variable.pa(nm, lo, hi, mo, dt)}, TNone{})

# `ProgramInfo.launch_dims` -- ops.py:1352 -- AND `ProgramInfo.from_sink`
# -- ops.py:1358. the two methods upstream's `ProgramInfo` has at the PIN.
def fs.arg(ar: Arena, u: U32) -> Arg:
  Arena.arg(ar, u)

def fs.op(ar: Arena, u: U32) -> Op:
  Arena.op(ar, u)

type PSlot is Data:
  PSlot{slot: U32, node: U32}

def PSlot.le(a: PSlot, b: PSlot) -> Bool:
  match a b:
    case PSlot{slot, node} PSlot{s2, n2}: U32.is_le(slot, s2)

type PInfo is Data:
  PInfo{slot: U32, alu: Bool}

def PInfo.slot(p: PInfo) -> U32:
  match p:
    case PInfo{slot, alu}: slot

def PInfo.alu(p: PInfo) -> Bool:
  match p:
    case PInfo{slot, alu}: alu

type FS is Data:
  FS{params: List<&2, PSlot>, globals: List<&2, U32>, outs: List<&2, U32>, ins: List<&2, U32>}

type Sz is Data:
  Sz{gs: List<&2, H.I64>, ls: List<&2, H.I64>}

type OI is Data:
  OI{o: List<&2, U32>, i: List<&2, U32>}

# `from_sink` -- ops.py:1358.
def fs.pinfo.of(+a: Arg) -> Maybe<&2, PInfo>:
  match a:
    case AParam{pa}: Some{PInfo{ParamArg.slot(pa), pa.is_alu.of(a)}}
    case _: None{}

def fs.pinfo(ar: Arena, u: U32) -> Maybe<&2, PInfo>:
  fs.pinfo.of(fs.arg(ar, u))

def fs.slot.of(a: Arg) -> Maybe<&2, U32>:
  match a:
    case AParam{pa}:
      match pa:
        case ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}:
          Some{slot}
    case _: None{}

def fs.slot(ar: Arena, u: U32) -> Maybe<&2, U32>:
  fs.slot.of(fs.arg(ar, u))

def fs.buf_slot(fuel: Nat, op: Op, +ar: Arena, +s: U32) -> Maybe<&2, U32>:
  match fuel:
    case 0n: None{}
    case 1n+f:
      match op:
        case OpsPARAM{}: fs.slot(ar, s)
        case OpsBUFFER{}: None{}
        case OpsALLOC{}: None{}
        case OpsSTAGE{}: None{}
        case OpsMSTACK{}: None{}
        case OpsMSELECT{}: None{}
        case _: fs.buf_slot(f, fs.op(ar, Arena.src0(ar, s)), ar, Arena.src0(ar, s))

def fs.buf_slot.of(+ar: Arena, +s: U32) -> Maybe<&2, U32>:
  fs.buf_slot(Arena.budget(ar), fs.op(ar, s), ar, s)

# or a LOAD. THE CAST ARM IS A SEPARATE DEF because it reads a DIFFERENT node.
# STORE'S OWN FIRST SRC -- AND NOT `u`:
def fs.idx.cast.of(op: Op, +ar: Arena, +u: U32) -> Maybe<&2, U32>:
  match op:
    case OpsINDEX{}: Some{Arena.src0(ar, Arena.src0(ar, u))}
    case _: None{}

def fs.idx.cast(+ar: Arena, +u: U32) -> Maybe<&2, U32>:
  fs.idx.cast.of(fs.op(ar, Arena.src0(ar, Arena.src0(ar, u))), ar, u)

def fs.idx.of(op: Op, +ar: Arena, +u: U32) -> Maybe<&2, U32>:
  match op:
    case OpsINDEX{}: Some{Arena.src0(ar, u)}
    case OpsSHRINK{}: Some{Arena.src0(ar, u)}
    case OpsCAST{}: fs.idx.cast(ar, u)
    case _: None{}

def fs.idx(+ar: Arena, +u: U32) -> Maybe<&2, U32>:
  fs.idx.of(fs.op(ar, Arena.src0(ar, u)), ar, u)

def fs.sp.local.of(cs: List<&2, Char>) -> Bool:
  match cs:
    case Nil{}: False{}
    case c <> _: Char.is_eq(c, Chr{108})

def fs.sp.local(nm: String) -> Bool:
  fs.sp.local.of(String.to_list(nm))

def fs.sp.dim.digit.of(is_digit: Bool, c: Char) -> Maybe<&2, U32>:
  match is_digit:
    case True{}: Some{U32.sub(Char.to_u32(c), 48)}
    case False{}: None{}

def fs.sp.dim.digit(+c: Char) -> Maybe<&2, U32>:
  fs.sp.dim.digit.of(Char.is_digit(c), c)

def fs.sp.dim.last(m: Maybe<&2, Char>) -> Maybe<&2, U32>:
  match m:
    case Some{c}: fs.sp.dim.digit(c)
    case None{}: None{}

def fs.sp.dim.of(cs: List<&2, Char>) -> Maybe<&2, U32>:
  fs.sp.dim.last(List.last(&2, Char, cs))

def fs.sp.dim(nm: String) -> Maybe<&2, U32>:
  fs.sp.dim.of(String.to_list(nm))

def fs.sp.val.of(m: Maybe<&1, Const>) -> Maybe<&2, H.I64>:
  match m:
    case Some{CInt{i}}: Some{i}
    case _: None{}

def fs.sp.val(+ar: Arena, u: U32) -> Maybe<&2, H.I64>:
  fs.sp.val.of(UOp.ssimplify_val(ar, Arena.src0(ar, u)))

def fs.sp.put.of(local: Bool, dim: Nat, v: H.I64, +sz: Sz) -> Maybe<&2, Sz>:
  match local:
    case True{}:
      match sz:
        case Sz{gs, ls}: Some{Sz{gs, List.set(&2, H.I64, ls, dim, v)}}
    case False{}:
      match sz:
        case Sz{gs, ls}: Some{Sz{List.set(&2, H.I64, gs, dim, v), ls}}

def fs.sp.put(nm: String, dim: Nat, v: H.I64, sz: Sz) -> Maybe<&2, Sz>:
  fs.sp.put.of(fs.sp.local(nm), dim, v, sz)

def fs.sp.set(+ar: Arena, u: U32, +nm: String, sz: Sz) -> Maybe<&2, Sz>:
  Maybe.bind(&2, U32, Sz, fs.sp.dim(nm), dim =>
    Maybe.bind(&2, H.I64, Sz, fs.sp.val(ar, u), v =>
      fs.sp.put(nm, U32.to_nat(dim), v, sz)))

def fs.sp.arg.of(a: Arg, +ar: Arena, +u: U32, sz: Sz) -> Maybe<&2, Sz>:
  match a:
    case AStr{nm}: fs.sp.set(ar, u, nm, sz)
    case _: Some{sz}

def fs.sp.step.of(op: Op, a: Arg, +ar: Arena, +u: U32, sz: Sz) -> Maybe<&2, Sz>:
  match op:
    case OpsSPECIAL{}: fs.sp.arg.of(a, ar, u, sz)
    case _: Some{sz}

def fs.sp.step(+ar: Arena, +u: U32, sz: Sz) -> Maybe<&2, Sz>:
  fs.sp.step.of(fs.op(ar, u), fs.arg(ar, u), ar, u, sz)

def fs.param.put(+p: PInfo, +u: U32, +params: List<&2, PSlot>, +globals: List<&2, U32>, +outs: List<&2, U32>, +ins: List<&2, U32>) -> FS:
  Bool.pick(FS, PInfo.alu(p),
    FS{List.append(&2, PSlot, params, [PSlot{PInfo.slot(p), u}]), globals, outs, ins},
    FS{List.append(&2, PSlot, params, [PSlot{PInfo.slot(p), u}]), List.append(&2, U32, globals, [PInfo.slot(p)]), outs, ins})

def fs.param.maybe(ar: Arena, +u: U32, acc: FS) -> Maybe<&2, FS>:
  match acc:
    case FS{params, globals, outs, ins}:
      Maybe.bind(&2, PInfo, FS, fs.pinfo(ar, u), p =>
        Some{fs.param.put(p, u, params, globals, outs, ins)})

def fs.param(ar: Arena, u: U32, +acc: FS) -> FS:
  Maybe.default(&2, FS, fs.param.maybe(ar, u, acc), acc)

def fs.io_slot(+ar: Arena, +u: U32) -> Maybe<&2, U32>:
  Maybe.bind(&2, U32, U32, fs.idx(ar, u), idx =>
    Maybe.bind(&2, U32, U32, fs.buf_slot.of(ar, Arena.src0(ar, idx)), slot =>
      Some{slot}))

# `(outs if u.op is Ops.STORE else ins).append(buf.arg.slot)` (ops.py:1368). The
def fs.io.put(is_store: Bool, slot: U32, params: List<&2, PSlot>, globals: List<&2, U32>, outs: List<&2, U32>, ins: List<&2, U32>) -> FS:
  match is_store:
    case True{}: FS{params, globals, List.append(&2, U32, outs, [slot]), ins}
    case False{}: FS{params, globals, outs, List.append(&2, U32, ins, [slot])}

def fs.io.maybe(+ar: Arena, +u: U32, acc: FS) -> Maybe<&2, FS>:
  match acc:
    case FS{params, globals, outs, ins}:
      Maybe.bind(&2, U32, FS, fs.io_slot(ar, u), slot =>
        Some{fs.io.put(eq_op(Arena.op(ar, u), OpsSTORE{}), slot, params, globals, outs, ins)})

def fs.io(ar: Arena, u: U32, +acc: FS) -> FS:
  Maybe.default(&2, FS, fs.io.maybe(ar, u, acc), acc)

# `match`, and each test is on a DIFFERENT node. THE SPECIAL ARM IS IN THE
def fs.step.io.of(is_io: Bool, +ar: Arena, +u: U32, +acc: FS) -> Maybe<&2, FS>:
  match is_io:
    case True{}: Some{fs.io(ar, u, acc)}
    case False{}: Some{acc}

def fs.step.io(+ar: Arena, +u: U32, +acc: FS) -> Maybe<&2, FS>:
  fs.step.io.of(Bool.or(eq_op(Arena.op(ar, u), OpsSTORE{}), eq_op(Arena.op(ar, u), OpsLOAD{})), ar, u, acc)

def fs.step.of(is_param: Bool, +ar: Arena, +u: U32, +acc: FS) -> Maybe<&2, FS>:
  match is_param:
    case True{}: Some{fs.param(ar, u, acc)}
    case False{}: fs.step.io(ar, u, acc)

def fs.step(+ar: Arena, +u: U32, +acc: FS) -> Maybe<&2, FS>:
  fs.step.of(eq_op(Arena.op(ar, u), OpsPARAM{}), ar, u, acc)

def fs.go(+ar: Arena, todo: List<&2, U32>, +acc: FS) -> Maybe<&2, FS>:
  match todo:
    case Nil{}: Some{acc}
    case u <> t:
      Maybe.bind(&2, FS, FS, fs.step(ar, u, acc), a2 => fs.go(ar, t, a2))

# DEF AND NOT TWO because the step CONTINUES THE FOLD, and a def that calls
def fs.sz.go(+ar: Arena, todo: List<&2, U32>, +sz: Sz) -> Maybe<&2, Sz>:
  match todo:
    case Nil{}: Some{sz}
    case +u <> t:
      Maybe.bind(&2, Sz, Sz, fs.sp.step(ar, u, sz), s2 => fs.sz.go(ar, t, s2))

def fs.slots(xs: List<&2, U32>) -> List<&2, U32>:
  List.sort(U32, U32.is_le, H.dedup_u32(xs))

def fs.nodes(xs: List<&2, PSlot>) -> List<&2, U32>:
  match xs:
    case Nil{}: Nil{}
    case PSlot{slot, node} <> t: List.append(&2, U32, [node], fs.nodes(t))

def fs.params(xs: List<&2, PSlot>) -> List<&2, U32>:
  fs.nodes(List.sort(PSlot, PSlot.le, xs))

# AND NOT IS THE WHOLE OF THIS DEF, and it was `Bool.or` for one run and
def fs.oi(+globals: List<&2, U32>, +outs: List<&2, U32>, +ins: List<&2, U32>) -> OI:
  Bool.pick(OI, Bool.and(List.is_empty(&2, U32, outs), List.is_empty(&2, U32, ins)),
    OI{globals, globals},
    OI{outs, ins})

def fs.finish.pair(oi: OI, gs: List<&2, H.I64>, ls: List<&2, H.I64>, params: List<&2, U32>, globals: List<&2, U32>, tgt: H.Target) -> ProgramInfo:
  match oi:
    case OI{o, i}: ProgramInfo{gs, ls, params, globals, fs.slots(o), fs.slots(i), tgt}

def fs.finish(acc: FS, sz: Sz, tgt: H.Target) -> ProgramInfo:
  match acc:
    case FS{params, +globals, outs, ins}:
      match sz:
        case Sz{gs, ls}:
          fs.finish.pair(fs.oi(globals, outs, ins), gs, ls, fs.params(params), fs.slots(globals), tgt)

def fs.one() -> H.I64: H.i64_of_i32(1)

def fs.ones() -> List<&2, H.I64>: [fs.one(), fs.one(), fs.one()]

# THE ENTRY. `ProgramInfo.from_sink(sink, target)` -- ops.py:1358.
def ProgramInfo.from_sink(+ar: Arena, +sink: U32, tgt: H.Target) -> Maybe<&2, ProgramInfo>:
  Maybe.bind(&2, FS, ProgramInfo, fs.go(ar, UOp.toposort(Arena.budget(ar), ar, sink), FS{Nil{}, Nil{}, Nil{}, Nil{}}), acc =>
    Maybe.bind(&2, Sz, ProgramInfo, fs.sz.go(ar, UOp.toposort(Arena.budget(ar), ar, sink), Sz{fs.ones(), fs.ones()}), sz =>
      Some{fs.finish(acc, sz, tgt)}))

def fs.i64_dec.of(hi: U32, lo: U32) -> String:
  match hi:
    case 0: U32.show(lo)
    case _: String.concat([U32.show(hi), ":", U32.show(lo)])

def fs.i64_dec(+x: H.I64) -> String:
  fs.i64_dec.of(H.hi32(x), H.lo32(x))

def t_gcd_const() -> Bool:
  +ar0 = Arena.empty()
  +fx = UOp.variable(ar0, "x", H.i64_of_i32(0), H.i64_of_i32(4), 1, S.weakint())
  +ar1 = Found.ar(fx)
  +fy = UOp.variable(ar1, "y", H.i64_of_i32(0), H.i64_of_i32(4), 1, S.weakint())
  +ar2 = Found.ar(fy)
  +g = UOp.gcd(ar2, [Found.i(fx), Found.i(fy)])
  +ga = Found.ar(g)
  Bool.and(eq_op(Arena.op(ga, Found.i(g)), OpsCONST{}), U32.is_eq(Arena.nsrc(ga, Found.i(g)), 0))

def t_gcd_shared() -> Bool:
  +ar0 = Arena.empty()
  +fx = UOp.variable(ar0, "x", H.i64_of_i32(0), H.i64_of_i32(4), 1, S.weakint())
  +ar1 = Found.ar(fx)
  +fz = UOp.variable(ar1, "z", H.i64_of_i32(0), H.i64_of_i32(4), 1, S.weakint())
  +ar2 = Found.ar(fz)
  +mxz = UOp.alu(ar2, OpsMUL{}, [Found.i(fx), Found.i(fz)])
  +ar3 = Found.ar(mxz)
  +g = UOp.gcd(ar3, [Found.i(mxz), Found.i(mxz)])
  +ga = Found.ar(g)
  eq_op(Arena.op(ga, Found.i(g)), OpsMUL{})

# `(op, src, arg, type(arg))` (`ops.py:194`), so `type(arg)` is the only thing that splits the
# AND CPYTHON's OWN ANSWERS, MEASURED AT THE PIN: `arg=True` vs `arg=1` is False (the
def arg_same(a1: Arg, a2: Arg) -> Bool:
  +u = UOp.new(Arena.empty(), OpsSINK{}, Nil{}, a1, TNone{})
  +v = UOp.new(Found.ar(u), OpsSINK{}, Nil{}, a2, TNone{})
  U32.is_eq(Found.i(u), Found.i(v))

def t_arg_bool_vs_int_splits() -> Bool:
  Bool.not(arg_same(APy{CBool{True{}}}, APy{CInt{H.i64_of_i32(1)}}))

def t_arg_none_vs_int_splits() -> Bool:
  Bool.not(arg_same(ANone{}, APy{CInt{H.i64_of_i32(0)}}))

def t_arg_int_same_interns() -> Bool:
  arg_same(APy{CInt{H.i64_of_i32(1)}}, APy{CInt{H.i64_of_i32(1)}})

# `UOp.divide_exact` -- ops.py:1038-1047. AND CPYTHON's OWN `UOp.divide_exact` IS THE
# AND CPYTHON's ANSWERS, MEASURED AT THE PIN:
def t_de_same() -> Bool:
  +ar0 = Arena.empty()
  +fx = UOp.variable(ar0, "x", H.i64_of_i32(0), H.i64_of_i32(4), 1, S.weakint())
  +ar1 = Found.ar(fx)
  +d = UOp.divide_exact(ar1, Found.i(fx), Found.i(fx))
  +ga = Found.ar(Dq.f(d))
  Bool.and(Dq.ok(d), eq_op(Arena.op(ga, Found.i(Dq.f(d))), OpsCONST{}))

def t_de_const_none() -> Bool:
  +ar0 = Arena.empty()
  +fx = UOp.variable(ar0, "x", H.i64_of_i32(0), H.i64_of_i32(4), 1, S.weakint())
  +ar1 = Found.ar(fx)
  +c2 = UOp.const(ar1, CInt{H.i64_of_i32(2)})
  +d = UOp.divide_exact(Found.ar(c2), Found.i(fx), Found.i(c2))
  Bool.not(Dq.ok(d))

def t_de_mul() -> Bool:
  +ar0 = Arena.empty()
  +fx = UOp.variable(ar0, "x", H.i64_of_i32(0), H.i64_of_i32(4), 1, S.weakint())
  +ar1 = Found.ar(fx)
  +fy = UOp.variable(ar1, "y", H.i64_of_i32(0), H.i64_of_i32(4), 1, S.weakint())
  +ar2 = Found.ar(fy)
  +mxy = UOp.alu(ar2, OpsMUL{}, [Found.i(fx), Found.i(fy)])
  +ar3 = Found.ar(mxy)
  +d = UOp.divide_exact(ar3, Found.i(mxy), Found.i(fy))
  +ga = Found.ar(Dq.f(d))
  +gi = Found.i(Dq.f(d))
  +left = Arena.src(ga, gi, 0)
  Bool.and(Dq.ok(d),
           Bool.and(eq_op(Arena.op(ga, gi), OpsMUL{}),
                    Bool.and(eq_op(Arena.op(ga, left), OpsCONST{}),
                             Cmp.is_eq(H.i64_cmp(UOp.divide_exact.constval(ga, left), H.i64_of_i32(1))))))

#     only writer is `codegen/__init__.py:446` and `do_estimates` is a WALL in
#     without it, because `uop/spec.py:110`'s `isinstance(x.arg, CustomFunction)`
#     MEASURED 2026-10-06, so the next reader does not have to re-derive it: the
#   `UPat.custom_function(fn, kwargs)` -- ops.py:1509 upstream, still NOT PORTED. A
#   `UOp.param_like(slot, name=None)` -- ops.py:1241 upstream. `name` was added so a
#     COMPILER (`tinygrad/uop/upat.py`). `UPat` is PORTED (see ops.py:1447, with
# AND THE **DENOMINATOR's SIDE** OF UPSTREAM's TEST, AND IT IS THE ROW THAT
# CATCHES A `divide_exact` THAT DOES NOT **SUBTRACT** THE DIVISOR's FACTORS:
# UPSTREAM's `new_count` IS `Counter(num) - Counter(den)` (ops.py:1044-1045), SO
# A FACTOR THAT IS IN THE DIVISOR AND NOT IN THE NUMERATOR HAS A **NEGATIVE**
# COUNT AND UPSTREAM's `all(v>=0 for v in new_count.values())` (ops.py:1046) IS
# FALSE.  MEASURED 2026-11-25: WITHOUT THE SUBTRACTION THE PORT ANSWERED
# `divide_exact(6x, y)` WITH A QUOTIENT AND UPSTREAM ANSWERS `None`.
def t_de_den() -> Bool:
  +ar0 = Arena.empty()
  +fx = UOp.variable(ar0, "x", H.i64_of_i32(0), H.i64_of_i32(4), 1, S.weakint())
  +ar1 = Found.ar(fx)
  +fy = UOp.variable(ar1, "y", H.i64_of_i32(0), H.i64_of_i32(4), 1, S.weakint())
  +ar2 = Found.ar(fy)
  +c6 = UOp.const(ar2, CInt{H.i64_of_i32(6)})
  +ar3 = Found.ar(c6)
  +mx6 = UOp.alu(ar3, OpsMUL{}, [Found.i(fx), Found.i(c6)])
  +ar4 = Found.ar(mx6)
  +d = UOp.divide_exact(ar4, Found.i(mx6), Found.i(fy))
  Bool.not(Dq.ok(d))

def t_de_const_out() -> Bool:
  +ar0 = Arena.empty()
  +fx = UOp.variable(ar0, "x", H.i64_of_i32(0), H.i64_of_i32(4), 1, S.weakint())
  +ar1 = Found.ar(fx)
  +c2 = UOp.const(ar1, CInt{H.i64_of_i32(2)})
  +ar2 = Found.ar(c2)
  +mx2 = UOp.alu(ar2, OpsMUL{}, [Found.i(fx), Found.i(c2)])
  +ar3 = Found.ar(mx2)
  +d = UOp.divide_exact(ar3, Found.i(mx2), Found.i(fx))
  +ga = Found.ar(Dq.f(d))
  Bool.and(Dq.ok(d),
           Bool.and(eq_op(Arena.op(ga, Found.i(Dq.f(d))), OpsCONST{}),
                    Cmp.is_eq(H.i64_cmp(UOp.divide_exact.constval(ga, Found.i(Dq.f(d))), H.i64_of_i32(2)))))

# THE TABLE IS IN `.agents/slop/tables/uop-ops-8427.md` -- NOT PORTED -- tinygrad/uop/ops.py, and why. One line each, the same shape
