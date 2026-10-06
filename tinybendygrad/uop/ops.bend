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
# ===========================================================================
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
# THREE THINGS THE LIST SAYS THAT A DIFF WOULD NOT.
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
#   * `runtime/support/hcq2.py:69,87` is `UOp.custom_function(name).call(...)` with
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
# range's arg prints as a name. `Ops.RANGE`'s arg is `(axis_type, axis_id)`, so
# the type is a field of the arg and has to be a datatype here; `Ops.name` is
# the same trick one level up.
#
# ===========================================================================
#
# REBASED ONTO `78d482262` ("range AxisType is first / delete REDUCE/UNROLL"),
# which is 53 files and the pin's hard blocker. Four upstream facts moved and all
# four are read by a CPython row now -- this block had NO CPython lane at all
# (`cpython=0`), which is how a wrong `AxisType.value` survived:
#
#   * UPSTREAM'S ORDER IS `DEVICE, GLOBAL, LOCAL, WARP, WEAK, LOOP, UPCAST,
#     PLACEHOLDER`. The pin was `DEVICE, GLOBAL, WARP, LOCAL, WEAK, REDUCE,
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
# ---------------------------------------------------------------------------
# THE ONE THING THIS BLOCK DOES NOT FIX, and it is a THEOREM rather than a choice.
#
# `AXIS_REDUCE` and `AXIS_UNROLL` are DELETED upstream but they are still CONSTRUCTED
# by six committed files, so they cannot be deleted here:
#     schedule/indexing.bend:1319          codegen/kernel.bend:401,:991
#     codegen/late.bend:902                codegen/opt/heuristic.bend:157,:160
#     codegen/opt/postrange.bend:214,:215,:292,:453,:457,:483,:675,:796,:799,:899,:933,:937,:959,:962
#     codegen/opt/search.bend:295,:393,:399
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
# ===========================================================================

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
# `match` ladders. UPSTREAM DROPS THE `REDUCE`/`UNROLL` ENTRIES and adds nothing, so
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

# ===========================================================================
# opt/__init__.py: `OptOps` and `Opt` (with its `arg`), MOVED DOWN from
# `codegen/opt/postrange.bend` because `KernelInfo` below CARRIES them and
# `postrange.bend` imports THIS file -- a file cannot import its own importer, so
# the types live at the bottom. `postrange.bend` reads them as `O.OPTOPS` /
# `O.OPT` / `O.SPL` / `O.OPTARG`; `search.bend` and `heuristic.bend` reach them
# through `postrange` and are unchanged.
# ===========================================================================
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
  KernelInfo{name: String, applied_opts: List<&2, OPT>, opts_to_apply: Maybe<&2, List<&2, OPT>>, beam: U32}

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
# `dtype: S.Dt` is a FOURTH FIELD UPSTREAM DOES NOT HAVE, and this comment used to
# read "IS read: by `dtype_from_uop`'s CALL arm and by `_shape`'s". THAT CITATION IS
# FALSE AND IT NAMES A FUNCTION AND A SHAPE, WHICH IS WHY IT LOOKED LIKE IT CONFIRMED
# THE FIELD. MEASURED:
#   * `tinygrad/uop/ops.py:130-132` is `case Ops.CALL:` / "a call has the dtype of its
#     body, void for opaque bodies" / **`return src[0].dtype`** -- it reads the BODY.
#     It never reads `CallInfo`.
#   * `git log -S'dtype: DType = dtypes.void' -- tinygrad/uop/ops.py` returns exactly
#     ONE commit, `6f4bfde23` "restrict allowed call bodies (#17925)", 2026-09-02 --
#     and that commit's hunk is `+  dtype: DType = dtypes.void`, so it ADDS the field.
#     `git show HEAD:tinygrad/uop/ops.py` has FIVE `CallInfo` fields and none is
#     `dtype`. **THE PORT IS PINNED TO A COMMIT UPSTREAM HAS SINCE MOVED PAST.**
#   * `tinygrad/uop/spec.py:112` at HEAD is `lambda x: isinstance(x.arg, CallInfo)` --
#     a pure TYPE test. `spec.bend`'s `arg_call` still answers HEAD's pre-`6f4bfde23`
#     `x.dtype is x.arg.dtype` half, so THAT citation is stale the same way.
# THE COST OF NOT KNOWING THIS IS MEASURED, and it is the corpus's only live `?`:
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

# ===========================================================================
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
#   (dims, DType, threads, tc_upcast_axes)   AWmma   WMMA arg
#   tuple[int, ...]         ATuple     PERMUTE arg (`movement.py:231`), UNSHARD arg
#                                     (`ops.py:691`: "the tuple of sharded axes, sorted")
#   -- and this is the WRONG SPELLING FOR A FLIP, which is `tuple[bool, ...]`:
#      `ops.py:428` asserts `all(isinstance(x, bool) for x in self.marg)` and
#      MEASURED on a fresh src `UOp(Ops.FLIP, src, (1, 0))` RAISES
#      `bad flip on (7, 3), (1, 0)` -- so the port can hold a shape CPython REJECTS,
#      and `graphcmp.bend`'s `g_flip` holds one (`O.ATuple{[1, 0]}`). The correct
#      type is a SEPARATE bool-carrying `Arg` variant, not this one narrowed,
#      because PERMUTE and UNSHARD really are ints. Five files construct or read a
#      FLIP's arg -- `fold.bend`'s `order_arg`, `schedule/prepare.bend:277`,
#      `mixin/movement.bend:993` and `:1533`, and `graphcmp.bend`'s `g_flip` and its
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
#                                     and for why `ABlob{n: U32}` was wrong.
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
  AWmma{dims: List<&2, U32>, dt: S.Dt, threads: U32, tc: List<&2, U32>}
  ATuple{ys: List<&2, U32>}
  AStr{s: String}
  AInk{ins: String, dt: S.Dt}
  AAllred{rop: Op, dev: S.Dev}
  ADev{dev: S.Dev}
  ABlob{bs: List<&2, U32>}
  AFloat{f: F32}
  ABad{}

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

# `shp` is the RANGE-arg tail shape, the component CPython's ucache key has and
# `ARange{ids, at}` does not. 0 = flat `(at, *ints)`; N>0 = `arg[1]` nested N
# times. It is NOT a field of `ARange`: a third field is `a ARange pattern with
# 3 fields` at every `case ARange{ids, at}`, and a new `Arg` variant is
# `expected : cases for …` in `render.bend`'s and `upat.bend`'s exhaustive
# matches. Both measured, `.agents/slop/arange-ucache/`. `UOp.new` stores 0, so
# every existing constructor is the flat reading.
type Arena is Data:
  Arena{nodes: List<&2, Node>, shp: List<&2, U32>}

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
# WHY NOT 0: `Arena.empty` spends arena index 0 on the bottom (ops.bend:1166), so
# `unique_num` starts at 1 and 0 is a REACHABLE real slot. `codegen/kernel.bend:269`
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

def KernelInfo.applied_opts(x: KernelInfo) -> List<&2, OPT>:
  match x:
    case KernelInfo{name, applied_opts, opts_to_apply, beam}: applied_opts

def KernelInfo.opts_to_apply(x: KernelInfo) -> Maybe<&2, List<&2, OPT>>:
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

def CustomFunction.name(x: CustomFunction) -> String:
  match x:
    case CustomFunction{name, dtype}: name

def CustomFunction.dtype(x: CustomFunction) -> S.Dt:
  match x:
    case CustomFunction{name, dtype}: dtype
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
# (Maybe, List) a four-arm ladder. Arg has nineteen constructors, so its 19x19 is
# a nested match: first on `x`, then a two-arm ladder on `y` inside each arm, with
# `x`'s own fields passed in as parameters because an arm may not see them.
# That is the same shape spec.bend uses in `Shape.max_dim`, and it is why
# `eq_arg` is twenty defs and not three hundred and sixty-one arms.
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
          eq_opt_pynest(val, w2)))))))))))))

