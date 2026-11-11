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
#      when one field holds nineteen unrelated things. `Arg` and `Tag` below
#      name all nineteen. Nothing is lost and the arms are compiler-checked.
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
#
# THE REBASE DEPENDENCY LIST -- what `78d482262` needs from the OTHER files.
#
# `78d482262` ("range AxisType is first / delete REDUCE/UNROLL") is 53 files and
# it is the pin's hard blocker: `tinygrad/codegen/opt/postrange.py` at the pin
# imports `axis_to_pos`, so re-vendoring upstream without re-porting the AxisType
# consumers fails at import. This file was the first candidate and it turned out
# to be a CROSS-FILE change, so here is the list an agent can sequence. Every
# line was read out of that commit's tree, not guessed from the diff.
#
# 16 of the 53 are under `tinygrad/`; one is this one. Of the other 15, ELEVEN read
# a symbol `78d482262` changed:
#
#   #  file                     needs from ops.py                        lines
#   1  codegen/__init__.py      axis_type, axis_id, `arg=(at, id, ...)`  45,162,166,170,184,190
#   2  codegen/gpudims.py       axis_type, axis_id                      39,40,53,55,56,66
#   3  codegen/simplify.py      axis_type, axis_id, range_start         3,9,26,33,68
#   4  codegen/opt/heuristic.py AxisType.UPCAST                         36
#   5  codegen/opt/postrange.py AxisType.UPCAST, axis_to_pos (DELETED)  14 and the -2 prefix
#   6  codegen/opt/search.py    AxisType.UPCAST                         15
#   7  schedule/indexing.py     range_start                             67
#   8  schedule/prepare.py      axis_id[0]                              114
#   9  schedule/multi.py        .ranges                                 11
#  10  schedule/rangeify.py     .ranges, `arg=(AxisType.WEAK, n)`       36,191
#  11  runtime/support/hcq2.py  custom_function(dtype=), axis_id, axis_type  69,87,283,336,429,467
#  12  uop/render.py            axis_id, axis_type, .ranges             51,96,101,102
#  13  uop/spec.py              CustomFunction, axis_type               4,34,110,271,290
#  14  nn/__init__.py           AxisType.WEAK                           340
#  15  llm/kernels/amd.py       contiguous_view                         82
#
# `tinygrad/uop/__init__.py` (`Ops`, `GroupOp`) is NOT among the 53 at all, so
# this file's other import surface is unmoved and nothing here waits on that half
# of the commit. The remaining 37 files in the 53 are `test/`, `extra/`,
# `docs/`, `spec/` and `llm/` kernels, which are out of scope for the port.
#
# three things the list says that a diff would not.
#
#   * `uop/spec.py`'s RANGE-arg predicate MOVED with the flip. Pin:
#     `all(isinstance(ra, int) for ra in rng.arg[0:-1]) and isinstance(rng.arg[-1], AxisType)`.
#     Upstream: `isinstance(rng.arg[0], AxisType) and all(isinstance(ra, int) for ra in rng.arg[1:])`.
#     MEASURED: the pin REJECTS the three-element arg and upstream ACCEPTS it.
#     `spec.py` is P3 here, so this is a row the CPython lane prints and the port
#     cannot -- `rngspec_*`, bend-only, reason in the oracle.
#   * `codegen/__init__.py:190` writes
#     `rr.replace(arg=(rr.axis_type, next_axis + j, *rr.axis_id[1:]))`. The SPLAT is
#     the load-bearing part: it only concatenates if `axis_id` is a TUPLE OF INTS,
#     i.e. the flat `(AxisType, int, ...)` arg. So `UOp.axis_id`'s RETURN TYPE is
#     forced by a file six levels away, and a port that returned the axis type with
#     the ids would break there. That is why the accessors above return two things.
#   * `runtime/support/hcq2.py:68,87` is `UOp.custom_function(name).call(...)` with
#     and without `dtype=`. Upstream that is `UOp(Ops.CUSTOM_FUNCTION, src=srcs,
#     arg=CustomFunction(name, dtype))`, and `CallInfo` LOST its `dtype` field
#     because the return dtype moved into the CUSTOM_FUNCTION's arg. The rebase
#     therefore also needs a `CustomFunction` datatype here and `CallInfo` re-cut.
#     HALF DONE 2026-10-03: the `CustomFunction` datatype landed, at ops.py's own
#     position, with `Arg`'s `ACustom` arm, `eq_customfunction` and
#     `UOp.custom_function` -- none of which needed the P6 hcq2 caller, since
#     `uop/spec.py:110`'s `isinstance(x.arg, CustomFunction)` needs the TYPE and
#     `uop/spec.bend`'s `sh_22` is stale without it. `CallInfo` re-cut is STILL
#     OPEN and is NOT a field delete: `spec.bend`'s `sh_23` reads `CallInfo.dtype`.
#     Both are in the NOT PORTED block at the foot of this file.
#
# THE REVERSE LIST -- who needs THIS file -- is the one that is not obvious, and
# it is the one that makes this a two-file change at minimum. `ARange`'s FIELD
# ORDER is read and written positionally by ELEVEN committed `.bend` files, listed
# at `UOp.range_end` below, and `AXIS_REDUCE`/`AXIS_UNROLL` are still constructed
# by SIX. Neither can move inside this file alone.

import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../renderer/estimates.bend as E
type Op is Data:
  #  1 -- defines/special 
  # this is a RANGE for GPU dimensions, similar to symbolic shapes but not exactly
  OpsSPECIAL{}
  # BUFFER references bound storage; ALLOC declares unbound global storage
  OpsBUFFER{}
  OpsALLOC{}
  #  2 -- non op uops 
  # uops that aren't rendered
  OpsNOOP{}
  OpsREWRITE_ERROR{}
  # CALL is a kernel invocation; value-producing calls write to ALLOC arguments
  OpsPARAM{}
  # REFERENCE A PARAM -- upstream `codegen/__init__.py:426` builds one when a param's addrspace is not ALU,
  # and every generic predicate that lists PARAM lists it too (`uop/__init__.py:114`'s `Defines`,
  # `ops.py:169`, `ops.py:350`, `ops.py:873`, `render.py:40`).
  OpsREFPARAM{}
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
  # vector creation / item selection
  OpsSTACK{}
  # hcq specific
  OpsGETADDR{}
  #  3 -- load/store 
  # INDEX is a BinaryOp similar to ADD, but it operates on pointers
  OpsINDEX{}
  OpsSHRINK{}
  # load/store before math
  OpsLOAD{}
  OpsSTORE{}
  #  4 -- math 
  # tensor core math op, not elementwise
  OpsWMMA{}
  # UnaryOps
  OpsCAST{}
  OpsBITCAST{}
  OpsEXP2{}
  OpsLOG2{}
  OpsSIN{}
  OpsSQRT{}
  OpsRECIP{}
  OpsNEG{}
  OpsTRUNC{}
  # BinaryOps
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
  # TernaryOps
  OpsWHERE{}
  OpsMULACC{}
  #  5 -- control flow / consts / custom 
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
  #  6 -- ops that don't exist in programs 
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
  # UNSHARD is really a movement op
  OpsUNSHARD{}
  # reduce
  OpsREDUCE{}
  OpsALLREDUCE{}
  #  7 -- pattern compiler IR (used in upat.py) 
  # PYLITERAL carries a Python literal as an arg for CUSTOM predicates
  OpsPYLITERAL{}

# FastEnum.__str__ and FastEnum.__repr__ are both `str(self)`, so one table --
# but `str(self)` is `Enum.__str__`, which is `"ClassName.MEMBER"`, and
# `Enum.name` is the BARE member name. CPython therefore has TWO strings per
# member and this file used to have one, which is the bug: `Ops.name` returned
# the bare one where its oracle is the prefixed one. So the bare table is
# `Ops.name.of` (this is `AxisType.name` too, which was always bare) and
# `Ops.name` is that plus the class name.
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

# AxisType -- tinygrad/uop/ops.py:17
#
# `def __repr__(self): return str(self)` in the Python, which exists only so a
# range's arg prints as a name. `Ops.RANGE`'s arg is `(axis_type, axis_id)`, so
# the type is a field of the arg and has to be a datatype here; `Ops.name` is
# the same trick one level up.
#
#
# REBASED ONTO `78d482262` ("range AxisType is first / delete REDUCE/UNROLL"),
# which is 53 files and the pin's hard blocker. Four upstream facts moved and all
# four are read by a CPython row now -- this block had NO CPython lane at all
# (`cpython=0`), which is how a wrong `AxisType.value` survived:
#
#   * upstream's order is `device, global, local, warp, weak, LOOP, upcast,
#     placeholder`. The pin was `device, global, warp, local, weak, reduce,
#     UPCAST, UNROLL, PLACEHOLDER`, so FOUR of the eight surviving values moved
#     and two members were deleted outright.
#   * `AxisType.__lt__` was ADDED ("Nesting order: RANGE args sort by axis type,
#     then axis id"). It is `AxisType.lt` below. `__le__`/`__ge__` were NOT
#     added, and there is no row pretending otherwise -- see `axlt_le`/`axlt_ge`
#     in the gate, which are BEND-ONLY and say why.
#   * `axis_to_pos` is DELETED. The port's copy is deleted with it, and nothing
#     in the repo called it -- a grep for `axis_to_pos` over every `.bend` returns
#     this block and nothing else, so the deletion is complete and the `Pos`
#     record goes with it.
#   * `axis_colors` changed `WEAK`/`LOOP` from "WHITE" to "red" -- the colour of a
#     range the renderer now folds into the enclosing one, so it renders as part
#     of it rather than as its own bar.
#
# the one thing this block does not fix, and it is a theorem rather than a choice.
#
# `AXIS_REDUCE` and `AXIS_UNROLL` are DELETED upstream but they are still CONSTRUCTED
# by six committed files, so they cannot be deleted here:
#     schedule/indexing.bend:1448 symbol=g_nr            codegen/kernel.bend:418 symbol=kn_unroll.ax
#     codegen/kernel.bend:1002 symbol=kn_fixture       codegen/late/linearizer.bend:877 symbol=lt_fix
#     codegen/opt/heuristic.bend:159 symbol=reduce_k   codegen/opt/heuristic.bend:162 symbol=matmul_k
#     codegen/opt/postrange.bend:160 symbol=split_targets   codegen/opt/search.bend:418 symbol=zero_variant.dead
# and three of those six are under `codegen/opt/*`, which another unit owns and which
# is mid-edit. So the enum here has TEN members where CPython has EIGHT.
#
# That makes `AxisType.value` A PROVABLE PARTIAL, and the argument is short. An
# `auto()` Enum's value is its index in the member list, so a TEN-member enum
# cannot carry upstream's eight values: the two retained members need two numbers,
# and every number in 1..8 is already one of upstream's. Therefore EITHER two
# survivors get the wrong number OR two survivors collide and `eq_axis` answers
# True for two different axis types -- which silently merges two RANGE args in the
# ucache. THIS FILE CHOSE THE FORMER: the eight survivors take upstream's exact
# numbers, and the two dead ones take 9 and 10, slots upstream does not use at all.
# They are therefore DISTINCT from every live value and from each other, which is
# the only property `eq_axis` needs -- and the gate proves it, with
# `eqax_distinct` over all pairs and one `axv_*` row per member.
#
# So `axv_LOCAL=3` and `axv_WARP=4` are FIXED here, and `axv_LOOP=6` /
# `axv_PLACEHOLDER=8` are fixed for the same reason. What is left is the two DEAD
# members' numbers, which are not an upstream fact at all because upstream has no
# such member. When the six consuming files land, delete the last two constructors,
# this paragraph, and nothing else -- no other value moves.

type AxisType is Data:
  AXIS_DEVICE{}
  AXIS_GLOBAL{}
  AXIS_LOCAL{}
  AXIS_WARP{}
  AXIS_WEAK{}
  AXIS_LOOP{}
  AXIS_UPCAST{}
  AXIS_PLACEHOLDER{}
  # DELETED UPSTREAM by 78d482262 and retained only because six committed files
  # still construct them. See the theorem above. No CPython row can ask for these
  # two: at the tree this gate reads they do not exist, so `axv_REDUCE` /
  # `axv_UNROLL` are BEND-ONLY rows and say so.
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

# THE MEMBER LIST, in the order the `type` above declares it. This is what the
# `#shared_axis_*` derivation rows are built from and what `eqax_distinct` walks, and
# it is a `List` rather than ten open-coded rows because CPython's answer is
# `list(AxisType)` -- ONE fact about the enum rather than ten facts about a ladder, so
# a member added to the `type` without a row here shows as a LENGTH diff rather than as
# a silent agreement about the wrong set.
def AxisType.all() -> List<&2, AxisType>:
  [AXIS_DEVICE{}, AXIS_GLOBAL{}, AXIS_LOCAL{}, AXIS_WARP{}, AXIS_WEAK{}, AXIS_LOOP{},
   AXIS_UPCAST{}, AXIS_PLACEHOLDER{}, AXIS_REDUCE{}, AXIS_UNROLL{}]

# `AxisType` is an `auto()` Enum, so its value is its position in the member list,
# exactly as `Ops.value` below. The eight live members carry upstream's numbers and
# the two dead ones take the two slots above them; see the theorem above.
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
# other.value`, so it is `AxisType.value` order and nothing else. There was no
# `__lt__` at the pin and `sorted(list(AxisType))` raised `TypeError` there, which is
# why the oracle prints `axlt_sorted=!TypeError` on the pin tree and a name sequence on
# the upstream one: the SORT is the addition, measured rather than asserted.
def AxisType.lt(x: AxisType, y: AxisType) -> Bool:
  U32.is_lt(AxisType.value(x), AxisType.value(y))

# axis_letters / axis_colors -- ops.py:51,53. Two dictionaries keyed by an Enum, two
# `match` ladders. upstream drops the `REDUCE`/`UNROLL` entries and adds nothing, so
# PLACEHOLDER -- in the enum and in neither dict -- and the two dead members are all
# MISSES. A Bend def cannot raise, so the miss is ANSWERED rather than swallowed: both
# ladders return `"!KeyError"`, the name of the exception Python raises, which is the
# same treatment `ABad{}` gives `self.src[0]` on an empty src. Returning `""` would
# have been a silent widening -- indistinguishable from a member whose letter really is
# empty -- and there is no such member, so the marker is free of false agreement.
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

# `WEAK` and `LOOP` are "red" upstream, not the pin's "WHITE". A red range is one the
# renderer folds into its parent, so it draws as part of the parent rather than as a
# bar of its own; that is a rendering decision and `uop/render.bend` is where the
# colour is consumed.
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
# the literal `0` at the four call sites that read it (`_shard`'s device range,
# `device_range_src`, and `axis`'s default), because "RANGE args sort by axis type,
# then axis id" makes the position redundant with the TYPE. The `Pos` record went with
# it: it existed only because the dict's values were negative and Bend has no signed
# integer, and the remaining values are all non-negative literals.
#
# The `xpos` gate rows are how this deletion is CHECKED rather than claimed: CPython's
# `hasattr(ops, 'axis_to_pos')` is False, and `ops-gate.sh` additionally greps the Bend
# source for the symbol and fails if it is still there -- because a def Bend cannot
# print as "absent" is exactly the case where a claim in a comment is not a gate.

# range_start -- ops.py:56. `range_start[self.op]` is a slice offset, so it is a
# ladder and Python's KeyError is the `case _` arm.
#
# UNCHANGED by 78d482262, and the gate now says so from CPython rather than from this
# comment: `axs_*` is one row per op in the dict PLUS one for an op that is not in it
# (`Ops.NOOP`), because `ended_ranges` asks `if self.op in range_start` and a miss is a
# real answer there. `Ops.LINEAR`'s answer is 0 and the miss is also 0, so without the
# marker row a dropped `LINEAR` entry and a dropped `NOOP` entry would be the same
# string; `range_start_str` is what keeps them apart.
#
# DEAD CLAIM, MEASURED. This `U32` ladder has NO CALLER in the port -- `ended_ranges` is
# P3 -- and the rows read `range_start_str` instead. Mutation M14 of
# `.agents/slop/ops-mutate.py` breaks this ladder (`STAGE 1 -> 0`) and moves NOTHING,
# which is the "a def nothing calls is invisible to every other check" rule landing
# inside this file. It is NOT deleted because it is a ported Python symbol that
# `ended_ranges` needs the moment it lands, and deleting it would move the break to P3.
# The fix is a caller, not a deletion, and it is recorded here so the next reader knows
# the ladder is currently unchecked.
def range_start(op: Op) -> U32:
  match op:
    case OpsSTAGE{}: 1
    case OpsREDUCE{}: 1
    case OpsEND{}: 1
    case OpsCALL{}: 1
    case OpsLINEAR{}: 0
    case _: 0

# `range_start` AS A ROW. `range_start` answers a `U32` and a miss is 0, which is also
# `Ops.LINEAR`'s answer, so the U32 alone cannot say whether an op was NAMED. This is
# the printer the `axs_*` rows use: `U32.show` for a hit and the exception's name for a
# miss, which is what CPython's `range_start[op]` in a `try` prints. This is a GATE
# PRINTER, not a ported def -- it has no counterpart in ops.py.
def range_start_str(op: Op) -> String:
  match op:
    case OpsSTAGE{}: "1"
    case OpsREDUCE{}: "1"
    case OpsEND{}: "1"
    case OpsCALL{}: "1"
    case OpsLINEAR{}: "0"
    case _: "!KeyError"

# Const -- tinygrad/dtype.py: `PyConst = float|int|bool`, and `InvalidType` is
# a singleton, so `ConstType = PyConst|InvalidType`.
#
# THE ORDER MATTERS in `dtype_from_uop`'s CONST arm, which says so in Python:
# "order matters: bool is an int subclass, ConstFloat is a float subclass". The
# ladder there is written in the same order.
#
# ints are `H.I64`, Python's unbounded int under the port's 64-bit cap, because
# a CONST carries -1 and 2**40 and a U32 has neither.

type Const is Data:
  CBool{b: Bool}
  CInt{i: H.I64}
  CFloat{f: F32}
  CInvalid{}

# `Sint` is ops.py:1923 symbol=sint -- `sint = int|UOp`, spelled out. It is the element type
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

# ParamArg -- tinygrad/uop/ops.py:22
#
# The `arg` of a BUFFER, ALLOC or PARAM: thirteen fields, nine of them optional.
# Python's `X|None` is a union with None, so each one is a `Maybe` here and
# every Python field comment is kept.
#
# two fields are not what the name says in BEND, for the same reason: both hold
# a Python object this port has not built, and a handle is a `Type` so it cannot
# be a `Data` field.
#   * `buffer: Buffer|MultiBuffer|None` -- the 1:1 UOp/Buffer pairing. It is a
#     `Maybe<&1, U32>` slot into the device allocator, which is P6. It is a real
#     slot, not a placeholder: `UOp.buffer`, `UOp.realized` and the ucache key
#     all read it.
#   * `device: str|tuple[str, ...]|None` -- a device NAME or a tuple of them, so
#     it is `S.Dev` (spec.bend's `D1{tag}` / `Dn{tags}`). and the tag is not one per
#     NAME, which the field's own comment used to claim: `device.bend:344 tag_of` is
#     a THREE-VALUED sentinel (DISK 6, NPY 10, PYTHON 13, everything else 0), so
#     CPU, metal, AMD, NV, CUDA, qcom, CL, dsp, WEBGPU and every typo share 0.
#     `device_vocab_holds` reads that arm list out of `device.bend`'s CODE every run,
#     and `gates/devtag-gate.py` reads the VALUES out of it as well. THE NAMES PLUG IN
#     AT A `U32 -> String` TABLE (P6), and it is THE PORT'S OWN to mint: CPython has
#     no `str -> int` device index to mirror -- this very field is `str|tuple[str,
#     ...]|None` (`uop/ops.py:34`) and `device.py:29`'s table is string-keyed. See
#     `spec.bend`'s `is_device` note for all six witnesses.

type ParamArg is Data:
  ParamArg{slot: U32, dtype: S.Dt,
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

# The three arg payloads, moved UP from ops.py:1339-1404.
#
# They are moved because `Arg` holds them and `eq_arg` -- the ucache key --
# compares them, and Bend resolves a call at compile time while Python resolves
# a lambda at call time. Their order AMONG THEMSELVES is Python's: KernelInfo,
# ProgramInfo, OPAQUE_CALL_BODIES, CallInfo. The METHODS of ProgramInfo
# (`launch_dims`, `vals`, `from_sink`) stay down at ops.py's position, because
# they read UOps.

# opt/__init__.py: `OptOps` and `Opt` (with its `arg`), MOVED DOWN from
# `codegen/opt/postrange.bend` because `KernelInfo` below CARRIES them and
# `postrange.bend` imports THIS file -- a file cannot import its own importer, so
# the types live at the bottom. `postrange.bend` reads them as `O.OPTOPS` /
# `O.OPT` / `O.SPL` / `O.OPTARG`; `search.bend` and `heuristic.bend` reach them
# through `postrange` and are unchanged.
type OPTOPS is Data:
  OPS_TC{}
  OPS_SPLIT{}
  OPS_PADTO{}
  OPS_SWAP{}

# `auto()` numbering is the declaration order, and `OptOps.__lt__` is the only
# reader of it -- which nothing calls. Kept anyway: it is the enum's documented value.
def OPTOPS.value(o: OPTOPS) -> U32:
  match o:
    case OPS_TC{}: 1
    case OPS_SPLIT{}: 2
    case OPS_PADTO{}: 3
    case _: 4

# `Opt.arg: int|tuple|None`. `SPL` and `TC` ARE that arg's TWO TUPLE SHAPES, as
# records: `apply_opt` reads two of the three split fields at once and a `U32`
# cannot be `+`, so the pair travels as the `Data` record Python already had it as.
# `top: Maybe<&2, Bool>` because upstream's split arg is a 2-tuple `(amt, target)`
# or a 3-tuple `(amt, target, top)` (`postrange.py:114` checks `len(opt.arg) in
# (2, 3)` and `:115` defaults `top` to False), and the canonical form prints WHICH.
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

# `axis: int|None` in Python, but NO construction site in `search.py`,
# `heuristic.py` or `postrange.py` passes None, so `axis` is a `U32` here and the
# `check(opt.axis is not None)` is vacuous. If a `None` axis ever appears, `axis`
# needs a `Maybe` and this record a `Bool` beside it, not an `OA_NONE` arg.
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
#
# They are moved because `Arg` holds them and `eq_arg` -- the ucache key --
# compares them, and Bend resolves a call at compile time while Python resolves
# a lambda at call time. Their order AMONG THEMSELVES is Python's: KernelInfo,
# ProgramInfo, OPAQUE_CALL_BODIES, CallInfo. The METHODS of ProgramInfo
# (`launch_dims`, `vals`, `from_sink`) stay down at ops.py's position, because
# they read UOps.

# KernelInfo -- ops.py:1339. six fields, upstream's six, in upstream's order:
# `name, applied_opts, opts_to_apply, estimates, beam, optimized`.
#
# `estimates` IS PORTED AS A FIELD. `Estimates` is `tinygrad.renderer`'s cost
# model, so the record lives in `renderer/estimates.bend` -- A LEAF -- because
# upstream's own `ops.py:26` imports it under `TYPE_CHECKING` and Bend REFUSES
# AN IMPORT CYCLE. The value is `None` in every `KernelInfo` this port builds,
# because `do_estimates` -- upstream's only writer, `codegen/__init__.py:446` --
# is a WALL in `codegen/kernel.bend`. `optimized` is `False` in every one too:
# upstream's only writer is `runtime/support/hcq2.py:295` and the port's
# `hcq2.bend` builds no `KernelInfo`. A FIELD THAT IS ALWAYS ABSENT IS NOT A
# LIE; A MISSING FIELD IS -- the record was FOUR against upstream's SIX, so
# `repr` could not answer CPython's.
#
# `applied_opts`/`opts_to_apply` ARE `List<&2, OPT>` and not `List<&2, U32>`:
# upstream's elements are `Opt` dataclasses (pin ops.py:1342,1343 `tuple`), and
# `--graph lin` carries one, MEASURED by calling the py side,
#   SINK applied_opts=(Opt(op=OptOps.SPLIT, axis=2, arg=(0, AxisType.UPCAST)),)
# which is `heuristic.py:109`'s own `Opt(OptOps.SPLIT, axis, (0, AxisType.UPCAST))`.
# A `U32` could not hold it, so the canonical row printed one ledger `q` per option
# and the CONTENT was unobservable -- MEASURED, changing a fixture's payload `0` to
# `7` moved no byte. `OPT` now lives above.
type KernelInfo is Data:
  KernelInfo{name: String, applied_opts: List<&2, OPT>, opts_to_apply: Maybe<&2, List<&2, OPT>>,
    estimates: Maybe<&2, E.Estimates>, beam: U32, optimized: Bool}

def KernelInfo.of() -> KernelInfo:
  # name: str = "test"            # name of the kernel
  KernelInfo{"test", Nil{}, None{}, None{}, 0, False{}}

# `Target` -- tinygrad/helpers.py:198. `device, renderer, arch, interface, indices`,
# and the port spells `interface` as `iface` (which is what
# `runtime/ops_python.bend:2785 symbol=fx` already does).
#
# the record is not declared here. It is declared once, in `helpers.bend` -- the
# `Target` record, in upstream's field order -- which is upstream's own home,
# `helpers.py`. This file reaches it as `H.Target` through the alias it ALREADY
# imports `helpers.bend` under. `helpers.bend` is a LEAF: it imports `Base` and
# nothing else, so the edge `ops.bend -> helpers.bend` was already there and NO
# CYCLE IS CLOSED.
#
# this file used to declare its own `Target`, and the reason it gave was a cycle
# that does not exist. The local copy was placed here because
# ``runtime/ops_python.bend`'s IMPORT BLOCK (`import ../uop/ops.bend as O`)` imports `../uop/ops.bend`, so `ops.bend` cannot
# import `runtime/ops_python.bend` -- TRUE, AND IRRELEVANT, because the record
# never had to come from there. Two records with the same five fields and
# DIFFERENT identities are two types: a `H.Target.parse`d target could not go
# into a `ProgramInfo`, and the round trip (`gates/target-roundtrip.bend` --
# twenty rows against CPython's own `Target.parse` and `ProgramInfo`) could not
# be typed at all. MEASURED, before this change: the round trip gate answered
# `expected : O.Target`, and the census gate answered "2 `type Target is Data:`
# declaration(s)".
#
# THE DEFAULT IS THE OTHER FILE'S. Upstream's `ProgramInfo.target: Target =
# Target()` is the dataclass default of FIVE EMPTY STRINGS, and the port spells
# the nullary constructor `of`, as `ProgramInfo.of` and `VarVals.new` do -- so it
# is `H.Target.of()`, and it is the ONLY one. This file's own `Target.of()` is
# gone, so there is no second default to keep in step.

# ProgramInfo -- ops.py:1343. SEVEN fields, and the SEVENTH is `target: Target`.
#
# `target` was ABSENT because the CONSTRUCTOR was: upstream's `from_sink`
# (`ops.py:1358`) takes a `target` argument and there was no `from_sink`, so
# there was no argument to drop and no value to store. `from_sink` is ported
# below, so the field is here.
#
# THE OTHER SIX ARE UNCHANGED. `global_size` is `tuple[int|float, ...]`, so its
# elements are `H.I64`: an int is an I64 and a float is not a shape, so the
# float case in `sym_infer` is recorded on `sym_infer` itself.
type ProgramInfo is Data:
  ProgramInfo{global_size: List<&2, H.I64>, local_size: List<&2, H.I64>, params: List<&2, U32>, globals: List<&2, U32>, outs: List<&2, U32>, ins: List<&2, U32>, target: H.Target}

def ProgramInfo.of() -> ProgramInfo:
  ProgramInfo{[H.i64_of_i32(1), H.i64_of_i32(1), H.i64_of_i32(1)], [H.i64_of_i32(1), H.i64_of_i32(1), H.i64_of_i32(1)], Nil{}, Nil{}, Nil{}, Nil{}, H.Target.of()}

# `var_vals: dict[str, int]` -- a `Map` is string-keyed in Bend, which is the
# one place Python's dict and Bend's Map agree without an encoding, so it is
# used directly. `Map` is a `Type`, so it is affine and threaded, exactly like
# the arena.
# `Data` and NOT `Type`, and it was the ONLY `is Type` in this file -- every other
# record here is `is Data`, and `Type` is a kind, not a value. It compiled for as
# long as it existed because NOTHING CALLED IT: `ProgramInfo.vals` was a marker, so
# the one def that takes a `VarVals` never typechecked and the declaration was never
# exercised. `Map.has` wants a Data and `vv_of` passed a Type, which is the error
# that finally noticed.
#
# So: a declaration nobody calls is not checked, and the file compiled green for the
# whole time. That is the argument for a mutation table over a gate on defs.
type VarVals is Data:
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

# CustomFunction -- ops.py:1394-1397 upstream. NOT AT THE PIN: `git show
# 6c3d401cf324:tinygrad/uop/ops.py | grep CustomFunction` returns NOTHING, so at the
# pin a CUSTOM_FUNCTION's arg was a bare `str` (ops.py:1256,
# `UOp(Ops.CUSTOM_FUNCTION, src=src, arg=name)`) and this class did not exist. It is
# here because `uop/spec.py:110` now reads `isinstance(x.arg, CustomFunction)` and
# `uop/spec.bend`'s `sh_22` is stale against that until this lands.
#
# TWO FIELDS, and both are load-bearing, which is why this is a record and not the
# `str` it replaced:
#   name: str                    the external function's SYMBOL. `hcq2.py:84` writes
#                                it from `fn.__name__`, so `ccall(SELNAME, sel)`
#                                becomes `custom_function("sel_registerName")`.
#   dtype: DType = dtypes.void   the dtype of the VALUE THE FUNCTION RETURNS. This
#                                field is the whole reason the class exists:
#                                `dtype_from_uop`'s CUSTOM_FUNCTION arm (ops.py:133)
#                                is `return arg.dtype`, and upstream MOVED
#                                `CallInfo.dtype` here to make it so. `CallInfo` here
#                                has NOT been re-cut to match -- see the `CallInfo`
#                                block below for the commit that took the field back
#                                and the eleven sites a delete costs.
# The dataclass is `frozen=True` with no `__eq__` of its own, so structural equality
# over BOTH fields -- measured, not assumed: `CustomFunction("f") ==
# CustomFunction("f", dtypes.uint64)` is False and so is a name change, which is what
# the ucache key needs (`UOp.custom_function("f") is not UOp.custom_function("f",
# dtypes.uint64)` is True: the return dtype SPLITS the cache, as `type(arg)` split
# the `AStr` and `ACustom` constructors did for `eq_arg`).
type CustomFunction is Data:
  CustomFunction{name: String, dtype: S.Dt}

# the default arm, upstream's `CustomFunction(name)`. `UPat.custom_function`
# (ops.py:1509) builds exactly this value -- `arg=CustomFunction(fn)`, dtype void.
def CustomFunction.of(name: String) -> CustomFunction:
  CustomFunction{name, S.void()}

# CallInfo -- ops.py:1391. TWO FIELDS DROPPED, and both for the same reason:
#   * `grad_fxn: Callable|None` is a Python function object. Bend has no
#     function values except a closure, and a closure is single-use and is a
#     `Type`, so it cannot be a `Data` field. The reverse-mode plumbing that
#     calls it is tinygrad/nn/gradient.py, P7.
#   * `aux: Any` is the per-call side channel, written by the hcq paths in
#     tinygrad/runtime/ops_*.py, which are out of scope (P6, hardware we do not
#     have). Nothing in this file reads it except `__reduce__`.
# `dtype: S.Dt` is a fourth field upstream does not have, and this comment used to
# read "IS read: by `dtype_from_uop`'s CALL arm and by `_shape`'s". THAT CITATION IS
# FALSE and it names a function and a shape, which is why it looked like it confirmed
# THE FIELD. MEASURED:
#   * `tinygrad/uop/ops.py:130-132` is `case Ops.CALL:` / "a call has the dtype of its
#     body, void for opaque bodies" / `return src[0].dtype` -- it reads the BODY.
#     It never reads `CallInfo`.
#   * `git log -S'dtype: DType = dtypes.void' -- tinygrad/uop/ops.py` returns exactly
#     ONE commit, `6f4bfde23` "restrict allowed call bodies (#17925)", 2026-09-02 --
#     and that commit's hunk is `+  dtype: DType = dtypes.void`, so it ADDS the field.
#     `git show HEAD:tinygrad/uop/ops.py` has FIVE `CallInfo` fields and none is
#     `dtype`. the port is pinned to a commit upstream has since moved past.
#   * `tinygrad/uop/spec.py:112` at HEAD is `lambda x: isinstance(x.arg, CallInfo)` --
#     a pure TYPE test. `spec.bend`'s `arg_call` still answers HEAD's pre-`6f4bfde23`
#     `x.dtype is x.arg.dtype` half, so THAT citation is stale the same way.
# the cost of not knowing this is measured, and it is the corpus's only live `?`:
# `--graph loop`'s CALL#25 renders `dtype=? shape=?` because the fold never settles
# that node (`settled=False` in `graphcmp.bend`'s own header). Deleting this field
# moves the `arg` chunk to `cI(shcq_fence,b0,b0)` -- byte-identical to CPython -- and
# leaves `? ?` exactly where it was, so the field and the `?` are TWO defects.
# A delete costs ELEVEN sites in SEVEN files, four of them in this one: the type, the
# three accessors, `eq_callinfo`, `CallInfo.of`, `sg.ci` and `sg.arena` here, plus
# `fold.bend`'s `call_dt`/`call_ds` (repoint the CALL's dtype at `src[0]`),
# `spec.bend`'s `arg_call`/`sh_23` (HEAD's rule is a pure type test), `render.bend`'s
# two `arg_repr` fixtures, `engine/jit.bend`, `engine/realize.bend`, and the SETTLED
# `graphcmp.bend` (`callinfo` renders this exact field, and `g_loop` hard-codes it).
type CallInfo is Data:
  CallInfo{name: Maybe<&2, String>, precompile: Bool, precompile_backward: Bool, dtype: S.Dt}

# Arg -- the `arg: Any` field -- and Tag -- the `tag: Any` field.
#
# `Any` is Python's way of saying "this field holds twenty unrelated things
# and the reader has to know which". The twenty, with the ops.py line each
# comes from:
#
#   None                    ANone      the default; SINK/STAGE arg is None
#   DType                   ADt        CAST/BITCAST arg; INS arg[1]
#   PyConst|InvalidType     APy        CONST arg
#   ParamArg                AParam     BUFFER/ALLOC/PARAM arg
#   CustomFunction          ACustom    CUSTOM_FUNCTION arg (ops.py:1394 upstream;
#                                     a `str` at the pin -- see the datatype)
#   CallInfo                ACall      CALL arg
#   KernelInfo              AKernel    SINK arg
#   ProgramInfo             AProgram   PROGRAM arg
#   (axis_id, axis_type)    ARange     RANGE arg
#   (Ops, int)              AReduce    REDUCE arg
#   Ops                     AOpLit     PYLITERAL arg (`upat.py:26` passes `self.op[0]`,
#                                     a bare `Ops`; `__init__.py:101` says the literal is
#                                     "a Python literal", and it is one of four -- Ops here,
#                                     a DType (:39), a str (:44) and `self.arg` (:29))
#   (dims, DType, threads, tc_upcast_axes)   AWmma   WMMA arg. `tc` is a `Maybe` (upstream's slot is `tuple|None`)
#   tuple[int, ...]         ATuple     PERMUTE arg (`movement.py:231`), UNSHARD arg
#                                     (`ops.py:691`: "the tuple of sharded axes, sorted")
#   -- and this is the WRONG SPELLING FOR A FLIP, which is `tuple[bool, ...]`:
#      `ops.py:428` asserts `all(isinstance(x, bool) for x in self.marg)` and
#      MEASURED on a fresh src `UOp(Ops.FLIP, src, (1, 0))` RAISES
#      `bad flip on (7, 3), (1, 0)` -- so the port can hold a shape CPython REJECTS,
#      and `graphcmp.bend`'s `g_flip` holds one (`O.ATuple{[1, 0]}`). The correct
#      type is a SEPARATE bool-carrying `Arg` variant, not this one narrowed,
#      because PERMUTE and UNSHARD really are ints. Five files construct or read a
#      FLIP's arg -- `fold.bend`'s `order_arg`, `schedule/prepare.bend:274 symbol=pr_perm`,
#      `mixin/movement.bend:991 symbol=G.pad` and `:1533`, and `graphcmp.bend`'s `g_flip` and its
#      one `argstr` arm -- so this cannot be a one-file change.
#   str                     AStr       SPECIAL name (`gpudims.py:104`), SOURCE text
#                                     (`codegen/__init__.py:455`)
#   (str, DType)            AInk       INS arg (`ops.py:622`), CUSTOM/CUSTOMI arg --
#                                     `ops.py:137` ASSERTS that pair: "CUSTOM/CUSTOMI arg
#                                     must be (str, DType)". These two ops are NOT `AStr`,
#                                     which is what this table claimed until 2026-10-05, and
#                                     `graphcmp.py`'s missing `carg` arm is the same claim.
#   (Ops, str|tuple)        AAllred    ALLREDUCE arg
#   str|tuple               ADev       COPY arg
#   bytes                   ABlob      BINARY arg; the BYTES themselves, as a list of
#                                     byte values. `ops.py:201`'s key holds the `bytes`
#                                     OBJECT, so the key compares CONTENT -- see the
#                                     BLOB block above `t_blob_*` for the measurement
#   int                     AInt       MSELECT's shard index (`ops.py:772`), a bare int.
#                                     It was `ABlob{[k]}` -- BYTES -- until 2026-10-06, when
#                                     `--graph mselect` measured the two differ lanes
#                                     disagreeing (`py=i0` vs `bend=y n(i0)`,
#                                     `runs/graphcmp/D/D1-graph-mselect.txt`): `ops.py:201`'s
#                                     key separates on `type(arg)`, so an int and a bytes are
#                                     two kinds. It is a general `AInt` and NOT an
#                                     `AMSelect`: the op is already in the key, and
#                                     `upat.bend`'s `arg_int` asks the same question of any
#                                     `Arg`.
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
  # THE UNPAIRED `Op`. `AReduce` and `AAllred` both hold one and BOTH PAIR it, so before
  # this variant `Arg` could not spell `UOp(Ops.PYLITERAL, arg=<a bare Ops>)` at all --
  # `upat.py:26`'s `UOp(Ops.PYLITERAL, arg=self.op[0])` -- and the compiler said so:
  # `expected : O.Arg / observed : O.Op`. `AReduce{op, 0}` renders as `rd(OADD,i0)` and
  # `AAllred` needs a device, so a paired constructor is a LYING answer, not a close one.
  AOpLit{op: Op}
  AWmma{dims: List<&2, U32>, dt: S.Dt, threads: U32, tc: Maybe<&2, List<&2, U32>>}
  ATuple{ys: List<&2, U32>}
  # `tuple[bool, ...]` -- FLIP's arg, and the ONLY reason upstream's `Ops.FLIP` has a
  # guard `not all(isinstance(x, bool) for x in self.marg)` (ops.py:428) while PERMUTE
  # has none.  ONE upstream pattern (`upat`/`spec.py:166` asserts `isinstance(mv.arg,
  # tuple)` over PERMUTE and FLIP TOGETHER) covers TWO arg types: `tuple[int,...]` and
  # this.  MEASURED on the corpus: CPython renders `a.flip(0).uop.arg` as
  # `(True, False)` -> `n(b1,b0)` and the port rendered `n(i1,i0)`, which is the whole
  # of the surviving `flip` disagreement.  A `Bool` is NOT a `U32` in this port, so
  # `ATuple` cannot carry it and the erasure was invisible rather than absent.
  ABoolList{bs: List<&2, Bool>}
  AStr{s: String}
  AInk{ins: String, dt: S.Dt}
  AAllred{rop: Op, dev: S.Dev}
  ADev{dev: S.Dev}
  ABlob{bs: List<&2, U32>}
  AInt{i: U32}
  AFloat{f: F32}
  ABad{}

def CallInfo.of() -> CallInfo:
  CallInfo{None{}, False{}, False{}, S.void()}

# `CallInfo.__repr__` (ops.py:1401) is at the end of the equality block, because it
# compares against `S.void()` and `eq_dt` is what does the comparing.

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

type Node is Data:
  Node{op: Op, src: List<&2, U32>, arg: Arg, tag: Tag}

# `shp` is the RANGE-arg tail shape, the component CPython's ucache key has and
# `ARange{ids, at}` does not. 0 = flat `(at, *ints)`; N>0 = `arg[1]` nested N
# times. It is NOT a field of `ARange`: a third field is `a ARange pattern with
# 3 fields` at every `case ARange{ids, at}`, and a new `Arg` variant is
# `expected : cases for …` in `render.bend`'s and `upat.bend`'s exhaustive
# matches. Both measured, `.agents/slop/arange-ucache/`. `UOp.new` stores 0, so
# every existing constructor is the flat reading.
type Arena is Data:
  Arena{nodes: List<&2, Node>, shp: List<&2, U32>}

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

# THE BOTTOM. No srcs, an `ABad` arg, no tag, so every derived property answers
# void / None / () for it: it is inert, and a program that reaches it has asked
# the arena for a node that was never interned.
def Arena.bottom() -> Node:
  Node{OpsNOOP{}, Nil{}, ABad{}, TNone{}}

# the arena starts with the bottom at index 0, so `Arena.next` is
# `next(UOp.unique_num)` with the first slot already spent.
def Arena.empty() -> Arena:
  Arena{[Arena.bottom()], [0]}

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
# each site. The `0n` arm KEEPS the head: `src_from.go` is "drop k", and a `t`
# there is "drop k + 1" -- which is how `src_from(ar, u, 1)` came to answer
# `src[2:]` and `src_without_body` answered `src[2:]` for every CALL.
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

# The remaining field accessors, for the record types declared above. Same two
# lines each; they exist because Bend has no `x.field`, not because they carry
# any meaning.

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

# `-1` IS `4294967295` IN A `U32`, and this def is where that is SAID ONCE, in the
# file that OWNS the field. `ParamArg.slot` is a bare `U32` because a `Maybe` here
# would change 50 construction literals, 13 accessors and every slot comparison --
# a substrate change, and one that would invalidate the gate rows this naming
# exists to enable. The value was never in question; the NAME and its home were.
#
# The value is "no POSITIONAL slot": upstream's `variable()` passes `slot=-1`
# because a Variable is bound by NAME (function.py:15-17), and `param_like` then
# overwrites it with the call site's index. It does NOT mean "negative" --
# `from_buffer` (ops.py:860) uses `-id(opaque)` for an unrelated reason -- and a
# docstring that said "negatives are the no-slot namespace" would silently conflate
# the two. `from_buffer` is P6, so nothing collides today; saying it now costs one
# line and a wrong sentinel costs a miscompiled buffer later.
#
# WHY NOT 0: `Arena.empty` spends arena index 0 on the bottom (ops.bend:1368 symbol=Arena.empty), so
# `unique_num` starts at 1 and 0 is a REACHABLE real slot. `codegen/kernel.bend:278 symbol=u32_none`
# already argues this for its own copy.
#
# Four sibling files had each invented the same literal -- `FN_NEG1`
# (function.bend:153), `u32_none` (codegen/kernel.bend:274 AND
# codegen/late/linearizer.bend:329, two independent definitions), and a bare
# `4294967295` in uop/symbolic.bend:3488. This def is the one they should name.
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
# missing until `from_sink` landed. The accessor is here for the same reason the
# other six are: a Bend record has no projection syntax, so a field reader is
# two defs. The field's TYPE is `helpers.bend`'s record -- `H.Target` -- and not
# a second copy of it.
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
# Equality. Bend has no `==` on Data, so the ucache key needs one comparison per
# component. `UOpMetaClass.__call__` keys on
# `(op, src, arg, tag, type(arg))` and the NOTE there says why the dtype has to
# be separated: "a CONST's dtype is the type of its arg, and True == 1 as dict
# keys". The Arg CONSTRUCTOR is `type(arg)` here, so the key separates them for
# the same reason and for free -- one thing this encoding gets right that a bare
# U32 tag would not.
#
# A `match` may take two scrutinees, which is what makes a two-constructor type
# (Maybe, List) a four-arm ladder. Arg has nineteen constructors, so its 19x19 is
# a nested match: first on `x`, then a two-arm ladder on `y` inside each arm, with
# `x`'s own fields passed in as parameters because an arm may not see them.
# That is the same shape spec.bend uses in `Shape.max_dim`, and it is why
# `eq_arg` is twenty defs and not three hundred and sixty-one arms.

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

# `eq_u32`'s twin over `Bool`.  A separate def, not `eq_u32` with `Bool.to_u32`
# applied at both ends: that conversion is lossless only because `Bool` is two
# values, and a caller who later widens `ABoolList`'s element would silently
# compare a bit instead of a flag.
def eq_bool_list(ys: List<&2, Bool>, zs: List<&2, Bool>) -> Bool:
  match ys zs:
    case Nil{} Nil{}: True{}
    case y <> t w <> u: Bool.and(eq_bool(y, w), eq_bool_list(t, u))
    case Nil{} _ <> _: False{}
    case _ <> _ Nil{}: False{}

# `movement.py:253`'s `tuple([i in axis_arg for i in range(len(self.shape))])` --
# the int axis list to the bool flag list, in one place because FOUR call sites
# need it (prepare.bend `pr_flip`, mixin/movement.bend `G.flip` and
# `mxw_flip_new`, uop/fold.bend `g_mv_flip`).  It is NOT `i != 0`: upstream's
# membership test is `i in axis_arg`, which for a repeated axis still yields one
# True per DIM, and a nonzero test yields the same flags for the 0/1 axis lists
# every construction site actually builds.  The header says which reading this is.
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

# `Opt` equality, field by field, for `eq_arg`'s AKernel arm. `OPTOPS.value` and
# `AxisType.value` rather than a new `==`: both are `auto()` ladders defined above.
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

# `S.Cls` has SEVEN constructors (spec.bend:66-73) and this ladder had SIX, so
# `CWeakFloat` fell into `case _:` and was answered as `CFloat`. That made
# `eq_dt(weakfloat, weakfloat)` FALSE -- dtype.py's `DType` is `@dataclass(frozen=True,
# eq=False)` and the metaclass caches, so `dtypes.weakfloat == dtypes.weakfloat` is
# True -- and `intern.find` compares with `eq_node`, so two structurally identical
# `CAST(..., weakfloat)` nodes did not hash-cons.
#
# THE POSITION IS LOAD-BEARING, and `case _` is why. Measured on Bend 2.0.34: an
# arm AFTER a `case _:` is DEAD, because the catch-all claims every remaining tag
#     match x: { case A{}: 1; case _: 99; case Cc{}: 3 }   # A=1  Cc=99
# so appending the seventh arm to the old ladder would have added code that never
# runs. This ladder is therefore written the way `eq_const.sel` above is written
# and the way `Cls`'s own declaration order reads: every constructor but the LAST
# gets its own arm, and the LAST (`CWeakFloat`) is the catch-all. That is also the
# adjacency `dtype.py` asks for -- `is_float` is `x in (dtypes.floats + (dtypes.weakfloat,))`,
# so `CWeakFloat` sits next to `CFloat` and nowhere near the integer arms.
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

# `S.Addr` has FOUR constructors (spec.bend:78-82) and this ladder had THREE, so
# `Aalu` fell into `case _:` and was answered as `AReg`: `eq_addr(Aalu, Aalu)`
# False and `eq_addr(Aalu, AReg)` True. dtype.py:51-54's `AddrSpace` is a plain
# `IntEnum` -- four singletons, no `__eq__` override -- so both answers are
# backwards, and since `intern.find` compares with `eq_node`, two PARAMs that
# differ only in `addrspace` hash-consed to one node.
#
# THE POSITION IS LOAD-BEARING, and `case _` is why; see the measurement above
# `eq_cls.sel`. Appending the `AReg` arm to the old ladder would have been dead
# code. `AReg` therefore goes BEFORE the catch-all and the catch-all answers
# `Aalu` -- the LAST constructor in the declaration, the same shape `eq_cls.sel`
# and `eq_const.sel` above use.
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
# THE ALU/GLOBAL SPLIT, and it is asked in TWO places: `from_sink`'s `_globals`
# and `ProgramInfo.vals`'s variables. SO IT IS WRITTEN ONCE, HERE, AGAINST THE
# `ParamArg` -- and both call it, because BEND has no forward references and
# the two callers are 7000 lines apart.
def pa.is_alu.of(a: Arg) -> Bool:
  match a:
    case AParam{pa}:
      match pa:
        case ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}:
          eq_addr(addrspace, S.Aalu{})
    case _: False{}

# the name compare is only LOAD-bearing for the fp8 pairs, and `String.eq` is a lexicographic ordering.
# MEASURED (`PARITY.md` §107): `Ops.eq_dt` accounts for 34,757 of the 39,478 `String.eq` calls in 1,500 turns,
# and the runtime implements `String.eq` as `String_order(...) == EQ`. The dtype table has eight `pri` values
# that are unique on `(pri, bits, cls)`, and TWO PAIRS THAT ARE NOT: `fp8e4m3`/`fp8e4m3fnuz` both 10/8/CFloat
# and `fp8e5m2`/`fp8e5m2fnuz` both 11/8/CFloat. So the string is compared only when `pri` is 10 or 11 -- never
# on the CPU lane -- and the `match` on a Bool parameter is what makes it SKIP rather than evaluate and discard.
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
  # BITS, NOT IEEE. `UOp.key` is a hash over the packed arg, so CONST identity is
  # the bit pattern; `F32.is_eq` is IEEE and disagrees in both directions (see
  # `t_float_zeros_differ` / `t_float_nan_interns`, which are CPython-measured).
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
# using `eq_const` for both is the second instance of the over-split `eq_tag` had.
#
# `ops.py:201`'s key is `(op, src, arg, tag, type(arg))`, so `type(arg)` disambiguates the
# element that IS `arg` and nothing below it. `arg` is `bool` for `UOp(Ops.CONST, arg=True)`
# and `int` for `arg=1`, so a CONST splits -- which is what `eq_const` does and why
# `const_bool_vs_int_splits=True` holds. But `ParamArg.val` is `PyConst|None`
# (ops.py:42, `PyConst = float|int|bool` at dtype.py:38) NESTED inside `arg`, and there
# `type(arg)` is `ParamArg` on both sides, so `True` and `1` are ONE key.
#
# CPython-measured, `.agents/slop/ops-oracle.py`, and the fixture is a PAIR THAT DIFFERS
# ONLY IN `val`:
#     val=True      vs val=1        -> is True,  1 node
#     val=1        vs val=2        -> is False, 2 nodes
#     val=None     vs val=0        -> is False, 2 nodes
#     val=CF(-0.0) vs val=CF(0.0)  -> is False, 2 nodes
#     val=CF(1.0)  vs val=1        -> is False, 2 nodes
# The last one is why this comparator crosses bool against `CInt` and NOT against
# `CFloat`: `ConstFloat.__hash__` is `hash(self.bits)` (dtype.py:21) and
# `hash(0x3ff0000000000000) != hash(1.0)`, so a `ConstFloat` and an equal int land in
# different dict buckets and are never compared at all. `__eq__` would say they are equal;
# the HASH is what keeps them apart, and a value-based port has to reproduce that.
#
# `vmin_vmax` is nested too and does NOT get this comparator, because `PyRange` holds
# `H.I64` and has no bool/int distinction to cross. Its own defect is a different one --
# it cannot represent a float bound at all -- and is reported, not fixed here.
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
    # `CFloat` and `CInvalid` are the SAME answer as `eq_const`'s: upstream's `ConstFloat`
    # hash is `hash(bits)` and its `InvalidType` is a singleton, so neither is ever
    # equal to a bool, an int, or each other by value.
    case _: eq_const(y, z)

def eq_opt_pynest(x: Maybe<&2, Const>, y: Maybe<&2, Const>) -> Bool:
  match x y:
    case None{} None{}: True{}
    case Some{a} Some{b}: eq_pynest(a, b)
    case None{} Some{b}: False{}
    case Some{a} None{}: False{}

# ParamArg -- the 12-field dataclass of ops.py:23 (13 before `72f98ffe0` moved `size`
# out). A record of records, so the comparison is the conjunction of the field
# comparisons; nothing is skipped. `size` is NOT compared here and CANNOT be: it is
# `src[0]` now, and it is compared as part of the NODE's src list by `eq_node`, which
# is where upstream compares it too -- the ucache key is `(op, src, arg, tag)` and
# `src` is one of its four terms.

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

# `KernelInfo` IS A FROZEN DATACLASS UPSTREAM, so its equality is ALL SIX
# FIELDS -- MEASURED, `KernelInfo() == KernelInfo(optimized=True)` is False and
# `KernelInfo() == KernelInfo(estimates=Estimates(1,2,3))` is False. `eq_arg` IS
# THE UCACHE KEY, so a comparator that skipped the two would answer True where
# CPython answers False.
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

# `eq_target` -- the SEVENTH field's comparator. `Target` is a frozen dataclass
# upstream, so its equality is the five strings, and the port's `Target` is a
# `Data` record whose equality is the same five strings. It is
# `helpers.bend`'s record, so the pattern is `H.Target{...}`: the field ORDER is
# upstream's (`device, renderer, arch, iface, indices`), and a positional
# pattern against a record with a different order would compare the wrong pairs
# SILENTLY.
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

# CONTENT, NOT A SUMMARY. This arm used to compare `U32.is_eq(n, y1)` on an
# `ABlob{n: U32}` -- the LENGTH -- and two different same-length blobs were then the
# same ucache key: ONE node where `ops.py:201`'s key, which holds the `bytes` object
# and lets dict equality compare bytes content-wise, has two. Measured on the pristine
# tree before the fix: two BINARY nodes with 4-byte args interned to arena index `1,1`
# and `Arena.next - 1 == 1`; CPython answers `False` and `2`. `eq_u32` is the file's
# structural list equality -- the SAME def `eq_arg.ATuple` and `eq_tag.TTuple` compare
# with, so a blob is compared exactly as an axis tuple or a tag tuple is: elementwise,
# order-sensitive, and length-sensitive because the empty/non-empty cases are arms.
def eq_arg.ABlob(y: Arg, +bs: List<&2, U32>) -> Bool:
  match y:
    case ABlob{y1}: eq_u32(bs, y1)
    case _: False{}

# The bare int (`AInt`). A plain `U32.is_eq`: an int overrides nothing, so its `type(arg)`
# is already the key's fifth element and two equal ints are one key -- the `AInt` variant
# IS the type tag. This is the counterpart of the measured int-vs-float cell below
# (`type(arg)` keeps an `int` 0 and a `float` 0.0 apart) applied to the int-vs-bytes case
# `MSELECT` exercised.
def eq_arg.AInt(y: Arg, +i: U32) -> Bool:
  match y:
    case AInt{y1}: U32.is_eq(i, y1)
    case _: False{}

# ieee equality is correct here, and `F32.bits` would be a regression. `eq_const.CFloat`
# one hundred lines up compares `F32.bits` and is right, so this arm LOOKS like the
# same bug. It is the OPPOSITE bug, and the difference is the PYTHON CLASS of the
# element `ops.py:201`'s key holds -- the key is
# `(op, src, arg, tag, type(arg))` and each element is compared with ITS OWN `__eq__`:
#
#   * `dtype.py:8-23` `class ConstFloat(float)` says in its own docstring that it
#     "distinguishes -0.0 from 0.0 and where nan == nan", and it overrides BOTH
#     `__eq__` (line 16) and `__hash__` (line 21, `hash(self.bits)`). So a CONST's
#     arg compares BITWISE -- which is why `eq_const.CFloat` is `F32.bits`.
#   * `AFloat` is the BARE `float`. It overrides nothing, so its hash is
#     `hash(-0.0) == hash(0.0)` and its equality is IEEE, and CPython therefore
#     interns `0.0` and `-0.0` as ONE key.
#
# MEASURED, live, on both trees this gate can select, by CALLING
# `.agents/slop/afloat-probe.py` (and by the four `afloat_*` rows of
# `.agents/slop/ops-oracle.py`, which are the same measurement as a gate):
#     UOp(Ops.CONST, arg=0.0)   is UOp(Ops.CONST, arg=-0.0)         -> True,  1 node
#     two DISTINCT float('nan') with the SAME 0x7fc00000 payload     -> False, 2 nodes
#     UOp(Ops.CONST, arg=1.5)   is UOp(Ops.CONST, arg=1.5)         -> True,  1 node
#     UOp(Ops.CONST, arg=1.5)   is UOp(Ops.CONST, arg=2.5)         -> False, 2 nodes
#     `type(arg)` keeps an `int` 0 and a `float` 0.0 apart           -> False, 2 nodes
# A `F32.bits` comparator inverts BOTH discriminating cells: it would split the signed
# zeros CPython joins and merge the two NaNs CPython keeps apart. THE ONE CELL NO
# value-based port can reproduce is the same NaN object twice, which interns in
# CPython (1 node -- `lookdict` short-circuits on pointer identity) and is False under
# `F32.is_eq`. That is a fact about Python object IDENTITY rather than about the float,
# so there is deliberately no row for it: a row would have to lie about one or the other.
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
# `type(tag)`, so a `tag` is compared by its OWN value and nothing separates an `int`
# from a `bool` there. These two arms are therefore CROSSED rather than each matching
# only its own constructor, and that is the whole of the difference from
# `eq_const.CBool`/`eq_const.CInt` ten defs up, which DO separate them -- correctly,
# because a CONST's arg IS the key's `arg` element and `type(arg)` is the fifth element
# of the key itself.
#
# THE CELL THAT PROVES IT, CPython-measured (`.agents/slop/ops-oracle.py`, rows
# `tag_bool_vs_int_interns` / `tag_true_vs_false_splits` / `tag_none_vs_zero_interns`):
#     UOp(Ops.SINK, tag=True)   is UOp(Ops.SINK, tag=1)      -> True,  1 node
#     UOp(Ops.SINK, tag=True)   is UOp(Ops.SINK, tag=False)   -> False, 2 nodes
#     UOp(Ops.SINK, tag=None)   is UOp(Ops.SINK, tag=0)      -> False, 2 nodes
# and the control in the same block, `const_bool_vs_int_splits=True`, which says the
# top-level split must be KEPT. `rtag(self, tag=True)` -- ops.py:258 -- is what makes
# this reachable rather than theoretical: `x.rtag()` puts a `bool` True in the key, and
# an `int` 1 built by hand is the same key.
#
# `TBool{b}` holds a `Bool` and `TInt{i}` a `U32`, so the crossing is exactly
# `(b ? 1 : 0) == i`, which is `eq_bool(Bool.not(U32.is_zero(i)), b)`. Written twice
# rather than shared because the two arms are reached from `eq_tag.sel` in opposite
# directions and a shared helper would need the pair of tags, which is the value
# `eq_tag.sel` is holding.
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

# UOpMetaClass.__call__ -- ops.py:193 symbol=UOpMetaClass.__call__. THE CONSTRUCTOR.
#
# `ucache.get(key) or super().__call__(...)` is one lookup and one append, and
# in an arena the lookup IS a scan for a node with the same key, because the
# arena IS the cache. That is the whole of `intern`. The difference from Python
# is cost, not meaning: a dict is O(1) and a list scan is O(n), so constructing
# the n-th node costs n key comparisons.
#
# two calls, not one returning a pair, and this is forced rather than chosen.
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
# Accessors. Bend 2.0.34 has no projection syntax and a `match` may not
# scrutinise a computed value, so each field reader is a def -- the same shape
# the UOp accessors above use. Eleven fields, eleven readers; there is no
# shorter spelling that is not a parse error.

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

# the linear scan. `want` is `+` because the key comparison and the next
# iteration both read it, and a Node is `Data` so the refcount is the only cost.

# `depth` is `arg`'s tail shape. CPython's key is `(op, src, arg, tag, type(arg))`
# (ops.py:201); both colliding args are tuples, so `type(arg)` does not split
# them — the tuple structure does. `eq_node` cannot see it (`ARange` has no
# field for it), so the scan compares it here.
def intern.find(ns: List<&2, Node>, ss: List<&2, U32>, +k: U32, +want: Node, +depth: U32) -> Maybe<&2, U32>:
  match ns ss:
    case Nil{} Nil{}:
      None{}
    case Nil{} _ <> _:
      None{}
    case _ <> _ Nil{}:
      None{}
    case nd <> t sh <> st:
      nxt = intern.find(t, st, U32.add(k, 1), want, depth)
      intern.find.pick(Bool.and(eq_node(nd, want), U32.is_eq(sh, depth)), k, nxt)

# intern.put: the MISS branch of `ucache.get(key) or ...`, i.e. the append.
# The public spelling stores depth 0. `transcendental.bend` calls it directly
# for a CONST; a CONST has no tail shape.

def intern.put.shp(+ar: Arena, +want: Node, depth: U32) -> Arena:
  Arena{List.append(&2, Node, Arena.nodes(ar), [want]), List.append(&2, U32, Arena.shp(ar), [depth])}

def intern.put(+ar: Arena, +want: Node) -> Arena:
  intern.put.shp(ar, want, 0)

# intern.get: the HIT branch, which hands back the arena untouched.

def intern.get(ar: Arena, hit: Maybe<&2, U32>) -> Maybe<&2, U32>:
  hit

# `UOp.make(ar, op, src, arg, tag)` -- the `UOp(...)` call itself, with Python's
# keyword names flattened into positional ones.

def UOp.make.intern.put(+ar: Arena, hit: Maybe<&2, U32>, +want: Node, depth: U32) -> Arena:
  match hit:
    case Some{i}: ar
    case None{}: intern.put.shp(ar, want, depth)

# and the index of that node, which the Python gets for free because the
# constructor RETURNS the object.

def UOp.make.intern(+ar: Arena, +want: Node, +depth: U32) -> Arena:
  UOp.make.intern.put(ar, intern.find(Arena.nodes(ar), Arena.shp(ar), 0, want, depth), want, depth)

def UOp.make.shp(+ar: Arena, +op: Op, +src: List<&2, U32>, +arg: Arg, +tag: Tag, depth: U32) -> Arena:
  UOp.make.intern(ar, Node{op, src, arg, tag}, depth)

# The five key parameters are all `+`: the two-call constructor reads the key
# twice, once to intern and once to find the index, and every one of them is
# `Data`, so the refcount is the only cost. This is the one place in the file
# where the arena's "no mutable store" bill comes due on every node.
# Depth 0: the flat tail. Every existing caller is this reading.
def UOp.make(+ar: Arena, +op: Op, +src: List<&2, U32>, +arg: Arg, +tag: Tag) -> Arena:
  UOp.make.shp(ar, op, src, arg, tag, 0)

def UOp.of.intern.put(+ar: Arena, hit: Maybe<&2, U32>, +want: Node) -> U32:
  match hit:
    case Some{i}: i
    # a miss appended, so the new index is the one before the end
    case None{}: U32.sub(Arena.next(ar), 1)

# `Metadata` is helpers.py:293's `(name, backward)` record, and ops.py is where
# it is used: the `metadata=` keyword of the constructor and the `metadata`
# property at ops.py:775.

def UOp.of.intern(+ar: Arena, +want: Node, depth: U32) -> U32:
  UOp.of.intern.put(ar, intern.find(Arena.nodes(ar), Arena.shp(ar), 0, want, depth), want)

def UOp.of.shp(+ar: Arena, +op: Op, +src: List<&2, U32>, +arg: Arg, +tag: Tag, depth: U32) -> U32:
  UOp.of.intern(ar, Node{op, src, arg, tag}, depth)

def UOp.of(+ar: Arena, +op: Op, +src: List<&2, U32>, +arg: Arg, +tag: Tag) -> U32:
  UOp.of.shp(ar, op, src, arg, tag, 0)

# The intern key. Flat fields, plus a list of INDICES -- so this is NOT the
# recursive walk a bare `UPat` would need, and that is the whole point of the
# arena. These are `eq_op_list` and friends, mirroring the `eq_u32` /
# `eq_i64s` / `eq_opt_u32` family already above.

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

# `functools.cache`. `pintern.find` is `intern.find` with `equal` for `eq_upat`,
# and `pintern.of` is the same HIT/MISS pair `UOp.make.intern` uses.

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

# MERGING TWO ARENAS. `Arena` is an IMMUTABLE `Data` VALUE (`ops.bend:1305 symbol=Arena`), so a
# `Found` SNAPSHOTS the arena it was built in and an index is legal only in an arena
# DESCENDING FROM the one that minted it. Two tensors built from two `Arena.empty()`
# values are SIBLINGS with no common ancestor, and there was no way to name both in
# one node until this. The wall is recorded at `tensor.bend`'s SIBLING ARENAS block.
#
# THE ALGORITHM IS A FOLD, NOT A COPY, because the arena has no mutable store: `other`'s
# nodes are re-INTERNED into `base` one at a time (`UOp.new`), so a node `base` already
# holds is found rather than duplicated and `map` sends it to the index it already had.
# `map[i]` is therefore "where `other`'s node `i` ended up", which is NOT `i + len(base)`
# in general -- it is only that when nothing was shared.
#
# `Arena.nodes` IS TOPOLOGICALLY SORTED: `UOp.new` is only ever called with srcs already
# in the arena, so every node's srcs were appended before it and a node's src indices are
# all BELOW its own position in `map`. That is what lets `remap` read `map` while the fold
# is still appending to it, and it is an invariant of the builder, not of this fold.

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
# the arena can already answer. Every one of these is a `UOp(...)` call, so each
# is `UOp.new` plus the argument list Python builds for it.
#
# THE `kwargs` ARE GONE. Python threads `kwargs` through thirty of these
# and forwards it to the constructor, so it carries op/arg/tag. Bend has no
# kwargs: the constructor's three fields are spelled out at each call site, and
# the sugar that exists only to forward them collapses to the call. That is why
# `UOp.index` is not a def -- the Python `UOp.index` is
# `UOp(Ops.INDEX, src=(self,)+tuple(new_srcs), kwargs)` and the whole of it is
# that call. The comparison table records each one.
#
# THE `-> Found` RETURN. Python returns the UOp; here the arena grows, so the
# return is the arena and the index together. `Found` is a two-field record
# because an `Arena & U32` pair is a `Type` and cannot carry a `+`.

# sink -- ops.py:559. `UOp(Ops.SINK, src=tuple([x for x in srcs if x is not None]), kwargs)`
def UOp.sink(ar: Arena, +srcs: List<&2, U32>) -> Found:
  UOp.new(ar, OpsSINK{}, srcs, ANone{}, TNone{})

# alu -- ops.py:630. `UOp(op, src=(self, *src), kwargs)`
def UOp.alu(ar: Arena, +op: Op, +srcs: List<&2, U32>) -> Found:
  UOp.new(ar, op, srcs, ANone{}, TNone{})

# `where` -- mixin/elementwise.py:426, `self.alu(Ops.WHERE, x, y)`, i.e.
# `UOp(Ops.WHERE, src=(cond, x, y))` with `cond` FIRST because `alu` puts `self` at src[0].
def UOp.where(ar: Arena, +cond: U32, +x: U32, +y: U32) -> Found:
  UOp.new(ar, OpsWHERE{}, [cond, x, y], ANone{}, TNone{})

# `valid` -- ops.py:664. `cond.where(self, self.const_like(Invalid))`, and for the CONST case
# `const_like` IS `UOp.const(Invalid)` -- no `_shape` to expand into, so no EXPAND. The shaped case
# needs `_mop` and `_shape`, which is why the ROWS here are consts.
#
# the arena is the caller's and it must hold all three indices, which cost me a wrong diagnosis
# earlier: I passed the ORIGINAL arena after siblings had grown it, read `ANone{}` back, and wrote
# down that the constructor could not be verified. It can. Each `UOp.const` answers a node in the
# GROWN arena -- the rule my own notes record as "mint derived consts in the result's arena".
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

# `src=(self,)+srcs` puts SELF FIRST. This used to read
# `List.append(&2, U32, srcs, [self])`, which is `srcs ++ [self]` -- so the node landed
# LAST, the exact inverse of the comment right above it. Nothing caught it because an AFTER
# built this way has the same op, the same nsrc, the same shape and the same dtype as the
# correct one: only the SRC OP SEQUENCE differs, and no row printed that. Found by the
# schedule/prepare unit, which built its own AFTER in the right order to route around it.
def UOp.after(+ar: Arena, +self: U32, +srcs: List<&2, U32>) -> Found:
  UOp.after.go(srcs, ar, self, UOp.new(ar, OpsAFTER{}, List.append(&2, U32, [self], srcs), ANone{}, TNone{}))

# group -- ops.py:536-538, and upstream DELETED `Ops.GROUP` to get there:
#   `if len(srcs) == 1 and isinstance(srcs[0], UOp): return srcs[0]`
#   `return UOp(Ops.STACK).after(*[x for x in srcs if x is not None], kwargs)`
# IT SITS BELOW `UOp.after` BECAUSE IT CALLS IT, and Bend's checker refuses a live use of a
# definition it has not filled yet ("an unfilled law is a dead claim"). `sink` is above and
# call and it is the same trade every other `.go`/`.of` split in this section already made.
#
# The one-element case IS the node itself, so that arm hands the arena back UNCHANGED and
# upstream's own `UOp(Ops.STACK)` is never the answer. The STACK the `of` arm was handed is
# then stranded in the arena; `mxw_count` walks from a ROOT (`toposort(budget, ar, u)`, not
# `len(Arena.nodes(ar))`) so a stranded node is invisible to it.
# ZERO srcs is `UOp(Ops.STACK).after()` with nothing to after, and `after` is
# `... if len(src) else self`, so the answer is the BARE STACK -- a real node with no srcs,
# which is what the old `Found{nar, 0}` meant when it named index 0 of an arena that had
# nothing in it. TWO OR MORE is an AFTER over `(STACK,) + srcs`: one op changed and one node
# ADDED, and `UOp.after` already spells `src=(self,)+srcs` with SELF FIRST.
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

# `src=(self,)+src` puts SELF FIRST -- see UOp.after above, which had this inverted.
def UOp.end(+ar: Arena, +self: U32, +srcs: List<&2, U32>) -> Found:
  UOp.end.go(srcs, ar, self, UOp.new(ar, OpsEND{}, List.append(&2, U32, [self], srcs), ANone{}, TNone{}))

# mstack -- ops.py:773. `UOp(Ops.MSTACK, src=(self,)+srcs) if len(srcs) else self`
def UOp.mstack.go(srcs: List<&2, U32>, ar: Arena, self: U32, made: Found) -> Found:
  match srcs:
    case Nil{}: Found{ar, self}
    case _ <> _: made

# `src=(self,)+srcs` puts SELF FIRST -- see UOp.after above, which had this inverted.
def UOp.mstack(+ar: Arena, +self: U32, +srcs: List<&2, U32>) -> Found:
  UOp.mstack.go(srcs, ar, self, UOp.new(ar, OpsMSTACK{}, List.append(&2, U32, [self], srcs), ANone{}, TNone{}))

# replace -- ops.py:253. `b.replace(op=..., src=..., arg=..., tag=...)` is a
# copy with up to four fields swapped. Each `Maybe` says: `Some{v}` means use
# v, `None{}` means keep the current. Identity is returned when all four
# `Some` values match the current (or all four are `None`); otherwise a new
# node is built via `UOp.new`. This is the SEAM ABOVE `substitute`, which is
# the matcher-driven form. `ParamArg` is a 13-field Data record, so an
# `arg=replace(b.arg, ...)` call site is a 13-field literal at every rewrite
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
#
# DEVIATION FROM CPYTHON. CPython's identity check reads `self.dtype`, which is a
# FOLD property (`dtype_from_uop`, ops.py:247). A rule body that has no fold
# context (every PMEntry body in `pm_dispatch_m.go`) cannot read `self.dtype`, so the
# identity check is unreachable from a rule body. the port always builds a new node,
# which means: when `self.dtype` already equals `dt`, the graph has ONE extra
# `OpsCAST{}` node that CPython would have skipped.
#
# The extra node is a GRAPH BLOAT, not a correctness issue: the cast is a no-op on
# the value, and downstream optimizations fold it. The four call sites that name
# this def as a wall (renderer/tc_ptx.bend:523 symbol=r_pmx_n, :49, :52, :55, :56, plus
# schedule/rangeify.bend:1568 symbol=ab_5_cast weak-CAST INDEX) get a `UOp.cast` to resolve against, which is
# what unblocks the port. The full identity check would need a FOLD CONTEXT, which
# is what `cast_at` in `mixin/dtype.bend:350 symbol=cast_at` IS, and a future unit that wires
# rule bodies into the fold can call THAT instead.
def UOp.cast(ar: Arena, self: U32, dt: S.Dt) -> Found:
  UOp.new(ar, OpsCAST{}, [self], ADt{dt}, TNone{})

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
# TODO(p3) ops.py:610  def const -- `UOp.const` needs `dtypes.from_py` (dtype.py:100, which also needs
# `commit_int` and `strong_dtype`) and `truncate` (dtype.py:289, half of which is
# the C-effect seam ./dtype.bend already has). Both land with the dtype fold.
def UOp.const(ar: Arena, +v: Const) -> Found:
  UOp.new(ar, OpsCONST{}, Nil{}, APy{v}, TNone{})

# `shape_to_shape_arg` -- ops.py:103-107, NEW to this file. Upstream:
#
#     def shape_to_shape_arg(arg:tuple[sint, ...]) -> UOp:
#       src = tuple(x if isinstance(x, UOp) else UOp.const(x) for x in arg)
#       return src[0] if len(src) == 1 else UOp(Ops.STACK, src=src)
#
# It is called with a SHAPE and every call site this port reaches passes a 1-tuple or
# the empty tuple -- `alloc` and `_buffer` pass `(prod(...),)`, `param` passes
# `(prod(...),) if shape else ()`, and `variable` passes nothing at all -- so the
# multi-dim STACK arm has no caller here and the argument is therefore the `Maybe`
# that already separated the two cases when `size` was a field. THE TWO ARMS ARE
# BOTH LOAD-BEARING:
#
#   * `Some{n}` -> `UOp.const(n)`. `_shape` reads `src[0].as_shape`, and a CONST's
#     `as_shape` is `(self.val,)` (ops.py:783-786), so the shape is `(n,)`.
#   * `None{}` -> `UOp(Ops.STACK)` with NO src, whose `as_shape` is `()`. This is
#     the scalar case -- a `variable`, an ALU PARAM bound by name -- and `src=(UOp(
#     Ops.STACK),)` is upstream's own spelling at `ops.py:1002`.
#
# and the empty case is not cosmetic: `src=()` makes `_shape`'s `self.src[0]` raise
# `IndexError`, and a scalar PARAM whose src is a CONST `1` is a DIFFERENT NODE from
# one whose src is an empty STACK. MEASURED on CPython, `Tensor.empty(1).uop.src` is a
# CONST and a `variable`'s is a STACK, and their interning keys differ.
def shape_to_shape_arg.of(+ar: Arena, +made: Arena, n: Maybe<&2, U32>) -> Found:
  match n:
    case Some{k}: UOp.const(made, CInt{H.i64_of_i32(k)})
    case None{}: UOp.new(made, OpsSTACK{}, Nil{}, ANone{}, TNone{})

def shape_to_shape_arg(+ar: Arena, n: Maybe<&2, U32>) -> U32:
  Found.i(shape_to_shape_arg.of(ar, ar, n))

# `src=(shape_to_shape_arg(...),)+UOp.device_range_src(device)` -- ops.py:829, :1187,
# :1219, :1002. The `device_range_src` half is P6 (no multi-device ALLOC in the port)
# and is `()` for a single device (`mixin/creation.bend:429 symbol=cr_empty` says so), so the src of a
# PARAM/BUFFER/ALLOC here is exactly this one element.
# THE TUPLE FORM OF `shape_to_shape_arg` -- AND THIS IS THE ONE
# UPSTREAM's `_mop` (`ops.py:790-791`) CALLS:
#
# ```
# usrcs = [shape_to_shape_arg(arg) for arg in src_args]
# return UOp(op, src=(self,)+UOp.sink(*usrcs).simplify().src)
# ```
#
# AND IT LIVES HERE, AND NOT ONLY HERE -- THE PORT HAD THREE
# COPIES OF THE SHAPE-ARG BUILDING BECAUSE EVERY FILE THAT NEEDED IT
# COULD NOT SEE THE OTHERS:
# - `mixin/movement.bend`'s `G.stkN` (AND `G.stk4`, THE HARD-CODED
# LENGTH-4 ONE), AND
# - `mixin/gradient.bend`'s `gstkN` (AND THE COPY IS THE POINT:
# `mixin/gradient.bend` CANNOT IMPORT `mixin/movement.bend`, BECAUSE
# `mixin/movement.bend` IMPORTS `tensor.bend` AND `tensor.bend` IMPORTS
# `mixin/gradient.bend`), AND
# - `uop/ops.bend`'s THE SCALAR `shape_to_shape_arg` (WHICH IS THE
# 0-OR-1-DIM FORM).
#
# AND `uop/ops.bend` IS THE ONE FILE EVERY ONE OF THEM CAN SEE
# -- AND SO THE TUPLE FORM IS HERE, AND THE OTHER TWO CALL
# IT, AND THE DUPLICATION IS THE DEFECT AND NOT THE COPY.
#
# AND THE LENGTH-1 ARM IS A BARE CONST -- `ops.py:112`: `return src[0]
# if len(src) == 1 else UOp(Ops.STACK, src=src)` -- AND THE EMPTY ARM IS AN
# EMPTY STACK, WHICH IS WHAT `shape_to_shape_arg.of` ALREADY DOES.
def shape_arg.const(+ar: Arena, v: U32) -> Found:
  UOp.const(ar, CInt{H.i64_of_i32(v)})

# THE PUSH IS A DEF OF ITS OWN, BECAUSE BEND SPENDS A BINDER
# WHEN IT READS IT ("consumed more than once") AND THE RECURSIVE CALL's
# ARGUMENTS MUST EACH BE SMALLER THAN THE MATCHED EXPRESSION ("a call
# smaller than ...") -- AND THIS IS THE IDiom `mixin/movement.bend`'s
# `G.stk.go`/`G.stk.push` USES, AND THE TWO COPIES OF IT ARE THE
# DUPLICATION THIS FILE EXISTS TO END.
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

# THE INDEX FORM, AND IT IS THE ONE A CROSS-FILE CALLER WANTS:
# A CROSS-FILE `Found` CAN NOT BE READ TWICE ("consumed more than once"),
# AND THE CALLERS NEED BOTH ITS ARENA AND ITS INDEX -- AND THE
# INDEX IS A PLAIN `U32`, SO THE CALLER CAN READ IT AS MANY
# TIMES AS IT LIKES AND TAKE THE ARENA FROM THE `Found` IT BUILT
# THE SHAPE IN -- AND THAT IS WHY THE INDEX FORM IS THE ONE
# THE `uop`-LAYER CALLERS USE.
def shape_arg(ar: Arena, ys: List<&2, U32>) -> U32:
  Found.i(shape_arg_found(ar, ys))

# `src=(shape_to_shape_arg(...),)+UOp.device_range_src(device)` -- ops.py:829, :1187,
# :1219, :1002. The `device_range_src` half is P6 (no multi-device ALLOC in the port)
# and is `()` for a single device (`mixin/creation.bend:429 symbol=cr_empty` says so), so the src of a
# PARAM/BUFFER/ALLOC here is exactly this one element.
def param_src(+ar: Arena, n: Maybe<&2, U32>) -> List<&2, U32>:
  [shape_to_shape_arg(ar, n)]

# `UOp.new.param` is the only safe way to build one of these three nodes, and
# `param_src` is NOT. An `Arena` is an immutable `Data` VALUE (`ops.bend:1305 symbol=Arena`), so
# `shape_to_shape_arg` -- which hands back `Found.i(...)` and DROPS the arena it interned
# the size node into -- returns an index into an arena the caller does not hold. The
# caller then interns the node into the arena it DOES hold, where that index names
# nothing, and `Arena.src0` reads the arena BOTTOM. `Arena.src(ar, i, 0)` answers
# `Maybe.default(..., 0)` (`uop/ops.bend:1389 symbol=Arena.at.go`), so there is no error: the node comes out
# pointing at INDEX 0 or at ITSELF.
#
# MEASURED, `gates/../sizetosrc/paramsrc_probe.bend` over both spellings on one BUFFER:
#
#     idiom_Some12  nsrc=1 next=2 op=BUFFER src0=1 src0_op=BUFFER size=N
#     threaded_*    nsrc=1 next=3 op=BUFFER src0=1 src0_op=CONST  size=12
#
# `next=2` says the size CONST was never interned; `src0_op=BUFFER` says the BUFFER is
# its OWN parent, a self-loop, which is why the fold does not settle (`F.Kahn.settled`
# false) and why `rows.of` emits nothing. `size=N` says `ParamArg.size` -- which reads
# `src[0]` -- cannot answer. And it is not a fixture: `MX.mxw_buf`
# (`mixin/movement.bend:1229`) is the port's own BOTTOM-OF-EVERY-GRAPH builder and
# measured `nsrc=1 next=2 src0_op=BUFFER size=N` on the live library.
#
# So `param_src` is kept only so its 62 call sites can be migrated one at a time and this
# note can name them; it is not a second way to build a node. `shape_to_shape_arg.of`
# ALREADY returns the `Found` -- arena and index -- and this is its only correct use.
def UOp.new.param(+ar: Arena, +op: Op, n: Maybe<&2, U32>, arg: Arg, tag: Tag) -> Found:
  +f = shape_to_shape_arg.of(ar, ar, n)
  UOp.new(Found.ar(f), op, [Found.i(f)], arg, tag)

# THE READER, and the reason it takes the OWNER. `ops.py:353-357`:
#
#     case Ops.BUFFER | Ops.ALLOC | Ops.PARAM:
#       assert len(self.src[0].as_shape) <= 1
#       if (img:=self.arg.image) is not None: return (img[0], img[1], 4)
#       return self.src[0].as_shape
#
# so the size is `src[0]`'s VALUE and a bare `ParamArg` cannot reach it -- the same
# reason upstream's `size_of(owner)` takes a `UOp` (`.agents/slop/graphcmp.py:703`).
# `H.lo32` is the CONST's own reader (`UOp.index.slot.go` above), so a size CONST
# interns against a `UOp.const` written anywhere else, which is the whole of the
# identity `f(4) is f(6) == False` rests on.
def ParamArg.size.const(arg: Arg) -> Maybe<&2, U32>:
  match arg:
    case APy{CInt{i}}: Some{H.lo32(i)}
    case _: None{}

def ParamArg.size.node(op: Op, arg: Arg) -> Maybe<&2, U32>:
  match op:
    case OpsCONST{}: ParamArg.size.const(arg)
    case _: None{}

def ParamArg.size.of(+ar: Arena, self: U32, +n: U32) -> Maybe<&2, U32>:
  ParamArg.size.node(Node.op(Arena.node(ar, n)), Arena.arg(ar, n))

def ParamArg.size(+ar: Arena, +self: U32) -> Maybe<&2, U32>:
  ParamArg.size.of(ar, self, Arena.src0(ar, self))

# range -- ops.py:642. `UOp(Ops.RANGE, src=(sint_to_uop(end, dtype),)+src,
# arg=(axis_type, axis_id), kwargs)`. `end` is already a UOp index here,
# because `sint_to_uop` is `UOp.const(x, dtype)` and that is the CONST above.
#
# the ARG order is flipped and `ARange` is not -- the coupling, stated exactly.
#
# Upstream `arg=(axis_type, axis_id)` and the pin's was `arg=(axis_id, axis_type)`.
# `ARange` is this file's SPLIT of that tuple, so faithful would be
# `ARange{at, ids}`. It is `ARange{ids, at}` and that is a DELIBERATE wall, because
# `ARange` is read and written POSITIONALLY by eleven committed files:
#     schedule/rangeify.bend:2116 symbol=ren_axis0.go   schedule/multi.bend:611 symbol=mu_at_of.go
#     schedule/indexing.bend:687,692     codegen/late.bend:910,1000,1573,1796-1798
#     uop/render.bend:741 symbol=arg_repr              uop/spec.bend:363 symbol=arg_axis.go
#     uop/fold.bend:2288,2300            uop/validate.bend:1601
#     uop/fold2_work.bend:2280,2292      uop/fold_mm_work.bend:2280,2292
#     uop/upat.bend:396 symbol=arg_int                engine/realize.bend:1729 symbol=rz_is_devrng.ax
# Flipping the field order here would break all twenty-nine of those sites and leave
# six files I do not own red. It is a TWO-FILE change that has to be sequenced, not a
# one-file rebase, and `.agents/UPSTREAM-PIN.md` outcome 2 ("re-verify, no change") is
# the wrong label for it -- it is a coupling, recorded here and in the rebase list.
#
# WHAT IS NOT AFFECTED, and is fixed below: nothing in the ported surface reads the arg
# POSITIONALLY. `axis_id` and `axis_type` are the only readers, they are properties in
# Python, and `UOp.axis_id` / `UOp.axis_type` below return CPython's answers off the
# split. So the observable semantics of `UOp.range`, `UOp.loop`, `axis_id` and
# `axis_type` are upstream-exact and gated; the one thing still wrong is `repr(arg)`,
# which is `range_str`'s job and is P3 (`uop/render.py`), plus `hcq2.py:498`'s
# `arg=(u.axis_type, next(ctx))+u.axis_id[1:]`, which is P6 and unported. Both name the
# field, not the position, which is why they survive the wall.
# `depth` is how many times `arg[1]` is a tuple. `UOp.range(end, (0, 1), at)`
# builds `(at, (0, 1))` (ops.py:643); a flat `arg=(at, 0, 1)` is a different
# ucache key (ops.py:201) with the same ints. `ARange` stores the ints only.
def UOp.range_shaped(ar: Arena, +end: U32, +ids: List<&2, U32>, at: AxisType, depth: U32) -> Found:
  UOp.new.shp(ar, OpsRANGE{}, [end], ARange{ids, at}, TNone{}, depth)

def UOp.range_end(ar: Arena, +end: U32, +ids: List<&2, U32>, at: AxisType) -> Found:
  UOp.range_shaped(ar, end, ids, at, 0)

# axis_id / axis_type -- ops.py:499-505 upstream, 502-508 at the pin. Both assert
# `self.op is Ops.RANGE` in Python; the port reads the arg's SHAPE instead, because an
# `Arg` that is not an `ARange` cannot be a RANGE's -- `UOp.new` puts the arg and the op
# in the same node, so the op is the discriminator and there is nothing to assert. The
# answer is a `Maybe` because that is what the assertion would have been.
#
# these are the swapped pair the rebase moved, and the gate asks CPython's property
# (`u.axis_id`, `u.axis_type`) rather than re-deriving either slice, so the row follows
# the tree instead of encoding a reading of the diff. Measured: for an arg of length
# TWO -- which is every `UOp.range` and every `UOp.loop` -- the pin's `arg[0:-1]` and
# upstream's `arg[1:]` are the SAME slice, so those four fixtures answer identically on
# both trees. Only a three-element arg separates them, and `rng_twoid` is that fixture.
#
# the rows read these defs and not the fixture's literals. An earlier version of
# caller -- and mutation M19 of `.agents/slop/ops-mutate.py`, `axis_id` answering
# `Nil{}`, moved NOTHING, which is the "a def nothing calls is invisible to every other
# check" failure in miniature. The row now goes through `Arena.arg`, so the properties
# are what is gated.
#
# Note what the port CANNOT do here: upstream's `axis_id` is `self.arg[1:]`, a slice of
# a Python TUPLE of arbitrary length, so a port whose `ARange` holds a `List` answers it
# only while the list is the whole tail. Nesting depth is `Arena.depth`, not a second
# list — `List<U32>` cannot hold `((0, 1),)`. TODO(p3): a reader that needs that tuple.
#
# MEASURED 2026-10-03, CALLING CPython (`UOp.range(4, <axis_id>, AxisType.WEAK)`), which
# is what makes this a NAMED wall rather than a shrug. The depth is real and visible:
#
#   axis_id arg      CPython `u.arg`             `u.axis_id`      `str(u.axis_id)`
#   0                (AxisType.WEAK, 0)           (0,)             '(0,)'
#   (0,)             (AxisType.WEAK, (0,))        ((0,),)          '((0,),)'
#   (0, 1)           (AxisType.WEAK, (0, 1))      ((0, 1),)        '((0, 1),)'
#   ((0, 1),)        (AxisType.WEAK, ((0, 1),))   (((0, 1),),)     '(((0, 1),),)'
#
# So the nesting is observable THREE ways upstream -- in `axis_id`'s value, in
# `pyrender` (render.py:101 is `repr(y) for y in x.arg`, not `axis_id`), and in
# `range_str` (ops.py:96 joins `str(x) for x in u.axis_id`) -- and this def can see
# NONE of them, because it takes `arg` and not the arena. `Arena.shp` is where the
# depth lives (`Arena.depth.at(Arena.shp(ar), ...)`, and `intern.put.shp`), and
# `Uc.depth` already GATES it: `ucdepth_flat_nest=0,1` is a flat and a nested RANGE
# with the same ids, and it reads 0 and 1. So the arena half is done and tested.
#
# WHAT IS LEFT, and it is SMALL: this def's signature is right and should not change
# (`axis_id`'s ints ARE the flat tail; only the SHAPE nests, so `(ids, depth)` is the
# honest answer, not a nested list). What is missing is that `t_rng_row`'s four rows
# are only ever fed DEPTH-0 fixtures -- `rng_twoid` builds with `UOp.range_end`, so
# `axid_twoid=(0,1)/len=2` gates only the flat case, and no row routes a depth-1
# arg through here. Adding one means a depth-aware `AxIds` (uop/ops.bend:4979 symbol=UOp.split_uop.pop, one def,
# ONE call site) plus a matching row in `.agents/slop/ops-oracle.py`, and that oracle
# is a BYTE DIFF whose row order is documented as matching EXACTLY -- so a row added
# here and not there is a diff, not a silent gap. Hence not done blind.
#
# BLAST RADIUS, measured rather than assumed: `UOp.axis_id` has FIVE textual call
# sites, and only ONE of them calls THIS def -- the gate row at 4895. The other three
# are same-named defs of a DIFFERENT shape, `(ar, i)`, in `fold.bend`, `fold_mm_work.bend`
# and `fold2_work.bend`. The 63-importer figure is for the FILE, not for this def.
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
# of budget, which for a DAG it never does: the fuel is `Arena.budget(ar)`.
#
# The budget is NODES PLUS EDGES and NOT `2 * len(arena)`. A node is pushed once
# per INCOMING EDGE -- every consumer pushes it -- and once more as
# `Frame{n, True}`, so a node with two consumers is popped three times and
# `2 * len(arena)` is the tighter of the two bounds. It was, and it truncated:
# render.bend's `g_fan` fixture (one node with six consumers, E=24 against N=21)
# needs 44 pops and answers a toposort missing its sink on 42.
#
# The gate (`gate=Callable|None`) and the visitor (`visitor: Callable`) are
# Python callables. A closure in Bend is single-use and cannot be stored in a
# `Data` field, so they are NOT PORTED as parameters; the two call sites in
# tinygrad that pass a gate pass a *bound method* or a lambda over one op, and
# both are P3/P4 work. Every other caller passes None, which is the behaviour
# here. The visitor is the same story, and `topovisit` has NO caller in
# ops.py at all.

type Frame is Data:
  # each stack entry is (node, visited_flag)
  Frame{n: U32, visited: Bool}

type Topo is Data:
  # `calls` is Python's `enter_calls`, and it rides on the RECORD rather than on
  # the walk because `Topo.step` has to read it on every pop.
  Topo{cache: List<&2, U32>, stack: List<&2, Frame>, calls: Bool}

def Topo.empty() -> Topo:
  Topo{Nil{}, Nil{}, True{}}

# `cache[node] = None` -- an append, because a Dict preserves insertion order and
# the toposort IS its iteration order.

def Topo.cache_add(n: U32, t: Topo) -> Topo:
  match t:
    case Topo{cache, stack, calls}: Topo{List.append(&2, U32, cache, [n]), stack, calls}

# `if n in cache: continue`
# `stack.append((n, True))` then the srcs, reversed.

def Arena.push_srcs.go(srcs: List<&2, U32>, st: List<&2, Frame>) -> List<&2, Frame>:
  match srcs:
    case Nil{}: st
    case s <> t: Arena.push_srcs.go(t, Frame{s, False{}} <> st)

# THE STACK IS LIFO: reversed and consed, so the pop-head visits src[0] first.
# A tail-append here is a QUEUE, and `pyrender` then renders consumers before
# their srcs -- verified by render.bend's 25 `pyrender` rows.

def Arena.push_srcs(+srcs: List<&2, U32>, st: List<&2, Frame>) -> List<&2, Frame>:
  Arena.push_srcs.go(List.reverse(&2, U32, srcs), st)

# `node.src if enter_calls else node.src_without_body`

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

# `for s in reversed(node.src): stack.append((s, False))`
# the membership test is the FIRST line of Python's loop, so an already-visited
# node is never re-EXPANDED -- and that is what makes `Arena.budget` sufficient.

def Topo.step.hit(ar: Arena, +n: U32, rest: List<&2, Frame>, seen: Bool, +cache: List<&2, U32>, calls: Bool) -> Topo:
  match seen:
    case True{}: Topo{cache, rest, calls}
    case False{}: Topo.push(ar, n, Topo{cache, rest, calls})

# the while loop, as a self-call on the worklist

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

# `Arena.next(ar) + edges`: one pop per pushed frame, and a frame is pushed once
# per edge into a node plus once per node as `Frame{n, True}`. EXACT, so the
# fuel can never cut a DAG short. TODO(p3): fold.bend's `Kahn.budget` and
# spec.bend's `topo_budget` compute this same number and should call it.

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

# `UOp.toposort(self, gate=None, enter_calls=True)`. The fuel is the caller's and
# the only correct one is `Arena.budget(ar)`: the header says why.

def UOp.toposort(fuel: Nat, +ar: Arena, self: U32) -> List<&2, U32>:
  toposort(fuel, ar, Topo.push(ar, self, Topo.empty()))

# toposort(enter_calls=False) -- the two call sites that pass it, both in
# `ProgramInfo.from_sink` and `contiguous_view`.

def UOp.topovisit(fuel: Nat, +ar: Arena, self: U32) -> List<&2, U32>:
  UOp.toposort(fuel, ar, self)

def UOp.toposort_nocalls(fuel: Nat, +ar: Arena, self: U32) -> List<&2, U32>:
  toposort(fuel, ar, Topo{Nil{}, List.append(&2, Frame, Nil{}, [Frame{self, False{}}]), False{}})

# the backward slice -- ops.py:280, :286, :289. three defs, one walk.
#
# MOVED BELOW `toposort_nocalls`, and Python has them above it: `backward_slice`
# is DEFINED in terms of `toposort`, and Bend has no forward references. This is
# the same class of move the header lists, and it is the only one this block needs.
#
# WHY `nocalls` AND NOT `toposort`. `enter_calls=False` is the WHOLE of the
# difference between `backward_slice` and a plain toposort, and on every fixture
# whose graph has no CALL it is invisible -- the two walks return the same list.
# So the `call` and `nest` rows are the ones that carry the fact, and a port that
# reached for `toposort` here would agree on `chain` and on `backedge`.

# `res.pop(self)`. Python pops BY KEY and the key is `self`, so this filters on
# IDENTITY. The tempting one-liner is `List.drop(.., 1n)`, and it is wrong in a way
# the toposort order hides until it is measured: the root is the LAST node to
# complete -- it has no consumers -- so `self` is the TAIL of the cache, and a drop
# from the front removes a different node. MEASURED on `chain`:
#     toposort_nocalls   = Ops.CONST Ops.RANGE Ops.CONST Ops.ADD Ops.CONST Ops.ADD
#     List.drop(.., 1n)  = Ops.RANGE Ops.CONST Ops.ADD Ops.CONST Ops.ADD
# and substituting the drop moved all four `bsl_*` rows. `+h` because the head is
# both the test and the kept element.
def bsl.go(+self: U32, xs: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case +h <> t: bsl.go(self, t, Bool.pick(List<&2, U32>, U32.is_eq(h, self), acc, List.append(&2, U32, acc, [h])))

def UOp.backward_slice(fuel: Nat, +ar: Arena, +self: U32) -> List<&2, U32>:
  bsl.go(self, UOp.toposort_nocalls(fuel, ar, self), Nil{})

# `{self:None, self.backward_slice}` -- a dict literal whose only addition is
# the key `self`, and a Dict iterates in INSERTION order, so the key is FIRST.
def UOp.backward_slice_with_self(fuel: Nat, +ar: Arena, +self: U32) -> List<&2, U32>:
  List.append(&2, U32, [self], UOp.backward_slice(fuel, ar, self))

# topovisit -- ops.py:309. "NOTE: this shares a lot of code with toposort". It
# has no caller in ops.py, and its visitor is a Python callable, so the def is
# here for the inventory and its body is the toposort order with the visitor
# call left to the caller that has one.
#
# TODO(p3): the visitor is a Callable. It is a P4 concern (every rewrite rule
# and every `pm.rewrite` callback is one) and it needs the same Sel-tag shape
# the master plan already prescribes for `PatternMatcher` rules.

# `src` normalisation -- ops.py:1456-1461, the `permutations` line:
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
# OR, XOR, all of them. Arity >= 3 is TODO(p3) ops.py:1457  def UPat.__init__ --
# and belongs with `spec.py`, the only other caller.
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

# `early_reject` -- ops.py:1476-1478. The comprehension is
#   `{pp.op[0] for pp in upat_match if pp.op is not None and len(pp.op) == 1}`
# over `upat_match`, which is `[src]` for a UPat src, `[]` for None, and
# `self.src[0]` -- the FIRST alternative only -- otherwise.
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

# The constructor -- ops.py:1449. `UPat(Ops.CAST, dtype, (self,))` becomes
# `UPat.of(pat, Some{[OpsCAST{}]}, Some{[dt]}, None{}, STuple{[k]}, ...)`: Python's
# positional and keyword arguments flattened into positional ones, which is the
# `UOp.make` convention above.
#
# `strict_length`, `required_len` and `early_reject` are DERIVED here rather than
# passed, because in Python they are derived in `__init__` too -- and deriving
# them is what makes the ten-argument call sites short.
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
# A `match` may not scrutinise a computed `Maybe`, and `List.head` returns a
# `Maybe` too, so the unwrap and the head are two defs rather than one.
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

# `named` -- ops.py:1485. Every field is carried across, and `not
# self.strict_length` is `allow_any_len`, which is how the raw `src` survives a
# round trip. Python's `self.op` is already a tuple, so it is already a `Some`.
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

  # `alts_of(src)` is pure and `src` is `+`-shared, so it is recomputed rather
  # than bound: a `let` is affine and would be consumed by the constructor.
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
    # a miss cannot happen for a pattern built here; Python would raise
    # AttributeError, and a bare named var is the honest nothing-to-rebuild
    case None{}: UPat.var(pat, Some{name}, None{})

def UPat.named(+pat: Pat, k: U32, name: String) -> PatFound:
  UPat.named.of(List.get(&2, UPat, Pat.upats(pat), U32.to_nat(k)), name, pat)

# `any` / `or_casted` / `or_bitcasted` / `or_after` -- ops.py:1487-1493.
#
# `self if name is None else self.named(name)` is a Maybe-index choice, and the
# wrapper's `src=(self,)` is the ORIGINAL pattern even when `any` gets the named
# copy -- an upstream subtlety that a "tidy" rewrite would lose.

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

# three steps, each returning `(arena, index)`: pick self-or-named, wrap it, then
# `UPat.any` over the two. The wrapper's `src` is always the ORIGINAL index.

# three steps, each carrying the arena: pick self-or-named, wrap the ORIGINAL
# index, then `UPat.any` over the two. The wrapper's `src=(self,)` is the
# original pattern even when `any` receives the named copy -- an upstream
# subtlety a "tidy" rewrite would lose.

# `self if name is None else self.named(name)`

# `var` / `cvar` / `const` -- ops.py:1495-1501. `@functools.cache` is the intern
# inside `UPat.of`, so these three are also the interning demonstration: two calls
# with the same name return the SAME index.
#
# `dtype` may be one `DType` or a tuple of them, and a single one is wrapped.

def UPat.cvar(pat: Pat, name: Maybe<&2, String>, dt: Maybe<&2, S.Dt>, arg: Maybe<&2, Arg>) -> PatFound:
  UPat.of(pat, Some{[OpsCONST{}]}, opt_dts(dt), SNone{}, arg, name, False{}, None{}, False{})

def UPat.const(pat: Pat, b: Const, dt: Maybe<&2, S.Dt>) -> PatFound:
  UPat.of(pat, Some{[OpsCONST{}]}, opt_dts(dt), SNone{}, Some{APy{b}}, None{}, False{}, None{}, False{})

# The one-src sugar -- ops.py:1504-1522. Each is `UPat.of` with a fixed `op` and
# `(self,)+src`, so each is one call and there is nothing to decide.
#
# `sink` -- ops.py:1506. `tuple([x for x in srcs if x is not None])` filters Nones
# in Python; here every index is already present, so the caller owns that and
# `None` would be a caller bug, not a runtime case.

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
# arg = (arg, 0)`, so a bare `Ops` arg becomes a `(rop, 0)` REDUCE pair. The port
# takes the two halves directly, which is the same information with the
# `isinstance` test already done at the call site.
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
# self.match_dtype == (dtype,): return self` is a no-op guard, so it is kept:
# it is what stops a redundant CAST from being built.
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
#
#   asrc = (self,)+src
#   UPat(op, boolean if op in {CMPLT, CMPNE} else asrc[-1].match_dtype,
#        list(asrc) if op in GroupOp.Commutative else asrc)
#
# `GroupOp.Commutative` is read off the Op tag, which is what `Ops.value` already
# gives: ADD, AND, CMPEQ, CMPNE, MAX, MUL, OR, XOR -- all BINARY, which is why
# the permutation branch above is exact at arity 2 and refuses 3.
# `asrc[-1]` is the LAST of 1 or 2, so the arity dispatch is two cases.
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

# `boolean if op in {CMPLT, CMPNE} else asrc[-1].match_dtype`

# `list(asrc) if op in GroupOp.Commutative else asrc`

# ops.py:1474-1475: `custom_early_reject` overrides the computed set.

# intern, then hand back the index. The MISS index is the arena's length BEFORE
# the append -- so the two facts are read at different points on purpose, and
# `UPat.of.hit` is where they are brought together. Reading the length AFTER the
# append and subtracting one is the same number, and `UOp.of.intern.put` spells
# it that way; the point is that it must be the pre-append count either way.

# `PatternMatcher` -- ops.py:1587, in its COMPILED form.
#
# This is not the interpreter. `ops.py:1588` is
# `compiled=bool(getenv("UPAT_COMPILE", 1))`, so `upat_compile` is the live path
# and `upat_interpret` is the fallback; and the interpreter is the one carrying a
# mutable store, a cartesian product, and an `is_any` flatten that recurses over
# the pattern's own src. All of that is a workaround for not having locals.
#
# A compiled rule is a TOP-LEVEL DEF named by a tag, and that is the whole design
# here. Three consequences, all of them things the interpreter could not do:
#
#   * THE TABLE IS `Data`, SO IT IS COPYABLE. `PMEntry` is read by the scan and by
#     `early_reject` in the same pass, with no `+` and no linear-table
#     workaround. A table of closures forces `Type`; a table of tags does not.
#   * a rule may read the arena as often as it likes. a closure cannot take a
#     shared argument -- there is no spelling of one in a function type -- so an
#     interpreter rule could not receive `+Arena`. A def can.
#   * a rule's captures are its own parameters. No store, no `setdefault`, no
#     cartesian product, and `is_any` is a DISJUNCTION rather than a flatten.
#
# The cost is the dispatch: Bend has no first-class functions, so a tag selects a
# top-level def through a `match`. One `case` per rule. For `spec.py`'s 82 rules
# that is 82 cases, which is the trade the master plan's LOC rule cares about --
# more lines, in exchange for rules that are individually readable and
# individually gateable.
#
# The runnable model with the gate and the mutation table is
# .agents/slop/notes/compiled-matcher-shape.bend.

# One entry per pattern: the op set it claims (`pdict`'s key in Python),
# `early_reject`, and the tag of the def that IS the compiled rule.
type PMEntry is Data:
  PMEntry{tag: U32, ops: List<&2, Op>, rej: List<&2, Op>}

# A rule table. `Data`, so copyable -- see the header.
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

# `PatternMatcher.rewrite` returns the FIRST non-None, so this is a fold with
# first-wins and `pm_keep` is a leaf. Keying on the ACCUMULATOR is what makes it
# first-wins: keying on the new verdict is last-wins, and a rule that skips then
# erases every earlier verdict, so most verdicts are destroyed before the pass
# ends. Measured -- the last-wins mutation moves three of the model's six rows.
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

# `if cond: v else None`, the shape of most of spec.py's rule bodies. A leaf,
# and what keeps a rule one def instead of three.
def pm_when.of(b: Bool, v: Verdict) -> Verdict:
  match b:
    case True{}: v
    case False{}: VSkip{}

def pm_when(b: Bool, v: Verdict) -> Verdict:
  pm_when.of(b, v)

# THE PASS. `pdict.get(uop.op, [])` as a scan over a flat list in insertion
# order. Python's dict preserves that order and `Map` here is string-keyed while
# `Ops.value` gives a number, so a linear scan is both the faithful order and the
# honest structure.
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
# says it checks `self` first "to avoid creating an intermediate dict", so the
# port does not prepend `self` to the slice and rescan it either: the two halves
# are `self.op in ops or <this fold>`, one `Bool.or` at the call site.
# `Bool.or` does not short-circuit, and here it does not need to: the arena read
# is total (`Arena.node` answers the bottom past the end), so a wasted read is
# not a wrong answer. `+ar` and `+want` are both read once per element.
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
# `Arena.src` and `Arena.op` are ops.bend's OWN readers and return bare values,
# not `Maybe` -- so `ler` is a two-element list built directly, with no
# unwrapping. The model carried its own `Maybe` readers; this reuses the file's.
# `ler` is ops.py:1607's `{u.op for u in uop.src}`, so it is a FOLD OVER THE SRC
# COUNT and not a fixed pair. Reading only src[0] and src[1] was a real bug, found
# by the spec.bend port: spec.py:201's reject set is FOUR ops, so under the pair
# version a four-src PROGRAM could never pass its own necessary condition and its
# rule could never fire. It typechecked, it ran, and every gate row stayed green.
#
# Order does not matter: Python builds a SET and `op_in` scans, so the subset test
# is order-free.
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

# THE ENGINE FAMILY (`_m`). PARALLEL to the `pm_rewrite` family above; this
# one returns the REPLACEMENT NODE, not just the verdict. `pm_rewrite` is the
# scan and decides which rule WANTS the node; `pm_rewrite_m` is the scan and
# the rule body's answer, which is the new U32 (or `None{}` to mean "no
# rewrite, rebuild with rewritten srcs").
#
# WHY A PARALLEL FAMILY. `uop/spec.bend` is the only consumer of `pm_rewrite`
# and reads the Verdict. The codegen rewrite engine is a NEW consumer and
# reads `Maybe<&2, U32>`. The two families co-exist until spec.bend moves
# off Verdict (it won't, in this unit). Each rule's `_m` body takes
# `(ctx: CTX, ar: Arena, self: U32)` and returns `Maybe<&2, U32>`.
# `ctx` is a `List<&2, U32>` here, which is the wall-passing shape from
# `walk_rewrite`; the engine threads it through the dispatch so the rule body
# can read it. The codegen pipeline eventually passes a typed `CTX` record
# and the `List<&2, U32>` becomes the new record's first projection.

# the rule bodies. The default for every rule is "no rewrite" (`None{}`).
# The no-op `pm_rewrite_m` body for a SINK is `Some(self)` so the engine
# does not have to special-case SINK in the rebuild step.

type Aa is Data:
  Aa{b: U32, v: U32}

type CallifyCtx is Data:
  CallifyCtx{replacements: List<&2, U32>, allocs: List<&2, Aa>, views: List<&2, U32>, stores: List<&2, U32>}

def CallifyCtx.of(replacements: List<&2, U32>, allocs: List<&2, Aa>, views: List<&2, U32>, stores: List<&2, U32>) -> CallifyCtx:
  CallifyCtx{replacements, allocs, views, stores}

# `CallifyCtx()` -- all four fields are `field(default_factory=...)`, so four
# `Nil{}`. `CallifyCtx.of` is the four-argument rebuild, exactly as `Ctx.of` is.
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

# `ctx.allocs.get(b, None)` -- the ONE reader of `allocs` a ported body needs.
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

# `ctx.allocs[b] = v`. INSERT if absent and REPLACE if present -- Python's
# `dict[k] = v` does both -- so the walk needs the `found` accumulator `ka_go`
# uses: without it a second write leaves TWO entries for ONE key, and `ca_n3` is
# the row that sees it.
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

# `b in ctx.allocs`
def aa_has(+as: List<&2, Aa>, +b: U32) -> Bool:
  match as:
    case Nil{}       : False{}
    case Aa{j, _} <> t: Bool.or(U32.is_eq(j, b), aa_has(t, b))

# 3. `collect_stores` -- __init__.py:220-221. NEEDS ctx, and it is one of only
# TWO of the twelve that do:
#
#     def collect_stores(ctx:CallifyCtx, u:UOp):
#       if is_store_after(u): ctx.stores.append(u)
#
# Python returns None on BOTH arms and the rewriter reads that as "no rewrite",
# so the ANSWER is `None{}` twice and the only effect is the append. A rule body
# that mutated the ctx and returned the node would be a DIFFERENT rule, so the
# ctx and the answer come back TOGETHER in `Cw`: Python's one-call-one-side-effect
# signature cannot be spelled, and splitting it into two defs would let a caller
# drop one of them.

# `CTX` -- THE REWRITER'S CONTEXT, TYPED. Until now every one of the ~20 defs
# from `pm_r_sink_m` to `graph_rewrite` carried `ctx: CTX`, which is
# `upstream's `RewriteContext.ctx` FLATTENED TO A POSITIONAL LIST. That is enough
# for `pm_post_sched_cache` (its rules read `ctx[slot]`) and it CANNOT EXPRESS
# `_substitute`, whose ctx is `dvars`, KEYED BY NODE:
#
#   _substitute = PatternMatcher([(UPat(tuple(Ops), name="x"), lambda ctx,x: ctx.get(x,None))])
#
# two variants, and the second is the one the list could not hold:
#   CArgs{xs}    -- positional. tags 3, 4, 42. The behaviour is UNCHANGED.
#   CNodes{m}    -- keyed by `U32.show(node)`, i.e. by the node itself.
#
# `CNodes` IS NOT REACHED BY A RULE YET and that is stated rather than implied.
# the sentinel it needs already exists and i said it did not: a node-keyed table
# needs `PMEntry.ops` to mean "any op", `op_in(Nil{}, x)` is `False`, and Nil IS
# ALREADY A NEVER-MATCH DEFAULT in about ten tables (`weak.bend:1631`,
# `mixin/gradient.bend:2062`, `schedule/indexing.bend:1307`,
# `codegen/late/linearizer.bend:1649`, ...), so it cannot be reinterpreted. The
# right sentinel is `all_ops()` -- this file's own, at `:4578`, already used by
# `pm_drop_after` -- so wiring `_substitute` onto `CNodes` is a TABLE and not a
# decision. THE TYPE IS THE WALL THIS REMOVES.
type CTX is Data:
  CArgs{xs: List<&2, U32>}
  CNodes{m: Map<&2, U32>}
  # `canonicalize_alloc`'s ctx. IT IS HERE AND NOT IN `schedule/` FOR A MEASURED
  # REASON: `uop/ops.bend` imports Base, helpers, LAWS/spec and renderer/estimates
  # and NOTHING that reaches `schedule`, while `schedule/__init__.bend` imports
  # `uop/ops.bend`. So a rule body dispatched from `pm_dispatch_m` -- which is in
  # this file -- can only carry a ctx this file can name, and `CallifyCtx` had to
  # MOVE here for that to be possible. `Aa` came with it (its `allocs` element).
  CCallify{c: CallifyCtx}

def CTX.has_hit.m(r: Sigma<&1, &1, Map<&2, U32>, _ => Bool>) -> Bool:
  match r:
    case Tuple{m, v}: v

def CTX.get_v.m(r: Sigma<&1, &1, Map<&2, U32>, _ => U32>) -> U32:
  match r:
    case Tuple{m, v}: v

# `None{}` for an ABSENT node, and the presence test is `Map.has` -- `Map.get`
# answers default `0` and `0` is a legal arena index, which is the exact trap
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
  # the rule does not transform a CAST/BITCAST; it just claims it for
  # tables whose body is identity. The real `pm_dtype_decomps` /
  # `pm_move_gates_from_index` will replace this.
  Some{self}

def pm_r_noop_m(+ctx: CTX, ar: Arena, self: U32) -> Maybe<&2, U32>:
  # NOOP -> its source. The minimal "rule fires and returns a new node".
  Some{Arena.src(ar, self, 0)}

# Tag 3: PARAM. Reads the node's `AParam` arg, looks up `ctx[slot]`. The
# rule fires on a positive slot (0 or 1 in the test fixture; any other slot
# is the "free Variable" sentinel and is left alone with `None{}`).
#
# The .go split: a `match` cannot scrutinize a computed value, so the match
# on `Arena.arg` lives in `pm_r_param_m.go` and the wrapper computes it.
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

# Tag 4: ALLOC. Mints a fresh BUFFER with a placeholder slot (99, dtype int).
# The new arena is the `Found.ar` of `UOp.new`; the engine discards it (the
# `+ar` it carries is the pre-mint arena, and the new node's index points
# into the grown arena which the test fixture does not need to address).
# Tag 4: ALLOC. Returns the pre-minted BUFFER from `ctx[2]`. The
# arena-growth wall: the original implementation minted a BUFFER
# here, but the new arena was discarded by the engine fold, so the
# rebuilt index was unreachable. Returning a pre-minted BUFFER
# avoids the wall entirely: the index is in the engine's arena.
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

# THE OPS.PY RULE TABLES -- ops.py:1898 symbol=_substitute,
# ops.py:1899 symbol=_pm_resolve_params, ops.py:1908 symbol=pm_drop_after, and
# tinygrad/uop/spec.py:207 symbol=spec_program. The FOURTH is NOT IN upstream's
# `ops.py` AT ALL -- upstream has NO `remove_all_tags`, which is THIS port's own
# table -- and the surviving construct is `spec.py`'s `UPat(GroupOp.All-{Ops.CONST}, dtypes.weaks)`.
# These four are the WHOLE of `PatternMatcher` surface in ops.py, and until now
# `pm_dispatch_m` could reach none of them: it answered three placeholder bodies
# (SINK, NOOP, CAST) and codegen's two. `engine/realize.bend:1072-1080` records the wall this
# creates -- "a `PMEntrys` built in THIS file can only ever reach those three
# bodies" -- and the cost is that eleven files in this tree each grew their own
# scan. What follows puts the four in the table that already exists.
#
# `ops.py:1591-1593` symbol=PatternMatcher.__init__ is where a `PMEntry` comes from, and it is three lines:
#
#     entry: list = [p, None, p.early_reject]
#     entry[1] = upat_deferred_compile(p, fxn, entry) if compiled else upat_interpret(p, fxn)
#     for uop in p.op: self.pdict.setdefault(uop, []).append(entry)
#
# `p.early_reject` is field three and `entry[1]` -- the compiled function -- is
# the TAG. `for uop in p.op` is the fan-out that makes `PMEntry.ops` a CLAIMED
# SET, and it is `ops.py:1601` symbol=PatternMatcher.rewrite's
# `self.pdict.get(uop.op, [])`, which `pm_claimed` already reads.
#
# all four reject sets are empty, and that is ops.py's arithmetic rather than a
# shortcut. `ops.py:1469-1470` symbol=UPat.__init__ computes `upat_match` and
# `self.early_reject`, and all four patterns are built with `src=` OMITTED, so
# `src is None`, so `upat_match == []`, so `early_reject == set()`.
# `ops.py:1604` symbol=PatternMatcher.rewrite's `if not early_reject.issubset(ler): continue`
# therefore never skips any of them, and `PMEntry.rej` is `Nil{}` four times. A
# non-empty reject set here would be an invention.

# `tuple(Ops)` -- the claim of ops.py:1898 symbol=_substitute's
# `UPat(tuple(Ops), name="x")` and of tinygrad/uop/spec.py:207 symbol=spec_program's
# `UPat(GroupOp.All-{Ops.CONST}, dtypes.weaks)`. `GroupOp.All` IS `set(Ops)`
# (tinygrad/uop/__init__.py:134 symbol=GroupOp.All), measured by CPython:
# `len(tuple(Ops))` is 77 and `GroupOp.All == set(Ops)` is `True`. One list serves both rules -- 77 for both.
#
# `pm_claimed` SCANS (`op_in`), so the ORDER IS FREE. This is Python's
# enumeration order only so the literal can be diffed against CPython entry by
# entry; `all_ops_n` in `.agents/slop/lintable/03-PROBE.md` re-measures both the
# count and the set against `from tinygrad.uop import Ops`.
def all_ops() -> List<&2, Op>:
  [OpsSPECIAL{} OpsBUFFER{} OpsALLOC{} OpsNOOP{} OpsREWRITE_ERROR{} OpsPARAM{} OpsREFPARAM{} OpsCALL{} OpsPROGRAM{} OpsLINEAR{} OpsSOURCE{} OpsBINARY{},
   OpsSINK{} OpsAFTER{} OpsSTACK{} OpsGETADDR{} OpsINDEX{} OpsSHRINK{} OpsLOAD{} OpsSTORE{} OpsWMMA{} OpsCAST{},
   OpsBITCAST{} OpsEXP2{} OpsLOG2{} OpsSIN{} OpsSQRT{} OpsRECIP{} OpsNEG{} OpsTRUNC{} OpsADD{} OpsMUL{} OpsSHL{},
   OpsSHR{} OpsTRUNCDIV{} OpsMAX{} OpsTRUNCMOD{} OpsCMPLT{} OpsCMPNE{} OpsCMPEQ{} OpsXOR{} OpsOR{} OpsAND{} OpsTHREEFRY{},
   OpsSUB{} OpsFDIV{} OpsPOW{} OpsDIV{} OpsMOD{} OpsWHERE{} OpsMULACC{} OpsBARRIER{} OpsRANGE{} OpsIF{} OpsEND{},
   OpsENDIF{} OpsBACKEDGE{} OpsCONST{} OpsCUSTOM{} OpsCUSTOMI{} OpsINS{} OpsCONTIGUOUS_BACKWARD{} OpsDETACH{} OpsSTAGE{} OpsCOPY{} OpsMSELECT{},
   OpsMSTACK{} OpsCUSTOM_FUNCTION{} OpsRESHAPE{} OpsPERMUTE{} OpsEXPAND{} OpsPAD{} OpsUNSHARD{} OpsREDUCE{} OpsALLREDUCE{} OpsPYLITERAL{}]

# `x.tag is not None` -- the guard of the port's OWN `remove_all_tags` lambda,
# which is NOT IN upstream's `ops.py` at this pin (upstream has NO `remove_all_tags`); the surviving upstream construct is tinygrad/uop/spec.py:207 symbol=spec_program's `UPat(GroupOp.All-{Ops.CONST}, dtypes.weaks)`. `Tag`'s bottom
# is `TNone{}` (this file's `type Tag is Data`, whose five constructors are
# TNone/TBool/TStr/TInt/TTuple), so Python's `None` IS `TNone{}` and the guard is
# the other four. The same shape as `eq_tag.TNone` above, which is why it is a
# separate def and not a fold: a fold over the constructors is the mutual
# recursion the `Tag` header says it would force on `eq_tag`.
def tag_is_none(t: Tag) -> Bool:
  match t:
    case TNone{}: True{}
    case _: False{}

# TAG 40 -- ops.py:1908 symbol=pm_drop_after. `pm_drop_after`:
#     pm_drop_after = PatternMatcher([(UPat(Ops.AFTER, name="a"), lambda a: a.src[0])])
# The body is `a.src[0]`, which is an EXISTING node, so this family answers
# `Maybe<&2, U32>` and needs no arena of its own -- it is the one ops.py rule in
# this file that a rebuilding-rule-free table can already carry.
#
# `ctx` is unused because ops.py's lambda takes one and does not read it. The
# claim (`OpsAFTER`) is `PMEntry.ops`, not a guard in here.
def pm_r_drop_m(+ctx: CTX, +ar: Arena, +self: U32) -> Maybe<&2, U32>:
  Some{Arena.src(ar, self, 0)}

# TAG 42 -- ops.py:1899 symbol=_pm_resolve_params. `_pm_resolve_params`:
#     _pm_resolve_params = PatternMatcher([(UPat(Ops.PARAM, name="p"), lambda ctx,p: ctx[p.arg.slot] if p.arg.slot >= 0 else None)])
#
# TWO DIFFERENCES FROM `pm_r_param_m` (tag 3) above, and both are the source:
#   * tag 3 answers `ctx[0]` and `ctx[1]` ONLY and `None{}` for every other slot,
#     because it is the codegen fixture. ops.py indexes WHATEVER slot the PARAM
#     carries, so this one is `List.get` and no slot is special.
#   * `p.arg.slot >= 0` is TRUE for EVERY Python `int`, so in Python the guard is
#     vacuous; the only thing it can be excluding is an arg that is not an
#     `AParam` at all, and `p.arg.slot` would raise there. So the port's guard is
#     the `AParam` match, and the bottom below stands for "no slot".
# `4294967295` is `U32`'s top and cannot be a real slot (`ParamArg.slot` counts
# program inputs), so it is the bottom. It is matched EXPLICITLY rather than left
# to `List.get`, because `U32.to_nat` on the top is a `Nat` no `List.get` answers
# and the out-of-range behaviour would then be an accident of that fold.
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

# dispatch by tag. Tags 0/1/2 are the same as `pm_dispatch.go`. Tags 3/4
# are the codegen pipeline's `pm_post_sched_cache` rules and read `ctx`.
# Tags 40/42 are ops.py's own, above.
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

# `pm_scan_m` is a first-wins fold over the rule list. First `Some` wins;
# later `Some`s are dropped. The accumulator is `Maybe<&2, U32>` and the
# identity is `None{}`. The order is the table order, which IS Python's
# `PatternMatcher` order (Python's `pm.rewrite` returns the first non-None
# result).
def pm_scan_m(+ts: PMEntrys, +ar: Arena, +self: U32, todo: List<&2, PMEntry>, acc: Maybe<&2, U32>, +ctx: CTX) -> Maybe<&2, U32>:
  match todo:
    case Nil{}: acc
    case e <> t:
      match acc:
        case Some{value}: acc
        case None{}: pm_scan_m(ts, ar, self, t, pm_try_m(ts, ar, self, e, ctx), ctx)

def pm_rewrite_m(+ts: PMEntrys, +ar: Arena, +self: U32, +ctx: CTX) -> Maybe<&2, U32>:
  pm_scan_m(ts, ar, self, PMEntrys.es(ts), None{}, ctx)

# two more tables, and each exists because of a TYPE, not a preference.
#
# one table cannot hold all four of ops.py's rules, and the blocker is not
# linearity. `ops.py:1600` symbol=PatternMatcher.rewrite and `ops.py:1698` symbol=TrackedPatternMatcher.rewrite type the pass's `ctx` as `ctx=None`, and each lambda
# reads whatever shape it likes off it, so Python has no reason for the four to
# agree. A Bend parameter has a type, so:
#
#     _pm_resolve_params   ctx[p.arg.slot]      -> List<&2, U32>   tag 42, above
#     _substitute          ctx.get(x)           -> Map<&2, U32>    tag 43, `_sub`
#     remove_all_tags      (ctx unused)         -> List<&2, U32>   tag 41, `_f`
#     pm_drop_after        (ctx unused)         -> List<&2, U32>   tag 40, above
#
# And there is a second, sharper blocker, which is the one `pm_r_alloc_m` above
# already paid for: `remove_all_tags` MINTS. `ops.py:245-249` symbol=UOp.replace returns
# a NEW UOp, so `UOp.new` returns `Found{ar, i}` and the arena it grew is part of
# the answer. `pm_rewrite_m` answers `Maybe<&2, U32>` -- an INDEX and no arena --
# so a rebuilding rule cannot be carried by that family at all. Hence `_f`, whose
# answer is `Maybe<&2, Found>` and which is the first table in this file whose
# rule can hand back a grown arena.
#
# `_sub` is the opposite problem: one rule, one entry, and a ctx type of its own,
# so it gets a THREE-DEF family and no scan at all -- a one-entry scan is
# `pm_try_m` with a different ctx type, and spelling that out is two lines worse
# than reading the one entry.

# TAG 41 -- tinygrad/uop/spec.py:207 symbol=spec_program. `remove_all_tags`:
#     remove_all_tags = PatternMatcher([(UPat(GroupOp.All, name="x"), lambda x: x.replace(tag=None) if x.tag is not None else None)])
#
# `remove_all_tags` is NOT IN upstream's `ops.py` AT THIS PIN; the surviving upstream construct that matches "every op" is `spec.py`'s `UPat(GroupOp.All-{Ops.CONST}, dtypes.weaks)`.
# `ops.py:245-249` symbol=UOp.replace is what `replace(tag=None)` is:
#     new_args = (kwargs.pop("op", self.op), kwargs.pop("src", self.src), kwargs.pop("arg", self.arg), kwargs.pop("tag", self.tag))
#     if (self.op, self.src, self.arg, self.tag) == new_args: return self
#     return UOp(*new_args)
# so the port is the node rebuilt with all four of ITS OWN fields and `TNone{}` in the tag slot -- which is `ops.bend:896 symbol=TNone`'s inline `replace`, already written.
#
# THE MINT IS EAGER, and that is safe rather than lazy. `Bool.pick` CHOOSES an arm
# and does not SEQUENCE one, so the `UOp.new` runs on both paths. For an
# already-untagged node that is a NO-OP and not a leak: `UOp.make.intern.put` is
# `case Some{i}: ar` (`UOp.make.intern`, this file) -- a structurally identical
# node returns the index it already has and the arena does NOT grow. So `None{}`
# for a tagged node is the only answer that can lose information, and eager
# evaluation cannot produce it.
# THE PARAMETER IS NAMED `untagged`, NOT `tagged`, and the first draft called it
# `tagged` while passing it `tag_is_none(...)`. That compiled, typechecked, answered
# CORRECTLY for every input, and the probe's `pick_t_rule`/`pick_f_rule` pair is what
# found it: those two rows are written from the port's OWN `remove_all_tags` guard,
# which is NOT IN upstream's `ops.py`; the surviving upstream construct that matches
# "every op" is tinygrad/uop/spec.py:207 symbol=spec_program. And the implementation
# answered the other way round, so the row and the code disagreed and the ROW was
# right about what the name claims. A name that is the negation of the value it holds
# is the same defect as a shadowed binder with better manners: both compile, both report their flag correctly, and both mislead whoever writes the next mutation.
def pm_r_tag_m.of(untagged: Bool, made: Found) -> Maybe<&2, Found>:
  Bool.pick(Maybe<&2, Found>, untagged, None{}, Some{made})

def pm_r_tag_m(+ctx: CTX, +ar: Arena, +self: U32) -> Maybe<&2, Found>:
  pm_r_tag_m.of(tag_is_none(Arena.tag(ar, self)),
    UOp.new(ar, Arena.op(ar, self), Arena.srcs(ar, self), Arena.arg(ar, self), TNone{}))

# TAG 43 -- ops.py:1898 symbol=_substitute. `_substitute`:
#     _substitute = PatternMatcher([(UPat(tuple(Ops), name="x"), lambda ctx,x: ctx.get(x,None))])
#
# The ctx is `dvars: dict[UOp, UOp]` (`ops.py:514` symbol=UOp.substitute), so it is keyed by the NODE
# and not by a slot. Bend's `Map` is STRING-keyed -- `Map.set(a, -V, m, key:
# String, x)` and `Map.has(-a, -V, m, key: String)` in the compiler's `base.bend`
# -- so the key is `U32.show(self)`, which is the arena index in string form and
# is what `uop/render.bend:1419` and `:1426` already do for a node-keyed map.
#
# `ctx.get(x, None)` IS ONE LOOKUP, and `Map.get` needs a default because a miss
# is indistinguishable from a value of 0 by the value alone. `Map.has` is what
# tells them apart, exactly as `vv_of` above says it must.
# BOTH READERS ANSWER A `Sigma`, not a bare value -- `Map.get` returns the map and
# the value and `Map.has` returns the map and the Bool (`base.bend`'s signatures:
# `Map.has(...) -> Map<a, V> & Bool`, `Map.get(...) -> Map<&2, V> & V`). So the
# destructuring is a TWO-SCRUTINEE match, which is `uop/render.bend`'s `cu32`/`chas`
# on the same map type. `U32, Bool` would be one scrutinee and is not the shape.
def pm_sub_m.of(r: Sigma<&1, &1, Map<&2, U32>, _ => U32>, s: Sigma<&1, &1, Map<&2, U32>, _ => Bool>) -> Maybe<&2, U32>:
  match r, s:
    case Tuple{m, v}, Tuple{n, b}: Bool.pick(Maybe<&2, U32>, b, Some{v}, None{})

def pm_sub_m(+ctx: Map<&2, U32>, +ar: Arena, +self: U32) -> Maybe<&2, U32>:
  pm_sub_m.of(Map.get(U32, 0, ctx, U32.show(self)), Map.has(&2, U32, ctx, U32.show(self)))

# THE THREE TABLES. Each is `ops.py`'s own `PatternMatcher(...)` as a literal,
# and each entry's three fields are `ops.py:1604`'s `[p, None, p.early_reject]`
# with the compiled function's PLACE taken by the tag.
#
# the tag is global and the table is not. Every `PMEntry` in the tree numbers its
# own rules from 0 -- `codegen/__init__.bend:317 symbol=pm_post_sched_cache`'s tag 0 is `_pm_resolve_params`
# and `engine/realize.bend:1145 symbol=get_call_name`'s tag 0 is `pm_flatten_linear` -- because the
# scan that reads a table and the dispatch that reads a tag live in DIFFERENT
# files. That is the "a name is not a binding" trap one level down: the same
# `PMEntry{0, ...}` means a different rule in every one of them. Tags 40-43 are
# the ops.py four, so the numbers here are the ones `pm_dispatch_m` above can
# reach; tags 0-32 and 999 are already taken somewhere in the tree.
def pm_substitute() -> PMEntrys:
  PMEntrys{[PMEntry{43, all_ops(), Nil{}}]}

def pm_resolve_params() -> PMEntrys:
  PMEntrys{[PMEntry{42, [OpsPARAM{}], Nil{}}]}

def pm_remove_all_tags() -> PMEntrys:
  PMEntrys{[PMEntry{41, all_ops(), Nil{}}]}

def pm_drop_after_table() -> PMEntrys:
  PMEntrys{[PMEntry{40, [OpsAFTER{}], Nil{}}]}

# `_f` IS THE `_m` FAMILY WITH A DIFFERENT ANSWER, so it is the same five defs in
# the same order -- `pm_rewrite_f`, `pm_scan_f`, `pm_try_f`, `pm_try_f.of`,
# `pm_try_f.go` against `pm_rewrite_m`, `pm_scan_m`, `pm_try_m`, `pm_try_m.of`,
# `pm_try_m.go`. First-wins is `pm_scan_m`'s accumulator match and it is unchanged:
# a `Some{}` in the accumulator stops the fold, so the table order IS the rule
# order (ops.py:1618's `return ret` on the first non-None).
#
# declaration order is the other half of that. `pm_rewrite_f` is last because a
# def may only call defs declared ABOVE it, and putting it first fails with
# "expected : a filled definition" -- measured, not remembered.
#
# `.of`/`.go` is not decoration. `pm_try_f.of` computes `Bool.and(claimed, early)`
# and HANDS IT OVER; `pm_try_f.go` matches the parameter. Folding the `match`
# into `.of` is refused -- "a match cannot scrutinize a computed value" -- and
# that is measured here, not remembered: it was the first compile of this block.
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

# one rule: does it claim this op, and does `early_reject` pass?

# --- `early_reject`, and THE NAME IS A MISLEADER ---------------------------
#
# ops.py:1609 is `if not early_reject.issubset(ler): continue`, so the rule FIRES
# when the op set IS a subset of `ler` and is SKIPPED when it is not. It reads
# as a reject set and computes as a NECESSARY CONDITION: it is built from the ops
# of the pattern's FIRST src, and an empty set is a subset of everything, which is
# why the many rules with an empty `early_reject` always fire.
#
# `ler` is `uop.__dict__['_src_ops']`, CACHED ON THE UOP. There is no mutable uop
# here, so it is recomputed per rule, and that cache is the one place this port is
# slower than the thing it ports.

# `ler`: the ops among the node's srcs

# --- the op-set membership tests -------------------------------------------

# `uop.op in self.op`
# `uop.op in self.op`. `Arena.op` is ops.bend's own reader, so no Maybe here.

# `uop.op is want`, which is `len(self.op) == 1` specialised

# `uop.src[n].op is want` -- the read a capture replaces
def src_op(+ar: Arena, self: U32, n: U32, want: Op) -> Bool:
  op_is(ar, Arena.src(ar, self, n), want)

# THE DISPATCH. `upat.py` emits a closure; Bend has no first-class functions, so
# the tag selects a top-level def. THIS is the mechanism, and it is why the table
# is `Data` rather than a list of closures.
#
# `UPatCompileError` -- ops.py:1588 raises when a pattern's source cannot be read,
# because the compiler reflects on the CALLING FRAME to find the pattern's
# location. There is no frame here, so a rule that cannot be compiled has no
# representation at all: it is a missing `case` below, and the honest response is
# a missing def rather than a runtime error.

# --- the rules -------------------------------------------------------------
#
# `spec_shared`'s first two entries plus the CAST rule: a leaf, a leaf, and an
# `is_any` disjunction. These are the three shapes that need nothing from a
# store, because a compiled rule's captures are its own parameters.

# `(UPat(Ops.SINK, dtypes.void), lambda: True{})`

# `(UPat(Ops.NOOP), lambda: True{})` -- TODO: remove this

# `is_any` is a DISJUNCTION, which is what upat.py:18 compiles it to. The
# interpreter FLATTENED the alternatives and recursed over the pattern's own src;
# this is straight-line code, so that recursion is not present.

# THE BASE FAMILY -- ops.py:785 `base`, :792 `unsharded_base`, :801
# `storage_base`, :623 `without_after`, :925 `buf_uop`, :952
# `has_buffer_identity`. Six walks down `src[0]`, and they differ ONLY in the set
# of ops each one walks past -- which is the whole of what makes them six defs
# rather than one parameterised one (see THE ONE PARAM BELOW).
#
# WHAT EACH IS IN PYTHON, and the sets are the entire difference:
#     base                GroupOp.Movement | {DETACH}
#     unsharded_base      GroupOp.Movement | {DETACH, UNSHARD}
#     storage_base        that, then {BITCAST, AFTER} as well
#     without_after       {AFTER}
#     buf_uop             walks while `len(s.src) and s.op not in
#                         {BUFFER, ALLOC, PARAM, STAGE, MSTACK}` -- a WALK PAST a
#                         non-buffer, not a peel, so the answer is the first
#                         buffer-ish node DOWN the spine
#     has_buffer_identity {RESHAPE, UNSHARD, MSELECT}, plus {AFTER} when
#                         `after_ok`, and the terminal answer is
#                         `op in {BUFFER, ALLOC, PARAM}`
# `base` is ALSO in ./fold.bend (`UOp.base`, a table read of the Kahn fold).
# That is not a duplicate: the fold carries it because it shares the table, and
# this one carries it because a peel that needs only the OP needs no table, and
# paying for one would be the fold's cost for the fold's absence. The two agree
# because the peel and the fold compute the same function; `s5_base_*` is the row
# that holds them to it.
#
# THE SHAPE, and it is the reason this block is 90 lines and not 30. A walk is a
# self-call on `Arena.src(ar, self, 0)`, and a self-call must pass a SUBTERM of
# its own parameter -- a store read is not one. So the walk cannot be the
# self-call, and three shapes were measured and refused before this one:
#
#   * `Bool.pick(U32, peels(ar, self), walk(..., Arena.src(ar, self, 0), ...), self)`
#     -- `self` in both arms, the arms are not exclusive, and a parameter read
#     once per arm is still "consumed more than once" when they are in ONE
#     expression.
#   * the `.go` split (`X.go` above `X`, R-3): `X.go` CALLS `X`, so the pair is
#     mutually recursive and that is refused outright. The error is the unfilled-
#     law one and it names the PARENT, which is the least useful message in the
#     compiler.
#   * a two-scrutinee `match fuel peels:` -- `peels` is a call at the call site
#     and `match` may not scrutinise a computed value. The split is not optional.
#
# what works is the fuel with the stop encoded in the node. One def, one
# scrutinee, and `p` is the first argument so the decrease check passes:
#
#     match fuel:
#       case 0n: <the terminal answer, on the node the walk stopped at>
#       case 1n+p: X(p, ar, Bool.pick(<T>, <walks>, Arena.src(ar, self, 0), self))
#
# A node that does not walk is carried UNCHANGED for the rest of the fuel and
# comes back out of `case 0n:`, so the answer is exact whenever the fuel
# outlasts the walk and the fuel is `Arena.budget(ar)`, which the header shows is
# the only sound one. The cost is that a terminal node burns the whole budget;
# that is a constant factor on a walk already O(fuel), and it is the price of six
# defs instead of one def and a set parameter.
#
# WHY `+self` AND `+ar` EVERYWHERE. `Bool.pick` reads both arms, so each is read
# twice in one expression. `+` on a `U32` is free (bend2-constraints rule 29) and
# `+ar` is the arena being `Type`-affine, the same `+` every arena reader here
# takes.
#
# THE ONE PARAM. All six are `T -> T` over a node, and Bend has no higher-order
# def -- a function value in a datatype field forces `Type`, and a `Type` cannot
# be parameterised. So the set is spelled in each def's `peel` and the six share
# the FUEL SHAPE and nothing else. That is six near-identical three-line defs,
# and it is not the copy-paste the reviewer rules out: the copy-paste rule is
# about logic that could be hoisted, and this cannot be, because the one thing
# that differs is the thing a parameter would have to carry.

# `base` -- ops.py:785. `if self.op in GroupOp.Movement: return self.src[0].base;
# if self.op is Ops.DETACH: return self.src[0].base; return self`
def UOp.base.peel(+ar: Arena, +self: U32) -> Bool:
  Bool.or(GroupOp.movement(Arena.op(ar, self)), eq_op(Arena.op(ar, self), OpsDETACH{}))

def UOp.base(fuel: Nat, +ar: Arena, +self: U32) -> U32:
  match fuel:
    case 0n: self
    case 1n+p: UOp.base(p, ar, Bool.pick(U32, UOp.base.peel(ar, self), Arena.src(ar, self, 0), self))

# `unsharded_base` -- ops.py:792. Python's second and third arms are `self.src[0]
# .base`, NOT `.unsharded_base`, so this is `base` with UNSHARD added to the SET
# and not a recursion -- which is why it is one peel and not two.
def UOp.unsharded_base.peel(+ar: Arena, +self: U32) -> Bool:
  Bool.or(UOp.base.peel(ar, self), eq_op(Arena.op(ar, self), OpsUNSHARD{}))

def UOp.unsharded_base(fuel: Nat, +ar: Arena, +self: U32) -> U32:
  match fuel:
    case 0n: self
    case 1n+p: UOp.unsharded_base(p, ar, Bool.pick(U32, UOp.unsharded_base.peel(ar, self), Arena.src(ar, self, 0), self))

# `storage_base` -- ops.py:801. Python is `b = self.unsharded_base; while b.op in
# {BITCAST, AFTER, UNSHARD}: b = b.src[0].unsharded_base; return b` -- a `while`,
# and this is that `while` as ONE peel with all three added to the set. The
# `unsharded_base` set alone is NOT sufficient and `s5_storage_base_bc` is the
# row: BITCAST is not a movement op, so `unsharded_base` stops on it (that row
# reads BITCAST) and `storage_base` does not (that row reads BUFFER).
def UOp.storage_base.peel(+ar: Arena, +self: U32) -> Bool:
  Bool.or(UOp.unsharded_base.peel(ar, self),
    Bool.or(eq_op(Arena.op(ar, self), OpsBITCAST{}), eq_op(Arena.op(ar, self), OpsAFTER{})))

def UOp.storage_base(fuel: Nat, +ar: Arena, +self: U32) -> U32:
  match fuel:
    case 0n: self
    case 1n+p: UOp.storage_base(p, ar, Bool.pick(U32, UOp.storage_base.peel(ar, self), Arena.src(ar, self, 0), self))

# `without_after` -- ops.py:623. `self.src[0].without_after if self.op is Ops.AFTER
# else self`. It does NOT strip UNSHARD, which `s5_wo_after_us` is the row for.
def UOp.without_after(fuel: Nat, +ar: Arena, +self: U32) -> U32:
  match fuel:
    case 0n: self
    case 1n+p: UOp.without_after(p, ar, Bool.pick(U32, eq_op(Arena.op(ar, self), OpsAFTER{}), Arena.src(ar, self, 0), self))

# `buf_uop` -- ops.py:925. NOT a peel: Python walks while `len(s.src) and s.op not
# in {BUFFER, ALLOC, PARAM, STAGE, MSTACK}`, so it goes PAST a RESHAPE to reach
# the BUFFER under it, and a peel-shaped reading would stop at the RESHAPE. The
# `len(s.src)` half matters on its own -- a leaf is the answer, so a BUFFER with
# no srcs must not walk off the end of the arena.
def UOp.buf_uop.cont(op: Op) -> Bool:
  match op:
    case OpsBUFFER{}: False{}
    case OpsALLOC{}: False{}
    case OpsPARAM{}: False{}
    case OpsREFPARAM{}: False{}
    case OpsSTAGE{}: False{}
    case OpsMSTACK{}: False{}
    case _: True{}

# `len(s.src) and s.op not in {...}` -- the `len` half is load-bearing on its own,
# because a leaf is the answer and a BUFFER with no srcs must not walk off the end.
def UOp.buf_uop.walk(+ar: Arena, +self: U32) -> Bool:
  Bool.and((Arena.nsrc(ar, self) > 0 : U32), UOp.buf_uop.cont(Arena.op(ar, self)))

def UOp.buf_uop(fuel: Nat, +ar: Arena, +self: U32) -> U32:
  match fuel:
    case 0n: self
    case 1n+p: UOp.buf_uop(p, ar, Bool.pick(U32, UOp.buf_uop.walk(ar, self), Arena.src(ar, self, 0), self))

# `has_buffer_identity` -- ops.py:952. A `U32 -> Bool` walk, so the same shape
# with a `Bool` accumulator and a TERMINAL answer that is not the node.
#
# `after_ok` is a parameter and both its values are rows (`s5_hbi_*` and
# `s5_hbi_after_*`). The two differ on exactly ONE fixture, `af`, so a port that
# dropped the parameter would agree on the other eight and be wrong on the ninth
# -- which is the whole reason both are printed. Python's arms:
#     {RESHAPE, UNSHARD, MSELECT} -> src[0]
#     after_ok and AFTER         -> src[0]
#     else                       -> op in {BUFFER, ALLOC, PARAM}
# `op in {RESHAPE, UNSHARD, MSELECT}`, as a ladder rather than `op_in` over a
# literal list: this is on the hot path of every storage walk and the list would
# be rebuilt at every node. `+op` because `Bool.or` does not short-circuit, so all
# three comparisons are evaluated and `op` is read three times.
def op_in3(+op: Op) -> Bool:
  Bool.or(eq_op(op, OpsRESHAPE{}), Bool.or(eq_op(op, OpsUNSHARD{}), eq_op(op, OpsMSELECT{})))

def UOp.has_buffer_identity.walk(after_ok: Bool, +ar: Arena, +self: U32) -> Bool:
  Bool.or(op_in3(Arena.op(ar, self)), Bool.and(after_ok, eq_op(Arena.op(ar, self), OpsAFTER{})))

# The terminal answer, and it is NOT "the node's own op is in the walk set" --
# it is a different set, so the two are separate defs and the fuel arm has to
# call BOTH. Getting that wrong answers `s5_hbi_af` 1 for the `after_ok=False`
# lane, which is the row that moves.
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
# :772 `mselect`, :707 `sharding`, :685 `split_uop`, :1893 `sint_to_uop`,
# :1901 `gate_kernel_sink`. Eight defs, and each is a `UOp(...)` call or a fold
# with no dtype and no shape in it, which is why they are here and the rest of
# ops.py:501-1928 is not.
#
# `kwargs` IS GONE, as everywhere else in this file: Python threads it through
# thirty of these and forwards it to the constructor, so it carries op/arg/tag.
# Bend has no kwargs, so the three constructor fields are spelled at the call
# site and the sugar that only forwards them collapses to the call. `barrier`
# and `bufferize` are that collapse, and they are here anyway because the ARG
# they choose is a decision, not a forwarding: `bufferize` answers `ABad{}` where
# `barrier` would answer `ANone{}`, and a row that prints the node's op and src
# sequence is what holds both.

# `bufferize` -- ops.py:679. `UOp(Ops.STAGE, src=(self,)+args, kwargs)`, and
# the two fixtures differ ONLY in the extra src, so `s5_bufferize_arg` is the row
# that sees `+args` at all and `s5_bufferize` is the row that sees the op is STAGE
# and not a forwarding of something else.
def UOp.bufferize(ar: Arena, +self: U32, +args: List<&2, U32>) -> Found:
  UOp.new(ar, OpsSTAGE{}, List.append(&2, U32, [self], args), ABad{}, TNone{})

# `barrier` -- ops.py:624. `UOp(Ops.BARRIER, src=(self,)+src)`, self FIRST, the
# same self-first convention `UOp.after` and `UOp.end` have.
def UOp.barrier(ar: Arena, +self: U32, +src: List<&2, U32>) -> Found:
  UOp.new(ar, OpsBARRIER{}, List.append(&2, U32, [self], src), ABad{}, TNone{})

# `allreduce` -- ops.py:680. `UOp(Ops.ALLREDUCE, src=(self,), arg=(op, device))`
# -- exactly ONE src, self, and the arg is the PAIR `(rop, dev)`, which is
# `AAllred`. The device must be a TUPLE, which is why the fixture is a
# two-element one: `assert isinstance(self.device, tuple)`, and the port's
# `S.Dn{tags}` is that tuple.
def UOp.allreduce(ar: Arena, +self: U32, +rop: Op, +dev: S.Dev) -> Found:
  UOp.new(ar, OpsALLREDUCE{}, [self], AAllred{rop, dev}, TNone{})

# `mselect` -- ops.py:772. `UOp(Ops.MSELECT, src=(self,), arg=arg)` where `arg` is
# an INT -- a shard index into a multi-device tensor -- and the port spells it `AInt`.
# `ABlob` is BINARY's BYTES, not "a bare number in the arg": `ops.py:201`'s key holds
# `type(arg)`, so an int and a bytes are two kinds, and the port wrote a ONE-BYTE
# `ABlob{[k]}` here until 2026-10-06. `--graph mselect` then measured the two differ
# lanes disagreeing on exactly that (`arg py=i0 bend=y n(i0)`,
# `runs/graphcmp/D/D1-graph-mselect.txt`, VERDICT DISAGREE), which is the wall this
# comment used to carry. The `WALL(p3)` is CLOSED by the `AInt` variant and
# `eq_arg.AInt` above -- a NEW `Arg` arm, which is what it said the fix was.
# `ABlob` is injective in `k` was true and beside the point: injectivity is not the
# same as the key agreeing with CPython's.
def UOp.mselect(ar: Arena, +self: U32, k: U32) -> Found:
  UOp.new(ar, OpsMSELECT{}, [self], AInt{k}, TNone{})

# `sharding` -- ops.py:707. `tuple(zip(self.arg, self.src[1:])) if self.op is
# Ops.UNSHARD else ()`. The arg is the SORTED tuple of sharded axes and the srcs
# carry one RANGE each, so the answer is a list of PAIRS -- and `Shard{ax, rng}`
# is a `Data` record because Bend has no tuple and the two travel together. The
# op test is not decoration: `s5_sharding_none` is a RESHAPE whose answer is the
# EMPTY list, so a port that dropped the `if` would answer a pair for it.
type Shard is Data: Shard{ax: U32, rng: U32}

# `zip(self.arg, self.src[1:])` -- stops at the shorter, as Python's does. The two
# lengths are equal for every UNSHARD tinygrad builds, so the row is the CONTENT
# and not a length, and the three arms are the cross product the checker wants.
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
# s.split_uop(sep) else: yield self` -- a generator, and a generator is a fold with
# an accumulator and no early exit. THE ORDER IS PYTHON'S and the row is what says
# so: the srcs go on the FRONT of the worklist, which makes the walk depth-first
# PRE-order, which is what `yield from` in source order produces. A fold that
# appended them at the back would answer the same LENGTH on every fixture and the
# REVERSED sequence, which is why `s5_split_*` prints the sequence and not a count.
#
# ONE `Data` RECORD, `Wk`, and it is forced by the countdown. A two-scrutinee
# `match fuel xs:` needs the cross product, so the exhausted `0n` arm has to bind
# the list too -- and `0n` is a PREFIX that already claims every successor, so the
# arm meant to say "out of fuel" silently becomes "any fuel, any list" and the
# fold never terminates. Measured, not assumed: it ran until the arena's memory
# nodes ran out and it looked exactly like an infinite loop. ONE scrutinee, the
# fuel, with the worklist in the record, is the fix.
#
# THE STEP IS A `Bool.pick` AND NOT A `match`, because `sep` is a PARAMETER and
# `Op` has seventy-eight constructors: a `match op: case OpsADD{}:` is exhaustive
# only because the separator is a literal, and here it is not. The `+ar` and `+h`
# are the two-read rule -- `Arena.op(ar, h)`, `Arena.srcs(ar, h)` and `[h]` are
# three reads of one node -- and `+` on a `U32` is free.
type Wk is Data: Wk{work: List<&2, U32>, out: List<&2, U32>}

def Wk.out(w: Wk) -> List<&2, U32>:
  match w:
    case Wk{work, out}: out

# THE POPPED NODE, as a record, and it is the SECOND `Data` record for the same
# reason `Wk` is the first. The step needs three things about the popped node --
# whether it is the separator, what its srcs are, and its own index -- and all
# three are READS OF ONE `h`. A `U32` is not affine, so the reads are legal under
# `+h`, but then `match` needs a FIELD to scrutinise and `split_uop.sep(ar, sep, h)`
# is a call. So the DECISION is what goes in the record: `go` is computed once at
# the pop and the step matches on it.
#
# MEASURED, and this is the bug the shape exists to prevent: the first version had
# the step return the new OUTPUT and the worklist shrink independently, so a node
# that IS the separator had its srcs appended to the ANSWER instead of being
# descended into. It typechecked, it checked, and `s5_split_nest` read
# `Ops.ADD Ops.CONST` where CPython reads three CONSTs -- the src sequence with
# the descent missing. Both lists therefore live in `Wk` and the step returns the
# whole `Wk`, so "which list grows" is the arm and not an accident of the return
# type.
type Nd is Data: Nd{go: Bool, srcs: List<&2, U32>, i: U32}

def UOp.split_uop.node(+ar: Arena, +sep: Op, +h: U32) -> Nd:
  Nd{op_is(ar, h, sep), Arena.srcs(ar, h), h}

# THE SEPARATOR, and it is the file's own `op_is` rather than a second copy of it.
# Python's `self.op is sep` with `op` a FIELD binder, so this is a parameter and
# not a ladder -- which is the whole difference between this and the first version
# of the step, and reusing `op_is` is the whole difference between one copy of it
# and two.
# A separator: push its srcs ONTO THE WORKLIST, at the FRONT. That is what makes
# the walk depth-first PRE-order, which is what `yield from` in source order is.
# Not a separator: keep the node, on the ANSWER.
#
# the two lists are parameters and not the record, and that is a measured wall
# rather than a preference: `match nd:` kills every name bound before it, so a
# `match go:` nested inside a second `match w:` cannot see `go`. Passing `work`
# and `out` as parameters puts them on the right side of both matches, and the
# step still answers a `Wk` so the caller cannot grow the wrong list by accident.
def split_uop.step(nd: Nd, work: List<&2, U32>, out: List<&2, U32>) -> Wk:
  match nd:
    case Nd{go, srcs, i}:
      match go:
        case True{}: Wk{List.append(&2, U32, srcs, work), out}
        case False{}: Wk{work, List.append(&2, U32, out, [i])}

# ONE def: the fuel is the scrutinee and the worklist is DESTRUCTURED in the same
# arm, so there is no sub-def and therefore no mutual recursion. R-3 would want a
# `.pop` above this and mutual recursion is refused, and a def carrying both
# matches in its own body is the only arrangement with neither problem.
def UOp.split_uop.pop(fuel: Nat, +ar: Arena, +sep: Op, w: Wk) -> Wk:
  match fuel:
    case 0n: w
    case 1n+p:
      match w:
        case Wk{work, out}:
          match work:
            case Nil{}: w
            case h <> rest: UOp.split_uop.pop(p, ar, sep, split_uop.step(UOp.split_uop.node(ar, sep, h), rest, out))

# `split_uop(self, sep)` with the root already on the worklist. The fuel is the
# caller's and the only sound one is `Arena.budget(ar)`: one step per worklist
# entry, and an entry is pushed once per edge into a node plus once for the root.
def UOp.split_uop(fuel: Nat, +ar: Arena, self: U32, +sep: Op) -> List<&2, U32>:
  Wk.out(UOp.split_uop.pop(fuel, ar, sep, Wk{[self], Nil{}}))

# `sint_to_uop` -- ops.py:1895 symbol=sint_to_uop. `UOp.const(x, dtype=dtypes.weakint)`, and the
# whole of it is that a `sint` is either already a UOp or a literal CONST. The
# port's `Sint` is exactly that union (`SI{i64}` | `SU{uop}`), so the def is the
# two arms and nothing else: the `SU` arm is the node itself and the `SI` arm
# mints a weakint CONST. This is the def `UOp.range` and `UOp.special` would take
# a `Sint` from, and it is why those two take a `U32` today.
def UOp.sint_to_uop(ar: Arena, s: Sint) -> Found:
  match s:
    case SU{u}: Found{ar, u}
    case SI{i}: UOp.new(ar, OpsCONST{}, Nil{}, APy{CInt{i}}, TNone{})

# `gate_kernel_sink` -- ops.py:1915 symbol=gate_kernel_sink. Three arms, two of them NEGATIVE tests, and
# the third is `isinstance(x.arg, KernelInfo)` -- an ARG-TYPE test, which in the
# arena is a `match` on the `Arg` and NOT on `Arena.arg(ar, x)` for the reason
# the `Nd` record above exists. The rows are one per arm: `s5_gate_linear` (0),
# `s5_gate_kernel` (0) and `s5_gate_plain` (1), and a port that collapsed the two
# negatives would answer 1 on one of the first two.
# `isinstance(x.arg, KernelInfo)` is an ARG-TYPE test, and in the arena that is
# the `AKernel` arm -- so a SINK with any other arg is True, which is the arm a
# check that tested the OP instead would get wrong.
def gate_kernel_sink.arg(arg: Arg) -> Bool:
  match arg:
    case AKernel{ki}: False{}
    case _: True{}

# The op test and the arg test are ONE def over TWO reads of the node, and the op
# is a parameter so the ladder is a legal scrutinee. Both reads are needed: the
# LINEAR arm is an op test and the KernelInfo arm is an arg test, and either one
# alone answers the wrong thing on one of the three rows. `+` on the `Arg` because
# it is read once per SINK arm. R-3: this is ABOVE the entry, not below it.
def gate_kernel_sink.of(op: Op, +arg: Arg) -> Bool:
  match op:
    case OpsLINEAR{}: False{}
    case OpsSINK{}: gate_kernel_sink.arg(arg)
    case _: True{}

def gate_kernel_sink(+ar: Arena, +x: U32) -> Bool:
  gate_kernel_sink.of(Arena.op(ar, x), Arena.arg(ar, x))

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
# so the folds do not fit in one BEND module as the python is written. The fix is
# known and it is not a hack: fold dtype and shape together into ONE def that
# answers the pair, drive it with a Kahn worklist (the shape `toposort` above
# already has), and keep `graph_rewrite` out of that module, because nothing in
# the rewrite engine may call back into the fold. That is a P3 design decision
# and it is written down in spec/ops.md.

# ops.py:1-500. WHERE EACH NAME ACTUALLY LIVES NOW.
#
# lies: the def was already written, in ANOTHER file, and the queue was the only
# thing that did not know it. `rg "TODO(p3)"` is the work queue, so a stale entry
# is not a note -- it is work that gets done twice, or a name the next agent
# re-derives from scratch. So every ops.py line in [1, 500] is now in exactly one
# of three buckets, and the two that are PORTED have no queue line at all:
#
#   PORTED HERE         a real def in this file, with its rows.
#   PORTED ELSEWHERE    a real def in the named file, with its rows. The queue
#                       entry is DELETED, not deferred: the wall is not this
#                       file's to clear, and writing it here would be a second
#                       implementation of a thing that already has one.
#   STILL A WALL        a Bend rule no arrangement in THIS file beats. Kept in
#                       the queue WITH the rule, so the next agent does not spend
#                       an hour rediscovering it.

# PORTED HERE, 2026-10-03. Four defs, above `pm_r_sink`:
#     bsl.go, UOp.backward_slice (ops.py:280), UOp.backward_slice_with_self (:286)
#     op_in_bsl.go, UOp.op_in_backward_slice_with_self (:289)
# They are BELOW the toposort they are written in terms of, and Python has them
# above it, because Bend has no forward references. Gated by `bsl_<tag>` and
# `bsws_<tag>` over four fixtures plus six `bsop_<tag>_*` Booleans: 14 rows, three
# lanes, byte-identical. The `call` and `nest` fixtures are the ones that carry
# `enter_calls=False`; `bsl_chain` would agree with a plain `toposort`.

# PORTED ELSEWHERE -- `uop/render.bend`, which IMPORTS this file, so nothing here
# can call it and nothing here should re-implement it.
#     ops.py:18  AxisType.__repr__   -> axis_repr        (render.bend:561)
#     ops.py:41  ParamArg.__repr__   -> paramarg_repr    (render.bend:512)
#     ops.py:269 UOp.__repr__        -> pretty_print, render.bend's `pyrender`
# The first two are reached by `arg_repr`'s `ARange` and `AParam` arms, which is
# where the mutation table's `arg_repr ARng` / `arg_repr AParam` labels point; the
# third IS `UOp.__repr__`'s whole body (`return pretty_print(self)`) and it carries
# 25 CPython-compared rows of its own. `repr` is a rendering concern, so
# render.bend is where it belongs.

# PORTED ELSEWHERE -- `uop/fold.bend`, the Kahn worklist the block above this one
# describes, and the reason the entries below are walls and not chores.
#     ops.py:329 UOp._shape        -> fold.shape.of / dt_shape  (fold.bend:888)
#     ops.py:456 UOp.shape         -> UOp.shape                (fold.bend:4038)
#     ops.py:470 UOp.ended_ranges  -> UOp.ended_ranges         (fold.bend:4013)
# `UOp.dtype` came with them, and `dtype` is what every remaining entry below reads.

# STILL A WALL. Each names the rule, and each is ALSO in the NOT PORTED block at
# the foot of this file, where the reason is longer.
# TODO(p3) ops.py:76  def srender
#   `x.render()` is render.bend's and `str(x)` is its `const_repr`. Both live in
#   the file that imports this one, so the two-arm dispatch cannot be written here.
# TODO(p3) ops.py:1169  def sym_infer
#   `exec` in `_sym_fxn` builds Python source from the graph and runs it in a
#   namespace of `max/cdiv/cmod/floordiv/floormod/bitcast/dtypes`. Bend has no
#   `eval`, so this needs a C effect that compiles a lambda or a tree-walking
#   interpreter. P3/P6.
# WALL(p3) ops.py:212  def __init__ -- BLOCKED. STORE A FUNCTION IN A DATA FIELD -- `recursive_property.__init__` keeps `self.fxn`. The
#   port's own note at the `t_*` block says a function value in a FIELD forces `Type`, not
#   `Data`, MEASURED. (A function as a PARAMETER is fine -- `bend guide:69` says functions may
#   be stored, passed and returned, and `Maybe.map` already takes one.)
# TODO(p3) ops.py:216  def __get__
#   `recursive_property` stores a FUNCTION in a record field (`self.fxn = fxn`),
#   and a function value in a field forces `Type`, not `Data` -- measured, and the
#   reason the rule tables in this file are linear. The `__get__` half is the memo
#   the header's point 5 drops, and its GATE is `self.nm not in node.__dict__`:
#   a memo-less port cannot answer that, because the predicate is vacuously true
#   for every node and the "gate" would visit the whole slice unconditionally.
# WALL(p3) ops.py:240  def __del__ -- BLOCKED. NO GARBAGE COLLECTOR TO CALL IT. `bend guide:646` -- "values are affine, a `match` frees
#   the node it opens" -- so there is no `__del__` hook and nothing for it to remove itself
#   from. The `ucache` it deletes from is Python's, and this port's interner is
#   `intern.find`'s direct comparison, not a table a node has to leave.
#   Refcount-driven eviction from `ucache`. The arena is monotone, so nothing is
#   ever evicted and there is nothing to port.
# WALL(p3) ops.py:244  def __reduce__ -- BLOCKED. THE PICKLE PROTOCOL. `return UOp, (op, src, arg, tag, metadata)` is a `__reduce__`: an
#   instruction to Python's `pickle`. Nothing in the port serialises a live UOp, so there is
#   no protocol to implement.
#   Pickling. A `U32` index and an `Arena` are not picklable objects, and this
#   file has no process boundary to pickle across.
# TODO(p3) ops.py:261  def key
#   `hashlib.sha256` over `str((op, dtype, arg))` and the srcs' keys concatenated.
#   Two walls: the digest is a C effect (`tinygrad/runtime/`'s), and the string
#   half reads `dtype`, which is `fold.bend`'s -- so neither half is writable here.
# wall(p3) ops.py:284  def _bool_slice -- blocked. needs `fold`'s walk and a dtype predicate, so it lives downstream of this file like
#   `_eval`, `param_noshape` and `wk_is_virtual` do -- `dt_is_bool` is in `mixin/dtype.bend`
#   and this file cannot import it (`ops.bend:87`). Its only consumer is a marker of its own:
#   `uop/symbolic.bend:3054 symbol=fx_ne0` records that `fold_where_closure` needs `bool_slice` AND
#   `substitute`, so porting this alone closes nothing downstream. THE INTERNING DOES MAKE
#   IT CHEAPER THAN CPYTHON'S: two structurally equal nodes share an arena index, so the
#   `frozenset[UOp]` is a deduped index list and needs no hash.
# TODO(p3) ops.py:287  def bool_slice
#   A `recursive_property` over the srcs, gated on `self.dtype is dtypes.bool`.
#   `dtype` is `fold.bend`'s, so both halves belong to the worklist beside it; and
#   `bool_slice`'s `| {self}` is a self-reference the fold has to add OUTSIDE its
#   own memo, which is what Python's comment above the property says.
# wall(p3) ops.py:316  def tuplize -- blocked. the mechanism is replaced, not missing. `tuplize` builds `(op.value, repr(arg), dtype, *(src
#   tuplize))` to KEY CPython's `ucache`; this port's interner is `intern.find`, a direct
#   comparison over `Arena.nodes`, so there is no hash table for a key to serve. Its two
#   consumers are outside ops.py anyway -- `codegen/late/linearizer.py:36` (a sort) and
#   `uop/symbolic.py:225` (a rewrite rule) -- and neither is ported.
#   `_UOpTuple((op.value, repr(arg), self.dtype) plus every src's tuplize)`:
#   `dtype` again, plus a `recursive_property` over the srcs, plus the sort it
#   feeds. `repr(arg)` is render.bend's `arg_repr`, so this is three files deep.
# TODO(p3) ops.py:444  def shard_shape
# TODO(p3) ops.py:450  def max_shard_shape
#   `shard_shape` reads `self.device` (fold), `self.axis` (fold) and `self.shape`
#   (fold), and `max_shard_shape` is `to_max_shape(shard_shape)`, a fold over a
#   `Sint` list. Every input is the worklist's, so these are fold.bend's rows;
#   `schedule/multi.bend` is the caller and it inlines what it can today.
# PORTED -- `ops.py:481 _ranges` and `ops.py:495 ranges` are `fold.bend`'s
# `Ranged` / `UOp.ranges` (fold.bend:5118 symbol=UOp.ranges), 12 `rg_*` rows byte-identical to
# CPython. The reason these two carried for a month -- "Dict set algebra over the
# with a membership test, and `ended_ranges` is ported too (uop/fold.bend:2868 symbol=ended_of).
# TODO(p3) ops.py:479  def ranges
#   Dict set algebra over the fold's memo: union every src's ranges, then `pop` the
#   ones the ended ranges close. The wall is named where it is HIT --
#   `schedule/rangeify.bend:205 symbol=rf_in_ranges`, whose `rf_in_ranges` is the standing stub.

# TODO(p3) ops.py:495  def simplify
#   # * uop evaluation *

# DONE(p3) ops.py:92 def ssimplify -- `ssimplify_of` and `UOp.ssimplify_val` /
#   `UOp.ssimplify_is_val`, with `cval_arg` (written for `pop_const`) as the value reader. Gated at
#   `gates/ops-core-gate.py` in SIX rows over THREE fixtures, and the third fixture is the one
#   that makes the other two mean something: a CAST of a PARAM satisfies neither of CPython's
#   conditions, so CPython hands the NODE back -- a THIRD answer, neither a value nor an absence.
#
#   IT DOES NOT NEED `simplify`, which is the finding rather than a convenience. `simplify` is a
#   documented wall in this file (`ops.py:511`, "* uop evaluation *") and 3,679 lines of
#   partial symbolic work sit behind it, so anything that truly required a rewriter would be
#   stuck on the largest subsystem here. But a CONST is already reduced, so `simplify` is the
#   IDENTITY on it, and the CAST arm's test is a SHAPE test on the node rather than a rewrite.
#   What is left out is `ret.dtype.const(...)` -- the dtype round trip -- and `wk_dt` already
#   answers a node's dtype, so the value half is the whole of the discriminating claim.
#   Planted: a reader that answers `none` for everything fails `ss_const_val` and
#   `ss_cast_const_val` and nothing else.

# done(p3) ops.py:521 def _eval -- and it was misfiled here, which is the finding. `_eval` needs
#   the node's dtype AND its two bounds, and this file imports only `Base`, `helpers` and
#   `LAWS/spec`, while `UOp.vmin`/`vmax` are in `fold.bend` and the node-level dtype reader is in
#   `weak.bend` -- and BOTH of those import `ops.bend`. So the def sits DOWNSTREAM of the file
#   that wanted it: an import edge, not a language limit, and the same relocation
#   `wk_commit_dtype` already got. It is now `wk_eval_int` / `wk_eval_float` / `wk_eval_bool` in
#   `weak.bend`, gated at `gates/wk-eval-gate.py`: 16 rows, 3 lanes, 15 identical to CPython and
#   ONE documented divergence.
# TODO(p3) ops.py:511  def __bool__   -- DONE, same gate (`bool_true`, `bool_false`,
#   `bool_on_i32`).
# TODO(p3) ops.py:512  def __int__    -- DONE, same gate (`int_weakint`, `int_i32`,
#   `int_on_range`).
# TODO(p3) ops.py:513  def __float__  -- DONE, same gate (`float_weakfloat`,
#   `float_on_i32`).

# TODO(p3) ops.py:514  def substitute

# TODO(p3) ops.py:521  def __index__
#   # NOTE: this is not called by Tensor slice (Tensor handles UOps directly), but satisfies SupportsIndex for type checking

# TODO(p3) ops.py:526  def trace_num

# WALL(p3) ops.py:563  def __getitem__ -- BLOCKED. PYTHON'S SLICE PROTOCOL. The body calls `super(UOp, self).__getitem__(idx)`,
#   `argfix`, `_normalize_indices`, `slice` objects and `self.shape[i]`. A slice is a Python
#   runtime object with `start`/`stop`, and Bend has no slicing syntax to normalise.

# done(p3) ops.py:597 def _uop -- and the honest answer is that there is nothing to
#   WRITE. CPython's is `def _uop(self) -> UOp: return self`, which is the IDENTITY, and
#   it is the identity because `Tensor` SUBCLASSES `UOp`. This port's
#   `type Tensor is Data: Tensor{ar, uop, is_param, grad}` (`tensor.bend:190`) is a RECORD
#   WRAPPING a U32 index, so it is not a UOp -- and the port's node reference is already a
#   `Found`, which IS the UOp reference. There is no unwrap on this side to perform.
#   the tensor side of the same name is ported and gated elsewhere: `tensor.bend:196-200`
#   names `Tensor.u` as `_uop -- tensor.py:118` and every graph-building method there
#   reads that field in place of `self.uop`. So the NAME is done, from the side that has
#   something to do.

# done(p3) ops.py:599 def _wrap_uop -- same reason, and it is the stronger one.
#   CPython's is `@classmethod def _wrap_uop(cls, u: UOp) -> UOp: return u`, so it returns
#   its argument UNCHANGED. It exists at all because `Tensor` subclasses `UOp`: without the
#   subclassing, a `UOp` passed where a `Tensor` is expected would not be one, and this
#   would have to convert rather than hand back. The port has no such gap -- `Tensor` is a
#   record wrapping a `U32` and a `Found` is a `U32` plus an arena -- so there is no
#   coercion to bridge and no def to write. a marker that asks for a function which is
#   CORRECTLY ABSENT IS A WALL, NOT A GAP, and the reason it was a marker at all is that
#   nobody had written down WHICH kind it was.

# TODO(p3) ops.py:581  def const_like

# TODO(p3) ops.py:587  def ufix

# TODO(p3) ops.py:594  def store

# TODO(p3) ops.py:603  def ins

# TODO(p3) ops.py:604  def contract

#   # cast, except for CONST, in which case rebuild a new CONST at the dtype

# TODO(p3) ops.py:621  def cconst

# TODO(p3) ops.py:630  def wmma

# PORTED -- `ops.py:652 _rop` is `tensor.bend`'s `tn_rop`, which is
# `tensor.bend:1843` symbol=tn_rop.

# TODO(p3) ops.py:644  def invalid

# DONE(p3) ops.py:664 def valid -- `UOp.where` and `UOp.valid_of` above, gated at
#   `gates/ops-core-gate.py` in FOUR rows. `where` is `mixin/elementwise.py:426`'s
#   `self.alu(Ops.WHERE, x, y)`, i.e. `UOp(Ops.WHERE, src=(cond, x, y))`, and it is the constructor
#   `UOp.valid_of` is one line on top of.
#
#   defs, could not read their own src fields back, and reverted them as "an unverifiable
#   constructor". The truth is the arena rule this project already records: each `UOp.const` grows
#   the arena and answers a node in the GROWN one, so reading an index against the original `ar0`
#   finds a different node -- I read `ANone{}` out of three srcs that were there all along. MEASURED
#   with a probe: threaded wrongly, all three read `ANone{}`; threaded right,
#   `cbool:True|cbool:True|cinvalid`.
#
#   so the rule for this whole file is narrower than i wrote it last time. Three defs moved
#   downstream because `ops.bend` cannot name `fold.bend`'s bounds or import `dtype.bend`. THIS one
#   needed neither: it was a bug in the CALLER's arena discipline, and the def was always writable
#   here. "Cannot read it back" is not evidence that it cannot be written.
#   PLANTED: swapping the two trailing srcs fails `valid_src1` and `valid_src2` together.

# TODO(p3) ops.py:646  def get_idx

# TODO(p3) ops.py:652  def reduce

# TODO(p3) ops.py:661  def overflows
#   `def overflows(self, dtype: DType) -> bool: return self.vmin < dtype.min or
#   dtype.max < self.vmax`. Two comparisons and no minting, which is why it looks
#   like the cheapest def on this list. It is not, and the reason is a QUESTION
#   rather than a wall:
#
#   CPython's `vmin`/`vmax` are concrete ints. This port's are
#   `Maybe<&2, Bnd>` (`uop/fold.bend`:4498), and `Bnd` is
#   `Bnd{inf} | BndInt{neg, mag} | BndFlt{v}` -- an INTEGER OR A FLOAT OR AN
#   INFINITY, symbolically. So `vmin < dtype.min` is not one comparison, it is a
#   comparison over that union, and the honest answer to "is `vmin` below the dtype
#   minimum" when `vmin` is SYMBOLIC is neither True nor False: it may be undecidable
#   until the range table resolves it.
#
#   `Bool` has no third value, and defaulting unknown to False makes the port assert
#   a range is SAFE when it has not been shown to be. That is the one failure mode a
#   dtype fold must not have, and it is why this is not ported as a one-liner with
#   `Bool.or(lt(...), lt(...))`.
#
#   The shape it needs: a THREE-valued predicate over `Bnd` (below / provably not
#   below / unresolved), and a decision about what the two-valued public answer does
#   with the third -- almost certainly "not overflowing is a MAYBE, and every caller
#   that needs certainty has to say so".
#
#   `bnd.lt` DOES exist -- `fold.bend:3306`, with `bnd.eq` at `:3317` -- and an
#   narrower and stranger than "add an ordering": `bnd.lt` is a TWO-valued TOTAL
#   answer over `BndInt`, and what is missing is the third.
#
#   AND `dt_max` IS NOT A SUBSTITUTE FOR IT. `dtype.bend`'s `dt_max` answers
#   `int64.max` for `uint64` -- the `i64_max_u` fallthrough, `dtype.bend:379-389` --
#   which is documented as safe only because that bound is read as `hi <= max`.
#   `uint64.max` is `2**64-1` and `int64.max` is `2**63-1`, so borrowing the table
#   here would make every `uint64` bound wrong by a factor of two. This needs `Bnd`.
#   P3, with `vmin`/`vmax`.

# WALL(p3) ops.py:670  def unshard -- BLOCKED. `def _shard` IS ABSENT -- checked as a definition, comments excluded. `unshard` builds a
#   UNSHARD and `_shard` is the constructor it shares with `shard` below.
#   # * multi-device helpers *

# WALL(p3) ops.py:690  def bounds -- BLOCKED. `def max_numel` IS ABSENT, and `bounds` also reads `self.axis` and a device COUNT
#   (`len(self.device)`, on the `Dev` tag). It is a `itertools.accumulate` + `pairwise`
#   over per-axis shapes.

# TODO(p3) ops.py:715  def axis

# TODO(p3) ops.py:728  def _shard

# WALL(p3) ops.py:734  def shard -- BLOCKED. `def _shard` IS ABSENT -- the same one `unshard` needs. `copy_to_device` IS present, so
#   this is one missing constructor rather than a missing subsystem.

#   `def param_like` IS ABSENT, and `store_call`'s body is two of them:
# TODO(p3) ops.py:746  def store_call  -- BLOCKED, and is `self.param_like(0).store(...).call(self, src)`.

#   a device is a `U32` tag here, not a string: `type Dev is Data: D1{tag: U32}`. So a device name has no prefix to test, and the two below are exactly a `startswith`:
# TODO(p3) ops.py:755  def on_disk  -- BLOCKED, and is `device.startswith("DISK")`.
# TODO(p3) ops.py:756  def on_creation_device  -- BLOCKED, and is `device.startswith(...)`.
#   # little helpers

# PORTED -- `ops.py:818 _mop` is `tensor.bend`'s `tn_mop`, which is
# `tensor.bend:1704` symbol=tn_mop.

# TODO(p3) ops.py:835  def new_buffer

# TODO(p3) ops.py:843  def from_buffer

#   `def canonicalize_device` and `def is_disk_device` ARE BOTH ABSENT, and both start with one:
# TODO(p3) ops.py:849  def empty_like  -- BLOCKED, and opens `canonicalize_device(...)`.
# TODO(p3) ops.py:867  def clone  -- BLOCKED, and opens `canonicalize_device(...)` then tests `is_disk_device`.

# TODO(p3) ops.py:855  def _frompy

# DONE(p3) ops.py:902 def is_virtual -- `wk_is_virtual` in `weak.bend`, `no_dev` beside it.
#   `device is None or dtype in weaks`, and the device half needs a node that CARRIES a `Dev`:
#   `fold.bend`'s `mw_pa` hard-codes `ParamArg`'s device field to `None{}`.
#   the claim that no DEF in the port sets it was FALSE. measured 2026-10-30:
#   `renderer/__init__.bend:450` builds a `ParamArg` with `device = Some{S.D1{0}}`, and
#   `fold.bend`'s `device_of.param` reads `O.ParamArg.device(pa)`, so a node that CARRIES a
#   device was reachable all along. The rows are `gates/wk-isvirt-gate.py` -- 5 rows, 3 lanes,
#   0 divergences, and three mutations that each move the row they name.

# TODO(p3) ops.py:931  def contiguous_view

#   `def contiguous_view` IS ABSENT, and both of these ask it first:
# TODO(p3) ops.py:941  def contiguous_view_offset  -- BLOCKED, and is `None if (view := self.contiguous_view()) is None`.
# TODO(p3) ops.py:957  def _buffer_view  -- BLOCKED, and raises on `self.contiguous_view() is None`.

# wall(p3) -- storage, device and alloc. no live `Buffer` -- there is no `type Buffer is Data` anywhere in the port and zero `Buffer{` constructors. tinygrad's Buffer is an allocated object with a `realized` field and a `memory`
# TODO(p3) ops.py:950  def _base_buffer_is_realized  -- BLOCKED, and walks the AFTER chain then reads `u.base.realized`.
# TODO(p3) ops.py:988  def realized  -- BLOCKED, and ANSWERS a Buffer.
# TODO(p3) ops.py:999  def is_realized  -- BLOCKED, and is `self.base.realized is not None`.
# TODO(p3) ops.py:757  def needs_storage  -- BLOCKED, and is `not is_virtual and (storage_base.op is ALLOC or base.realized)`.

# TODO(p3) ops.py:974  def buffer

# PORTED -- `ops.py:1015 UOp.variable` is `UOp.variable` (this file), four `vrn_*`
# rows byte-identical to CPython on all three lanes via
# `sh .agents/slop/ops-vrn-gate.sh`, with six mutations in
# `.agents/slop/ops-vrn-mutate.py` each moving EXACTLY the rows it names.
#
# IT WAS BLOCKED ON A NAME, NOT ON A SUBSTRATE. CPython writes `slot=-1` and this
# file's `ParamArg.slot` is a `U32`, so the def needed a name for "no POSITIONAL
# slot" and the file that OWNS the field had none -- while `function.bend`,
# `codegen/kernel.bend`, `codegen/late/linearizer.bend` and `uop/symbolic.bend` had
# each invented one. `ParamArg.no_slot()` (this file) is the single name, landed the
# commit before, and this def is the first thing it unblocked.
#
# `is_variable` (ops.py:1020) is STILL BLOCKED and this does not change that: its
# fifth conjunct is `self._shape == ()` and `Node{op, src, arg, tag}` has no shape
# field. The `vrn_*` rows print `nsrc` as the closest honest proxy and the `is_
# variable` marker says why that is not the same question.

#   ops.py:1020  def is_variable
#     `self.op is Ops.PARAM and isinstance(self.arg, ParamArg) and self.arg.vmin_vmax
#     is not None and self.arg.addrspace is AddrSpace.ALU and self._shape == ()`.
#     FOUR of the five conjuncts are functions of `Node{op, src, arg, tag}`. The
#     fifth is not, and that is the whole of the wall: this arena's Node has NO
#     SHAPE FIELD. `Arena{nodes, shp}`'s `shp` is the arena's own table, not a
#     per-node shape, so `self._shape` has nowhere to be read from.
#
#     A four-of-five port is not a partial port, it is a WRONG ANSWER: it returns
#     True for a PARAM with a src, which is not a scalar, which upstream says is
#     not a Variable. Every caller of `is_bound_var`, `unbound` and `bind` would
#     then take the Variable path on a non-Variable. So the four readable
#     conjuncts are NOT landed, and `expr` -- the one def of the lattice whose
#     answer is a function of the ARG ALONE -- is landed instead.
#
#     Unblocking it is a substrate change, not a port: `Node` needs a shape, or an
#     accessor that derives one. P3, with the shape work `uop/fold.bend` already
#     owns for the fold.

#   ops.py:1025  def is_bound_var
#     `self.is_variable and self.arg.val is not None`. The second conjunct is two
#     fields of a `ParamArg` and both are readable; the first is `is_variable`
#     above. Gated on it, not on anything of its own.

#   ops.py:1032  def bind
#     `assert self.is_variable and not self.is_bound_var; uval = UOp.const(val) ...
#     return self.replace(arg=replace(self.arg, val=uval.val))`. THREE dependencies
#     and none of them is this def: `is_variable` (the shape wall), `self.vmin <=
#     uval.vmin and uval.vmax <= self.vmax` (`uop/fold.bend`'s `vmin`/`vmax` over
#     the range table) and `uval.divides(self.arg.multiple_of)` (ops.py:1069, not
#     ported). `self.replace` is `UOp.new` and needs no port -- the arena IS the
#     intern table -- which is the one part of this def that is ready.

#   ops.py:1039  def unbound
#     `assert self.is_variable; return self.replace(arg=replace(self.arg, val=None),
#     tag=None)`. The REWRITE is two field writes, both readable, and `replace` is
#     `UOp.new`, so the def itself is nearly free. It is gated on the assert only,
#     and the assert is `is_variable`: without that conjunct the def would clear
#     `val` on nodes upstream refuses to touch, and a gate that cannot see the
#     difference is not a gate.

#   ops.py:1043  def unbind
#     `assert self.is_bound_var; return self.unbound(), self.arg.val`. Both halves
#     are the two defs above, including the assert.

#   ops.py:1046  def unbind_all
#     `{x: x.unbound() for x in self.backward_slice_with_self if x.is_bound_var}` and
#     then `self.substitute(bound, walk=True)`. The slice and the dict build are
#     `bsl.go`'s shape and readable; `substitute` (ops.py:514 symbol=UOp.substitute) is not ported, and
#     the dict is keyed by a `UOp` in Python, which in this arena means keyed by an
#     INDEX whose validity is a session property. P3, with `substitute`.

#   ops.py:1049  def variables
#     Walks the backward slice collecting `x.unbound() if x.is_variable else x` and
#     an `_device_num` Variable per DEVICE RANGE, then `sorted(ret, key=lambda v:
#     (v.arg.name or "", v.arg.slot))`. The sort key is `(Maybe<String>, U32)` and
#     the `or ""` is Python's `None`-sorts-first, which this port has to state
#     rather than inherit. Gated on `is_variable` and on the shape wall.

# * uop symbolic stuff *
# AND `const_factor` IS DONE -- MEASURED 2026-11-08: `def UOp.const_factor(fuel, ar, i) ->
# H.I64` IS AT `:7752` AND `def UOp.divides(fuel, ar, v, i) -> Dv` IS AT `:7972`. THE `TODO`
# that used to stand here was stale against a `DONE` NOTE eleven lines below it, and a `TODO`
# beside a `DONE` for the same DEF is a ledger that disagrees with itself.

# DONE(p3) ops.py:1048 def const_factor -- `UOp.const_factor` above, FLATTENED: the def and
#   its fold are not mutually recursive once the arms are read (a STACK/ADD contributes the
#   gcd identity and every other node is a leaf), so `cf.walk` is a FUEL-bounded worklist.
#   The "Bend cannot express that" probe below was measuring the OBVIOUS spelling.

# DONE(p3) ops.py:1082 def pop_const -- `UOp.pop_const_val` / `UOp.pop_const_hits` above, with
#   `cval_arg`. Gated at `gates/ops-core-gate.py` in EIGHT rows over FOUR fixtures, and the
#   fixtures are built so the def's TWO conditions fail SEPARATELY: a second src that is not a
#   CONST, and a `MUL` popped as an `ADD`. Planted -- dropping the `op` comparison from
#   `pop_const_hits` fails exactly `pop_mul_const_hits` and nothing else, which is what says the
#   op is COMPARED rather than assumed. The value is a `Const` and not an `H.I64`: an I64-only
#   reader recorded a divergence on the float fixture that was really just a narrow type, and
#   `pop_const` returns whatever the CONST carries.

# TODO(p3) ops.py:1073  def gcd

# TODO(p3) ops.py:1079  def divide_exact

# TODO(p3) ops.py:1090  def vmin

# TODO(p3) ops.py:1092  def vmax

# TODO(p3) ops.py:1106  def _min_max

# TODO(p3) ops.py:1168  def _sym_fxn

# TODO(p3) ops.py:1169  def sym_infer

# TODO(p3) ops.py:1173  def render

# TODO(p3) ops.py:1181  def render_uir  -- upstream's `pyrender` was DELETED before this pin.

#   `def view_as` IS ABSENT, and the alloc family ends in one:
# TODO(p3) ops.py:1188  def alloc  -- BLOCKED, and ends `ret.view_as(shape)`.
# TODO(p3) ops.py:1194  def alloc_like  -- BLOCKED, and delegates to `alloc`.
# TODO(p3) ops.py:1206  def placeholder  -- BLOCKED, and ends `view_as`.
# TODO(p3) ops.py:1208  def placeholder_like  -- BLOCKED, and delegates to `placeholder`.

# PORTED -- `ops.py:1224 UOp.set` is `UOp.set` (this file). The def, its fixture,
# its four rows and its gate landed inside a CONCURRENT agent's commit rather than
# one of mine, so the history does not attribute them; the write-up is here and at
# the gate, which is where a reader lands anyway. Four `set_*` rows
# byte-identical to CPython on all three lanes via `sh .agents/slop/ops-set-gate.sh`,
# with TWO negative controls that are the two bugs below.
#
#   # set is store+end+after
#   def set(self:UOp, val:UOp|ConstType, end:UOp|tuple[UOp, ...]|list[UOp]=()) -> UOp:
#     return self.src[0].after(self.store(val).end(*argfix(end)))
#
# Upstream's own comment says the whole of it, so the def has no logic: it is a
# COMPOSITION, and the only things a row can test are that the three pieces are
# wired in this ORDER and that `argfix`'s empty arm is honoured. The number of
# `end` operands is the only input that varies, so it is the only thing the family
# varies. `argfix` is already ported as `argfix1`/`argfix2`/`argfix_seq`
# (helpers.bend:547-554), so `end` is a `Maybe<&2, List<&2, U32>>` and not a node.
#
# TWO BUGS, AND BOTH COMPILED.
#
#   THE STALE ARENA. The first draft was
#       +e = UOp.end(ar, Found.i(s), ...)          -- `ar`, the CALLER's
#   and `UOp.store` MINTS, so `s` lives in a GROWN arena and `Found.i(s)` read out
#   of `ar` indexes the wrong arena. It typechecked and answered
#   `Ops.AFTER(Ops.BUFFER Ops.AFTER)` where CPython answers
#   `Ops.AFTER(Ops.BUFFER Ops.STORE)`. That is the failure mode bend2-constraints
#   names, and `UOp.copy_to_device` above is the fix in one line: thread the
#   previous step's `Found.ar`. The first negative control reintroduces it.
#
#   THE SUBJECT IS A STORE. The first fixture was a BUFFER and CPython raised
#   `IndexError: tuple index out of range`, because `set` is called ON a store and
#   `src[0]` is the store's target. A fixture that does not reach the code is a
#   fixture that cannot fail, and this one looked like a red gate.
#
# and a printer that was three drafts worse than it needed to be: a recursive
# `deep` needing a closer that knows its own depth, a `Bool.pick` for the first
# separator, and a fold that opened a paren in the accumulator. The file already
# had the shape under another name (`Rng.srcops.go`'s `+first` flag). Grep for
# the IDIOM before writing the INSTANCE.
#   # set is store+end+after

# done(p3) ops.py:1229 def param -- the shape-less arm only, and it is in `weak.bend`. the third
#   def to arrive downstream for a THIRD distinct reason: `ops.bend` cannot NAME `fold.bend`'s bounds
#   (`_eval`), and it cannot IMPORT `dtype.bend` at all -- `THE PORT's `uop/ops.bend` HEADER` says so and it is TRUE, since
#   dtype.bend's fp16/bf16/i64 C effects make the checker exit 1 for ANY importer. So the weaks guard
#   `md_weak` is unreachable from this file, and `wk_param_noshape` lives in `uop/weak.bend` beside the
#   other two. the rule is not "those three were misfiled" but "a DEF needing a dtype predicate or a
#   BOUND LIVES DOWNSTREAM OF `ops.bend`."
#   Gated at `gates/wk-eval-gate.py`: 22 rows, 3 lanes, 21 identical and the ONE documented
#   `simplify` divergence. Planted -- removing the guard fails BOTH `_built` rows.
#
#   the other two arms are not ported and the reason is the missing piece, named: a shaped param is
#   `prod(to_max_shape(shape))` plus a `view_as` RESHAPE, and `view_as` IS ABSENT FROM THE PORT
#   (so is `unique_num`). Checked, not assumed.

# TODO(p3) ops.py:1228  def param_like

# TODO(p3) ops.py:1236  def view_as

# custom_function -- ops.py:1258 upstream. `UOp(Ops.CUSTOM_FUNCTION, src=src,
# arg=CustomFunction(name, dtype))`. The pin's spelling was ops.py:1256 and took no
# dtype, because there was no `CustomFunction` to hold one.
# `dtype=dtypes.void` is upstream's DEFAULT and Bend has no default argument, so `dt`
# is required here and `CustomFunction.of(name)` builds the void-dtype value.
# `UOp.call` below is NOT PORTED, so nothing in this file consumes the dtype yet:
# `dtype_from_uop` is not ported either (the folds do not fit, see the header).
def UOp.custom_function(+ar: Arena, name: String, +srcs: List<&2, U32>, dt: S.Dt) -> Found:
  UOp.new(ar, OpsCUSTOM_FUNCTION{}, srcs, ACustom{CustomFunction{name, dt}}, TNone{})

# TODO(p3) ops.py:1247  def call

# WALL(p3) ops.py:1274  def call_with_outputs -- BLOCKED. ENDS IN THE `alloc` CHAIN: the body binds output ALLOCs through `mint` below, and `mint`
#   calls `UOp.alloc`, which ends in `view_as` -- absent as a definition.

# WALL(p3) ops.py:1280  def mint -- BLOCKED. CALLS `UOp.alloc` ("`buf = UOp.alloc(...)`"), and `alloc` ends in `ret.view_as(shape)`
#   -- `view_as` is absent as a definition.

# WALL(p3) ops.py:1298  def call_with_output -- BLOCKED. IS `UOp.call_with_outputs((self,), *srcs)`, one line over the marker above it, so it is
#   blocked on the same `alloc` -> `view_as` chain.
#   # one-line convenience for the single-output case: self is the value

# wall(p3) ops.py:1299  def custom_kernel -- blocked. builds its placeholders with `UOp.placeholder_like`, and `placeholder_like` delegates to
#   `placeholder`, which ends in `view_as` -- absent as a definition. NOTE the `fxn:Callable`
#   is NOT the blocker: `bend guide:69` says functions are values that can be passed and
#   called, affine, and this calls `fxn` once.

# TODO(p3) ops.py:1312  def to_elf

# TODO(p3) ops.py:1319  def uopfunc

# done(p3) ops.py:1229 def param -- the shape-less arm only, and it is in `weak.bend`. the third
#   def to arrive downstream for a THIRD distinct reason: `ops.bend` cannot NAME `fold.bend`'s bounds
#   (`_eval`), and it cannot IMPORT `dtype.bend` at all -- `THE PORT's `uop/ops.bend` HEADER` says so and it is TRUE, since
#   dtype.bend's fp16/bf16/i64 C effects make the checker exit 1 for ANY importer. So the weaks guard
#   `md_weak` is unreachable from this file, and `wk_param_noshape` lives in `uop/weak.bend` beside the
#   other two. the rule is not "those three were misfiled" but "a DEF needing a dtype predicate or a
#   BOUND LIVES DOWNSTREAM OF `ops.bend`."
#   Gated at `gates/wk-eval-gate.py`: 22 rows, 3 lanes, 21 identical and the ONE documented
#   `simplify` divergence. Planted -- removing the guard fails BOTH `_built` rows.
#
#   the other two arms are not ported and the reason is the missing piece, named: a shaped param is
#   `prod(to_max_shape(shape))` plus a `view_as` RESHAPE, and `view_as` IS ABSENT FROM THE PORT
#   (so is `unique_num`). Checked, not assumed.

# WALL(p3) ops.py:1323  def outlined -- BLOCKED. PYTHON INTROSPECTION OF A CALLABLE: `inspect.signature(fn).bind(*args, kwargs)`,
#   `bound.items()`, and the dict union `bound | {...}`. That is the runtime's own view of a
#   function's parameters, which no compiled language exposes.

# DONE(p3) ops.py:1352 def launch_dims -- `ProgramInfo.launch_dims` is
# `ProgramInfo.launch_dims` (this file, the `from_sink` block below). It is the
# IDENTITY on the port's launch sizes, because `sym_infer` (ops.py:95) is the
# identity on an int and the port's `global_size`/`local_size` are
# `List<&2, H.I64>`. The block says which half of upstream's method the port
# does NOT have and why.
#
#   ops.py:1366  def vals
# PORTED -- `ProgramInfo.vals` is `ProgramInfo.vals` (this file). Five `vv_*` rows.
#
# the rows are read by no instrument, and that is measured, not assumed:
# `rg -n 'vv_two|vv_one|vv_zero|vv_none|vv_miss_second'` over the tree answers
# THIS FILE and nothing else. THE `sh .agents/slop/ops-vv-gate.sh` THIS BLOCK
# used to cite does not exist -- measured 2026-10-22, `find . -name
# 'ops-vv-gate*'` (not under `references/`) answers NOTHING -- so the
# "byte-identical to CPython on all three lanes" claim had NO INSTRUMENT BEHIND
# IT and the two negative controls it named had nothing to fire against. THE
# CLAIM IS WITHDRAWN, NOT REPLACED.
#
# what does read the lane: `gates/valsdiv-gate.py` reads the port-extension
# DECLARATION above and checks that the extension is LIVE -- DEFINED, CALLED, AND
# REACHABLE FROM `main` -- which it reports as
# `finding: declared-extension -- tinybendygrad/uop/ops.bend:8675 via main ->
# vd_rows -> vd_row -> ProgramInfo.vals`. It reads the DECLARATION and the
# CALL GRAPH; it does not read the five rows' VALUES.
#
# SO THE LANE STAYS, because the rows are still the best statement of what
# `vals` does, and DELETING THEM to make a number look better is what
# `AGENTS.md` forbids. and `vals` still has no real-program caller after
# `from_sink` landed: `from_sink` builds `ProgramInfo.params` as upstream's pin
# does -- ALL the params -- while `vals` is the port of the method upstream HAD
# at `186fbba2a`, which read `self.vars`, the VARIABLES. The two are different
# lists, and `vals` now reads the ALU SUBSET of `params` so that it keeps its
# own declared contract.
#
# I GOT THIS BLOCKER WRONG TWICE before landing it, and both errors were the same
# shape: a claim about a LANGUAGE, written without grepping. First that `Map` was
# undefined in the tree; it is a Bend stdlib type from `import Base` with put, set,
# has and get all present, and `uop/render.bend:1007`/`:1017` were ALREADY calling
# two of them. Then that `Map.put` needed a new Bend RULE; `Map.set` IS that rule
# and it exists. The cost of those two was four compile rounds chasing arity, and
# the arity is the interesting part:
#
#   Map.set(a, -V: Kind(a), m, key, x)   quantifier SECOND, after the linearity
#   Map.has(-a: Quant, -V: Kind(a), m, key)
#   Map.get(-V: Data, d, m, key)         NO linearity parameter, and a DEFAULT
# Three readers, three shapes, and a stray `&2` lands in the NEXT parameter's slot
# so the error names a TYPE rather than an arity. All three are spelled correctly
# in `render.bend` already.
#
# `VarVals` WAS `is Type` AND IS NOW `is Data`, and it is the only record in this
# file that was ever a Type. It compiled for as long as it existed because NOTHING
# CALLED IT -- `vals` was a marker, so the one def that takes a `VarVals` never
# typechecked. A declaration nobody calls is not checked, and this file was green
# the whole time.
#
# already here, and `bcast.go` (fold.bend:590) is a Maybe-carried List accumulator
# using it. My first draft was TEN defs and was MUTUALLY RECURSIVE; the lambda in
# `Maybe.bind` IS the continuation, so the whole fold is one def with one `match`
# and two binds. Three near-identical presence-test dunders (`sg.pa.put`,
# `rnd_is_set`, and the one that draft added) were the cost of not finding it.

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

# THE CONST-IDENTITY GATE, and the arg-type lane below it. Fourteen `t_*` in this file
# have a CPython-confirmed denominator under `gates/ops-core-gate.py`, so they are no longer
# written-and-believed: each row is diffed against tinygrad's own answer on three lanes (CPython,
# bend interpreted, bend compiled). The oracle builds the same graphs out of real tinygrad UOps
# and the two lanes share no code, so a row agrees only if two implementations of the property
# say so.
#
# `zeros_differ` and `nan_interns` are the pair that pins the comparison: IEEE equality disagrees
# with the packed-arg key in BOTH directions, so a port keying on `F32.is_eq` instead of `F32.bits`
# gets exactly one of the two rows backwards and no single-cell test sees it.
#
# THREE OF THE ARG-TYPE ROWS ARE `0`, which is why they are here. The key is
# `(op, src, arg, tag, type(arg))` -- it carries `type(arg)` and NOT `type(tag)` -- so `True` and
# `1` SPLIT as a top-level arg and MERGE in the tag and in a nested `ParamArg.val`. A comparator
# that treated the three positions alike would pass any ONE of these rows.
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

# CONST identity is bitwise, and ieee equality is wrong in both directions.
# `UOp.key` in CPython is a hash over the packed arg, so identity is the bit
# pattern -- but `eq_bool`, `eq_op` and `eq_i64` are all bitwise too, and
# `F32.is_eq` is IEEE, which disagrees with a bit pattern in exactly two cells,
# one each way. Measured, live:
#     Tensor(0.0)._uop is Tensor(-0.0)._uop   -> False   0x00000000 vs 0x80000000
#     Tensor(nan)._uop is Tensor(nan)._uop   -> True    0x7fc00000 both
# So `F32.is_eq` answers True for a pair CPython keeps APART and False for a pair
# CPython JOINS: it would collapse two distinct CONSTs in the first cell and
# re-mint one identical node in the second. `F32.bits` is the comparison the key
# performs. NOTE `decomp.bend:126` keeps `F32.is_eq` -- there it tests a value
# against a literal (is this 1.0?), which is IEEE equality asked to do its own job.
def t_float_zeros_differ() -> Bool:
  +f = UOp.const(Arena.empty(), CFloat{0.0})
  +g = UOp.const(Found.ar(f), CFloat{F32.neg(0.0)})
  Bool.not(U32.is_eq(Found.i(f), Found.i(g)))

def t_float_nan_interns() -> Bool:
  +nan: F32 = F32.div(0.0, 0.0)
  +f = UOp.const(Arena.empty(), CFloat{nan})
  +g = UOp.const(Found.ar(f), CFloat{nan})
  U32.is_eq(Found.i(f), Found.i(g))

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

# FOUR, not five: `Arena.empty()` parks a BOTTOM sentinel at index 0 that is not
# a UOp, so a four-node graph has `Arena.next(ar) == 5` and a four-element
# toposort. CPython agrees, on the tree `g_chain` rebuilds --
#   c0 = UOp.const(0); r0 = UOp.range(c0, (0,), AxisType.LOOP)
#   list(UOp.range(r0 + c0, (0,), AxisType.GLOBAL).toposort()) has four entries,
#   'Ops.CONST', 'Ops.RANGE', 'Ops.ADD', 'Ops.RANGE'.
# ops.py:621 `UOp.after` builds `src=(self,)+src`, so SELF IS src[0]. This row exists
# because `UOp.after`, `UOp.end` and `UOp.mstack` all had the inverse -- SELF LAST -- and
# nothing in this file could see it. An after built either way has the same op, the same
# nsrc, the same shape and the same dtype; only the SRC OP SEQUENCE differs, and no row
# printed that. Found by the schedule/prepare unit, which built its own AFTER in the right
# order to route around the bug instead of editing this file.
#
# So this row asserts the SEQUENCE, not the count. The self is a RANGE (UOp.range_end
# builds OpsRANGE, ops.py:660) and the supplied node is a CONST, so self-first means
# src[0]=RANGE and src[1]=CONST. The bug answers exactly the reverse.
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

# --- eq_dt, and the hash-consing that DEPENDS on it -----------------------------
# `eq_dt` is the whole of the dtype half of the ucache key, so a row that does not
# call it cannot see an `eq_cls` bug. This one does, on all SEVEN of `Cls`'s
# constructors, and the SEVEN is the point: with six arms in `eq_cls.sel` the
# weakfloat self-equality was False and every other row stayed green.
#
# dtype.py:59-62 is the oracle and it is an IDENTITY: `DType` is
# `@dataclass(frozen=True, eq=False)` under a metaclass that caches by
# `(priority, bitsize, name, fmt)`, so `dtypes.X == dtypes.X` is True for every
# dtype and `dtypes.X == dtypes.Y` is False for X != Y. `S.Dt` spells the same
# comparison out field by field, so a row here is that identity, restricted to
# one representative per class.
def t_eq_dt() -> Bool:
  Bool.and(Bool.and(eq_dt(S.void(), S.void()), eq_dt(S.weakint(), S.weakint())),
    Bool.and(Bool.and(eq_dt(S.boolean(), S.boolean()), eq_dt(S.uint32(), S.uint32())),
    Bool.and(Bool.and(eq_dt(S.int32(), S.int32()), eq_dt(S.half(), S.half())),
    Bool.and(eq_dt(S.single(), S.single()), eq_dt(S.weakfloat(), S.weakfloat())))))

# and the CONFLATION is pinned separately, because a row that only asks "is it
# equal to itself" would also pass a `Cls` compared by something weaker than
# identity. These five are the pairs a six-arm ladder gets wrong or gets right by
# accident, and each names a different arm boundary: weakfloat against the
# lattice step from, void against either, and the two 16-bit floats whose only
# difference is `pri`.
def t_eq_dt_disjoint() -> Bool:
  Bool.and(Bool.and(Bool.not(eq_dt(S.weakfloat(), S.half())), Bool.not(eq_dt(S.half(), S.weakfloat()))),
    Bool.and(Bool.and(Bool.not(eq_dt(S.weakfloat(), S.weakint())), Bool.not(eq_dt(S.weakint(), S.weakfloat()))),
    Bool.and(Bool.not(eq_dt(S.half(), S.bfloat16())), Bool.not(eq_dt(S.void(), S.weakfloat())))))

# THE DAMAGE, not just the predicate. `intern.find` compares with `eq_node`, which
# reaches `eq_dt` through `eq_arg.ADt`, so a wrong `eq_dt` is a wrong ucache and
# two equal-in-value nodes become two arena nodes. The CAST is the smallest
# fixture that carries a dtype in its `arg`: bottom, the CONST, the first CAST
# and the second -- three nodes when the two CASTs hash-cons to one, four when
# they do not. `half` is the control: it went through the same `case _:` and was
# always right, so a row that passed for `half` and failed for `weakfloat` is
# what a missing seventh arm looks like from outside.
def g_cast_twice(+dt: S.Dt) -> U32:
  +c = UOp.const(Arena.empty(), CInt{H.i64_of_i32(0)})
  +ar = Found.ar(c)
  +a = UOp.new(ar, OpsCAST{}, [Found.i(c)], ADt{dt}, TNone{})
  +b = UOp.new(Found.ar(a), OpsCAST{}, [Found.i(c)], ADt{dt}, TNone{})
  Arena.next(Found.ar(b))

def t_weakfloat_interns() -> Bool:
  Bool.and(U32.is_eq(g_cast_twice(S.weakfloat()), 3), U32.is_eq(g_cast_twice(S.half()), 3))

# --- eq_addr, and the hash-consing that DEPENDS on it -------------------------
# The whole 4x4, in declaration order, against an oracle that is an IDENTITY:
# dtype.py:51-54's `AddrSpace` is an `IntEnum` with four members and no
# `__eq__` override, so `(a == b) == (a is b)` and the matrix `tinygrad` answers
# is `[[T,F,F,F],[F,T,F,F],[F,F,T,F],[F,F,F,T]]`. Each row below is one `x` of
# `eq_addr`, read left to right against AGlobal, ALocal, AReg, Aalu.
def t_eq_addr() -> Bool:
  Bool.and(Bool.and(Bool.and(Bool.and(eq_addr(S.AGlobal{}, S.AGlobal{}), Bool.not(eq_addr(S.AGlobal{}, S.ALocal{}))), Bool.and(Bool.not(eq_addr(S.AGlobal{}, S.AReg{})), Bool.not(eq_addr(S.AGlobal{}, S.Aalu{})))), Bool.and(Bool.and(Bool.not(eq_addr(S.ALocal{}, S.AGlobal{})), eq_addr(S.ALocal{}, S.ALocal{})), Bool.and(Bool.not(eq_addr(S.ALocal{}, S.AReg{})), Bool.not(eq_addr(S.ALocal{}, S.Aalu{}))))),
    Bool.and(Bool.and(Bool.and(Bool.not(eq_addr(S.AReg{}, S.AGlobal{})), Bool.not(eq_addr(S.AReg{}, S.ALocal{}))), Bool.and(eq_addr(S.AReg{}, S.AReg{}), Bool.not(eq_addr(S.AReg{}, S.Aalu{})))), Bool.and(Bool.and(Bool.not(eq_addr(S.Aalu{}, S.AGlobal{})), Bool.not(eq_addr(S.Aalu{}, S.ALocal{}))), Bool.and(Bool.not(eq_addr(S.Aalu{}, S.AReg{})), eq_addr(S.Aalu{}, S.Aalu{})))))

# THE DAMAGE, not just the predicate -- the shape of `weakfloat_interns` above,
# because `eq_addr` is reached from `intern.find` the same way `eq_dt` is.
# `ParamArg.addrspace` is the seventh field and is a BARE `S.Addr` (ops.py:23-36
# defaults it to `AddrSpace.GLOBAL`), so a PARAM is the smallest node whose arg
# carries one. Two PARAMs differing ONLY in addrspace are one node when `eq_addr`
# conflates Aalu with AReg and two when it does not.
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

# --- Ops.name, which is `FastEnum.__str__` ----------------------------------
# `Ops.name` has NO reader inside this file, so nothing above could see it: the
# first bug this port found in it was found in `render.bend`, from a
# `REDUCE.arg`. Both halves of the answer are pinned, because CPython has TWO
# string forms of an enum member and this file used to have one.
def t_ops_name() -> Bool:
  Bool.and(Bool.and(String.eq(Ops.name(OpsSPECIAL{}), "Ops.SPECIAL"), String.eq(Ops.name(OpsADD{}), "Ops.ADD")),
    Bool.and(Bool.and(String.eq(Ops.name(OpsREDUCE{}), "Ops.REDUCE"), String.eq(Ops.name(OpsPYLITERAL{}), "Ops.PYLITERAL")),
      Bool.and(String.eq(Ops.name.of(OpsADD{}), "ADD"), String.eq(Ops.name.of(OpsCUSTOM_FUNCTION{}), "CUSTOM_FUNCTION"))))

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
# `strict_length` being False{} instead.
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

# THE REGRESSION ROW for the `pm_ler` bug. `ler` is `{u.op for u in uop.src}`, so
# its LENGTH must equal the node's src count -- and FOUR srcs is the case that
# matters, because spec.py:201's reject set is four ops and the broken version
# read only src[0] and src[1], so that rule could never fire. Every other row
# stayed green throughout, which is the reason this row exists.
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

# THE SIGNATURE PRINTERS -- four facts plus the answer as ONE string. Every graph row
# in this file's new lane goes through `Rng.sig`, and the four facts are FIXED here
# rather than per row because a row that prints three of them and hand-builds the
# fourth is a row whose formatting can drift from its siblings'.
#
#   node count      `toposort`'s length
#   root op         `Ops.name` of the node
#   root nsrc       the src COUNT
#   SRC OP SEQUENCE the ops of the srcs, in order
#
# The src op SEQUENCE is the fifth fact and it is here for the same reason
# `after_puts_self_first` exists -- `mixin/movement` measured a two-src swap that left
# the count, the root op, the root nsrc and the toposort ALL identical. It is the ONLY
# thing in a UOp row that sees a swap.
def Rng.srcops.go(+ar: Arena, xs: List<&2, U32>, +acc: String, +first: Bool) -> String:
  match xs:
    case Nil{}: acc
    case +h <> t:
      Rng.srcops.go(ar, t, Bool.pick(String, first, acc ++ Ops.name(Arena.op(ar, h)),
        acc ++ " " ++ Ops.name(Arena.op(ar, h))), False{})

# `-` for a node with no srcs, matching CPython's own `-` for an empty join. `+first`
# is what carries "have I printed anything yet": a trailing separator would need a
# string drop-last, and a leading separator on the first element would need a second
# pass; a fold that knows which element is first needs neither. `+h` and `+ar` are the
# duplication Bend asks for when a value is used twice.
#
# `+first` starts FALSE and not TRUE, because `seeded` has ALREADY put the head's name
# in `acc` and passes the TAIL. Measured: seeding TRUE printed `Ops.RANGEOps.CONST` --
# the second element took the no-space arm.
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

# Bend has no assertion form, so `main` PRINTS each answer and the gate is that both
# lanes print the same lines. A `False{}` anywhere is the failure.
def row(nm: String, b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(b)]))

# A STRING row: the four facts plus the answer, as ONE line. `row` is for a Bool and
# this is for everything else -- a table cell, a signature, a name sequence -- because a
# Bool row cannot express "which of eight", and that is the whole of the AxisType gate.
def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

# THE ARG, read back through the `ACustom` ARM rather than compared with `eq_arg` --
# deliberately. A row whose expected value is a def of the thing under test is not a
# test, so this does not ask "is this arg equal to a hand-built ACustom"; it asks
# "which Arg constructor did `UOp.custom_function` actually build, and what are its
# two fields in order". The pin's `UOp.custom_function` built an `AStr`, so the
# `case _:` cell answers `!ACustom` and the row moves.
def dt_name(d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, nm}: nm

# blob -- the intern key's bytes half. ops.py:201, spec.py:96, ops.py:365.
#
# `UOpMetaClass.__call__` keys on `(op, src, arg, tag, type(arg))`, so for a BINARY
# the key HOLDS the `bytes` object and dict equality compares bytes CONTENT-WISE.
# This port spells that arg `ABlob`, and it spelled it `ABlob{n: U32}` -- the LENGTH --
# so `eq_arg.ABlob` compared a summary. Two DIFFERENT blobs of the SAME length were
# then the same key: one node where CPython has two, and `Arena.next` one short.
#
# THE FIXTURE IS THE WHOLE POINT. `blob_len_diff_content` uses `b"aaaa"` against
# `b"bbbb"` -- EQUAL LENGTH, UNEQUAL CONTENT. A fixture of DIFFERENT lengths is
# satisfied by a length key, which is why this sat in a green gate: every existing
# fixture pair differed in length, and two of the three rows below are DIAGONAL or
# OFF-DIAGONAL cells of a 3x3 over the same three blobs.
#
# The expected values are CPython's, produced by CALLING it
# (`.agents/slop/blob-intern-oracle.py`, whose output is the `#shared` block of
# `.agents/slop/ops-oracle.py`). Nothing here is transcribed. The three cells, read
# live off the upstream tree:
#     UOp(Ops.BINARY, src=(), arg=b"aaaa") is UOp(..., arg=b"aaaa")  -> True,  1 node
#     UOp(Ops.BINARY, src=(), arg=b"aaaa") is UOp(..., arg=b"bbbb")  -> False, 2 nodes
#     UOp(Ops.BINARY, src=(), arg=b"aaaa") is UOp(..., arg=b"aa")    -> False, 2 nodes
# and `len(ucache)` is 1 / 2 / 2 respectively.
#
# `ucount` is the PORT's node count with the bottom sentinel subtracted, so the
# `srow` answers the same integer CPython's `len(ucache)` does. The sentinel is
# accounted for in the ROW rather than in a `#bend_only` filter, because a row that
# needs a filter to line up with the oracle is a row that can drift from it silently.

# the control that pins the other half, and it is the row that says the fix above is a
# fix and not a widening: at the TOP level `type(arg)` IS in the key, so a bool CONST
# and an int CONST of the same value are TWO nodes and must stay two. If this row ever
# flips, `eq_const` has been changed and `eq_tag` was the wrong place to fix it.
def t_const_bool_vs_int_splits() -> Bool:
  +u = UOp.new(Arena.empty(), OpsCONST{}, Nil{}, APy{CBool{True{}}}, TNone{})
  +v = UOp.new(Found.ar(u), OpsCONST{}, Nil{}, APy{CInt{H.i64_of_i32(1)}}, TNone{})
  Bool.not(U32.is_eq(Found.i(u), Found.i(v)))

# THE NESTED LANE, and it is the SECOND instance of the same over-split. A CONST's arg IS
# the key's `arg` element, so `type(arg)` splits `True` from `1` and `eq_const` must.
# `ParamArg.val` is a `PyConst` NESTED inside `arg` (ops.py:42, `PyConst = float|int|bool`
# at dtype.py:38), `type(arg)` is `ParamArg` on both sides, and the same two values are ONE
# key. The fixture is a pair of PARAMs differing in EXACTLY ONE FIELD, `val`: a comparator
# that dropped any other field could not satisfy it, and one that dropped `val` cannot pass.
def pa_with(v: Maybe<&2, Const>) -> Arg:
  AParam{ParamArg{0, S.int32(), None{}, None{}, None{}, S.AGlobal{}, None{}, False{}, None{},
                  None{}, False{}, v}}

def pynest_same(v1: Maybe<&2, Const>, v2: Maybe<&2, Const>) -> Bool:
  +u = UOp.new(Arena.empty(), OpsPARAM{}, Nil{}, pa_with(v1), TNone{})
  +v = UOp.new(Found.ar(u), OpsPARAM{}, Nil{}, pa_with(v2), TNone{})
  U32.is_eq(Found.i(u), Found.i(v))

# the cell the fix is about, and it reads TRUE -- "the two interned to one node".
def t_pynest_bool_vs_int_interns() -> Bool: pynest_same(Some{CBool{True{}}}, Some{CInt{H.i64_of_i32(1)}})

# THE TWO DISTINCTNESS CONTROLS, and without them a comparator answering True for every
# pair would satisfy the row above alone.
def t_pynest_int_distinct_interns() -> Bool: pynest_same(Some{CInt{H.i64_of_i32(1)}}, Some{CInt{H.i64_of_i32(2)}})

def t_pynest_none_vs_zero_interns() -> Bool: pynest_same(None{}, Some{CInt{H.i64_of_i32(0)}})

# and the one that keeps the comparator from being "cross bool against every number":
# `ConstFloat.__hash__` is `hash(self.bits)` (dtype.py:21) and
# `hash(0x3ff0000000000000) != hash(1.0)`, so a `ConstFloat` and an equal int sit in
# DIFFERENT dict buckets upstream and are never compared at all. This row reads FALSE and
# must stay false; the signed zeros are the same fact from the other side, differing in bits.
def t_pynest_cfloat_vs_int_interns() -> Bool:
  pynest_same(Some{CFloat{1.0}}, Some{CInt{H.i64_of_i32(1)}})

def t_pynest_signed_zero_interns() -> Bool:
  pynest_same(Some{CFloat{F32.neg(0.0)}}, Some{CFloat{0.0}})

# THE AXIS CPYTHON LANE. This block is new: the file had 22 rows and NO cpython
# lane at all, and everything below is about `AxisType` -- the thing `78d482262`
# changed and the thing nothing could see change.
#
# Every row here has its expectation GENERATED BY CALLING CPython; see
# `.agents/slop/ops-oracle.py` and `.agents/slop/ops-gate.sh`. The rows come in two
# kinds and they are not interchangeable:
#
#   * CPYTHON rows -- printed by both lanes and diffed. `axv_*` is the headline:
#     one row per AxisType MEMBER, because a fixture-driven gate would only ask
#     about the axis types a fixture happens to hold, and PLACEHOLDER is in no
#     fixture tinygrad builds. That is precisely how the pin's wrong PLACEHOLDER
#     value (9) survived.
#   * BEND-ONLY rows -- printed by this file, filtered BY NAME by `ops-gate.sh`,
#     each with a `#bend_only_*` reason in the oracle. They are the four
#     cross-file walls (the `ARange` field order, the two retained dead members,
#     `spec_shared`, and `hasattr`), and none of them is quietly dropped: the
#     gate script lists every one.

def ax_names_str.go(xs: List<&2, AxisType>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case a <> t: List.append(&2, String, [AxisType.name(a)], ax_names_str.go(t))

# --- THE AXIS CPYTHON LANE. Row order matches `.agents/slop/ops-oracle.py` EXACTLY and
# --- the gate is a byte diff, so a row added on one side and not the other is a diff and
# --- not a silent gap.

# THE GATE for the ops.py:501-1928 block above. The CPython lane is
# `.agents/slop/ops-501-oracle.py` and the diff is `.agents/slop/ops-501-gate.sh`.
# Every row name starts `s5_` so the gate filters by PREFIX: a row that MOVED
# cannot be silently dropped, and filtering by position is what drops one.
#
# why the port's answer is an INDEX and CPython's is a name. `UOp.base` and its
# five siblings answer a `U32` arena index, and an index is meaningless outside
# the arena that produced it, so a numeric diff would compare two unrelated
# numberings. What is comparable is what the index POINTS AT, and that is the op
# name through `Ops.name` -- the same decision `codegen/__init__.bend`'s
# `gr-diff.sh` made and for the same reason.
#
# the fixtures are the smallest graphs that separate two answers, and each is named
# for the thing it separates rather than for its shape:
#
#   c    a CONST: nothing peels, so every walk answers CONST and the FUEL is the
#        only thing that can move a row. This is the non-movement fixture, and it
#        is here because a gate with only movement fixtures leaves every `match`'s
#        catch-all arm dead code.
#   b    a BUFFER: the terminal of every walk that terminates on storage.
#   p/a  a PARAM and an ALLOC, the other two of `{BUFFER, ALLOC, PARAM}`. Three
#        fixtures for a three-op set is what says the SET is tested and not one op.
#   r1   RESHAPE[BUFFER], one movement deep. `s5_base_r1` is BUFFER, so a walk
#        that stopped at the RESHAPE would answer RESHAPE.
#   r2   RESHAPE[RESHAPE[BUFFER]], two deep: the row that says the walk REPEATS
#        rather than testing once. A one-step walk answers RESHAPE here.
#   us   UNSHARD[BUFFER] -- the op `base` does NOT strip and `unsharded_base` does.
#        `s5_base_us` is UNSHARD and `s5_unsharded_base_us` is BUFFER. One op, two
#        answers, and that pair IS the difference between the two defs.
#   bc   BITCAST[BUFFER], which NEITHER strips and `storage_base` DOES. One node,
#        three rows, three different answers.
#   af   AFTER[BUFFER], which `storage_base` and `without_after` and
#        `has_buffer_identity(after_ok=True)` strip and `has_buffer_identity()`
#        does not -- so `s5_hbi_af` and `s5_hbi_after_af` are 0 and 1 and are the
#        only two rows in the family that the `after_ok` parameter moves.
#
# THE ARENA IS A LITERAL NODE LIST, and that is deliberate. `UOp.make` appends, so
# the k-th node built is index k; writing the list out means the index of a
# fixture is its POSITION and a reviewer can check the rows by counting, and
# `s5_idx_*` prints each one so a miscount is a visible row rather than a silent
# re-labelling. The nodes bypass `UOp.make` and therefore its interning, which is
# what a fixture wants -- every node here is already distinct, and a hash-consed
# fixture would silently MERGE two of them and move a row for the wrong reason.

def s5.pa(slot: U32) -> ParamArg: ParamArg.of(slot, S.int32())

# The nine fixture indices, as a `Data` record so the row table reads them by name
# and a fixture cannot be swapped for another without the row changing.
type S5 is Data: S5{c: U32, b: U32, p: U32, a: U32, r1: U32, r2: U32, us: U32, bc: U32, af: U32}

# The nine `S5` field readers. Bend has no `x.field` sugar (bend2-constraints
# rule 26) and no auto-generated projection, so each is one `match`, and R-3 wants
# them above their first caller -- which is `s5.base`.
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

# THE PRINTERS, three of them and no more.
#
# `s5.name` prints the op name of whatever a walk landed on -- the ONE comparable
# thing about an arena index, and it is what every row in the base family uses.
#
# `s5.seps` prints the op-name SEQUENCE of a list, and it is `split_uop`'s row
# because the ORDER is the fact: a fold that appended at the back answers the same
# LENGTH and the REVERSED order, and only the sequence tells them apart.
#
# `s5.shardstr` prints `axis:RANGE` per shard, because `sharding` answers a list of
# PAIRS and a list of pairs has no other printable form.
# The accumulator already holds the HEAD's name, so every further element is
# appended behind a space and no `first` flag is needed. The first version carried
# one and got it backwards -- the separator belongs to what came BEFORE, and the
# row read `Ops.CONSTOps.CONST`.
def s5.seps.go(+ar: Arena, xs: List<&2, U32>, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case +h <> t: s5.seps.go(ar, t, String.concat([acc, " ", s5.name(ar, h)]))

def s5.seps(+ar: Arena, xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}: ""
    case +h <> t: s5.seps.go(ar, t, s5.name(ar, h))

# The movers. Each answers a `Found`, so each row prints the node's op name and
# its SRC OP SEQUENCE -- two facts, because a mint that got the op right and the
# src order wrong would answer one string either way, which is the same reason
# `Rng.sig` exists for the rest of this file's graph rows.
# The arena is the `Found`'s own -- a mint GROWS the arena, and reading the
# caller's would be the stale-arena bug bend2-constraints rule "AN ARENA IS THE
# ONE A BUILD RETURNED" names. So `s5.minted` takes the `Found` and reads
# `Found.ar` for both halves, and it is split in two because `f` is then read
# three times.
# `sig` in the oracle is `nm(u) if not u.src else nm(u) + "/" + ...`, so a
# srcless node prints BARE. Always emitting the `/` put `Ops.CONST/` where
# CPython says `Ops.CONST`, and no mutation of any row using it could see
# the difference -- every row happened to have a src. This is the fix.
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
# ops.py's own predicate and it is here rather than in the inventory because
# `get_idx` and `get_valid` read it. The `Const` datatype's `CInvalid` arm is the
# reason `self.val is Invalid` is a `match` and not an integer comparison.
def UOp.is_invalid.of(op: Op, arg: Arg) -> Bool:
  match op arg:
    case OpsCONST{} APy{CInvalid{}}: True{}
    case _ _: False{}

def UOp.is_invalid(+ar: Arena, +self: U32) -> Bool:
  UOp.is_invalid.of(Arena.op(ar, self), Arena.arg(ar, self))

# `invalid` -- ops.py:663. `UOp.const(Invalid)`: a CONST whose `APy` payload is the
# `CInvalid` arm, the ONE place `Const` holds something that is not a number.
def UOp.invalid(ar: Arena) -> Found:
  UOp.const(ar, CInvalid{})

# `reduce` -- ops.py:671. `arg = kwargs.pop('arg', None); if isinstance(arg, Ops):
# arg = (arg, 0); return UOp(Ops.REDUCE, src=(self,)+src, arg=arg)`. The one
# non-trivial thing it does is that NORMALISATION, and `AReduce` is this file's
# split of the resulting pair, so the `Maybe` IS the normalisation's other arm:
# `Some` becomes `(rop, 0)` and `None` stays `None`. Both values are rows -- a
# fixture with no `arg` is the one that cannot tell a dropped normalisation from a
# correct one.
def UOp.reduce.arg(rop: Maybe<&2, Op>) -> Arg:
  match rop:
    case Some{r}: AReduce{r, 0}
    case None{}: ANone{}

def UOp.reduce(ar: Arena, self: U32, srcs: List<&2, U32>, rop: Maybe<&2, Op>) -> Found:
  UOp.new(ar, OpsREDUCE{}, List.append(&2, U32, [self], srcs), UOp.reduce.arg(rop), TNone{})

# `cconst` -- ops.py:640. `UOp(Ops.CAST, src=(UOp.const(b),), arg=dtype)`. A FORCED
# cast, which is the entire point: ".cast(bool) folds, so UOp.const cannot state
# the width". TWO nodes, so the CAST goes into `Found.ar`'s arena -- `UOp.const`'s
# -- and NOT the caller's: `Arena.node` answers the bottom for a stale arena
# (bend2-constraints rule at line 3854), so a CAST read out of the caller's is an
# empty answer that typechecks.
def UOp.cconst(+ar: Arena, v: Const, dt: S.Dt) -> Found:
  +c = UOp.const(ar, v)
  UOp.new(Found.ar(c), OpsCAST{}, [Found.i(c)], ADt{dt}, TNone{})

# `ssimplify` -- ops.py:92. TWO ARMS AND A CAST:
#
#   if (ret := self.simplify()).op is CAST and ret.src[0].op is CONST: return ret.dtype.const(ret.src[0].val)
#   return ret.val if ret.op is CONST else ret
#
# neither arm needs `simplify` for the nodes that matter here, and that is the finding rather than
# a convenience. `simplify` is a documented wall in this file (`ops.py:511`, "* uop evaluation
# *"), so anything behind it is behind the largest subsystem here -- but a CONST is already
# reduced, so `simplify` is the IDENTITY on it, and the first arm's test is a SHAPE test on the
# node rather than a rewrite. What is missing is only the dtype round trip, and `wk_dt` already
# answers a node's dtype, so the value half is the whole of the discriminating claim.
#
# `None{}` MEANS "NOT A VALUE", and that is CPython's third arm: `ret.val if ret.op is CONST
# else ret` hands back the NODE for anything that is not a const. This def answers only the value
# question, and `ssimplify_is_val` beside it answers the other half, so the pair covers the
# three-arm answer between them rather than one def pretending the third arm does not exist.
def cval_arg(a: Arg) -> Maybe<&1, Const>:
  match a:
    case APy{CBool{b}}: Some{CBool{b}}
    case APy{CInt{i}}: Some{CInt{i}}
    case APy{CFloat{f}}: Some{CFloat{f}}
    case _: None{}

# THE SCRUTINEE IN ITS OWN DEF, because a match may not scrutinise a COMPUTED value -- the third
# time this session that rule has cost a shape, and three readers do it the same way.
#
# one DEF, not two, and mutual recursion is why. The obvious shape has the CAST arm ask `ssimplify_of`
# again about the src, and that is a CYCLE between two defs, which this language does not express.
# The way out is that the cycle was never necessary: CPython guards the CAST arm with
# `ret.src[0].op is Ops.CONST`, but `cval_arg` already accepts only `APy{CBool|CInt|CFloat}`, so a
# CAST of anything else reads a PARAM or BUFFER arg and falls out of `cval_arg` as `None` -- the
# same answer, from the arm set instead of from a second test. So the guard is kept as a COMMENT
# rather than as a branch, which is the only place it earns its keep.
def ssimplify_of(op: Op, +ar: Arena, +i: U32) -> Maybe<&1, Const>:
  match op:
    case OpsCONST{}: cval_arg(Arena.arg(ar, i))
    # CPython tests `ret.src[0].op is Ops.CONST` here; see the note above.
    case OpsCAST{}: cval_arg(Arena.arg(ar, Arena.src0(ar, i)))
    case _: None{}

def UOp.ssimplify_val(+ar: Arena, +i: U32) -> Maybe<&1, Const>:
  ssimplify_of(Arena.op(ar, i), ar, i)

# THE THIRD ARM, as its own Bool, because `None{}` cannot distinguish "a node that is not a value"
# from "a value I failed to read" -- and those are opposite bugs.
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

# and the row that says it hit, separately from the value's presence. a reader that always
# returned `None{}` would satisfy every value row, and one that ignored the op would satisfy
# every hit row; the pair is what makes both fail.
def UOp.pop_const_hits(+ar: Arena, +i: U32, op: Op) -> Bool:
  Bool.and(eq_op(Arena.op(ar, i), op),
           eq_op(Arena.op(ar, Arena.src(ar, i, 1)), OpsCONST{}))

# `UOp.const_factor` -- ops.py:1048, "largest known int that divides self".
#
# the TODO above said this was inexpressible because the DEF and its FOLD are mutually
# recursive. that is TRUE of the obvious spelling and FALSE of the arms: a stack or ADD node's
# own contribution to the answer IS the gcd identity (`gcd(children)`), and every other node is a
# LEAF -- MUL reads its srcs' OPS and never descends, CONST is its value, Defines is its
# `multiple_of`, everything else is 1. So the answer is a `gcd` over the LOCAL values of the
# nodes reachable through STACK/ADD EDGES ONLY, and `cf.walk` is that reachability: a worklist on
# FUEL, which is one def and no cycle.
#
# the root is handled separately and it is not an optimisation: `const_factor` returns `self.val`
# for a CONST and that value can be NEGATIVE (ops.py's own comment says "for negatives it's not
# the largest"), while `math.gcd` answers a non-negative. Folding the root in would answer 3 for
# `CONST(-3)`.
# `cval_arg` answers a `Const`, not a number: a MUL's const src can be a bool or a float, and
# `const_factor` is an INT answer, so anything that is not a `CInt` falls back to the 1 upstream
# would have answered for a non-const src.
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

# a `match` may not scrutinise a local binder, so `c0` is a parameter of its own def.
def cf.mul.a(c0: Bool, +ar: Arena, +i: U32, c1: Bool) -> H.I64:
  match c0:
    case True{} : cf.mul.val(ar, i, 0)
    case False{}: cf.mul.b(c1, ar, i)

# `self.src[0].val if src[0].op is CONST else self.src[1].val if src[1].op is CONST else 1`
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

# a stack or ADD contributes the gcd identity and not 1, and the difference is the whole rule:
# their arm is `gcd(children)`, so their own term must be 0 -- `gcd(0, x)` is `x` while
# `gcd(1, x)` is 1. MEASURED on the probe: `add_m6_m4` answered 1 for want of this arm, and 2 is
# `gcd(6, 4)`.
def cf.local.go(op: Op, arg: Arg, +ar: Arena, +i: U32) -> H.I64:
  match op:
    case OpsCONST{}: cf.cv(cval_arg(arg))
    case OpsMUL{}  : cf.mul(ar, i)
    case OpsSTACK{}: H.i64_of_i32(0)
    case OpsADD{}  : H.i64_of_i32(0)
    case _         : cf.defs.op(ar, i, GroupOp.defines(op))

# The local value of ONE node: the gcd identity for a STACK/ADD, else the leaf rule.
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

# THE WORKLIST. Fuel, not the list, is the decreasing argument: a STACK's srcs are PUSHED, so
# the list can grow and only fuel bounds the walk.
def cf.walk(fuel: Nat, +ar: Arena, todo: List<&2, U32>, out: List<&2, U32>) -> List<&2, U32>:
  match fuel todo:
    case 0n Nil{}: out
    case 1n+p Nil{}: out
    case 0n +h <> rest: out
    case 1n+p +h <> rest:
      cf.walk(p, ar, cf.next(cf.keep(Arena.op(ar, h)), rest, ar, h), List.append(&2, U32, out, [h]))

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

# the counter -- `collections.Counter` over node lists, as a list of pairs.
#
# ops.py:1073-1079 -- `UOp.gcd` and `UOp.divide_exact`.
#
# and the port has no integer-keyed map. measured 2026-11-08: `helpers.bend:502` says
# "Bend's `Map` is string-keyed only, so the set is a linear scan", and there is no
# `HashMap` and no `HashSet` in the port. but the port has the honest spelling already,
# TWICE: `dedup_u32` (`helpers.bend:509`) AND `merge_dicts` (`helpers.bend:2467`) ARE BOTH "A
# list of pairs with a linear scan", and `merge_dicts`'s own NOTE says exactly that: "a list
# of pairs is the honest representation". so the claim "the port has no multiset" was a
# claim about a container and not about a capability.
#
# and upstream's counter's keys are nodes, because a `UOp` is hashable by identity
# (`ops.py:219-220`: `__hash__ = tuple.__hash__` AND `__eq__` IS `self is other`). SO THE
# key is the arena's `U32` INDEX -- which is the node's identity in this port.
#
# and the count is a `U32` and not a `Nat`: a count of occurrences is a `U32`, and
# `Nat`'s ARITHMETIC IS A PRELUDE-LEVEL DETAIL (`Nat.add`/`Nat.mul` IN bend2's `safe.ts`)
# that the port uses only for fuel. and a `U32` literal is a plain number
# (`bend.ts:70`: "U32 | NUMBER").
#
# the four spelling rules, all measured 2026-11-08 against bend2's compiler.
#
# 1. a plain parameter may be consumed once and a `+`-binder may be consumed twice. two
#    PROBES: `def use2(x: U32) -> U32: U32.add(x, x)` REFUSES WITH "x (consumed more than
#    once)" and `def use2(+x: U32) -> U32: U32.add(x, x)` compiles and answers 6. and the
#    port's own `split_uop.pop` uses `+ar` and `+sep` twice each, so this is the tree's
#    CONVENTION AND NOT A NEW ONE.
# 2. a DEF's helper must come before its user -- "defs are checked in file order, and an
#    unfilled law has none". so the order below is the dependency order and not the
#    READING ORDER.
# 3. a `match` heads a DEF body and not a term, and a `match` may not scrutinize a
#    COMPUTED VALUE -- "a match cannot scrutinize a computed value: give it its own def".
#    so every comparison is a parameter and every branch is a DEF.
# 4. arguments are read left to right and each is passed unchanged until used, so a list's
#    tail may not be passed to two calls. and the port's own `Merge.go` is the pattern
#    -- `ops.bend:2845`: `Merge.go(t, Found.ar(f), List.append(&2, U32, map, [Found.i(f)]))`
#    -- the tail is the recursion's first argument and the accumulator is the third.
#
# THE ALGORITHM, AND IT IS UPSTREAM's.
#
# `collections.Counter` OVER NODE LISTS: `Counter(term.split_uop(Ops.MUL))` COUNTS THE
# MUL-factors of a term, and `functools.reduce(operator.and_, ...)` intersects the counters,
# and `operator.and_` on two counters is "the keys in both, with the minimum count".
#
# so the counter is a list of `(KEY, COUNT)` pairs, the intersection is the keys of the first
# counter with the minimum count across all of them, and the product is a FOLD over the pairs
# WITH `count` COPIES OF THE KEY.
type Ctr is Data:
  Ctr{k: U32, n: U32}

# the two accessors, and each reads one field -- the port's own `Dv.ok`/`Dv.f`/`Dv.i` are
# three accessors and each destructures the record once, and a DEF that reads both fields
# DESTRUCTURES IT ONCE AND BINDS BOTH.
def Ctr.k(+c: Ctr) -> U32:
  match c:
    case Ctr{k, n}: k

def Ctr.n(+c: Ctr) -> U32:
  match c:
    case Ctr{k, n}: n

# the find: the count of `k` in the list, or 0.
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

# the "found" flag, and it is ORed along the FOLD.
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

# and the bump extends the given counter and does not rebuild it -- measured: the first
# spelling started at `Nil{}` and so the result was a counter of one key no matter how many
# NODES WERE COUNTED, AND `t_ctr_bump` READ `False`.
def ctr_bump.end(+found: Bool, +acc: List<&2, Ctr>, +k: U32) -> List<&2, Ctr>:
  ctr_bump.pick(found, acc, List.append(&2, Ctr, acc, [Ctr{k, 1}]))

# the hit: the key matches, so the old record is dropped and the bumped one is put
# in its place; and it does not, so the record is copied.
def ctr_bump.hit(+c: Ctr, +k: U32, +acc: List<&2, Ctr>) -> List<&2, Ctr>:
  ctr_bump.pick(ctr_bump.same(c, k),
                ctr_bump.hit2(c, k, acc),
                List.append(&2, Ctr, acc, [c]))

# the replacement: the matched record's own key with the count raised by one.
def ctr_bump.go(+l: List<&2, Ctr>, +k: U32, +acc: List<&2, Ctr>, +found: Bool) -> List<&2, Ctr>:
  match l:
    case Nil{}: ctr_bump.end(found, acc, k)
    case c <> t: ctr_bump.go(t, k, ctr_bump.hit(c, k, acc), ctr_bump.found(c, k, found))

# NOTHING IS APPENDED.
def ctr_bump(+l: List<&2, Ctr>, +k: U32, +acc: List<&2, Ctr>) -> List<&2, Ctr>: ctr_bump.go(l, k, acc, False{})

# the counter of a list of nodes: one bump per node.
#
# and the bump is on the counter and not on an accumulator that is also the counter.
#
# and the first spelling passed the same list as both the source and the accumulator, so
# every bump re-copied the whole counter -- measured 2026-11-08 with a probe that prints it:
# the counter of `[1,2,3,2]` had 17 records instead of 3. so the bump folds over the
# counter and copies the non-matched records, and the counter is built by folding the
# nodes and bumping the counter so far -- and the bump takes the counter as its own
# source and a fresh accumulator, which is why it is not given the counter as both.
def ctr_of.go(+l: List<&2, U32>, +acc: List<&2, Ctr>) -> List<&2, Ctr>:
  match l:
    case Nil{}: acc
    case k <> t: ctr_of.go(t, ctr_bump(acc, k, Nil{}))

def ctr_of(+l: List<&2, U32>) -> List<&2, Ctr>: ctr_of.go(l, Nil{})

# the set: one key's count, replaced. the list is short, so a linear scan is the scan.
#
# and it is an accumulator and not an in-place replacement -- measured 2026-11-08: the
# first spellings passed the tail to both the recursion and the helper, and "arguments are
# read left to right: each passed unchanged until used" MAKES THAT AN ERROR ("expected : U32
# / observed : List<&2, Ctr>").
def ctr_find(+l: List<&2, Ctr>, +k: U32) -> U32: ctr_find.go(l, k, 0)

# the minimum: the multiset intersection's count is the smaller of the two.
def ctr_min.pick(less: Bool, +m: U32, +n: U32) -> U32:
  match less:
    case True{}: m
    case False{}: n

def ctr_min(+m: U32, +n: U32) -> U32: ctr_min.pick(U32.is_lt(m, n), m, n)

# the intersection: for each key of the first counter, the minimum of its counts across all
# the counters -- and a key that is missing from any counter is not in the intersection.
#
# and the minimum is a FOLD over the counters for one key, and that FOLD and the FOLD over
# the keys are two folds -- which is a mutual recursion in BEND. measured 2026-11-08, the
# reorderer reported "a cycle" over five spellings: `go`->`step`->`pick`->`go`,
# `go`->`step`->`go`, a fuel-bounded worklist, a flattened one, and a pair walk -- and BEND
# REFUSES MUTUAL RECURSION.
#
# so the two folds do not make a cycle, because the inner one is a call in an argument
# and not a helper of the outer one's recursion -- measured 2026-11-08, the reorderer
# reported "a cycle" over every spelling WHERE the inner FOLD called the outer one.
#
# and upstream's `operator.and_` is the minimum, and a key missing from one counter
# contributes 0, which is why a missing one ends the FOLD.
def ctr_inter.min.hit4(+seen: Bool, +n: U32, +acc: U32) -> U32:
  match seen:
    case True{}: ctr_min(acc, n)
    case False{}: n

# and the FOLD's end: no counter at all is a 0, which is the empty intersection.
def ctr_inter.min.hit3(+missing: Bool, +n: U32, +acc: U32, +seen: Bool) -> U32:
  match missing:
    case True{}: 0
    case False{}: ctr_inter.min.hit4(seen, n, acc)

# the running minimum, and the first counter sets it.
def ctr_inter.min.hit2(+n: U32, +k: U32, +acc: U32, +seen: Bool) -> U32:
  ctr_inter.min.hit3(U32.is_eq(n, 0), n, acc, seen)

# a zero ends the FOLD: the key is not in every counter, so the intersection does not have it.
def ctr_inter.min.hit(+l: List<&2, Ctr>, +k: U32, +acc: U32, +seen: Bool) -> U32:
  ctr_inter.min.hit2(ctr_find(l, k), k, acc, seen)

def ctr_inter.min.end(+seen: Bool, +acc: U32) -> U32:
  match seen:
    case True{}: acc
    case False{}: 0

# and the intersection: the keys of the first counter, each with its minimum.
def ctr_inter.min.go(+ls: List<&2, List<&2, Ctr>>, +k: U32, +acc: U32, +seen: Bool) -> U32:
  match ls:
    case Nil{}: ctr_inter.min.end(seen, acc)
    case l <> t: ctr_inter.min.go(t, k, ctr_inter.min.hit(l, k, acc, seen), True{})

# the count of `k` in one counter, and a missing one is 0, which is what
# `operator.and_` GIVES WHEN A KEY IS ABSENT.
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

# and the key is read once, in a helper, because `Ctr.k(c)` twice is two consumptions --
# MEASURED 2026-11-08: "c (consumed more than once)".
def ctr_inter(+ls: List<&2, List<&2, Ctr>>) -> List<&2, Ctr>:
  match ls:
    case Nil{}: Nil{}
    case first <> t: ctr_inter.go(first, ls, Nil{})

# the counter's own tests. `ops.bend` carries 55 `t_*` tests and the project rule is that
# nothing is ported until it has a CPYTHON-confirmed row -- so the counter gets three, and
# CPYTHON's OWN `collections.Counter` IS THE ORACLE.
#
# and the three claims are not change-detectors, and here is why:
#   t_ctr_bump     the count of each key in a list of nodes. Catches a port that counts
#                  DISTINCT KEYS INSTEAD OF OCCURRENCES, which is the difference between a
#                  multiset and a set -- and the multiset is the whole point, because
#                  UPSTREAM's `Counter` IS A MULTISET.
#   t_ctr_find     the count of a key, and zero for a key that is not there. Catches a
#                  port that returns the list's length for a missing key.
#   t_ctr_inter    the multiset intersection: the keys in every counter, with the
#                  MINIMUM COUNT. Catches a port that takes the MAXIMUM (a union), or
#                  that keeps a key which is missing from one counter.
#
# and two of the three read `False` on the first run and CPYTHON's read `True`, which is
# the point: a compiling counter and a correct one are the same thing until a row says
# OTHERWISE.

# the counter of a list of nodes: the keys are 1, 2, 3 and the counts are 1, 2, 1.
def t_ctr_bump() -> Bool:
  +c = ctr_of([1, 2, 3, 2])
  Bool.and(U32.is_eq(ctr_find(c, 1), 1),
    Bool.and(U32.is_eq(ctr_find(c, 2), 2),
      U32.is_eq(ctr_find(c, 3), 1)))

# a key that is not in the counter has count zero -- and not the list's length.
def t_ctr_find() -> Bool:
  +c = ctr_of([7, 7, 9])
  Bool.and(U32.is_eq(ctr_find(c, 7), 2),
    Bool.and(U32.is_eq(ctr_find(c, 9), 1),
      U32.is_eq(ctr_find(c, 4), 0)))

# the multiset intersection: `[1,1,2]` and `[1,2,2]` give the key 1 with count 1 (the
# minimum) and the key 2 with count 1 -- and not 2, which is a union.
def t_ctr_inter() -> Bool:
  +i = ctr_inter([ctr_of([1, 1, 2]), ctr_of([1, 2, 2])])
  Bool.and(U32.is_eq(ctr_find(i, 1), 1),
    Bool.and(U32.is_eq(ctr_find(i, 2), 1),
      U32.is_eq(ctr_find(i, 3), 0)))
# `UOp.divides` -- ops.py:1069, "self / v as the same shape, or None when it is not exact".
#
# the stack arm is not ported and the reason is measured: it is a FOLD over the srcs, so a def
# that answers one node and a def that answers a list would call each other, and Bend has no
# forward declarations to express that (the same wall `const_factor`'s TODO recorded -- which the
# FLATTENING got past there is unavailable here, because this arm REBUILDS a STACK rather than
# collecting a gcd). A STACK operand therefore DECLINES here where CPython rebuilds it. That is a
# gap, named, and the arms that ARE written are a tree recursion with no list.
#
# the answer is a record and not a `Maybe<Found>`: the ADD and MUL arms need two chained
# self-calls and then a decision on both, and a `match` may not scrutinise a local binder -- so
# `ok` travels in a `Dv` and the decision happens in a def whose PARAMETER it is.
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

# `self.const_like(self.val//v) if self.val%v == 0 else None`
def dv.const2(+z: Bool, +f: Found, +val: H.I64, +v: H.I64) -> Dv:
  match z:
    case True{}:
      +c = UOp.const(Found.ar(f), CInt{H.i64_div(val, v)})
      dv.yes(c, Found.i(c))
    case False{}: dv.no(f)

# `d0 + d1` when BOTH divided; the arena is `db`'s because it is the one that was grown last.
def dv.add(ok: Bool, +da: Dv, +db: Dv) -> Dv:
  match ok:
    case True{}:
      +m = UOp.alu(Found.ar(Dv.f(db)), OpsADD{}, [Dv.i(da), Dv.i(db)])
      dv.yes(m, Found.i(m))
    case False{}: dv.no(Dv.f(db))

# `d0 * self.src[1]` if `src[0]` divided, else `self.src[0] * d1` if `src[1]` did.
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

# `self // v if self.arg.multiple_of % v == 0 else None`
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

# The node case. `op` is a PARAMETER because a `match` may not scrutinise `Arena.op(ar, i)`.
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
          +mb = UOp.divides.op(p, Arena.op(ar, Arena.src(ar, i, 1)), Found.ar(Dv.f(ma)), v, Arena.src(ar, i, 1))
          dv.mul.a(Dv.ok(ma), ma, mb, Arena.src(ar, i, 0), Arena.src(ar, i, 1))
        case _         : dv.defs.op(ar, i, GroupOp.defines(op), Found{ar, 0}, v)

def UOp.divides.one(one: Bool, +fuel: Nat, +ar: Arena, +v: H.I64, +i: U32) -> Dv:
  match one:
    case True{} : Dv{True{}, Found{ar, i}, i}
    case False{}: UOp.divides.op(fuel, Arena.op(ar, i), ar, v, i)

def UOp.divides(fuel: Nat, +ar: Arena, +v: H.I64, +i: U32) -> Dv:
  UOp.divides.one(dv.is1(v), fuel, ar, v, i)

# `UOp.gcd` AND `UOp.divide_exact` -- ops.py:1073-1079.
#
# and both are built on the counter (above), and the counter is a list of pairs
# because the port has no integer-keyed map -- measured 2026-11-08, `helpers.bend:502`:
# "Bend's `Map` is string-keyed only, so the set is a linear scan".
#
# `UOp.gcd(*uops)` -- ops.py:1073:
#
#     terms, factors = zip(*[u.pop_const(Ops.MUL) for u in uops])
#     count = functools.reduce(operator.and_, [Counter(t.split_uop(Ops.MUL)) for t in terms])
#     if not count: factors = tuple(u.const_factor() for u in uops)
#     return math.prod(count.elements(), start=uops[0].const_like(math.gcd(*factors)))
#
# and the port's spelling follows it step for step, with three measured substitutions:
#
#   * `pop_const(Ops.MUL)` returns `(NODE, CONST)` upstream, and the port has only the
#     CONST half (`pop_const_val`/`pop_const_hits`). so the port spells the node half
#     DIRECTLY: A `MUL` WHOSE SECOND SRC IS A CONST IS `(src[0], that const)` AND ANYTHING
#     ELSE IS `(self, identity)`, AND `identity_element(MUL, dt)` IS 1 UPSTREAM
#     (`ops.py:81`: `{Ops.ADD:0, Ops.MUL:1, Ops.MAX:dt.min}[op]`).
#   * `const_like` is not ported (`ops.py:581`, a bare `TODO(p3)` with no wall named),
#     and the port's arena has no shape field -- so the shaped half cannot be spelled.
#     but measured 2026-11-07 on CPYTHON: for the `(x*y)/y` case, `x` is a variable and
#     has no shape, so `x.const_like(1)` takes the unshaped branch and is
#     `UOp.const(1, dtype)`. so the port spells the unshaped `const_like`, which is
#     `UOp.const(b, dt)`, and the shaped half is a separate matter.
#   * `math.gcd(*factors)` is a FOLD over a list of I64s, and the port has `H.gcd` for
#     TWO OF THEM (`helpers.bend:2299`) -- SO THE VARIADIC FORM IS A FOLD.
#
# and `Counter.elements()` -- which repeats each key by its count -- is the port's own
# `H.make_tuple_rep` (`helpers.bend:1309`: `make_tuple_rep(x, cnt) -> List<&2, U32>`), SO
# the product is a concatenation of those and not a hand-unrolled recursion.
#
# and every comparison is a parameter and not a computed value -- measured 2026-11-08:
# "a match cannot scrutinize a computed value: give it its own def" -- AND A `match` OVER A
# call is also a computed value, so the comparison is done in a helper and its result is
# PASSED IN.
#
# THE NODE HALF OF `pop_const(Ops.MUL)`.
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

# and the node half is the first SRC of a `MUL` whose second SRC is a CONST, and
# ANYTHING ELSE IS THE NODE ITSELF.
def UOp.pop_const_node(+ar: Arena, +i: U32, +op: Op) -> U32:
  UOp.pop_const_node.hit3(ar, i, op, i, U32.is_eq(Arena.nsrc(ar, i), 2))

# THE COUNTER OF A NODE's MUL FACTORS: `Counter(term.split_uop(Ops.MUL))`.
def UOp.gcd.counter(+fuel: Nat, +ar: Arena, +i: U32) -> List<&2, Ctr>:
  ctr_of(UOp.split_uop(fuel, ar, i, OpsMUL{}))

# the list of counters, one per term -- and `UOp.gcd.count` is the list that
# `functools.reduce(operator.and_, ...)` FOLDS OVER.
#
# and the FOLD is the port's own `merge_dicts.go` shape (`helpers.bend:2533`):
# `merge_dicts.go(t, merge_dicts.add(kv_conflict(merged_seen(m), kv), kv, m))` -- THE LIST IS
# the only argument, the HEAD is bound by the match, the state is passed once inside the
# adder's argument list, and the adder answers the new state.
#
# and measured 2026-11-08, the two failures this shape avoids:
#   * "expected : a call smaller than UOp.gcd.count.go(ar, h, t, acc) (arguments are read left
#     to right: each passed unchanged until used)" -- A VALUE MAY NOT BE PASSED TO TWO
#     calls, so the state is passed only to the adder.
#   * "A CYCLE" OVER `['UOp.gcd.count.go', 'UOp.gcd.count.go2', 'UOp.gcd.count']` -- A
#     two-step ping-pong is a cycle, so the DEF recurses directly.
def UOp.gcd.count.step(+ar: Arena, +h: U32, +acc: List<&2, List<&2, Ctr>>) -> List<&2, List<&2, Ctr>>:
  List.append(&2, List<&2, Ctr>, acc, [UOp.gcd.counter(Arena.budget(ar), ar, h)])

# and the entry: the list of counters, one per term.
def UOp.gcd.count.go(+ar: Arena, +l: List<&2, U32>, +acc: List<&2, List<&2, Ctr>>) -> List<&2, List<&2, Ctr>>:
  match l:
    case Nil{}: acc
    case nh <> nt : UOp.gcd.count.go(ar, nt, UOp.gcd.count.step(ar, nh, acc))

# and the adder: the HEAD's counter is appended to the state -- and it answers the new
# state, which is what the recursion passes on.
def UOp.gcd.count(+ar: Arena, +uops: List<&2, U32>) -> List<&2, List<&2, Ctr>>:
  UOp.gcd.count.go(ar, uops, Nil{})

# and the terms are the popped nodes -- `terms, factors = zip(*[u.pop_const(Ops.MUL) for
# u in uops])` -- SO A TERM IS A `MUL` WITH ITS CONSTANT STRIPPED.
def UOp.gcd.terms.go(+ar: Arena, +uops: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match uops:
    case Nil{}: acc
    case h <> t: UOp.gcd.terms.go(ar, t, List.append(&2, U32, acc, [UOp.pop_const_node(ar, h, OpsMUL{})]))

def UOp.gcd.terms(+ar: Arena, +uops: List<&2, U32>) -> List<&2, U32>:
  UOp.gcd.terms.go(ar, uops, Nil{})

# one factor: the popped constant, or the identity 1 -- and the identity is what
# `identity_element(MUL, dt)` IS.
def UOp.gcd.isempty(+c: List<&2, Ctr>) -> Bool:
  match c:
    case Nil{}: True{}
    case _ <> _ : False{}

# and the constant factors are `u.const_factor()` for every `u`, which is the port's own
# FUEL-BOUNDED FOLD.
def UOp.gcd.cfactors.go(+fuel: Nat, +ar: Arena, +uops: List<&2, U32>, +acc: List<&2, H.I64>) -> List<&2, H.I64>:
  match uops:
    case Nil{}: acc
    case h <> t: UOp.gcd.cfactors.go(fuel, ar, t, List.append(&2, H.I64, acc, [UOp.const_factor(fuel, ar, h)]))

def UOp.gcd.cfactors(+fuel: Nat, +ar: Arena, +uops: List<&2, U32>) -> List<&2, H.I64>:
  UOp.gcd.cfactors.go(fuel, ar, uops, Nil{})

# and the gcd of a list of factors is a FOLD over `H.gcd` -- which is two I64s -- and the
# FIRST FACTOR IS THE START.
def UOp.gcd.gcd.go(+fs: List<&2, H.I64>, +acc: H.I64) -> H.I64:
  match fs:
    case Nil{}: acc
    case h <> t: UOp.gcd.gcd.go(t, H.gcd(acc, h))

def UOp.gcd.gcd(+fs: List<&2, H.I64>) -> H.I64:
  match fs:
    case Nil{}: H.i64_of_i32(1)
    case h <> t: UOp.gcd.gcd.go(t, h)

# and `Counter.elements()` is the port's own `H.make_tuple_rep` -- so the product is a
# concatenation of those, one per pair, and no recursion over a count is needed at all.
# and `List.concat` takes a list of lists -- measured 2026-11-08: the first spelling
# passed two lists and the compiler said "expected : List<&2, List<&2, U32>> / observed :
# List<&2, U32>"; and the port's own uses are `List.concat(&2, U32, [a, b])`
# (`nn/pool.bend:53`, `llm/cli.bend:126`).
def UOp.gcd.prod.go(+c: List<&2, Ctr>, +acc: List<&2, U32>) -> List<&2, U32>:
  match c:
    case Nil{}: acc
    case x <> t: UOp.gcd.prod.go(t, List.concat(&2, U32, [acc, H.make_tuple_rep(Ctr.k(x), Ctr.n(x))]))

def UOp.gcd.prod(+c: List<&2, Ctr>) -> List<&2, U32>:
  UOp.gcd.prod.go(c, Nil{})

# the answer itself: `UOp.gcd(*uops)` -- and it is a node, so it is built in the arena
# AND IT ANSWERS A `Found`, NOT A BARE `U32`.
#
# and this is the port's own shape -- measured 2026-11-08: a probe read `gcd=3` and
# `mk=3` with `mk_op=Ops.NOOP`, and the CONST is at INDEX 3 in the grown arena while
# INDEX 3 in the old arena is the noop -- so a DEF that answers a bare `U32` loses
# the arena and its INDEX is read in the wrong one. `UOp.const` answers a `Found`
# (`ops.bend:3071`), `UOp.alu` ANSWERS A `Found` (`ops.bend:2883`), AND THE CALLER
# THREADS `Found.ar` (`ops.bend:2784`).
#
# and the three steps are upstream's, in order:
#   1. the terms are the popped nodes and the factors are the popped consts.
#   2. the count is the multiset intersection of the terms' counters, and IF it is empty the
#      factors become the constant factors of the uops (`if not count: factors = ...`).
#   3. the product is the counter's elements and the start is `uops[0].const_like(gcd)`.
#
# and `const_like` is not ported and the port's arena has no shape field, so the port
# spells the unshaped one -- measured 2026-11-07 on CPYTHON: for the `(x*y)/y` case `x`
# IS A VARIABLE AND HAS NO SHAPE, SO `x.const_like(1)` IS `UOp.const(1, dtype)`.
def UOp.gcd.const2(+ar: Arena, +uops: List<&2, U32>, g: H.I64) -> Found:
  match uops:
    case Nil{}: Found{ar, 0}
    case x <> _ : UOp.const(ar, CInt{g})

# and the answer's product is a FOLD of `MUL`s over the counter's elements, starting at
# the CONST -- and it is not the counter's product, which is a list of indices -- measured
# 2026-11-08: the two were given one name and the reorderer reported "a cycle".
def UOp.gcd.const(+ar: Arena, +uops: List<&2, U32>) -> Found:
  UOp.gcd.const2(ar, uops, UOp.gcd.gcd(UOp.gcd.cfactors(Arena.budget(ar), ar, uops)))

def UOp.gcd.answer.mul2(+made: Found, +h: U32) -> Found:
  UOp.alu(Found.ar(made), OpsMUL{}, [Found.i(made), h])

# the counter's own tests, and they are CPYTHON-confirmed against CPYTHON's own
# `UOp.gcd` -- so the port's answer and python's are two independent computations of the
# SAME PROPERTY.
#
# and the claims are not change-detectors:
#   t_gcd_const   THE GCD OF TWO UNRELATED VARIABLES IS 1 -- A CONST. Catches a port that
#                  returns the wrong node shape.
#   t_gcd_shared  the gcd of `x*z` and `x*z` is the shared factor `x` times the gcd of
#                  the constants -- and the CONST is stripped by `pop_const`, which is
#                  what makes the counter `{x:1}` and not `{x:1, 3:1}`.

# `UOp.divide_exact` -- ops.py:1038-1047.
#
#     def divide_exact(self, v:UOp) -> UOp|None:
#       if self is v: return self.const_like(1)
#       if v.op is Ops.CONST: return self.divides(v.val)
#       if self.op is Ops.ADD: return None if (s0:=self.src[0].divide_exact(v)) is None or (s1:=self.src[1].divide_exact(v)) is None else s0+s1
#       if self.op is Ops.MUL:
#         (fac, const), (div_fac, div_const) = self.pop_const(Ops.MUL), v.pop_const(Ops.MUL)
#         new_count = collections.Counter(fac.split_uop(Ops.MUL))
#         new_count.subtract(div_fac.split_uop(Ops.MUL))
#         if const%div_const==0 and all(v>=0 for v in new_count.values()): return math.prod(new_count.elements())
#       return None # generic None if we aren't sure
#
# and the port spells it with the port's own pieces:
#   * `self is v` is `U32.is_eq(self, v)` -- and the port's nodes are indices into an
#     arena, so two nodes are the same iff their indexes are.
#   * `self.divides(v.val)` IS THE PORT's OWN `UOp.divides` (`ops.bend:8569`), WHICH ANSWERS A
#     `Dv{ok, f, i}` -- the `ok` is the "it divides" flag and `f`/`i` are the quotient's node
#     AND ITS INDEX.
#   * `new_count.subtract(...)` and `all(v>=0 ...)` are one comparison of two unsigned
#     counters instead of a subtraction and a sign test -- and they are the same property:
#     upstream's difference is non-negative iff every key of the divisor's counter is present
#     in the numerator's counter at least as many times. and that is what makes the
#     port's `U32` count enough: a signed counter would be new arithmetic for a comparison that
#     TWO UNSIGNED COUNTERS ALREADY ANSWER.
#   * `math.prod(new_count.elements())` IS THE PORT's OWN `H.make_tuple_rep` CONCATENATION,
#     THE SAME SHAPE AS `UOp.gcd`'s PRODUCT.
#
# and the answer is a `Maybe<&1, U32>` -- and `None{}` is upstream's `None`, which is the
# "WE AREN'T SURE" ANSWER AND NOT AN ERROR.

# the FOLD's state: the product so far and the "all counts non-negative" flag so far
# -- and a record is positional -- measured 2026-11-08 -- so it is built in one place and
# READ IN ONE PLACE.
type Ds is Data:
  Ds{ok: Bool, es: List<&2, U32>}

def UOp.gcd.answer.mul(+es: List<&2, U32>, +made: Found) -> Found:
  match es:
    case Nil{}: made
    case h <> t: UOp.gcd.answer.mul(t, UOp.gcd.answer.mul2(made, h))

# and the adder: the state times the HEAD -- and it answers the new state, and it is not
# IN THE RECURSION.
def Ds.ok(+d: Ds) -> Bool:
  match d:
    case Ds{ok, es}: ok

def Ds.es(+d: Ds) -> List<&2, U32>:
  match d:
    case Ds{ok, es}: es

# and the FOLD over the numerator's counter -- and the state is passed once and the
# adder answers the new state, which is the port's own `merge_dicts.go` shape
# (`helpers.bend:2533`): `merge_dicts.go(t, merge_dicts.add(kv_conflict(merged_seen(m), kv), kv, m))`.
#
# and the denominator's counter is the FOLD's other state -- and it is passed once per
# step too -- and the two answers come out of one FOLD, which is what makes `den` a
# SINGLE CONSUMPTION -- MEASURED 2026-11-09: "expected : den / observed : den (consumed more
# than once)".
def UOp.divide_exact.ge1(+h: Ctr, +den: List<&2, Ctr>) -> Bool:
  Bool.not(U32.is_gt(ctr_find(den, Ctr.k(h)), Ctr.n(h)))

# and one key's contribution: the key repeated by the difference of the two counts --
# and that is `math.prod(new_count.elements())` -- and a key the divisor consumed twice
# leaves a count of zero and contributes nothing.
def UOp.divide_exact.diff(n: U32, +d: U32, gt: Bool) -> U32:
  match gt:
    case True{}: 0
    case False{}: U32.sub(n, d)

# THE FOUR ARMS OF `divide_exact`, IN UPSTREAM's ORDER.
#
# and every comparison is a parameter and not a computed value -- measured 2026-11-08:
# "a match cannot scrutinize a computed value: give it its own def" -- AND A `match` OVER A
# call is also a computed value, so the op is read into a parameter first.
#
# and the answer is a `Dq` and not a `Maybe` -- and that is because the two srcs' answers
# must be bound and a `Maybe` is a TYPE and not a `Data`, and a `+` binder's TYPE
# MUST BE `Data` -- MEASURED 2026-11-08: "Note: +m can be used many times, so its type must be
# Data". and the port's own `UOp.divides.op` is the pattern that works (`ops.bend:8252`):
# one DEF, a `match` on the op, two direct self-calls bound with `+` in the ADD's arm, and
# the results combined by a helper. and a `Dq{ok: Bool, f: Found}` is exactly the port's own
# `Dv{ok: Bool, f: Found}` shape (`ops.bend:8467`) -- so the answer's TYPE is the port's own
# ANSWER TYPE AND NOT A NEW ONE.
#
# and `None{}` is upstream's `None`, which is the "we aren't sure" answer and not an
# ERROR -- AND IT IS THE `ok: False` HALF OF THE RECORD.

# the answer: the port's own `Dv` shape -- `ok` says whether it divides exactly and `f`
# IS THE QUOTIENT's NODE.
type Dq is Data:
  Dq{ok: Bool, f: Found}

def UOp.divide_exact.fold.elems(+h: Ctr, +den: List<&2, Ctr>) -> List<&2, U32>:
  H.make_tuple_rep(Ctr.k(h), UOp.divide_exact.diff(Ctr.n(h), ctr_find(den, Ctr.k(h)),
                                                  U32.is_gt(ctr_find(den, Ctr.k(h)), Ctr.n(h))))

# and the difference of two counts, and it cannot go negative because the FOLD has already
# checked that every key of the divisor is present at least as many times.
def UOp.divide_exact.fold.add(+h: Ctr, +den: List<&2, Ctr>, +st: Ds) -> Ds:
  Ds{Bool.and(Ds.ok(st), UOp.divide_exact.ge1(h, den)),
     List.concat(&2, U32, [Ds.es(st), UOp.divide_exact.fold.elems(h, den)])}

# and one key's test: the numerator has at least as many of it as the divisor -- and
# `ctr_find` answers zero for a key that is not there, which is exactly the "missing" case.
def UOp.divide_exact.fold.go(+c: List<&2, Ctr>, +den: List<&2, Ctr>, +st: Ds) -> Ds:
  match c:
    case Nil{}: st
    case h <> t: UOp.divide_exact.fold.go(t, den, UOp.divide_exact.fold.add(h, den, st))

# and the adder: the key's contribution and the "non-negative" test -- and both read
# the denominator's counter, once each, in two defs.
def Dq.ok(+d: Dq) -> Bool:
  match d:
    case Dq{ok, f}: ok

def Dq.f(+d: Dq) -> Found:
  match d:
    case Dq{ok, f}: f

# and the "we aren't sure" answer: a `Dv`-shaped record with `ok` FALSE -- and the INDEX is
# 0 BECAUSE THERE IS NO NODE.
def Dq.no(+ar: Arena) -> Dq:
  Dq{False{}, Found{ar, 0}}

# and the entry: the two booleans and then the op -- and this is the port's own
# `UOp.divides` SHAPE (`ops.bend:8573`):
# `UOp.divides.one(dv.is1(v), fuel, ar, v, i)`.
def UOp.divide_exact.add(+ar: Arena, +da: Dq, +db: Dq, +ok: Bool) -> Dq:
  match ok:
    case True{}: Dq{True{}, UOp.alu(Found.ar(Dq.f(db)), OpsADD{}, [Found.i(Dq.f(da)), Found.i(Dq.f(db))])}
    case False{}: Dq.no(ar)

# and the CONST's value: and it is the port's own `cf.cv`, which answers the CONST's value
# or the identity `1` -- and that is upstream's `identity_element(MUL, dt)`, which is
# 1 (`ops.py:81`: `{Ops.ADD:0, Ops.MUL:1, Ops.MAX:dt.min}[op]`). -- MEASURED 2026-11-09:
# `ops.bend:7776` READS `def cf.cv(m: Maybe<&1, Const>) -> H.I64` WITH `case Some{+c}: cf.cv.c(c)`
# and `case None{}: H.i64_of_i32(1)` -- and a second COPY of that reader is a second COPY.
def UOp.divide_exact.cval(+ar: Arena, +v: U32) -> H.I64:
  cf.cv(UOp.pop_const_val(ar, v, OpsMUL{}))

# and the CONST node's own value -- and that is the node's own ARG -- and it is what
# a test reads to check the answer -- measured 2026-11-09: the two are different reads and
# THE PORT's OWN `cval_arg` READS THE ARG (`ops.bend:7705`).
def UOp.divide_exact.constval(+ar: Arena, +v: U32) -> H.I64:
  cf.cv(cval_arg(Arena.arg(ar, v)))

# and the `Dv` answer: ok is the quotient and not-ok is the "we aren't sure" answer.
def UOp.divide_exact.dv(+d: Dv, +ok: Bool) -> Dq:
  match ok:
    case True{}: Dq{True{}, Dv.f(d)}
    case False{}: Dq.no(Found.ar(Dv.f(d)))

# and the MUL arm, step for step:
#
#     (fac, const), (div_fac, div_const) = self.pop_const(Ops.MUL), v.pop_const(Ops.MUL)
#     new_count = collections.Counter(fac.split_uop(Ops.MUL))
#     new_count.subtract(div_fac.split_uop(Ops.MUL))
#     if const%div_const==0 and all(v>=0 for v in new_count.values()): return math.prod(new_count.elements())
#
# and the port spells `pop_const(Ops.MUL)` as its own pair -- the node half is the port's own
# `UOp.pop_const_node` (which this block adds) and the CONST half's value is
# `UOp.divide_exact.cval`.
def UOp.divide_exact.start(+ar: Arena, +self: U32, +v: U32) -> Found:
  UOp.const(ar, CInt{H.i64_div(UOp.divide_exact.cval(ar, self), UOp.divide_exact.cval(ar, v))})

# and the remainder: `const % div_const == 0` -- and the port's own `H.i64_mod` is the
# SPELLING (`helpers.bend:2268`) -- AND A ZERO DIVISOR IS UPSTREAM's `ZeroDivisionError`,
# and the port spells the zero case as not dividing rather than as an ERROR, and that
# IS A DIFFERENCE WORTH NAMING.
def UOp.divide_exact.mod0(+c: H.I64, d: H.I64, zero: Bool) -> Bool:
  match zero:
    case True{}: False{}
    case False{}: H.i64_is_zero(H.i64_mod(c, d))

# and the MUL's body: the two counters.
def UOp.divide_exact.ar(+m: Found) -> Arena:
  Found.ar(m)

# AND THE INDEX: THE STATE's INDEX.
def UOp.divide_exact.i(+m: Found) -> U32:
  Found.i(m)

# and the elements of the counter, which is a list of node indices -- and it is the same
# shape as the product, so the product is the elements.
def UOp.divide_exact.mul8(+m: Found, +nh: U32) -> Found:
  UOp.alu(UOp.divide_exact.ar(m), OpsMUL{}, [UOp.divide_exact.i(m), nh])

# and the arena: the state's arena.
def UOp.divide_exact.mul7(+t: List<&2, U32>, +m: Found, +h: U32) -> Dq:
  match t:
    case Nil{}: Dq{True{}, UOp.divide_exact.mul8(m, h)}
    case nh <> nt :
      UOp.divide_exact.mul7(nt, UOp.divide_exact.mul8(m, h), nh)

# and the new node: the state times the HEAD -- and the state's two fields are read once
# EACH, IN TWO DEFS -- MEASURED 2026-11-09: "expected : a call smaller than
# UOp.divide_exact.mul7(m, nh <> nt) (arguments are read left to right: each passed unchanged
# until used)" and the port's own `Dv.ok`/`Dv.f`/`Dv.i` are three accessors that each
# DESTRUCTURE THE RECORD ONCE (`ops.bend:8470`/`8474`/`8478`).
def UOp.divide_exact.mul6(+ar: Arena, +start: Found, +es: List<&2, U32>) -> Dq:
  match es:
    case Nil{}: Dq{True{}, start}
    case h <> t: UOp.divide_exact.mul7(t, start, h)

# and the MUL-chain: the first element times the second, and the tail is the recursion --
# and it is right-nested and has no accumulator, exactly like the port's own
# `H.prod_u32` (`helpers.bend:486`): `case h <> t: (U32.mul(h, prod_u32(t)) : U32)`.
def UOp.divide_exact.mul5(+ar: Arena, +self: U32, +v: U32, fac: U32, div_fac: U32, start: Found,
                          st: Ds) -> Dq:
  match st:
    case Ds{ok, es}:
      match ok:
        case True{}: UOp.divide_exact.mul6(ar, start, es)
        case False{}: Dq.no(ar)

# and the elements: and the match is over a parameter and not a computed value.
def UOp.divide_exact.mul4(+ar: Arena, +self: U32, +v: U32, fac: U32, div_fac: U32, start: Found,
                          num: List<&2, Ctr>, den: List<&2, Ctr>) -> Dq:
  UOp.divide_exact.mul5(ar, self, v, fac, div_fac, start,
                        UOp.divide_exact.fold.go(num, den, Ds{True{}, Nil{}}))

# and the product: the numerator's keys repeated by the difference of the two counts --
# and that is `math.prod(new_count.elements())` -- and a key that is fully consumed
# CONTRIBUTES NOTHING.
# and the `Ds` record is a field and a field scrutinee is legal -- measured 2026-11-09:
# "a parameter or field scrutinee (a match cannot scrutinize a computed value: give it its own
# def)" -- and the port's own `Dv.ok`/`Dv.f`/`Dv.i` are three accessors that each
# DESTRUCTURE THE RECORD ONCE (`ops.bend:8470`/`8474`/`8478`).
def UOp.divide_exact.mul3(+ar: Arena, +self: U32, +v: U32, +fac: U32, +div_fac: U32, +start: Found) -> Dq:
  UOp.divide_exact.mul4(ar, self, v, fac, div_fac, start,
                        ctr_of(UOp.split_uop(Arena.budget(ar), ar, fac, OpsMUL{})),
                        ctr_of(UOp.split_uop(Arena.budget(ar), ar, div_fac, OpsMUL{})))

# and the second condition: the counts are non-negative -- and it is a parameter and
# NOT A COMPUTED VALUE.
def UOp.divide_exact.mul2(+ar: Arena, +self: U32, +v: U32, fac: U32, div_fac: U32, mod0: Bool,
                          start: Found) -> Dq:
  match mod0:
    case True{}: UOp.divide_exact.mul3(ar, self, v, fac, div_fac, start)
    case False{}: Dq.no(ar)

# AND THE START: `self.const_like(const//div_const)` -- AND `const_like` IS THE
# UNSHAPED `UOp.const(b, dt)` -- MEASURED 2026-11-07 ON CPYTHON -- AND THE DIVISION IS
# an integer division of the two constants, and the port's own `H.i64_div` is the
# SPELLING (`helpers.bend`: `H.i64_div(val, v)` IN `dv.const2`).
def UOp.divide_exact.mul(+ar: Arena, +self: U32, +v: U32) -> Dq:
  UOp.divide_exact.mul2(ar, self, v,
                        UOp.pop_const_node(ar, self, OpsMUL{}),
                        UOp.pop_const_node(ar, v, OpsMUL{}),
                        UOp.divide_exact.mod0(UOp.divide_exact.cval(ar, self), UOp.divide_exact.cval(ar, v),
                                              H.i64_is_zero(UOp.divide_exact.cval(ar, v))),
                        UOp.divide_exact.start(ar, self, v))

# and the first condition: `const % div_const == 0` -- and it is a parameter and not a
# COMPUTED VALUE -- MEASURED 2026-11-09: "a parameter or field scrutinee (a match cannot
# scrutinize a computed value: give it its own def)".
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

# and the ADD: both answers must be ok, and the sum is built in the second's arena -- and
# THE PORT's OWN `dv.add` IS THE PATTERN (`ops.bend:8201`):
# `dv.add(Bool.and(Dv.ok(da), Dv.ok(db)), da, db)`.
def UOp.divide_exact.cst(isconst: Bool, +ar: Arena, +self: U32, +v: U32) -> Dq:
  match isconst:
    case True{}:
      +dv = UOp.divides(Arena.budget(ar), ar, UOp.divide_exact.constval(ar, v), self)
      UOp.divide_exact.dv(dv, Dv.ok(dv))
    case False{}: UOp.divide_exact.op(Arena.budget(ar), Arena.op(ar, self), ar, v, self)

# and the op match -- and it is the port's own `UOp.divides.op` shape (`ops.bend:8252`):
# a `match` on a parameter, and the ADD's arm makes two direct self-calls -- and the
# op is passed as a call at the call site (`Arena.op(ar, self)`), and the recursion
# passes the child's op, which is also a call -- and that is exactly
# `UOp.divides.op(p, Arena.op(ar, Arena.src(ar, i, 0)), ar, v, Arena.src(ar, i, 0))`.
def UOp.divide_exact.one(same: Bool, +ar: Arena, +self: U32, +v: U32) -> Dq:
  match same:
    case True{}: Dq{True{}, UOp.const(ar, CInt{H.i64_of_i32(1)})}
    case False{}: UOp.divide_exact.cst(eq_op(Arena.op(ar, v), OpsCONST{}), ar, self, v)

# and the "v is a CONST" arm: `self.divides(v.val)` -- and the port's own `UOp.divides`
# answers a `Dv{ok, f, i}`, so a `Dv` that is not ok is the "we aren't sure" answer.
def UOp.divide_exact(+ar: Arena, +self: U32, +v: U32) -> Dq:
  UOp.divide_exact.one(U32.is_eq(self, v), ar, self, v)

# and the "self is v" arm: `self.const_like(1)` -- and `const_like(1)` is the unshaped
# `UOp.const(1, dt)`, MEASURED 2026-11-07 ON CPYTHON.
def UOp.gcd.prod.elems(+c: List<&2, Ctr>) -> List<&2, U32>:
  UOp.gcd.prod(c)

def UOp.gcd.answer(+ar: Arena, +uops: List<&2, U32>) -> Found:
  match uops:
    case Nil{}: Found{ar, 0}
    case x <> _ :
      +c = UOp.const(ar, CInt{UOp.gcd.gcd(UOp.gcd.cfactors(Arena.budget(ar), ar, uops))})
      UOp.gcd.answer.mul(UOp.gcd.prod.elems(ctr_inter(UOp.gcd.count(ar, UOp.gcd.terms(ar, uops)))), c)

# and the FOLD of `MUL`s: the product of the CONST and the counter's elements -- and the
# state is a `Found`, which is the port's own shape (`ops.bend:3274`:
# `def UOp.loop.go(+made: Found, +axis_id: U32) -> Found`), AND IT IS READ ONCE PER FIELD.
#
# and the recursion is direct and the helper is out of it -- measured 2026-11-08:
# THE REORDERER REPORTED "A CYCLE" OVER `['UOp.gcd.answer.mul', 'UOp.gcd.answer.mul2',
# 'UOp.gcd.answer.mul3']` THREE TIMES, AND THE PORT's OWN `merge_dicts.go` is the shape
# THAT WORKS (`helpers.bend:2533`):
# `merge_dicts.go(t, merge_dicts.add(kv_conflict(merged_seen(m), kv), kv, m))` -- THE
# recursion calls itself and the adder is a side branch that answers the new state.
#
# AND "arguments are read left to right: each passed unchanged until used" REFUSED EVERY
# spelling that passed the state to both the adder and the recursion -- and the port's own
# `merge_dicts.go` solves it: the state is passed once, inside the adder's argument list,
# and the adder answers the new state.
def UOp.gcd.mk2(+ar: Arena, +uops: List<&2, U32>, empty: Bool) -> Found:
  match empty:
    case True{}: UOp.gcd.const(ar, uops)
    case False{}: UOp.gcd.answer(ar, uops)

# and the constant answer: `uops[0].const_like(gcd(*factors))` -- and the port spells the
# UNSHAPED `const_like`, WHICH IS `UOp.const(b, dt)`.
def UOp.gcd.mk(+ar: Arena, +uops: List<&2, U32>) -> Found:
  UOp.gcd.mk2(ar, uops, UOp.gcd.isempty(ctr_inter(UOp.gcd.count(ar, UOp.gcd.terms(ar, uops)))))

def UOp.gcd(+ar: Arena, +uops: List<&2, U32>) -> Found:
  match uops:
    case Nil{}: Found{ar, 0}
    case h <> t: UOp.gcd.mk(ar, uops)

# and the two arms: the count is empty and it is not -- and the comparison is a
# parameter and not a computed value (measured 2026-11-08).

# `index` -- ops.py:578. `UOp(Ops.INDEX, src=(self,)+tuple(new_srcs))`, and above it
# a guard: a STACK indexed by ONE CONST is not an INDEX at all, it is that element
# of the STACK's own srcs. `st.index(1)` answers `st.src[1]`, and that is the row
# a STACK fixture exists for.
#
# `new_srcs` is `[UOp.const(x) if isinstance(x, int) else x for x in srcs if x is
# not None]`, and in the arena that list is the CALLER's: the int arm is
# `UOp.ufix` and the `None` arm is a `Maybe`. Stated once here because there is no
# way to spell it inline -- `List<U32>` has no `Maybe` element and `Maybe<&2, U32>`
# is not a list -- and that is a real API change from Python, not a convenience.
def UOp.index.isconst(ar: Arena, k: U32) -> Bool:
  eq_op(Arena.op(ar, k), OpsCONST{})

# The guard's answer: `self.src[new_srcs[0].val]`. The CONST's payload is an `H.I64`
# and a src index is a `U32`, so this is the low word. CPython raises IndexError
# past the end of the srcs; `Arena.src` answers the bottom, which is this file's
# standing spelling for "no such src".
def UOp.index.slot.go(arg: Arg) -> U32:
  match arg:
    case APy{CInt{i}}: H.lo32(i)
    case _: 0

def UOp.index.slot(+ar: Arena, self: U32, k: U32) -> U32:
  Arena.src(ar, self, UOp.index.slot.go(Arena.arg(ar, k)))

# THE PICK, and it is where the two answers have DIFFERENT ARENAS: the fast path
# hands back an index that already existed, so the arena is the caller's and
# NOTHING is minted. One mint, not two -- `UOp.after` and `UOp.end` build both
# candidates and throw one away because Bend evaluates an argument before the
# callee branches, and that waste is only free when the two candidates are the
# SAME node. Here they are DIFFERENT nodes, so the `Bool` decides and one is built.
# The arena the fast path returns is visibly the caller's, which is the check the
# rule at line 3097 ("a def that returns a bare index discards its arena") asks
# for: drop the guard here and the row that must move is the one whose answer is
# an index the caller already had.
def UOp.index.pick(hit: Bool, +ar: Arena, self: U32, k: U32) -> Found:
  match hit:
    case True{}: Found{ar, UOp.index.slot(ar, self, k)}
    case False{}: UOp.new(ar, OpsINDEX{}, [self, k], ANone{}, TNone{})

# THE GUARD, two tests rather than one `match` because `Arena.op(ar, self)` and
# `Arena.op(ar, k)` are both computed values and a `match` may scrutinise neither.
# `Bool.and` does not short-circuit, which is what makes the eager reads safe:
# `Arena.op` answers the bottom for a stale index rather than trapping.
def UOp.index.guard(+ar: Arena, self: U32, k: U32) -> Bool:
  Bool.and(eq_op(Arena.op(ar, self), OpsSTACK{}), UOp.index.isconst(ar, k))

# The ONE-src arm, the only one the guard can fire in. `self` and `k` are `+` here
# because `UOp.index.pick` reads them a second time.
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
# UOp) else src) + ((gate,) if gate is not None else ())`. SELF IS FIRST, the value
# second, the gate LAST and OPTIONAL, and the optional gate is the whole of the
# guard -- so `UOp.store.srcs` matches on it rather than `Bool.pick`ing between
# two lists, both of which would have to be built first.
#
# `const_like(src)` is the wall: it is `UOp.const(b, self.dtype)` and then an
# EXPAND when the shapes differ, and both halves are `fold.bend`'s. So `val` is
# the RESOLVED node and the caller does the coercion, which the signature says and
# a comment would not.
def UOp.store.srcs(+self: U32, +val: U32, gate: Maybe<&2, U32>) -> List<&2, U32>:
  match gate:
    case Some{g}: [self, val, g]
    case None{}: [self, val]

def UOp.store(ar: Arena, +self: U32, +val: U32, gate: Maybe<&2, U32>) -> Found:
  UOp.new(ar, OpsSTORE{}, UOp.store.srcs(self, val, gate), ANone{}, TNone{})

# `wmma` -- ops.py:649. `UOp(Ops.WMMA, src=(a, b, acc), arg=(dims, a.dtype,
# threads, tc_upcast_axes))`. "dtype_in is stored in the arg (not derived from
# src[0].dtype) because bitcast rewrites change src dtypes" -- so `dt` is the
# arg's OWN field, and that comment is why this def takes it rather than reading
# it back off `a`.
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

# THE INDEX ROW. Every fixture's index is its POSITION in the literal node list
# above and this prints the op name of each in that order, so a miscount is a
# visible row rather than a silent re-labelling of twenty-three rows. The
# arithmetic being easy is exactly why it needs a row.

# `ufix` -- ops.py:606. THREE rows and the third is the one the def exists for:
# `sg_ufix_miss` is a CONST fixture, so a def that MINTED on the `CU` arm would
# answer it with a fresh index and `False`. The other two are the arm names -- the
# op for the `CU` arm and the arg for the `CV` arm -- because a two-arm def with one
# fixture is a one-arm def with a comment.

# `sg_store_gate` is the optional-gate row and `sg_store_nogate` is its
# non-movement pair: the two differ in the THIRD src and in nothing else, so a def
# that dropped the gate entirely would answer the first row with three srcs.
# `sg_ins_tag` is `ta` and `sg_ins_none` is `bu`, and they differ ONLY in the tag,
# which is what makes `UOp.ins`'s third default load-bearing: a port that
# hardcoded `TNone` passes `sg_ins_none` and fails `sg_ins_tag`.

# `sg_reduce_none` is the row the `AReduce` normalisation cannot be dropped from: a
# def that always built `AReduce` would answer it `reduce:Ops.NOOP/0`, because the
# `Maybe`'s `None` arm is the only thing that writes `ANone` here.

# `sg_huo_src0` is the row the `1` in `src[1:]` exists for: `ca0`'s only ALLOC is
# src[0], which is the CALL's BODY, so the answer is False and a def that walked
# `src` instead of `src[1:]` answers True. `sg_huo_op` is the same separation on
# the other side -- a non-CALL with an ALLOC src -- and `sg_huo_unshard` is the only
# row that sees the `unsharded_base` peel, because `cun`'s ALLOC is two nodes down.

# `sg_body_add` is the `case _` row: without a non-CALL the `None` arm of
# `UOp.body.of` is dead code, and a dead arm cannot be mutated into moving anything.

# `() if not isinstance(device, tuple) else (UOp.range(len(device), 0, DEVICE),)`.
# `S.Dev` IS Python's `str | tuple[str, ...]` -- `D1` is the str and `Dn` the tuple
# -- so the `isinstance` test is the `match` and there is nothing else to it.
# `List.length` of the tags is `len(device)`, and `s5_devrange_one` / `_two` are
# the rows that see the number: a fixture that only printed the RANGE's op name
# would pass with the end hard-coded.
#
# The RANGE is TWO mints, not one: `UOp.range`'s `end` is `sint_to_uop(len)` and
# `sint_to_uop` is the CONST below, so the RANGE's `src[0]` is a node and the row
# reads the count back out of it. R-3: `.dn` is above its caller.
def UOp.device_range_src.dn(ar: Arena, +tags: List<&2, U32>) -> DRng:
  +c = UOp.const(ar, CInt{H.i64_of_i32(U32.from_nat(List.length(&2, U32, tags)))})
  DRng.of(UOp.range_end(Found.ar(c), Found.i(c), [0], AXIS_DEVICE{}))

def UOp.device_range_src(ar: Arena, +dev: S.Dev) -> DRng:
  match dev:
    case S.D1{tag}: DRng{ar, Nil{}}
    case S.Dn{tags}: UOp.device_range_src.dn(ar, tags)

# `copy_to_device` -- ops.py:761. `inp = self if arg is None else MSELECT(self,
# arg)`, then `UOp(Ops.COPY, src=(inp, *device_range_src(device)), arg=device)`.
#
# `arg` is a SHARD INDEX and it is a `Maybe<&2, U32>` because Python's `None` is
# the whole of what chooses between `self` and a fresh MSELECT. `UOp.mselect` above
# already mints that node, so the MSELECT is made HERE and not by the caller: the
# COPY's srcs are indices, and the only arena they may be read back from is the one
# the MSELECT grew. `ADev` is `arg=device`, the same `ADev` `getaddr` uses below.
#
# THE TWO `raise`s ARE NOT PORTED, and that is the honest state of them:
# `is_disk_device(device)` reads `device`, which is `uop/fold.bend`'s table read,
# and `inp.dtype in dtypes.weaks` needs the dtype fold, which is not ported. They
# cannot change the node, so this def builds the node CPython builds or it builds
# one CPython would have refused. TODO(p3) on both, and `s5_copy_*` does not
# pretend otherwise: it is the NODE that is gated, and the two guards are named.
def UOp.copy_to_device.inp(ar: Arena, +self: U32, k: Maybe<&2, U32>) -> Found:
  match k:
    case None{}: Found{ar, self}
    case Some{j}: UOp.mselect(ar, self, j)

def UOp.copy_to_device(+ar: Arena, +self: U32, k: Maybe<&2, U32>, +dev: S.Dev) -> Found:
  +f = UOp.copy_to_device.inp(ar, self, k)
  +d = UOp.device_range_src(Found.ar(f), dev)
  UOp.new(DRng.ar(d), OpsCOPY{}, List.append(&2, U32, [Found.i(f)], DRng.ys(d)), ADev{dev}, TNone{})

# `getaddr` -- ops.py:844. `if self.without_after.op not in {BUFFER, ALLOC, SHRINK,
# BITCAST, BINARY, MSTACK, MSELECT, PARAM, LINEAR}: return self` else
# `UOp(Ops.GETADDR, src=(self,), arg=device or to_tuple(self.device)[0])`.
#
# The nine-op test is a `match` with a `case _:` arm, which is the shape
# `UOp.buf_uop.cont` above uses and for the same reason: `Op` has seventy-eight
# constructors and a PARAMETER is not a legal scrutinee. `s5_ga_*` is one fixture
# per op rather than four ops standing in for nine, so dropping any one of the
# nine from the ladder moves a row.
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

# `self.without_after.op` -- the walk is in the PEEK, not in the ladder, and
# `s5_ga_after` is the row: WITHOUT it that fixture answers AFTER, with it
# GETADDR. A peel reading `Arena.op(ar, self)` directly typechecks and is wrong.
def UOp.getaddr.peel(fuel: Nat, +ar: Arena, +self: U32) -> Bool:
  UOp.getaddr.op(Arena.op(ar, UOp.without_after(fuel, ar, self)))

def UOp.getaddr.go(peels: Bool, ar: Arena, +self: U32, made: Found) -> Found:
  match peels:
    case True{}: made
    case False{}: Found{ar, self}

def UOp.getaddr(fuel: Nat, +ar: Arena, +self: U32, +dev: S.Dev) -> Found:
  UOp.getaddr.go(UOp.getaddr.peel(fuel, ar, self), ar, self,
    UOp.new(ar, OpsGETADDR{}, [self], ADev{dev}, TNone{}))

# `device or to_tuple(self.device)[0]` IS THE DEVICE AND IS A PARAMETER, not a
# fold. Python's default reads `self.device`, which is `uop/fold.bend`'s
# `UOp.device(ar, tb, i)` over a Table this file has no business building, so `dev`
# is what the caller resolved. That is this block's only signature change and it
# is stated here rather than left to be discovered. The discarded GETADDR in the
# `case False{}` arm grows the arena and is thrown away, which is what `UOp.after`
# and `UOp.broadcast` above already do.

# ==== ops.py:1030  `expr`, the one Variable-lattice def this arena can read ====
#
# A Variable is a scalar ALU PARAM carrying a name and a value RANGE; binding it
# sets the `val` payload on the arg. `expr` is the only def of that lattice whose
# answer is a FUNCTION OF THE ARG ALONE, which is exactly why it is the only one
# ported here -- see the wall at `is_variable` below.
#
# `expr` -- ops.py:1030. `assert self.op in {Ops.PARAM, Ops.BUFFER}; return
# unwrap(self.arg.name)`. A BUFFER's arg is an `AParam` too, so ONE arm is right
# for both ops and the op test is not repeated.
#
# The `None` is the `unwrap` raise, and it is this file's standing spelling for
# "CPython raises here" -- the same `None` `UOp.body` uses for its RuntimeError.
# The two `None`s mean different things: this one is a `ParamArg` whose `name` is
# unset, the other is an `Arg` that is not a `ParamArg` at all. `vr_expr_*` has a
# row for each, because one row cannot tell them apart.
#
# A `ParamArg` pattern must name all THIRTEEN fields, so this read ignores twelve.
# That is not verbosity: two literals of a fourteen-field record are how eleven of
# its fields drift, which is the entire reason `sg.pa.put` exists.
def UOp.expr.go(arg: Arg) -> Maybe<&2, String>:
  match arg:
    case AParam{pa}:
      match pa:
        case ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: name
    case _: None{}

def UOp.expr(+ar: Arena, +self: U32) -> Maybe<&2, String>:
  UOp.expr.go(Arena.arg(ar, self))

# DONE(p3) ops.py:1048  def const_factor
#   `def const_factor(self) -> int: """largest known int that divides self"""` --
#   five arms, a `math.gcd` over the STACK and ADD srcs, and a positional read for
#   MUL. Four of the five arms are one `match` each and are trivially expressible.
#   AND IT IS DONE: `def UOp.const_factor(fuel, ar, i) -> H.I64` IS ABOVE, AT `:7752`.
#   measured 2026-11-08 -- this NOTE used to say `TODO` while the DEF two hundred lines
#   above said `DONE`, and the two disagreed.
#
#   the blocker is the other two, and it is not a porting difficulty: computing
#   `x.const_factor()` for a src means CALLING this def, and this def's STACK/ADD
#   arms are a FOLD over the srcs, so the def and its fold are MUTUALLY recursive.
#   Bend cannot express that. Measured, not assumed -- a two-def probe where `a`
#   calls `b` and `b` calls `a`:
#
#       def a(n: U32) -> U32: ... case _: b(n)
#       def b(n: U32) -> U32: ... case _: U32.add(1, a(n))
#
#   is `expected : a filled definition (an unfilled law is a dead claim)`. Whichever
#   of the two is written first, the other's call reads as an unfilled law, and
#   there is no third order.
#
#   Every fold already in this file is SELF-recursive for this reason -- `UOp.base`,
#   `UOp.unsharded_base`, `UOp.storage_base`, `UOp.huo.go` -- one def with the
#   `match fuel` inside it and a non-recursive `.peel` above. `const_factor` cannot
#   be written that way, because its recursion is over a DIFFERENT node per step
#   (each src) while its arm is decided per node: fusing them means one def that
#   both picks the arm and walks the list, which is a worklist rewrite of the
#   shape `UOp.base` uses for a single peel.
#
#   So the wall is real and it is a substrate limit, not a missing thought.
#   `.agents/slop/bend-toposort.py` detects the cycle and refuses to write rather
#   than oscillating, which is how this was found.
#
# what that wall still blocks, re-measured 2026-11-04 -- and this paragraph used to
# overstate it. It named five markers as blocked. two of the five are done:
#
#   DONE  ops.py:1069 `divides`   -- `UOp.divides.op` (:7951) and `UOp.divides` (:7972),
#                                    verified against CPython on 8 of 8 shapes.
#   DONE  ops.py:1082 `pop_const` -- `UOp.pop_const_val` (:7738) / `UOp.pop_const_hits`
#                                    (:7748), with its DONE(p3) marker at :5693.
#   TODO  ops.py:1073 `gcd`
#   TODO  ops.py:1079 `divide_exact`
#
# a marker that names finished work is not a TODO, it is a trap: it tells the next
# reader to build what is already there, and the reader who trusts it will either
# duplicate the function or report the row as blocked. `divides` was listed as gated on
# `const_like` while it sat ported and verified below the list.

# TODO(p3) ops.py:1073  def gcd
#   `zip(*[u.pop_const(Ops.MUL) for u in uops])`, a `Counter` intersection of
#   `split_uop(Ops.MUL)` terms, and `math.gcd` over `const_factor`s. `const_factor`
#   (:7855), `split_uop` (:5169) and `pop_const` (:7738) all exist, so what is missing
#   is the MULTISET and not the walk: a `Counter` intersection is a fold over two node
#   lists, and `math.prod(count.elements(), start=...)` is a MUL chain from a base.

# TODO(p3) ops.py:1079  def divide_exact
#   Recurses over ADD/MUL srcs and calls `divides` (DONE), `const_like` and
#   `__floordiv__`. `const_like` is ops.py:572 and is NOT ported (:5441): it is
#   `UOp.const(b, dtype or self.dtype)` plus `_mop(Ops.EXPAND, arg=self._shape)`, so the
#   SHAPED half needs the shape field this arena does not carry. The scalar half already
#   exists as `sy_const_like` (symbolic.bend:485).

# ==== ops.py:1015  `UOp.variable` =========================================
#
# `return UOp(Ops.PARAM, arg=ParamArg(-1, dtype, name=name, vmin_vmax=(min_val,
# max_val), multiple_of=multiple_of, addrspace=AddrSpace.ALU))`, with the comment
# that says what it is: "a Variable is a scalar ALU PARAM with a name and a value
# range; binding it sets the val payload on the arg".
#
# THIS DEF WAS BLOCKED UNTIL `ParamArg.no_slot` EXISTED, and that name is the whole
# of the unblocking: CPython writes `slot=-1`, this port's `ParamArg.slot` is a
# `U32`, and the file that OWNS the field had no name for "no positional slot" while
# three siblings had each invented one. MEASURED: `variable("i",0,10).arg.slot` is
# `-1`, and `ParamArg.no_slot()` is that value in a `U32`.
#
# `AddrSpace.ALU` is `S.Aalu{}` and it is the ONLY addrspace this def sets, which
# is why `is_variable` tests it: a PARAM with a range and a name is a Variable only
# if it is ALU, because a BUFFER carrying a range is a shaped buffer.
#
# The thirteen-field rebuild is a `match` and not a second literal, and its scrutinee
# is a PARAMETER rather than the `ParamArg.of(...)` call -- a match may scrutinise
# neither a computed value nor a local binder. Same reason `sg.pa.put` takes its
# record as an argument.
def UOp.variable.pa.of(base: ParamArg, nm: String, r: PyRange, mo: U32) -> ParamArg:
  match base:
    case ParamArg{slot, dtype, vmin_vmax, multiple_of, _n, addrspace, device, volatile, image, buffer, bind_on_realize, val}:
      ParamArg{slot, dtype, Some{r}, Some{mo}, Some{nm}, S.Aalu{},
        device, volatile, image, buffer, bind_on_realize, val}

def UOp.variable.pa(nm: String, lo: H.I64, hi: H.I64, mo: U32, dt: S.Dt) -> ParamArg:
  UOp.variable.pa.of(ParamArg.of(ParamArg.no_slot(), dt), nm, PyRange{lo, hi}, mo)

def UOp.variable(+ar: Arena, nm: String, lo: H.I64, hi: H.I64, mo: U32, dt: S.Dt) -> Found:
  UOp.new(ar, OpsPARAM{}, Nil{}, AParam{UOp.variable.pa(nm, lo, hi, mo, dt)}, TNone{})

# the three `Map` readers take their quantifier in three different places, and
# getting it wrong is a `expected : Map<&2, H.I64> / observed: VarVals` rather than a
# clean arity error, because the stray value lands in the next parameter.
#   Map.set(a, -V: Kind(a), m, key, x)  -- quantifier SECOND, after the linearity
#   Map.has(-a: Quant, -V: Kind(a), m, key)
#   Map.get(-V: Data, d, m, key)        -- NO linearity parameter at all
# `uop/render.bend:1012 symbol=range_ids.of` and `:1017` already spell all three correctly; this cost three
# compile rounds to find, and the first of them I had recorded as a LANGUAGE gap.
# `Map.set` puts its QUANTIFIER SECOND (`Map.set(a, -V: Kind(a), m, key, x)`) and
# the three `Map` readers in the tree disagree about that -- `Map.has` takes it
# first, `Map.get` has NO linearity parameter. A stray `&2` lands in the next
# parameter's slot and the error names a type rather than an arity.

# `ProgramInfo.launch_dims` -- ops.py:1352 -- AND `ProgramInfo.from_sink`
# -- ops.py:1358. the two methods upstream's `ProgramInfo` has at the PIN.
#
# `gates/valsdiv-gate.py` READS UPSTREAM'S CLASS AND PRINTED
# `upstream-methods: launch_dims, from_sink` on 2026-10-22, which is the same
# two names this block carries.
#
# `launch_dims` COMES FIRST BECAUSE UPSTREAM'S ORDER IS `launch_dims` (1352)
# THEN `from_sink` (1358), and the `vals` block above is the port of the
# method upstream had at `186fbba2a` -- the parent of the commit that deleted
# it -- so the order here is `vals`, `launch_dims`, `from_sink`.
#
# THE ORDER INSIDE IS DEPENDENCY ORDER, and Bend has no forward references: a
# def may only call defs written ABOVE it. That is why every `.of` def is
# written before the def that calls it, and why the three arena readers are at
# the top.

# the three arena reads this block matchs on. a `match` may not scrutinise a
# computed value ("give it its own def"), so each one gets its own DEF.
def fs.arg(ar: Arena, u: U32) -> Arg:
  Arena.arg(ar, u)

def fs.op(ar: Arena, u: U32) -> Op:
  Arena.op(ar, u)

# the PARAM list holds `PSlot` and not the node INDEX, because the sort key is
# the PARAM's SLOT and `List.sort`'s comparator must be a TOP-LEVEL DEF: a
# closure is affine and `List.sort` calls its comparator once per comparison,
# so a comparator that reads the arena cannot be a closure. The key therefore
# travels BESIDE the value.
type PSlot is Data:
  PSlot{slot: U32, node: U32}

# the comparator's parameters are named `a` and `b` and not `x` and `y`,
# because `List.sort`'s comparator is a TEMPLATE and it is INLINED into
# `List.merge.go`, whose own pattern binders are `x` and `y`.
def PSlot.le(a: PSlot, b: PSlot) -> Bool:
  match a b:
    case PSlot{slot, node} PSlot{s2, n2}: U32.is_le(slot, s2)

# A PARAM's SLOT and whether it is an ALU one -- the two facts `from_sink` asks
# of a PARAM.
type PInfo is Data:
  PInfo{slot: U32, alu: Bool}

def PInfo.slot(p: PInfo) -> U32:
  match p:
    case PInfo{slot, alu}: slot

def PInfo.alu(p: PInfo) -> Bool:
  match p:
    case PInfo{slot, alu}: alu

# UPSTREAM'S `_params`, `_globals`, `outs` AND `ins`, IN ONE RECORD. `params`
# holds the PARAM node INDICES (upstream holds the UOps, and the port's
# `ProgramInfo.params` is `List<&2, U32>`), `globals`/`outs`/`ins` hold SLOTS.
type FS is Data:
  FS{params: List<&2, PSlot>, globals: List<&2, U32>, outs: List<&2, U32>, ins: List<&2, U32>}

# THE TWO LAUNCH-SIZE TRIPLES. It is also the ANSWER TYPE of `launch_dims`,
# because a pair is not a `Type` this language can return and upstream's
# `launch_dims` returns a pair.
type Sz is Data:
  Sz{gs: List<&2, H.I64>, ls: List<&2, H.I64>}

# `outs` AND `ins` TOGETHER, because upstream's default (`if not outs and not
# ins: outs = ins = _globals`) sets BOTH at once.
type OI is Data:
  OI{o: List<&2, U32>, i: List<&2, U32>}

# `from_sink` -- ops.py:1358.
#
#     @staticmethod
#     def from_sink(sink:UOp, target:Target=Target()) -> ProgramInfo:
#       _params: list[UOp] = []
#       _globals: list[int] = []
#       outs: list[int] = []
#       ins: list[int] = []
#       global_size: list[int] = [1, 1, 1]
#       local_size: list[int] = [1, 1, 1]
#       for u in sink.toposort():
#         if u.op is Ops.PARAM: _params.append(u)
#         if u.op is Ops.PARAM and u.addrspace != AddrSpace.ALU: _globals.append(u.arg.slot)
#         if u.op in (Ops.STORE, Ops.LOAD):
#           if (idx:=u.src[0]).op in (Ops.INDEX, Ops.SHRINK) or (u.src[0].op is Ops.CAST and (idx:=u.src[0].src[0]).op is Ops.INDEX):
#             if (buf:=idx.src[0].buf_uop).op is Ops.PARAM: (outs if u.op is Ops.STORE else ins).append(buf.arg.slot)
#         if u.op is Ops.SPECIAL: (local_size if u.arg[0] == 'l' else global_size)[int(u.arg[-1])] = cast(int, u.src[0].substitute({v:v.replace(arg=replace(v.arg, slot=-1)) for v in u.src[0].toposort() if v.op is Ops.PARAM and v.is_variable}).ssimplify())
#       if not outs and not ins: outs = ins = _globals # if neither is inferred, default to all buffers
#       return ProgramInfo(tuple(global_size), tuple(local_size),
#                          tuple(sorted(_params, key=lambda p: p.arg.slot)), tuple(sorted(dedup(_globals))), tuple(sorted(dedup(outs))),
#                          tuple(sorted(dedup(ins))), target)
#
# the port's answer is a `Maybe`, and the refusal is measured and not a
# CONVENIENCE: upstream's `cast(int, ...)` is a LIE in the SYMBOLIC case -- the
# value in `global_size` is a UOp -- and the port's `global_size` is
# `List<&2, H.I64>`, which holds INTS. So a sink whose launch size is not a
# CONST is REFUSED, and `Maybe` is the port's standing spelling for "this
# cannot be answered here" (the same one `ProgramInfo.vals` uses for an
# unbound Variable).
#
# a `match` may not scrutinise a computed value, so every read that is
# MATCHED ON GETS ITS OWN `.of` DEF, and every read that is a BOOL is
# DISPATCHED WITH `Bool.pick` RATHER THAN A `match`. That is why this block is
# longer than upstream's twenty lines: Bend has no projection syntax, no
# `for`, and no mutable list.

# THE PARAM'S SLOT AND ITS ADDRSPACE. `ParamArg`'s pattern must name all
# THIRTEEN fields, so the port's own accessors (`ParamArg.slot`,
# `ParamArg.addrspace`) are used rather than a second copy of that pattern.
def fs.pinfo.of(+a: Arg) -> Maybe<&2, PInfo>:
  match a:
    case AParam{pa}: Some{PInfo{ParamArg.slot(pa), pa.is_alu.of(a)}}
    case _: None{}

def fs.pinfo(ar: Arena, u: U32) -> Maybe<&2, PInfo>:
  fs.pinfo.of(fs.arg(ar, u))

# THE PARAM'S SLOT, for the `buf_uop` answer.
def fs.slot.of(a: Arg) -> Maybe<&2, U32>:
  match a:
    case AParam{pa}:
      match pa:
        case ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}:
          Some{slot}
    case _: None{}

def fs.slot(ar: Arena, u: U32) -> Maybe<&2, U32>:
  fs.slot.of(fs.arg(ar, u))

# `(buf:=idx.src[0].buf_uop).op is Ops.PARAM` -- upstream asks whether the
# buffer under the index is a PARAM and then reads its SLOT, so the answer here
# is the slot and `None{}` is "not a PARAM".
#
# THE WALK IS upstream's `while len(s.src) and s.op not in {Ops.BUFFER,
# Ops.alloc, Ops.PARAM, Ops.stage, Ops.mstack}: s = s.src[0]`. the two arms
# before it answer the same question: an mselect (`buf_uop` returns
# `self.src[0].buf_uop.mselect(self.arg)`) and an MSTACK (`buf_uop` returns an
# MSTACK) are NOT PARAMs, so `from_sink` records nothing for either -- and the
# port does not rebuild those nodes, which is the only part of the two arms
# `from_sink` can see.
#
# UPSTREAM'S FOURTH ARM (`if self.base.op is Ops.AFTER: return
# self.base.src[0].buf_uop.base`) IS THE SAME ANSWER AS THE WALK: `base` skips
# the MOVEMENT ops and a movement op's `src[0]` IS the node it moves, so the
# walk and `base` reach the same node, and upstream's `buf_uop` stops at the
# same set.
#
# THE FUEL IS `Arena.budget(ar)` -- NODES PLUS EDGES -- and it is the port's
# standing bound for a walk with no structural decrease: the walk follows
# `src[0]` in an ARENA, so nothing about the ARENA gets smaller.
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

# `(idx:=u.src[0]).op in (Ops.INDEX, Ops.SHRINK) or (u.src[0].op is Ops.CAST
# and (idx:=u.src[0].src[0]).op is Ops.INDEX)` -- the index node under a STORE
# or a LOAD. THE CAST ARM IS A SEPARATE DEF because it reads a DIFFERENT node.
# the INDEX node under a STORE or a LOAD. upstream reads `u.src[0]` -- the
# STORE'S OWN FIRST SRC -- AND NOT `u`:
#
#     if (idx:=u.src[0]).op in (Ops.INDEX, Ops.SHRINK) or
#        (u.src[0].op is Ops.CAST and (idx:=u.src[0].src[0]).op is Ops.INDEX):
#
# and the op that is tested is the op of `u.src[0]`, not the op of `u`. that
# not an INDEX", so NO SLOT WAS EVER RECORDED, and every sink's `outs` AND `ins`
# CAME OUT EMPTY -- so upstream's `if not outs and not ins` default fired and
# the rows read `outs=(0) ins=(0)`, WHICH IS NOT EITHER UPSTREAM'S ANSWER.
# the CPYTHON diff caught it, and the two rows that carry it are `fs_store` and
# `fs_load`.
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

# `u.arg[0] == 'l'` -- the FIRST character of a SPECIAL's name. 'l' is ASCII
# 108 and `Char.to_u32` answers the byte.
def fs.sp.local.of(cs: List<&2, Char>) -> Bool:
  match cs:
    case Nil{}: False{}
    case c <> _: Char.is_eq(c, Chr{108})

def fs.sp.local(nm: String) -> Bool:
  fs.sp.local.of(String.to_list(nm))

# `int(u.arg[-1])` -- the LAST character of the name, as a DIMENSION INDEX.
# The names are "g0", "g1", "g2", "l0", "l1", so the last character is a
# DIGIT and '0' is ASCII 48.
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

# `u.src[0].substitute(...).ssimplify()` -- upstream. THE PORT'S `ssimplify` IS
# `UOp.ssimplify_val`, WHICH ANSWERS A CONST AND A CAST OF A CONST AND NOTHING
# ELSE, and the symbolic case is WHERE the port refuses.
def fs.sp.val.of(m: Maybe<&1, Const>) -> Maybe<&2, H.I64>:
  match m:
    case Some{CInt{i}}: Some{i}
    case _: None{}

def fs.sp.val(+ar: Arena, u: U32) -> Maybe<&2, H.I64>:
  fs.sp.val.of(UOp.ssimplify_val(ar, Arena.src0(ar, u)))

# `(local_size if u.arg[0] == 'l' else global_size)[int(u.arg[-1])] = value` --
# upstream's ONE update. `List.set` REBUILDS the list, so the LAST special for
# a dimension wins, which is what upstream's assignment does.
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

# the special's arm, and the difference between "not a special" and "a
# special whose SIZE i cannot hold". the first is skipped and the second is
# REFUSED, and they must not share a spelling: a `Maybe` that answers `None{}`
# for a node that is not a SPECIAL would REFUSE THE WHOLE SINK, and every sink
# in the tree has nodes that are not SPECIALs.
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

# `if u.op is Ops.PARAM: _params.append(u)` AND `if u.op is Ops.PARAM and
# u.addrspace != AddrSpace.ALU: _globals.append(u.arg.slot)` -- ONE def,
# because the second test is a CONJUNCTION of the first.
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

# `(outs if u.op is Ops.STORE else ins).append(buf.arg.slot)` -- ONE def for
# the STORE and the LOAD, because the two differ only in WHICH list the slot
# lands in.
def fs.io_slot(+ar: Arena, +u: U32) -> Maybe<&2, U32>:
  Maybe.bind(&2, U32, U32, fs.idx(ar, u), idx =>
    Maybe.bind(&2, U32, U32, fs.buf_slot.of(ar, Arena.src0(ar, idx)), slot =>
      Some{slot}))

# A STORE RECORDS AN `out` AND A LOAD RECORDS AN `in` -- upstream's
# `(outs if u.op is Ops.STORE else ins).append(buf.arg.slot)` (ops.py:1368). The
# two arms WERE SWAPPED for one run, and the CPython diff caught it: with the
# swap AND a wrong `outs = ins = _globals` default the two mistakes cancelled
# on `fs_store` and `fs_load` and the rows read `outs=(0) ins=(0)` -- a
# self-consistent answer that is not either upstream's. the proof is the pair
# `fs_store` (a STORE and no LOAD) AND `fs_load` (a LOAD and no STORE).
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

# the `if`s of upstream's LOOP, in order, as a chain of defs: a def holds one
# `match`, and each test is on a DIFFERENT node. THE SPECIAL ARM IS IN THE
# SIZE FOLD BELOW, because it needs its own accumulator.
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

# THE FOLD OVER `sink.toposort()`. `Maybe.bind`'s LAMBDA IS THE CONTINUATION,
# so the whole fold is one def with one `match` and one bind -- the same shape
# as `vals.step` above.
def fs.go(+ar: Arena, todo: List<&2, U32>, +acc: FS) -> Maybe<&2, FS>:
  match todo:
    case Nil{}: Some{acc}
    case u <> t:
      Maybe.bind(&2, FS, FS, fs.step(ar, u, acc), a2 => fs.go(ar, t, a2))

# THE SIZE FOLD -- upstream's SPECIAL arm, over the same toposort.
# THE SIZE FOLD -- upstream's SPECIAL arm, over the same toposort. IT IS ONE
# DEF AND NOT TWO because the step CONTINUES THE FOLD, and a def that calls
# the fold it is a step of is a CYCLE, which this language refuses.
def fs.sz.go(+ar: Arena, todo: List<&2, U32>, +sz: Sz) -> Maybe<&2, Sz>:
  match todo:
    case Nil{}: Some{sz}
    case +u <> t:
      Maybe.bind(&2, Sz, Sz, fs.sp.step(ar, u, sz), s2 => fs.sz.go(ar, t, s2))

# `sorted(dedup(...))` -- the three slot lists. `H.dedup_u32` IS upstream's
# `dedup` (`list(dict.fromkeys(x))`: first occurrence wins, order retained).
def fs.slots(xs: List<&2, U32>) -> List<&2, U32>:
  List.sort(U32, U32.is_le, H.dedup_u32(xs))

# `sorted(_params, key=lambda p: p.arg.slot)` -- the SORT, and then the
# mapping back to node indices.
# the HEAD goes first and not last, and `List.append` is `xs ++ ys`, so the
# order of the two arguments is the whole of this def. `ax_names_str.go` is the
# same shape: `List.append(&2, String, [AxisType.name(a)], ax_names_str.go(t))`.
def fs.nodes(xs: List<&2, PSlot>) -> List<&2, U32>:
  match xs:
    case Nil{}: Nil{}
    case PSlot{slot, node} <> t: List.append(&2, U32, [node], fs.nodes(t))

def fs.params(xs: List<&2, PSlot>) -> List<&2, U32>:
  fs.nodes(List.sort(PSlot, PSlot.le, xs))

# `if not outs and not ins: outs = ins = _globals` -- upstream's default when
# NEITHER is inferred: every buffer is both.
#
# AND NOT IS THE WHOLE OF THIS DEF, and it was `Bool.or` for one run and
# the CPython diff caught it: `Bool.or` fires when EITHER list is empty, so a
# sink with a STORE and no LOAD would have had its `ins` overwritten with the
# globals. Upstream's default fires only when BOTH are empty. THE PROOF IS
# `fs_store` (a STORE and no LOAD) AND `fs_load` (a LOAD and no STORE).
def fs.oi(+globals: List<&2, U32>, +outs: List<&2, U32>, +ins: List<&2, U32>) -> OI:
  Bool.pick(OI, Bool.and(List.is_empty(&2, U32, outs), List.is_empty(&2, U32, ins)),
    OI{globals, globals},
    OI{outs, ins})

# THE `ProgramInfo` UPSTREAM RETURNS.
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

# THE DECIMAL OF AN I64. The port's own `H.i64_text` is the `hi:lo` form --
# "a dump the oracle can diff line for line" -- and a launch size of 1 reading
# as "0:1" is a row nobody can read, so this def prints the DECIMAL when the
# high word is zero (which every launch size is) and the `hi:lo` form when it
# is not.
def fs.i64_dec.of(hi: U32, lo: U32) -> String:
  match hi:
    case 0: U32.show(lo)
    case _: String.concat([U32.show(hi), ":", U32.show(lo)])

def fs.i64_dec(+x: H.I64) -> String:
  fs.i64_dec.of(H.hi32(x), H.lo32(x))

# the gcd of two unrelated variables is 1 -- a CONST with no srcs.
#
# and the arena must be threaded between the two variables -- measured 2026-11-08:
# a probe built `x` and `y` from one `Arena.empty()` and read `x=1 y=1 z=1 nodes=1` --
# because `UOp.variable` answers a `Found` which carries the grown arena, and a caller
# that ignores `Found.ar` gets two sibling arenas (`ops.bend:2784`: "def Found.ar(f: Found)
# -> Arena"). so the second variable is built in the first's arena.
def t_gcd_const() -> Bool:
  +ar0 = Arena.empty()
  +fx = UOp.variable(ar0, "x", H.i64_of_i32(0), H.i64_of_i32(4), 1, S.weakint())
  +ar1 = Found.ar(fx)
  +fy = UOp.variable(ar1, "y", H.i64_of_i32(0), H.i64_of_i32(4), 1, S.weakint())
  +ar2 = Found.ar(fy)
  +g = UOp.gcd(ar2, [Found.i(fx), Found.i(fy)])
  +ga = Found.ar(g)
  Bool.and(eq_op(Arena.op(ga, Found.i(g)), OpsCONST{}), U32.is_eq(Arena.nsrc(ga, Found.i(g)), 0))

# the gcd of `x*z` and `x*z` is the shared factor -- and the constant is stripped by
# `pop_const`, which is what makes the counter `{x:1}` and not `{x:1, 3:1}`.
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

# the top-level `arg` lane -- and it is the lane that replaces the three `tag_*` rows
# IN `gates/ops-core-gate.py`.
#
# and the replacement is a measurement, not a whim: measured 2026-11-08, upstream deleted
# `UOp.tag` IN `fb518b44e` ("delete UOp.tag [pr] (#18954)", 2026-10-21) AND
# `git merge-base --is-ancestor fb518b44e f5ac54685074` ANSWERS YES -- SO AT THE PIN THERE IS
# no `tag` slot, and `rg '\btag\b' tinygrad/uop/ops.py` finds nothing. the PIN's key is
# `(op, src, arg, type(arg))` (`ops.py:194`), so `type(arg)` is the only thing that splits the
# KEY BY A PYTHON TYPE.
#
# and the port's `arg` carries that TYPE in itself -- `APy{CBool{…}}` and `APy{CInt{…}}` are
# different `Arg` values and `ANone{}` is a third -- so the port can answer the question, and
# the three rows below ask it at the top level of `arg`, which the `pynest_*` rows ask one
# level deep (inside `ParamArg.val`) and the `const_bool_vs_int_splits` row asks about a
# CONST's DTYPE-KEY.
#
# AND CPYTHON's OWN ANSWERS, MEASURED AT THE PIN: `arg=True` vs `arg=1` is False (the
# types differ), `arg=True` vs `arg=False` is False, `arg=None` vs `arg=0` is False
# (`NoneType` is not `int`), `arg=True` vs `arg=True` is True, `arg=1` vs `arg=1` is
# True, `arg=None` vs `arg=None` is True.

# the same `arg` on two nodes: one node (the two interned together).
def arg_same(a1: Arg, a2: Arg) -> Bool:
  +u = UOp.new(Arena.empty(), OpsSINK{}, Nil{}, a1, TNone{})
  +v = UOp.new(Found.ar(u), OpsSINK{}, Nil{}, a2, TNone{})
  U32.is_eq(Found.i(u), Found.i(v))

# a `bool` and an `int` are two nodes -- because `type(arg)` is in the key.
def t_arg_bool_vs_int_splits() -> Bool:
  Bool.not(arg_same(APy{CBool{True{}}}, APy{CInt{H.i64_of_i32(1)}}))

# AND A `None` AND AN `int` ARE TWO NODES -- `NoneType` is not `int`.
def t_arg_none_vs_int_splits() -> Bool:
  Bool.not(arg_same(ANone{}, APy{CInt{H.i64_of_i32(0)}}))

# and the control that the comparator is not "cross every TYPE against every other": two
# `int`s with the same value ARE ONE NODE.
def t_arg_int_same_interns() -> Bool:
  arg_same(APy{CInt{H.i64_of_i32(1)}}, APy{CInt{H.i64_of_i32(1)}})

# `UOp.divide_exact` -- ops.py:1038-1047. AND CPYTHON's OWN `UOp.divide_exact` IS THE
# ORACLE.
#
# AND CPYTHON's ANSWERS, MEASURED AT THE PIN:
#   divide_exact(x, x)      = 1
#   divide_exact(x, 2)      = None   (`x` DOES NOT DIVIDE 2)
#   divide_exact(x, y)      = None
#   divide_exact(x*y, y)    = (mul 1 x)   -- THE CONSTANT IS STRIPPED BY
#                                `pop_const`, WHICH IS WHAT MAKES THE COUNTER `{x:1}`
#   divide_exact(x+y, y)    = None   (and `y` does not divide `x`, so the ADD's first
#                                SRC FAILS)
#   divide_exact(x*y, x)    = (mul 1 y)
#   divide_exact(x*2, x)    = 2      (THE CONSTANT COMES OUT)
#   divide_exact(x*2, 2)    = (mul x 1)

# THE `self IS v` ANSWER IS 1 -- A CONST WITH NO SRCS.
def t_de_same() -> Bool:
  +ar0 = Arena.empty()
  +fx = UOp.variable(ar0, "x", H.i64_of_i32(0), H.i64_of_i32(4), 1, S.weakint())
  +ar1 = Found.ar(fx)
  +d = UOp.divide_exact(ar1, Found.i(fx), Found.i(fx))
  +ga = Found.ar(Dq.f(d))
  Bool.and(Dq.ok(d), eq_op(Arena.op(ga, Found.i(Dq.f(d))), OpsCONST{}))

# the "v is a CONST and self does not divide it" answer is NONE.
def t_de_const_none() -> Bool:
  +ar0 = Arena.empty()
  +fx = UOp.variable(ar0, "x", H.i64_of_i32(0), H.i64_of_i32(4), 1, S.weakint())
  +ar1 = Found.ar(fx)
  +c2 = UOp.const(ar1, CInt{H.i64_of_i32(2)})
  +d = UOp.divide_exact(Found.ar(c2), Found.i(fx), Found.i(c2))
  Bool.not(Dq.ok(d))

# the `x*y DIVIDED BY y` answer is a MUL -- and the constant is stripped by
# `pop_const`, which is what makes the counter `{x:1}` and not `{x:1, 2:1}`.
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

# the `x*2 DIVIDED BY x` answer is the constant -- a CONST with no srcs -- and that is
# THE `pop_const` CONST HALF COMING OUT ALONE.
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
#   `Estimates` in `KernelInfo` -- PORTED 2026-10-30 as a FIELD, in
#     `renderer/estimates.bend`. What is NOT PORTED is the VALUE: upstream's
#     only writer is `codegen/__init__.py:446` and `do_estimates` is a WALL in
#     `codegen/kernel.bend`, so every `KernelInfo` the port builds carries
#     `estimates=None`.
#   `CustomFunction` -- PORTED 2026-10-03, at ops.py's own position (between
#     `OPAQUE_CALL_BODIES` and `CallInfo`), together with `Arg`'s `ACustom` arm,
#     `eq_customfunction` and `UOp.custom_function`. The old text here said it was
#     PORTABLE but unreachable and so would "land with" the P6 hcq2 work; it landed
#     without it, because `uop/spec.py:110`'s `isinstance(x.arg, CustomFunction)`
#     needs the datatype and `spec.bend`'s `sh_22` is stale until it has one. Being
#     P6 only ever described the CALLERS, never the type.
#     what is still open is the other half, and it is not optional: upstream moved
#     `CallInfo.dtype` into `CustomFunction.dtype`, so a CALL's return dtype now
#     lives on its CUSTOM_FUNCTION body (`dtype_from_uop`'s CALL arm is
#     `return src[0].dtype`). `CallInfo` here STILL HAS `dtype`, and it is still
#     read by `eq_callinfo` and by `uop/spec.bend`'s `arg_call`/`sh_23`. So the
#     re-cut is a SEPARATE change with its own blast radius, not a field delete:
#     `sh_23` compares a DECLARED dtype against the node's own, and under HEAD
#     there is no declared dtype to compare -- the CALL's dtype IS its body's. P3,
#     with `dtype_from_uop`.
#     MEASURED 2026-10-06, so the next reader does not have to re-derive it: the
#     eleven-site, seven-file delete is APPLIED AND GREEN in a scratch copy of this
#     tree, it moves `--graph loop`'s `arg` chunk to CPython's bytes, and it closes
#     HALF the row -- `dtype` and `shape` stay `?` because `fold.bend` never settles
#     that node, which is a second defect. See the `CallInfo` block above for the
#     `git log -S` pin, and `spec.bend`'s own `arg_call` comment for its stale half.
#   `UPat.custom_function(fn, kwargs)` -- ops.py:1509 upstream, still NOT PORTED. A
#     `PatternMatcher` rule constructor, so it lands with `uop/upat.py`.
#   `UOp.param_like(slot, name=None)` -- ops.py:1241 upstream. `name` was added so a
#     scalar argument can be bound by NAME while its slot and value stay out of the
#     schedule cache key. P6, with the hcq call sites that use it.
#   `UOp.contiguous_view()`'s new tail -- upstream now returns a BITCAST SLICE
#     (`b.src[0].flatten()[...]`) where the pin returned `(b.rtag(None), offset)`, and
#     it computes the offset with `strides_for_shape` instead of a
#     `pm_contiguous_view_offset` matcher. P3 with `symbolic.bend`; the matcher form is
#     NOT PORTED for the reason the pattern compiler is, below.
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
