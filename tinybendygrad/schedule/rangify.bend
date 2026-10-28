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
# SO THE DRIVER IS FOUR THINGS AND THE PORT HAD NONE OF THEM:
#
#   1. THE DISPATCH for `pm_generate_realize_map` -- `indexing.bend`'s
#      `grm_table()` (schedule/indexing.bend:1246 symbol=grm_table) is the TABLE and the four rule BODIES are in
#      the same file (`realize` schedule/indexing.bend:909 symbol=realize, `realize_srcs` schedule/indexing.bend:943 symbol=realize_srcs,
#      `ix_realize_custom` schedule/indexing.bend:999 symbol=ix_realize_custom, `ix_war_hit` schedule/indexing.bend:960 symbol=ix_war_hit), but there is NO
#      `_dispatch`/`_try`/`_scan` for it -- MEASURED, `grep -n "grm_dispatch"
#      tinybendygrad/schedule/indexing.bend` answers NOTHING.
#   2. THE CONSUMER MAP -- `data_srcs` is ported (`indexing.bend`'s `ix_ds_*`)
#      and nothing reads it.
#   3. THE RANGE-MAP LOOP -- the port has `IxCtx` (`indexing.bend:195` symbol=IxCtx), the
#      `new_range` counter (`:811`), `broadcast_rngs` (`:1048`) and
#      `broadcast_axes` (`:427`), and nothing drives them.
#   4. THE APPLY -- `pm_apply_rangeify`'s five rules (`par_table`,
#      schedule/indexing.bend:1275 symbol=par_table) and `pm_fix_deviceless` (`pfd_table`, schedule/indexing.bend:1282 symbol=pfd_table).
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
# AND THE PAYOFF, MEASURED, NOT ASSUMED: **CPython's `run_rangeify` OUTPUT IS
# `SINK(AFTER(PARAM, END))` -- WITH AN `END`, NOT A `CALL`** (upstream's stage 6,
# `split_kernels`, later turns the `END` into a `CALL`), **AND THE PORT's OWN
# `schedule()` COUNTS AN `END` AS A KERNEL**: `sc_is_kernel`
# (`tinybendygrad/schedule/__init__.bend:274`) is
# `sc_is(ar, i, O.OpsCALL{}) or sc_is(ar, i, O.OpsEND{})`.
#
# ⇒ SO THIS DRIVER IS WHAT MOVES `rz_lin_n` OFF ZERO, AND IT IS THE WHOLE OF
# THE PORT's OWN `Device` LANE'S LAST LINK.
#
# THE SPELLING. The dump is `op:argkey:srcops` joined by `;` -- the ORACLE's
# spelling and the port's own `rz_dump` spelling, so the two are byte
# comparable with no translator.
#
# THE WALLS, NAMED HERE AND NOT DISGUISED:
#
#   W-A. `_apply_reshape` (`indexing.py:155-167`) -- the RESHAPE arm of
#        `apply_movement_op`. It is `UOp.sink`, `usum`, `%`, `//` and a
#        `graph_rewrite` under `symbolic`. `indexing.bend:575` already names it
#        ("three builders and W2"). ⇒ THE RESHAPE'S INPUT RANGE IS AN AFFINE
#        EXPRESSION IN CPython (`ADD:none:MUL,RANGE`) AND THE PORT CANNOT BUILD
#        ONE. THE PORT'S ANSWER IS THE INPUT RANGE ITSELF. ⇒ THE OUTPUT GRAPH
#        DIFFERS FROM CPython'S IN THE INDEX NODES' ARGUMENT, AND ONLY THERE.
#   W-B. The port has no `symbolic` REWRITER -- `fold.bend`'s `mm.*` is the
#        INTERVAL algebra, not upstream's `tinygrad/uop/symbolic.py` matcher.
#   W-C. `UOp(Ops.STAGE, arg=BufferizeOpts(...))` -- `indexing.bend`'s W3. NOT
#        REACHED BY THIS PROGRAM: the realize map holds ONE node and it is a
#        STORE, and a STORE becomes an `END`, not a `STAGE`.
#
# ⇒ A ROW THAT CANNOT GO RED IS A LABEL, SO **NO ROW IN THIS FILE IS A TEST.**
# THE TEST IS THE COMPARISON AGAINST THE ORACLE: `.agents/slop/rangify/cmp.py`.

