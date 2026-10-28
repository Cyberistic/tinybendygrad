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
#      `grm_table()` (`:1141`) is the TABLE and the four rule BODIES are in
#      the same file (`realize` `:827`, `realize_srcs` `:861`,
#      `ix_realize_custom` `:917`, `ix_war_hit` `:878`), but there is NO
#      `_dispatch`/`_try`/`_scan` for it -- MEASURED, `grep -n "grm_dispatch"
#      tinybendygrad/schedule/indexing.bend` answers NOTHING.
#   2. THE CONSUMER MAP -- `data_srcs` is ported (`indexing.bend`'s `ix_ds_*`)
#      and nothing reads it.
#   3. THE RANGE-MAP LOOP -- the port has `IxCtx` (`indexing.bend:149`), the
#      `new_range` counter (`:811`), `broadcast_rngs` (`:1048`) and
#      `broadcast_axes` (`:427`), and nothing drives them.
#   4. THE APPLY -- `pm_apply_rangeify`'s five rules (`par_table`,
#      `indexing.bend:1170`) and `pm_fix_deviceless` (`pfd_table`, `:1177`).
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
# traversal as `RZ.rz_dump` (`schedule/realize.bend:381`), which is the oracle's
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
# THE PORT's `grm_table()` (`indexing.bend:1141`) carries the op sets and the
# TAG, and the tag IS the rule index -- the same convention `rangeify.bend`'s
# `aprt_table`/`aprt_dispatch` uses. **⇒ SO THE DISPATCH IS: THE TAG PICKS THE
# BODY, AND THE OP SET PICKS THE MATCH.**
# ===========================================================================

# RULE 3's TEST: `if dest.base in src.toposort()` (`indexing.py:34-36`). The
# port's `ix_war_hit` (`indexing.bend:878`) is that test.
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

# RULE 0's BODY: `ix_realize_custom` (`indexing.bend:917`).
def rr_call_real(+ar: O.Arena, u: U32) -> List<&2, IX.IxReal>:
  IX.ix_realize_custom(ar, u)

# RULE 2's BODY: `realize_srcs` (`indexing.bend:861`).
def rr_mstack_real(+ar: O.Arena, u: U32) -> List<&2, IX.IxReal>:
  IX.realize_srcs(ar, u)

# RULE 1's BODY: `realize` (`indexing.bend:827`).
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

def main() -> IO(Unit):
  do IO<Unit>:
    rr_row.line("rr_realize", rr_row_realize())
    rr_row.line("rr_realize_plant", rr_row_realize_plant())
    rr_row.line("rr_in", rr_row_in())
