# tinybendygrad/schedule/prepare.bend
# Port of tinygrad/schedule/prepare.py (278 lines). `prepare_rangeify`.
#
# WHAT THIS FILE IS, IN ONE PARAGRAPH. `prepare.py` is a SCHEDULING PASS: it
# takes a UOp graph and rewrites it into a form the device can run. Almost all of
# it is DECISION -- eleven functions and five `PatternMatcher`s, most of whose
# rules are lambdas -- and the decisions are arithmetic over SHAPES (a `prod`, a
# `src_prefix`, a `%` inside the split search, two itemsizes and a `rate`, an
# `argsort`) or over the ARENA (a `toposort` with a gate, a `base` reachability
# map, a `placed` substitution). What it BUILDS is a set of nodes through
# `UOp.store`, `.after`, `.index`, `.pad_to`, `.contiguous`, `.usum` and
# `UOp.unique_num`, and those builders are the wall named below.
#
# THE ORDER OF THE FILE IS PYTHON'S ORDER: `forward_call_outputs` (11-38),
# `walk_mop` (40-43), `found_after` (45-53) and its table (56-62), `_mop_index`
# (65-74) and `pm_mops` (76-83), then the "0. cleanup" block: the hazard pair
# (89-101), `split_reduceop` (103-125), `resolve_function` (127-150),
# `expand_bitcast` (153-162), the three materialisers (164-182),
# `pm_inline_calls` (184-187), `pm_disk_copy` (189-197), `earliest_rewrites`
# (199-269) and `prepare_rangeify` (271-278).
#
# ---------------------------------------------------------------------------
# THE SPLIT. Every rule body here is a DECISION: it answers "which arm, and
# with what arithmetic", and the node it would build is named at the call site.
# That is `agent-core.md`'s split with the trace side unused -- nothing in this
# file declares a foreign effect, and both lanes run it.
#
# ---------------------------------------------------------------------------
# THE WALLS. Six, each with the Python line that hits it. Nothing here is
# approximated and nothing here is faked: a row that cannot be computed prints
# the wall's name, so a diff can tell a wall from a value.
#
# W1. `graph_rewrite` -- ops.py:1611, called FOUR TIMES at prepare.py:274-277.
#     It is a fixpoint over a worklist: rewrite every node, push the result
#     back, repeat until nothing fires. Bend refuses mutual recursion and a
#     worklist with a REBUILT todo is not a subterm, so ONE pass per table is
#     the most this file can spell. The per-step rows are labelled `1p` (one
#     pass) and a one-pass row is not a fixpoint row.
# W2. `UOp.substitute` -- ops.py:1273, and `dict_map` / `dict_map.update` at
#     prepare.py:139-149. `forward_call_outputs`'s `placed` map and
#     `resolve_function`'s `flat_storage` are both substitutions, so both inherit
#     W1.
# W3. THE BUILDERS. `UOp.index`, `.after`, `.store`, `.contiguous`, `.pad_to`,
#     `.reshape`, `.permute`, `.shrink`, `.usum`, `.squeeze`, `.flatten`,
#     `.bitcast`, `.cast` and `UOp.unique_num` are ops.py:581-1040. `ops.bend`
#     has `UOp.after`, `UOp.new`, `UOp.group` and `UOp.alu` but NOT the
#     move-mixin half, so every rule whose body IS a builder is ported as its
#     DECISION: the arm, and the arithmetic that chose it.
# W4. `is_expanded` -- prepare.py:113-115. `indexed.substitute({x.base:NOOP},
#     extra_pm=pm_mops).ranges` needs `substitute` (W2) AND `pm_mops`'s own
#     rewrite (W1). `split_reduceop`'s candidate SEARCH takes the vector as a
#     PARAMETER and the oracle supplies it from tinygrad's own call, so the
#     search arithmetic is gated and the vector is the wall.
# W5. `resolve` -- ops.py:64, the arm that needs `UOp._min_max`. Called once in
#     this file, at prepare.py:113, inside W4 anyway.
# W6. `mop_cleanup` (uop/movement.py) and `create_allreduce_function`
#     (schedule/allreduce.py) and `multi_pm` (schedule/multi.py) are rule BODIES
#     of `earliest_rewrites` rules 0-8 and 9 and of the first `graph_rewrite`.
#     `movement.bend` HAS `mop_cleanup` and `allreduce.bend` HAS the selection,
#     but neither is imported: this file owns the TABLE and the DISPATCH, and a
#     body that lives in another file is named at the call site. Their RULES are
#     in the table and their DATA (`slen`/`rlen`/`nalts`/`rej`) is gated.
#
# `O.PMEntry` is `tag`/`ops`/`rej` and NOTHING ELSE (ops.bend:2966), so the
# oracle's `<t>_<k>_dt` and `_src` columns have no field to read: those are
# `UPat` facts (`match_dtype`, and the src permutation tuple at upat.py:47) and
# `UPat` does not survive into the compiled IR. `schedule/indexing.bend` records
# the same wall for its three tables.
#
# THE TABLES. Five `PatternMatcher`s plus `mop_cleanup`, which `earliest_rewrites`
# prepends (`prepare.py:199`), so SIX tables live here. `PatternMatcher.__add__`
# is `functools.cache`d over `(self.patterns + more.patterns)` (ops.py:1603), so
# a `+` composition is a CONCATENATION with a TAG SHIFT: `pm_mops` is 3 rules and
# `earliest_rewrites` is 29, so `pr_t_mix2` is `pm_mops` then `pm_inline_calls`
# then `pm_disk_copy` (3+2+2 = 7 rules, tags 0..6) and `pr_t_mix3` is `pm_mops`
# then `earliest_rewrites` (3+29 = 32 rules, tags 0..31). `ops.bend` cannot call
# a def in this file, so each table gets its own `try` / `scan` / `dispatch` --
# the same cost `uop/spec.bend` pays six times and `schedule/indexing.bend` three.
import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F

