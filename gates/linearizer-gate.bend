# gates/linearizer-gate.bend -- the gate driver for `tinybendygrad/codegen/late/linearizer.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/codegen/late/linearizer.bend as P

import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F
import ./../tinybendygrad/codegen/kernel.bend as KER
def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

def lt_u32s.go(xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}   : acc
    case v <> +r : lt_u32s.go(r, List.append(&2, String, acc, [U32.show(v)]))

def lt_u32s(xs: List<&2, U32>) -> String:
  String.join(lt_u32s.go(xs, Nil{}), " ")

# `lt_lines` IS `print` FOR A LIST OF ROWS, and `String.join` IS the whole of it:
# the oracle prints one row per line, so a block of rows is the rows joined by
# "\n" and `IO.print`'s own newline is the LAST one. `String.join` drops the final
# separator, which is exactly what is wanted here and costs one def instead of a
# string-accumulator fold.
def lt_lines(xs: List<&2, String>) -> String:
  String.join(xs, "\n")

# THE NODE LABEL, which is what pins `lin_srcs`: `RANGE:<axis id>` for a RANGE and
# the op NAME for everything else. CPython has no per-node index in this fork
# (ops.py:842 keeps only the counter), so the toposort is pinned by a label; and
# the three CONST/CAST pairs are told apart by their ADJACENCY -- each is CONST
# then CAST -- which is why a CONST needs no value printed and why building the
# CAST explicitly above is load-bearing rather than cosmetic.
def lt_lab.ids(ids: List<&2, U32>) -> U32:
  P.at(ids, 0n)

def lt_lab.range.pick(a: O.Arg) -> String:
  match a:
    case O.ARange{ids, at}: String.concat(["RANGE:", U32.show(lt_lab.ids(ids))])
    case _: ""

def lt_lab.range.of(a: O.Arg) -> String:
  lt_lab.range.pick(a)

def lt_lab.range(+ar: O.Arena, +v: U32) -> String:
  lt_lab.range.of(O.Arena.arg(ar, v))

def lt_lab.pick(c: Bool, a: String, +b: String) -> String:
  Bool.pick(String, c, a, b)

def lt_lab.of(+ar: O.Arena, +v: U32) -> String:
  lt_lab.pick(P.lt_is_range(O.Arena.op(ar, v)), lt_lab.range(ar, v), O.Ops.name.of(O.Arena.op(ar, v)))

