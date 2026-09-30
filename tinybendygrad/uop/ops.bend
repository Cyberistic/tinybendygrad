# ops.bend -- tinygrad/uop/ops.py.
#
# THIS FILE IS THE GATE. .agents/TODO.md: "if the arena does not work here, the
# 30k-line plan changes and we say so rather than limping along". So the first
# thing to report is what the arena turned out to be:
#
#   A UOp is a U32 index into an append-only `List<Node>`, threaded through
#   every function that touches the graph and returned by every function that
#   grows it.   -> THE ARENA WORKS. No @unsafe, no stub, both lanes green.
#
# WHY AN INDEX AND NOT A TREE. tinygrad hash-conses UOps in
# `UOpMetaClass.ucache` and the range graph has back-edges -- a SPECIAL whose
# end is a symbolic uop, an END whose src[0] is the body it closes over -- so
# the graph is CYCLIC. `UOp.__eq__` is deliberately identity (it is not
# overridden: `UOpMetaClass.__call__` hands back the cached object) and tinygrad
# `test/` leans on that with `assertIs`. Bend's datatypes are inductive trees:
# they cannot hold a cycle, and Bend's only loop is a structurally decreasing
# self-call, so a cyclic graph cannot even be WALKED without a worklist. An
# index into a store can point anywhere, including backwards, and gives O(1)
# identity for free. That is the one place this representation is better than
# Python's.
#
# WHAT THE ARENA COST. This is the list a reviewer should check first.
#
#   1. NO GLOBAL STATE. `Array<T>` masks its index (`Array.get` computes
#      `i & (n-1)`), so `Array.set` cannot grow a table; `Array.fork` and
#      `Array.atomic.*` are `@unsafe` or unfilled laws. So the store is a
#      `List`, which is affine and has exactly one owner, and that owner is
#      threaded as `ar: Arena`, the first parameter of every UOp-taking def.
#   2. READS ARE O(n) FOLDS. So hash-consing is a linear scan of the arena
#      rather than a dict lookup, and `self.src[0]` is a fold rather than a
#      tuple index. Same information as Python's ucache, computed the slow way.
#      `intern` carries the whole argument.
#   3. GRAPH WALKS TAKE A FUEL `Nat`. tinygrad's `toposort`, `topovisit`,
#      `walk_rewrite` and `unified_rewrite` are `while stack:` loops over a
#      mutable list. Bend has no loop, only a self-call, and a self-call must
#      pass a subterm of its own parameter: a worklist is not a subterm, and
#      neither is a U32 read back out of the store. So those four and the
#      bottom-up fixed point take `fuel: Nat` FIRST and `case 0n:` answers
#      None -- "past this depth, unknown", never a wrong value.
#      This is NOT the retracted fuel from
#      .agents/slop/notes/bend2-constraints.md. That one leaned on a
#      `case 2n+p:` sibling, which numeric patterns made dead code, so a fold
#      over it answered None for every operand. This one is a plain
#      `case 1n+p:` countdown, which is exact.
#   4. `arg: Any` AND `tag: Any` BECAME DATATYPES. `Any` is what Python spells
#      when one field holds eighteen unrelated things. `Arg` and `Tag` below
#      name all eighteen. Nothing is lost and the arms are compiler-checked.
#   5. THE `recursive_property` MEMO IS DROPPED. Python memoises dtype, shape,
#      device, _ranges, key, _min_max and the rest on `node.__dict__`, which is
#      both a cache and a cycle guard: without it a diamond DAG is walked
#      exponentially often. Reproducing it needs a second store threaded beside
#      the arena and a pair return on every property read, so all ~20 memoised
#      properties would stop matching the Python return shape. This port keeps
#      the shapes and recomputes. The cost is exponential in DAG depth and it
#      is real; the memo is the first thing to put back if a walk gets slow.
#      `UOp.dtype` carries the whole argument.
#   6. `Ops` IS NOT AN IntEnum HERE. Python's is (`FastEnum`), and
#      `UOp.tuplize` uses the NUMBER where `repr` uses the NAME, so both
#      `Ops.name` and `Ops.value` are ported. A datatype carries the name and
#      the declaration order below IS the number, because `__init__.py` says
#      "the order of these Ops controls the order of the toposort".
#
# WHERE DEFS WERE REORDERED, and why. Bend has no forward references: a def may
# only call defs written above it, and mutual recursion is refused outright.
# Python's order is kept wherever the dependency graph allows. Four moves, each
# marked where it happens:
#   * `Ops` and `GroupOp` are at the top. They come from
#     `tinygrad/uop/__init__.py` and ops.py IMPORTS them, so they have to be
#     written before the first `match op`. They move to `uop/init.bend` when
#     that file is ported; they are here because this file is the gate.
#   * The arena types, `intern` and `dtype_from_uop` come before the UOp
#     methods, because `dtype_from_uop` reads `src[0].dtype` and the property
#     reader reads the arena.
#   * `UPat`, `PatternMatcher`, `RewriteContext` and `graph_rewrite` sit ABOVE
#     the UOp method block, because `simplify`, `substitute` and
#     `contiguous_view` all call `graph_rewrite`. In Python they come after and
#     that is fine there -- they are lambdas and module names resolved at call
#     time; in Bend a call is resolved at compile time. Their order among
#     themselves is unchanged.
#   * `sint_to_uop`, `to_max_shape`, `_substitute`, `_pm_resolve_params` and the
#     trailing helpers come last, as in Python.
#
# NOT PORTED, one line each, with the reason. The block at the bottom is the
# same shape helpers.bend and dtype.bend use.
#
# `./../dtype.bend` IS NOT IMPORTED, and that is worth a line. The gate says
# "must reach zero errors", and importing dtype.bend makes that impossible for
# ANY file: its fp16/bf16/fp8/i64 C effects are foreign code, so the checker
# prints "14 defs rely on unsafe or foreign code" and exits 1 whatever the
# importer does. A two-line file that imports dtype.bend and does nothing else
# prints the same fourteen lines. So this file takes `Dt` from
# `./LAWS/spec.bend` -- the ONE datatype, which is what dtype.bend itself does --
# and the two dtype.py functions ops.py needs and dtype.bend has
# (`least_upper_dtype`, `dt.min`/`dt.max`) are NOT PORTED with the folds that
# call them. When they land, so does the import, and the notice comes back.

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
type Op is Data:
  # ** 1 -- defines/special **
  # this is a RANGE for GPU dimensions, similar to symbolic shapes but not exactly
  OpsSPECIAL{}
  # BUFFER references bound storage; ALLOC declares unbound global storage
  OpsBUFFER{}
  OpsALLOC{}
  # ** 2 -- non op uops **
  # uops that aren't rendered
  OpsNOOP{}
  OpsREWRITE_ERROR{}
  # CALL is a kernel invocation; value-producing calls write to ALLOC arguments
  OpsPARAM{}
  OpsCALL{}
  # renderer
  # LINEAR is a list of UOps, SOURCE has a str arg that's human readable, BINARY has bytes arg that's compiled
  OpsPROGRAM{}
  OpsLINEAR{}
  OpsSOURCE{}
  OpsBINARY{}
  # AFTER passes src[0] through and promises in the toposort that any consumers of the AFTER run after src[1:]
  # GROUP is a NOOP that just merges things together
  OpsSINK{}
  OpsAFTER{}
  OpsGROUP{}
  # vector creation / item selection
  OpsSTACK{}
  # hcq specific
  OpsGETADDR{}
  # ** 3 -- load/store **
  # INDEX is a BinaryOp similar to ADD, but it operates on pointers
  OpsINDEX{}
  OpsSHRINK{}
  # load/store before math
  OpsLOAD{}
  OpsSTORE{}
  # ** 4 -- math **
  # tensor core math op, not elementwise
  OpsWMMA{}
  # UnaryOps
  OpsCAST{}
  OpsBITCAST{}
  OpsEXP2{}
  OpsLOG2{}
  OpsSIN{}
  OpsSQRT{}
  OpsRECIPROCAL{}
  OpsNEG{}
  OpsTRUNC{}
  # BinaryOps
  OpsADD{}
  OpsMUL{}
  OpsSHL{}
  OpsSHR{}
  OpsCDIV{}
  OpsMAX{}
  OpsCMOD{}
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
  OpsFLOORDIV{}
  OpsFLOORMOD{}
  # TernaryOps
  OpsWHERE{}
  OpsMULACC{}
  # ** 5 -- control flow / consts / custom **
  # control flow ops
  OpsBARRIER{}
  OpsRANGE{}
  OpsIF{}
  OpsEND{}
  OpsENDIF{}
  # (body, unbounded RANGE, condition): repeat while condition is true
  OpsBACKEDGE{}
  # const.
  OpsCONST{}
  # CUSTOM/CUSTOMI are used to output strings into codegen. the I makes the string inline
  OpsCUSTOM{}
  OpsCUSTOMI{}
  # INS is a machine instruction
  OpsINS{}
  # ** 6 -- ops that don't exist in programs **
  # ops that adjust the behavior of the scheduler
  OpsCONTIGUOUS_BACKWARD{}
  OpsDETACH{}
  # buffer ops
  OpsSTAGE{}
  OpsCOPY{}
  OpsMSELECT{}
  OpsMSTACK{}
  OpsCUSTOM_FUNCTION{}
  # the core 6 movement ops! these only exist in the tensor graph
  OpsRESHAPE{}
  OpsPERMUTE{}
  OpsEXPAND{}
  OpsPAD{}
  OpsFLIP{}
  # UNSHARD is really a movement op
  OpsUNSHARD{}
  # reduce
  OpsREDUCE{}
  OpsALLREDUCE{}
  # ** 7 -- pattern compiler IR (used in upat.py) **
  # PYLITERAL carries a Python literal as an arg for CUSTOM predicates
  OpsPYLITERAL{}

# FastEnum.__str__ and FastEnum.__repr__ are both `str(self)`, so one table.
def Ops.name(op: Op) -> String:
  match op:
    case OpsSPECIAL{}: "SPECIAL"
    case OpsBUFFER{}: "BUFFER"
    case OpsALLOC{}: "ALLOC"
    case OpsNOOP{}: "NOOP"
    case OpsREWRITE_ERROR{}: "REWRITE_ERROR"
    case OpsPARAM{}: "PARAM"
    case OpsCALL{}: "CALL"
    case OpsPROGRAM{}: "PROGRAM"
    case OpsLINEAR{}: "LINEAR"
    case OpsSOURCE{}: "SOURCE"
    case OpsBINARY{}: "BINARY"
    case OpsSINK{}: "SINK"
    case OpsAFTER{}: "AFTER"
    case OpsGROUP{}: "GROUP"
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
    case OpsRECIPROCAL{}: "RECIPROCAL"
    case OpsNEG{}: "NEG"
    case OpsTRUNC{}: "TRUNC"
    case OpsADD{}: "ADD"
    case OpsMUL{}: "MUL"
    case OpsSHL{}: "SHL"
    case OpsSHR{}: "SHR"
    case OpsCDIV{}: "CDIV"
    case OpsMAX{}: "MAX"
    case OpsCMOD{}: "CMOD"
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
    case OpsFLOORDIV{}: "FLOORDIV"
    case OpsFLOORMOD{}: "FLOORMOD"
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
    case OpsFLIP{}: "FLIP"
    case OpsUNSHARD{}: "UNSHARD"
    case OpsREDUCE{}: "REDUCE"
    case OpsALLREDUCE{}: "ALLREDUCE"
    case OpsPYLITERAL{}: "PYLITERAL"

# `self.op.value` -- the IntEnum number, which `UOp.tuplize` puts in the sort
# key. `_generate_next_value_` makes it 1 + the max over every FastEnum, and
# Ops is the only one, so it is the declaration order starting at 1.
def Ops.value(op: Op) -> U32:
  match op:
    case OpsSPECIAL{}: 1
    case OpsBUFFER{}: 2
    case OpsALLOC{}: 3
    case OpsNOOP{}: 4
    case OpsREWRITE_ERROR{}: 5
    case OpsPARAM{}: 6
    case OpsCALL{}: 7
    case OpsPROGRAM{}: 8
    case OpsLINEAR{}: 9
    case OpsSOURCE{}: 10
    case OpsBINARY{}: 11
    case OpsSINK{}: 12
    case OpsAFTER{}: 13
    case OpsGROUP{}: 14
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
    case OpsRECIPROCAL{}: 28
    case OpsNEG{}: 29
    case OpsTRUNC{}: 30
    case OpsADD{}: 31
    case OpsMUL{}: 32
    case OpsSHL{}: 33
    case OpsSHR{}: 34
    case OpsCDIV{}: 35
    case OpsMAX{}: 36
    case OpsCMOD{}: 37
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
    case OpsFLOORDIV{}: 48
    case OpsFLOORMOD{}: 49
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
    case OpsFLIP{}: 73
    case OpsUNSHARD{}: 74
    case OpsREDUCE{}: 75
    case OpsALLREDUCE{}: 76
    case OpsPYLITERAL{}: 77

def GroupOp.unary(op: Op) -> Bool:
  match op:
    case OpsEXP2{}: True{}
    case OpsLOG2{}: True{}
    case OpsSIN{}: True{}
    case OpsSQRT{}: True{}
    case OpsRECIPROCAL{}: True{}
    case OpsNEG{}: True{}
    case OpsTRUNC{}: True{}
    case _: False{}

def GroupOp.binary(op: Op) -> Bool:
  match op:
    case OpsADD{}: True{}
    case OpsMUL{}: True{}
    case OpsCDIV{}: True{}
    case OpsMAX{}: True{}
    case OpsCMOD{}: True{}
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
    case OpsFLOORDIV{}: True{}
    case OpsFLOORMOD{}: True{}
    case _: False{}

def GroupOp.ternary(op: Op) -> Bool:
  match op:
    case OpsWHERE{}: True{}
    case OpsMULACC{}: True{}
    case _: False{}

def GroupOp.defines(op: Op) -> Bool:
  match op:
    case OpsPARAM{}: True{}
    case OpsBUFFER{}: True{}
    case OpsALLOC{}: True{}
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
    case OpsFLIP{}: True{}
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

# set.union(Unary, Binary, Ternary) and set.union(Binary, Ternary) are written as
# the union they are and not as a fourth table, so a derived set cannot drift
# from the sets it is built out of.  # TODO: is BITCAST always Elementwise
# if it's shape changing?
def GroupOp.alu(+op: Op) -> Bool:
  Bool.or(GroupOp.unary(op), Bool.or(GroupOp.binary(op), GroupOp.ternary(op)))

def GroupOp.broadcastable(+op: Op) -> Bool:
  Bool.or(GroupOp.binary(op), GroupOp.ternary(op))

def GroupOp.elementwise(op: Op) -> Bool:
  match op:
    case OpsCAST{}: True{}
    case OpsBITCAST{}: True{}
    case _: GroupOp.alu(op)

# ===========================================================================
# AxisType -- tinygrad/uop/ops.py:17
#
# `def __repr__(self): return str(self)` in the Python, which exists only so a
# range's arg prints as a name. `Ops.RANGE`'s arg is `(axis_id, axis_type)`, so
# the type is a field of the arg and has to be a datatype here; `Ops.name` is
# the same trick one level up.
# ===========================================================================

type AxisType is Data:
  AXIS_DEVICE{}
  AXIS_GLOBAL{}
  AXIS_WARP{}
  AXIS_LOCAL{}
  AXIS_WEAK{}
  AXIS_REDUCE{}
  AXIS_UPCAST{}
  AXIS_UNROLL{}
  AXIS_PLACEHOLDER{}
  AXIS_LOOP{}

