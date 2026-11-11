# tinybendygrad/schedule/prepare.bend
# Port of tinygrad/schedule/prepare.py (278 lines). `prepare_rangeify`.
#
# what this file is, in one paragraph. `prepare.py` is a scheduling pass: it
# takes a UOp graph and rewrites it into a form the device can run. Almost all of
# it is DECISION -- eleven functions and five `PatternMatcher`s, most of whose
# rules are lambdas -- and the decisions are arithmetic over SHAPES (a `prod`, a
# `src_prefix`, a `%` inside the split search, two itemsizes and a `rate`, an
# `argsort`) or over the ARENA (a `toposort` with a gate, a `base` reachability
# map, a `placed` substitution). What it BUILDS is a set of nodes through
# `UOp.store`, `.after`, `.index`, `.pad_to`, `.contiguous`, `.usum` and
# `UOp.unique_num`, and those builders are the wall named below.
#
# the order of the file is python's order: `forward_call_outputs` (11-38),
# `walk_mop` (40-43), `found_after` (45-53) and its table (56-62), `_mop_index`
# (65-74) and `pm_mops` (76-83), then the "0. cleanup" block: the hazard pair
# (89-101), `split_reduceop` (103-125), `resolve_function` (127-150),
# `expand_bitcast` (153-162), the three materialisers (164-182),
# `pm_inline_calls` (184-187), `pm_disk_copy` (189-197), `earliest_rewrites`
# (199-269) and `prepare_rangeify` (271-278).
#

# THE SPLIT. Every rule body here is a DECISION: it answers "which arm, and
# with what arithmetic", and the node it would build is named at the call site.
# That is `agent-core.md`'s split with the trace side unused -- nothing in this
# file declares a foreign effect, and both lanes run it.
#

# THE WALLS. Six, each with the Python line that hits it. Nothing here is
# approximated and nothing here is faked: a row that cannot be computed prints
# the wall's name, so a diff can tell a wall from a value.
#
# W1. `graph_rewrite` -- ops.py:1886 symbol=graph_rewrite, called FOUR TIMES at prepare.py:280-283.
#     It is a fixpoint over a worklist: rewrite every node, push the result
#     back, repeat until nothing fires. Bend refuses mutual recursion and a
#     worklist with a REBUILT todo is not a subterm, so ONE pass per table is
#     the most this file can spell. The per-step rows are labelled `1p` (one
#     pass) and a one-pass row is not a fixpoint row.
# W2. `UOp.substitute` -- ops.py:514 symbol=substitute, and `dict_map` / `dict_map.update` at
#     prepare.py:11-21 symbol=forward_call_outputs. `forward_call_outputs`'s `placed` map and
#     `resolve_function`'s `flat_storage` are both substitutions, so both inherit
#     W1.
# W3. THE BUILDERS. `UOp.index`, `.after`, `.store`, `.contiguous`, `.pad_to`,
#     `.reshape`, `.permute`, `.shrink`, `.usum`, `.squeeze`, `.flatten`,
#     `.bitcast`, `.cast` and `UOp.unique_num` are ops.py:581-1040. `ops.bend`
#     has `UOp.after`, `UOp.new`, `UOp.group` and `UOp.alu` but NOT the
#     move-mixin half, so every rule whose body IS a builder is ported as its
#     DECISION: the arm, and the arithmetic that chose it.
# W4. `is_expanded` -- prepare.py:123-125. `indexed.substitute({x.base:NOOP},
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
# `O.PMEntry` is `tag`/`ops`/`rej` and NOTHING ELSE (uop/ops.bend:4043 symbol=PMEntry), so the
# oracle's `<t>_<k>_dt` and `_src` columns have no field to read: those are
# `UPat` facts (`match_dtype`, and the src permutation tuple at upat.py:39) and
# `UPat` does not survive into the compiled IR. `schedule/indexing.bend` records
# the same wall for its three tables.
#
# THE TABLES. Five `PatternMatcher`s plus `mop_cleanup`, which `earliest_rewrites`
# prepends (`prepare.py:195`), so SIX tables live here. `PatternMatcher.__add__`
# is `functools.cache`d over `(self.patterns + more.patterns)` (ops.py:290), so
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


# THE ROW PRINTER. One line per claim, `name=value`, so the differ reads whole
# lines and never compares row NAMES.

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
# `H.i64_text` renders an I64 as `hi:lo` (helpers.bend:1713 symbol=i64_text, "an I64 prints as its
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

# the gate's four facts plus the answer as one string. `toposort` SIZE and not
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