# `lin_srcs` SPACES ITS PIECES, so a missing element is a double space and a
# doubled one is a repeat -- `String.join(xs, "")` would make both invisible.
def lt_srcs.go(+ar: O.Arena, ix: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ix:
    case Nil{}   : acc
    case v <> +r : lt_srcs.go(ar, r, List.append(&2, String, acc, [lt_lab.of(ar, v)]))

def lt_srcs(+ar: O.Arena, ix: List<&2, U32>) -> String:
  String.join(lt_srcs.go(ar, ix, Nil{}), " ")

# `lin_edg` -- the edge list, in the declared toposort's own positions. this is
# THE ROW `lin_srcs` COULD NOT BE.
#
# The defect, measured and not argued. `P.lt_lst()` and `P.lt_vm_lst()` are LITERALS
# read off CPython, and every other row reads the arena only for a node's OP and
# ARG (`lt_lab`, `P.lt_extra`, `P.lt_addr_of`). `P.lt_deg` walks `Arena.src_without_body`
# but `out_degree` is a COUNT OF OCCURRENCES (linearizer.py:11,16-17), so a
# permutation of one node's srcs leaves it identical. The consequence: swapping
# any src list in `P.lt_fix()` -- an SINK's, an END's, a RANGE's, either ADD's --
# moves NOTHING, while CPython's answer over the same seven graphs moves in 2, 0,
# 20, 6, 9, 3 and 10 rows (`.agents/slop/order-lin-sweep.sh`). The gate was green
#
# THE ALPHABET IS A POSITION, NOT AN ARENA INDEX, and that is the whole design.
# CPython derives positions from its OWN `toposort`; the port derives them from
# its OWN arena plus its OWN literal. Neither side borrows the other's fixture,
# and CPython's three-node CONST/CAST interning divergence (`lin_fixture`'s
# comment: `UOp.const(1, i32)` is one node here and two in `ops.bend`) stops
# mattering, because a position is a position either way.

# A src the declared toposort does not NAME answers `4294967295`, which is what
# `P.LtKey.ex`'s "no extra" sentinel already is. A disagreement between the arena
# and `P.lt_lst` therefore prints a sentinel rather than a plausible number.
def lt_pos.of(ix: List<&2, U32>, +u: U32, +n: U32, missing: U32) -> U32:
  match ix:
    case Nil{}   : missing
    case v <> +r : Bool.pick(U32, U32.is_eq(v, u), n, lt_pos.of(r, u, U32.add(n, 1), missing))

def lt_pos(ix: List<&2, U32>, u: U32) -> U32:
  lt_pos.of(ix, u, 0, 4294967295)

# ONE NODE'S SRCS, each already a position. `lt_u32s` is the same fold over the
# numbers themselves, so this is that fold with `lt_pos` in the step.
def lt_epos.go(+ix: List<&2, U32>, +ar: O.Arena, xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}   : acc
    case s <> +r : lt_epos.go(ix, ar, r, List.append(&2, String, acc, [U32.show(lt_pos(ix, s))]))

# `<position>:<src positions>`, one node per piece. A node with no srcs is
# `5:` and the trailing colon is what says so -- `String.join(xs, "")` would drop
# it and make an edgeless node indistinguishable from a missing one.
def lt_epos(ix: List<&2, U32>, +ar: O.Arena, xs: List<&2, U32>) -> String:
  String.join(lt_epos.go(ix, ar, xs, Nil{}), " ")

def lt_edg.piece(ix: List<&2, U32>, +ar: O.Arena, +n: U32, u: U32) -> String:
  String.concat([U32.show(n), ":", lt_epos(ix, ar, O.Arena.src_without_body(ar, u))])

def lt_edg.go(+ix: List<&2, U32>, rest: List<&2, U32>, +ar: O.Arena, +n: U32,
              +acc: List<&2, String>) -> List<&2, String>:
  match rest:
    case Nil{}   : acc
    case u <> +r : lt_edg.go(ix, r, ar, U32.add(n, 1),
                 List.append(&2, String, acc, [lt_edg.piece(ix, ar, n, u)]))

def lt_edg(+ar: O.Arena, +ix: List<&2, U32>) -> String:
  String.join(lt_edg.go(ix, ix, ar, 0, Nil{}), " ")

def lt_is_sink(op: O.Op) -> Bool:
  P.lt_op_is(op, O.OpsSINK{})

def lt_is_end(op: O.Op) -> Bool:
  P.lt_op_is(op, O.OpsEND{})

def lt_is_const(op: O.Op) -> Bool:
  P.lt_op_is(op, O.OpsCONST{})

def lt_is_cast(op: O.Op) -> Bool:
  P.lt_op_is(op, O.OpsCAST{})

# THE SORTED LIST, ONCE: `lt_lin_nkey`, `lt_lin_ties` and every `lin_u<i>` need
# it, and three independent sorts of the same keys are three chances to disagree.
def lt_srt.of(k: KER.K) -> List<&2, P.LtKey>:
  P.lt_sorted(P.lt_keys(F.Folded.ar(KER.K.fx(k)), P.lt_lst(), P.lt_vm_lst()))

def lt_srt() -> List<&2, P.LtKey>:
  lt_srt.of(P.lt_fix())

def lt_srt_call.of(k: KER.K) -> List<&2, P.LtKey>:
  P.lt_sorted(P.lt_keys(F.Folded.ar(KER.K.fx(k)), P.lt_lst_call(), P.lt_vm_call()))

def lt_srt_call() -> List<&2, P.LtKey>:
  lt_srt_call.of(P.lt_fix())

# THE ROWS. Grouped by the def they test, in that order.

# `ix_len` and `ix` -- THE FIXTURE'S OWN SIZE AND INDEX LIST. The notes' rule
# (mixin/creation, item 4) again: a fixture off by one is a fixture whose rows
# cannot be READ, and four rows of an earlier revision of this file answered 0
# because the CONST/CAST pair was missing from it.
def lt_ix_len.of(k: KER.K) -> U32:
  U32.from_nat(P.nlen(KER.K.ix(k)))

def lt_ix_len() -> U32:
  lt_ix_len.of(P.lt_fix())

def lt_ix.of(k: KER.K) -> String:
  lt_u32s(KER.K.ix(k))

def lt_ix() -> String:
  lt_ix.of(P.lt_fix())

# `rc_*` -- `P.lt_rc` IS `helpers.prod`, and on `lin` it only ever sees `[]`, `[3]`
# and `[15]`, which cannot tell a product from a sum. These six can, and
# `rc_max=65536` is ALSO the row that pins `P.lt_key`'s 26-bit run_count range.
def lt_rc_nil() -> U32:
  P.lt_rc(Nil{})

def lt_rc_1() -> U32:
  P.lt_rc([3])

def lt_rc_2() -> U32:
  P.lt_rc([3, 15])

def lt_rc_3() -> U32:
  P.lt_rc([1, 1, 4])

def lt_rc_max() -> U32:
  P.lt_rc([15, 15, 15, 15])

def lt_rc_big() -> U32:
  P.lt_rc([63, 63, 63])

# `po_*` -- one row per arm of the ladder, because a mutation dropping one arm of
# a disjunction moves only the row for that arm (`k_alu_recip`'s lesson).
# `po_bufl` and `po_bufg` are the two halves of `linearizer.py:27`'s conditional.
def lt_po_op2(local: Bool) -> U32:
  P.lt_po.w5(local, True{})

def lt_po_buf(local: Bool) -> U32:
  lt_po_op2(local)

def lt_po_param() -> U32:
  P.lt_po_op(O.OpsPARAM{})

def lt_po_bufl() -> U32:
  lt_po_buf(True{})

def lt_po_bufg() -> U32:
  lt_po_buf(False{})

def lt_po_load() -> U32:
  P.lt_po_op(O.OpsLOAD{})

def lt_po_store() -> U32:
  P.lt_po_op(O.OpsSTORE{})

def lt_po_range() -> U32:
  P.lt_po_op(O.OpsRANGE{})

def lt_po_end() -> U32:
  P.lt_po_op(O.OpsEND{})

def lt_po_backedge() -> U32:
  P.lt_po_op(O.OpsBACKEDGE{})

def lt_po_add() -> U32:
  P.lt_po_op(O.OpsADD{})

# `lin_*` -- THE PER-UOP TABLE. One row per uop in the LINEARIZED order carrying
# that node's op, its run_count, its priority offset and its nkey, and `lin_srcs`
# / `lin_vm` pin the two INPUTS the rows are computed from.
def lt_lin_srcs() -> String:
  lt_srcs(F.Folded.ar(KER.K.fx(P.lt_fix())), P.lt_lst())

def lt_lin_n() -> U32:
  U32.from_nat(P.nlen(P.lt_lst()))

def lt_vm_print(flat: List<&2, U32>) -> String:
  lt_u32s(flat)

def lt_lin_vm() -> String:
  lt_vm_print(P.lt_vm_lst())

# THE ACCUMULATOR IS A PARAMETER, not the recursive result, and that is the WHOLE
# difference between this row being right and being reversed:
#     List.append(acc, [x])           -- walk order
#     List.append(lt.go(tail), [x])   -- the head lands LAST, so it REVERSES
# Both compile, both run, and the reversed one is a permutation of the right answer
# -- every value present, every position wrong. `lin_ord` is what caught it, and
# the lesson generalises: a row whose oracle is a SET rather than a LIST cannot see
# this P.at all, which is why `lin_ties` is a separate row and why `lin_ord` (the
# sorted list itself) is gated alongside `lin_nkey`.
def lt_lin_nkey.go(ix: List<&2, U32>, +i: U32, +srt: List<&2, P.LtKey>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ix:
    case Nil{}   : acc
    case v <> +r : lt_lin_nkey.go(r, U32.add(i, 1), srt,
                                 List.append(&2, U32, acc, [P.lt_nkey(srt, v)]))

def lt_lin_nkey() -> String:
  lt_u32s(lt_lin_nkey.go(P.lt_lst(), 0, lt_srt(), Nil{}))

# `lin_ties` -- W2's SIZE. The number of node PAIRS that tie on (run_count,
# priority), which is exactly the number of pairs `x.tuplize` decides under
# `TUPLE_ORDER=1`. 47 of 171 pairs, so the `TUPLE_ORDER=1` order is NOT the
# `TUPLE_ORDER=0` order and W2 is load-bearing rather than cosmetic.
def lt_ties.pair(+done: List<&2, P.LtKey>, +e: P.LtKey, n: U32) -> U32:
  match done:
    case Nil{}    : n
    case +d <> +r : lt_ties.pair(r, e, U32.add(n, P.b2u(U32.is_eq(P.LtKey.k(d), P.LtKey.k(e)))))

def lt_ties.go(srt: List<&2, P.LtKey>, +done: List<&2, P.LtKey>, n: U32) -> U32:
  match srt:
    case Nil{}   : n
    case +e <> r : lt_ties.go(r, List.append(&2, P.LtKey, done, [e]), lt_ties.pair(done, e, n))

def lt_lin_ties() -> U32:
  lt_ties.go(lt_srt(), Nil{}, 0)

# `lin_u<i>` -- THE CENTRE OF THE GATE. A reordering bug has the right node COUNT
# and the wrong list, so the per-uop tuple (op, rc, po, nk) is the only thing that
# can see it -- and it is also the row class that says a run_count is wrong rather
# than a priority. The rows are printed by WALKING the answer, so a short answer
# produces FEWER rows and the byte diff shows it as a missing line. `pre` is the
# row class (`lin` or `linc`) because the IDENTITY fixture is this same walk over a
# second sink, and two row classes over one walk is one walk with a prefix.
def lt_lin_u.nm(+pre: String, pos: U32) -> String:
  String.concat([pre, "_u", U32.show(pos)])

def lt_lin_u.tag(+k: KER.K, +v: U32) -> String:
  O.Ops.name.of(O.Arena.op(F.Folded.ar(KER.K.fx(k)), v))

# THE POSITIONAL READ, with `Bool.pick` taking the self-call as an argument, which
# is legal because both arms are total: the discarded branch walks the rest of the
# list and throws the answer away. `+e` because `P.LtKey.rc(e)` and the `pos` test
# are two reads.
def lt_srt_rc(srt: List<&2, P.LtKey>, +pos: U32) -> U32:
  match srt:
    case Nil{}     : 0
    case +e <> +r  : Bool.pick(U32, U32.is_zero(pos), P.LtKey.rc(e), lt_srt_rc(r, U32.sub(pos, 1)))

def lt_lin_u.rc(+srt: List<&2, P.LtKey>, +v: U32) -> U32:
  lt_srt_rc(srt, P.lt_nkey(srt, v))

def lt_lin_u.p(+pre: String, pos: U32, +srt: List<&2, P.LtKey>, +k: KER.K, +v: U32) -> String:
  String.concat([lt_lin_u.nm(pre, pos), "=", lt_lin_u.tag(k, v), " rc=", U32.show(lt_lin_u.rc(srt, v)),
                 " po=", U32.show(P.lt_po(F.Folded.ar(KER.K.fx(k)), v)),
                 " nk=", U32.show(P.lt_nkey(srt, v))])

def lt_lin_u.go(+pre: String, ix: List<&2, U32>, +pos: U32, +srt: List<&2, P.LtKey>, +k: KER.K,
                +acc: List<&2, String>) -> List<&2, String>:
  match ix:
    case Nil{}   : acc
    case v <> +r : lt_lin_u.go(pre, r, U32.add(pos, 1), srt, k,
                              List.append(&2, String, acc, [lt_lin_u.p(pre, pos, srt, k, v)]))

# ONE `IO.print` PER ROW CLASS, so a byte diff against the oracle shows a moved uop
# as a CHANGED line and a lost uop as a MISSING line -- never as a row count alone.
def lt_rows(+pre: String, +ix: List<&2, U32>, +srt: List<&2, P.LtKey>, +k: KER.K) -> IO(Unit):
  IO.print(lt_lines(lt_lin_u.go(pre, ix, 0, srt, k, Nil{})))

# THE IDENTITY SINK. `linc_*` is `SINK(CALL(STORE, ADD))`: six nodes, every
# priority already in nkey order, so `P.linearize` must return the input unchanged.
def lt_linc_srcs() -> String:
  lt_srcs(F.Folded.ar(KER.K.fx(P.lt_fix())), P.lt_lst_call())

def lt_linc_n() -> U32:
  U32.from_nat(P.nlen(P.lt_lst_call()))

def lt_linc_vm() -> String:
  lt_vm_print(P.lt_vm_call())

def lt_lin_edg() -> String:
  lt_edg(F.Folded.ar(KER.K.fx(P.lt_fix())), P.lt_lst())

def lt_linc_edg() -> String:
  lt_edg(F.Folded.ar(KER.K.fx(P.lt_fix())), P.lt_lst_call())

def lt_linc_nkey() -> String:
  lt_u32s(lt_lin_nkey.go(P.lt_lst_call(), 0, lt_srt_call(), Nil{}))

def lt_linc_ties() -> U32:
  lt_ties.go(lt_srt_call(), Nil{}, 0)

def lt_linc_rows() -> IO(Unit):
  lt_rows("linc", P.linearize(F.Folded.ar(KER.K.fx(P.lt_fix())), P.lt_lst_call(), P.lt_vm_call(), 21),
          lt_srt_call(), P.lt_fix())

# `lin_exmix` -- WHY `extra` IS NOT A FIELD. The COUNT of node pairs that tie on
# the composite key (run_count, priority) and disagree on whether `extra` is
# `None`. It is 0, so `extra` is never compared ACROSS types and Python -- which
# would raise `TypeError` on `None < int` -- does not raise. It is a gate and not
# a comment because dropping `extra` from `priorities` is only sound while it is
# 0, and `P.LtKey`'s fourth field exists to make this row computable.
def lt_exmix.hit(+d: P.LtKey, +e: P.LtKey) -> Bool:
  Bool.and(U32.is_eq(P.LtKey.k(d), P.LtKey.k(e)),
           Bool.xor(U32.is_eq(P.LtKey.ex(d), 4294967295), U32.is_eq(P.LtKey.ex(e), 4294967295)))

def lt_exmix.pair(+done: List<&2, P.LtKey>, +e: P.LtKey, n: U32) -> U32:
  match done:
    case Nil{}    : n
    case +d <> +r : lt_exmix.pair(r, e, U32.add(n, P.b2u(lt_exmix.hit(d, e))))

# the walk list is the first parameter and the accumulator is second, so the
# self-call's shrinking argument -- the tail -- is first and the GROWING list
# (`done`) is second. That is the notes' rule 5 read left to right, and it is
# also why this is not the same shape as `lt_ties.go` above: two accumulators
# cannot both be parameters after the tail, so the new `done` is a computed
# argument and the decrease check only ever sees the tail.
# the call must pass the sort first. `lt_exmix.go(Nil{}, lt_srt(), 0)` typechecks
# -- both parameters are the same type -- and answers 0 because the walk list is
# empty, so the row was green and MEASURING NOTHING. Two same-typed parameters in
# a fold are a silent swap, and the row that catches one COUNTS a difference
# rather than testing a predicate.
def lt_exmix.go(walk: List<&2, P.LtKey>, +done: List<&2, P.LtKey>, n: U32) -> U32:
  match walk:
    case Nil{}   : n
    case +e <> +r : lt_exmix.go(r, List.append(&2, P.LtKey, done, [e]), lt_exmix.pair(done, e, n))

def lt_lin_exmix() -> U32:
  lt_exmix.go(lt_srt(), Nil{}, 0)

def lt_linc_exmix() -> U32:
  lt_exmix.go(lt_srt_call(), Nil{}, 0)

def lt_srt_idx.go(srt: List<&2, P.LtKey>, +acc: List<&2, U32>) -> List<&2, U32>:
  match srt:
    case Nil{}   : acc
    case e <> +r : lt_srt_idx.go(r, List.append(&2, U32, acc, [P.LtKey.i(e)]))

def lt_srt_idx() -> List<&2, U32>:
  lt_srt_idx.go(lt_srt(), Nil{})

def lt_srt_call_idx() -> List<&2, U32>:
  lt_srt_idx.go(lt_srt_call(), Nil{})

# `CFGContext` -- linearizer.py:53-81, and `pm_add_control_flow` :83-85.
#
# the three tables are one record. `deps` is a U32 -> set of U32 map, `nesting`
# and `edges` are U32 -> U32 maps, all three are `P.RaTb`, and all three are keyed
# by an arena index -- which is why `Cfg` is a two-field `Data` record and not
# three parameters every call site has to keep in step. The walk is
# `for u in sink.toposort()` (:62) and for the `lin` sink `enter_calls=True`
# makes no difference (its only CALL belongs to the separate `linc` sink), so the
# walk list is `P.lt_lst` again.
#
# THE SET IS A LIST, and that is not a convenience. `deps[u]` is a DICT whose
# ITERATION ORDER decides which range `nesting` claims first, and `cfg_edges` is
# printed in `edges` insertion order, so a membership-only container would throw
# the row away. `|=` keeps an existing key's position and appends a new one, so
# the union is `a ++ [x for x in b if x not in a]` and NOT a fold that rebuilds
# the left side from the right.

type Cfg is Data:
  Cfg{dp: P.RaTb, ns: P.RaTb}

def Cfg.dp(c: Cfg) -> P.RaTb:
  match c:
    case Cfg{dp, ns}: dp

def Cfg.ns(c: Cfg) -> P.RaTb:
  match c:
    case Cfg{dp, ns}: ns

# `deps[u] |= deps[s]` -- and the two arms are the dict's two behaviours: an
# existing key keeps its slot, a new key takes the next one. `+x` because
# `List.contains` and `[x]` are two reads.
def cfg_cat.a(+xs: List<&2, U32>, +x: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, List.contains(U32, U32.is_eq, xs, x),
            xs, List.append(&2, U32, xs, [x]))

# THE WALK LIST IS FIRST so the decrease check sees the tail (notes' rule 5).
def cfg_cat(ys: List<&2, U32>, +xs: List<&2, U32>) -> List<&2, U32>:
  match ys:
    case Nil{}   : xs
    case +y <> +r : cfg_cat(r, cfg_cat.a(xs, y))

# `for s in u.src: deps[u] |= deps[s]` -- :65, ONE fold over the node's srcs.
def cfg_deps(ss: List<&2, U32>, +deps: P.RaTb, +acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}   : acc
    case +s <> +r : cfg_deps(r, deps, cfg_cat(P.tb_vs(deps, s), acc))

def lt_is_loopend(+op: O.Op) -> Bool:
  Bool.or(P.lt_is_range(op), P.lt_is_exit(op))

# :67's `u.op in (Ops.END, Ops.BACKEDGE, Ops.SINK)` is NOT :69's
# `u.op in (Ops.RANGE, Ops.END, Ops.BACKEDGE)` -- the SINK is on the nesting line
# and the RANGE is on the self-add line, and the two sets differ in exactly one op
# each. One predicate for both is a silent bug that drops every SINK's edges.
def lt_is_loopnest(+op: O.Op) -> Bool:
  Bool.or(lt_is_sink(op), P.lt_is_exit(op))

# `deps[u][u] = None` -- :69, and it runs AFTER the `nesting` scan on the line
# above, so the scan must NOT see `u` in `deps[u]`. The order of these two defs
# is the order of the two lines.
def cfg_self.of(+op: O.Op, u: U32, +d: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, lt_is_loopend(op), List.append(&2, U32, d, [u]), d)

def cfg_self(ar: O.Arena, +u: U32, +d: List<&2, U32>) -> List<&2, U32>:
  cfg_self.of(O.Arena.op(ar, u), u, d)

# `nesting |= {x:u for x in deps[u] if x.op in (END,BACKEDGE) and (u.op is SINK
# or u.src[1] in deps[x]) and x not in nesting}` -- :68. Three conjuncts, and the
# `x not in nesting` one is why this is a `Bool.pick` over a `P.tb_put` and not a
# put: `|=` keeps the FIRST claim and drops a second. `O.Arena.src(ar, u, 1)` is
# read unconditionally (`Bool.pick` is strict) even when `u` is a SINK; a node
# with fewer than two srcs reads the bottom, whose `deps` bucket is empty, so the
# test answers False either way.
# `u.op is Ops.SINK or u.src[1] in deps[x]` IS A SHORT-CIRCUIT `or`, and
# `Bool.or` IS NOT ONE: it evaluates both sides, so for a SINK it evaluates
# `deps[x]` against `sk.src[1]` and then `Bool.and`s a FALSE into the answer.
# `Bool.pick` reproduces the short-circuit as a VALUE choice -- the discarded
# branch still runs, but its answer is not ANDed in.
def cfg_nest.dep(+ar: O.Arena, +c: Cfg, +u: U32, +x: U32) -> Bool:
  Bool.pick(Bool, lt_is_sink(O.Arena.op(ar, u)),
            True{}, List.contains(U32, U32.is_eq, P.tb_vs(Cfg.dp(c), x), O.Arena.src(ar, u, 1)))

def cfg_nest.ok(+ar: O.Arena, +c: Cfg, +u: U32, +x: U32) -> Bool:
  Bool.and(P.lt_is_exit(O.Arena.op(ar, x)),
           Bool.and(cfg_nest.dep(ar, c, u, x), Bool.not(P.tb_has(Cfg.ns(c), x))))

def cfg_nest.hit(ok: Bool, +c: Cfg, +x: U32, +u: U32) -> Cfg:
  Bool.pick(Cfg, ok, Cfg{Cfg.dp(c), P.tb_put(Cfg.ns(c), x, u, Nil{})}, c)

def cfg_nest(d: List<&2, U32>, +ar: O.Arena, +c: Cfg, +u: U32) -> Cfg:
  match d:
    case Nil{}   : c
    case +x <> +r : cfg_nest(r, ar, cfg_nest.hit(cfg_nest.ok(ar, c, u, x), c, x, u), u)

# ONE NODE, in PYTHON's order: `deps[u]` is written first (:64-65 and :69) and
# the `nesting` scan runs second (:68), so the scan's ITERATION list is `d` -- the
# bucket BEFORE the self-add -- passed in as an argument rather than re-read from
# the table. BOTH ARMS write the bucket, and that is the load-bearing part: the
# write is `deps[u] = ...` for EVERY node, so folding it into the `if` arm alone
# leaves every CONST, CAST, STORE and RANGE with NO BUCKET, and the whole section
# then reads zero edges. `cfg_edges` is the row that saw it.
def cfg_step.of(+c: Cfg, +ar: O.Arena, +u: U32, +d: List<&2, U32>) -> Cfg:
  Cfg{P.tb_put(Cfg.dp(c), u, 0, cfg_self(ar, u, d)), Cfg.ns(c)}

def cfg_step.go(+c: Cfg, +ar: O.Arena, +u: U32, +d: List<&2, U32>) -> Cfg:
  Bool.pick(Cfg, lt_is_loopnest(O.Arena.op(ar, u)),
            cfg_nest(d, ar, cfg_step.of(c, ar, u, d), u), cfg_step.of(c, ar, u, d))

def cfg_step(+c: Cfg, +ar: O.Arena, +u: U32) -> Cfg:
  cfg_step.go(c, ar, u, cfg_deps(O.Arena.srcs(ar, u), Cfg.dp(c), Nil{}))

def cfg_go(rest: List<&2, U32>, +ar: O.Arena, +c: Cfg) -> Cfg:
  match rest:
    case Nil{}   : c
    case u <> +r : cfg_go(r, ar, cfg_step(c, ar, u))

def cfg_ctx(ar: O.Arena) -> Cfg:
  cfg_go(P.lt_lst(), ar, Cfg{P.tb_new(), P.tb_new()})

# `siblings.setdefault(vv, []).append(k)` -- :73. One bucket per parent, in
# `nesting` INSERTION order, and the bucket IS the table's `vs` field, so
# `.append(k)` is `P.tb_put` with `vs = [k]`: `P.tb_ins.cat` PREPENDS the argument to
# the bucket already there, and the new tail is the whole argument. Walking
# `P.tb_keys(ns)` rather than `P.RaTb.es(ns)` is what keeps the insertion order.
#
# THE ACCUMULATOR IS ITS OWN PARAMETER, separate from `ns`, and that is load
# bearing. Handing `put` the SOURCE table -- which typechecks, because both are
# `P.RaTb` -- makes every iteration rebuild on `nesting` and the answer is the
# nesting table plus one entry per iteration, never merged. `cfg_edges_n` is the
# row that saw it, and it saw 1 where the merge would have given 1 as well: the
# bucket that mattered was never built.
def cfg_sib.put(+acc: P.RaTb, +ns: P.RaTb, +u: U32, +k: U32) -> P.RaTb:
  P.tb_put(acc, u, k, [k])

def cfg_sib.go(+ns: P.RaTb, ks: List<&2, U32>, +acc: P.RaTb) -> P.RaTb:
  match ks:
    case Nil{}   : acc
    case +k <> +r : cfg_sib.go(ns, r, cfg_sib.put(acc, ns, P.tb_get(ns, k), k))

def cfg_sib(+ns: P.RaTb) -> P.RaTb:
  cfg_sib.go(ns, P.tb_keys(ns), P.tb_new())

# `sorted(v, key=lambda x: len([u for u in v if u in deps[x]]))` -- :76. A
# STABLE SORT on a COUNT, so the element is a two-field record (the count key and
# the node) and the comparator is `<=` on the count -- exactly the shape
# `P.lt_sorted` is for the linearizer's keys. `Sb` is therefore the SECOND
# composite key in this file and it exists for the same reason as the first:
# `List.sort` wants `A -> A -> Bool` and a count is not a field of the element.
type Sb is Data:
  Sb{ks: U32, i: U32}

def Sb.ks(x: Sb) -> U32:
  match x:
    case Sb{ks, i}: ks

def Sb.i(x: Sb) -> U32:
  match x:
    case Sb{ks, i}: i

# `List.sort`'s COMPARATOR TYPE IS `@a -> @b -> Bool` WITH NO ANNOTATION, so a
# comparator's parameters must stay BARE: `+b` is refused with "expected
# @_:Sb -> @_:Sb -> Bool, observed @a:Sb -> @+b:Sb -> Bool". Every comparator here reads
# each field ONCE, which is what `Sb.ks(a)` and not a `match` is for.
def sb_le(a: Sb, b: Sb) -> Bool:
  U32.is_le(Sb.ks(a), Sb.ks(b))

# `reverse=True` -- `sorted(rngs, key=..., reverse=True)` P.at :90 is the SAME sort
# with the comparison FLIPPED, not a reversal of the output, so `>=` over a stable
# merge is exactly it and equal keys keep their input order.
def sb_ge(a: Sb, b: Sb) -> Bool:
  U32.is_ge(Sb.ks(a), Sb.ks(b))

def cfg_cnt.hit(ok: Bool, +n: U32) -> U32:
  Bool.pick(U32, ok, U32.add(n, 1), n)

def cfg_cnt(+vs: List<&2, U32>, +deps: P.RaTb, +x: U32, +n: U32) -> U32:
  match vs:
    case Nil{}   : n
    case u <> +r : cfg_cnt(r, deps, x, cfg_cnt.hit(List.contains(U32, U32.is_eq, P.tb_vs(deps, x), u), n))

def cfg_key(+vs: List<&2, U32>, +deps: P.RaTb, rest: List<&2, U32>) -> List<&2, Sb>:
  match rest:
    case Nil{}   : Nil{}
    case +x <> +r : List.append(&2, Sb, [Sb{cfg_cnt(vs, deps, x, 0), x}], cfg_key(vs, deps, r))

def cfg_unkey(srt: List<&2, Sb>, +acc: List<&2, U32>) -> List<&2, U32>:
  match srt:
    case Nil{}   : acc
    case +e <> +r : cfg_unkey(r, List.append(&2, U32, acc, [Sb.i(e)]))

def cfg_order(+vs: List<&2, U32>, +deps: P.RaTb) -> List<&2, U32>:
  cfg_unkey(List.sort(Sb, sb_le, cfg_key(vs, deps, vs)), Nil{})

# `for x,y in zipped: self.edges[y.src[1]] = x` -- :78-81, and BOTH `zipped`
# spellings P.at :77 are "consecutive pairs of ONE list": the SINK case is the PLAIN
# `order` and the non-SINK case prepends `k.src[1]` to it, so there is ONE walk and
# not a two-arm dispatch. The dispatch is one predicate wide and getting it
# backwards is invisible in the EDGE COUNT on a fixture with one bucket: the SINK
# arm gives 2 pairs over a 2-element list where the non-SINK arm gives 1, and
# `cfg_edges` is the row that names the extra one.
# W3: `assert y.src[1] not in x.backward_slice_with_self` (:80) is NOT PORTED.
# `backward_slice_with_self` is a recursive reachability over UOps and this arena
# has no such reader; :79's own comment says the assert "can happen" on
# shufflenet, so it is a live guard, not a dead one. The claim that dropping it is
# safe ON THIS FIXTURE is `cfg_edges_n` and the shape of `cfg_hits`.
def cfg_edge.put(+ed: P.RaTb, +ar: O.Arena, x: U32, y: U32) -> P.RaTb:
  P.tb_put(ed, O.Arena.src(ar, y, 1), x, Nil{})

# THE RECURSION IS ON THE TAIL AFTER `x`, not after `y`. `zip(xs, xs[1:])` is
# (xs[0],xs[1]), (xs[1],xs[2]), ... and the OVERLAP is the whole of it: recursing
# past `y` answers only the disjoint pairs, so a three-element list gives one edge
# where `zip` gives two. `List.is_empty` on the tail is `zip`'s one-element case
# (it yields nothing) and it is the ONLY guard, because `P.at(r, 0n)` on an empty
# tail answers 0 -- the bottom -- which would invent an edge.
def cfg_edge(rest: List<&2, U32>, +ed: P.RaTb, +ar: O.Arena) -> P.RaTb:
  match rest:
    case Nil{}        : ed
    case +x <> +r     : Bool.pick(P.RaTb, List.is_empty(&2, U32, r), ed,
                          cfg_edge(r, cfg_edge.put(ed, ar, x, P.at(r, 0n)), ar))

def cfg_bucket(+ed: P.RaTb, +ar: O.Arena, +k: U32, +vs: List<&2, U32>) -> P.RaTb:
  Bool.pick(P.RaTb, lt_is_sink(O.Arena.op(ar, k)),
            cfg_edge(vs, ed, ar),
            cfg_edge(List.append(&2, U32, [O.Arena.src(ar, k, 1)], vs), ed, ar))

def cfg_edges(rest: List<&2, P.RaEn>, +ar: O.Arena, +deps: P.RaTb, +ed: P.RaTb) -> P.RaTb:
  match rest:
    case Nil{}   : ed
    case +e <> +r : cfg_edges(r, ar, deps, cfg_bucket(ed, ar, P.RaEn.k(e), cfg_order(P.RaEn.vs(e), deps)))

# `nesting` is `dict[child, parent]` and `siblings` is `dict[parent, [child]]` --
# two different keys -- so the regrouping is a real step and NOT the identity, and
# walking `nesting` directly would bucket every child under ITSELF.
def cfg_ed(ar: O.Arena, +c: Cfg) -> P.RaTb:
  cfg_edges(P.RaTb.es(cfg_sib(Cfg.ns(c))), ar, Cfg.dp(c), P.tb_new())

# `pm_add_control_flow` -- linearizer.py:83-85. ONE rule, ONE op, and the whole
# rewrite is `x.src + (edges[x],)`, so the table is two rows and the answer is
# either the new node's src list or `-`.

def cfg_tbl() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsRANGE{}], Nil{}}]