import Base

import ./../helpers.bend as H

import ./../uop/ops.bend as O

import ./../uop/fold.bend as F

import ./indexing.bend as IX

import ./realize.bend as RZ

# ===========================================================================
# 1. THE DUMP -- the ORACLE's spelling, `op:argkey:srcops`.
#
# `eng_op_name` (`schedule/rangeify.bend:2987`) names TEN ops and answers
# "OTHER" for the rest, and the graph this file produces is made of INDEX,
# RANGE, END, ADD and MUL -- so this file needs its own. `RZ.rz_argkey` IS
# reused: it is the oracle's `arg_key` (`cother` for a CONST, `none` for a node
# with no arg, `other` for everything else), and it is the same function the
# port's own realize-to-sink comparator already compares against.
# ===========================================================================
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

# ===========================================================================
# 2. THE REALIZE MAP -- `pm_generate_realize_map` (`indexing.py:45-54`), FOUR
# RULES, AND THE DISPATCH THAT IS MISSING.
#
#   0  UPat(Ops.CALL, src=(UPat((Ops.SINK, Ops.PROGRAM)),), name="c", allow_any_len=True)
#        -> realize_custom_kernel_srcs      (indexing.py:40-43)
#   1  UPat(Ops.STORE, name="tr")           -> realize                (indexing.py:28)
#   2  UPat((Ops.MSELECT, Ops.MSTACK), name="rb") -> realize_srcs     (indexing.py:30-32)
#   3  UPat(Ops.STORE, src=(UPat.var("dest"), UPat.var("src")))
#        -> realize_store_after_src         (indexing.py:34-36)
#
# **⇒ AND ALL FOUR RULE BODIES RETURN `None`**, so upstream's
# `PatternMatcher.rewrite` -- which returns the FIRST non-`None` answer -- runs
# EVERY rule that MATCHES. That is why rule 1 AND rule 3 both fire on a STORE:
# the STORE is realized AND its src is tested for the WAR hazard.
#
# THE PORT's `grm_table()` (`indexing.bend:1246` symbol=grm_table) carries the op sets and the
# TAG, and the tag IS the rule index -- the same convention `rangeify.bend`'s
# `aprt_table`/`aprt_dispatch` uses. **⇒ SO THE DISPATCH IS: THE TAG PICKS THE
# BODY, AND THE OP SET PICKS THE MATCH.**
# ===========================================================================

# RULE 3's TEST: `if dest.base in src.toposort()` (`indexing.py:34-36`). The
# port's `ix_war_hit` (`indexing.bend:960` symbol=ix_war_hit) is that test.
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

# RULE 0's BODY: `ix_realize_custom` (`indexing.bend:999` symbol=ix_realize_custom).
def rr_call_real(+ar: O.Arena, u: U32) -> List<&2, IX.IxReal>:
  IX.ix_realize_custom(ar, u)

# RULE 2's BODY: `realize_srcs` (`indexing.bend:943` symbol=realize_srcs).
def rr_mstack_real(+ar: O.Arena, u: U32) -> List<&2, IX.IxReal>:
  IX.realize_srcs(ar, u)

# RULE 1's BODY: `realize` (`indexing.bend:909` symbol=realize).
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

# RULE 0's PATTERN CARRIES A SRC CONDITION: `src=(UPat((Ops.SINK, Ops.PROGRAM)),)`.
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

# ===========================================================================
# THE PLANT. **⇒ THE PORT HAS NO ENV READER, SO THE PLANT IS A **SEPARATE ROW** AND NOT
# A FLAG: **⇒ THE MEASURED FOLD ABOVE IS **ALWAYS** THE UNPLANTED ONE**, AND THE PORT's
# OWN DRIVER IS NEVER SHIPPED BROKEN.**
# **⇒ AND THE PLANT IS "DROP THE **FIRST** REALIZED ENTRY", WHICH IS **EXACTLY THE CLASS
# OF BUG** THE MEASUREMENT IS ABOUT: A REALIZE MAP WITH AN ENTRY MISSING.**
def rr_realize_plant.go(fuel: Nat, ns: List<&2, U32>, +ar: O.Arena, +m: IX.IxMap,
                        +dropped: Bool) -> IX.IxMap:
  match fuel:
    case 0n: m
    case 1n+p:
      match ns:
        case Nil{}: m
        case u <> t:
          +e = rr_realize_one(ar, u)
          # THE ENTRY IS **NON-EMPTY** WHEN THE NODE IS ONE THE REALIZE RULES FIRE ON, AND
          # `rr_realize_one` ANSWERS **A LIST** OF SUCH ENTRIES -- **⇒ SO THE PLANT DROPS
          # THE **FIRST** ENTRY OF THE **FIRST** NODE THAT HAS ONE.**
          +n = U32.from_nat(List.length(&2, IX.IxReal, e))
          +drop = Bool.and(Bool.not(dropped), Bool.not(U32.is_eq(n, 0)))
          rr_realize_plant.go(p, t, ar,
            IX.IxMap{Bool.pick(List<&2, IX.IxReal>, drop, IX.IxMap.es(m),
                               List.append(&2, IX.IxReal, IX.IxMap.es(m), e))},
            Bool.or(dropped, drop))