def eq_kernelinfo(x: KernelInfo, y: KernelInfo) -> Bool:
  match x y:
    case KernelInfo{name, applied_opts, opts_to_apply, beam} KernelInfo{n2, o2, p2, b2}:
      Bool.and(String.eq(name, n2), Bool.and(eq_opts(applied_opts, o2),
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

# IEEE EQUALITY IS CORRECT HERE, AND `F32.bits` WOULD BE A REGRESSION. `eq_const.CFloat`
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
# VALUE-BASED PORT CAN REPRODUCE is the SAME NaN object twice, which interns in
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
    case AStr{s}: eq_arg.AStr(y, s)
    case AInk{ins, dt}: eq_arg.AInk(y, ins, dt)
    case AAllred{rop, dev}: eq_arg.AAllred(y, rop, dev)
    case ADev{dev}: eq_arg.ADev(y, dev)
    case ABlob{bs}: eq_arg.ABlob(y, bs)
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

def UOp.new.shp.of(+ar: Arena, +made: Arena, +op: Op, +src: List<&2, U32>, +arg: Arg, +tag: Tag, depth: U32) -> Found:
  Found{made, UOp.of.shp(made, op, src, arg, tag, depth)}

def UOp.new.shp(+ar: Arena, +op: Op, +src: List<&2, U32>, +arg: Arg, +tag: Tag, +depth: U32) -> Found:
  UOp.new.shp.of(ar, UOp.make.shp(ar, op, src, arg, tag, depth), op, src, arg, tag, depth)

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

# `where` -- mixin/elementwise.py:426, `self.alu(Ops.WHERE, x, y)`, i.e.
# `UOp(Ops.WHERE, src=(cond, x, y))` with `cond` FIRST because `alu` puts `self` at src[0].
def UOp.where(ar: Arena, +cond: U32, +x: U32, +y: U32) -> Found:
  UOp.new(ar, OpsWHERE{}, [cond, x, y], ANone{}, TNone{})

# `valid` -- ops.py:664. `cond.where(self, self.const_like(Invalid))`, and for the CONST case
# `const_like` IS `UOp.const(Invalid)` -- no `_shape` to expand into, so no EXPAND. The shaped case
# needs `_mop` and `_shape`, which is why the ROWS here are consts.
#
# THE ARENA IS THE CALLER'S AND IT MUST HOLD ALL THREE INDICES, which cost me a wrong diagnosis
# earlier: I passed the ORIGINAL arena after siblings had grown it, read `ANone{}` back, and wrote
# down that the constructor could not be verified. It can. Each `UOp.const` answers a node in the
# GROWN arena -- the rule my own notes record as "mint derived consts in the result's arena".
def UOp.valid_of(ar: Arena, +self: U32, +inv: U32, +cond: U32) -> Found:
  UOp.where(ar, cond, self, inv)

# backedge -- ops.py:620. `UOp(Ops.BACKEDGE, src=(self, loop, cond))`
def UOp.backedge(ar: Arena, +self: U32, +loop: U32, +cond: U32) -> Found:
  UOp.new(ar, OpsBACKEDGE{}, [self, loop, cond], ANone{}, TNone{})

# after -- ops.py:621. `UOp(Ops.AFTER, src=(self,)+src, **kwargs) if len(src) else self`
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

# range -- ops.py:642. `UOp(Ops.RANGE, src=(sint_to_uop(end, dtype),)+src,
# arg=(axis_type, axis_id), **kwargs)`. `end` is already a UOp index here,
# because `sint_to_uop` is `UOp.const(x, dtype)` and that is the CONST above.
#
# ---------------------------------------------------------------------------
# THE ARG ORDER IS FLIPPED AND `ARange` IS NOT -- THE COUPLING, STATED EXACTLY.
#
# Upstream `arg=(axis_type, axis_id)` and the pin's was `arg=(axis_id, axis_type)`.
# `ARange` is this file's SPLIT of that tuple, so faithful would be
# `ARange{at, ids}`. It is `ARange{ids, at}` and that is a DELIBERATE wall, because
# `ARange` is read and written POSITIONALLY by eleven committed files:
#     schedule/rangeify.bend:744,2283,2581,3001,3005,3013   schedule/multi.bend:684
#     schedule/indexing.bend:628,633     codegen/late.bend:910,1000,1573,1796-1798
#     uop/render.bend:588,792,797,833,841,1848,1934          uop/spec.bend:348,360
#     uop/fold.bend:2288,2300            uop/validate.bend:1601
#     uop/fold2_work.bend:2280,2292      uop/fold_mm_work.bend:2280,2292
#     uop/upat.bend:406                   engine/realize.bend:1345,1623
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
# THESE ARE THE SWAPPED PAIR the rebase moved, and the gate asks CPython's PROPERTY
# (`u.axis_id`, `u.axis_type`) rather than re-deriving either slice, so the row follows
# the tree instead of encoding a reading of the diff. Measured: for an arg of length
# TWO -- which is every `UOp.range` and every `UOp.loop` -- the pin's `arg[0:-1]` and
# upstream's `arg[1:]` are the SAME slice, so those four fixtures answer identically on
# both trees. Only a three-element arg separates them, and `rng_twoid` is that fixture.
#
# THE ROWS READ THESE DEFS AND NOT THE FIXTURE'S LITERALS. An earlier version of
# `t_rng_row` printed the `ids` it had been handed, which left these two defs with no
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
# arg through here. Adding one means a depth-aware `AxIds` (ops.bend:4881, one def,
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
# ===========================================================================

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

# ===========================================================================
# THE BACKWARD SLICE -- ops.py:280, :286, :289. THREE DEFS, ONE WALK.
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
# ===========================================================================

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

# `{self:None, **self.backward_slice}` -- a dict literal whose only addition is
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
#   * A RULE MAY READ THE ARENA AS OFTEN AS IT LIKES. A closure cannot take a
#     shared argument -- there is no spelling of one in a function type -- so an
#     interpreter rule could not receive `+Arena`. A def can.
#   * A RULE'S CAPTURES ARE ITS OWN PARAMETERS. No store, no `setdefault`, no
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
# ===========================================================================

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


# ===========================================================================
# THE PASS. `pdict.get(uop.op, [])` as a scan over a flat list in insertion
# order. Python's dict preserves that order and `Map` here is string-keyed while
# `Ops.value` gives a number, so a linear scan is both the faithful order and the
# honest structure.
# ===========================================================================
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


# ===========================================================================
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
# `(ctx: List<&2, U32>, ar: Arena, self: U32)` and returns `Maybe<&2, U32>`.
# `ctx` is a `List<&2, U32>` here, which is the wall-passing shape from
# `walk_rewrite`; the engine threads it through the dispatch so the rule body
# can read it. The codegen pipeline eventually passes a typed `CTX` record
# and the `List<&2, U32>` becomes the new record's first projection.
# ===========================================================================

# the rule bodies. The default for every rule is "no rewrite" (`None{}`).
# The no-op `pm_rewrite_m` body for a SINK is `Some(self)` so the engine
# does not have to special-case SINK in the rebuild step.

def pm_r_sink_m(+ctx: List<&2, U32>, ar: Arena, self: U32) -> Maybe<&2, U32>:
  Some{self}

def pm_r_cast_m(+ctx: List<&2, U32>, +ar: Arena, +self: U32) -> Maybe<&2, U32>:
  # the rule does not transform a CAST/BITCAST; it just claims it for
  # tables whose body is identity. The real `pm_dtype_decomps` /
  # `pm_move_gates_from_index` will replace this.
  Some{self}

def pm_r_noop_m(+ctx: List<&2, U32>, ar: Arena, self: U32) -> Maybe<&2, U32>:
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

def pm_r_param_m.go(slot: U32, +ctx: List<&2, U32>) -> Maybe<&2, U32>:
  match slot:
    case 0: List.get(&2, U32, ctx, U32.to_nat(0))
    case 1: List.get(&2, U32, ctx, U32.to_nat(1))
    case _: None{}

def pm_r_param_m(+ctx: List<&2, U32>, +ar: Arena, +self: U32) -> Maybe<&2, U32>:
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
def pm_r_alloc_m.at(+ctx: List<&2, U32>, n: Nat) -> Maybe<&2, U32>:
  match ctx:
    case Nil{}: None{}
    case h <> t:
      match n:
        case 0n: Some{h}
        case 1n+p: pm_r_alloc_m.at(t, p)

def pm_r_alloc_m(+ctx: List<&2, U32>, +ar: Arena, +self: U32) -> Maybe<&2, U32>:
  pm_r_alloc_m.at(ctx, 2n)

# ===========================================================================
# THE OPS.PY RULE TABLES -- ops.py:1896, 1897, 1904, 1907. These four are the
# WHOLE of `PatternMatcher` surface in ops.py, and until now `pm_dispatch_m`
# could reach none of them: it answered three placeholder bodies (SINK, NOOP,
# CAST) and codegen's two. `engine/realize.bend:1072-1080` records the wall this
# creates -- "a `PMEntrys` built in THIS file can only ever reach those three
# bodies" -- and the cost is that eleven files in this tree each grew their own
# scan. What follows puts the four in the table that already exists.
#
# `ops.py:1602-1606` is where a `PMEntry` comes from, and it is three lines:
#
#     entry: list = [p, None, p.early_reject]
#     entry[1] = upat_deferred_compile(p, fxn, entry) if compiled else upat_interpret(p, fxn)
#     for uop in p.op: self.pdict.setdefault(uop, []).append(entry)
#
# `p.early_reject` is field three and `entry[1]` -- the compiled function -- is
# the TAG. `for uop in p.op` is the fan-out that makes `PMEntry.ops` a CLAIMED
# SET, and it is `ops.py:1614`'s `self.pdict.get(uop.op, [])`, which `pm_claimed`
# already reads.
#
# ALL FOUR REJECT SETS ARE EMPTY, and that is ops.py's arithmetic rather than a
# shortcut. `ops.py:1480-1483` is
#
#     upat_match = [src] if isinstance(src, UPat) else ([] if src is None else self.src[0])
#     self.early_reject = {pp.op[0] for pp in upat_match if pp.op is not None and len(pp.op) == 1}
#
# and all four patterns are built with `src=` OMITTED, so `src is None`, so
# `upat_match == []`, so `early_reject == set()`. `ops.py:1617`'s
# `if not early_reject.issubset(ler): continue` therefore never skips any of
# them, and `PMEntry.rej` is `Nil{}` four times. A non-empty reject set here
# would be an invention.
# ===========================================================================

# `tuple(Ops)` -- the claim of ops.py:1896's `UPat(tuple(Ops), name="x")` and of
# ops.py:1904's `UPat(GroupOp.All, name="x")`. `GroupOp.All` IS `set(Ops)`
# (tinygrad/uop/__init__.py:135), measured by CPython: `len(tuple(Ops))` is 77
# and `GroupOp.All == set(Ops)` is `True`. So one list serves both rules, and it
# is the same 77 for both.
#
# `pm_claimed` SCANS (`op_in`), so the ORDER IS FREE. This is Python's
# enumeration order only so the literal can be diffed against CPython entry by
# entry; `all_ops_n` in `.agents/slop/lintable/03-PROBE.md` re-measures both the
# count and the set against `from tinygrad.uop import Ops`.
def all_ops() -> List<&2, Op>:
  [OpsSPECIAL{} OpsBUFFER{} OpsALLOC{} OpsNOOP{} OpsREWRITE_ERROR{} OpsPARAM{} OpsCALL{} OpsPROGRAM{} OpsLINEAR{} OpsSOURCE{} OpsBINARY{},
   OpsSINK{} OpsAFTER{} OpsGROUP{} OpsSTACK{} OpsGETADDR{} OpsINDEX{} OpsSHRINK{} OpsLOAD{} OpsSTORE{} OpsWMMA{} OpsCAST{},
   OpsBITCAST{} OpsEXP2{} OpsLOG2{} OpsSIN{} OpsSQRT{} OpsRECIPROCAL{} OpsNEG{} OpsTRUNC{} OpsADD{} OpsMUL{} OpsSHL{},
   OpsSHR{} OpsCDIV{} OpsMAX{} OpsCMOD{} OpsCMPLT{} OpsCMPNE{} OpsCMPEQ{} OpsXOR{} OpsOR{} OpsAND{} OpsTHREEFRY{},
   OpsSUB{} OpsFDIV{} OpsPOW{} OpsFLOORDIV{} OpsFLOORMOD{} OpsWHERE{} OpsMULACC{} OpsBARRIER{} OpsRANGE{} OpsIF{} OpsEND{},
   OpsENDIF{} OpsBACKEDGE{} OpsCONST{} OpsCUSTOM{} OpsCUSTOMI{} OpsINS{} OpsCONTIGUOUS_BACKWARD{} OpsDETACH{} OpsSTAGE{} OpsCOPY{} OpsMSELECT{},
   OpsMSTACK{} OpsCUSTOM_FUNCTION{} OpsRESHAPE{} OpsPERMUTE{} OpsEXPAND{} OpsPAD{} OpsFLIP{} OpsUNSHARD{} OpsREDUCE{} OpsALLREDUCE{} OpsPYLITERAL{}]

# `x.tag is not None` -- the guard of ops.py:1904's
# `lambda x: x.replace(tag=None) if x.tag is not None else None`. `Tag`'s bottom
# is `TNone{}` (this file's `type Tag is Data`, whose five constructors are
# TNone/TBool/TStr/TInt/TTuple), so Python's `None` IS `TNone{}` and the guard is
# the other four. The same shape as `eq_tag.TNone` above, which is why it is a
# separate def and not a fold: a fold over the constructors is the mutual
# recursion the `Tag` header says it would force on `eq_tag`.
def tag_is_none(t: Tag) -> Bool:
  match t:
    case TNone{}: True{}
    case _: False{}

# TAG 40 -- ops.py:1907. `pm_drop_after`:
#     pm_drop_after = PatternMatcher([(UPat(Ops.AFTER, name="a"), lambda a: a.src[0])])
# The body is `a.src[0]`, which is an EXISTING node, so this family answers
# `Maybe<&2, U32>` and needs no arena of its own -- it is the one ops.py rule in
# this file that a rebuilding-rule-free table can already carry.
#
# `ctx` is unused because ops.py's lambda takes one and does not read it. The
# claim (`OpsAFTER`) is `PMEntry.ops`, not a guard in here.
def pm_r_drop_m(+ctx: List<&2, U32>, +ar: Arena, +self: U32) -> Maybe<&2, U32>:
  Some{Arena.src(ar, self, 0)}

# TAG 42 -- ops.py:1897. `_pm_resolve_params`:
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

def pm_r_rp_m.at(+ctx: List<&2, U32>, slot: U32) -> Maybe<&2, U32>:
  match slot:
    case 4294967295: None{}
    case _: List.get(&2, U32, ctx, U32.to_nat(slot))

def pm_r_rp_m(+ctx: List<&2, U32>, +ar: Arena, +self: U32) -> Maybe<&2, U32>:
  pm_r_rp_m.at(ctx, pm_r_rp_m.slot(Arena.arg(ar, self)))

# dispatch by tag. Tags 0/1/2 are the same as `pm_dispatch.go`. Tags 3/4
# are the codegen pipeline's `pm_post_sched_cache` rules and read `ctx`.
# Tags 40/42 are ops.py's own, above.
def pm_dispatch_m.go(tag: U32, ar: Arena, self: U32, +ctx: List<&2, U32>) -> Maybe<&2, U32>:
  match tag:
    case 0: pm_r_sink_m(ctx, ar, self)
    case 1: pm_r_noop_m(ctx, ar, self)
    case 2: pm_r_cast_m(ctx, ar, self)
    case 3: pm_r_param_m(ctx, ar, self)
    case 4: pm_r_alloc_m(ctx, ar, self)
    case 40: pm_r_drop_m(ctx, ar, self)
    case 42: pm_r_rp_m(ctx, ar, self)
    case _: None{}

def pm_dispatch_m(tag: U32, ar: Arena, self: U32, ctx: List<&2, U32>) -> Maybe<&2, U32>:
  pm_dispatch_m.go(tag, ar, self, ctx)

def pm_try_m.go(ok: Bool, tag: U32, ar: Arena, self: U32, +ctx: List<&2, U32>) -> Maybe<&2, U32>:
  match ok:
    case True{}: pm_dispatch_m(tag, ar, self, ctx)
    case False{}: None{}

def pm_try_m.of(claimed: Bool, early: Bool, tag: U32, ar: Arena, self: U32, ctx: List<&2, U32>) -> Maybe<&2, U32>:
  pm_try_m.go(Bool.and(claimed, early), tag, ar, self, ctx)

def pm_try_m(ts: PMEntrys, +ar: Arena, +self: U32, +e: PMEntry, +ctx: List<&2, U32>) -> Maybe<&2, U32>:
  pm_try_m.of(pm_claimed(PMEntry.ops(e), ar, self), pm_early(ts, ar, self, PMEntry.rej(e)), PMEntry.tag(e), ar, self, ctx)

# `pm_scan_m` is a first-wins fold over the rule list. First `Some` wins;
# later `Some`s are dropped. The accumulator is `Maybe<&2, U32>` and the
# identity is `None{}`. The order is the table order, which IS Python's
# `PatternMatcher` order (Python's `pm.rewrite` returns the first non-None
# result).
def pm_scan_m(+ts: PMEntrys, +ar: Arena, +self: U32, todo: List<&2, PMEntry>, acc: Maybe<&2, U32>, +ctx: List<&2, U32>) -> Maybe<&2, U32>:
  match todo:
    case Nil{}: acc
    case e <> t:
      match acc:
        case Some{value}: acc
        case None{}: pm_scan_m(ts, ar, self, t, pm_try_m(ts, ar, self, e, ctx), ctx)

def pm_rewrite_m(+ts: PMEntrys, +ar: Arena, +self: U32, +ctx: List<&2, U32>) -> Maybe<&2, U32>:
  pm_scan_m(ts, ar, self, PMEntrys.es(ts), None{}, ctx)

# ===========================================================================
# TWO MORE TABLES, AND EACH EXISTS BECAUSE OF A TYPE, NOT A PREFERENCE.
#
# ONE TABLE CANNOT HOLD ALL FOUR of ops.py's rules, and the blocker is not
# linearity. `ops.py:1888` types the pass's `ctx` as `ctx=None` and each lambda
# reads whatever shape it likes off it, so Python has no reason for the four to
# agree. A Bend parameter has a type, so:
#
#     _pm_resolve_params   ctx[p.arg.slot]      -> List<&2, U32>   tag 42, above
#     _substitute          ctx.get(x)           -> Map<&2, U32>    tag 43, `_sub`
#     remove_all_tags      (ctx unused)         -> List<&2, U32>   tag 41, `_f`
#     pm_drop_after        (ctx unused)         -> List<&2, U32>   tag 40, above
#
# And there is a second, sharper blocker, which is the one `pm_r_alloc_m` above
# already paid for: `remove_all_tags` MINTS. `ops.py:253-257`'s `replace` returns
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
# ===========================================================================

# TAG 41 -- ops.py:1904. `remove_all_tags`:
#     remove_all_tags = PatternMatcher([(UPat(GroupOp.All, name="x"), lambda x: x.replace(tag=None) if x.tag is not None else None)])
#
# `ops.py:253-257` is what `replace(tag=None)` is:
#     new_args = (kwargs.pop("op", self.op), kwargs.pop("src", self.src), kwargs.pop("arg", self.arg), kwargs.pop("tag", self.tag))
#     if (self.op, self.src, self.arg, self.tag) == new_args: return self
#     return UOp(*new_args)
# so the port is the node rebuilt with all four of ITS OWN fields and `TNone{}` in
# the tag slot -- which is `ops.bend:6594`'s inline `replace`, already written.
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
# found it: those two rows are written from ops.py:1904's guard -- "True means the
# node HAS a tag, so it gets a replacement" -- and the implementation answered the
# other way round, so the row and the code disagreed and the ROW was right about
# what the name claims. A name that is the negation of the value it holds is the
# same defect as a shadowed binder with better manners: both compile, both report
# their flag correctly, and both mislead whoever writes the next mutation.
def pm_r_tag_m.of(untagged: Bool, made: Found) -> Maybe<&2, Found>:
  Bool.pick(Maybe<&2, Found>, untagged, None{}, Some{made})

def pm_r_tag_m(+ctx: List<&2, U32>, +ar: Arena, +self: U32) -> Maybe<&2, Found>:
  pm_r_tag_m.of(tag_is_none(Arena.tag(ar, self)),
    UOp.new(ar, Arena.op(ar, self), Arena.srcs(ar, self), Arena.arg(ar, self), TNone{}))

# TAG 43 -- ops.py:1896. `_substitute`:
#     _substitute = PatternMatcher([(UPat(tuple(Ops), name="x"), lambda ctx,x: ctx.get(x,None))])
#
# The ctx is `dvars: dict[UOp, UOp]` (`ops.py:530`), so it is keyed by the NODE
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
# THE TAG IS GLOBAL AND THE TABLE IS NOT. Every `PMEntry` in the tree numbers its
# own rules from 0 -- `codegen/__init__.bend:318`'s tag 0 is `_pm_resolve_params`
# and `engine/realize.bend:1150`'s tag 0 is `pm_flatten_linear` -- because the
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
# DECLARATION ORDER IS THE OTHER HALF OF THAT. `pm_rewrite_f` is LAST because a
# def may only call defs declared ABOVE it, and putting it first fails with
# "expected : a filled definition" -- measured, not remembered.
#
# `.of`/`.go` is not decoration. `pm_try_f.of` computes `Bool.and(claimed, early)`
# and HANDS IT OVER; `pm_try_f.go` matches the parameter. Folding the `match`
# into `.of` is refused -- "a match cannot scrutinize a computed value" -- and
# that is measured here, not remembered: it was the first compile of this block.
def pm_try_f.go(ok: Bool, +ar: Arena, +self: U32, +ctx: List<&2, U32>) -> Maybe<&2, Found>:
  match ok:
    case True{}: pm_r_tag_m(ctx, ar, self)
    case False{}: None{}

def pm_try_f.of(claimed: Bool, early: Bool, +ar: Arena, +self: U32, +ctx: List<&2, U32>) -> Maybe<&2, Found>:
  pm_try_f.go(Bool.and(claimed, early), ar, self, ctx)

def pm_try_f(ts: PMEntrys, +ar: Arena, +self: U32, +e: PMEntry, +ctx: List<&2, U32>) -> Maybe<&2, Found>:
  pm_try_f.of(pm_claimed(PMEntry.ops(e), ar, self), pm_early(ts, ar, self, PMEntry.rej(e)), ar, self, ctx)

def pm_scan_f(+ts: PMEntrys, +ar: Arena, +self: U32, todo: List<&2, PMEntry>, acc: Maybe<&2, Found>, +ctx: List<&2, U32>) -> Maybe<&2, Found>:
  match todo:
    case Nil{}: acc
    case e <> t:
      match acc:
        case Some{value}: acc
        case None{}: pm_scan_f(ts, ar, self, t, pm_try_f(ts, ar, self, e, ctx), ctx)

def pm_rewrite_f(+ts: PMEntrys, +ar: Arena, +self: U32, +ctx: List<&2, U32>) -> Maybe<&2, Found>:
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

# ===========================================================================
# THE DISPATCH. `upat.py` emits a closure; Bend has no first-class functions, so
# the tag selects a top-level def. THIS is the mechanism, and it is why the table
# is `Data` rather than a list of closures.
#
# `UPatCompileError` -- ops.py:1588 raises when a pattern's source cannot be read,
# because the compiler reflects on the CALLING FRAME to find the pattern's
# location. There is no frame here, so a rule that cannot be compiled has no
# representation at all: it is a missing `case` below, and the honest response is
# a missing def rather than a runtime error.
# ===========================================================================



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

# ===========================================================================
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
# ---------------------------------------------------------------------------
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
# WHAT WORKS IS THE FUEL WITH THE STOP ENCODED IN THE NODE. One def, one
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
# ===========================================================================

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
# `after_ok` IS A PARAMETER AND BOTH ITS VALUES ARE ROWS (`s5_hbi_*` and
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
    case _: False{}

def UOp.has_buffer_identity(fuel: Nat, +after_ok: Bool, +ar: Arena, +self: U32) -> Bool:
  match fuel:
    case 0n: UOp.has_buffer_identity.term(Arena.op(ar, self))
    case 1n+p: Bool.pick(Bool, UOp.has_buffer_identity.walk(after_ok, ar, self),
      UOp.has_buffer_identity(p, after_ok, ar, Arena.src(ar, self, 0)),
      UOp.has_buffer_identity.term(Arena.op(ar, self)))

# ===========================================================================
# THE MOVERS -- ops.py:624 `barrier`, :679 `bufferize`, :680 `allreduce`,
# :772 `mselect`, :707 `sharding`, :685 `split_uop`, :1893 `sint_to_uop`,
# :1901 `gate_kernel_sink`. Eight defs, and each is a `UOp(...)` call or a fold
# with no dtype and no shape in it, which is why they are here and the rest of
# ops.py:501-1928 is not.
#
# `**kwargs` IS GONE, as everywhere else in this file: Python threads it through
# thirty of these and forwards it to the constructor, so it carries op/arg/tag.
# Bend has no kwargs, so the three constructor fields are spelled at the call
# site and the sugar that only forwards them collapses to the call. `barrier`
# and `bufferize` are that collapse, and they are here anyway because the ARG
# they choose is a decision, not a forwarding: `bufferize` answers `ABad{}` where
# `barrier` would answer `ANone{}`, and a row that prints the node's op and src
# sequence is what holds both.
# ===========================================================================

# `bufferize` -- ops.py:679. `UOp(Ops.STAGE, src=(self,)+args, **kwargs)`, and
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
# an INT -- a shard index into a multi-device tensor. `ABlob` is the arena's existing
# "a bare number in the arg" arm, and reusing it is the honest choice over minting a new
# one: MSELECT's arg is a number and nothing else reads it. Since `ABlob` now holds BYTES
# rather than a length, the int is the ONE-BYTE blob `[k]` -- which is injective in `k`,
# so two different shard indices are still two different keys, and it is what the key
# needs since `eq_arg.ABlob` reads content. The op is in the key too, so an MSELECT's
# `[k]` can never collide with a BINARY's bytes.
# WALL(p3) ops.py:201 -- BLOCKED ON A CASE THAT HAS NOT ARISEN, and the trigger is written down.
# `type(arg)` in `ops.py:201` separates an `int` arg from a `bytes` one; `eq_arg` has no such arm.
# The port does not need one TODAY: `ABlob` holds BYTES rather than a length, so an MSELECT's `[k]`
# is injective in `k` (two shard indices stay two keys) and the op is in the key too, so it cannot
# collide with a BINARY's bytes. IF A LATER UNIT MUST TELL AN `int` FROM A `bytes` ON ONE NODE,
# that is a NEW `Arg` arm and `eq_arg` grows an arm with it.
def UOp.mselect(ar: Arena, +self: U32, k: U32) -> Found:
  UOp.new(ar, OpsMSELECT{}, [self], ABlob{[k]}, TNone{})

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

# ---------------------------------------------------------------------------
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
# ---------------------------------------------------------------------------
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
# THE TWO LISTS ARE PARAMETERS AND NOT THE RECORD, and that is a MEASURED wall
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

# `sint_to_uop` -- ops.py:1893. `UOp.const(x, dtype=dtypes.weakint)`, and the
# whole of it is that a `sint` is either already a UOp or a literal CONST. The
# port's `Sint` is exactly that union (`SI{i64}` | `SU{uop}`), so the def is the
# two arms and nothing else: the `SU` arm is the node itself and the `SI` arm
# mints a weakint CONST. This is the def `UOp.range` and `UOp.special` would take
# a `Sint` from, and it is why those two take a `U32` today.
def UOp.sint_to_uop(ar: Arena, s: Sint) -> Found:
  match s:
    case SU{u}: Found{ar, u}
    case SI{i}: UOp.new(ar, OpsCONST{}, Nil{}, APy{CInt{i}}, TNone{})

# `gate_kernel_sink` -- ops.py:1901. Three arms, two of them NEGATIVE tests, and
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

# ===========================================================================
# ops.py:1-500. WHERE EACH NAME ACTUALLY LIVES NOW.
#
# This block used to be nineteen bare `# TODO(p3)` lines and ELEVEN of them were
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
# ===========================================================================

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
# TODO(p3) ops.py:74  def srender
#   `x.render()` is render.bend's and `str(x)` is its `const_repr`. Both live in
#   the file that imports this one, so the two-arm dispatch cannot be written here.
# TODO(p3) ops.py:93  def sym_infer
#   `exec` in `_sym_fxn` builds Python source from the graph and runs it in a
#   namespace of `max/cdiv/cmod/floordiv/floormod/bitcast/dtypes`. Bend has no
#   `eval`, so this needs a C effect that compiles a lambda or a tree-walking
#   interpreter. P3/P6.
# WALL(p3) ops.py:219  def __init__ -- BLOCKED. STORE A FUNCTION IN A DATA FIELD -- `recursive_property.__init__` keeps `self.fxn`. The
#   port's own note at the `t_*` block says a function value in a FIELD forces `Type`, not
#   `Data`, MEASURED. (A function as a PARAMETER is fine -- `bend guide:69` says functions may
#   be stored, passed and returned, and `Maybe.map` already takes one.)
# TODO(p3) ops.py:224  def __get__
#   `recursive_property` stores a FUNCTION in a record field (`self.fxn = fxn`),
#   and a function value in a field forces `Type`, not `Data` -- measured, and the
#   reason the rule tables in this file are linear. The `__get__` half is the memo
#   the header's point 5 drops, and its GATE is `self.nm not in node.__dict__`:
#   a memo-less port cannot answer that, because the predicate is vacuously true
#   for every node and the "gate" would visit the whole slice unconditionally.
# WALL(p3) ops.py:248  def __del__ -- BLOCKED. NO GARBAGE COLLECTOR TO CALL IT. `bend guide:646` -- "values are affine, a `match` frees
#   the node it opens" -- so there is no `__del__` hook and nothing for it to remove itself
#   from. The `ucache` it deletes from is Python's, and this port's interner is
#   `intern.find`'s direct comparison, not a table a node has to leave.
#   Refcount-driven eviction from `ucache`. The arena is monotone, so nothing is
#   ever evicted and there is nothing to port.
# WALL(p3) ops.py:251  def __reduce__ -- BLOCKED. THE PICKLE PROTOCOL. `return UOp, (op, src, arg, tag, metadata)` is a `__reduce__`: an
#   instruction to Python's `pickle`. Nothing in the port serialises a live UOp, so there is
#   no protocol to implement.
#   Pickling. A `U32` index and an `Arena` are not picklable objects, and this
#   file has no process boundary to pickle across.
# TODO(p3) ops.py:269  def key
#   `hashlib.sha256` over `str((op, dtype, arg))` and the srcs' keys concatenated.
#   Two walls: the digest is a C effect (`tinygrad/runtime/`'s), and the string
#   half reads `dtype`, which is `fold.bend`'s -- so neither half is writable here.
# WALL(p3) ops.py:292  def _bool_slice -- BLOCKED. NEEDS `fold`'s WALK AND A dtype PREDICATE, so it lives DOWNSTREAM of this file like
#   `_eval`, `param_noshape` and `wk_is_virtual` do -- `dt_is_bool` is in `mixin/dtype.bend`
#   and this file cannot import it (`ops.bend:87`). Its only consumer is a marker of its own:
#   `symbolic.bend:3054` records that `fold_where_closure` needs `bool_slice` AND
#   `substitute`, so porting this alone closes nothing downstream. **THE INTERNING DOES MAKE
#   IT CHEAPER THAN CPYTHON'S**: two structurally equal nodes share an arena index, so the
#   `frozenset[UOp]` is a deduped index list and needs no hash.
# TODO(p3) ops.py:295  def bool_slice
#   A `recursive_property` over the srcs, gated on `self.dtype is dtypes.bool`.
#   `dtype` is `fold.bend`'s, so both halves belong to the worklist beside it; and
#   `bool_slice`'s `| {self}` is a self-reference the fold has to add OUTSIDE its
#   own memo, which is what Python's comment above the property says.
# WALL(p3) ops.py:324  def tuplize -- BLOCKED. THE MECHANISM IS REPLACED, NOT MISSING. `tuplize` builds `(op.value, repr(arg), dtype, *(src
#   tuplize))` to KEY CPython's `ucache`; this port's interner is `intern.find`, a direct
#   comparison over `Arena.nodes`, so there is no hash table for a key to serve. Its two
#   consumers are outside ops.py anyway -- `codegen/late/linearizer.py:36` (a sort) and
#   `uop/symbolic.py:225` (a rewrite rule) -- and neither is ported.
#   `_UOpTuple((op.value, repr(arg), self.dtype) plus every src's tuplize)`:
#   `dtype` again, plus a `recursive_property` over the srcs, plus the sort it
#   feeds. `repr(arg)` is render.bend's `arg_repr`, so this is three files deep.
# TODO(p3) ops.py:459  def shard_shape
# TODO(p3) ops.py:465  def max_shard_shape
#   `shard_shape` reads `self.device` (fold), `self.axis` (fold) and `self.shape`
#   (fold), and `max_shard_shape` is `to_max_shape(shard_shape)`, a fold over a
#   `Sint` list. Every input is the worklist's, so these are fold.bend's rows;
#   `schedule/multi.bend` is the caller and it inlines what it can today.
# PORTED -- `ops.py:481 _ranges` and `ops.py:495 ranges` are `fold.bend`'s
# `Ranged` / `UOp.ranges` (fold.bend:4372), 12 `rg_*` rows byte-identical to
# CPython. The reason these two carried for a month -- "Dict set algebra over the
# fold's memo" -- was wrong: the arena interns, so `dict[UOp, None]` IS a list
# with a membership test, and `ended_ranges` is ported too (fold.bend:4059).
# TODO(p3) ops.py:495  def ranges
#   Dict set algebra over the fold's memo: union every src's ranges, then `pop` the
#   ones the ended ranges close. The wall is named where it is HIT --
#   `schedule/rangeify.bend:189`, whose `rf_in_ranges` is the standing stub.



# TODO(p3) ops.py:511  def simplify
#   # *** uop evaluation ***

# DONE(p3) ops.py:92 def ssimplify -- `ssimplify_of` and `UOp.ssimplify_val` /
#   `UOp.ssimplify_is_val`, with `cval_arg` (written for `pop_const`) as the value reader. Gated at
#   `gates/ops-core-gate.py` in SIX rows over THREE fixtures, and the third fixture is the one
#   that makes the other two mean something: a CAST of a PARAM satisfies neither of CPython's
#   conditions, so CPython hands the NODE back -- a THIRD answer, neither a value nor an absence.
#
#   IT DOES NOT NEED `simplify`, which is the finding rather than a convenience. `simplify` is a
#   documented wall in this file (`ops.py:511`, "*** uop evaluation ***") and 3,679 lines of
#   partial symbolic work sit behind it, so anything that truly required a rewriter would be
#   stuck on the largest subsystem here. But a CONST is already reduced, so `simplify` is the
#   IDENTITY on it, and the CAST arm's test is a SHAPE test on the node rather than a rewrite.
#   What is left out is `ret.dtype.const(...)` -- the dtype round trip -- and `wk_dt` already
#   answers a node's dtype, so the value half is the whole of the discriminating claim.
#   Planted: a reader that answers `none` for everything fails `ss_const_val` and
#   `ss_cast_const_val` and nothing else.

# DONE(p3) ops.py:521 def _eval -- AND IT WAS MISFILED HERE, WHICH IS THE FINDING. `_eval` needs
#   the node's dtype AND its two bounds, and this file imports only `Base`, `helpers` and
#   `LAWS/spec`, while `UOp.vmin`/`vmax` are in `fold.bend` and the node-level dtype reader is in
#   `weak.bend` -- and BOTH of those import `ops.bend`. So the def sits DOWNSTREAM of the file
#   that wanted it: an import edge, not a language limit, and the same relocation
#   `wk_commit_dtype` already got. It is now `wk_eval_int` / `wk_eval_float` / `wk_eval_bool` in
#   `weak.bend`, gated at `gates/wk-eval-gate.py`: 16 rows, 3 lanes, 15 identical to CPython and
#   ONE documented divergence.
# TODO(p3) ops.py:527  def __bool__   -- DONE, same gate (`bool_true`, `bool_false`,
#   `bool_on_i32`).
# TODO(p3) ops.py:528  def __int__    -- DONE, same gate (`int_weakint`, `int_i32`,
#   `int_on_range`).
# TODO(p3) ops.py:529  def __float__  -- DONE, same gate (`float_weakfloat`,
#   `float_on_i32`).

# TODO(p3) ops.py:530  def substitute

# TODO(p3) ops.py:537  def __index__
#   # NOTE: this is not called by Tensor slice (Tensor handles UOps directly), but satisfies SupportsIndex for type checking

# TODO(p3) ops.py:542  def trace_num






# WALL(p3) ops.py:582  def __getitem__ -- BLOCKED. PYTHON'S SLICE PROTOCOL. The body calls `super(UOp, self).__getitem__(idx)`,
#   `argfix`, `_normalize_indices`, `slice` objects and `self.shape[i]`. A slice is a Python
#   runtime object with `start`/`stop`, and Bend has no slicing syntax to normalise.

# DONE(p3) ops.py:597 def _uop -- AND THE HONEST ANSWER IS THAT THERE IS NOTHING TO
#   WRITE. CPython's is `def _uop(self) -> UOp: return self`, which is the IDENTITY, and
#   it is the identity because `Tensor` SUBCLASSES `UOp`. This port's
#   `type Tensor is Data: Tensor{ar, uop, is_param, grad}` (`tensor.bend:190`) is a RECORD
#   WRAPPING a U32 index, so it is not a UOp -- and the port's node reference is already a
#   `Found`, which IS the UOp reference. There is no unwrap on this side to perform.
#   THE TENSOR SIDE OF THE SAME NAME IS PORTED AND GATED ELSEWHERE: `tensor.bend:196-200`
#   names `Tensor.u` as `_uop -- tensor.py:118` and every graph-building method there
#   reads that field in place of `self.uop`. So the NAME is done, from the side that has
#   something to do.

# DONE(p3) ops.py:599 def _wrap_uop -- SAME REASON, AND IT IS THE STRONGER ONE.
#   CPython's is `@classmethod def _wrap_uop(cls, u: UOp) -> UOp: return u`, so it returns
#   its argument UNCHANGED. It exists at all because `Tensor` subclasses `UOp`: without the
#   subclassing, a `UOp` passed where a `Tensor` is expected would not be one, and this
#   would have to convert rather than hand back. The port has no such gap -- `Tensor` is a
#   record wrapping a `U32` and a `Found` is a `U32` plus an arena -- so there is no
#   coercion to bridge and no def to write. **A MARKER THAT ASKS FOR A FUNCTION WHICH IS
#   CORRECTLY ABSENT IS A WALL, NOT A GAP**, and the reason it was a marker at all is that
#   nobody had written down WHICH kind it was.

# TODO(p3) ops.py:600  def const_like


# TODO(p3) ops.py:609  def ufix

# TODO(p3) ops.py:616  def store


# TODO(p3) ops.py:622  def ins

# TODO(p3) ops.py:623  def contract


#   # cast, except for CONST, in which case rebuild a new CONST at the dtype

# TODO(p3) ops.py:640  def cconst



# TODO(p3) ops.py:649  def wmma

# PORTED -- `ops.py:652 _rop` is `tensor.bend`'s `tn_rop` (tensor.bend:868).

# TODO(p3) ops.py:663  def invalid

# DONE(p3) ops.py:664 def valid -- `UOp.where` and `UOp.valid_of` above, gated at
#   `gates/ops-core-gate.py` in FOUR rows. `where` is `mixin/elementwise.py:426`'s
#   `self.alu(Ops.WHERE, x, y)`, i.e. `UOp(Ops.WHERE, src=(cond, x, y))`, and it is the constructor
#   `UOp.valid_of` is one line on top of.
#
#   THIS WAS DIAGNOSED AS UNPORTABLE AND WAS NOT, AND THE MISDIAGNOSIS IS THE FINDING. I wrote both
#   defs, could not read their own src fields back, and reverted them as "an unverifiable
#   constructor". The truth is the ARENA RULE THIS PROJECT ALREADY RECORDS: each `UOp.const` GROWS
#   the arena and answers a node in the GROWN one, so reading an index against the original `ar0`
#   finds a different node -- I read `ANone{}` out of three srcs that were there all along. MEASURED
#   with a probe: threaded wrongly, all three read `ANone{}`; threaded right,
#   `cbool:True|cbool:True|cinvalid`.
#
#   SO THE RULE FOR THIS WHOLE FILE IS NARROWER THAN I WROTE IT LAST TIME. Three defs moved
#   downstream because `ops.bend` cannot name `fold.bend`'s bounds or import `dtype.bend`. THIS one
#   needed neither: it was a bug in the CALLER's arena discipline, and the def was always writable
#   here. "Cannot read it back" is not evidence that it cannot be written.
#   PLANTED: swapping the two trailing srcs fails `valid_src1` and `valid_src2` together.

# TODO(p3) ops.py:665  def get_idx


# TODO(p3) ops.py:674  def reduce

# TODO(p3) ops.py:680  def overflows
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
#   earlier version of this marker said it did not. That was wrong. The real work is
#   narrower and stranger than "add an ordering": `bnd.lt` is a TWO-valued TOTAL
#   answer over `BndInt`, and what is missing is the third.
#
#   AND `dt_max` IS NOT A SUBSTITUTE FOR IT. `dtype.bend`'s `dt_max` answers
#   `int64.max` for `uint64` -- the `i64_max_u` fallthrough, `dtype.bend:379-389` --
#   which is documented as safe only because that bound is read as `hi <= max`.
#   `uint64.max` is `2**64-1` and `int64.max` is `2**63-1`, so borrowing the table
#   here would make every `uint64` bound wrong by a factor of two. This needs `Bnd`.
#   P3, with `vmin`/`vmax`.

# WALL(p3) ops.py:689  def unshard -- BLOCKED. `def _shard` IS ABSENT -- checked as a definition, comments excluded. `unshard` builds a
#   UNSHARD and `_shard` is the constructor it shares with `shard` below.
#   # *** multi-device helpers ***

# WALL(p3) ops.py:709  def bounds -- BLOCKED. `def max_numel` IS ABSENT, and `bounds` also reads `self.axis` and a device COUNT
#   (`len(self.device)`, on the `Dev` tag). It is a `itertools.accumulate` + `pairwise`
#   over per-axis shapes.

# TODO(p3) ops.py:715  def axis

# TODO(p3) ops.py:748  def _shard

# WALL(p3) ops.py:754  def shard -- BLOCKED. `def _shard` IS ABSENT -- the same one `unshard` needs. `copy_to_device` IS present, so
#   this is one missing constructor rather than a missing subsystem.


#   `def param_like` IS ABSENT, and `store_call`'s body is two of them:
# TODO(p3) ops.py:766  def store_call  -- BLOCKED, and is `self.param_like(0).store(...).call(self, src)`.

#   A DEVICE IS A `U32` TAG HERE, NOT A STRING: `type Dev is Data: D1{tag: U32}`. So a device NAME has no prefix to test, and the two below are exactly a `startswith`:
# TODO(p3) ops.py:775  def on_disk  -- BLOCKED, and is `device.startswith("DISK")`.
# TODO(p3) ops.py:776  def on_creation_device  -- BLOCKED, and is `device.startswith(...)`.
#   # little helpers





# PORTED -- `ops.py:818 _mop` is `tensor.bend`'s `tn_mop` (tensor.bend:729).



# TODO(p3) ops.py:850  def new_buffer

# TODO(p3) ops.py:857  def from_buffer

#   `def canonicalize_device` and `def is_disk_device` ARE BOTH ABSENT, and both start with one:
# TODO(p3) ops.py:861  def empty_like  -- BLOCKED, and opens `canonicalize_device(...)`.
# TODO(p3) ops.py:879  def clone  -- BLOCKED, and opens `canonicalize_device(...)` then tests `is_disk_device`.

# TODO(p3) ops.py:867  def _frompy



# DONE(p3) ops.py:902 def is_virtual -- `wk_is_virtual` in `weak.bend`, `no_dev` beside it.
#   PORTED BUT UNGATED, AND THE REASON IS A FIXTURE, NOT A DEF. `is_virtual` answers
#   `device is None or dtype in weaks`, and the device half needs a node that CARRIES a `Dev`:
#   `fold.bend`'s `mw_pa` hard-codes `ParamArg`'s device field to `None{}` and no def in the port
#   sets it, so EVERY node is virtual and the reader has no negative witness. MEASURED: both
#   candidate rows came out `True`, and two rows that are always `True` cannot fail -- adding them
#   would have been a denominator counting nothing, which is the defect this project keeps removing.
#   The rows appear when something populates `Dev`; the reader is already there to be gated.


# TODO(p3) ops.py:931  def contiguous_view

#   `def contiguous_view` IS ABSENT, and both of these ask it first:
# TODO(p3) ops.py:952  def contiguous_view_offset  -- BLOCKED, and is `None if (view := self.contiguous_view()) is None`.
# TODO(p3) ops.py:968  def _buffer_view  -- BLOCKED, and raises on `self.contiguous_view() is None`.

# WALL(p3) -- STORAGE, DEVICE AND ALLOC. NO LIVE `Buffer` -- there is no `type Buffer is Data` anywhere in the port and ZERO `Buffer{` constructors. tinygrad's Buffer is an ALLOCATED OBJECT with a `realized` field and a `memory`
# TODO(p3) ops.py:961  def _base_buffer_is_realized  -- BLOCKED, and walks the AFTER chain then reads `u.base.realized`.
# TODO(p3) ops.py:999  def realized  -- BLOCKED, and ANSWERS a Buffer.
# TODO(p3) ops.py:1010  def is_realized  -- BLOCKED, and is `self.base.realized is not None`.
# TODO(p3) ops.py:777  def needs_storage  -- BLOCKED, and is `not is_virtual and (storage_base.op is ALLOC or base.realized)`.


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
#     `bsl.go`'s shape and readable; `substitute` (ops.py:530) is not ported, and
#     the dict is keyed by a `UOp` in Python, which in this arena means keyed by an
#     INDEX whose validity is a session property. P3, with `substitute`.

#   ops.py:1049  def variables
#     Walks the backward slice collecting `x.unbound() if x.is_variable else x` and
#     an `_device_num` Variable per DEVICE RANGE, then `sorted(ret, key=lambda v:
#     (v.arg.name or "", v.arg.slot))`. The sort key is `(Maybe<String>, U32)` and
#     the `or ""` is Python's `None`-sorts-first, which this port has to state
#     rather than inherit. Gated on `is_variable` and on the shape wall.






# TODO(p3) ops.py:1060  def const_factor
#   # *** uop symbolic stuff ***

# TODO(p3) ops.py:1069  def divides

# DONE(p3) ops.py:1082 def pop_const -- `UOp.pop_const_val` / `UOp.pop_const_hits` above, with
#   `cval_arg`. Gated at `gates/ops-core-gate.py` in EIGHT rows over FOUR fixtures, and the
#   fixtures are built so the def's TWO conditions fail SEPARATELY: a second src that is not a
#   CONST, and a `MUL` popped as an `ADD`. Planted -- dropping the `op` comparison from
#   `pop_const_hits` fails exactly `pop_mul_const_hits` and nothing else, which is what says the
#   op is COMPARED rather than assumed. The value is a `Const` and not an `H.I64`: an I64-only
#   reader recorded a divergence on the float fixture that was really just a narrow type, and
#   `pop_const` returns whatever the CONST carries.

# TODO(p3) ops.py:1085  def gcd

# TODO(p3) ops.py:1091  def divide_exact

# TODO(p3) ops.py:1102  def vmin

# TODO(p3) ops.py:1104  def vmax

# TODO(p3) ops.py:1106  def _min_max

# TODO(p3) ops.py:1168  def _sym_fxn

# TODO(p3) ops.py:93  def sym_infer

# TODO(p3) ops.py:1183  def render

# TODO(p3) ops.py:1191  def pyrender

#   `def view_as` IS ABSENT, and the alloc family ends in one:
# TODO(p3) ops.py:1198  def alloc  -- BLOCKED, and ends `ret.view_as(shape)`.
# TODO(p3) ops.py:1203  def alloc_like  -- BLOCKED, and delegates to `alloc`.
# TODO(p3) ops.py:1206  def placeholder  -- BLOCKED, and ends `view_as`.
# TODO(p3) ops.py:1219  def placeholder_like  -- BLOCKED, and delegates to `placeholder`.




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
# (helpers.bend:539-546), so `end` is a `Maybe<&2, List<&2, U32>>` and not a node.
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
# AND A PRINTER THAT WAS THREE DRAFTS WORSE THAN IT NEEDED TO BE: a recursive
# `deep` needing a closer that knows its own depth, a `Bool.pick` for the first
# separator, and a fold that opened a paren in the accumulator. The file already
# had the shape under another name (`Rng.srcops.go`'s `+first` flag). Grep for
# the IDIOM before writing the INSTANCE.
#   # set is store+end+after

# DONE(p3) ops.py:1229 def param -- THE SHAPE-LESS ARM ONLY, and it is in `weak.bend`. THE THIRD
#   def to arrive downstream for a THIRD distinct reason: `ops.bend` cannot NAME `fold.bend`'s bounds
#   (`_eval`), and it cannot IMPORT `dtype.bend` at all -- `ops.bend:87` says so and it is TRUE, since
#   dtype.bend's fp16/bf16/i64 C effects make the checker exit 1 for ANY importer. So the weaks guard
#   `md_weak` is unreachable from this file, and `wk_param_noshape` lives in `uop/weak.bend` beside the
#   other two. **THE RULE IS NOT "THOSE THREE WERE MISFILED" BUT "A DEF NEEDING A dtype PREDICATE OR A
#   BOUND LIVES DOWNSTREAM OF `ops.bend`."**
#   Gated at `gates/wk-eval-gate.py`: 22 rows, 3 lanes, 21 identical and the ONE documented
#   `simplify` divergence. Planted -- removing the guard fails BOTH `_built` rows.
#
#   THE OTHER TWO ARMS ARE NOT PORTED and the reason is the missing piece, named: a shaped param is
#   `prod(to_max_shape(shape))` plus a `view_as` RESHAPE, and **`view_as` IS ABSENT FROM THE PORT**
#   (so is `unique_num`). Checked, not assumed.

# TODO(p3) ops.py:1241  def param_like

# TODO(p3) ops.py:1250  def view_as

# custom_function -- ops.py:1258 upstream. `UOp(Ops.CUSTOM_FUNCTION, src=src,
# arg=CustomFunction(name, dtype))`. The pin's spelling was ops.py:1256 and took no
# dtype, because there was no `CustomFunction` to hold one.
# `dtype=dtypes.void` is upstream's DEFAULT and Bend has no default argument, so `dt`
# is required here and `CustomFunction.of(name)` builds the void-dtype value.
# `UOp.call` below is NOT PORTED, so nothing in this file consumes the dtype yet:
# `dtype_from_uop` is not ported either (the folds do not fit, see the header).
def UOp.custom_function(+ar: Arena, name: String, +srcs: List<&2, U32>, dt: S.Dt) -> Found:
  UOp.new(ar, OpsCUSTOM_FUNCTION{}, srcs, ACustom{CustomFunction{name, dt}}, TNone{})

# TODO(p3) ops.py:1261  def call

# WALL(p3) ops.py:1274  def call_with_outputs -- BLOCKED. ENDS IN THE `alloc` CHAIN: the body binds output ALLOCs through `mint` below, and `mint`
#   calls `UOp.alloc`, which ends in `view_as` -- absent as a definition.

# WALL(p3) ops.py:1292  def mint -- BLOCKED. CALLS `UOp.alloc` ("`buf = UOp.alloc(...)`"), and `alloc` ends in `ret.view_as(shape)`
#   -- `view_as` is absent as a definition.

# WALL(p3) ops.py:1312  def call_with_output -- BLOCKED. IS `UOp.call_with_outputs((self,), *srcs)`, one line over the marker above it, so it is
#   blocked on the same `alloc` -> `view_as` chain.
#   # one-line convenience for the single-output case: self is the value

# WALL(p3) ops.py:1313  def custom_kernel -- BLOCKED. BUILDS ITS PLACEHOLDERS WITH `UOp.placeholder_like`, and `placeholder_like` delegates to
#   `placeholder`, which ends in `view_as` -- absent as a definition. NOTE the `fxn:Callable`
#   is NOT the blocker: `bend guide:69` says functions are values that can be passed and
#   called, affine, and this calls `fxn` once.

# TODO(p3) ops.py:1318  def to_elf

# TODO(p3) ops.py:1331  def uopfunc

# DONE(p3) ops.py:1229 def param -- THE SHAPE-LESS ARM ONLY, and it is in `weak.bend`. THE THIRD
#   def to arrive downstream for a THIRD distinct reason: `ops.bend` cannot NAME `fold.bend`'s bounds
#   (`_eval`), and it cannot IMPORT `dtype.bend` at all -- `ops.bend:87` says so and it is TRUE, since
#   dtype.bend's fp16/bf16/i64 C effects make the checker exit 1 for ANY importer. So the weaks guard
#   `md_weak` is unreachable from this file, and `wk_param_noshape` lives in `uop/weak.bend` beside the
#   other two. **THE RULE IS NOT "THOSE THREE WERE MISFILED" BUT "A DEF NEEDING A dtype PREDICATE OR A
#   BOUND LIVES DOWNSTREAM OF `ops.bend`."**
#   Gated at `gates/wk-eval-gate.py`: 22 rows, 3 lanes, 21 identical and the ONE documented
#   `simplify` divergence. Planted -- removing the guard fails BOTH `_built` rows.
#
#   THE OTHER TWO ARMS ARE NOT PORTED and the reason is the missing piece, named: a shaped param is
#   `prod(to_max_shape(shape))` plus a `view_as` RESHAPE, and **`view_as` IS ABSENT FROM THE PORT**
#   (so is `unique_num`). Checked, not assumed.

# WALL(p3) ops.py:1333  def outlined -- BLOCKED. PYTHON INTROSPECTION OF A CALLABLE: `inspect.signature(fn).bind(*args, **kwargs)`,
#   `bound.items()`, and the dict union `bound | {...}`. That is the runtime's own view of a
#   function's parameters, which no compiled language exposes.

# TODO(p3) ops.py:1361  def launch_dims

#   ops.py:1366  def vals
# PORTED -- `ProgramInfo.vals` is `ProgramInfo.vals` (this file). Five `vv_*` rows
# byte-identical to CPython on all three lanes via `sh .agents/slop/ops-vv-gate.sh`,
# with TWO negative controls: drop `Map.has` and the gate reds; flip the fold's
# order and the gate reds.
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
# AND THE `Maybe`-FOLD I SAID WAS MISSING WAS NOT. It is `Maybe.bind`, it was
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

# CONST IDENTITY IS BITWISE, AND IEEE EQUALITY IS WRONG IN BOTH DIRECTIONS.
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
# NOTHING IN THIS FILE COULD SEE IT. An AFTER built either way has the same op, the same
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
# concrete float it used to be conflated with, against the weak int it is one
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
  ParamArg{slot, S.uint32(), None{}, None{}, None{}, None{}, as, None{}, False{}, None{}, None{}, False{}, None{}}

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

# ---------------------------------------------------------------------------
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
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# CustomFunction -- ops.py:1394 / :1258. THE ROWS THIS TYPE WAS MISSING, and the
# measurement that asked for them.
#
# `eq_customfunction` and `CustomFunction.of` landed with NO row at all, and three of
# their mutations each moved 0 of the other 104: drop the dtype half of the
# comparison, drop the name half, and make the `eq_arg.ACustom` arm unconditionally
# true. None of those is a THEOREM -- there is nothing undecidable about a two-field
# structural comparison. They were a 0 because nothing the gate could see ever called
# them, which is the `0` that means REQUEST FOR A FIXTURE rather than coverage.
#
# THE FIXTURES ARE THREE CPython ANSWERS, read live and not transcribed:
#     CustomFunction("f")                 == CustomFunction("f")                 -> True
#     CustomFunction("f")                 == CustomFunction("f", dtypes.uint64) -> False
#     CustomFunction("f", dtypes.uint64)  == CustomFunction("g", dtypes.uint64) -> False
# BOTH fields are therefore in the key, and the return dtype SPLITS the ucache. The
# third answer is the one that matters downstream: `dtype_from_uop`'s CUSTOM_FUNCTION
# arm is `return arg.dtype`, so the dtype is the node's TYPE, not a field nobody
# reads. The `hcq2.py:84` caller spells it `custom_function(fn.__name__, dtype=ret)`
# for exactly that reason.
def g_cfun_pair(nm1: String, dt1: S.Dt, nm2: String, dt2: S.Dt) -> Bool:
  # the DIAGONAL CELL IS `True` -- intern's linear scan finds the existing key -- and
  # the two OFF-DIAGONAL cells are the ones a row has to earn.
  +a = UOp.custom_function(Arena.empty(), nm1, Nil{}, dt1)
  +b = UOp.custom_function(Found.ar(a), nm2, Nil{}, dt2)
  U32.is_eq(Found.i(a), Found.i(b))

def t_cfun_interns() -> Bool:
  g_cfun_pair("sel_registerName", S.void(), "sel_registerName", S.void())

def t_cfun_dtype_splits() -> Bool:
  Bool.not(g_cfun_pair("sel_registerName", S.void(), "sel_registerName", S.uint64()))

def t_cfun_name_splits() -> Bool:
  Bool.not(g_cfun_pair("submit_null", S.void(), "submit_cl", S.void()))

# THE ARG, read back through the `ACustom` ARM rather than compared with `eq_arg` --
# deliberately. A row whose expected value is a def of the thing under test is not a
# test, so this does not ask "is this arg equal to a hand-built ACustom"; it asks
# "which Arg constructor did `UOp.custom_function` actually build, and what are its
# two fields in order". The pin's `UOp.custom_function` built an `AStr`, so the
# `case _:` cell answers `!ACustom` and the row moves.
def dt_name(d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, nm}: nm

def cfun_fields_str(cf: CustomFunction) -> String:
  match cf:
    case CustomFunction{name, dtype}: String.concat([name, "|", dt_name(dtype)])

def cfun_arg_str.go(a: Arg) -> String:
  match a:
    case ACustom{cf}: cfun_fields_str(cf)
    case _: "!ACustom"
    case _: "!ACustom"

def cfun_arg_str(+ar: Arena, i: U32) -> String:
  cfun_arg_str.go(Arena.arg(ar, i))

# THE DEFAULT, ops.py:1397's `dtype: DType = dtypes.void`. This is the row for
# `CustomFunction.of`, and it is a STRING row for the same reason `cfun_arg_str` is:
# the answer is a PAIR, and a Bool row cannot say which pair.
def cfun_of_str() -> String:
  String.concat([CustomFunction.name(CustomFunction.of("sel_registerName")), "|", dt_name(CustomFunction.dtype(CustomFunction.of("sel_registerName")))])

def t_cfun_arg() -> String:
  +a = UOp.custom_function(Arena.empty(), "sel_registerName", Nil{}, S.uint64())
  cfun_arg_str(Found.ar(a), Found.i(a))

# ---------------------------------------------------------------------------
# BLOB -- THE INTERN KEY'S BYTES HALF. ops.py:201, spec.py:96, ops.py:365.
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
# ---------------------------------------------------------------------------

# the blob bytes, as the port spells them. 97..102 are `a`..`f`.
def BLOB_A() -> List<&2, U32>: [97, 97, 97, 97]
def BLOB_B() -> List<&2, U32>: [98, 98, 98, 98]
def BLOB_C() -> List<&2, U32>: [97, 97]

# `List<&2, U32>` as the file's ONE canonical spelling of a sequence, comma and no
# space -- the same rule `AxisVals.str` uses and the same one the oracle's `render`
# uses, so a byte is never spelled two ways across the two lanes.
def U32s.go(xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: U32s.go(t, List.append(&2, String, acc, [U32.show(x)]))

def U32s.str(xs: List<&2, U32>) -> String:
  String.join(List.reverse(&2, String, U32s.go(xs, Nil{})), ",")

# intern the first blob, then the second, on ONE arena. The answer is identity of the
# two INDICES, which is the arena's answer and not `eq_arg`'s: a row that asserted
# `eq_arg` directly would be asserting the def under test with itself.
def blob_same(bs1: List<&2, U32>, bs2: List<&2, U32>) -> Bool:
  +u = UOp.new(Arena.empty(), OpsBINARY{}, Nil{}, ABlob{bs1}, TNone{})
  +v = UOp.new(Found.ar(u), OpsBINARY{}, Nil{}, ABlob{bs2}, TNone{})
  U32.is_eq(Found.i(u), Found.i(v))

# the node count CPython's `len(ucache)` answers, sentinel removed.
def blob_ucount(bs1: List<&2, U32>, bs2: List<&2, U32>) -> U32:
  +u = UOp.new(Arena.empty(), OpsBINARY{}, Nil{}, ABlob{bs1}, TNone{})
  +v = UOp.new(Found.ar(u), OpsBINARY{}, Nil{}, ABlob{bs2}, TNone{})
  U32.sub(Arena.next(Found.ar(v)), 1)

def t_blob_interns() -> Bool: blob_same(BLOB_A(), BLOB_A())

def t_blob_len_diff_content() -> Bool: Bool.not(blob_same(BLOB_A(), BLOB_B()))

def t_blob_diff_len() -> Bool: Bool.not(blob_same(BLOB_A(), BLOB_C()))

def s_blob_count_same() -> String: U32.show(blob_ucount(BLOB_A(), BLOB_A()))

def s_blob_count_len_diff_content() -> String: U32.show(blob_ucount(BLOB_A(), BLOB_B()))

# the blob bytes read back OUT of a node's arg, which is what `len()` and the repr both
# need now that `ABlob` holds the bytes rather than a count. `Nil{}` for a non-blob arg:
# `uop/fold.bend`'s `binary_n` already answers 0 for one, and a second spelling of the
# same absence is a second thing to keep in step.
def blob_bytes(a: Arg) -> List<&2, U32>:
  match a:
    case ABlob{bs}: bs
    case _: Nil{}

# `ops.py:365`, `case Ops.BINARY: return (len(self.arg),)` -- the LENGTH is still a
# fact about a blob after the key reads its content, and it is the one
# `uop/fold.bend`'s `binary_n` and `uop/render.bend`'s repr read. A fix that dropped it
# would leave both of those answering 0. The trailing comma is Python's 1-tuple comma.
def s_blob_shape() -> String:
  +u = UOp.new(Arena.empty(), OpsBINARY{}, Nil{}, ABlob{BLOB_A()}, TNone{})
  String.concat(["(", Nat.show(List.length(&2, U32, blob_bytes(Arena.arg(Found.ar(u), Found.i(u))))), ",)"])

# the CONTENT, read back out of the node rather than asserted about it. This is the row
# that pins the REPRESENTATION: whatever the key compares, it must read back as
# CPython reads `list(u.arg)`.
def s_blob_content() -> String:
  +u = UOp.new(Arena.empty(), OpsBINARY{}, Nil{}, ABlob{BLOB_A()}, TNone{})
  U32s.str(blob_bytes(Arena.arg(Found.ar(u), Found.i(u))))

# THE NODE-COUNT SWEEP, and it is here because of a measured failure in this repo: four
# aliasing bugs in `codegen/decomp/dtype.bend` agreed at one arena size and broke at the
# next, with the signature "count barely moves, cone collapses". One configuration is
# one point, so this walks SIX blobs and every blob is interned TWICE. Both halves of
# the answer are in the one Bool: a key that MERGED two blobs lands the second on the
# first's index, and a key that STOPPED hash-consing lands the repeat one index further
# on. Either moves `Found.i(u)` off `i+1`.
#
# The lengths run 0,1,2,3,4,4 -- the LAST TWO ARE THE SAME LENGTH AND DIFFERENT CONTENT.
# Six blobs of six distinct lengths would be a pure count sweep, and measured: with
# lengths 0,1,2,3,4,5 the length-summary mutation M1 moved `blob_len_diff_content` and
# `blob_sweep_count` but left `blob_sweep` True, because no two sweep blobs could collide
# under a length key. The equal-length tail is what closes that.
def blob_sweep.go(bss: List<&2, List<&2, U32>>, +ar: Arena, +i: U32) -> Bool:
  match bss:
    case Nil{}: True{}
    case +b <> t:
      +u = UOp.new(ar, OpsBINARY{}, Nil{}, ABlob{b}, TNone{})
      +v = UOp.new(Found.ar(u), OpsBINARY{}, Nil{}, ABlob{b}, TNone{})
      Bool.and(U32.is_eq(Found.i(u), Found.i(v)),
        Bool.and(U32.is_eq(Found.i(u), U32.add(i, 1)), blob_sweep.go(t, Found.ar(v), U32.add(i, 1))))

def blob_sweep_blobs() -> List<&2, List<&2, U32>>:
  [Nil{}, [97], [97, 98], [97, 98, 99], [97, 98, 99, 100], [97, 98, 99, 101]]

def blob_sweep_ar.go(bss: List<&2, List<&2, U32>>, +ar: Arena) -> Arena:
  match bss:
    case Nil{}: ar
    case b <> t:
      +f = UOp.new(ar, OpsBINARY{}, Nil{}, ABlob{b}, TNone{})
      blob_sweep_ar.go(t, Found.ar(f))

def t_blob_sweep() -> Bool: blob_sweep.go(blob_sweep_blobs(), Arena.empty(), 0)

def s_blob_sweep_count() -> String:
  U32.show(U32.sub(Arena.next(blob_sweep_ar.go(blob_sweep_blobs(), Arena.empty())), 1))

# ---------------------------------------------------------------------------
# AFLOAT -- `Arg`'s BARE-float arm, the OTHER half of the intern key. ops.py:201.
#
# The measurement and the reason `F32.is_eq` is right here and `F32.bits` would be a
# regression are the comment on `eq_arg.AFloat` above; this block is the GATE for it.
# `AFloat` has no constructor anywhere in the tree -- `uop/upat.bend:418` and
# `uop/render.bend:717` only READ it, and its one would-be builder `_frompy` is
# `TODO(p3)` at :4318 -- so no interning fixture can reach the arm the normal way and
# the comparator was untested rather than unreachable. These rows intern two
# `AFloat`s on ONE arena through `UOp.new`, so the answer is IDENTITY OF THE TWO
# INDICES and not `eq_arg` read directly: `blob_same` above says why, and this is
# the same rule.
# ---------------------------------------------------------------------------
def afloat_same(f1: F32, f2: F32) -> Bool:
  +u = UOp.new(Arena.empty(), OpsCONST{}, Nil{}, AFloat{f1}, TNone{})
  +v = UOp.new(Found.ar(u), OpsCONST{}, Nil{}, AFloat{f2}, TNone{})
  U32.is_eq(Found.i(u), Found.i(v))

# THE DISCRIMINATING CELL. `0.0` and `-0.0` are `0x00000000` and `0x80000000` and
# CPython interns them as ONE key; a bit comparator answers False here and splits it.
def t_afloat_zeros_intern() -> Bool: afloat_same(0.0, F32.neg(0.0))

# THE COUNTER-CELL. Two NaNs of the same payload, IEEE-unequal, and CPython keeps two
# nodes; a bit comparator answers True here and merges them. `F32.div(0,0)` is the
# file's NaN, the same construction `t_float_nan_interns` uses.
def t_afloat_nan_distinct_intern() -> Bool: afloat_same(F32.div(0.0, 0.0), F32.div(0.0, 0.0))

# THE TWO CONTROLS, and they are what make the two cells above mean something: a
# comparator that answered False for every float would satisfy the NaN row alone, and
# one that answered True for every float would satisfy the zeros row alone.
def t_afloat_same_intern() -> Bool: afloat_same(1.5, 1.5)

def t_afloat_distinct_intern() -> Bool: afloat_same(1.5, 2.5)

# ---------------------------------------------------------------------------
# THE `type(tag)` LANE. `ops.py:201`'s key carries `type(arg)` and NOT `type(tag)`, so a
# `bool` tag and an `int` tag of the same value are ONE key. This is the ONLY
# over-split the port has: every other comparator dispute in this file is a
# UNDER-split, and the direction is the reason this lane needs its own rows rather
# than one more field comparison.
#
# Same rule as the two lanes above: intern two nodes on ONE arena through `UOp.new`
# and answer IDENTITY OF THE TWO INDICES, never `eq_tag` read directly.
# ---------------------------------------------------------------------------
def tag_same(t1: Tag, t2: Tag) -> Bool:
  +u = UOp.new(Arena.empty(), OpsSINK{}, Nil{}, ANone{}, t1)
  +v = UOp.new(Found.ar(u), OpsSINK{}, Nil{}, ANone{}, t2)
  U32.is_eq(Found.i(u), Found.i(v))

# THE CELL THE FIX IS ABOUT, and it reads TRUE, which is "the two interned to ONE node".
# `rtag(self, tag=True)` -- ops.py:258 -- is what puts a `bool` True in the key, and
# `UOp(Ops.SINK, tag=1)` is the same key.
def t_tag_bool_vs_int_interns() -> Bool: tag_same(TBool{True{}}, TInt{1})

# THE COUNTER-CELL, and it is what makes the row above mean something: an `eq_tag` that
# answered True for every pair would satisfy it alone. Printed as "did they SPLIT", so
# this is `Bool.not` of `tag_same` where the `_interns` rows are `tag_same` itself.
def t_tag_true_vs_false_splits() -> Bool: Bool.not(tag_same(TBool{True{}}, TBool{False{}}))

# AND THE ONE THAT KEEPS `TNone` SEPARATE FROM ZERO, which a `case` arm that stopped
# matching would answer the other way SILENTLY. `hash(None) != hash(0)`, so this is
# FALSE -- two nodes -- and the row exists to hold that.
def t_tag_none_vs_zero_interns() -> Bool: tag_same(TNone{}, TInt{0})

# THE CONTROL THAT PINS THE OTHER HALF, and it is the row that says the fix above is a
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
  AParam{ParamArg{0, S.int32(), None{}, None{}, None{}, None{}, S.AGlobal{}, None{}, False{}, None{},
                  None{}, False{}, v}}

def pynest_same(v1: Maybe<&2, Const>, v2: Maybe<&2, Const>) -> Bool:
  +u = UOp.new(Arena.empty(), OpsPARAM{}, Nil{}, pa_with(v1), TNone{})
  +v = UOp.new(Found.ar(u), OpsPARAM{}, Nil{}, pa_with(v2), TNone{})
  U32.is_eq(Found.i(u), Found.i(v))

# THE CELL THE FIX IS ABOUT, and it reads TRUE -- "the two interned to ONE node".
def t_pynest_bool_vs_int_interns() -> Bool: pynest_same(Some{CBool{True{}}}, Some{CInt{H.i64_of_i32(1)}})

# THE TWO DISTINCTNESS CONTROLS, and without them a comparator answering True for every
# pair would satisfy the row above alone.
def t_pynest_int_distinct_interns() -> Bool: pynest_same(Some{CInt{H.i64_of_i32(1)}}, Some{CInt{H.i64_of_i32(2)}})

def t_pynest_none_vs_zero_interns() -> Bool: pynest_same(None{}, Some{CInt{H.i64_of_i32(0)}})

# AND THE ONE THAT KEEPS THE COMPARATOR FROM BEING "cross bool against every number":
# `ConstFloat.__hash__` is `hash(self.bits)` (dtype.py:21) and
# `hash(0x3ff0000000000000) != hash(1.0)`, so a `ConstFloat` and an equal int sit in
# DIFFERENT dict buckets upstream and are never compared at all. This row reads FALSE and
# must stay false; the signed zeros are the same fact from the other side, differing in bits.
def t_pynest_cfloat_vs_int_interns() -> Bool:
  pynest_same(Some{CFloat{1.0}}, Some{CInt{H.i64_of_i32(1)}})

def t_pynest_signed_zero_interns() -> Bool:
  pynest_same(Some{CFloat{F32.neg(0.0)}}, Some{CFloat{0.0}})

# ---------------------------------------------------------------------------
# MSTACK -- ops.py:770, `UOp(Ops.MSTACK, src=(self,)+srcs) if len(srcs) else self`.
#
# THE ROW THIS FILE WAS MISSING, and it is a KNOWN LOOSE END rather than a new finding.
# `UOp.after`, `UOp.end` and `UOp.mstack` all had `srcs ++ [self]` where CPython has
# `(self,)+src`, so self landed LAST in all three; that was fixed in `847c5f5fb` and
# `after_puts_self_first` / `end_puts_self_first` were added with it -- and `mstack` was
# fixed in the same commit with NO row of its own. So a re-regression of mstack alone
# would leave both of its siblings green and this file would not notice, which is the
# same failure the AFTER fix was made for, one def over.
#
# The two rows are deliberately not the same row. `t_mstack_puts_self_first` is a Bool
# naming the regression, beside its two siblings; `mstack0/1/2` are CPython-compared
# STRINGS carrying the four facts plus the answer, and `mstack2`'s src op sequence
# `RANGE CONST CONST` is the fact a swap moves. Count, root op, root nsrc and arg are
# all identical either way.
# ---------------------------------------------------------------------------
def g_mstack.base(ar: Arena, r: U32, b: U32, c: U32) -> Found: UOp.mstack(ar, r, Nil{})

def g_mstack.one(ar: Arena, r: U32, b: U32, c: U32) -> Found: UOp.mstack(ar, r, [b])

def g_mstack.go(+n: U32, ar: Arena, r: U32, b: U32, c: U32) -> Found:
  match n:
    case 0: g_mstack.base(ar, r, b, c)
    case 1: g_mstack.one(ar, r, b, c)
    case _: UOp.mstack(ar, r, [b, c])

def g_mstack(n: U32) -> Found:
  # `self` is a RANGE and the supplied srcs are CONSTs, so self-first prints
  # `RANGE CONST CONST` and the bug prints `CONST CONST RANGE`.
  #
  # THE ARENA IS THREADED THROUGH EVERY NODE, and this is the rule that costs the most
  # when it is forgotten. `UOp.const(ar, v)` takes an arena and returns a `Found` over a
  # GROWTH arena; the local `ar` is not advanced. Binding `+b = UOp.const(ar, ...)` and
  # then passing `ar` onwards builds the MSTACK in a THREE-node arena while `Found.i(b)`
  # is an index into a FOUR-node one -- MEASURED: the src ops printed
  # `RANGE MSTACK MSTACK` and the node count printed 2, and `mstack_puts_self_first`
  # answered False. `Found.ar` of the previous node is the only way to carry the growth.
  +c0 = UOp.const(Arena.empty(), CInt{H.i64_of_i32(4)})
  +r = UOp.range_end(Found.ar(c0), Found.i(c0), [0], AXIS_WEAK{})
  +ri = Found.i(r)
  +b = UOp.const(Found.ar(r), CInt{H.i64_of_i32(1)})
  +bi = Found.i(b)
  +c = UOp.const(Found.ar(b), CInt{H.i64_of_i32(2)})
  g_mstack.go(n, Found.ar(c), ri, bi, Found.i(c))

def t_mstack_puts_self_first() -> Bool:
  +f = g_mstack(2)
  +ar = Found.ar(f)
  Bool.and(op_is(ar, Found.i(f), OpsMSTACK{}),
  Bool.and(op_is(ar, Arena.src(ar, Found.i(f), 0), OpsRANGE{}),
           op_is(ar, Arena.src(ar, Found.i(f), 1), OpsCONST{})))

# ONE BUILD PER ROW. `g_mstack` returns a `Found` over an affine arena, so calling it
# twice to get `.ar` and `.i` would read TWO arenas and print a signature over one node
# taken out of the other. Binding once with `+` is the only correct spelling.
def MStack.sig(n: U32) -> String:
  +f = g_mstack(n)
  Rng.sig(Found.ar(f), Found.i(f))

def t_mstack_rows() -> IO(Unit):
  do IO<Unit>:
    srow("mstack2", MStack.sig(2))
    srow("mstack1", MStack.sig(1))
    srow("mstack0", MStack.sig(0))



# ===========================================================================
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
# ===========================================================================

# `(0,)`, `(0,1)`, `(0,1,2)` -- the axis-id spelling, comma and no space, with
# Python's TRAILING COMMA on a one-element tuple. The comma is load-bearing:
# upstream's `axis_id` on a two-element arg is the 1-tuple `(0,)`, and `(0)` would
# read as a parenthesised int. Two defs rather than `List.show` because `List.show`
# brackets and spaces (`[0, 1]`), and reproducing `repr`'s spacing rules would put
# the formatting into the comparison instead of the values.
def IdsStr.rest(xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}: ""
    case h <> t: String.concat([",", U32.show(h), IdsStr.rest(t)])

def IdsStr(xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}: "()"
    case h <> t:
      # a one-element tuple gets its trailing comma, so the empty tail is not enough
      match t:
        case Nil{}: String.concat(["(", U32.show(h), ",)"])
        case _: String.concat(["(", U32.show(h), IdsStr.rest(t), ")"])

# `axis_id` WITH ITS LENGTH, which is what `axid_*` prints. The length is in the row
# because upstream's `axis_id` is a SLICE of the arg and a slice's length is the fact
# that says which slice: `arg[1:]` on a two-element arg and on a three-element arg both
# begin at 1 and only the length tells them apart.
def IdsStr.ids(+xs: List<&2, U32>) -> String:
  String.concat([IdsStr(xs), "/len=", Nat.show(List.length(&2, U32, xs))])

def ax_names_str.go(xs: List<&2, AxisType>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case a <> t: List.append(&2, String, [AxisType.name(a)], ax_names_str.go(t))

def ax_names_str(xs: List<&2, AxisType>) -> String:
  String.join(ax_names_str.go(xs), ",")

# THE EIGHT MEMBERS UPSTREAM KEEPS, as a list, in DECLARATION order. Not `AxisType.all`
# -- that is the port's ten, and the two dead ones are the wall. This list IS the wall's
# content and it is here because `eqax_distinct` and `#shared_axis_*` need a member set
# to walk; the two dead constructors are visibly absent from it, which is the honest
# shape while six other files still build them.
def AxisType.live() -> List<&2, AxisType>:
  [AXIS_DEVICE{}, AXIS_GLOBAL{}, AXIS_LOCAL{}, AXIS_WARP{}, AXIS_WEAK{}, AXIS_LOOP{},
   AXIS_UPCAST{}, AXIS_PLACEHOLDER{}]

# `eqax_collide` -- how many pairs of DIFFERENT members `eq_axis` calls equal. `eq_axis`
# is `AxisType.value` equality, so two members sharing a number make it answer True for
# two different axis types, which merges two RANGE args in the ucache and is invisible
# everywhere else. CPython's answer is 0, and this walks the same pairs on the port's
# member list.
#
# THE COUNT IS NOT THE SUM, and that is a measurement: summing every equal pair gives
# 8 on the live set and 10 on the full one, because `eq_axis(a, a)` is True for all ten.
# So the row is `pairs - diag`, the off-diagonal count -- which is 0 only when no two
# DISTINCT members collide, and a collision makes it 1 or 2. Both sets are walked because
# the port has TEN members where CPython has eight and the two retained dead ones are
# exactly where a collision would hide.
#
# ONE row per member set and NOT the 8x8 = 64 table: 64 rows of `eqax_*` would be a
# CHANGE DETECTOR, because a PERMUTED `value` table moves none of them (every value is
# still distinct) and that permuted table is precisely the defect upstream shipped. The
# off-diagonal COUNT moves on the permutation's twin (a collision) and `axv_*` moves on
# the permutation itself; a 64-row table would cover only the first of those two facts
# and 64 rows of `False` is a table that cannot fail.
def EqAx.pairs(+a: AxisType, ys: List<&2, AxisType>) -> U32:
  match ys:
    case Nil{}: 0
    case b <> t: U32.add(Bool.pick(U32, eq_axis(a, b), 1, 0), EqAx.pairs(a, t))

def EqAx.disagree(xs: List<&2, AxisType>, +ys: List<&2, AxisType>) -> U32:
  match xs:
    case Nil{}: 0
    case a <> t: U32.add(EqAx.pairs(a, ys), EqAx.disagree(t, ys))

# `eq_axis(a, a)` for every member, counted. The off-diagonal row cannot see a
# value-keyed equality that answers FALSE on the diagonal, which is what a saturated or
# misnumbered U32 would do, so it is a separate count over the same set.
def EqAx.diag(xs: List<&2, AxisType>) -> U32:
  match xs:
    case Nil{}: 0
    case +a <> t: U32.add(Bool.pick(U32, eq_axis(a, a), 1, 0), EqAx.diag(t))

def EqAx.collide(+xs: List<&2, AxisType>) -> U32:
  U32.sub(EqAx.disagree(xs, xs), EqAx.diag(xs))

def t_eqax() -> Bool:
  Bool.and(Bool.and(U32.is_eq(EqAx.collide(AxisType.live()), 0),
                    U32.is_eq(EqAx.collide(AxisType.all()), 0)),
           Bool.and(U32.is_eq(EqAx.diag(AxisType.live()), 8),
                    U32.is_eq(EqAx.diag(AxisType.all()), 10)))

# ---------------------------------------------------------------------------
# The RANGE fixtures. FIVE of them and each earns its place:
#
#   weak1    `UOp.range(1, 0)`                 the DEFAULT axis type is WEAK
#   loop2    `UOp.range(2, (0, 1), LOOP)`      a NESTED axis id, which upstream's spec
#                                            matcher REJECTS -- kept so the pin's
#                                            `(ids, type)` packing stays representable
#   dev3     `UOp.range(3, 0, DEVICE)`         the literal `0` that replaced
#                                            `axis_to_pos[AxisType.DEVICE]`
#   loopfn   `UOp.loop(7)`                    src is NOOP not CONST
#   twoid    `UOp(Ops.RANGE, ..., (LOOP,0,1))` THE DISCRIMINATOR, built directly
#
# `twoid` is the one that earned its place by MEASUREMENT: for an arg of length TWO,
# `arg[1:]` and `arg[0:-1]` are the same slice, so `axis_id`/`axis_type` answer
# identically on the pin and on upstream for every `UOp.range` and every `UOp.loop`.
# The `axid_*`/`axt_*` rows for `weak1`/`loop2`/`dev3`/`loopfn` are byte-identical
# across the two trees; only a three-element arg separates them. Its `rng_` four
# facts DO match, because the flip is in the arg and not in the graph.
# ---------------------------------------------------------------------------
def g_rng_weak1() -> Found:
  +c = UOp.const(Arena.empty(), CInt{H.i64_of_i32(1)})
  UOp.range_end(Found.ar(c), Found.i(c), [0], AXIS_WEAK{})

def g_rng_loop1() -> Found:
  +c = UOp.const(Arena.empty(), CInt{H.i64_of_i32(2)})
  UOp.range_end(Found.ar(c), Found.i(c), [0], AXIS_LOOP{})

def g_rng_dev3() -> Found:
  +c = UOp.const(Arena.empty(), CInt{H.i64_of_i32(3)})
  UOp.range_end(Found.ar(c), Found.i(c), [0], AXIS_DEVICE{})

def g_rng_loopfn() -> Found:
  UOp.loop(Arena.empty(), 7)

def g_rng_twoid() -> Found:
  +c = UOp.const(Arena.empty(), CInt{H.i64_of_i32(2)})
  UOp.range_end(Found.ar(c), Found.i(c), [0, 1], AXIS_LOOP{})

# Two RANGE nodes, one arena, same end / ids / axis / tag. The only difference
# is the tail depth. `Found.i` is the intern index — identity, not the depth
# argument echoed back.
# ONE arena. The two indices are identity. Depth is a separate row: folding
# `Arena.depth(ib) == db` into this bool makes a collision print False (both
# indices are the first node) and the row no longer moves.
def Uc.same(+da: U32, +db: U32, +ids: List<&2, U32>) -> Bool:
  +c = UOp.const(Arena.empty(), CInt{H.i64_of_i32(4)})
  +a = UOp.range_shaped(Found.ar(c), Found.i(c), ids, AXIS_WEAK{}, da)
  +b = UOp.range_shaped(Found.ar(a), Found.i(c), ids, AXIS_WEAK{}, db)
  U32.is_eq(Found.i(a), Found.i(b))

def Uc.depth(+da: U32, +db: U32, +ids: List<&2, U32>) -> String:
  +c = UOp.const(Arena.empty(), CInt{H.i64_of_i32(4)})
  +a = UOp.range_shaped(Found.ar(c), Found.i(c), ids, AXIS_WEAK{}, da)
  +b = UOp.range_shaped(Found.ar(a), Found.i(c), ids, AXIS_WEAK{}, db)
  String.concat([U32.show(Arena.depth(Found.ar(b), Found.i(a))), ",",
                 U32.show(Arena.depth(Found.ar(b), Found.i(b)))])

# --- THE AXIS CPYTHON LANE. Row order matches `.agents/slop/ops-oracle.py` EXACTLY and
# --- the gate is a byte diff, so a row added on one side and not the other is a diff and
# --- not a silent gap.

# `List.reverse` of the member list, so `axlt_revsorted` can be a row. `sorted(reversed)`
# must come back as the declaration order, which is the one direction a `__lt__` that
# compares by NAME rather than by value gets right -- hence both rows.
def RevAxis.go(xs: List<&2, AxisType>, +acc: List<&2, AxisType>) -> List<&2, AxisType>:
  match xs:
    case Nil{}: acc
    case a <> t: RevAxis.go(t, List.append(&2, AxisType, [a], acc))

# `axv_<NAME>` etc -- one row per MEMBER, in `AxisType.live()` order. CPython prints the
# eight it has; the two the port retains for other files are BEND-ONLY and the gate script
# filters them by name with the `#bend_only_*` reason in the oracle.
def AxisVals.go(xs: List<&2, AxisType>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case a <> t: AxisVals.go(t, List.append(&2, String, [U32.show(AxisType.value(a))], acc))

def AxisVals.str(xs: List<&2, AxisType>) -> String:
  String.join(List.reverse(&2, String, AxisVals.go(xs, Nil{})), ",")

def t_ax_derivation() -> IO(Unit):
  do IO<Unit>:
    srow("#shared_axis_members", ax_names_str(AxisType.live()))
    srow("#shared_axis_values", AxisVals.str(AxisType.live()))
    srow("#shared_axis_count", U32.show(U32.from_nat(List.length(&2, AxisType, AxisType.live()))))
    srow("#shared_axis_sorted", ax_names_str(List.sort(AxisType, AxisType.lt, AxisType.live())))

def t_ax_tables(l: List<&2, AxisType>) -> IO(Unit):
  do IO<Unit>:
    srow("axv_" ++ AxisType.name(AXIS_DEVICE{}), U32.show(AxisType.value(AXIS_DEVICE{})))
    srow("axn_" ++ AxisType.name(AXIS_DEVICE{}), AxisType.name(AXIS_DEVICE{}))
    srow("axl_" ++ AxisType.name(AXIS_DEVICE{}), axis_letters(AXIS_DEVICE{}))
    srow("axc_" ++ AxisType.name(AXIS_DEVICE{}), axis_colors(AXIS_DEVICE{}))
    srow("axv_" ++ AxisType.name(AXIS_GLOBAL{}), U32.show(AxisType.value(AXIS_GLOBAL{})))
    srow("axn_" ++ AxisType.name(AXIS_GLOBAL{}), AxisType.name(AXIS_GLOBAL{}))
    srow("axl_" ++ AxisType.name(AXIS_GLOBAL{}), axis_letters(AXIS_GLOBAL{}))
    srow("axc_" ++ AxisType.name(AXIS_GLOBAL{}), axis_colors(AXIS_GLOBAL{}))
    srow("axv_" ++ AxisType.name(AXIS_LOCAL{}), U32.show(AxisType.value(AXIS_LOCAL{})))
    srow("axn_" ++ AxisType.name(AXIS_LOCAL{}), AxisType.name(AXIS_LOCAL{}))
    srow("axl_" ++ AxisType.name(AXIS_LOCAL{}), axis_letters(AXIS_LOCAL{}))
    srow("axc_" ++ AxisType.name(AXIS_LOCAL{}), axis_colors(AXIS_LOCAL{}))
    srow("axv_" ++ AxisType.name(AXIS_WARP{}), U32.show(AxisType.value(AXIS_WARP{})))
    srow("axn_" ++ AxisType.name(AXIS_WARP{}), AxisType.name(AXIS_WARP{}))
    srow("axl_" ++ AxisType.name(AXIS_WARP{}), axis_letters(AXIS_WARP{}))
    srow("axc_" ++ AxisType.name(AXIS_WARP{}), axis_colors(AXIS_WARP{}))
    srow("axv_" ++ AxisType.name(AXIS_WEAK{}), U32.show(AxisType.value(AXIS_WEAK{})))
    srow("axn_" ++ AxisType.name(AXIS_WEAK{}), AxisType.name(AXIS_WEAK{}))
    srow("axl_" ++ AxisType.name(AXIS_WEAK{}), axis_letters(AXIS_WEAK{}))
    srow("axc_" ++ AxisType.name(AXIS_WEAK{}), axis_colors(AXIS_WEAK{}))
    srow("axv_" ++ AxisType.name(AXIS_LOOP{}), U32.show(AxisType.value(AXIS_LOOP{})))
    srow("axn_" ++ AxisType.name(AXIS_LOOP{}), AxisType.name(AXIS_LOOP{}))
    srow("axl_" ++ AxisType.name(AXIS_LOOP{}), axis_letters(AXIS_LOOP{}))
    srow("axc_" ++ AxisType.name(AXIS_LOOP{}), axis_colors(AXIS_LOOP{}))
    srow("axv_" ++ AxisType.name(AXIS_UPCAST{}), U32.show(AxisType.value(AXIS_UPCAST{})))
    srow("axn_" ++ AxisType.name(AXIS_UPCAST{}), AxisType.name(AXIS_UPCAST{}))
    srow("axl_" ++ AxisType.name(AXIS_UPCAST{}), axis_letters(AXIS_UPCAST{}))
    srow("axc_" ++ AxisType.name(AXIS_UPCAST{}), axis_colors(AXIS_UPCAST{}))
    srow("axv_" ++ AxisType.name(AXIS_PLACEHOLDER{}), U32.show(AxisType.value(AXIS_PLACEHOLDER{})))
    srow("axn_" ++ AxisType.name(AXIS_PLACEHOLDER{}), AxisType.name(AXIS_PLACEHOLDER{}))
    srow("axl_" ++ AxisType.name(AXIS_PLACEHOLDER{}), axis_letters(AXIS_PLACEHOLDER{}))
    srow("axc_" ++ AxisType.name(AXIS_PLACEHOLDER{}), axis_colors(AXIS_PLACEHOLDER{}))
    # --- THE TWO RETAINED DEAD MEMBERS. BEND-ONLY: upstream has no such member, so
    # --- there is nothing to ask. They carry 9 and 10, slots upstream does not use, and
    # --- `t_eqax` is what proves the ten values are still distinct.
    srow("axv_REDUCE", U32.show(AxisType.value(AXIS_REDUCE{})))
    srow("axn_REDUCE", AxisType.name(AXIS_REDUCE{}))
    srow("axl_REDUCE", axis_letters(AXIS_REDUCE{}))
    srow("axc_REDUCE", axis_colors(AXIS_REDUCE{}))
    srow("axv_UNROLL", U32.show(AxisType.value(AXIS_UNROLL{})))
    srow("axn_UNROLL", AxisType.name(AXIS_UNROLL{}))
    srow("axl_UNROLL", axis_letters(AXIS_UNROLL{}))
    srow("axc_UNROLL", axis_colors(AXIS_UNROLL{}))

# `axs_<OP>` -- `range_start` as a row. Five ops CPython names, and `Ops.NOOP`, which it
# does not: the port's `case _` arm answers 0 where Python raises, and `Ops.LINEAR`'s
# answer is also 0, so without a MISS row a dropped `LINEAR` and a dropped `NOOP` arm
# would print the same string.
def t_ax_range_start() -> IO(Unit):
  do IO<Unit>:
    srow("axs_NOOP", range_start_str(OpsNOOP{}))
    srow("axs_CALL", range_start_str(OpsCALL{}))
    srow("axs_LINEAR", range_start_str(OpsLINEAR{}))
    srow("axs_END", range_start_str(OpsEND{}))
    srow("axs_STAGE", range_start_str(OpsSTAGE{}))
    srow("axs_REDUCE", range_start_str(OpsREDUCE{}))

# `rng_<tag>` (four facts) + `rngarg_<tag>` (the arg) + `axid_/axt_` (the PROPERTIES,
# read off the NODE through `UOp.axis_id` / `UOp.axis_type` and not off the fixture's
# literals -- see the note above `UOp.axis_id` for why that is the difference between a
# gated property and a dead claim).
#
# `rngarg_<tag>` spells the port's OWN `ARange` encoding, `(ids, at)`, which is the wall
# -- see the block above `UOp.range_end` -- so every `rngarg_*` row is BEND-ONLY.
def Rng.arg(arg: Arg) -> String:
  match arg:
    case ARange{ids, at}: String.concat(["(", IdsStr(ids), ",", AxisType.name(at), ")/len=2"])
    case _: "!NotARange"

def AxIds.of(m: Maybe<&2, List<&2, U32>>) -> String:
  match m:
    case Some{ids}: IdsStr.ids(ids)
    case None{}: "!NotARange"

def AxTypes.of(m: Maybe<&2, AxisType>) -> String:
  match m:
    case Some{at}: AxisType.name(at)
    case None{}: "!NotARange"

def t_rng_row(+nm: String, +ar: Arena, +self: U32) -> IO(Unit):
  do IO<Unit>:
    srow("rng_" ++ nm, Rng.sig(ar, self))
    srow("rngarg_" ++ nm, Rng.arg(Arena.arg(ar, self)))
    srow("axid_" ++ nm, AxIds.of(UOp.axis_id(Arena.arg(ar, self))))
    srow("axt_" ++ nm, AxTypes.of(UOp.axis_type(Arena.arg(ar, self))))

# ONE BUILD PER ROW, one def per fixture. `g_rng_*` returns a `Found` over an affine
# arena, so `main` cannot call it twice to get `.ar` and `.i`: the two calls build two
# arenas and the signature would be over one node read from the other.
def t_rng_weak1() -> IO(Unit):
  +f = g_rng_weak1()
  t_rng_row("weak1", Found.ar(f), Found.i(f))

def t_rng_loop1() -> IO(Unit):
  +f = g_rng_loop1()
  t_rng_row("loop1", Found.ar(f), Found.i(f))

def t_rng_dev3() -> IO(Unit):
  +f = g_rng_dev3()
  t_rng_row("dev3", Found.ar(f), Found.i(f))

def t_rng_loopfn() -> IO(Unit):
  +f = g_rng_loopfn()
  t_rng_row("loopfn", Found.ar(f), Found.i(f))

def t_rng_twoid() -> IO(Unit):
  +f = g_rng_twoid()
  t_rng_row("twoid", Found.ar(f), Found.i(f))

# ---------------------------------------------------------------------------
# THE BACKWARD-SLICE LANE -- ops.py:280, :286, :289. The three defs are above
# `pm_r_sink`; the fixtures and the rows are here because a row is a fixture plus
# a printer and both of those belong with the other gates.
#
# CPython answers, read live off the oracle's tree:
#     bsl_chain=5    Ops.CONST Ops.RANGE Ops.CONST Ops.ADD Ops.CONST
#     bsl_call=1     Ops.CONST
#     bsl_nest=3     Ops.CONST Ops.CALL Ops.CONST
#     bsl_backedge=3 Ops.CONST Ops.RANGE Ops.CONST
# and `toposort(enter_calls=True)` answers 6, 5, 6 and 4 for the same four. So
# the `call`, `nest` and `backedge` rows are the ones that carry
# `enter_calls=False`, and `bsl_chain` would agree with a `toposort`.
#
# THE FIXTURES ARE THE SMALLEST GRAPHS THAT SEPARATE THE FOUR ANSWERS, and each
# is named for the thing it separates rather than for its shape:
#   chain    no CALL anywhere, so the two walks agree -- the baseline.
#   call     a CALL AT THE ROOT, whose body is src[0] and so is dropped.
#   nest     the same CALL ONE LEVEL DOWN, so the pruning cannot be a special
#            case on the root.
#   backedge `src[0] is src[2]`, so the walk meets the same RANGE twice and it is
#            the CACHE that makes it terminate. `g_cycle` is NOT this fixture: it
#            reads `Found.i(r)` out of `Found.ar(sp)`, and `g_rng()` builds in a
#            different arena, so that index is past the end and `Arena.node`
#            answers the bottom for it. The wall is "an arena is the one a build
#            RETURNED, not the one that went in", and this fixture threads it.
# ---------------------------------------------------------------------------
def Bsl.facts(+xs: List<&2, U32>, ar: Arena) -> String:
  String.concat([Nat.show(List.length(&2, U32, xs)), " ", Rng.srcops.seeded(ar, xs)])

# `Arena.budget(ar)` IS the fuel and the header says why: one step per pushed
# frame, so it is exact for a DAG and is only ever reached on one by cutting.
# Hoisting it here keeps four rows from each re-deriving it.
def Bsl.row(+ar: Arena, +self: U32) -> String:
  Bsl.facts(UOp.backward_slice(Arena.budget(ar), ar, self), ar)

def Bsl.with_self(+ar: Arena, +self: U32) -> String:
  Bsl.facts(UOp.backward_slice_with_self(Arena.budget(ar), ar, self), ar)

def Bsl.op_in(+ar: Arena, +self: U32, want: List<&2, Op>) -> Bool:
  UOp.op_in_backward_slice_with_self(Arena.budget(ar), ar, self, want)

# CONST(0), CONST(1) <- RANGE(LOOP, 0) <- ADD <- ADD, which is CPython's
# `UOp.range(1, 0, AxisType.LOOP)`, an ADD of it with CONST(0) and an ADD of that
# with CONST(2). A range's end is a src of its own, which is why there are three
# CONSTs here and not two.
def g_bsl_chain() -> Found:
  +c0 = UOp.const(Arena.empty(), CInt{H.i64_of_i32(0)})
  +c1 = UOp.const(Found.ar(c0), CInt{H.i64_of_i32(1)})
  +c2 = UOp.const(Found.ar(c1), CInt{H.i64_of_i32(2)})
  +r0 = UOp.range_end(Found.ar(c2), Found.i(c1), [0], AXIS_LOOP{})
  +a0 = UOp.alu(Found.ar(r0), OpsADD{}, [Found.i(r0), Found.i(c0)])
  UOp.alu(Found.ar(a0), OpsADD{}, [Found.i(a0), Found.i(c2)])

# CALL(ADD(CONST(1), CONST(2)), CONST(9)). The BODY is src[0] and
# `src_without_body` is `src[1:]`, so the three body nodes are not in the slice.
def g_bsl_call() -> Found:
  +c1 = UOp.const(Arena.empty(), CInt{H.i64_of_i32(1)})
  +c2 = UOp.const(Found.ar(c1), CInt{H.i64_of_i32(2)})
  +c9 = UOp.const(Found.ar(c2), CInt{H.i64_of_i32(9)})
  +b = UOp.alu(Found.ar(c9), OpsADD{}, [Found.i(c1), Found.i(c2)])
  UOp.new(Found.ar(b), OpsCALL{}, [Found.i(b), Found.i(c9)], ACall{CallInfo.of()}, TNone{})

# ADD(CALL(..), CONST(2)) -- the same CALL, one level down.
def g_bsl_nest() -> Found:
  +c1 = UOp.const(Arena.empty(), CInt{H.i64_of_i32(1)})
  +c2 = UOp.const(Found.ar(c1), CInt{H.i64_of_i32(2)})
  +c9 = UOp.const(Found.ar(c2), CInt{H.i64_of_i32(9)})
  +b = UOp.alu(Found.ar(c9), OpsADD{}, [Found.i(c1), Found.i(c2)])
  +cl = UOp.new(Found.ar(b), OpsCALL{}, [Found.i(b), Found.i(c9)], ACall{CallInfo.of()}, TNone{})
  UOp.alu(Found.ar(cl), OpsADD{}, [Found.i(cl), Found.i(c2)])

# BACKEDGE(RANGE(DEVICE, 0), CONST(0), RANGE(DEVICE, 0)) -- ops.py:617's
# `self.backedge(loop, cond)` with `cond` the same node as `self`, so the walk
# meets the RANGE twice and the shared node must appear ONCE.
def g_bsl_backedge() -> Found:
  +c0 = UOp.const(Arena.empty(), CInt{H.i64_of_i32(0)})
  +c1 = UOp.const(Found.ar(c0), CInt{H.i64_of_i32(1)})
  +r = UOp.range_end(Found.ar(c1), Found.i(c1), [0], AXIS_DEVICE{})
  UOp.backedge(Found.ar(r), Found.i(r), Found.i(c0), Found.i(r))

# ONE PURE DEF PER ROW, named after the row, because a `do IO<Unit>` block can
# only bind an `IO` -- so the arena has to be built in a def BODY. That is the
# same reason `MStack.sig` and `Uc.depth` are the shape they are.
#
# `bsop_chain_add` is the SRC half and `bsop_chain_mul` is the miss; `bsop_call_call`
# is the SELF half, because CALL is in no src of that slice so only reading `self`
# answers True. `bsop_nest_pair` is the `*ops` list, which is `*args` in Python.
def Bsl.chain() -> String:
  +f = g_bsl_chain()
  Bsl.row(Found.ar(f), Found.i(f))

def Bsl.chain.ws() -> String:
  +f = g_bsl_chain()
  Bsl.with_self(Found.ar(f), Found.i(f))

def Bsl.chain.add() -> String:
  +f = g_bsl_chain()
  Bool.show(Bsl.op_in(Found.ar(f), Found.i(f), [OpsADD{}]))

def Bsl.chain.mul() -> String:
  +f = g_bsl_chain()
  Bool.show(Bsl.op_in(Found.ar(f), Found.i(f), [OpsMUL{}]))

def Bsl.call() -> String:
  +f = g_bsl_call()
  Bsl.row(Found.ar(f), Found.i(f))

def Bsl.call.ws() -> String:
  +f = g_bsl_call()
  Bsl.with_self(Found.ar(f), Found.i(f))

def Bsl.call.call() -> String:
  +f = g_bsl_call()
  Bool.show(Bsl.op_in(Found.ar(f), Found.i(f), [OpsCALL{}]))

def Bsl.nest() -> String:
  +f = g_bsl_nest()
  Bsl.row(Found.ar(f), Found.i(f))

def Bsl.nest.ws() -> String:
  +f = g_bsl_nest()
  Bsl.with_self(Found.ar(f), Found.i(f))

def Bsl.nest.pair() -> String:
  +f = g_bsl_nest()
  Bool.show(Bsl.op_in(Found.ar(f), Found.i(f), [OpsMUL{}, OpsCALL{}]))

# `bsop_backedge_backedge` is the SELF half again and `bsop_backedge_range` the
# SRC half on the fixture where the two nodes are not the same op, so neither
# answer can be produced by reading only one of them.
def Bsl.backedge() -> String:
  +f = g_bsl_backedge()
  Bsl.row(Found.ar(f), Found.i(f))

def Bsl.backedge.ws() -> String:
  +f = g_bsl_backedge()
  Bsl.with_self(Found.ar(f), Found.i(f))

def Bsl.backedge.be() -> String:
  +f = g_bsl_backedge()
  Bool.show(Bsl.op_in(Found.ar(f), Found.i(f), [OpsBACKEDGE{}]))

def Bsl.backedge.range() -> String:
  +f = g_bsl_backedge()
  Bool.show(Bsl.op_in(Found.ar(f), Found.i(f), [OpsRANGE{}]))

# ===========================================================================
# THE GATE for the ops.py:501-1928 block above. The CPython lane is
# `.agents/slop/ops-501-oracle.py` and the diff is `.agents/slop/ops-501-gate.sh`.
# Every row name starts `s5_` so the gate filters by PREFIX: a row that MOVED
# cannot be silently dropped, and filtering by position is what drops one.
#
# WHY THE PORT'S ANSWER IS AN INDEX AND CPython'S IS A NAME. `UOp.base` and its
# five siblings answer a `U32` arena index, and an index is meaningless outside
# the arena that produced it, so a numeric diff would compare two unrelated
# numberings. What is comparable is what the index POINTS AT, and that is the op
# name through `Ops.name` -- the same decision `codegen/__init__.bend`'s
# `gr-diff.sh` made and for the same reason.
#
# THE FIXTURES ARE THE SMALLEST GRAPHS THAT SEPARATE TWO ANSWERS, and each is named
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
# ===========================================================================

def s5.pa(slot: U32) -> ParamArg: ParamArg.of(slot, S.int32())

def s5.arena() -> Arena:
  Arena{[
    Arena.bottom(),
    Node{OpsCONST{}, Nil{}, APy{CInt{H.i64_of_i32(3)}}, TNone{}},
    Node{OpsBUFFER{}, Nil{}, AParam{s5.pa(1)}, TNone{}},
    Node{OpsPARAM{}, Nil{}, AParam{s5.pa(2)}, TNone{}},
    Node{OpsALLOC{}, Nil{}, AParam{s5.pa(3)}, TNone{}},
    Node{OpsRESHAPE{}, [2, 10], ATuple{[0]}, TNone{}},
    Node{OpsRESHAPE{}, [5], ATuple{Nil{}}, TNone{}},
    Node{OpsUNSHARD{}, [2, 11], ATuple{[0]}, TNone{}},
    Node{OpsBITCAST{}, [2], ADt{S.single()}, TNone{}},
    Node{OpsAFTER{}, [2], ANone{}, TNone{}},
    Node{OpsSTACK{}, [1, 1], APy{CInvalid{}}, TNone{}},
    Node{OpsRANGE{}, [1], ARange{[0], AXIS_DEVICE{}}, TNone{}},
    Node{OpsSINK{}, [12], AKernel{KernelInfo.of()}, TNone{}},
    Node{OpsLINEAR{}, [2], ANone{}, TNone{}},
    Node{OpsADD{}, [1, 1], ANone{}, TNone{}},
    Node{OpsADD{}, [14, 16], ANone{}, TNone{}},
    Node{OpsMUL{}, [1, 14], ANone{}, TNone{}},
    Node{OpsADD{}, [16, 1], ANone{}, TNone{}},
    Node{OpsDETACH{}, [2], ANone{}, TNone{}}
  ], [0]}

# The nine fixture indices, as a `Data` record so the row table reads them by name
# and a fixture cannot be swapped for another without the row changing.
type S5 is Data: S5{c: U32, b: U32, p: U32, a: U32, r1: U32, r2: U32, us: U32, bc: U32, af: U32}

def s5.ids() -> S5: S5{1, 2, 3, 4, 5, 6, 7, 8, 9}

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

# ---------------------------------------------------------------------------
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
# ---------------------------------------------------------------------------
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

# `Shard{ax, rng}` is a `Data` record so it is destructured; the pair is printed
# as `axis:RANGE` and a fixture whose src[1] is not a RANGE would print its own
# op name, which is the point.
# One pair per line of the list, `axis:RANGE`, and the arena is the FIXTURE's so
# the name is the RANGE's and not the bottom's.
def s5.one(ar: Arena, ax: U32, rng: U32) -> String:
  String.concat([U32.show(ax), ":", s5.name(ar, rng)])

def s5.shardstr.go(+ar: Arena, xs: List<&2, Shard>, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case Shard{ax, rng} <> t:
      s5.shardstr.go(ar, t, String.concat([acc, " ", s5.one(ar, ax, rng)]))

def s5.shardstr(+ar: Arena, xs: List<&2, Shard>) -> String:
  match xs:
    case Nil{}: ""
    case Shard{ax, rng} <> t: s5.shardstr.go(ar, t, s5.one(ar, ax, rng))

# THE ROWS. One `String` row per answer, and every walk takes `Arena.budget(ar)` as
# its fuel -- the only sound one, for the reason the header gives: one step per
# peel and one per worklist entry, and both are bounded by the arena.
def s5.walk(+fuel: Nat, +ar: Arena, self: U32) -> String:
  String.concat([s5.name(ar, UOp.base(fuel, ar, self))])

def s5.walk.u(+fuel: Nat, +ar: Arena, self: U32) -> String:
  String.concat([s5.name(ar, UOp.unsharded_base(fuel, ar, self))])

def s5.walk.s(+fuel: Nat, +ar: Arena, self: U32) -> String:
  String.concat([s5.name(ar, UOp.storage_base(fuel, ar, self))])

def s5.walk.w(+fuel: Nat, +ar: Arena, self: U32) -> String:
  String.concat([s5.name(ar, UOp.without_after(fuel, ar, self))])

def s5.walk.b(+fuel: Nat, +ar: Arena, self: U32) -> String:
  String.concat([s5.name(ar, UOp.buf_uop(fuel, ar, self))])

# The nine base-family rows, one call site each, so a def nothing calls has no row
# and cannot hide. `s5.walk*` are six one-liners rather than one parameterised
# def because Bend has no function values: a function in a datatype field forces
# `Type`, and a `Type` cannot be passed an arena.
def s5.base(+fuel: Nat, +ar: Arena, +f: S5) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("s5_base_c", s5.walk(fuel, ar, S5.c(f)))
    b : Unit <- srow("s5_base_b", s5.walk(fuel, ar, S5.b(f)))
    c : Unit <- srow("s5_base_p", s5.walk(fuel, ar, S5.p(f)))
    d : Unit <- srow("s5_base_a", s5.walk(fuel, ar, S5.a(f)))
    e : Unit <- srow("s5_base_r1", s5.walk(fuel, ar, S5.r1(f)))
    g : Unit <- srow("s5_base_r2", s5.walk(fuel, ar, S5.r2(f)))
    h : Unit <- srow("s5_base_us", s5.walk(fuel, ar, S5.us(f)))
    i : Unit <- srow("s5_base_bc", s5.walk(fuel, ar, S5.bc(f)))
    j : Unit <- srow("s5_base_af", s5.walk(fuel, ar, S5.af(f)))
    srow("s5_base_detach", s5.walk(fuel, ar, 18))

def s5.unsharded(+fuel: Nat, +ar: Arena, +f: S5) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("s5_unsharded_base_c", s5.walk.u(fuel, ar, S5.c(f)))
    b : Unit <- srow("s5_unsharded_base_b", s5.walk.u(fuel, ar, S5.b(f)))
    c : Unit <- srow("s5_unsharded_base_p", s5.walk.u(fuel, ar, S5.p(f)))
    d : Unit <- srow("s5_unsharded_base_a", s5.walk.u(fuel, ar, S5.a(f)))
    e : Unit <- srow("s5_unsharded_base_r1", s5.walk.u(fuel, ar, S5.r1(f)))
    g : Unit <- srow("s5_unsharded_base_r2", s5.walk.u(fuel, ar, S5.r2(f)))
    h : Unit <- srow("s5_unsharded_base_us", s5.walk.u(fuel, ar, S5.us(f)))
    i : Unit <- srow("s5_unsharded_base_bc", s5.walk.u(fuel, ar, S5.bc(f)))
    j : Unit <- srow("s5_unsharded_base_af", s5.walk.u(fuel, ar, S5.af(f)))
    srow("s5_unsharded_base_detach", s5.walk.u(fuel, ar, 18))

def s5.storage(+fuel: Nat, +ar: Arena, +f: S5) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("s5_storage_base_c", s5.walk.s(fuel, ar, S5.c(f)))
    b : Unit <- srow("s5_storage_base_b", s5.walk.s(fuel, ar, S5.b(f)))
    c : Unit <- srow("s5_storage_base_p", s5.walk.s(fuel, ar, S5.p(f)))
    d : Unit <- srow("s5_storage_base_a", s5.walk.s(fuel, ar, S5.a(f)))
    e : Unit <- srow("s5_storage_base_r1", s5.walk.s(fuel, ar, S5.r1(f)))
    g : Unit <- srow("s5_storage_base_r2", s5.walk.s(fuel, ar, S5.r2(f)))
    h : Unit <- srow("s5_storage_base_us", s5.walk.s(fuel, ar, S5.us(f)))
    i : Unit <- srow("s5_storage_base_bc", s5.walk.s(fuel, ar, S5.bc(f)))
    j : Unit <- srow("s5_storage_base_af", s5.walk.s(fuel, ar, S5.af(f)))
    srow("s5_storage_base_detach", s5.walk.s(fuel, ar, 18))

def s5.woafter(+fuel: Nat, +ar: Arena, +f: S5) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("s5_wo_after_c", s5.walk.w(fuel, ar, S5.c(f)))
    b : Unit <- srow("s5_wo_after_b", s5.walk.w(fuel, ar, S5.b(f)))
    e : Unit <- srow("s5_wo_after_r1", s5.walk.w(fuel, ar, S5.r1(f)))
    h : Unit <- srow("s5_wo_after_us", s5.walk.w(fuel, ar, S5.us(f)))
    i : Unit <- srow("s5_wo_after_af", s5.walk.w(fuel, ar, S5.af(f)))
    srow("s5_wo_after_detach", s5.walk.w(fuel, ar, 18))

def s5.bufuop(+fuel: Nat, +ar: Arena, +f: S5) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("s5_buf_uop_c", s5.walk.b(fuel, ar, S5.c(f)))
    b : Unit <- srow("s5_buf_uop_b", s5.walk.b(fuel, ar, S5.b(f)))
    c : Unit <- srow("s5_buf_uop_p", s5.walk.b(fuel, ar, S5.p(f)))
    e : Unit <- srow("s5_buf_uop_r1", s5.walk.b(fuel, ar, S5.r1(f)))
    g : Unit <- srow("s5_buf_uop_r2", s5.walk.b(fuel, ar, S5.r2(f)))
    i : Unit <- srow("s5_buf_uop_bc", s5.walk.b(fuel, ar, S5.bc(f)))
    j : Unit <- srow("s5_buf_uop_af", s5.walk.b(fuel, ar, S5.af(f)))
    srow("s5_buf_uop_detach", s5.walk.b(fuel, ar, 18))

# `has_buffer_identity` answers a `Bool`, and BOTH values of `after_ok` are rows:
# the two differ on exactly one fixture, so a port that dropped the parameter would
# agree on the other eight and be wrong on the ninth.
def s5.hbi.t(+fuel: Nat, after_ok: Bool, +ar: Arena, f: S5) -> String:
  U32.show(Bool.to_u32(UOp.has_buffer_identity(fuel, after_ok, ar, S5.c(f))))

def s5.hbi(+fuel: Nat, +ar: Arena, +f: S5) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("s5_hbi_c", UOp.has_buffer_identity(fuel, False{}, ar, S5.c(f)))
    b : Unit <- row("s5_hbi_b", UOp.has_buffer_identity(fuel, False{}, ar, S5.b(f)))
    c : Unit <- row("s5_hbi_p", UOp.has_buffer_identity(fuel, False{}, ar, S5.p(f)))
    d : Unit <- row("s5_hbi_a", UOp.has_buffer_identity(fuel, False{}, ar, S5.a(f)))
    e : Unit <- row("s5_hbi_r1", UOp.has_buffer_identity(fuel, False{}, ar, S5.r1(f)))
    g : Unit <- row("s5_hbi_r2", UOp.has_buffer_identity(fuel, False{}, ar, S5.r2(f)))
    h : Unit <- row("s5_hbi_us", UOp.has_buffer_identity(fuel, False{}, ar, S5.us(f)))
    i : Unit <- row("s5_hbi_bc", UOp.has_buffer_identity(fuel, False{}, ar, S5.bc(f)))
    j : Unit <- row("s5_hbi_af", UOp.has_buffer_identity(fuel, False{}, ar, S5.af(f)))
    w : Unit <- row("s5_hbi_detach", UOp.has_buffer_identity(fuel, False{}, ar, 18))
    k : Unit <- row("s5_hbi_after_c", UOp.has_buffer_identity(fuel, True{}, ar, S5.c(f)))
    l : Unit <- row("s5_hbi_after_b", UOp.has_buffer_identity(fuel, True{}, ar, S5.b(f)))
    m : Unit <- row("s5_hbi_after_p", UOp.has_buffer_identity(fuel, True{}, ar, S5.p(f)))
    n : Unit <- row("s5_hbi_after_a", UOp.has_buffer_identity(fuel, True{}, ar, S5.a(f)))
    o : Unit <- row("s5_hbi_after_r1", UOp.has_buffer_identity(fuel, True{}, ar, S5.r1(f)))
    q : Unit <- row("s5_hbi_after_r2", UOp.has_buffer_identity(fuel, True{}, ar, S5.r2(f)))
    r : Unit <- row("s5_hbi_after_us", UOp.has_buffer_identity(fuel, True{}, ar, S5.us(f)))
    t : Unit <- row("s5_hbi_after_bc", UOp.has_buffer_identity(fuel, True{}, ar, S5.bc(f)))
    u : Unit <- row("s5_hbi_after_af", UOp.has_buffer_identity(fuel, True{}, ar, S5.af(f)))
    row("s5_hbi_after_detach", UOp.has_buffer_identity(fuel, True{}, ar, 18))

# `split_uop` -- the sequence, and the ORDER is the fact. Five fixtures and the
# middle one is the one that matters: `nest` is ADD[MUL[CONST,ADD[...]],CONST],
# so a fold that pushed at the BACK answers `CONST,ADD,CONST,MUL` and one that
# pushed at the FRONT answers `MUL,CONST,CONST`, and both have length 3.
def s5.split(+fuel: Nat, +ar: Arena, i: U32, sep: Op) -> String:
  s5.seps(ar, UOp.split_uop(fuel, ar, i, sep))

def s5.splitrows(+fuel: Nat, +ar: Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("s5_split_const", s5.split(fuel, ar, 1, OpsADD{}))
    b : Unit <- srow("s5_split_add", s5.split(fuel, ar, 14, OpsADD{}))
    c : Unit <- srow("s5_split_nest", s5.split(fuel, ar, 15, OpsADD{}))
    d : Unit <- srow("s5_split_diamond", s5.split(fuel, ar, 16, OpsMUL{}))
    e : Unit <- srow("s5_split_mismatch", s5.split(fuel, ar, 17, OpsMUL{}))
    srow("s5_split_left", s5.split(fuel, ar, 16, OpsADD{}))

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

# `sint_to_uop` answers a `Found` because the `SI` arm MINTS, so the row prints the
# op name of the node it made -- CONST for the literal arm, and the `SU` arm prints
# the name of the node that already existed, which is what makes `s5_sint_uop`
# different from `s5_sint_const`. Split in three because `f` is read twice and a
# `do IO<Unit>` block can only bind an `IO`.
def s5.sint.go(ar: Arena, i: U32) -> String: s5.name(ar, i)

def s5.sint.of(+f: Found) -> String: s5.sint.go(Found.ar(f), Found.i(f))

def s5.sint(ar: Arena, s: Sint) -> String: s5.sint.of(UOp.sint_to_uop(ar, s))

type DRng is Data: DRng{ar: Arena, ys: List<&2, U32>}

def DRng.ar(+d: DRng) -> Arena:
  match d:
    case DRng{ar, ys}: ar

def DRng.ys(+d: DRng) -> List<&2, U32>:
  match d:
    case DRng{ar, ys}: ys

def DRng.of(+f: Found) -> DRng: DRng{Found.ar(f), [Found.i(f)]}

def s5.cint(+v: Const) -> Maybe<&2, H.I64>:
  match v:
    case CInt{i}: Some{i}
    case _: None{}

def s5.cend.of(+arg: Arg) -> Maybe<&2, H.I64>:
  match arg:
    case APy{v}: s5.cint(v)
    case _: None{}

def s5.maybe_i64(m: Maybe<&2, H.I64>) -> String:
  match m:
    case Some{i}: H.i64_text(i)
    case None{}: "-"

def s5.dr.of(+ar: Arena, xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}: "-"
    case +h <> _:
      String.concat([s5.name(ar, h), ":", s5.maybe_i64(s5.cend.of(Arena.arg(ar, Arena.src(ar, h, 0))))])

def s5.dr(d: DRng) -> String:
  match d:
    case DRng{ar, ys}: s5.dr.of(ar, ys)

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
    Node{OpsMSELECT{}, [1, 2], ABlob{BLOB_A()}, TNone{}},
    Node{OpsLINEAR{}, [1], ANone{}, TNone{}},
    Node{OpsCONST{}, Nil{}, APy{CInt{H.i64_of_i32(3)}}, TNone{}},
    Node{OpsRESHAPE{}, [1, 14], ATuple{[0]}, TNone{}},
    Node{OpsAFTER{}, [1], ANone{}, TNone{}},
    Node{OpsADD{}, [1, 1], ANone{}, TNone{}},
    Node{OpsSTACK{}, [10, 10], ANone{}, TNone{}}
  ], [0]}

def s5.ga.of(+f: Found) -> String: s5.minted.go(Found.ar(f), f)

def s5.minted.row(nm: String, +f: Found) -> IO(Unit):
  srow(nm, s5.minted.go(Found.ar(f), f))

# `gate_kernel_sink` and `sint_to_uop` are the two module-level defs, and
# `s5_gate_*` is one row per ARM: a port that collapsed the two negative tests
# would answer 1 on one of the first two and the third row would not see it.
def s5.gate(+ar: Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("s5_gate_linear", gate_kernel_sink(ar, 13))
    b : Unit <- row("s5_gate_kernel", gate_kernel_sink(ar, 12))
    row("s5_gate_plain", gate_kernel_sink(ar, 2))

# The index row. Every fixture's index is its POSITION in the literal node list
# above, and this prints them, so a miscount is a visible row rather than a silent
# re-labelling of the fixtures. The arithmetic being easy is exactly why it needs
# a row.
def s5.idx(+ar: Arena, +f: S5) -> IO(Unit):
  srow("s5_idx", String.concat([Ops.name(Arena.op(ar, S5.c(f))), ",",
    Ops.name(Arena.op(ar, S5.b(f))), ",", Ops.name(Arena.op(ar, S5.p(f))), ",",
    Ops.name(Arena.op(ar, S5.a(f))), ",", Ops.name(Arena.op(ar, S5.r1(f))), ",",
    Ops.name(Arena.op(ar, S5.r2(f))), ",", Ops.name(Arena.op(ar, S5.us(f))), ",",
    Ops.name(Arena.op(ar, S5.bc(f))), ",", Ops.name(Arena.op(ar, S5.af(f)))]))


type CLike is Data:
  CU{u: U32}
  CV{v: Const}

# `ufix` -- ops.py:606. `if isinstance(x, UOp): return x; return UOp.const(x)`.
# The guard is the union and the two arms are the whole of it. MEASURED, because
# `UOp.const` reaches a UOp through `isinstance(b, UOp): return b.cast(dtype)` and
# a cast MIGHT have been a mint: `UOp.const(0).ufix(UOp.const(0)) is UOp.const(0)`
# and `UOp(Ops.BUFFER, arg=ParamArg(1, dtypes.int32)).ufix(...)` is itself too, so
# the `CU` arm returns the node and MINTS NOTHING.
#
# THE SIBLING IS NOT THE SAME DEF, and the measurement is why. `sint_to_uop(x,
# dtypes.weakint)` is `UOp.const(x, weakint)`, which for a UOp is `x.cast(weakint)`
# -- and for a BUFFER that is a REAL CAST, not a fold. So `UOp.sint_to_uop`'s `SU`
# arm below DIVERGES for any node whose dtype is not weak; see the TODO on it.
def clike.uop_of(x: CLike) -> Maybe<&2, U32>:
  match x:
    case CU{u}: Some{u}
    case CV{v}: None{}
def clike.val(x: CLike) -> Const:
  match x:
    case CU{u}: CInt{H.i64_of_i32(u)}
    case CV{v}: v
def UOp.ufix.of(ar: Arena, hit: Maybe<&2, U32>, v: Const) -> Found:
  match hit:
    case Some{u}: Found{ar, u}
    case None{}: UOp.const(ar, v)
def UOp.ufix.of2(ar: Arena, +x: CLike) -> Found:
  UOp.ufix.of(ar, clike.uop_of(x), clike.val(x))

# R-3: the two readers are above `UOp.ufix.of2`, and `Maybe` is read ONCE per arm
# so it is the payload that cannot be `+`'d, not the union.
def UOp.ufix(ar: Arena, x: CLike) -> Found: UOp.ufix.of2(ar, x)

# `body` -- ops.py:562. `if self.op is not Ops.CALL: raise; return self.src[0]`.
# The `raise` is the `Maybe`, which is this file's standing spelling for it (see
# `UOp.axis_id` above), and `src[0]` is `Arena.src0`. The op is a PARAMETER because
# a `match` may not scrutinise `Arena.op(ar, self)`.
def UOp.body.of(op: Op, src0: U32) -> Maybe<&2, U32>:
  match op:
    case OpsCALL{}: Some{src0}
    case _: None{}

def UOp.body(+ar: Arena, +self: U32) -> Maybe<&2, U32>:
  UOp.body.of(Arena.op(ar, self), Arena.src0(ar, self))

# `is_inline_call` -- ops.py:567. `self.op is Ops.CALL and self.body.op is
# Ops.SINK and self.body.arg is None and not self.arg.precompile`. FOUR conjuncts
# and a `Maybe` answer, and the `Maybe` is not decoration: `self.arg` is a
# `CallInfo` in the pin's `Arg` and a `CustomFunction` upstream, and CPython raises
# AttributeError on the second, so `None` is that raise. It is the same spelling
# `UOp.body`'s `None` is for its RuntimeError, and the two Nones mean different
# things on purpose.
#
# The first two conjuncts are combined into ONE `Bool` parameter and the last two
# are separate `match` arms, which looks arbitrary and is not: the first two are
# OP tests and the last two are ARG tests, and an `Arg` can only be matched where
# it is a binder. The four are separated by FIXTURE rather than by def, which is
# the honest arrangement -- a CALL with a non-SINK body, a non-CALL, a SINK body
# with a `KernelInfo` arg and a `precompile=True` arg are four rows and each one
# moves if its own conjunct is dropped.
def UOp.is_inline_call.pre(arg: Arg) -> Maybe<&2, Bool>:
  match arg:
    case ACall{ci}: Some{Bool.not(CallInfo.precompile(ci))}
    case _: None{}

def UOp.is_inline_call.anon(barg: Arg, +arg: Arg) -> Maybe<&2, Bool>:
  match barg:
    case ANone{}: UOp.is_inline_call.pre(arg)
    case _: Some{False{}}

def UOp.is_inline_call.of(heads: Bool, barg: Arg, +arg: Arg) -> Maybe<&2, Bool>:
  match heads:
    case True{}: UOp.is_inline_call.anon(barg, arg)
    case False{}: Some{False{}}

def UOp.is_inline_call(+ar: Arena, +self: U32) -> Maybe<&2, Bool>:
  +b = Arena.src0(ar, self)
  UOp.is_inline_call.of(
    Bool.and(eq_op(Arena.op(ar, self), OpsCALL{}), eq_op(Arena.op(ar, b), OpsSINK{})),
    Arena.arg(ar, b), Arena.arg(ar, self))

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
# NEITHER ARM NEEDS `simplify` FOR THE NODES THAT MATTER HERE, and that is the finding rather than
# a convenience. `simplify` is a documented wall in this file (`ops.py:511`, "*** uop evaluation
# ***"), so anything behind it is behind the largest subsystem here -- but a CONST is already
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
# ONE DEF, NOT TWO, AND MUTUAL RECURSION IS WHY. The obvious shape has the CAST arm ask `ssimplify_of`
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

# AND THE ROW THAT SAYS IT HIT, separately from the value's presence. A reader that always
# returned `None{}` would satisfy every value row, and one that ignored the op would satisfy
# every hit row; the pair is what makes both fail.
def UOp.pop_const_hits(+ar: Arena, +i: U32, op: Op) -> Bool:
  Bool.and(eq_op(Arena.op(ar, i), op),
           eq_op(Arena.op(ar, Arena.src(ar, i, 1)), OpsCONST{}))

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

# `ins` -- ops.py:622. `UOp(Ops.INS, kwargs.pop("src", self.src), (arg,
# kwargs.pop("dtype", self.dtype)), kwargs.pop("tag", self.tag))`. TWO of the three
# defaults are ARENA READS and one is `fold.bend`'s, so two are here and the third
# is the `dt` PARAMETER. That split is the point of the def: a port that spelled
# all three at each call site would copy `self.src` and `self.tag` by hand at
# every one of them, and a hand copy is where two sites drift apart. The `tag`
# default is load-bearing and the row says so: the fixture is a node with a
# non-`TNone` tag, and a port that hardcoded `TNone` would agree on every other
# fixture in the file.
def UOp.ins.of(+ar: Arena, +self: U32, nm: String, dt: S.Dt) -> Found:
  UOp.new(ar, OpsINS{}, Arena.srcs(ar, self), AInk{nm, dt}, Arena.tag(ar, self))

# `wmma` -- ops.py:649. `UOp(Ops.WMMA, src=(a, b, acc), arg=(dims, a.dtype,
# threads, tc_upcast_axes))`. "dtype_in is stored in the arg (not derived from
# src[0].dtype) because bitcast rewrites change src dtypes" -- so `dt` is the
# arg's OWN field, and that comment is why this def takes it rather than reading
# it back off `a`.
def UOp.wmma(ar: Arena, a: U32, b: U32, acc: U32, dims: List<&2, U32>, dt: S.Dt, threads: U32, tc: List<&2, U32>) -> Found:
  UOp.new(ar, OpsWMMA{}, [a, b, acc], AWmma{dims, dt, threads, tc}, TNone{})

# `has_unbound_outputs` -- ops.py:570. `self.op is Ops.CALL and any((b:=
# x.unsharded_base).op is Ops.ALLOC and not b.arg.bind_on_realize for x in
# self.src[1:])`. THREE tests per element, and the src range is `Arena.src_to`:
# src[0] is the body and is not an output, which is a row and the only one that
# sees the `1`.
def UOp.huo.bor(arg: Arg) -> Bool:
  match arg:
    case AParam{pa}: Bool.not(ParamArg.bind_on_realize(pa))
    case _: True{}

def UOp.huo.at(fuel: Nat, +ar: Arena, x: U32) -> Bool:
  +b = UOp.unsharded_base(fuel, ar, x)
  Bool.and(eq_op(Arena.op(ar, b), OpsALLOC{}), UOp.huo.bor(Arena.arg(ar, b)))

# `Bool.or` does not short-circuit, so the whole list is walked even once the
# answer is known. That is not an optimisation miss: it is what makes the fold's
# cost a function of the src count alone rather than of where the hit is, and
# `UOp.unsharded_base` is fuel-bounded so the walk always terminates.
def UOp.huo.go(+fuel: Nat, +ar: Arena, xs: List<&2, U32>, hit: Bool) -> Bool:
  match xs:
    case Nil{}: hit
    case x <> t: UOp.huo.go(fuel, ar, t, Bool.or(hit, UOp.huo.at(fuel, ar, x)))

# The `self.op is Ops.CALL` half, and it is its own def because a CALL's src[1:] is
# a real list for EVERY op -- only the op test says the list means outputs.
def UOp.has_unbound_outputs.of(op: Op, fuel: Nat, ar: Arena, xs: List<&2, U32>) -> Bool:
  match op:
    case OpsCALL{}: UOp.huo.go(fuel, ar, xs, False{})
    case _: False{}

def UOp.has_unbound_outputs(fuel: Nat, +ar: Arena, +self: U32) -> Bool:
  UOp.has_unbound_outputs.of(Arena.op(ar, self), fuel, ar, Arena.src_from(ar, self, 1))


def sg.unbound.rows(+ar: Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("sg_huo_alloc", UOp.has_unbound_outputs(Arena.budget(ar), ar, 19))
    b : Unit <- row("sg_huo_bind", UOp.has_unbound_outputs(Arena.budget(ar), ar, 20))
    c : Unit <- row("sg_huo_buffer", UOp.has_unbound_outputs(Arena.budget(ar), ar, 21))
    d : Unit <- row("sg_huo_src0", UOp.has_unbound_outputs(Arena.budget(ar), ar, 18))
    g : Unit <- row("sg_huo_unshard", UOp.has_unbound_outputs(Arena.budget(ar), ar, 22))
    h : Unit <- row("sg_huo_noncall", UOp.has_unbound_outputs(Arena.budget(ar), ar, 26))
    row("sg_huo_op", UOp.has_unbound_outputs(Arena.budget(ar), ar, 23))

def sg.pa.put(p: ParamArg, bor: Bool) -> ParamArg:
  match p:
    case ParamArg{slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}:
      ParamArg{slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bor, val}

# `ParamArg.of` hardcodes `bind_on_realize=False` and this family needs both values
# of it, so the bound one is the same record with the field spelled. It is one def
# and not a second fourteen-field literal because two literals of a fourteen-field
# record are how eleven of the fields drift.
def sg.pa(sl: U32, bor: Bool) -> ParamArg: sg.pa.put(ParamArg.of(sl, S.int32()), bor)

def sg.ci() -> Arg: ACall{CallInfo{None{}, False{}, False{}, S.void()}}

def sg.arena() -> Arena:
  Arena{[
    Arena.bottom(),
    Node{OpsCONST{}, Nil{}, APy{CInt{H.i64_of_i32(0)}}, TNone{}},
    Node{OpsCONST{}, Nil{}, APy{CInt{H.i64_of_i32(1)}}, TNone{}},
    Node{OpsCONST{}, Nil{}, APy{CInt{H.i64_of_i32(2)}}, TNone{}},
    Node{OpsCONST{}, Nil{}, APy{CInvalid{}}, TNone{}},
    Node{OpsBUFFER{}, Nil{}, AParam{sg.pa(1, False{})}, TNone{}},
    Node{OpsADD{}, [1, 2], ANone{}, TInt{9}},
    Node{OpsALLOC{}, Nil{}, AParam{sg.pa(3, False{})}, TNone{}},
    Node{OpsALLOC{}, Nil{}, AParam{sg.pa(4, True{})}, TNone{}},
    Node{OpsUNSHARD{}, [7, 1], ATuple{[0]}, TNone{}},
    Node{OpsSTACK{}, [1, 2], ANone{}, TNone{}},
    Node{OpsSINK{}, [5], ANone{}, TNone{}},
    Node{OpsSINK{}, [5], AKernel{KernelInfo.of()}, TNone{}},
    Node{OpsCALL{}, [11], sg.ci(), TNone{}},
    Node{OpsCALL{}, [11], ACall{CallInfo{None{}, True{}, False{}, S.void()}}, TNone{}},
    Node{OpsCALL{}, [6], sg.ci(), TNone{}},
    Node{OpsCALL{}, [12], sg.ci(), TNone{}},
    Node{OpsCALL{}, [11], ACustom{CustomFunction{"f", S.void()}}, TNone{}},
    Node{OpsCALL{}, [7], sg.ci(), TNone{}},
    Node{OpsCALL{}, [11, 7], sg.ci(), TNone{}},
    Node{OpsCALL{}, [11, 8], sg.ci(), TNone{}},
    Node{OpsCALL{}, [11, 5], sg.ci(), TNone{}},
    Node{OpsCALL{}, [11, 9], sg.ci(), TNone{}},
    Node{OpsADD{}, [7, 1], ANone{}, TNone{}},
    Node{OpsADD{}, [1, 2], ANone{}, TNone{}},
    Node{OpsAFTER{}, [11], sg.ci(), TNone{}},
    Node{OpsADD{}, [1, 7], ANone{}, TNone{}}
  ], [0]}

def sg.seps(ar: Arena, xs: List<&2, U32>) -> String: s5.seps(ar, xs)

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

# THE FOUR FACTS of a minted node as one string, and the arena is the `Found`'s OWN.
# A mint GROWS the arena, so reading the caller's is the stale-arena bug
# bend2-constraints names at line 3854 -- and it PRINTS: the bottom is a NOOP, so a
# CAST interned into a discarded arena prints `Ops.NOOP` here and the gate catches
# it. That is the whole of what `sg_cconst_i32` is for, and it is why this def
# takes the `Found` rather than the caller's arena.
def sg.minted.of(+ar: Arena, +f: Found) -> String:
  String.concat([Ops.name(Arena.op(ar, Found.i(f))), "/", sg.seps(ar, Arena.srcs(ar, Found.i(f))),
    " ", sg.ctor(Arena.arg(ar, Found.i(f))), " t=", sg.tag(Arena.tag(ar, Found.i(f)))])

def sg.minted.go(ar: Arena, f: Found) -> String: sg.minted.of(ar, f)

def sg.minted.row(nm: String, +f: Found) -> IO(Unit): srow(nm, sg.minted.go(Found.ar(f), f))

# The `Maybe<&2, U32>` and `Maybe<&2, Bool>` printers. `none` is a Python RAISE in
# both cases -- `UOp.body` raises RuntimeError on a non-CALL and
# `UOp.is_inline_call` raises AttributeError on a CustomFunction arg -- and the
# oracle answers with the exception's NAME, so a row cannot be satisfied by a port
# that invented the spelling.
# `none:` NAMES the raise each `None` stands in for rather than printing a bare
# `none`. `UOp.body` is a RuntimeError and `UOp.is_inline_call` is an
# AttributeError, and the two are different facts: a port that returned `None` for
# some other reason would pass a bare `none` and fail these, which is the whole
# reason the exception's name is in the row.
def sg.maybe.go(hit: Maybe<&2, U32>, ar: Arena) -> String:
  match hit:
    case Some{i}: String.concat(["some:", Ops.name(Arena.op(ar, i))])
    case None{}: "none:RuntimeError"

def sg.pre.go(hit: Maybe<&2, Bool>) -> String:
  match hit:
    case Some{b}: String.concat(["some:", Bool.show(b)])
    case None{}: "none:AttributeError"

# ONE ROW PER TERM of `is_inline_call`'s four-term `and`. A four-term conjunction
# with one fixture is three dead terms, and this is the family of rows that says so:
# `pre` is `not self.arg.precompile`, `body` is `body.op is SINK`, `kernel` is
# `body.arg is None`, `add` is `op is CALL`, and `cfun` is the AttributeError.
def sg.invalid.isinv.of(+f: Found) -> Bool: UOp.is_invalid(Found.ar(f), Found.i(f))

def sg.invalid.isinv(ar: Arena) -> Bool: sg.invalid.isinv.of(UOp.invalid(ar))

def sg.idx.go(+ar: Arena, xs: List<&2, U32>, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case h <> t: sg.idx.go(ar, t, String.concat([acc, Ops.name(Arena.op(ar, h)), ","]))

def sg.idx.of(ar: Arena) -> String: sg.idx.go(ar, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26], "")

def sg.idx.str(ar: Arena) -> String: sg.idx.of(ar)

def sg.idx.tail(ar: Arena) -> IO(Unit): srow("sg_idx", sg.idx.str(ar))

def sg.ufix.name(+f: Found) -> String: Ops.name(Arena.op(Found.ar(f), Found.i(f)))

# THE INDEX ROW. Every fixture's index is its POSITION in the literal node list
# above and this prints the op name of each in that order, so a miscount is a
# visible row rather than a silent re-labelling of twenty-three rows. The
# arithmetic being easy is exactly why it needs a row.

def sg.ufix.rows(+ar: Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("sg_ufix_uop", sg.ufix.name(UOp.ufix(ar, CU{1})))
    b : Unit <- sg.minted.row("sg_ufix_lit", UOp.ufix(ar, CV{CInt{H.i64_of_i32(9)}}))
    row("sg_ufix_miss", U32.is_eq(Found.i(UOp.ufix(ar, CU{23})), 23))

def sg.index.rows2(+ar: Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- sg.minted.row("sg_index_st2", UOp.index(ar, 10, [2, 3]))
    b : Unit <- sg.minted.row("sg_store_nogate", UOp.store(ar, 5, 1, None{}))
    c : Unit <- sg.minted.row("sg_store_gate", UOp.store(ar, 5, 1, Some{2}))
    d : Unit <- sg.minted.row("sg_ins_tag", UOp.ins.of(ar, 6, "x", S.int32()))
    g : Unit <- sg.minted.row("sg_ins_none", UOp.ins.of(ar, 24, "x", S.int32()))
    h : Unit <- sg.minted.row("sg_wmma", UOp.wmma(ar, 5, 1, 6, [16, 16, 16], S.int32(), 32, Nil{}))
    i : Unit <- sg.ufix.rows(ar)
    sg.idx.tail(ar)

# `ufix` -- ops.py:606. THREE rows and the third is the one the def exists for:
# `sg_ufix_miss` is a CONST fixture, so a def that MINTED on the `CU` arm would
# answer it with a fresh index and `False`. The other two are the arm names -- the
# op for the `CU` arm and the arg for the `CV` arm -- because a two-arm def with one
# fixture is a one-arm def with a comment.

def sg.index.rows(+ar: Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("sg_index_hit1", U32.is_eq(Found.i(UOp.index(ar, 10, [2])), 2))
    b : Unit <- row("sg_index_hit0", U32.is_eq(Found.i(UOp.index(ar, 10, [1])), 1))
    c : Unit <- row("sg_index_hitmiss", U32.is_eq(Found.i(UOp.index(ar, 5, [2])), 2))
    d : Unit <- sg.minted.row("sg_index_plain", UOp.index(ar, 5, Nil{}))
    g : Unit <- sg.minted.row("sg_index_one", UOp.index(ar, 5, [2]))
    h : Unit <- sg.minted.row("sg_index_two", UOp.index(ar, 5, [2, 3]))
    i : Unit <- sg.minted.row("sg_index_nc", UOp.index(ar, 10, [5]))
    sg.index.rows2(ar)

# `sg_store_gate` is the optional-gate row and `sg_store_nogate` is its
# non-movement pair: the two differ in the THIRD src and in nothing else, so a def
# that dropped the gate entirely would answer the first row with three srcs.
# `sg_ins_tag` is `ta` and `sg_ins_none` is `bu`, and they differ ONLY in the tag,
# which is what makes `UOp.ins`'s third default load-bearing: a port that
# hardcoded `TNone` passes `sg_ins_none` and fails `sg_ins_tag`.

def sg.const.of(+ar: Arena) -> IO(Unit):
  do IO<Unit>:
    x : Unit <- sg.minted.row("sg_invalid", UOp.invalid(ar))
    row("sg_isinv_ci", sg.invalid.isinv(ar))

# `sg_reduce_none` is the row the `AReduce` normalisation cannot be dropped from: a
# def that always built `AReduce` would answer it `reduce:Ops.NOOP/0`, because the
# `Maybe`'s `None` arm is the only thing that writes `ANone` here.

def sg.const.rows(+ar: Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- sg.const.of(ar)
    b : Unit <- row("sg_isinv_c0", UOp.is_invalid(ar, 1))
    c : Unit <- sg.minted.row("sg_reduce_some", UOp.reduce(ar, 5, Nil{}, Some{OpsADD{}}))
    d : Unit <- sg.minted.row("sg_reduce_none", UOp.reduce(ar, 5, Nil{}, None{}))
    g : Unit <- sg.minted.row("sg_reduce_two", UOp.reduce(ar, 5, [1], Some{OpsMAX{}}))
    h : Unit <- sg.minted.row("sg_cconst_i32", UOp.cconst(ar, CInt{H.i64_of_i32(7)}, S.int32()))
    j : Unit <- sg.minted.row("sg_cconst_f32", UOp.cconst(ar, CInt{H.i64_of_i32(7)}, S.single()))
    sg.index.rows(ar)


def sg.body.rows(+ar: Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("sg_body_call", sg.maybe.go(UOp.body(ar, 13), ar))
    srow("sg_body_add", sg.maybe.go(UOp.body(ar, 23), ar))

# `sg_huo_src0` is the row the `1` in `src[1:]` exists for: `ca0`'s only ALLOC is
# src[0], which is the CALL's BODY, so the answer is False and a def that walked
# `src` instead of `src[1:]` answers True. `sg_huo_op` is the same separation on
# the other side -- a non-CALL with an ALLOC src -- and `sg_huo_unshard` is the only
# row that sees the `unsharded_base` peel, because `cun`'s ALLOC is two nodes down.

def sg.inline.rows(+ar: Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("sg_inline_call", sg.pre.go(UOp.is_inline_call(ar, 13)))
    b : Unit <- srow("sg_inline_pre", sg.pre.go(UOp.is_inline_call(ar, 14)))
    c : Unit <- srow("sg_inline_body", sg.pre.go(UOp.is_inline_call(ar, 15)))
    d : Unit <- srow("sg_inline_kernel", sg.pre.go(UOp.is_inline_call(ar, 16)))
    g : Unit <- srow("sg_inline_cfun", sg.pre.go(UOp.is_inline_call(ar, 17)))
    h : Unit <- srow("sg_inline_aft", sg.pre.go(UOp.is_inline_call(ar, 25)))
    srow("sg_inline_add", sg.pre.go(UOp.is_inline_call(ar, 23)))


def sg.rows.arena(+ar: Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- sg.body.rows(ar)
    b : Unit <- sg.inline.rows(ar)
    c : Unit <- sg.unbound.rows(ar)
    sg.const.rows(ar)

def sg.rows() -> IO(Unit): sg.rows.arena(sg.arena())

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

def s5.devrange(ar: Arena, dev: S.Dev) -> String: s5.dr(UOp.device_range_src(ar, dev))

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

# The MSELECT arm is a def of its own and not a third line of `s5.devrows`
# because a mint GROWS the arena: the `Found` is the only thing carrying the arena
# the answer's index lives in, and `s5.minted.row` takes one `Found` and cannot
# thread a grown arena into a second call. A row that called `copy_to_device`
# twice and printed the first's index against the second's arena is the
# stale-arena bug, and this shape is the one that cannot spell it.
def s5.selrow(+ar: Arena) -> IO(Unit):
  +f = UOp.copy_to_device(ar, 4, Some{1}, s5.dn(2))
  srow("s5_copy_sel", s5.minted.go(Found.ar(f), f))

def s5.devrows(+ar: Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("s5_devrange_single", s5.devrange(ar, s5.d1(0)))
    b : Unit <- srow("s5_devrange_one", s5.devrange(ar, s5.dn(1)))
    c : Unit <- srow("s5_devrange_two", s5.devrange(ar, s5.dn(2)))
    d : Unit <- s5.minted.row("s5_copy_single", UOp.copy_to_device(ar, 1, None{}, s5.d1(0)))
    e : Unit <- s5.minted.row("s5_copy_multi", UOp.copy_to_device(ar, 1, None{}, s5.dn(2)))
    s5.selrow(ar)

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

def s5.ga(+ar: Arena, +fuel: Nat, i: U32) -> String: s5.ga.of(UOp.getaddr(fuel, ar, i, s5.d1(0)))

def s5.garows(+ar: Arena) -> IO(Unit):
  +fuel = Arena.budget(ar)
  do IO<Unit>:
    a : Unit <- srow("s5_ga_buffer", s5.ga(ar, fuel, 1))
    b : Unit <- srow("s5_ga_alloc", s5.ga(ar, fuel, 2))
    c : Unit <- srow("s5_ga_param", s5.ga(ar, fuel, 3))
    d : Unit <- srow("s5_ga_shrink", s5.ga(ar, fuel, 4))
    e : Unit <- srow("s5_ga_bitcast", s5.ga(ar, fuel, 5))
    f : Unit <- srow("s5_ga_binary", s5.ga(ar, fuel, 6))
    g : Unit <- srow("s5_ga_mstack", s5.ga(ar, fuel, 7))
    h : Unit <- srow("s5_ga_mselect", s5.ga(ar, fuel, 8))
    i : Unit <- srow("s5_ga_linear", s5.ga(ar, fuel, 9))
    j : Unit <- srow("s5_ga_const", s5.ga(ar, fuel, 10))
    k : Unit <- srow("s5_ga_reshape", s5.ga(ar, fuel, 11))
    l : Unit <- srow("s5_ga_after", s5.ga(ar, fuel, 12))
    srow("s5_ga_add", s5.ga(ar, fuel, 13))

# `copy_to_device` (:761), `device_range_src` (:849) and `getaddr` (:844) arrive
# from ops.py[701,1000] and their rows sit between `s5_sint_const` and
# `s5_gate_linear` in the oracle, so they are emitted HERE rather than from
# `main`: a gate compares rows in emission order, and `main` is the wrong seam.
def s5.movers.r2() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- s5.devrows(s5.ga.arena())
    s5.garows(s5.ga.arena())

def s5.movers.rest(+ar: Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("s5_sharding_us", s5.shardstr(ar, UOp.sharding(ar, 7)))
    b : Unit <- srow("s5_sharding_none", s5.shardstr(ar, UOp.sharding(ar, 5)))
    c : Unit <- srow("s5_sint_const", s5.sint(ar, SInt.of(H.i64_of_i32(1))))
    s5.movers.r2()

def s5.movers(+ar: Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- s5.minted.row("s5_barrier", UOp.barrier(ar, 2, Nil{}))
    b : Unit <- s5.minted.row("s5_bufferize", UOp.bufferize(ar, 2, Nil{}))
    c : Unit <- s5.minted.row("s5_bufferize_arg", UOp.bufferize(ar, 2, [1]))
    d : Unit <- s5.minted.row("s5_allreduce", UOp.allreduce(ar, 4, OpsADD{}, S.Dn{[1, 1]}))
    e : Unit <- s5.minted.row("s5_mselect", UOp.mselect(ar, 2, 0))
    s5.movers.rest(ar)

# ONE entry point for the whole block, so `main` gets one line and the fuel is
# computed in one place. `Arena.budget` is the only sound fuel: one step per peel,
# one per worklist entry, and both are bounded by the arena's own size plus edges.
def s5.rows.rest(+ar: Arena, +f: S5) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- s5.movers(ar)
    s5.gate(ar)

def s5.rows.arena(+ar: Arena, +f: S5) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- s5.idx(ar, f)
    b : Unit <- s5.base(Arena.budget(ar), ar, f)
    c : Unit <- s5.unsharded(Arena.budget(ar), ar, f)
    d : Unit <- s5.storage(Arena.budget(ar), ar, f)
    e : Unit <- s5.woafter(Arena.budget(ar), ar, f)
    g : Unit <- s5.bufuop(Arena.budget(ar), ar, f)
    h : Unit <- s5.hbi(Arena.budget(ar), ar, f)
    i : Unit <- s5.splitrows(Arena.budget(ar), ar)
    s5.rows.rest(ar, f)



def s5.rows() -> IO(Unit):
  s5.rows.arena(s5.arena(), s5.ids())

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
        case ParamArg{slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: name
    case _: None{}

def UOp.expr(+ar: Arena, +self: U32) -> Maybe<&2, String>:
  UOp.expr.go(Arena.arg(ar, self))

def vr.pa.name(pa: ParamArg, nm: Maybe<&2, String>) -> ParamArg:
  match pa:
    case ParamArg{slot, dtype, size, vmin_vmax, multiple_of, _n, addrspace, device, volatile, image, buffer, bind_on_realize, val}:
      ParamArg{slot, dtype, size, vmin_vmax, multiple_of, nm, addrspace, device, volatile, image, buffer, bind_on_realize, val}

# ==== the `vr_expr_*` fixture and rows =====================================
#
# `expr` has THREE answers and each gets a row, because one row cannot tell a
# name from a missing name from a non-`ParamArg` arg -- and those three are three
# different reasons CPython raises. The `vr_expr_` rows are the whole gate: there
# is no second family, so nothing here can be load-bearing by accident.
#
# The four PARAM fixtures differ in ONE field each, which is what makes the
# mutation table below able to move a row. A fixture set where every node is
# identical except the field under test is one where a wrong answer is invisible.
def vr.pa(nm: Maybe<&2, String>) -> ParamArg:
  vr.pa.name(ParamArg.of(1, S.int32()), nm)

# 1 PARAM named, 2 BUFFER named, 3 PARAM unnamed, 4 CONST (arg is not a ParamArg).
# 1 and 2 are the SAME arm of the arg sum and they must answer the same -- that
# is the row pair that says the op is genuinely not consulted.
def vr.arena() -> Arena:
  Arena{[
    Arena.bottom(),
    Node{OpsPARAM{}, Nil{}, AParam{vr.pa(Some{"i"})}, TNone{}},
    Node{OpsBUFFER{}, Nil{}, AParam{vr.pa(Some{"buf"})}, TNone{}},
    Node{OpsPARAM{}, Nil{}, AParam{vr.pa(None{})}, TNone{}},
    Node{OpsCONST{}, Nil{}, APy{CInt{H.i64_of_i32(7)}}, TNone{}}], [0]}

def vr.show(m: Maybe<&2, String>) -> String:
  match m:
    case Some{s}: String.concat(["some:", s])
    case None{}: "none"

def vr.expr.row(nm: String, +ar: Arena, i: U32) -> IO(Unit):
  srow(nm, vr.show(UOp.expr(ar, i)))

def vr.expr.rows(+ar: Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- vr.expr.row("vr_expr_param", ar, 1)
    b : Unit <- vr.expr.row("vr_expr_buffer", ar, 2)
    c : Unit <- vr.expr.row("vr_expr_unnamed", ar, 3)
    vr.expr.row("vr_expr_nonparam", ar, 4)

# TODO(p3) ops.py:1060  def const_factor
#   `def const_factor(self) -> int: """largest known int that divides self"""` --
#   five arms, a `math.gcd` over the STACK and ADD srcs, and a positional read for
#   MUL. Four of the five arms are one `match` each and are trivially expressible.
#
#   THE BLOCKER IS THE OTHER TWO, AND IT IS NOT A PORTING DIFFICULTY: computing
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
#   So the wall is real and it is a substrate limit, not a missing thought. It also
#   blocks ops.py:1069 `divides`, ops.py:1085 `gcd` and ops.py:1091 `divide_exact`,
#   which all call it, and those in turn block ops.py:1046 `unbind_all` and
#   ops.py:1049 `variables`. That is five of this file's markers on one wall.
#   `.agents/slop/bend-toposort.py` detects the cycle and refuses to write rather
#   than oscillating, which is how this was found.

# TODO(p3) ops.py:1069  def divides
#   `if v==1: return self; if CONST: const_like(val//v) if val%v==0 else None; ...`
#   Calls `const_factor`'s sibling `const_like` (ops.py:600, not ported) and does
#   `//` and `%` on an `H.I64`, plus `UOp.__floordiv__` for the Defines arm.
#   Gated on all three.

# TODO(p3) ops.py:1085  def gcd
#   `zip(*[u.pop_const(Ops.MUL) for u in uops])`, a `Counter` intersection of
#   `split_uop(Ops.MUL)` terms, and `math.gcd` over `const_factor`s. Needs
#   `collections.Counter` as a fold and `const_factor` above.

# TODO(p3) ops.py:1091  def divide_exact
#   Recurses over ADD/MUL srcs and calls `divides`, `const_like` and `__floordiv__`.


# ==== ops.py:1899  `resolve_returned_after` ===============================
#
# `"""Extract a call output's matching store, preserving writes to the enclosing
# scope's output PARAMs."""` -- `[st for st in t.src if st.op is Ops.STORE and
# st.src[0].unsharded_base is r.unsharded_base]`, then `if len(stores) != 1: return
# None`, then one of two mints.
#
# `r.unsharded_base` IS COMPUTED ONCE AND PASSED, not read twice. CPython evaluates
# the peel again in the final `r.unsharded_base.op is Ops.PARAM`; `unsharded_base`
# is a PURE peel (`UOp.base` plus UNSHARD, and neither mints), so the two walks
# answer the same index and computing it once is the same answer for one less walk.
# A gate row cannot see the difference, and the reason is written here so nobody
# "simplifies" it back into two reads.
#
# THE ANSWER'S ARENA IS NOT THE CALLER'S IN ONE ARM. `r.after(stores[0])` MINTS and
# grows the arena; `stores[0].src[1]` is an index that already existed. So the
# answer is a `Found` and not a bare `U32` -- the same reason `UOp.index.pick`
# returns a `Found`, and the same stale-arena bug if it does not: a caller reading
# the index out of ITS OWN arena gets the bottom, which is a NOOP. The `rra_arena`
# row reads the op from the RETURNED arena on purpose.
def rra.hit(fuel: Nat, +ar: Arena, rb: U32, +st: U32) -> Bool:
  Bool.and(eq_op(Arena.op(ar, st), OpsSTORE{}),
    U32.is_eq(UOp.unsharded_base(fuel, ar, Arena.src(ar, st, 0)), rb))

# THE FILTER, and it is ONE def rather than three. The first draft split it into
# `filter.go` / `at` / `put` so each `match` would scrutinise a binder -- and that is
# MUTUALLY recursive, which Bend refuses: `go` calls `at` and `at` calls `go`, and
# `bend-toposort.py` reported the cycle and declined to write, correctly.
#
# `Bool.pick` is the way out, and it is why the file's own folds are single defs: it
# is the only conditional that does not need a `match`, so the accumulator is an
# ordinary expression and the def can recurse into ITSELF. The `List.append` is built
# even when the test is False, which is the same eager-argument waste `UOp.after.go`
# and `UOp.getaddr.go` already pay and is free here: a discarded list is not a
# discarded NODE.
def rra.filter.go(+fuel: Nat, +ar: Arena, +xs: List<&2, U32>, +acc: List<&2, U32>, +rb: U32) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case h <> t:
      rra.filter.go(fuel, ar, t, Bool.pick(List<&2, U32>, rra.hit(fuel, ar, rb, h),
        List.append(&2, U32, acc, [h]), acc), rb)

def rra.one.tail(s: U32, rest: List<&2, U32>) -> Maybe<&2, U32>:
  match rest:
    case _ <> _ <> _: None{}
    case _: Some{s}

# THE PICK. `!= 1` is a REFUSAL, so this is a `Maybe`, and the refusal is the whole
# of what `rra_none_*` rows gate. Two of the three fixtures that reach `None` reach
# it through DIFFERENT conjuncts, which is the point of having three rows and not one.
# THE COUNT, and it is `len(stores) != 1` over the LIST rather than a length compare,
# so `rra_none_two` and `rra_none_empty` are the SAME code path and not two arms that
# happen to agree. ONE match per def: a def with two `match`es reads the second as a
# consumed binder, which Bend rejects with a message about binders and not about
# matches.
def rra.one(+stores: List<&2, U32>) -> Maybe<&2, U32>:
  match stores:
    case Nil{}: None{}
    case s <> _: rra.one.tail(s, stores)

# The PARAM arm MINTS and the other arm does not, so the two answers have different
# arenas and the pick must carry the `Found` rather than an index. The discarded
# `UOp.after` in the `False{}` arm grows the arena and is unreachable, which is the
# same waste `UOp.after.go` and `UOp.getaddr.go` already pay: Bend evaluates an
# argument before the callee branches, and the waste is only free when the two
# candidates are the same node -- here they are NOT, which is exactly why the pick
# carries a `Found` rather than an index.
def rra.pick(isparam: Bool, +ar: Arena, r: U32, st: U32) -> Found:
  match isparam:
    case True{}: UOp.after(ar, r, [st])
    case False{}: Found{ar, Arena.src(ar, st, 1)}

# The `Maybe` from `rra.one` is a COMPUTED value, so the `match` that opens it lives
# in a def that RECEIVES it. `done` does not call back, so this is one-directional
# and not a second instance of the mutual-recursion wall above.
def rra.done(+ar: Arena, r: U32, rb: U32, hit: Maybe<&2, U32>) -> Maybe<&2, Found>:
  match hit:
    case None{}: None{}
    case Some{st}: Some{rra.pick(eq_op(Arena.op(ar, rb), OpsPARAM{}), ar, r, st)}

def resolve_returned_after(+fuel: Nat, +ar: Arena, +r: U32, t: U32) -> Maybe<&2, Found>:
  +rb = UOp.unsharded_base(fuel, ar, r)
  +stores = rra.filter.go(fuel, ar, Arena.srcs(ar, t), Nil{}, rb)
  rra.done(ar, r, rb, rra.one(stores))

# ==== the `rra_*` fixture and rows =========================================
#
# ONE ARENA, and the ordering is LOAD-BEARING rather than cosmetic. CPython's test
# is `st.src[0].unsharded_base is r.unsharded_base`, so a store only matches when its
# TARGET peels to `r` -- which means every target must appear BEFORE the store that
# writes it. The first draft put the AFTERs after the stores and every row answered
# `none`: the filter was correct and the FIXTURE was wrong, which is the failure
# mode this file's own rule warns about ("a fixture that does not reach the branch").
#
#   idx  node            why it is here
#     1  CONST 7         the stored value
#     2  CONST 9         a second value
#     3  BUFFER          a target
#     4  AFTER [3]       r_val. AFTER is NOT a movement op, so base(4) = 4
#     5  PARAM           r_param. PARAM is not a movement op either: base(5) = 5,
#                        and op(5) is PARAM, which is the `after` arm
#     6  STORE [4,1]     the one matching store for r_val
#     7  SINK [6]        t for rra_val
#     8  STORE [4,2]     a SECOND store to the same r
#     9  SINK [6,8]      two matches -> the `!= 1` refusal
#    10  SINK [1]        no STORE src -> also a refusal, via a different conjunct
#    11  SINK []         no srcs at all -> the filter's Nil arm
#    12  SINK [6,1]      one match plus a non-store src
#    13  STORE [5,1]     the store into the PARAM
#    14  SINK [13]       t for rra_param
#    15  UNSHARD [3]     r_unshard. UNSHARD is the ONE op where base and
#                        unsharded_base differ: `base.peel` is movement, and UNSHARD
#                        is not, so base(15) = 15 while unsharded_base(15) = 3
#    16  STORE [3,1]     its target peels to 3, which is r_unshard's base
#    17  SINK [16]       t for rra_unshard
#    18  RESHAPE [3]     NOT a STORE, and its base IS r_unshard's base: RESHAPE is in
#                        `GroupOp.movement`, so unsharded_base(18) = 3 = rb
#    19  SINK [16,18]    the store AND that reshape. The ONLY sink where the op test
#                        and the base test disagree, so it is the only row that can
#                        see the op test at all.
#
#                        BOTH of these were FOUND BY THE MUTATION TABLE, not by
#                        reading the code, and the two attempts are the reason the
#                        comment is here. `rra_none_zero` does not carry the conjunct:
#                        its only src is a CONST, whose base is not r either. A sink of
#                        [the store, the BUFFER] does not either -- the BUFFER has no
#                        srcs, so `Arena.src` answers the bottom and the base test
#                        rejects it. Two fixtures, two rounds, both measuring zero
#                        moved rows. A conjunct needs a fixture where it is the ONLY
#                        failing test, and that is not the same as a fixture where it
#                        happens to be one of two.
def rra.pa(slot: U32) -> ParamArg: ParamArg.of(slot, S.int32())

def rra.arena() -> Arena:
  Arena{[
    Arena.bottom(),
    Node{OpsCONST{}, Nil{}, APy{CInt{H.i64_of_i32(7)}}, TNone{}},
    Node{OpsCONST{}, Nil{}, APy{CInt{H.i64_of_i32(9)}}, TNone{}},
    Node{OpsBUFFER{}, Nil{}, AParam{rra.pa(1)}, TNone{}},
    Node{OpsAFTER{}, [3], ANone{}, TNone{}},
    Node{OpsPARAM{}, Nil{}, AParam{rra.pa(2)}, TNone{}},
    Node{OpsSTORE{}, [4, 1], ANone{}, TNone{}},
    Node{OpsSINK{}, [6], ANone{}, TNone{}},
    Node{OpsSTORE{}, [4, 2], ANone{}, TNone{}},
    Node{OpsSINK{}, [6, 8], ANone{}, TNone{}},
    Node{OpsSINK{}, [1], ANone{}, TNone{}},
    Node{OpsSINK{}, Nil{}, ANone{}, TNone{}},
    Node{OpsSINK{}, [6, 1], ANone{}, TNone{}},
    Node{OpsSTORE{}, [5, 1], ANone{}, TNone{}},
    Node{OpsSINK{}, [13], ANone{}, TNone{}},
    Node{OpsUNSHARD{}, [3], ATuple{[0]}, TNone{}},
    Node{OpsSTORE{}, [3, 1], ANone{}, TNone{}},
    Node{OpsSINK{}, [16], ANone{}, TNone{}},
    Node{OpsRESHAPE{}, [3], ANone{}, TNone{}},
    Node{OpsSINK{}, [16, 18], ANone{}, TNone{}}], [0]}

# The printer, and it reads the op out of the FOUND'S OWN ARENA. That is not
# tidiness: the `rra_param` answer is a freshly minted AFTER, and a reader using the
# fixture's arena would get the BOTTOM, which is a NOOP -- the stale-arena bug, and
# it PRINTS as `Ops.NOOP`.
def rra.show(m: Maybe<&2, Found>) -> String:
  match m:
    case Some{+f}: String.concat(["some:", Ops.name(Arena.op(Found.ar(f), Found.i(f)))])
    case None{}: "none"

def rra.row(nm: String, +ar: Arena, r: U32, t: U32) -> IO(Unit):
  srow(nm, rra.show(resolve_returned_after(Arena.budget(ar), ar, r, t)))

# THE COUNT row, and it reads the RETURNED arena. `rra_param` is the one answer that
# MINTS, so this pins that single node: a def that stopped building the AFTER would
# answer all seven other rows identically and this row would drop.
# THE DELTA, and the first draft printed the arena SIZE and called it a count. The
# oracle prints how many nodes were minted, which is 1 for the PARAM arm; the port
# printed `Arena.next` of the returned arena, which is 19, and the two lanes were
# measuring DIFFERENT THINGS and disagreeing. Same gate, two quantities, and only
# one of them says anything: a def that minted nothing would still answer 19 if the
# arena happened to be that size.
def rra.next(base: U32, hit: Maybe<&2, Found>) -> String:
  match hit:
    case Some{+f}: U32.show(U32.sub(Arena.next(Found.ar(f)), base))
    case None{}: "none"

def rra.count(+ar: Arena, r: U32, t: U32) -> String:
  rra.next(Arena.next(ar), resolve_returned_after(Arena.budget(ar), ar, r, t))

# rra_val and rra_param are a PAIR and neither is worth having alone. Both have
# exactly one matching store; they differ only in whether `r.unsharded_base.op` is
# PARAM, and a def with that conjunct dropped answers `rra_param` with the CONST and
# passes every other row in the family.
def rra.rows(+ar: Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- rra.row("rra_val", ar, 4, 7)
    b : Unit <- rra.row("rra_param", ar, 5, 14)
    c : Unit <- rra.row("rra_unshard", ar, 15, 17)
    d : Unit <- rra.row("rra_none_zero", ar, 4, 10)
    e : Unit <- rra.row("rra_none_two", ar, 4, 9)
    f : Unit <- rra.row("rra_none_empty", ar, 4, 11)
    g : Unit <- rra.row("rra_mixed", ar, 4, 12)
    h : Unit <- rra.row("rra_samebase", ar, 15, 19)
    srow("rra_arena", rra.count(ar, 5, 14))

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
    case ParamArg{slot, dtype, size, vmin_vmax, multiple_of, _n, addrspace, device, volatile, image, buffer, bind_on_realize, val}:
      ParamArg{slot, dtype, size, Some{r}, Some{mo}, Some{nm}, S.Aalu{},
        device, volatile, image, buffer, bind_on_realize, val}

def UOp.variable.pa(nm: String, lo: H.I64, hi: H.I64, mo: U32, dt: S.Dt) -> ParamArg:
  UOp.variable.pa.of(ParamArg.of(ParamArg.no_slot(), dt), nm, PyRange{lo, hi}, mo)

def UOp.variable(+ar: Arena, nm: String, lo: H.I64, hi: H.I64, mo: U32, dt: S.Dt) -> Found:
  UOp.new(ar, OpsPARAM{}, Nil{}, AParam{UOp.variable.pa(nm, lo, hi, mo, dt)}, TNone{})

# ==== the `vrn_*` rows =====================================================
#
# `variable` sets FIVE fields -- slot, name, vmin_vmax, multiple_of, addrspace -- and
# the other eight keep `ParamArg.of`'s defaults. So a row prints those five plus the
# src count, and NOTHING else: a row that printed the whole record would move on any
# of thirteen fields and say nothing about any one of them.
#
# The four fixtures differ in ONE input each, and the defaults are CPython's
# (`dtype=dtypes.weakint`, `multiple_of=1`), so `vrn_default` is the def's own
# signature rather than a fixture choice. `vrn_neg` and `vrn_multi` are the rows that
# make the two `H.I64` ends and the `U32` separate: one row printing `(0,10)` cannot
# tell a swapped pair from a correct one.
def vrn_optu(m: Maybe<&2, U32>) -> String:
  match m:
    case Some{u}: U32.show(u)
    case None{}: "-"

def vrn_opts(m: Maybe<&2, String>) -> String:
  match m:
    case Some{s}: s
    case None{}: "-"

def vrn_addr_name(a: S.Addr) -> String:
  match a:
    case S.Aalu{}: "ALU"
    case S.AGlobal{}: "GLOBAL"
    case S.ALocal{}: "LOCAL"
    case S.AReg{}: "REG"

def vrn_lo.of(r: PyRange) -> String:
  match r:
    case PyRange{lo, hi}: H.i64_text(lo)

# The two range ends are TWO defs, and `Bool.pick` is why: it EVALUATES both
# branches, so `Bool.pick(H.I64, top, r.hi, r.lo)` is `r.hi` and `r.lo` read as terms
# outside a match, which Bend rejects. A `top: Bool` parameter would be the terser
# spelling and it is not available; the two ends are the two arms.
# `PyRange` has NO accessors, and a `case PyRange{lo}` is not a partial match -- the
# same all-fields rule `ParamArg` has. So the range is destructured in full and the
# two ends are read from the BINDERS, which is why these two defs take the payload
# rather than the `Maybe`: `ops.bend:1503` spells the same destructuring.
def vrn_lo(m: Maybe<&2, PyRange>) -> String:
  match m:
    case Some{r}: vrn_lo.of(r)
    case None{}: "-"

def vrn_hi.of(r: PyRange) -> String:
  match r:
    case PyRange{lo, hi}: H.i64_text(hi)

def vrn_hi(m: Maybe<&2, PyRange>) -> String:
  match m:
    case Some{r}: vrn_hi.of(r)
    case None{}: "-"

def vrn_f5(p: ParamArg) -> Maybe<&2, U32>:
  match p:
    case ParamArg{slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: multiple_of

def vrn_f4(p: ParamArg) -> Maybe<&2, PyRange>:
  match p:
    case ParamArg{slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: vmin_vmax

def vrn_f3(p: ParamArg) -> Maybe<&2, String>:
  match p:
    case ParamArg{slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: name

# The five field readers, one match each. Seven defs and not one that returns a
# record, because a record would have to spell all thirteen fields and a
# thirteen-field literal is the thing `sg.pa.put` exists to avoid.
def vrn_pa_of(arg: Arg) -> ParamArg:
  match arg:
    case AParam{p}: p
    case _: ParamArg.of(ParamArg.no_slot(), S.weakint())

def vrn_f7(p: ParamArg) -> S.Addr:
  match p:
    case ParamArg{slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: addrspace

def vrn_row(nm: String, +f: Found) -> IO(Unit):
  +ar = Found.ar(f)
  +p = vrn_pa_of(Arena.arg(ar, Found.i(f)))
  srow(nm, String.concat([
    "slot=", Bool.pick(String, U32.is_eq(ParamArg.slot(p), ParamArg.no_slot()), "-1", U32.show(ParamArg.slot(p))),
    " name=", vrn_opts(vrn_f3(p)), " mult=", vrn_optu(vrn_f5(p)), " addr=", vrn_addr_name(vrn_f7(p)),
    " lo=", vrn_lo(vrn_f4(p)), " hi=", vrn_hi(vrn_f4(p)),
    " nsrc=", U32.show(Arena.nsrc(ar, Found.i(f)))]))

def vrn_rows(+ar: Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- vrn_row("vrn_default", UOp.variable(ar, "i", H.i64_of_i32(0), H.i64_of_i32(10), 1, S.weakint()))
    b : Unit <- vrn_row("vrn_multi", UOp.variable(ar, "j", H.i64_neg(True{}, H.i64_of_i32(5)), H.i64_of_i32(5), 4, S.weakint()))
    c : Unit <- vrn_row("vrn_neg", UOp.variable(ar, "m", H.i64_neg(True{}, H.i64_of_i32(100)), H.i64_neg(True{}, H.i64_of_i32(1)), 1, S.weakint()))
    vrn_row("vrn_int32", UOp.variable(ar, "k", H.i64_of_i32(1), H.i64_of_i32(2), 1, S.int32()))

# `Map.has` answers a `Sigma` and not a `Maybe`, so the Bool rides out in the second
# half of the pair. `render.bend:1020`'s `ctx_has.of` destructures the same shape and
# this is the third copy of THAT two-line destructure -- see `Maybe.has` below.
def vv_has.of(r: Sigma<&1, &1, Map<&2, H.I64>, _ => Bool>) -> Bool:
  match r:
    case Tuple{m, b}: b

def vv_has(v: VarVals, k: String) -> Bool:
  vv_has.of(Map.has(&2, H.I64, VarVals.m(v), k))

# ==== ops.py:1366  `ProgramInfo.vals` ======================================
#
# `tuple(var_vals[k.expr] for k in self.vars)` with
# `raise RuntimeError(f"unbound Variable {e}")` on a miss. MEASURED:
# `ProgramInfo(vars=(i,j)).vals({'i':7,'j':9})` is `(7, 9)` and a miss is
# `RuntimeError: unbound Variable 'j'`.
#
# I RECORDED THIS BLOCKER WRONG TWICE, both times in the same direction: I claimed
# a BEND LANGUAGE CHANGE was needed and never grepped for it. `Map` is a stdlib type
# from `import Base` -- `references/bend/bend2/base.bend:2551` Map.put, `:2675`
# Map.set, `:2683` Map.has, `:2736` Map.get, all four present -- and
# `uop/render.bend:1007` and `:1017` were already CALLING `Map.set` and `Map.get`
# through `Ctx` while the note here said the rule did not exist.
#
# AND THE SECOND CALLER I NAMED WAS WRONG TOO. I wrote that `pyrender`'s `Ctx` walk
# wanted the same fold; `render.bend:1878`'s `render_with_splits` answers
# `List<&2, Bind>` and not a `Maybe`, so it does not. The REAL second caller is
# `unified_rewrite`'s fixpoint (ops.py:1828-1835), where `test_n: UOp|None` is
# carried through a loop and a `BottomUpGate` breaks out of it -- and THAT is the
# engine's remaining named wall. Two real callers, and the second one is why the
# idiom was worth looking for.
#
# THE IDIOM IS `bcast.go` (fold.bend:590) verbatim: a `Maybe`-carried LIST
# accumulator and `Maybe.bind` for the miss arm. `memory.bend:405`'s `mem_some` is
# the element form of the same thing, and both are in files this one imports. My
# first draft was TEN defs and did not compile because a def may hold ONE `match`
# and a hand-rolled `Maybe` accumulator wants two per step; `Maybe.bind` is what
# collapses that, and it was already here.
#
# A MISS IS `Map.get`'s DEFAULT, so "unbound" cannot be told from "bound to 0" by the
# value alone -- and `vals` on a partially-bound program must REFUSE, not answer
# zeros. So the Bool comes from `Map.has` and the value from `Map.get`. The default
# is never a value the map can hold, which is why the `has` is not belt-and-braces.
# `Map.get` answers a `Sigma` -- the MAP and the value -- not a bare value, so the
# pair is destructured before the value is used. `render.bend:1009`'s `ctx_get.of` is
# the same two lines on a `String` map, and getting this wrong is what the
# `expected : Data / observed : Quant` was: a `Map` where an `H.I64` was expected.
def vv_of.val(r: Sigma<&1, &1, Map<&2, H.I64>, _ => H.I64>) -> H.I64:
  match r:
    case Tuple{m, x}: x

def vv_of.of(r: Sigma<&1, &1, Map<&2, H.I64>, _ => H.I64>, present: Bool) -> Maybe<&2, H.I64>:
  Bool.pick(Maybe<&2, H.I64>, present, Some{vv_of.val(r)}, None{})

# `Map.get(-V: Data, d: V, m, key)` TAKES A DEFAULT and it is the SECOND argument,
# which is how the `expected : Data / observed : Quant` happened: the `&2` that
# `Map.has` and `Map.set` want was written here too, and it landed in the `V` slot
# where a bare `H.I64` belongs. `Map.get` has NO quantifier -- `render.bend:1017`'s
# `Map.get(String, "", Ctx.map(c), U32.show(u))` shows the shape with the `""` in
# the same slot. Three of the four `Map` readers in the tree and not the fourth.
#
# THE DEFAULT IS 0 AND THAT IS WHY THE `has` IS NOT REDUNDANT. A miss returns 0,
# which is a legal bound, so "unbound" and "bound to 0" are the same value here and
# only `Map.has` separates them. `ctx_get` gets away with `""` because
# render.bend:1014 states every src was written first; `vals` has no such guarantee.
def vv_of(+v: VarVals, +k: String) -> Maybe<&2, H.I64>:
  vv_of.of(Map.get(H.I64, H.i64_of_i32(0), VarVals.m(v), k), vv_has(v, k))

# THE FOLD, AND IT IS ONE DEF. The first draft split it into `step` / `lookup` /
# `fetch`, which is MUTUALLY RECURSIVE -- `step` calls `lookup`, `lookup` calls
# `fetch`, and `fetch` calls `step` back. Bend refuses that, and `bend-toposort`
# reported the cycle and declined to write, correctly.
#
# `Maybe.bind`'s LAMBDA is the continuation, so the three become one def with ONE
# `match` (on the list, the only scrutinee) and TWO binds. `bcast.go` at
# fold.bend:590 is the same shape and is why that fold is two lines: the recursion
# is in the CLOSURE, not in a call chain. `Maybe.bind` is the answer to "a `Maybe`
# accumulator wants two matches per step", and it was already in the tree.
def vals.step(+ar: Arena, +v: VarVals, xs: List<&2, U32>, acc: List<&2, H.I64>) -> Maybe<&2, List<&2, H.I64>>:
  match xs:
    case Nil{}: Some{acc}
    case h <> t:
      Maybe.bind(&2, String, List<&2, H.I64>, UOp.expr(ar, h), k =>
        Maybe.bind(&2, H.I64, List<&2, H.I64>, vv_of(v, k), x =>
          vals.step(ar, v, t, List.append(&2, H.I64, acc, [x]))))

# THE ENTRY, and the `Maybe` is the refusal for an unbound Variable. Python raises,
# and this file's standing spelling for a raise is the absent case -- the same
# `Maybe` `UOp.expr` uses, and the reason `Maybe` rather than a sentinel is that a
# schedule key of the WRONG LENGTH is a wrong program and not a diagnostic.
def ProgramInfo.vals(+ar: Arena, v: VarVals, x: ProgramInfo) -> Maybe<&2, List<&2, H.I64>>:
  vals.step(ar, v, ProgramInfo.vars(x), Nil{})

# ==== the `vv_*` fixture and rows =========================================
#
# FIVE rows and they are the FIVE answers, because `vals` has three ways to be
# interesting and one of them is invisible: a Variable BOUND TO 0 answers `(0)`,
# which is the same value `Map.get` hands back for a MISS. Without that row a def
# that dropped `Map.has` entirely would pass the other four -- it would answer
# `(0)` for an unbound program instead of refusing, and a schedule key of the wrong
# LENGTH is a wrong program rather than a diagnostic.
#
# `vv_miss_first` is the SECOND-MISS row and not the first: `vals` refuses at the
# first miss, so a fixture that missed on `i` would never look at `j` and the two
# would be one row. Missing on the SECOND name is what proves the fold STOPS.
def vd_pa.put(p: ParamArg, nm: Maybe<&2, String>) -> ParamArg:
  match p:
    case ParamArg{slot, dtype, size, vmin_vmax, multiple_of, _n, addrspace, device, volatile, image, buffer, bind_on_realize, val}:
      ParamArg{slot, dtype, size, vmin_vmax, multiple_of, nm, addrspace, device, volatile, image, buffer, bind_on_realize, val}

def vd_pa(slot: U32, nm: Maybe<&2, String>) -> ParamArg:
  vd_pa.put(ParamArg.of(slot, S.weakint()), nm)

# `UOp.variable` is PORTED and is what mints these, so the fixture is the def under
# test's OWN constructor rather than a hand-built ParamArg. That is the discipline
# `rra`'s arena follows and the reason `vrn_*` can gate `UOp.variable` from inside
# the file that uses it.
def vd_arena() -> Arena:
  Arena{[
    Arena.bottom(),
    Node{OpsPARAM{}, Nil{}, AParam{vd_pa(ParamArg.no_slot(), Some{"i"})}, TNone{}},
    Node{OpsPARAM{}, Nil{}, AParam{vd_pa(ParamArg.no_slot(), Some{"j"})}, TNone{}},
    Node{OpsCONST{}, Nil{}, APy{CInt{H.i64_of_i32(5)}}, TNone{}}], [0]}

def vd_put(nm: String, x: H.I64, base: VarVals) -> VarVals:
  VarVals{Map.set(&2, H.I64, VarVals.m(base), nm, x)}

# THE THREE `Map` READERS TAKE THEIR QUANTIFIER IN THREE DIFFERENT PLACES, and
# getting it wrong is a `expected : Map<&2, H.I64> / observed: VarVals` rather than a
# clean arity error, because the stray value lands in the next parameter.
#   Map.set(a, -V: Kind(a), m, key, x)  -- quantifier SECOND, after the linearity
#   Map.has(-a: Quant, -V: Kind(a), m, key)
#   Map.get(-V: Data, d, m, key)        -- NO linearity parameter at all
# `render.bend:1007` and `:1017` already spell all three correctly; this cost three
# compile rounds to find, and the first of them I had recorded as a LANGUAGE gap.
# `Map.set` puts its QUANTIFIER SECOND (`Map.set(a, -V: Kind(a), m, key, x)`) and
# the three `Map` readers in the tree disagree about that -- `Map.has` takes it
# first, `Map.get` has NO linearity parameter. A stray `&2` lands in the next
# parameter's slot and the error names a type rather than an arity.

# The row, and the `Maybe` is a refusal: `none` is an unbound Variable. A bare
# `(0)` would be the bug this whole `has` exists to prevent, so the printer spells
# the refusal rather than letting a default through.
# THE PRINTER, and it is `s5.seps`'s TWO-DEF SHAPE for a reason I got wrong twice.
# The accumulator is a `String` and is NOT `+`-marked, the HEAD is `+h`, and the
# recursion is a SEPARATE def -- `s5.seps.go` above. I wrote it as one def with
# `+acc` and a self-call, which typechecked and then answered `()` for every input,
# because a `+` accumulator that starts life as a bare `Nil{}` literal never
# accumulates. A fold that compiles and returns nothing is worse than one that does
# not compile, and this is the second time this session that bit (the first was
# `rra.filter`).
# THE PRINTER, and it is the `ax_names_str` shape (ops.bend:5738): collect the
# pieces, `List.reverse`, `String.join`. Three attempts got here and the third is
# the file's own idiom --
#   1. a `+acc` String that COMPILED and answered `()` for every input, because a
#      `+` accumulator starting as a bare `Nil{}` literal never accumulates
#   2. `String.drop_last` to strip the trailing comma, and there is no
#      `String.drop_last` in helpers.bend
# So the list is built, reversed and joined, and nothing is stripped.
# APPEND-AT-THE-TAIL and not at the head, which is what `ax_names_str.go` does --
# and that difference is the whole of `vv_two` coming out `(0:9,0:7)`. This fold
# APPENDS, so the list is in SOURCE order already and must NOT be reversed. A
# reader copying `ax_names_str`'s trailing `List.reverse` gets the wrong answer
# with no compile error, which is the fourth time this unit produced a row that
# compiled and was wrong.
def vd_text.go(+ys: List<&2, H.I64>, +acc: List<&2, String>) -> List<&2, String>:
  match ys:
    case Nil{}: acc
    case h <> t: vd_text.go(t, List.append(&2, String, acc, [H.i64_text(h)]))

# NO `match` HERE, and that is the fourth attempt's only content. A match on
# `vd_text.go(ys, Nil{})` -- a computed value -- is refused, so the empty case is
# handled by the JOIN: `String.join` of an empty list is "", and "" wrapped in
# parentheses is "()". `ax_names_str` at ops.bend:5737 is the same shape and it has
# no `match` either.
def vd_text(ys: List<&2, H.I64>) -> String:
  String.concat(["(", String.join(vd_text.go(ys, Nil{}), ","), ")"])

def vd_show(m: Maybe<&2, List<&2, H.I64>>) -> String:
  match m:
    case Some{ys}: vd_text(ys)
    case None{}: "none"

# The record is spelled through a helper because the SIX fields are all defaulted
# and only `vars` is under test; `ProgramInfo.of()` supplies the three `(1,1,1)`s
# and the three empty lists, and a six-field LITERAL here would be a second copy of
# a default that already has a name.
def vd.pi.of(pi: ProgramInfo, xs: List<&2, U32>) -> ProgramInfo:
  match pi:
    case ProgramInfo{g, l, _v, go, o, i}: ProgramInfo{g, l, xs, go, o, i}

def vd.pi(xs: List<&2, U32>) -> ProgramInfo: vd.pi.of(ProgramInfo.of(), xs)

def vd_row(nm: String, +ar: Arena, v: VarVals, xs: List<&2, U32>) -> IO(Unit):
  +pi = vd.pi(xs)
  srow(nm, vd_show(ProgramInfo.vals(ar, v, pi)))

def vd_rows(+ar: Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- vd_row("vv_two", ar, vd_put("j", H.i64_of_i32(9), vd_put("i", H.i64_of_i32(7), VarVals.new())), [1, 2])
    b : Unit <- vd_row("vv_one", ar, vd_put("i", H.i64_of_i32(7), VarVals.new()), [1])
    c : Unit <- vd_row("vv_zero", ar, vd_put("i", H.i64_of_i32(0), VarVals.new()), [1])
    d : Unit <- vd_row("vv_none", ar, VarVals.new(), Nil{})
    vd_row("vv_miss_second", ar, vd_put("i", H.i64_of_i32(7), VarVals.new()), [1, 2])

def UOp.set.end.of(e: Maybe<&2, List<&2, U32>>) -> List<&2, U32>:
  match e:
    case Some{xs}: xs
    case None{}: Nil{}

# ==== ops.py:1224  `UOp.set` ===============================================
#
#     # set is store+end+after
#     def set(self:UOp, val:UOp|ConstType, end:UOp|tuple[UOp, ...]|list[UOp]=()) -> UOp:
#       return self.src[0].after(self.store(val).end(*argfix(end)))
#
# Upstream's own comment says the whole thing: this is a COMPOSITION, and it has no
# logic of its own. So the only things a row can test are (a) that the three pieces
# are wired in this ORDER and (b) that `argfix`'s `None`-means-empty arm is
# honoured -- and `argfix` is already ported, as `argfix1` / `argfix2` /
# `argfix_seq` (helpers.bend:539-546), one def per arity.
#
# `end` IS A `Maybe<&2, List<&2, U32>>` and not a node, because Python's `end` is
# `UOp | tuple | list` and the tuple and the single node are the SAME thing to
# `argfix`. Two defs rather than one per arity: a def whose answer is a LIST does
# not need to know how many there are, and `argfix1`/`argfix2` already are the
# per-arity spellings for the other callers.
#
# THE SUBJECT IS A STORE, and the first draft built a BUFFER and got `IndexError:
# tuple index out of range`. `set` reads `self.src[0]`, so `self` is a store and
# `src[0]` is its target -- the thing being rewritten. That is a fixture that did
# not reach the code, which is worse than no fixture: it looked like a red gate.
def UOp.set.end(e: Maybe<&2, List<&2, U32>>) -> List<&2, U32>:
  UOp.set.end.of(e)

# `val` is a node, because `argfix`/`UOp.const` turns a bare Python int into one
# before this point and the port takes the CONST. The `set_val_int` row is what
# proves the CAST was folded upstream of here rather than here.
# THE ARENA IS THREADED, NOT REUSED, and the first draft reused it:
#   +e = UOp.end(ar, Found.i(s), ...)   -- `ar`, the CALLER's
# `UOp.store` MINTS, so `s` lives in a GROWN arena and `Found.i(s)` read out of
# `ar` is an index into the wrong arena. It typechecked and answered
# `Ops.AFTER(Ops.BUFFER Ops.AFTER)` where CPython answers
# `Ops.AFTER(Ops.BUFFER Ops.STORE)` -- the stale node read back as whatever the
# caller's arena holds at that index, which is exactly the failure mode
# `bend2-constraints` names and `UOp.copy_to_device` above demonstrates the fix
# for. Every step takes the PREVIOUS step's `Found.ar`.
def UOp.set(+ar: Arena, +self: U32, val: U32, end: Maybe<&2, List<&2, U32>>) -> Found:
  +s = UOp.store(ar, self, val, None{})
  +e = UOp.end(Found.ar(s), Found.i(s), UOp.set.end(end))
  UOp.after(Found.ar(e), Arena.src(Found.ar(s), self, 0), [Found.i(e)])

# ==== the `set_*` fixture and rows =========================================
#
# The subject is a STORE over a BUFFER, because `UOp.set` reads `self.src[0]`. Node 3
# is that store and node 1 is its target; the CONSTs are the values the rows store
# and end with.
#
#   1 BUFFER   the store's target, and the AFTER's src[0]
#   2 CONST 1   the value already in the store
#   3 STORE[1,2] the SUBJECT
#   4 CONST 7   the value the rows store
#   5 CONST 9   the first end
#   6 CONST 3   the second end
#
# THE PRINTER IS TWO LEVELS DEEP, not the oracle's three, and that is a fact about
# the ROW rather than a gap: the answer is an AFTER over the END over the STORE, and
# naming the answer and its DIRECT children already separates all four answers. The
# oracle prints to the leaves because CPython's `deep` is a one-liner and there the
# depth was free. A printer deeper than the rows need is cost for nothing.
#
# `set_end_none` and `set_end_one` are the PAIR that makes `argfix`'s empty arm
# load-bearing: with no end the STORE's src count is one and with one end it is two,
# and the AFTER above it is the same op in both. A def that dropped the `Maybe` arm
# would pass one and fail the other.
def set_pa(slot: U32) -> ParamArg: ParamArg.of(slot, S.int32())

def set_ar() -> Arena:
  Arena{[
    Arena.bottom(),
    Node{OpsBUFFER{}, Nil{}, AParam{set_pa(1)}, TNone{}},
    Node{OpsCONST{}, Nil{}, APy{CInt{H.i64_of_i32(1)}}, TNone{}},
    Node{OpsSTORE{}, [1, 2], ANone{}, TNone{}},
    Node{OpsCONST{}, Nil{}, APy{CInt{H.i64_of_i32(7)}}, TNone{}},
    Node{OpsCONST{}, Nil{}, APy{CInt{H.i64_of_i32(9)}}, TNone{}},
    Node{OpsCONST{}, Nil{}, APy{CInt{H.i64_of_i32(3)}}, TNone{}}], [0]}

# THE PRINTER IS `Rng.srcops.seeded` (ops.bend:5072) AND NOT A NEW ONE. It folds
# op names in SOURCE ORDER with no trailing separator, which is the whole of what
# these rows need: `set` is a composition whose only failure modes are the SHAPE and
# the ORDER, and a row that printed a top-level op name could not tell `END` from a
# bare `STORE`.
#
# Three drafts of a local printer came first and all three were worse: a recursive
# `deep` needing a closer that knows its own depth, a `Bool.pick` for the first
# separator, and a fold that opened a paren in the accumulator. The file already had
# the right shape under a different name, which is the recurring lesson of this
# session: grep for the IDIOM before writing the INSTANCE.
# THE NODE ITSELF IS PART OF THE ROW. `Rng.srcops.seeded(ar, xs)` prints the ops of
# a SRC LIST, so passing `Arena.srcs(ar, i)` answers the CHILDREN and the answer's own
# op never appears -- the first run printed `Ops.BUFFER Ops.AFTER` where CPython
# prints `AFTER(...)`, and the missing AFTER is the whole of what the row is for.
# The concat puts the node's own name in front of its children.
# NO TRAILING SEPARATOR, and the first draft emitted one -- `Ops.AFTER(Ops.BUFFER
# Ops.STORE )` against CPython's `Ops.AFTER(Ops.BUFFER Ops.STORE)`. The separator is
# appended BEFORE each element rather than after, which is the same thing
# `Rng.srcops.go`'s `+first` flag does and for the same reason.
def set_deep.go(+ar: Arena, xs: List<&2, U32>, +acc: String, first: Bool) -> String:
  match xs:
    case Nil{}: acc
    case +i <> t:
      set_deep.go(ar, t, Bool.pick(String, first, String.concat([acc, Ops.name(Arena.op(ar, i))]),
        String.concat([acc, " ", Ops.name(Arena.op(ar, i))])), False{})

def set_deep(+ar: Arena, +i: U32) -> String:
  String.concat([Ops.name(Arena.op(ar, i)), "(", set_deep.go(ar, Arena.srcs(ar, i), "", True{}), ")"])

def set_row(nm: String, +ar: Arena, subj: U32, val: U32, end: Maybe<&2, List<&2, U32>>) -> IO(Unit):
  +f = UOp.set(ar, subj, val, end)
  srow(nm, set_deep(Found.ar(f), Found.i(f)))

def set_rows(+ar: Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- set_row("set_end_none", ar, 3, 4, None{})
    b : Unit <- set_row("set_end_one", ar, 3, 4, Some{[5]})
    c : Unit <- set_row("set_end_two", ar, 3, 4, Some{[5, 6]})
    set_row("set_end_two_src", ar, 3, 4, Some{[6, 5]})

def main() -> IO(Unit):
  do IO<Unit>:
    u0 : Unit <- set_rows(set_ar())
    x0 : Unit <- vd_rows(vd_arena())
    y0 : Unit <- vrn_rows(Arena.empty())
    w0 : Unit <- rra.rows(rra.arena())
    v0 : Unit <- vr.expr.rows(vr.arena())
    a0 : Unit <- sg.rows()
    z : Unit <- s5.rows()
    a : Unit <- row("hashcons", t_hashcons())
    a2 : Unit <- row("float_zeros_differ", t_float_zeros_differ())
    a3 : Unit <- row("float_nan_interns", t_float_nan_interns())
    b : Unit <- row("dtype_key", t_dtype_key())
    c : Unit <- row("cycle", t_cycle())
    row("after_puts_self_first", t_after_puts_self_first())
    row("end_puts_self_first", t_end_puts_self_first())
    d : Unit <- row("toposort", t_toposort())
    e : Unit <- row("cycle_terminates", t_cycle_terminates())
    f : Unit <- row("key_eq", t_key_eq())
    g : Unit <- row("eq_dt", t_eq_dt())
    h : Unit <- row("eq_dt_disjoint", t_eq_dt_disjoint())
    i : Unit <- row("weakfloat_interns", t_weakfloat_interns())
    j : Unit <- row("eq_addr", t_eq_addr())
    k : Unit <- row("addr_interns", t_addr_interns())
    l : Unit <- row("ops_name", t_ops_name())
    m : Unit <- row("var_interns", t_var_interns())
    n : Unit <- row("broadcast_repeats", t_broadcast_repeats())
    o : Unit <- row("required_len", t_required_len())
    p : Unit <- row("alu_permutes", t_alu_permutes())
    row("early_reject", t_early_reject())
    row("ler_len", t_ler_len())
    # --- THE CustomFunction LANE. ops.py:1394/1258. `eq_customfunction` and
    # --- `CustomFunction.of` had no row, so three mutations of them moved nothing.
    row("cfun_interns", t_cfun_interns())
    row("cfun_dtype_splits", t_cfun_dtype_splits())
    row("cfun_name_splits", t_cfun_name_splits())
    srow("cfun_arg", t_cfun_arg())
    srow("cfun_of", cfun_of_str())
    # --- THE BLOB LANE. ops.py:201. `ABlob` is the intern key's bytes half and it
    # --- compared the LENGTH, so two different same-length blobs were ONE node.
    row("blob_interns", t_blob_interns())
    row("blob_len_diff_content", t_blob_len_diff_content())
    row("blob_diff_len", t_blob_diff_len())
    srow("blob_count_same", s_blob_count_same())
    srow("blob_count_len_diff_content", s_blob_count_len_diff_content())
    srow("blob_shape", s_blob_shape())
    srow("blob_content", s_blob_content())
    row("blob_sweep", t_blob_sweep())
    srow("blob_sweep_count", s_blob_sweep_count())
    # --- THE BARE-FLOAT LANE. ops.py:201. `AFloat` is the intern key's float half and
    # --- it compares IEEE, which is CORRECT for a bare `float` and wrong for the
    # --- `ConstFloat` in `eq_const.CFloat` -- see the comment on `eq_arg.AFloat`.
    row("afloat_zeros_intern", t_afloat_zeros_intern())
    row("afloat_nan_distinct_intern", t_afloat_nan_distinct_intern())
    row("afloat_same_intern", t_afloat_same_intern())
    row("afloat_distinct_intern", t_afloat_distinct_intern())
    # --- THE `type(tag)` LANE. ops.py:201 carries `type(arg)` and NOT `type(tag)`, so
    # --- `tag=True` and `tag=1` are ONE key. This is the only OVER-split in the file;
    # --- every other comparator dispute here is an under-split.
    #
    # THE ORDER IS THE ORACLE'S: `const_bool_vs_int_splits` first, because it is the
    # control for the three below and ops-gate.sh diffs whole lines in order.
    row("const_bool_vs_int_splits", t_const_bool_vs_int_splits())
    # --- THE NESTED LANE, the second instance of the same over-split: `ParamArg.val` is a
    # --- `PyConst` INSIDE `arg`, so `type(arg)` does not separate a bool from an int there.
    row("pynest_bool_vs_int_interns", t_pynest_bool_vs_int_interns())
    row("pynest_int_distinct_interns", t_pynest_int_distinct_interns())
    row("pynest_none_vs_zero_interns", t_pynest_none_vs_zero_interns())
    row("pynest_signed_zero_interns", t_pynest_signed_zero_interns())
    row("pynest_cfloat_vs_int_interns", t_pynest_cfloat_vs_int_interns())
    row("tag_bool_vs_int_interns", t_tag_bool_vs_int_interns())
    row("tag_true_vs_false_splits", t_tag_true_vs_false_splits())
    row("tag_none_vs_zero_interns", t_tag_none_vs_zero_interns())
    # --- THE AXIS CPYTHON LANE. `#bend_only_mstack_puts_self_first` first, because it is
    # --- the row this file was MISSING: `UOp.after` and `UOp.end` had rows and
    # --- `UOp.mstack` had the same inverse bug fixed in the same commit with none, so a
    # --- re-regression of mstack alone was invisible while the other two stayed green.
    row("mstack_puts_self_first", t_mstack_puts_self_first())
    t_ax_derivation()
    t_ax_tables(AxisType.live())
    t_ax_range_start()
    t_rng_weak1()
    t_rng_loop1()
    t_rng_dev3()
    t_rng_loopfn()
    t_rng_twoid()
    srow("axlt_sorted", ax_names_str(List.sort(AxisType, AxisType.lt, AxisType.live())))
    srow("axlt_revsorted", ax_names_str(RevAxis.go(List.reverse(&2, AxisType, AxisType.live()), Nil{})))
    srow("axlt_lt", Bool.show(AxisType.lt(AXIS_LOOP{}, AXIS_WEAK{})))
    srow("axlt_gt", Bool.show(AxisType.lt(AXIS_WEAK{}, AXIS_LOOP{})))
    srow("eqax_collide", U32.show(EqAx.collide(AxisType.live())))
    srow("eqax_collide_all", U32.show(EqAx.collide(AxisType.all())))
    srow("eqax_diag", U32.show(EqAx.diag(AxisType.live())))
    srow("eqax_diag_all", U32.show(EqAx.diag(AxisType.all())))
    t_mstack_rows()
    # CPython `is` on the two args `ARange` flattens together. ops.py:201, :643.
    row("uc_flat_nest", Uc.same(0, 1, [0, 1]))
    row("uc_int_tup1", Uc.same(0, 1, [0]))
    row("uc_nest_deep", Uc.same(1, 2, [0, 1]))
    row("uc_flat_same", Uc.same(0, 0, [0, 1]))
    row("uc_nest_same", Uc.same(1, 1, [0, 1]))
    srow("ucdepth_flat_nest", Uc.depth(0, 1, [0, 1]))
    # --- THE BACKWARD-SLICE LANE. ops.py:280/286/289, ported above `pm_r_sink`.
    srow("bsl_chain", Bsl.chain())
    srow("bsws_chain", Bsl.chain.ws())
    srow("bsop_chain_add", Bsl.chain.add())
    srow("bsop_chain_mul", Bsl.chain.mul())
    srow("bsl_call", Bsl.call())
    srow("bsws_call", Bsl.call.ws())
    srow("bsop_call_call", Bsl.call.call())
    srow("bsl_nest", Bsl.nest())
    srow("bsws_nest", Bsl.nest.ws())
    srow("bsop_nest_pair", Bsl.nest.pair())
    srow("bsl_backedge", Bsl.backedge())
    srow("bsws_backedge", Bsl.backedge.ws())
    srow("bsop_backedge_backedge", Bsl.backedge.be())
    srow("bsop_backedge_range", Bsl.backedge.range())

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
#   `CustomFunction` -- PORTED 2026-10-03, at ops.py's own position (between
#     `OPAQUE_CALL_BODIES` and `CallInfo`), together with `Arg`'s `ACustom` arm,
#     `eq_customfunction` and `UOp.custom_function`. The old text here said it was
#     PORTABLE but unreachable and so would "land with" the P6 hcq2 work; it landed
#     without it, because `uop/spec.py:110`'s `isinstance(x.arg, CustomFunction)`
#     needs the datatype and `spec.bend`'s `sh_22` is stale until it has one. Being
#     P6 only ever described the CALLERS, never the type.
#     WHAT IS STILL OPEN IS THE OTHER HALF, and it is NOT optional: upstream MOVED
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
#   `UPat.custom_function(fn, **kwargs)` -- ops.py:1509 upstream, still NOT PORTED. A
#     `PatternMatcher` rule constructor, so it lands with `uop/upat.py`.
#   `UOp.param_like(slot, name=None)` -- ops.py:1241 upstream. `name` was added so a
#     scalar argument can be bound by NAME while its slot and value stay out of the
#     schedule cache key. P6, with the hcq call sites that use it.
#   `UOp.contiguous_view()`'s new tail -- upstream now returns a BITCAST SLICE
#     (`b.src[0].flatten()[...]`) where the pin returned `(b.rtag(None), offset)`, and
#     it computes the offset with `strides_for_shape` instead of a
#     `pm_contiguous_view_offset` matcher. P3 with `symbolic.bend`; the matcher form is
#     NOT PORTED for the reason the pattern compiler is, below.
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



def head1(xs: List<&2, U32>) -> U32:
  match xs:
    case Nil{}: 0
    case x <> _: x