# ===========================================================================
# THE ROW PRINTER. One line per claim, `name=value`, so the differ reads whole
# lines and never compares row NAMES.
# ===========================================================================
def row(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

def rowb(nm: String, b: Bool) -> IO(Unit): row(nm, Bool.show(b))

def rowu(nm: String, v: U32) -> IO(Unit): row(nm, U32.show(v))

def b2u(b: Bool) -> U32: Bool.pick(U32, b, 1, 0)

def rowi(nm: String, b: Bool) -> IO(Unit): rowu(nm, b2u(b))

def len_u32(xs: List<&2, U32>) -> U32: U32.from_nat(List.length(&2, U32, xs))

def show_u32.go(+xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: show_u32.go(t, List.append(&2, String, acc, [U32.show(x)]))

def show_u32(+xs: List<&2, U32>) -> String: String.join(show_u32.go(xs, Nil{}), ",")

def ops_str.go(+xs: List<&2, O.Op>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: ops_str.go(t, List.append(&2, String, acc, [O.Ops.name.of(x)]))

def ops_str(+xs: List<&2, O.Op>) -> String: String.join(ops_str.go(xs, Nil{}), ",")

def len_ops(xs: List<&2, O.Op>) -> U32: U32.from_nat(List.length(&2, O.Op, xs))

# `O.Sint` is `SI{i64} | SU{u32}` and a shape dim is a `SInt`, so the two cases
# are the two cases. The rendering is `U32.show` for the unsigned arm and the
# I64 spelling for the signed one, and a `Data` match is the only way to read a
# sum type's arms.
# `H.i64_text` renders an I64 as `hi:lo` (helpers.bend:1232, "an I64 prints as its
# two words"), which is right for a 64-BIT pointer and wrong for a shape dim, where
# CPython prints the plain integer.  `H.i64_is_neg` / `H.i64_add` / `H.lo32` are
# the pieces, and a shape dim in this tree is either a small positive I64 or the
# ZERO sign-extended, so the rendering is the low word and a `-` for a negative.
def pr_sint_str(neg: Bool, +lo: U32) -> String:
  Bool.pick(String, neg, String.concat(["-", U32.show(lo)]), U32.show(lo))

def sint_str.go(s: O.Sint) -> String:
  match s:
    case O.SI{+i}: pr_sint_str(H.i64_is_neg(i), H.lo32(i))
    case O.SU{u}: U32.show(u)

def show_sints.go(+xs: List<&2, O.Sint>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: show_sints.go(t, List.append(&2, String, acc, [sint_str.go(x)]))

def shape_str.go(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> String:
  match m:
    case Some{Some{xs}}: String.join(show_sints.go(xs, Nil{}), "x")
    case Some{None{}}: "ERR"
    case None{}: "ERR"

def shape_str(+ar: O.Arena, +tb: F.Table, +self: U32) -> String:
  shape_str.go(F.fold.shape(ar, tb, self))

# THE GATE'S FOUR FACTS PLUS THE ANSWER AS ONE STRING. `toposort` SIZE and not
# arena size: the size of a node's OWN subgraph is graph-intrinsic, so it is the
# one number that survives the difference between CPython's arena and this one.
# The dtype is left out because `LAWS/spec.bend` has no `Dt.name` and a dtype is
# not one of the four facts; where a dtype MATTERS it is a row of its own.
def src_ops.go(+ar: O.Arena, +self: U32, ns: List<&2, Nat>, acc: List<&2, O.Op>) -> List<&2, O.Op>:
  match ns:
    case Nil{}: acc
    case n <> t:
      src_ops.go(ar, self, t, List.append(&2, O.Op, acc, [O.Arena.op(ar, O.Arena.src(ar, self, U32.from_nat(n)))]))


def topo_ops.go(+ar: O.Arena, +tb: F.Table, +ns: List<&2, U32>, acc: List<&2, O.Op>) -> List<&2, O.Op>:
  match ns:
    case Nil{}: acc
    case n <> t: topo_ops.go(ar, tb, t, List.append(&2, O.Op, acc, [O.Arena.op(ar, n)]))


def topo_ops(+ar: O.Arena, +tb: F.Table, +ns: List<&2, U32>) -> List<&2, O.Op>:
  topo_ops.go(ar, tb, ns, Nil{})


# `S.Dt`'s fourth field is the NAME (`LAWS/spec.bend:78`, `Dt{pri, bits, cls, nm}`)
# and CPython's `uop.dtype.name` is exactly it, so the dtype column is one binder and
# not a table -- which is the reason `sig4` can carry a dtype at all.
def dt_name(d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, nm}: nm

def dt_name.of(m: Maybe<&2, S.Dt>) -> String:
  match m:
    case Some{d}: dt_name(d)
    case None{}: "ERR"

def sig4(+fx: F.Folded, +self: U32) -> String:
  +ar = F.Folded.ar(fx)
  +tb = F.Folded.t(fx)
  String.join([
    U32.show(U32.from_nat(List.length(&2, U32, O.UOp.toposort(O.Arena.budget(ar), ar, self)))),
    O.Ops.name.of(O.Arena.op(ar, self)),
    U32.show(O.Arena.nsrc(ar, self)),
    ops_str(src_ops.go(ar, self, List.range(U32.to_nat(O.Arena.nsrc(ar, self))), Nil{})),
    shape_str(ar, tb, self),
    dt_name.of(F.fold.dt(ar, tb, self))
  ], "|")

# THE WALK ORDER, which for a scheduling pass is the point. Never a count.

def topo_str(+fx: F.Folded, +self: U32) -> String:
  +ar = F.Folded.ar(fx)
  +tb = F.Folded.t(fx)
  +ns = O.UOp.toposort(O.Arena.budget(ar), ar, self)
  ops_str(topo_ops(ar, tb, ns))

# ===========================================================================
# THE FIXTURE BUILDERS. `O.Found` is `ops.bend`'s `(arena, node)` pair, and a
# node is an arena INDEX, so every fixture is built once and the arena is what
# every reader sees.
# ===========================================================================

def pr_c(v: U32) -> O.Found: O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(v)})

# `ParamArg(slot, dtype, size, name, addrspace, device)` -- ops.py:696 read
# through `ops.bend:697`. A BUFFER's `src` is EMPTY in Python
# (`UOp(Ops.BUFFER, arg=...)`), so this is a 0-src node.

def pr_pa(slot: U32, size: U32, name: String, dev: U32) -> O.ParamArg:
  O.ParamArg{slot, S.int32(), Some{size}, None{}, None{}, Some{name}, S.AGlobal{},
    Some{S.D1{dev}}, False{}, None{}, None{}, False{}, None{}}


def pr_wm_same(self: U32, b: U32) -> Bool: U32.is_eq(b, self)

def pr_buf(+ar: O.Arena, slot: U32, size: U32, name: String, dev: U32) -> O.Found:
  O.UOp.new(ar, O.OpsBUFFER{}, Nil{}, O.AParam{pr_pa(slot, size, name, dev)}, O.TNone{})

def pr_range(+ar: O.Arena, n: U32, ax: U32) -> O.Found:
  +z = O.UOp.const(ar, O.CInt{H.i64_of_i32(n)})
  O.UOp.range_end(O.Found.ar(z), O.Found.i(z), [ax], O.AXIS_WEAK{})

def pr_c1(+ar: O.Arena, v: U32) -> O.Found: O.UOp.const(ar, O.CInt{H.i64_of_i32(v)})

# `UOp(Ops.STACK, src=(CONST(a), CONST(b)))` is `as_shape`'s tuple form (ops.py:811)
# and is what RESHAPE / PAD / SHRINK / EXPAND read at ops.py:816-817.  Two CONSTs
# with the SAME value HASH-CONS to one node, so `(2, 2)` is a one-constant stack and
# `(4, 1)` is a two-constant one -- which is why CPython's `(2, 2)` and `(0, 0)` are
# both single-constant stacks and this must be too.
# A ONE-ELEMENT STACK. `UOp(Ops.STACK, src=(CONST(4),))` -- `as_shape` on a bare
# CONST answers `(self.val,)` (ops.py:809) and reads the SAME shape, but CPython's
# `shp()` helper in the oracle builds a STACK and the SRC OP SEQUENCE is one of the
# four facts, so the node has to be the STACK the oracle built.
def pr_shp1(+ar: O.Arena, a: U32) -> O.Found:
  +z = pr_c1(ar, a)
  O.UOp.new(O.Found.ar(z), O.OpsSTACK{}, [O.Found.i(z)], O.ANone{}, O.TNone{})

def pr_shp2(+ar: O.Arena, a: U32, b: U32) -> O.Found:
  +z = pr_c1(ar, a)
  +y = pr_c1(O.Found.ar(z), b)
  O.UOp.new(O.Found.ar(y), O.OpsSTACK{}, [O.Found.i(z), O.Found.i(y)], O.ANone{}, O.TNone{})

# EVERY BUILDER TAKES THE ARENA FIRST AND USES *IT*, never the arena of one of its
# own arguments.  A builder that reads `O.Found.ar(x)` builds into the arena as it
# stood BEFORE `x` was interned, which silently interns the new node into a stale
# arena and makes every later index wrong -- and every later index is what the gate
# compares.  This cost one debug pass and is written here so it does not cost
# another: the arena is threaded top to bottom and a builder never invents one.
def pr_mov3(ar: O.Arena, op: O.Op, +x: O.Found, +o: O.Found, +s: O.Found) -> O.Found:
  O.UOp.new(ar, op, [O.Found.i(x), O.Found.i(o), O.Found.i(s)], O.ANone{}, O.TNone{})

def pr_pad(ar: O.Arena, +x: O.Found, +o: O.Found, +s: O.Found) -> O.Found:
  pr_mov3(ar, O.OpsPAD{}, x, o, s)

def pr_shrink(ar: O.Arena, +x: O.Found, +o: O.Found, +s: O.Found) -> O.Found:
  pr_mov3(ar, O.OpsSHRINK{}, x, o, s)

def pr_reshape(ar: O.Arena, +x: O.Found, +s: O.Found) -> O.Found:
  O.UOp.new(ar, O.OpsRESHAPE{}, [O.Found.i(x), O.Found.i(s)], O.ANone{}, O.TNone{})

def pr_expand(ar: O.Arena, +x: O.Found, +s: O.Found) -> O.Found:
  O.UOp.new(ar, O.OpsEXPAND{}, [O.Found.i(x), O.Found.i(s)], O.ANone{}, O.TNone{})

# PERMUTE and FLIP take their marg in the ARG (`ops.py:818`), not in srcs, and FLIP's
# is a bool TUPLE (`ops.py:430` refuses anything else) while PERMUTE's is an int
# tuple, and the arena now SPELLS the difference: `O.ABoolList` for FLIP,
# `O.ATuple` for PERMUTE.  `pr_flip` takes the int axis pair its caller has and
# converts, which is `movement.py:253`'s `i in axis_arg`.
def pr_perm(ar: O.Arena, +x: O.Found, +a: U32, b: U32) -> O.Found:
  O.UOp.new(ar, O.OpsPERMUTE{}, [O.Found.i(x)], O.ATuple{[a, b]}, O.TNone{})

def pr_flip(ar: O.Arena, +x: O.Found, a: U32, b: U32) -> O.Found:
  O.UOp.new(ar, O.OpsFLIP{}, [O.Found.i(x)], O.ABoolList{O.bools_of([a, b])}, O.TNone{})

# ---------------------------------------------------------------------------
# REPORTED, NOT USED: `ops.bend`'s `UOp.after` (ops.bend:2085) and `UOp.end`
# (ops.bend:2094) build `List.append(srcs, [self])`, which is `srcs ++ [self]`.
# `ops.py:621` is `src=(self,)+src` and `ops.py:619` is `src=(self,)+src`, so the
# two helpers put the node LAST where Python puts it FIRST.  That is an INVERTED
# FIELD ORDER and it is exactly the class of defect `agent-core.md` names
# ("`ops_cl`'s unit found `Sig`'s field names INVERTED"): an AFTER built by
# `ops.bend` has srcs `[END, BUFFER]` where CPython has `[BUFFER, END]`, and the
# four-facts gate sees it immediately.  `ops.bend` is READ-ONLY to this unit, so
# the two defs below build the node directly with Python's order and the defect is
# REPORTED for its owner.
def pr_end(ar: O.Arena, +x: O.Found) -> O.Found:
  O.UOp.new(ar, O.OpsEND{}, [O.Found.i(x)], O.ANone{}, O.TNone{})

def pr_after(ar: O.Arena, +self: O.Found, +e: O.Found) -> O.Found:
  O.UOp.new(ar, O.OpsAFTER{}, [O.Found.i(self), O.Found.i(e)], O.ANone{}, O.TNone{})

def pr_alu2(ar: O.Arena, op: O.Op, +a: O.Found, +b: O.Found) -> O.Found:
  O.UOp.alu(ar, op, [O.Found.i(a), O.Found.i(b)])

def pr_store(ar: O.Arena, +d: O.Found, +v: O.Found) -> O.Found:
  O.UOp.new(ar, O.OpsSTORE{}, [O.Found.i(d), O.Found.i(v)], O.ANone{}, O.TNone{})

def pr_sink(+a: O.Found) -> O.Found: O.UOp.sink(O.Found.ar(a), [O.Found.i(a)])

# ===========================================================================
# THE SIX TABLES, emitted by `.agents/slop/prep-gen-tables.py` from tinygrad's
# OWN `PatternMatcher` objects: `pat.op` IS `pdict`'s key (ops.py:1598) and
# `pat.early_reject` is ops.py:1477.  The comment on each entry is the rule's
# `strict_length` / `required_len` / `is_any` / `nalts` / `name`.
# ===========================================================================

def pr_fma_table() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0, [O.OpsAFTER{}], [O.OpsSTORE{}]},  # 0 AFTER rej=STORE slen=1 rlen=2 any=0 nalts=1 name=after
    O.PMEntry{1, [O.OpsSTAGE{}], Nil{}},  # 1 STAGE rej=- slen=1 rlen=1 any=0 nalts=1 name=after
    O.PMEntry{2, [O.OpsEXP2{}, O.OpsLOG2{}, O.OpsSIN{}, O.OpsSQRT{}, O.OpsRECIPROCAL{}, O.OpsNEG{}, O.OpsTRUNC{}, O.OpsADD{}, O.OpsMUL{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsCDIV{}, O.OpsMAX{}, O.OpsCMOD{}, O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsCMPEQ{}, O.OpsXOR{}, O.OpsOR{}, O.OpsAND{}, O.OpsTHREEFRY{}, O.OpsSUB{}, O.OpsFDIV{}, O.OpsPOW{}, O.OpsFLOORDIV{}, O.OpsFLOORMOD{}, O.OpsWHERE{}, O.OpsMULACC{}], Nil{}},  # 2 ADD AND CDIV CMOD CMPEQ CMPLT CMPNE EXP2 FDIV FLOORDIV FLOORMOD LOG2 MAX MUL MULACC NEG OR POW RECIPROCAL SHL SHR SIN SQRT SUB THREEFRY TRUNC WHERE XOR rej=- slen=0 rlen=0 any=0 nalts=0 name=alu
  ]}


def pr_mop_table() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0, [O.OpsINDEX{}], Nil{}},  # 0 INDEX rej=- slen=0 rlen=1 any=0 nalts=1 name=idx
    O.PMEntry{1, [O.OpsAFTER{}], Nil{}},  # 1 AFTER rej=- slen=0 rlen=1 any=0 nalts=1 name=a
    O.PMEntry{2, [O.OpsEND{}], Nil{}},  # 2 END rej=- slen=0 rlen=1 any=0 nalts=1 name=a
  ]}