def rr_realize_plant(+ar: O.Arena, sink: U32) -> IX.IxMap:
  rr_realize_plant.go(O.Arena.budget(ar), O.UOp.toposort(O.Arena.budget(ar), ar, sink),
                       ar, IX.IxMap{Nil{}}, False{})

# ===========================================================================
# 4. THE RANGE MAP -- `indexing.py:190-306`. THE CONSUMER MAP, THE LOOP, AND
#    THE RANGE TABLE.
#
# THE STATE. `ctx` IS UPSTREAM's `IndexingContext`, `ends` IS UPSTREAM's
# `ending_ranges` AS A FLAG PER NODE (WHICH IS ALL THE ALGORITHM READS OF IT:
# `len(ending_ranges[x])`), `tbl` IS THE RANGE TABLE, AND `out`/`inp` ARE THE
# RANGE MAP's TWO HALVES FOR THE NODE BEING PROCESSED.
#
# **⇒ THE TABLE IS ALSO THE COUNTER: A RANGE's AXIS ID IS ITS TABLE INDEX
# MINUS ONE, BECAUSE INDEX 0 IS THE CONST 0 AND `new_range(1)` DOES NOT ADVANCE
# UPSTREAM's `range_idx` (`indexing.py:21`).**
#
# **⇒ AND THE PHASES ARE SEPARATE DEFS, NOT ONE BIG EXPRESSION, BECAUSE A
# `Bool.pick` EVALUATES BOTH ARMS AND THE TABLE IS APPENDED-ONLY: A BRANCH THAT
# CREATES A RANGE MUST NOT ALSO CREATE ONE IN THE ARM THAT IS NOT TAKEN. A
# `match` ON A `Bool` IS LAZY, SO THE BRANCHES ARE `match`es.**
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

# THE SAME STATE WITH A NEW CONTEXT.
def RrMap.with_ctx(+ctx: IX.IxCtx, +x: RrMap) -> RrMap:
  RrMap{ctx, RrMap.ends(x), RrMap.tbl(x), RrMap.out(x), RrMap.inp(x), RrMap.e(x), RrMap.b(x), RrMap.ne(x)}

# THE SAME STATE WITH A NEW `ends` LIST.
def RrMap.with_ends(+ends: List<&2, Bool>, +x: RrMap) -> RrMap:
  RrMap{RrMap.ctx(x), ends, RrMap.tbl(x), RrMap.out(x), RrMap.inp(x), RrMap.e(x), RrMap.b(x), RrMap.ne(x)}

# ===========================================================================
# 4a. THE SHAPE. `x.shape` (ops.py:456) IS A DOUBLE `Maybe`, AND EVERY DIM OF
# THIS PROGRAM IS CONCRETE (`rr_py_shapes` AGAINST THE PORT's OWN ARENA: 23 of
# 23 NODES AGREE).
# ===========================================================================
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

# ===========================================================================
# 4b. THE CONSUMER MAP. `consumer_map[x][c]` IS "c's DATA SRCS CONTAIN x"
# (`indexing.py:193-196`), AND `data_srcs` IS `indexing.bend`'s OWN
# `ix_ds_take` TWICE -- SO THE PORT's OWN DECISION IS REUSED, NOT COPIED.
# ===========================================================================
def rr_dsrcs(+ar: O.Arena, +op: O.Op, +ss: List<&2, U32>) -> List<&2, U32>:
  IX.ix_ds_take(IX.ix_ds_one(op), IX.ix_ds_take(IX.ix_ds_zero(op), ss))

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