# `S.Dt`'s fourth field is the NAME (`LAWS/spec.bend:76 symbol=Dt`, `Dt{pri, bits, cls, nm}`)
# and CPython's `uop.dtype.name` is exactly it, so the dtype column is one binder and
# not a table -- which is the reason `sig4` can carry a dtype at all.
def dt_name(d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, nm}: nm

def dt_name.of(m: Maybe<&2, S.Dt>) -> String:
  match m:
    case Some{d}: dt_name(d)
    case None{}: "ERR"

def pr_c(v: U32) -> O.Found: O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(v)})

# `ParamArg(slot, dtype, size, name, addrspace, device)` -- ops.py:696 read
# through `uop/ops.bend:697 symbol=AxisType.lt`. A BUFFER's `src` is EMPTY in Python
# (`UOp(Ops.BUFFER, arg=...)`), so this is a 0-src node.

def pr_pa(slot: U32, name: String, dev: U32) -> O.ParamArg:
  O.ParamArg{slot, S.int32(), None{}, None{}, Some{name}, S.AGlobal{},
    Some{S.D1{dev}}, False{}, None{}, None{}, False{}, None{}}


def pr_buf(+ar: O.Arena, slot: U32, size: U32, name: String, dev: U32) -> O.Found:
  O.UOp.new.param(ar, O.OpsBUFFER{}, Some{size}, O.AParam{pr_pa(slot, name, dev)}, O.TNone{})

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

# every builder takes the arena first and uses *it*, never the arena of one of its
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

# AND THE ORDER IS IN `src[1]` -- UPSTREAM's `_mop` (`ops.py:784,790-791`)
# BUILDS THE NODE AS `UOp(op, src=(self,)+UOp.sink(*usrcs).simplify().src)`, AND
# `marg` (`ops.py:772`) READS IT BACK FROM `src[1].as_shape` -- AND THE
# OLD COMMENT ("PERMUTE and FLIP take their marg in the ARG
# (`ops.py:818`)") WAS WRITTEN AGAINST AN OLDER UPSTREAM.
#
# AND FLIP IS GONE AT THE PIN (`900880433`, 2026-10-11), AND THE
# `O.ABoolList` THE OLD COMMENT SPOKE OF IS THE PORT's OWN SPELLING
# OF A `tuple[bool, ...]` FOR A NODE THAT NO LONGER EXISTS.
def pr_perm(ar: O.Arena, +x: O.Found, +a: U32, b: U32) -> O.Found:
  +sk = O.shape_arg_found(ar, [a, b])
  O.UOp.new(O.Found.ar(sk), O.OpsPERMUTE{}, [O.Found.i(x), O.Found.i(sk)], O.ANone{}, O.TNone{})


# REPORTED, NOT USED: `ops.bend`'s `UOp.after` (uop/ops.bend:2897 symbol=UOp.after) and `UOp.end`
# (uop/ops.bend:2944 symbol=UOp.end) build `List.append(srcs, [self])`, which is `srcs ++ [self]`.
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


# THE SIX TABLES, emitted by `.agents/slop/prep-gen-tables.py` from tinygrad's
# OWN `PatternMatcher` objects: `pat.op` IS `pdict`'s key (ops.py:1598) and
# `pat.early_reject` is ops.py:1477.  The comment on each entry is the rule's
# `strict_length` / `required_len` / `is_any` / `nalts` / `name`.


def braced(+rej: List<&2, O.Op>) -> String: String.concat(["{", ops_str(rej), "}"])


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
# (`Kahn.seed.work`, uop/fold.bend:2990 symbol=Kahn.seed.work, is the precedent for a list fuel).  The tail is
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
# the builder's arena is the one `UOp.new` returns, never the one it was handed.
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
# which is `Kahn.run(fuel, ar, k)` exactly (uop/fold.bend:4896 symbol=Kahn.run): the tail is the
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

type WMI is Data:
  WMI{nm: String, i: U32}

type WMF is Data:
  WMF{fx: F.Folded, items: List<&2, WMI>}

def pr_wm_wmx.yes(b: U32, s0: U32) -> String: Bool.pick(String, U32.is_eq(b, s0), "1", "0")

def pr_wm_wmx.of(isafter: Bool, +ar: O.Arena, +self: U32, b: U32) -> String:
  match isafter:
    case True{}: pr_wm_wmx.yes(b, O.Arena.src0(ar, self))
    case False{}: "-1"

def pr_wm_wmx(+ar: O.Arena, +self: U32, b: U32) -> String:
  pr_wm_wmx.of(O.op_is(ar, self, O.OpsAFTER{}), ar, self, b)

