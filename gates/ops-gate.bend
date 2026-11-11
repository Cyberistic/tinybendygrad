# gates/ops-gate.bend -- THE GATE DRIVER for `tinybendygrad/uop/ops.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. The port file carries the port and
# this file carries the instrument, and the tree's own convention says so:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# And the rows are pure consumers: they call the port's defs and define
# nothing that the port needs.

import Base
import ./../tinybendygrad/uop/ops.bend as P
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/renderer/estimates.bend as E

# axis_letters / axis_colors -- ops.py:51,53. Two dictionaries keyed by an Enum, two
# `match` ladders. upstream drops the `REDUCE`/`UNROLL` entries and adds nothing, so
# PLACEHOLDER -- in the enum and in neither dict -- and the two dead members are all
# MISSES. A Bend def cannot raise, so the miss is ANSWERED rather than swallowed: both
# ladders return `"!KeyError"`, the name of the exception Python raises, which is the
# same treatment `P.ABad{}` gives `self.src[0]` on an empty src. Returning `""` would
# have been a silent widening -- indistinguishable from a member whose letter really is
# empty -- and there is no such member, so the marker is free of false agreement.
def axis_letters(a: P.AxisType) -> String:
  match a:
    case P.AXIS_DEVICE{}: "d"
    case P.AXIS_GLOBAL{}: "g"
    case P.AXIS_LOCAL{}: "l"
    case P.AXIS_WARP{}: "w"
    case P.AXIS_WEAK{}: "L"
    case P.AXIS_LOOP{}: "L"
    case P.AXIS_UPCAST{}: "u"
    case _: "!KeyError"

# `range_start` AS A ROW. `range_start` answers a `U32` and a miss is 0, which is also
# `Ops.LINEAR`'s answer, so the U32 alone cannot say whether an op was NAMED. This is
# the printer the `axs_*` rows use: `U32.show` for a hit and the exception's name for a
# miss, which is what CPython's `range_start[op]` in a `try` prints. This is a GATE
# PRINTER, not a ported def -- it has no counterpart in ops.py.
def range_start_str(op: P.Op) -> String:
  match op:
    case P.OpsSTAGE{}: "1"
    case P.OpsREDUCE{}: "1"
    case P.OpsEND{}: "1"
    case P.OpsCALL{}: "1"
    case P.OpsLINEAR{}: "0"
    case _: "!KeyError"

def gate_kernel_sink(+ar: P.Arena, +x: U32) -> Bool:
  P.gate_kernel_sink.of(P.Arena.op(ar, x), P.Arena.arg(ar, x))

# FOUR, not five: `P.Arena.empty()` parks a BOTTOM sentinel at index 0 that is not
# a UOp, so a four-node graph has `P.Arena.next(ar) == 5` and a four-element
# toposort. CPython agrees, on the tree `g_chain` rebuilds --
#   c0 = P.UOp.const(0); r0 = UOp.range(c0, (0,), AxisType.LOOP)
#   list(UOp.range(r0 + c0, (0,), AxisType.GLOBAL).toposort()) has four entries,
#   'Ops.CONST', 'Ops.RANGE', 'Ops.ADD', 'Ops.RANGE'.
# ops.py:621 `P.UOp.after` builds `src=(self,)+src`, so SELF IS src[0]. This row exists
# because `P.UOp.after`, `P.UOp.end` and `P.UOp.mstack` all had the inverse -- SELF LAST -- and
# nothing in this file could see it. An after built either way has the same op, the same
# nsrc, the same shape and the same dtype; only the SRC OP SEQUENCE differs, and no row
# printed that. P.Found by the schedule/prepare unit, which built its own AFTER in the right
# order to route around the bug instead of editing this file.
#
# So this row asserts the SEQUENCE, not the count. The self is a RANGE (P.UOp.range_end
# builds OpsRANGE, ops.py:660) and the supplied node is a CONST, so self-first means
# src[0]=RANGE and src[1]=CONST. The bug answers exactly the reverse.
def t_after_puts_self_first() -> Bool:
  +c = P.UOp.const(P.Arena.empty(), P.CInt{H.i64_of_i32(0)})
  +e = P.UOp.range_end(P.Found.ar(c), P.Found.i(c), [0], P.AXIS_GLOBAL{})
  +a = P.UOp.after(P.Found.ar(e), P.Found.i(e), [P.Found.i(c)])
  +ar = P.Found.ar(a)
  Bool.and(P.op_is(ar, P.Found.i(a), P.OpsAFTER{}),
  Bool.and(P.op_is(ar, P.Arena.src(ar, P.Found.i(a), 0), P.OpsRANGE{}),
           P.op_is(ar, P.Arena.src(ar, P.Found.i(a), 1), P.OpsCONST{})))

# the same for `P.UOp.end` (ops.py:619): self first, supplied node second.
def t_end_puts_self_first() -> Bool:
  +c = P.UOp.const(P.Arena.empty(), P.CInt{H.i64_of_i32(0)})
  +e = P.UOp.range_end(P.Found.ar(c), P.Found.i(c), [0], P.AXIS_GLOBAL{})
  +e2 = P.UOp.end(P.Found.ar(e), P.Found.i(e), [P.Found.i(c)])
  +ar = P.Found.ar(e2)
  Bool.and(P.op_is(ar, P.Found.i(e2), P.OpsEND{}),
  Bool.and(P.op_is(ar, P.Arena.src(ar, P.Found.i(e2), 0), P.OpsRANGE{}),
           P.op_is(ar, P.Arena.src(ar, P.Found.i(e2), 1), P.OpsCONST{})))

def t_toposort() -> Bool:
  +f = P.g_chain()
  +ar = P.Found.ar(f)
  o = P.UOp.toposort(P.Arena.budget(ar), ar, P.Found.i(f))
  Nat.is_eq(List.length(&2, U32, o), 4n)

# the same walk over a cycle must terminate. The fuel is what makes that true,
# and it answers the partial set rather than looping: `case 0n:` in `toposort`.
def t_cycle_terminates() -> Bool:
  +f = P.g_cycle()
  +o = P.UOp.toposort(64n, P.Found.ar(f), P.Found.i(f))
  Bool.and(Bool.not(Nat.is_eq(List.length(&2, U32, o), 0n)), Nat.is_le(List.length(&2, U32, o), 8n))

def t_key_eq() -> Bool:
  Bool.and(Bool.and(P.key_same(P.Node{P.OpsADD{}, [1, 2], P.ANone{}, P.TNone{}}, P.Node{P.OpsADD{}, [1, 2], P.ANone{}, P.TNone{}}),
    Bool.not(P.key_same(P.Node{P.OpsADD{}, [1, 2], P.ANone{}, P.TNone{}}, P.Node{P.OpsADD{}, [1, 3], P.ANone{}, P.TNone{}}))),
    Bool.not(P.key_same(P.Node{P.OpsADD{}, [1, 2], P.ANone{}, P.TNone{}}, P.Node{P.OpsADD{}, [1, 2], P.ANone{}, P.TStr{"t"}})))

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
  Bool.and(Bool.and(P.eq_dt(S.void(), S.void()), P.eq_dt(S.weakint(), S.weakint())),
    Bool.and(Bool.and(P.eq_dt(S.boolean(), S.boolean()), P.eq_dt(S.uint32(), S.uint32())),
    Bool.and(Bool.and(P.eq_dt(S.int32(), S.int32()), P.eq_dt(S.half(), S.half())),
    Bool.and(P.eq_dt(S.single(), S.single()), P.eq_dt(S.weakfloat(), S.weakfloat())))))

# and the CONFLATION is pinned separately, because a row that only asks "is it
# equal to itself" would also pass a `Cls` compared by something weaker than
# identity. These five are the pairs a six-arm ladder gets wrong or gets right by
# accident, and each names a different arm boundary: weakfloat against the
# concrete float it used to be conflated with, against the weak int it is one
# lattice step from, void against either, and the two 16-bit floats whose only
# difference is `pri`.
def t_eq_dt_disjoint() -> Bool:
  Bool.and(Bool.and(Bool.not(P.eq_dt(S.weakfloat(), S.half())), Bool.not(P.eq_dt(S.half(), S.weakfloat()))),
    Bool.and(Bool.and(Bool.not(P.eq_dt(S.weakfloat(), S.weakint())), Bool.not(P.eq_dt(S.weakint(), S.weakfloat()))),
    Bool.and(Bool.not(P.eq_dt(S.half(), S.bfloat16())), Bool.not(P.eq_dt(S.void(), S.weakfloat())))))

def t_weakfloat_interns() -> Bool:
  Bool.and(U32.is_eq(P.g_cast_twice(S.weakfloat()), 3), U32.is_eq(P.g_cast_twice(S.half()), 3))

# --- eq_addr, and the hash-consing that DEPENDS on it -------------------------
# The whole 4x4, in declaration order, against an oracle that is an IDENTITY:
# dtype.py:51-54's `AddrSpace` is an `IntEnum` with four members and no
# `__eq__` override, so `(a == b) == (a is b)` and the matrix `tinygrad` answers
# is `[[T,F,F,F],[F,T,F,F],[F,F,T,F],[F,F,F,T]]`. Each row below is one `x` of
# `eq_addr`, read left to right against AGlobal, ALocal, AReg, Aalu.
def t_eq_addr() -> Bool:
  Bool.and(Bool.and(Bool.and(Bool.and(P.eq_addr(S.AGlobal{}, S.AGlobal{}), Bool.not(P.eq_addr(S.AGlobal{}, S.ALocal{}))), Bool.and(Bool.not(P.eq_addr(S.AGlobal{}, S.AReg{})), Bool.not(P.eq_addr(S.AGlobal{}, S.Aalu{})))), Bool.and(Bool.and(Bool.not(P.eq_addr(S.ALocal{}, S.AGlobal{})), P.eq_addr(S.ALocal{}, S.ALocal{})), Bool.and(Bool.not(P.eq_addr(S.ALocal{}, S.AReg{})), Bool.not(P.eq_addr(S.ALocal{}, S.Aalu{}))))),
    Bool.and(Bool.and(Bool.and(Bool.not(P.eq_addr(S.AReg{}, S.AGlobal{})), Bool.not(P.eq_addr(S.AReg{}, S.ALocal{}))), Bool.and(P.eq_addr(S.AReg{}, S.AReg{}), Bool.not(P.eq_addr(S.AReg{}, S.Aalu{})))), Bool.and(Bool.and(Bool.not(P.eq_addr(S.Aalu{}, S.AGlobal{})), Bool.not(P.eq_addr(S.Aalu{}, S.ALocal{}))), Bool.and(Bool.not(P.eq_addr(S.Aalu{}, S.AReg{})), P.eq_addr(S.Aalu{}, S.Aalu{})))))

def t_addr_interns() -> Bool:
  Bool.and(U32.is_eq(P.g_param_twice(P.g_param_addr(0, S.Aalu{}), P.g_param_addr(0, S.Aalu{})), 3),
    U32.is_eq(P.g_param_twice(P.g_param_addr(0, S.Aalu{}), P.g_param_addr(0, S.AReg{})), 4))

# --- P.Ops.name, which is `FastEnum.__str__` ----------------------------------
# `P.Ops.name` has NO reader inside this file, so nothing above could see it: the
# first bug this port found in it was found in `render.bend`, from a
# `REDUCE.arg`. Both halves of the answer are pinned, because CPython has TWO
# string forms of an enum member and this file used to have one.
def t_ops_name() -> Bool:
  Bool.and(Bool.and(String.eq(P.Ops.name(P.OpsSPECIAL{}), "Ops.SPECIAL"), String.eq(P.Ops.name(P.OpsADD{}), "Ops.ADD")),
    Bool.and(Bool.and(String.eq(P.Ops.name(P.OpsREDUCE{}), "Ops.REDUCE"), String.eq(P.Ops.name(P.OpsPYLITERAL{}), "Ops.PYLITERAL")),
      Bool.and(String.eq(P.Ops.name.of(P.OpsADD{}), "ADD"), String.eq(P.Ops.name.of(P.OpsCUSTOM_FUNCTION{}), "CUSTOM_FUNCTION"))))

def t_var_interns() -> Bool:
  P.t_var_interns.of(P.UPat.var(P.Pat{[]}, Some{"x"}, None{}))




def t_broadcast_repeats() -> Bool:
  P.t_broadcast_repeats.go(P.UPat.broadcast(P.pat_base(), 0))



def t_required_len() -> Bool:
  P.t_required_len.of(P.pat_nth(P.UPat.broadcast(P.pat_base(), 0), 1),
                    P.pat_nth(P.UPat.f(P.pat_base(), 0, P.OpsADD{}), 1))


def t_alu_permutes() -> Bool:
  P.t_alu_permutes.of(P.UPat.alu(P.pat_base(), 0, P.OpsADD{}, 1),
                    P.UPat.alu(P.pat_base(), 0, P.OpsCAST{}, 1))



def t_early_reject() -> Bool:
  P.t_early_reject.of(P.UPat.early_reject(P.pat_nth(P.UPat.f(P.pat_base_op(), 0, P.OpsADD{}), 1)))





def t_ler_len() -> Bool:
  P.t_ler_len.of(P.g_ler())


# --- THE GATE ROWS ------------------------------------------------------
# Bend has no assertion form, so `main` PRINTS each answer and the gate is that both
# lanes print the same lines. A `False{}` anywhere is the failure.
def row(nm: String, b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(b)]))

# ---------------------------------------------------------------------------
# P.CustomFunction -- ops.py:1394 / :1258. THE ROWS THIS TYPE WAS MISSING, and the
# measurement that asked for them.
#
# `eq_customfunction` and `P.CustomFunction.of` landed with NO row at all, and three of
# their mutations each moved 0 of the other 104: drop the dtype half of the
# comparison, drop the name half, and make the `eq_arg.ACustom` arm unconditionally
# true. None of those is a THEOREM -- there is nothing undecidable about a two-field
# structural comparison. They were a 0 because nothing the gate could see ever called
# them, which is the `0` that means REQUEST FOR A FIXTURE rather than coverage.
#
# THE FIXTURES ARE THREE CPython ANSWERS, read live and not transcribed:
#     P.CustomFunction("f")                 == P.CustomFunction("f")                 -> True
#     P.CustomFunction("f")                 == P.CustomFunction("f", dtypes.uint64) -> False
#     P.CustomFunction("f", dtypes.uint64)  == P.CustomFunction("g", dtypes.uint64) -> False
# BOTH fields are therefore in the key, and the return dtype SPLITS the ucache. The
# third answer is the one that matters downstream: `dtype_from_uop`'s CUSTOM_FUNCTION
# arm is `return arg.dtype`, so the dtype is the node's TYPE, not a field nobody
# reads. The `hcq2.py:84` caller spells it `custom_function(fn.__name__, dtype=ret)`
# for exactly that reason.
def g_cfun_pair(nm1: String, dt1: S.Dt, nm2: String, dt2: S.Dt) -> Bool:
  # the DIAGONAL CELL IS `True` -- intern's linear scan finds the existing key -- and
  # the two OFF-DIAGONAL cells are the ones a row has to earn.
  +a = P.UOp.custom_function(P.Arena.empty(), nm1, Nil{}, dt1)
  +b = P.UOp.custom_function(P.Found.ar(a), nm2, Nil{}, dt2)
  U32.is_eq(P.Found.i(a), P.Found.i(b))

def t_cfun_interns() -> Bool:
  g_cfun_pair("sel_registerName", S.void(), "sel_registerName", S.void())

def t_cfun_dtype_splits() -> Bool:
  Bool.not(g_cfun_pair("sel_registerName", S.void(), "sel_registerName", S.uint64()))

def t_cfun_name_splits() -> Bool:
  Bool.not(g_cfun_pair("submit_null", S.void(), "submit_cl", S.void()))

def cfun_fields_str(cf: P.CustomFunction) -> String:
  match cf:
    case P.CustomFunction{name, dtype}: String.concat([name, "|", P.dt_name(dtype)])

def cfun_arg_str.go(a: P.Arg) -> String:
  match a:
    case P.ACustom{cf}: cfun_fields_str(cf)
    case _: "!ACustom"
    case _: "!ACustom"

def cfun_arg_str(+ar: P.Arena, i: U32) -> String:
  cfun_arg_str.go(P.Arena.arg(ar, i))

# THE DEFAULT, ops.py:1397's `dtype: DType = dtypes.void`. This is the row for
# `P.CustomFunction.of`, and it is a STRING row for the same reason `cfun_arg_str` is:
# the answer is a PAIR, and a Bool row cannot say which pair.
def cfun_of_str() -> String:
  String.concat([P.CustomFunction.name(P.CustomFunction.of("sel_registerName")), "|", P.dt_name(P.CustomFunction.dtype(P.CustomFunction.of("sel_registerName")))])

def t_cfun_arg() -> String:
  +a = P.UOp.custom_function(P.Arena.empty(), "sel_registerName", Nil{}, S.uint64())
  cfun_arg_str(P.Found.ar(a), P.Found.i(a))

# ---------------------------------------------------------------------------
# blob -- the intern key's bytes half. ops.py:201, spec.py:96, ops.py:365.
#
# `UOpMetaClass.__call__` keys on `(op, src, arg, tag, type(arg))`, so for a BINARY
# the key HOLDS the `bytes` object and dict equality compares bytes CONTENT-WISE.
# This port spells that arg `ABlob`, and it spelled it `P.ABlob{n: U32}` -- the LENGTH --
# so `eq_arg.ABlob` compared a summary. Two DIFFERENT blobs of the SAME length were
# then the same key: one node where CPython has two, and `P.Arena.next` one short.
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
  +u = P.UOp.new(P.Arena.empty(), P.OpsBINARY{}, Nil{}, P.ABlob{bs1}, P.TNone{})
  +v = P.UOp.new(P.Found.ar(u), P.OpsBINARY{}, Nil{}, P.ABlob{bs2}, P.TNone{})
  U32.is_eq(P.Found.i(u), P.Found.i(v))

# the node count CPython's `len(ucache)` answers, sentinel removed.
def blob_ucount(bs1: List<&2, U32>, bs2: List<&2, U32>) -> U32:
  +u = P.UOp.new(P.Arena.empty(), P.OpsBINARY{}, Nil{}, P.ABlob{bs1}, P.TNone{})
  +v = P.UOp.new(P.Found.ar(u), P.OpsBINARY{}, Nil{}, P.ABlob{bs2}, P.TNone{})
  U32.sub(P.Arena.next(P.Found.ar(v)), 1)

def t_blob_interns() -> Bool: blob_same(BLOB_A(), BLOB_A())

def t_blob_len_diff_content() -> Bool: Bool.not(blob_same(BLOB_A(), BLOB_B()))

def t_blob_diff_len() -> Bool: Bool.not(blob_same(BLOB_A(), BLOB_C()))

def s_blob_count_same() -> String: U32.show(blob_ucount(BLOB_A(), BLOB_A()))

def s_blob_count_len_diff_content() -> String: U32.show(blob_ucount(BLOB_A(), BLOB_B()))

# the blob bytes read back OUT of a node's arg, which is what `len()` and the repr both
# need now that `ABlob` holds the bytes rather than a count. `Nil{}` for a non-blob arg:
# `uop/fold.bend`'s `binary_n` already answers 0 for one, and a second spelling of the
# same absence is a second thing to keep in step.
def blob_bytes(a: P.Arg) -> List<&2, U32>:
  match a:
    case P.ABlob{bs}: bs
    case _: Nil{}

# `ops.py:365`, `case Ops.BINARY: return (len(self.arg),)` -- the LENGTH is still a
# fact about a blob after the key reads its content, and it is the one
# `uop/fold.bend`'s `binary_n` and `uop/render.bend`'s repr read. A fix that dropped it
# would leave both of those answering 0. The trailing comma is Python's 1-tuple comma.
def s_blob_shape() -> String:
  +u = P.UOp.new(P.Arena.empty(), P.OpsBINARY{}, Nil{}, P.ABlob{BLOB_A()}, P.TNone{})
  String.concat(["(", Nat.show(List.length(&2, U32, blob_bytes(P.Arena.arg(P.Found.ar(u), P.Found.i(u))))), ",)"])

# the CONTENT, read back out of the node rather than asserted about it. This is the row
# that pins the REPRESENTATION: whatever the key compares, it must read back as
# CPython reads `list(u.arg)`.
def s_blob_content() -> String:
  +u = P.UOp.new(P.Arena.empty(), P.OpsBINARY{}, Nil{}, P.ABlob{BLOB_A()}, P.TNone{})
  U32s.str(blob_bytes(P.Arena.arg(P.Found.ar(u), P.Found.i(u))))

# THE NODE-COUNT SWEEP, and it is here because of a measured failure in this repo: four
# aliasing bugs in `codegen/decomp/dtype.bend` agreed at one arena size and broke at the
# next, with the signature "count barely moves, cone collapses". One configuration is
# one point, so this walks SIX blobs and every blob is interned TWICE. Both halves of
# the answer are in the one Bool: a key that MERGED two blobs lands the second on the
# first's index, and a key that STOPPED hash-consing lands the repeat one index further
# on. Either moves `P.Found.i(u)` off `i+1`.
#
# The lengths run 0,1,2,3,4,4 -- the last two are the same length and different content.
# Six blobs of six distinct lengths would be a pure count sweep, and measured: with
# lengths 0,1,2,3,4,5 the length-summary mutation M1 moved `blob_len_diff_content` and
# `blob_sweep_count` but left `blob_sweep` True, because no two sweep blobs could collide
# under a length key. The equal-length tail is what closes that.
def blob_sweep.go(bss: List<&2, List<&2, U32>>, +ar: P.Arena, +i: U32) -> Bool:
  match bss:
    case Nil{}: True{}
    case +b <> t:
      +u = P.UOp.new(ar, P.OpsBINARY{}, Nil{}, P.ABlob{b}, P.TNone{})
      +v = P.UOp.new(P.Found.ar(u), P.OpsBINARY{}, Nil{}, P.ABlob{b}, P.TNone{})
      Bool.and(U32.is_eq(P.Found.i(u), P.Found.i(v)),
        Bool.and(U32.is_eq(P.Found.i(u), U32.add(i, 1)), blob_sweep.go(t, P.Found.ar(v), U32.add(i, 1))))

def blob_sweep_blobs() -> List<&2, List<&2, U32>>:
  [Nil{}, [97], [97, 98], [97, 98, 99], [97, 98, 99, 100], [97, 98, 99, 101]]

def blob_sweep_ar.go(bss: List<&2, List<&2, U32>>, +ar: P.Arena) -> P.Arena:
  match bss:
    case Nil{}: ar
    case b <> t:
      +f = P.UOp.new(ar, P.OpsBINARY{}, Nil{}, P.ABlob{b}, P.TNone{})
      blob_sweep_ar.go(t, P.Found.ar(f))

def t_blob_sweep() -> Bool: blob_sweep.go(blob_sweep_blobs(), P.Arena.empty(), 0)