# `.replace` keeps `arg` and `tag` and the arena hash-conses, so a rewrite whose
# `src` is unchanged answers the same index. The `hit` flag is a separate field
# rather than a comparison of indices because the MISS arm does not build a node
# P.at all -- Python's `else None` is the absence of an edge, and an index
# comparison would confuse "no edge" with "the edge is the node itself".
type Cg is Data:
  Cg{ar: O.Arena, hit: Bool, ix: U32}

def Cg.ar(+c: Cg) -> O.Arena:
  match c:
    case Cg{ar, hit, ix}: ar

def Cg.hit(+c: Cg) -> Bool:
  match c:
    case Cg{ar, hit, ix}: hit

def Cg.ix(+c: Cg) -> U32:
  match c:
    case Cg{ar, hit, ix}: ix

def cfg_rewrite.put(+f: O.Found) -> Cg:
  Cg{O.Found.ar(f), True{}, O.Found.i(f)}

def cfg_rewrite.new(+ar: O.Arena, ed: P.RaTb, +x: U32) -> Cg:
  cfg_rewrite.put(O.UOp.new(ar, O.OpsRANGE{},
                            List.append(&2, U32, O.Arena.srcs(ar, x), [P.tb_get(ed, x)]),
                            O.Arena.arg(ar, x), O.Arena.tag(ar, x)))

