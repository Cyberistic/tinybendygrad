# schedule/rangify.bend -- THE PORT's OWN `run_rangeify` DRIVER.
#
# WHAT THIS FILE IS. `tinygrad/schedule/indexing.py:183-210` is upstream's
# `run_rangeify`, and it is the ONE stage of `get_kernel_graph`
# (`tinygrad/schedule/rangeify.py:341-376`) that the port's own engine spells
# `Stg{0, Nil{}}` -- "run_rangeify -- NOT PORTED"
# (`tinybendygrad/schedule/rangeify.bend:2810`).
#
#   upstream: tinygrad/schedule/rangeify.py:344
#     tsink = run_rangeify(tsink, bool(DEBUG_RANGEIFY))     # "convert movement ops to ranges"
#
#   upstream: tinygrad/schedule/indexing.py:183
#     @rewrite_group(new_ctx=False)
#     def run_rangeify(tsink:UOp, debug:bool=False) -> UOp:
#       rctx = IndexingContext()
#       graph_rewrite(tsink, pm_generate_realize_map, ctx=rctx, name="get realize")
#       ... the consumer map ...
#       ... the range-map loop over reversed(tsink_toposort) ...
#       tsink = graph_rewrite(tsink, pm_apply_rangeify, ctx=rctx, bottom_up=True, name="apply rangeify")
#       tsink = graph_rewrite(tsink, pm_fix_deviceless, ctx=tsink.device, name="add device to deviceless")
#       return tsink
#
# so the driver is four things and the port had NONE of them:
#
#   1. THE DISPATCH for `pm_generate_realize_map` -- `indexing.bend`'s
#      `grm_table()` (schedule/indexing.bend:1274 symbol=grm_table) is the TABLE and the four rule BODIES are in
#      the same file (`realize` schedule/indexing.bend:935 symbol=realize, `realize_srcs` schedule/indexing.bend:969 symbol=realize_srcs,
#      `ix_realize_custom` schedule/indexing.bend:1025 symbol=ix_realize_custom, `ix_war_hit` schedule/indexing.bend:986 symbol=ix_war_hit), but there is NO
#      `_dispatch`/`_try`/`_scan` for it -- MEASURED, `grep -n "grm_dispatch"
#      tinybendygrad/schedule/indexing.bend` answers NOTHING.
#   2. THE CONSUMER MAP -- `data_srcs` is ported (`indexing.bend`'s `ix_ds_*`)
#      and nothing reads it.
#   3. THE RANGE-MAP LOOP -- the port has `IxCtx` (`indexing.bend:195` symbol=IxCtx), the
#      `new_range` counter (`:811`), `broadcast_rngs` (`:1048`) and
#      `broadcast_axes` (`:427`), and nothing drives them.
#   4. THE APPLY -- `pm_apply_rangeify`'s five rules (`par_table`,
#      schedule/indexing.bend:1303 symbol=par_table) and `pm_fix_deviceless` (`pfd_table`, schedule/indexing.bend:1310 symbol=pfd_table).
#
# THE ORACLE. `.agents/slop/rangify/rr-oracle.py` spies on upstream's OWN
# `tinygrad.schedule.indexing.run_rangeify` on the SAME program the port's own
# `realize.bend` builds (`(4,5) = (4,3) @ (3,5)`), and prints CPython's own
# `IndexingContext` (the realize map and the range map) and the graph
# `run_rangeify` RETURNS. MEASURED:
#
#   rr_py_in_nodes=23            the graph `run_rangeify` RECEIVES
#   rr_py_out_nodes=27           the graph `run_rangeify` RETURNS -- THE TARGET
#   rr_py_realize_n=1            ONE realized node: the STORE
#   rr_py_range_n=11             ELEVEN nodes carry ranges
#
# and the payoff, measured, not assumed: CPython's `run_rangeify` output is
# `SINK(AFTER(PARAM, END))` -- with an `END`, not a `CALL` (upstream's stage 6,
# `split_kernels`, later turns the `END` into a `CALL`), and the port's own
# `schedule()` COUNTS AN `END` AS A KERNEL: `sc_is_kernel`
# (`tinybendygrad/schedule/__init__.bend:274`) is
# `sc_is(ar, i, O.OpsCALL{}) or sc_is(ar, i, O.OpsEND{})`.
#
# - so this driver is what moves `rz_lin_n` off zero, and it is the whole of
# the port's own `Device` lane's last link.
#
# THE SPELLING. The dump is `op:argkey:srcops` joined by `;` -- the ORACLE's
# spelling and the port's own `rz_dump` spelling, so the two are byte
# comparable with no translator.
#
# the walls, named here and not disguised:
#
#   W-A. `_apply_reshape` (`indexing.py:155-167`) -- the RESHAPE arm of
#        `apply_movement_op`. It is `UOp.sink`, `usum`, `%`, `//` and a
#        `graph_rewrite` under `symbolic`. `schedule/indexing.bend:663` already names it
#        ("three builders and W2"). - THE RESHAPE'S INPUT RANGE IS AN AFFINE
#        expression in CPython (`ADD:none:MUL,RANGE`) and the port cannot build
#        one. the port's answer is the input RANGE itself. - the output graph
#        differs from CPython's in the INDEX nodes' argument, and only there.
#   W-B. The port has no `symbolic` REWRITER -- `fold.bend`'s `mm.*` is the
#        INTERVAL algebra, not upstream's `tinygrad/uop/symbolic.py` matcher.
#   W-C. `UOp(Ops.STAGE, arg=BufferizeOpts(...))` -- `indexing.bend`'s W3. NOT
#        REACHED BY THIS PROGRAM: the realize map holds ONE node and it is a
#        STORE, and a STORE becomes an `END`, not a `STAGE`.
#
# - a row that cannot go red is a label, so no row in this file is a test.
# the test is the comparison against the oracle: `.agents/slop/rangify/cmp.py`.

import Base

import ./../helpers.bend as H

import ./../uop/ops.bend as O

import ./../uop/fold.bend as F

import ./indexing.bend as IX

import ./realize.bend as RZ

# THE ENGINE -- `schedule/rangeify.bend`, UPSTREAM's `tinygrad/schedule/rangeify.py`.
# - and this edge is one-way: `rangeify.bend` imports nothing from here, and
# it must not. `realize.bend` used to import it (the engine) and this file
# imports `realize.bend` (the fixture), - so the other way round was a cycle
# and the engine's stage 1 -- `run_rangeify` -- was an empty table.
# - and now the composition lives here, WHERE `run_rangeify` lives.
import ./rangeify.bend as RG


# 1. THE DUMP -- the ORACLE's spelling, `op:argkey:srcops`.
#
# `eng_op_name` (`schedule/rangeify.bend:2987`) names TEN ops and answers
# "OTHER" for the rest, and the graph this file produces is made of INDEX,
# RANGE, END, ADD and MUL -- so this file needs its own. `RZ.rz_argkey` IS
# reused: it is the oracle's `arg_key` (`cother` for a CONST, `none` for a node
# with no arg, `other` for everything else), and it is the same function the
# port's own realize-to-sink comparator already compares against.

def rr_op_name(op: O.Op) -> String:
  match op:
    case O.OpsCONST{}  : "CONST"
    case O.OpsPARAM{}  : "PARAM"
    case O.OpsBUFFER{} : "BUFFER"
    case O.OpsALLOC{}  : "ALLOC"
    case O.OpsRESHAPE{}: "RESHAPE"
    case O.OpsPERMUTE{}: "PERMUTE"
    case O.OpsEXPAND{} : "EXPAND"
    case O.OpsPAD{}    : "PAD"
    case O.OpsSHRINK{} : "SHRINK"
    case O.OpsSTACK{}  : "STACK"
    case O.OpsMUL{}    : "MUL"
    case O.OpsADD{}    : "ADD"
    case O.OpsSUB{}    : "SUB"
    case O.OpsREDUCE{} : "REDUCE"
    case O.OpsSTORE{}  : "STORE"
    case O.OpsAFTER{}  : "AFTER"
    case O.OpsSINK{}   : "SINK"
    case O.OpsINDEX{}  : "INDEX"
    case O.OpsRANGE{}  : "RANGE"
    case O.OpsEND{}    : "END"
    case O.OpsCALL{}   : "CALL"
    case O.OpsSTAGE{}  : "STAGE"
    case O.OpsWHERE{}  : "WHERE"
    case _: "OTHER"

def rr_src_names.go(+ar: O.Arena, ss: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}: acc
    case s <> t: rr_src_names.go(ar, t, List.append(&2, String, acc, [rr_op_name(O.Arena.op(ar, s))]))

def rr_node_str(+ar: O.Arena, +n: U32) -> String:
  String.concat([rr_op_name(O.Arena.op(ar, n)), ":", RZ.rz_argkey(ar, n), ":",
                 String.join(rr_src_names.go(ar, O.Arena.srcs(ar, n), Nil{}), ",")])

# THE DUMP. A DFS from the root, each node ONCE, joined by `;` -- the same
# traversal as `RZ.rz_dump` (`schedule/realize.bend:391` symbol=rz_dump), which is the oracle's
# own `dump` (`eng-oracle.py:79`) and NOT the port's `eng_dump` (a BFS). The
# comparison is over MULTISETS, so the order is not the subject; the TRAVERSAL
# is, because a different traversal would not visit the same nodes.
def rr_dump.go(fuel: Nat, todo: List<&2, U32>, +ar: O.Arena, +seen: List<&2, U32>, +n: U32,
               +acc: List<&2, String>) -> List<&2, String>:
  match fuel:
    case 0n: acc
    case 1n+p:
      match todo:
        case Nil{}: acc
        case +x <> t:
          +s = List.contains(U32, U32.is_eq, seen, x)
          rr_dump.go(p, List.concat(&2, U32, [t, O.Arena.srcs(ar, x)]), ar,
                     Bool.pick(List<&2, U32>, s, seen, List.append(&2, U32, seen, [x])),
                     x,
                     Bool.pick(List<&2, String>, s, acc,
                       List.append(&2, String, acc, [rr_node_str(ar, x)])))

def rr_dump(+ar: O.Arena, +root: U32) -> String:
  String.join(rr_dump.go(O.Arena.budget(ar), [root], ar, Nil{}, root, Nil{}), ";")


# 2. THE REALIZE MAP -- `pm_generate_realize_map` (`indexing.py:45-54`), FOUR
# rules, and the dispatch that is missing.
#
#   0  UPat(Ops.CALL, src=(UPat((Ops.SINK, Ops.PROGRAM)),), name="c", allow_any_len=True)
#        -> realize_custom_kernel_srcs      (indexing.py:40-43)
#   1  UPat(Ops.STORE, name="tr")           -> realize                (indexing.py:28)
#   2  UPat((Ops.MSELECT, Ops.MSTACK), name="rb") -> realize_srcs     (indexing.py:30-32)
#   3  UPat(Ops.STORE, src=(UPat.var("dest"), UPat.var("src")))
#        -> realize_store_after_src         (indexing.py:34-36)
#
# - and all four rule bodies return `None`, so upstream's
# `PatternMatcher.rewrite` -- which returns the FIRST non-`None` answer -- runs
# EVERY rule that MATCHES. That is why rule 1 AND rule 3 both fire on a STORE:
# the STORE is realized AND its src is tested for the WAR hazard.
#
# THE PORT's `grm_table()` (`indexing.bend:1274` symbol=grm_table) carries the op sets and the
# TAG, and the tag IS the rule index -- the same convention `rangeify.bend`'s
# `aprt_table`/`aprt_dispatch` uses. - so the dispatch is: the tag picks the
# body, and the op set picks the match.


# RULE 3's TEST: `if dest.base in src.toposort()` (`indexing.py:34-36`). The
# port's `ix_war_hit` (`indexing.bend:986` symbol=ix_war_hit) is that test.
def rr_war(+ar: O.Arena, +u: U32) -> Bool:
  IX.ix_war_hit(ar, O.Arena.src0(ar, u), O.Arena.src(ar, u, 1))

# RULE 3's BODY: `ctx.realize_map[src] = None` (`indexing.py:35`). IT IS GATED
# BY RULE 3's TEST, and the gate has to be HERE and not at the call site: a
# `Bool.pick` evaluates BOTH arms (`bend2-constraints.md`, `mixin/movement.bend`
# rule 5 -- "a flag parameter makes the arms cheap, it does not make the
# arguments lazy"), so an ungated body in the `then` arm would be BUILT for
# every node and INCLUDED for every STORE.
def rr_war_real(+ar: O.Arena, u: U32) -> List<&2, IX.IxReal>:
  [IX.realize(O.Arena.src(ar, u, 1))]

# RULE 0's BODY: `ix_realize_custom` (`indexing.bend:1025` symbol=ix_realize_custom).
def rr_call_real(+ar: O.Arena, u: U32) -> List<&2, IX.IxReal>:
  IX.ix_realize_custom(ar, u)

# RULE 2's BODY: `realize_srcs` (`indexing.bend:969` symbol=realize_srcs).
def rr_mstack_real(+ar: O.Arena, u: U32) -> List<&2, IX.IxReal>:
  IX.realize_srcs(ar, u)

# RULE 1's BODY: `realize` (`indexing.bend:935` symbol=realize).
def rr_store_real(+ar: O.Arena, u: U32) -> List<&2, IX.IxReal>:
  [IX.realize(u)]

# RULE 1 + RULE 3, TOGETHER, because they are the two rules that fire on a
# STORE and upstream runs BOTH (every rule body returns `None`).
def rr_store_entries(+ar: O.Arena, +u: U32) -> List<&2, IX.IxReal>:
  Bool.pick(List<&2, IX.IxReal>, rr_war(ar, u),
    List.append(&2, IX.IxReal, rr_war_real(ar, u), rr_store_real(ar, u)),
    rr_store_real(ar, u))

# THE OP TESTS. Each is its own def because a `match` may not scrutinise a
# COMPUTED value (`bend2-constraints.md`, rule 2).
def rr_is_store(+ar: O.Arena, u: U32) -> Bool:
  O.eq_op(O.Arena.op(ar, u), O.OpsSTORE{})

def rr_is_call(+ar: O.Arena, u: U32) -> Bool:
  O.eq_op(O.Arena.op(ar, u), O.OpsCALL{})