def s_blob_sweep_count() -> String:
  U32.show(U32.sub(P.Arena.next(blob_sweep_ar.go(blob_sweep_blobs(), P.Arena.empty())), 1))

# ---------------------------------------------------------------------------
# AFLOAT -- `P.Arg`'s BARE-float arm, the OTHER half of the intern key. ops.py:201.
#
# The measurement and the reason `F32.is_eq` is right here and `F32.bits` would be a
# regression are the comment on `eq_arg.AFloat` above; this block is the GATE for it.
# `AFloat` has no constructor anywhere in the tree -- `uop/upat.bend:396 symbol=arg_int` and
# `uop/render.bend:741 symbol=arg_repr` only READ it, and its one would-be builder `_frompy` is
# `TODO(p3)` at :4318 -- so no interning fixture can reach the arm the normal way and
# the comparator was untested rather than unreachable. These rows intern two
# `AFloat`s on ONE arena through `P.UOp.new`, so the answer is IDENTITY OF THE TWO
# INDICES and not `eq_arg` read directly: `blob_same` above says why, and this is
# the same rule.
# ---------------------------------------------------------------------------
def afloat_same(f1: F32, f2: F32) -> Bool:
  +u = P.UOp.new(P.Arena.empty(), P.OpsCONST{}, Nil{}, P.AFloat{f1}, P.TNone{})
  +v = P.UOp.new(P.Found.ar(u), P.OpsCONST{}, Nil{}, P.AFloat{f2}, P.TNone{})
  U32.is_eq(P.Found.i(u), P.Found.i(v))

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
# Same rule as the two lanes above: intern two nodes on ONE arena through `P.UOp.new`
# and answer IDENTITY OF THE TWO INDICES, never `eq_tag` read directly.
# ---------------------------------------------------------------------------
def tag_same(t1: P.Tag, t2: P.Tag) -> Bool:
  +u = P.UOp.new(P.Arena.empty(), P.OpsSINK{}, Nil{}, P.ANone{}, t1)
  +v = P.UOp.new(P.Found.ar(u), P.OpsSINK{}, Nil{}, P.ANone{}, t2)
  U32.is_eq(P.Found.i(u), P.Found.i(v))

# the cell the fix is about, and it reads TRUE, which is "the two interned to one node".
# `rtag(self, tag=True)` -- ops.py:258 -- is what puts a `bool` True in the key, and
# `UOp(Ops.SINK, tag=1)` is the same key.
def t_tag_bool_vs_int_interns() -> Bool: tag_same(P.TBool{True{}}, P.TInt{1})

# THE COUNTER-CELL, and it is what makes the row above mean something: an `eq_tag` that
# answered True for every pair would satisfy it alone. Printed as "did they SPLIT", so
# this is `Bool.not` of `tag_same` where the `_interns` rows are `tag_same` itself.
def t_tag_true_vs_false_splits() -> Bool: Bool.not(tag_same(P.TBool{True{}}, P.TBool{False{}}))

# and the one that keeps `TNone` separate from zero, which a `case` arm that stopped
# matching would answer the other way SILENTLY. `hash(None) != hash(0)`, so this is
# FALSE -- two nodes -- and the row exists to hold that.
def t_tag_none_vs_zero_interns() -> Bool: tag_same(P.TNone{}, P.TInt{0})

# ---------------------------------------------------------------------------
# MSTACK -- ops.py:770, `UOp(Ops.MSTACK, src=(self,)+srcs) if len(srcs) else self`.
#
# the row this file was missing, and it is a known loose end rather than a new finding.
# `P.UOp.after`, `P.UOp.end` and `P.UOp.mstack` all had `srcs ++ [self]` where CPython has
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
def g_mstack.base(ar: P.Arena, r: U32, b: U32, c: U32) -> P.Found: P.UOp.mstack(ar, r, Nil{})

def g_mstack.one(ar: P.Arena, r: U32, b: U32, c: U32) -> P.Found: P.UOp.mstack(ar, r, [b])

def g_mstack.go(+n: U32, ar: P.Arena, r: U32, b: U32, c: U32) -> P.Found:
  match n:
    case 0: g_mstack.base(ar, r, b, c)
    case 1: g_mstack.one(ar, r, b, c)
    case _: P.UOp.mstack(ar, r, [b, c])

def g_mstack(n: U32) -> P.Found:
  # `self` is a RANGE and the supplied srcs are CONSTs, so self-first prints
  # `RANGE CONST CONST` and the bug prints `CONST CONST RANGE`.
  #
  # the arena is threaded through every node, and this is the rule that costs the most
  # when it is forgotten. `P.UOp.const(ar, v)` takes an arena and returns a `P.Found` over a
  # GROWTH arena; the local `ar` is not advanced. Binding `+b = P.UOp.const(ar, ...)` and
  # then passing `ar` onwards builds the MSTACK in a THREE-node arena while `P.Found.i(b)`
  # is an index into a FOUR-node one -- MEASURED: the src ops printed
  # `RANGE MSTACK MSTACK` and the node count printed 2, and `mstack_puts_self_first`
  # answered False. `P.Found.ar` of the previous node is the only way to carry the growth.
  +c0 = P.UOp.const(P.Arena.empty(), P.CInt{H.i64_of_i32(4)})
  +r = P.UOp.range_end(P.Found.ar(c0), P.Found.i(c0), [0], P.AXIS_WEAK{})
  +ri = P.Found.i(r)
  +b = P.UOp.const(P.Found.ar(r), P.CInt{H.i64_of_i32(1)})
  +bi = P.Found.i(b)
  +c = P.UOp.const(P.Found.ar(b), P.CInt{H.i64_of_i32(2)})
  g_mstack.go(n, P.Found.ar(c), ri, bi, P.Found.i(c))

def t_mstack_puts_self_first() -> Bool:
  +f = g_mstack(2)
  +ar = P.Found.ar(f)
  Bool.and(P.op_is(ar, P.Found.i(f), P.OpsMSTACK{}),
  Bool.and(P.op_is(ar, P.Arena.src(ar, P.Found.i(f), 0), P.OpsRANGE{}),
           P.op_is(ar, P.Arena.src(ar, P.Found.i(f), 1), P.OpsCONST{})))

# ONE BUILD PER ROW. `g_mstack` returns a `P.Found` over an affine arena, so calling it
# twice to get `.ar` and `.i` would read TWO arenas and print a signature over one node
# taken out of the other. Binding once with `+` is the only correct spelling.
def MStack.sig(n: U32) -> String:
  +f = g_mstack(n)
  P.Rng.sig(P.Found.ar(f), P.Found.i(f))

def t_mstack_rows() -> IO(Unit):
  do IO<Unit>:
    P.srow("mstack2", MStack.sig(2))
    P.srow("mstack1", MStack.sig(1))
    P.srow("mstack0", MStack.sig(0))



# ===========================================================================
# THE AXIS CPYTHON LANE. This block is new: the file had 22 rows and NO cpython
# lane at all, and everything below is about `P.AxisType` -- the thing `78d482262`
# changed and the thing nothing could see change.
#
# Every row here has its expectation GENERATED BY CALLING CPython; see
# `.agents/slop/ops-oracle.py` and `.agents/slop/ops-gate.sh`. The rows come in two
# kinds and they are not interchangeable:
#
#   * CPYTHON rows -- printed by both lanes and diffed. `axv_*` is the headline:
#     one row per P.AxisType MEMBER, because a fixture-driven gate would only ask
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