def cfg_rewrite.pick(hit: Bool, +ar: O.Arena, +ed: P.RaTb, +x: U32) -> Cg:
  Bool.pick(Cg, hit, cfg_rewrite.new(ar, ed, x), Cg{ar, False{}, x})

def cfg_rewrite(+ar: O.Arena, +ed: P.RaTb, +x: U32) -> Cg:
  cfg_rewrite.pick(P.tb_has(ed, x), ar, ed, x)

# THE `cfg_*` ROWS. `cfg_edges` prints `key/axis->value.op` in `edges` insertion
# order, which is why the assoc list's key order had to be Python's.

def lt_slash.axis(a: O.Arg) -> U32:
  match a:
    case O.ARange{ids, at}: lt_lab.ids(ids)
    case _: 0

def lt_slash.of(+op: O.Op, +a: O.Arg) -> String:
  Bool.pick(String, P.lt_is_range(op),
            String.concat(["RANGE/", U32.show(lt_slash.axis(a))]),
            O.Ops.name.of(op))

def lt_slash(+ar: O.Arena, +v: U32) -> String:
  lt_slash.of(O.Arena.op(ar, v), O.Arena.arg(ar, v))

# `List.get` answers a `Maybe` and every table here is non-empty by construction,
# so the table read has ONE `Maybe.default` and every other table read is the
# table itself.
def cfg_entry(ts: List<&2, O.PMEntry>, n: Nat) -> O.PMEntry:
  Maybe.default(&2, O.PMEntry, List.get(&2, O.PMEntry, ts, n), O.PMEntry{0, Nil{}, Nil{}})