def pr_inl_table() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0, [O.OpsCALL{}], Nil{}},  # 0 CALL rej=- slen=0 rlen=0 any=0 nalts=0 name=c
    O.PMEntry{1, [O.OpsAFTER{}], [O.OpsSINK{}]},  # 1 AFTER rej=SINK slen=0 rlen=2 any=0 nalts=1 name=-
  ]}


def pr_dsk_table() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0, [O.OpsCOPY{}], [O.OpsSTAGE{}]},  # 0 COPY rej=STAGE slen=1 rlen=1 any=0 nalts=1 name=copy
    O.PMEntry{1, [O.OpsCOPY{}], Nil{}},  # 1 COPY rej=- slen=1 rlen=1 any=0 nalts=1 name=copy
  ]}


def pr_ear_table() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0, [O.OpsSHRINK{}], [O.OpsSHRINK{}]},  # 0 SHRINK rej=SHRINK slen=0 rlen=1 any=0 nalts=1 name=s
    O.PMEntry{1, [O.OpsRESHAPE{}], [O.OpsRESHAPE{}]},  # 1 RESHAPE rej=RESHAPE slen=1 rlen=2 any=0 nalts=1 name=x
    O.PMEntry{2, [O.OpsRESHAPE{}], Nil{}},  # 2 RESHAPE rej=- slen=1 rlen=2 any=0 nalts=1 name=x
    O.PMEntry{3, [O.OpsPERMUTE{}], [O.OpsPERMUTE{}]},  # 3 PERMUTE rej=PERMUTE slen=1 rlen=1 any=0 nalts=1 name=x
    O.PMEntry{4, [O.OpsPERMUTE{}], Nil{}},  # 4 PERMUTE rej=- slen=0 rlen=0 any=0 nalts=0 name=x
    O.PMEntry{5, [O.OpsSTACK{}], [O.OpsINDEX{}]},  # 5 STACK rej=INDEX slen=0 rlen=0 any=0 nalts=1 name=stk
    O.PMEntry{6, [O.OpsINDEX{}], [O.OpsCONST{}, O.OpsSTACK{}]},  # 6 INDEX rej=CONST STACK slen=0 rlen=2 any=0 nalts=1 name=idx
    O.PMEntry{7, [O.OpsINDEX{}], [O.OpsINDEX{}]},  # 7 INDEX rej=INDEX slen=0 rlen=1 any=0 nalts=1 name=idx2
    O.PMEntry{8, [O.OpsINDEX{}], [O.OpsINDEX{}]},  # 8 INDEX rej=INDEX slen=0 rlen=1 any=0 nalts=1 name=idx2
    O.PMEntry{9, [O.OpsALLREDUCE{}], Nil{}},  # 9 ALLREDUCE rej=- slen=1 rlen=1 any=0 nalts=1 name=red
    O.PMEntry{10, [O.OpsREDUCE{}], Nil{}},  # 10 REDUCE rej=- slen=1 rlen=1 any=0 nalts=1 name=reduce
    O.PMEntry{11, [O.OpsDETACH{}, O.OpsCONTIGUOUS_BACKWARD{}], Nil{}},  # 11 CONTIGUOUS_BACKWARD DETACH rej=- slen=0 rlen=0 any=0 nalts=0 name=x
    O.PMEntry{12, [O.OpsSINK{}], Nil{}},  # 12 SINK rej=- slen=0 rlen=0 any=0 nalts=0 name=x
    O.PMEntry{13, [O.OpsCOPY{}], Nil{}},  # 13 COPY rej=- slen=0 rlen=1 any=0 nalts=1 name=copy
    O.PMEntry{14, [O.OpsSTORE{}], [O.OpsCOPY{}]},  # 14 STORE rej=COPY slen=1 rlen=2 any=0 nalts=1 name=-
    O.PMEntry{15, [O.OpsCOPY{}], Nil{}},  # 15 COPY rej=- slen=0 rlen=1 any=0 nalts=1 name=copy
    O.PMEntry{16, [O.OpsSTAGE{}], Nil{}},  # 16 STAGE rej=- slen=1 rlen=1 any=0 nalts=1 name=stg
    O.PMEntry{17, [O.OpsSTAGE{}], Nil{}},  # 17 STAGE rej=- slen=1 rlen=1 any=0 nalts=1 name=stg
    O.PMEntry{18, [O.OpsSTORE{}], [O.OpsRESHAPE{}]},  # 18 STORE rej=RESHAPE slen=1 rlen=2 any=0 nalts=1 name=-
    O.PMEntry{19, [O.OpsSTORE{}], Nil{}},  # 19 STORE rej=- slen=1 rlen=2 any=0 nalts=1 name=-
    O.PMEntry{20, [O.OpsSTORE{}], Nil{}},  # 20 STORE rej=- slen=1 rlen=2 any=0 nalts=1 name=-
    O.PMEntry{21, [O.OpsAFTER{}], [O.OpsAFTER{}, O.OpsSTORE{}]},  # 21 AFTER rej=AFTER STORE slen=1 rlen=2 any=0 nalts=1 name=-
    O.PMEntry{22, [O.OpsAFTER{}], [O.OpsSTORE{}]},  # 22 AFTER rej=STORE slen=1 rlen=2 any=0 nalts=1 name=-
    O.PMEntry{23, [O.OpsSTORE{}], [O.OpsBITCAST{}]},  # 23 STORE rej=BITCAST slen=1 rlen=2 any=0 nalts=1 name=-
    O.PMEntry{24, [O.OpsBITCAST{}], Nil{}},  # 24 BITCAST rej=- slen=0 rlen=0 any=0 nalts=0 name=bc
    O.PMEntry{25, [O.OpsREDUCE{}], Nil{}},  # 25 REDUCE rej=- slen=1 rlen=1 any=0 nalts=1 name=reduce
    O.PMEntry{26, [O.OpsSPECIAL{}, O.OpsBUFFER{}, O.OpsALLOC{}, O.OpsNOOP{}, O.OpsREWRITE_ERROR{}, O.OpsPARAM{}, O.OpsCALL{}, O.OpsPROGRAM{}, O.OpsLINEAR{}, O.OpsSOURCE{}, O.OpsBINARY{}, O.OpsAFTER{}, O.OpsGROUP{}, O.OpsSTACK{}, O.OpsGETADDR{}, O.OpsINDEX{}, O.OpsSHRINK{}, O.OpsLOAD{}, O.OpsSTORE{}, O.OpsWMMA{}, O.OpsCAST{}, O.OpsBITCAST{}, O.OpsEXP2{}, O.OpsLOG2{}, O.OpsSIN{}, O.OpsSQRT{}, O.OpsRECIPROCAL{}, O.OpsNEG{}, O.OpsTRUNC{}, O.OpsADD{}, O.OpsMUL{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsCDIV{}, O.OpsMAX{}, O.OpsCMOD{}, O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsCMPEQ{}, O.OpsXOR{}, O.OpsOR{}, O.OpsAND{}, O.OpsTHREEFRY{}, O.OpsSUB{}, O.OpsFDIV{}, O.OpsPOW{}, O.OpsFLOORDIV{}, O.OpsFLOORMOD{}, O.OpsWHERE{}, O.OpsMULACC{}, O.OpsBARRIER{}, O.OpsRANGE{}, O.OpsIF{}, O.OpsEND{}, O.OpsENDIF{}, O.OpsBACKEDGE{}, O.OpsCONST{}, O.OpsCUSTOM{}, O.OpsCUSTOMI{}, O.OpsINS{}, O.OpsCONTIGUOUS_BACKWARD{}, O.OpsDETACH{}, O.OpsSTAGE{}, O.OpsCOPY{}, O.OpsMSELECT{}, O.OpsMSTACK{}, O.OpsCUSTOM_FUNCTION{}, O.OpsRESHAPE{}, O.OpsPERMUTE{}, O.OpsEXPAND{}, O.OpsPAD{}, O.OpsFLIP{}, O.OpsUNSHARD{}, O.OpsREDUCE{}, O.OpsALLREDUCE{}, O.OpsPYLITERAL{}], Nil{}},  # 26 ADD AFTER ALLOC ALLREDUCE AND BACKEDGE BARRIER BINARY BITCAST BUFFER CALL CAST CDIV CMOD CMPEQ CMPLT CMPNE CONST CONTIGUOUS_BACKWARD COPY CUSTOM CUSTOMI CUSTOM_FUNCTION DETACH END ENDIF EXP2 EXPAND FDIV FLIP FLOORDIV FLOORMOD GETADDR GROUP IF INDEX INS LINEAR LOAD LOG2 MAX MSELECT MSTACK MUL MULACC NEG NOOP OR PAD PARAM PERMUTE POW PROGRAM PYLITERAL RANGE RECIPROCAL REDUCE RESHAPE REWRITE_ERROR SHL SHR SHRINK SIN SOURCE SPECIAL SQRT STACK STAGE STORE SUB THREEFRY TRUNC UNSHARD WHERE WMMA XOR rej=- slen=0 rlen=0 any=0 nalts=0 name=x
    O.PMEntry{27, [O.OpsSINK{}], Nil{}},  # 27 SINK rej=- slen=0 rlen=0 any=0 nalts=0 name=s
    O.PMEntry{28, [O.OpsAFTER{}], Nil{}},  # 28 AFTER rej=- slen=0 rlen=0 any=0 nalts=0 name=s
  ]}