def rr_is_mstack(+ar: O.Arena, +u: U32) -> Bool:
  Bool.or(O.eq_op(O.Arena.op(ar, u), O.OpsMSELECT{}),
          O.eq_op(O.Arena.op(ar, u), O.OpsMSTACK{}))

# rule 0's pattern carries a SRC condition: `src=(UPat((Ops.SINK, Ops.PROGRAM)),)`.
# The port's `grm_table()` does not carry it -- `PMEntry` is `tag`/`ops`/`rej`
# and the reject sets are all EMPTY (MEASURED by the oracle: `grm_*_rej` is
# `-`) -- so the condition is checked HERE, where the port can.
def rr_call_is_custom(+ar: O.Arena, +u: U32) -> Bool:
  Bool.or(O.eq_op(O.Arena.op(ar, O.Arena.src0(ar, u)), O.OpsSINK{}),
          O.eq_op(O.Arena.op(ar, O.Arena.src0(ar, u)), O.OpsPROGRAM{}))

# THE DISPATCH, ONE NODE. Every rule that MATCHES fires, because every rule
# body returns `None` upstream.
def rr_realize_one(+ar: O.Arena, +u: U32) -> List<&2, IX.IxReal>:
  Bool.pick(List<&2, IX.IxReal>, rr_is_store(ar, u), rr_store_entries(ar, u),
    Bool.pick(List<&2, IX.IxReal>, rr_is_mstack(ar, u), rr_mstack_real(ar, u),
      Bool.pick(List<&2, IX.IxReal>,
        Bool.and(rr_is_call(ar, u), rr_call_is_custom(ar, u)), rr_call_real(ar, u),
        Nil{})))

# THE FOLD. The toposort is the port's own `O.UOp.toposort`, and the map is
# APPENDED -- upstream's `realize_map` is a `dict` and the ORDER of its keys is
# the order the rules fired, which is the order the rewrite visited the nodes.
def rr_realize.go(fuel: Nat, ns: List<&2, U32>, +ar: O.Arena, +m: IX.IxMap) -> IX.IxMap:
  match fuel:
    case 0n: m
    case 1n+p:
      match ns:
        case Nil{}: m
        case u <> t:
          rr_realize.go(p, t, ar,
            IX.IxMap{List.append(&2, IX.IxReal, IX.IxMap.es(m), rr_realize_one(ar, u))})

def rr_realize(+ar: O.Arena, sink: U32) -> IX.IxMap:
  rr_realize.go(O.Arena.budget(ar), O.UOp.toposort(O.Arena.budget(ar), ar, sink),
                ar, IX.IxMap{Nil{}})


# the plant. - the port has no env reader, so the plant is a separate row and not
# a flag: - the measured FOLD above is always the unplanted one, and the port's
# OWN DRIVER IS NEVER SHIPPED BROKEN.
# - and the plant is "drop the first realized entry", which is exactly the class
# of bug the measurement is about: a realize map with an entry missing.
def rr_realize_plant.go(fuel: Nat, ns: List<&2, U32>, +ar: O.Arena, +m: IX.IxMap,
                        +dropped: Bool) -> IX.IxMap:
  match fuel:
    case 0n: m
    case 1n+p:
      match ns:
        case Nil{}: m
        case u <> t:
          +e = rr_realize_one(ar, u)
          # the entry is non-empty when the node is one the realize rules fire on, and
          # `rr_realize_one` answers a list of such entries -- - so the plant drops
          # the first entry of the first node that has one.
          +n = U32.from_nat(List.length(&2, IX.IxReal, e))
          +drop = Bool.and(Bool.not(dropped), Bool.not(U32.is_eq(n, 0)))
          rr_realize_plant.go(p, t, ar,
            IX.IxMap{Bool.pick(List<&2, IX.IxReal>, drop, IX.IxMap.es(m),
                               List.append(&2, IX.IxReal, IX.IxMap.es(m), e))},
            Bool.or(dropped, drop))

def rr_realize_plant(+ar: O.Arena, sink: U32) -> IX.IxMap:
  rr_realize_plant.go(O.Arena.budget(ar), O.UOp.toposort(O.Arena.budget(ar), ar, sink),
                       ar, IX.IxMap{Nil{}}, False{})


# 4. the RANGE map -- `indexing.py:190-306`. the consumer map, the LOOP, and
#    THE RANGE TABLE.
#
# THE STATE. `ctx` IS UPSTREAM's `IndexingContext`, `ends` IS UPSTREAM's
# `ending_ranges` as a flag per node (which is all the algorithm reads of it:
# `len(ending_ranges[x])`), `tbl` IS THE RANGE TABLE, AND `out`/`inp` ARE THE
# RANGE map's two halves for the node being processed.
#
# - the table is also the counter: a RANGE's axis ID is its table INDEX
# minus one, because INDEX 0 is the CONST 0 and `new_range(1)` does not advance
# UPSTREAM's `range_idx` (`indexing.py:21`).
#
# - and the phases are separate defs, not one big expression, because a
# `Bool.pick` evaluates both arms and the table is appended-only: a branch that
# creates a RANGE must not also create one in the arm that is not taken. a
# `match` ON A `Bool` IS LAZY, SO THE BRANCHES ARE `match`es.
type RrMap is Data:
  RrMap{ctx: IX.IxCtx, ends: List<&2, Bool>, tbl: List<&2, IX.IxRange>,
        out: List<&2, U32>, inp: List<&2, U32>, e: Bool, b: Bool, sk: Bool}

def RrMap.ctx(x: RrMap) -> IX.IxCtx:
  match x:
    case RrMap{ctx, ends, tbl, out, inp, e, b, ne}: ctx

def RrMap.ends(x: RrMap) -> List<&2, Bool>:
  match x:
    case RrMap{ctx, ends, tbl, out, inp, e, b, ne}: ends

def RrMap.tbl(x: RrMap) -> List<&2, IX.IxRange>:
  match x:
    case RrMap{ctx, ends, tbl, out, inp, e, b, ne}: tbl

def RrMap.out(x: RrMap) -> List<&2, U32>:
  match x:
    case RrMap{ctx, ends, tbl, out, inp, e, b, ne}: out

def RrMap.inp(x: RrMap) -> List<&2, U32>:
  match x:
    case RrMap{ctx, ends, tbl, out, inp, e, b, ne}: inp

def RrMap.e(x: RrMap) -> Bool:
  match x:
    case RrMap{ctx, ends, tbl, out, inp, e, b, ne}: e

def RrMap.b(x: RrMap) -> Bool:
  match x:
    case RrMap{ctx, ends, tbl, out, inp, e, b, ne}: b

def RrMap.ne(x: RrMap) -> Bool:
  match x:
    case RrMap{ctx, ends, tbl, out, inp, e, b, ne}: ne

def RrMap.put(+x: RrMap, out: List<&2, U32>, inp: List<&2, U32>, e: Bool, b: Bool, ne: Bool) -> RrMap:
  RrMap{RrMap.ctx(x), RrMap.ends(x), RrMap.tbl(x), out, inp, e, b, ne}

# the same state with a new context.
def RrMap.with_ctx(+ctx: IX.IxCtx, +x: RrMap) -> RrMap:
  RrMap{ctx, RrMap.ends(x), RrMap.tbl(x), RrMap.out(x), RrMap.inp(x), RrMap.e(x), RrMap.b(x), RrMap.ne(x)}

# the same state with a new `ends` list.
def RrMap.with_ends(+ends: List<&2, Bool>, +x: RrMap) -> RrMap:
  RrMap{RrMap.ctx(x), ends, RrMap.tbl(x), RrMap.out(x), RrMap.inp(x), RrMap.e(x), RrMap.b(x), RrMap.ne(x)}


# 4a. the shape. `x.shape` (ops.py:456) is a double `Maybe`, and every dim of
# this program is concrete (`rr_py_shapes` against the port's own arena: 23 of
# 23 NODES AGREE).

def rr_dim.of(m: Maybe<&2, O.Sint>) -> Maybe<&2, U32>:
  match m:
    case Some{s}:
      match s:
        case O.SI{i}: Some{H.lo32(i)}
        case _: None{}
    case _: None{}

def rr_num(m: Maybe<&2, U32>) -> U32:
  match m:
    case Some{v}: v
    case _: 0