def lt_ops_name.go(ops: List<&2, O.Op>, +acc: List<&2, String>) -> List<&2, String>:
  match ops:
    case Nil{}   : acc
    case +o <> +r : lt_ops_name.go(r, List.append(&2, String, acc, [O.Ops.name.of(o)]))

def lt_ops_name(ops: List<&2, O.Op>) -> String:
  String.join(lt_ops_name.go(ops, Nil{}), " ")

def cfg_edges_str(rest: List<&2, P.RaEn>, +ar: O.Arena, +acc: List<&2, String>) -> List<&2, String>:
  match rest:
    case Nil{}    : acc
    case +e <> +r : cfg_edges_str(r, ar, List.append(&2, String, acc,
                          [String.concat([lt_slash(ar, P.RaEn.k(e)), "->",
                                          O.Ops.name.of(O.Arena.op(ar, P.RaEn.v(e)))])]))

def cfg_edges_row(+ar: O.Arena, +ed: P.RaTb) -> String:
  String.join(cfg_edges_str(P.RaTb.es(ed), ar, Nil{}), " ")

def cfg_edges_n(+ed: P.RaTb) -> U32:
  U32.from_nat(P.nlen(P.tb_keys(ed)))

# `cfg_hits` -- the rewrite's answer per range, `-` where `edges.get(x)` is None.
# The range pair is the FIXTURE's two RANGEs (`linc` has none) and it is a literal
# for the same reason `P.lt_lst` is: it is an input, not a computed answer.
def cfg_rngs() -> List<&2, U32>:
  [10, 15]

