# gates/rangify-gate.bend -- THE GATE DRIVER for `tinybendygrad/schedule/rangify.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. THE PORT FILE CARRIES THE PORT AND
# THIS FILE CARRIES THE INSTRUMENT, AND THE TREE's OWN CONVENTION SAYS SO:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# THE ROWS ARE PURE CONSUMERS: THEY CALL THE PORT's DEFS AND DEFINE
# NOTHING THAT THE PORT NEEDS.

import Base
import ./../tinybendygrad/schedule/rangify.bend as P
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F
import ./../tinybendygrad/schedule/indexing.bend as IX
import ./../tinybendygrad/schedule/realize.bend as RZ
import ./../tinybendygrad/schedule/rangeify.bend as RG

def rr_row_kg() -> String:
  +q = RZ.rz_built()
  +k = P.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  RG.eng_dump(O.Found.ar(k), O.Found.i(k))
# the rebuilt srcs of one node: the old srcs, => and each is the rebuilt
# CHILD IF IT IS IN THE MAP.
def rr_row_out(plant: Bool) -> String:
  +q = RZ.rz_built()
  +ar = RZ.RZProg.ar(q)
  +sink = RZ.RZProg.sink(q)
  +tb = F.Folded.t(F.folded(ar))
  +m = P.rr_range_map(ar, tb, sink)
  +ctx = P.RrMap.ctx(m)
  +tbl = P.RrMap.tbl(m)
  # => and the apply walks the toposort (`bottom_up=True`, `indexing.py:308`),
  # => which is children first: upstream's `toposort` is a post-order
  # (`ops.py:289-301`, the node is added when it is popped the second time), => and
  +ns = O.UOp.toposort(O.Arena.budget(ar), ar, sink)
  +rep = P.rr_ap_walk(ar, tb, tbl, ctx, ns)
  +root = P.rr_ap_root(P.ApFin.fin(rep), sink)
  P.rr_dump(P.ApFin.ar(rep), root)
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
def rr_row_tbl() -> String:
  +q = RZ.rz_built()
  +ar = RZ.RZProg.ar(q)
  +sink = RZ.RZProg.sink(q)
  +tb = F.Folded.t(F.folded(ar))
  +m = P.rr_range_map(ar, tb, sink)
  String.join(P.rr_tbl_str.go(P.RrMap.tbl(m), Nil{}), " ")
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
def rr_row_realize() -> String:
  +q = RZ.rz_built()
  +ar = RZ.RZProg.ar(q)
  +m = P.rr_realize(ar, RZ.RZProg.sink(q))
  String.join(P.rr_real_row.go(IX.IxMap.es(m), ar, Nil{}), ";")