def pr_mcl_table() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0, [O.OpsSHRINK{}], [O.OpsSHRINK{}]},  # 0 SHRINK rej=SHRINK slen=0 rlen=1 any=0 nalts=1 name=s
    O.PMEntry{1, [O.OpsRESHAPE{}], [O.OpsRESHAPE{}]},  # 1 RESHAPE rej=RESHAPE slen=1 rlen=2 any=0 nalts=1 name=x
    O.PMEntry{2, [O.OpsRESHAPE{}], Nil{}},  # 2 RESHAPE rej=- slen=1 rlen=2 any=0 nalts=1 name=x
    O.PMEntry{3, [O.OpsPERMUTE{}], [O.OpsPERMUTE{}]},  # 3 PERMUTE rej=PERMUTE slen=1 rlen=1 any=0 nalts=1 name=x
    O.PMEntry{4, [O.OpsPERMUTE{}], Nil{}},  # 4 PERMUTE rej=- slen=0 rlen=0 any=0 nalts=0 name=x
    O.PMEntry{5, [O.OpsSTACK{}], [O.OpsINDEX{}]},  # 5 STACK rej=INDEX slen=0 rlen=0 any=0 nalts=1 name=stk
    O.PMEntry{6, [O.OpsINDEX{}], [O.OpsCONST{}, O.OpsSTACK{}]},  # 6 INDEX rej=CONST STACK slen=0 rlen=2 any=0 nalts=1 name=idx
    O.PMEntry{7, [O.OpsINDEX{}], [O.OpsINDEX{}]},  # 7 INDEX rej=INDEX slen=0 rlen=1 any=0 nalts=1 name=idx2
    O.PMEntry{8, [O.OpsINDEX{}], [O.OpsINDEX{}]},  # 8 INDEX rej=INDEX slen=0 rlen=1 any=0 nalts=1 name=idx2
  ]}

# ===========================================================================
# THE TABLE ROWS.  `<t>_n` is the rule COUNT; `<t>_keys` is how many ops CLAIM a
# rule (`pdict`'s key set, ops.py:1592); `<t>_pd_<OP>` is the ORDERED list of
# rule indices that op claims, which is where FIRST-WINS lives (ops.py:1606 walks
# `pdict.get(uop.op, [])` in insertion order); and `<t>_<k>_{ops,rej}` are the two
# fields `PMEntry` actually has.
#
# `early_reject` is a SET (ops.py:1477) so it renders in BRACES and an EMPTY one
# renders `{}`, while `pat.op` is a TUPLE in the UPat's DECLARED order (ops.py:1454)
# and renders as a bare comma list.  The table literal therefore keeps `ops` in
# declared order and sorts `rej`, and this is where the two are rendered.
# ===========================================================================

def len_pme(es: List<&2, O.PMEntry>) -> U32: U32.from_nat(List.length(&2, O.PMEntry, es))


def len_strs(xs: List<&2, String>) -> U32: U32.from_nat(List.length(&2, String, xs))


def braced(+rej: List<&2, O.Op>) -> String: String.concat(["{", ops_str(rej), "}"])


def rej_str(+rej: List<&2, O.Op>) -> String:
  Bool.pick(String, U32.is_zero(len_ops(rej)), "{}", braced(rej))


def pr_t_row(+name: String, +k: U32, +e: O.PMEntry) -> IO(Unit):
  do IO<Unit>:
    row(String.concat([name, "_", U32.show(k), "_ops"]), ops_str(O.PMEntry.ops(e)))
    row(String.concat([name, "_", U32.show(k), "_rej"]), rej_str(O.PMEntry.rej(e)))


def pr_t_go(+name: String, +es: List<&2, O.PMEntry>, +k: Nat) -> IO(Unit):
  match es:
    case Nil{}: IO.print("")
    case e <> t:
      do IO<Unit>:
        pr_t_row(name, U32.from_nat(k), e)
        pr_t_go(name, t, Nat.add(k, 1n))


def pr_t_of(+name: String, +ts: O.PMEntrys) -> IO(Unit):
  do IO<Unit>:
    rowu(String.concat([name, "_n"]), len_pme(O.PMEntrys.es(ts)))
    pr_t_go(name, O.PMEntrys.es(ts), 0n)