def rr_dims.go(+ds: List<&2, O.Sint>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ds:
    case Nil{}: acc
    case d <> t: rr_dims.go(t, List.append(&2, U32, acc, [rr_num(rr_dim.of(Some{d}))]))

def rr_dims.of(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> List<&2, U32>:
  match m:
    case Some{Some{ds}}: rr_dims.go(ds, Nil{})
    case _: Nil{}

def rr_dims(+ar: O.Arena, +tb: F.Table, n: U32) -> List<&2, U32>:
  rr_dims.of(F.fold.shape(ar, tb, n))


# 4b. the consumer map. `consumer_map[x][c]` is "c's data srcs contain x"
# (`indexing.py:193-196`), AND `data_srcs` IS `indexing.bend`'s OWN
# `ix_ds_take` twice -- so the port's own decision is reused, not copied.

def rr_dsrcs(+ar: O.Arena, +op: O.Op, +ss: List<&2, U32>) -> List<&2, U32>:
  # upstream's `data_srcs` (`indexing.py:68-71`) IS THREE CASES -- ZERO srcs
  # for {PARAM, BUFFER, ALLOC, RANGE, SPECIAL}, `src[:1]` for the movements, ALL
  # of them otherwise -- - AND THE DECISION IS `indexing.bend`'s OWN
  # `ix_ds_list`, beside the length form `ix_ds_n`, so it is made once.
  #
  # - and this composition used to read `ix_ds_zero` as "take one", which is
  # the opposite of what `ix_ds_n.of` reads it as -- so a `PARAM` contributed its
  # first SRC as a data SRC, and the RANGE map grew an entry for every `CONST`
  # that feeds a `PARAM` (three of them, at toposort positions 0, 6 and 12),
  # WHERE UPSTREAM HAS NO ENTRY AT ALL.
  IX.ix_ds_list(op, ss)

def rr_cons.go(+topo: List<&2, U32>, +ar: O.Arena, +x: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match topo:
    case Nil{}: acc
    case c <> t:
      +ds = rr_dsrcs(ar, O.Arena.op(ar, c), O.Arena.srcs(ar, c))
      rr_cons.go(t, ar, x,
        Bool.pick(List<&2, U32>, List.contains(U32, U32.is_eq, ds, x),
                  List.append(&2, U32, acc, [c]), acc))

def rr_cons(+ar: O.Arena, +topo: List<&2, U32>, x: U32) -> List<&2, U32>:
  rr_cons.go(topo, ar, x, Nil{})


# 4c. the reversed toposort and the `ends` list. the LOOP runs over
# `reversed(tsink_toposort)` (`indexing.py:200`) AND `ending_ranges` IS READ
# for a node's consumers, which are processed first -- so the flag list is
# indexed by the position in the reversed toposort.

def rr_rev_dbg(+ns: List<&2, U32>) -> List<&2, U32>:
  match ns:
    case Nil{}: Nil{}
    case h <> t: List.append(&2, U32, Nil{}, [h])

def rr_rev.go(+ns: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ns:
    case Nil{}: acc
    case x <> t: rr_rev.go(t, List.append(&2, U32, [x], acc))

def rr_rev(+ns: List<&2, U32>) -> List<&2, U32>:
  rr_rev.go(ns, Nil{})

def rr_rpos.go(+rs: List<&2, U32>, +c: U32, +k: Nat, acc: Nat) -> Nat:
  match rs:
    case Nil{}: acc
    case x <> t: rr_rpos.go(t, c, Nat.add(k, 1n),
                           Bool.pick(Nat, U32.is_eq(x, c), k, acc))

def rr_rpos(+rs: List<&2, U32>, c: U32) -> Nat:
  rr_rpos.go(rs, c, 0n, 0n)

def rr_ends_at.of(m: Maybe<&2, Bool>) -> Bool:
  match m:
    case Some{v}: v
    case _: False{}

def rr_ends_at(+es: List<&2, Bool>, p: Nat) -> Bool:
  rr_ends_at.of(List.get(&2, Bool, es, p))

# `ending_ranges[x] = sum([ending_ranges.get(u, []) for u in consumer_map[x]], [])`
# -- and the algorithm only reads `len()` of it, so it is a flag.
def rr_ends_of.go(+cs: List<&2, U32>, +rs: List<&2, U32>, +ends: List<&2, Bool>, acc: Bool) -> Bool:
  match cs:
    case Nil{}: acc
    case c <> t: rr_ends_of.go(t, rs, ends, Bool.or(acc, rr_ends_at(ends, rr_rpos(rs, c))))

def rr_ends_of(+rs: List<&2, U32>, +ends: List<&2, Bool>, +cs: List<&2, U32>) -> Bool:
  rr_ends_of.go(cs, rs, ends, False{})


# 4d. THE RANGE TABLE. INDEX 0 IS THE CONST 0 -- `UOp.const(0)` AND
# `r.const_like(0)` are the same node -- and every other INDEX is a RANGE.

# the new RANGE: its INDEX, the indices so far, and the table with it appended.
type RrRs is Data:
  RrRs{i: U32, rs: List<&2, U32>, tbl: List<&2, IX.IxRange>}

def RrRs.i(x: RrRs) -> U32:
  match x:
    case RrRs{i, rs, tbl}: i

def RrRs.rs(x: RrRs) -> List<&2, U32>:
  match x:
    case RrRs{i, rs, tbl}: rs

def RrRs.tbl(x: RrRs) -> List<&2, IX.IxRange>:
  match x:
    case RrRs{i, rs, tbl}: tbl

# `new_range(s)` -- `indexing.py:18-21`. A CONST 0 FOR AN EXTENT OF 1, AND A
# RANGE otherwise. - the CONST 0 is table INDEX 0 and the axis ID is the
# table INDEX minus one, so the table is also the counter.
def rr_new.one(one: Bool, ext: U32, +tbl: List<&2, IX.IxRange>) -> RrRs:
  match one:
    case True{}: RrRs{IX.ix_rg_c0_idx(), [IX.ix_rg_c0_idx()], tbl}
    case False{}:
      +i = U32.from_nat(List.length(&2, IX.IxRange, tbl))
      RrRs{i, [i], List.append(&2, IX.IxRange, tbl, [IX.ix_rg_r(U32.sub(i, 1), ext)])}

# `tuple(rctx.new_range(s) for s in shape)`.
def rr_new.all(+ds: List<&2, U32>, +tbl: List<&2, IX.IxRange>, +acc: List<&2, U32>) -> RrRs:
  match ds:
    case Nil{}: RrRs{0, acc, tbl}
    case d <> t:
      +e = d
      +n = rr_new.one(IX.ix_nr_is_one(e), e, tbl)
      rr_new.all(t, RrRs.tbl(n), List.append(&2, U32, acc, RrRs.rs(n)))


# 4e. the op tests. a `match` may not scrutinize a computed value, so each
# TEST IS ITS OWN DEF.

# `rr_is_call`, `rr_is_store` AND `rr_is_mstack` ARE ALREADY HERE -- ABOVE, IN
# the realize-map dispatch -- and are reused, not copied.
def rr_is_after(+ar: O.Arena, +x: U32) -> Bool: O.eq_op(O.Arena.op(ar, x), O.OpsAFTER{})
def rr_is_reduce(+ar: O.Arena, +x: U32) -> Bool: O.eq_op(O.Arena.op(ar, x), O.OpsREDUCE{})
def rr_is_stack(+ar: O.Arena, +x: U32) -> Bool: O.eq_op(O.Arena.op(ar, x), O.OpsSTACK{})

# `indexing.py:202-208`: no ranges on calls, afters, mstacks and mselects.
def rr_skip(+ar: O.Arena, +x: U32) -> Bool:
  Bool.or(rr_is_call(ar, x), Bool.or(rr_is_after(ar, x), rr_is_mstack(ar, x)))

# `GroupOp.Elementwise.union({Ops.REDUCE})` -- `indexing.py:264`.
def rr_is_elemwise(+ar: O.Arena, +x: U32) -> Bool:
  Bool.or(O.GroupOp.elementwise(O.Arena.op(ar, x)), rr_is_reduce(ar, x))


# 4f. THE AXES. `realize_map[x] = list(range(len(x.shape)))` (`indexing.py:231`)
# AND `realize_map[x] = _realize_axis` (`indexing.py:261`, `:268`).

def rr_axes.go(+k: Nat, +i: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match k:
    case 0n: acc
    case 1n+p: rr_axes.go(p, U32.add(i, 1), List.append(&2, U32, acc, [i]))

def rr_axes(n: U32) -> List<&2, U32>:
  rr_axes.go(U32.to_nat(n), 0, Nil{})

# the realize map, with the node's axes set.
def rr_real(+ctx: IX.IxCtx, +x: U32, axes: List<&2, U32>) -> IX.IxCtx:
  IX.IxCtx{IX.ix_rmap_set(IX.IxCtx.rmap(ctx), x, IX.IxReal{x, True{}, axes}),
            IX.IxCtx.nrem(ctx), IX.IxCtx.rngm(ctx), IX.IxCtx.ridx(ctx)}


# 4g. `ended` -- the ranges the consumers iterate that this node broadcasts
# OVER (`indexing.py:212-213`).

# ONE AXIS'S RANGE: `rctx.range_map[c][0][i]`.
def rr_ended_pick.go(+axes: List<&2, U32>, +rngs: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match axes:
    case Nil{}: acc
    case i <> t: rr_ended_pick.go(t, rngs, List.append(&2, U32, acc, [IX.ix_nth(rngs, U32.to_nat(i))]))

def rr_ended_pick(+axes: List<&2, U32>, +rngs: List<&2, U32>) -> List<&2, U32>:
  rr_ended_pick.go(axes, rngs, Nil{})

# ONE CONSUMER'S CONTRIBUTION.
def rr_ended_one.bcast(bc: Bool, +ar: O.Arena, +tb: F.Table, +ctx: IX.IxCtx, +c: U32, +x: U32,
                       +e: IX.IxRngs) -> List<&2, U32>:
  match bc:
    case True{}: rr_ended_pick(IX.ix_bax(rr_dims(ar, tb, x), rr_dims(ar, tb, c)), IX.IxRngs.inp(e))
    case False{}: Nil{}

def rr_ended_one(+ar: O.Arena, +tb: F.Table, +ctx: IX.IxCtx, +c: U32, +x: U32,
                 has: Maybe<&2, IX.IxRngs>) -> List<&2, U32>:
  match has:
    case Some{e}: rr_ended_one.bcast(O.GroupOp.broadcastable(O.Arena.op(ar, c)), ar, tb, ctx, c, x, e)
    case _: Nil{}

def rr_ended.go(+cs: List<&2, U32>, +ar: O.Arena, +tb: F.Table, +ctx: IX.IxCtx, +x: U32,
                +acc: List<&2, U32>) -> List<&2, U32>:
  match cs:
    case Nil{}: acc
    case c <> t:
      +has = IX.ix_rngm_get(IX.IxCtx.rngm(ctx), c)
      rr_ended.go(t, ar, tb, ctx, x,
        List.append(&2, U32, acc, rr_ended_one(ar, tb, ctx, c, x, has)))

def rr_ended(+ar: O.Arena, +tb: F.Table, +ctx: IX.IxCtx, +cs: List<&2, U32>, +x: U32) -> List<&2, U32>:
  rr_ended.go(cs, ar, tb, ctx, x, Nil{})

# `list(UOp.sink(*ended).ranges)` -- THE RANGE NODES AMONG `ended`. A CONST
# 0 IS NOT A RANGE, SO IT DOES NOT COUNT.
def rr_any_range.go(+rs: List<&2, U32>, +tbl: List<&2, IX.IxRange>, acc: Bool) -> Bool:
  match rs:
    case Nil{}: acc
    case r <> t:
      rr_any_range.go(t, tbl, Bool.or(acc, Bool.not(IX.ix_rg_is_c0(IX.ix_tbl_at(tbl, r)))))

def rr_any_range(+tbl: List<&2, IX.IxRange>, +rs: List<&2, U32>) -> Bool:
  rr_any_range.go(rs, tbl, False{})


# 4h. THE LOOP -- `indexing.py:200-306`, PHASE BY PHASE.
#
# the phases are separate defs because the RANGE table is append-only and a
# `Bool.pick` evaluates both arms: a branch that creates a RANGE must not also
# create one in the arm that is not taken. a `match` on a `Bool` is lazy.


# THE CONSUMERS THAT HAVE RANGES: `for c in consumer_map[x] if c in rctx.range_map`
def rr_cons_rngs.go(+cs: List<&2, U32>, +ctx: IX.IxCtx, +acc: List<&2, U32>) -> List<&2, U32>:
  match cs:
    case Nil{}: acc
    case c <> t:
      rr_cons_rngs.go(t, ctx, Bool.pick(List<&2, U32>, IX.ix_rngm_has(IX.IxCtx.rngm(ctx), c),
                                         List.append(&2, U32, acc, [c]), acc))

def rr_cons_rngs(+ctx: IX.IxCtx, +cs: List<&2, U32>) -> List<&2, U32>:
  rr_cons_rngs.go(cs, ctx, Nil{})

# ONE CONSUMER's RANGES: `broadcast_rngs(c, x, rctx.range_map[c][0])`.
def rr_one_rngs.of(m: Maybe<&2, IX.IxRngs>, +ar: O.Arena, +tb: F.Table, +ctx: IX.IxCtx, +c: U32, +x: U32) -> List<&2, U32>:
  match m:
    case Some{e}: IX.broadcast_rngs(O.Arena.op(ar, c), rr_dims(ar, tb, x), rr_dims(ar, tb, c), IX.IxRngs.inp(e))
    case _: Nil{}

def rr_one_rngs(+ar: O.Arena, +tb: F.Table, +ctx: IX.IxCtx, +c: U32, +x: U32) -> List<&2, U32>:
  rr_one_rngs.of(IX.ix_rngm_get(IX.IxCtx.rngm(ctx), c), ar, tb, ctx, c, x)

# the merge -- `indexing.py:238-261`. => the port's answer is upstream's
# fallback for every axis: a new RANGE and the axis realized. upstream keeps
# the RANGE when every consumer agrees and refines it with `.valid`, which is
# W3 (`UOp.valid` is not ported) -- => the agree case is a named deviation.
# => and the branch is not exercised by the measured program: no node has two
# consumers in the RANGE map (measured, and `rr_cons_rngs` is the instrument).
def rr_merge(+ar: O.Arena, +tb: F.Table, +ctx: IX.IxCtx, +x: U32, +tbl: List<&2, IX.IxRange>) -> RrRs:
  +n = rr_new.all(rr_dims(ar, tb, x), tbl, Nil{})
  RrRs{0, RrRs.rs(n), RrRs.tbl(n)}

# `apply_movement_op` -- `indexing.py:165-180`. PERMUTE AND EXPAND ARE FULLY
# PORTED -- `indexing.bend`'s OWN `ix_mv_permute` AND `ix_mv_expand`, REUSED AND
# NOT COPIED. RESHAPE IS W-A (`_apply_reshape`: `UOp.sink`, `usum`, `%`, `//`
# and a `symbolic` rewriter) and the port's answer is the identity, which
# is what `rangify.bend`'s own header says. shrink, flip and pad have their
# arithmetic named and not built (W3), so they answer the identity too.
def rr_mv.of(perm: Bool, exp: Bool, +arg: List<&2, U32>, +rngs: List<&2, U32>) -> List<&2, U32>:
  match perm:
    case True{}: IX.ix_mv_permute(arg, rngs)
    case False{}:
      match exp:
        case True{}: IX.ix_mv_expand(arg, rngs)
        case False{}: rngs

# the marg: `x.marg` is the permute's and the expand's tuple.
def rr_marg.of(a: O.Arg) -> Maybe<&2, List<&2, U32>>:
  match a:
    case O.ATuple{ys}: Some{ys}
    case _: None{}

def rr_marg.of2(m: Maybe<&2, List<&2, U32>>) -> List<&2, U32>:
  match m:
    case Some{ys}: ys
    case _: Nil{}

def rr_marg(+ar: O.Arena, x: U32) -> List<&2, U32>:
  rr_marg.of2(rr_marg.of(O.Arena.arg(ar, x)))

# the reduce's reduced axes: `x.arg[1]` is the number of reduced axes.
def rr_reduce_n.of(a: O.Arg) -> U32:
  match a:
    case O.AReduce{rop, num_axes}: num_axes
    case _: 0

# the P0 phase: the state, the consumers, the ending ranges, and the skip.
def rr_p0(+ar: O.Arena, +tb: F.Table, +rev: List<&2, U32>, +m: RrMap, +x: U32) -> RrMap:
  +ctx = RrMap.ctx(m)
  +ends = RrMap.ends(m)
  +tbl = RrMap.tbl(m)
  +cons = rr_cons(ar, rev, x)
  +ends_x = rr_ends_of(rev, ends, cons)
  +ended = rr_ended(ar, tb, ctx, cons, x)
  +b = rr_any_range(tbl, ended)
  +ends_x = Bool.pick(Bool, rr_is_reduce(ar, x), Bool.or(ends_x, b), ends_x)
  +sk = rr_skip(ar, x)
  RrMap{ctx, ends, tbl, Nil{}, Nil{}, Bool.pick(Bool, sk, False{}, ends_x), b, sk}

# the P1 phases: the output ranges. the realize branch, the single-consumer
# branch, the merge, and the `continue` (no consumer with ranges).
def rr_p1.real(+ar: O.Arena, +tb: F.Table, +ctx: IX.IxCtx, +m: RrMap, +x: U32) -> RrMap:
  +shape = rr_dims(ar, tb, x)
  +n = rr_new.all(shape, RrMap.tbl(m), Nil{})
  RrMap{rr_real(ctx, x, rr_axes(U32.from_nat(List.length(&2, U32, shape)))),
        RrMap.ends(m), RrRs.tbl(n), RrRs.rs(n), Nil{}, False{}, RrMap.b(m), RrMap.ne(m)}

def rr_p1.none(+ar: O.Arena, +tb: F.Table, +ctx: IX.IxCtx, +m: RrMap, +x: U32) -> RrMap:
  RrMap{ctx, RrMap.ends(m), RrMap.tbl(m), Nil{}, Nil{}, RrMap.e(m), RrMap.b(m), True{}}

def rr_p1.one(+ar: O.Arena, +tb: F.Table, +ctx: IX.IxCtx, +m: RrMap, x: U32, +c: U32) -> RrMap:
  RrMap{ctx, RrMap.ends(m), RrMap.tbl(m), rr_one_rngs(ar, tb, ctx, c, x), Nil{},
        RrMap.e(m), RrMap.b(m), RrMap.ne(m)}

def rr_p1.many(+ar: O.Arena, +tb: F.Table, +ctx: IX.IxCtx, +m: RrMap, +x: U32) -> RrMap:
  +n = rr_merge(ar, tb, ctx, x, RrMap.tbl(m))
  RrMap{ctx, RrMap.ends(m), RrRs.tbl(n), RrRs.rs(n), Nil{}, RrMap.e(m), RrMap.b(m), RrMap.ne(m)}

def rr_p1.pick(zero: Bool, one: Bool, +ar: O.Arena, +tb: F.Table, +ctx: IX.IxCtx, +m: RrMap,
               +x: U32, +c: U32) -> RrMap:
  match zero:
    case True{}: rr_p1.none(ar, tb, ctx, m, x)
    case False{}:
      match one:
        case True{}: rr_p1.one(ar, tb, ctx, m, x, c)
        case False{}: rr_p1.many(ar, tb, ctx, m, x)

def rr_p1.pick2(real: Bool, zero: Bool, one: Bool, +ar: O.Arena, +tb: F.Table, +ctx: IX.IxCtx,
                +m: RrMap, +x: U32, +c: U32) -> RrMap:
  match real:
    case True{}: rr_p1.real(ar, tb, ctx, m, x)
    case False{}: rr_p1.pick(zero, one, ar, tb, ctx, m, x, c)

def rr_p1(+ar: O.Arena, +tb: F.Table, +rev: List<&2, U32>, +m: RrMap, +x: U32) -> RrMap:
  +ctx = RrMap.ctx(m)
  +cons = rr_cons(ar, rev, x)
  +cs = rr_cons_rngs(ctx, cons)
  +cnt = U32.from_nat(List.length(&2, U32, cs))
  +hd = Maybe.default(&2, U32, List.head(&2, U32, cs), 0)
  rr_p1.pick2(IX.ix_rmap_has(IX.IxCtx.rmap(ctx), x), U32.is_eq(cnt, 0), U32.is_eq(cnt, 1),
             ar, tb, ctx, m, x, hd)

# THE P2 PHASE: `if len(ending_ranges[x]) and x.op in Elementwise|{REDUCE}` --
# realize every axis and give the node new ranges (`indexing.py:264-270`).
def rr_p2.fire(+ar: O.Arena, +tb: F.Table, +ctx: IX.IxCtx, +m: RrMap, +x: U32) -> RrMap:
  +out = RrMap.out(m)
  +shape = rr_dims(ar, tb, x)
  +n = rr_new.all(List.take(&2, U32, shape, U32.to_nat(U32.from_nat(List.length(&2, U32, out)))), RrMap.tbl(m), Nil{})
  RrMap{rr_real(ctx, x, rr_axes(U32.from_nat(List.length(&2, U32, out)))),
        RrMap.ends(m), RrRs.tbl(n), RrRs.rs(n), Nil{}, False{}, RrMap.b(m), RrMap.ne(m)}

def rr_p2.pick(fire: Bool, +ar: O.Arena, +tb: F.Table, +ctx: IX.IxCtx, +m: RrMap, +x: U32) -> RrMap:
  match fire:
    case True{}: rr_p2.fire(ar, tb, ctx, m, x)
    case False{}: m

def rr_p2(+ar: O.Arena, +tb: F.Table, +rev: List<&2, U32>, +m: RrMap, +x: U32) -> RrMap:
  rr_p2.pick(Bool.and(RrMap.e(m), rr_is_elemwise(ar, x)), ar, tb, RrMap.ctx(m), m, x)

# THE P3 PHASE: `ending_ranges[x] += broadcast_ending_ranges` (`indexing.py:270`).
def rr_p3(+m: RrMap) -> RrMap:
  RrMap.put(m, RrMap.out(m), RrMap.inp(m), Bool.or(RrMap.e(m), RrMap.b(m)), RrMap.b(m), RrMap.ne(m))

# THE P4 PHASE: THE INPUT RANGES (`indexing.py:281-294`).
def rr_p4.stack(isstack: Bool, +m: RrMap, +out: List<&2, U32>, +rngs: List<&2, U32>) -> RrMap:
  match isstack:
    case True{}: RrMap.put(m, out, List.drop(&2, U32, out, 1n), RrMap.e(m), RrMap.b(m), RrMap.ne(m))
    case False{}: RrMap.put(m, out, rngs, RrMap.e(m), RrMap.b(m), RrMap.ne(m))

def rr_p4.move(+ar: O.Arena, +tb: F.Table, +ctx: IX.IxCtx, +m: RrMap, +x: U32) -> RrMap:
  +out = RrMap.out(m)
  +op = O.Arena.op(ar, x)
  +arg = rr_marg(ar, x)
  +rngs = rr_mv.of(O.eq_op(op, O.OpsPERMUTE{}), O.eq_op(op, O.OpsEXPAND{}), arg, out)
  rr_p4.stack(rr_is_stack(ar, x), m, out, rngs)

def rr_p4.reduce(+ar: O.Arena, +tb: F.Table, +ctx: IX.IxCtx, +m: RrMap, +x: U32) -> RrMap:
  # - the grown table is the point: `rr_new.all` appends the reduce-axis
  # RANGE to the table (`rr_new.one` takes its INDEX from the table's length),
  # - AND `RrMap.put` KEEPS `RrMap.tbl(m)` -- THE TABLE AS IT WAS -- -
  # so the RANGE's INDEX pointed at a table that never received it. - this is
  # the class "a key that is not the key": the RANGE was created and nothing
  # COULD READ IT.
  # - and the rows are built like `rr_p1.real`'s, which uses the grown table
  # the same way -- - and `RrMap.out(m)` is read twice rather than bound, so
  # THE `+` LOCAL IS NOT USED TWICE.
  +n = rr_new.all(List.take(&2, U32, rr_dims(ar, tb, O.Arena.src0(ar, x)),
                            U32.to_nat(rr_reduce_n.of(O.Arena.arg(ar, x)))),
                  RrMap.tbl(m), Nil{})
  RrMap{RrMap.ctx(m), RrMap.ends(m), RrRs.tbl(n), RrMap.out(m),
        List.append(&2, U32, RrRs.rs(n), RrMap.out(m)), RrMap.e(m), RrMap.b(m), RrMap.ne(m)}

def rr_p4.pick(isred: Bool, +ar: O.Arena, +tb: F.Table, +ctx: IX.IxCtx, +m: RrMap, +x: U32) -> RrMap:
  match isred:
    case True{}: rr_p4.reduce(ar, tb, ctx, m, x)
    case False{}: rr_p4.move(ar, tb, ctx, m, x)

def rr_p4(+ar: O.Arena, +tb: F.Table, +rev: List<&2, U32>, +m: RrMap, +x: U32) -> RrMap:
  rr_p4.pick(rr_is_reduce(ar, x), ar, tb, RrMap.ctx(m), m, x)

# THE P5 PHASE: THE RANGE MAP's ENTRY (`indexing.py:306`).
def rr_p5.put(+ctx: IX.IxCtx, +e: IX.IxRngs) -> IX.IxCtx:
  IX.IxCtx{IX.IxCtx.rmap(ctx), IX.IxCtx.nrem(ctx),
            IX.IxRMap{List.append(&2, IX.IxRngs, IX.IxRMap.es(IX.IxCtx.rngm(ctx)), [e])},
            IX.IxCtx.ridx(ctx)}

def rr_p5.pick(ne: Bool, +ctx: IX.IxCtx, +m: RrMap, +x: U32) -> RrMap:
  match ne:
    case True{}: m
    case False{}: RrMap.with_ctx(rr_p5.put(ctx, IX.IxRngs{x, RrMap.inp(m), RrMap.out(m)}), m)

def rr_p5(+ar: O.Arena, +tb: F.Table, +rev: List<&2, U32>, +m: RrMap, +x: U32) -> RrMap:
  rr_p5.pick(RrMap.ne(m), RrMap.ctx(m), m, x)

# the P6 phase: the `ends` entry for this node.
def rr_p6(+m: RrMap) -> RrMap:
  RrMap.with_ends(List.append(&2, Bool, RrMap.ends(m), [RrMap.e(m)]), m)

# THE STEP, IN UPSTREAM's ORDER.
def rr_step(+ar: O.Arena, +tb: F.Table, +rev: List<&2, U32>, +m: RrMap, +x: U32) -> RrMap:
  rr_p6(rr_p5(ar, tb, rev, rr_p4(ar, tb, rev, rr_p3(rr_p2(ar, tb, rev, rr_p1(ar, tb, rev, rr_p0(ar, tb, rev, m, x), x), x)), x), x))

# THE FOLD, OVER THE REVERSED TOPOSORT (`indexing.py:200`).
def rr_range_map.go(+xs: List<&2, U32>, +ar: O.Arena, +tb: F.Table, +rev: List<&2, U32>,
                    +m: RrMap) -> RrMap:
  match xs:
    case Nil{}: m
    case x <> t: rr_range_map.go(t, ar, tb, rev, rr_step(ar, tb, rev, m, x))

# the realize map is filled before the LOOP (`indexing.py:188`:
# `graph_rewrite(tsink, pm_generate_realize_map, ctx=rctx)`), SO THE CONTEXT
# starts with it -- and it is the port's own `rr_realize`, which agrees with
# CPython's `rr_py_realize` EXACTLY.
def rr_range_map(+ar: O.Arena, +tb: F.Table, sink: U32) -> RrMap:
  # => and the realize map is filled before the toposort -- - and that is
  # upstream's order too (`indexing.py:188` is the realize rewrite and `:192` is the
  # toposort), - and `sink` is read twice, so the order matters: the realize map
  # MUST COME FIRST.
  # => `sink` is read twice, so it is bound once to a `+` local (which is BEND's
  # spelling for "readable many times") - and the realize map is filled before the
  # TOPOSORT, WHICH IS UPSTREAM's ORDER (`indexing.py:188` THEN `:192`).
  +sk = sink
  +rm = rr_realize(ar, sk)
  +topo = O.UOp.toposort(O.Arena.budget(ar), ar, sk)
  +rev = rr_rev(topo)
  # => and the context is built by the port's own constructor
  # (`indexing.bend:213` `ix_ctx_realize(rm)`), => BECAUSE A LITERAL WITH A CALL IN IT
  # CANNOT BE INFERRED -- THE ERROR IS *"expected : an annotated term (cannot infer)"*.
  # => and the constructor is named for exactly this job: *"a context with a realize map
  # and nothing ELSE ... upstream fills the realize map before the RANGE-map LOOP
  # (`indexing.py:188`), SO THE LOOP's CONTEXT STARTS WITH IT."*
  +ctx = IX.ix_ctx_realize(rm)
  rr_range_map.go(rev, ar, tb, rev, RrMap{ctx, Nil{}, [IX.ix_rg_c0()], Nil{}, Nil{}, False{}, False{}, False{}})


# 3. THE ROWS.

def rr_row.line(nm: String, got: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", got]))

def rr_real_axes.go(+xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: rr_real_axes.go(t, List.append(&2, String, acc, [U32.show(x)]))

def rr_real_axes(+e: IX.IxReal) -> String:
  Bool.pick(String, IX.IxReal.islist(e),
            String.join(rr_real_axes.go(IX.IxReal.axes(e), Nil{}), ","), "none")

def rr_real_row.go(+es: List<&2, IX.IxReal>, +ar: O.Arena, +acc: List<&2, String>) -> List<&2, String>:
  match es:
    case Nil{}: acc
    case e <> t:
      rr_real_row.go(t, ar,
        List.append(&2, String, acc,
          [String.concat([rr_node_str(ar, IX.IxReal.n(e)), ":", rr_real_axes(e)])]))

def rr_row_realize() -> String:
  +q = RZ.rz_built()
  +ar = RZ.RZProg.ar(q)
  +m = rr_realize(ar, RZ.RZProg.sink(q))
  String.join(rr_real_row.go(IX.IxMap.es(m), ar, Nil{}), ";")

# the planted row. - it is a row, not a build.
def rr_row_realize_plant() -> String:
  +q = RZ.rz_built()
  +ar = RZ.RZProg.ar(q)
  +m = rr_realize_plant(ar, RZ.RZProg.sink(q))
  String.join(rr_real_row.go(IX.IxMap.es(m), ar, Nil{}), ";")

def rr_row_in() -> String:
  +q = RZ.rz_built()
  rr_dump(RZ.RZProg.ar(q), RZ.RZProg.sink(q))



# 5. the RANGE map's row. the oracle's spelling: `#N <node>:[<in>]->[<out>]`,
# and a RANGE is `R` and its axis ID while the CONST 0 is `<CONST:cother:>`
# (`rr-oracle.py`'s `render_range`).

def rr_rng_str.c0() -> String: "<CONST:cother:>"
def rr_rng_str.rg(i: U32) -> String: String.concat(["R", U32.show(i)])

def rr_rng_str.of(c0: Bool, i: U32) -> String:
  match c0:
    case True{}: rr_rng_str.c0()
    case False{}: rr_rng_str.rg(i)

def rr_rng_str(+tbl: List<&2, IX.IxRange>, r: U32) -> String:
  +e = IX.ix_tbl_at(tbl, r)
  rr_rng_str.of(IX.ix_rg_is_c0(e), IX.IxRange.idx(e))

def rr_rngs_str.go(+tbl: List<&2, IX.IxRange>, +rs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match rs:
    case Nil{}: acc
    case r <> t: rr_rngs_str.go(tbl, t, List.append(&2, String, acc, [rr_rng_str(tbl, r)]))

def rr_rngs_str(+tbl: List<&2, IX.IxRange>, +rs: List<&2, U32>) -> String:
  String.concat(["[", String.join(rr_rngs_str.go(tbl, rs, Nil{}), ","), "]"])

def rr_range_one.of(m: Maybe<&2, IX.IxRngs>, k: Nat, +ctx: IX.IxCtx, +tbl: List<&2, IX.IxRange>,
                    +ar: O.Arena, +n: U32) -> List<&2, String>:
  match m:
    case Some{e}:
      +r = e
      [String.concat(["#", U32.show(U32.from_nat(k)), " ", rr_node_str(ar, n), ":",
                      rr_rngs_str(tbl, IX.IxRngs.inp(r)), "->", rr_rngs_str(tbl, IX.IxRngs.outp(r))])]
    case _: Nil{}

def rr_range_row.go(+ns: List<&2, U32>, +k: Nat, +ctx: IX.IxCtx, +tbl: List<&2, IX.IxRange>,
                    +ar: O.Arena, +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case n <> t:
      +e = IX.ix_rngm_get(IX.IxCtx.rngm(ctx), n)
      rr_range_row.go(t, Nat.add(k, 1n), ctx, tbl, ar,
        List.append(&2, String, acc, rr_range_one.of(e, k, ctx, tbl, ar, n)))

def rr_row_range() -> String:
  +q = RZ.rz_built()
  +ar = RZ.RZProg.ar(q)
  +sink = RZ.RZProg.sink(q)
  +tb = F.Folded.t(F.folded(ar))
  +m = rr_range_map(ar, tb, sink)
  String.join(rr_range_row.go(O.UOp.toposort(O.Arena.budget(ar), ar, sink), 0n,
                              RrMap.ctx(m), RrMap.tbl(m), ar, Nil{}), ";")


# the apply rewrite -- the second half of `run_rangeify`.
#
# UPSTREAM'S `pm_apply_rangeify` (`tinygrad/schedule/indexing.py:130-140`) IS FIVE
# RULES, AND THE BULK IS RULE 4, `create_bufferize_and_index_based_on_ranges`
# (`:97-98`), WHICH CALLS `create_bufferize_and_index_srcs` (`:73-95`) -- 23 LINES AND
# THE WHOLE OF THE TRANSFORMATION.
#
# => and the port has the RANGE map already (it is `rr_range_map`), => so the
# ranges exist and the only thing missing is the rewrite that uses them.
#
# => AND THE FIVE RULES ARE (`indexing.py:130-140`):
#   1. `convert_reduce_to_reduce_with_ranges`  (`:106-112`)
#   2. `convert_pad_to_where_to_keep_behavior_local` (`:100-104`)
#   3. `convert_stack_to_where` (`:120-125`)
#   4. `create_bufferize_and_index_based_on_ranges` (`:97-98`) -- EVERY OTHER NODE
#      gets its srcs rebuilt: its PARAM/BUFFER/alloc/mstack/mselect/after srcs are
#      indexed by the ranges, and its realized srcs become a `STAGE` (or an `END`
#      FOR A STORE).
#   5. `remove_movement_op_after_rangeify` (`:127-128`) -- A MOVEMENT OP IS REPLACED BY
#      ITS `src[0]` WHEN IT IS IN THE RANGE MAP.
#
# => and the rewrite is `bottom_up=True` (`indexing.py:308`), => so the port walks
# the arena in reverse INDEX order (which is children first, because the arena's
# INDEX ORDER IS TOPOLOGICAL -- `uop/ops.bend:1314 symbol=Arena`).
#
# => and the RANGE map's entries are the input ranges of a node (`IxRngs.inp`)
# and the output ranges (`IxRngs.outp`), and the apply uses both: the input
# ranges INDEX the srcs (`broadcast_rngs`) and the output ranges become the `STAGE`'s
# CLOSED RANGES.


# the op tests the five rules need. => a `match` may not scrutinize a computed value, so
# EACH TEST IS ITS OWN DEF.
def rr_ap_reduce(+ar: O.Arena, x: U32) -> Bool: O.eq_op(O.Arena.op(ar, x), O.OpsREDUCE{})
def rr_ap_pad(+ar: O.Arena, x: U32) -> Bool: O.eq_op(O.Arena.op(ar, x), O.OpsPAD{})
def rr_ap_stack(+ar: O.Arena, x: U32) -> Bool: O.eq_op(O.Arena.op(ar, x), O.OpsSTACK{})
def rr_ap_index(+ar: O.Arena, x: U32) -> Bool: O.eq_op(O.Arena.op(ar, x), O.OpsINDEX{})
def rr_ap_store(+ar: O.Arena, x: U32) -> Bool: O.eq_op(O.Arena.op(ar, x), O.OpsSTORE{})

# the srcs that get indexed by the ranges (`indexing.py:80`):
# `{Ops.PARAM, Ops.BUFFER, Ops.ALLOC, Ops.MSTACK, Ops.MSELECT, Ops.AFTER}`.
def rr_ap_indexable.of(op: O.Op) -> Bool:
  match op:
    case O.OpsPARAM{}: True{}
    case O.OpsBUFFER{}: True{}
    case O.OpsALLOC{}: True{}
    case O.OpsMSTACK{}: True{}
    case O.OpsMSELECT{}: True{}
    case O.OpsAFTER{}: True{}
    case _: False{}

def rr_ap_indexable(+ar: O.Arena, x: U32) -> Bool: rr_ap_indexable.of(O.Arena.op(ar, x))

# the data srcs (`indexing.py:68-71`) -- the port's own `rr_dsrcs` is this already
# (`:393`), => so the count is the length of that list.
def rr_ap_dsrc_n(+ar: O.Arena, +x: U32) -> U32:
  U32.from_nat(List.length(&2, U32, rr_dsrcs(ar, O.Arena.op(ar, x), O.Arena.srcs(ar, x))))

# THE REALIZED SRCS (`indexing.py:82`): `s in ctx.realize_map`.
def rr_ap_realized(+ctx: IX.IxCtx, s: U32) -> Bool: IX.ix_rmap_has(IX.IxCtx.rmap(ctx), s)

# THE CLOSED RANGES OF A REALIZED SRC (`indexing.py:84`): `ctx.range_map[s][1]`.
# THE CLOSED RANGES OF A REALIZED SRC (`indexing.py:84`): `ctx.range_map[s][1]`.
def rr_ap_closed.of(m: Maybe<&2, IX.IxRngs>) -> List<&2, U32>:
  match m:
    case Some{e}: IX.IxRngs.outp(e)
    case _: Nil{}

# THE INPUT RANGES OF A NODE (`indexing.py:79`): `ctx.range_map[x][0]`.
# THE INPUT RANGES OF A NODE (`indexing.py:79`): `ctx.range_map[x][0]`.
#
# => - - and they are table indices, not nodes -- => because the port's
# RANGE MAP IS A TABLE (`rangify.bend`'s `RrRs{i, rs, tbl}`) AND A TABLE
# entry becomes a node only at the boundary (`indexing.bend:921` `ix_rg_node`).
# => - - so the apply materialises them, => and the port's arena internes
# THEM (`indexing.bend:899`), => SO ONE RANGE IS ONE NODE EVERYWHERE.
def rr_ap_inp.of(m: Maybe<&2, IX.IxRngs>) -> List<&2, U32>:
  match m:
    case Some{e}: IX.IxRngs.inp(e)
    case _: Nil{}

# THE INDEXED CASE (`indexing.py:80-81`): `new_src = new_src.index(*src_rngs)`, AND
# only IF the node is in the RANGE map and `i < data_src_count`.
# THE INPUT RANGES, BROADCAST (`indexing.py:79`):
# `broadcast_rngs(x, s, ctx.range_map[x][0])` -- the node first, => and the port's own
# `broadcast_rngs(op, src, x, rngs)` has the op first, => and `src` is the node's
# shape and `x` is the SRC's shape -- => - - and the port's own `ix_bax_nleft(src, x)`
# COMPUTES `len(x) - len(src)`, WHICH IS UPSTREAM's `len(s.shape) - len(x.shape)`.
# THE INPUT RANGES, BROADCAST (`indexing.py:79`):
# `broadcast_rngs(x, s, ctx.range_map[x][0])` -- THE NODE FIRST, => AND THE
# port's own `broadcast_rngs(op, src, x, rngs)` has the op first, => and `src` is
# the node's shape and `x` is the SRC's shape -- => - - and the
# PORT's OWN `ix_bax_nleft(src, x)` COMPUTES `len(x) - len(src)`, WHICH IS
# UPSTREAM's `len(s.shape) - len(x.shape)`.
# => - - and the ranges are table indices here too, => so the
# materialisation is after the broadcast (`broadcast_rngs` substitutes the
# CONST 0 for a broadcast axis, => and that is a table substitution).
def rr_ap_bcast(+ar: O.Arena, +tb: F.Table, +ctx: IX.IxCtx, +x: U32, +s: U32) -> List<&2, U32>:
  IX.broadcast_rngs(O.Arena.op(ar, x), rr_dims(ar, tb, x), rr_dims(ar, tb, s),
                    rr_ap_inp.of(IX.ix_rngm_get(IX.IxCtx.rngm(ctx), x)))

# one SRC, rebuilt (`indexing.py:78-94`). => and the two cases are disjoint: a SRC is
# either indexed (it is a PARAM/BUFFER/alloc/mstack/mselect/after) or realized
# (it is in the realize map), => and upstream's `if/elif` is that disjointion.
# the realized case (`indexing.py:85-93`): a STORE becomes an `END` with its closed
# ranges, => and everything ELSE becomes a `STAGE` -- => and the stage is then indexed
# IF THE NODE IS IN THE RANGE MAP.
def rr_ap_is_range.of(k: U32) -> Bool:
  match k:
    case 0: True{}
    case _: False{}

def rr_ap_is_range(+tbl: List<&2, IX.IxRange>, r: U32) -> Bool:
  rr_ap_is_range.of(IX.IxRange.kind(IX.ix_tbl_at(tbl, r)))

def rr_ap_ranges_only.go(+tbl: List<&2, IX.IxRange>, +closed: List<&2, U32>,
                          +acc: List<&2, U32>) -> List<&2, U32>:
  match closed:
    case Nil{}: acc
    case h <> t: rr_ap_ranges_only.go(tbl, t,
      Bool.pick(List<&2, U32>, rr_ap_is_range(tbl, h),
                List.append(&2, U32, acc, [h]), acc))

def rr_ap_ranges_only(+tbl: List<&2, IX.IxRange>, +closed: List<&2, U32>) -> List<&2, U32>:
  rr_ap_ranges_only.go(tbl, closed, Nil{})

# EVERYTHING ELSE BECOMES A `STAGE` (`indexing.py:90-92`): `new_src =
# UOp(Ops.STAGE, src=(new_src,)+closed_ranges, arg=opts)`, => AND THEN IT IS INDEXED IF
# THE NODE IS IN THE RANGE MAP.
# the ranges among the closed ones (`indexing.py:87`'s `if r.op is Ops.RANGE`). => and the
# table's INDEX 0 is the CONST 0, which is not a RANGE, => so the closed list's
# table indices are filtered through the table.
# ALL OF A NODE's SRCS, REBUILT (`indexing.py:73-95`).
# the stage node. => and the `BufferizeOpts` ARG is a named wall: `indexing.py:56-61` is
# a frozen dataclass read at `indexing.py:6-7`, and `ops.bend`'s `Arg` has no constructor
# for a stage's ARG at all -- => so `s.device`, `s.removable` and `s.addrspace` are all
# WALLS (`indexing.bend`'s HEADER, `:22-50`).
# => - - so the stage is built without the opts ARG, => and that is named here
# rather than hidden: a stage with no opts is a different graph, and the comparison
# AGAINST THE ORACLE WILL SHOW IT.
# A STORE BECOMES AN `END` (`indexing.py:87`): `new_src = s.end(*[r for r in closed_ranges
# if r.op is Ops.RANGE])`. => and "is a RANGE" is a table lookup: the table's entries are
# `IxRange{kind, idx, ext}` AND KIND 0 IS A RANGE (`indexing.bend:153` `ix_rg_r`).
# THE INDEXED CASE (`indexing.py:80-81`).

# the apply driver. the rewrite is `bottom_up=True` (`indexing.py:308`), => so the
# port walks the arena in reverse INDEX order -- => which is children first,
# because the arena's INDEX order is topological (`ops.bend:2754`: *"UOp.new is only ever
# called with srcs already in the arena, so every node's SRC indices are all below its own
# POSITION"*).
#
# => - - and each node's rebuilt srcs are the rebuilt srcs of its children --
# => and the port's own `UOp.replace` (`ops.bend:2986`) is exactly upstream's
# `x.replace(src=tuple(...))`.
#
# => - - and the map is the old INDEX -> new INDEX map, => and the port's own
# `Rep{old, new}` (`rangeify.bend:2758`) IS THE SAME SHAPE -- => - - AND SO THE
# apply's output is the same kind of thing the engine's `eng_*` produces, => which
# IS WHAT MAKES THE TWO COMPOSE.



# the rebuild map -- the (old node, rebuilt node) pairs, in walk order.
#
# => - - and the port's arena is append-only (`ops.bend:2754`: *"UOp.new is only ever
# called with srcs already in the arena"*), => - - so a rebuilt node cannot replace
# an old one in place -- => - - and upstream's `graph_rewrite` does replace in
# place (`x.replace(src=...)` returns a new uop and the rewrite's worklist carries it),
# => - - - so the port needs an explicit map -- => - - - and that is why the
# port's own `Rep{old, new}` map exists (`rangeify.bend:2758`) and why the engine's
# `eng_put` EXISTS.
#
# => - - and the map is the (old, new) pairs so that a child's rebuilt node can
# be found by its old node -- => - - - and the pairs are in walk order, => - -
# - and the walk is the reversed toposort, => - - - - so a node's children are
# walked before it and the rebuilt srcs are the pairs' new values for the old
# CHILDREN.

type ApRep is Data:
  ApRep{old: U32, new: U32}

def ApRep.old(x: ApRep) -> U32:
  match x:
    case ApRep{old, new}: old

def ApRep.new(x: ApRep) -> U32:
  match x:
    case ApRep{old, new}: new
# the map's lookup: the new node for an old node, => and a node not in
# the map is the unchanged one (it is outside the walk -- the toposort drops
# THE BOTTOM).
def ApRep.of(old: U32, new: U32) -> ApRep: ApRep{old, new}

def ap_rep_get.one(hit: Bool, v: U32, acc: Maybe<&2, U32>) -> Maybe<&2, U32>:
  Bool.pick(Maybe<&2, U32>, hit, Some{v}, acc)

def ap_rep_get.go(+es: List<&2, ApRep>, +k: U32, acc: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match es:
    case Nil{}: acc
    case e <> t:
      ap_rep_get.go(t, k, ap_rep_get.one(U32.is_eq(ApRep.old(e), k), ApRep.new(e), acc))

# the map's put: the (old, new) pair.
def ap_rep_put(+es: List<&2, ApRep>, old: U32, new: U32) -> List<&2, ApRep>:
  List.append(&2, ApRep, es, [ApRep.of(old, new)])

def ap_rep_get(+es: List<&2, ApRep>, k: U32) -> Maybe<&2, U32>:
  ap_rep_get.go(es, k, None{})


# THE APPLY. `pm_apply_rangeify` (`indexing.py:130-141`) IS FIVE RULES IN A
# list, and the list's order is the order `PatternMatcher.rewrite` tries
# THEM -- MEASURED, NOT ASSUMED: `.agents/slop/rangify/rr-rules.py` ASKS
# upstream's own matcher about every node of the same program and
# prints what each one becomes.  the measured readings:
#
#   RESHAPE -> RESHAPE   (RULE 4 CHANGED IT)
#   PERMUTE -> MUL       (RULE 5 REPLACED IT WITH ITS `src[0]`)
#   REDUCE  -> REDUCE    (RULE 1)
#   STORE   -> None      (NO RULE FIRED)
#
# => - - and the order is not a matter of style: the fixed point makes it
# MATTER.  UPSTREAM's `unified_rewrite` (`ops.py`) RUNS
#
#     test_n = n
#     while test_n is not None:
#       new_n, test_n = test_n, self.cached_bpm_rewrite(test_n)
#
# => - - so a `RESHAPE` is rewritten twice: once by rule 4 (which puts
# an `INDEX` in its `src[0]`) and then again, and the second pass takes
# rule 5 -- => because `rewrite` skips a rule that returns the node itself
# (`ret is not uop`), => - - and that is why rule 4 must return NONE when
# it changes nothing.  => - - and the port's first attempt applied one rule
# and produced the unchanged input graph -- - and that is why it did.
#
# - and the second half is upstream's stage 2 (`ops.py`, `unified_rewrite`):
# the rebuilt node's srcs are the rebuilt children -- `new_src = tuple(
# self.replace.get(x, x) for x in new_n.src)` -- - AND THE PORT's ARENA IS
# append-only (`uop/ops.bend:1314 symbol=Arena`), - - - so the port needs an explicit
# map, - - - and that is why the port's own `Rep{old, new}` map exists
# (`schedule/rangeify.bend:2758 symbol=Rep`) AND WHY THE ENGINE's `eng_put` EXISTS.
#

# THE ARENA IS A VALUE, NOT A MUTABLE STORE (`ops.bend:1314`: *"`Arena` is
# `Data`"*), AND BEND's `+` IS A REUSABLE LET, NOT A REBINDING (`bend
# guide`: *"`x = v  +x = v  -x = v` -- a let: affine, reusable, erased"*), - AND
# so a DEF that mints a node must hand the grown arena back -- - and
# the port's spelling for that is `Found{ar, i}` (`ops.bend:2765`), - and
# `realize.bend:113`'s `O.Found.ar(r)` IS THE PATTERN.
#
# - - - and the first attempt at this block dropped the arena (`O.Found.i(f)`
# without `O.Found.ar(f)`), - - - which puts every new node in a phantom
# arena and makes the reads below it read the old arena's entry -- - and
# that is a second instance of the class this tree names: a result
# that nothing reads.  - and the port's own `rr_ap_node` had it too.


# the two records that carry the arena alongside the list.
type ApSrcs is Data:
  ApSrcs{ar: O.Arena, ss: List<&2, U32>}

def ApSrcs.of(+ar: O.Arena, +ss: List<&2, U32>) -> ApSrcs: ApSrcs{ar, ss}

def ApSrcs.ar(+x: ApSrcs) -> O.Arena:
  match x:
    case ApSrcs{ar, ss}: ar

def ApSrcs.ss(+x: ApSrcs) -> List<&2, U32>:
  match x:
    case ApSrcs{ar, ss}: ss

type ApFin is Data:
  ApFin{ar: O.Arena, fin: List<&2, ApRep>}

def ApFin.of(+ar: O.Arena, +fin: List<&2, ApRep>) -> ApFin: ApFin{ar, fin}

def ApFin.ar(+x: ApFin) -> O.Arena:
  match x:
    case ApFin{ar, fin}: ar

def ApFin.fin(+x: ApFin) -> List<&2, ApRep>:
  match x:
    case ApFin{ar, fin}: fin

# the node itself, grown arena and all -- => and it is the unchanged
# NODE WHEN NOBODY MINTS ONE.
def rr_ap_keep(+ar: O.Arena, +s: U32) -> O.Found:
  O.Found{ar, s}

# the materialiser: a table entry becomes a node (`indexing.bend:901`
# `ix_rg_node`), => AND THE PORT's ARENA INTERNES IT (`indexing.bend:921`),
# => so one RANGE is one node everywhere, => which is what makes the table
# sound.  => - - and the port's RANGE map is a table, => - - so this is
# THE BOUNDARY WHERE A RANGE ENTERS THE GRAPH.
def rr_ap_rng_nodes.go(+rs: List<&2, U32>, +ar: O.Arena, +tbl: List<&2, IX.IxRange>,
                       +acc: List<&2, U32>) -> ApSrcs:
  match rs:
    case Nil{}: ApSrcs.of(ar, acc)
    case r <> t:
      +f = IX.ix_rg_node(O.AXIS_WEAK{}, ar, IX.ix_tbl_at(tbl, r))
      rr_ap_rng_nodes.go(t, O.Found.ar(f), tbl, List.append(&2, U32, acc, [O.Found.i(f)]))

def rr_ap_rng_nodes(+ar: O.Arena, +tbl: List<&2, IX.IxRange>, +rs: List<&2, U32>) -> ApSrcs:
  rr_ap_rng_nodes.go(rs, ar, tbl, Nil{})

# THE INDEXED CASE (`indexing.py:80-81`): `new_src = new_src.index(*src_rngs)`,
# => and only IF the node is in the RANGE map and `i < data_src_count`.
def rr_ap_index_node(+ar: O.Arena, +s: U32, +rngs: List<&2, U32>) -> O.Found:
  O.UOp.index(ar, s, rngs)

def rr_ap_index_src(+ar: O.Arena, +tb: F.Table, +tbl: List<&2, IX.IxRange>, +ctx: IX.IxCtx,
                    +x: U32, +s: U32, +i: U32, +dsrc_n: U32) -> O.Found:
  +has = IX.ix_rngm_has(IX.IxCtx.rngm(ctx), x)
  # => - - and the broadcast ranges are table indices, => - - so they must be
  # materialised before they can be an `INDEX`'s srcs -- => and not
  # materialising them is what put a `CONST` and a `BUFFER` in the INDEX
  # (MEASURED: `rr_arena`'s `29->43:...INDEX:none:PARAM,CONST,BUFFER`).
  +rs = rr_ap_bcast(ar, tb, ctx, x, s)
  +rn = rr_ap_rng_nodes(ar, tbl, rs)
  +ix = rr_ap_index_node(ApSrcs.ar(rn), s, ApSrcs.ss(rn))
  Bool.pick(O.Found, Bool.and(has, U32.is_lt(i, dsrc_n)), ix, rr_ap_keep(ApSrcs.ar(rn), s))

# EVERYTHING ELSE BECOMES A `STAGE` (`indexing.py:90-92`): `new_src =
# UOp(Ops.STAGE, src=(new_src,)+closed_ranges, arg=opts)`, => AND THEN IT IS INDEXED IF
# THE NODE IS IN THE RANGE MAP.
def rr_ap_stage_node(+ar: O.Arena, +s: U32, +closed: List<&2, U32>) -> O.Found:
  O.UOp.new(ar, O.OpsSTAGE{}, List.append(&2, U32, [s], closed), O.ANone{}, O.TNone{})

def rr_ap_stage_src(+ar: O.Arena, +tbl: List<&2, IX.IxRange>, +ctx: IX.IxCtx, +x: U32, +s: U32,
                    +closed: List<&2, U32>) -> O.Found:
  +cl = rr_ap_rng_nodes(ar, tbl, closed)
  +st = rr_ap_stage_node(ApSrcs.ar(cl), s, ApSrcs.ss(cl))
  +has = IX.ix_rngm_has(IX.IxCtx.rngm(ctx), x)
  +inp = rr_ap_rng_nodes(O.Found.ar(st), tbl, rr_ap_inp.of(IX.ix_rngm_get(IX.IxCtx.rngm(ctx), x)))
  Bool.pick(O.Found, has, rr_ap_index_node(O.Found.ar(st), O.Found.i(st), ApSrcs.ss(inp)), st)

# A STORE BECOMES AN `END` (`indexing.py:87`): `new_src = s.end(*[r for r in closed_ranges
# if r.op is Ops.RANGE])`. => and "is a RANGE" is a table lookup: the table's entries are
# `IxRange{kind, idx, ext}` AND KIND 0 IS A RANGE (`indexing.bend:153` `ix_rg_r`).
def rr_ap_end_src(+ar: O.Arena, +tbl: List<&2, IX.IxRange>, +s: U32,
                  +closed: List<&2, U32>) -> O.Found:
  +rs = rr_ap_rng_nodes(ar, tbl, closed)
  O.UOp.end(ApSrcs.ar(rs), s, ApSrcs.ss(rs))

# the realized case (`indexing.py:85-93`): a STORE becomes an `END` with its closed
# ranges, => and everything ELSE becomes a `STAGE` -- => and the stage is then indexed
# IF THE NODE IS IN THE RANGE MAP.
def rr_ap_realized_src(+ar: O.Arena, +tbl: List<&2, IX.IxRange>, +ctx: IX.IxCtx, +x: U32,
                       +s: U32) -> O.Found:
  +closed = rr_ap_closed.of(IX.ix_rngm_get(IX.IxCtx.rngm(ctx), s))
  +rs = rr_ap_ranges_only(tbl, closed)
  Bool.pick(O.Found, rr_ap_store(ar, s), rr_ap_end_src(ar, tbl, s, rs),
            rr_ap_stage_src(ar, tbl, ctx, x, s, closed))

# one SRC, rebuilt (`indexing.py:78-94`). => and the two cases are disjoint: a SRC is
# either indexed (it is a PARAM/BUFFER/alloc/mstack/mselect/after) or realized
# (it is in the realize map), => and upstream's `if/elif` is that disjointion.
def rr_ap_src.of(+ar: O.Arena, +tb: F.Table, +tbl: List<&2, IX.IxRange>, +ctx: IX.IxCtx, +x: U32,
                 +s: U32, +i: U32, +dsrc_n: U32) -> O.Found:
  +inx = rr_ap_indexable(ar, s)
  +real = rr_ap_realized(ctx, s)
  Bool.pick(O.Found, Bool.and(inx, Bool.not(real)),
            rr_ap_index_src(ar, tb, tbl, ctx, x, s, i, dsrc_n),
    Bool.pick(O.Found, real, rr_ap_realized_src(ar, tbl, ctx, x, s), rr_ap_keep(ar, s)))

# ALL OF A NODE's SRCS, REBUILT (`indexing.py:73-95`).
#
# => - - and the shrinking argument is first, => because a self-call's
# arguments are read left to right and each is passed unchanged until one
# shrinks, => and the arena is the first thing that changes (every
# mint grows it), => - - so it must come after the list.
def rr_ap_srcs.go(+ss: List<&2, U32>, +ar: O.Arena, +tb: F.Table, +tbl: List<&2, IX.IxRange>,
                  +ctx: IX.IxCtx, +x: U32, +dsrc_n: U32, +i: U32,
                  +acc: List<&2, U32>) -> ApSrcs:
  match ss:
    case Nil{}: ApSrcs.of(ar, acc)
    case s <> t:
      +f = rr_ap_src.of(ar, tb, tbl, ctx, x, s, i, dsrc_n)
      rr_ap_srcs.go(t, O.Found.ar(f), tb, tbl, ctx, x, dsrc_n, U32.add(i, 1),
        List.append(&2, U32, acc, [O.Found.i(f)]))

def rr_ap_srcs(+ar: O.Arena, +tb: F.Table, +tbl: List<&2, IX.IxRange>, +ctx: IX.IxCtx, +x: U32,
               +ss: List<&2, U32>) -> ApSrcs:
  rr_ap_srcs.go(ss, ar, tb, tbl, ctx, x, rr_ap_dsrc_n(ar, x), 0, Nil{})


# THE FIVE RULES, IN UPSTREAM's ORDER.


# RULE 4 -- `GroupOp.All-{Ops.STAGE, Ops.INDEX}` (`indexing.py:138`):
# `x.replace(src=tuple(create_bufferize_and_index_srcs(ctx, x)))`.
def rr_ap_r4_skip(+ar: O.Arena, +x: U32) -> Bool:
  Bool.or(rr_ap_index(ar, x), O.eq_op(O.Arena.op(ar, x), O.OpsSTAGE{}))

def rr_ap_r4_node(+ar: O.Arena, +tb: F.Table, +tbl: List<&2, IX.IxRange>, +ctx: IX.IxCtx,
                  +x: U32) -> O.Found:
  +ss = O.Arena.srcs(ar, x)
  +ns = rr_ap_srcs(ar, tb, tbl, ctx, x, ss)
  O.UOp.replace(ApSrcs.ar(ns), x, None{}, Some{ApSrcs.ss(ns)}, None{}, None{})

# => - - and rule 4 returns NONE when the srcs did not change -- => because
# `PatternMatcher.rewrite` skips a rule that returns the node itself (`ret is
# not uop`), => - - and that is what lets rule 5 see the same node.
def rr_ap_r4(+ar: O.Arena, +tb: F.Table, +tbl: List<&2, IX.IxRange>, +ctx: IX.IxCtx,
             +x: U32) -> Maybe<&2, O.Found>:
  +f = rr_ap_r4_node(ar, tb, tbl, ctx, x)
  Bool.pick(Maybe<&2, O.Found>, U32.is_eq(O.Found.i(f), x), None{}, Some{f})

# RULE 1 -- `REDUCE` (`indexing.py:106-112`).
# `if x.arg[1] == 0: return None`; `if x not in ctx.range_map: raise`; then
# `bx = create_bufferize_and_index_based_on_ranges(ctx, x)`,
# `new_ranges = list(ctx.range_map[x][0][:x.arg[1]])`, and
# `UOp(Ops.REDUCE, src=(bx.src[0],)+tuple(new_ranges), arg=(x.arg[0], 0))`.
def rr_ap_red_num.of(+a: O.Arg) -> U32:
  match a:
    case O.AReduce{rop, num_axes}: num_axes
    case _: 0

def rr_ap_red_num(+ar: O.Arena, +x: U32) -> U32:
  rr_ap_red_num.of(O.Arena.arg(ar, x))

def rr_ap_red_op.of(+a: O.Arg) -> O.Op:
  match a:
    case O.AReduce{rop, num_axes}: rop
    case _: O.OpsADD{}

def rr_ap_red_op(+ar: O.Arena, +x: U32) -> O.Op:
  rr_ap_red_op.of(O.Arena.arg(ar, x))

def rr_ap_red_hit(+ar: O.Arena, +ctx: IX.IxCtx, +x: U32) -> Bool:
  Bool.and(rr_ap_reduce(ar, x),
    Bool.and(U32.is_ne(rr_ap_red_num(ar, x), 0),
             IX.ix_rngm_has(IX.IxCtx.rngm(ctx), x)))

def rr_ap_red_new(+ar: O.Arena, +tb: F.Table, +tbl: List<&2, IX.IxRange>, +ctx: IX.IxCtx,
                  +x: U32) -> O.Found:
  +bx = rr_ap_r4_node(ar, tb, tbl, ctx, x)
  +ar2 = O.Found.ar(bx)
  +n = rr_ap_red_num(ar2, x)
  +rs = List.take(&2, U32, rr_ap_inp.of(IX.ix_rngm_get(IX.IxCtx.rngm(ctx), x)), U32.to_nat(n))
  +rn = rr_ap_rng_nodes(ar2, tbl, rs)
  +ar3 = ApSrcs.ar(rn)
  +srcs = List.append(&2, U32, [O.Arena.src(ar2, O.Found.i(bx), 0)], ApSrcs.ss(rn))
  rop = rr_ap_red_op(ar2, x)
  # => - - AND THE ARG IS THE PORT's OWN `UOp.reduce.arg` (`ops.bend:7474`),
  # => BECAUSE `AReduce{rop, 0}` AS A LET CANNOT BE INFERRED (MEASURED:
  # the compiler says *"an annotated term (cannot infer)"*), => and the port's
  # own spelling takes a `Maybe<&2, Op>` and makes the same pair.
  +ropm = {Some{rop} : Maybe<&2, O.Op>}
  +arg = O.UOp.reduce.arg(ropm)
  O.UOp.new(ar3, O.OpsREDUCE{}, srcs, arg, O.TNone{})

def rr_ap_red_some(+ar: O.Arena, +tb: F.Table, +tbl: List<&2, IX.IxRange>, +ctx: IX.IxCtx,
                   +x: U32) -> Maybe<&2, O.Found>:
  +f = rr_ap_red_new(ar, tb, tbl, ctx, x)
  Some{f}

# rules 2 and 3 -- `PAD` and `STACK` (`indexing.py:100-125`) -- are named walls.
# `convert_pad_to_where_to_keep_behavior_local` NEEDS `UOp.const(True).uprod([...])`
# AND `.where(...)`; `convert_stack_to_where` NEEDS `_stack_select`, => AND
# the port has neither `where` nor `usum` nor `%` (`ops.bend` has no such
# constructors).  - and the port does not pretend: it leaves the node
# unchanged and counts it, => and the count is a row (`rr_wall`), - and
# a wall that is counted is not a silent divergence.
def rr_ap_wall_hit(+ar: O.Arena, +ctx: IX.IxCtx, +x: U32) -> Bool:
  Bool.and(IX.ix_rngm_has(IX.IxCtx.rngm(ctx), x),
    Bool.or(rr_ap_pad(ar, x), rr_ap_stack(ar, x)))

# RULE 5 -- `GroupOp.Movement` (`indexing.py:127-128`):
# `if x in ctx.range_map or x.src[0].op is Ops.INDEX: return x.src[0]`.
# the movement ops (`indexing.py:163-180`): reshape, expand, permute, pad, shrink.
# => and the port's own `O.GroupOp.movement` is the port's own spelling of
# UPSTREAM's `GroupOp.Movement` (`uop/__init__.py`).
def rr_ap_mv.of(op: O.Op) -> Bool: O.GroupOp.movement(op)

def rr_ap_mv(+ar: O.Arena, x: U32) -> Bool: rr_ap_mv.of(O.Arena.op(ar, x))

# => - - AND RULE 5 IS A MOVEMENT OP's RULE (`UPat(GroupOp.Movement,
# name="x")`, `indexing.py:140`), => - - AND LEAVING THAT OUT MAKES IT
# fire on every node in the RANGE map -- => and the port's own RANGE map has
# SIX CONSTS AND THREE PARAMs IN IT (`rr_range`), => - - AND A `CONST`
# has no `src[0]`, => - - and the answer was the bottom (node 0), => - -
# and that is the `OTHER` in the dump -- measured, not guessed (the
# `rr_arena` ROW: `1->0:CONST:cother:/OTHER:other:`).
def rr_ap_r5_hit(+ar: O.Arena, +ctx: IX.IxCtx, +x: U32) -> Bool:
  Bool.and(rr_ap_mv(ar, x),
    Bool.or(IX.ix_rngm_has(IX.IxCtx.rngm(ctx), x),
            rr_ap_index(ar, O.Arena.src(ar, x, 0))))

def rr_ap_r5.some(+ar: O.Arena, +s: U32) -> Maybe<&2, O.Found>:
  +f = rr_ap_keep(ar, s)
  Some{f}

def rr_ap_r5(+ar: O.Arena, +ctx: IX.IxCtx, +x: U32) -> Maybe<&2, O.Found>:
  Bool.pick(Maybe<&2, O.Found>, rr_ap_r5_hit(ar, ctx, x),
            rr_ap_r5.some(ar, O.Arena.src(ar, x, 0)), None{})

# RULES 4 THEN 5, IN UPSTREAM's ORDER.
def rr_ap_r45.go(+ar: O.Arena, +tb: F.Table, +tbl: List<&2, IX.IxRange>, +ctx: IX.IxCtx,
                 +x: U32, +r4: Maybe<&2, O.Found>) -> Maybe<&2, O.Found>:
  Bool.pick(Maybe<&2, O.Found>, Maybe.is_some(&2, O.Found, r4), r4, rr_ap_r5(ar, ctx, x))

def rr_ap_r45.of(+ar: O.Arena, +tb: F.Table, +tbl: List<&2, IX.IxRange>, +ctx: IX.IxCtx,
                  +x: U32) -> Maybe<&2, O.Found>:
  Bool.pick(Maybe<&2, O.Found>, rr_ap_r4_skip(ar, x), None{},
    rr_ap_r45.go(ar, tb, tbl, ctx, x, rr_ap_r4(ar, tb, tbl, ctx, x)))

# one pass of the matcher over one node: rule 1, then the walls, then 4 then 5.
def rr_ap_once.of(+ar: O.Arena, +tb: F.Table, +tbl: List<&2, IX.IxRange>, +ctx: IX.IxCtx,
                  +x: U32) -> Maybe<&2, O.Found>:
  Bool.pick(Maybe<&2, O.Found>, rr_ap_red_hit(ar, ctx, x), rr_ap_red_some(ar, tb, tbl, ctx, x),
    Bool.pick(Maybe<&2, O.Found>, rr_ap_wall_hit(ar, ctx, x), None{},
      rr_ap_r45.of(ar, tb, tbl, ctx, x)))

def rr_ap_once(+ar: O.Arena, +tb: F.Table, +tbl: List<&2, IX.IxRange>, +ctx: IX.IxCtx,
               +x: U32) -> Maybe<&2, O.Found>:
  rr_ap_once.of(ar, tb, tbl, ctx, x)

# THE ARENA AND THE INDEX, OUT OF A `Maybe`.
def rr_ap_ar(+r: Maybe<&2, O.Found>, +ar: O.Arena) -> O.Arena:
  match r:
    case Some{f}: O.Found.ar(f)
    case None{}: ar

def rr_ap_idx(+r: Maybe<&2, O.Found>, +d: U32) -> U32:
  match r:
    case Some{f}: O.Found.i(f)
    case None{}: d

# the fixed point (`ops.py`'s `while test_n is not None:` LOOP). => and the fuel
# is 16, => and that is a fuel, not a bound on the answer: the port's
# graph is 23 nodes and the measured fixed point is two steps.
def rr_ap_fix.go(+fuel: Nat, +ar: O.Arena, +tb: F.Table, +tbl: List<&2, IX.IxRange>,
                 +ctx: IX.IxCtx, +n: U32, +acc: Maybe<&2, O.Found>) -> Maybe<&2, O.Found>:
  match fuel:
    case 0n: acc
    case 1n+f:
      +r = rr_ap_once(ar, tb, tbl, ctx, n)
      +ar2 = rr_ap_ar(r, ar)
      Bool.pick(Maybe<&2, O.Found>, Maybe.is_none(&2, O.Found, r), acc,
        rr_ap_fix.go(f, ar2, tb, tbl, ctx, rr_ap_idx(r, n), r))

def rr_ap_fix(+ar: O.Arena, +tb: F.Table, +tbl: List<&2, IX.IxRange>, +ctx: IX.IxCtx,
              +x: U32) -> Maybe<&2, O.Found>:
  rr_ap_fix.go(16n, ar, tb, tbl, ctx, x, None{})

# the fixed point's answer, or the node itself IF no rule fired.
def rr_ap_fix_val.go(+ar: O.Arena, +tb: F.Table, +tbl: List<&2, IX.IxRange>, +ctx: IX.IxCtx,
                     +x: U32, +r: Maybe<&2, O.Found>) -> O.Found:
  match r:
    case Some{f}: f
    case None{}: rr_ap_keep(ar, x)

def rr_ap_fix_val(+ar: O.Arena, +tb: F.Table, +tbl: List<&2, IX.IxRange>, +ctx: IX.IxCtx,
                  +x: U32) -> O.Found:
  rr_ap_fix_val.go(ar, tb, tbl, ctx, x, rr_ap_fix(ar, tb, tbl, ctx, x))


# THE FINAL PASS -- UPSTREAM's STAGE 2 (`ops.py`'s `unified_rewrite`):
# `new_src = tuple(self.replace.get(x, x) for x in new_n.src)` AND THEN
# `self.replace[n] = UOp(new_n.op, new_src, new_n.arg, new_n.tag)`.
#
# => - - so a node's final form is the fixed point's form with the
# final forms of its srcs -- => and the port's arena is append-only,
# => - - so the port's map is the (old, final) pairs and the lookup is
# A SEARCH (`ap_rep_get`).
#
# => - - and a node not in the map is the unchanged one -- => and
# THAT IS UPSTREAM's `self.replace.get(x, x)` WITH `x` NOT IN `self.replace`.
# => - - and a fresh node (one the rewrite created) is in upstream's
# `self.replace` (the stack walks it), => - - SO THE PORT LEAVES IT UNCHANGED
# -- => and that is a named wall, not a silent divergence: it matters only
# when a fresh node's SRC has a different final, => and the one way that
# happens is the `INDEX` over a `STAGE` (`rr_ap_stage_src` builds the `STAGE`
# AND THEN THE `INDEX` THAT INDEXES IT).


# the final form of a node: the map's answer IF it has one, => and the
# NODE ITSELF IF IT DOES NOT.
def rr_ap_final.of(+fin: List<&2, ApRep>, +x: U32) -> U32:
  Maybe.default(&2, U32, ap_rep_get(fin, x), x)

# THE SRCS, REMAPPED.
def rr_ap_final_srcs.go(+fin: List<&2, ApRep>, +ss: List<&2, U32>,
                        +acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}: acc
    case s <> t:
      rr_ap_final_srcs.go(fin, t,
        List.append(&2, U32, acc, [rr_ap_final.of(fin, s)]))

def rr_ap_final_srcs(+fin: List<&2, ApRep>, +ss: List<&2, U32>) -> List<&2, U32>:
  rr_ap_final_srcs.go(fin, ss, Nil{})

# the fresh nodes -- the ones the fix created -- are the arena's new
# entries, => and the arena is in creation order, => and creation order
# is dependency order for these nodes (a `STAGE` is created before the
# `INDEX` that indexes it), => - - so the walk over them is well-founded.
#
# => - - and upstream's stage 0 applies the matcher to them too (the stack
# walks them), => - - and for every fresh node the port builds (`INDEX`,
# `END`, `STAGE`) the matcher changes nothing -- => because rule 4
# excludes `INDEX` and `STAGE` (`indexing.py:138`), => and the `END`'s rule-4
# result is unchanged because upstream deleted the STORE from the realize
# MAP WHEN IT TURNED IT INTO AN `END` (`indexing.py:88`: `del ctx.realize_map[s]`)
# => and the port's context is an immutable value and cannot delete, => - -
# and so skipping the fix is the equivalent answer -- => - - and
# that is why the port's fresh-node finalisation is a remap and nothing
# ELSE (measured: without it the `END`'s SRC is the old STORE,
# => and the target says `END:none:STORE,RANGE,RANGE` with the new STORE).
def rr_ap_fresh_one(+ar: O.Arena, +i: U32, +fin: List<&2, ApRep>) -> ApFin:
  +ss = O.Arena.srcs(ar, i)
  +ms = rr_ap_final_srcs(fin, ss)
  +f = O.UOp.replace(ar, i, None{}, Some{ms}, None{}, None{})
  ApFin.of(O.Found.ar(f), ap_rep_put(fin, i, O.Found.i(f)))

def rr_ap_fresh.go(fuel: Nat, +i: U32, +ar: O.Arena, +fin: List<&2, ApRep>) -> ApFin:
  match fuel:
    case 0n: ApFin.of(ar, fin)
    case 1n+f:
      +one = rr_ap_fresh_one(ar, i, fin)
      rr_ap_fresh.go(f, U32.add(i, 1), ApFin.ar(one), ApFin.fin(one))

# the whole apply: the walk list in order -- the toposort, => and
# upstream's `toposort` is a post-order (`ops.py:289-301`: the node is added
# when it is popped the second time), => so the toposort is children first
# => and that is the bottom-up order the apply needs (`bottom_up=True`,
# `indexing.py:310`).  => - - AND THE REVERSE OF IT IS THE RANGE MAP's
# order (`indexing.py:200`), => and the two are different lists.
def rr_ap_walk.go(+fuel: Nat, +ar: O.Arena, +tb: F.Table, +tbl: List<&2, IX.IxRange>,
                  +ctx: IX.IxCtx, +ns: List<&2, U32>,
                  +fin: List<&2, ApRep>) -> ApFin:
  match fuel:
    case 0n: ApFin.of(ar, fin)
    case 1n+f:
      match ns:
        case Nil{}: ApFin.of(ar, fin)
        case x <> t:
          +before = O.Arena.next(ar)
          +fx = rr_ap_fix_val(ar, tb, tbl, ctx, x)
          +ar2 = O.Found.ar(fx)
          +after = O.Arena.next(ar2)
          +fr = rr_ap_fresh.go(U32.to_nat(U32.sub(after, before)), before, ar2, fin)
          +ar3 = ApFin.ar(fr)
          +fin2 = ApFin.fin(fr)
          +ms = rr_ap_final_srcs(fin2, O.Arena.srcs(ar3, O.Found.i(fx)))
          +g = O.UOp.replace(ar3, O.Found.i(fx), None{}, Some{ms}, None{}, None{})
          +ar4 = O.Found.ar(g)
          +i = O.Found.i(g)
          rr_ap_walk.go(f, ar4, tb, tbl, ctx, t,
            List.append(&2, ApRep, fin2, [ApRep.of(x, i)]))

def rr_ap_walk(+ar: O.Arena, +tb: F.Table, +tbl: List<&2, IX.IxRange>, +ctx: IX.IxCtx,
               +ns: List<&2, U32>) -> ApFin:
  rr_ap_walk.go(List.length(&2, U32, ns), ar, tb, tbl, ctx, ns, Nil{})

# the rebuilt root: the map's answer for the sink.
def rr_ap_root(+fin: List<&2, ApRep>, +s: U32) -> U32:
  Maybe.default(&2, U32, ap_rep_get(fin, s), s)

# the map: old INDEX -> new INDEX, and it is the port's own `Rep` shape
# (`rangeify.bend:2753`). => - - and the map is indexed by the old INDEX, which
# is why the insert is at the old INDEX's position.
# the rangeified graph, dumped. => and the port's own `rr_dump` is the port's own
# spelling (`op:argkey:srcops`, joined by `;`), => and the oracle's output is the same
# spelling -- => so the comparison is whole-string with no translator.
# the rebuilt root: the map's answer for the sink.
# the root: the last entry of the map. => and that is because the walk is
# the reversed toposort and the sink is the first node of the toposort -- => - -
# so the sink is the last node the walk visits, - and its entry is the last one
# THE MAP HOLDS.
# the map, dumped. => a diagnostic row, and it is the one that says whether the
# rebuilt nodes are the rebuilt nodes.
def rr_map_str(+xs: List<&2, ApRep>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case h <> t: rr_map_str(t, List.append(&2, String, acc,
      [String.concat([U32.show(ApRep.old(h)), "->", U32.show(ApRep.new(h))])]))
# the last element of a list -- the row's spelling of the walk's end.
def rr_list_last(+xs: List<&2, U32>, acc: U32) -> U32:
  match xs:
    case Nil{}: acc
    case h <> t: rr_list_last(t, h)

# the wall count: how many nodes hit rule 2 (`PAD`) or rule 3 (`STACK`),
# => and a wall that is counted is not a silent divergence.
def rr_wall_count.go(+ns: List<&2, U32>, +ar: O.Arena, +ctx: IX.IxCtx, acc: U32) -> U32:
  match ns:
    case Nil{}: acc
    case x <> t:
      rr_wall_count.go(t, ar, ctx, U32.add(acc, Bool.to_u32(rr_ap_wall_hit(ar, ctx, x))))

def rr_row_wall() -> String:
  +q = RZ.rz_built()
  +ar = RZ.RZProg.ar(q)
  +sink = RZ.RZProg.sink(q)
  +tb = F.Folded.t(F.folded(ar))
  +m = rr_range_map(ar, tb, sink)
  +ctx = RrMap.ctx(m)
  +ns = rr_rev(O.UOp.toposort(O.Arena.budget(ar), ar, sink))
  U32.show(rr_wall_count.go(ns, ar, ctx, 0))

def rr_row_walk() -> String:
  +q = RZ.rz_built()
  +ar = RZ.RZProg.ar(q)
  +sink = RZ.RZProg.sink(q)
  +tb = F.Folded.t(F.folded(ar))
  +m = rr_range_map(ar, tb, sink)
  +ns = rr_rev(O.UOp.toposort(O.Arena.budget(ar), ar, sink))
  String.concat(["walk_n=", U32.show(U32.from_nat(List.length(&2, U32, ns))),
                 " first=", U32.show(Maybe.default(&2, U32, List.head(&2, U32, ns), 0)),
                 " last=", U32.show(rr_list_last(ns, 0)),
                 " sink=", U32.show(sink),
                 " arena_next=", U32.show(O.Arena.next(ar))])

def rr_row_map() -> List<&2, String>:
  +q = RZ.rz_built()
  +ar = RZ.RZProg.ar(q)
  +sink = RZ.RZProg.sink(q)
  +tb = F.Folded.t(F.folded(ar))
  +m = rr_range_map(ar, tb, sink)
  +ctx = RrMap.ctx(m)
  +tbl = RrMap.tbl(m)
  +ns = O.UOp.toposort(O.Arena.budget(ar), ar, sink)
  +rep = rr_ap_walk(ar, tb, tbl, ctx, ns)
  rr_map_str(ApFin.fin(rep), Nil{})

def rr_row_out(plant: Bool) -> String:
  +q = RZ.rz_built()
  +ar = RZ.RZProg.ar(q)
  +sink = RZ.RZProg.sink(q)
  +tb = F.Folded.t(F.folded(ar))
  +m = rr_range_map(ar, tb, sink)
  +ctx = RrMap.ctx(m)
  +tbl = RrMap.tbl(m)
  # => and the apply walks the toposort (`bottom_up=True`, `indexing.py:308`),
  # => which is children first: upstream's `toposort` is a post-order
  # (`ops.py:289-301`, the node is added when it is popped the second time), => and
  +ns = O.UOp.toposort(O.Arena.budget(ar), ar, sink)
  +rep = rr_ap_walk(ar, tb, tbl, ctx, ns)
  +root = rr_ap_root(ApFin.fin(rep), sink)
  rr_dump(ApFin.ar(rep), root)

# the port's `run_rangeify` -- `indexing.py:183`. the RANGE map and the apply
# rewrite, in that order, and the rebuilt root. - and it is the stage 1 of
# `get_kernel_graph`, which the engine's `eng_stages()` spells as an empty table
# BECAUSE `run_rangeify` IS AN ALGORITHM, NOT A RULE TABLE.
# - and the answer is the port's own `O.Found{ar, i}` -- the arena and a
# NODE -- - SO NO NEW TYPE IS INVENTED.
# - and `sink` is read three times (the RANGE map, the toposort, the root
# lookup), - so it is bound once to a `+` local -- which is BEND's spelling for
# "readable many times" -- - and that is the same rule `rr_range_map` already
# follows at its own HEAD (`+sk = sink`, with the comment *"and `sink` is read
# twice, so it is bound once to a `+` local"*). - and the compiler says so by
# NAME: `expected : sink` / `observed : sink (consumed more than once)`.
def rr_run_rangeify(+ar: O.Arena, sink: U32) -> O.Found:
  +sk = sink
  +tb = F.Folded.t(F.folded(ar))
  +m = rr_range_map(ar, tb, sk)
  +ctx = RrMap.ctx(m)
  +tbl = RrMap.tbl(m)
  +ns = O.UOp.toposort(O.Arena.budget(ar), ar, sk)
  +rep = rr_ap_walk(ar, tb, tbl, ctx, ns)
  +root = rr_ap_root(ApFin.fin(rep), sk)
  O.Found{ApFin.ar(rep), root}

# THE PORT's `get_kernel_graph` -- `rangeify.py:341-376`: THE PORT's OWN
# `run_rangeify` and then the engine's six table stages. - and the composition
# lives here because `rangeify.bend` must not import this file.
def rr_kernel_graph(+ar: O.Arena, sink: U32) -> O.Found:
  +r = rr_run_rangeify(ar, sink)
  RG.eng_after_rangeify(O.Found.ar(r), O.Found.i(r))

# the row: the kernel graph, in the engine's own spelling (`eng_dump`, the
# bfs), - so the oracle's `eng_py_out` and this row are comparable with no
# translator. - and the count is a row too, because "how many nodes" is the
# first question and a dump alone does not answer it.
def rr_row_kg() -> String:
  +q = RZ.rz_built()
  +k = rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  RG.eng_dump(O.Found.ar(k), O.Found.i(k))


# the rebuilt srcs of one node: the old srcs, => and each is the rebuilt
# CHILD IF IT IS IN THE MAP.
def rr_ap_rebuilt.go(+ar: O.Arena, +ss: List<&2, U32>, +es: List<&2, ApRep>,
                     +acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}: acc
    case s <> t:
      +m = ap_rep_get(es, s)
      rr_ap_rebuilt.go(ar, t, es,
        List.append(&2, U32, acc,
          [Maybe.default(&2, U32, m, s)]))

def rr_ap_rebuilt(+ar: O.Arena, ss: List<&2, U32>, +es: List<&2, ApRep>) -> List<&2, U32>:
  rr_ap_rebuilt.go(ar, ss, es, Nil{})

# the map, dumped with both spellings: the old node and the new one.
# => and it is the row that says whether the walk's nodes are what upstream
# says they are -- => - - and a new node that reads the unchanged one
# is a rule that did not fire, => - - and that is the class of the last
# TWO FAILS.
def rr_rep_str.go(+es: List<&2, ApRep>, +ar: O.Arena, +acc: List<&2, String>) -> List<&2, String>:
  match es:
    case Nil{}: acc
    case e <> t:
      rr_rep_str.go(t, ar, List.append(&2, String, acc,
        [String.concat([U32.show(ApRep.old(e)), "->", U32.show(ApRep.new(e)), ":",
                        rr_node_str(ar, ApRep.old(e)), "/", rr_node_str(ar, ApRep.new(e))])]))

def rr_row_arena() -> String:
  +q = RZ.rz_built()
  +ar = RZ.RZProg.ar(q)
  +sink = RZ.RZProg.sink(q)
  +tb = F.Folded.t(F.folded(ar))
  +m = rr_range_map(ar, tb, sink)
  +ctx = RrMap.ctx(m)
  +tbl = RrMap.tbl(m)
  +ns = O.UOp.toposort(O.Arena.budget(ar), ar, sink)
  +rep = rr_ap_walk(ar, tb, tbl, ctx, ns)
  String.join(rr_rep_str.go(ApFin.fin(rep), ApFin.ar(rep), Nil{}), " ")

# every node's shape, in the toposort order. => and upstream's `toposort` is the
# same order (a post-order dfs over the same graph), => and the oracle
# prints upstream's own shapes (`rr_py_shapes`), => - - so the two are
# comparable position for position -- => and the position is the key, not
# the spelling (many nodes spell the same).
def rr_dims_str.go(+ds: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ds:
    case Nil{}: acc
    case d <> t: rr_dims_str.go(t, List.append(&2, String, acc, [U32.show(d)]))

def rr_dims_str(+ds: List<&2, U32>) -> String:
  String.join(rr_dims_str.go(ds, Nil{}), ",")

# the reduce's two readings: the number of reduced axes (`x.arg[1]`,
# => and the port's `AReduce{rop, num_axes}` carries it) and the dims of
# `x.src[0]` -- => BECAUSE `rr_p4.reduce` TAKES THE FIRST `num_axes` DIMS
# OF `x.src[0]` (`indexing.py:294`), => AND A `CONST 0` IN THE PORT's ANSWER
# MEANS ONE OF THOSE DIMS WAS 1.
def rr_reduce_reading(+ar: O.Arena, +tb: F.Table, +x: U32) -> String:
  +red = rr_is_reduce(ar, x)
  Bool.pick(String, red,
    String.concat(["n=", U32.show(rr_reduce_n.of(O.Arena.arg(ar, x))),
                   " src0=", rr_dims_str(rr_dims(ar, tb, O.Arena.src0(ar, x)))]),
    "")

def rr_dims_row.go(+ns: List<&2, U32>, +ar: O.Arena, +tb: F.Table,
                   +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case x <> t:
      rr_dims_row.go(t, ar, tb, List.append(&2, String, acc,
        [String.concat([rr_node_str(ar, x), "=", rr_dims_str(rr_dims(ar, tb, x)),
                        rr_reduce_reading(ar, tb, x)])]))

def rr_row_dims() -> String:
  +q = RZ.rz_built()
  +ar = RZ.RZProg.ar(q)
  +sink = RZ.RZProg.sink(q)
  +tb = F.Folded.t(F.folded(ar))
  +ns = O.UOp.toposort(O.Arena.budget(ar), ar, sink)
  String.join(rr_dims_row.go(ns, ar, tb, Nil{}), " ")

# the RANGE table, dumped: every entry as `idx:kind:ext`, => and kind 0 is
# A `RANGE` AND KIND 1 IS THE `CONST 0` (`indexing.bend:153` `ix_rg_r` /
# `:149` `ix_rg_c0`). => and this is the row that says whether the port's
# `new_range` MADE A `RANGE` WHERE UPSTREAM MADE ONE -- => AND IT IS
# THE INSTRUMENT FOR W-D (THE `R2` AXIS).
def rr_tbl_str.go(+tbl: List<&2, IX.IxRange>, +acc: List<&2, String>) -> List<&2, String>:
  match tbl:
    case Nil{}: acc
    case e <> t: rr_tbl_str.go(t, List.append(&2, String, acc,
      [String.concat([U32.show(IX.IxRange.idx(e)), ":", U32.show(IX.IxRange.kind(e)),
                      ":", U32.show(IX.IxRange.ext(e))])]))

def rr_row_tbl() -> String:
  +q = RZ.rz_built()
  +ar = RZ.RZProg.ar(q)
  +sink = RZ.RZProg.sink(q)
  +tb = F.Folded.t(F.folded(ar))
  +m = rr_range_map(ar, tb, sink)
  String.join(rr_tbl_str.go(RrMap.tbl(m), Nil{}), " ")

# THE COMPLETE ENGINE, INCLUDING `run_rangeify` -- the row `realize.bend` could not
# hold, and it was REMOVED there without being added here, which is why this def
# exists. `realize.bend` imports `rangeify.bend` (the engine) and THIS file imports
# `realize.bend` (the fixture), so `rangeify.bend` could not import `rangify.bend`
# and its stage 1 was an empty table. the row lives here and the edge stays one-way:
# `rangify.bend` -> `rangeify.bend`, and nothing back.
#
# THE NAME IS `rz_eng` AND NOT `rr_eng` ON PURPOSE: `.agents/slop/rangify/rz_before.rows:7`
# records that row's value from BEFORE the move, so the comparison is against a
# MEASUREMENT rather than against a name invented to match.
def rr_row_eng() -> String:
  +q = RZ.rz_built()
  String.join(RG.eng_drive(RG.eng_stages(), RG.eng_fresh(RG.Eng{RZ.RZProg.ar(q), Nil{}}),
                            RZ.RZProg.sink(q), 0, "rz", Nil{}), "\n")

def main() -> IO(Unit):
  do IO<Unit>:
    rr_row.line("rr_realize", rr_row_realize())
    rr_row.line("rr_realize_plant", rr_row_realize_plant())
    rr_row.line("rr_in", rr_row_in())
    rr_row.line("rr_range", rr_row_range())
    rr_row.line("rr_out", rr_row_out(False{}))
    rr_row.line("rr_map", String.join(rr_row_map(), ","))
    rr_row.line("rr_walk", rr_row_walk())
    rr_row.line("rr_wall", rr_row_wall())
    rr_row.line("rr_dims", rr_row_dims())
    rr_row.line("rr_tbl", rr_row_tbl())
    rr_row.line("rr_arena", rr_row_arena())
    rr_row.line("rr_kg", rr_row_kg())
    rr_row.line("rz_eng", rr_row_eng())