# `lt_srcs` SPACES its pieces, so this row needs its own COMMA join: the oracle's
# `','.join(u.op.name for u in r2.src)` is a different separator, and reusing the
# space-joined printer would make the row a diff over punctuation.
def cfg_hit.of(+c: Cg, +ar: O.Arena, +r: U32) -> String:
  Bool.pick(String, Cg.hit(c),
            String.concat([U32.show(lt_slash.axis(O.Arena.arg(ar, r))), "->[",
                           String.join(lt_srcs.go(Cg.ar(c), O.Arena.srcs(Cg.ar(c), Cg.ix(c)), Nil{}), ","),
                           "]"]),
            "-")

def cfg_hit(+ar: O.Arena, +ed: P.RaTb, +r: U32) -> String:
  cfg_hit.of(cfg_rewrite(ar, ed, r), ar, r)

def cfg_hits.go(rs: List<&2, U32>, +ar: O.Arena, +ed: P.RaTb, +acc: List<&2, String>) -> List<&2, String>:
  match rs:
    case Nil{}    : acc
    case +r <> +t : cfg_hits.go(t, ar, ed, List.append(&2, String, acc, [cfg_hit(ar, ed, r)]))

def cfg_hits(+ar: O.Arena, +ed: P.RaTb) -> String:
  String.join(cfg_hits.go(cfg_rngs(), ar, ed, Nil{}), " ")

def cfg_tbl_len() -> U32:
  KER.n_of(cfg_tbl())

def cfg_tbl_ops() -> String:
  lt_ops_name(O.PMEntry.ops(cfg_entry(cfg_tbl(), 0n)))

# `do_split_ends` and `pm_split_ends` -- linearizer.py:87-96.
#
# W1: `((s,) if s.op is Ops.RANGE else s.ranges)` -- :89. The `else` half is a
# `UOp.ranges` READER and is NOT PORTED; `se_ranges.of` answers the empty list
# there. The fixture is built so every `e.src[1:]` IS a RANGE (the oracle's own
# comment says the same), so the arm is NAMED and not exercised -- a wall, not a
# closed one. `se_rngs` is the row that would move if the arm were filled in for
# a fixture that had a non-RANGE src, and `se_len` counts the END nodes actually
# BUILT, so a stub that built one END instead of three would be caught.

def se_dup1(+acc: List<&2, U32>, +s: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, List.contains(U32, U32.is_eq, acc, s),
            acc, List.append(&2, U32, acc, [s]))

# `dedup` is `H.dedup_u32` REVERSED, so it is written here rather than shared:
# `dedup` as a SET is order-blind and `dedup` as a LIST is not, and this one is
# the list kind because it feeds a `sorted`.
def se_dedup(ss: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}   : acc
    case +s <> +r : se_dedup(r, se_dup1(acc, s))