# ===========================================================================
# 4c. THE REVERSED TOPOSORT AND THE `ends` LIST. THE LOOP RUNS OVER
# `reversed(tsink_toposort)` (`indexing.py:200`) AND `ending_ranges` IS READ
# FOR A NODE'S CONSUMERS, WHICH ARE PROCESSED FIRST -- SO THE FLAG LIST IS
# INDEXED BY THE POSITION IN THE **REVERSED** TOPOSORT.
# ===========================================================================
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
# -- AND THE ALGORITHM ONLY READS `len()` OF IT, SO IT IS A FLAG.
def rr_ends_of.go(+cs: List<&2, U32>, +rs: List<&2, U32>, +ends: List<&2, Bool>, acc: Bool) -> Bool:
  match cs:
    case Nil{}: acc
    case c <> t: rr_ends_of.go(t, rs, ends, Bool.or(acc, rr_ends_at(ends, rr_rpos(rs, c))))

def rr_ends_of(+rs: List<&2, U32>, +ends: List<&2, Bool>, +cs: List<&2, U32>) -> Bool:
  rr_ends_of.go(cs, rs, ends, False{})

# ===========================================================================
# 4d. THE RANGE TABLE. INDEX 0 IS THE CONST 0 -- `UOp.const(0)` AND
# `r.const_like(0)` ARE THE SAME NODE -- AND EVERY OTHER INDEX IS A RANGE.
# ===========================================================================
# THE NEW RANGE: ITS INDEX, THE INDICES SO FAR, AND THE TABLE WITH IT APPENDED.
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
# RANGE OTHERWISE. **⇒ THE CONST 0 IS TABLE INDEX 0 AND THE AXIS ID IS THE
# TABLE INDEX MINUS ONE, SO THE TABLE IS ALSO THE COUNTER.**
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

# ===========================================================================
# 4e. THE OP TESTS. A `match` MAY NOT SCRUTINIZE A COMPUTED VALUE, SO EACH
# TEST IS ITS OWN DEF.
# ===========================================================================
# `rr_is_call`, `rr_is_store` AND `rr_is_mstack` ARE ALREADY HERE -- ABOVE, IN
# THE REALIZE-MAP DISPATCH -- AND ARE REUSED, NOT COPIED.
def rr_is_after(+ar: O.Arena, +x: U32) -> Bool: O.eq_op(O.Arena.op(ar, x), O.OpsAFTER{})
def rr_is_reduce(+ar: O.Arena, +x: U32) -> Bool: O.eq_op(O.Arena.op(ar, x), O.OpsREDUCE{})
def rr_is_stack(+ar: O.Arena, +x: U32) -> Bool: O.eq_op(O.Arena.op(ar, x), O.OpsSTACK{})

# `indexing.py:202-208`: NO RANGES ON CALLS, AFTERS, MSTACKS AND MSELECTS.
def rr_skip(+ar: O.Arena, +x: U32) -> Bool:
  Bool.or(rr_is_call(ar, x), Bool.or(rr_is_after(ar, x), rr_is_mstack(ar, x)))

# `GroupOp.Elementwise.union({Ops.REDUCE})` -- `indexing.py:264`.
def rr_is_elemwise(+ar: O.Arena, +x: U32) -> Bool:
  Bool.or(O.GroupOp.elementwise(O.Arena.op(ar, x)), rr_is_reduce(ar, x))

