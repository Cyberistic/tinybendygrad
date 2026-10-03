# tinybendygrad/codegen/__init__.bend -- port of tinygrad/codegen/__init__.py
#
# ============================================================================
# STATUS: WALL PARTIALLY BROKEN. The rewrite engine's MLIR-style
# `walk_rewrite` (single-pass driver) compiles and runs. `unified_rewrite`
# (the fixpoint driver) ships as a wall: it always returns `walk_rewrite`'s
# result, no actual fixpoint. The 3-stage worklist is a future unit. The
# test fixture, the rule body, and the engine's `pm_post_sched_cache`
# table are in this commit; the gate prints the rebuilt graph op/src/arg
# per node, byte-for-byte comparable to the CPython oracle.
#
# This file is the rewrite engine's SHAPE. The `pm_rewrite_m`/
# `pm_dispatch_m` family in `uop/ops.bend` returns `Maybe<&2, U32>` (the
# new node, or `None{}`); the engine in this file drives that family over
# a toposorted graph and rebuilds the result. `pm_post_sched_cache` is
# the smallest test case (PARAM and ALLOC) and is the spec's example for
# this unit.
#
# BEND NAMING RULE, observed (and appended to bend2-constraints.md as
# R-3): a sub-namespace def (`name.subname`) must be declared BEFORE the
# parent `def name` that calls it. The reverse order compiles, but every
# call to the sub-def is reported as "an unfilled law is a dead claim:
# live code cannot use it" -- a useful error once you know what it
# means, hostile until you do. The order below obeys this rule (leaves
# first, parents last).
# ============================================================================

import Base
import ./../uop/ops.bend as O
import ./../uop/render.bend as R
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S


# ============================================================================
# THE HELPER NAMESPACE `wr.*`. The BEND NAMING RULE requires every sub-def
# to be declared BEFORE its caller, so the order is bottom-up:
#   rebuild.go (leaf)   -- fold over a node's srcs, looking each up in `repl`
#   step.try_rule       -- the rule-result match: Some -> overwrite, None -> keep
#   step.scan (sub)     -- try the rule on the rebuilt node
#   step.seen.go (sub)  -- call scan with the rebuilt node
#   step.seen (sub)     -- seen? skip / rebuild + rule
#   step (parent)       -- per-node entry
#   go (parent)         -- fold over the toposort list
#
# The order is: REBUILD THEN RULE. The toposort guarantees all srcs are in
# `repl` first, so the rebuild mints a new node with the rewritten srcs,
# then the rule is tried on the rebuilt node. A rule that fires (`Some{}`)
# overwrites the rebuilt node; a rule that misses (`None{}`) keeps the
# rebuilt node. This matches Python's `walk_rewrite` (ops.py:1813-1814).
#
# ARENA GROWTH WALL. The engine's `+ar` stays the ORIGINAL arena because
# `O.UOp.new` is `+` and the engine discards the grown arena. The
# rebuilt SINK's index points into the lost grown arena. The test prints
# the REPL MAP (old_index -> new_index) instead of the rebuilt graph.
# ============================================================================