def AxisType.name(a: AxisType) -> String:
  match a:
    case AXIS_DEVICE{}: "DEVICE"
    case AXIS_GLOBAL{}: "GLOBAL"
    case AXIS_WARP{}: "WARP"
    case AXIS_LOCAL{}: "LOCAL"
    case AXIS_WEAK{}: "WEAK"
    case AXIS_REDUCE{}: "REDUCE"
    case AXIS_UPCAST{}: "UPCAST"
    case AXIS_UNROLL{}: "UNROLL"
    case AXIS_PLACEHOLDER{}: "PLACEHOLDER"
    case AXIS_LOOP{}: "LOOP"

# `AxisType` is an `auto()` Enum, so its value is its declaration order, exactly
# as `Ops.value` below. `range_str` does not read it, but the ucache key and
# `eq_axis` do, and it is the same number Python has.
def AxisType.value(a: AxisType) -> U32:
  match a:
    case AXIS_DEVICE{}: 1
    case AXIS_GLOBAL{}: 2
    case AXIS_WARP{}: 3
    case AXIS_LOCAL{}: 4
    case AXIS_WEAK{}: 5
    case AXIS_REDUCE{}: 6
    case AXIS_UPCAST{}: 7
    case AXIS_UNROLL{}: 8
    case AXIS_PLACEHOLDER{}: 9
    case AXIS_LOOP{}: 10

# axis_letters / axis_colors / axis_to_pos -- ops.py:49,51,55. Three
# dictionaries keyed by an Enum; three `match` ladders here. PLACEHOLDER is in
# the enum and in none of the three tables, which is why each ladder needs a
# `_` arm: Python's would raise KeyError, and these answer "" / 0.
def axis_letters(a: AxisType) -> String:
  match a:
    case AXIS_DEVICE{}: "d"
    case AXIS_GLOBAL{}: "g"
    case AXIS_LOCAL{}: "l"
    case AXIS_WARP{}: "w"
    case AXIS_WEAK{}: "L"
    case AXIS_LOOP{}: "L"
    case AXIS_UPCAST{}: "u"
    case AXIS_REDUCE{}: "R"
    case AXIS_UNROLL{}: "r"
    case _: ""

def axis_colors(a: AxisType) -> String:
  match a:
    case AXIS_DEVICE{}: "green"
    case AXIS_GLOBAL{}: "blue"
    case AXIS_LOCAL{}: "cyan"
    case AXIS_WARP{}: "CYAN"
    case AXIS_WEAK{}: "WHITE"
    case AXIS_LOOP{}: "WHITE"
    case AXIS_UPCAST{}: "yellow"
    case AXIS_REDUCE{}: "red"
    case AXIS_UNROLL{}: "magenta"
    case _: ""

# axis_to_pos: DEVICE is -2, WEAK and LOOP are -1, everything else counts up
# from 0. The negative ranks put a DEVICE axis before a GLOBAL one in a sort.
# Bend has no signed integer, so the value is a sign flag and a magnitude.
type Pos is Data:
  Pos{neg: Bool, mag: U32}

def axis_to_pos(a: AxisType) -> Pos:
  match a:
    case AXIS_DEVICE{}: Pos{True{}, 2}
    case AXIS_WEAK{}: Pos{True{}, 1}
    case AXIS_LOOP{}: Pos{True{}, 1}
    case AXIS_GLOBAL{}: Pos{False{}, 0}
    case AXIS_WARP{}: Pos{False{}, 1}
    case AXIS_LOCAL{}: Pos{False{}, 2}
    case AXIS_UPCAST{}: Pos{False{}, 3}
    case AXIS_REDUCE{}: Pos{False{}, 4}
    case AXIS_UNROLL{}: Pos{False{}, 5}
    case _: Pos{False{}, 0}

# range_start -- ops.py:58. `range_start[self.op]` is a slice offset, so it is
# a ladder and Python's KeyError is the `case _` arm.
def range_start(op: Op) -> U32:
  match op:
    case OpsSTAGE{}: 1
    case OpsREDUCE{}: 1
    case OpsEND{}: 1
    case OpsCALL{}: 1
    case OpsLINEAR{}: 0
    case _: 0

# ===========================================================================
# Const -- tinygrad/dtype.py: `PyConst = float|int|bool`, and `InvalidType` is
# a singleton, so `ConstType = PyConst|InvalidType`.
#
# THE ORDER MATTERS in `dtype_from_uop`'s CONST arm, which says so in Python:
# "order matters: bool is an int subclass, ConstFloat is a float subclass". The
# ladder there is written in the same order.
#
# ints are `H.I64`, Python's unbounded int under the port's 64-bit cap, because
# a CONST carries -1 and 2**40 and a U32 has neither.
# ===========================================================================

type Const is Data:
  CBool{b: Bool}
  CInt{i: H.I64}
  CFloat{f: F32}
  CInvalid{}

# `Sint` is ops.py:1925's `sint = int|UOp`, spelled out. It is the element type
# of every shape in this file, so the distinction between "the literal 4" and
# "the uop that may be 4" survives into the arena, which is exactly what
# `_shape`'s `isinstance(ps[-1], int)` and `_min_max`'s `isinstance(s0_vmin,
# int)` tests read.
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

# TWO PYTHON TUPLES, AS RECORDS. `Maybe<&2, A & B>` is a `Type`, not a `Data`,
# so it cannot be a field of a `Data` record; a one-field record is the
# equivalent, and both of these are read in exactly one place each.
#
# `vmin_vmax: tuple[PyConst, PyConst]|None` -- (min, max) of a Variable's value
# range. It is `H.I64` on both halves because PyConst is the wider of the two
# (`_min_max` returns PyConst and every reader of a range bound wants a number).
type PyRange is Data:
  PyRange{lo: H.I64, hi: H.I64}

# `image: tuple[int, int]|None` -- (h, w) if this is an image2d buffer, then
# size == h*w*4. `_shape`'s BUFFER arm reads it.
type Img is Data:
  Img{h: U32, w: U32}

# ===========================================================================
# ParamArg -- tinygrad/uop/ops.py:22
#
# The `arg` of a BUFFER, ALLOC or PARAM: thirteen fields, nine of them optional.
# Python's `X|None` is a union with None, so each one is a `Maybe` here and
# every Python field comment is kept.
#
# TWO FIELDS ARE NOT WHAT THE NAME SAYS IN BEND, for the same reason: both hold
# a Python object this port has not built, and a handle is a `Type` so it cannot
# be a `Data` field.
#   * `buffer: Buffer|MultiBuffer|None` -- the 1:1 UOp/Buffer pairing. It is a
#     `Maybe<&1, U32>` slot into the device allocator, which is P6. It is a real
#     slot, not a placeholder: `UOp.buffer`, `UOp.realized` and the ucache key
#     all read it.
#   * `device: str|tuple[str, ...]|None` -- a device NAME or a tuple of them, so
#     it is `S.Dev` (spec.bend's `D1{tag}` / `Dn{tags}`) with a `U32` tag per
#     name interned by the runtime. `Device.tag` below is where the P6 device
#     table plugs in.
# ===========================================================================

type ParamArg is Data:
  ParamArg{slot: U32, dtype: S.Dt,
    # number of elements in the buffer. always a concrete int (never symbolic), None for scalars (shape ())
    size: Maybe<&2, U32>,
    vmin_vmax: Maybe<&2, PyRange>,
    multiple_of: Maybe<&2, U32>,
    name: Maybe<&2, String>,
    addrspace: S.Addr,
    device: Maybe<&2, S.Dev>,
    volatile: Bool,
    # (h, w) if this is an image2d buffer, then size == h*w*4
    image: Maybe<&2, Img>,
    # the device Buffer for a realized BUFFER. the UOp is the owner of the Buffer: they live and die together (1:1)
    buffer: Maybe<&2, U32>,
    bind_on_realize: Bool,
    # the bound value of a Variable (an ALU PARAM with a value range); None means unbound
    val: Maybe<&2, Const>}

# ===========================================================================
# Arg -- the `arg: Any` field -- and Tag -- the `tag: Any` field.
#
# `Any` is Python's way of saying "this field holds eighteen unrelated things
# and the reader has to know which". The eighteen, with the ops.py line each
# comes from:
#
#   None                    ANone      the default; SINK/STAGE arg is None
#   DType                   ADt        CAST/BITCAST arg; INS arg[1]
#   PyConst|InvalidType     APy        CONST arg
#   ParamArg                AParam     BUFFER/ALLOC/PARAM arg
#   CallInfo                ACall      CALL arg
#   KernelInfo              AKernel    SINK arg
#   ProgramInfo             AProgram   PROGRAM arg
#   (axis_id, axis_type)    ARange     RANGE arg
#   (Ops, int)              AReduce    REDUCE arg
#   (dims, DType, threads, tc_upcast_axes)   AWmma   WMMA arg
#   tuple[int, ...]         ATuple     PERMUTE/FLIP arg, UNSHARD arg,
#                                     MSELECT arg, PYLITERAL arg
#   str                     AStr       SPECIAL name, SOURCE text, CUSTOM text,
#                                     CUSTOM_FUNCTION name
#   (str, DType)            AInk       INS arg
#   (Ops, str|tuple)        AAllred    ALLREDUCE arg
#   str|tuple               ADev       COPY arg
#   bytes                   ABlob      BINARY arg; only its length is read
#   float                   AFloat     the one bare float, for `_frompy`'s
#                                     `assert bdtype.fmt is not None` path
#   -- and one this port adds, see Arena.bottom
#   (never interned)        ABad       the arena's bottom: what a read of an
#                                     index that was never interned answers
#
# WHAT WE GAIN, and it is the reason this is a datatype rather than an opaque
# word: `dtype_from_uop`, `_shape`, `_min_max` and `addrspace` all read
# `self.arg`, and each of those reads is now a match the compiler checks against
# the full set. In Python a wrong arm is an `AttributeError` at 3am on a GPU.
# ===========================================================================

type Arg is Data:
  ANone{}
  ADt{dt: S.Dt}
  APy{v: Const}
  AParam{pa: ParamArg}
  ACall{ci: CallInfo}
  AKernel{ki: KernelInfo}
  AProgram{pi: ProgramInfo}
  ARange{ids: List<&2, U32>, at: AxisType}
  AReduce{rop: Op, num_axes: U32}
  AWmma{dims: List<&2, U32>, dt: S.Dt, threads: U32, tc: List<&2, U32>}
  ATuple{ys: List<&2, U32>}
  AStr{s: String}
  AInk{ins: String, dt: S.Dt}
  AAllred{rop: Op, dev: S.Dev}
  ADev{dev: S.Dev}
  ABlob{n: U32}
  AFloat{f: F32}
  ABad{}

# Tag is `Any` too, and a much smaller one: ops.py reads it in `rtag` (True, a
# str, an int), in `trace_num` (`isinstance(self.tag, tuple)`) and in
# `remove_all_tags` (`x.tag is not None`).
#
# A tag tuple holds UOPS, so it holds their INDICES: ops.py:547 says "tags can
# contain UOps (callify tags nodes with their originals)" and `trace_num` walks
# them replacing each with its number. `List<&2, U32>` is therefore both the
# faithful reading and the one that keeps `eq_tag` a leaf -- a `List<&2, Tag>`
# would make `eq_tag` and `eq_tags` mutually recursive, and Bend refuses that.
type Tag is Data:
  TNone{}
  TBool{b: Bool}
  TStr{s: String}
  TInt{i: U32}
  TTuple{xs: List<&2, U32>}

# ===========================================================================
# The three arg payloads, moved UP from ops.py:1339-1404.
#
# They are moved because `Arg` holds them and `eq_arg` -- the ucache key --
# compares them, and Bend resolves a call at compile time while Python resolves
# a lambda at call time. Their order AMONG THEMSELVES is Python's: KernelInfo,
# ProgramInfo, OPAQUE_CALL_BODIES, CallInfo. The METHODS of ProgramInfo
# (`launch_dims`, `vals`, `from_sink`) stay down at ops.py's position, because
# they read UOps.
# ===========================================================================

# KernelInfo -- ops.py:1339. `estimates: Estimates|None` is NOT PORTED:
# `Estimates` is `tinygrad.renderer`'s cost model, P5. A field the port cannot
# read is a field that would silently always be None.
type KernelInfo is Data:
  KernelInfo{name: String, applied_opts: List<&2, U32>, opts_to_apply: Maybe<&2, List<&2, U32>>, beam: U32}

def KernelInfo.of() -> KernelInfo:
  # name: str = "test"            # name of the kernel
  KernelInfo{"test", Nil{}, None{}, 0}

# ProgramInfo -- ops.py:1349. `target: Target` is NOT PORTED: `Target` is
# helpers.py's device-target record and helpers.bend lists it as P6 ("it exists
# to parse DEV, and DEV only exists once there is a device to point at"). So
# `from_sink` drops its `target` parameter and the field goes with it. The other
# six are ported. `global_size` is `tuple[int|float, ...]`, so its elements are
# `H.I64`: an int is an I64 and a float is not a shape, so the float case in
# `sym_infer` is recorded on `sym_infer` itself.
type ProgramInfo is Data:
  ProgramInfo{global_size: List<&2, H.I64>, local_size: List<&2, H.I64>, vars: List<&2, U32>, globals: List<&2, U32>, outs: List<&2, U32>, ins: List<&2, U32>}

def ProgramInfo.of() -> ProgramInfo:
  ProgramInfo{[H.i64_of_i32(1), H.i64_of_i32(1), H.i64_of_i32(1)], [H.i64_of_i32(1), H.i64_of_i32(1), H.i64_of_i32(1)], Nil{}, Nil{}, Nil{}, Nil{}}

# `var_vals: dict[str, int]` -- a `Map` is string-keyed in Bend, which is the
# one place Python's dict and Bend's Map agree without an encoding, so it is
# used directly. `Map` is a `Type`, so it is affine and threaded, exactly like
# the arena.
type VarVals is Type:
  VarVals{m: Map<&2, H.I64>}

def VarVals.new() -> VarVals:
  VarVals{Map.new(&2, H.I64)}

# the body of a CALL is always one of these: programs (SINK/PROGRAM/LINEAR), bulk stores, and function references
# OPAQUE_CALL_BODIES = {Ops.SINK, Ops.PROGRAM, Ops.LINEAR, Ops.STORE, Ops.CUSTOM_FUNCTION}
def GroupOp.opaque_call_bodies(op: Op) -> Bool:
  match op:
    case OpsSINK{}: True{}
    case OpsPROGRAM{}: True{}
    case OpsLINEAR{}: True{}
    case OpsSTORE{}: True{}
    case OpsCUSTOM_FUNCTION{}: True{}
    case _: False{}

# CallInfo -- ops.py:1391. TWO FIELDS DROPPED, and both for the same reason:
#   * `grad_fxn: Callable|None` is a Python function object. Bend has no
#     function values except a closure, and a closure is single-use and is a
#     `Type`, so it cannot be a `Data` field. The reverse-mode plumbing that
#     calls it is tinygrad/nn/gradient.py, P7.
#   * `aux: Any` is the per-call side channel, written by the hcq paths in
#     tinygrad/runtime/ops_*.py, which are out of scope (P6, hardware we do not
#     have). Nothing in this file reads it except `__reduce__`.
# `dtype: DType = dtypes.void` is the (possibly void) return dtype and IS read:
# by `dtype_from_uop`'s CALL arm and by `_shape`'s.
type CallInfo is Data:
  CallInfo{name: Maybe<&2, String>, precompile: Bool, precompile_backward: Bool, dtype: S.Dt}

def CallInfo.of() -> CallInfo:
  CallInfo{None{}, False{}, False{}, S.void()}

# `CallInfo.__repr__` (ops.py:1401) is at the end of the equality block, because it
# compares against `S.void()` and `eq_dt` is what does the comparing.