def ax_names_str.go(xs: List<&2, P.AxisType>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case a <> t: List.append(&2, String, [P.AxisType.name(a)], ax_names_str.go(t))

def ax_names_str(xs: List<&2, P.AxisType>) -> String:
  String.join(ax_names_str.go(xs), ",")

# the eight members upstream keeps, as a list, in declaration order. Not `P.AxisType.all`
# -- that is the port's ten, and the two dead ones are the wall. This list IS the wall's
# content and it is here because `eqax_distinct` and `#shared_axis_*` need a member set
# to walk; the two dead constructors are visibly absent from it, which is the honest
# shape while six other files still build them.
def AxisType.live() -> List<&2, P.AxisType>:
  [P.AXIS_DEVICE{}, P.AXIS_GLOBAL{}, P.AXIS_LOCAL{}, P.AXIS_WARP{}, P.AXIS_WEAK{}, P.AXIS_LOOP{},
   P.AXIS_UPCAST{}, P.AXIS_PLACEHOLDER{}]

# `eqax_collide` -- how many pairs of DIFFERENT members `eq_axis` calls equal. `eq_axis`
# is `P.AxisType.value` equality, so two members sharing a number make it answer True for
# two different axis types, which merges two RANGE args in the ucache and is invisible
# everywhere else. CPython's answer is 0, and this walks the same pairs on the port's
# member list.
#
# THE COUNT IS NOT THE SUM, and that is a measurement: summing every equal pair gives
# 8 on the live set and 10 on the full one, because `P.eq_axis(a, a)` is True for all ten.
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
def EqAx.pairs(+a: P.AxisType, ys: List<&2, P.AxisType>) -> U32:
  match ys:
    case Nil{}: 0
    case b <> t: U32.add(Bool.pick(U32, P.eq_axis(a, b), 1, 0), EqAx.pairs(a, t))

def EqAx.disagree(xs: List<&2, P.AxisType>, +ys: List<&2, P.AxisType>) -> U32:
  match xs:
    case Nil{}: 0
    case a <> t: U32.add(EqAx.pairs(a, ys), EqAx.disagree(t, ys))

# `P.eq_axis(a, a)` for every member, counted. The off-diagonal row cannot see a
# value-keyed equality that answers FALSE on the diagonal, which is what a saturated or
# misnumbered U32 would do, so it is a separate count over the same set.
def EqAx.diag(xs: List<&2, P.AxisType>) -> U32:
  match xs:
    case Nil{}: 0
    case +a <> t: U32.add(Bool.pick(U32, P.eq_axis(a, a), 1, 0), EqAx.diag(t))

def EqAx.collide(+xs: List<&2, P.AxisType>) -> U32:
  U32.sub(EqAx.disagree(xs, xs), EqAx.diag(xs))

def t_eqax() -> Bool:
  Bool.and(Bool.and(U32.is_eq(EqAx.collide(AxisType.live()), 0),
                    U32.is_eq(EqAx.collide(P.AxisType.all()), 0)),
           Bool.and(U32.is_eq(EqAx.diag(AxisType.live()), 8),
                    U32.is_eq(EqAx.diag(P.AxisType.all()), 10)))

# ---------------------------------------------------------------------------
# The RANGE fixtures. FIVE of them and each earns its place:
#
#   weak1    `UOp.range(1, 0)`                 the DEFAULT axis type is WEAK
#   loop2    `UOp.range(2, (0, 1), LOOP)`      a NESTED axis id, which upstream's spec
#                                            matcher REJECTS -- kept so the pin's
#                                            `(ids, type)` packing stays representable
#   dev3     `UOp.range(3, 0, DEVICE)`         the literal `0` that replaced
#                                            `axis_to_pos[AxisType.DEVICE]`
#   loopfn   `P.UOp.loop(7)`                    src is NOOP not CONST
#   twoid    `UOp(Ops.RANGE, ..., (LOOP,0,1))` THE DISCRIMINATOR, built directly
#
# `twoid` is the one that earned its place by MEASUREMENT: for an arg of length TWO,
# `arg[1:]` and `arg[0:-1]` are the same slice, so `axis_id`/`axis_type` answer
# identically on the pin and on upstream for every `UOp.range` and every `P.UOp.loop`.
# The `axid_*`/`axt_*` rows for `weak1`/`loop2`/`dev3`/`loopfn` are byte-identical
# across the two trees; only a three-element arg separates them. Its `rng_` four
# facts DO match, because the flip is in the arg and not in the graph.
# ---------------------------------------------------------------------------
def g_rng_weak1() -> P.Found:
  +c = P.UOp.const(P.Arena.empty(), P.CInt{H.i64_of_i32(1)})
  P.UOp.range_end(P.Found.ar(c), P.Found.i(c), [0], P.AXIS_WEAK{})

def g_rng_loop1() -> P.Found:
  +c = P.UOp.const(P.Arena.empty(), P.CInt{H.i64_of_i32(2)})
  P.UOp.range_end(P.Found.ar(c), P.Found.i(c), [0], P.AXIS_LOOP{})

def g_rng_dev3() -> P.Found:
  +c = P.UOp.const(P.Arena.empty(), P.CInt{H.i64_of_i32(3)})
  P.UOp.range_end(P.Found.ar(c), P.Found.i(c), [0], P.AXIS_DEVICE{})

def g_rng_loopfn() -> P.Found:
  P.UOp.loop(P.Arena.empty(), 7)

def g_rng_twoid() -> P.Found:
  +c = P.UOp.const(P.Arena.empty(), P.CInt{H.i64_of_i32(2)})
  P.UOp.range_end(P.Found.ar(c), P.Found.i(c), [0, 1], P.AXIS_LOOP{})

# Two RANGE nodes, one arena, same end / ids / axis / tag. The only difference
# is the tail depth. `P.Found.i` is the intern index — identity, not the depth
# argument echoed back.
# ONE arena. The two indices are identity. Depth is a separate row: folding
# `P.Arena.depth(ib) == db` into this bool makes a collision print False (both
# indices are the first node) and the row no longer moves.
def Uc.same(+da: U32, +db: U32, +ids: List<&2, U32>) -> Bool:
  +c = P.UOp.const(P.Arena.empty(), P.CInt{H.i64_of_i32(4)})
  +a = P.UOp.range_shaped(P.Found.ar(c), P.Found.i(c), ids, P.AXIS_WEAK{}, da)
  +b = P.UOp.range_shaped(P.Found.ar(a), P.Found.i(c), ids, P.AXIS_WEAK{}, db)
  U32.is_eq(P.Found.i(a), P.Found.i(b))

def Uc.depth(+da: U32, +db: U32, +ids: List<&2, U32>) -> String:
  +c = P.UOp.const(P.Arena.empty(), P.CInt{H.i64_of_i32(4)})
  +a = P.UOp.range_shaped(P.Found.ar(c), P.Found.i(c), ids, P.AXIS_WEAK{}, da)
  +b = P.UOp.range_shaped(P.Found.ar(a), P.Found.i(c), ids, P.AXIS_WEAK{}, db)
  String.concat([U32.show(P.Arena.depth(P.Found.ar(b), P.Found.i(a))), ",",
                 U32.show(P.Arena.depth(P.Found.ar(b), P.Found.i(b)))])

# --- THE AXIS CPYTHON LANE. Row order matches `.agents/slop/ops-oracle.py` EXACTLY and
# --- the gate is a byte diff, so a row added on one side and not the other is a diff and
# --- not a silent gap.

# `List.reverse` of the member list, so `axlt_revsorted` can be a row. `sorted(reversed)`
# must come back as the declaration order, which is the one direction a `__lt__` that
# compares by NAME rather than by value gets right -- hence both rows.
def RevAxis.go(xs: List<&2, P.AxisType>, +acc: List<&2, P.AxisType>) -> List<&2, P.AxisType>:
  match xs:
    case Nil{}: acc
    case a <> t: RevAxis.go(t, List.append(&2, P.AxisType, [a], acc))

# `axv_<NAME>` etc -- one row per MEMBER, in `AxisType.live()` order. CPython prints the
# eight it has; the two the port retains for other files are BEND-ONLY and the gate script
# filters them by name with the `#bend_only_*` reason in the oracle.
def AxisVals.go(xs: List<&2, P.AxisType>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case a <> t: AxisVals.go(t, List.append(&2, String, [U32.show(P.AxisType.value(a))], acc))

def AxisVals.str(xs: List<&2, P.AxisType>) -> String:
  String.join(List.reverse(&2, String, AxisVals.go(xs, Nil{})), ",")

def t_ax_derivation() -> IO(Unit):
  do IO<Unit>:
    P.srow("#shared_axis_members", ax_names_str(AxisType.live()))
    P.srow("#shared_axis_values", AxisVals.str(AxisType.live()))
    P.srow("#shared_axis_count", U32.show(U32.from_nat(List.length(&2, P.AxisType, AxisType.live()))))
    P.srow("#shared_axis_sorted", ax_names_str(List.sort(P.AxisType, P.AxisType.lt, AxisType.live())))

def t_ax_tables(l: List<&2, P.AxisType>) -> IO(Unit):
  do IO<Unit>:
    P.srow("axv_" ++ P.AxisType.name(P.AXIS_DEVICE{}), U32.show(P.AxisType.value(P.AXIS_DEVICE{})))
    P.srow("axn_" ++ P.AxisType.name(P.AXIS_DEVICE{}), P.AxisType.name(P.AXIS_DEVICE{}))
    P.srow("axl_" ++ P.AxisType.name(P.AXIS_DEVICE{}), axis_letters(P.AXIS_DEVICE{}))
    P.srow("axc_" ++ P.AxisType.name(P.AXIS_DEVICE{}), P.axis_colors(P.AXIS_DEVICE{}))
    P.srow("axv_" ++ P.AxisType.name(P.AXIS_GLOBAL{}), U32.show(P.AxisType.value(P.AXIS_GLOBAL{})))
    P.srow("axn_" ++ P.AxisType.name(P.AXIS_GLOBAL{}), P.AxisType.name(P.AXIS_GLOBAL{}))
    P.srow("axl_" ++ P.AxisType.name(P.AXIS_GLOBAL{}), axis_letters(P.AXIS_GLOBAL{}))
    P.srow("axc_" ++ P.AxisType.name(P.AXIS_GLOBAL{}), P.axis_colors(P.AXIS_GLOBAL{}))
    P.srow("axv_" ++ P.AxisType.name(P.AXIS_LOCAL{}), U32.show(P.AxisType.value(P.AXIS_LOCAL{})))
    P.srow("axn_" ++ P.AxisType.name(P.AXIS_LOCAL{}), P.AxisType.name(P.AXIS_LOCAL{}))
    P.srow("axl_" ++ P.AxisType.name(P.AXIS_LOCAL{}), axis_letters(P.AXIS_LOCAL{}))
    P.srow("axc_" ++ P.AxisType.name(P.AXIS_LOCAL{}), P.axis_colors(P.AXIS_LOCAL{}))
    P.srow("axv_" ++ P.AxisType.name(P.AXIS_WARP{}), U32.show(P.AxisType.value(P.AXIS_WARP{})))
    P.srow("axn_" ++ P.AxisType.name(P.AXIS_WARP{}), P.AxisType.name(P.AXIS_WARP{}))
    P.srow("axl_" ++ P.AxisType.name(P.AXIS_WARP{}), axis_letters(P.AXIS_WARP{}))
    P.srow("axc_" ++ P.AxisType.name(P.AXIS_WARP{}), P.axis_colors(P.AXIS_WARP{}))
    P.srow("axv_" ++ P.AxisType.name(P.AXIS_WEAK{}), U32.show(P.AxisType.value(P.AXIS_WEAK{})))
    P.srow("axn_" ++ P.AxisType.name(P.AXIS_WEAK{}), P.AxisType.name(P.AXIS_WEAK{}))
    P.srow("axl_" ++ P.AxisType.name(P.AXIS_WEAK{}), axis_letters(P.AXIS_WEAK{}))
    P.srow("axc_" ++ P.AxisType.name(P.AXIS_WEAK{}), P.axis_colors(P.AXIS_WEAK{}))
    P.srow("axv_" ++ P.AxisType.name(P.AXIS_LOOP{}), U32.show(P.AxisType.value(P.AXIS_LOOP{})))
    P.srow("axn_" ++ P.AxisType.name(P.AXIS_LOOP{}), P.AxisType.name(P.AXIS_LOOP{}))
    P.srow("axl_" ++ P.AxisType.name(P.AXIS_LOOP{}), axis_letters(P.AXIS_LOOP{}))
    P.srow("axc_" ++ P.AxisType.name(P.AXIS_LOOP{}), P.axis_colors(P.AXIS_LOOP{}))
    P.srow("axv_" ++ P.AxisType.name(P.AXIS_UPCAST{}), U32.show(P.AxisType.value(P.AXIS_UPCAST{})))
    P.srow("axn_" ++ P.AxisType.name(P.AXIS_UPCAST{}), P.AxisType.name(P.AXIS_UPCAST{}))
    P.srow("axl_" ++ P.AxisType.name(P.AXIS_UPCAST{}), axis_letters(P.AXIS_UPCAST{}))
    P.srow("axc_" ++ P.AxisType.name(P.AXIS_UPCAST{}), P.axis_colors(P.AXIS_UPCAST{}))
    P.srow("axv_" ++ P.AxisType.name(P.AXIS_PLACEHOLDER{}), U32.show(P.AxisType.value(P.AXIS_PLACEHOLDER{})))
    P.srow("axn_" ++ P.AxisType.name(P.AXIS_PLACEHOLDER{}), P.AxisType.name(P.AXIS_PLACEHOLDER{}))
    P.srow("axl_" ++ P.AxisType.name(P.AXIS_PLACEHOLDER{}), axis_letters(P.AXIS_PLACEHOLDER{}))
    P.srow("axc_" ++ P.AxisType.name(P.AXIS_PLACEHOLDER{}), P.axis_colors(P.AXIS_PLACEHOLDER{}))
    # --- the two retained dead members. BEND-only: upstream has no such member, so
    # --- there is nothing to ask. They carry 9 and 10, slots upstream does not use, and
    # --- `t_eqax` is what proves the ten values are still distinct.
    P.srow("axv_REDUCE", U32.show(P.AxisType.value(P.AXIS_REDUCE{})))
    P.srow("axn_REDUCE", P.AxisType.name(P.AXIS_REDUCE{}))
    P.srow("axl_REDUCE", axis_letters(P.AXIS_REDUCE{}))
    P.srow("axc_REDUCE", P.axis_colors(P.AXIS_REDUCE{}))
    P.srow("axv_UNROLL", U32.show(P.AxisType.value(P.AXIS_UNROLL{})))
    P.srow("axn_UNROLL", P.AxisType.name(P.AXIS_UNROLL{}))
    P.srow("axl_UNROLL", axis_letters(P.AXIS_UNROLL{}))
    P.srow("axc_UNROLL", P.axis_colors(P.AXIS_UNROLL{}))

# `axs_<OP>` -- `range_start` as a row. Five ops CPython names, and `Ops.NOOP`, which it
# does not: the port's `case _` arm answers 0 where Python raises, and `Ops.LINEAR`'s
# answer is also 0, so without a MISS row a dropped `LINEAR` and a dropped `NOOP` arm
# would print the same string.
def t_ax_range_start() -> IO(Unit):
  do IO<Unit>:
    P.srow("axs_NOOP", range_start_str(P.OpsNOOP{}))
    P.srow("axs_CALL", range_start_str(P.OpsCALL{}))
    P.srow("axs_LINEAR", range_start_str(P.OpsLINEAR{}))
    P.srow("axs_END", range_start_str(P.OpsEND{}))
    P.srow("axs_STAGE", range_start_str(P.OpsSTAGE{}))
    P.srow("axs_REDUCE", range_start_str(P.OpsREDUCE{}))

# `rng_<tag>` (four facts) + `rngarg_<tag>` (the arg) + `axid_/axt_` (the PROPERTIES,
# read off the NODE through `P.UOp.axis_id` / `P.UOp.axis_type` and not off the fixture's
# literals -- see the note above `P.UOp.axis_id` for why that is the difference between a
# gated property and a dead claim).
#
# `rngarg_<tag>` spells the port's OWN `ARange` encoding, `(ids, at)`, which is the wall
# -- see the block above `P.UOp.range_end` -- so every `rngarg_*` row is BEND-ONLY.
def Rng.arg(arg: P.Arg) -> String:
  match arg:
    case P.ARange{ids, at}: String.concat(["(", IdsStr(ids), ",", P.AxisType.name(at), ")/len=2"])
    case _: "!NotARange"

def AxIds.of(m: Maybe<&2, List<&2, U32>>) -> String:
  match m:
    case Some{ids}: IdsStr.ids(ids)
    case None{}: "!NotARange"

def AxTypes.of(m: Maybe<&2, P.AxisType>) -> String:
  match m:
    case Some{at}: P.AxisType.name(at)
    case None{}: "!NotARange"

def t_rng_row(+nm: String, +ar: P.Arena, +self: U32) -> IO(Unit):
  do IO<Unit>:
    P.srow("rng_" ++ nm, P.Rng.sig(ar, self))
    P.srow("rngarg_" ++ nm, Rng.arg(P.Arena.arg(ar, self)))
    P.srow("axid_" ++ nm, AxIds.of(P.UOp.axis_id(P.Arena.arg(ar, self))))
    P.srow("axt_" ++ nm, AxTypes.of(P.UOp.axis_type(P.Arena.arg(ar, self))))

# ONE BUILD PER ROW, one def per fixture. `g_rng_*` returns a `P.Found` over an affine
# arena, so `main` cannot call it twice to get `.ar` and `.i`: the two calls build two
# arenas and the signature would be over one node read from the other.
def t_rng_weak1() -> IO(Unit):
  +f = g_rng_weak1()
  t_rng_row("weak1", P.Found.ar(f), P.Found.i(f))

def t_rng_loop1() -> IO(Unit):
  +f = g_rng_loop1()
  t_rng_row("loop1", P.Found.ar(f), P.Found.i(f))

def t_rng_dev3() -> IO(Unit):
  +f = g_rng_dev3()
  t_rng_row("dev3", P.Found.ar(f), P.Found.i(f))

def t_rng_loopfn() -> IO(Unit):
  +f = g_rng_loopfn()
  t_rng_row("loopfn", P.Found.ar(f), P.Found.i(f))

def t_rng_twoid() -> IO(Unit):
  +f = g_rng_twoid()
  t_rng_row("twoid", P.Found.ar(f), P.Found.i(f))

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
# and `P.toposort(enter_calls=True)` answers 6, 5, 6 and 4 for the same four. So
# the `call`, `nest` and `backedge` rows are the ones that carry
# `enter_calls=False`, and `bsl_chain` would agree with a `toposort`.
#
# the fixtures are the smallest graphs that separate the four answers, and each
# is named for the thing it separates rather than for its shape:
#   chain    no CALL anywhere, so the two walks agree -- the baseline.
#   call     a CALL AT THE ROOT, whose body is src[0] and so is dropped.
#   nest     the same CALL ONE LEVEL DOWN, so the pruning cannot be a special
#            case on the root.
#   backedge `src[0] is src[2]`, so the walk meets the same RANGE twice and it is
#            the CACHE that makes it terminate. `g_cycle` is NOT this fixture: it
#            reads `P.Found.i(r)` out of `P.Found.ar(sp)`, and `P.g_rng()` builds in a
#            different arena, so that index is past the end and `P.Arena.node`
#            answers the bottom for it. The wall is "an arena is the one a build
#            RETURNED, not the one that went in", and this fixture threads it.
# ---------------------------------------------------------------------------
def Bsl.facts(+xs: List<&2, U32>, ar: P.Arena) -> String:
  String.concat([Nat.show(List.length(&2, U32, xs)), " ", P.Rng.srcops.seeded(ar, xs)])

# `P.Arena.budget(ar)` IS the fuel and the header says why: one step per pushed
# frame, so it is exact for a DAG and is only ever reached on one by cutting.
# Hoisting it here keeps four rows from each re-deriving it.
def Bsl.row(+ar: P.Arena, +self: U32) -> String:
  Bsl.facts(P.UOp.backward_slice(P.Arena.budget(ar), ar, self), ar)

def Bsl.with_self(+ar: P.Arena, +self: U32) -> String:
  Bsl.facts(P.UOp.backward_slice_with_self(P.Arena.budget(ar), ar, self), ar)

def Bsl.op_in(+ar: P.Arena, +self: U32, want: List<&2, P.Op>) -> Bool:
  P.UOp.op_in_backward_slice_with_self(P.Arena.budget(ar), ar, self, want)

# CONST(0), CONST(1) <- RANGE(LOOP, 0) <- ADD <- ADD, which is CPython's
# `UOp.range(1, 0, AxisType.LOOP)`, an ADD of it with CONST(0) and an ADD of that
# with CONST(2). A range's end is a src of its own, which is why there are three
# CONSTs here and not two.
def g_bsl_chain() -> P.Found:
  +c0 = P.UOp.const(P.Arena.empty(), P.CInt{H.i64_of_i32(0)})
  +c1 = P.UOp.const(P.Found.ar(c0), P.CInt{H.i64_of_i32(1)})
  +c2 = P.UOp.const(P.Found.ar(c1), P.CInt{H.i64_of_i32(2)})
  +r0 = P.UOp.range_end(P.Found.ar(c2), P.Found.i(c1), [0], P.AXIS_LOOP{})
  +a0 = P.UOp.alu(P.Found.ar(r0), P.OpsADD{}, [P.Found.i(r0), P.Found.i(c0)])
  P.UOp.alu(P.Found.ar(a0), P.OpsADD{}, [P.Found.i(a0), P.Found.i(c2)])

# CALL(ADD(CONST(1), CONST(2)), CONST(9)). The BODY is src[0] and
# `src_without_body` is `src[1:]`, so the three body nodes are not in the slice.
def g_bsl_call() -> P.Found:
  +c1 = P.UOp.const(P.Arena.empty(), P.CInt{H.i64_of_i32(1)})
  +c2 = P.UOp.const(P.Found.ar(c1), P.CInt{H.i64_of_i32(2)})
  +c9 = P.UOp.const(P.Found.ar(c2), P.CInt{H.i64_of_i32(9)})
  +b = P.UOp.alu(P.Found.ar(c9), P.OpsADD{}, [P.Found.i(c1), P.Found.i(c2)])
  P.UOp.new(P.Found.ar(b), P.OpsCALL{}, [P.Found.i(b), P.Found.i(c9)], P.ACall{P.CallInfo.of()}, P.TNone{})

# ADD(CALL(..), CONST(2)) -- the same CALL, one level down.
def g_bsl_nest() -> P.Found:
  +c1 = P.UOp.const(P.Arena.empty(), P.CInt{H.i64_of_i32(1)})
  +c2 = P.UOp.const(P.Found.ar(c1), P.CInt{H.i64_of_i32(2)})
  +c9 = P.UOp.const(P.Found.ar(c2), P.CInt{H.i64_of_i32(9)})
  +b = P.UOp.alu(P.Found.ar(c9), P.OpsADD{}, [P.Found.i(c1), P.Found.i(c2)])
  +cl = P.UOp.new(P.Found.ar(b), P.OpsCALL{}, [P.Found.i(b), P.Found.i(c9)], P.ACall{P.CallInfo.of()}, P.TNone{})
  P.UOp.alu(P.Found.ar(cl), P.OpsADD{}, [P.Found.i(cl), P.Found.i(c2)])

# BACKEDGE(RANGE(DEVICE, 0), CONST(0), RANGE(DEVICE, 0)) -- ops.py:617's
# `self.backedge(loop, cond)` with `cond` the same node as `self`, so the walk
# meets the RANGE twice and the shared node must appear ONCE.
def g_bsl_backedge() -> P.Found:
  +c0 = P.UOp.const(P.Arena.empty(), P.CInt{H.i64_of_i32(0)})
  +c1 = P.UOp.const(P.Found.ar(c0), P.CInt{H.i64_of_i32(1)})
  +r = P.UOp.range_end(P.Found.ar(c1), P.Found.i(c1), [0], P.AXIS_DEVICE{})
  P.UOp.backedge(P.Found.ar(r), P.Found.i(r), P.Found.i(c0), P.Found.i(r))

# ONE PURE DEF PER ROW, named after the row, because a `do IO<Unit>` block can
# only bind an `IO` -- so the arena has to be built in a def BODY. That is the
# same reason `MStack.sig` and `Uc.depth` are the shape they are.
#
# `bsop_chain_add` is the SRC half and `bsop_chain_mul` is the miss; `bsop_call_call`
# is the SELF half, because CALL is in no src of that slice so only reading `self`
# answers True. `bsop_nest_pair` is the `*ops` list, which is `*args` in Python.
def Bsl.chain() -> String:
  +f = g_bsl_chain()
  Bsl.row(P.Found.ar(f), P.Found.i(f))

def Bsl.chain.ws() -> String:
  +f = g_bsl_chain()
  Bsl.with_self(P.Found.ar(f), P.Found.i(f))

def Bsl.chain.add() -> String:
  +f = g_bsl_chain()
  Bool.show(Bsl.op_in(P.Found.ar(f), P.Found.i(f), [P.OpsADD{}]))

def Bsl.chain.mul() -> String:
  +f = g_bsl_chain()
  Bool.show(Bsl.op_in(P.Found.ar(f), P.Found.i(f), [P.OpsMUL{}]))

def Bsl.call() -> String:
  +f = g_bsl_call()
  Bsl.row(P.Found.ar(f), P.Found.i(f))

def Bsl.call.ws() -> String:
  +f = g_bsl_call()
  Bsl.with_self(P.Found.ar(f), P.Found.i(f))

def Bsl.call.call() -> String:
  +f = g_bsl_call()
  Bool.show(Bsl.op_in(P.Found.ar(f), P.Found.i(f), [P.OpsCALL{}]))

def Bsl.nest() -> String:
  +f = g_bsl_nest()
  Bsl.row(P.Found.ar(f), P.Found.i(f))

def Bsl.nest.ws() -> String:
  +f = g_bsl_nest()
  Bsl.with_self(P.Found.ar(f), P.Found.i(f))

def Bsl.nest.pair() -> String:
  +f = g_bsl_nest()
  Bool.show(Bsl.op_in(P.Found.ar(f), P.Found.i(f), [P.OpsMUL{}, P.OpsCALL{}]))

# `bsop_backedge_backedge` is the SELF half again and `bsop_backedge_range` the
# SRC half on the fixture where the two nodes are not the same op, so neither
# answer can be produced by reading only one of them.
def Bsl.backedge() -> String:
  +f = g_bsl_backedge()
  Bsl.row(P.Found.ar(f), P.Found.i(f))

def Bsl.backedge.ws() -> String:
  +f = g_bsl_backedge()
  Bsl.with_self(P.Found.ar(f), P.Found.i(f))

def Bsl.backedge.be() -> String:
  +f = g_bsl_backedge()
  Bool.show(Bsl.op_in(P.Found.ar(f), P.Found.i(f), [P.OpsBACKEDGE{}]))

def Bsl.backedge.range() -> String:
  +f = g_bsl_backedge()
  Bool.show(Bsl.op_in(P.Found.ar(f), P.Found.i(f), [P.OpsRANGE{}]))

# ===========================================================================
# THE GATE for the ops.py:501-1928 block above. The CPython lane is
# `.agents/slop/ops-501-oracle.py` and the diff is `.agents/slop/ops-501-gate.sh`.
# Every row name starts `s5_` so the gate filters by PREFIX: a row that MOVED
# cannot be silently dropped, and filtering by position is what drops one.
#
# why the port's answer is an INDEX and CPython's is a name. `P.UOp.base` and its
# five siblings answer a `U32` arena index, and an index is meaningless outside
# the arena that produced it, so a numeric diff would compare two unrelated
# numberings. What is comparable is what the index POINTS AT, and that is the op
# name through `P.Ops.name` -- the same decision `codegen/__init__.bend`'s
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
# THE ARENA IS A LITERAL NODE LIST, and that is deliberate. `P.UOp.make` appends, so
# the k-th node built is index k; writing the list out means the index of a
# fixture is its POSITION and a reviewer can check the rows by counting, and
# `s5_idx_*` prints each one so a miscount is a visible row rather than a silent
# re-labelling. The nodes bypass `P.UOp.make` and therefore its interning, which is
# what a fixture wants -- every node here is already distinct, and a hash-consed
# fixture would silently MERGE two of them and move a row for the wrong reason.
# ===========================================================================

def s5.arena() -> P.Arena:
  P.Arena{[
    P.Arena.bottom(),
    P.Node{P.OpsCONST{}, Nil{}, P.APy{P.CInt{H.i64_of_i32(3)}}, P.TNone{}},
    P.Node{P.OpsBUFFER{}, Nil{}, P.AParam{P.s5.pa(1)}, P.TNone{}},
    P.Node{P.OpsPARAM{}, Nil{}, P.AParam{P.s5.pa(2)}, P.TNone{}},
    P.Node{P.OpsALLOC{}, Nil{}, P.AParam{P.s5.pa(3)}, P.TNone{}},
    P.Node{P.OpsRESHAPE{}, [2, 10], P.ATuple{[0]}, P.TNone{}},
    P.Node{P.OpsRESHAPE{}, [5], P.ATuple{Nil{}}, P.TNone{}},
    P.Node{P.OpsUNSHARD{}, [2, 11], P.ATuple{[0]}, P.TNone{}},
    P.Node{P.OpsBITCAST{}, [2], P.ADt{S.single()}, P.TNone{}},
    P.Node{P.OpsAFTER{}, [2], P.ANone{}, P.TNone{}},
    P.Node{P.OpsSTACK{}, [1, 1], P.APy{P.CInvalid{}}, P.TNone{}},
    P.Node{P.OpsRANGE{}, [1], P.ARange{[0], P.AXIS_DEVICE{}}, P.TNone{}},
    P.Node{P.OpsSINK{}, [12], P.AKernel{P.KernelInfo.of()}, P.TNone{}},
    P.Node{P.OpsLINEAR{}, [2], P.ANone{}, P.TNone{}},
    P.Node{P.OpsADD{}, [1, 1], P.ANone{}, P.TNone{}},
    P.Node{P.OpsADD{}, [14, 16], P.ANone{}, P.TNone{}},
    P.Node{P.OpsMUL{}, [1, 14], P.ANone{}, P.TNone{}},
    P.Node{P.OpsADD{}, [16, 1], P.ANone{}, P.TNone{}},
    P.Node{P.OpsDETACH{}, [2], P.ANone{}, P.TNone{}}
  ], [0]}

# The nine fixture indices, as a `Data` record so the row table reads them by name
# and a fixture cannot be swapped for another without the row changing.

def s5.ids() -> P.S5: P.S5{1, 2, 3, 4, 5, 6, 7, 8, 9}

# The nine `P.S5` field readers. Bend has no `x.field` sugar (bend2-constraints
# rule 26) and no auto-generated projection, so each is one `match`, and R-3 wants
# them above their first caller -- which is `s5.base`.
def S5.c(f: P.S5) -> U32:
  match f:
    case P.S5{c, b, p, a, r1, r2, us, bc, af}: c

def S5.b(f: P.S5) -> U32:
  match f:
    case P.S5{c, b, p, a, r1, r2, us, bc, af}: b

def S5.p(f: P.S5) -> U32:
  match f:
    case P.S5{c, b, p, a, r1, r2, us, bc, af}: p

def S5.a(f: P.S5) -> U32:
  match f:
    case P.S5{c, b, p, a, r1, r2, us, bc, af}: a

def S5.r1(f: P.S5) -> U32:
  match f:
    case P.S5{c, b, p, a, r1, r2, us, bc, af}: r1

def S5.r2(f: P.S5) -> U32:
  match f:
    case P.S5{c, b, p, a, r1, r2, us, bc, af}: r2

def S5.us(f: P.S5) -> U32:
  match f:
    case P.S5{c, b, p, a, r1, r2, us, bc, af}: us

def S5.bc(f: P.S5) -> U32:
  match f:
    case P.S5{c, b, p, a, r1, r2, us, bc, af}: bc

def S5.af(f: P.S5) -> U32:
  match f:
    case P.S5{c, b, p, a, r1, r2, us, bc, af}: af

# `P.Shard{ax, rng}` is a `Data` record so it is destructured; the pair is printed
# as `axis:RANGE` and a fixture whose src[1] is not a RANGE would print its own
# op name, which is the point.
# One pair per line of the list, `axis:RANGE`, and the arena is the FIXTURE's so
# the name is the RANGE's and not the bottom's.
def s5.one(ar: P.Arena, ax: U32, rng: U32) -> String:
  String.concat([U32.show(ax), ":", P.s5.name(ar, rng)])

def s5.shardstr.go(+ar: P.Arena, xs: List<&2, P.Shard>, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case P.Shard{ax, rng} <> t:
      s5.shardstr.go(ar, t, String.concat([acc, " ", s5.one(ar, ax, rng)]))

def s5.shardstr(+ar: P.Arena, xs: List<&2, P.Shard>) -> String:
  match xs:
    case Nil{}: ""
    case P.Shard{ax, rng} <> t: s5.shardstr.go(ar, t, s5.one(ar, ax, rng))

# THE ROWS. One `String` row per answer, and every walk takes `P.Arena.budget(ar)` as
# its fuel -- the only sound one, for the reason the header gives: one step per
# peel and one per worklist entry, and both are bounded by the arena.
def s5.walk(+fuel: Nat, +ar: P.Arena, self: U32) -> String:
  String.concat([P.s5.name(ar, P.UOp.base(fuel, ar, self))])

def s5.walk.u(+fuel: Nat, +ar: P.Arena, self: U32) -> String:
  String.concat([P.s5.name(ar, P.UOp.unsharded_base(fuel, ar, self))])

def s5.walk.s(+fuel: Nat, +ar: P.Arena, self: U32) -> String:
  String.concat([P.s5.name(ar, P.UOp.storage_base(fuel, ar, self))])

def s5.walk.w(+fuel: Nat, +ar: P.Arena, self: U32) -> String:
  String.concat([P.s5.name(ar, P.UOp.without_after(fuel, ar, self))])

def s5.walk.b(+fuel: Nat, +ar: P.Arena, self: U32) -> String:
  String.concat([P.s5.name(ar, P.UOp.buf_uop(fuel, ar, self))])

# The nine base-family rows, one call site each, so a def nothing calls has no row
# and cannot hide. `s5.walk*` are six one-liners rather than one parameterised
# def because Bend has no function values: a function in a datatype field forces
# `Type`, and a `Type` cannot be passed an arena.
def s5.base(+fuel: Nat, +ar: P.Arena, +f: P.S5) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- P.srow("s5_base_c", s5.walk(fuel, ar, P.S5.c(f)))
    b : Unit <- P.srow("s5_base_b", s5.walk(fuel, ar, P.S5.b(f)))
    c : Unit <- P.srow("s5_base_p", s5.walk(fuel, ar, P.S5.p(f)))
    d : Unit <- P.srow("s5_base_a", s5.walk(fuel, ar, P.S5.a(f)))
    e : Unit <- P.srow("s5_base_r1", s5.walk(fuel, ar, P.S5.r1(f)))
    g : Unit <- P.srow("s5_base_r2", s5.walk(fuel, ar, P.S5.r2(f)))
    h : Unit <- P.srow("s5_base_us", s5.walk(fuel, ar, P.S5.us(f)))
    i : Unit <- P.srow("s5_base_bc", s5.walk(fuel, ar, P.S5.bc(f)))
    j : Unit <- P.srow("s5_base_af", s5.walk(fuel, ar, P.S5.af(f)))
    P.srow("s5_base_detach", s5.walk(fuel, ar, 18))

def s5.unsharded(+fuel: Nat, +ar: P.Arena, +f: P.S5) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- P.srow("s5_unsharded_base_c", s5.walk.u(fuel, ar, P.S5.c(f)))
    b : Unit <- P.srow("s5_unsharded_base_b", s5.walk.u(fuel, ar, P.S5.b(f)))
    c : Unit <- P.srow("s5_unsharded_base_p", s5.walk.u(fuel, ar, P.S5.p(f)))
    d : Unit <- P.srow("s5_unsharded_base_a", s5.walk.u(fuel, ar, P.S5.a(f)))
    e : Unit <- P.srow("s5_unsharded_base_r1", s5.walk.u(fuel, ar, P.S5.r1(f)))
    g : Unit <- P.srow("s5_unsharded_base_r2", s5.walk.u(fuel, ar, P.S5.r2(f)))
    h : Unit <- P.srow("s5_unsharded_base_us", s5.walk.u(fuel, ar, P.S5.us(f)))
    i : Unit <- P.srow("s5_unsharded_base_bc", s5.walk.u(fuel, ar, P.S5.bc(f)))
    j : Unit <- P.srow("s5_unsharded_base_af", s5.walk.u(fuel, ar, P.S5.af(f)))
    P.srow("s5_unsharded_base_detach", s5.walk.u(fuel, ar, 18))

def s5.storage(+fuel: Nat, +ar: P.Arena, +f: P.S5) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- P.srow("s5_storage_base_c", s5.walk.s(fuel, ar, P.S5.c(f)))
    b : Unit <- P.srow("s5_storage_base_b", s5.walk.s(fuel, ar, P.S5.b(f)))
    c : Unit <- P.srow("s5_storage_base_p", s5.walk.s(fuel, ar, P.S5.p(f)))
    d : Unit <- P.srow("s5_storage_base_a", s5.walk.s(fuel, ar, P.S5.a(f)))
    e : Unit <- P.srow("s5_storage_base_r1", s5.walk.s(fuel, ar, P.S5.r1(f)))
    g : Unit <- P.srow("s5_storage_base_r2", s5.walk.s(fuel, ar, P.S5.r2(f)))
    h : Unit <- P.srow("s5_storage_base_us", s5.walk.s(fuel, ar, P.S5.us(f)))
    i : Unit <- P.srow("s5_storage_base_bc", s5.walk.s(fuel, ar, P.S5.bc(f)))
    j : Unit <- P.srow("s5_storage_base_af", s5.walk.s(fuel, ar, P.S5.af(f)))
    P.srow("s5_storage_base_detach", s5.walk.s(fuel, ar, 18))

def s5.woafter(+fuel: Nat, +ar: P.Arena, +f: P.S5) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- P.srow("s5_wo_after_c", s5.walk.w(fuel, ar, P.S5.c(f)))
    b : Unit <- P.srow("s5_wo_after_b", s5.walk.w(fuel, ar, P.S5.b(f)))
    e : Unit <- P.srow("s5_wo_after_r1", s5.walk.w(fuel, ar, P.S5.r1(f)))
    h : Unit <- P.srow("s5_wo_after_us", s5.walk.w(fuel, ar, P.S5.us(f)))
    i : Unit <- P.srow("s5_wo_after_af", s5.walk.w(fuel, ar, P.S5.af(f)))
    P.srow("s5_wo_after_detach", s5.walk.w(fuel, ar, 18))

def s5.bufuop(+fuel: Nat, +ar: P.Arena, +f: P.S5) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- P.srow("s5_buf_uop_c", s5.walk.b(fuel, ar, P.S5.c(f)))
    b : Unit <- P.srow("s5_buf_uop_b", s5.walk.b(fuel, ar, P.S5.b(f)))
    c : Unit <- P.srow("s5_buf_uop_p", s5.walk.b(fuel, ar, P.S5.p(f)))
    e : Unit <- P.srow("s5_buf_uop_r1", s5.walk.b(fuel, ar, P.S5.r1(f)))
    g : Unit <- P.srow("s5_buf_uop_r2", s5.walk.b(fuel, ar, P.S5.r2(f)))
    i : Unit <- P.srow("s5_buf_uop_bc", s5.walk.b(fuel, ar, P.S5.bc(f)))
    j : Unit <- P.srow("s5_buf_uop_af", s5.walk.b(fuel, ar, P.S5.af(f)))
    P.srow("s5_buf_uop_detach", s5.walk.b(fuel, ar, 18))

# `has_buffer_identity` answers a `Bool`, and BOTH values of `after_ok` are rows:
# the two differ on exactly one fixture, so a port that dropped the parameter would
# agree on the other eight and be wrong on the ninth.
def s5.hbi.t(+fuel: Nat, after_ok: Bool, +ar: P.Arena, f: P.S5) -> String:
  U32.show(Bool.to_u32(P.UOp.has_buffer_identity(fuel, after_ok, ar, P.S5.c(f))))

def s5.hbi(+fuel: Nat, +ar: P.Arena, +f: P.S5) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("s5_hbi_c", P.UOp.has_buffer_identity(fuel, False{}, ar, P.S5.c(f)))
    b : Unit <- row("s5_hbi_b", P.UOp.has_buffer_identity(fuel, False{}, ar, P.S5.b(f)))
    c : Unit <- row("s5_hbi_p", P.UOp.has_buffer_identity(fuel, False{}, ar, P.S5.p(f)))
    d : Unit <- row("s5_hbi_a", P.UOp.has_buffer_identity(fuel, False{}, ar, P.S5.a(f)))
    e : Unit <- row("s5_hbi_r1", P.UOp.has_buffer_identity(fuel, False{}, ar, P.S5.r1(f)))
    g : Unit <- row("s5_hbi_r2", P.UOp.has_buffer_identity(fuel, False{}, ar, P.S5.r2(f)))
    h : Unit <- row("s5_hbi_us", P.UOp.has_buffer_identity(fuel, False{}, ar, P.S5.us(f)))
    i : Unit <- row("s5_hbi_bc", P.UOp.has_buffer_identity(fuel, False{}, ar, P.S5.bc(f)))
    j : Unit <- row("s5_hbi_af", P.UOp.has_buffer_identity(fuel, False{}, ar, P.S5.af(f)))
    w : Unit <- row("s5_hbi_detach", P.UOp.has_buffer_identity(fuel, False{}, ar, 18))
    k : Unit <- row("s5_hbi_after_c", P.UOp.has_buffer_identity(fuel, True{}, ar, P.S5.c(f)))
    l : Unit <- row("s5_hbi_after_b", P.UOp.has_buffer_identity(fuel, True{}, ar, P.S5.b(f)))
    m : Unit <- row("s5_hbi_after_p", P.UOp.has_buffer_identity(fuel, True{}, ar, P.S5.p(f)))
    n : Unit <- row("s5_hbi_after_a", P.UOp.has_buffer_identity(fuel, True{}, ar, P.S5.a(f)))
    o : Unit <- row("s5_hbi_after_r1", P.UOp.has_buffer_identity(fuel, True{}, ar, P.S5.r1(f)))
    q : Unit <- row("s5_hbi_after_r2", P.UOp.has_buffer_identity(fuel, True{}, ar, P.S5.r2(f)))
    r : Unit <- row("s5_hbi_after_us", P.UOp.has_buffer_identity(fuel, True{}, ar, P.S5.us(f)))
    t : Unit <- row("s5_hbi_after_bc", P.UOp.has_buffer_identity(fuel, True{}, ar, P.S5.bc(f)))
    u : Unit <- row("s5_hbi_after_af", P.UOp.has_buffer_identity(fuel, True{}, ar, P.S5.af(f)))
    row("s5_hbi_after_detach", P.UOp.has_buffer_identity(fuel, True{}, ar, 18))

# `split_uop` -- the sequence, and the ORDER is the fact. Five fixtures and the
# middle one is the one that matters: `nest` is ADD[MUL[CONST,ADD[...]],CONST],
# so a fold that pushed at the BACK answers `CONST,ADD,CONST,MUL` and one that
# pushed at the FRONT answers `MUL,CONST,CONST`, and both have length 3.
def s5.split(+fuel: Nat, +ar: P.Arena, i: U32, sep: P.Op) -> String:
  P.s5.seps(ar, P.UOp.split_uop(fuel, ar, i, sep))

def s5.splitrows(+fuel: Nat, +ar: P.Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- P.srow("s5_split_const", s5.split(fuel, ar, 1, P.OpsADD{}))
    b : Unit <- P.srow("s5_split_add", s5.split(fuel, ar, 14, P.OpsADD{}))
    c : Unit <- P.srow("s5_split_nest", s5.split(fuel, ar, 15, P.OpsADD{}))
    d : Unit <- P.srow("s5_split_diamond", s5.split(fuel, ar, 16, P.OpsMUL{}))
    e : Unit <- P.srow("s5_split_mismatch", s5.split(fuel, ar, 17, P.OpsMUL{}))
    P.srow("s5_split_left", s5.split(fuel, ar, 16, P.OpsADD{}))

# `sint_to_uop` answers a `P.Found` because the `SI` arm MINTS, so the row prints the
# op name of the node it made -- CONST for the literal arm, and the `SU` arm prints
# the name of the node that already existed, which is what makes `s5_sint_uop`
# different from `s5_sint_const`. Split in three because `f` is read twice and a
# `do IO<Unit>` block can only bind an `IO`.
def s5.sint.go(ar: P.Arena, i: U32) -> String: P.s5.name(ar, i)

def s5.sint.of(+f: P.Found) -> String: s5.sint.go(P.Found.ar(f), P.Found.i(f))

def s5.sint(ar: P.Arena, s: P.Sint) -> String: s5.sint.of(P.UOp.sint_to_uop(ar, s))


def s5.cint(+v: P.Const) -> Maybe<&2, H.I64>:
  match v:
    case P.CInt{i}: Some{i}
    case _: None{}

def s5.cend.of(+arg: P.Arg) -> Maybe<&2, H.I64>:
  match arg:
    case P.APy{v}: s5.cint(v)
    case _: None{}

def s5.maybe_i64(m: Maybe<&2, H.I64>) -> String:
  match m:
    case Some{i}: H.i64_text(i)
    case None{}: "-"

def s5.dr.of(+ar: P.Arena, xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}: "-"
    case +h <> _:
      String.concat([P.s5.name(ar, h), ":", s5.maybe_i64(s5.cend.of(P.Arena.arg(ar, P.Arena.src(ar, h, 0))))])

def s5.dr(d: P.DRng) -> String:
  match d:
    case P.DRng{ar, ys}: s5.dr.of(ar, ys)

def s5.ga.of(+f: P.Found) -> String: P.s5.minted.go(P.Found.ar(f), f)

def s5.minted.row(nm: String, +f: P.Found) -> IO(Unit):
  P.srow(nm, P.s5.minted.go(P.Found.ar(f), f))

# `gate_kernel_sink` and `sint_to_uop` are the two module-level defs, and
# `s5_gate_*` is one row per ARM: a port that collapsed the two negative tests
# would answer 1 on one of the first two and the third row would not see it.
def s5.gate(+ar: P.Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("s5_gate_linear", gate_kernel_sink(ar, 13))
    b : Unit <- row("s5_gate_kernel", gate_kernel_sink(ar, 12))
    row("s5_gate_plain", gate_kernel_sink(ar, 2))

# The index row. Every fixture's index is its POSITION in the literal node list
# above, and this prints them, so a miscount is a visible row rather than a silent
# re-labelling of the fixtures. The arithmetic being easy is exactly why it needs
# a row.
def s5.idx(+ar: P.Arena, +f: P.S5) -> IO(Unit):
  P.srow("s5_idx", String.concat([P.Ops.name(P.Arena.op(ar, P.S5.c(f))), ",",
    P.Ops.name(P.Arena.op(ar, P.S5.b(f))), ",", P.Ops.name(P.Arena.op(ar, P.S5.p(f))), ",",
    P.Ops.name(P.Arena.op(ar, P.S5.a(f))), ",", P.Ops.name(P.Arena.op(ar, P.S5.r1(f))), ",",
    P.Ops.name(P.Arena.op(ar, P.S5.r2(f))), ",", P.Ops.name(P.Arena.op(ar, P.S5.us(f))), ",",
    P.Ops.name(P.Arena.op(ar, P.S5.bc(f))), ",", P.Ops.name(P.Arena.op(ar, P.S5.af(f)))]))



# `ufix` -- ops.py:606. `if isinstance(x, UOp): return x; return P.UOp.const(x)`.
# The guard is the union and the two arms are the whole of it. MEASURED, because
# `P.UOp.const` reaches a UOp through `isinstance(b, UOp): return b.cast(dtype)` and
# a cast MIGHT have been a mint: `P.UOp.const(0).ufix(P.UOp.const(0)) is P.UOp.const(0)`
# and `UOp(Ops.BUFFER, arg=P.ParamArg(1, dtypes.int32)).ufix(...)` is itself too, so
# the `CU` arm returns the node and MINTS NOTHING.
#
# THE SIBLING IS NOT THE SAME DEF, and the measurement is why. `sint_to_uop(x,
# dtypes.weakint)` is `P.UOp.const(x, weakint)`, which for a UOp is `x.cast(weakint)`
# -- and for a BUFFER that is a REAL CAST, not a fold. So `P.UOp.sint_to_uop`'s `SU`
# arm below DIVERGES for any node whose dtype is not weak; see the TODO on it.
def clike.uop_of(x: P.CLike) -> Maybe<&2, U32>:
  match x:
    case P.CU{u}: Some{u}
    case P.CV{v}: None{}
def clike.val(x: P.CLike) -> P.Const:
  match x:
    case P.CU{u}: P.CInt{H.i64_of_i32(u)}
    case P.CV{v}: v
def UOp.ufix.of(ar: P.Arena, hit: Maybe<&2, U32>, v: P.Const) -> P.Found:
  match hit:
    case Some{u}: P.Found{ar, u}
    case None{}: P.UOp.const(ar, v)
def UOp.ufix.of2(ar: P.Arena, +x: P.CLike) -> P.Found:
  UOp.ufix.of(ar, clike.uop_of(x), clike.val(x))

# R-3: the two readers are above `UOp.ufix.of2`, and `Maybe` is read ONCE per arm
# so it is the payload that cannot be `+`'d, not the union.
def UOp.ufix(ar: P.Arena, x: P.CLike) -> P.Found: UOp.ufix.of2(ar, x)

# `body` -- ops.py:562. `if self.op is not Ops.CALL: raise; return self.src[0]`.
# The `raise` is the `Maybe`, which is this file's standing spelling for it (see
# `P.UOp.axis_id` above), and `src[0]` is `P.Arena.src0`. The op is a PARAMETER because
# a `match` may not scrutinise `P.Arena.op(ar, self)`.
def UOp.body.of(op: P.Op, src0: U32) -> Maybe<&2, U32>:
  match op:
    case P.OpsCALL{}: Some{src0}
    case _: None{}

def UOp.body(+ar: P.Arena, +self: U32) -> Maybe<&2, U32>:
  UOp.body.of(P.Arena.op(ar, self), P.Arena.src0(ar, self))

# `is_inline_call` -- ops.py:567. `self.op is Ops.CALL and self.body.op is
# Ops.SINK and self.body.arg is None and not self.arg.precompile`. FOUR conjuncts
# and a `Maybe` answer, and the `Maybe` is not decoration: `self.arg` is a
# `P.CallInfo` in the pin's `P.Arg` and a `P.CustomFunction` upstream, and CPython raises
# AttributeError on the second, so `None` is that raise. It is the same spelling
# `UOp.body`'s `None` is for its RuntimeError, and the two Nones mean different
# things on purpose.
#
# The first two conjuncts are combined into ONE `Bool` parameter and the last two
# are separate `match` arms, which looks arbitrary and is not: the first two are
# OP tests and the last two are ARG tests, and an `P.Arg` can only be matched where
# it is a binder. The four are separated by FIXTURE rather than by def, which is
# the honest arrangement -- a CALL with a non-SINK body, a non-CALL, a SINK body
# with a `P.KernelInfo` arg and a `precompile=True` arg are four rows and each one
# moves if its own conjunct is dropped.
def UOp.is_inline_call.pre(arg: P.Arg) -> Maybe<&2, Bool>:
  match arg:
    case P.ACall{ci}: Some{Bool.not(P.CallInfo.precompile(ci))}
    case _: None{}

def UOp.is_inline_call.anon(barg: P.Arg, +arg: P.Arg) -> Maybe<&2, Bool>:
  match barg:
    case P.ANone{}: UOp.is_inline_call.pre(arg)
    case _: Some{False{}}

def UOp.is_inline_call.of(heads: Bool, barg: P.Arg, +arg: P.Arg) -> Maybe<&2, Bool>:
  match heads:
    case True{}: UOp.is_inline_call.anon(barg, arg)
    case False{}: Some{False{}}

def UOp.is_inline_call(+ar: P.Arena, +self: U32) -> Maybe<&2, Bool>:
  +b = P.Arena.src0(ar, self)
  UOp.is_inline_call.of(
    Bool.and(P.eq_op(P.Arena.op(ar, self), P.OpsCALL{}), P.eq_op(P.Arena.op(ar, b), P.OpsSINK{})),
    P.Arena.arg(ar, b), P.Arena.arg(ar, self))

# ===========================================================================
# the counter -- `collections.Counter` over node lists, as a list of pairs.
#
# ops.py:1073-1079 -- `P.UOp.gcd` and `P.UOp.divide_exact`.
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
# ---------------------------------------------------------------------------
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
#    tail may not be passed to two calls. and the port's own `P.Merge.go` is the pattern
#    -- `ops.bend:2845`: `P.Merge.go(t, P.Found.ar(f), List.append(&2, U32, map, [P.Found.i(f)]))`
#    -- the tail is the recursion's first argument and the accumulator is the third.
#
# ---------------------------------------------------------------------------
# THE ALGORITHM, AND IT IS UPSTREAM's.
#
# `collections.Counter` OVER NODE LISTS: `Counter(term.split_uop(Ops.MUL))` COUNTS THE
# MUL-factors of a term, and `functools.reduce(operator.and_, ...)` intersects the counters,
# and `operator.and_` on two counters is "the keys in both, with the minimum count".
#
# so the counter is a list of `(KEY, COUNT)` pairs, the intersection is the keys of the first
# counter with the minimum count across all of them, and the product is a FOLD over the pairs
# WITH `count` COPIES OF THE KEY.

# the bump: `count[k] += 1`, and a key that is not there is created with a count of 1.
#
# and the FOLD carries a "found" flag, because the `Nil{}` arm must append the new key
# only when the key was not found. measured 2026-11-08 with a probe that prints the
# counter: the first spellings read `1=1 2=2 3=1 2=1` for `P.ctr_of([1,2,3,2])` -- the key `2`
# twice -- and `1=2 1=1` for `bump([1],1)`, because the `Nil{}` arm appended `P.Ctr{k,1}`
# and the matched arm appended the bumped one. and `ctr_find` reads the first match,
# so it read 1 for every key, and `t_ctr_bump` and `t_ctr_find` read `False`.
def ctr_set.pick(+same: Bool, hit: List<&2, P.Ctr>, miss: List<&2, P.Ctr>) -> List<&2, P.Ctr>:
  match same:
    case True{}: hit
    case False{}: miss

def ctr_set.hit(+c: P.Ctr, +k: U32, +n: U32, +acc: List<&2, P.Ctr>) -> List<&2, P.Ctr>:
  match c:
    case P.Ctr{k2, n2}: ctr_set.pick(U32.is_eq(k2, k),
                                   List.append(&2, P.Ctr, acc, [P.Ctr{k, n}]),
                                   List.append(&2, P.Ctr, acc, [c]))

def ctr_set.go(+l: List<&2, P.Ctr>, +k: U32, +n: U32, +acc: List<&2, P.Ctr>) -> List<&2, P.Ctr>:
  match l:
    case Nil{}: Nil{}
    case c <> t: ctr_set.go(t, k, n, ctr_set.hit(c, k, n, acc))

def ctr_set(+l: List<&2, P.Ctr>, +k: U32, +n: U32, +acc: List<&2, P.Ctr>) -> List<&2, P.Ctr>:
  ctr_set.go(l, k, n, Nil{})

# ===========================================================================
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
# ===========================================================================

# `P.UOp.divides` -- ops.py:1069, "self / v as the same shape, or None when it is not exact".
#
# the stack arm is not ported and the reason is measured: it is a FOLD over the srcs, so a def
# that answers one node and a def that answers a list would call each other, and Bend has no
# forward declarations to express that (the same wall `const_factor`'s TODO recorded -- which the
# FLATTENING got past there is unavailable here, because this arm REBUILDS a STACK rather than
# collecting a gcd). A STACK operand therefore DECLINES here where CPython rebuilds it. That is a
# gap, named, and the arms that ARE written are a tree recursion with no list.
#
# the answer is a record and not a `Maybe<P.Found>`: the ADD and MUL arms need two chained
# self-calls and then a decision on both, and a `match` may not scrutinise a local binder -- so
# `ok` travels in a `P.Dv` and the decision happens in a def whose PARAMETER it is.

# THE IDENTITY ELEMENT OF A MULTIPLICATION IS 1 -- `ops.py:81`'s
# `{Ops.ADD:0, Ops.MUL:1, Ops.MAX:dt.min}[op]` -- and only the multiplication is needed
# here, because `pop_const` is spelled with `Ops.MUL` in both places upstream uses it.
def UOp.pop_const_identity.ismul(+op: P.Op) -> Bool:
  P.eq_op(op, P.OpsMUL{})

def UOp.pop_const_identity.pick(ismul: Bool) -> H.I64:
  match ismul:
    case True{}: H.i64_of_i32(1)
    case False{}: H.i64_of_i32(0)

def UOp.pop_const_identity(+op: P.Op) -> H.I64:
  UOp.pop_const_identity.pick(UOp.pop_const_identity.ismul(op))

# and the factors are the constants that were popped -- `u.pop_const(Ops.MUL)`'s second
# half -- and the port takes them from the port's own `pop_const_val`.
def UOp.gcd.factors.val(+c: P.Const) -> H.I64:
  match c:
    case P.CInt{i}: i
    case _: H.i64_of_i32(1)

# AND THE `count` IS EMPTY OR NOT -- `if not count: factors = tuple(u.const_factor() for u
# in uops)` -- AND THE CONSTANT FACTOR OF A NODE IS THE PORT's OWN `P.UOp.const_factor`.
def UOp.gcd.factors.three(+ar: P.Arena, +h: U32, +acc: List<&2, H.I64>, +c: P.Const) -> List<&2, H.I64>:
  List.append(&2, H.I64, acc, [UOp.gcd.factors.val(c)])

def UOp.gcd.factors.two(+ar: P.Arena, +h: U32, acc: List<&2, H.I64>, m: Maybe<&1, P.Const>) -> List<&2, H.I64>:
  match m:
    case Some{c}: UOp.gcd.factors.three(ar, h, acc, c)
    case None{}: UOp.gcd.factors.three(ar, h, acc, P.CInt{H.i64_of_i32(1)})

# and the CONST's value: an INT CONST is its value and anything ELSE is the identity.
def UOp.gcd.factors.one(+ar: P.Arena, +h: U32, +acc: List<&2, H.I64>) -> List<&2, H.I64>:
  UOp.gcd.factors.two(ar, h, acc, P.UOp.pop_const_val(ar, h, P.OpsMUL{}))

def UOp.gcd.factors.go(+ar: P.Arena, +uops: List<&2, U32>, +acc: List<&2, H.I64>) -> List<&2, H.I64>:
  match uops:
    case Nil{}: acc
    case h <> t: UOp.gcd.factors.go(ar, t, UOp.gcd.factors.one(ar, h, acc))

# ===========================================================================
# the counter's own tests, and they are CPYTHON-confirmed against CPYTHON's own
# `P.UOp.gcd` -- so the port's answer and python's are two independent computations of the
# SAME PROPERTY.
#
# and the claims are not change-detectors:
#   t_gcd_const   THE GCD OF TWO UNRELATED VARIABLES IS 1 -- A CONST. Catches a port that
#                  returns the wrong node shape.
#   t_gcd_shared  the gcd of `x*z` and `x*z` is the shared factor `x` times the gcd of
#                  the constants -- and the CONST is stripped by `pop_const`, which is
#                  what makes the counter `{x:1}` and not `{x:1, 3:1}`.
# ===========================================================================



# ===========================================================================
# `P.UOp.divide_exact` -- ops.py:1038-1047.
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
#   * `self.divides(v.val)` IS THE PORT's OWN `P.UOp.divides` (`ops.bend:8569`), WHICH ANSWERS A
#     `P.Dv{ok, f, i}` -- the `ok` is the "it divides" flag and `f`/`i` are the quotient's node
#     AND ITS INDEX.
#   * `new_count.subtract(...)` and `all(v>=0 ...)` are one comparison of two unsigned
#     counters instead of a subtraction and a sign test -- and they are the same property:
#     upstream's difference is non-negative iff every key of the divisor's counter is present
#     in the numerator's counter at least as many times. and that is what makes the
#     port's `U32` count enough: a signed counter would be new arithmetic for a comparison that
#     TWO UNSIGNED COUNTERS ALREADY ANSWER.
#   * `math.prod(new_count.elements())` IS THE PORT's OWN `H.make_tuple_rep` CONCATENATION,
#     THE SAME SHAPE AS `P.UOp.gcd`'s PRODUCT.
#
# and the answer is a `Maybe<&1, U32>` -- and `None{}` is upstream's `None`, which is the
# "WE AREN'T SURE" ANSWER AND NOT AN ERROR.
# ===========================================================================

# the FOLD's state: the product so far and the "all counts non-negative" flag so far
# -- and a record is positional -- measured 2026-11-08 -- so it is built in one place and
# READ IN ONE PLACE.

# ===========================================================================
# THE FOUR ARMS OF `divide_exact`, IN UPSTREAM's ORDER.
#
# and every comparison is a parameter and not a computed value -- measured 2026-11-08:
# "a match cannot scrutinize a computed value: give it its own def" -- AND A `match` OVER A
# call is also a computed value, so the op is read into a parameter first.
#
# and the answer is a `P.Dq` and not a `Maybe` -- and that is because the two srcs' answers
# must be bound and a `Maybe` is a TYPE and not a `Data`, and a `+` binder's TYPE
# MUST BE `Data` -- MEASURED 2026-11-08: "Note: +m can be used many times, so its type must be
# Data". and the port's own `P.UOp.divides.op` is the pattern that works (`ops.bend:8252`):
# one DEF, a `match` on the op, two direct self-calls bound with `+` in the ADD's arm, and
# the results combined by a helper. and a `P.Dq{ok: Bool, f: P.Found}` is exactly the port's own
# `P.Dv{ok: Bool, f: P.Found}` shape (`ops.bend:8467`) -- so the answer's TYPE is the port's own
# ANSWER TYPE AND NOT A NEW ONE.
#
# and `None{}` is upstream's `None`, which is the "we aren't sure" answer and not an
# ERROR -- AND IT IS THE `ok: False` HALF OF THE RECORD.
# ===========================================================================

# the answer: the port's own `P.Dv` shape -- `ok` says whether it divides exactly and `f`
# IS THE QUOTIENT's NODE.

# and the two arms: the count is empty and it is not -- and the comparison is a
# parameter and not a computed value (measured 2026-11-08).

# `ins` -- ops.py:622. `UOp(Ops.INS, kwargs.pop("src", self.src), (arg,
# kwargs.pop("dtype", self.dtype)), kwargs.pop("tag", self.tag))`. TWO of the three
# defaults are ARENA READS and one is `fold.bend`'s, so two are here and the third
# is the `dt` PARAMETER. That split is the point of the def: a port that spelled
# all three at each call site would copy `self.src` and `self.tag` by hand at
# every one of them, and a hand copy is where two sites drift apart. The `tag`
# default is load-bearing and the row says so: the fixture is a node with a
# non-`TNone` tag, and a port that hardcoded `TNone` would agree on every other
# fixture in the file.
def UOp.ins.of(+ar: P.Arena, +self: U32, nm: String, dt: S.Dt) -> P.Found:
  P.UOp.new(ar, P.OpsINS{}, P.Arena.srcs(ar, self), P.AInk{nm, dt}, P.Arena.tag(ar, self))

# `has_unbound_outputs` -- ops.py:570. `self.op is Ops.CALL and any((b:=
# x.unsharded_base).op is Ops.ALLOC and not b.arg.bind_on_realize for x in
# self.src[1:])`. THREE tests per element, and the src range is `P.Arena.src_to`:
# src[0] is the body and is not an output, which is a row and the only one that
# sees the `1`.
def UOp.huo.bor(arg: P.Arg) -> Bool:
  match arg:
    case P.AParam{pa}: Bool.not(P.ParamArg.bind_on_realize(pa))
    case _: True{}

def UOp.huo.at(fuel: Nat, +ar: P.Arena, x: U32) -> Bool:
  +b = P.UOp.unsharded_base(fuel, ar, x)
  Bool.and(P.eq_op(P.Arena.op(ar, b), P.OpsALLOC{}), UOp.huo.bor(P.Arena.arg(ar, b)))

# `Bool.or` does not short-circuit, so the whole list is walked even once the
# answer is known. That is not an optimisation miss: it is what makes the fold's
# cost a function of the src count alone rather than of where the hit is, and
# `P.UOp.unsharded_base` is fuel-bounded so the walk always terminates.
def UOp.huo.go(+fuel: Nat, +ar: P.Arena, xs: List<&2, U32>, hit: Bool) -> Bool:
  match xs:
    case Nil{}: hit
    case x <> t: UOp.huo.go(fuel, ar, t, Bool.or(hit, UOp.huo.at(fuel, ar, x)))

# The `self.op is Ops.CALL` half, and it is its own def because a CALL's src[1:] is
# a real list for EVERY op -- only the op test says the list means outputs.
def UOp.has_unbound_outputs.of(op: P.Op, fuel: Nat, ar: P.Arena, xs: List<&2, U32>) -> Bool:
  match op:
    case P.OpsCALL{}: UOp.huo.go(fuel, ar, xs, False{})
    case _: False{}

def UOp.has_unbound_outputs(fuel: Nat, +ar: P.Arena, +self: U32) -> Bool:
  UOp.has_unbound_outputs.of(P.Arena.op(ar, self), fuel, ar, P.Arena.src_from(ar, self, 1))


def sg.unbound.rows(+ar: P.Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("sg_huo_alloc", UOp.has_unbound_outputs(P.Arena.budget(ar), ar, 19))
    b : Unit <- row("sg_huo_bind", UOp.has_unbound_outputs(P.Arena.budget(ar), ar, 20))
    c : Unit <- row("sg_huo_buffer", UOp.has_unbound_outputs(P.Arena.budget(ar), ar, 21))
    d : Unit <- row("sg_huo_src0", UOp.has_unbound_outputs(P.Arena.budget(ar), ar, 18))
    g : Unit <- row("sg_huo_unshard", UOp.has_unbound_outputs(P.Arena.budget(ar), ar, 22))
    h : Unit <- row("sg_huo_noncall", UOp.has_unbound_outputs(P.Arena.budget(ar), ar, 26))
    row("sg_huo_op", UOp.has_unbound_outputs(P.Arena.budget(ar), ar, 23))

def sg.pa.put(p: P.ParamArg, bor: Bool) -> P.ParamArg:
  match p:
    case P.ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}:
      P.ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bor, val}

# `P.ParamArg.of` hardcodes `bind_on_realize=False` and this family needs both values
# of it, so the bound one is the same record with the field spelled. It is one def
# and not a second fourteen-field literal because two literals of a fourteen-field
# record are how eleven of the fields drift.
def sg.pa(sl: U32, bor: Bool) -> P.ParamArg: sg.pa.put(P.ParamArg.of(sl, S.int32()), bor)

def sg.ci() -> P.Arg: P.ACall{P.CallInfo{None{}, False{}, False{}, S.void()}}

def sg.arena() -> P.Arena:
  P.Arena{[
    P.Arena.bottom(),
    P.Node{P.OpsCONST{}, Nil{}, P.APy{P.CInt{H.i64_of_i32(0)}}, P.TNone{}},
    P.Node{P.OpsCONST{}, Nil{}, P.APy{P.CInt{H.i64_of_i32(1)}}, P.TNone{}},
    P.Node{P.OpsCONST{}, Nil{}, P.APy{P.CInt{H.i64_of_i32(2)}}, P.TNone{}},
    P.Node{P.OpsCONST{}, Nil{}, P.APy{P.CInvalid{}}, P.TNone{}},
    P.Node{P.OpsBUFFER{}, Nil{}, P.AParam{sg.pa(1, False{})}, P.TNone{}},
    P.Node{P.OpsADD{}, [1, 2], P.ANone{}, P.TInt{9}},
    P.Node{P.OpsALLOC{}, Nil{}, P.AParam{sg.pa(3, False{})}, P.TNone{}},
    P.Node{P.OpsALLOC{}, Nil{}, P.AParam{sg.pa(4, True{})}, P.TNone{}},
    P.Node{P.OpsUNSHARD{}, [7, 1], P.ATuple{[0]}, P.TNone{}},
    P.Node{P.OpsSTACK{}, [1, 2], P.ANone{}, P.TNone{}},
    P.Node{P.OpsSINK{}, [5], P.ANone{}, P.TNone{}},
    P.Node{P.OpsSINK{}, [5], P.AKernel{P.KernelInfo.of()}, P.TNone{}},
    P.Node{P.OpsCALL{}, [11], sg.ci(), P.TNone{}},
    P.Node{P.OpsCALL{}, [11], P.ACall{P.CallInfo{None{}, True{}, False{}, S.void()}}, P.TNone{}},
    P.Node{P.OpsCALL{}, [6], sg.ci(), P.TNone{}},
    P.Node{P.OpsCALL{}, [12], sg.ci(), P.TNone{}},
    P.Node{P.OpsCALL{}, [11], P.ACustom{P.CustomFunction{"f", S.void()}}, P.TNone{}},
    P.Node{P.OpsCALL{}, [7], sg.ci(), P.TNone{}},
    P.Node{P.OpsCALL{}, [11, 7], sg.ci(), P.TNone{}},
    P.Node{P.OpsCALL{}, [11, 8], sg.ci(), P.TNone{}},
    P.Node{P.OpsCALL{}, [11, 5], sg.ci(), P.TNone{}},
    P.Node{P.OpsCALL{}, [11, 9], sg.ci(), P.TNone{}},
    P.Node{P.OpsADD{}, [7, 1], P.ANone{}, P.TNone{}},
    P.Node{P.OpsADD{}, [1, 2], P.ANone{}, P.TNone{}},
    P.Node{P.OpsAFTER{}, [11], sg.ci(), P.TNone{}},
    P.Node{P.OpsADD{}, [1, 7], P.ANone{}, P.TNone{}}
  ], [0]}

def sg.seps(ar: P.Arena, xs: List<&2, U32>) -> String: P.s5.seps(ar, xs)

# THE FOUR FACTS of a minted node as one string, and the arena is the `P.Found`'s OWN.
# A mint GROWS the arena, so reading the caller's is the stale-arena bug
# bend2-constraints names at line 3854 -- and it PRINTS: the bottom is a NOOP, so a
# CAST interned into a discarded arena prints `Ops.NOOP` here and the gate catches
# it. That is the whole of what `sg_cconst_i32` is for, and it is why this def
# takes the `P.Found` rather than the caller's arena.
def sg.minted.of(+ar: P.Arena, +f: P.Found) -> String:
  String.concat([P.Ops.name(P.Arena.op(ar, P.Found.i(f))), "/", sg.seps(ar, P.Arena.srcs(ar, P.Found.i(f))),
    " ", P.sg.ctor(P.Arena.arg(ar, P.Found.i(f))), " t=", P.sg.tag(P.Arena.tag(ar, P.Found.i(f)))])

def sg.minted.go(ar: P.Arena, f: P.Found) -> String: sg.minted.of(ar, f)

def sg.minted.row(nm: String, +f: P.Found) -> IO(Unit): P.srow(nm, sg.minted.go(P.Found.ar(f), f))

# The `Maybe<&2, U32>` and `Maybe<&2, Bool>` printers. `none` is a Python RAISE in
# both cases -- `UOp.body` raises RuntimeError on a non-CALL and
# `UOp.is_inline_call` raises AttributeError on a P.CustomFunction arg -- and the
# oracle answers with the exception's NAME, so a row cannot be satisfied by a port
# that invented the spelling.
# `none:` NAMES the raise each `None` stands in for rather than printing a bare
# `none`. `UOp.body` is a RuntimeError and `UOp.is_inline_call` is an
# AttributeError, and the two are different facts: a port that returned `None` for
# some other reason would pass a bare `none` and fail these, which is the whole
# reason the exception's name is in the row.
def sg.maybe.go(hit: Maybe<&2, U32>, ar: P.Arena) -> String:
  match hit:
    case Some{i}: String.concat(["some:", P.Ops.name(P.Arena.op(ar, i))])
    case None{}: "none:RuntimeError"

def sg.pre.go(hit: Maybe<&2, Bool>) -> String:
  match hit:
    case Some{b}: String.concat(["some:", Bool.show(b)])
    case None{}: "none:AttributeError"

# ONE ROW PER TERM of `is_inline_call`'s four-term `and`. A four-term conjunction
# with one fixture is three dead terms, and this is the family of rows that says so:
# `pre` is `not self.arg.precompile`, `body` is `body.op is SINK`, `kernel` is
# `body.arg is None`, `add` is `op is CALL`, and `cfun` is the AttributeError.
def sg.invalid.isinv.of(+f: P.Found) -> Bool: P.UOp.is_invalid(P.Found.ar(f), P.Found.i(f))

def sg.invalid.isinv(ar: P.Arena) -> Bool: sg.invalid.isinv.of(P.UOp.invalid(ar))

def sg.idx.go(+ar: P.Arena, xs: List<&2, U32>, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case h <> t: sg.idx.go(ar, t, String.concat([acc, P.Ops.name(P.Arena.op(ar, h)), ","]))

def sg.idx.of(ar: P.Arena) -> String: sg.idx.go(ar, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26], "")

def sg.idx.str(ar: P.Arena) -> String: sg.idx.of(ar)

def sg.idx.tail(ar: P.Arena) -> IO(Unit): P.srow("sg_idx", sg.idx.str(ar))

def sg.ufix.name(+f: P.Found) -> String: P.Ops.name(P.Arena.op(P.Found.ar(f), P.Found.i(f)))

# THE INDEX ROW. Every fixture's index is its POSITION in the literal node list
# above and this prints the op name of each in that order, so a miscount is a
# visible row rather than a silent re-labelling of twenty-three rows. The
# arithmetic being easy is exactly why it needs a row.

def sg.ufix.rows(+ar: P.Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- P.srow("sg_ufix_uop", sg.ufix.name(UOp.ufix(ar, P.CU{1})))
    b : Unit <- sg.minted.row("sg_ufix_lit", UOp.ufix(ar, P.CV{P.CInt{H.i64_of_i32(9)}}))
    row("sg_ufix_miss", U32.is_eq(P.Found.i(UOp.ufix(ar, P.CU{23})), 23))

def sg.index.rows2(+ar: P.Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- sg.minted.row("sg_index_st2", P.UOp.index(ar, 10, [2, 3]))
    b : Unit <- sg.minted.row("sg_store_nogate", P.UOp.store(ar, 5, 1, None{}))
    c : Unit <- sg.minted.row("sg_store_gate", P.UOp.store(ar, 5, 1, Some{2}))
    d : Unit <- sg.minted.row("sg_ins_tag", UOp.ins.of(ar, 6, "x", S.int32()))
    g : Unit <- sg.minted.row("sg_ins_none", UOp.ins.of(ar, 24, "x", S.int32()))
    h : Unit <- sg.minted.row("sg_wmma", P.UOp.wmma(ar, 5, 1, 6, [16, 16, 16], S.int32(), 32, None{}))
    i : Unit <- sg.ufix.rows(ar)
    sg.idx.tail(ar)

# `ufix` -- ops.py:606. THREE rows and the third is the one the def exists for:
# `sg_ufix_miss` is a CONST fixture, so a def that MINTED on the `CU` arm would
# answer it with a fresh index and `False`. The other two are the arm names -- the
# op for the `CU` arm and the arg for the `CV` arm -- because a two-arm def with one
# fixture is a one-arm def with a comment.

def sg.index.rows(+ar: P.Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("sg_index_hit1", U32.is_eq(P.Found.i(P.UOp.index(ar, 10, [2])), 2))
    b : Unit <- row("sg_index_hit0", U32.is_eq(P.Found.i(P.UOp.index(ar, 10, [1])), 1))
    c : Unit <- row("sg_index_hitmiss", U32.is_eq(P.Found.i(P.UOp.index(ar, 5, [2])), 2))
    d : Unit <- sg.minted.row("sg_index_plain", P.UOp.index(ar, 5, Nil{}))
    g : Unit <- sg.minted.row("sg_index_one", P.UOp.index(ar, 5, [2]))
    h : Unit <- sg.minted.row("sg_index_two", P.UOp.index(ar, 5, [2, 3]))
    i : Unit <- sg.minted.row("sg_index_nc", P.UOp.index(ar, 10, [5]))
    sg.index.rows2(ar)

# `sg_store_gate` is the optional-gate row and `sg_store_nogate` is its
# non-movement pair: the two differ in the THIRD src and in nothing else, so a def
# that dropped the gate entirely would answer the first row with three srcs.
# `sg_ins_tag` is `ta` and `sg_ins_none` is `bu`, and they differ ONLY in the tag,
# which is what makes `UOp.ins`'s third default load-bearing: a port that
# hardcoded `TNone` passes `sg_ins_none` and fails `sg_ins_tag`.

def sg.const.of(+ar: P.Arena) -> IO(Unit):
  do IO<Unit>:
    x : Unit <- sg.minted.row("sg_invalid", P.UOp.invalid(ar))
    row("sg_isinv_ci", sg.invalid.isinv(ar))

# `sg_reduce_none` is the row the `AReduce` normalisation cannot be dropped from: a
# def that always built `AReduce` would answer it `reduce:Ops.NOOP/0`, because the
# `Maybe`'s `None` arm is the only thing that writes `ANone` here.

def sg.const.rows(+ar: P.Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- sg.const.of(ar)
    b : Unit <- row("sg_isinv_c0", P.UOp.is_invalid(ar, 1))
    c : Unit <- sg.minted.row("sg_reduce_some", P.UOp.reduce(ar, 5, Nil{}, Some{P.OpsADD{}}))
    d : Unit <- sg.minted.row("sg_reduce_none", P.UOp.reduce(ar, 5, Nil{}, None{}))
    g : Unit <- sg.minted.row("sg_reduce_two", P.UOp.reduce(ar, 5, [1], Some{P.OpsMAX{}}))
    h : Unit <- sg.minted.row("sg_cconst_i32", P.UOp.cconst(ar, P.CInt{H.i64_of_i32(7)}, S.int32()))
    j : Unit <- sg.minted.row("sg_cconst_f32", P.UOp.cconst(ar, P.CInt{H.i64_of_i32(7)}, S.single()))
    sg.index.rows(ar)


def sg.body.rows(+ar: P.Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- P.srow("sg_body_call", sg.maybe.go(UOp.body(ar, 13), ar))
    P.srow("sg_body_add", sg.maybe.go(UOp.body(ar, 23), ar))

# `sg_huo_src0` is the row the `1` in `src[1:]` exists for: `ca0`'s only ALLOC is
# src[0], which is the CALL's BODY, so the answer is False and a def that walked
# `src` instead of `src[1:]` answers True. `sg_huo_op` is the same separation on
# the other side -- a non-CALL with an ALLOC src -- and `sg_huo_unshard` is the only
# row that sees the `unsharded_base` peel, because `cun`'s ALLOC is two nodes down.

def sg.inline.rows(+ar: P.Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- P.srow("sg_inline_call", sg.pre.go(UOp.is_inline_call(ar, 13)))
    b : Unit <- P.srow("sg_inline_pre", sg.pre.go(UOp.is_inline_call(ar, 14)))
    c : Unit <- P.srow("sg_inline_body", sg.pre.go(UOp.is_inline_call(ar, 15)))
    d : Unit <- P.srow("sg_inline_kernel", sg.pre.go(UOp.is_inline_call(ar, 16)))
    g : Unit <- P.srow("sg_inline_cfun", sg.pre.go(UOp.is_inline_call(ar, 17)))
    h : Unit <- P.srow("sg_inline_aft", sg.pre.go(UOp.is_inline_call(ar, 25)))
    P.srow("sg_inline_add", sg.pre.go(UOp.is_inline_call(ar, 23)))


def sg.rows.arena(+ar: P.Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- sg.body.rows(ar)
    b : Unit <- sg.inline.rows(ar)
    c : Unit <- sg.unbound.rows(ar)
    sg.const.rows(ar)

def sg.rows() -> IO(Unit): sg.rows.arena(sg.arena())

# `sg_body_add` is the `case _` row: without a non-CALL the `None` arm of
# `UOp.body.of` is dead code, and a dead arm cannot be mutated into moving anything.

def s5.devrange(ar: P.Arena, dev: S.Dev) -> String: s5.dr(P.UOp.device_range_src(ar, dev))

# The MSELECT arm is a def of its own and not a third line of `s5.devrows`
# because a mint GROWS the arena: the `P.Found` is the only thing carrying the arena
# the answer's index lives in, and `s5.minted.row` takes one `P.Found` and cannot
# thread a grown arena into a second call. A row that called `copy_to_device`
# twice and printed the first's index against the second's arena is the
# stale-arena bug, and this shape is the one that cannot spell it.
def s5.selrow(+ar: P.Arena) -> IO(Unit):
  +f = P.UOp.copy_to_device(ar, 4, Some{1}, P.s5.dn(2))
  P.srow("s5_copy_sel", P.s5.minted.go(P.Found.ar(f), f))

def s5.devrows(+ar: P.Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- P.srow("s5_devrange_single", s5.devrange(ar, P.s5.d1(0)))
    b : Unit <- P.srow("s5_devrange_one", s5.devrange(ar, P.s5.dn(1)))
    c : Unit <- P.srow("s5_devrange_two", s5.devrange(ar, P.s5.dn(2)))
    d : Unit <- s5.minted.row("s5_copy_single", P.UOp.copy_to_device(ar, 1, None{}, P.s5.d1(0)))
    e : Unit <- s5.minted.row("s5_copy_multi", P.UOp.copy_to_device(ar, 1, None{}, P.s5.dn(2)))
    s5.selrow(ar)

def s5.ga(+ar: P.Arena, +fuel: Nat, i: U32) -> String: s5.ga.of(P.UOp.getaddr(fuel, ar, i, P.s5.d1(0)))

def s5.garows(+ar: P.Arena) -> IO(Unit):
  +fuel = P.Arena.budget(ar)
  do IO<Unit>:
    a : Unit <- P.srow("s5_ga_buffer", s5.ga(ar, fuel, 1))
    b : Unit <- P.srow("s5_ga_alloc", s5.ga(ar, fuel, 2))
    c : Unit <- P.srow("s5_ga_param", s5.ga(ar, fuel, 3))
    d : Unit <- P.srow("s5_ga_shrink", s5.ga(ar, fuel, 4))
    e : Unit <- P.srow("s5_ga_bitcast", s5.ga(ar, fuel, 5))
    f : Unit <- P.srow("s5_ga_binary", s5.ga(ar, fuel, 6))
    g : Unit <- P.srow("s5_ga_mstack", s5.ga(ar, fuel, 7))
    h : Unit <- P.srow("s5_ga_mselect", s5.ga(ar, fuel, 8))
    i : Unit <- P.srow("s5_ga_linear", s5.ga(ar, fuel, 9))
    j : Unit <- P.srow("s5_ga_const", s5.ga(ar, fuel, 10))
    k : Unit <- P.srow("s5_ga_reshape", s5.ga(ar, fuel, 11))
    l : Unit <- P.srow("s5_ga_after", s5.ga(ar, fuel, 12))
    P.srow("s5_ga_add", s5.ga(ar, fuel, 13))

# `copy_to_device` (:761), `device_range_src` (:849) and `getaddr` (:844) arrive
# from ops.py[701,1000] and their rows sit between `s5_sint_const` and
# `s5_gate_linear` in the oracle, so they are emitted HERE rather than from
# `main`: a gate compares rows in emission order, and `main` is the wrong seam.
def s5.movers.r2() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- s5.devrows(P.s5.ga.arena())
    s5.garows(P.s5.ga.arena())

def s5.movers.rest(+ar: P.Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- P.srow("s5_sharding_us", s5.shardstr(ar, P.UOp.sharding(ar, 7)))
    b : Unit <- P.srow("s5_sharding_none", s5.shardstr(ar, P.UOp.sharding(ar, 5)))
    c : Unit <- P.srow("s5_sint_const", s5.sint(ar, P.SInt.of(H.i64_of_i32(1))))
    s5.movers.r2()

def s5.movers(+ar: P.Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- s5.minted.row("s5_barrier", P.UOp.barrier(ar, 2, Nil{}))
    b : Unit <- s5.minted.row("s5_bufferize", P.UOp.bufferize(ar, 2, Nil{}))
    c : Unit <- s5.minted.row("s5_bufferize_arg", P.UOp.bufferize(ar, 2, [1]))
    d : Unit <- s5.minted.row("s5_allreduce", P.UOp.allreduce(ar, 4, P.OpsADD{}, S.Dn{[1, 1]}))
    e : Unit <- s5.minted.row("s5_mselect", P.UOp.mselect(ar, 2, 0))
    s5.movers.rest(ar)

# ONE entry point for the whole block, so `main` gets one line and the fuel is
# computed in one place. `P.Arena.budget` is the only sound fuel: one step per peel,
# one per worklist entry, and both are bounded by the arena's own size plus edges.
def s5.rows.rest(+ar: P.Arena, +f: P.S5) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- s5.movers(ar)
    s5.gate(ar)

def s5.rows.arena(+ar: P.Arena, +f: P.S5) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- s5.idx(ar, f)
    b : Unit <- s5.base(P.Arena.budget(ar), ar, f)
    c : Unit <- s5.unsharded(P.Arena.budget(ar), ar, f)
    d : Unit <- s5.storage(P.Arena.budget(ar), ar, f)
    e : Unit <- s5.woafter(P.Arena.budget(ar), ar, f)
    g : Unit <- s5.bufuop(P.Arena.budget(ar), ar, f)
    h : Unit <- s5.hbi(P.Arena.budget(ar), ar, f)
    i : Unit <- s5.splitrows(P.Arena.budget(ar), ar)
    s5.rows.rest(ar, f)



def s5.rows() -> IO(Unit):
  s5.rows.arena(s5.arena(), s5.ids())

# `device or to_tuple(self.device)[0]` IS THE DEVICE AND IS A PARAMETER, not a
# fold. Python's default reads `self.device`, which is `uop/fold.bend`'s
# `UOp.device(ar, tb, i)` over a Table this file has no business building, so `dev`
# is what the caller resolved. That is this block's only signature change and it
# is stated here rather than left to be discovered. The discarded GETADDR in the
# `case False{}` arm grows the arena and is thrown away, which is what `P.UOp.after`
# and `P.UOp.broadcast` above already do.

def vr.pa.name(pa: P.ParamArg, nm: Maybe<&2, String>) -> P.ParamArg:
  match pa:
    case P.ParamArg{slot, dtype, vmin_vmax, multiple_of, _n, addrspace, device, volatile, image, buffer, bind_on_realize, val}:
      P.ParamArg{slot, dtype, vmin_vmax, multiple_of, nm, addrspace, device, volatile, image, buffer, bind_on_realize, val}

# ==== the `vr_expr_*` fixture and rows =====================================
#
# `expr` has THREE answers and each gets a row, because one row cannot tell a
# name from a missing name from a non-`P.ParamArg` arg -- and those three are three
# different reasons CPython raises. The `vr_expr_` rows are the whole gate: there
# is no second family, so nothing here can be load-bearing by accident.
#
# The four PARAM fixtures differ in ONE field each, which is what makes the
# mutation table below able to move a row. A fixture set where every node is
# identical except the field under test is one where a wrong answer is invisible.
def vr.pa(nm: Maybe<&2, String>) -> P.ParamArg:
  vr.pa.name(P.ParamArg.of(1, S.int32()), nm)

# 1 PARAM named, 2 BUFFER named, 3 PARAM unnamed, 4 CONST (arg is not a P.ParamArg).
# 1 and 2 are the SAME arm of the arg sum and they must answer the same -- that
# is the row pair that says the op is genuinely not consulted.
def vr.arena() -> P.Arena:
  P.Arena{[
    P.Arena.bottom(),
    P.Node{P.OpsPARAM{}, Nil{}, P.AParam{vr.pa(Some{"i"})}, P.TNone{}},
    P.Node{P.OpsBUFFER{}, Nil{}, P.AParam{vr.pa(Some{"buf"})}, P.TNone{}},
    P.Node{P.OpsPARAM{}, Nil{}, P.AParam{vr.pa(None{})}, P.TNone{}},
    P.Node{P.OpsCONST{}, Nil{}, P.APy{P.CInt{H.i64_of_i32(7)}}, P.TNone{}}], [0]}

def vr.show(m: Maybe<&2, String>) -> String:
  match m:
    case Some{s}: String.concat(["some:", s])
    case None{}: "none"

def vr.expr.row(nm: String, +ar: P.Arena, i: U32) -> IO(Unit):
  P.srow(nm, vr.show(P.UOp.expr(ar, i)))

def vr.expr.rows(+ar: P.Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- vr.expr.row("vr_expr_param", ar, 1)
    b : Unit <- vr.expr.row("vr_expr_buffer", ar, 2)
    c : Unit <- vr.expr.row("vr_expr_unnamed", ar, 3)
    vr.expr.row("vr_expr_nonparam", ar, 4)

# DONE(p3) ops.py:1048  def const_factor
#   `def const_factor(self) -> int: """largest known int that divides self"""` --
#   five arms, a `math.gcd` over the STACK and ADD srcs, and a positional read for
#   MUL. Four of the five arms are one `match` each and are trivially expressible.
#   AND IT IS DONE: `def P.UOp.const_factor(fuel, ar, i) -> H.I64` IS ABOVE, AT `:7752`.
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
#   Every fold already in this file is SELF-recursive for this reason -- `P.UOp.base`,
#   `P.UOp.unsharded_base`, `P.UOp.storage_base`, `UOp.huo.go` -- one def with the
#   `match fuel` inside it and a non-recursive `.peel` above. `const_factor` cannot
#   be written that way, because its recursion is over a DIFFERENT node per step
#   (each src) while its arm is decided per node: fusing them means one def that
#   both picks the arm and walks the list, which is a worklist rewrite of the
#   shape `P.UOp.base` uses for a single peel.
#
#   So the wall is real and it is a substrate limit, not a missing thought.
#   `.agents/slop/bend-toposort.py` detects the cycle and refuses to write rather
#   than oscillating, which is how this was found.
#
# what that wall still blocks, re-measured 2026-11-04 -- and this paragraph used to
# overstate it. It named five markers as blocked. two of the five are done:
#
#   DONE  ops.py:1069 `divides`   -- `P.UOp.divides.op` (:7951) and `P.UOp.divides` (:7972),
#                                    verified against CPython on 8 of 8 shapes.
#   DONE  ops.py:1082 `pop_const` -- `P.UOp.pop_const_val` (:7738) / `P.UOp.pop_const_hits`
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
#   `P.UOp.const(b, dtype or self.dtype)` plus `_mop(Ops.EXPAND, arg=self._shape)`, so the
#   SHAPED half needs the shape field this arena does not carry. The scalar half already
#   exists as `sy_const_like` (symbolic.bend:485).


# ==== ops.py:1901 symbol=resolve_returned_after  ===============================
#
# `"""Extract a call output's matching store, preserving writes to the enclosing
# scope's output PARAMs."""` -- `[st for st in t.src if st.op is Ops.STORE and
# st.src[0].unsharded_base is r.unsharded_base]`, then `if len(stores) != 1: return
# None`, then one of two mints.
#
# `r.unsharded_base` IS COMPUTED ONCE AND PASSED, not read twice. CPython evaluates
# the peel again in the final `r.unsharded_base.op is Ops.PARAM`; `unsharded_base`
# is a PURE peel (`P.UOp.base` plus UNSHARD, and neither mints), so the two walks
# answer the same index and computing it once is the same answer for one less walk.
# A gate row cannot see the difference, and the reason is written here so nobody
# "simplifies" it back into two reads.
#
# the answer's arena is not the caller's in one arm. `r.after(stores[0])` mints and
# grows the arena; `stores[0].src[1]` is an index that already existed. So the
# answer is a `P.Found` and not a bare `U32` -- the same reason `P.UOp.index.pick`
# returns a `P.Found`, and the same stale-arena bug if it does not: a caller reading
# the index out of ITS OWN arena gets the bottom, which is a NOOP. The `rra_arena`
# row reads the op from the RETURNED arena on purpose.
def rra.hit(fuel: Nat, +ar: P.Arena, rb: U32, +st: U32) -> Bool:
  Bool.and(P.eq_op(P.Arena.op(ar, st), P.OpsSTORE{}),
    U32.is_eq(P.UOp.unsharded_base(fuel, ar, P.Arena.src(ar, st, 0)), rb))

# THE FILTER, and it is ONE def rather than three. The first draft split it into
# `filter.go` / `at` / `put` so each `match` would scrutinise a binder -- and that is
# MUTUALLY recursive, which Bend refuses: `go` calls `at` and `at` calls `go`, and
# `bend-toposort.py` reported the cycle and declined to write, correctly.
#
# `Bool.pick` is the way out, and it is why the file's own folds are single defs: it
# is the only conditional that does not need a `match`, so the accumulator is an
# ordinary expression and the def can recurse into ITSELF. The `List.append` is built
# even when the test is False, which is the same eager-argument waste `P.UOp.after.go`
# and `P.UOp.getaddr.go` already pay and is free here: a discarded list is not a
# discarded NODE.
def rra.filter.go(+fuel: Nat, +ar: P.Arena, +xs: List<&2, U32>, +acc: List<&2, U32>, +rb: U32) -> List<&2, U32>:
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
# arenas and the pick must carry the `P.Found` rather than an index. The discarded
# `P.UOp.after` in the `False{}` arm grows the arena and is unreachable, which is the
# same waste `P.UOp.after.go` and `P.UOp.getaddr.go` already pay: Bend evaluates an
# argument before the callee branches, and the waste is only free when the two
# candidates are the same node -- here they are NOT, which is exactly why the pick
# carries a `P.Found` rather than an index.
def rra.pick(isparam: Bool, +ar: P.Arena, r: U32, st: U32) -> P.Found:
  match isparam:
    case True{}: P.UOp.after(ar, r, [st])
    case False{}: P.Found{ar, P.Arena.src(ar, st, 1)}

# The `Maybe` from `rra.one` is a COMPUTED value, so the `match` that opens it lives
# in a def that RECEIVES it. `done` does not call back, so this is one-directional
# and not a second instance of the mutual-recursion wall above.
def rra.done(+ar: P.Arena, r: U32, rb: U32, hit: Maybe<&2, U32>) -> Maybe<&2, P.Found>:
  match hit:
    case None{}: None{}
    case Some{st}: Some{rra.pick(P.eq_op(P.Arena.op(ar, rb), P.OpsPARAM{}), ar, r, st)}

def resolve_returned_after(+fuel: Nat, +ar: P.Arena, +r: U32, t: U32) -> Maybe<&2, P.Found>:
  +rb = P.UOp.unsharded_base(fuel, ar, r)
  +stores = rra.filter.go(fuel, ar, P.Arena.srcs(ar, t), Nil{}, rb)
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
#                        `P.GroupOp.movement`, so unsharded_base(18) = 3 = rb
#    19  SINK [16,18]    the store AND that reshape. The ONLY sink where the op test
#                        and the base test disagree, so it is the only row that can
#                        see the op test at all.
#
#                        BOTH of these were FOUND BY THE MUTATION TABLE, not by
#                        reading the code, and the two attempts are the reason the
#                        comment is here. `rra_none_zero` does not carry the conjunct:
#                        its only src is a CONST, whose base is not r either. A sink of
#                        [the store, the BUFFER] does not either -- the BUFFER has no
#                        srcs, so `P.Arena.src` answers the bottom and the base test
#                        rejects it. Two fixtures, two rounds, both measuring zero
#                        moved rows. A conjunct needs a fixture where it is the ONLY
#                        failing test, and that is not the same as a fixture where it
#                        happens to be one of two.
def rra.pa(slot: U32) -> P.ParamArg: P.ParamArg.of(slot, S.int32())

def rra.arena() -> P.Arena:
  P.Arena{[
    P.Arena.bottom(),
    P.Node{P.OpsCONST{}, Nil{}, P.APy{P.CInt{H.i64_of_i32(7)}}, P.TNone{}},
    P.Node{P.OpsCONST{}, Nil{}, P.APy{P.CInt{H.i64_of_i32(9)}}, P.TNone{}},
    P.Node{P.OpsBUFFER{}, Nil{}, P.AParam{rra.pa(1)}, P.TNone{}},
    P.Node{P.OpsAFTER{}, [3], P.ANone{}, P.TNone{}},
    P.Node{P.OpsPARAM{}, Nil{}, P.AParam{rra.pa(2)}, P.TNone{}},
    P.Node{P.OpsSTORE{}, [4, 1], P.ANone{}, P.TNone{}},
    P.Node{P.OpsSINK{}, [6], P.ANone{}, P.TNone{}},
    P.Node{P.OpsSTORE{}, [4, 2], P.ANone{}, P.TNone{}},
    P.Node{P.OpsSINK{}, [6, 8], P.ANone{}, P.TNone{}},
    P.Node{P.OpsSINK{}, [1], P.ANone{}, P.TNone{}},
    P.Node{P.OpsSINK{}, Nil{}, P.ANone{}, P.TNone{}},
    P.Node{P.OpsSINK{}, [6, 1], P.ANone{}, P.TNone{}},
    P.Node{P.OpsSTORE{}, [5, 1], P.ANone{}, P.TNone{}},
    P.Node{P.OpsSINK{}, [13], P.ANone{}, P.TNone{}},
    P.Node{P.OpsUNSHARD{}, [3], P.ATuple{[0]}, P.TNone{}},
    P.Node{P.OpsSTORE{}, [3, 1], P.ANone{}, P.TNone{}},
    P.Node{P.OpsSINK{}, [16], P.ANone{}, P.TNone{}},
    P.Node{P.OpsRESHAPE{}, [3], P.ANone{}, P.TNone{}},
    P.Node{P.OpsSINK{}, [16, 18], P.ANone{}, P.TNone{}}], [0]}

# The printer, and it reads the op out of the FOUND'S OWN ARENA. That is not
# tidiness: the `rra_param` answer is a freshly minted AFTER, and a reader using the
# fixture's arena would get the BOTTOM, which is a NOOP -- the stale-arena bug, and
# it PRINTS as `Ops.NOOP`.
def rra.show(m: Maybe<&2, P.Found>) -> String:
  match m:
    case Some{+f}: String.concat(["some:", P.Ops.name(P.Arena.op(P.Found.ar(f), P.Found.i(f)))])
    case None{}: "none"

def rra.row(nm: String, +ar: P.Arena, r: U32, t: U32) -> IO(Unit):
  P.srow(nm, rra.show(resolve_returned_after(P.Arena.budget(ar), ar, r, t)))

# THE COUNT row, and it reads the RETURNED arena. `rra_param` is the one answer that
# MINTS, so this pins that single node: a def that stopped building the AFTER would
# answer all seven other rows identically and this row would drop.
# THE DELTA, and the first draft printed the arena SIZE and called it a count. The
# oracle prints how many nodes were minted, which is 1 for the PARAM arm; the port
# printed `P.Arena.next` of the returned arena, which is 19, and the two lanes were
# measuring DIFFERENT THINGS and disagreeing. Same gate, two quantities, and only
# one of them says anything: a def that minted nothing would still answer 19 if the
# arena happened to be that size.
def rra.next(base: U32, hit: Maybe<&2, P.Found>) -> String:
  match hit:
    case Some{+f}: U32.show(U32.sub(P.Arena.next(P.Found.ar(f)), base))
    case None{}: "none"

def rra.count(+ar: P.Arena, r: U32, t: U32) -> String:
  rra.next(P.Arena.next(ar), resolve_returned_after(P.Arena.budget(ar), ar, r, t))

# rra_val and rra_param are a PAIR and neither is worth having alone. Both have
# exactly one matching store; they differ only in whether `r.unsharded_base.op` is
# PARAM, and a def with that conjunct dropped answers `rra_param` with the CONST and
# passes every other row in the family.
def rra.rows(+ar: P.Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- rra.row("rra_val", ar, 4, 7)
    b : Unit <- rra.row("rra_param", ar, 5, 14)
    c : Unit <- rra.row("rra_unshard", ar, 15, 17)
    d : Unit <- rra.row("rra_none_zero", ar, 4, 10)
    e : Unit <- rra.row("rra_none_two", ar, 4, 9)
    f : Unit <- rra.row("rra_none_empty", ar, 4, 11)
    g : Unit <- rra.row("rra_mixed", ar, 4, 12)
    h : Unit <- rra.row("rra_samebase", ar, 15, 19)
    P.srow("rra_arena", rra.count(ar, 5, 14))

# ==== the `vrn_*` rows =====================================================
#
# `variable` sets FIVE fields -- slot, name, vmin_vmax, multiple_of, addrspace -- and
# the other eight keep `P.ParamArg.of`'s defaults. So a row prints those five plus the
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

def vrn_lo.of(r: P.PyRange) -> String:
  match r:
    case P.PyRange{lo, hi}: H.i64_text(lo)

# The two range ends are TWO defs, and `Bool.pick` is why: it EVALUATES both
# branches, so `Bool.pick(H.I64, top, r.hi, r.lo)` is `r.hi` and `r.lo` read as terms
# outside a match, which Bend rejects. A `top: Bool` parameter would be the terser
# spelling and it is not available; the two ends are the two arms.
# `P.PyRange` has NO accessors, and a `case P.PyRange{lo}` is not a partial match -- the
# same all-fields rule `P.ParamArg` has. So the range is destructured in full and the
# two ends are read from the BINDERS, which is why these two defs take the payload
# rather than the `Maybe`: `ops.bend:1503` spells the same destructuring.
def vrn_lo(m: Maybe<&2, P.PyRange>) -> String:
  match m:
    case Some{r}: vrn_lo.of(r)
    case None{}: "-"

def vrn_hi.of(r: P.PyRange) -> String:
  match r:
    case P.PyRange{lo, hi}: H.i64_text(hi)

def vrn_hi(m: Maybe<&2, P.PyRange>) -> String:
  match m:
    case Some{r}: vrn_hi.of(r)
    case None{}: "-"

def vrn_f5(p: P.ParamArg) -> Maybe<&2, U32>:
  match p:
    case P.ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: multiple_of

def vrn_f4(p: P.ParamArg) -> Maybe<&2, P.PyRange>:
  match p:
    case P.ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: vmin_vmax

def vrn_f3(p: P.ParamArg) -> Maybe<&2, String>:
  match p:
    case P.ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: name

# The five field readers, one match each. Seven defs and not one that returns a
# record, because a record would have to spell all thirteen fields and a
# thirteen-field literal is the thing `sg.pa.put` exists to avoid.
def vrn_pa_of(arg: P.Arg) -> P.ParamArg:
  match arg:
    case P.AParam{p}: p
    case _: P.ParamArg.of(P.ParamArg.no_slot(), S.weakint())

def vrn_f7(p: P.ParamArg) -> S.Addr:
  match p:
    case P.ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: addrspace

def vrn_row(nm: String, +f: P.Found) -> IO(Unit):
  +ar = P.Found.ar(f)
  +p = vrn_pa_of(P.Arena.arg(ar, P.Found.i(f)))
  P.srow(nm, String.concat([
    "slot=", Bool.pick(String, U32.is_eq(P.ParamArg.slot(p), P.ParamArg.no_slot()), "-1", U32.show(P.ParamArg.slot(p))),
    " name=", vrn_opts(vrn_f3(p)), " mult=", vrn_optu(vrn_f5(p)), " addr=", vrn_addr_name(vrn_f7(p)),
    " lo=", vrn_lo(vrn_f4(p)), " hi=", vrn_hi(vrn_f4(p)),
    " nsrc=", U32.show(P.Arena.nsrc(ar, P.Found.i(f)))]))

def vrn_rows(+ar: P.Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- vrn_row("vrn_default", P.UOp.variable(ar, "i", H.i64_of_i32(0), H.i64_of_i32(10), 1, S.weakint()))
    b : Unit <- vrn_row("vrn_multi", P.UOp.variable(ar, "j", H.i64_neg(True{}, H.i64_of_i32(5)), H.i64_of_i32(5), 4, S.weakint()))
    c : Unit <- vrn_row("vrn_neg", P.UOp.variable(ar, "m", H.i64_neg(True{}, H.i64_of_i32(100)), H.i64_neg(True{}, H.i64_of_i32(1)), 1, S.weakint()))
    vrn_row("vrn_int32", P.UOp.variable(ar, "k", H.i64_of_i32(1), H.i64_of_i32(2), 1, S.int32()))

# `Map.has` answers a `Sigma` and not a `Maybe`, so the Bool rides out in the second
# half of the pair. `uop/render.bend:1076 symbol=ctx_has.of`'s `ctx_has.of` destructures the same shape and
# this is the third copy of THAT two-line destructure -- see `Maybe.has` below.
def vv_has.of(r: Sigma<&1, &1, Map<&2, H.I64>, _ => Bool>) -> Bool:
  match r:
    case Tuple{m, b}: b

def vv_has(v: P.VarVals, k: String) -> Bool:
  vv_has.of(Map.has(&2, H.I64, P.VarVals.m(v), k))

# ==== 186fbba2a0e149a87b625c228254d49ffa72a2ca:tinygrad/uop/ops.py:1350
#      `ProgramInfo.vals` ====================================================
#
# upstream has no such method at the PIN, and this block is not a port of it.
# `a6addc2d4` ("buffers and args in any input order", 2026-10-14) DELETED
# `ProgramInfo.vals` and renamed the field it read, `vars` -> `params`; the pin
# `5c2bf39d6c4b` is a descendant of that commit, and its `class P.ProgramInfo`
# (`tinygrad/uop/ops.py:1343`) has `params` and NO `vals`. So the block below is
# the port of the method upstream HAD at `186fbba2a` -- the parent of
# `a6addc2d4` -- where `def vals` is at `tinygrad/uop/ops.py:1350`.
#
# IT IS NOT A LOOSE ADDITION. The port's realize lane is at that same revision:
# `engine/realize.bend`'s `get_call_var_uops` is the port of
# `186fbba2a0e149a87b625c228254d49ffa72a2ca:tinygrad/engine/realize.py:16`
# `get_call_var_uops`, which read `prg.arg.vars`; the pin reads
# `prg.kernel_params` instead (`tinygrad/engine/realize.py:17`
# `get_call_kernel_args`). And `P.ProgramInfo.from_sink` is NOT PORTED, so
# `P.ProgramInfo.params` is never built from a sink and this `vals` has no
# real-program caller: its only caller is this file's own `vv_*` lane.
#
# `tuple(var_vals[k.expr] for k in self.vars)` with
# `raise RuntimeError(f"unbound Variable {e}")` on a miss. MEASURED:
# `P.ProgramInfo(vars=(i,j)).vals({'i':7,'j':9})` is `(7, 9)` and a miss is
# `RuntimeError: unbound Variable 'j'`.
#
# I RECORDED THIS BLOCKER WRONG TWICE, both times in the same direction: I claimed
# a BEND LANGUAGE CHANGE was needed and never grepped for it. `Map` is a stdlib type
# from `import Base` -- `references/bend/bend2/base.bend:2752 symbol=Map.put` Map.put, `:2876`
# Map.set, `:2683` Map.has, `:2736` Map.get, all four present -- and
# `uop/render.bend:1012 symbol=range_ids.of` and `:1017` were already CALLING `Map.set` and `Map.get`
# through `Ctx` while the note here said the rule did not exist.
#
# and the second caller i named was wrong too. i wrote that `pyrender`'s `Ctx` walk
# wanted the same fold; `render.bend:1728 symbol=render_with_splits`'s `render_with_splits` answers
# `List<&2, Bind>` and not a `Maybe`, so it does not. The REAL second caller is
# `unified_rewrite`'s fixpoint (ops.py:1826-1837 symbol=RewriteContext.unified_rewrite), where `test_n: UOp|None` is
# carried through a loop and a `BottomUpGate` breaks out of it -- and THAT is the
# engine's remaining named wall. Two real callers, and the second one is why the
# idiom was worth looking for.
#
# THE IDIOM IS `bcast.go` (uop/fold.bend:587 symbol=bitcast_dims.res) verbatim: a `Maybe`-carried LIST
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
# where a bare `H.I64` belongs. `Map.get` has NO quantifier -- `uop/render.bend:1025 symbol=multirange_str.go`'s
# `Map.get(String, "", Ctx.map(c), U32.show(u))` shows the shape with the `""` in
# the same slot. Three of the four `Map` readers in the tree and not the fourth.
#
# the default is 0 and that is why the `has` is not redundant. a miss returns 0,
# which is a legal bound, so "unbound" and "bound to 0" are the same value here and
# only `Map.has` separates them. `ctx_get` gets away with `""` because
# uop/render.bend:1025 symbol=multirange_str.go states every src was written first; `vals` has no such guarantee.
def vv_of(+v: P.VarVals, +k: String) -> Maybe<&2, H.I64>:
  vv_of.of(Map.get(H.I64, H.i64_of_i32(0), P.VarVals.m(v), k), vv_has(v, k))

# THE FOLD, AND IT IS ONE DEF. The first draft split it into `step` / `lookup` /
# `fetch`, which is MUTUALLY RECURSIVE -- `step` calls `lookup`, `lookup` calls
# `fetch`, and `fetch` calls `step` back. Bend refuses that, and `bend-toposort`
# reported the cycle and declined to write, correctly.
#
# `Maybe.bind`'s LAMBDA is the continuation, so the three become one def with ONE
# `match` (on the list, the only scrutinee) and TWO binds. `bcast.go` at
# uop/fold.bend:587 symbol=bitcast_dims.res is the same shape and is why that fold is two lines: the recursion
# is in the CLOSURE, not in a call chain. `Maybe.bind` is the answer to "a `Maybe`
# accumulator wants two matches per step", and it was already in the tree.
def vals.step(+ar: P.Arena, +v: P.VarVals, xs: List<&2, U32>, acc: List<&2, H.I64>) -> Maybe<&2, List<&2, H.I64>>:
  match xs:
    case Nil{}: Some{acc}
    case h <> t:
      Maybe.bind(&2, String, List<&2, H.I64>, P.UOp.expr(ar, h), k =>
        Maybe.bind(&2, H.I64, List<&2, H.I64>, vv_of(v, k), x =>
          vals.step(ar, v, t, List.append(&2, H.I64, acc, [x]))))

# THE ENTRY, and the `Maybe` is the refusal for an unbound Variable. Python raises,
# and this file's standing spelling for a raise is the absent case -- the same
# `Maybe` `P.UOp.expr` uses, and the reason `Maybe` rather than a sentinel is that a
# schedule key of the WRONG LENGTH is a wrong program and not a diagnostic.
#
# ==== PORT EXTENSION ========================================================
# PORT-EXTENSION: ProgramInfo.vals
# PORT-EXTENSION-DATE: 2026-10-14T10:15:48Z
# PORT-EXTENSION-UPSTREAM: a6addc2d4344ef51636626e937afece3147f0db3
# PORT-EXTENSION-DERIVE: git --no-optional-locks log -1 --format=%H -S 'def vals(self, var_vals' refs/remotes/upstream/master -- tinygrad/uop/ops.py
#
# WHAT THIS IS. The port defines a member of `P.ProgramInfo` that upstream's
# `P.ProgramInfo` does not have, so it is an EXTENSION and it says so here, where
# the def is, so the declaration cannot drift away from the thing it declares.
# `gates/valsdiv-gate.py` READS these four lines and CHECKS them: an extension
# with no declaration is a FAIL, a declaration whose upstream revision does not
# hold the method is a FAIL, a declaration whose date is not the revision's own
# author date is a FAIL, and a declaration whose derive command does not
# reproduce is a FAIL. So this is not prose and it is not a licence: it is a
# claim the gate can lose.
#
# why the date is upstream's and not ours. `a6addc2d4` is the commit that
# DELETED `ProgramInfo.vals`, and `2026-10-14T10:15:48Z` is that commit's own
# author date. The gate reads the date out of the object store and compares, so
# the sha and the date are two different values that have to agree -- the check
# `gates/rotclaim-gate.py` calls a dated record, and the reason a sha written
# in prose is not one.
#
# why the upstream sha is the deleting commit and not the one that had it. The
# gate reads BOTH ends: at `a6addc2d4` upstream's `P.ProgramInfo` has no `vals`,
# and at its parent `186fbba2a` it has one. So the declaration names the moment
# the port and upstream parted.
#
# why the derive is a history query and not a `git show`. The derive re-derives
# the deleting commit from UPSTREAM's own ref -- the most recent upstream commit
# that changed the number of `def vals(self, var_vals` lines -- so the declared
# sha and the derive's answer are two INDEPENDENT reads that have to agree, and
# a re-vendor of `tinygrad/` in THIS repo cannot satisfy the claim.
# ==== END PORT EXTENSION ====================================================
# THE ALU SUBSET OF `params`, and it is a SUBSET because upstream's DELETED
# `ProgramInfo.vals` read `self.vars` -- the VARIABLES -- and the port's
# `P.ProgramInfo.params` is upstream's `params`, which `from_sink` fills with ALL
# the params (`if u.op is Ops.PARAM: _params.append(u)`, ops.py:1364). Reading
# the whole list would look a BUFFER's name up in the variable map, and a
# buffer has no name, so the fold would REFUSE a program that upstream's `vals`
# answers. THE SUBSET IS THE VARIABLES, and `AddrSpace.ALU` is what makes a
# PARAM a variable.
def vals.alu.put.of(is_alu: Bool, h: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match is_alu:
    case True{}: List.append(&2, U32, acc, [h])
    case False{}: acc

def vals.alu.put(ar: P.Arena, +h: U32, acc: List<&2, U32>) -> List<&2, U32>:
  vals.alu.put.of(P.pa.is_alu.of(P.Arena.arg(ar, h)), h, acc)

def vals.alu.go(+ar: P.Arena, xs: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case h <> t: vals.alu.go(ar, t, vals.alu.put(ar, h, acc))

def ProgramInfo.vals(+ar: P.Arena, v: P.VarVals, x: P.ProgramInfo) -> Maybe<&2, List<&2, H.I64>>:
  vals.step(ar, v, vals.alu.go(ar, P.ProgramInfo.params(x), Nil{}), Nil{})

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
# THE ADDRSPACE IS `ALU`, and that is the whole of what this def is for.
# UPSTREAM'S `ProgramInfo.vars` -- the field the DELETED `ProgramInfo.vals`
# READ -- IS THE ALU PARAMS (`if u.op is Ops.PARAM and u.addrspace ==
# AddrSpace.ALU`, ops.py:1363 at `186fbba2a`), and the port's `vals` reads the
# alu subset of `params` for the same reason. so the fixture's params must be
# alu params, or the lane would be testing a list upstream's `vals` never had.
# the rows' values do not change: they are the map's values, keyed by name.
def vd_pa.put(p: P.ParamArg, nm: Maybe<&2, String>) -> P.ParamArg:
  match p:
    case P.ParamArg{slot, dtype, vmin_vmax, multiple_of, _n, addrspace, device, volatile, image, buffer, bind_on_realize, val}:
      P.ParamArg{slot, dtype, vmin_vmax, multiple_of, nm, S.Aalu{}, device, volatile, image, buffer, bind_on_realize, val}

def vd_pa(slot: U32, nm: Maybe<&2, String>) -> P.ParamArg:
  vd_pa.put(P.ParamArg.of(slot, S.weakint()), nm)

# `P.UOp.variable` is PORTED and is what mints these, so the fixture is the def under
# test's OWN constructor rather than a hand-built ParamArg. That is the discipline
# `rra`'s arena follows and the reason `vrn_*` can gate `P.UOp.variable` from inside
# the file that uses it.
def vd_arena() -> P.Arena:
  P.Arena{[
    P.Arena.bottom(),
    P.Node{P.OpsPARAM{}, Nil{}, P.AParam{vd_pa(P.ParamArg.no_slot(), Some{"i"})}, P.TNone{}},
    P.Node{P.OpsPARAM{}, Nil{}, P.AParam{vd_pa(P.ParamArg.no_slot(), Some{"j"})}, P.TNone{}},
    P.Node{P.OpsCONST{}, Nil{}, P.APy{P.CInt{H.i64_of_i32(5)}}, P.TNone{}}], [0]}

def vd_put(nm: String, x: H.I64, base: P.VarVals) -> P.VarVals:
  P.VarVals{Map.set(&2, H.I64, P.VarVals.m(base), nm, x)}

# the three `Map` readers take their quantifier in three different places, and
# getting it wrong is a `expected : Map<&2, H.I64> / observed: P.VarVals` rather than a
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
# THE PRINTER, and it is the `ax_names_str` shape (ops.bend:6555 symbol=ax_names_str): collect the
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
# parentheses is "()". `ax_names_str` at ops.bend:6555 symbol=ax_names_str is the same shape and it has
# no `match` either.
def vd_text(ys: List<&2, H.I64>) -> String:
  String.concat(["(", String.join(vd_text.go(ys, Nil{}), ","), ")"])

def vd_show(m: Maybe<&2, List<&2, H.I64>>) -> String:
  match m:
    case Some{ys}: vd_text(ys)
    case None{}: "none"

# The record is spelled through a helper because the SIX fields are all defaulted
# and only `params` is under test; `P.ProgramInfo.of()` supplies the three `(1,1,1)`s
# and the three empty lists, and a six-field LITERAL here would be a second copy of
# a default that already has a name.
def vd.pi.of(pi: P.ProgramInfo, xs: List<&2, U32>) -> P.ProgramInfo:
  match pi:
    case P.ProgramInfo{g, l, _v, go, o, i, tg}: P.ProgramInfo{g, l, xs, go, o, i, tg}

def vd.pi(xs: List<&2, U32>) -> P.ProgramInfo: vd.pi.of(P.ProgramInfo.of(), xs)

def vd_row(nm: String, +ar: P.Arena, v: P.VarVals, xs: List<&2, U32>) -> IO(Unit):
  +pi = vd.pi(xs)
  P.srow(nm, vd_show(ProgramInfo.vals(ar, v, pi)))

def vd_rows(+ar: P.Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- vd_row("vv_two", ar, vd_put("j", H.i64_of_i32(9), vd_put("i", H.i64_of_i32(7), P.VarVals.new())), [1, 2])
    b : Unit <- vd_row("vv_one", ar, vd_put("i", H.i64_of_i32(7), P.VarVals.new()), [1])
    c : Unit <- vd_row("vv_zero", ar, vd_put("i", H.i64_of_i32(0), P.VarVals.new()), [1])
    d : Unit <- vd_row("vv_none", ar, P.VarVals.new(), Nil{})
    vd_row("vv_miss_second", ar, vd_put("i", H.i64_of_i32(7), P.VarVals.new()), [1, 2])

# ===========================================================================
# `ProgramInfo.launch_dims` -- ops.py:1352 -- AND `P.ProgramInfo.from_sink`
# -- ops.py:1358. the two methods upstream's `P.ProgramInfo` has at the PIN.
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
# ===========================================================================

def fs.srcs(ar: P.Arena, u: U32) -> List<&2, U32>:
  P.Arena.srcs(ar, u)

# the PARAM list holds `P.PSlot` and not the node INDEX, because the sort key is
# the PARAM's SLOT and `List.sort`'s comparator must be a TOP-LEVEL DEF: a
# closure is affine and `List.sort` calls its comparator once per comparison,
# so a comparator that reads the arena cannot be a closure. The key therefore
# travels BESIDE the value.

# the comparator's parameters are named `a` and `b` and not `x` and `y`,
# because `List.sort`'s comparator is a TEMPLATE and it is INLINED into
# `List.merge.go`, whose own pattern binders are `x` and `y`.
def PSlot.le(a: P.PSlot, b: P.PSlot) -> Bool:
  match a b:
    case P.PSlot{slot, node} P.PSlot{s2, n2}: U32.is_le(slot, s2)

# A PARAM's SLOT and whether it is an ALU one -- the two facts `from_sink` asks
# of a PARAM.

# UPSTREAM'S `_params`, `_globals`, `outs` AND `ins`, IN ONE RECORD. `params`
# holds the PARAM node INDICES (upstream holds the UOps, and the port's
# `P.ProgramInfo.params` is `List<&2, U32>`), `globals`/`outs`/`ins` hold SLOTS.

# THE TWO LAUNCH-SIZE TRIPLES. It is also the ANSWER TYPE of `launch_dims`,
# because a pair is not a `Type` this language can return and upstream's
# `launch_dims` returns a pair.

# `outs` AND `ins` TOGETHER, because upstream's default (`if not outs and not
# ins: outs = ins = _globals`) sets BOTH at once.

# `launch_dims` -- `global_size = tuple([sym_infer(sz, var_vals) for sz in
# self.global_size])` and the same for `local_size`.
#
# `sym_infer` (ops.py:95) IS THE IDENTITY ON AN INT, and `UOp.sym_infer`
# (ops.py:1169) EVALUATES RENDERED SOURCE WITH `exec` -- the port's `sym_infer`
# WALL, named at this file's `TODO(p3) ops.py:1169 def sym_infer` and at
# `uop/fold.bend:6590 symbol=main`. SO THE PORT'S `launch_dims` IS EXACT FOR EVERY
# `P.ProgramInfo` the port can build and not one more: the port's `global_size`
# and `local_size` are `List<&2, H.I64>`, so their elements are INTS.
#
# that is the port's shape and not a shortcut. Upstream's `global_size` is
# `tuple[int|float, ...]` and its `from_sink` puts a UOp in it when a launch
# size is SYMBOLIC -- MEASURED, the `fs_special_sym` row of
# `.agents/slop/programinfo/oracle.py` reads
#     global_size=(UOp(Ops.CAST, arg=dtypes.weakint, src=(UOp(Ops.PARAM,
#       arg=P.ParamArg(-1, dtypes.i32, vmin_vmax=(1, 10), name='nn',
#       addrspace=AddrSpace.ALU),)),), 1, 1)
# and the port's `from_sink` REFUSES that sink rather than pretend the size is
# 1. So every `P.ProgramInfo` the port can build has INT sizes, and `sym_infer`
# on an int is the identity on all of them.
#
# so the variable values are not read here, and that is the one thing this
# method does not do. `var_vals` is upstream's parameter and it is the SEAM:
# `sym_infer` lands HERE.
def ProgramInfo.launch_dims(v: P.VarVals, +x: P.ProgramInfo) -> P.Sz:
  P.Sz{P.ProgramInfo.global_size(x), P.ProgramInfo.local_size(x)}

# ---------------------------------------------------------------------------
# `from_sink` -- ops.py:1358.
#
#     @staticmethod
#     def from_sink(sink:UOp, target:Target=Target()) -> P.ProgramInfo:
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
#       return P.ProgramInfo(tuple(global_size), tuple(local_size),
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
# ---------------------------------------------------------------------------

# ==== the `fs_*` fixture and rows =========================================
#
# the fixture is one arena with every node in it, and each fixture is a sink
# over a different set of them. THE NODE MAP IS BELOW, and the indices are the
# positions in the arena's node list (`P.Arena.empty` spends slot 0 on the
# bottom, so node k is at index k).
#
#   0  bottom            1  PARAM slot 0 GLOBAL      "g0"
#   2  PARAM slot 1 GLOBAL      "g1"          3  PARAM slot 2 GLOBAL  "g2"
#   4  PARAM slot 3 GLOBAL      "g3"          5  PARAM slot 2 ALU "b"
#   6  PARAM slot 3 ALU "c"     7  PARAM slot 1 ALU "a"
#   8  CONST 0           9  CONST 1          10  CONST 16        11  CONST 4
#  12  INDEX (1, 8)     13  INDEX (2, 8)     14  INDEX (3, 8)     15  INDEX (4, 8)
#  16  STORE (12, 9)    17  LOAD (13)        18  STORE (14, 9)    19  LOAD (15)
#  20  CAST (12)        21  STORE (20, 9)    22  SHRINK (1)       23  STORE (22, 9)
#  24  SPECIAL (10) "g0"     25  SPECIAL (11) "l0"    26  SPECIAL (5) "g0"
#  27  SINK ()          28  SINK (8)         29  SINK (5)         30  SINK (1)
#  31  SINK (16)        32  SINK (17)        33  SINK (18, 19)    34  SINK (6, 7, 5)
#  35  SINK (1, 1)      36  SINK (24, 25)    37  SINK (26)        38  SINK (21)
#  39  SINK (23)        40  PARAM slot 0 GLOBAL "h"   41  SINK (1, 40)
#
# every fixture is one of the ways `from_sink` could be wrong, and each has a
# CPython row with the same name in `.agents/slop/programinfo/oracle.py`:
#
#   fs_empty        A SINK WITH NO SRCS AT ALL -- no params, no sizes.
#   fs_noparam      A SINK WHOSE ONLY SRC IS A CONST -- no PARAM anywhere.
#   fs_alu          A SINK WITH ONE ALU PARAM: `params` holds it and `globals`
#                   does not, so the ALU/GLOBAL SPLIT IS VISIBLE.
#   fs_global       A SINK WITH ONE GLOBAL PARAM and no STORE or LOAD: upstream's
#                   `if not outs and not ins: outs = ins = _globals` fires.
#   fs_store        A STORE into INDEX(PARAM) -- `outs`.
#   fs_load         A LOAD out of INDEX(PARAM) -- `ins`.
#   fs_store_load   BOTH, so `outs` and `ins` are separate and sorted.
#   fs_order        THREE ALU PARAMs WITH SLOTS 3, 1, 2 -- the SORT.
#   fs_dup          THE SAME PARAM TWICE -- the toposort's cache.
#   fs_dupslot      two params with the same slot -- the dedup of the slot lists
#                   (`sorted(dedup(_globals))`), which `fs_dup` cannot reach
#                   because the toposort visits a node once.
#   fs_special      TWO SPECIALs, "g0" over 16 and "l0" over 4 -- the sizes.
#   fs_special_sym  A SPECIAL OVER A VARIABLE -- the SYMBOLIC case, which the
#                   port REFUSES and CPython answers with a UOp in `global_size`.
#   fs_cast_index   A STORE of a CAST of an INDEX -- the CAST arm.
#   fs_shrink       A STORE of a SHRINK -- the SHRINK arm.
def fs.gparam(slot: U32) -> P.ParamArg:
  P.ParamArg.of(slot, S.int32())

# AN ALU PARAM WITH A SLOT AND A NAME: `UOp.param(slot, dtype, name=nm,
# addrspace=AddrSpace.ALU, vmin_vmax=(1, 10))`.
# A GLOBAL PARAM WITH A NAME. It is a DIFFERENT NODE from `fs.gparam(0)` --
# the intern key is (op, src, arg, tag) and the NAME is IN THE ARG -- and it has
# the SAME SLOT, which is what makes `fs_dupslot` the row the DEDUP needs.
def fs.gparam_named(slot: U32, nm: String) -> P.ParamArg:
  P.ParamArg{slot, S.int32(), None{}, None{}, Some{nm}, S.AGlobal{}, None{}, False{}, None{}, None{}, False{}, None{}}

def fs.aparam(slot: U32, nm: String) -> P.ParamArg:
  P.ParamArg{slot, S.int32(), Some{P.PyRange{H.i64_of_i32(1), H.i64_of_i32(10)}}, Some{1}, Some{nm},
    S.Aalu{}, None{}, False{}, None{}, None{}, False{}, None{}}

def fs.ar() -> P.Arena:
  P.Arena{[
    P.Arena.bottom(),
    P.Node{P.OpsPARAM{}, Nil{}, P.AParam{fs.gparam(0)}, P.TNone{}},
    P.Node{P.OpsPARAM{}, Nil{}, P.AParam{fs.gparam(1)}, P.TNone{}},
    P.Node{P.OpsPARAM{}, Nil{}, P.AParam{fs.gparam(2)}, P.TNone{}},
    P.Node{P.OpsPARAM{}, Nil{}, P.AParam{fs.gparam(3)}, P.TNone{}},
    P.Node{P.OpsPARAM{}, Nil{}, P.AParam{fs.aparam(2, "b")}, P.TNone{}},
    P.Node{P.OpsPARAM{}, Nil{}, P.AParam{fs.aparam(3, "c")}, P.TNone{}},
    P.Node{P.OpsPARAM{}, Nil{}, P.AParam{fs.aparam(1, "a")}, P.TNone{}},
    P.Node{P.OpsCONST{}, Nil{}, P.APy{P.CInt{H.i64_of_i32(0)}}, P.TNone{}},
    P.Node{P.OpsCONST{}, Nil{}, P.APy{P.CInt{H.i64_of_i32(1)}}, P.TNone{}},
    P.Node{P.OpsCONST{}, Nil{}, P.APy{P.CInt{H.i64_of_i32(16)}}, P.TNone{}},
    P.Node{P.OpsCONST{}, Nil{}, P.APy{P.CInt{H.i64_of_i32(4)}}, P.TNone{}},
    P.Node{P.OpsINDEX{}, [1, 8], P.ANone{}, P.TNone{}},
    P.Node{P.OpsINDEX{}, [2, 8], P.ANone{}, P.TNone{}},
    P.Node{P.OpsINDEX{}, [3, 8], P.ANone{}, P.TNone{}},
    P.Node{P.OpsINDEX{}, [4, 8], P.ANone{}, P.TNone{}},
    P.Node{P.OpsSTORE{}, [12, 9], P.ANone{}, P.TNone{}},
    P.Node{P.OpsLOAD{}, [13], P.ANone{}, P.TNone{}},
    P.Node{P.OpsSTORE{}, [14, 9], P.ANone{}, P.TNone{}},
    P.Node{P.OpsLOAD{}, [15], P.ANone{}, P.TNone{}},
    P.Node{P.OpsCAST{}, [12], P.ADt{S.int32()}, P.TNone{}},
    P.Node{P.OpsSTORE{}, [20, 9], P.ANone{}, P.TNone{}},
    P.Node{P.OpsSHRINK{}, [1], P.ATuple{Nil{}}, P.TNone{}},
    P.Node{P.OpsSTORE{}, [22, 9], P.ANone{}, P.TNone{}},
    P.Node{P.OpsSPECIAL{}, [10], P.AStr{"g0"}, P.TNone{}},
    P.Node{P.OpsSPECIAL{}, [11], P.AStr{"l0"}, P.TNone{}},
    P.Node{P.OpsSPECIAL{}, [5], P.AStr{"g0"}, P.TNone{}},
    P.Node{P.OpsSINK{}, Nil{}, P.AKernel{P.KernelInfo.of()}, P.TNone{}},
    P.Node{P.OpsSINK{}, [8], P.AKernel{P.KernelInfo.of()}, P.TNone{}},
    P.Node{P.OpsSINK{}, [5], P.AKernel{P.KernelInfo.of()}, P.TNone{}},
    P.Node{P.OpsSINK{}, [1], P.AKernel{P.KernelInfo.of()}, P.TNone{}},
    P.Node{P.OpsSINK{}, [16], P.AKernel{P.KernelInfo.of()}, P.TNone{}},
    P.Node{P.OpsSINK{}, [17], P.AKernel{P.KernelInfo.of()}, P.TNone{}},
    P.Node{P.OpsSINK{}, [18, 19], P.AKernel{P.KernelInfo.of()}, P.TNone{}},
    P.Node{P.OpsSINK{}, [6, 7, 5], P.AKernel{P.KernelInfo.of()}, P.TNone{}},
    P.Node{P.OpsSINK{}, [1, 1], P.AKernel{P.KernelInfo.of()}, P.TNone{}},
    P.Node{P.OpsSINK{}, [24, 25], P.AKernel{P.KernelInfo.of()}, P.TNone{}},
    P.Node{P.OpsSINK{}, [26], P.AKernel{P.KernelInfo.of()}, P.TNone{}},
    P.Node{P.OpsSINK{}, [21], P.AKernel{P.KernelInfo.of()}, P.TNone{}},
    P.Node{P.OpsSINK{}, [23], P.AKernel{P.KernelInfo.of()}, P.TNone{}},
    P.Node{P.OpsPARAM{}, Nil{}, P.AParam{fs.gparam_named(0, "h")}, P.TNone{}},
    P.Node{P.OpsSINK{}, [1, 40], P.AKernel{P.KernelInfo.of()}, P.TNone{}}], [0]}

# the printers. a U32 list, an I64 list, and the target.
def fs.u32_text.go(+ys: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ys:
    case Nil{}: acc
    case h <> t: fs.u32_text.go(t, List.append(&2, String, acc, [U32.show(h)]))

def fs.u32_text(ys: List<&2, U32>) -> String:
  String.concat(["(", String.join(fs.u32_text.go(ys, Nil{}), ", "), ")"])

def fs.i64_text.go(+ys: List<&2, H.I64>, +acc: List<&2, String>) -> List<&2, String>:
  match ys:
    case Nil{}: acc
    case h <> t: fs.i64_text.go(t, List.append(&2, String, acc, [P.fs.i64_dec(h)]))

def fs.i64_text(ys: List<&2, H.I64>) -> String:
  String.concat(["(", String.join(fs.i64_text.go(ys, Nil{}), ", "), ")"])

def fs.target_text(t: H.Target) -> String:
  match t:
    case H.Target{device, renderer, arch, iface, indices}:
      String.concat(["('", device, "', '", renderer, "', '", arch, "', '", iface, "', '", indices, "')"])

# the slots of the PARAM nodes. `P.ProgramInfo.params` holds the node indices --
# upstream holds the UOps -- and the row prints the SLOTS, because a node index
# is an artefact of the arena and a slot is the fact.
def fs.pslot(ar: P.Arena, u: U32) -> U32:
  Maybe.default(&2, U32, P.fs.slot(ar, u), 0)

def fs.pslots.go(+ar: P.Arena, xs: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case h <> t: fs.pslots.go(ar, t, List.append(&2, U32, acc, [fs.pslot(ar, h)]))

def fs.pslots(ar: P.Arena, xs: List<&2, U32>) -> List<&2, U32>:
  fs.pslots.go(ar, xs, Nil{})

# THE ROW. `global_size`, `local_size`, `params`, `globals`, `outs`, `ins` AND
# `target` -- upstream's SEVEN fields, in upstream's order.
def fs.show(+ar: P.Arena, +pi: P.ProgramInfo) -> String:
  String.concat([
    "global_size=", fs.i64_text(P.ProgramInfo.global_size(pi)),
    " local_size=", fs.i64_text(P.ProgramInfo.local_size(pi)),
    " params=", fs.u32_text(fs.pslots(ar, P.ProgramInfo.params(pi))),
    " globals=", fs.u32_text(P.ProgramInfo.globals(pi)),
    " outs=", fs.u32_text(P.ProgramInfo.outs(pi)),
    " ins=", fs.u32_text(P.ProgramInfo.ins(pi)),
    " target=", fs.target_text(P.ProgramInfo.target(pi))])

def fs.row.of(m: Maybe<&2, P.ProgramInfo>, nm: String, +ar: P.Arena) -> IO(Unit):
  match m:
    case None{}: P.srow(nm, "REFUSED")
    case Some{pi}: P.srow(nm, fs.show(ar, pi))

def fs.row(nm: String, +ar: P.Arena, sink: U32) -> IO(Unit):
  fs.row.of(P.ProgramInfo.from_sink(ar, sink, H.Target.of()), nm, ar)

def fs.rows(+ar: P.Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- fs.row("fs_empty", ar, 27)
    b : Unit <- fs.row("fs_noparam", ar, 28)
    c : Unit <- fs.row("fs_alu", ar, 29)
    d : Unit <- fs.row("fs_global", ar, 30)
    e : Unit <- fs.row("fs_store", ar, 31)
    f : Unit <- fs.row("fs_load", ar, 32)
    g : Unit <- fs.row("fs_store_load", ar, 33)
    h : Unit <- fs.row("fs_order", ar, 34)
    i : Unit <- fs.row("fs_dup", ar, 35)
    j : Unit <- fs.row("fs_special", ar, 36)
    k : Unit <- fs.row("fs_special_sym", ar, 37)
    l : Unit <- fs.row("fs_cast_index", ar, 38)
    m : Unit <- fs.row("fs_shrink", ar, 39)
    fs.row("fs_dupslot", ar, 41)

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
# `argfix_seq` (helpers.bend:547-554), one def per arity.
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

# `val` is a node, because `argfix`/`P.UOp.const` turns a bare Python int into one
# before this point and the port takes the CONST. The `set_val_int` row is what
# proves the CAST was folded upstream of here rather than here.
# THE ARENA IS THREADED, NOT REUSED, and the first draft reused it:
#   +e = P.UOp.end(ar, P.Found.i(s), ...)   -- `ar`, the CALLER's
# `P.UOp.store` MINTS, so `s` lives in a GROWN arena and `P.Found.i(s)` read out of
# `ar` is an index into the wrong arena. It typechecked and answered
# `Ops.AFTER(Ops.BUFFER Ops.AFTER)` where CPython answers
# `Ops.AFTER(Ops.BUFFER Ops.STORE)` -- the stale node read back as whatever the
# caller's arena holds at that index, which is exactly the failure mode
# `bend2-constraints` names and `P.UOp.copy_to_device` above demonstrates the fix
# for. Every step takes the PREVIOUS step's `P.Found.ar`.
def UOp.set(+ar: P.Arena, +self: U32, val: U32, end: Maybe<&2, List<&2, U32>>) -> P.Found:
  +s = P.UOp.store(ar, self, val, None{})
  +e = P.UOp.end(P.Found.ar(s), P.Found.i(s), UOp.set.end(end))
  P.UOp.after(P.Found.ar(e), P.Arena.src(P.Found.ar(s), self, 0), [P.Found.i(e)])

# ==== the `set_*` fixture and rows =========================================
#
# The subject is a STORE over a BUFFER, because `UOp.set` reads `self.src[0]`. P.Node 3
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
def set_pa(slot: U32) -> P.ParamArg: P.ParamArg.of(slot, S.int32())

def set_ar() -> P.Arena:
  P.Arena{[
    P.Arena.bottom(),
    P.Node{P.OpsBUFFER{}, Nil{}, P.AParam{set_pa(1)}, P.TNone{}},
    P.Node{P.OpsCONST{}, Nil{}, P.APy{P.CInt{H.i64_of_i32(1)}}, P.TNone{}},
    P.Node{P.OpsSTORE{}, [1, 2], P.ANone{}, P.TNone{}},
    P.Node{P.OpsCONST{}, Nil{}, P.APy{P.CInt{H.i64_of_i32(7)}}, P.TNone{}},
    P.Node{P.OpsCONST{}, Nil{}, P.APy{P.CInt{H.i64_of_i32(9)}}, P.TNone{}},
    P.Node{P.OpsCONST{}, Nil{}, P.APy{P.CInt{H.i64_of_i32(3)}}, P.TNone{}}], [0]}

# the printer is `P.Rng.srcops.seeded` (ops.bend:6101) and not a new one. It folds
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
# the node itself is part of the row. `P.Rng.srcops.seeded(ar, xs)` prints the ops of
# a SRC LIST, so passing `P.Arena.srcs(ar, i)` answers the CHILDREN and the answer's own
# op never appears -- the first run printed `Ops.BUFFER Ops.AFTER` where CPython
# prints `AFTER(...)`, and the missing AFTER is the whole of what the row is for.
# The concat puts the node's own name in front of its children.
# NO TRAILING SEPARATOR, and the first draft emitted one -- `Ops.AFTER(Ops.BUFFER
# Ops.STORE )` against CPython's `Ops.AFTER(Ops.BUFFER Ops.STORE)`. The separator is
# appended BEFORE each element rather than after, which is the same thing
# `P.Rng.srcops.go`'s `+first` flag does and for the same reason.
def set_deep.go(+ar: P.Arena, xs: List<&2, U32>, +acc: String, first: Bool) -> String:
  match xs:
    case Nil{}: acc
    case +i <> t:
      set_deep.go(ar, t, Bool.pick(String, first, String.concat([acc, P.Ops.name(P.Arena.op(ar, i))]),
        String.concat([acc, " ", P.Ops.name(P.Arena.op(ar, i))])), False{})

def set_deep(+ar: P.Arena, +i: U32) -> String:
  String.concat([P.Ops.name(P.Arena.op(ar, i)), "(", set_deep.go(ar, P.Arena.srcs(ar, i), "", True{}), ")"])

def set_row(nm: String, +ar: P.Arena, subj: U32, val: U32, end: Maybe<&2, List<&2, U32>>) -> IO(Unit):
  +f = UOp.set(ar, subj, val, end)
  P.srow(nm, set_deep(P.Found.ar(f), P.Found.i(f)))

def set_rows(+ar: P.Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- set_row("set_end_none", ar, 3, 4, None{})
    b : Unit <- set_row("set_end_one", ar, 3, 4, Some{[5]})
    c : Unit <- set_row("set_end_two", ar, 3, 4, Some{[5, 6]})
    set_row("set_end_two_src", ar, 3, 4, Some{[6, 5]})

# ===========================================================================
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
# and the port's `arg` carries that TYPE in itself -- `P.APy{P.CBool{…}}` and `P.APy{P.CInt{…}}` are
# different `P.Arg` values and `P.ANone{}` is a third -- so the port can answer the question, and
# the three rows below ask it at the top level of `arg`, which the `pynest_*` rows ask one
# level deep (inside `P.ParamArg.val`) and the `const_bool_vs_int_splits` row asks about a
# CONST's DTYPE-KEY.
#
# AND CPYTHON's OWN ANSWERS, MEASURED AT THE PIN: `arg=True` vs `arg=1` is False (the
# types differ), `arg=True` vs `arg=False` is False, `arg=None` vs `arg=0` is False
# (`NoneType` is not `int`), `arg=True` vs `arg=True` is True, `arg=1` vs `arg=1` is
# True, `arg=None` vs `arg=None` is True.
# ===========================================================================

# ===========================================================================
# `P.UOp.divide_exact` -- ops.py:1038-1047. AND CPYTHON's OWN `P.UOp.divide_exact` IS THE
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
# ===========================================================================

def main() -> IO(Unit):
  do IO<Unit>:
    u0 : Unit <- set_rows(set_ar())
    x0 : Unit <- vd_rows(vd_arena())
    w1 : Unit <- fs.rows(fs.ar())
    y0 : Unit <- vrn_rows(P.Arena.empty())
    w0 : Unit <- rra.rows(rra.arena())
    v0 : Unit <- vr.expr.rows(vr.arena())
    a0 : Unit <- sg.rows()
    z : Unit <- s5.rows()
    a : Unit <- row("ctr_bump", P.t_ctr_bump())
    a1 : Unit <- row("ctr_find", P.t_ctr_find())
    a4 : Unit <- row("ctr_inter", P.t_ctr_inter())
    g0 : Unit <- row("gcd_const", P.t_gcd_const())
    g1 : Unit <- row("gcd_shared", P.t_gcd_shared())
    d0 : Unit <- row("de_same", P.t_de_same())
    d1 : Unit <- row("de_const_none", P.t_de_const_none())
    d2 : Unit <- row("de_mul", P.t_de_mul())
    d3 : Unit <- row("de_const_out", P.t_de_const_out())
    a : Unit <- row("hashcons", P.t_hashcons())
    a2 : Unit <- row("float_zeros_differ", P.t_float_zeros_differ())
    a3 : Unit <- row("float_nan_interns", P.t_float_nan_interns())
    b : Unit <- row("dtype_key", P.t_dtype_key())
    c : Unit <- row("cycle", P.t_cycle())
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
    # --- THE P.CustomFunction LANE. ops.py:1394/1258. `eq_customfunction` and
    # --- `P.CustomFunction.of` had no row, so three mutations of them moved nothing.
    row("cfun_interns", t_cfun_interns())
    row("cfun_dtype_splits", t_cfun_dtype_splits())
    row("cfun_name_splits", t_cfun_name_splits())
    P.srow("cfun_arg", t_cfun_arg())
    P.srow("cfun_of", cfun_of_str())
    # --- THE BLOB LANE. ops.py:201. `ABlob` is the intern key's bytes half and it
    # --- compared the LENGTH, so two different same-length blobs were ONE node.
    row("blob_interns", t_blob_interns())
    row("blob_len_diff_content", t_blob_len_diff_content())
    row("blob_diff_len", t_blob_diff_len())
    P.srow("blob_count_same", s_blob_count_same())
    P.srow("blob_count_len_diff_content", s_blob_count_len_diff_content())
    P.srow("blob_shape", s_blob_shape())
    P.srow("blob_content", s_blob_content())
    row("blob_sweep", t_blob_sweep())
    P.srow("blob_sweep_count", s_blob_sweep_count())
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
    row("const_bool_vs_int_splits", P.t_const_bool_vs_int_splits())
    # --- THE NESTED LANE, the second instance of the same over-split: `P.ParamArg.val` is a
    # --- `PyConst` INSIDE `arg`, so `type(arg)` does not separate a bool from an int there.
    row("pynest_bool_vs_int_interns", P.t_pynest_bool_vs_int_interns())
    row("pynest_int_distinct_interns", P.t_pynest_int_distinct_interns())
    row("pynest_none_vs_zero_interns", P.t_pynest_none_vs_zero_interns())
    row("pynest_signed_zero_interns", P.t_pynest_signed_zero_interns())
    row("pynest_cfloat_vs_int_interns", P.t_pynest_cfloat_vs_int_interns())
    row("tag_bool_vs_int_interns", t_tag_bool_vs_int_interns())
    row("tag_true_vs_false_splits", t_tag_true_vs_false_splits())
    row("tag_none_vs_zero_interns", t_tag_none_vs_zero_interns())
    # --- THE AXIS CPYTHON LANE. `#bend_only_mstack_puts_self_first` first, because it is
    # --- the row this file was MISSING: `P.UOp.after` and `P.UOp.end` had rows and
    # --- `P.UOp.mstack` had the same inverse bug fixed in the same commit with none, so a
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
    P.srow("axlt_sorted", ax_names_str(List.sort(P.AxisType, P.AxisType.lt, AxisType.live())))
    P.srow("axlt_revsorted", ax_names_str(RevAxis.go(List.reverse(&2, P.AxisType, AxisType.live()), Nil{})))
    P.srow("axlt_lt", Bool.show(P.AxisType.lt(P.AXIS_LOOP{}, P.AXIS_WEAK{})))
    P.srow("axlt_gt", Bool.show(P.AxisType.lt(P.AXIS_WEAK{}, P.AXIS_LOOP{})))
    P.srow("eqax_collide", U32.show(EqAx.collide(AxisType.live())))
    P.srow("eqax_collide_all", U32.show(EqAx.collide(P.AxisType.all())))
    P.srow("eqax_diag", U32.show(EqAx.diag(AxisType.live())))
    P.srow("eqax_diag_all", U32.show(EqAx.diag(P.AxisType.all())))
    t_mstack_rows()
    # CPython `is` on the two args `ARange` flattens together. ops.py:201, :643.
    row("uc_flat_nest", Uc.same(0, 1, [0, 1]))
    row("uc_int_tup1", Uc.same(0, 1, [0]))
    row("uc_nest_deep", Uc.same(1, 2, [0, 1]))
    row("uc_flat_same", Uc.same(0, 0, [0, 1]))
    row("uc_nest_same", Uc.same(1, 1, [0, 1]))
    P.srow("ucdepth_flat_nest", Uc.depth(0, 1, [0, 1]))
    # --- THE BACKWARD-SLICE LANE. ops.py:280/286/289, ported above `pm_r_sink`.
    P.srow("bsl_chain", Bsl.chain())
    P.srow("bsws_chain", Bsl.chain.ws())
    P.srow("bsop_chain_add", Bsl.chain.add())
    P.srow("bsop_chain_mul", Bsl.chain.mul())
    P.srow("bsl_call", Bsl.call())
    P.srow("bsws_call", Bsl.call.ws())
    P.srow("bsop_call_call", Bsl.call.call())
    P.srow("bsl_nest", Bsl.nest())
    P.srow("bsws_nest", Bsl.nest.ws())
    P.srow("bsop_nest_pair", Bsl.nest.pair())
    P.srow("bsl_backedge", Bsl.backedge())
    P.srow("bsws_backedge", Bsl.backedge.ws())
    P.srow("bsop_backedge_backedge", Bsl.backedge.be())
    P.srow("bsop_backedge_range", Bsl.backedge.range())

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
#     source location. That is CPython's frame stack, and every `P.UPat` carries
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
#     `canonicalize_device` -- the device memory layer. P6, and `P.ParamArg.buffer`
#     is the slot they all read.
#   `Estimates` in `P.KernelInfo` -- PORTED 2026-10-30 as a FIELD, in
#     `renderer/estimates.bend`. What is NOT PORTED is the VALUE: upstream's
#     only writer is `codegen/__init__.py:446` and `do_estimates` is a WALL in
#     `codegen/kernel.bend`, so every `P.KernelInfo` the port builds carries
#     `estimates=None`.
#   `P.CustomFunction` -- PORTED 2026-10-03, at ops.py's own position (between
#     `OPAQUE_CALL_BODIES` and `P.CallInfo`), together with `P.Arg`'s `ACustom` arm,
#     `eq_customfunction` and `P.UOp.custom_function`. The old text here said it was
#     PORTABLE but unreachable and so would "land with" the P6 hcq2 work; it landed
#     without it, because `uop/spec.py:110`'s `isinstance(x.arg, P.CustomFunction)`
#     needs the datatype and `spec.bend`'s `sh_22` is stale until it has one. Being
#     P6 only ever described the CALLERS, never the type.
#     what is still open is the other half, and it is not optional: upstream moved
#     `P.CallInfo.dtype` into `P.CustomFunction.dtype`, so a CALL's return dtype now
#     lives on its CUSTOM_FUNCTION body (`dtype_from_uop`'s CALL arm is
#     `return src[0].dtype`). `P.CallInfo` here STILL HAS `dtype`, and it is still
#     read by `eq_callinfo` and by `uop/spec.bend`'s `arg_call`/`sh_23`. So the
#     re-cut is a SEPARATE change with its own blast radius, not a field delete:
#     `sh_23` compares a DECLARED dtype against the node's own, and under HEAD
#     there is no declared dtype to compare -- the CALL's dtype IS its body's. P3,
#     with `dtype_from_uop`.
#     MEASURED 2026-10-06, so the next reader does not have to re-derive it: the
#     eleven-site, seven-file delete is APPLIED AND GREEN in a scratch copy of this
#     tree, it moves `--graph loop`'s `arg` chunk to CPython's bytes, and it closes
#     HALF the row -- `dtype` and `shape` stay `?` because `fold.bend` never settles
#     that node, which is a second defect. See the `P.CallInfo` block above for the
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
#   `grad_fxn` in `P.CallInfo` and `uopfunc` -- a Python function object; a Bend
#     closure is single-use and is a `Type`, so it cannot be a `Data` field.
#     The reverse-mode plumbing is `tinygrad/nn/gradient.py`, P7.
#   `aux` in `P.CallInfo` and `trace_num` -- the per-call side channel, written by
#     the hcq paths in `tinygrad/runtime/ops_*.py`, which are out of scope.
#   `uopfunc`'s `inspect.signature(fn).bind(...)` -- Python reflection over a
#     function object, used to turn uop arguments into params. P7 with the mixin.
#   `is_any`, `custom_early_reject`, `allow_any_len`, `permutations` and
#     `functools.repeat` in `UPat.__init__`, and `upat_compile` -- the pattern
#     COMPILER (`tinygrad/uop/upat.py`). `P.UPat` is PORTED (see ops.py:1447, with
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
#   `Ops` reverse lookup (`Ops("ADD")`) and `P.AxisType` reverse lookup -- not
#     called by ops.py; `AxisType.of` is here anyway because `range_str` needs
#     a name and a test needs a name.



def head1(xs: List<&2, U32>) -> U32:
  match xs:
    case Nil{}: 0
    case x <> _: x