def se_ranges.of(+ar: O.Arena, +s: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, P.lt_is_range(O.Arena.op(ar, s)), [s], Nil{})

def se_rngs(ss: List<&2, U32>, +ar: O.Arena, +acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}   : acc
    case +s <> +r : se_rngs(r, ar, se_dedup(List.append(&2, U32, se_ranges.of(ar, s), acc), acc))

def se_key(+rngs: List<&2, U32>, +ar: O.Arena, rest: List<&2, U32>) -> List<&2, Sb>:
  match rest:
    case Nil{}   : Nil{}
    case +x <> +r : List.append(&2, Sb, [Sb{lt_slash.axis(O.Arena.arg(ar, x)), x}], se_key(rngs, ar, r))

def se_unkey(srt: List<&2, Sb>, +acc: List<&2, U32>) -> List<&2, U32>:
  match srt:
    case Nil{}   : acc
    case +e <> +r : se_unkey(r, List.append(&2, U32, acc, [Sb.i(e)]))

# `key=lambda x: x.arg, reverse=True` -- :90. `x.arg` for a RANGE is the axis
# tuple, so the key is the axis id and the sort is DESCENDING.
def se_sort(+ar: O.Arena, +rngs: List<&2, U32>) -> List<&2, U32>:
  se_unkey(List.sort(Sb, sb_ge, se_key(rngs, ar, rngs)), Nil{})

# `ret = ret.end(r)` -- :90. `UOp.end` is `UOp(Ops.END, (ret, r), None)`, which
# returns the new ARENA as well as the index, so `Se` carries both. The recursion
# calls the two-call constructor twice because the arena and the index come from
# separate reads; interning makes the two answers the same node so they agree, and
# the alternative -- threading one four-field record -- costs a def for a
# property of the hash-cons.
type Se is Data:
  Se{ar: O.Arena, i: U32}

def Se.ar(x: Se) -> O.Arena:
  match x:
    case Se{ar, i}: ar

def Se.i(x: Se) -> U32:
  match x:
    case Se{ar, i}: i

def Se.of(+f: O.Found) -> Se:
  Se{O.Found.ar(f), O.Found.i(f)}

def se_end(+ret: U32, r: U32, +ar: O.Arena) -> Se:
  Se.of(O.UOp.new(ar, O.OpsEND{}, [ret, r], O.ANone{}, O.TNone{}))

def do_split_ends(rngs: List<&2, U32>, +ret: U32, +ar: O.Arena) -> Se:
  match rngs:
    case Nil{}   : Se{ar, ret}
    case +x <> +t : do_split_ends(t, Se.i(se_end(ret, x, ar)), Se.ar(se_end(ret, x, ar)))

# `do_split_ends` -- :87-91. `ret = e.src[0]` and the range list, sorted descending
# by axis, is the loop's fuel.
def se_rngs_of(+ar: O.Arena, e: U32) -> List<&2, U32>:
  se_sort(ar, se_rngs(O.Arena.src_from(ar, e, 1), ar, Nil{}))

def se_of(+ar: O.Arena, +e: U32) -> Se:
  do_split_ends(se_rngs_of(ar, e), O.Arena.src(ar, e, 0), ar)

# `pm_split_ends` -- :93-96. ONE rule on END, so `se_tbl_len`, `se_tbl_ops` and the
# `se_fired`/`se_miss` pair are the whole table, and the MISS row is the
# non-movement fixture the notes' rule 17 asks for.
def se_tbl() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsEND{}], Nil{}}]

def se_fired(+ar: O.Arena, v: U32) -> U32:
  P.b2u(lt_is_end(O.Arena.op(ar, v)))

# `se_len` is the COUNT of END nodes in the arena `do_split_ends` BUILT, walked
# over the node list -- not `P.nlen(rngs)`. The two agree because the loop is
# `for r in sorted(rngs): ret = ret.end(r)`, and counting is the honest gate: a
# `se_len` derived from the range list would still read 3 if the loop body
# stopped building an END.
def se_cnt(rest: List<&2, O.Node>, +n: U32) -> U32:
  match rest:
    case Nil{}    : n
    case +d <> +r : se_cnt(r, Bool.pick(U32, lt_is_end(O.Node.op(d)), U32.add(n, 1), n))

# and minus the one end the fixture started with, because the arena is walked, not
# the graph: `e` is not in `ret`'s toposort but it IS in the arena.
def se_len(+se: Se, skip: U32) -> U32:
  U32.sub(se_cnt(O.Arena.nodes(Se.ar(se)), 0), skip)

def se_nsrc(+se: Se) -> U32:
  O.Arena.nsrc(Se.ar(se), Se.i(se))

# THE TOPOSORT of the built graph, as a LITERAL, for the same reason `P.lt_lst` is
# one: `toposort` is ops.py's and not this file's, and a literal that disagrees
# is the row `se_ops` rather than a silent difference under it. The LABELS come
# from the arena, so `se_ops` still gates the built graph -- a `se_len` of 3 over
# the wrong three nodes changes it.
#   F2's CONST/CAST, then R2's CONST/CAST and R2, then the first END, then R1's
# CONST/CAST and R1, then the second END, then R0 (whose CONST is already cached)
# and the third END. `e` itself is NOT in `ret`'s graph, so it is absent.
def se_lst() -> List<&2, U32>:
  [5, 6, 1, 2, 9, 11, 3, 4, 8, 12, 7, 13]

def se_lab.of(+op: O.Op, +a: O.Arg) -> String:
  String.concat([O.Ops.name.of(op), "/",
                 Bool.pick(String, P.lt_is_range(op), U32.show(lt_slash.axis(a)), "-")])

def lt_lab2.go(ix: List<&2, U32>, +ar: O.Arena, +acc: List<&2, String>) -> List<&2, String>:
  match ix:
    case Nil{}   : acc
    case +v <> +r : lt_lab2.go(r, ar, List.append(&2, String, acc, [se_lab.of(O.Arena.op(ar, v), O.Arena.arg(ar, v))]))

def se_lab_str(+ar: O.Arena, ix: List<&2, U32>) -> String:
  String.join(lt_lab2.go(ix, ar, Nil{}), " ")

def se_tbl_len() -> U32:
  KER.n_of(se_tbl())

def se_tbl_ops() -> String:
  lt_ops_name(O.PMEntry.ops(cfg_entry(se_tbl(), 0n)))