# the planted row. - it is a row, not a build.
def rr_row_in() -> String:
  +q = RZ.rz_built()
  P.rr_dump(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
# 5. the RANGE map's row. the oracle's spelling: `#N <node>:[<in>]->[<out>]`,
# and a RANGE is `R` and its axis ID while the CONST 0 is `<CONST:cother:>`
# (`rr-oracle.py`'s `render_range`).
def rr_row.line(nm: String, got: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", got]))
def rr_row_walk() -> String:
  +q = RZ.rz_built()
  +ar = RZ.RZProg.ar(q)
  +sink = RZ.RZProg.sink(q)
  +tb = F.Folded.t(F.folded(ar))
  +m = P.rr_range_map(ar, tb, sink)
  +ns = P.rr_rev(O.UOp.toposort(O.Arena.budget(ar), ar, sink))
  String.concat(["walk_n=", U32.show(U32.from_nat(List.length(&2, U32, ns))),
                 " first=", U32.show(Maybe.default(&2, U32, List.head(&2, U32, ns), 0)),
                 " last=", U32.show(P.rr_list_last(ns, 0)),
                 " sink=", U32.show(sink),
                 " arena_next=", U32.show(O.Arena.next(ar))])
def rr_row_arena() -> String:
  +q = RZ.rz_built()
  +ar = RZ.RZProg.ar(q)
  +sink = RZ.RZProg.sink(q)
  +tb = F.Folded.t(F.folded(ar))
  +m = P.rr_range_map(ar, tb, sink)
  +ctx = P.RrMap.ctx(m)
  +tbl = P.RrMap.tbl(m)
  +ns = O.UOp.toposort(O.Arena.budget(ar), ar, sink)
  +rep = P.rr_ap_walk(ar, tb, tbl, ctx, ns)
  String.join(P.rr_rep_str.go(P.ApFin.fin(rep), P.ApFin.ar(rep), Nil{}), " ")
# every node's shape, in the toposort order. => and upstream's `toposort` is the
# same order (a post-order dfs over the same graph), => and the oracle
# prints upstream's own shapes (`rr_py_shapes`), => - - so the two are
# comparable position for position -- => and the position is the key, not
# the spelling (many nodes spell the same).
def rr_row_wall() -> String:
  +q = RZ.rz_built()
  +ar = RZ.RZProg.ar(q)
  +sink = RZ.RZProg.sink(q)
  +tb = F.Folded.t(F.folded(ar))
  +m = P.rr_range_map(ar, tb, sink)
  +ctx = P.RrMap.ctx(m)
  +ns = P.rr_rev(O.UOp.toposort(O.Arena.budget(ar), ar, sink))
  U32.show(P.rr_wall_count.go(ns, ar, ctx, 0))
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
def rr_row_dims() -> String:
  +q = RZ.rz_built()
  +ar = RZ.RZProg.ar(q)
  +sink = RZ.RZProg.sink(q)
  +tb = F.Folded.t(F.folded(ar))
  +ns = O.UOp.toposort(O.Arena.budget(ar), ar, sink)
  String.join(P.rr_dims_row.go(ns, ar, tb, Nil{}), " ")
# the RANGE table, dumped: every entry as `idx:kind:ext`, => and kind 0 is
# A `RANGE` AND KIND 1 IS THE `CONST 0` (`indexing.bend:153` `ix_rg_r` /
# `:149` `ix_rg_c0`). => and this is the row that says whether the port's
# `new_range` MADE A `RANGE` WHERE UPSTREAM MADE ONE -- => AND IT IS
# THE INSTRUMENT FOR W-D (THE `R2` AXIS).
# the planted row. - it is a row, not a build.
def rr_row_realize_plant() -> String:
  +q = RZ.rz_built()
  +ar = RZ.RZProg.ar(q)
  +m = P.rr_realize_plant(ar, RZ.RZProg.sink(q))
  String.join(P.rr_real_row.go(IX.IxMap.es(m), ar, Nil{}), ";")
def rr_row_range() -> String:
  +q = RZ.rz_built()
  +ar = RZ.RZProg.ar(q)
  +sink = RZ.RZProg.sink(q)
  +tb = F.Folded.t(F.folded(ar))
  +m = P.rr_range_map(ar, tb, sink)
  String.join(P.rr_range_row.go(O.UOp.toposort(O.Arena.budget(ar), ar, sink), 0n,
                              P.RrMap.ctx(m), P.RrMap.tbl(m), ar, Nil{}), ";")
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
def rr_row_map() -> List<&2, String>:
  +q = RZ.rz_built()
  +ar = RZ.RZProg.ar(q)
  +sink = RZ.RZProg.sink(q)
  +tb = F.Folded.t(F.folded(ar))
  +m = P.rr_range_map(ar, tb, sink)
  +ctx = P.RrMap.ctx(m)
  +tbl = P.RrMap.tbl(m)
  +ns = O.UOp.toposort(O.Arena.budget(ar), ar, sink)
  +rep = P.rr_ap_walk(ar, tb, tbl, ctx, ns)
  P.rr_map_str(P.ApFin.fin(rep), Nil{})
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