# ===========================================================================
# 4f. THE AXES. `realize_map[x] = list(range(len(x.shape)))` (`indexing.py:231`)
# AND `realize_map[x] = _realize_axis` (`indexing.py:261`, `:268`).
# ===========================================================================
def rr_axes.go(+k: Nat, +i: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match k:
    case 0n: acc
    case 1n+p: rr_axes.go(p, U32.add(i, 1), List.append(&2, U32, acc, [i]))

def rr_axes(n: U32) -> List<&2, U32>:
  rr_axes.go(U32.to_nat(n), 0, Nil{})

# THE REALIZE MAP, WITH THE NODE'S AXES SET.
def rr_real(+ctx: IX.IxCtx, +x: U32, axes: List<&2, U32>) -> IX.IxCtx:
  IX.IxCtx{IX.ix_rmap_set(IX.IxCtx.rmap(ctx), x, IX.IxReal{x, True{}, axes}),
            IX.IxCtx.nrem(ctx), IX.IxCtx.rngm(ctx), IX.IxCtx.ridx(ctx)}

# ===========================================================================
# 4g. `ended` -- THE RANGES THE CONSUMERS ITERATE THAT THIS NODE BROADCASTS
# OVER (`indexing.py:212-213`).
# ===========================================================================
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

# `list(UOp.sink(*ended).ranges)` -- THE **RANGE** NODES AMONG `ended`. A CONST
# 0 IS NOT A RANGE, SO IT DOES NOT COUNT.
def rr_any_range.go(+rs: List<&2, U32>, +tbl: List<&2, IX.IxRange>, acc: Bool) -> Bool:
  match rs:
    case Nil{}: acc
    case r <> t:
      rr_any_range.go(t, tbl, Bool.or(acc, Bool.not(IX.ix_rg_is_c0(IX.ix_tbl_at(tbl, r)))))

def rr_any_range(+tbl: List<&2, IX.IxRange>, +rs: List<&2, U32>) -> Bool:
  rr_any_range.go(rs, tbl, False{})

# ===========================================================================
# 4h. THE LOOP -- `indexing.py:200-306`, PHASE BY PHASE.
#
# THE PHASES ARE SEPARATE DEFS BECAUSE THE RANGE TABLE IS APPEND-ONLY AND A
# `Bool.pick` EVALUATES BOTH ARMS: A BRANCH THAT CREATES A RANGE MUST NOT ALSO
# CREATE ONE IN THE ARM THAT IS NOT TAKEN. A `match` ON A `Bool` IS LAZY.
# ===========================================================================

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

# THE MERGE -- `indexing.py:238-261`. **=> THE PORT'S ANSWER IS UPSTREAM's
# FALLBACK FOR EVERY AXIS: A NEW RANGE AND THE AXIS REALIZED. UPSTREAM KEEPS
# THE RANGE WHEN EVERY CONSUMER AGREES AND REFINES IT WITH `.valid`, WHICH IS
# W3 (`UOp.valid` IS NOT PORTED) -- => THE AGREE CASE IS A NAMED DEVIATION.
# **=> AND THE BRANCH IS NOT EXERCISED BY THE MEASURED PROGRAM: NO NODE HAS TWO
# CONSUMERS IN THE RANGE MAP (MEASURED, AND `rr_cons_rngs` IS THE INSTRUMENT).**
def rr_merge(+ar: O.Arena, +tb: F.Table, +ctx: IX.IxCtx, +x: U32, +tbl: List<&2, IX.IxRange>) -> RrRs:
  +n = rr_new.all(rr_dims(ar, tb, x), tbl, Nil{})
  RrRs{0, RrRs.rs(n), RrRs.tbl(n)}

# `apply_movement_op` -- `indexing.py:165-180`. PERMUTE AND EXPAND ARE FULLY
# PORTED -- `indexing.bend`'s OWN `ix_mv_permute` AND `ix_mv_expand`, REUSED AND
# NOT COPIED. RESHAPE IS W-A (`_apply_reshape`: `UOp.sink`, `usum`, `%`, `//`
# AND A `symbolic` REWRITER) AND **THE PORT'S ANSWER IS THE IDENTITY**, WHICH
# IS WHAT `rangify.bend`'s OWN HEADER SAYS. SHRINK, FLIP AND PAD HAVE THEIR
# ARITHMETIC NAMED AND NOT BUILT (W3), SO THEY ANSWER THE IDENTITY TOO.
def rr_mv.of(perm: Bool, exp: Bool, +arg: List<&2, U32>, +rngs: List<&2, U32>) -> List<&2, U32>:
  match perm:
    case True{}: IX.ix_mv_permute(arg, rngs)
    case False{}:
      match exp:
        case True{}: IX.ix_mv_expand(arg, rngs)
        case False{}: rngs

# THE MARG: `x.marg` IS THE PERMUTE's AND THE EXPAND's TUPLE.
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

# THE REDUCE's REDUCED AXES: `x.arg[1]` IS THE NUMBER OF REDUCED AXES.
def rr_reduce_n.of(a: O.Arg) -> U32:
  match a:
    case O.AReduce{rop, num_axes}: num_axes
    case _: 0

# THE P0 PHASE: THE STATE, THE CONSUMERS, THE ENDING RANGES, AND THE SKIP.
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

# THE P1 PHASES: THE OUTPUT RANGES. THE REALIZE BRANCH, THE SINGLE-CONSUMER
# BRANCH, THE MERGE, AND THE `continue` (NO CONSUMER WITH RANGES).
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
# REALIZE EVERY AXIS AND GIVE THE NODE NEW RANGES (`indexing.py:264-270`).
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
  +out = RrMap.out(m)
  +n = rr_new.all(List.take(&2, U32, rr_dims(ar, tb, O.Arena.src0(ar, x)),
                            U32.to_nat(rr_reduce_n.of(O.Arena.arg(ar, x)))),
                  RrMap.tbl(m), Nil{})
  RrMap.put(m, out, List.append(&2, U32, RrRs.rs(n), out), RrMap.e(m), RrMap.b(m), RrMap.ne(m))

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

# THE P6 PHASE: THE `ends` ENTRY FOR THIS NODE.
def rr_p6(+m: RrMap) -> RrMap:
  RrMap.with_ends(List.append(&2, Bool, RrMap.ends(m), [RrMap.e(m)]), m)

# THE STEP, IN UPSTREAM's ORDER.
def rr_step(+ar: O.Arena, +tb: F.Table, +rev: List<&2, U32>, +m: RrMap, +x: U32) -> RrMap:
  rr_p6(rr_p5(ar, tb, rev, rr_p4(ar, tb, rev, rr_p3(rr_p2(ar, tb, rev, rr_p1(ar, tb, rev, rr_p0(ar, tb, rev, m, x), x), x)), x), x))

# THE FOLD, OVER THE **REVERSED** TOPOSORT (`indexing.py:200`).
def rr_range_map.go(+xs: List<&2, U32>, +ar: O.Arena, +tb: F.Table, +rev: List<&2, U32>,
                    +m: RrMap) -> RrMap:
  match xs:
    case Nil{}: m
    case x <> t: rr_range_map.go(t, ar, tb, rev, rr_step(ar, tb, rev, m, x))

# THE REALIZE MAP IS FILLED **BEFORE** THE LOOP (`indexing.py:188`:
# `graph_rewrite(tsink, pm_generate_realize_map, ctx=rctx)`), SO THE CONTEXT
# STARTS WITH IT -- AND IT IS THE PORT's OWN `rr_realize`, WHICH AGREES WITH
# CPython's `rr_py_realize` EXACTLY.
def rr_range_map(+ar: O.Arena, +tb: F.Table, sink: U32) -> RrMap:
  +topo = O.UOp.toposort(O.Arena.budget(ar), ar, sink)
  +rev = rr_rev(topo)
  +ctx = IX.IxCtx{rr_realize(ar, sink), IX.IxSet{Nil{}}, IX.IxRMap{Nil{}}, 0}
  rr_range_map.go(rev, ar, tb, rev, RrMap{ctx, Nil{}, [IX.ix_rg_c0()], Nil{}, Nil{}, False{}, False{}, False{}})

# ===========================================================================
# 3. THE ROWS.
# ===========================================================================
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

# THE PLANTED ROW. **⇒ IT IS A ROW, NOT A BUILD.**
def rr_row_realize_plant() -> String:
  +q = RZ.rz_built()
  +ar = RZ.RZProg.ar(q)
  +m = rr_realize_plant(ar, RZ.RZProg.sink(q))
  String.join(rr_real_row.go(IX.IxMap.es(m), ar, Nil{}), ";")

def rr_row_in() -> String:
  +q = RZ.rz_built()
  rr_dump(RZ.RZProg.ar(q), RZ.RZProg.sink(q))


# ===========================================================================
# 5. THE RANGE MAP's ROW. THE ORACLE's SPELLING: `#N <node>:[<in>]->[<out>]`,
# AND A RANGE IS `R` AND ITS AXIS ID WHILE THE CONST 0 IS `<CONST:cother:>`
# (`rr-oracle.py`'s `render_range`).
# ===========================================================================
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

def main() -> IO(Unit):
  do IO<Unit>:
    rr_row.line("rr_realize", rr_row_realize())
    rr_row.line("rr_realize_plant", rr_row_realize_plant())
    rr_row.line("rr_in", rr_row_in())
    rr_row.line("rr_range", rr_row_range())