# THE `se` FIXTURE. `e = END(F2, R0, R1, R2)` with the three axes in ASCENDING
# order, so `sorted(key=arg, reverse=True)` is a REORDER and not the identity --
# `se_rngs` reading `0 1 2` would be a `sorted` that does nothing. R0 and R2
# share the CONST 4 and R1 has the CONST 8, so the three `CONST/CAST` PAIRS are
# all reachable and `se_ops` shows three of them.
#   1 C4a 2 C4  3 C8a 4 C8  5 C2f 6 F2  7 R0 8 R1 9 R2  10 E
def se_fix() -> KER.K:
  +c4a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(4)})
  +c4 = P.lt_i32(4, O.Found.ar(c4a))
  +c8a = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(8)})
  +c8 = P.lt_i32(8, O.Found.ar(c8a))
  +c2f = O.UOp.const(O.Found.ar(c8), O.CFloat{2.0})
  +f2 = O.UOp.new(O.Found.ar(c2f), O.OpsCAST{}, [O.Found.i(c2f)], O.ADt{S.single()}, O.TNone{})
  +r0 = O.UOp.new(O.Found.ar(f2), O.OpsRANGE{}, [O.Found.i(c4)], O.ARange{[0], O.AXIS_LOOP{}}, O.TNone{})
  +r1 = O.UOp.new(O.Found.ar(r0), O.OpsRANGE{}, [O.Found.i(c8)], O.ARange{[1], O.AXIS_LOOP{}}, O.TNone{})
  +r2 = O.UOp.new(O.Found.ar(r1), O.OpsRANGE{}, [O.Found.i(c4)], O.ARange{[2], O.AXIS_LOOP{}}, O.TNone{})
  +e = O.UOp.new(O.Found.ar(r2), O.OpsEND{},
                 [O.Found.i(f2), O.Found.i(r0), O.Found.i(r1), O.Found.i(r2)], O.ANone{}, O.TNone{})
  KER.K{F.folded(O.Found.ar(e)),
    [0, O.Found.i(c4a), O.Found.i(c4), O.Found.i(c8a), O.Found.i(c8), O.Found.i(c2f),
     O.Found.i(f2), O.Found.i(r0), O.Found.i(r1), O.Found.i(r2), O.Found.i(e)]}

def se_e(+k: KER.K) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, KER.K.ix(k), 10n), 0)

def se_se(+k: KER.K) -> Se:
  se_of(F.Folded.ar(KER.K.fx(k)), se_e(k))

# `se_rngs` -- the LOOP'S FUEL, printed by axis. It is the row that says the
# `dedup` kept all three and the `reverse=True` sort put them in descending axis
# order, which is the order `ret.end(r)` is called in.
def se_rngs_str(rngs: List<&2, U32>, +ar: O.Arena, +acc: List<&2, String>) -> List<&2, String>:
  match rngs:
    case Nil{}   : acc
    case +r <> +t : se_rngs_str(t, ar, List.append(&2, String, acc, [U32.show(lt_slash.axis(O.Arena.arg(ar, r)))]))

def se_rngs_row(+k: KER.K) -> String:
  String.join(se_rngs_str(se_rngs_of(F.Folded.ar(KER.K.fx(k)), se_e(k)),
                          F.Folded.ar(KER.K.fx(k)), Nil{}), " ")

# The labels come out of the BUILT arena, not the fixture's, so `se_ops` gates the
# chain `do_split_ends` produced and not only the fixture's own nodes.
def se_ops_row(+k: KER.K) -> String:
  se_lab_str(Se.ar(se_se(k)), se_lst())

# THE THREE SHARED READERS of the CFG section. `cfg_ctx` and `cfg_ed` each walk
# the whole graph, and `cfg_hits` rewrites against the SAME `edges` table, so the
# table is read once per row rather than once per row CLASS.
def lt_ar() -> O.Arena:
  F.Folded.ar(KER.K.fx(P.lt_fix()))

def lt_cfged() -> P.RaTb:
  cfg_ed(lt_ar(), cfg_ctx(lt_ar()))

def se_ar() -> O.Arena:
  F.Folded.ar(KER.K.fx(se_fix()))
def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("ix_len", lt_ix_len())
    b : Unit <- srow("ix", lt_ix())
    c : Unit <- row("po_param", lt_po_param())
    d : Unit <- row("po_bufl", lt_po_bufl())
    e : Unit <- row("po_bufg", lt_po_bufg())
    f : Unit <- row("po_load", lt_po_load())
    g : Unit <- row("po_store", lt_po_store())
    h : Unit <- row("po_range", lt_po_range())
    i : Unit <- row("po_end", lt_po_end())
    j : Unit <- row("po_backedge", lt_po_backedge())
    k : Unit <- row("po_add", lt_po_add())
    l : Unit <- row("rc_nil", lt_rc_nil())
    m : Unit <- row("rc_1", lt_rc_1())
    n : Unit <- row("rc_2", lt_rc_2())
    o : Unit <- row("rc_3", lt_rc_3())
    p : Unit <- row("rc_max", lt_rc_max())
    q : Unit <- row("rc_big", lt_rc_big())
    r : Unit <- srow("lin_srcs", lt_lin_srcs())
    s : Unit <- row("lin_n", lt_lin_n())
    t : Unit <- srow("lin_vm", lt_lin_vm())
    t2 : Unit <- srow("lin_edg", lt_lin_edg())
    u : Unit <- srow("lin_nkey", lt_lin_nkey())
    v : Unit <- srow("lin_ord", lt_srcs(F.Folded.ar(KER.K.fx(P.lt_fix())), lt_srt_idx()))
    w : Unit <- lt_rows("lin", P.linearize(F.Folded.ar(KER.K.fx(P.lt_fix())), P.lt_lst(), P.lt_vm_lst(), 19),
                        lt_srt(), P.lt_fix())
    x : Unit <- row("lin_ties", lt_lin_ties())
    y : Unit <- row("lin_exmix", lt_lin_exmix())
    p1 : Unit <- srow("linc_srcs", lt_linc_srcs())
    p2 : Unit <- row("linc_n", lt_linc_n())
    p3 : Unit <- srow("linc_vm", lt_linc_vm())
    p3b : Unit <- srow("linc_edg", lt_linc_edg())
    p4 : Unit <- srow("linc_nkey", lt_linc_nkey())
    p5 : Unit <- srow("linc_ord", lt_srcs(F.Folded.ar(KER.K.fx(P.lt_fix())), lt_srt_call_idx()))
    p6 : Unit <- lt_linc_rows()
    p7 : Unit <- row("linc_ties", lt_linc_ties())
    p8 : Unit <- row("linc_exmix", lt_linc_exmix())
    q1 : Unit <- srow("cfg_edges", cfg_edges_row(lt_ar(), lt_cfged()))
    q2 : Unit <- row("cfg_edges_n", cfg_edges_n(lt_cfged()))
    q3 : Unit <- srow("cfg_hits", cfg_hits(lt_ar(), lt_cfged()))
    q4 : Unit <- row("cfg_tbl_len", cfg_tbl_len())
    q5 : Unit <- srow("cfg_tbl_ops", cfg_tbl_ops())
    r1 : Unit <- srow("se_rngs", se_rngs_row(se_fix()))
    r2 : Unit <- srow("se_ops", se_ops_row(se_fix()))
    r3 : Unit <- row("se_len", se_len(se_se(se_fix()), 1))
    r4 : Unit <- row("se_nsrc", se_nsrc(se_se(se_fix())))
    r5 : Unit <- row("se_tbl_len", se_tbl_len())
    r6 : Unit <- srow("se_tbl_ops", se_tbl_ops())
    r7 : Unit <- row("se_fired", se_fired(se_ar(), se_e(se_fix())))
    # THE LAST ROW IS UNBOUND and IS the `do IO<Unit>` block's final
    # expression, so there is no trailing `IO.print("")` and the file ends
    # with the LAST ROW's newline -- what the oracle's `print("\n".join(out))`
    # does. A trailing empty line is a one-line diff a reader must notice.
    row("se_miss", se_fired(se_ar(), 7))