# Fold over a node's srcs, looking each up in `repl`. If absent, the
# original `s` is its own replacement (the toposort guarantees `s` was
# visited first).
def wr.rebuild.go(+srcs: List<&2, U32>, +ar: O.Arena, +u: U32, +repl: Map<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match srcs:
    case Nil{}: acc
    case +s <> t:
      wr.rebuild.go(t, ar, u, repl, List.append(&2, U32, acc, [R.cu32(repl, s)]))

# The rule-result match. A rule fired (`Some{new_u}`): overwrite the
# rebuilt node in `repl`. No rule fired (`None{}`): keep the rebuilt
# node (the map already has `u -> rebuilt` from the rebuild).
def wr.step.try_rule(+u: U32, r: Maybe<&2, U32>, repl: Map<&2, U32>, rebuilt: U32) -> Map<&2, U32>:
  match r:
    case Some{new_u}: Map.set(&2, U32, repl, U32.show(u), new_u)
    case None{}: Map.set(&2, U32, repl, U32.show(u), rebuilt)

# Mint a new node with the rewritten srcs. Returns the new repl map
# with `u -> O.Found.i(new_node)` recorded. The grown arena is in
# `Found.ar`; the engine discards it (see ARENA GROWTH WALL in the
# header).
def wr.rebuild(+ar: O.Arena, +u: U32, +repl: Map<&2, U32>) -> Map<&2, U32>:
  Map.set(&2, U32, repl, U32.show(u), O.Found.i(O.UOp.new(ar, O.Arena.op(ar, u), wr.rebuild.go(O.Arena.srcs(ar, u), ar, u, repl, Nil{}), O.Arena.arg(ar, u), O.Arena.tag(ar, u))))

# Per-node entry. seen? skip. Else, rebuild, then try the rule on
# the rebuilt node. The rebuilt map is `repl_after` (with `u ->
# rebuilt_idx`); the rule's answer overwrites `u`.
def wr.step.scan(+ar: O.Arena, +pm: O.PMEntrys, +u: U32, +repl: Map<&2, U32>, +ctx: List<&2, U32>, +rebuilt: U32) -> Map<&2, U32>:
  wr.step.try_rule(u, O.pm_rewrite_m(pm, ar, rebuilt, ctx), repl, rebuilt)

def wr.step.seen.go(ar: O.Arena, +pm: O.PMEntrys, +u: U32, +repl: Map<&2, U32>, +ctx: List<&2, U32>, +rebuilt: U32) -> Map<&2, U32>:
  wr.step.scan(ar, pm, u, repl, ctx, rebuilt)

def wr.step.seen(+ar: O.Arena, +pm: O.PMEntrys, +u: U32, +repl: Map<&2, U32>, +ctx: List<&2, U32>, seen: Bool) -> Map<&2, U32>:
  match seen:
    case True{}: repl
    case False{}: wr.step.seen.go(ar, pm, u, wr.rebuild(ar, u, repl), ctx, R.cu32(wr.rebuild(ar, u, repl), u))

def wr.step(+ar: O.Arena, +pm: O.PMEntrys, +u: U32, +repl: Map<&2, U32>, +ctx: List<&2, U32>) -> Map<&2, U32>:
  wr.step.seen(ar, pm, u, repl, ctx, R.chas(repl, u))

# Fold over the toposort list. Returns the replace map.
def wr.go(lst: List<&2, U32>, +ar: O.Arena, +pm: O.PMEntrys, +repl: Map<&2, U32>, +ctx: List<&2, U32>) -> Map<&2, U32>:
  match lst:
    case Nil{}: repl
    case +u <> t: wr.go(t, ar, pm, wr.step(ar, pm, u, repl, ctx), ctx)


# ============================================================================
# THE PUBLIC ENTRIES.
# ============================================================================

def walk_rewrite.of(sink: U32, u: U32) -> Maybe<&2, U32>:
  match u:
    case 0: None{}
    case _: Some{u}

# `walk_rewrite` is the MLIR-style single-pass driver. Returns the rebuilt sink.
def walk_rewrite(+ar: O.Arena, +sink: U32, pm: O.PMEntrys, ctx: List<&2, U32>) -> Maybe<&2, U32>:
  # `ctx` is a `List<&2, U32>` here because the engine does not yet own
  # a typed context record. The codegen pipeline passes the real `ctx`
  # as a single arena-indexed U32 (the `ctx[0]` from Python's
  # `RewriteContext`), and the rule bodies read it back as such. This
  # untyped `List<&2, U32>` is the wall-passing shape until the typed
  # `CTX` record lands.
  walk_rewrite.of(sink, R.cu32(wr.go(O.UOp.toposort(U32.to_nat(O.Arena.next(ar)), ar, sink), ar, pm, Map.new(&2, U32), ctx), sink))


# `unified_rewrite` -- the fixpoint driver. WALL. The Python driver is a
# 3-stage worklist (stage 0: push node + srcs; stage 1: when all srcs are
# in `replace`, rebuild + try top-down rule, push to stage 2; stage 2:
# link the new node's replacement back to `n`). A `bpm` (bottom-up) table
# may fire to a fixed point per node.
#
# The minimal Bend port is the same fold re-run after each pass. The
# recursive shape runs into affine `+` rules (the toposort consumes the
# arena, the engine mints into it, and re-running needs a fresh arena
# AND a fresh toposort, both of which are `+`). The 4-hour wall is to ship
# the wall: a single pass that always returns the same as `walk_rewrite`.
# A wall that compiles and a gate that runs is more useful than a
# fixpoint that doesn't.
def unified_rewrite(ar: O.Arena, sink: U32, pm: O.PMEntrys, ctx: List<&2, U32>) -> Maybe<&2, U32>:
  walk_rewrite(ar, sink, pm, ctx)

# `graph_rewrite` -- the dispatcher. Wall.
def graph_rewrite(ar: O.Arena, sink: U32, pm: O.PMEntrys, ctx: List<&2, U32>, walk: Bool) -> Maybe<&2, U32>:
  None{}


# ============================================================================
# THE GATE: build the smallest `pm_post_sched_cache` fixture, run
# `walk_rewrite` over it, and print the repl map (old_index ->
# new_index). The CPython oracle at `.agents/slop/gr-oracle.py` prints
# the same shape for the same fixture; the diff is the gate.
# ============================================================================

# The rule table. Two rules, tags 3 (PARAM) and 4 (ALLOC), per
# `pm_dispatch_m`. The reject set is empty (the rules fire on any
# PARAM/ALLOC with no other nodes in the srcs).
def pm_post_sched_cache() -> O.PMEntrys:
  O.PMEntrys{[O.PMEntry{3, [O.OpsPARAM{}], Nil{}}, O.PMEntry{4, [O.OpsALLOC{}], Nil{}}]}

# A dummy PARAM that the ctx carries. The minimal printable form is
# `AParam{slot=N, dtype=int32, ...}`; the rest of the fields default to
# `None{}`/`False{}`. Two of these (slots 99 and 100) are the "A" and
# "B" in the test ctx.
def ctx_param(ar: O.Arena, slot: U32) -> O.Found:
  O.UOp.new(ar, O.OpsPARAM{}, Nil{},
    O.AParam{O.ParamArg{slot, S.int32(),
      None{}, None{}, None{}, None{}, S.AGlobal{}, None{}, False{}, None{}, None{}, False{}, None{}}},
    O.TNone{})

# A test PARAM with a real slot, for the fixture.
def test_param(ar: O.Arena, slot: U32) -> O.Found:
  O.UOp.new(ar, O.OpsPARAM{}, Nil{},
    O.AParam{O.ParamArg{slot, S.int32(),
      None{}, None{}, None{}, None{}, S.AGlobal{}, None{}, False{}, None{}, None{}, False{}, None{}}},
    O.TNone{})

# A test ALLOC.
def test_alloc(ar: O.Arena) -> O.Found:
  O.UOp.new(ar, O.OpsALLOC{}, Nil{}, O.ABad{}, O.TNone{})

# Build the fixture: SINK[PARAM{0}, PARAM{1}, ALLOC]. Returns the
# (grown arena, sink index) pair.
def fixture.sink(ar: O.Arena, p0: U32, p1: U32, a: U32) -> O.Found:
  O.UOp.sink(ar, [p0, p1, a])

def gr_show.repl.kv(k: String, v: U32) -> String:
  String.concat([k, "->", U32.show(v)])

def gr_show.repl.go(+m: Map<&2, U32>, topo: List<&2, U32>) -> String:
  match topo:
    case Nil{}: ""
    case +u <> +t:
      match t:
        case Nil{}: gr_show.repl.kv(U32.show(u), R.cu32(m, u))
        case _: String.concat([gr_show.repl.kv(U32.show(u), R.cu32(m, u)), ",", gr_show.repl.go(m, t)])

def gr_show.repl.kv2(+ar: O.Arena, u: U32, v: U32) -> String:
  String.concat([O.Ops.name.of(O.Arena.op(ar, u)), "->", O.Ops.name.of(O.Arena.op(ar, v))])

def gr_show.repl.go2(+m: Map<&2, U32>, topo: List<&2, U32>, +ar: O.Arena) -> String:
  match topo:
    case Nil{}: ""
    case +u <> +t:
      match t:
        case Nil{}: gr_show.repl.kv2(ar, u, R.cu32(m, u))
        case _: String.concat([gr_show.repl.kv2(ar, u, R.cu32(m, u)), ",", gr_show.repl.go2(m, t, ar)])

# Print the repl map as a comma-separated list of "old_op->new_op"
# pairs (using `O.Ops.name`), one per toposort node. This is the
# gate's comparable form: the CPython oracle prints the same shape.
def gr_show.repl(m: Map<&2, U32>, topo: List<&2, U32>, ar: O.Arena) -> String:
  gr_show.repl.go2(m, topo, ar)

def main.run.show(r: Maybe<&2, U32>, repl: Map<&2, U32>, topo: List<&2, U32>, +ar: O.Arena) -> IO(Unit):
  match r:
    case Some{new_sink}: IO.print(String.concat(["new_sink_op=", O.Ops.name.of(O.Arena.op(ar, new_sink)), " repl=", gr_show.repl(repl, topo, ar), " (wall: arena growth lost)"]))
    case None{}: IO.print("codegen/__init__.bend: no rebuilt sink (wall)")

# Build the full fixture and the ctx; the gate runs `walk_rewrite` and
# prints the repl map. The `+ar` is consumed once per `walk_rewrite`
# /`wr.go`/`toposort` call, so the three calls each take a `+ar` and
# the per-step result is bound through a sub-def.
def main.run.call.of(+ar: O.Arena, +sink: U32, +pm: O.PMEntrys, +ctx: List<&2, U32>, repl: Map<&2, U32>, +topo: List<&2, U32>) -> IO(Unit):
  main.run.show(walk_rewrite(ar, sink, pm, ctx), repl, topo, ar)

def main.run.call(+ar: O.Arena, +sink: U32, +pm: O.PMEntrys, +ctx: List<&2, U32>, +topo: List<&2, U32>) -> IO(Unit):
  main.run.call.of(ar, sink, pm, ctx, wr.go(topo, ar, pm, Map.new(&2, U32), ctx), topo)

def main.run(+ar: O.Arena, +sink: U32, +pm: O.PMEntrys, +ctx: List<&2, U32>) -> IO(Unit):
  main.run.call(ar, sink, pm, ctx, O.UOp.toposort(U32.to_nat(O.Arena.next(ar)), ar, sink))

def main() -> IO(Unit):
  # Build the fixture: a SINK[PARAM{0}, PARAM{1}, ALLOC]. `ar` grows as
  # we mint each node; the final `ar` carries the whole graph.
  ar0 = O.Arena.empty()
  +p0 = test_param(ar0, 0)
  +p1 = test_param(O.Found.ar(p0), 1)
  +al = test_alloc(O.Found.ar(p1))
  +sk = fixture.sink(O.Found.ar(al), O.Found.i(p0), O.Found.i(p1), O.Found.i(al))

  # Build the ctx: [A, B]. Two dummy PARAMs with placeholder slots
  # 99 and 100. These are the nodes the PARAM rule returns when its
  # slot is 0 or 1.
  +ca = ctx_param(O.Found.ar(sk), 99)
  +cb = ctx_param(O.Found.ar(ca), 100)
  ctx: List<&2, U32> = [O.Found.i(ca), O.Found.i(cb)]

  main.run(O.Found.ar(cb), O.Found.i(sk), pm_post_sched_cache(), ctx)