# ===========================================================================
# THE ARENA.
#
# `Node` is `UOp`'s four fields and adds nothing: `op`, `src`, `arg`, `tag`. The
# arena IS the ucache and the node table at once, because in Bend they are the
# same thing -- a UOp is an index into a list of nodes, and a hash-cons hit is
# "a node with this key is already in the list".
#
# INDEX 0 IS RESERVED. `Arena.empty` starts with one node in it, the bottom, so
# every U32 is a valid index and 0 is this port's spelling of both Python's
# `None` UOp and the IndexError that `self.src[0]` on an empty src raises.
# `UOp.is_none` is the test, and it is the only place a UOp index is compared
# against a constant.
#
# The `Metadata` side table (`all_metadata`, ops.py:215) is NOT a second store.
# Python keeps it in a `WeakKeyDictionary` beside the arena so that replacing a
# UOp drops its metadata; the arena is monotone and has no weakrefs, so metadata
# is a field of the node and `UOp.replace` does not carry it over, which is the
# behaviour Python gets from the weakref dying.
# ===========================================================================

type Node is Data:
  Node{op: Op, src: List<&2, U32>, arg: Arg, tag: Tag}

type Arena is Data:
  Arena{nodes: List<&2, Node>}

# ===========================================================================
# ACCESSORS, and the ONE shape rule everything below follows. Bend 2.0.34 has no
# projection syntax -- `n.f` parses as a NAME lookup and fails -- and a `match`
# may only scrutinise a PARAMETER or a pattern binder, never a projection and
# never a `let`-bound name. So a property reader is always TWO defs:
#
#     def UOp.dtype(ar: Arena, self: U32) -> Dt:            # the arena read
#       UOp.dtype.node(ar, Arena.node(ar, self))
#
#     def UOp.dtype.node(ar: Arena, nd: Node) -> Dt:        # one match, four binders
#       match nd:
#         case Node{op, src, arg, tag}: <the Python body, destructuring op>
#
# and the nested records need no accessors at all, because a pattern binder IS a
# legal scrutinee: `case AParam{pa}: match pa: case ParamArg{vmin_vmax}: ...` is
# the Python `self.arg.vmin_vmax` in three lines. That is the whole trick and it
# is why this file is not accessor soup.
# ===========================================================================

def Arena.nodes(x: Arena) -> List<&2, Node>:
  match x:
    case Arena{nodes}: nodes

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

# THE BOTTOM. No srcs, an `ABad` arg, no tag, so every derived property answers
# void / None / () for it: it is inert, and a program that reaches it has asked
# the arena for a node that was never interned.
def Arena.bottom() -> Node:
  Node{OpsNOOP{}, Nil{}, ABad{}, TNone{}}

# the arena starts with the bottom at index 0, so `Arena.next` is
# `next(UOp.unique_num)` with the first slot already spent.
def Arena.empty() -> Arena:
  Arena{[Arena.bottom()]}

# `UOp.unique_num = itertools.count(0)` is a monotonic slot counter that
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

# `Arena.at` is the dict lookup: None for an index that was never interned.
def Arena.at(ar: Arena, i: U32) -> Maybe<&1, Node>:
  Arena.at.go(Arena.nodes(ar), U32.to_nat(i))

# `Arena.node` is `at(i)` or `bottom`, and it is TOTAL, which is what keeps the
# property readers below from threading a Maybe through everything.
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

# `self.src[i]` -- the fold, with 0 (the bottom) for the IndexError Python
# raises when the tuple is short. `Arena.src0` is the `src[0]` the Python
# writes most, because it is written most.
def Arena.src(ar: Arena, i: U32, n: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, Node.src(Arena.node(ar, i)), U32.to_nat(n)), 0)

def Arena.src0(ar: Arena, i: U32) -> U32:
  Arena.src(ar, i, 0)

def Arena.nsrc(ar: Arena, i: U32) -> U32:
  U32.from_nat(List.length(&2, U32, Node.src(Arena.node(ar, i))))

# `self.src[k:]` and `self.src[:k]` -- `range_start`, `ended_ranges` and
# `src_without_body` all slice, so the slice is a def rather than a fold at
# each site.
def Arena.src_from.go(xs: List<&2, U32>, k: Nat) -> List<&2, U32>:
  match xs k:
    case Nil{} 0n: Nil{}
    case Nil{} 1n+p: Nil{}
    case h <> t 0n: t
    case h <> t 1n+p: h <> Arena.src_from.go(t, p)

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
# `self.src` otherwise, so it needs the op as well as the srcs.
def Arena.src_without_body.op(op: Op, src: List<&2, U32>) -> List<&2, U32>:
  match op:
    case OpsCALL{}: Arena.src_from.go(src, 1n)
    case _: src

def Arena.src_without_body.node(nd: Node) -> List<&2, U32>:
  match nd:
    case Node{op, src, arg, tag}: Arena.src_without_body.op(op, src)

def Arena.src_without_body(ar: Arena, i: U32) -> List<&2, U32>:
  Arena.src_without_body.node(Arena.node(ar, i))