# ===========================================================================
# THE `pdict` KEY SETS, emitted by `.agents/slop/prep-gen-tables.py` from
# `PatternMatcher.pdict` (ops.py:1592), in the alphabetical order the oracle
# prints.  `pr_<t>_keys` is the LENGTH and `pr_<t>_pd_<OP>` is the ordered rule
# list for one key.
# ===========================================================================
def pr_fma_keys() -> List<&2, O.Op>: [O.OpsADD{}, O.OpsAFTER{}, O.OpsAND{}, O.OpsCDIV{}, O.OpsCMOD{}, O.OpsCMPEQ{}, O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsEXP2{}, O.OpsFDIV{}, O.OpsFLOORDIV{}, O.OpsFLOORMOD{}, O.OpsLOG2{}, O.OpsMAX{}, O.OpsMUL{}, O.OpsMULACC{}, O.OpsNEG{}, O.OpsOR{}, O.OpsPOW{}, O.OpsRECIPROCAL{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsSIN{}, O.OpsSQRT{}, O.OpsSTAGE{}, O.OpsSUB{}, O.OpsTHREEFRY{}, O.OpsTRUNC{}, O.OpsWHERE{}, O.OpsXOR{}]
def pr_mop_keys() -> List<&2, O.Op>: [O.OpsAFTER{}, O.OpsEND{}, O.OpsINDEX{}]
def pr_inl_keys() -> List<&2, O.Op>: [O.OpsAFTER{}, O.OpsCALL{}]
def pr_dsk_keys() -> List<&2, O.Op>: [O.OpsCOPY{}]
def pr_ear_keys() -> List<&2, O.Op>: [O.OpsADD{}, O.OpsAFTER{}, O.OpsALLOC{}, O.OpsALLREDUCE{}, O.OpsAND{}, O.OpsBACKEDGE{}, O.OpsBARRIER{}, O.OpsBINARY{}, O.OpsBITCAST{}, O.OpsBUFFER{}, O.OpsCALL{}, O.OpsCAST{}, O.OpsCDIV{}, O.OpsCMOD{}, O.OpsCMPEQ{}, O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsCONST{}, O.OpsCONTIGUOUS_BACKWARD{}, O.OpsCOPY{}, O.OpsCUSTOM{}, O.OpsCUSTOMI{}, O.OpsCUSTOM_FUNCTION{}, O.OpsDETACH{}, O.OpsEND{}, O.OpsENDIF{}, O.OpsEXP2{}, O.OpsEXPAND{}, O.OpsFDIV{}, O.OpsFLIP{}, O.OpsFLOORDIV{}, O.OpsFLOORMOD{}, O.OpsGETADDR{}, O.OpsGROUP{}, O.OpsIF{}, O.OpsINDEX{}, O.OpsINS{}, O.OpsLINEAR{}, O.OpsLOAD{}, O.OpsLOG2{}, O.OpsMAX{}, O.OpsMSELECT{}, O.OpsMSTACK{}, O.OpsMUL{}, O.OpsMULACC{}, O.OpsNEG{}, O.OpsNOOP{}, O.OpsOR{}, O.OpsPAD{}, O.OpsPARAM{}, O.OpsPERMUTE{}, O.OpsPOW{}, O.OpsPROGRAM{}, O.OpsPYLITERAL{}, O.OpsRANGE{}, O.OpsRECIPROCAL{}, O.OpsREDUCE{}, O.OpsRESHAPE{}, O.OpsREWRITE_ERROR{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsSHRINK{}, O.OpsSIN{}, O.OpsSINK{}, O.OpsSOURCE{}, O.OpsSPECIAL{}, O.OpsSQRT{}, O.OpsSTACK{}, O.OpsSTAGE{}, O.OpsSTORE{}, O.OpsSUB{}, O.OpsTHREEFRY{}, O.OpsTRUNC{}, O.OpsUNSHARD{}, O.OpsWHERE{}, O.OpsWMMA{}, O.OpsXOR{}]
def pr_mcl_keys() -> List<&2, O.Op>: [O.OpsINDEX{}, O.OpsPERMUTE{}, O.OpsRESHAPE{}, O.OpsSHRINK{}, O.OpsSTACK{}]

# THE `pdict` ROW: the ordered rule indices ONE op claims.  `List.append` is
# `xs ++ ys` (agent-core.md), so the accumulator is already in order and there is
# no reverse -- `fold.bend`'s M2 note is about the PAIR, not about append.
# An op TWO rules claim prints a two-element list, and that is the row which
# separates a first-wins fold from a conjunction.
def pr_pd_str(b: Bool, k: Nat) -> List<&2, String>:
  match b:
    case True{}: [U32.show(U32.from_nat(k))]
    case False{}: Nil{}

def pr_pd_go(+es: List<&2, O.PMEntry>, +k: Nat, +op: O.Op, acc: List<&2, String>) -> List<&2, String>:
  match es:
    case Nil{}: acc
    case e <> t:
      pr_pd_go(t, Nat.add(k, 1n), op,
        List.append(&2, String, acc, pr_pd_str(O.op_in(O.PMEntry.ops(e), op), k)))

def pr_pd_row(+name: String, +es: List<&2, O.PMEntry>, +op: O.Op) -> IO(Unit):
  do IO<Unit>:
    row(String.concat([name, "_pd_", O.Ops.name.of(op)]),
      Bool.pick(String, U32.is_zero(len_strs(pr_pd_go(es, 0n, op, Nil{}))), "-",
        String.join(pr_pd_go(es, 0n, op, Nil{}), ",")))

def pr_keys_go(+name: String, +ops: List<&2, O.Op>, +es: List<&2, O.PMEntry>) -> IO(Unit):
  match ops:
    case Nil{}: IO.print("")
    case op <> t:
      do IO<Unit>:
        pr_pd_row(name, es, op)
        pr_keys_go(name, t, es)

def pr_keys_row(+name: String, +ops: List<&2, O.Op>, +ts: O.PMEntrys) -> IO(Unit):
  do IO<Unit>:
    rowu(String.concat([name, "_keys"]), len_ops(ops))
    pr_keys_go(name, ops, O.PMEntrys.es(ts))

def g_t1() -> IO(Unit):
  do IO<Unit>:
    pr_t_of("fma", pr_fma_table())
    pr_keys_row("fma", pr_fma_keys(), pr_fma_table())

def g_t2() -> IO(Unit):
  do IO<Unit>:
    pr_t_of("mop", pr_mop_table())
    pr_keys_row("mop", pr_mop_keys(), pr_mop_table())

def g_t3() -> IO(Unit):
  do IO<Unit>:
    pr_t_of("inl", pr_inl_table())
    pr_keys_row("inl", pr_inl_keys(), pr_inl_table())

def g_t4() -> IO(Unit):
  do IO<Unit>:
    pr_t_of("dsk", pr_dsk_table())
    pr_keys_row("dsk", pr_dsk_keys(), pr_dsk_table())

def g_t5() -> IO(Unit):
  do IO<Unit>:
    pr_t_of("ear", pr_ear_table())
    pr_keys_row("ear", pr_ear_keys(), pr_ear_table())

def g_t6() -> IO(Unit):
  do IO<Unit>:
    pr_t_of("mcl", pr_mcl_table())
    pr_keys_row("mcl", pr_mcl_keys(), pr_mcl_table())

# ===========================================================================
# ===========================================================================
# THE `pdict` KEY SETS, emitted by `.agents/slop/prep-gen-tables.py` from
# `PatternMatcher.pdict` (ops.py:1592), in the alphabetical order the oracle
# prints.  `pr_<t>_keys` is the LENGTH and `pr_<t>_pd_<OP>` is the ordered rule
# list for one key.
# ===========================================================================

# ===========================================================================
# 1. `walk_mop` -- prepare.py:40-43.
#      if u.op in GroupOp.Movement or u.op in {INDEX, UNSHARD, BITCAST}:
#        return walk_mop(u.src[0])
#      if u.op is AFTER and (b:=walk_mop(u.src[0])) is not u.src[0]:
#        return b.after(*u.src[1:])
#      return u
#
# THE IDENTITY IS THE RULE. `is not u.src[0]` decides whether the AFTER arm fires
# at all, so the rows are `wm_<nm>_same` (the answer IS the input) and
# `wm_<nm>_wmx` (the answer IS `u.src[0]`) -- neither is a count, and a movement
# node and its un-moved alias have the same op, the same nsrc, the same src op
# sequence and the same shape.  `GroupOp.movement` is `ops.bend:443` and owns the
# predicate; the three extra ops are written out because they are three.
# ---------------------------------------------------------------------------
# The SHAPE is `fold.bend`'s: ONE self-recursive def with the decreasing fuel
# first, and a `Data` RECORD for the rest of the state, because a `match` on a
# record's field binder is legal where a `match` on a computed value is not.  That
# is `Kahn.run` / `Kahn.step` / `Kahn.pop` exactly (fold.bend:2635-2646), and it is
# the only reason this walk is writable at all: Python's two `if`s become one
# `match` on `WmSt{kind}`, and the AFTER arm's "build or keep" becomes a
# `Bool.pick` inside `pr_wm_fork`, which is a FUNCTION and not a scrutinee -- which
# is exactly what makes the `is not u.src[0]` identity expressible.
def pr_wm_is(op: O.Op, want: O.Op) -> Bool: O.eq_op(op, want)

def pr_wm_extra(+op: O.Op) -> Bool:
  Bool.or(Bool.or(pr_wm_is(op, O.OpsINDEX{}), pr_wm_is(op, O.OpsUNSHARD{})),
          pr_wm_is(op, O.OpsBITCAST{}))

def pr_wm_hop(+op: O.Op) -> Bool: Bool.or(O.GroupOp.movement(op), pr_wm_extra(op))

# THE SPINE STATE.  Four fields and no `more`: the loop condition is the LIST, so
# `walk_mop` recursing while `hop(u) or u.op is AFTER` is a countdown that `pr_wm_step`
# can end by emptying, which is the same trick `Kahn` uses when it drains a worklist.
type WmSp is Data:
  WmSp{ar: O.Arena, me: U32, acc: List<&2, U32>, done: Bool}

def WmSp.ar(st: WmSp) -> O.Arena:
  match st:
    case WmSp{ar, me, acc, done}: ar

def WmSp.me(st: WmSp) -> U32:
  match st:
    case WmSp{ar, me, acc, done}: me

def WmSp.acc(st: WmSp) -> List<&2, U32>:
  match st:
    case WmSp{ar, me, acc, done}: acc

def WmSp.done(st: WmSp) -> Bool:
  match st:
    case WmSp{ar, me, acc, done}: done

# `List.append(x, A, xs, ys)` is `xs ++ ys` (agent-core.md), so `[me] ++ acc` is a
# PREPEND and the spine comes out DEEPEST-FIRST -- the order Python unwinds
# `walk_mop`'s recursion in.  The `done` flag exists because the self-call may only
# pass the countdown's TAIL, so a def cannot empty it: `pr_wm_step.end` sets `done`
# and every later turn is a no-op, and that is what "stop at the terminal node"
# costs in Bend.
def pr_wm_pre(+me: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, [me], acc)

def pr_wm_push.of(+ar: O.Arena, +me: U32, +acc: List<&2, U32>, +done: Bool) -> WmSp:
  WmSp{ar, me, pr_wm_pre(me, acc), done}

def pr_wm_push(+st: WmSp) -> WmSp:
  pr_wm_push.of(WmSp.ar(st), WmSp.me(st), WmSp.acc(st), WmSp.done(st))

def pr_wm_step.go.of(+ar: O.Arena, +me: U32, +acc: List<&2, U32>) -> WmSp:
  WmSp{ar, O.Arena.src0(ar, me), pr_wm_pre(me, acc), False{}}

def pr_wm_step.go(+st: WmSp) -> WmSp:
  pr_wm_step.go.of(WmSp.ar(st), WmSp.me(st), WmSp.acc(st))

# The TERMINAL node is pushed HERE and not by `pr_wm_last`: it is the node the loop
# condition rejects, and `walk_mop(u)` IS `u` for it, so it has to be on the spine or
# the fold starts from the wrong answer.  `pr_wm_last` then only ends the walk.
def pr_wm_step.end.of(+ar: O.Arena, +me: U32, +acc: List<&2, U32>, +done: Bool) -> WmSp:
  WmSp{ar, me, pr_wm_pre(me, acc), True{}}

def pr_wm_step.end(+st: WmSp) -> WmSp:
  pr_wm_step.end.of(WmSp.ar(st), WmSp.me(st), WmSp.acc(st), WmSp.done(st))

def pr_wm_more(+ar: O.Arena, +me: U32) -> Bool:
  Bool.or(pr_wm_hop(O.Arena.op(ar, me)), O.op_is(ar, me, O.OpsAFTER{}))

def pr_wm_step(more: Bool, +st: WmSp) -> WmSp:
  match more:
    case True{}: pr_wm_step.go(st)
    case False{}: pr_wm_step.end(st)

def pr_wm_turn.of(done: Bool, +st: WmSp) -> WmSp:
  match done:
    case True{}: st
    case False{}: pr_wm_step(pr_wm_more(WmSp.ar(st), WmSp.me(st)), st)

# ONE TURN, and it is a def rather than an inlined expression because the arm needs
# `st` for the `done` test AND for the `more` test: a parameter is affine, so reading
# it twice in one arm is a type error unless it is `+`, and `pr_wm_spine` hands it
# over whole instead.  The PUSH is `pr_wm_step.go` / `.end` and not here: an earlier
# version pushed in both places and every node with a hop descendant landed on the
# spine TWICE, which folded the AFTER arm against its own answer and answered
# `NOOP`.
def pr_wm_turn(+st: WmSp) -> WmSp: pr_wm_turn.of(WmSp.done(st), st)

# THE LAST TURN, and it only fires when the countdown ran out BEFORE the loop
# condition rejected a node -- a chain longer than the fuel, which `Arena.budget`
# cannot produce.  It exists so the walk is total, and both arms are listed because
# a `match` on a `Data` must name every constructor.
def pr_wm_last.of(done: Bool, +st: WmSp) -> List<&2, U32>:
  match done:
    case True{}: WmSp.acc(st)
    case False{}: WmSp.acc(pr_wm_push(st))

def pr_wm_last(+st: WmSp) -> List<&2, U32>: pr_wm_last.of(WmSp.done(st), st)

# THE SPINE.  `ns` is the fuel and it is the FIRST parameter, because a
# self-recursive def's decreasing argument must be first and read left to right
# (`Kahn.seed.work`, fold.bend:2186, is the precedent for a list fuel).  The tail is
# what shrinks, so `pr_wm_turn` cannot shorten it -- which is what `done` is for.
def pr_wm_spine(+ns: List<&2, Nat>, st: WmSp) -> List<&2, U32>:
  match ns:
    case Nil{}: pr_wm_last(st)
    case _ <> t: pr_wm_spine(t, pr_wm_turn(st))

# THE FOLD.  `walk_mop(u)` is `f(u, walk_mop(u.src[0]))` and Python's walrus binds
# once, so the answer is threaded along the spine in the order Python unwinds it.
# `UOp.after` GROWS the arena, so the arena rides in the accumulator.
type WmA is Data:
  WmA{ar: O.Arena, ans: U32}

def WmA.ar(a: WmA) -> O.Arena:
  match a:
    case WmA{ar, ans}: ar

def WmA.ans(a: WmA) -> U32:
  match a:
    case WmA{ar, ans}: ans

def WmA.of(+ar: O.Arena, +ans: U32) -> WmA: WmA{ar, ans}

# NOT an AFTER: a movement op KEEPS the answer it was handed, because
# `walk_mop(u)` IS `walk_mop(u.src[0])`; anything else STOPS and is its own answer.
def pr_wm_keep(hop: Bool, +n: U32, a: WmA) -> WmA:
  match hop:
    case True{}: a
    case False{}: WmA.of(WmA.ar(a), n)

# AFTER: `(b:=walk_mop(u.src[0])) is not u.src[0]` decides whether to rebuild, and
# the rebuild is `b.after(*u.src[1:])`.  `ops.bend` HAS `UOp.after`, so this arm is
# PORTED and is not a wall -- it is the only builder `walk_mop` needs.
# THE BUILDER'S ARENA IS THE ONE `UOp.new` RETURNS, never the one it was handed.
# `UOp.make` appends, so the arena it returns is one node longer than the one it
# took, and an index read against the OLD arena is out of range -- which is what
# every `wm_after_mov*_out` row did before this line existed: index `next`, op NOOP.
def pr_wm_mk.of(+f: O.Found) -> WmA: WmA.of(O.Found.ar(f), O.Found.i(f))

def pr_wm_mk(+ar: O.Arena, +b: U32, +n: U32) -> WmA:
  pr_wm_mk.of(O.UOp.new(ar, O.OpsAFTER{},
    List.append(&2, U32, [b], O.Arena.src_from(ar, n, 1)), O.ANone{}, O.TNone{}))

def pr_wm_keep_a(changed: Bool, +ar: O.Arena, +n: U32, +b: U32) -> WmA:
  match changed:
    case True{}: WmA.of(ar, n)
    case False{}: pr_wm_mk(ar, b, n)

def pr_wm_after.of(+ar: O.Arena, +b: U32, s0: U32, +n: U32) -> WmA:
  pr_wm_keep_a(U32.is_eq(b, s0), ar, n, b)

# THE AFTER ARM, with NO `hop` test at all: Python's line 42 is
#   `if u.op is Ops.AFTER and (b:=walk_mop(u.src[0])) is not u.src[0]: ...`
# and the ONLY condition is the identity.  An earlier version of this def tested
# `hop` first, which is wrong and was MEASURED wrong: `walk_mop(AFTER(RESHAPE(..),
# END))` rebuilds, because `RESHAPE` is a movement op and so its answer differs from
# `u.src[0]` -- `hop` is about the AFTER's OWN op and says nothing about `src[0]`.
# The rows `wm_after_mov_same` and `wm_after_plain_same` are the two sides.
def pr_wm_after(+n: U32, +a: WmA) -> WmA:
  pr_wm_after.of(WmA.ar(a), WmA.ans(a), O.Arena.src0(WmA.ar(a), n), n)

def pr_wm_keep.of(hop: Bool, isafter: Bool, +n: U32, +a: WmA) -> WmA:
  match isafter:
    case True{}: pr_wm_after(n, a)
    case False{}: pr_wm_keep(hop, n, a)

def pr_wm_arm(+n: U32, +a: WmA) -> WmA:
  pr_wm_keep.of(pr_wm_hop(O.Arena.op(WmA.ar(a), n)), O.op_is(WmA.ar(a), n, O.OpsAFTER{}), n, a)

# The SPINE is the fuel and it is the FIRST parameter with the accumulator LAST,
# which is `Kahn.run(fuel, ar, k)` exactly (fold.bend:2650): the tail is the
# decreasing argument, so it is read first, and the changed accumulator rides in
# the last position where nothing else has to be read twice.
def pr_wm_fold(+ns: List<&2, U32>, a: WmA) -> WmA:
  match ns:
    case Nil{}: a
    case n <> t: pr_wm_fold(t, pr_wm_arm(n, a))

# `walk_mop` ITSELF: SPINE then FOLD.  Three Python lines become two passes because
# a Bend def may have ONE decreasing argument in ONE self-call, and `walk_mop`'s
# AFTER arm has both a recursion and a builder whose arena has to be threaded.
# `walk_mop` returns a `Found` and NOT a `U32`: the AFTER arm BUILDS, so the arena
# GROWS, and a gate that folded the ORIGINAL arena would read the new node's index in
# an arena that does not contain it.  That is not hypothetical -- it is what this def
# returned at first, and every `wm_after_*_out` row came out `NOOP` because
# `Arena.op` read index 0 of an arena whose node 0 is the bottom.
def pr_wm_all.of(+a: WmA) -> O.Found: O.Found{WmA.ar(a), WmA.ans(a)}

def pr_wm_all(fuel: Nat, +st: WmSp) -> O.Found:
  pr_wm_all.of(pr_wm_fold(pr_wm_spine(List.range(fuel), st), WmA.of(WmSp.ar(st), WmSp.me(st))))

def pr_wm(fuel: Nat, +ar: O.Arena, self: U32) -> O.Found:
  pr_wm_all(fuel, WmSp{ar, self, Nil{}, False{}})

# THE FIXTURE PAIR. `O.Found` is `ops.bend`'s `(arena, node)`, and a node is an
# arena INDEX, so a fixture list has to carry the folded arena with it or every
# reader has to be handed both.
type WMI is Data:
  WMI{nm: String, i: U32}

type WMF is Data:
  WMF{fx: F.Folded, items: List<&2, WMI>}

def WMI.nm(w: WMI) -> String:
  match w:
    case WMI{nm, i}: nm

def WMI.i(w: WMI) -> U32:
  match w:
    case WMI{nm, i}: i

def WMF.fx(w: WMF) -> F.Folded:
  match w:
    case WMF{fx, items}: fx

def WMF.items(w: WMF) -> List<&2, WMI>:
  match w:
    case WMF{fx, items}: items

# THE FIXTURES.  ONE arena for all of them, because a `toposort` SIZE is only
# comparable with CPython's if both sides count the same reachable set, and two
# arenas would make every fixture a different graph.  The nodes are built in the
# same order the oracle builds its, so the arena layout agrees as well.
def wm_fix() -> WMF:
  +a4 = pr_buf(O.Arena.empty(), 0, 4, "a4", 0)
  +a8 = pr_buf(O.Found.ar(a4), 1, 8, "a8", 0)
  +sh22 = pr_shp2(O.Found.ar(a8), 2, 2)
  +sh4 = pr_shp1(O.Found.ar(sh22), 4)
  +sh41 = pr_shp2(O.Found.ar(sh4), 4, 1)
  +rs22 = pr_reshape(O.Found.ar(sh41), a4, sh22)
  +rs41 = pr_reshape(O.Found.ar(rs22), a4, sh41)
  +rs4 = pr_reshape(O.Found.ar(rs41), a4, sh4)
  +pm22 = pr_perm(O.Found.ar(rs4), rs22, 1, 0)
  +fl22 = pr_flip(O.Found.ar(pm22), rs22, 1, 0)
  +c0 = pr_shp1(O.Found.ar(fl22), 0)
  +pd = pr_pad(O.Found.ar(c0), a4, c0, sh4)
  +pe = pr_expand(O.Found.ar(pd), a4, sh4)
  +r0 = pr_range(O.Found.ar(pe), 4, 0)
  +ix = O.UOp.new(O.Found.ar(r0), O.OpsINDEX{}, [O.Found.i(a4), O.Found.i(r0)], O.ANone{}, O.TNone{})
  +bc = O.UOp.new(O.Found.ar(ix), O.OpsBITCAST{}, [O.Found.i(a4)], O.ADt{S.single()}, O.TNone{})
  # UNSHARD is one of the three extra hop ops and its arm is in `pr_wm_hop`, but it is NOT a
  # gate fixture: `fold.bend` has no UNSHARD dtype rule, so `F.fold.dt` answers `None`
  # where CPython answers `int` and a row that printed `ERR` on this side and `int`
  # on that one would be a row that CANNOT PASS.  It is a REPORTED fold gap, not a
  # port bug, and the mutation M09 below is the check that the arm is live.
  +bcx = O.UOp.new(O.Found.ar(bc), O.OpsINDEX{}, [O.Found.i(a8), O.Found.i(r0)], O.ANone{}, O.TNone{})
  +cf = O.UOp.new(O.Found.ar(bcx), O.OpsCAST{}, [O.Found.i(a4)], O.ADt{S.single()}, O.TNone{})
  +al = pr_alu2(O.Found.ar(cf), O.OpsADD{}, a4, a4)
  +e4 = pr_end(O.Found.ar(al), a4)
  +af = pr_after(O.Found.ar(e4), a4, e4)
  +afm = pr_after(O.Found.ar(af), rs22, e4)
  +afm2 = pr_after(O.Found.ar(afm), pm22, e4)
  +afi = pr_after(O.Found.ar(afm2), ix, e4)
  +nest = pr_reshape(O.Found.ar(afi), pm22, sh4)
  +st = pr_store(O.Found.ar(nest), a4, a4)
  +mom = pr_perm(O.Found.ar(st), rs22, 0, 1)
  +ia4 = O.Found.i(a4)
  +irs22 = O.Found.i(rs22)
  +irs41 = O.Found.i(rs41)
  +irs4 = O.Found.i(rs4)
  +ipm22 = O.Found.i(pm22)
  +ifl22 = O.Found.i(fl22)
  +ipd = O.Found.i(pd)
  +ipe = O.Found.i(pe)
  +iix = O.Found.i(ix)
  +ibc = O.Found.i(bc)
  +icf = O.Found.i(cf)
  +ial = O.Found.i(al)
  +iaf = O.Found.i(af)
  +iafm = O.Found.i(afm)
  +iafm2 = O.Found.i(afm2)
  +iafi = O.Found.i(afi)
  +inest = O.Found.i(nest)
  +ist = O.Found.i(st)
  +imom = O.Found.i(mom)
  WMF{F.folded(O.Found.ar(mom)), [
    WMI{"buf", ia4}, WMI{"reshape", irs22}, WMI{"rs41", irs41}, WMI{"rs4", irs4},
    WMI{"permute", ipm22}, WMI{"flip", ifl22}, WMI{"pad", ipd}, WMI{"expand", ipe},
    WMI{"index", iix}, WMI{"bitcast", ibc}, WMI{"cast", icf},
    WMI{"alu", ial}, WMI{"after_plain", iaf}, WMI{"after_mov", iafm},
    WMI{"after_mov2", iafm2}, WMI{"after_idx", iafi}, WMI{"nested_mov", inest},
    WMI{"store", ist}, WMI{"mov_of_mov", imom}]}

def pr_wm_wmx.yes(b: U32, s0: U32) -> String: Bool.pick(String, U32.is_eq(b, s0), "1", "0")

def pr_wm_wmx.of(isafter: Bool, +ar: O.Arena, +self: U32, b: U32) -> String:
  match isafter:
    case True{}: pr_wm_wmx.yes(b, O.Arena.src0(ar, self))
    case False{}: "-1"

def pr_wm_wmx(+ar: O.Arena, +self: U32, b: U32) -> String:
  pr_wm_wmx.of(O.op_is(ar, self, O.OpsAFTER{}), ar, self, b)

def wm_row(+nm: String, +fx: F.Folded, +self: U32) -> IO(Unit):
  +ar = F.Folded.ar(fx)
  +f = pr_wm(O.Arena.budget(ar), ar, self)
  +b = O.Found.i(f)
  +g = F.folded(O.Found.ar(f))
  +pre = String.concat(["wm_", nm, "_"])
  do IO<Unit>:
    row(String.concat([pre, "in"]), sig4(fx, self))
    row(String.concat([pre, "out"]), sig4(g, b))
    rowi(String.concat([pre, "same"]), pr_wm_same(self, b))
    row(String.concat([pre, "wmx"]), pr_wm_wmx(ar, self, b))
    row(String.concat([pre, "topo"]), topo_str(g, b))

# `wmx` is `-1` for a non-AFTER input and the identity for an AFTER one, which is
# how the oracle spells it: the question "was the answer `u.src[0]`" only HAS a
# meaning on the AFTER arm.

def wm_go(+fx: F.Folded, +ws: List<&2, WMI>) -> IO(Unit):
  match ws:
    case Nil{}: IO.print("")
    case w <> t:
      do IO<Unit>:
        wm_row(WMI.nm(w), fx, WMI.i(w))
        wm_go(fx, t)

def g_wm() -> IO(Unit):
  +w = wm_fix()
  wm_go(WMF.fx(w), WMF.items(w))

# ===========================================================================
# THE MUTATION TABLE.  One edit per ported rule, re-run in the INTERPRETED lane
# (the two lanes are byte-identical at baseline, so the native lane adds nothing
# here and costs minutes), and the rows each edit moves are reported BY NAME.
# `.agents/slop/prep-mutate.py` applies them and this table is its output; nothing
# here is transcribed by hand.  The harness diffs whole `name=value` lines, never
# row NAMES.
#
#   MUT   DEF                WHAT IT CHANGES                              ROWS MOVED
#   M01   pr_fma_table       rule 2's ALU op set GAINS CONST                  1
#   M02   pr_mop_table       rule 2 claims STORE, not END                    2
#   M03   pr_ear_table       rule 10 (`split_reduceop`) claims WHERE          3
#   M04   pr_inl_table       rule 0 (`resolve_function`) claims END            2
#   M05   pr_dsk_table       rule 0's early_reject gains CONST                 1
#   M06   pr_mcl_table       `mop_cleanup` rule 5's reject gains CONST         1
#   M07   pr_wm_hop          drop INDEX/UNSHARD/BITCAST from the hop set       9
#   M08   pr_wm_extra        keep only INDEX of the three extra hop ops        3
#   M09   pr_wm_step         the spine's loop condition loses the AFTER half   9
#   M10   pr_wm_keep         a movement arm takes the node instead of keeping 42
#   M11   pr_wm_keep_a       INVERT `is not u.src[0]` -- rebuild on no change   9
#   M12   pr_wm_pre          APPEND the spine node instead of prepending it   10
#   M13   pr_wm_step.go.of   the spine stops pushing on the descent          10
#   M14   pr_wm_step.end.of  the spine never pushes the TERMINAL node        42
#   M15   pr_wm_mk           `*u.src[1:]` reads srcs BEFORE index 1            6
#   M16   pr_wm_turn.of      the `done` flag is ignored                  DOES NOT COMPILE
#   M17   pr_pd_go           the `pdict` scan claims no rule for any op      118
#   M19   rej_str            an EMPTY early_reject prints `-`, not `{}`      22
#   M20   braced             the reject set loses its braces                22
#   M21   shape_str.go       a shape's dim separator is `,`, not `x`          8
#   M22   sint_str.go        a SYMBOLIC dim prints `hi:lo`                   NOTHING (0)
#   M23   dt_name.of         an unresolved dtype prints `void`, not `ERR`    NOTHING (0)
#   M24   sig4               nsrc reads src[0]'s OWN nsrc                    23
#   M25   pr_wm_more         the spine descends on AFTER only                39
#   M26   pr_wm_fold         the fold visits no node at all                  42
#   M27   pr_ear_table       rule 20 (`fix_store_hazard`) reject gains AFTER   1
#   M28   pr_fma_table       rule 0 (`found_after`) reject loses STORE         1
#
# TWENTY-FIVE OF TWENTY-SEVEN MOVE ROWS.  The three that do not are reported as
# blind spots with their reasons, NOT closed with rows:
#
#   M16 IS NOT A MUTATION.  The edit deletes one arm of a `match`, which is a
#   syntax error and not a behaviour change -- it is listed so the table does not
#   claim a measurement it did not take.  The `done` flag IS measured, by M13: a
#   spine that keeps pushing after the terminal node moves the same ten rows.
#
#   M22 IS AN UNREACHABLE ARM, not a gap.  `Sint` is `SI{i64} | SU{u32}` and `O.SU`
#   is a shape dim for a SYMBOLIC size.  Nothing in this tree can mint one:
#   `ops.bend`'s `ParamArg.size` is `Maybe<&2, U32>` with the comment "always a
#   concrete int (never symbolic)" (ops.bend:698-699) and `fold.bend`'s
#   `param_shape.size` reads it as `sint_of(n)`.  Every fixture dim is a concrete
#   `O.SI`, so `sint_str.go`'s second arm never runs.  This is `fold.bend`'s M9
#   verbatim and it is reported here for the same reason.
#
#   M23 IS THE SAME KIND OF THING WITH ONE EXTRA EDGE.  `dt_name.of`'s `None` arm
#   fires for a node the FOLD does not resolve, and the only such node in this
#   gate's fixtures would be a UNSHARD -- which is why the UNSHARD fixture was
#   REMOVED from the gate, and the reason is written into `wm_fix` beside the node
#   it would have used.  `fold.bend` has no UNSHARD dtype rule, so the arm is
#   reachable only by a fixture this gate deliberately does not build.  That is a
#   THIRD option the brief does not name: the fixture was REMOVED rather than kept
#   with a row that could not pass, and the removal is visible in the diff.  The
#   arm of `pr_wm_extra` that reads UNSHARD is still live, and M08 measures it.
#
# THE ROWS THIS PORT CANNOT PRINT, and the substrate fact behind each.  The oracle
# is 2544 rows; 321 of them are gated here and the rest are the WALLS above, named
# rather than faked:
#
#   * `mi_*` (190 rows) -- `_mop_index`'s three index counts, `src_prefix`, the tail
#     equality and `ret.shape == idx.shape`.  All but the last are PURE and PORTABLE
#     without an arena; the last needs `apply_movement_op` (schedule/indexing.py:130)
#     plus `UOp.index` (ops.py:581), which is W3.  The fixtures exist in the oracle.
#   * `sr_*` / `srp_*` (140 rows) -- `split_reduceop`'s candidate search.  The search
#     is PURE (`range` over `reduce.arg[1]`, `range(cap, 7, -1)`, `x.shape[i]%d` and
#     `is_expanded[i]`) and 2**22 is a `U32` LITERAL rather than a shift, so the
#     `U32.shl` trap does not bite here.  `is_expanded` is W4, so the search takes it
#     as a PARAMETER; `srp_L_*` in the oracle is `is_expanded` measured through
#     tinygrad's own `index` + `substitute`, so the fixture is already in hand.
#   * `ebp_*` (140 rows) -- `expand_bitcast`'s itemsize ladder: `ns`, `os`, the DISK
#     early-out, `rate = ns//os`, the reshape `x.shape[:-1] + (last//rate, rate)`,
#     `nparts` and the shift step `8*os` / `8*ns`.  All of it is pure arithmetic on
#     two itemsizes and a last dim, with NO arena and NO builder.  This is the
#     highest-value un-ported section and the shortest.
#   * `fa_*` (56 rows) -- `found_after`'s loop.  `argsort` is `H.argsort_u32`
#     (helpers.bend:196) and the RESHAPE / WHERE / SHRINK arms are pure, so it is
#     PORTABLE; only the `.after(...)` at the end is W3.
#   * `shb_*` / `fsh_*` (55 rows) -- `store_hazard_boundary` and `fix_store_hazard`.
#     The gated toposort is `O.UOp.toposort_nocalls` FILTERED by the boundary, which
#     is order-preserving, so both are portable; `op_in_backward_slice_with_self`
#     (ops.py) is not, and `target.store(src.contiguous())` is W3.
#   * `cas_*` / `sas_*` / `mcd_*` (40 rows) -- the three materialisers.  Each is one
#     predicate over `prod(x.max_shape)` and a device comparison; `max_shape` is
#     ops.py:467 and is not in `fold.bend`.
#   * `rfn_*` (52 rows) -- `resolve_function`'s THREE REFUSALS
#     (`arg {slot} shape mismatch: expected size {n}, got {shape}`,
#     `... expected scalar, got ...`, `... dtype mismatch: expected {p}, got {a}`)
#     and its OK rows.  `flat_storage`'s `a.pad_to(shp).reshape((n,))` is W3 and
#     `UOp.unique_num` is a global counter with no arena, so the ALLOC re-mint is
#     the part that cannot be answered.  The refusal MESSAGES are the rows and they
#     are exactly reproducible from the oracle.
#   * `fco_*` (100 rows) and `pr_*` (90 rows) -- `forward_call_outputs` and
#     `prepare_rangeify`.  Both are gated by `graph_rewrite` (W1) and
#     `UOp.substitute` (W2): the first is a fixpoint over a worklist with a rebuilt
#     todo, and the second IS a rewrite of every node.  `schedule/indexing.bend`
#     records the same `graph_rewrite` wall from the other side.
#   * `cl_*` (600+ rows) -- the per-rule FIRING rows, and they are the biggest
#     un-ported prize.  Each is "how many rules CLAIM this node, which ones, and
#     what `PatternMatcher.rewrite` returns", and the fixtures already exist in the
#     oracle (`FIX`, 33 nodes).  They are absent for a DEF-ORDER reason and not an
#     impossibility: `O.pm_rewrite` needs a `PMEntrys` and a dispatch, so the six
#     tables' `try`/`scan`/`dispatch` have to be written before any row can print,
#     and that is the next block of work rather than a wall.  The measurements to
#     make first are `cl_ear_bitstore_n=4`, `cl_ear_rsstore_n=4` and
#     `cl_ear_copystore_n=4`: four rules claim one node and only a FIRST-WINS scan
#     separates them.
#   * `<t>_<k>_{dt,src}` (2 per rule) -- `UPat.match_dtype` and the src permutation
#     tuple (upat.py:47).  `PMEntry` is `tag`/`ops`/`rej` and NOTHING ELSE
#     (ops.bend:2966), so `UPat` does not survive into the compiled IR.
# ===========================================================================
def main() -> IO(Unit):
  do IO<Unit>:
    g_t1()
    g_t2()
    g_t3()
    g_t4()
    g_t5()
    g_t6()
    g_wm()
    IO.print("done")