# ===========================================================================
# The remaining field accessors, for the record types declared above. Same two
# lines each; they exist because Bend has no `x.field`, not because they carry
# any meaning.
# ===========================================================================

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
    case ParamArg{slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: slot

def ParamArg.dtype(x: ParamArg) -> S.Dt:
  match x:
    case ParamArg{slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: dtype

def ParamArg.size(x: ParamArg) -> Maybe<&2, U32>:
  match x:
    case ParamArg{slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: size

def ParamArg.vmin_vmax(x: ParamArg) -> Maybe<&2, PyRange>:
  match x:
    case ParamArg{slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: vmin_vmax

def ParamArg.multiple_of(x: ParamArg) -> Maybe<&2, U32>:
  match x:
    case ParamArg{slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: multiple_of

def ParamArg.name(x: ParamArg) -> Maybe<&2, String>:
  match x:
    case ParamArg{slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: name

def ParamArg.addrspace(x: ParamArg) -> S.Addr:
  match x:
    case ParamArg{slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: addrspace

def ParamArg.device(x: ParamArg) -> Maybe<&2, S.Dev>:
  match x:
    case ParamArg{slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: device

def ParamArg.volatile(x: ParamArg) -> Bool:
  match x:
    case ParamArg{slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: volatile

def ParamArg.image(x: ParamArg) -> Maybe<&2, Img>:
  match x:
    case ParamArg{slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: image

def ParamArg.buffer(x: ParamArg) -> Maybe<&2, U32>:
  match x:
    case ParamArg{slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: buffer

def ParamArg.bind_on_realize(x: ParamArg) -> Bool:
  match x:
    case ParamArg{slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: bind_on_realize

def ParamArg.val(x: ParamArg) -> Maybe<&2, Const>:
  match x:
    case ParamArg{slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: val

# ParamArg -- ops.py:23's constructor with every default the dataclass declares.
def ParamArg.of(slot: U32, dtype: S.Dt) -> ParamArg:
  # size: int|None = None
  # vmin_vmax: tuple[PyConst, PyConst]|None = None
  # multiple_of: int|None = None
  # name: str|None = None
  # addrspace: AddrSpace|None = AddrSpace.GLOBAL
  # device: str|tuple[str, ...]|None = None
  # volatile: bool = False
  # image: tuple[int, int]|None = None
  # buffer: Buffer|MultiBuffer|None = None
  # bind_on_realize: bool = False
  # val: PyConst|None = None
  ParamArg{slot, dtype, None{}, None{}, None{}, None{}, S.AGlobal{}, None{}, False{}, None{}, None{}, False{}, None{}}

def KernelInfo.name(x: KernelInfo) -> String:
  match x:
    case KernelInfo{name, applied_opts, opts_to_apply, beam}: name

def KernelInfo.applied_opts(x: KernelInfo) -> List<&2, U32>:
  match x:
    case KernelInfo{name, applied_opts, opts_to_apply, beam}: applied_opts

def KernelInfo.opts_to_apply(x: KernelInfo) -> Maybe<&2, List<&2, U32>>:
  match x:
    case KernelInfo{name, applied_opts, opts_to_apply, beam}: opts_to_apply

def KernelInfo.beam(x: KernelInfo) -> U32:
  match x:
    case KernelInfo{name, applied_opts, opts_to_apply, beam}: beam

# `to_function_name` is NOT PORTED, so `function_name` is the name unchanged.
# helpers.py:156 is `''.join([c if c in (letters+digits+'_') else
# f'{ord(c):02X}' for c in ansistrip(s)])` and `ansistrip` is one of the regex
# helpers helpers.bend already lists as not-ported ("string, regex and
# reflection helpers for the interpreter-facing surfaces"), because it exists to
# make renderer symbol names printable. Getting it wrong renames every generated
# kernel, so it waits for P5 with the renderer. The def is kept so KernelInfo
# keeps Python's shape, and it sits HERE rather than at ops.py:1347 because it
# reads a field and this is where the field accessors are.
def KernelInfo.function_name(x: KernelInfo) -> String:
  KernelInfo.name(x)

def ProgramInfo.global_size(x: ProgramInfo) -> List<&2, H.I64>:
  match x:
    case ProgramInfo{global_size, local_size, vars, globals, outs, ins}: global_size

def ProgramInfo.local_size(x: ProgramInfo) -> List<&2, H.I64>:
  match x:
    case ProgramInfo{global_size, local_size, vars, globals, outs, ins}: local_size

def ProgramInfo.vars(x: ProgramInfo) -> List<&2, U32>:
  match x:
    case ProgramInfo{global_size, local_size, vars, globals, outs, ins}: vars

def ProgramInfo.globals(x: ProgramInfo) -> List<&2, U32>:
  match x:
    case ProgramInfo{global_size, local_size, vars, globals, outs, ins}: globals

def ProgramInfo.outs(x: ProgramInfo) -> List<&2, U32>:
  match x:
    case ProgramInfo{global_size, local_size, vars, globals, outs, ins}: outs

def ProgramInfo.ins(x: ProgramInfo) -> List<&2, U32>:
  match x:
    case ProgramInfo{global_size, local_size, vars, globals, outs, ins}: ins

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
# ===========================================================================
# Equality. Bend has no `==` on Data, so the ucache key needs one comparison per
# component. `UOpMetaClass.__call__` keys on
# `(op, src, arg, tag, type(arg))` and the NOTE there says why the dtype has to
# be separated: "a CONST's dtype is the type of its arg, and True == 1 as dict
# keys". The Arg CONSTRUCTOR is `type(arg)` here, so the key separates them for
# the same reason and for free -- one thing this encoding gets right that a bare
# U32 tag would not.
#
# A `match` may take two scrutinees, which is what makes a two-constructor type
# (Maybe, List) a four-arm ladder. Arg has eighteen constructors, so its 18x18 is
# a nested match: first on `x`, then a two-arm ladder on `y` inside each arm, with
# `x`'s own fields passed in as parameters because an arm may not see them.
# That is the same shape spec.bend uses in `Shape.max_dim`, and it is why
# `eq_arg` is nineteen defs and not three hundred and sixty-one arms.
# ===========================================================================

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

def KernelInfo.eq_opts(x: Maybe<&2, List<&2, U32>>, y: Maybe<&2, List<&2, U32>>) -> Bool:
  match x y:
    case None{} None{}: True{}
    case Some{a} Some{b}: eq_u32(a, b)
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

def eq_cls.sel(x: S.Cls, y: S.Cls) -> Bool:
  match x:
    case S.CVoid{}: eq_cls.CVoid(x, y)
    case S.CWeakInt{}: eq_cls.CWeakInt(x, y)
    case S.CBool{}: eq_cls.CBool(x, y)
    case S.CUint{}: eq_cls.CUint(x, y)
    case S.CSint{}: eq_cls.CSint(x, y)
    case _: eq_cls.CFloat(x, y)

def eq_cls(x: S.Cls, y: S.Cls) -> Bool:
  eq_cls.sel(x, y)

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
    case _:
      match y:
        case S.AReg{}: True{}
        case _: False{}

def eq_dt(x: S.Dt, y: S.Dt) -> Bool:
  match x y:
    case S.Dt{pri, bits, cls, nm} S.Dt{p2, b2, c2, n2}:
      Bool.and(U32.is_eq(pri, p2), Bool.and(U32.is_eq(bits, b2),
        Bool.and(eq_cls(cls, c2), String.eq(nm, n2))))

# AxisType is an auto() Enum in Python, so its value is its declaration order,
# exactly like Ops. That is the whole of eq_axis.

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
    case CFloat{g}: F32.is_eq(f, g)
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

# ParamArg -- the 13-field dataclass of ops.py:23. A record of records, so the
# comparison is the conjunction of the field comparisons; nothing is skipped.

def eq_paramarg(x: ParamArg, y: ParamArg) -> Bool:
  match x y:
    case ParamArg{slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val} ParamArg{s2, d2, z2, v2, m2, n2, a2, dv2, vo2, i2, b2, br2, w2}:
      Bool.and(U32.is_eq(slot, s2), Bool.and(eq_dt(dtype, d2),
        Bool.and(eq_opt_u32(size, z2), Bool.and(eq_opt_pyrange(vmin_vmax, v2),
        Bool.and(eq_opt_u32(multiple_of, m2), Bool.and(eq_opt_str(name, n2),
        Bool.and(eq_addr(addrspace, a2), Bool.and(eq_opt_dev(device, dv2),
        Bool.and(eq_bool(volatile, vo2), Bool.and(eq_opt_img(image, i2),
        Bool.and(eq_opt_u32(buffer, b2), Bool.and(eq_bool(bind_on_realize, br2),
          eq_opt_const(val, w2)))))))))))))

def eq_kernelinfo(x: KernelInfo, y: KernelInfo) -> Bool:
  match x y:
    case KernelInfo{name, applied_opts, opts_to_apply, beam} KernelInfo{n2, o2, p2, b2}:
      Bool.and(String.eq(name, n2), Bool.and(eq_u32(applied_opts, o2),
        Bool.and(KernelInfo.eq_opts(opts_to_apply, p2), U32.is_eq(beam, b2))))

def eq_programinfo(x: ProgramInfo, y: ProgramInfo) -> Bool:
  match x y:
    case ProgramInfo{global_size, local_size, vars, globals, outs, ins} ProgramInfo{g2, l2, v2, b2, o2, i2}:
      Bool.and(eq_i64s(global_size, g2), Bool.and(eq_i64s(local_size, l2),
        Bool.and(eq_u32(vars, v2), Bool.and(eq_u32(globals, b2),
        Bool.and(eq_u32(outs, o2), eq_u32(ins, i2))))))

def eq_callinfo(x: CallInfo, y: CallInfo) -> Bool:
  match x y:
    case CallInfo{name, precompile, precompile_backward, dtype} CallInfo{n2, p2, b2, d2}:
      Bool.and(eq_opt_str(name, n2), Bool.and(eq_bool(precompile, p2),
        Bool.and(eq_bool(precompile_backward, b2), eq_dt(dtype, d2))))

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

def eq_arg.AWmma(y: Arg, +dims: List<&2, U32>, +dt: S.Dt, +threads: U32, +tc: List<&2, U32>) -> Bool:
  match y:
    case AWmma{y1, y2, y3, y4}: Bool.and(eq_u32(dims, y1), Bool.and(eq_dt(dt, y2), Bool.and(U32.is_eq(threads, y3), eq_u32(tc, y4))))
    case _: False{}

def eq_arg.ATuple(y: Arg, +ys: List<&2, U32>) -> Bool:
  match y:
    case ATuple{y1}: eq_u32(ys, y1)
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

def eq_arg.ABlob(y: Arg, +n: U32) -> Bool:
  match y:
    case ABlob{y1}: U32.is_eq(n, y1)
    case _: False{}

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
    case ACall{ci}: eq_arg.ACall(y, ci)
    case AKernel{ki}: eq_arg.AKernel(y, ki)
    case AProgram{pi}: eq_arg.AProgram(y, pi)
    case ARange{ids, at}: eq_arg.ARange(y, ids, at)
    case AReduce{rop, num_axes}: eq_arg.AReduce(y, rop, num_axes)
    case AWmma{dims, dt, threads, tc}: eq_arg.AWmma(y, dims, dt, threads, tc)
    case ATuple{ys}: eq_arg.ATuple(y, ys)
    case AStr{s}: eq_arg.AStr(y, s)
    case AInk{ins, dt}: eq_arg.AInk(y, ins, dt)
    case AAllred{rop, dev}: eq_arg.AAllred(y, rop, dev)
    case ADev{dev}: eq_arg.ADev(y, dev)
    case ABlob{n}: eq_arg.ABlob(y, n)
    case AFloat{f}: eq_arg.AFloat(y, f)
    case ABad{}: eq_arg.ABad(y)

def eq_arg(x: Arg, y: Arg) -> Bool:
  eq_arg.sel(x, y)

def eq_tag.TNone(y: Tag) -> Bool:
  match y:
    case TNone{}: True{}
    case _: False{}

def eq_tag.TBool(y: Tag, +b: Bool) -> Bool:
  match y:
    case TBool{y1}: eq_bool(b, y1)
    case _: False{}

def eq_tag.TStr(y: Tag, +s: String) -> Bool:
  match y:
    case TStr{y1}: String.eq(s, y1)
    case _: False{}

def eq_tag.TInt(y: Tag, +i: U32) -> Bool:
  match y:
    case TInt{y1}: U32.is_eq(i, y1)
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

# ===========================================================================
# UOpMetaClass.__call__ -- ops.py:196-212. THE CONSTRUCTOR.
#
# `ucache.get(key) or super().__call__(...)` is one lookup and one append, and
# in an arena the lookup IS a scan for a node with the same key, because the
# arena IS the cache. That is the whole of `intern`. The difference from Python
# is cost, not meaning: a dict is O(1) and a list scan is O(n), so constructing
# the n-th node costs n key comparisons.
#
# TWO CALLS, NOT ONE RETURNING A PAIR, and this is forced rather than chosen.
# `intern` has to return both the arena and the index, so its return type is
# `Arena & U32` -- and a pair can only be destructured when it is a PARAMETER:
# `(a, i) = intern(...)` on a `let`-bound name is refused with "a match cannot
# scrutinise a local binder". So the construction is two calls on the same key,
# `UOp.put` to grow and `UOp.of` to read the index back, and the key is written
# twice. That is the price of no mutable store, and it is paid once per node
# rather than once per read.
#
# `__del__`, the ucache eviction, needs no comment of its own: the arena has no
# destruction, so nothing is evicted, and `UOp.unique_num`'s "must never be
# reset" note is satisfied by construction.
#
# SPEC > 1 -- the `spec_full.rewrite`, the shape check and `test_pyrender` -- is
# the SPEC layer (`tinygrad/uop/spec.py`, P3) and is NOT PORTED here.
# `dtype_from_uop`'s None arm is the same check in the form this port can state,
# and `UOp.spec_ok` is where it gets consulted.
# ONE alternative of `src`. `src=(a, b)` is a tuple -> one exact alternative.
# `src=UPat(...)` is `itertools.repeat(src)`: UNBOUNDED. It is a variant here, not
# an infinite list, because nothing ever enumerates it -- `required_len` and
# `strict_length` are what bound the read, and a list would want a partiality
# this port does not have.
type UpAlt is Data:
  UpFixed{ys: List<&2, U32>}
  UpRepeat{x: U32}

# The four shapes of `__init__`'s `src` argument. TUPLE and LIST are separate
# variants because ops.py:1464 reads the difference: a tuple keeps its order, a
# list is permuted.
type SrcArg is Data:
  SNone{}
  SOne{x: U32}
  STuple{ys: List<&2, U32>}
  SList{ys: List<&2, U32>}

# ops.py:1448. `src_in` is `_in_src`, the RAW argument, which `named` and
# `__reduce__` need to rebuild the pattern unchanged. `location` is NOT PORTED
# (frame introspection, P3) and is deliberately NOT a field: a field the port
# cannot read is a field that would silently always be None.
type UPat is Data:
  UPat{
    op: Maybe<&2, List<&2, Op>>,
    match_dtype: Maybe<&2, List<&2, S.Dt>>,
    match_tag: Maybe<&2, List<&2, Tag>>,
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

# `Found` is the UOp file's `(arena, index)` pair, and its `ar` is specifically
# an `Arena`. A pattern arena is a different type, so it gets the same shape
# under its own name rather than a parameterised `Found` that would touch every
# one of the UOp call sites.
type PatFound is Data:
  PatFound{pat: Pat, i: U32}

# `PatFound` readers, same two-def shape as the UOp accessors above.
def PatFound.pat(f: PatFound) -> Pat:
  match f:
    case PatFound{pat, _}: pat

def PatFound.i(f: PatFound) -> U32:
  match f:
    case PatFound{_, i}: i
# ---------------------------------------------------------------------------
# Accessors. Bend 2.0.34 has no projection syntax and a `match` may not
# scrutinise a computed value, so each field reader is a def -- the same shape
# the UOp accessors above use. Eleven fields, eleven readers; there is no
# shorter spelling that is not a parse error.
# ---------------------------------------------------------------------------

def Pat.upats(pat: Pat) -> List<&2, UPat>:
  match pat:
    case Pat{upats}: upats

def UPat.op(u: UPat) -> Maybe<&2, List<&2, Op>>:
  match u:
    case UPat{op, _, _, _, _, _, _, _, _, _, _}: op

def UPat.match_dtype(u: UPat) -> Maybe<&2, List<&2, S.Dt>>:
  match u:
    case UPat{_, md, _, _, _, _, _, _, _, _, _}: md

def UPat.match_tag(u: UPat) -> Maybe<&2, List<&2, Tag>>:
  match u:
    case UPat{_, _, mt, _, _, _, _, _, _, _, _}: mt

def UPat.arg(u: UPat) -> Maybe<&2, Arg>:
  match u:
    case UPat{_, _, _, a, _, _, _, _, _, _, _}: a

def UPat.name(u: UPat) -> Maybe<&2, String>:
  match u:
    case UPat{_, _, _, _, n, _, _, _, _, _, _}: n

def UPat.src_in(u: UPat) -> SrcArg:
  match u:
    case UPat{_, _, _, _, _, si, _, _, _, _, _}: si

def UPat.src(u: UPat) -> List<&2, UpAlt>:
  match u:
    case UPat{_, _, _, _, _, _, s, _, _, _, _}: s

def UPat.is_any(u: UPat) -> Bool:
  match u:
    case UPat{_, _, _, _, _, _, _, b, _, _, _}: b

def UPat.strict_length(u: UPat) -> Bool:
  match u:
    case UPat{_, _, _, _, _, _, _, _, b, _, _}: b

def UPat.required_len(u: UPat) -> U32:
  match u:
    case UPat{_, _, _, _, _, _, _, _, _, n, _}: n

def UPat.early_reject(u: UPat) -> List<&2, Op>:
  match u:
    case UPat{_, _, _, _, _, _, _, _, _, _, er}: er

# ===========================================================================

def intern.find.pick(hit: Bool, k: U32, +nxt: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match hit:
    case True{}: Some{k}
    case False{}: nxt

# the linear scan. `want` is `+` because the key comparison and the next
# iteration both read it, and a Node is `Data` so the refcount is the only cost.

def intern.find(ns: List<&2, Node>, +k: U32, +want: Node) -> Maybe<&2, U32>:
  match ns:
    case Nil{}:
      None{}
    case nd <> t:
      nxt = intern.find(t, U32.add(k, 1), want)
      intern.find.pick(eq_node(nd, want), k, nxt)

# intern.put: the MISS branch of `ucache.get(key) or ...`, i.e. the append.

def intern.put(+ar: Arena, +want: Node) -> Arena:
  Arena{List.append(&2, Node, Arena.nodes(ar), [want])}

# intern.get: the HIT branch, which hands back the arena untouched.

def intern.get(ar: Arena, hit: Maybe<&2, U32>) -> Maybe<&2, U32>:
  hit

# `UOp.make(ar, op, src, arg, tag)` -- the `UOp(...)` call itself, with Python's
# keyword names flattened into positional ones.

def UOp.make.intern.put(+ar: Arena, hit: Maybe<&2, U32>, +want: Node) -> Arena:
  match hit:
    case Some{i}: ar
    case None{}: intern.put(ar, want)

# and the index of that node, which the Python gets for free because the
# constructor RETURNS the object.

def UOp.make.intern(+ar: Arena, +want: Node) -> Arena:
  UOp.make.intern.put(ar, intern.find(Arena.nodes(ar), 0, want), want)

# The five key parameters are all `+`: the two-call constructor reads the key
# twice, once to intern and once to find the index, and every one of them is
# `Data`, so the refcount is the only cost. This is the one place in the file
# where the arena's "no mutable store" bill comes due on every node.
def UOp.make(+ar: Arena, +op: Op, +src: List<&2, U32>, +arg: Arg, +tag: Tag) -> Arena:
  UOp.make.intern(ar, Node{op, src, arg, tag})

def UOp.of.intern.put(+ar: Arena, hit: Maybe<&2, U32>, +want: Node) -> U32:
  match hit:
    case Some{i}: i
    # a miss appended, so the new index is the one before the end
    case None{}: U32.sub(Arena.next(ar), 1)

# `Metadata` is helpers.py:293's `(name, backward)` record, and ops.py is where
# it is used: the `metadata=` keyword of the constructor and the `metadata`
# property at ops.py:775.

def UOp.of.intern(+ar: Arena, +want: Node) -> U32:
  UOp.of.intern.put(ar, intern.find(Arena.nodes(ar), 0, want), want)

def UOp.of(+ar: Arena, +op: Op, +src: List<&2, U32>, +arg: Arg, +tag: Tag) -> U32:
  UOp.of.intern(ar, Node{op, src, arg, tag})

# ---------------------------------------------------------------------------
# The intern key. Flat fields, plus a list of INDICES -- so this is NOT the
# recursive walk a bare `UPat` would need, and that is the whole point of the
# arena. These are `eq_op_list` and friends, mirroring the `eq_u32` /
# `eq_i64s` / `eq_opt_u32` family already above.
# ---------------------------------------------------------------------------

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

def eq_tag_list(xs: List<&2, Tag>, ys: List<&2, Tag>) -> Bool:
  match xs:
    case Nil{}:
      match ys:
        case Nil{}: True{}
        case _ <> _: False{}
    case x <> t:
      match ys:
        case Nil{}: False{}
        case y <> u: Bool.and(eq_tag(x, y), eq_tag_list(t, u))

# The `Maybe` wrappers. Each unwrap is its own def, so the scrutinee is a
# parameter -- the `intern.find.pick` shape.

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

def eq_opt_tag(x: Maybe<&2, List<&2, Tag>>, y: Maybe<&2, List<&2, Tag>>) -> Bool:
  match x:
    case Some{a}:
      match y:
        case Some{b}: eq_tag_list(a, b)
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

# A 4x4 cross product of the `SrcArg` variants would be sixteen arms; the variant
# is a discriminant and the payload is one list, so it is two. A wildcard arm is
# cons-only (`case _ <> _`), so a `Data` match must name every remaining
# constructor -- which is the whole reason to project instead.
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

# `+` is the SHARE annotation: the tag and the payload are two reads of one
# argument, which is exactly Python's shared reference.
def eq_in_src(+x: SrcArg, +y: SrcArg) -> Bool:
  Bool.and(U32.is_eq(srcarg.tag(x), srcarg.tag(y)), eq_u32(srcarg.ys(x), srcarg.ys(y)))

def eq_upat(x: UPat, y: UPat) -> Bool:
  match x y:
    case UPat{op1, md1, mt1, a1, n1, si1, s1, y1, l1, r1, e1} UPat{op2, md2, mt2, a2, n2, si2, s2, y2, l2, r2, e2}:
      Bool.and(eq_opt_op(op1, op2),
      Bool.and(eq_opt_dt(md1, md2),
      Bool.and(eq_opt_tag(mt1, mt2),
      Bool.and(eq_opt_arg(a1, a2),
      Bool.and(eq_opt_str(n1, n2),
      Bool.and(eq_in_src(si1, si2),
      Bool.and(eq_inalts(s1, s2),
      Bool.and(eq_bool(y1, y2),
      Bool.and(eq_bool(l1, l2),
                U32.is_eq(r1, r2))))))))))


# ---------------------------------------------------------------------------
# `functools.cache`. `pintern.find` is `intern.find` with `equal` for `eq_upat`,
# and `pintern.of` is the same HIT/MISS pair `UOp.make.intern` uses.
# ---------------------------------------------------------------------------

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

# The MISS index is the arena's length BEFORE the append. Reading it after the
# append and subtracting one gives the same number, and `UOp.of.intern.put`
# spells it that way -- what must not happen is reading the length from an arena
# the append has not reached yet, which is a borrow and not an index.
def pintern.of(pat: Pat, hit: Maybe<&2, U32>) -> U32:
  match hit:
    case Some{i}: i
    case None{}: U32.from_nat(List.length(&2, UPat, Pat.upats(pat)))

def Pat.of.put(pat: Pat, i: U32) -> PatFound:
  PatFound{pat, i}

type Metadata is Data:
  Metadata{name: String, backward: Bool}

# the `metadata` property, ops.py:775, which is the one getter. Python returns
# `all_metadata.get(self, None)`, i.e. a `Maybe`, and that is what this answers.

def UOp.metadata(m: Maybe<&2, Metadata>) -> Maybe<&2, Metadata>:
  m

# `Found` is the pair `Arena & U32` as a RECORD. A pair is a `Type`, so it cannot
# carry a `+` and a reader that wants the arena twice cannot have one; a record
# of two `Data` fields can. Every construction in this file returns one.
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

# `UOp.new` is the whole constructor in one call: grow the arena and read the
# index back, which is what Python's `UOp(...)` does by returning the object.
def UOp.new.of(+ar: Arena, +made: Arena, +op: Op, +src: List<&2, U32>, +arg: Arg, +tag: Tag) -> Found:
  Found{made, UOp.of(made, op, src, arg, tag)}

def UOp.new(+ar: Arena, +op: Op, +src: List<&2, U32>, +arg: Arg, +tag: Tag) -> Found:
  UOp.new.of(ar, UOp.make(ar, op, src, arg, tag), op, src, arg, tag)

# ===========================================================================
# The syntactic sugar of ops.py:557-737, in Python's order, and only the part
# the arena can already answer. Every one of these is a `UOp(...)` call, so each
# is `UOp.new` plus the argument list Python builds for it.
#
# THE `**kwargs` ARE GONE. Python threads `**kwargs` through thirty of these
# and forwards it to the constructor, so it carries op/arg/tag. Bend has no
# kwargs: the constructor's three fields are spelled out at each call site, and
# the sugar that exists only to forward them collapses to the call. That is why
# `UOp.index` is not a def -- the Python `UOp.index` is
# `UOp(Ops.INDEX, src=(self,)+tuple(new_srcs), **kwargs)` and the whole of it is
# that call. The comparison table records each one.
#
# THE `-> Found` RETURN. Python returns the UOp; here the arena grows, so the
# return is the arena and the index together. `Found` is a two-field record
# because an `Arena & U32` pair is a `Type` and cannot carry a `+`.
# ===========================================================================

# sink -- ops.py:559. `UOp(Ops.SINK, src=tuple([x for x in srcs if x is not None]), **kwargs)`
def UOp.sink(ar: Arena, +srcs: List<&2, U32>) -> Found:
  UOp.new(ar, OpsSINK{}, srcs, ANone{}, TNone{})

# group -- ops.py:561. `if len(srcs) == 1 and isinstance(srcs[0], UOp): return
# srcs[0]` -- the one-element case IS the node itself, not a GROUP, so that arm
# hands the arena back unchanged. Zero srcs still makes a GROUP, which is the
# Python's `UOp(Ops.GROUP, src=())`.
def UOp.group.of(srcs: List<&2, U32>, ar: Arena, nar: Arena) -> Found:
  match srcs:
    case Nil{}: Found{nar, 0}
    case s <> t:
      match t:
        case Nil{}: Found{ar, s}
        case _ <> _: UOp.new(nar, OpsGROUP{}, srcs, ANone{}, TNone{})

def UOp.group(+ar: Arena, +srcs: List<&2, U32>) -> Found:
  UOp.group.of(srcs, ar, UOp.make(ar, OpsGROUP{}, srcs, ANone{}, TNone{}))

# alu -- ops.py:630. `UOp(op, src=(self, *src), **kwargs)`
def UOp.alu(ar: Arena, +op: Op, +srcs: List<&2, U32>) -> Found:
  UOp.new(ar, op, srcs, ANone{}, TNone{})

# backedge -- ops.py:620. `UOp(Ops.BACKEDGE, src=(self, loop, cond))`
def UOp.backedge(ar: Arena, +self: U32, +loop: U32, +cond: U32) -> Found:
  UOp.new(ar, OpsBACKEDGE{}, [self, loop, cond], ANone{}, TNone{})

# after -- ops.py:621. `UOp(Ops.AFTER, src=(self,)+src, **kwargs) if len(src) else self`
def UOp.after.go(srcs: List<&2, U32>, ar: Arena, self: U32, made: Found) -> Found:
  match srcs:
    case Nil{}: Found{ar, self}
    case _ <> _: made

def UOp.after(+ar: Arena, +self: U32, +srcs: List<&2, U32>) -> Found:
  UOp.after.go(srcs, ar, self, UOp.new(ar, OpsAFTER{}, List.append(&2, U32, srcs, [self]), ANone{}, TNone{}))

# end -- ops.py:619. `UOp(Ops.END, src=(self,)+src) if len(src) else self`
def UOp.end.go(srcs: List<&2, U32>, ar: Arena, self: U32, made: Found) -> Found:
  match srcs:
    case Nil{}: Found{ar, self}
    case _ <> _: made

def UOp.end(+ar: Arena, +self: U32, +srcs: List<&2, U32>) -> Found:
  UOp.end.go(srcs, ar, self, UOp.new(ar, OpsEND{}, List.append(&2, U32, srcs, [self]), ANone{}, TNone{}))

# mstack -- ops.py:773. `UOp(Ops.MSTACK, src=(self,)+srcs) if len(srcs) else self`
def UOp.mstack.go(srcs: List<&2, U32>, ar: Arena, self: U32, made: Found) -> Found:
  match srcs:
    case Nil{}: Found{ar, self}
    case _ <> _: made

def UOp.mstack(+ar: Arena, +self: U32, +srcs: List<&2, U32>) -> Found:
  UOp.mstack.go(srcs, ar, self, UOp.new(ar, OpsMSTACK{}, List.append(&2, U32, srcs, [self]), ANone{}, TNone{}))

# `(self,)*count` from `UOp.broadcast` below, written out. It is helpers.py's
# `list(x) * n`, and it is why `UOp.broadcast` needs no variadic.
def UOp.replicate.go(+self: U32, n: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+p: UOp.replicate.go(self, p, List.append(&2, U32, acc, [self]))

def UOp.replicate(+self: U32, n: U32) -> List<&2, U32>:
  UOp.replicate.go(self, U32.to_nat(n), Nil{})

# broadcast -- ops.py:612. `if count == 1: return self`; else `UOp(Ops.STACK,
# src=(self,)*count)`. NOTE it always builds a STACK, "even if they are all the
# same" -- that is `UOp.const`'s comment, and the same rule.
def UOp.broadcast.go(isone: Bool, ar: Arena, +self: U32, made: Found) -> Found:
  match isone:
    case True{}: Found{ar, self}
    case False{}: made

def UOp.broadcast(+ar: Arena, +self: U32, +count: U32) -> Found:
  UOp.broadcast.go(U32.is_eq(count, 1), ar, self,
    UOp.new(ar, OpsSTACK{}, UOp.replicate(self, count), ANone{}, TNone{}))

# const -- ops.py:631. `UOp(Ops.CONST, arg=dtype.const(b), src=()).cast(dtype)`
#
# THE `dtype` HALF IS NOT PORTED, and this is the honest state of it. Python
# resolves `dtype` from the Python value (`dtypes.from_py(b)`), truncates the
# value to it (`DType.const` -> `truncate`), and then emits a CONST with a CAST
# on top, noting that "`.cast` folds away at exactly the dtypes a CONST derives
# (bool/weakint/weakfloat): bare there, the pair everywhere else". Both halves
# need the dtype fold, so this interns the bare CONST and the value arrives
# ALREADY TRUNCATED from the caller.
#
# That is a real divergence and it is not hidden: a bare CONST is what Python
# builds for bool/weakint/weakfloat, and the pair for every other dtype, so a
# CONST of int32 is one node here and two there.
#
# TODO(p3): `UOp.const` needs `dtypes.from_py` (dtype.py:100, which also needs
# `commit_int` and `strong_dtype`) and `truncate` (dtype.py:297, half of which is
# the C-effect seam ./dtype.bend already has). Both land with the dtype fold.
def UOp.const(ar: Arena, +v: Const) -> Found:
  UOp.new(ar, OpsCONST{}, Nil{}, APy{v}, TNone{})

# range -- ops.py:644. `UOp(Ops.RANGE, src=(sint_to_uop(end, dtype),)+src,
# arg=(axis_id, axis_type), **kwargs)`. `end` is already a UOp index here,
# because `sint_to_uop` is `UOp.const(x, dtype)` and that is the CONST above.
def UOp.range_end(ar: Arena, +end: U32, +ids: List<&2, U32>, at: AxisType) -> Found:
  UOp.new(ar, OpsRANGE{}, [end], ARange{ids, at}, TNone{})

# loop -- ops.py:647. `UOp(Ops.RANGE, src=(UOp(Ops.NOOP),), arg=(axis_id, AxisType.WEAK))`
def UOp.loop.go(+made: Found, +axis_id: U32) -> Found:
  UOp.range_end(Found.ar(made), Found.i(made), [axis_id], AXIS_WEAK{})

def UOp.loop(+ar: Arena, axis_id: U32) -> Found:
  UOp.loop.go(UOp.new(ar, OpsNOOP{}, Nil{}, ANone{}, TNone{}), axis_id)

# special -- ops.py:650. `UOp(Ops.SPECIAL, src=(sint_to_uop(end),), arg=name)`
def UOp.special(ar: Arena, +end: U32, nm: String) -> Found:
  UOp.new(ar, OpsSPECIAL{}, [end], AStr{nm}, TNone{})

# ===========================================================================
# The graph walks. ops.py:295 and 309.
#
# BOTH TAKE A FUEL `Nat` FIRST, and this is where the reason is. Python's
# `toposort` is an explicit worklist:
#
#     stack: list[tuple[UOp, bool]] = [(self, False)] # each stack entry is (node, visited_flag)
#     while stack:
#       node, visited = stack.pop()
#       if node in cache: continue
#       if not visited:
#         if gate is None or gate(node):
#           stack.append((node, True))  # push node back on stack to process after its srcs
#           for s in reversed(node.src if enter_calls else node.src_without_body):
#             stack.append((s, False)) # push srcs on the stack
#       else: cache[node] = None # second time i'm seeing this node, add it to returned toposort
#
# Bend has no loop and no mutable list. The worklist is therefore the FIRST
# PARAMETER after the fuel, the "already seen" set is the second, and the whole
# `while` is a self-call on the worklist -- a list TAIL, which is a legal
# descent. `case 0n:` answers the set Python would have had if the loop ran out
# of budget, which for a DAG it never does: every node is pushed at most twice,
# so `2 * len(arena)` steps always suffice. The caller is given the arena
# length, and the number is exact rather than a guess.
#
# The gate (`gate=Callable|None`) and the visitor (`visitor: Callable`) are
# Python callables. A closure in Bend is single-use and cannot be stored in a
# `Data` field, so they are NOT PORTED as parameters; the two call sites in
# tinygrad that pass a gate pass a *bound method* or a lambda over one op, and
# both are P3/P4 work. Every other caller passes None, which is the behaviour
# here. The visitor is the same story, and `topovisit` has NO caller in
# ops.py at all.
# ===========================================================================

type Frame is Data:
  # each stack entry is (node, visited_flag)
  Frame{n: U32, visited: Bool}

type Topo is Data:
  Topo{cache: List<&2, U32>, stack: List<&2, Frame>}

def Topo.empty() -> Topo:
  Topo{Nil{}, Nil{}}

# `cache[node] = None` -- an append, because a Dict preserves insertion order and
# the toposort IS its iteration order.

def Topo.cache_add(n: U32, t: Topo) -> Topo:
  match t:
    case Topo{cache, stack}: Topo{List.append(&2, U32, cache, [n]), stack}

# `if n in cache: continue`
# `stack.append((n, True))` then the srcs, reversed.

def Arena.push_srcs.go(srcs: List<&2, U32>, st: List<&2, Frame>) -> List<&2, Frame>:
  match srcs:
    case Nil{}: st
    case s <> t: Arena.push_srcs.go(t, List.append(&2, Frame, st, [Frame{s, False{}}]))

# one turn of the while loop

def Arena.push_srcs(ar: Arena, n: U32, st: List<&2, Frame>) -> List<&2, Frame>:
  Arena.push_srcs.go(Arena.src_without_body(ar, n), st)

def Topo.push(ar: Arena, +n: U32, t: Topo) -> Topo:
  match t:
    case Topo{cache, stack}: Topo{cache, Arena.push_srcs(ar, n, List.append(&2, Frame, stack, [Frame{n, True{}}]))}

# `for s in reversed(node.src): stack.append((s, False))`

def Topo.step.hit(ar: Arena, +n: U32, rest: List<&2, Frame>, seen: Bool, +cache: List<&2, U32>) -> Topo:
  match seen:
    case True{}: Topo{cache, rest}
    case False{}: Topo.push(ar, n, Topo{cache, rest})

# the while loop, as a self-call on the worklist

def Topo.step.fresh(ar: Arena, +n: U32, rest: List<&2, Frame>, +cache: List<&2, U32>) -> Topo:
  Topo.step.hit(ar, n, rest, List.contains(U32, U32.is_eq, cache, n), cache)

def Topo.step.vis(ar: Arena, +n: U32, visited: Bool, rest: List<&2, Frame>, cache: List<&2, U32>) -> Topo:
  match visited:
    case True{}: Topo.cache_add(n, Topo{cache, rest})
    case False{}: Topo.step.fresh(ar, n, rest, cache)

def Topo.step(ar: Arena, t: Topo) -> Topo:
  match t:
    case Topo{cache, stack}:
      match stack:
        case Nil{}: t
        case Frame{n, visited} <> rest:
          Topo.step.vis(ar, n, visited, rest, cache)

def Topo.cache_of(t: Topo) -> List<&2, U32>:
  match t:
    case Topo{cache, stack}: cache

def toposort(fuel: Nat, +ar: Arena, t: Topo) -> List<&2, U32>:
  match fuel:
    case 0n: Topo.cache_of(t)
    case 1n+p: toposort(p, ar, Topo.step(ar, t))

# `UOp.toposort(self, gate=None, enter_calls=True)`. The fuel is the arena
# length times two, and the comment above says why that is exact.

def UOp.toposort(fuel: Nat, +ar: Arena, self: U32) -> List<&2, U32>:
  toposort(fuel, ar, Topo.push(ar, self, Topo.empty()))

# toposort(enter_calls=False) -- the two call sites that pass it, both in
# `ProgramInfo.from_sink` and `contiguous_view`.


def UOp.topovisit(fuel: Nat, +ar: Arena, self: U32) -> List<&2, U32>:
  UOp.toposort(fuel, ar, self)


def UOp.toposort_nocalls(fuel: Nat, +ar: Arena, self: U32) -> List<&2, U32>:
  toposort(fuel, ar, Topo{Nil{}, List.append(&2, Frame, Nil{}, [Frame{self, False{}}])})

# topovisit -- ops.py:309. "NOTE: this shares a lot of code with toposort". It
# has no caller in ops.py, and its visitor is a Python callable, so the def is
# here for the inventory and its body is the toposort order with the visitor
# call left to the caller that has one.
#
# TODO(p3): the visitor is a Callable. It is a P4 concern (every rewrite rule
# and every `pm.rewrite` callback is one) and it needs the same Sel-tag shape
# the master plan already prescribes for `PatternMatcher` rules.

# ---------------------------------------------------------------------------
# `src` normalisation -- ops.py:1463-1468, the `permutations` line:
#
#   src is a list  -> all permutations, or one alternative if `all_same`
#   src is a tuple -> one alternative
#   src is a UPat  -> [itertools.repeat(src)]: ONE UNBOUNDED alternative
#   src is None    -> no alternatives
#
# ARITY, and this is a refusal rather than an approximation. The permutation
# branch is exact for 1 and 2 srcs and yields NO alternatives for 3 or more, so
# a 3-ary commutative pattern matches nothing instead of matching wrongly. That
# is unreachable from ops.py: the only caller of a list `src` is `alu`, and every
# member of `GroupOp.Commutative` is BINARY -- ADD, AND, CMPEQ, CMPNE, MAX, MUL,
# OR, XOR, all of them. Arity >= 3 is TODO(p3) and belongs with `spec.py`, the
# only other caller.
# ---------------------------------------------------------------------------
def all_same.from(+h: U32, t: List<&2, U32>) -> Bool:
  match t:
    case Nil{}: True{}
    case y <> u: Bool.and(U32.is_eq(h, y), all_same.from(h, u))


def all_same(ys: List<&2, U32>) -> Bool:
  match ys:
    case Nil{}: True{}
    case y <> t: all_same.from(y, t)


# `[tuple(src)]` when `all_same`, else `list(itertools.permutations(src))`
def perms.of(+a: U32, t: List<&2, U32>) -> List<&2, UpAlt>:
  match t:
    case Nil{}: [UpFixed{[a]}]
    case +b <> u:
      # `u` empty means the src list was EXACTLY [a, b], so both orders. A
      # non-empty `u` means arity 3 or more, which this branch refuses. Neither
      # re-wraps a list TAIL, which is what Bend refuses.
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




# a `match` may not scrutinise a computed list, so the four-way dispatch is its
# own def
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

# ---------------------------------------------------------------------------
# `early_reject` -- ops.py:1476-1478. The comprehension is
#   `{pp.op[0] for pp in upat_match if pp.op is not None and len(pp.op) == 1}`
# over `upat_match`, which is `[src]` for a UPat src, `[]` for None, and
# `self.src[0]` -- the FIRST alternative only -- otherwise.
# ---------------------------------------------------------------------------
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




# the `pp.op is not None and len(pp.op) == 1` guard. Three defs, because a
# `match` scrutinee must be a PARAMETER: `Maybe` first, then the `Nat` length.





# ---------------------------------------------------------------------------
# The constructor -- ops.py:1449. `UPat(Ops.CAST, dtype, (self,))` becomes
# `UPat.of(pat, Some{[OpsCAST{}]}, Some{[dt]}, None{}, STuple{[k]}, ...)`: Python's
# positional and keyword arguments flattened into positional ones, which is the
# `UOp.make` convention above.
#
# `strict_length`, `required_len` and `early_reject` are DERIVED here rather than
# passed, because in Python they are derived in `__init__` too -- and deriving
# them is what makes the ten-argument call sites short.
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# `dtype` -- ops.py:1480. `self.match_dtype[0] if ... else dtypes.void`.
# A `match` may not scrutinise a computed `Maybe`, and `List.head` returns a
# `Maybe` too, so the unwrap and the head are two defs rather than one.
# ---------------------------------------------------------------------------
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



# `(self,)+src` -- `List.append` CONCATENATES, so `[self] ++ src` is the cons.

def prepend(self: U32, src: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, [self], src)

# ---------------------------------------------------------------------------
# `named` -- ops.py:1485. Every field is carried across, and `not
# self.strict_length` is `allow_any_len`, which is how the raw `src` survives a
# round trip. Python's `self.op` is already a tuple, so it is already a `Some`.
# ---------------------------------------------------------------------------
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
  match_tag: Maybe<&2, List<&2, Tag>>,
  +src: SrcArg,
  arg: Maybe<&2, Arg>,
  name: Maybe<&2, String>,
  allow_any_len: Bool,
  custom_early_reject: Maybe<&2, List<&2, Op>>,
  is_any: Bool) -> PatFound:

  # `alts_of(src)` is pure and `src` is `+`-shared, so it is recomputed rather
  # than bound: a `let` is affine and would be consumed by the constructor.
  u: UPat = UPat{op, match_dtype, match_tag, arg, name, src, alts_of(src), is_any,
           strict_of(src, allow_any_len), required_of(src),
           early_of(pat, src, custom_early_reject, alts_of(src))}
  UPat.of.put(pat, u)

def UPat.named.put(u: UPat, name: String, pat: Pat) -> PatFound:
  match u:
    case UPat{op, md, mt, arg, _, si, _, any, sl, _, _}: UPat.of(
      pat, op, md, mt, si, arg, Some{name}, Bool.not(sl), None{}, any)
def opt_dts.one(dt: Maybe<&2, S.Dt>) -> Maybe<&2, List<&2, S.Dt>>:
  match dt:
    case Some{d}: Some{[d]}
    case None{}: None{}

def opt_dts(dt: Maybe<&2, S.Dt>) -> Maybe<&2, List<&2, S.Dt>>:
  opt_dts.one(dt)

def UPat.var(pat: Pat, name: Maybe<&2, String>, dt: Maybe<&2, S.Dt>) -> PatFound:
  UPat.of(pat, None{}, opt_dts(dt), None{}, SNone{}, None{}, name, False{}, None{}, False{})


def UPat.named.of(hit: Maybe<&2, UPat>, name: String, pat: Pat) -> PatFound:
  match hit:
    case Some{u}: UPat.named.put(u, name, pat)
    # a miss cannot happen for a pattern built here; Python would raise
    # AttributeError, and a bare named var is the honest nothing-to-rebuild
    case None{}: UPat.var(pat, Some{name}, None{})


def UPat.named(+pat: Pat, k: U32, name: String) -> PatFound:
  UPat.named.of(List.get(&2, UPat, Pat.upats(pat), U32.to_nat(k)), name, pat)



# ---------------------------------------------------------------------------
# `any` / `or_casted` / `or_bitcasted` / `or_after` -- ops.py:1487-1493.
#
# `self if name is None else self.named(name)` is a Maybe-index choice, and the
# wrapper's `src=(self,)` is the ORIGINAL pattern even when `any` gets the named
# copy -- an upstream subtlety that a "tidy" rewrite would lose.
# ---------------------------------------------------------------------------

def UPat.any(pat: Pat, src: List<&2, U32>) -> PatFound:
  UPat.of(pat, None{}, None{}, None{}, STuple{src}, None{}, None{}, False{}, None{}, True{})
def UPat.or_any.pair(chosen: U32, +wrapped: PatFound) -> PatFound:
  UPat.any(PatFound.pat(wrapped), [chosen, PatFound.i(wrapped)])
def or_pick(pat: Pat, k: U32, name: Maybe<&2, String>) -> U32:
  match name:
    case None{}: k
    case Some{nm}: PatFound.i(UPat.named(pat, k, nm))
def UPat.or_any.wrap(pat: Pat, k: U32, name: Maybe<&2, String>, wrap: Op, any_len: Bool) -> PatFound:
  UPat.of(pat, Some{[wrap]}, None{}, None{}, STuple{[k]}, None{}, name, any_len, None{}, False{})



def UPat.or_any(+pat: Pat, +k: U32, +name: Maybe<&2, String>, wrap: Op, any_len: Bool) -> PatFound:
  UPat.or_any.pair(or_pick(pat, k, name), UPat.or_any.wrap(pat, k, name, wrap, any_len))


def UPat.or_casted(pat: Pat, k: U32, name: Maybe<&2, String>) -> PatFound:
  UPat.or_any(pat, k, name, OpsCAST{}, False{})

def UPat.or_bitcasted(pat: Pat, k: U32, name: Maybe<&2, String>) -> PatFound:
  UPat.or_any(pat, k, name, OpsBITCAST{}, False{})

def UPat.or_after(pat: Pat, k: U32, name: Maybe<&2, String>) -> PatFound:
  UPat.or_any(pat, k, name, OpsAFTER{}, True{})

# three steps, each returning `(arena, index)`: pick self-or-named, wrap it, then
# `UPat.any` over the two. The wrapper's `src` is always the ORIGINAL index.

# three steps, each carrying the arena: pick self-or-named, wrap the ORIGINAL
# index, then `UPat.any` over the two. The wrapper's `src=(self,)` is the
# original pattern even when `any` receives the named copy -- an upstream
# subtlety a "tidy" rewrite would lose.




# `self if name is None else self.named(name)`


# ---------------------------------------------------------------------------
# `var` / `cvar` / `const` -- ops.py:1495-1501. `@functools.cache` is the intern
# inside `UPat.of`, so these three are also the interning demonstration: two calls
# with the same name return the SAME index.
#
# `dtype` may be one `DType` or a tuple of them, and a single one is wrapped.
# ---------------------------------------------------------------------------




def UPat.cvar(pat: Pat, name: Maybe<&2, String>, dt: Maybe<&2, S.Dt>, arg: Maybe<&2, Arg>) -> PatFound:
  UPat.of(pat, Some{[OpsCONST{}]}, opt_dts(dt), None{}, SNone{}, arg, name, False{}, None{}, False{})

def UPat.const(pat: Pat, b: Const, dt: Maybe<&2, S.Dt>) -> PatFound:
  UPat.of(pat, Some{[OpsCONST{}]}, opt_dts(dt), None{}, SNone{}, Some{APy{b}}, None{}, False{}, None{}, False{})

# ---------------------------------------------------------------------------
# The one-src sugar -- ops.py:1504-1522. Each is `UPat.of` with a fixed `op` and
# `(self,)+src`, so each is one call and there is nothing to decide.
#
# `sink` -- ops.py:1506. `tuple([x for x in srcs if x is not None])` filters Nones
# in Python; here every index is already present, so the caller owns that and
# `None` would be a caller bug, not a runtime case.
# ---------------------------------------------------------------------------

def UPat.f(pat: Pat, k: U32, op: Op) -> PatFound:
  UPat.of(pat, Some{[op]}, None{}, None{}, STuple{[k]}, None{}, None{}, False{}, None{}, False{})

def UPat.sink(pat: Pat, srcs: List<&2, U32>) -> PatFound:
  UPat.of(pat, Some{[OpsSINK{}]}, None{}, None{}, STuple{srcs}, None{}, None{}, False{}, None{}, False{})

def UPat.index(pat: Pat, k: U32, srcs: List<&2, U32>) -> PatFound:
  UPat.of(pat, Some{[OpsINDEX{}]}, None{}, None{}, STuple{prepend(k, srcs)}, None{}, None{}, False{}, None{}, False{})

def UPat.load(pat: Pat, k: U32, srcs: List<&2, U32>) -> PatFound:
  UPat.of(pat, Some{[OpsLOAD{}]}, None{}, None{}, STuple{prepend(k, srcs)}, None{}, None{}, False{}, None{}, False{})

def UPat.store(pat: Pat, k: U32, srcs: List<&2, U32>) -> PatFound:
  UPat.of(pat, Some{[OpsSTORE{}]}, None{}, None{}, STuple{prepend(k, srcs)}, None{}, None{}, False{}, None{}, False{})

def UPat.end(pat: Pat, k: U32, srcs: List<&2, U32>) -> PatFound:
  UPat.of(pat, Some{[OpsEND{}]}, None{}, None{}, STuple{prepend(k, srcs)}, None{}, None{}, False{}, None{}, False{})

def UPat.backedge(pat: Pat, k: U32, loop: U32, cond: U32) -> PatFound:
  UPat.of(pat, Some{[OpsBACKEDGE{}]}, None{}, None{}, STuple{[k, loop, cond]}, None{}, None{}, False{}, None{}, False{})

# `reduce` -- ops.py:1516. `arg = kwargs.pop('arg', None); if isinstance(arg, Ops):
# arg = (arg, 0)`, so a bare `Ops` arg becomes a `(rop, 0)` REDUCE pair. The port
# takes the two halves directly, which is the same information with the
# `isinstance` test already done at the call site.
def UPat.reduce.md(u: UPat, arg: Maybe<&2, Arg>, k: U32, srcs: List<&2, U32>, pat: Pat) -> PatFound:
  match u:
    case UPat{_, md, _, _, _, _, _, _, _, _, _}: UPat.of(
      pat, Some{[OpsREDUCE{}]}, md, None{}, STuple{prepend(k, srcs)}, arg, None{}, False{}, None{}, False{})

def UPat.reduce.put(hit: Maybe<&2, UPat>, arg: Maybe<&2, Arg>, k: U32, srcs: List<&2, U32>, pat: Pat) -> PatFound:
  match hit:
    case Some{u}: UPat.reduce.md(u, arg, k, srcs, pat)
    case None{}: UPat.var(pat, None{}, None{})

def UPat.reduce.of(+pat: Pat, +k: U32, srcs: List<&2, U32>, arg: Maybe<&2, Arg>) -> PatFound:
  UPat.reduce.put(List.get(&2, UPat, Pat.upats(pat), U32.to_nat(k)), arg, k, srcs, pat)

def UPat.reduce(+pat: Pat, k: U32, srcs: List<&2, U32>, rop: Op, ax: U32) -> PatFound:
  UPat.reduce.of(pat, k, srcs, Some{AReduce{rop, ax}})




# `cast` -- ops.py:1510. The short-circuit `if dtype is not None and
# self.match_dtype == (dtype,): return self` is a no-op guard, so it is kept:
# it is what stops a redundant CAST from being built.
def UPat.bitcast.put(pat: Pat, u: UPat, dt: Maybe<&2, S.Dt>, k: U32) -> PatFound:
  match u:
    case UPat{_, _, _, _, _, _, _, _, _, _, _}: UPat.of(
      pat, Some{[OpsBITCAST{}]}, opt_dts(dt), None{}, STuple{[k]}, None{}, None{}, False{}, None{}, False{})

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


# the short-circuit returns SELF, not a new pattern, so the arena is untouched
# and the answer is the index it was handed.




# `bitcast` is the tail of `cast`'s body, and is its own method upstream
def UPat.bitcast.of(hit: Maybe<&2, UPat>, dt: Maybe<&2, S.Dt>, k: U32, pat: Pat) -> PatFound:
  match hit:
    case Some{u}: UPat.bitcast.put(pat, u, dt, k)
    case None{}: UPat.var(pat, None{}, None{})

def UPat.bitcast(+pat: Pat, +k: U32, dt: Maybe<&2, S.Dt>) -> PatFound:
  UPat.bitcast.of(List.get(&2, UPat, Pat.upats(pat), U32.to_nat(k)), dt, k, pat)



# `broadcast` -- ops.py:1519. `src=self` is a UPat, not a tuple, so this is the
# `SOne` case: ONE UNBOUNDED alternative rather than a permuted list.
def UPat.broadcast.put(pat: Pat, u: UPat, k: U32) -> PatFound:
  match u:
    case UPat{_, md, _, _, _, _, _, _, _, _, _}: UPat.of(
      pat, Some{[OpsSTACK{}]}, md, None{}, SOne{k}, None{}, None{}, False{}, None{}, False{})

def UPat.broadcast.of(hit: Maybe<&2, UPat>, +k: U32, pat: Pat) -> PatFound:
  match hit:
    case Some{u}: UPat.broadcast.put(pat, u, k)
    case None{}: UPat.var(pat, None{}, None{})

def UPat.broadcast(+pat: Pat, +k: U32) -> PatFound:
  UPat.broadcast.of(List.get(&2, UPat, Pat.upats(pat), U32.to_nat(k)), k, pat)



# `after` -- ops.py:1520
def UPat.after.put(pat: Pat, u: UPat, k: U32, srcs: List<&2, U32>) -> PatFound:
  match u:
    case UPat{_, md, _, _, _, _, _, _, _, _, _}: UPat.of(
      pat, Some{[OpsAFTER{}]}, md, None{}, STuple{prepend(k, srcs)}, None{}, None{}, False{}, None{}, False{})

def UPat.after.of(hit: Maybe<&2, UPat>, +k: U32, +srcs: List<&2, U32>, pat: Pat) -> PatFound:
  match hit:
    case Some{u}: UPat.after.put(pat, u, k, srcs)
    case None{}: UPat.var(pat, None{}, None{})

def UPat.after(+pat: Pat, +k: U32, srcs: List<&2, U32>) -> PatFound:
  UPat.after.of(List.get(&2, UPat, Pat.upats(pat), U32.to_nat(k)), k, srcs, pat)



# ---------------------------------------------------------------------------
# `alu` -- ops.py:1531.
#
#   asrc = (self,)+src
#   UPat(op, boolean if op in {CMPLT, CMPNE} else asrc[-1].match_dtype,
#        list(asrc) if op in GroupOp.Commutative else asrc)
#
# `GroupOp.Commutative` is read off the Op tag, which is what `Ops.value` already
# gives: ADD, AND, CMPEQ, CMPNE, MAX, MUL, OR, XOR -- all BINARY, which is why
# the permutation branch above is exact at arity 2 and refuses 3.
# `asrc[-1]` is the LAST of 1 or 2, so the arity dispatch is two cases.
# ---------------------------------------------------------------------------
def UPat.alu.src.of(pat: Pat, comm: Bool, op: Op, +k: U32, other: U32, md: Maybe<&2, List<&2, S.Dt>>) -> PatFound:
  match comm:
    case True{}: UPat.of(pat, Some{[op]}, md, None{}, SList{[k, other]}, None{}, None{}, False{}, None{}, False{})
    case False{}: UPat.of(pat, Some{[op]}, md, None{}, STuple{[k, other]}, None{}, None{}, False{}, None{}, False{})
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
    case UPat{_, _, _, _, _, _, _, _, _, _, _}: UPat.alu.src(
      pat, UPat.alu.dt(pat, k, other, op), op, k, other)

def UPat.alu.of(hit: Maybe<&2, UPat>, op: Op, +k: U32, +other: U32, pat: Pat) -> PatFound:
  match hit:
    case Some{u}: UPat.alu.put(pat, u, op, k, other)
    case None{}: UPat.var(pat, None{}, None{})


def UPat.alu(+pat: Pat, +k: U32, op: Op, other: U32) -> PatFound:
  UPat.alu.of(List.get(&2, UPat, Pat.upats(pat), U32.to_nat(k)), op, k, other, pat)



# `boolean if op in {CMPLT, CMPNE} else asrc[-1].match_dtype`








# `list(asrc) if op in GroupOp.Commutative else asrc`





# ops.py:1474-1475: `custom_early_reject` overrides the computed set.



# intern, then hand back the index. The MISS index is the arena's length BEFORE
# the append -- so the two facts are read at different points on purpose, and
# `UPat.of.hit` is where they are brought together. Reading the length AFTER the
# append and subtracting one is the same number, and `UOp.of.intern.put` spells
# it that way; the point is that it must be the pre-append count either way.


# ===========================================================================
# THE INVENTORY: every ops.py def that is NOT yet a Bend def, with the reason.
#
# THESE ARE NOT DEFS, ON PURPOSE. A def whose body answers a placeholder would be
# a stub, and the brief for this file rules stubs out: a stub hides the wall, and
# the wall is the thing this unit exists to find. So each entry is the Python
# name, its line, and the constraint that stops it being written today.
# `rg "TODO(p3)" tinybendygrad/uop/ops.bend` is the work queue and the line
# numbers are the Python's, so the queue diffs against ops.py line for line.
#
# THE TWO CONSTRAINTS, and both are Bend rules rather than choices.
#
#   A. A self-call must pass a FIELD of its own parameter. The arena's "field" is
#      a U32 read back out of a store, which the checker cannot see as a subterm.
#      Measured: `def f(u: U32): case _: f(U32.sub(u, 1))` is refused with
#      "expected : a decreasing self-call". So every property fold over the graph
#      -- dtype, _shape, device, addrspace, _ranges, _min_max, key, axis, marg,
#      ended_ranges, bool_slice, backward_slice, trace_num, tuplize, vmin, vmax --
#      has no legal recursion as written. `toposort` above DOES work, because its
#      recursion is on a WORKLIST: a list tail of its own parameter, with the node
#      being visited as a payload. The property folds have no such payload.
#
#   B. Mutual recursion is refused, and tinygrad's folds are a cycle.
#      `dtype_from_uop` reads `src[0]._shape` (the INDEX arm's image test) and
#      `_shape` reads `src[0].dtype` (the BITCAST arm's itemsize ratio); and
#      `simplify()` calls `graph_rewrite`, whose rules call `dtype` and `shape`.
#      Python breaks that cycle with `recursive_property`'s memo on
#      `node.__dict__`, which this port does not have -- see the header, point 5.
#
# SO THE FOLDS DO NOT FIT IN ONE BEND MODULE AS THE PYTHON IS WRITTEN. The fix is
# known and it is not a hack: fold dtype and shape together into ONE def that
# answers the pair, drive it with a Kahn worklist (the shape `toposort` above
# already has), and keep `graph_rewrite` out of that module, because nothing in
# the rewrite engine may call back into the fold. That is a P3 design decision
# and it is written down in spec/ops.md.
# ===========================================================================

# TODO(p3) ops.py:18  def __repr__

# TODO(p3) ops.py:41  def __repr__

# TODO(p3) ops.py:76  def srender

# TODO(p3) ops.py:95  def sym_infer

# TODO(p3) ops.py:219  def __init__

# TODO(p3) ops.py:223  def __get__

# TODO(p3) ops.py:247  def __del__

# TODO(p3) ops.py:251  def __reduce__

# TODO(p3) ops.py:267  def key

# TODO(p3) ops.py:269  def __repr__

# TODO(p3) ops.py:278  def backward_slice

# TODO(p3) ops.py:284  def backward_slice_with_self

# TODO(p3) ops.py:285  def op_in_backward_slice_with_self

# TODO(p3) ops.py:290  def _bool_slice

# TODO(p3) ops.py:293  def bool_slice

# TODO(p3) ops.py:322  def tuplize

# TODO(p3) ops.py:329  def _shape

# TODO(p3) ops.py:456  def shape

# TODO(p3) ops.py:461  def shard_shape

# TODO(p3) ops.py:467  def max_shard_shape

# TODO(p3) ops.py:470  def ended_ranges

# TODO(p3) ops.py:483  def _ranges

# TODO(p3) ops.py:497  def ranges

# TODO(p3) ops.py:502  def axis_id

# TODO(p3) ops.py:507  def axis_type

# TODO(p3) ops.py:513  def simplify
#   # *** uop evaluation ***

# TODO(p3) ops.py:520  def ssimplify

# TODO(p3) ops.py:523  def _eval

# TODO(p3) ops.py:529  def __bool__

# TODO(p3) ops.py:530  def __int__

# TODO(p3) ops.py:531  def __float__

# TODO(p3) ops.py:532  def substitute

# TODO(p3) ops.py:539  def __index__
#   # NOTE: this is not called by Tensor slice (Tensor handles UOps directly), but satisfies SupportsIndex for type checking

# TODO(p3) ops.py:544  def trace_num

# TODO(p3) ops.py:565  def body

# TODO(p3) ops.py:570  def is_inline_call

# TODO(p3) ops.py:573  def has_unbound_outputs

# TODO(p3) ops.py:578  def unbound_outputs

# TODO(p3) ops.py:581  def index

# TODO(p3) ops.py:585  def __getitem__

# TODO(p3) ops.py:600  def _uop

# TODO(p3) ops.py:602  def _wrap_uop

# TODO(p3) ops.py:603  def const_like

# TODO(p3) ops.py:606  def vconst_like

# TODO(p3) ops.py:609  def ufix

# TODO(p3) ops.py:616  def store

# TODO(p3) ops.py:623  def without_after

# TODO(p3) ops.py:624  def barrier

# TODO(p3) ops.py:625  def ins

# TODO(p3) ops.py:626  def contract

# TODO(p3) ops.py:632  def const

# TODO(p3) ops.py:640  def ccast
#   # cast, except for CONST, in which case rebuild a new CONST at the dtype

# TODO(p3) ops.py:643  def cconst

# TODO(p3) ops.py:645  def range

# TODO(p3) ops.py:648  def loop

# TODO(p3) ops.py:652  def wmma

# TODO(p3) ops.py:655  def _rop

# TODO(p3) ops.py:666  def invalid

# TODO(p3) ops.py:667  def valid

# TODO(p3) ops.py:668  def get_idx

# TODO(p3) ops.py:671  def get_valid

# TODO(p3) ops.py:674  def reduce

# TODO(p3) ops.py:679  def bufferize

# TODO(p3) ops.py:680  def allreduce

# TODO(p3) ops.py:683  def overflows

# TODO(p3) ops.py:685  def split_uop

# TODO(p3) ops.py:692  def unshard
#   # *** multi-device helpers ***

# TODO(p3) ops.py:707  def sharding

# TODO(p3) ops.py:712  def bounds

# TODO(p3) ops.py:718  def axis

# TODO(p3) ops.py:751  def _shard

# TODO(p3) ops.py:757  def shard

# TODO(p3) ops.py:761  def copy_to_device

# TODO(p3) ops.py:769  def store_call

# TODO(p3) ops.py:772  def mselect

# TODO(p3) ops.py:778  def on_disk
#   # little helpers

# TODO(p3) ops.py:779  def on_creation_device

# TODO(p3) ops.py:780  def needs_storage

# TODO(p3) ops.py:785  def base

# TODO(p3) ops.py:792  def unsharded_base

# TODO(p3) ops.py:801  def storage_base

# TODO(p3) ops.py:808  def as_shape

# TODO(p3) ops.py:814  def marg

# TODO(p3) ops.py:821  def _mop

# TODO(p3) ops.py:844  def getaddr

# TODO(p3) ops.py:849  def device_range_src

# TODO(p3) ops.py:853  def new_buffer

# TODO(p3) ops.py:860  def from_buffer

# TODO(p3) ops.py:864  def empty_like

# TODO(p3) ops.py:870  def _frompy

# TODO(p3) ops.py:882  def clone

# TODO(p3) ops.py:890  def device

# TODO(p3) ops.py:905  def is_virtual

# TODO(p3) ops.py:910  def addrspace

# TODO(p3) ops.py:925  def buf_uop

# TODO(p3) ops.py:934  def contiguous_view

# TODO(p3) ops.py:950  def contiguous_view_offset

# TODO(p3) ops.py:952  def has_buffer_identity

# TODO(p3) ops.py:959  def _base_buffer_is_realized

# TODO(p3) ops.py:966  def _buffer_view

# TODO(p3) ops.py:972  def buffer

# TODO(p3) ops.py:997  def realized

# TODO(p3) ops.py:1008  def is_realized

# TODO(p3) ops.py:1013  def variable

# TODO(p3) ops.py:1018  def is_variable

# TODO(p3) ops.py:1023  def is_bound_var

# TODO(p3) ops.py:1027  def expr

# TODO(p3) ops.py:1030  def bind

# TODO(p3) ops.py:1037  def unbound

# TODO(p3) ops.py:1041  def unbind

# TODO(p3) ops.py:1044  def unbind_all

# TODO(p3) ops.py:1047  def variables

# TODO(p3) ops.py:1058  def const_factor
#   # *** uop symbolic stuff ***

# TODO(p3) ops.py:1067  def divides

# TODO(p3) ops.py:1080  def pop_const

# TODO(p3) ops.py:1083  def gcd

# TODO(p3) ops.py:1089  def divide_exact

# TODO(p3) ops.py:1100  def vmin

# TODO(p3) ops.py:1102  def vmax

# TODO(p3) ops.py:1104  def _min_max

# TODO(p3) ops.py:1166  def _sym_fxn

# TODO(p3) ops.py:1177  def sym_infer

# TODO(p3) ops.py:1181  def render

# TODO(p3) ops.py:1189  def pyrender

# TODO(p3) ops.py:1196  def alloc

# TODO(p3) ops.py:1201  def alloc_like

# TODO(p3) ops.py:1204  def placeholder

# TODO(p3) ops.py:1217  def placeholder_like

# TODO(p3) ops.py:1222  def set
#   # set is store+end+after

# TODO(p3) ops.py:1227  def param

# TODO(p3) ops.py:1239  def param_like

# TODO(p3) ops.py:1248  def view_as

# TODO(p3) ops.py:1256  def custom_function

# TODO(p3) ops.py:1258  def call

# TODO(p3) ops.py:1272  def call_with_outputs

# TODO(p3) ops.py:1292  def mint

# TODO(p3) ops.py:1310  def call_with_output
#   # one-line convenience for the single-output case: self is the value

# TODO(p3) ops.py:1311  def custom_kernel

# TODO(p3) ops.py:1316  def to_elf

# TODO(p3) ops.py:1329  def uopfunc

# TODO(p3) ops.py:1330  def param

# TODO(p3) ops.py:1333  def outlined

# TODO(p3) ops.py:1359  def launch_dims

# TODO(p3) ops.py:1364  def vals

# TODO(p3) ops.py:1400  def __reduce__
#   # grad_fxn can't be pickled

# TODO(p3) ops.py:1408  def safe_exp2
#   # ******** ops in python ********

# TODO(p3) ops.py:1412  def safe_pow

# TODO(p3) ops.py:1427  def exec_alu

# TODO(p3) ops.py:1438  def get_location
#   # ***** pattern matcher *****

# `UPat` IS PORTED -- the type, the pattern arena, the intern, the `src`
# normalisation, and every constructor except the five below. See the section at
# ops.py:1447. The pattern ARENA is the load-bearing decision and it is recorded
# at the type: `src` holds INDICES, so `eq_upat` is a flat walk instead of the
# mutual recursion a recursive pattern type would demand, and both sides of a
# match are read-only `Data`, so no arena is threaded.
#
# PORTED  __init__     -> UPat.of / alts_of / strict_of / required_of / early_of
# PORTED  dtype        -> UPat.dtype
# PORTED  named        -> UPat.named
# PORTED  any          -> UPat.any
# PORTED  or_casted    -> UPat.or_casted
# PORTED  or_bitcasted -> UPat.or_bitcasted
# PORTED  or_after     -> UPat.or_after
# PORTED  var          -> UPat.var        (functools.cache is the intern)
# PORTED  cvar         -> UPat.cvar       (functools.cache is the intern)
# PORTED  const        -> UPat.const
# PORTED  f            -> UPat.f
# PORTED  sink         -> UPat.sink
# PORTED  index        -> UPat.index
# PORTED  cast         -> UPat.cast       (the no-op short-circuit is kept)
# PORTED  bitcast      -> UPat.bitcast
# PORTED  load         -> UPat.load
# PORTED  store        -> UPat.store
# PORTED  reduce       -> UPat.reduce
# PORTED  broadcast    -> UPat.broadcast  (src=self, so ONE unbounded alt)
# PORTED  after        -> UPat.after
# PORTED  end          -> UPat.end
# PORTED  backedge     -> UPat.backedge
# PORTED  alu          -> UPat.alu        (Commutative read off Ops.value)
#
# TODO(p3) ops.py:1482  def __reduce__
#   # CPython frame introspection. `location` is deliberately not a field: a
#   # field the port cannot read is a field that would silently always be None.

# The five left are ONE deferral, not five. `_broadcasted` is
# `self, y = self.ufix(y)`, and `ufix` is `UPat.cvar(arg=x) if not isinstance(x,
# UPat) else x` -- the only place in the class that accepts a value which is NOT
# already a pattern. In an arena that is a two-armed sum over `ConstType`, and
# the arm would be threaded through all five methods rather than tested once.
# Every one of the five is a caller of `ufix` and nothing else.

# TODO(p3) ops.py:1526  def _broadcasted
# TODO(p3) ops.py:1529  def ufix
# TODO(p3) ops.py:1530  def __floordiv__
# TODO(p3) ops.py:1531  def __rfloordiv__
# TODO(p3) ops.py:1532  def mod

# `itertools.permutations` is exact at arity 1 and 2 and REFUSES 3 or more by
# yielding no alternatives, so a 3-ary commutative pattern matches nothing
# rather than matching wrongly. Unreachable from ops.py -- every member of
# `GroupOp.Commutative` is binary -- and the only other caller is `spec.py`.
# TODO(p3) ops.py:1464  permutations, arity >= 3

# TODO(p3) ops.py:1537  def match

# TODO(p3) ops.py:1556  def deconstruct_function

# TODO(p3) ops.py:1558  def names
#   # globals can be referenced from arbitrarily nested code objects (comprehensions/lambdas, pre PEP 709)

# TODO(p3) ops.py:1566  def upat_interpret

# TODO(p3) ops.py:1569  def universal_match

# TODO(p3) ops.py:1574  def universal_match

# TODO(p3) ops.py:1580  def upat_deferred_compile

# TODO(p3) ops.py:1581  def lazy_compile

# TODO(p3) ops.py:1588  def __init__

# TODO(p3) ops.py:1600  def __reduce__

# TODO(p3) ops.py:1603  def __add__

# TODO(p3) ops.py:1605  def rewrite

# TODO(p3) ops.py:1642  def save_to_diskcache

# TODO(p3) ops.py:1646  def add_trace_group

# TODO(p3) ops.py:1652  def rewrite_group

# TODO(p3) ops.py:1654  def _decorator

# TODO(p3) ops.py:1655  def __wrapper

# TODO(p3) ops.py:1699  def rewrite

# TODO(p3) ops.py:1733  def print_match_stats

# TODO(p3) ops.py:1749  def launch_viz

# TODO(p3) ops.py:1766  def __init__

# TODO(p3) ops.py:1775  def pm_rewrite
#   # no cache needed: pm_rewrite is called at most once per UOp due to the replace dict check in unified_rewrite

# TODO(p3) ops.py:1777  def cached_bpm_rewrite

# TODO(p3) ops.py:1782  def walk_rewrite

# TODO(p3) ops.py:1808  def unified_rewrite

# TODO(p3) ops.py:1880  def graph_rewrite

# TODO(p3) ops.py:1885  def sint_to_uop

# TODO(p3) ops.py:1886  def to_max_shape

# TODO(p3) ops.py:1891  def resolve_returned_after

# TODO(p3) ops.py:1901  def gate_kernel_sink

# TODO(p3) ops.py:1907  def contiguous_bitcast_index


# ===========================================================================
# THE GATE. `main` builds a small graph in the arena and checks the four things
# the master plan says the trial run has to prove, so the answer is printed and
# can be diffed rather than asserted in prose.
#
#   1. HASH-CONSING. The same (op, src, arg, tag) twice is ONE node and the
#      index is the same number. This is `UOpMetaClass.ucache`, and it is what
#      makes `UOp.__eq__` identity.
#   2. THE KEY SEPARATES DTYPES. "a CONST's dtype is the type of its arg, and
#      True == 1 as dict keys" -- CBool and CInt are two nodes.
#   3. A CYCLE. A node whose src is a LATER index is a legal arena state. That
#      is the back-edge the range graph makes and the whole reason this is an
#      index and not a tree.
#   4. A TOPOSORT over the acyclic part in DFS postorder, and the same walk over
#      a cycle TERMINATING instead of looping.
# ===========================================================================

# CONST(3) interned, and the arena that holds it.
def g_const() -> Found:
  UOp.const(Arena.empty(), CInt{H.i64_of_i32(3)})

# RANGE(1) over CONST(1) -- the device range the SPECIAL below names.
def g_rng() -> Found:
  +c0 = UOp.const(Arena.empty(), CInt{H.i64_of_i32(1)})
  UOp.range_end(Found.ar(c0), Found.i(c0), [1], AXIS_DEVICE{})

# SPECIAL("g") over that range.
def g_special() -> Found:
  +r = g_rng()
  UOp.special(Found.ar(r), Found.i(r), "g")

# a BACKEDGE over a SPECIAL, a RANGE and itself: the cycle.
def g_cycle() -> Found:
  +sp = g_special()
  +r = g_rng()
  UOp.backedge(Found.ar(sp), Found.i(sp), Found.i(r), Found.i(sp))

# CONST(0) <- RANGE(0) <- ADD <- RANGE(0): four nodes, a DAG.
def g_chain() -> Found:
  +c0 = UOp.const(Arena.empty(), CInt{H.i64_of_i32(0)})
  +r0 = UOp.range_end(Found.ar(c0), Found.i(c0), [0], AXIS_LOOP{})
  +a0 = UOp.alu(Found.ar(r0), OpsADD{}, [Found.i(r0), Found.i(c0)])
  UOp.range_end(Found.ar(a0), Found.i(a0), [0], AXIS_GLOBAL{})

def t_hashcons() -> Bool:
  # the same key again, on the arena that already holds it
  +f = g_const()
  +again = UOp.const(Found.ar(f), CInt{H.i64_of_i32(3)})
  Bool.and(U32.is_eq(Found.i(f), Found.i(again)),
    U32.is_eq(Arena.next(Found.ar(again)), U32.add(Found.i(f), 1)))

def t_dtype_key() -> Bool:
  +f = g_const()
  +b = UOp.const(Found.ar(f), CBool{True{}})
  Bool.not(U32.is_eq(Found.i(f), Found.i(b)))

# the BACKEDGE reads back as itself: src[0] is the SPECIAL and src[1] the RANGE
# whose arg names the axis it closes over. Python's IndexError on a short src is
# the 0 that `Arena.src` answers.
def t_cycle() -> Bool:
  +f = g_cycle()
  +ar = Found.ar(f)
  +sp = g_special()
  +s = Found.i(sp)
  +be = Found.i(f)
  Bool.and(Bool.and(Bool.and(U32.is_eq(Arena.src0(ar, be), s), U32.is_eq(Arena.src(ar, be, 1), Found.i(g_rng()))),
    eq_op(Arena.op(ar, s), OpsSPECIAL{})), eq_op(Arena.op(ar, Arena.src(ar, be, 1)), OpsRANGE{}))

def t_toposort() -> Bool:
  +f = g_chain()
  +ar = Found.ar(f)
  # every node is pushed at most twice, so 2 * len(arena) steps always suffice
  o = UOp.toposort(U32.to_nat(U32.mul(Arena.next(ar), 2)), ar, Found.i(f))
  Nat.is_eq(List.length(&2, U32, o), 5n)

# the same walk over a cycle must terminate. The fuel is what makes that true,
# and it answers the partial set rather than looping: `case 0n:` in `toposort`.
def t_cycle_terminates() -> Bool:
  +f = g_cycle()
  +o = UOp.toposort(64n, Found.ar(f), Found.i(f))
  Bool.and(Bool.not(Nat.is_eq(List.length(&2, U32, o), 0n)), Nat.is_le(List.length(&2, U32, o), 8n))

# the ucache key is compared component by component, and this is the whole of
# `eq_node`: same op, same srcs, same arg, same tag is the same node.
def key_same(p: Node, q: Node) -> Bool: eq_node(p, q)

def t_key_eq() -> Bool:
  Bool.and(Bool.and(key_same(Node{OpsADD{}, [1, 2], ANone{}, TNone{}}, Node{OpsADD{}, [1, 2], ANone{}, TNone{}}),
    Bool.not(key_same(Node{OpsADD{}, [1, 2], ANone{}, TNone{}}, Node{OpsADD{}, [1, 3], ANone{}, TNone{}}))),
    Bool.not(key_same(Node{OpsADD{}, [1, 2], ANone{}, TNone{}}, Node{OpsADD{}, [1, 2], ANone{}, TStr{"t"}})))

# --- the UPat arena ---------------------------------------------------------
# Four claims, each a decision rather than a transliteration, so each is checked.
# `pat_base` is the fixture: a pattern arena holding ONE named var at index 0, so
# every later index is a real child. Without it `List.get` misses, the sugar
# falls to its no-input branch, and the test passes for the wrong reason.
def pat_base.of(f: PatFound) -> Pat:
  PatFound.pat(f)


def pat_base() -> Pat:
  pat_base.of(UPat.var(Pat{[]}, Some{"x"}, None{}))


# all three from ONE arena, threaded: `x` lands at 0, `x` again must still be 0,
# and `y` must be 1. Two SEPARATE arenas would make every index 0 and the test
# would pass for the wrong reason, so the arena is threaded rather than rebuilt.
def t_var_interns.y(+x1: PatFound, +x2: PatFound, y1: PatFound) -> Bool:
  Bool.and(U32.is_eq(PatFound.i(x1), PatFound.i(x2)),
           Bool.not(U32.is_eq(PatFound.i(x2), PatFound.i(y1))))

def t_var_interns.go(+x1: PatFound, +x2: PatFound) -> Bool:
  t_var_interns.y(x1, x2, UPat.var(PatFound.pat(x2), Some{"y"}, None{}))

def t_var_interns.of(+x1: PatFound) -> Bool:
  t_var_interns.go(x1, UPat.var(PatFound.pat(x1), Some{"x"}, None{}))

def t_var_interns() -> Bool:
  t_var_interns.of(UPat.var(Pat{[]}, Some{"x"}, None{}))




# `src=self` in `broadcast` is `itertools.repeat`, so ONE unbounded alternative --
# never an infinite list -- and `required_len` 0, because the read is bounded by
# `strict_length` being False instead.
def t_broadcast_repeats.of(alts: List<&2, UpAlt>) -> Bool:
  match alts:
    case Nil{}: False{}
    case UpRepeat{x} <> _: U32.is_eq(x, 0)
    case UpFixed{_} <> _: False{}
def pat_nth.of(hit: Maybe<&2, UPat>) -> UPat:
  match hit:
    case Some{u}: u
    case None{}: UPat{None{}, None{}, None{}, None{}, None{}, SNone{}, Nil{}, False{}, False{}, 0, Nil{}}

def pat_nth(+f: PatFound, n: U32) -> UPat:
  pat_nth.of(List.get(&2, UPat, Pat.upats(PatFound.pat(f)), U32.to_nat(n)))


def t_broadcast_repeats.go(+f: PatFound) -> Bool:
  t_broadcast_repeats.of(UPat.src(pat_nth(f, PatFound.i(f))))

def t_broadcast_repeats() -> Bool:
  t_broadcast_repeats.go(UPat.broadcast(pat_base(), 0))



# `required_len` is 0 for the repeat case and the src LENGTH otherwise.
def t_required_len.of(rep: UPat, tup: UPat) -> Bool:
  Bool.and(U32.is_eq(UPat.required_len(rep), 0), U32.is_eq(UPat.required_len(tup), 1))

def t_required_len() -> Bool:
  t_required_len.of(pat_nth(UPat.broadcast(pat_base(), 0), 1),
                    pat_nth(UPat.f(pat_base(), 0, OpsADD{}), 1))


# a list src of two DISTINCT patterns permutes, so `alu(ADD, ...)` -- ADD is in
# `GroupOp.Commutative` -- has TWO alternatives. `OpsCAST` is not, so it keeps
# its tuple order and has ONE.
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



# `early_reject` reads only the FIRST alternative, and only patterns whose `op`
# is a single Op. A `cvar` is `op=(CONST,)`, so wrapping one in an `f` yields
# exactly one rejected op.
def t_early_reject.of(ers: List<&2, Op>) -> Bool:
  U32.is_eq(U32.from_nat(List.length(&2, Op, ers)), 1)


# a `cvar` is `op=(CONST,)`, which is what `early_reject` collects
def pat_base_op.of(f: PatFound) -> Pat:
  PatFound.pat(f)

def pat_base_op() -> Pat:
  pat_base_op.of(UPat.cvar(Pat{[]}, Some{"c"}, None{}, None{}))

def t_early_reject() -> Bool:
  t_early_reject.of(UPat.early_reject(pat_nth(UPat.f(pat_base_op(), 0, OpsADD{}), 1)))




# Bend has no assertion form, so `main` PRINTS each answer and the gate is that
# both lanes print the same lines. A `False{}` anywhere is the failure.
def row(nm: String, b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(b)]))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("hashcons", t_hashcons())
    b : Unit <- row("dtype_key", t_dtype_key())
    c : Unit <- row("cycle", t_cycle())
    d : Unit <- row("toposort", t_toposort())
    e : Unit <- row("cycle_terminates", t_cycle_terminates())
    f : Unit <- row("key_eq", t_key_eq())
    g : Unit <- row("var_interns", t_var_interns())
    h : Unit <- row("broadcast_repeats", t_broadcast_repeats())
    i : Unit <- row("required_len", t_required_len())
    j : Unit <- row("alu_permutes", t_alu_permutes())
    row("early_reject", t_early_reject())

# ===========================================================================
# NOT PORTED -- tinygrad/uop/ops.py, and why. One line each, the same shape
# helpers.bend and dtype.bend use, and each with the phase that owns it.
#
# The Python-object machinery, all of which needs a runtime Bend does not have:
#   `UOpMetaClass.ucache` and its `weakref` eviction -- replaced by the arena
#     itself (`intern`), so this is not a loss but the mechanism is different.
#   `UOp.__del__`, `UOp.__reduce__`, `CallInfo.__reduce__`, `UPat.__reduce__` --
#     pickling and refcount-driven cache eviction. The arena is monotone and has
#     no destruction, so nothing is evicted and nothing needs pickling.
#   `_UOpTuple` -- a tuple subclass whose `__eq__` is identity, "so that tuple <
#     doesn't rescan deep equal prefixes with O(n) value equality at every level
#     of the walk". A `List` of `U32` arena indices has that property for free,
#     which is `UOp.tuplize`'s return type here (P3, with the sort it feeds).
#   `hashlib.sha256` in `UOp.key` -- a digest over the render. `key` is P3 with
#     the cache it keys; the C effect would be `tinygrad/runtime/`'s.
#   `pickle` in `deconstruct_function` and `PatternMatcher.__reduce__` -- Bend
#     has no code objects to pickle, and the rules become top-level defs
#     dispatched by a tag, which is what the master plan already prescribes.
#   `exec` in `_sym_fxn` -- it builds Python source from the graph and runs it
#     with a namespace of `max/cdiv/cmod/floordiv/floormod/bitcast/dtypes`.
#     Bend has no `eval` and no generated code, so `sym_infer` needs either a C
#     effect that compiles a lambda or a tree-walking interpreter. P3/P6.
#   `sys._getframe` in `get_location` and in `rewrite_group` -- a pattern's
#     source location. That is CPython's frame stack, and every `UPat` carries
#     a `location` that the viz and `print_match_stats` read. Rebuilt in P8 on
#     the `IO.now` clock, the same answer helpers.bend gives for the profiler.
#   `time.perf_counter` in `TrackedPatternMatcher.rewrite` -- the per-rule
#     timing. Same clock story as `cpu_profile` in helpers.bend; P8.
#   `atexit` + `diskcache_put` in `save_to_diskcache` and `print_match_stats` --
#     a pickled `RewriteTrace` on disk for the viz. The sqlite/pickle cache is
#     P6, and the viz is P8.
#   `os.execv` in `launch_viz` -- re-exec into `viz/serve.py`. P8.
#   `collections.Counter` in `gcd` and `divide_exact`, and `itertools` in
#     `split_uop`, `contract`, `broadcast_axes`, `argfix` and `_align_left` --
#     folds over Python iterables. Each becomes a Bend fold; P3, with the
#     symbolic helpers they serve.
#   `functools.reduce(operator.and_, ...)` in `gcd` -- the same.
#   `operator.neg/add/sub/mul/ne/lt/xor/or_/and_/rshift/lshift/max` in
#     `python_alu`, and `math.*` in `safe_exp2`/`safe_pow` -- the `python_alu`
#     table. F32 arithmetic is native in Bend and `F32.is_eq`/`is_lt` exist, so
#     this table is a match ladder; P3, with `exec_alu` (whose `tuple` operand
#     case is a vectorised ALIKE branch).
#   `math.inf` in `identity_element` and `_min_max` -- Bend cannot name an
#     infinity in a U32, so it is `F32.div(1, 0)`; the ONE place dtype.py's
#     `dt.min` for a float needs the seam, and `identity_element` above spells
#     it out.
#   `Buffer`/`MultiBuffer` in `UOp.buffer`, `UOp.realized`, `UOp._buffer_view`,
#     `new_buffer`, `from_buffer`, `_frompy`, `to_elf`, `TinyELF` and
#     `canonicalize_device` -- the device memory layer. P6, and `ParamArg.buffer`
#     is the slot they all read.
#   `Estimates` in `KernelInfo` -- the renderer's cost model, P5.
#   `Target` in `ProgramInfo` -- helpers.py's device-target record, already
#     listed as P6 in helpers.bend's own NOT PORTED block.
#   `grad_fxn` in `CallInfo` and `uopfunc` -- a Python function object; a Bend
#     closure is single-use and is a `Type`, so it cannot be a `Data` field.
#     The reverse-mode plumbing is `tinygrad/nn/gradient.py`, P7.
#   `aux` in `CallInfo` and `trace_num` -- the per-call side channel, written by
#     the hcq paths in `tinygrad/runtime/ops_*.py`, which are out of scope.
#   `uopfunc`'s `inspect.signature(fn).bind(...)` -- Python reflection over a
#     function object, used to turn uop arguments into params. P7 with the mixin.
#   `is_any`, `custom_early_reject`, `allow_any_len`, `permutations` and
#     `functools.repeat` in `UPat.__init__`, and `upat_compile` -- the pattern
#     COMPILER (`tinygrad/uop/upat.py`). `UPat` is PORTED (see ops.py:1447, with
#     a pattern arena of its own); the COMPILER is a separate file whose output is
#     a def per rule, so the machinery here dispatches a tag rather than calling
#     a compiled function pointer. `permutations` at arity >= 3 is the one part
#     of `__init__` not ported, and it is unreachable from ops.py.
#   `upat_interpret`'s `types.FunctionType(*deconstruct_function(fxn))` and
#     `inspect.signature(real_fxn).parameters` -- rebuilding a Python function
#     from its code object. Same answer as above: rules are top-level defs.
#   `REWRITE_STACK_LIMIT` and the `BottomUpGate` exception in
#     `RewriteContext.unified_rewrite` -- the stack limit is a fuel budget here
#     (the same `case 0n:` the walks use) and the gate is a value, because a
#     Bend def cannot raise. `BottomUpGate` therefore becomes a `Maybe` result
#     the driver inspects; P3, with the engine.
#   `ops.py`'s `SPEC > 1` block in `UOpMetaClass.__call__` -- `spec_full.rewrite`,
#     `created._shape` and `test_pyrender`. That is `tinygrad/uop/spec.py`, P3,
#     and `dtype_from_uop`'s `None` is the check in the form this port states.
#   `Ops` reverse lookup (`Ops("ADD")`) and `AxisType` reverse lookup -- not
#     called by ops.py; `AxisType.of` is here anyway because `range_str` needs
#     a name and a test needs a name.

